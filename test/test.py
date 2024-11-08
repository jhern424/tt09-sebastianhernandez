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
            dut._log.info(f"Cycle {cycle}: V_mem1 = {v_mem1}, V_mem2 = {v