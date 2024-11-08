import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles

@cocotb.test()
async def test_two_lif_stdp(dut):
    dut._log.info("Starting test...")
    
    # Create clock (50MHz)
    clock = Clock(dut.clk, 20, units="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize
    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    
    # Reset
    await Timer(200, units="ns")
    dut.rst_n.value = 1
    await Timer(400, units="ns")
    
    spike_count_n1 = 0
    spike_count_n2 = 0
    last_weight = 0
    
    # Initial quiet period
    dut.ui_in.value = 0x00
    await Timer(1000, units="ns")
    
    # STDP training cycles
    for i in range(20):
        dut._log.info(f"Training cycle {i}")
        
        # Strong stimulation
        dut.ui_in.value = 0xFF  # Maximum input current
        await Timer(200, units="ns")
        
        # Check for spikes after strong input
        if dut.uio_out.value & 0x80:
            spike_count_n1 += 1
            dut._log.info(f"N1 spike detected at strong input")
        if dut.uio_out.value & 0x40:
            spike_count_n2 += 1
            dut._log.info(f"N2 spike detected at strong input")
        
        # Medium stimulation
        dut.ui_in.value = 0x80
        await Timer(200, units="ns")
        
        # Check for spikes after medium input
        if dut.uio_out.value & 0x80:
            spike_count_n1 += 1
            dut._log.info(f"N1 spike detected at medium input")
        if dut.uio_out.value & 0x40:
            spike_count_n2 += 1
            dut._log.info(f"N2 spike detected at medium input")
        
        # Rest period
        dut.ui_in.value = 0x00
        await Timer(200, units="ns")
        
        # Monitor weight changes
        current_weight = dut.uio_out.value & 0x3F
        if current_weight != last_weight:
            dut._log.info(f"Weight changed from {last_weight} to {current_weight}")
            last_weight = current_weight
            
        # Log neuron states
        dut._log.info(f"N2 state = {dut.uo_out.value}, Weight = {dut.uio_out.value & 0x3F}")
    
    # Final test with sustained input
    dut.ui_in.value = 0xFF
    await Timer(2000, units="ns")
    
    # Check final spike counts
    dut._log.info(f"Test completed. N1 spikes: {spike_count_n1}, N2 spikes: {spike_count_n2}")
    
    assert spike_count_n1 > 0, "First neuron did not spike"
    assert spike_count_n2 > 0, "Second neuron did not spike"