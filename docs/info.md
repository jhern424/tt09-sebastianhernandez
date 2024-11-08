<!---
This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.
You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

This design implements a biologically accurate Hodgkin-Huxley (HH) neuron model with spike-timing-dependent plasticity (STDP). The system consists of:

1. Two Hodgkin-Huxley Neurons:
   - Implements full ion channel dynamics (Na+, K+, leak)
   - Uses fixed-point arithmetic (16-bit, 7 decimal bits)
   - Features configurable membrane properties and channel conductances
   - Generates biologically realistic action potentials

2. STDP Synapse:
   - Connects the two neurons
   - Implements spike-timing-dependent plasticity
   - Features adjustable learning rates for potentiation and depression
   - Maintains pre- and post-synaptic traces for timing

3. Advanced Features:
   - LUT-based exponential calculations for efficiency
   - Pipelined architecture for improved performance
   - Linear interpolation for smooth dynamics
   - Overflow protection and bounded calculations

The design uses the following parameters:
- Operating Frequency: 50 MHz
- Resolution: 16-bit fixed-point
- Voltage Range: -100mV to +100mV
- Conductances: Na+ (120mS), K+ (36mS), Leak (0.3mS)

## How to test

The design can be tested in several ways:

1. Basic Functionality:
   - Apply current input through ui[7:0]
   - Monitor first neuron's membrane voltage on uo[7:0]
   - Observe spike generation on uio[0] (Neuron 1) and uio[1] (Neuron 2)
   - View second neuron's voltage on uio[7:2]

2. Spike Generation Test:
   ```verilog
   // Example test sequence
   ui_in = 8'h20;  // Apply moderate current
   #1000;          // Wait for spike
   ui_in = 8'h00;  // Remove current
   #2000;          // Observe recovery
   ```

3. STDP Learning:
   - Generate spikes in first neuron
   - Observe synaptic weight changes
   - Monitor second neuron's response

4. Debug Outputs:
   - Gate variables (m, h, n) available for monitoring
   - Pre- and post-synaptic trace values
   - Pipeline stage status

## External hardware

No external hardware is required for basic operation. However, for detailed analysis, the following might be useful:

1. Oscilloscope or Logic Analyzer:
   - Monitor membrane voltage waveforms
   - Capture spike timing
   - Observe synaptic weight changes

2. Signal Generator (optional):
   - Generate precise current injection patterns
   - Test frequency response
   - Analyze refractory period

## Target Performance

The design aims to achieve:
- Temporal Resolution: 0.1ms
- Voltage Resolution: 0.1mV
- Spike Generation: ~2ms width
- STDP Window: ±20ms
- Maximum Firing Rate: 200Hz

## Resource Usage

The implementation utilizes:
- LUT Resources: 256 entries for exponential calculation
- Memory: Minimal, mainly for state variables
- Pipeline Stages: 4 for neuron, 2 for synapse
- Fixed-Point Units: Multipliers and dividers with overflow protection

## Future Improvements

Possible enhancements:
1. Additional ion channels for more complex dynamics
2. Multiple synapse types (excitatory/inhibitory)
3. Neuromodulation capabilities
4. Parameter runtime configurability
5. Extended STDP learning rules