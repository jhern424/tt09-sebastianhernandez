// hodgkin_huxley.v - Main neuron implementation
`default_nettype none

module hodgkin_huxley #(
    parameter WIDTH = `WIDTH,
    parameter DECIMAL_BITS = `DECIMAL_BITS
)(
    input wire clk,
    input wire reset_n,
    input wire [WIDTH-1:0] i_stim,    
    input wire [WIDTH-1:0] i_syn,     
    output reg spike,                 
    output reg [WIDTH-1:0] v_mem,
    output reg [1:0] pipeline_stage,
    output reg valid_out,
    input wire ready_in,
    output reg ready_out,
    // Debug outputs
    output wire [WIDTH-1:0] debug_n,
    output wire [WIDTH-1:0] debug_m,
    output wire [WIDTH-1:0] debug_h
);
    // Pipeline stage definition
    localparam STAGE_CURRENTS = 2'b00;
    localparam STAGE_VMEM = 2'b01;
    localparam STAGE_GATES = 2'b10;
    localparam STAGE_OUTPUT = 2'b11;

    // Pipeline control
    reg [3:0] valid_pipeline;
    reg stall_pipeline;
    
    // State variables and conductances
    reg [WIDTH-1:0] g_na, g_k, g_l, Cm;
    reg [WIDTH-1:0] m, h, n;
    reg [WIDTH-1:0] m_prev, h_prev, n_prev;
    reg [WIDTH-1:0] dt;
    
    // Pipeline registers
    reg [WIDTH-1:0] i_na_reg, i_k_reg, i_l_reg;
    reg [WIDTH-1:0] v_mem_stage1, v_mem_stage2;
    reg [WIDTH-1:0] total_current;
    
    // Parameters
    localparam V_REST = -65 * `ONE;
    localparam E_NA = 50 * `ONE;
    localparam E_K = -77 * `ONE;
    localparam E_L = -54.387 * `ONE;
    
    // Rate constants from state calculator
    wire [WIDTH-1:0] alpha_n, beta_n, alpha_m, beta_m, alpha_h, beta_h;
    
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
    
    // Stage 1: Current calculations
    always @(posedge clk) begin
        if (!reset_n) begin
            i_na_reg <= 0;
            i_k_reg <= 0;
            i_l_reg <= 0;
            valid_pipeline[0] <= 0;
        end else if (!stall_pipeline) begin
            // Na current
            i_na_reg <= safe_mult3(g_na, h_prev, safe_mult3(m_prev, m_prev, m_prev)) *
                       safe_div(v_mem - E_NA, `ONE);
            
            // K current
            i_k_reg <= safe_mult3(g_k, safe_mult2(n_prev, n_prev), 
                      safe_mult2(n_prev, n_prev)) * safe_div(v_mem - E_K, `ONE);
            
            // Leak current
            i_l_reg <= safe_mult2(g_l, v_mem - E_L);
            
            valid_pipeline[0] <= ready_in;
        end
    end

    // Stage 2: Membrane potential
    always @(posedge clk) begin
        if (!reset_n) begin
            v_mem_stage1 <= V_REST;
            total_current <= 0;
            valid_pipeline[1] <= 0;
        end else if (!stall_pipeline) begin
            // Calculate total current and update membrane potential
            total_current <= bound_value(i_stim + i_syn - i_na_reg - i_k_reg - i_l_reg);
            v_mem_stage1 <= bound_value(v_mem + safe_mult2(total_current, dt));
            
            valid_pipeline[1] <= valid_pipeline[0];
        end
    end

    // Stage 3: Gate updates
    always @(posedge clk) begin
        if (!reset_n) begin
            n <= `ONE >> 2;
            m <= `ONE >> 2;
            h <= `ONE >> 6;
            valid_pipeline[2] <= 0;
        end else if (!stall_pipeline) begin
            // Update gates using alpha/beta values
            n <= bound_value(n_prev + safe_mult2(
                safe_mult2(alpha_n, `ONE - n_prev) - safe_mult2(beta_n, n_prev),
                dt));
            m <= bound_value(m_prev + safe_mult2(
                safe_mult2(alpha_m, `ONE - m_prev) - safe_mult2(beta_m, m_prev),
                dt));
            h <= bound_value(h_prev + safe_mult2(
                safe_mult2(alpha_h, `ONE - h_prev) - safe_mult2(beta_h, h_prev),
                dt));
            
            valid_pipeline[2] <= valid_pipeline[1];
        end
    end

    // Stage 4: Output and state update
    always @(posedge clk) begin
        if (!reset_n) begin
            v_mem <= V_REST;
            Cm <= `ONE;
            g_na <= 120 * `ONE;
            g_k <= 36 * `ONE;
            g_l <= 0.3 * `ONE;
            dt <= `ONE >> 4;
            spike <= 0;
            valid_pipeline[3] <= 0;
            ready_out <= 1;
        end else if (!stall_pipeline) begin
            // Update membrane voltage and spike detection
            v_mem <= v_mem_stage1;
            spike <= (v_mem_stage1 > 0);
            
            // Store previous values
            n_prev <= n;
            m_prev <= m;
            h_prev <= h;
            
            valid_pipeline[3] <= valid_pipeline[2];
            ready_out <= valid_pipeline[2];
        end
    end

    // Pipeline control
    always @(*) begin
        stall_pipeline = !ready_in || (valid_pipeline[3] && !ready_out);
        pipeline_stage = {valid_pipeline[3], valid_pipeline[1]};
        valid_out = valid_pipeline[3];
    end

    // Debug outputs
    assign debug_n = n;
    assign debug_m = m;
    assign debug_h = h;

    // Helper functions
    function [WIDTH-1:0] safe_mult2;
        input [WIDTH-1:0] a, b;
        reg [2*WIDTH-1:0] temp;
        begin
            temp = a * b;
            safe_mult2 = bound_value(temp >>> DECIMAL_BITS);
        end
    endfunction

    function [WIDTH-1:0] safe_mult3;
        input [WIDTH-1:0] a, b, c;
        reg [2*WIDTH-1:0] temp;
        begin
            temp = a * b * c;
            safe_mult3 = bound_value(temp >>> (2*DECIMAL_BITS));
        end
    endfunction

    function [WIDTH-1:0] safe_div;
        input [WIDTH-1:0] num, den;
        begin
            safe_div = (den == 0) ? `MAX_VALUE : (num << DECIMAL_BITS) / den;
        end
    endfunction

    function [WIDTH-1:0] bound_value;
        input [WIDTH-1:0] val;
        begin
            if (val > `MAX_VALUE)
                bound_value = `MAX_VALUE;
            else if (val < `MIN_VALUE)
                bound_value = `MIN_VALUE;
            else
                bound_value = val;
        end
    endfunction

endmodule