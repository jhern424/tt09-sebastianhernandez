import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles
from cocotb.binary import BinaryValue

async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)

@cocotb.test()
async def test_hh_neuron(dut):
    """Test the simplified neuron with proper current scaling"""
    
    # Start clock
    clock = Clock(dut.clk, 20, units="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize values
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    
    # Reset the design
    await reset_dut(dut)
    
    # Test sequence with appropriate current values for 8-bit input
    test_currents = [0, 32, 64, 96, 128]
    spike_counts = []
    v_mem_readings = []
    
    for current in test_currents:
        dut._log.info(f"Testing with current: {current}")
        
        # Apply current
        dut.ui_in.value = current
        
        # Monitor for 50 cycles
        spikes = 0
        v_mem_samples = []
        last_spike = False
        
        for _ in range(50):
            await RisingEdge(dut.clk)
            
            # Check for spikes
            if dut.uio_out.value[7] and not last_spike:
                spikes += 1
            last_spike = bool(dut.uio_out.value[7])
            
            # Record membrane voltage every 10 cycles
            if _ % 10 == 0:
                v_mem = int(dut.uo_out.value)
                v_mem_samples.append(v_mem)
                dut._log.info(f"Membrane voltage: {v_mem}")
        
        spike_counts.append(spikes)
        v_mem_readings.append(sum(v_mem_samples) / len(v_mem_samples))
        
        # Reset and wait
        dut.ui_in.value = 0
        await ClockCycles(dut.clk, 25)
    
    # Verify basic functionality
    assert spike_counts[0] == 0, "Should not spike at zero current"
    assert max(spike_counts) > 0, "Should spike at high current"
    assert v_mem_readings[-1] > v_mem_readings[0], "Membrane voltage should increase with current"
    
    dut._log.info("Test completed successfully!")

@cocotb.test()
async def test_stdp(dut):
    """Test STDP learning with proper timing"""
    
    clock = Clock(dut.clk, 20, units="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize and reset
    dut.ena.value = 1
    await reset_dut(dut)
    
    # Test STDP by generating controlled spike patterns
    for trial in range(3):
        dut._log.info(f"STDP trial {trial + 1}")
        
        # Generate pre-synaptic spike
        dut.ui_in.value = 96  # Strong enough to cause spike
        await ClockCycles(dut.clk, 5)
        dut.ui_in.value = 0
        
        # Record spike timing
        pre_spike_time = None
        post_spike_time = None
        
        # Monitor for spikes
        for _ in range(30):
            await RisingEdge(dut.clk)
            
            if dut.uio_out.value[7] and pre_spike_time is None:
                pre_spike_time = _
                dut._log.info(f"Pre-synaptic spike at cycle {_}")
            
            if dut.uio_out.value[6] and post_spike_time is None:
                post_spike_time = _
                dut._log.info(f"Post-synaptic spike at cycle {_}")
        
        # Allow system to recover
        await ClockCycles(dut.clk, 20)
        
        if pre_spike_time is not None and post_spike_time is not None:
            dut._log.info(f"Spike interval: {post_spike_time - pre_spike_time} cycles")
    
    dut._log.info("STDP test completed!")