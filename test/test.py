import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles

async def reset_dut(dut):
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)

@cocotb.test()
async def test_hh_neuron(dut):
    """Test the Hodgkin-Huxley neuron with STDP"""
    
    # Start clock
    clock = Clock(dut.clk, 20, units="ns")  # 50MHz clock
    cocotb.start_soon(clock.start())
    
    # Initialize values
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    
    # Reset the design
    await reset_dut(dut)
    
    # Test sequence
    test_currents = [0, 20, 40, 80, 120, 200]
    spike_counts = []
    
    for current in test_currents:
        dut._log.info(f"Testing with current: {current}")
        
        # Apply current
        dut.ui_in.value = current
        
        # Count spikes for 100 cycles
        spikes = 0
        last_spike = 0
        
        for _ in range(100):
            await RisingEdge(dut.clk)
            
            # Check for spikes on both neurons
            if dut.uio_out.value[0] and not last_spike:
                spikes += 1
            last_spike = dut.uio_out.value[0]
            
            # Log membrane voltage
            if _ % 10 == 0:
                dut._log.info(f"Membrane voltage: {dut.uo_out.value}")
        
        spike_counts.append(spikes)
        dut._log.info(f"Spike count for current {current}: {spikes}")
        
        # Reset current and wait for neuron to recover
        dut.ui_in.value = 0
        await ClockCycles(dut.clk, 50)
    
    # Verify basic functionality
    assert spike_counts[0] == 0, "Should not spike at zero current"
    assert spike_counts[-1] > spike_counts[0], "Should spike more at higher current"
    
    dut._log.info("Test completed successfully!")

@cocotb.test()
async def test_stdp(dut):
    """Test STDP learning mechanism"""
    
    clock = Clock(dut.clk, 20, units="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize and reset
    dut.ena.value = 1
    await reset_dut(dut)
    
    # Test STDP by generating spike pairs
    for _ in range(5):
        # Generate pre-synaptic spike
        dut.ui_in.value = 100
        await ClockCycles(dut.clk, 10)
        dut.ui_in.value = 0
        
        # Wait for post-synaptic response
        await ClockCycles(dut.clk, 20)
        
        # Log spike timing
        if dut.uio_out.value[0]:
            dut._log.info("Pre-synaptic spike detected")
        if dut.uio_out.value[1]:
            dut._log.info("Post-synaptic spike detected")
            
        # Allow system to settle
        await ClockCycles(dut.clk, 50)
    
    dut._log.info("STDP test completed!")