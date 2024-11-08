// tt_um_hh_stdp.v - Top-level module
`default_nettype none

module tt_um_hh_stdp (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // will go high when the design is enabled
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // Parameters
    localparam WIDTH = `WIDTH;
    localparam DECIMAL_BITS = `DECIMAL_BITS;

    // Internal signals
    wire [WIDTH-1:0] v_mem1, v_mem2;
    wire spike1, spike2;
    wire [WIDTH-1:0] i_syn;
    wire [WIDTH-1:0] current;
    
    // Pipeline control signals
    wire ready_n1_to_syn, ready_syn_to_n2;
    wire valid_n1_to_syn, valid_syn_to_n2;
    wire [1:0] n1_pipeline_stage, n2_pipeline_stage;

    // Debug signals
    wire [WIDTH-1:0] debug_n1, debug_m1, debug_h1;
    wire [WIDTH-1:0] debug_n2, debug_m2, debug_h2;
    wire [WIDTH-1:0] debug_pre_trace, debug_post_trace;

    // Convert input current
    assign current = {8'b0, ui_in, 7'b0};

    // First neuron
    hodgkin_huxley #(
        .WIDTH(WIDTH),
        .DECIMAL_BITS(DECIMAL_BITS)
    ) neuron1 (
        .clk(clk),
        .reset_n(rst_n),
        .i_stim(current),
        .i_syn(16'b0),
        .spike(spike1),
        .v_mem(v_mem1),
        .pipeline_stage(n1_pipeline_stage),
        .valid_out(valid_n1_to_syn),
        .ready_in(ready_syn_to_n1),
        .ready_out(ready_n1_to_syn),
        .debug_n(debug_n1),
        .debug_m(debug_m1),
        .debug_h(debug_h1)
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
        .valid_in(valid_n1_to_syn),
        .ready_in(ready_n2_to_syn),
        .valid_out(valid_syn_to_n2),
        .ready_out(ready_syn_to_n1),
        .i_syn(i_syn),
        .debug_pre_trace(debug_pre_trace),
        .debug_post_trace(debug_post_trace)
    );

    // Second neuron
    hodgkin_huxley #(
        .WIDTH(WIDTH),
        .DECIMAL_BITS(DECIMAL_BITS)
    ) neuron2 (
        .clk(clk),
        .reset_n(rst_n),
        .i_stim(16'b0),
        .i_syn(i_syn),
        .spike(spike2),
        .v_mem(v_mem2),
        .pipeline_stage(n2_pipeline_stage),
        .valid_in(valid_syn_to_n2),
        .ready_in(1'b1),
        .valid_out(),
        .ready_out(ready_n2_to_syn),
        .debug_n(debug_n2),
        .debug_m(debug_m2),
        .debug_h(debug_h2)
    );

    // Output assignments
    assign uo_out = v_mem1[WIDTH-1:WIDTH-8];
    assign uio_out = {
        spike1,
        spike2,
        v_mem2[WIDTH-1:WIDTH-6]
    };
    assign uio_oe = 8'b11111111;

    // Unused signals
    wire unused = &{ena, uio_in};

    // Monitor total pipeline latency
    reg [3:0] total_latency;
    always @(posedge clk) begin
        if (!rst_n)
            total_latency <= 0;
        else
            total_latency <= `TOTAL_PIPELINE_STAGES + 
                           `SYNAPSE_PIPELINE_STAGES;
    end

endmodule