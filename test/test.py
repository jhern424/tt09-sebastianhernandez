import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
import logging

async def reset_dut(dut):
    """Reset the DUT and wait for stability"""
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 40)  # Extended reset period
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 40)  # Stability period

async def apply_input(dut, current, duration):
    """Apply input current to the first neuron"""
    dut.ui_in.value = current
    await ClockCycles(dut.clk, duration)

async def monitor_network(dut, duration):
    """Monitor spikes, states, and synaptic weight"""
    spikes_n1 = 0
    spikes_n2 = 0
    last_spike_n1 = False
    last_spike_n2 = False
    last_weight = 0
    
    for cycle in range(duration):
        await RisingEdge(dut.clk)
        
        # Monitor spikes (uio_out[7] for N1, uio_out[6] for N2)
        current_spike_n1 = bool(dut.uio_out.value.integer & 0x80)
        current_spike_n2 = bool(dut.uio_out.value.integer & 0x40)
        
        # Detect new spikes
        if current_spike_n1 and not last_spike_n1:
            spikes_n1 += 1
            dut._log.info(f"Cycle {cycle}: Neuron 1 spike detected (Total: {spikes_n1})")
            
        if current_spike_n2 and not last_spike_n2:
            spikes_n2 += 1
            dut._log.info(f"Cycle {cycle}: Neuron 2 spike detected (Total: {spikes_n2})")
        
        # Update spike history
        last_spike_n1 = current_spike_n1
        last_spike_n2 = current_spike_n2
        
        # Monitor states and weight every 10 cycles
        if cycle % 10 == 0:
            # Get second neuron state (uo_out)
            n2_state = dut.uo_out.value.integer
            
            # Get synaptic weight (uio_out[5:0])
            current_weight = dut.uio_out.value.integer & 0x3F
            
            # Log state and weight
            dut._log.info(f"Cycle {cycle}: N2 state = {n2_state}, Weight = {current_weight}")
            
            # Detect and log weight changes
            if current_weight != last_weight:
                dut._log.info(f"Cycle {cycle}: Weight changed from {last_weight} to {current_weight}")
                last_weight = current_weight
                
    return spikes_n1, spikes_n2, last_weight

@cocotb.test()
async def test_stdp_learning(dut):
    """Test STDP learning with two LIF neurons"""
    
    # Setup logging
    dut._log.setLevel(logging.INFO)
    
    # Start clock (50 MHz)
    clock = Clock(dut.clk, 20, units="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize
    dut.ena.value = 1
    await reset_dut(dut)
    
    # Initial quiet period
    dut._log.info("Starting with quiet period...")
    await apply_input(dut, 0, 100)
    
    # STDP learning phase
    initial_spikes = [0, 0]
    final_spikes = [0, 0]
    initial_weight = None
    final_weight = None
    
    dut._log.info("\nStarting STDP learning trials...")
    
    # Record initial behavior
    spikes_n1, spikes_n2, weight = await monitor_network(dut, 100)
    initial_spikes = [spikes_n1, spikes_n2]
    initial_weight = weight
    
    # Perform STDP training trials
    for trial in range(20):
        dut._log.info(f"\nSTDP Trial {trial + 1}")
        
        # Strong stimulus to first neuron
        await apply_input(dut, 0xE0, 100)
        await ClockCycles(dut.clk, 50)
        
        # Quiet period
        await apply_input(dut, 0x80, 100)
        
        # Monitor response
        spikes_n1, spikes_n2, weight = await monitor_network(dut, 200)
        
        dut._log.info(f"Trial {trial + 1} results:")
        dut._log.info(f"Spikes - N1: {spikes_n1}, N2: {spikes_n2}")
        dut._log.info(f"Current weight: {weight}")
    
    # Test post-learning behavior
    dut._log.info("\nTesting post-learning response...")
    await apply_input(dut, 0xA0, 500)  # Moderate stimulus
    final_spikes[0], final_spikes[1], final_weight = await monitor_network(dut, 500)
    
    # Log final results
    dut._log.info("\nTest Results:")
    dut._log.info(f"Initial - Spikes N1: {initial_spikes[0]}, N2: {initial_spikes[1]}, Weight: {initial_weight}")
    dut._log.info(f"Final - Spikes N1: {final_spikes[0]}, N2: {final_spikes[1]}, Weight: {final_weight}")
    
    # Verify learning occurred
    assert final_spikes[0] > 0, "First neuron should spike during test"
    assert final_spikes[1] > 0, "Second neuron should spike after learning"
    assert final_weight != initial_weight, "Synaptic weight should change during learning"

@cocotb.test()
async def test_weight_limits(dut):
    """Test that synaptic weights remain within bounds"""
    
    # Setup
    dut._log.setLevel(logging.INFO)
    clock = Clock(dut.clk, 20, units="ns")
    cocotb.start_soon(clock.start())
    dut.ena.value = 1
    await reset_dut(dut)
    
    # Test maximum weight bound
    dut._log.info("\nTesting maximum weight bound...")
    for _ in range(50):  # Many pre-then-post spike pairs
        await apply_input(dut, 0xE0, 50)
        await ClockCycles(dut.clk, 20)
    
    # Verify weight doesn't exceed maximum
    _, _, weight = await monitor_network(dut, 100)
    assert weight < 64, f"Weight {weight} exceeded 6-bit maximum"
    
    # Reset and test minimum weight bound
    await reset_dut(dut)
    dut._log.info("\nTesting minimum weight bound...")
    for _ in range(50):  # Many post-then-pre spike pairs
        await apply_input(dut, 0xE0, 50)
        await ClockCycles(dut.clk, 100)
    
    # Verify weight doesn't go below zero
    _, _, weight = await monitor_network(dut, 100)
    assert weight >= 0, f"Weight {weight} went below zero"