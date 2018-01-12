
import logging
import cocotb

from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, ClockCycles

PERIOD = 5000

@cocotb.test()
def test_pifo_pkt_storage(dut):
    """Test plus_one module in HW simulation
    """
    cocotb.fork(Clock(dut.axis_aclk, PERIOD).start())

    # Wait to start
    dut._log.debug("Resetting DUT")
    dut.axis_resetn <= 0
    dut.m_axis_pkt_tready <= 0
    yield ClockCycles(dut.axis_aclk, 10)
    dut.axis_resetn <= 1
    dut.m_axis_pkt_tready <= 1
    dut._log.debug("Out of reset")

    dut.s_axis_pkt_tvalid <= 0
    dut.s_axis_pkt_tdata <= 0
    dut.s_axis_pkt_tkeep <= 0
    dut.s_axis_pkt_tuser <= 0
    dut.s_axis_pkt_tlast <= 0

    dut.s_axis_ptr_tvalid <= 0
    dut.s_axis_ptr_tdata <= 0
    dut.s_axis_ptr_tkeep <= 0
    dut.s_axis_ptr_tlast <= 0
 
    yield ClockCycles(dut.axis_aclk, 100)

