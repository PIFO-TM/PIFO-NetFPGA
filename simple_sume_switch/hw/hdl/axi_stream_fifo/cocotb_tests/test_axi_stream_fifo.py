
import logging
import cocotb
import random

from cocotb.clock import Clock
from cocotb.triggers import Timer, ReadOnly, RisingEdge, ClockCycles, FallingEdge
from cocotb.binary import BinaryValue
from cocotb.axi4stream import AXI4StreamMaster, AXI4StreamSlave, AXI4StreamStats, CycleCounter
from cocotb.result import TestFailure

from metadata import Metadata
from scapy.all import Ether, IP, TCP, hexdump, rdpcap

# Add include directory for python sims
import sys, os

NUM_PKTS = 10
PKT_LEN = 1500 # bytes

INGRESS_LINK_RATE = 10 # Gbps

START_DELAY = 100
PERIOD = 5000
IDLE_TIMEOUT = PERIOD*1000

BP_COUNT = 0

@cocotb.coroutine
def reset_dut(dut):
    # Reset the DUT
    dut._log.debug("Resetting DUT")
    dut.axis_resetn <= 0
    yield ClockCycles(dut.axis_aclk, 10)
    dut.axis_resetn <= 1
    dut._log.debug("Out of reset")

def make_meta(pkts_in):
    meta_in = []
    for p in pkts_in:
        meta = Metadata(pkt_len=len(p))
        tuser = BinaryValue(bits=len(meta)*8, bigEndian=False)
        tuser.set_buff(str(meta))
        meta_in.append(tuser)   
    return meta_in

def make_pkts_meta_in():
    pkts_in = []
    for i in range(NUM_PKTS):
        pkt = Ether() / ('\x00'*(PKT_LEN-14))
        pkts_in.append(pkt)

    meta_in = make_meta(pkts_in)

    print 'len(pkts_in) = {}'.format(len(pkts_in))
    return pkts_in, meta_in

def check_pkts(pkts_in, pkts_out):
    max_len = max([len(p) for p in pkts_in])

    max_plen = 0
    for p in pkts_out:
        if len(p) < 64:
            print "ERROR: received pkt that is too small"
        elif len(p) > max_len:
            print "ERROR: received pkt that is too large"
        max_plen = len(p) if len(p) > max_plen else max_plen
    print 'INFO: max packet length = {}'.format(max_plen)

@cocotb.test()
def test_axi_stream_fifo(dut):
    """Test to make sure that axi_stream_fifo is working properly.
    """
    # start HW sim clock
    cocotb.fork(Clock(dut.axis_aclk, PERIOD).start())

    yield reset_dut(dut)
    yield ClockCycles(dut.axis_aclk, START_DELAY)

    # read the pkts and rank values
    pkts_in, meta_in = make_pkts_meta_in()

    # Attach an AXI4Stream Master to the input pkt interface
    pkt_master = AXI4StreamMaster(dut, 's_axis', dut.axis_aclk)

    # Attach an AXI4StreamSlave to the output pkt interface
    pkt_slave = AXI4StreamSlave(dut, 'm_axis', dut.axis_aclk, tready_delay=BP_COUNT, idle_timeout=IDLE_TIMEOUT)

    # start reading for pkts
    pkt_slave_thread = cocotb.fork(pkt_slave.read_n_pkts(len(pkts_in), log_raw=True))

    # Send pkts and metadata in the HW sim
    rate = 1.0*INGRESS_LINK_RATE*5/8.0 # bytes/cycle
    pkt_master_thread = cocotb.fork(pkt_master.write_pkts(pkts_in, meta_in, rate=rate))

    yield pkt_master_thread.join()

    # Wait for the pkt_slave to finish (or timeout)
    yield pkt_slave_thread.join()

    pkts_out = pkt_slave.pkts
    meta_out = pkt_slave.metadata
#    ranks_out = [Metadata(m.get_buff()).rank for m in meta_out]

    yield ClockCycles(dut.axis_aclk, 20)

    print 'len(pkts_out) = {}'.format(len(pkts_out))
    check_pkts(pkts_in, pkts_out)

