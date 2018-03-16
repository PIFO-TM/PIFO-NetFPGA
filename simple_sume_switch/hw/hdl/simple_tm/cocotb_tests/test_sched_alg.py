
import logging
import cocotb
import simpy
import random

from cocotb.clock import Clock
from cocotb.triggers import Timer, ReadOnly, RisingEdge, ClockCycles
from cocotb.binary import BinaryValue
from cocotb.axi4stream import AXI4StreamMaster, AXI4StreamSlave, AXI4StreamStats, CycleCounter
from cocotb.result import TestFailure

from metadata import Metadata
from scapy.all import Ether, IP, UDP, hexdump

# Add include directory for python sims
import sys, os
import json

sys.path.append(os.path.expandvars('$SUME_FOLDER/../tm-proto'))
from stats_utils import StatsGenerator

PCAP_FILE = 'strict.pcap'
RANK_FILE = 'strict_ranks.json'

RESULTS_FILE = 'cocotb_results.json'
PERIOD = 5000

@cocotb.coroutine
def reset_dut(dut):
    # Reset the DUT
    dut._log.debug("Resetting DUT")
    dut.axis_resetn <= 0
    yield ClockCycles(dut.axis_aclk, 10)
    dut.axis_resetn <= 1
    dut._log.debug("Out of reset")

def make_pkts_meta_in():
    # read the pkts and rank values
#    pkts_in = rdpcap(PCAP_FILE)
#    with open(RANK_FILE) as f:
#        ranks_in = json.load(f)

    num_pkts = 1
    pkts_in = [Ether(dst='aa:aa:aa:aa:aa:aa', src='bb:bb:bb:bb:bb:bb')/('\x11'*18 + '\x22'*32 + '\x33'*32 + '\x44'*32 + '\x55'*16)]
    ranks_in = [1]
    #ranks_in = range(num_pkts)

    assert(len(pkts_in) == len(ranks_in))

    meta_in = []
    for pkt, rank in zip(pkts_in, ranks_in):
        meta = Metadata(pkt_len=len(pkt), src_port=0b00000001, dst_port=0b00000100, rank=rank)
        tuser = BinaryValue(bits=len(meta)*8, bigEndian=False)
        tuser.set_buff(str(meta))
        meta_in.append(tuser)
    return pkts_in, meta_in, ranks_in

def plot_stats(input_pkts, output_pkts, egress_link_rate):
    # convert cycles to ns
    input_pkts = [(tup[0]*5, tup[1]) for tup in input_pkts]
    output_pkts = [(tup[0]*5, tup[1]) for tup in output_pkts]
    print 'input_pkts:  (start, end) = ({} ns, {} ns)'.format(input_pkts[0][0], input_pkts[-1][0])
    print 'output_pkts: (start, end) = ({} ns, {} ns)'.format(output_pkts[0][0], output_pkts[-1][0])
    flowID_tuple = ((IP, 'sport'),)
    print "Calculating Input Rates ..."
    input_stats = StatsGenerator(flowID_tuple, input_pkts)
    print "Calculating Output Rates ..."
    output_stats = StatsGenerator(flowID_tuple, output_pkts)
    # create plots
    fig, axarr = plt.subplots(2)
    plt.sca(axarr[0])
    input_stats.plot_rates('Input Flow Rates', linewidth=3)
    plt.sca(axarr[1])
    output_stats.plot_rates('Output Flow Rates', ymax=egress_link_rate+egress_link_rate*0.5, linewidth=3)

    font = {'family' : 'normal',
            'weight' : 'bold',
            'size'   : 22}
    matplotlib.rc('font', **font)
    plt.show()

@cocotb.test()
def test_sched_alg(dut):
    """Testing the simple_tm module with a particular scheduling alg
    """

    # start HW sim clock
    cocotb.fork(Clock(dut.axis_aclk, PERIOD).start())

    counter = CycleCounter(dut.axis_aclk)
    counter_thread = cocotb.fork(counter.start())

    yield reset_dut(dut)

    # read the pkts and rank values
    pkts_in, meta_in, ranks_in = make_pkts_meta_in()

    # Attach an AXI4Stream Master to the input pkt interface
    pkt_master = AXI4StreamMaster(dut, 's_axis', dut.axis_aclk)
    pkt_in_stats = AXI4StreamStats(dut, 's_axis', dut.axis_aclk)
    pkt_in_stats_thread = cocotb.fork(pkt_in_stats.record_n_start_times(len(pkts_in), counter))

    # Attach and AXI4StreamSlave to the output pkt interface
    pkt_slave = AXI4StreamSlave(dut, 'm_axis', dut.axis_aclk)
    pkt_out_stats = AXI4StreamStats(dut, 'm_axis', dut.axis_aclk)
    pkt_out_stats_thread = cocotb.fork(pkt_out_stats.record_n_start_times(len(pkts_in), counter))  # assumes no pkts dropped

    # start reading for pkts
    pkt_slave_thread = cocotb.fork(pkt_slave.read_n_pkts(len(pkts_in)))

    # Send pkts and metadata in the HW sim
    yield pkt_master.write_pkts(pkts_in, meta_in)

    # wait for stats threads to finish
    yield pkt_in_stats_thread.join()
    yield pkt_out_stats_thread.join()

    # stop the counter
    counter.finish = True
    counter_thread.join()

    t_in = pkt_in_stats.times
    t_out = pkt_out_stats.times

    pkts_out = pkt_slave.pkts
    meta_out = pkt_slave.metadata
    ranks_out = [Metadata(m.get_buff()).rank for m in meta_out]

    print 'input ranks    = {}'.format(ranks_in)
    print 'output ranks   = {}'.format(ranks_out)
    print ''
    print 't_in  = {}'.format(t_in)
    print 't_out = {}'.format(t_out)

    yield ClockCycles(dut.axis_aclk, 20)

    egress_link_rate = 10 # Gbps
    assert(len(t_in) == len(pkts_in) and len(t_out) == len(pkts_out))

    # plot input / output rates
#    plot_stats(zip(t_in, pkts_in), zip(t_out, pkts_out), egress_link_rate)

