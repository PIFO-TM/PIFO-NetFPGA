
import logging
import cocotb
import random

from cocotb.clock import Clock
from cocotb.triggers import Timer, ReadOnly, RisingEdge, ClockCycles, FallingEdge
from cocotb.binary import BinaryValue
from cocotb.axi4stream import AXI4StreamMaster, AXI4StreamSlave, AXI4StreamStats, CycleCounter
from cocotb.result import TestFailure

from metadata import Metadata
from scapy.all import Ether, IP, UDP, hexdump

# Add include directory for python sims
import sys, os
import json

NUM_PKTS = 100

RESULTS_FILE = 'cocotb_results.json'
PERIOD = 5000
IDLE_TIMEOUT = PERIOD*1000

DEBUG = True

input_ranks = []

def make_pkts_and_meta(n):
    pkts_and_meta = [] 
    for i in range(n):
        # build a packet
        pkt = Ether(dst='aa:aa:aa:aa:aa:aa', src='bb:bb:bb:bb:bb:bb')
        pkt = pkt / ('\x11'*18 + '\x22'*32)

        rank = random.randint(0, 100)
        input_ranks.append(rank)
        # build the metadata 
        meta = Metadata(pkt_len=len(pkt), src_port=0b00000001, dst_port=0b00000100, rank=rank)
        tuser = BinaryValue(bits=len(meta)*8, bigEndian=False)
        tuser.set_buff(str(meta))

        pkts_and_meta.append((rank, pkt, tuser))
    return pkts_and_meta

@cocotb.test()
def test_slow_egress(dut):
    """Testing the simple_tm module with a constant fill level
    """

    # start HW sim clock
    cocotb.fork(Clock(dut.axis_aclk, PERIOD).start())

    # Reset the DUT
    dut._log.debug("Resetting DUT")
    dut.axis_resetn <= 0
    yield ClockCycles(dut.axis_aclk, 10)
    dut.axis_resetn <= 1
    dut._log.debug("Out of reset")

    # wait for the pifo to finish resetting
    yield FallingEdge(dut.axis_aclk)
    while dut.simple_tm_inst.pifo_busy.value:
        yield RisingEdge(dut.axis_aclk)
        yield FallingEdge(dut.axis_aclk)
    yield RisingEdge(dut.axis_aclk)

    yield ClockCycles(dut.axis_aclk, 100)
    dut.m_axis_tready <= 0

    # Attach an AXI4Stream Master to the input pkt interface
    pkt_master = AXI4StreamMaster(dut, 's_axis', dut.axis_aclk)

    # Attach and AXI4StreamSlave to the output pkt interface
    pkt_slave = AXI4StreamSlave(dut, 'm_axis', dut.axis_aclk, idle_timeout=IDLE_TIMEOUT)

    # connect stats tools
    pkt_in_stats = AXI4StreamStats(dut, 's_axis', dut.axis_aclk, idle_timeout=IDLE_TIMEOUT)
    pkt_out_stats = AXI4StreamStats(dut, 'm_axis', dut.axis_aclk, idle_timeout=IDLE_TIMEOUT)

    # start counter for stats
    counter = CycleCounter(dut.axis_aclk)
    counter_thread = cocotb.fork(counter.start())

    # start recording stats
    pkt_in_stats_thread = cocotb.fork(pkt_in_stats.record_n_start_times(NUM_PKTS, counter))
    pkt_out_stats_thread = cocotb.fork(pkt_out_stats.record_n_start_times(NUM_PKTS, counter))

    # start writing pkts
    data = make_pkts_and_meta(NUM_PKTS)
    pkts_in = [tup[1] for tup in data]
    meta_in = [tup[2] for tup in data]
    pkt_master_thread = cocotb.fork(pkt_master.write_pkts(pkts_in, meta_in))

    # wait a few cycles between samples
    for i in range(10):
        yield FallingEdge(dut.axis_aclk)
    yield RisingEdge(dut.axis_aclk)


    expected_ranks = []
    for i in range(NUM_PKTS):
        # compute expected pkt
        input_ranks = [Metadata(m.get_buff()).rank for m in pkt_in_stats.metadata]
#        print 'input_ranks     = {}'.format(input_ranks)
        output_ranks = [Metadata(m.get_buff()).rank for m in pkt_out_stats.metadata]
#        print 'output_ranks    = {}'.format(output_ranks)
        [input_ranks.remove(r) for r in expected_ranks]
#        print 'curr_rank_set   = {}'.format(input_ranks)
        try:
            expected_ranks.append(min(input_ranks))
        except ValueError as e:
            pass
#        print 'expected_ranks  = {}'.format(expected_ranks)
#        print '======================='
        # Read out packet
        yield pkt_slave.read_n_pkts(1)

        # wait a few cycles between samples
        for i in range(10):
            yield FallingEdge(dut.axis_aclk)
            yield RisingEdge(dut.axis_aclk)
        if pkt_slave.error:
            print "ERROR: pkt_slave timed out"
            break

    # get the actual ranks
    meta_out = pkt_slave.metadata
    actual_ranks = [Metadata(m.get_buff()).rank for m in meta_out]

    input_ranks = [Metadata(m.get_buff()).rank for m in pkt_in_stats.metadata]

    print 'input_ranks           = {}'.format(input_ranks)
    print 'expected output ranks = {}'.format(expected_ranks)
    print 'actual output ranks   = {}'.format(actual_ranks)
            

    error = False
#    for (exp_rank, rank, i) in zip(expected_ranks, actual_ranks, range(len(expected_ranks))):
#        if exp_rank != rank:
#            print 'ERROR: exp_rank ({}) != actual_rank ({}) for pkt {}'.format(exp_rank, rank, i)
#            error = True

    for r, i in zip(actual_ranks, range(len(actual_ranks))):
        try:
            input_ranks.remove(r)
        except ValueError as e:
            print 'ERROR: output rank ({}) not in input set'.format(r)
            print e
            error = True
    if len(input_ranks) > 0:
        print 'ERROR: not all ranks removed: {}'.format(input_ranks)
        error = True

    yield ClockCycles(dut.axis_aclk, 20)

    if error:
        print 'ERROR: Test Failed'
        raise(TestFailure)



