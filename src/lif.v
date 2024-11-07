`default_nettype none

module lif (
    input wire [7:0] current,
    input wire clk,
    input wire reset_n,
    output reg [7:0] state,
    output wire spike
);

    // Internal signals
    wire [7:0] next_state;
    reg [7:0] threshold;

    // Sequential logic for state and threshold updates
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= 8'd0;
            threshold <= 8'd200;
        end else begin 
            state <= next_state;
        end
    end

    // Next state logic
    assign next_state = current + (state >> 1);

    // Spiking logic
    assign spike = (state >= threshold);

endmodule
