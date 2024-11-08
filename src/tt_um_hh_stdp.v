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

    // Modified current input scaling for stronger effect
    assign current = $signed({1'b0, ui_in}) - $signed(8'd128);  // Full range current input

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

    // STDP synapse with stronger effect
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
    // Much more sensitive parameters
    localparam signed [WIDTH-1:0] ONE = (1 << DECIMAL_BITS);
    localparam signed [WIDTH-1:0] V_REST = 0;                // Resting at 0
    localparam signed [WIDTH-1:0] V_THRESH = (ONE >>> 2);    // Very low threshold
    localparam signed [WIDTH-1:0] TAU = ONE << 1;           // Much faster integration
    
    reg signed [WIDTH-1:0] v_mem_int;
    reg signed [WIDTH-1:0] leak_current;
    reg signed [WIDTH-1:0] total_current;

    // Simple linear scaling
    assign v_mem = v_mem_int[WIDTH-1:DECIMAL_BITS];

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            v_mem_int <= V_REST;
            leak_current <= 0;
            total_current <= 0;
            spike <= 0;
        end else begin
            // Very weak leak
            leak_current <= (V_REST - v_mem_int) >>> 3;
            
            // Direct current summation with emphasis on input
            total_current <= (i_stim <<< 1) + i_syn + leak_current;
            
            if (spike) begin
                v_mem_int <= V_REST;
                spike <= 0;
            end else begin
                // Faster integration
                v_mem_int <= v_mem_int + ((total_current * TAU) >>> (DECIMAL_BITS - 2));
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
    // Modified parameters for stronger effect
    localparam [WIDTH-1:0] ONE = (1 << DECIMAL_BITS);
    localparam [WIDTH-1:0] MAX_WEIGHT = ONE << 2;  // Much higher max weight
    localparam [WIDTH-1:0] MIN_WEIGHT = ONE >>> 2;
    
    reg [WIDTH-1:0] trace;
    reg [WIDTH-1:0] weight;

    // Stronger synaptic current
    assign i_syn = pre_spike ? $signed({1'b0, weight}) <<< 1 : 0;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            trace <= 0;
            weight <= ONE;
        end else begin
            // Faster trace dynamics
            if (pre_spike)
                trace <= ONE << 2;
            else
                trace <= (trace > 0) ? trace - 1 : 0;
            
            // More aggressive weight updates
            if (post_spike && trace > 0) begin
                weight <= (weight < MAX_WEIGHT - (ONE >>> 1)) ? 
                         weight + (ONE >>> 1) : MAX_WEIGHT;
            end else if (pre_spike && post_spike) begin
                weight <= (weight > MIN_WEIGHT + (ONE >>> 2)) ? 
                         weight - (ONE >>> 2) : MIN_WEIGHT;
            end
        end
    end
endmodule