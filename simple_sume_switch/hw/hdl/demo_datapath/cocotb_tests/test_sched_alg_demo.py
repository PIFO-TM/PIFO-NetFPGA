
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

# # strict priority
# PCAP_FILE = 'sched_data/strict/big_test/pkts.pcap'
# INGRESS_LINK_RATE = 10 # Gbps
# EGRESS_LINK_RATE = 4 # Gbps
# NUM_PKTS = 1500
# RANK_OP = 0

# # round robin
# PCAP_FILE = 'sched_data/round-robin/pkts.pcap'
# INGRESS_LINK_RATE = 10 # Gbps
# EGRESS_LINK_RATE = 4 # Gbps
# NUM_PKTS = 1500
# RANK_OP = 1

# weighted round robin
PCAP_FILE = 'sched_data/weighted-round-robin/pkts.pcap'
INGRESS_LINK_RATE = 10 # Gbps
EGRESS_LINK_RATE = 4 # Gbps
NUM_PKTS = 1500
RANK_OP = 2

# #### DEBUGGING ####
# #PCAP_FILE = 'sched_data/debug/queue_1_pkts_1500.pcap'
# #PCAP_FILE = 'sched_data/debug/queues_2_3_pkts_1500.pcap'
# PCAP_FILE = 'sched_data/debug/rand_pkts.pcap'
# #PCAP_FILE = 'sched_data/debug/pkts_inc_data_seq.pcap'
# INGRESS_LINK_RATE = 10 # Gbps
# EGRESS_LINK_RATE = 4 # Gbps
# NUM_PKTS = 200
# RANK_OP = 0


FLOW_WEIGHTS = {0:2, 1:1, 2:1, 3:1}
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
    while dut.simple_tm_inst.pifo_busy.value:
        yield RisingEdge(dut.axis_aclk)
        yield FallingEdge(dut.axis_aclk)
    yield RisingEdge(dut.axis_aclk)

def make_pkts_meta_in():
    global TEST_PKT
    # read the pkts
    pkts_in = rdpcap(PCAP_FILE)
    pkts_in =  pkts_in[0:NUM_PKTS]

#    rst_pkt = Ether(dst='08:11:11:11:11:08', src='ff:ff:ff:ff:ff:ff') / IP(src='10.0.0.2', dst='10.0.0.1') / TCP(sport=1) / ('\x00'*10)
#    pkts_in.append(rst_pkt)
#    final_pkt = Ether(dst='08:11:11:11:11:08', src='08:22:22:22:22:08') / IP(src='10.0.0.2', dst='10.0.0.1') / TCP(sport=1) / ('\x00'*10)
#    pkts_in.append(final_pkt)

    meta_in = []
    for pkt in pkts_in:
        flowID = pkt.sport
        rank_rst = 1 if pkt[Ether].src == 'ff:ff:ff:ff:ff:ff' else 0
        meta = Metadata(pkt_len=len(pkt), src_port=0b00000001, dst_port=0b00000100, bp_count=BP_COUNT, q_id=flowID, rank_op=RANK_OP, flow_id=flowID, flow_weight=FLOW_WEIGHTS[flowID], rank_rst=rank_rst)
        tuser = BinaryValue(bits=len(meta)*8, bigEndian=False)
        tuser.set_buff(str(meta))
        meta_in.append(tuser)

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

def plot_stats(input_log_pkts, output_log_pkts, egress_link_rate):
    start_time = input_log_pkts[0].time
    print "Calculating Input Rates ..."
    input_stats = FlowStats(input_log_pkts, start_time, avg_interval=RATE_AVG_INTERVAL)
    print "Calculating Output Rates ..."
    output_stats = FlowStats(output_log_pkts, start_time, avg_interval=RATE_AVG_INTERVAL)
    # create plots
    fig, axarr = plt.subplots(2)
    plt.sca(axarr[0])
    input_stats.plot_rates('', ymax=12, linewidth=5)
    plt.ylabel('Input Rate (Gb/s)')
    plt.sca(axarr[1])
    output_stats.plot_rates('', ymax=12, linewidth=5)
    plt.ylabel('Output Rate (Gb/s)')

    # plot queue sizes
    in_queue_stats = QueueStats(input_log_pkts, start_time)
    in_queue_stats.plot_queues()
    plt.title('Input Queue Sizes')
    out_queue_stats = QueueStats(output_log_pkts, start_time)
    out_queue_stats.plot_queues()
    plt.title('Output Queue Sizes')

@cocotb.test()
def test_sched_alg_demo(dut):
    """Test to make sure that the demo will work in simulation.
    """
    # start HW sim clock
    cocotb.fork(Clock(dut.axis_aclk, PERIOD).start())

    yield reset_dut(dut)
    yield ClockCycles(dut.axis_aclk, START_DELAY)

    # read the pkts and rank values
    pkts_in, meta_in = make_pkts_meta_in()

    # Attach an AXI4Stream Master to the input pkt interface
    pkt_master = AXI4StreamMaster(dut, 's_axis', dut.axis_aclk)

    # Attach and AXI4StreamSlave to the output pkt interface
    pkt_slave = AXI4StreamSlave(dut, 'nf1_m_axis', dut.axis_aclk, idle_timeout=IDLE_TIMEOUT)
    input_logger = AXI4StreamSlave(dut, 'nf3_m_axis', dut.axis_aclk, idle_timeout=IDLE_TIMEOUT)
    output_logger = AXI4StreamSlave(dut, 'nf2_m_axis', dut.axis_aclk, idle_timeout=IDLE_TIMEOUT)

    # start reading for pkts
    pkt_slave_thread = cocotb.fork(pkt_slave.read_n_pkts(len(pkts_in)))
    input_logger_thread = cocotb.fork(input_logger.read_n_pkts(len(pkts_in)))
    output_logger_thread = cocotb.fork(output_logger.read_n_pkts(len(pkts_in)))

    # Send pkts and metadata in the HW sim
    rate = 1.3*INGRESS_LINK_RATE*5/8.0 # bytes/cycle
    yield pkt_master.write_pkts(pkts_in, meta_in, rate=rate)

    # Wait for the pkt_slave to finish (or timeout)
    yield pkt_slave_thread.join()

    pkts_out = pkt_slave.pkts
    meta_out = pkt_slave.metadata
#    ranks_out = [Metadata(m.get_buff()).rank for m in meta_out]

    yield ClockCycles(dut.axis_aclk, 20)

    print 'len(pkts_in) = {}'.format(len(pkts_in))
    print 'len(pkts_out) = {}'.format(len(pkts_out))
#    check_pkts(pkts_out)

    # Parse the logged pkts
    pkt_parser = LogPktParser()
    input_log_pkts = pkt_parser.parse_pkts(map(str, input_logger.pkts))
    output_log_pkts = pkt_parser.parse_pkts(map(str, output_logger.pkts))

#    print 'input_log_pkts:'
#    for p in map(str, input_log_pkts):
#        print p
#
#    print 'output_log_pkts:'
#    for p in map(str, output_log_pkts):
#        print p

    # plot input / output rates
    plot_stats(input_log_pkts, output_log_pkts, EGRESS_LINK_RATE)

    font = {'family' : 'normal',
            'weight' : 'bold',
            'size'   : 32}
    matplotlib.rc('font', **font)
    plt.show()


