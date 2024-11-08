`default_nettype none
`timescale 1ns / 1ps

module tb (
    // No ports in the testbench
);
    // Dump waveforms
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb);
        #1;
    end

    // Declare signals
    reg clk;
    reg rst_n;
    reg ena;
    reg [7:0] ui_in;
    reg [7:0] uio_in;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    // Gate level test signals
    `ifdef GL_TEST
        wire VPWR = 1'b1;
        wire VGND = 1'b0;
    `endif

    // Instantiate the DUT
    tt_um_hh_stdp dut (
    `ifdef GL_TEST
        .VPWR(VPWR),
        .VGND(VGND),
    `endif
        .ui_in(ui_in),
        .uo_out(uo_out),
        .uio_in(uio_in),
        .uio_out(uio_out),
        .uio_oe(uio_oe),
        .ena(ena),
        .clk(clk),
        .rst_n(rst_n)
    );

    // Clock generation (50MHz)
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    // Monitor spike outputs
    always @(posedge clk) begin
        if (uio_out[0]) 
            $display("Neuron 1 spike at time %t", $time);
        if (uio_out[1])
            $display("Neuron 2 spike at time %t", $time);
    end

endmodule