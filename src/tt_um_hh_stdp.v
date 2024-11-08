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
    // Reduced bit width parameters for area optimization
    parameter WIDTH = 12;
    parameter DECIMAL_BITS = 5;

    // Internal signals
    wire [7:0] v_mem1;
    wire [7:0] v_mem2;
    wire spike1, spike2;
    wire [WIDTH-1:0] i_syn;
    wire [WIDTH-1:0] current;
    wire [WIDTH-1:0] weight;
    
    // Convert input current (reduced width)
    assign current = {{(WIDTH-11){1'b0}}, ui_in, 3'b0};

    // First neuron
    hodgkin_huxley #(
        .WIDTH(WIDTH),
        .DECIMAL_BITS(DECIMAL_BITS)
    ) neuron1 (
        .clk(clk),
        .reset_n(rst_n),
        .i_stim(current),
        .i_syn(0),
        .spike(spike1),
        .v_mem(v_mem1)
    );

    // STDP synapse
    stdp_synapse #(
        .WIDTH(WIDTH),
        .DECIMAL_BITS(DECIMAL_BITS)
    ) synapse (
        .clk(clk),
        .reset_n(rst_n),
        .pre_spike(spike1),
        .post_spike(spike2),
        .weight(weight),
        .i_syn(i_syn)
    );

    // Second neuron
    hodgkin_huxley #(
        .WIDTH(WIDTH),
        .DECIMAL_BITS(DECIMAL_BITS)
    ) neuron2 (
        .clk(clk),
        .reset_n(rst_n),
        .i_stim(0),
        .i_syn(i_syn),
        .spike(spike2),
        .v_mem(v_mem2)
    );

    // Output assignments
    assign uo_out = v_mem1;
    assign uio_out = {spike1, spike2, v_mem2[7:2]};
    assign uio_oe = 8'b11111111;

    // Unused signals
    wire unused = ena & |uio_in;

endmodule

module hodgkin_huxley #(
    parameter WIDTH = 12,
    parameter DECIMAL_BITS = 5
)(
    input wire clk,
    input wire reset_n,
    input wire [WIDTH-1:0] i_stim,
    input wire [WIDTH-1:0] i_syn,
    output reg spike,
    output wire [7:0] v_mem
);
    // Local parameters with reduced precision
    localparam ONE = (1 << DECIMAL_BITS);
    localparam V_REST = (-65 * ONE) >>> 2;
    localparam E_NA = (50 * ONE) >>> 2;
    localparam E_K = (-77 * ONE) >>> 2;
    localparam E_L = (-54 * ONE) >>> 2;
    localparam MAX_VALUE = ((1 << (WIDTH-1)) - 1);
    localparam MIN_VALUE = (-(1 << (WIDTH-1)));
    
    // State variables with reduced widths
    reg [WIDTH-2:0] g_na, g_k, g_l;
    reg [WIDTH-2:0] m, h, n;
    reg [WIDTH-2:0] dt;
    reg [WIDTH-1:0] v_mem_full;
    
    // Pipeline registers
    reg [WIDTH-1:0] i_na, i_k, i_l;
    reg [WIDTH-1:0] total_current;
    
    // Rate constants
    wire [WIDTH-2:0] alpha_n, beta_n, alpha_m, beta_m, alpha_h, beta_h;

    // Map internal membrane potential to output
    assign v_mem = {v_mem_full[WIDTH-1:WIDTH-8]};

    function automatic [WIDTH-1:0] bound_value;
        input [WIDTH-1:0] val;
        begin
            bound_value = (val > MAX_VALUE) ? MAX_VALUE :
                         (val < MIN_VALUE) ? MIN_VALUE : val;
        end
    endfunction

    // Simplified state calculator
    hh_state #(
        .WIDTH(WIDTH),
        .DECIMAL_BITS(DECIMAL_BITS)
    ) state_calc (
        .voltage(v_mem_full),
        .alpha_n(alpha_n),
        .alpha_m(alpha_m),
        .alpha_h(alpha_h),
        .beta_n(beta_n),
        .beta_m(beta_m),
        .beta_h(beta_h),
        .clk(clk),
        .rst_n(reset_n)
    );

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            i_na <= 0;
            i_k <= 0;
            i_l <= 0;
            g_na <= (120 * ONE) >>> 2;
            g_k <= (36 * ONE) >>> 2;
            g_l <= ONE >>> 4;
            dt <= ONE >>> 4;
            n <= ONE >>> 2;
            m <= ONE >>> 2;
            h <= ONE >>> 2;
            v_mem_full <= V_REST;
            spike <= 0;
            total_current <= 0;
        end else begin
            // Simplified current calculations
            i_na <= ((g_na * h * m) >>> DECIMAL_BITS) * (v_mem_full - E_NA);
            i_k <= ((g_k * n * n) >>> DECIMAL_BITS) * (v_mem_full - E_K);
            i_l <= g_l * (v_mem_full - E_L);
            
            // Update total current
            total_current <= i_stim + i_syn - i_na - i_k - i_l;
            
            // Update membrane potential
            v_mem_full <= bound_value(v_mem_full + ((total_current * dt) >>> DECIMAL_BITS));
            
            // Simplified gate updates
            n <= bound_value(n + ((alpha_n * (ONE - n) - beta_n * n) * dt) >>> DECIMAL_BITS);
            m <= bound_value(m + ((alpha_m * (ONE - m) - beta_m * m) * dt) >>> DECIMAL_BITS);
            h <= bound_value(h + ((alpha_h * (ONE - h) - beta_h * h) * dt) >>> DECIMAL_BITS);
            
            // Spike detection
            spike <= (v_mem_full > 0);
        end
    end
