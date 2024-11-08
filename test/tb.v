// tb.v
`default_nettype none
`timescale 1ns / 1ps

module tb;
    // Modified timing parameters
    localparam RESET_DELAY = 200;
    localparam TEST_DURATION = 10000;
    localparam CYCLE_PERIOD = 20;

    reg clk;
    reg rst_n;
    reg ena;
    reg [7:0] ui_in;
    reg [7:0] uio_in;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    reg [31:0] spike_count_n1;
    reg [31:0] spike_count_n2;
    reg test_passed;

    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb);
        #1;
    end

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

    initial begin
        clk = 0;
        forever #(CYCLE_PERIOD/2) clk = ~clk;
    end

    initial begin
        rst_n = 0;
        ena = 1;
        ui_in = 0;
        uio_in = 0;
        spike_count_n1 = 0;
        spike_count_n2 = 0;
        test_passed = 1;

        #RESET_DELAY rst_n = 1;
        
        #400;
        test_pre_post_spiking();
        
        #400;
        check_test_results();
        
        $display("Test completed at time %t", $time);
        #100 $finish;
    end

    task test_pre_post_spiking;
        begin
            integer i;
            apply_current(8'h00, 8'h00, 1000);
            
            for (i = 0; i < 20; i = i + 1) begin
                // Strong stimulation
                apply_current(8'hE0, 8'h00, 100);
                #50;
                apply_current(8'h00, 8'hE0, 100);
                #50;
                apply_current(8'h00, 8'h00, 200);
            end

            // Test response with strong stimulus
            apply_current(8'hE0, 8'h00, 2000);
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

    always @(posedge clk) begin
        if (uio_out[7]) begin
            spike_count_n1 <= spike_count_n1 + 1;
            $display("Neuron 1 spike at time %t", $time);
        end
        if (uio_out[6]) begin
            spike_count_n2 <= spike_count_n2 + 1;
            $display("Neuron 2 spike at time %t", $time);
        end
        
        if ($time % 50 == 0) begin
            $display("Time %t: V_mem1 = %d, V_mem2 = %d",
                    $time,
                    $signed({1'b0, uo_out}),
                    $signed({1'b0, uio_out[5:0], 2'b00}));
        end
    end

endmodule