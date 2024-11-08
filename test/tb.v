// tb.v
`default_nettype none
`timescale 1ns / 1ps

module tb;
    // Modified timing parameters
    localparam RESET_DELAY = 200;         // Increased from 100
    localparam TEST_DURATION = 10000;     // Increased from 5000
    localparam CYCLE_PERIOD = 20;         // Kept at 50MHz clock period

    // DUT signals
    reg clk;
    reg rst_n;
    reg ena;
    reg [7:0] ui_in;
    reg [7:0] uio_in;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    // Test status signals
    reg [31:0] spike_count_n1;
    reg [31:0] spike_count_n2;
    reg test_passed;

    // Dump waveforms
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb);
        #1;
    end

    // DUT instantiation
    tt_um_hh_stdp dut (
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
        forever #(CYCLE_PERIOD/2) clk = ~clk;
    end

    // Test stimulus
    initial begin
        // Initialize
        rst_n = 0;
        ena = 1;
        ui_in = 0;
        uio_in = 0;
        spike_count_n1 = 0;
        spike_count_n2 = 0;
        test_passed = 1;

        // Extended reset sequence
        #RESET_DELAY rst_n = 1;
        
        // Test sequence
        #400;  // Longer stabilization period
        test_pre_post_spiking();
        
        // End simulation
        #400;  // Longer observation period
        check_test_results();
        
        $display("Test completed at time %t", $time);
        #100 $finish;
    end

    // Modified test tasks
    task test_pre_post_spiking;
        begin
            integer i;
            // Extended rest period
            apply_current(8'h00, 8'h00, 1000);
            
            // Modified STDP Training Phase
            for (i = 0; i < 15; i = i + 1) begin  // Increased iterations
                // Stronger stimulus for Neuron 1
                apply_current(8'hA0, 8'h00, 200);  // Increased duration
                #100;  // Longer inter-stimulus interval
                // Stronger stimulus for Neuron 2
                apply_current(8'h00, 8'hA0, 200);  // Increased duration
                #100;
                // Extended rest period
                apply_current(8'h00, 8'h00, 400);
            end

            // Extended test period
            apply_current(8'hA0, 8'h00, 4000);
            #1000;
        end
    endtask

    task apply_current;
        input [7:0] current_n1;
        input [7:0] current_n2;
        input integer duration;
        begin
            ui_in = current_n1;
            uio_in = current_n2;
            #duration;
        end
    endtask

    task check_test_results;
        begin
            if (spike_count_n1 == 0) begin
                $display("ERROR: Neuron 1 did not spike");
                test_passed = 0;
            end else begin
                $display("SUCCESS: Neuron 1 spiked %d times", spike_count_n1);
            end
            
            if (spike_count_n2 == 0) begin
                $display("Checking synaptic response...");
                if (spike_count_n2 > 0)
                    $display("SUCCESS: Neuron 2 spiked %d times", spike_count_n2);
                else begin
                    $display("ERROR: Neuron 2 did not spike");
                    test_passed = 0;
                end
            end
            
            if (test_passed)
                $display("All tests PASSED");
            else
                $display("Some tests FAILED");
        end
    endtask

    // Enhanced monitoring
    always @(posedge clk) begin
        // Monitor spikes with more detailed logging
        if (uio_out[7]) begin
            spike_count_n1 <= spike_count_n1 + 1;
            $display("Neuron 1 spike at time %t, Count: %d", $time, spike_count_n1 + 1);
        end
        if (uio_out[6]) begin
            spike_count_n2 <= spike_count_n2 + 1;
            $display("Neuron 2 spike at time %t, Count: %d", $time, spike_count_n2 + 1);
        end
        
        // More frequent membrane potential monitoring
        if ($time % 50 == 0) begin
            $display("Time %t: V_mem1 = %d, V_mem2 = %d",
                    $time,
                    $signed({1'b0, uo_out}),
                    $signed({1'b0, uio_out[5:0], 2'b00}));
        end
    end

endmodule