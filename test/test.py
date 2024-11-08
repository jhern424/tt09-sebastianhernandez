import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer
from cocotb.result import TestSuccess, TestFailure
import logging

async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await Timer(200, units="ns")
    dut.rst_n.value = 1
    await Timer(200, units="ns")

@cocotb.test()
async def test_learning(dut):
    # Setup logging
    dut._log.setLevel(logging.INFO)
    
    # Start clock (50 MHz)
    clock = Clock(dut.clk, 20, units="ns")
    clk_thread = cocotb.start_soon(clock.start())
    
    try:
        # Initialize
        dut.ena.value = 1
        await reset_dut(dut)
        
        # Monitor spikes
        spike_count_n1 = 0
        spike_count_n2 = 0
        last_weight = None
        
        # Wait for testbench to complete (slightly shorter than tb.v finish time)
        for _ in range(700):  # Monitor for 14000ns
            await Timer(20, units="ns")
            
            # Check for spikes
            if dut.uio_out.value.integer & 0x80:
                spike_count_n1 += 1
            if dut.uio_out.value.integer & 0x40:
                spike_count_n2 += 1
                
            # Monitor weight changes
            current_weight = dut.uio_out.value.integer & 0x3F
            if last_weight is not None and current_weight != last_weight:
                dut._log.info(f"Weight changed: {last_weight} -> {current_weight}")
            last_weight = current_weight
        
        # Log results
        dut._log.info(f"Test completed. N1 spikes: {spike_count_n1}, N2 spikes: {spike_count_n2}")
        
        if spike_count_n1 > 0 and spike_count_n2 > 0:
            raise TestSuccess("Both neurons spiked successfully")
        if spike_count_n1 == 0:
            raise TestFailure("First neuron did not spike")
        if spike_count_n2 == 0:
            raise TestFailure("Second neuron did not spike")
            
    finally:
        clk_thread.kill()