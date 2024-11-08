// tb.v
`default_nettype none
`timescale 1ns / 1ps

module tb;
    // Testbench duration parameters
    localparam RESET_DELAY = 100;
    localparam TEST_DURATION = 5000;
    localparam CYCLE_PERIOD = 20;  // 50MHz clock period

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

    // Gate level test signals
    `ifdef GL_TEST
        wire VPWR = 1'b1;
        wire VGND = 1'b0;
    `endif

    // DUT instantiation
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

        // Reset sequence
        #RESET_DELAY rst_n = 1;
        
        // Test sequence 1: Gradually increasing current to both neurons
        #200;
        test_current_response();
        
        // Test sequence 2: STDP learning test
        #200;
        test_stdp();
        
        // Test sequence 3: Burst response
        #200;
        test_burst_response();

        // End simulation
        #200;
        check_test_results();
        
        $display("Test completed at time %t", $time);
        #100 $finish;
    end

    // Test tasks
    task test_current_response;
        begin
            // Test different current levels on both neurons
            apply_current(8'h20, 8'h20, 500); // Small current
            apply_current(8'h40, 8'h40, 500); // Medium current
            apply_current(8'h80, 8'h80, 500); // Large current
            apply_current(8'h00, 8'h00, 500); // Return to rest
        end
    endtask

    task test_stdp;
        begin
            repeat(3) begin
                // Generate pre-post spike pairs on both neurons
                apply_current(8'h60, 8'h60, 100);  // Induce spikes
                #200;
                apply_current(8'h00, 8'h00, 100);  // Allow recovery
                #200;
            end
        end
    endtask

    task test_burst_response;
        begin
            repeat(5) begin
                apply_current(8'h70, 8'h70, 50);   // Brief strong stimulus
                #100;
                apply_current(8'h00, 8'h00, 50);   // Brief recovery
                #100;
            end
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
            end
            if (spike_count_n2 == 0) begin
                $display("ERROR: Neuron 2 did not spike");
                test_passed = 0;
            end
            
            if (test_passed)
                $display("All tests PASSED");
            else
                $display("Some tests FAILED");
        end
    endtask

    // Monitor outputs
    always @(posedge clk) begin
        // Monitor spikes
        if (uio_out[7]) begin
            spike_count_n1 <= spike_count_n1 + 1;
            $display("Neuron 1 spike at time %t", $time);
        end
        if (uio_out[6]) begin
            spike_count_n2 <= spike_count_n2 + 1;
            $display("Neuron 2 spike at time %t", $time);
        end
        
        // Monitor membrane potentials periodically
        if ($time % 100 == 0)
            $display("Time %t: V_mem1 = %d, V_mem2 = %d",
                    $time,
                    $signed({1'b0, uo_out}),
                    $signed({1'b0, uio_out[5:0], 2'b00}));
    end

endmodule
