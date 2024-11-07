import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # Set up the clock
    clock = Clock(dut.clk, 1, units="ns")
    cocotb.start_soon(clock.start())

    # Reset the DUT
    dut.rst_n.value = 0  # Assert reset (active low)
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1  # Deassert reset

    # Test sequence
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 10)

    dut.ui_in.value = 20
    await ClockCycles(dut.clk, 100)

    dut._log.info("Finished test! Wawaweewa!!")
