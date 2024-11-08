// hh_state.v - Improved state calculator with interpolation
`default_nettype none

module hh_state (
    input wire [15:0] voltage,
    output reg [15:0] alpha_n,
    output reg [15:0] alpha_m,
    output reg [15:0] alpha_h,
    output reg [15:0] beta_n,
    output reg [15:0] beta_m,
    output reg [15:0] beta_h,
    input wire clk,
    input wire rst_n,
    // Debug outputs
    output wire [15:0] debug_exp_val,
    output wire [`LUT_ADDR_BITS-1:0] debug_index
);
    // LUT storage
    reg [15:0] exp_lut [0:`LUT_SIZE-1];
    
    // LUT access signals
    wire [`LUT_ADDR_BITS-1:0] v_index;
    wire [`LUT_ADDR_BITS-1:0] v_index_next;
    wire [15:0] frac;
    
    // Instantiate LUT generator
    exp_lut_gen #(
        .WIDTH(`WIDTH),
        .DECIMAL_BITS(`DECIMAL_BITS),
        .LUT_SIZE(`LUT_SIZE)
    ) lut_gen (
        .exp_lut(exp_lut)
    );
    
    // Calculate LUT index and fraction for interpolation
    wire [23:0] v_lookup = voltage_to_index(voltage);
    assign v_index = v_lookup[23:`DECIMAL_BITS];
    assign v_index_next = (v_index == `LUT_SIZE-1) ? v_index : v_index + 1;
    assign frac = v_lookup[`DECIMAL_BITS-1:0];
    
    // Get interpolated value
    wire [15:0] exp_val = interpolate(
        exp_lut[v_index],
        exp_lut[v_index_next],
        frac
    );
    
    // Pipeline stages for rate calculations
    reg [15:0] voltage_delayed;
    reg [15:0] exp_val_delayed;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            voltage_delayed <= 0;
            exp_val_delayed <= 0;
            alpha_n <= 0;
            beta_n <= 0;
            alpha_m <= 0;
            beta_m <= 0;
            alpha_h <= 0;
            beta_h <= 0;
        end else begin
            // Stage 1: Delay inputs
            voltage_delayed <= voltage;
            exp_val_delayed <= exp_val;
            
            // Stage 2: Calculate rate constants
            alpha_n <= calc_alpha_n(voltage_delayed, exp_val_delayed);
            beta_n <= calc_beta_n(voltage_delayed, exp_val_delayed);
            alpha_m <= calc_alpha_m(voltage_delayed, exp_val_delayed);
            beta_m <= calc_beta_m(voltage_delayed, exp_val_delayed);
            alpha_h <= calc_alpha_h(voltage_delayed, exp_val_delayed);
            beta_h <= calc_beta_h(voltage_delayed, exp_val_delayed);
        end
    end
    
    // Debug outputs
    assign debug_exp_val = exp_val;
    assign debug_index = v_index;
    
    // Helper Functions
    function [23:0] voltage_to_index;
        input [15:0] v;
        reg [31:0] scaled;
        begin
            scaled = ((v - `V_MIN) * `LUT_SIZE) / `V_RANGE;
            voltage_to_index = scaled;
        end
    endfunction
    
    function [15:0] interpolate;
        input [15:0] val1;
        input [15:0] val2;
        input [15:0] frac;
        reg [31:0] temp;
        begin
            temp = val1 * (`ONE - frac) + val2 * frac;
            interpolate = temp >>> `DECIMAL_BITS;
        end
    endfunction
    
    // Rate calculation functions
    function [15:0] calc_alpha_n;
        input [15:0] v;
        input [15:0] exp_val;
        reg [15:0] v_shifted;
        reg [15:0] denominator;
        begin
            v_shifted = v + (55 * `ONE);
            denominator = `ONE - exp_val;
            calc_alpha_n = safe_div_mult(v_shifted, denominator, `ONE >>> 7);
        end
    endfunction
    
    function [15:0] calc_beta_n;
        input [15:0] v;
        input [15:0] exp_val;
        begin
            calc_beta_n = safe_mult(`ONE >>> 3, exp_val);
        end
    endfunction
    
    // [Similar implementations for other rate functions...]
    
    // Safe arithmetic operations
    function [15:0] safe_div_mult;
        input [15:0] num, den, scale;
        reg [31:0] temp;
        begin
            if (den == 0)
                safe_div_mult = `MAX_VALUE;
            else begin
                temp = (num * scale) / den;
                safe_div_mult = bound_value(temp);
            end
        end
    endfunction
    
    function [15:0] safe_mult;
        input [15:0] a, b;
        reg [31:0] temp;
        begin
            temp = a * b;
            safe_mult = bound_value(temp >>> `DECIMAL_BITS);
        end
    endfunction
    
    function [15:0] bound_value;
        input [15:0] val;
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