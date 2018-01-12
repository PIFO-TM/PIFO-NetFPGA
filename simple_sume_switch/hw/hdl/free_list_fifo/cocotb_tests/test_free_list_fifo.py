
import logging
import cocotb

from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, FallingEdge, ClockCycles

PERIOD = 5000

@cocotb.test()
def test_free_list_fifo(dut):
    """Test free_list_fifo module 
    """
    cocotb.fork(Clock(dut.clk, PERIOD).start())

    # Pulse reset
    cocotb.log.info("Resetting DUT")
    dut.reset = 1
    yield ClockCycles(dut.clk, 10)
    dut.reset = 0
    cocotb.log.info("Out of reset")

    dut.din = 0
    dut.wr_en = 0
    dut.rd_en = 0
 
    # wait for reset to complete
    while dut.reset_done == 0:
        yield FallingEdge(dut.clk)

    # print values in FIFO
    cocotb.log.info("-----------------------")
    cocotb.log.info("depth = {}".format(dut.fifo.fifo.depth.value.integer))
    cocotb.log.info("-----------------------")

    dut.rd_en = 1

    # wait for empty to be asserted
    yield RisingEdge(dut.empty)

    dut.rd_en = 0

    yield ClockCycles(dut.clk, 10)

