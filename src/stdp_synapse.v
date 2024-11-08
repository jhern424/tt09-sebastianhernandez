// stdp_synapse.v - Improved STDP synapse
`default_nettype none

module stdp_synapse #(
    parameter WIDTH = `WIDTH,
    parameter DECIMAL_BITS = `DECIMAL_BITS
)(
    input wire clk,
    input wire reset_n,
    input wire pre_spike,
    input wire post_spike,
    input wire valid_in,
    input wire ready_in,
    output wire valid_out,
    output wire ready_out,
    output reg [WIDTH-1:0] weight,
    output wire [WIDTH-1:0] i_syn,
    // Debug outputs
    output wire [WIDTH-1:0] debug_pre_trace,
    output wire [WIDTH-1:0] debug_post_trace
);
    // STDP parameters
    localparam A_PLUS = (`ONE >> 5);    // LTP strength
    localparam A_MINUS = (`ONE >> 6);   // LTD strength
    localparam TAU_TRACE = (`ONE >> 3); // Trace decay rate
    localparam MAX_WEIGHT = (`ONE << 1); // Maximum weight
    localparam MIN_WEIGHT = 0;          // Minimum weight

    // Internal registers
    reg [WIDTH-1:0] pre_trace;
    reg [WIDTH-1:0] post_trace;
    reg [WIDTH-1:0] weight_update;
    reg pre_spike_delayed, post_spike_delayed;
    reg [1:0] valid_pipeline;
    
    // Pipeline control
    wire stall_pipeline;
    assign stall_pipeline = !ready_in;
    assign ready_out = !stall_pipeline;
    assign valid_out = valid_pipeline[1];

    // Stage 1: Trace updates
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            pre_trace <= 0;
            post_trace <= 0;
            valid_pipeline[0] <= 0;
        end else if (!stall_pipeline) begin
            // Decay traces
            pre_trace <= bound_value(pre_trace - (pre_trace >>> 4));
            post_trace <= bound_value(post_trace - (post_trace >>> 4));
            
            // Update traces on spikes
            if (pre_spike)
                pre_trace <= bound_value(pre_trace + `ONE);
            if (post_spike)
                post_trace <= bound_value(post_trace + `ONE);
                
            valid_pipeline[0] <= valid_in;
        end
    end

    // Stage 2: Weight updates
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            weight <= `ONE;
            pre_spike_delayed <= 0;
            post_spike_delayed <= 0;
            weight_update <= 0;
            valid_pipeline[1] <= 0;
        end else if (!stall_pipeline) begin
            pre_spike_delayed <= pre_spike;
            post_spike_delayed <= post_spike;
            
            // LTP: Pre before Post
            if (pre_spike_delayed && post_trace > 0) begin
                weight_update <= safe_mult2(A_PLUS, post_trace);
                weight <= bound_weight(weight + weight_update);
            end
            // LTD: Post before Pre
            else if (post_spike_delayed && pre_trace > 0) begin
                weight_update <= safe_mult2(A_MINUS, pre_trace);
                weight <= bound_weight(weight - weight_update);
            end
            
            valid_pipeline[1] <= valid_pipeline[0];
        end
    end
    
    // Synaptic current generation
    assign i_syn = pre_spike ? safe_mult2(weight, `ONE) : 0;
    
    // Debug outputs
    assign debug_pre_trace = pre_trace;
    assign debug_post_trace = post_trace;
    
    // Helper functions
    function [WIDTH-1:0] bound_weight;
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
    
    function [WIDTH-1:0] safe_mult2;
        input [WIDTH-1:0] a, b;
        reg [2*WIDTH-1:0] temp;
        begin
            temp = a * b;
            safe_mult2 = bound_value(temp >>> DECIMAL_BITS);
        end
    endfunction
    
    function [WIDTH-1:0] bound_value;
        input [WIDTH-1:0] val;
        begin
            if (val > `MAX_VALUE)
                bound_value = `MAX_VALUE;
            else if (val < `MIN_VALUE)
                bound_value = `MIN_VALUE;
            else
                bound_value = val;
        end
    endfunction

endmodule