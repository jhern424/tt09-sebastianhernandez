// tt_um_hh_stdp.v
`default_nettype none

module tt_um_hh_stdp (
    input  wire [7:0] ui_in,    
    output wire [7:0] uo_out,   
    input  wire [7:0] uio_in,   
    output wire [7:0] uio_out,  
    output wire [7:0] uio_oe,   
    input  wire       ena,      
    input  wire       clk,      
    input  wire       rst_n     
);
    parameter WIDTH = 8;
    parameter DECIMAL_BITS = 4;

    // Internal signals
    wire [7:0] v_mem1;
    wire [7:0] v_mem2;
    wire spike1, spike2;
    wire signed [WIDTH-1:0] i_syn;
    wire signed [WIDTH-1:0] current;

    // Current input scaling - modified for better response
    assign current = $signed({1'b0, ui_in[7:1], 1'b0}) - $signed(8'd32);  // Changed from 8'd64

    // First neuron
    lif_neuron #(
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

    // STDP synapse
    stdp_synapse #(
        .WIDTH(WIDTH),
        .DECIMAL_BITS(DECIMAL_BITS)
    ) synapse (
        .clk(clk),
        .reset_n(rst_n),
        .pre_spike(spike1),
        .post_spike(spike2),
        .i_syn(i_syn)
    );

    // Second neuron
    lif_neuron #(
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

    // Output assignments
    assign uo_out = v_mem1;
    assign uio_out = {spike1, spike2, v_mem2[7:2]};
    assign uio_oe = 8'b11111111;

    wire unused = ena & |uio_in;
endmodule

module lif_neuron #(
    parameter WIDTH = 8,
    parameter DECIMAL_BITS = 4
)(
    input wire clk,
    input wire reset_n,
    input wire signed [WIDTH-1:0] i_stim,
    input wire signed [WIDTH-1:0] i_syn,
    output reg spike,
    output wire [7:0] v_mem
);
    // Modified constants for better neuron dynamics
    localparam signed [WIDTH-1:0] ONE = (1 << DECIMAL_BITS);
    localparam signed [WIDTH-1:0] V_REST = -(2 * ONE);    // Changed from -4*ONE
    localparam signed [WIDTH-1:0] V_THRESH = (ONE);       // Changed from 2*ONE
    localparam signed [WIDTH-1:0] TAU = ONE >>> 1;        // Changed from ONE >>> 2
    
    // Internal registers
    reg signed [WIDTH-1:0] v_mem_int;
    reg signed [WIDTH-1:0] leak_current;
    reg signed [WIDTH-1:0] total_current;

    // Modified membrane potential scaling
    wire signed [WIDTH:0] scaled_v_mem = v_mem_int + (4 * ONE);
    assign v_mem = (scaled_v_mem[WIDTH]) ? 8'd0 :
                  (scaled_v_mem > (8'd255 << DECIMAL_BITS)) ? 8'd255 :
                  scaled_v_mem[WIDTH-1:DECIMAL_BITS];

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            v_mem_int <= V_REST;
            leak_current <= 0;
            total_current <= 0;
            spike <= 0;
        end else begin
            // Modified leak current calculation
            leak_current <= (V_REST - v_mem_int) >>> 1;
            
            // Modified current summation with scaling
            total_current <= i_stim + (i_syn >>> 1) + leak_current;
            
            if (spike) begin
                v_mem_int <= V_REST;
                spike <= 0;
            end else begin
                v_mem_int <= v_mem_int + ((total_current * TAU) >>> DECIMAL_BITS);
                spike <= (v_mem_int >= V_THRESH);
            end
        end
    end
endmodule

module stdp_synapse #(
    parameter WIDTH = 8,
    parameter DECIMAL_BITS = 4
)(
    input wire clk,
    input wire reset_n,
    input wire pre_spike,
    input wire post_spike,
    output wire signed [WIDTH-1:0] i_syn
);
    // Modified parameters for stronger synaptic effect
    localparam [WIDTH-1:0] ONE = (1 << DECIMAL_BITS);
    localparam [WIDTH-1:0] MAX_WEIGHT = (1 << (WIDTH-1)) - 1;
    localparam [WIDTH-1:0] MIN_WEIGHT = ONE >>> 1;  // Changed from ONE >>> 2
    
    // Internal registers
    reg [WIDTH-1:0] trace;
    reg [WIDTH-1:0] weight;
    reg [WIDTH-1:0] syn_current;

    // Modified synaptic current for stronger effect
    assign i_syn = pre_spike ? $signed({1'b0, weight}) : 0;  // Removed shift

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            trace <= 0;
            weight <= ONE;
            syn_current <= 0;
        end else begin
            // Modified trace dynamics for faster learning
            if (pre_spike)
                trace <= ONE << 1;  // Increased trace magnitude
            else
                trace <= (trace > 0) ? trace - 1 : 0;
            
            // Modified weight update rules
            if (post_spike && trace > 0) begin
                // Stronger potentiation
                weight <= (weight < MAX_WEIGHT - (ONE >>> 1)) ? 
                         weight + (ONE >>> 1) : MAX_WEIGHT;
            end else if (pre_spike && post_spike) begin
                // Weaker depression
                weight <= (weight > MIN_WEIGHT + (ONE >>> 2)) ? 
                         weight - (ONE >>> 2) : MIN_WEIGHT;
            end
        end
    end
endmodule