endmodule

module hh_state #(
    parameter WIDTH = 12,
    parameter DECIMAL_BITS = 5
)(
    input wire [WIDTH-1:0] voltage,
    output reg [WIDTH-2:0] alpha_n,
    output reg [WIDTH-2:0] alpha_m,
    output reg [WIDTH-2:0] alpha_h,
    output reg [WIDTH-2:0] beta_n,
    output reg [WIDTH-2:0] beta_m,
    output reg [WIDTH-2:0] beta_h,
    input wire clk,
    input wire rst_n
);
    localparam ONE = (1 << DECIMAL_BITS);

    always @(posedge clk) begin
        if (!rst_n) begin
            alpha_n <= 0;
            beta_n <= 0;
            alpha_m <= 0;
            beta_m <= 0;
            alpha_h <= 0;
            beta_h <= 0;
        end else begin
            // Simplified rate calculations
            alpha_n <= (voltage + (55 * ONE)) >>> 6;
            beta_n <= ONE >>> 2;
            alpha_m <= (voltage + (40 * ONE)) >>> 3;
            beta_m <= ONE << 1;
            alpha_h <= ONE >>> 3;
            beta_h <= ONE >>> 1;
        end
    end
endmodule

module stdp_synapse #(
    parameter WIDTH = 12,
    parameter DECIMAL_BITS = 5
)(
    input wire clk,
    input wire reset_n,
    input wire pre_spike,
    input wire post_spike,
    output reg [WIDTH-1:0] weight,
    output wire [WIDTH-1:0] i_syn
);
    localparam ONE = (1 << DECIMAL_BITS);
    localparam MAX_WEIGHT = ((1 << (WIDTH-1)) - 1);
    localparam MIN_WEIGHT = 0;
    
    reg [WIDTH-2:0] pre_trace;
    reg [WIDTH-2:0] post_trace;
    
    function automatic [WIDTH-1:0] bound_weight;
        input [WIDTH-1:0] w;
        begin
            bound_weight = (w > MAX_WEIGHT) ? MAX_WEIGHT :
                          (w < MIN_WEIGHT) ? MIN_WEIGHT : w;
        end
    endfunction

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            weight <= ONE;
            pre_trace <= 0;
            post_trace <= 0;
        end else begin
            // Simplified trace decay
            pre_trace <= pre_trace - (pre_trace >>> 3);
            post_trace <= post_trace - (post_trace >>> 3);
            
            // Simplified weight updates
            if (pre_spike) begin
                pre_trace <= pre_trace + (ONE >>> 1);
                if (post_trace > 0)
                    weight <= bound_weight(weight - ((post_trace * weight) >>> (DECIMAL_BITS + 2)));
            end
            
            if (post_spike) begin
                post_trace <= post_trace + (ONE >>> 1);
                if (pre_trace > 0)
                    weight <= bound_weight(weight + ((pre_trace * (ONE - weight)) >>> (DECIMAL_BITS + 2)));
            end
        end
    end
    
    assign i_syn = pre_spike ? (weight >>> 2) : 0;
endmodule