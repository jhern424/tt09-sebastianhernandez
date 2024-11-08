import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, Timer
from cocotb.binary import BinaryValue
import logging
import random

async def reset_dut(dut):
    """Reset the DUT and wait for stability"""
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 10)  # Longer reset period
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)  # Wait for stability

async def monitor_spikes(dut, duration):
    """Monitor spike activity for a specified duration"""
    spikes_n1 = 0
    spikes_n2 = 0
    last_spike_n1 = False
    last_spike_n2 = False
    
    for _ in range(duration):
        await RisingEdge(dut.clk)
        
        # Detect rising edges of spikes
        if dut.uio_out.value[7] and not last_spike_n1:
            spikes_n1 += 1
            dut._log.info(f"Neuron 1 spike at cycle {_}")
        if dut.uio_out.value[6] and not last_spike_n2:
            spikes_n2 += 1
            dut._log.info(f"Neuron 2 spike at cycle {_}")
            
        last_spike_n1 = bool(dut.uio_out.value[7])
        last_spike_n2 = bool(dut.uio_out.value[6])
        
    return spikes_n1, spikes_n2

@cocotb.test()
async def test_neuron_basic(dut):
    """Test basic neuron functionality with different current levels"""
    
    # Setup logging
    dut._log.setLevel(logging.INFO)
    
    # Start clock
    clock = Clock(dut.clk, 20, units="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize
    dut.ena.value = 1
    await reset_dut(dut)
    
    # Test current response
    test_currents = [
        (0, 50),    # No current
        (32, 50),   # Small current
        (64, 50),   # Medium current
        (96, 50),   # Large current
        (128, 50)   # Maximum current
    ]
    
    for current, duration in test_currents:
        dut._log.info(f"\nTesting current level: {current}")
        dut.ui_in.value = current
        
        # Monitor response
        spikes_n1, spikes_n2 = await monitor_spikes(dut, duration)
        dut._log.info(f"Spikes - N1: {spikes_n1}, N2: {spikes_n2}")
        
        # Allow system to recover
        dut.ui_in.value = 0
        await ClockCycles(dut.clk, 25)
    
    # Basic assertions
    assert spikes_n1 > 0, "Neuron 1 should spike with sufficient current"

@cocotb.test()
async def test_stdp_learning(dut):
    """Test STDP learning with controlled spike timing"""
    
    clock = Clock(dut.clk, 20, units="ns")
    cocotb.start_soon(clock.start())
    
    dut.ena.value = 1
    await reset_dut(dut)
    
    # Test several STDP episodes
    for trial in range(5):
        dut._log.info(f"\nSTDP Trial {trial + 1}")
        
        # Generate pre-synaptic spike
        dut.ui_in.value = 96  # Strong stimulus
        await ClockCycles(dut.clk, 10)
        dut.ui_in.value = 0
        
        # Monitor for spike timing
        spikes_n1, spikes_n2 = await monitor_spikes(dut, 40)
        
        # Verify spike generation
        assert spikes_n1 > 0, f"No pre-synaptic spike in trial {trial}"
        
        # Recovery period
        await ClockCycles(dut.clk, 30)
    
    dut._log.info("STDP test completed successfully")

@cocotb.test()
async def test_burst_response(dut):
    """Test response to burst stimulation"""
    
    clock = Clock(dut.clk, 20, units="ns")
    cocotb.start_soon(clock.start())
    
    dut.ena.value = 1
    await reset_dut(dut)
    
    # Generate burst pattern
    burst_current = 80
    burst_duration = 10
    inter_burst_interval = 20
    num_bursts = 5
    
    for burst in range(num_bursts):
        dut._log.info(f"\nBurst {burst + 1}")
        
        # Apply burst
        dut.ui_in.value = burst_current
        spikes_n1, spikes_n2 = await monitor_spikes(dut, burst_duration)
        dut._log.info(f"Burst response - N1: {spikes_n1}, N2: {spikes_n2}")
        
        # Inter-burst interval
        dut.ui_in.value = 0
        await ClockCycles(dut.clk, inter_burst_interval)
    
    dut._log.info("Burst test completed successfully")