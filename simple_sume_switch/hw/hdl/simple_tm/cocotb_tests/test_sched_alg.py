
import logging
import cocotb
import simpy
import random

from cocotb.clock import Clock
from cocotb.triggers import Timer, ReadOnly, RisingEdge, ClockCycles, FallingEdge
from cocotb.binary import BinaryValue
from cocotb.axi4stream import AXI4StreamMaster, AXI4StreamSlave, AXI4StreamStats, CycleCounter
from cocotb.result import TestFailure

from metadata import Metadata
from scapy.all import Ether, IP, UDP, hexdump, rdpcap
from queue_stats import QueueStats, plot_queues

import matplotlib
import matplotlib.pyplot as plt

# Add include directory for python sims
import sys, os
import json

sys.path.append(os.path.expandvars('$SUME_FOLDER/../tm-proto'))
from stats_utils import StatsGenerator

# # strict priority
# PCAP_FILE = 'sched_data/strict/big_test/pkts.pcap'
# RANK_FILE = 'sched_data/strict/big_test/ranks.json'
# NUM_QUEUES = 2

# round robin
PCAP_FILE = 'sched_data/round-robin/pkts.pcap'
RANK_FILE = 'sched_data/round-robin/ranks.json'
NUM_QUEUES = 4

# # weighted round robin
# PCAP_FILE = 'sched_data/weighted-round-robin/pkts.pcap'
# RANK_FILE = 'sched_data/weighted-round-robin/ranks.json'
# NUM_QUEUES = 4

START_DELAY = 100
RESULTS_FILE = 'cocotb_results.json'
PERIOD = 5000
IDLE_TIMEOUT = PERIOD*1000
INGRESS_LINK_RATE = 10 # Gbps
EGRESS_LINK_RATE = 2 # Gbps
RATE_AVG_INTERVAL = 1000 # ns

@cocotb.coroutine
def reset_dut(dut):
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

def make_pkts_meta_in():
    # read the pkts and rank values
    pkts_in = rdpcap(PCAP_FILE)
    with open(RANK_FILE) as f:
        ranks_in = json.load(f)

    pkts_in = pkts_in
    ranks_in = ranks_in
    assert(len(pkts_in) == len(ranks_in))

    meta_in = []
    for pkt, rank in zip(pkts_in, ranks_in):
        flowID = pkt.sport
        meta = Metadata(pkt_len=len(pkt), src_port=0b00000001, dst_port=0b00000100, rank=rank, q_id=flowID)
        tuser = BinaryValue(bits=len(meta)*8, bigEndian=False)
        tuser.set_buff(str(meta))
        meta_in.append(tuser)

    print 'len(pkts_in) = {}'.format(len(pkts_in))
    return pkts_in, meta_in, ranks_in

def plot_stats(input_pkts, output_pkts, egress_link_rate):
    # convert cycles to ns
    input_pkts = [(tup[0]*5, tup[1]) for tup in input_pkts]
    output_pkts = [(tup[0]*5, tup[1]) for tup in output_pkts]
    print 'input_pkts:  (start, end) = ({} ns, {} ns)'.format(input_pkts[0][0], input_pkts[-1][0])
    print 'output_pkts: (start, end) = ({} ns, {} ns)'.format(output_pkts[0][0], output_pkts[-1][0])
    flowID_tuple = ((IP, 'sport'),)
    print "Calculating Input Rates ..."
    input_stats = StatsGenerator(flowID_tuple, input_pkts, avg_interval=RATE_AVG_INTERVAL)
    print "Calculating Output Rates ..."
    output_stats = StatsGenerator(flowID_tuple, output_pkts, avg_interval=RATE_AVG_INTERVAL)
    # create plots
    fig, axarr = plt.subplots(2)
    plt.sca(axarr[0])
    input_stats.plot_rates('Input Flow Rates', linewidth=3)
    plt.sca(axarr[1])
    output_stats.plot_rates('Output Flow Rates', ymax=egress_link_rate+egress_link_rate*0.5, linewidth=3)

@cocotb.test()
def test_sched_alg(dut):
    """Testing the simple_tm module with a particular scheduling alg
    """
    # start HW sim clock
    cocotb.fork(Clock(dut.axis_aclk, PERIOD).start())

    # start counter for stats
    counter = CycleCounter(dut.axis_aclk)
    counter_thread = cocotb.fork(counter.start())

    yield reset_dut(dut)
    yield ClockCycles(dut.axis_aclk, START_DELAY)

    # start recording queue_sizes
    q_stats = QueueStats(dut, NUM_QUEUES)
    q_stats_thread = cocotb.fork(q_stats.start())

    # read the pkts and rank values
    pkts_in, meta_in, ranks_in = make_pkts_meta_in()

    # Attach an AXI4Stream Master to the input pkt interface
    pkt_master = AXI4StreamMaster(dut, 's_axis', dut.axis_aclk)
    pkt_in_stats = AXI4StreamStats(dut, 's_axis', dut.axis_aclk, idle_timeout=IDLE_TIMEOUT)
    pkt_in_stats_thread = cocotb.fork(pkt_in_stats.record_n_start_times(len(pkts_in), counter))

    # Attach and AXI4StreamSlave to the output pkt interface
    tready_delay = 256/(EGRESS_LINK_RATE*5) - 1
    pkt_slave = AXI4StreamSlave(dut, 'm_axis', dut.axis_aclk, idle_timeout=IDLE_TIMEOUT, tready_delay=tready_delay)
    pkt_out_stats = AXI4StreamStats(dut, 'm_axis', dut.axis_aclk, idle_timeout=IDLE_TIMEOUT)
    pkt_out_stats_thread = cocotb.fork(pkt_out_stats.record_n_start_times(len(pkts_in), counter))  # assumes no pkts dropped

    # start reading for pkts
    pkt_slave_thread = cocotb.fork(pkt_slave.read_n_pkts(len(pkts_in)))

    # Send pkts and metadata in the HW sim
    rate = 1.3*INGRESS_LINK_RATE*5/8.0 # bytes/cycle
    yield pkt_master.write_pkts(pkts_in, meta_in, rate=rate)

    # Wait for the pkt_slave and stats to finish (or timeout)
    yield pkt_slave_thread.join()
    yield pkt_in_stats_thread.join()
    yield pkt_out_stats_thread.join()

    # stop the counter
    counter.finish = True
    yield counter_thread.join()
    # stop the q_stats
    q_stats.stop()
    yield q_stats_thread.join()

    t_in = pkt_in_stats.times
    t_out = pkt_out_stats.times

    pkts_out = pkt_slave.pkts
    meta_out = pkt_slave.metadata
    ranks_out = [Metadata(m.get_buff()).rank for m in meta_out]

    yield ClockCycles(dut.axis_aclk, 20)

    print 'len(t_in) = {}'.format(len(t_in))
    print 'len(pkts_in) = {}'.format(len(pkts_in))
    print 'len(t_out) = {}'.format(len(t_out))
    print 'len(pkts_out) = {}'.format(len(pkts_out))
    assert(len(t_in) == len(pkts_in) and len(t_out) == len(pkts_out))

    # plot input / output rates
    plot_stats(zip(t_in, pkts_in), zip(t_out, pkts_out), EGRESS_LINK_RATE)
    plot_queues(q_stats.q_sizes)

    font = {'family' : 'normal',
            'weight' : 'bold',
            'size'   : 22}
    matplotlib.rc('font', **font)
    plt.show()


