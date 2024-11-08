`default_nettype none

// STDP module to handle synaptic weight updates
module stdp (
    input wire clk,
    input wire reset_n,
    input wire pre_spike,
    input wire post_spike,
    output reg [7:0] weight
);
    // Parameters for STDP
    parameter INIT_WEIGHT = 8'd100;
    parameter POS_DELTA = 8'd10;
    parameter NEG_DELTA = 8'd5;
    
    // STDP timing window (in clock cycles)
    parameter WINDOW = 4'd10;
    
    // Counters for pre and post spike timing
    reg [3:0] pre_counter;
    reg [3:0] post_counter;
    
    // Sequential logic for STDP
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            weight <= INIT_WEIGHT;
            pre_counter <= 0;
            post_counter <= 0;
        end else begin
            // Update counters
            if (pre_spike)
                pre_counter <= WINDOW;
            else if (pre_counter > 0)
                pre_counter <= pre_counter - 1;
                
            if (post_spike)
                post_counter <= WINDOW;
            else if (post_counter > 0)
                post_counter <= post_counter - 1;
                
            // Update weight based on spike timing
            if (pre_spike && post_counter > 0) begin
                // Potentiation: pre -> post
                if (weight <= (8'd255 - POS_DELTA))
                    weight <= weight + POS_DELTA;
                else
                    weight <= 8'd255;
            end else if (post_spike && pre_counter > 0) begin
                // Depression: post -> pre
                if (weight >= NEG_DELTA)
                    weight <= weight - NEG_DELTA;
                else
                    weight <= 8'd0;
            end
        end
    end
endmodule

// Modified LIF module with weighted input
module lif_weighted (
    input wire [7:0] current,
    input wire [7:0] weight,
    input wire clk,
    input wire reset_n,
    output reg [7:0] state,
    output wire spike
);
    // Internal signals
    wire [15:0] weighted_input;
    wire [7:0] next_state;
    reg [7:0] threshold;
    
    // Apply weight to input current
    assign weighted_input = (current * weight) >> 8;
    
    // Sequential logic
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= 8'd0;
            threshold <= 8'd200;
        end else begin
            state <= next_state;
        end
    end
    
    // Next state logic
    assign next_state = weighted_input[7:0] + (state >> 1);
    
    // Spike output
    assign spike = (state >= threshold);
endmodule

// Top module with two connected LIF neurons
module tt_um_two_lif_stdp (
    input wire [7:0] ui_in,      // Input current for first neuron
    output wire [7:0] uo_out,    // State of second neuron
    input wire [7:0] uio_in,     // Additional inputs (unused)
    output wire [7:0] uio_out,   // Additional outputs
    output wire [7:0] uio_oe,    // IO direction control
    input wire ena,              // Enable (unused)
    input wire clk,              // Clock
    input wire rst_n             // Reset (active low)
);
    // Internal signals
    wire spike1, spike2;
    wire [7:0] state1;
    wire [7:0] synapse_weight;
    
    // All output pins must be assigned
    assign uio_oe = 8'hFF;  // All outputs
    assign uio_out = {spike1, spike2, synapse_weight[5:0]};
    
    // First LIF neuron
    lif lif1 (
        .current(ui_in),
        .clk(clk),
        .reset_n(rst_n),
        .state(state1),
        .spike(spike1)
    );
    
    // STDP synapse
    stdp stdp1 (
        .clk(clk),
        .reset_n(rst_n),
        .pre_spike(spike1),
        .post_spike(spike2),
        .weight(synapse_weight)
    );
    
    // Second LIF neuron with weighted input
    lif_weighted lif2 (
        .current(state1),
        .weight(synapse_weight),
        .clk(clk),
        .reset_n(rst_n),
        .state(uo_out),
        .spike(spike2)
    );
    
    // Unused inputs
    wire unused = &{ena, uio_in, 1'b0};
    
endmodule