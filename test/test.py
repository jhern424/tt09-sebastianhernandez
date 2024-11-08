import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer
from cocotb.result import TestSuccess, TestFailure
import logging

async def reset_dut(dut):
    """Reset the DUT"""
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 40)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 40)

@cocotb.test()
async def test_learning(dut):
    """Test STDP learning"""
    
    # Setup logging
    dut._log.setLevel(logging.INFO)
    
    # Start clock (50 MHz)
    clock = Clock(dut.clk, 20, units="ns")
    clk_thread = cocotb.start_soon(clock.start())
    
    try:
        # Initialize
        dut.ena.value = 1
        await reset_dut(dut)
        
        # Let the testbench drive the inputs
        dut._log.info("Starting test sequence...")
        
        # Wait for test completion
        # Just monitor for spikes and don't interfere with testbench stimulus
        spike_count_n1 = 0
        spike_count_n2 = 0
        
        for _ in range(5000):  # Monitor for reasonable duration
            await RisingEdge(dut.clk)
            
            # Check for spikes
            if dut.uio_out.value.integer & 0x80:
                spike_count_n1 += 1
                if spike_count_n1 == 1:  # Log first spike
                    dut._log.info(f"First spike from N1 detected at cycle {_}")
                    
            if dut.uio_out.value.integer & 0x40:
                spike_count_n2 += 1
                if spike_count_n2 == 1:  # Log first spike
                    dut._log.info(f"First spike from N2 detected at cycle {_}")
                    
            # Periodically log status
            if _ % 1000 == 0:
                dut._log.info(f"Cycle {_}: N1 spikes={spike_count_n1}, N2 spikes={spike_count_n2}")
        
        # Final results
        dut._log.info(f"\nTest completed:")
        dut._log.info(f"Total N1 spikes: {spike_count_n1}")
        dut._log.info(f"Total N2 spikes: {spike_count_n2}")
        
        if spike_count_n1 > 0 and spike_count_n2 > 0:
            dut._log.info("Test PASSED - Both neurons spiked")
        else:
            if spike_count_n1 == 0:
                raise TestFailure("First neuron did not spike")
            if spike_count_n2 == 0:
                raise TestFailure("Second neuron did not spike")
                
    finally:
        clk_thread.kill()