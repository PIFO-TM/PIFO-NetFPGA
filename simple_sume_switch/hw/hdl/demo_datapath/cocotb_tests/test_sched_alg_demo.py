
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

import matplotlib
import matplotlib.pyplot as plt

# Add include directory for python sims
import sys, os
import json

from demo_utils.log_pkt_parser import LogPktParser
from demo_utils.flow_stats import FlowStats
from demo_utils.queue_stats import QueueStats

NF1_PCAP_FILE = 'iperf-sim-traces/iperf3-10MB-dport1-trim.pcap'
NF1_META_FILE = 'iperf-sim-traces/metadata_10MB_dport1.csv'
NF2_PCAP_FILE = 'iperf-sim-traces/iperf3-20MB-dport2-trim.pcap'
NF2_META_FILE = 'iperf-sim-traces/metadata_20MB_dport2.csv'
INGRESS_LINK_RATE = 10 # Gbps
EGRESS_LINK_RATE = 12 # Gbps

START_DELAY = 100
RESULTS_FILE = 'cocotb_results.json'
PERIOD = 5000
IDLE_TIMEOUT = PERIOD*1000
RATE_AVG_INTERVAL = 1000 # ns
#RATE_AVG_INTERVAL = 20000 # ns

BP_COUNT = 256/(EGRESS_LINK_RATE*5) + 1
#BP_COUNT = 0 

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
    while dut.demo_datapath_inst.simple_tm_inst.pifo_busy.value:
        yield RisingEdge(dut.axis_aclk)
        yield FallingEdge(dut.axis_aclk)
    yield RisingEdge(dut.axis_aclk)

def rdmeta(meta_file):
    meta_in = []
    with open(meta_file) as f:
        for line in f:
            vals = map(int, line.strip().split(','))
#            meta = Metadata(pkt_len=vals[-1], src_port=vals[-2], dst_port=vals[-3], bp_count=BP_COUNT, q_id=vals[-5], rank_op=vals[-6], srpt_rank=vals[-7], log_pkt=vals[-8])
            meta = Metadata(pkt_len=vals[-1], src_port=vals[-2], dst_port=vals[-3], bp_count=vals[-4], q_id=0, rank_op=vals[-6], srpt_rank=vals[-7], log_pkt=1)
            tuser = BinaryValue(bits=len(meta)*8, bigEndian=False)
            tuser.set_buff(str(meta))
            meta_in.append(tuser)   
    return meta_in

def make_pkts_meta_in(pcap_file, meta_file):
    # read the pkts
    pkts_in = rdpcap(pcap_file)
    #pkts_in =  pkts_in[0:NUM_PKTS]

    meta_in = rdmeta(meta_file)

    print 'len(pkts_in) = {}'.format(len(pkts_in))
    return pkts_in, meta_in

def check_pkts(pkts_out):
    pkts_exp = rdpcap(PCAP_FILE)
    pkts_exp = pkts_exp[0:NUM_PKTS]

    for p_out, p_exp, i in zip(pkts_out, pkts_exp, range(len(pkts_out))):
        if p_out != p_exp:
            print 'WARNING: unexpected pkt -- index: {} -- pkt_len: {}'.format(i, len(p_out))
            p_out.show()
            print ''

def plot_stats(log_pkts, egress_link_rate):
    start_time = log_pkts[0].time

#    print "Calculating Input Rates ..."
#    input_stats = FlowStats(log_pkts, start_time, avg_interval=RATE_AVG_INTERVAL)
#    # create plots
#    plt.figure()
#    input_stats.plot_rates('', ymax=12, linewidth=5)
#    plt.ylabel('Input Rate (Gb/s)')

    # plot queue sizes
    in_queue_stats = QueueStats(log_pkts, start_time)
    in_queue_stats.plot_queues()
    plt.title('Input Queue Sizes')

@cocotb.test()
def test_sched_alg_demo(dut):
    """Test to make sure that the demo will work in simulation.
    """
    # start HW sim clock
    cocotb.fork(Clock(dut.axis_aclk, PERIOD).start())

    yield reset_dut(dut)
    yield ClockCycles(dut.axis_aclk, START_DELAY)

    # read the pkts and rank values
    nf1_pkts_in, nf1_meta_in = make_pkts_meta_in(NF1_PCAP_FILE, NF1_META_FILE)
    nf2_pkts_in, nf2_meta_in = make_pkts_meta_in(NF2_PCAP_FILE, NF2_META_FILE)

    # Attach an AXI4Stream Master to the input pkt interface
    nf1_master = AXI4StreamMaster(dut, 's_axis_1', dut.axis_aclk)
    nf2_master = AXI4StreamMaster(dut, 's_axis_2', dut.axis_aclk)

    # Attach an AXI4StreamSlave to the output pkt interface
    pkt_slave = AXI4StreamSlave(dut, 'nf0_m_axis', dut.axis_aclk, tready_delay=BP_COUNT, idle_timeout=IDLE_TIMEOUT)
    input_logger = AXI4StreamSlave(dut, 'nf3_m_axis', dut.axis_aclk, idle_timeout=IDLE_TIMEOUT*1000000)

    # start reading for pkts
    num_pkts = len(nf1_pkts_in) + len(nf2_pkts_in)
    pkt_slave_thread = cocotb.fork(pkt_slave.read_n_pkts(num_pkts))
    input_logger_thread = cocotb.fork(input_logger.read_n_pkts(num_pkts, log_raw=True))

    # Send pkts and metadata in the HW sim
    rate = 1.0*INGRESS_LINK_RATE*5/8.0 # bytes/cycle
    nf2_master_thread = cocotb.fork(nf2_master.write_pkts(nf2_pkts_in, nf2_meta_in, rate=rate))
    for i in range(10000):
        yield RisingEdge(dut.axis_aclk)
        yield FallingEdge(dut.axis_aclk)
    print 'starting nf1_master'
    nf1_master_thread = cocotb.fork(nf1_master.write_pkts(nf1_pkts_in, nf1_meta_in, rate=rate))

    yield nf1_master_thread.join()
    yield nf2_master_thread.join()

    # Wait for the pkt_slave to finish (or timeout)
    yield pkt_slave_thread.join()

    pkts_out = pkt_slave.pkts
    meta_out = pkt_slave.metadata
#    ranks_out = [Metadata(m.get_buff()).rank for m in meta_out]

    yield ClockCycles(dut.axis_aclk, 20)

    print 'len(pkts_out) = {}'.format(len(pkts_out))
    print 'len(logged_pkts) = {}'.format(len(input_logger.pkts))
#    check_pkts(pkts_out)

    # Parse the logged pkts
    pkt_parser = LogPktParser()
    input_log_pkts = pkt_parser.parse_pkts(map(str, input_logger.pkts))

#    print 'input_log_pkts:'
#    for p in map(str, input_log_pkts):
#        print p


    # plot input / output rates
    plot_stats(input_log_pkts, EGRESS_LINK_RATE)

    font = {'family' : 'normal',
            'weight' : 'bold',
            'size'   : 32}
    matplotlib.rc('font', **font)
    plt.show()


