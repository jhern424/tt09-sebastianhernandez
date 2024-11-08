import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
import logging

async def reset_dut(dut):
    """Reset the DUT with extended stability period"""
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 40)  # Extended reset period
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 40)  # Extended stability period

async def apply_current(dut, current_n1, current_n2, duration):
    """Apply current to both neurons with modified timing"""
    dut.ui_in.value = current_n1
    dut.uio_in.value = current_n2
    await ClockCycles(dut.clk, duration)

async def monitor_spikes(dut, duration):
    """Enhanced spike monitoring with detailed logging"""
    spikes_n1 = 0
    spikes_n2 = 0
    last_spike_n1 = False
    last_spike_n2 = False
    
    for cycle in range(duration):
        await RisingEdge(dut.clk)
        
        # Detect rising edges of spikes
        current_spike_n1 = bool(dut.uio_out.value.integer & 0x80)
        current_spike_n2 = bool(dut.uio_out.value.integer & 0x40)
        
        if current_spike_n1 and not last_spike_n1:
            spikes_n1 += 1
            dut._log.info(f"Neuron 1 spike at cycle {cycle}, Total: {spikes_n1}")
        
        if current_spike_n2 and not last_spike_n2:
            spikes_n2 += 1
            dut._log.info(f"Neuron 2 spike at cycle {cycle}, Total: {spikes_n2}")
        
        last_spike_n1 = current_spike_n1
        last_spike_n2 = current_spike_n2
        
        # More frequent membrane potential monitoring
        if cycle % 5 == 0:
            v_mem1 = dut.uo_out.value.integer
            v_mem2 = ((dut.uio_out.value.integer & 0x3F) << 2)
            dut._log.info(f"Cycle {cycle}: V_mem1 = {v_mem1}, V_mem2 = {v_mem2}")
    
    return spikes_n1, spikes_n2

@cocotb.test()
async def test_neuron_stdp_with_post_spikes(dut):
    """Test STDP learning with induced post-synaptic spikes"""
    # Setup logging
    dut._log.setLevel(logging.INFO)
    
    # Start clock (100 MHz)
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize
    dut.ena.value = 1
    await reset_dut(dut)
    
    # Ensure both neurons are at rest
    await apply_current(dut, 0, 0, 100)
    
    # STDP Training Phase
    for trial in range(15):  # Increased number of trials
        dut._log.info(f"\nSTDP Training Trial {trial + 1}")
        
        # Strong stimulation for more reliable spiking
        await apply_current(dut, 160, 0, 20)  # Increased current for N1
        await ClockCycles(dut.clk, 10)
        
        await apply_current(dut, 0, 160, 20)  # Increased current for N2
        await ClockCycles(dut.clk, 10)
        
        # Longer recovery period
        await apply_current(dut, 0, 0, 100)
    
    # Test synaptic response with stronger stimulus
    dut._log.info("\nTesting synaptic response after training")
    await apply_current(dut, 160, 0, 400)  # Longer test period with stronger stimulus
    spikes_n1, spikes_n2 = await monitor_spikes(dut, 400)
    
    # Log results
    dut._log.info(f"Final spike counts - N1: {spikes_n1}, N2: {spikes_n2}")
    
    # Assertions
    assert spikes_n1 > 0, "Neuron 1 should spike during test"
    assert spikes_n2 > 0, "Neuron 2 should spike in response to N1"