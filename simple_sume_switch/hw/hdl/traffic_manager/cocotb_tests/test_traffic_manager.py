
import logging
import cocotb
import simpy
import random

from cocotb.clock import Clock
from cocotb.triggers import Timer, ReadOnly, RisingEdge, ClockCycles
from cocotb.binary import BinaryValue
from cocotb.axi4stream import AXI4StreamMaster, AXI4StreamSlave, AXI4StreamStats
from cocotb.result import TestFailure

from metadata import Metadata
from scapy.all import Ether, IP, UDP, hexdump

import sys, os
import json

PERIOD = 5000

@cocotb.test()
def test_traffic_manager(dut):
    """Testing traffic_manager 
    """

    # start HW sim clock
    cocotb.fork(Clock(dut.axis_aclk, PERIOD).start())

    # Reset the DUT
    dut._log.debug("Resetting DUT")
    dut.axis_resetn <= 0
    yield ClockCycles(dut.axis_aclk, 10)
    dut.axis_resetn <= 1
    dut._log.debug("Out of reset")

    # Attach an AXI4Stream Master to the input pkt interface
    pkt_master = AXI4StreamMaster(dut, 's_axis', dut.axis_aclk)

    # Attach and AXI4StreamSlave to the output pkt interfaces
    nf0_slave = AXI4StreamSlave(dut, 'm_axis_0', dut.axis_aclk)
    nf1_slave = AXI4StreamSlave(dut, 'm_axis_1', dut.axis_aclk)
    nf2_slave = AXI4StreamSlave(dut, 'm_axis_2', dut.axis_aclk)
    nf3_slave = AXI4StreamSlave(dut, 'm_axis_3', dut.axis_aclk)

    # build the list of pkts and metadata to insert
    pkts_meta_in = [] 
    for i in range(4):
#        pkt_len = random.randint(50, 1000)
        # build a packet
        pkt = Ether(dst='aa:aa:aa:aa:aa:aa', src='bb:bb:bb:bb:bb:bb')
        pkt = pkt / ('\x11'*18 + '\x22'*32)
#        pkt = pkt / ('\x11'*18 + '\x22'*32 + '\x33'*32 + '\x44'*32 + '\x55'*16)
#        pkt = pkt / ('\x11'*(pkt_len - 14))

        rank = random.randint(0, 100)
    
        # build the metadata 
        meta = Metadata(pkt_len=len(pkt), src_port=0b00000001, dst_port=0b00000100, rank=rank)
        tuser = BinaryValue(bits=len(meta)*8, bigEndian=False)
        tuser.set_buff(str(meta))

        pkts_meta_in.append((rank, pkt, tuser))

    ranks_in = [tup[0] for tup in pkts_meta_in] 
    pkts_in = [tup[1] for tup in pkts_meta_in]
    meta_in = [tup[2] for tup in pkts_meta_in]

    # Send pkts and metadata in the HW sim
    yield pkt_master.write_pkts(pkts_in, meta_in)

    # delay between writing pkts and reading them out
    yield ClockCycles(dut.axis_aclk, 10)

    print "len(pkts_in) = {}".format(len(pkts_in))
    # Read pkts out
    yield nf1_slave.read_n_pkts(len(pkts_in))

    sorted_pkts_meta = sorted(pkts_meta_in, key=lambda x: x[0])

    expected_ranks = [tup[0] for tup in sorted_pkts_meta]
    expected_pkts = [tup[1] for tup in sorted_pkts_meta]
    expected_meta = [tup[2] for tup in sorted_pkts_meta]

    pkts_out = nf1_slave.pkts
    meta_out = nf1_slave.metadata

    actual_ranks = [Metadata(m.get_buff()).rank for m in meta_out]

    print 'input ranks           = {}'.format(ranks_in)
    print 'expected output ranks = {}'.format(expected_ranks)
    print 'actual output ranks   = {}'.format(actual_ranks)

    error = False
    for (exp_pkt, pkt, exp_meta, meta, i) in zip(expected_pkts, pkts_out, expected_meta, meta_out, range(len(expected_pkts))):
        if str(exp_pkt) != str(pkt):
            print 'ERROR: exp_pkt != pkt_out for pkt {}'.format(i)
            error = True
        if exp_meta.get_buff() != meta.get_buff():
            print 'ERROR: exp_meta != meta_out for pkt {}'.format(i)
            exp_meta = Metadata(exp_meta.get_buff())
            meta = Metadata(meta.get_buff())
            print 'exp_meta = {}'.format(exp_meta.summary())
            print 'meta = {}'.format(meta.summary())
            error = True

    yield ClockCycles(dut.axis_aclk, 20)

    if error:
        print 'ERROR: Test Failed'
        raise(TestFailure)



