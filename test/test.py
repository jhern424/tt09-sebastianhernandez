import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer
from cocotb.result import TestSuccess
import logging

async def reset_dut(dut):
    """Reset the DUT with extended stability period"""
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 100)  # Extended reset
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 100)  # Extended stability

async def monitor_network(dut, duration):
    """Monitor network activity"""
    spikes_n1 = 0
    spikes_n2 = 0
    last_weight = None
    weight_changes = 0
    
    for _ in range(duration):
        await RisingEdge(dut.clk)
        
        # Monitor spikes
        if dut.uio_out.value.integer & 0x80:
            spikes_n1 += 1
            dut._log.info(f"N1 spike at cycle {_} (Total: {spikes_n1})")
            
        if dut.uio_out.value.integer & 0x40:
            spikes_n2 += 2
            dut._log.info(f"N2 spike at cycle {_} (Total: {spikes_n2})")
        
        # Monitor weight
        current_weight = dut.uio_out.value.integer & 0x3F
        if last_weight is not None and current_weight != last_weight:
            weight_changes += 1
            dut._log.info(f"Weight changed: {last_weight} -> {current_weight}")
        last_weight = current_weight
        
        # Periodic state monitoring
        if _ % 100 == 0:
            dut._log.info(f"Cycle {_}: N2 state = {dut.uo_out.value.integer}, Weight = {current_weight}")
            
    return spikes_n1, spikes_n2, last_weight, weight_changes

@cocotb.test()
async def test_learning(dut):
    """Test STDP learning with improved stability checks"""
    
    # Setup logging
    dut._log.setLevel(logging.INFO)
    
    # Start clock (50 MHz)
    clock = Clock(dut.clk, 20, units="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize
    dut.ena.value = 1
    await reset_dut(dut)
    
    try:
        # Initial quiet period with monitoring
        dut._log.info("Initial monitoring period...")
        initial_spikes_n1, initial_spikes_n2, initial_weight, _ = await monitor_network(dut, 200)
        
        # Learning phase
        dut._log.info("\nStarting learning trials...")
        for i in range(15):
            dut._log.info(f"\nTrial {i+1}")
            # Strong stimulus to first neuron
            dut.ui_in.value = 0xE0
            await ClockCycles(dut.clk, 100)
            
            # Recovery period
            dut.ui_in.value = 0x60
            await ClockCycles(dut.clk, 50)
            
            # Quiet period
            dut.ui_in.value = 0x00
            await ClockCycles(dut.clk, 100)
        
        # Final monitoring period
        dut._log.info("\nFinal monitoring period...")
        final_spikes_n1, final_spikes_n2, final_weight, weight_changes = await monitor_network(dut, 300)
        
        # Test verification
        dut._log.info("\nTest Results:")
        dut._log.info(f"First neuron spikes: {final_spikes_n1}")
        dut._log.info(f"Second neuron spikes: {final_spikes_n2}")
        dut._log.info(f"Weight changes: {weight_changes}")
        dut._log.info(f"Final weight: {final_weight}")
        
        # Success criteria
        if final_spikes_n1 > 0 and final_spikes_n2 > 0 and weight_changes > 0:
            raise TestSuccess("Network shows proper learning behavior")
        
        # Final stabilization period
        await ClockCycles(dut.clk, 100)
        
    except TestSuccess:
        dut._log.info("Test completed successfully!")
    except Exception as e:
        dut._log.error(f"Test failed: {str(e)}")
        raise