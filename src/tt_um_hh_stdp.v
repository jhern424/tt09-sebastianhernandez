`default_nettype none

module tt_um_hh_stdp (
    input  wire [7:0] ui_in,    // Input stimulus current (0-255)
    output wire [7:0] uo_out,   // Neuron 1 membrane potential (0-255)
    input  wire [7:0] uio_in,   // Unused input port
    output wire [7:0] uio_out,  // [7:6]=spikes, [5:0]=Neuron 2 membrane potential
    output wire [7:0] uio_oe,   // Output enable (always active)
    input  wire       ena,      // Unused enable signal
    input  wire       clk,      // System clock
    input  wire       rst_n     // Active low reset
);
    // System parameters for fixed-point arithmetic
    parameter WIDTH = 8;        // Total bit width
    parameter DECIMAL_BITS = 4; // Number of fractional bits
    
    // Local parameters for scaling and learning
    localparam [WIDTH-1:0] ONE = (1 << DECIMAL_BITS);
    // Learning rates chosen for biological time scales:
    // LEARN_RATE_P: potentiation rate (~20% per coincidence)
    // LEARN_RATE_N: depression rate (~10% per coincidence)
    localparam [WIDTH-1:0] LEARN_RATE_P = ONE >>> 3; // 0.125 in fixed-point
    localparam [WIDTH-1:0] LEARN_RATE_N = ONE >>> 4; // 0.0625 in fixed-point
    
    // Internal signals
    wire [7:0] v_mem1;
    wire [5:0] v_mem2;
    wire spike1, spike2;
    wire signed [WIDTH-1:0] i_syn;
    reg signed [WIDTH-1:0] current;

    // Input current mapping:
    // Maps unsigned input (0-255) to signed range (-64 to +63)
    // This allows both excitatory (positive) and inhibitory (negative) currents
    always @* begin
        // Subtract 64 to center around zero
        // Values >= 64 become excitatory (positive)
        // Values < 64 become inhibitory (negative)
        current = $signed({1'b0, ui_in}) - $signed(8'd64);
    end

    // First neuron (pre-synaptic) - receives external current
    simple_neuron #(
        .WIDTH(WIDTH),
        .DECIMAL_BITS(DECIMAL_BITS)
    ) neuron1 (
        .clk(clk),
        .reset_n(rst_n),
        .i_stim(current),       // External current input
        .i_syn({WIDTH{1'b0}}),  // No synaptic input
        .spike(spike1),
        .v_mem(v_mem1)
    );

    // STDP synapse - connects neuron1 to neuron2
    simple_stdp #(
        .WIDTH(WIDTH),
        .DECIMAL_BITS(DECIMAL_BITS),
        .LEARN_RATE_P(LEARN_RATE_P),
        .LEARN_RATE_N(LEARN_RATE_N)
    ) synapse (
        .clk(clk),
        .reset_n(rst_n),
        .pre_spike(spike1),    // Spikes from neuron1
        .post_spike(spike2),   // Spikes from neuron2
        .i_syn(i_syn)         // Current to neuron2
    );

    // Second neuron (post-synaptic) - receives only synaptic current
    simple_neuron #(
        .WIDTH(WIDTH),
        .DECIMAL_BITS(DECIMAL_BITS)
    ) neuron2 (
        .clk(clk),
        .reset_n(rst_n),
        .i_stim({WIDTH{1'b0}}), // No external current
        .i_syn(i_syn),          // Synaptic current from STDP
        .spike(spike2),
        .v_mem({v_mem2, 2'b00}) // Pad to 8 bits
    );

    // Output assignments
    assign uo_out = v_mem1;                    // First neuron's membrane potential
    assign uio_out = {spike1, spike2, v_mem2}; // Spikes and second neuron's potential
    assign uio_oe = 8'b11111111;               // All outputs enabled

    // Synthesis directive to preserve unused signals
    (* keep = "true" *)
    wire unused = ena & |uio_in;
endmodule

module simple_neuron #(
    parameter WIDTH = 8,
    parameter DECIMAL_BITS = 4
)(
    input wire clk,
    input wire reset_n,
    input wire signed [WIDTH-1:0] i_stim,    // External stimulus current
    input wire signed [WIDTH-1:0] i_syn,     // Synaptic current
    output reg spike,                        // Spike output
    output wire [7:0] v_mem                  // Membrane potential (0-255)
);
    // Neuron model parameters (in fixed-point)
    localparam signed [WIDTH-1:0] ONE = (1 << DECIMAL_BITS);
    localparam signed [WIDTH-1:0] V_REST = -(4 * ONE);    // Resting potential
    localparam signed [WIDTH-1:0] V_THRESH = (2 * ONE);   // Spike threshold
    localparam signed [WIDTH-1:0] TAU = ONE >>> 2;        // Membrane time constant
    localparam signed [WIDTH-1:0] V_OFFSET = (6 * ONE);   // Output scaling offset

    // Internal state variables (extra bits for safe arithmetic)
    reg signed [WIDTH+2:0] v_mem_int;        // Internal membrane potential
    reg signed [WIDTH+2:0] v_mem_int_next;   // Next membrane potential
    reg signed [WIDTH+2:0] leak_current;     // Leakage current
    reg signed [WIDTH+2:0] total_current;    // Sum of all currents
    reg spike_next;                          // Next spike state

    // Output scaling with bounds checking:
    // 1. Add offset to shift negative values positive
    // 2. Scale to 8-bit range
    // 3. Clamp to 0-255
    wire signed [WIDTH+2:0] scaled_v_mem = v_mem_int + V_OFFSET;
    assign v_mem = (scaled_v_mem > 0) ? 
                  ((scaled_v_mem <= ((8'd255) << DECIMAL_BITS)) ? 
                   (scaled_v_mem >>> DECIMAL_BITS) : 8'd255) : 
                  8'd0;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            // Initialize all state variables
            v_mem_int <= V_REST;
            leak_current <= 0;
            total_current <= 0;
            spike <= 0;
            spike_next <= 0;
        end else begin
            // Calculate leak current (tends to restore rest potential)
            leak_current <= ($signed(V_REST) - v_mem_int) >>> 2;
            
            // Sum all currents (external + synaptic + leak)
            total_current <= $signed(i_stim) + $signed(i_syn) + leak_current;
            
            // Compute next membrane potential
            if (spike) begin
                // Reset after spike
                v_mem_int_next = V_REST;
            end else begin
                // Update potential based on currents
                v_mem_int_next = v_mem_int + ((total_current * $signed(TAU)) >>> DECIMAL_BITS);
            end

            // Generate spike if threshold is reached
            spike_next = (v_mem_int_next >= V_THRESH);
            
            // Update registers
            v_mem_int <= v_mem_int_next;
            spike <= spike_next;
        end
    end
endmodule

module simple_stdp #(
    parameter WIDTH = 8,
    parameter DECIMAL_BITS = 4,
    // Default learning rates if not specified
    parameter [WIDTH-1:0] LEARN_RATE_P = (1 << DECIMAL_BITS) >>> 3,
    parameter [WIDTH-1:0] LEARN_RATE_N = (1 << DECIMAL_BITS) >>> 4
)(
    input wire clk,
    input wire reset_n,
    input wire pre_spike,     // Spike from pre-synaptic neuron
    input wire post_spike,    // Spike from post-synaptic neuron
    output wire signed [WIDTH-1:0] i_syn  // Synaptic current output
);
    // STDP parameters
    localparam [WIDTH-1:0] ONE = (1 << DECIMAL_BITS);
    localparam [WIDTH-1:0] MAX_WEIGHT = (1 << (WIDTH-1)) - 1;  // Maximum weight
    localparam [WIDTH-1:0] MIN_WEIGHT = ONE >>> 2;             // Minimum weight
    localparam [WIDTH-1:0] TAU_SYN = ONE >>> 2;               // Synaptic decay time

    // STDP state variables (extra bit for calculations)
    reg [WIDTH+1:0] trace_pre;     // Pre-synaptic trace
    reg [WIDTH+1:0] trace_post;    // Post-synaptic trace
    reg [WIDTH+1:0] weight;        // Synaptic weight
    reg [WIDTH+1:0] syn_current;   // Synaptic current
    reg [WIDTH+1:0] next_weight;   // Next weight value

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            trace_pre <= 0;
            trace_post <= 0;
            weight <= ONE;
            syn_current <= 0;
            next_weight <= ONE;
        end else begin
            // Decay both traces (time window for STDP)
            trace_pre <= trace_pre - (trace_pre >>> 4);    // Decay rate sets STDP window
            trace_post <= trace_post - (trace_post >>> 4);
            
            // Exponential decay of synaptic current
            syn_current <= syn_current - ((syn_current * TAU_SYN) >>> DECIMAL_BITS);
            
            // Update traces and synaptic current on spikes
            if (pre_spike) begin
                trace_pre <= trace_pre + ONE;              // Record pre-spike
                syn_current <= syn_current + weight;       // Generate post-synaptic current
            end
            if (post_spike) begin
                trace_post <= trace_post + ONE;           // Record post-spike
            end
            
            // STDP weight updates
            next_weight = weight;
            if (pre_spike && trace_post > 0) begin
                // LTP: Strengthen synapse if post-spike preceded pre-spike
                next_weight = weight + ((trace_post * LEARN_RATE_P) >>> DECIMAL_BITS);
            end
            if (post_spike && trace_pre > 0) begin
                // LTD: Weaken synapse if pre-spike preceded post-spike
                next_weight = weight - ((trace_pre * LEARN_RATE_N) >>> DECIMAL_BITS);
            end
            
            // Apply weight bounds
            if (next_weight > MAX_WEIGHT)
                weight <= MAX_WEIGHT;
            else if (next_weight < MIN_WEIGHT)
                weight <= MIN_WEIGHT;
            else
                weight <= next_weight;
        end
    end

    // Generate scaled synaptic current output
    assign i_syn = $signed(syn_current[WIDTH-1:0] >>> DECIMAL_BITS);
endmodule