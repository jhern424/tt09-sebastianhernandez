import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
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
async def test_neuron_stdp_with_post_spikes(dut):
    """Test STDP learning with induced post-synaptic spikes"""
    
    # Setup logging
    dut._log.setLevel(logging.INFO)
    
    # Start clock
    clock = Clock(dut.clk, 10, units="ns")  # 100 MHz clock
    cocotb.start_soon(clock.start())
    
    # Initialize
    dut.ena.value = 1
    await reset_dut(dut)
    
    # Ensure both neurons are at rest
    await apply_current(dut, 0, 0, 100)
    
    # STDP Training Phase with Post-Synaptic Spikes
    for trial in range(10):
        dut._log.info(f"\nSTDP Training Trial {trial + 1}")
        
        # Stimulate Neuron 1 (pre-synaptic spike)
        await apply_current(dut, 128, 0, 10)
        await ClockCycles(dut.clk, 5)
        
        # Stimulate Neuron 2 (post-synaptic spike)
        await apply_current(dut, 0, 128, 10)
        await ClockCycles(dut.clk, 5)
        
        # Allow recovery
        await apply_current(dut, 0, 0, 50)
    
    # Test Synaptic Response
    dut._log.info("\nTesting synaptic response after training")
    await apply_current(dut, 128, 0, 200)
    spikes_n1, spikes_n2 = await monitor_spikes(dut, 200)
    dut._log.info(f"Spikes during synaptic test - N1: {spikes_n1}, N2: {spikes_n2}")
    
    # Assertions
    assert spikes_n1 > 0, "Neuron 1 should spike during synaptic test"
    if spikes_n2 > 0:
        dut._log.info("Neuron 2 spiked in response to Neuron 1 after training")
    else:
        dut._log.error("Neuron 2 did not spike in response to Neuron 1 after training")
        assert False, "Neuron 2 did not spike as expected"
