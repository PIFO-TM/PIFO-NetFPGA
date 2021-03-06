
import logging
import cocotb
import random

from cocotb.clock import Clock
from cocotb.triggers import Timer, ReadOnly, RisingEdge, ClockCycles, FallingEdge
from cocotb.binary import BinaryValue
from cocotb.axi4stream import AXI4StreamMaster, AXI4StreamSlave, AXI4StreamStats
from cocotb.result import TestFailure

from metadata import Metadata
from scapy.all import Ether, IP, UDP, hexdump

# Add include directory for python sims
import sys, os
import json

FILL_LEVEL = 50
NUM_SAMPLES = 10

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

@cocotb.coroutine
def wait_pifo_busy(dut):
    # wait for the pifo to finish resetting
    yield FallingEdge(dut.axis_aclk)
    while dut.simple_tm_inst.pifo_busy.value:
        yield RisingEdge(dut.axis_aclk)
        yield FallingEdge(dut.axis_aclk)
    yield RisingEdge(dut.axis_aclk)

@cocotb.test()
def test_const_fill(dut):
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
    yield wait_pifo_busy(dut)

    yield ClockCycles(dut.axis_aclk, 100)
    dut.m_axis_tready <= 0

    # build the list of pkts and metadata to insert
    pkts_meta_in = make_pkts_and_meta(FILL_LEVEL-1)

    ranks_in = [tup[0] for tup in pkts_meta_in] 
    pkts_in = [tup[1] for tup in pkts_meta_in]
    meta_in = [tup[2] for tup in pkts_meta_in]

    # Attach an AXI4Stream Master to the input pkt interface
    pkt_master = AXI4StreamMaster(dut, 's_axis', dut.axis_aclk)

    # Send pkts and metadata in the HW sim
    yield pkt_master.write_pkts(pkts_in, meta_in)

    # wait for the final write to complete
    yield wait_pifo_busy(dut)
    # wait a few cycles before begining measurements 
    yield ClockCycles(dut.axis_aclk, 25)

    # Attach and AXI4StreamSlave to the output pkt interface
    pkt_slave = AXI4StreamSlave(dut, 'm_axis', dut.axis_aclk, idle_timeout=IDLE_TIMEOUT)

    # connect stats tools
    pkt_in_stats = AXI4StreamStats(dut, 's_axis', dut.axis_aclk, idle_timeout=IDLE_TIMEOUT)
    pkt_out_stats = AXI4StreamStats(dut, 'm_axis', dut.axis_aclk, idle_timeout=IDLE_TIMEOUT)


    expected_outputs = []
    enq_delays = []
    deq_delays = []
    for i in range(NUM_SAMPLES):
        data = make_pkts_and_meta(1)
        pkts_in = [tup[1] for tup in data]
        meta_in = [tup[2] for tup in data]
        pkts_meta_in += data
        # compute expected outputs
        expected_outputs.append(min(pkts_meta_in))
        pkts_meta_in.remove(min(pkts_meta_in))
        # start recording stats
        pkt_in_stats_thread = cocotb.fork(pkt_in_stats.record_n_enq_delays(1))
        pkt_out_stats_thread = cocotb.fork(pkt_out_stats.record_n_deq_delays(1))
        # send in packet 
        yield pkt_master.write_pkts(pkts_in, meta_in)
        # wait for the write to complete
        yield wait_pifo_busy(dut)
        # Read out packet
        yield pkt_slave.read_n_pkts(1)
        # record results
        enq_delays += pkt_in_stats.enq_delays
        deq_delays += pkt_out_stats.deq_delays
        # wait a few cycles between samples
        yield ClockCycles(dut.axis_aclk, 30)
        if pkt_slave.error:
            print "ERROR: pkt_slave timed out"
            break


    sorted_pkts_meta = sorted(pkts_meta_in, key=lambda x: x[0])

    expected_ranks = [tup[0] for tup in expected_outputs]
    expected_pkts = [tup[1] for tup in expected_outputs]
    expected_meta = [tup[2] for tup in expected_outputs]

    pkts_out = pkt_slave.pkts
    meta_out = pkt_slave.metadata

    actual_ranks = [Metadata(m.get_buff()).rank for m in meta_out]

    print 'input_ranks           = {}'.format(input_ranks)
    print 'expected output ranks = {}'.format(expected_ranks)
    print 'actual output ranks   = {}'.format(actual_ranks)
    print ''
    print 'pkt_in_delays = {}'.format(enq_delays)
    print 'pkt_out_delays = {}'.format(deq_delays)

    results = {}
    results['enq_delays'] = enq_delays
    results['deq_delays'] = deq_delays
    with open(RESULTS_FILE, 'w') as f:
        json.dump(results, f)

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



