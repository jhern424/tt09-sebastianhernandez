`default_nettype none

module tt_um_hh_stdp (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path
    input  wire       ena,      // enable
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);
    // Drastically reduced bit width
    parameter WIDTH = 8;
    parameter DECIMAL_BITS = 4;

    wire [7:0] v_mem1;
    wire [7:0] v_mem2;
    wire spike1, spike2;
    wire [WIDTH-1:0] i_syn;
    wire [WIDTH-1:0] current;
    wire [WIDTH-1:0] weight;
    
    // Simple current conversion
    assign current = {ui_in[7:4], 4'b0};

    // First neuron
    simple_neuron #(
        .WIDTH(WIDTH),
        .DECIMAL_BITS(DECIMAL_BITS)
    ) neuron1 (
        .clk(clk),
        .reset_n(rst_n),
        .i_stim(current),
        .i_syn({WIDTH{1'b0}}),
        .spike(spike1),
        .v_mem(v_mem1)
    );

    // Simplified STDP synapse
    simple_stdp #(
        .WIDTH(WIDTH),
        .DECIMAL_BITS(DECIMAL_BITS)
    ) synapse (
        .clk(clk),
        .reset_n(rst_n),
        .pre_spike(spike1),
        .post_spike(spike2),
        .weight(weight),
        .i_syn(i_syn)
    );

    // Second neuron
    simple_neuron #(
        .WIDTH(WIDTH),
        .DECIMAL_BITS(DECIMAL_BITS)
    ) neuron2 (
        .clk(clk),
        .reset_n(rst_n),
        .i_stim({WIDTH{1'b0}}),
        .i_syn(i_syn),
        .spike(spike2),
        .v_mem(v_mem2)
    );

    assign uo_out = v_mem1;
    assign uio_out = {spike1, spike2, v_mem2[7:2]};
    assign uio_oe = 8'b11111111;

    wire unused = ena & |uio_in;
endmodule

module simple_neuron #(
    parameter WIDTH = 8,
    parameter DECIMAL_BITS = 4
)(
    input wire clk,
    input wire reset_n,
    input wire [WIDTH-1:0] i_stim,
    input wire [WIDTH-1:0] i_syn,
    output reg spike,
    output wire [7:0] v_mem
);
    localparam ONE = (1 << DECIMAL_BITS);
    localparam V_REST = -(8 * ONE);
    localparam V_THRESH = (2 * ONE);
    localparam TAU = ONE >>> 2;
    
    reg [WIDTH-1:0] v_mem_int;
    reg [WIDTH-1:0] leak_current;
    
    // Map internal voltage to output
    assign v_mem = {v_mem_int[WIDTH-1:WIDTH-8]};
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            v_mem_int <= V_REST;
            spike <= 0;
            leak_current <= 0;
        end else begin
            // Simple leaky integration
            leak_current <= (V_REST - v_mem_int) >>> 2;
            
            // Update membrane potential
            v_mem_int <= v_mem_int + (((i_stim + i_syn + leak_current) * TAU) >>> DECIMAL_BITS);
            
            // Simple spike generation
            if (v_mem_int >= V_THRESH) begin
                spike <= 1;
                v_mem_int <= V_REST;
            end else begin
                spike <= 0;
            end
        end
    end
endmodule

module simple_stdp #(
    parameter WIDTH = 8,
    parameter DECIMAL_BITS = 4
)(
    input wire clk,
    input wire reset_n,
    input wire pre_spike,
    input wire post_spike,
    output reg [WIDTH-1:0] weight,
    output wire [WIDTH-1:0] i_syn
);
    localparam ONE = (1 << DECIMAL_BITS);
    localparam MAX_WEIGHT = ((1 << WIDTH) - 1);
    
    reg [WIDTH-1:0] trace;
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            weight <= ONE;
            trace <= 0;
        end else begin
            // Simple trace decay
            trace <= trace - (trace >>> 2);
            
            // Basic STDP
            if (pre_spike) begin
                trace <= trace + (ONE >>> 1);
                if (weight > 0)
                    weight <= weight - 1;
            end
            
            if (post_spike && trace > 0) begin
                if (weight < MAX_WEIGHT)
                    weight <= weight + 1;
            end
        end
    end
    
    assign i_syn = pre_spike ? weight : 0;
endmodule