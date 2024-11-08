// defines.v - Complete parameter definitions
`ifndef _DEFINES_V_
`define _DEFINES_V_

// Basic arithmetic parameters
`define WIDTH 16
`define DECIMAL_BITS 7
`define INTEGER_BITS (`WIDTH - `DECIMAL_BITS)
`define ONE (1 << `DECIMAL_BITS)
`define MAX_VALUE ((1 << (`WIDTH-1)) - 1)
`define MIN_VALUE (-(1 << (`WIDTH-1)))

// Voltage and current scaling
`define VOLTAGE_SCALE (`ONE)
`define CURRENT_SCALE (`ONE)

// LUT parameters
`define LUT_ADDR_BITS 8
`define LUT_SIZE (1 << `LUT_ADDR_BITS)
`define V_MIN (-100 * `ONE)
`define V_MAX (100 * `ONE)
`define V_RANGE (`V_MAX - `V_MIN)
`define V_STEP (`V_RANGE / `LUT_SIZE)

// Pipeline configuration
`define TOTAL_PIPELINE_STAGES 4
`define SYNAPSE_PIPELINE_STAGES 2
`define MAX_CLOCK_FREQ 50_000_000

// Debug options
`define ENABLE_DEBUG_OUTPUTS
`define ENABLE_PIPELINE_MONITORING

`endif

// exp_lut_gen.v - LUT generation module
`default_nettype none

module exp_lut_gen #(
    parameter WIDTH = `WIDTH,
    parameter DECIMAL_BITS = `DECIMAL_BITS,
    parameter LUT_SIZE = `LUT_SIZE
)(
    output reg [WIDTH-1:0] exp_lut [0:LUT_SIZE-1]
);
    real temp;
    integer i;
    real step;
    real x_min = -10.0;
    real x_max = 10.0;
    
    initial begin
        step = (x_max - x_min) / LUT_SIZE;
        
        // Fill LUT with exp(-x) values
        for (i = 0; i < LUT_SIZE; i = i + 1) begin
            temp = x_min + (i * step);
            exp_lut[i] = $rtoi($exp(-temp) * (1 << DECIMAL_BITS));
        end
        
        // Ensure boundary conditions
        exp_lut[0] = (1 << DECIMAL_BITS);  // exp(0) = 1
        exp_lut[LUT_SIZE-1] = 0;           // exp(-inf) = 0
    end
endmodule

// math_functions.v - Common mathematical operations
`default_nettype none

module math_functions #(
    parameter WIDTH = `WIDTH,
    parameter DECIMAL_BITS = `DECIMAL_BITS
)(
    input wire clk,
    input wire [WIDTH-1:0] a,
    input wire [WIDTH-1:0] b,
    output reg [WIDTH-1:0] mult_result,
    output reg [WIDTH-1:0] div_result,
    output reg overflow
);
    // Extended precision for intermediate results
    reg [2*WIDTH-1:0] mult_temp;
    reg [WIDTH-1:0] div_temp;
    
    always @(posedge clk) begin
        // Multiplication with rounding
        mult_temp = a * b + (1 << (DECIMAL_BITS-1));
        mult_result = bound_value(mult_temp >> DECIMAL_BITS);
        
        // Division with overflow protection
        if (b == 0)
            div_result = `MAX_VALUE;
        else
            div_result = bound_value((a << DECIMAL_BITS) / b);
            
        // Set overflow flag
        overflow = (mult_temp > (1 << (2*WIDTH-1))) || (b == 0);
    end
    
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