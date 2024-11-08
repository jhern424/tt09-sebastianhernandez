`default_nettype none
`timescale 1ns / 1ps

module tb;
    // Modified timing parameters
    localparam RESET_DELAY = 200;
    localparam TEST_DURATION = 10000;
    localparam CYCLE_PERIOD = 20;
    
    // Test bench signals
    reg clk;
    reg rst_n;
    reg ena;
    reg [7:0] ui_in;
    reg [7:0] uio_in;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;
    
    // Monitoring variables
    reg [31:0] spike_count_n1;
    reg [31:0] spike_count_n2;
    reg [7:0] prev_weight;
    reg test_passed;
    
    // VCD dump
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb);
        #1;
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
        // Initialize signals
        rst_n = 0;
        ena = 1;
        ui_in = 0;
        uio_in = 0;
        spike_count_n1 = 0;
        spike_count_n2 = 0;
        prev_weight = 0;
        test_passed = 1;
        
        // Reset sequence
        #RESET_DELAY rst_n = 1;
        #400;
        
        // Run tests
        test_stdp_learning();
        #400;
        
        // Check results
        check_test_results();
        
        $display("Test completed at time %t", $time);
        #100 $finish;
    end
    
    // STDP learning test task
    task test_stdp_learning;
        begin
            integer i;
            
            // Initial quiet period
            apply_input(8'h00, 1000);
            
            // Test STDP with various spike patterns
            for (i = 0; i < 20; i = i + 1) begin
                // Generate pre-synaptic spike
                apply_input(8'hE0, 100);  // Strong stimulus to first neuron
                #50;
                
                // Allow some time for the spike to propagate
                apply_input(8'h80, 100);
                
                // Record weight
                $display("Time %t: Synaptic weight = %d", $time, uio_out[5:0]);
                
                // Quiet period
                apply_input(8'h00, 200);
            end
            
            // Test response after learning
            $display("Testing post-learning response...");
            apply_input(8'hA0, 2000);  // Moderate stimulus
            #500;
        end
    endtask
    
    // Input application task
    task apply_input;
        input [7:0] current;
        input integer duration;
        begin
            ui_in = current;
            #duration;
        end
    endtask
    
    // Results checking task
    task check_test_results;
        begin
            // Check if neurons spiked
            if (spike_count_n1 == 0) begin
                $display("ERROR: First neuron did not spike");
                test_passed = 0;
            end else begin
                $display("SUCCESS: First neuron spiked %d times", spike_count_n1);
            end
            
            if (spike_count_n2 == 0) begin
                $display("ERROR: Second neuron did not spike");
                test_passed = 0;
            end else begin
                $display("SUCCESS: Second neuron spiked %d times", spike_count_n2);
            end
            
            // Display final test status
            if (test_passed)
                $display("All tests PASSED");
            else
                $display("Some tests FAILED");
        end
    endtask
    
    // Monitor spikes and state
    always @(posedge clk) begin
        // Monitor spikes
        if (uio_out[7]) begin  // First neuron spike
            spike_count_n1 <= spike_count_n1 + 1;
            $display("Time %t: Neuron 1 spike", $time);
        end
        
        if (uio_out[6]) begin  // Second neuron spike
            spike_count_n2 <= spike_count_n2 + 1;
            $display("Time %t: Neuron 2 spike", $time);
        end
        
        // Monitor states and weight periodically
        if ($time % 100 == 0) begin
            $display("Time %t: N2_state = %d, Weight = %d", 
                    $time, 
                    $signed({1'b0, uo_out}),      // Second neuron state
                    uio_out[5:0]);                // Synaptic weight
                    
            // Check for weight changes
            if (uio_out[5:0] != prev_weight) begin
                $display("Time %t: Weight changed from %d to %d", 
                        $time, prev_weight, uio_out[5:0]);
                prev_weight = uio_out[5:0];
            end
        end
    end
    
endmodule