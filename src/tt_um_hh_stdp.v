`default_nettype none

module tt_um_hh_stdp (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path
    input  wire       ena,      // enable
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);
    // Fixed-point parameters
    parameter WIDTH = 16;
    parameter DECIMAL_BITS = 7;

    // Internal signals
    wire [WIDTH-1:0] v_mem1, v_mem2;
    wire spike1, spike2;
    wire [WIDTH-1:0] i_syn;
    wire [WIDTH-1:0] current;
    wire [WIDTH-1:0] weight;  // Added missing signal
    
    // Convert input current (fixed width)
    assign current = {{(WIDTH-15){1'b0}}, ui_in, 7'b0};

    // Instantiate submodules
    hodgkin_huxley neuron1 (
        .clk(clk),
        .reset_n(rst_n),
        .i_stim(current),
        .i_syn(16'b0),
        .spike(spike1),
        .v_mem(v_mem1)
    );

    stdp_synapse synapse (
        .clk(clk),
        .reset_n(rst_n),
        .pre_spike(spike1),
        .post_spike(spike2),
        .weight(weight),    // Connected missing port
        .i_syn(i_syn)
    );

    hodgkin_huxley neuron2 (
        .clk(clk),
        .reset_n(rst_n),
        .i_stim(16'b0),
        .i_syn(i_syn),
        .spike(spike2),
        .v_mem(v_mem2)
    );

    // Output assignments
    assign uo_out = v_mem1[WIDTH-1:WIDTH-8];
    assign uio_out = {spike1, spike2, v_mem2[WIDTH-1:WIDTH-6]};
    assign uio_oe = 8'b11111111;

    // Unused signals
    wire unused = ena & |uio_in;

endmodule

module hodgkin_huxley #(
    parameter WIDTH = 16,
    parameter DECIMAL_BITS = 7
)(
    input wire clk,
    input wire reset_n,
    input wire [WIDTH-1:0] i_stim,    
    input wire [WIDTH-1:0] i_syn,     
    output reg spike,                 
    output reg [WIDTH-1:0] v_mem
);
    // Neuron parameters
    reg [WIDTH-1:0] g_na, g_k, g_l, Cm;
    reg [WIDTH-1:0] m, h, n;
    wire [WIDTH-1:0] m_new, h_new, n_new;
    reg [WIDTH-1:0] dt;
    
    // Constants
    localparam V_REST = -65 * ONE;
    localparam E_NA = 50 * ONE;
    localparam E_K = -77 * ONE;
    localparam E_L = -54 * ONE;
    
    // Rate constants
    wire [WIDTH-1:0] alpha_n, beta_n, alpha_m, beta_m, alpha_h, beta_h;
    
    // Pipeline registers
    reg [WIDTH-1:0] i_na, i_k, i_l;
    reg [WIDTH-1:0] total_current;
    
    // State calculator instance
    hh_state state_calc (
        .voltage(v_mem),
        .alpha_n(alpha_n),
        .alpha_m(alpha_m),
        .alpha_h(alpha_h),
        .beta_n(beta_n),
        .beta_m(beta_m),
        .beta_h(beta_h),
        .clk(clk),
        .rst_n(reset_n)
    );

    // Initialize and update ion currents
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            i_na <= 0;
            i_k <= 0;
            i_l <= 0;
        end else begin
            // Calculate ion currents
            i_na <= ((g_na * h * m * m * m) >>> DECIMAL_BITS) * (v_mem - E_NA);
            i_k <= ((g_k * n * n * n * n) >>> DECIMAL_BITS) * (v_mem - E_K);
            i_l <= g_l * (v_mem - E_L);
        end
    end

    // Update membrane potential
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            v_mem <= V_REST;
            total_current <= 0;
            Cm <= ONE;
            g_na <= 120 * ONE;
            g_k <= 36 * ONE;
            g_l <= ONE / 4;  // 0.25
            dt <= ONE >>> 4;  // Small time step
            spike <= 0;
        end else begin
            // Update total current
            total_current <= i_stim + i_syn - i_na - i_k - i_l;
            // Update membrane potential
            v_mem <= bound_value(v_mem + ((total_current * dt) >>> DECIMAL_BITS));
            // Detect spike
            spike <= (v_mem > 0);
        end
    end

    // Update gate variables
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            n <= ONE >>> 2;  // ~0.25
            m <= ONE >>> 2;
            h <= ONE >>> 2;
        end else begin
            n <= bound_value(n + ((alpha_n * (ONE - n) - beta_n * n) * dt) >>> DECIMAL_BITS);
            m <= bound_value(m + ((alpha_m * (ONE - m) - beta_m * m) * dt) >>> DECIMAL_BITS);
            h <= bound_value(h + ((alpha_h * (ONE - h) - beta_h * h) * dt) >>> DECIMAL_BITS);
        end
    end

    // Helper function for value bounding
    function [WIDTH-1:0] bound_value;
        input [WIDTH-1:0] val;
        begin
            if (val > MAX_VALUE)
                bound_value = MAX_VALUE;
            else if (val < MIN_VALUE)
                bound_value = MIN_VALUE;
            else
                bound_value = val;
        end
    endfunction

endmodule

module hh_state #(
    parameter WIDTH = 16,
    parameter DECIMAL_BITS = 7
)(
    input wire [WIDTH-1:0] voltage,
    output reg [WIDTH-1:0] alpha_n,
    output reg [WIDTH-1:0] alpha_m,
    output reg [WIDTH-1:0] alpha_h,
    output reg [WIDTH-1:0] beta_n,
    output reg [WIDTH-1:0] beta_m,
    output reg [WIDTH-1:0] beta_h,
    input wire clk,
    input wire rst_n
);
    always @(posedge clk) begin
        if (!rst_n) begin
            alpha_n <= 0;
            beta_n <= 0;
            alpha_m <= 0;
            beta_m <= 0;
            alpha_h <= 0;
            beta_h <= 0;
        end else begin
            // Simplified rate constants with fixed-point arithmetic
            // alpha_n = 0.01(v+55)/(1-exp(-(v+55)/10))
            alpha_n <= (voltage + (55 * ONE)) >>> 7;
            
            // beta_n = 0.125*exp(-(v+65)/80)
            beta_n <= ONE >>> 3;
            
            // alpha_m = 0.1(v+40)/(1-exp(-(v+40)/10))
            alpha_m <= (voltage + (40 * ONE)) >>> 4;
            
            // beta_m = 4*exp(-(v+65)/18)
            beta_m <= ONE << 2;
            
            // alpha_h = 0.07*exp(-(v+65)/20)
            alpha_h <= ONE >>> 4;
            
            // beta_h = 1/(exp(-(v+35)/10)+1)
            beta_h <= ONE >>> 1;
        end
    end
endmodule

module stdp_synapse #(
    parameter WIDTH = 16,
    parameter DECIMAL_BITS = 7
)(
    input wire clk,
    input wire reset_n,
    input wire pre_spike,
    input wire post_spike,
    output reg [WIDTH-1:0] weight,    // Weight is now properly declared as output
    output wire [WIDTH-1:0] i_syn
);
    // STDP parameters
    localparam A_PLUS = ONE >>> 5;    // LTP strength
    localparam A_MINUS = ONE >>> 6;   // LTD strength
    
    reg [WIDTH-1:0] pre_trace;
    reg [WIDTH-1:0] post_trace;
    
    // Update traces and weights
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            weight <= ONE;
            pre_trace <= 0;
            post_trace <= 0;
        end else begin
            // Decay traces
            pre_trace <= pre_trace - (pre_trace >>> 4);
            post_trace <= post_trace - (post_trace >>> 4);
            
            // Update traces on spikes
            if (pre_spike) begin
                pre_trace <= pre_trace + ONE;
                if (post_trace > 0)  // LTD
                    weight <= bound_weight(weight - ((A_MINUS * post_trace * weight) >>> (DECIMAL_BITS + 4)));
            end
            
            if (post_spike) begin
                post_trace <= post_trace + ONE;
                if (pre_trace > 0)  // LTP
                    weight <= bound_weight(weight + ((A_PLUS * pre_trace * (ONE - weight)) >>> (DECIMAL_BITS + 4)));
            end
        end
    end
    
    // Generate synaptic current
    assign i_syn = pre_spike ? (weight >>> 2) : 0;
    
    // Helper function for weight bounding
    function [WIDTH-1:0] bound_weight;
        input [WIDTH-1:0] w;
        begin
            if (w > MAX_WEIGHT)
                bound_weight = MAX_WEIGHT;
            else if (w < MIN_WEIGHT)
                bound_weight = MIN_WEIGHT;
            else
                bound_weight = w;
        end
    endfunction

endmodule