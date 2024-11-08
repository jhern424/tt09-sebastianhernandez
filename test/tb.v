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
    reg [7:0] ui_in;      // Input current for first neuron
    reg [7:0] uio_in;
    wire [7:0] uo_out;    // Second neuron state
    wire [7:0] uio_out;   // [7]=N1 spike, [6]=N2 spike, [5:0]=weight
    wire [7:0] uio_oe;
    
    // Monitoring
    integer spike_count_n1;
    integer spike_count_n2;
    integer weight_changes;
    reg [7:0] last_weight;
    
    // VCD dump
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb);
        $display("Starting simulation...");
        spike_count_n1 = 0;
        spike_count_n2 = 0;
        weight_changes = 0;
        last_weight = 0;
    end
    
    // DUT instantiation
    tt_um_two_lif_stdp dut (
        .ui_in(ui_in),    // Input current to N1
        .uo_out(uo_out),  // N2 state
        .uio_in(uio_in),
        .uio_out(uio_out), // Spikes and weight
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
        
        // Reset sequence
        #RESET_DELAY;
        rst_n = 1;
        #100;
        
        // Test sequence
        for (integer i = 0; i < 10; i = i + 1) begin
            // Strong input to N1
            $display("Time %t: Applying strong input", $time);
            ui_in = 8'hFF;  // Maximum input current
            #200;
            
            // Reduce input but keep some current flowing
            ui_in = 8'h80;
            #200;
            
            // Rest period
            ui_in = 8'h00;
            #200;
        end
        
        // Final observation period
        #1000;
        
        // Print results
        $display("Test completed at time %t", $time);
        $display("N1 spikes: %d", spike_count_n1);
        $display("N2 spikes: %d", spike_count_n2);
        $display("Weight changes: %d", weight_changes);
        
        #100 $finish;
    end
    
    // Monitor spikes and weights
    always @(posedge clk) begin
        // Monitor N1 spikes
        if (uio_out[7]) begin
            spike_count_n1 = spike_count_n1 + 1;
            $display("Time %t: N1 SPIKE!", $time);
        end
        
        // Monitor N2 spikes
        if (uio_out[6]) begin
            spike_count_n2 = spike_count_n2 + 1;
            $display("Time %t: N2 SPIKE!", $time);
        end
        
        // Monitor weight changes
        if (uio_out[5:0] != last_weight) begin
            weight_changes = weight_changes + 1;
            $display("Time %t: Weight changed from %d to %d", 
                    $time, last_weight, uio_out[5:0]);
            last_weight = uio_out[5:0];
        end
    end
    
endmodule