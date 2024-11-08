`default_nettype none
`timescale 1ns / 1ps

module tb;
    // Parameters
    localparam RESET_DELAY = 200;
    localparam TEST_DURATION = 14000;
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
    reg test_passed;
    reg test_done;
    
    // VCD dump
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb);
        test_done = 0;
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
        // Initialize
        rst_n = 0;
        ena = 1;
        ui_in = 0;
        uio_in = 0;
        spike_count_n1 = 0;
        spike_count_n2 = 0;
        test_passed = 1;
        
        // Reset sequence
        #RESET_DELAY rst_n = 1;
        #400;
        
        // Run test
        test_pre_post_spiking();
        #400;
        
        // Check results
        check_test_results();
        
        // Signal test completion
        test_done = 1;
        
        // Wait for monitoring to complete
        #2000;
        
        $display("Test completed at time %t", $time);
        
        // Additional delay before finish
        #1000;
        
        if (test_passed)
            $display("All tests passed successfully");
        else
            $display("Some tests failed");
            
        #100 $finish;
    end
    
    // Test task
    task test_pre_post_spiking;
        begin
            integer i;
            
            // Initial quiet period
            apply_input(8'h00, 1000);
            
            // STDP training cycles
            for (i = 0; i < 20; i = i + 1) begin
                // Strong stimulation
                apply_input(8'hE0, 100);
                #50;
                
                // Allow for spike propagation
                apply_input(8'h80, 100);
                #50;
                
                // Quiet period
                apply_input(8'h00, 200);
            end
            
            // Test post-learning behavior
            apply_input(8'hE0, 2000);
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
        end
    endtask
    
    // Spike monitoring
    always @(posedge clk) begin
        if (uio_out[7]) begin  // First neuron spike
            spike_count_n1 <= spike_count_n1 + 1;
            if (!test_done)  // Only log spikes before test completion
                $display("First neuron spike at time %t", $time);
        end
        
        if (uio_out[6]) begin  // Second neuron spike
            spike_count_n2 <= spike_count_n2 + 1;
            if (!test_done)  // Only log spikes before test completion
                $display("Second neuron spike at time %t", $time);
        end
        
        // Reduced monitoring frequency and only before test completion
        if (!test_done && $time % 2000 == 0) begin
            $display("Time %t: N2_state = %d, Weight = %d",
                    $time,
                    uo_out,
                    uio_out[5:0]);
        end
    end
    
endmodule