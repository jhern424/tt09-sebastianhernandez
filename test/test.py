import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
import logging

async def reset_dut(dut):
    """Reset the DUT with stability period"""
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 40)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 40)

async def monitor_network(dut, duration):
    """Monitor spikes, states, and weights"""
    spikes_n1 = 0
    spikes_n2 = 0
    last_weight = None
    
    for _ in range(duration):
        await RisingEdge(dut.clk)
        
        # Check for spikes
        if dut.uio_out.value.integer & 0x80:
            spikes_n1 += 1
            dut._log.info(f"N1 spike detected (Total: {spikes_n1})")
            
        if dut.uio_out.value.integer & 0x40:
            spikes_n2 += 1
            dut._log.info(f"N2 spike detected (Total: {spikes_n2})")
        
        # Monitor weight changes
        current_weight = dut.uio_out.value.integer & 0x3F
        if last_weight != current_weight:
            dut._log.info(f"Weight changed: {last_weight} -> {current_weight}")
            last_weight = current_weight
            
    return spikes_n1, spikes_n2, last_weight

@cocotb.test()
async def test_learning(dut):
    """Test STDP learning with the two-neuron network"""
    
    # Setup logging
    dut._log.setLevel(logging.INFO)
    
    # Start clock (50 MHz)
    clock = Clock(dut.clk, 20, units="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize
    dut.ena.value = 1
    await reset_dut(dut)
    
    # Initial monitoring
    dut._log.info("Starting test...")
    initial_spikes_n1, initial_spikes_n2, initial_weight = await monitor_network(dut, 100)
    
    # Test pre-post spike pairs
    for i in range(10):
        dut._log.info(f"\nTrial {i+1}")
        dut.ui_in.value = 0xE0  # Strong stimulus
        await ClockCycles(dut.clk, 100)
        dut.ui_in.value = 0x00
        await ClockCycles(dut.clk, 50)
    
    # Final monitoring
    final_spikes_n1, final_spikes_n2, final_weight = await monitor_network(dut, 100)
    
    # Verify results
    assert final_spikes_n1 > initial_spikes_n1, "First neuron should spike"
    assert final_weight != initial_weight, "Weight should change during learning"
    dut._log.info(f"Test complete. Weight: {initial_weight} -> {final_weight}")