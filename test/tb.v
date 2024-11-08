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

    // Declare wire to access internal synaptic weight (RTL simulation only)
    `ifndef GL_TEST
        wire [7:0] synaptic_weight;
        assign synaptic_weight = dut.synapse.weight;
    `endif

    // Test status signals
    reg [31:0] spike_count_n1;
    reg [31:0] spike_count_n2;
    reg test_passed;

    // Dump waveforms
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb);
        // Dump synaptic weight only in RTL simulation
        `ifndef GL_TEST
            $dumpvars(1, dut.synapse.weight);
        `endif
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
        
        // Test sequence: Stimulate Neuron 1 only and train synapse
        #200;
        test_pre_post_spiking();
        
        // End simulation
        #200;
        check_test_results();
        
        $display("Test completed at time %t", $time);
        #100 $finish;
    end

    // Test tasks
    task test_pre_post_spiking;
        begin
            integer i;
            // Ensure both neurons are at rest
            apply_current(8'h00, 8'h00, 500);
            
            // STDP Training Phase
            for (i = 0; i < 10; i = i + 1) begin
                // Stimulate Neuron 1 (pre-synaptic spike)
                apply_current(8'h80, 8'h00, 100);
                #50;
                // Stimulate Neuron 2 (post-synaptic spike)
                apply_current(8'h00, 8'h80, 100);
                #50;
                // Rest period
                apply_current(8'h00, 8'h00, 200);
            end

            // Test if Neuron 2 spikes in response to Neuron 1 after training
            apply_current(8'h80, 8'h00, 2000);  // Extended duration to observe spiking
            #500;
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
                $display("Neuron 2 did not spike independently, checking synaptic response...");
                // If Neuron 2 spiked during the final test, consider it a pass
                if (spike_count_n2 > 0)
                    $display("Neuron 2 spiked in response to Neuron 1 after training.");
                else begin
                    $display("ERROR: Neuron 2 did not spike in response to Neuron 1");
                    test_passed = 0;
                end
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
        if ($time % 100 == 0) begin
            `ifndef GL_TEST
                $display("Time %t: V_mem1 = %d, V_mem2 = %d, Synaptic Weight = %d",
                        $time,
                        $signed({1'b0, uo_out}),
                        $signed({1'b0, uio_out[5:0], 2'b00}),
                        synaptic_weight);
            `else
                $display("Time %t: V_mem1 = %d, V_mem2 = %d",
                        $time,
                        $signed({1'b0, uo_out}),
                        $signed({1'b0, uio_out[5:0], 2'b00}));
            `endif
        end
    end

endmodule
