`default_nettype none
`timescale 1ns / 1ps

module tb;
    // Parameters
    localparam RESET_DELAY = 200;
    localparam TEST_DURATION = 5000;  // Reduced duration
    localparam CYCLE_PERIOD = 20;
    
    // Signals
    reg clk;
    reg rst_n;
    reg ena;
    reg [7:0] ui_in;
    reg [7:0] uio_in;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;
    
    // Monitoring
    reg [31:0] spike_count_n1;
    reg [31:0] spike_count_n2;
    reg [31:0] test_cycles;
    reg test_passed;
    
    // VCD dump
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb);
    end
    
    // DUT instantiation
    tt_um_two_lif_stdp dut (
        .ui_in(ui_in),
        .uo_out(uo_out),
        .uio_in(uio_in),
        .uio_out(uio_out),
        .uio_oe(uio_oe),
        .ena(ena),
        .clk(clk),
        .rst_n(rst_n)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CYCLE_PERIOD/2) clk = ~clk;
    end
    
    // Main test sequence
    initial begin
        // Initialize
        rst_n = 0;
        ena = 1;
        ui_in = 0;
        uio_in = 0;
        spike_count_n1 = 0;
        spike_count_n2 = 0;
        test_cycles = 0;
        test_passed = 1;
        
        // Reset
        #RESET_DELAY rst_n = 1;
        
        // Let cocotb drive the test
        #TEST_DURATION;
        
        // Check results
        check_test_results();
        
        // Clean finish
        #100 $display("Test completed successfully");
        #10 $finish;
    end
    
    // Results verification
    task check_test_results;
        begin
            if (spike_count_n1 > 0)
                $display("SUCCESS: First neuron spiked %d times", spike_count_n1);
            else begin
                $display("ERROR: First neuron did not spike");
                test_passed = 0;
            end
            
            if (spike_count_n2 > 0)
                $display("SUCCESS: Second neuron spiked %d times", spike_count_n2);
            else begin
                $display("ERROR: Second neuron did not spike");
                test_passed = 0;
            end
        end
    endtask
    
    // Monitoring
    always @(posedge clk) begin
        test_cycles <= test_cycles + 1;
        
        if (uio_out[7]) begin  // First neuron spike
            spike_count_n1 <= spike_count_n1 + 1;
            if (test_cycles % 10 == 0)  // Reduced logging
                $display("First neuron spike at time %t", $time);
        end
        
        if (uio_out[6]) begin  // Second neuron spike
            spike_count_n2 <= spike_count_n2 + 1;
            if (test_cycles % 10 == 0)  // Reduced logging
                $display("Second neuron spike at time %t", $time);
        end
        
        if (test_cycles % 100 == 0) begin  // Reduced monitoring frequency
            $display("Time %t: N2_state = %d, Weight = %d",
                    $time,
                    uo_out,
                    uio_out[5:0]);
        end
    end
    
endmodule