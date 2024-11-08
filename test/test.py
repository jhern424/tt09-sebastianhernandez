import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer
from cocotb.result import TestSuccess, TestFailure
import logging
from collections import defaultdict
import matplotlib.pyplot as plt

class SpikeMonitor:
    def __init__(self):
        self.spikes_n1 = []  # Store (time, spike) tuples for neuron 1
        self.spikes_n2 = []  # Store (time, spike) tuples for neuron 2
        self.weights = []    # Store (time, weight) tuples
        self.states_n2 = []  # Store (time, state) tuples for neuron 2
        self.current_time = 0

    def update(self, time_ns, uio_out, uo_out):
        self.current_time = time_ns
        # Record spikes (1 if spiked, 0 if not)
        self.spikes_n1.append((time_ns, 1 if uio_out & 0x80 else 0))
        self.spikes_n2.append((time_ns, 1 if uio_out & 0x40 else 0))
        # Record weight
        self.weights.append((time_ns, uio_out & 0x3F))
        # Record neuron 2 state
        self.states_n2.append((time_ns, uo_out))

    def plot_results(self, filename="neuron_activity.png"):
        # Create figure with subplots
        fig, (ax1, ax2, ax3, ax4) = plt.subplots(4, 1, figsize=(15, 10), sharex=True)
        
        # Plot Neuron 1 spikes
        times_n1, spikes_n1 = zip(*self.spikes_n1)
        ax1.stem(times_n1, spikes_n1, markerfmt='bo', linefmt='b-', basefmt=' ')
        ax1.set_ylabel('Neuron 1\nSpikes')
        ax1.set_title('Neural Network Activity Over Time')
        
        # Plot Neuron 2 spikes
        times_n2, spikes_n2 = zip(*self.spikes_n2)
        ax2.stem(times_n2, spikes_n2, markerfmt='ro', linefmt='r-', basefmt=' ')
        ax2.set_ylabel('Neuron 2\nSpikes')
        
        # Plot synaptic weight
        times_w, weights = zip(*self.weights)
        ax3.plot(times_w, weights, 'g-')
        ax3.set_ylabel('Synaptic\nWeight')
        
        # Plot Neuron 2 state
        times_s2, states_n2 = zip(*self.states_n2)
        ax4.plot(times_s2, states_n2, 'k-')
        ax4.set_ylabel('Neuron 2\nState')
        ax4.set_xlabel('Time (ns)')
        
        plt.tight_layout()
        plt.savefig(filename)
        plt.close()

async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await Timer(200, units="ns")
    dut.rst_n.value = 1
    await Timer(200, units="ns")

async def apply_input(dut, current, duration_ns):
    dut.ui_in.value = current
    await Timer(duration_ns, units="ns")

@cocotb.test()
async def test_learning(dut):
    # Setup logging
    dut._log.setLevel(logging.INFO)
    
    # Create spike monitor
    monitor = SpikeMonitor()
    
    # Start clock (50 MHz)
    clock = Clock(dut.clk, 20, units="ns")
    clk_thread = cocotb.start_soon(clock.start())
    
    try:
        # Initialize
        dut.ena.value = 1
        await reset_dut(dut)
        
        # Initial quiet period
        await apply_input(dut, 0x00, 1000)
        
        # STDP training cycles
        for i in range(20):
            # Strong stimulation
            await apply_input(dut, 0xE0, 100)
            await Timer(50, units="ns")
            
            # Allow for spike propagation
            await apply_input(dut, 0x80, 100)
            await Timer(50, units="ns")
            
            # Quiet period
            await apply_input(dut, 0x00, 200)
            
            # Record state at each time step during this cycle
            current_time = int(dut.clk.value.time)
            monitor.update(
                current_time,
                dut.uio_out.value.integer,
                dut.uo_out.value.integer
            )
            
            dut._log.info(f"Cycle {i}: Time={current_time}ns, "
                         f"N2_state={dut.uo_out.value.integer}, "
                         f"Weight={dut.uio_out.value.integer & 0x3F}")
        
        # Test post-learning behavior
        await apply_input(dut, 0xE0, 2000)
        await Timer(500, units="ns")
        
        # Generate visualization
        monitor.plot_results()
        
        # Check final results
        spike_count_n1 = sum(1 for _, spike in monitor.spikes_n1 if spike)
        spike_count_n2 = sum(1 for _, spike in monitor.spikes_n2 if spike)
        
        dut._log.info(f"Test completed. N1 spikes: {spike_count_n1}, N2 spikes: {spike_count_n2}")
        
        if spike_count_n1 > 0 and spike_count_n2 > 0:
            raise TestSuccess("Both neurons spiked successfully")
        if spike_count_n1 == 0:
            raise TestFailure("First neuron did not spike")
        if spike_count_n2 == 0:
            raise TestFailure("Second neuron did not spike")
            
    finally:
        clk_thread.kill()