import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer, FallingEdge
from cocotb.binary import BinaryValue
import numpy as np

# Constants for the test
CLOCK_FREQ = 50_000_000  # 50 MHz
CLOCK_PERIOD = 1_000_000 / CLOCK_FREQ  # in ns
RESET_CYCLES = 10
TEST_DURATION = 1000  # cycles

# Current injection patterns
def generate_step_current(amplitude):
    return int(amplitude * 255 / 100)  # Convert percentage to 8-bit value

def generate_sine_current(freq, amplitude, offset, time):
    """Generate sinusoidal current pattern"""
    value = offset + amplitude * np.sin(2 * np.pi * freq * time)
    return int(max(0, min(255, value)))  # Clamp to 8-bit range

class HHMonitor:
    """Monitor for HH neuron behavior"""
    def __init__(self, dut):
        self.dut = dut
        self.spike_count1 = 0
        self.spike_count2 = 0
        self.last_spike_time1 = 0
        self.last_spike_time2 = 0
        
    def update(self, current_time):
        """Update spike statistics"""
        if self.dut.uio_out.value[0]:  # Neuron 1 spike
            if current_time - self.last_spike_time1 > 10:  # Debounce
                self.spike_count1 += 1
                self.last_spike_time1 = current_time
                
        if self.dut.uio_out.value[1]:  # Neuron 2 spike
            if current_time - self.last_spike_time2 > 10:  # Debounce
                self.spike_count2 += 1
                self.last_spike_time2 = current_time

@cocotb.test()
async def test_initialization(dut):
    """Test proper initialization after reset"""
    clock = Clock(dut.clk, CLOCK_PERIOD, units="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize values
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    
    # Reset sequence
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, RESET_CYCLES)
    dut.rst_n.value = 1
    
    # Check initial state
    await RisingEdge(dut.clk)
    assert dut.uio_out.value[0] == 0, "Neuron 1 should not spike after reset"
    assert dut.uio_out.value[1] == 0, "Neuron 2 should not spike after reset"

@cocotb.test()
async def test_single_neuron_response(dut):
    """Test response of first neuron to current injection"""
    clock = Clock(dut.clk, CLOCK_PERIOD, units="ns")
    cocotb.start_soon(clock.start())
    monitor = HHMonitor(dut)
    
    # Reset
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, RESET_CYCLES)
    dut.rst_n.value = 1
    
    # Test different current levels
    current_levels = [20, 40, 60, 80]  # Percentage of max current
    for current in current_levels:
        dut._log.info(f"Testing current level: {current}%")
        dut.ui_in.value = generate_step_current(current)
        
        # Monitor for 100 cycles
        for _ in range(100):
            await RisingEdge(dut.clk)
            monitor.update(cocotb.utils.get_sim_time('ns'))
            
        dut._log.info(f"Spikes detected: {monitor.spike_count1}")
        
        # Reset current
        dut.ui_in.value = 0
        await ClockCycles(dut.clk, 50)  # Recovery period

@cocotb.test()
async def test_stdp_learning(dut):
    """Test STDP learning between neurons"""
    clock = Clock(dut.clk, CLOCK_PERIOD, units="ns")
    cocotb.start_soon(clock.start())
    monitor = HHMonitor(dut)
    
    # Reset
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, RESET_CYCLES)
    dut.rst_n.value = 1
    
    # Induce spikes with specific timing for STDP
    for trial in range(10):
        # Stimulate first neuron
        dut.ui_in.value = generate_step_current(60)
        await ClockCycles(dut.clk, 10)
        dut.ui_in.value = 0
        
        # Wait for second neuron response
        await ClockCycles(dut.clk, 40)
        
        # Update statistics
        monitor.update(cocotb.utils.get_sim_time('ns'))
    
    dut._log.info(f"STDP test completed. N1 spikes: {monitor.spike_count1}, N2 spikes: {monitor.spike_count2}")

@cocotb.test()
async def test_frequency_response(dut):
    """Test neuron response to different input frequencies"""
    clock = Clock(dut.clk, CLOCK_PERIOD, units="ns")
    cocotb.start_soon(clock.start())
    monitor = HHMonitor(dut)
    
    # Reset
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, RESET_CYCLES)
    dut.rst_n.value = 1
    
    # Test different input frequencies
    frequencies = [1, 5, 10, 20]  # Hz
    for freq in frequencies:
        dut._log.info(f"Testing frequency: {freq} Hz")
        
        # Generate sinusoidal input
        for t in range(200):  # 200 time steps
            current = generate_sine_current(freq, 100, 128, t/200)
            dut.ui_in.value = current
            await ClockCycles(dut.clk, 1)
            monitor.update(cocotb.utils.get_sim_time('ns'))
        
        dut._log.info(f"Spikes at {freq}Hz: {monitor.spike_count1}")
        monitor.spike_count1 = 0  # Reset counter

@cocotb.test()
async def test_refractory_period(dut):
    """Test neuron refractory period"""
    clock = Clock(dut.clk, CLOCK_PERIOD, units="ns")
    cocotb.start_soon(clock.start())
    monitor = HHMonitor(dut)
    
    # Reset
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, RESET_CYCLES)
    dut.rst_n.value = 1
    
    # Strong stimulus
    dut.ui_in.value = generate_step_current(90)
    
    # Monitor response
    last_spike_time = 0
    min_interval = float('inf')
    
    for _ in range(200):
        await RisingEdge(dut.clk)
        current_time = cocotb.utils.get_sim_time('ns')
        
        if dut.uio_out.value[0]:  # Spike detected
            if last_spike_time > 0:
                interval = current_time - last_spike_time
                min_interval = min(min_interval, interval)
            last_spike_time = current_time
    
    dut._log.info(f"Minimum inter-spike interval: {min_interval:.2f} ns")

dut._log.info("All tests completed successfully!")