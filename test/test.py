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
    await Timer(100, units="ns")

@cocotb.test()
async def test_neurons(dut):
    # Setup logging
    dut._log.setLevel(logging.INFO)
    dut._log.info("Starting test...")
    
    # Start clock (50 MHz)
    clock = Clock(dut.clk, 20, units="ns")
    clk_thread = cocotb.start_soon(clock.start())
    
    # Variables for monitoring
    spike_count_n1 = 0
    spike_count_n2 = 0
    last_weight = None
    
    try:
        # Initialize
        dut.ena.value = 1
        await reset_dut(dut)
        
        # Test sequence
        for i in range(10):
            # Strong stimulation
            dut._log.info(f"Cycle {i}: Applying strong input")
            dut.ui_in.value = 0xFF  # Maximum input
            await Timer(200, units="ns")
            
            # Reduced input
            dut.ui_in.value = 0x80
            await Timer(200, units="ns")
            
            # Rest period
            dut.ui_in.value = 0x00
            await Timer(200, units="ns")
            
            # Check for spikes
            if dut.uio_out.value.integer & 0x80:
                spike_count_n1 += 1
                dut._log.info(f"N1 spike detected in cycle {i}")
            
            if dut.uio_out.value.integer & 0x40:
                spike_count_n2 += 1
                dut._log.info(f"N2 spike detected in cycle {i}")
            
            # Monitor weight
            current_weight = dut.uio_out.value.integer & 0x3F
            if last_weight is not None and current_weight != last_weight:
                dut._log.info(f"Weight changed: {last_weight} -> {current_weight}")
            last_weight = current_weight
        
        # Final observation period
        await Timer(1000, units="ns")
        
        # Log results
        dut._log.info(f"Test completed. N1 spikes: {spike_count_n1}, N2 spikes: {spike_count_n2}")
        
        if spike_count_n1 == 0:
            raise TestFailure("First neuron did not spike")
        if spike_count_n2 == 0:
            raise TestFailure("Second neuron did not spike")
        
        raise TestSuccess(f"Both neurons spiked (N1: {spike_count_n1}, N2: {spike_count_n2})")
        
    finally:
        clk_thread.kill()