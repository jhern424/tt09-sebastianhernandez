import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer, FallingEdge
from cocotb.result import TestSuccess, TestFailure
import logging

async def reset_dut(dut):
    """Reset the DUT with extended stability period"""
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 100)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 100)

async def monitor_network(dut, duration):
    """Monitor network activity with synchronization"""
    spikes_n1 = 0
    spikes_n2 = 0
    last_weight = None
    weight_changes = 0
    
    for _ in range(duration):
        await RisingEdge(dut.clk)
        
        # Monitor spikes
        current_spikes_n1 = bool(dut.uio_out.value.integer & 0x80)
        current_spikes_n2 = bool(dut.uio_out.value.integer & 0x40)
        
        if current_spikes_n1:
            spikes_n1 += 1
            if _ % 100 == 0:  # Reduce logging frequency
                dut._log.info(f"N1 spike at cycle {_} (Total: {spikes_n1})")
            
        if current_spikes_n2:
            spikes_n2 += 1
            if _ % 100 == 0:  # Reduce logging frequency
                dut._log.info(f"N2 spike at cycle {_} (Total: {spikes_n2})")
        
        # Monitor weight less frequently
        if _ % 100 == 0:
            current_weight = dut.uio_out.value.integer & 0x3F
            if last_weight is not None and current_weight != last_weight:
                weight_changes += 1
                dut._log.info(f"Weight changed: {last_weight} -> {current_weight}")
            last_weight = current_weight
            
    return spikes_n1, spikes_n2, last_weight, weight_changes

@cocotb.test()
async def test_learning(dut):
    """Test STDP learning with improved synchronization"""
    
    # Setup logging with reduced verbosity
    dut._log.setLevel(logging.INFO)
    
    # Start clock (50 MHz)
    clock = Clock(dut.clk, 20, units="ns")
    clk_thread = cocotb.start_soon(clock.start())
    
    # Initialize
    dut.ena.value = 1
    await reset_dut(dut)
    
    try:
        # Initial monitoring
        dut._log.info("Starting initial monitoring...")
        initial_n1, initial_n2, initial_weight, _ = await monitor_network(dut, 200)
        
        # Learning phase
        dut._log.info("\nStarting learning phase...")
        for i in range(10):  # Reduced number of trials
            # Strong stimulus
            dut.ui_in.value = 0xE0
            await ClockCycles(dut.clk, 100)
            
            # Quiet period
            dut.ui_in.value = 0
            await ClockCycles(dut.clk, 100)
        
        # Final evaluation
        dut._log.info("\nFinal evaluation phase...")
        final_n1, final_n2, final_weight, weight_changes = await monitor_network(dut, 200)
        
        # Verify results
        success = True
        if final_n1 == 0:
            success = False
            dut._log.error("First neuron did not spike")
        if final_n2 == 0:
            success = False
            dut._log.error("Second neuron did not spike")
            
        # Log final results
        dut._log.info(f"\nTest Results:")
        dut._log.info(f"N1 spikes: {final_n1}")
        dut._log.info(f"N2 spikes: {final_n2}")
        dut._log.info(f"Weight changes: {weight_changes}")
        dut._log.info(f"Final weight: {final_weight}")
        
        # Ensure orderly completion
        await ClockCycles(dut.clk, 10)
        
        if success:
            dut._log.info("Test completed successfully")
        else:
            raise TestFailure("Network did not exhibit expected behavior")
            
    except Exception as e:
        dut._log.error(f"Test failed: {str(e)}")
        raise
    finally:
        # Ensure clock stops
        clk_thread.kill()