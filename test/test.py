import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles

@cocotb.test()
async def test_two_lif_stdp(dut):
    dut._log.info("Starting test...")
    
    # Create clock
    clock = Clock(dut.clk, 20, units="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    
    # Monitor variables
    spike_count_n1 = 0
    spike_count_n2 = 0
    last_weight = None
    
    # Test sequence
    for i in range(20):
        dut._log.info(f"Test cycle {i}")
        
        # Strong stimulation
        dut.ui_in.value = 0xE0
        await ClockCycles(dut.clk, 5)  # 100ns
        
        # Medium stimulation
        dut.ui_in.value = 0x80
        await ClockCycles(dut.clk, 5)  # 100ns
        
        # Rest period
        dut.ui_in.value = 0
        await ClockCycles(dut.clk, 10)  # 200ns
        
        # Check for spikes
        if dut.uio_out.value & 0x80:
            spike_count_n1 += 1
            dut._log.info(f"N1 spike detected in cycle {i}")
        
        if dut.uio_out.value & 0x40:
            spike_count_n2 += 1
            dut._log.info(f"N2 spike detected in cycle {i}")
        
        # Monitor weight
        current_weight = dut.uio_out.value & 0x3F
        if last_weight is not None and current_weight != last_weight:
            dut._log.info(f"Weight changed: {last_weight} -> {current_weight}")
        last_weight = current_weight
    
    # Final observation period
    dut.ui_in.value = 0xE0
    await ClockCycles(dut.clk, 100)  # 2000ns
    
    dut._log.info(f"Test completed. N1 spikes: {spike_count_n1}, N2 spikes: {spike_count_n2}")
    
    assert spike_count_n1 > 0, "First neuron did not spike"
    assert spike_count_n2 > 0, "Second neuron did not spike"