import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from cocotb.binary import BinaryValue
import logging

async def reset_dut(dut):
    """Reset the DUT and wait for stability"""
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 20)  # Longer reset period
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 20)  # Wait for stability

async def apply_current(dut, current_n1, current_n2, duration):
    """Apply current to both neurons for a specified duration"""
    dut.ui_in.value = current_n1
    dut.uio_in.value = current_n2
    await ClockCycles(dut.clk, duration)

async def monitor_spikes(dut, duration):
    """Monitor spike activity for a specified duration"""
    spikes_n1 = 0
    spikes_n2 = 0
    last_spike_n1 = False
    last_spike_n2 = False
    
    for _ in range(duration):
        await RisingEdge(dut.clk)
        
        # Detect rising edges of spikes
        current_spike_n1 = bool(dut.uio_out.value.integer & 0x80)
        current_spike_n2 = bool(dut.uio_out.value.integer & 0x40)
        
        if current_spike_n1 and not last_spike_n1:
            spikes_n1 += 1
            dut._log.info(f"Neuron 1 spike at cycle {_}")
        if current_spike_n2 and not last_spike_n2:
            spikes_n2 += 1
            dut._log.info(f"Neuron 2 spike at cycle {_}")
            
        last_spike_n1 = current_spike_n1
        last_spike_n2 = current_spike_n2
        
    return spikes_n1, spikes_n2

@cocotb.test()
async def test_neuron_basic(dut):
    """Test basic neuron functionality with different current levels"""
    
    # Setup logging
    dut._log.setLevel(logging.INFO)
    
    # Start clock
    clock = Clock(dut.clk, 10, units="ns")  # 100 MHz clock
    cocotb.start_soon(clock.start())
    
    # Initialize
    dut.ena.value = 1
    await reset_dut(dut)
    
    # Test current response
    test_currents = [
        (0, 0, 100),       # No current to both neurons
        (32, 32, 100),     # Small current
        (64, 64, 100),     # Medium current
        (96, 96, 100),     # Large current
        (128, 128, 100)    # Maximum current
    ]
    
    for current_n1, current_n2, duration in test_currents:
        dut._log.info(f"\nTesting current level: N1={current_n1}, N2={current_n2}")
        await apply_current(dut, current_n1, current_n2, duration)
        
        # Monitor response
        spikes_n1, spikes_n2 = await monitor_spikes(dut, duration)
        dut._log.info(f"Spikes - N1: {spikes_n1}, N2: {spikes_n2}")
        
        # Allow system to recover
        await apply_current(dut, 0, 0, 50)
    
    # Basic assertions
    assert spikes_n1 > 0, "Neuron 1 should spike with sufficient current"
    assert spikes_n2 > 0, "Neuron 2 should spike with sufficient current"

@cocotb.test()
async def test_stdp_learning(dut):
    """Test STDP learning with controlled spike timing"""
    
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    dut.ena.value = 1
    await reset_dut(dut)
    
    # Test several STDP episodes
    for trial in range(3):
        dut._log.info(f"\nSTDP Trial {trial + 1}")
        
        # Generate pre-synaptic spike on Neuron 1 and post-synaptic spike on Neuron 2
        await apply_current(dut, 96, 96, 20)  # Strong stimulus to both neurons
        spikes_n1, spikes_n2 = await monitor_spikes(dut, 50)
        
        # Verify spike generation
        assert spikes_n1 > 0, f"No pre-synaptic spike in trial {trial + 1}"
        assert spikes_n2 > 0, f"No post-synaptic spike in trial {trial + 1}"
        
        # Recovery period
        await apply_current(dut, 0, 0, 50)
    
    dut._log.info("STDP test completed successfully")

@cocotb.test()
async def test_burst_response(dut):
    """Test response to burst stimulation"""
    
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    dut.ena.value = 1
    await reset_dut(dut)
    
    # Generate burst pattern
    burst_current_n1 = 80
    burst_current_n2 = 80
    burst_duration = 20
    inter_burst_interval = 40
    num_bursts = 5
    
    for burst in range(num_bursts):
        dut._log.info(f"\nBurst {burst + 1}")
        
        # Apply burst to both neurons
        await apply_current(dut, burst_current_n1, burst_current_n2, burst_duration)
        spikes_n1, spikes_n2 = await monitor_spikes(dut, burst_duration)
        dut._log.info(f"Burst response - N1: {spikes_n1}, N2: {spikes_n2}")
        
        # Inter-burst interval
        await apply_current(dut, 0, 0, inter_burst_interval)
    
    dut._log.info("Burst test completed successfully")
