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
    // Keep small bit width for area efficiency
    parameter WIDTH = 8;
    parameter DECIMAL_BITS = 4;

    wire [7:0] v_mem1;
    wire [7:0] v_mem2;
    wire spike1, spike2;
    wire signed [WIDTH-1:0] i_syn;
    wire signed [WIDTH-1:0] current;
    wire [WIDTH-1:0] weight;
    
    // Convert unsigned input to signed current
    assign current = {1'b0, ui_in[7:1]};  // Positive current input

    // First neuron
    simple_neuron #(
        .WIDTH(WIDTH),
        .DECIMAL_BITS(DECIMAL_BITS)
    ) neuron1 (
        .clk(clk),
        .reset_n(rst_n),
        .i_stim(current),
        .i_syn(0),
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
        .i_stim(0),
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
    input wire signed [WIDTH-1:0] i_stim,
    input wire signed [WIDTH-1:0] i_syn,
    output reg spike,
    output wire [7:0] v_mem
);
    // Constants defined as signed values
    localparam signed [WIDTH-1:0] ONE = (1 << DECIMAL_BITS);
    localparam signed [WIDTH-1:0] V_REST = -(6 * ONE);
    localparam signed [WIDTH-1:0] V_THRESH = (2 * ONE);
    localparam signed [WIDTH-1:0] TAU = ONE >>> 2;
    
    // Internal state variables declared as signed
    reg signed [WIDTH-1:0] v_mem_int;
    reg signed [WIDTH-1:0] leak_current;
    reg signed [WIDTH-1:0] total_current;
    
    // Convert signed internal voltage to unsigned output
    // Scale and offset to get positive values for output
    assign v_mem = (v_mem_int + (8 * ONE)) >>> DECIMAL_BITS;
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            v_mem_int <= V_REST;
            spike <= 0;
            leak_current <= 0;
            total_current <= 0;
        end else begin
            // Calculate leak current (signed arithmetic)
            leak_current <= (V_REST - v_mem_int) >>> 2;
            
            // Sum all currents (signed arithmetic)
            total_current <= $signed(i_stim) + $signed(i_syn) + $signed(leak_current);
            
            // Update membrane potential with proper signed arithmetic
            v_mem_int <= v_mem_int + ((total_current * TAU) >>> DECIMAL_BITS);
            
            // Spike generation with signed comparison
            if (v_mem_int >= V_THRESH) begin
                spike <= 1'b1;
                v_mem_int <= V_REST;
            end else begin
                spike <= 1'b0;
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
    output wire signed [WIDTH-1:0] i_syn
);
    localparam [WIDTH-1:0] ONE = (1 << DECIMAL_BITS);
    localparam [WIDTH-1:0] MAX_WEIGHT = (1 << (WIDTH-1)) - 1;
    localparam [WIDTH-1:0] MIN_WEIGHT = ONE >>> 2;
    
    reg [WIDTH-1:0] trace;
    
    // Ensure weight stays within bounds
    function automatic [WIDTH-1:0] bound_weight;
        input [WIDTH-1:0] w;
        begin
            if (w > MAX_WEIGHT)
                bound_weight = MAX_WEIGHT;
            else if (w < MIN_WEIGHT)
                bound_weight = MIN_WEIGHT;
            else
                bound_weight = w;
        end
    endfunction
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            weight <= ONE;
            trace <= 0;
        end else begin
            // Trace decay
            trace <= trace - (trace >>> 2);
            
            // STDP updates with bounds checking
            if (pre_spike) begin
                trace <= trace + (ONE >>> 1);
                weight <= bound_weight(weight - (weight >>> 4));
            end
            
            if (post_spike && trace > 0) begin
                weight <= bound_weight(weight + (ONE >>> 3));
            end
        end
    end
    
    // Convert weight to signed synaptic current
    assign i_syn = pre_spike ? $signed({1'b0, weight[WIDTH-2:0]}) : 0;
endmodule