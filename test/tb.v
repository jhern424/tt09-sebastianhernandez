`default_nettype none
`timescale 1ns / 1ps

module tb ();
    // Debug settings
    parameter DUMP_WAVES = 1;
    parameter SIMULATION_TIME = 100000; // 100 microseconds
    
    // Dump signals to VCD file
    initial begin
        if (DUMP_WAVES) begin
            $dumpfile("tb.vcd");
            $dumpvars(0, tb);
        end
        #1;
    end

    // Test signals
    reg clk;
    reg rst_n;
    reg ena;
    reg [7:0] ui_in;    // Input current
    reg [7:0] uio_in;   // Unused inputs
    
    // Output monitoring
    wire [7:0] uo_out;  // First neuron membrane voltage
    wire [7:0] uio_out; // Second neuron data + spikes
    wire [7:0] uio_oe;  // IO direction control
    
    // Debug signals
    wire spike1 = uio_out[0];
    wire spike2 = uio_out[1];
    wire [5:0] v_mem2 = uio_out[7:2];
    
    // Internal monitoring (if debug enabled)
    `ifdef ENABLE_DEBUG_OUTPUTS
    wire [15:0] debug_n1, debug_m1, debug_h1;
    wire [15:0] debug_n2, debug_m2, debug_h2;
    wire [15:0] debug_pre_trace, debug_post_trace;
    `endif

    // Power signals for gate level testing
    `ifdef GL_TEST
    wire VPWR = 1'b1;
    wire VGND = 1'b0;
    `endif

    // Clock generation
    initial begin
        clk = 0;
        forever #10 clk = ~clk; // 50MHz clock
    end
    
    // Reset generation
    initial begin
        rst_n = 0;
        #100 rst_n = 1;
    end
    
    // DUT instantiation
    tt_um_hh_stdp dut (
        `ifdef GL_TEST
            .VPWR(VPWR),
            .VGND(VGND),
        `endif
        .ui_in(ui_in),      // Input current
        .uo_out(uo_out),    // First neuron voltage
        .uio_in(uio_in),    // Unused inputs
        .uio_out(uio_out),  // Second neuron + spikes
        .uio_oe(uio_oe),    // IO direction
        .ena(ena),          // Enable signal
        .clk(clk),          // System clock
        .rst_n(rst_n)       // Reset (active low)
    );
    
    // Stimulus generation
    reg [7:0] current_pattern [0:9];
    integer stim_index;
    
    initial begin
        // Initialize test vectors
        current_pattern[0] = 8'h00; // Rest
        current_pattern[1] = 8'h20; // Small current
        current_pattern[2] = 8'h40; // Medium current
        current_pattern[3] = 8'h60; // Large current
        current_pattern[4] = 8'h80; // Maximum current
        current_pattern[5] = 8'h60; // Step down
        current_pattern[6] = 8'h40;
        current_pattern[7] = 8'h20;
        current_pattern[8] = 8'h10;
        current_pattern[9] = 8'h00;
        
        // Initialize inputs
        ena = 1;
        ui_in = 0;
        uio_in = 0;
        
        // Wait for reset
        @(posedge rst_n);
        
        // Apply test pattern
        for (stim_index = 0; stim_index < 10; stim_index = stim_index + 1) begin
            @(posedge clk);
            ui_in = current_pattern[stim_index];
            #10000; // Wait 10us between changes
        end
    end
    
    // Monitoring and checking
    integer spike_count1 = 0;
    integer spike_count2 = 0;
    
    always @(posedge clk) begin
        // Count spikes
        if (spike1) spike_count1 = spike_count1 + 1;
        if (spike2) spike_count2 = spike_count2 + 1;
        
        // Basic checks
        if (spike1 && spike2) begin
            $display("Coincident spikes at time %t", $time);
        end
        
        // Monitor membrane voltages
        if (uo_out === 8'hxx) begin
            $display("Error: Invalid voltage value at time %t", $time);
        end
    end
    
    // Optional monitoring for debug builds
    `ifdef ENABLE_DEBUG_OUTPUTS
    always @(posedge clk) begin
        if (rst_n) begin
            // Monitor gate variables
            $display("N1 gates (n,m,h): %h, %h, %h", debug_n1, debug_m1, debug_h1);
            $display("N2 gates (n,m,h): %h, %h, %h", debug_n2, debug_m2, debug_h2);
            
            // Monitor STDP traces
            $display("STDP traces (pre,post): %h, %h", 
                    debug_pre_trace, debug_post_trace);
        end
    end
    `endif
    
    // Timeout
    initial begin
        #SIMULATION_TIME;
        $display("Simulation completed. Spike counts: N1=%d, N2=%d", 
                spike_count1, spike_count2);
        $finish;
    end

endmodule