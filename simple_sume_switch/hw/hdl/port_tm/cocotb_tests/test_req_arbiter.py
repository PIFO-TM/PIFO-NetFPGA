
import logging
import cocotb
import simpy
import random

from cocotb.clock import Clock
from cocotb.triggers import Timer, ReadOnly, RisingEdge, ClockCycles
from cocotb.binary import BinaryValue
from cocotb.result import TestFailure
from req_bus_driver import ReqMaster, ReqSlave


PERIOD = 5000
NUM_PORTS = 4

@cocotb.test()
def test_req_arbiter(dut):
    """Testing request arbiter 
    """

    # start HW sim clock
    cocotb.fork(Clock(dut.axis_aclk, PERIOD).start())

    # Reset the DUT
    dut._log.debug("Resetting DUT")
    dut.axis_resetn <= 0
    yield ClockCycles(dut.axis_aclk, 10)
    dut.axis_resetn <= 1
    dut._log.debug("Out of reset")

    requests = []
    for i in range(NUM_PORTS):
        requests.append(i)

    # Attach ReqMaster to each input interface
    nf0_req_master = ReqMaster(dut, 'nf0_sel', dut.axis_aclk)
    nf1_req_master = ReqMaster(dut, 'nf1_sel', dut.axis_aclk)
    nf2_req_master = ReqMaster(dut, 'nf2_sel', dut.axis_aclk)
    nf3_req_master = ReqMaster(dut, 'nf3_sel', dut.axis_aclk)

    # Attach ReqSlave to output interface
    req_slave = ReqSlave(dut, 'sel_out', dut.axis_aclk)
    # Start reading for output requests
    slave_thread = cocotb.fork(req_slave.read_reqs(NUM_PORTS*len(requests)))

    # start submitting requests
    delay = 20
    nf0_req_thread = cocotb.fork(nf0_req_master.write_reqs(requests, delay))
    nf1_req_thread = cocotb.fork(nf1_req_master.write_reqs(requests, delay))
    nf2_req_thread = cocotb.fork(nf2_req_master.write_reqs(requests, delay))
    nf3_req_thread = cocotb.fork(nf3_req_master.write_reqs(requests, delay))

    # wait for master threads to finish
    yield slave_thread.join()

    rcvd_reqs = req_slave.reqs
    print 'rcvd_reqs = {}'.format(rcvd_reqs)

    yield ClockCycles(dut.axis_aclk, 20)

    error = False
    if error:
        print 'ERROR: Test Failed'
        raise(TestFailure)



