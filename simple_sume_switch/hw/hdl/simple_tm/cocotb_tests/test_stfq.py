
import logging
import cocotb
import simpy
import random

from cocotb.clock import Clock
from cocotb.triggers import Timer, ReadOnly, RisingEdge, ClockCycles, FallingEdge
from cocotb.binary import BinaryValue
from cocotb.axi4stream import AXI4StreamMaster, AXI4StreamSlave, AXI4StreamStats, CycleCounter
from cocotb.result import TestFailure

from metadata import STFQ_Metadata
from scapy.all import Ether, IP, UDP, hexdump, rdpcap

import matplotlib
import matplotlib.pyplot as plt

# Add include directory for python sims
import sys, os
import json

sys.path.append(os.path.expandvars('$SUME_FOLDER/../tm-proto'))
from stats_utils import StatsGenerator

# STFQ pkts
PCAP_FILE = 'sched_data/stfq/pkts.pcap'


START_DELAY = 100
PERIOD = 5000
IDLE_TIMEOUT = PERIOD*1000
EGRESS_LINK_RATE = 10 # Gbps
NUM_QUEUES = 4
RATE_AVG_INTERVAL = 500 # ns

def scapy_to_bin(meta):
    tuser = BinaryValue(bits=len(meta)*8, bigEndian=False)
    tuser.set_buff(str(meta))
    return tuser

class STFQ_AXI4StreamMaster(AXI4StreamMaster):
    def __init__(self, entity, name, clock, global_state):
        super(STFQ_AXI4StreamMaster, self).__init__(entity, name, clock)
        self.gstate = global_state
        self.last_finish = {}

    @cocotb.coroutine
    def stfq_write_pkts(self, pkts):
        """
        Write a list of scapy pkts onto the AXI4Stream bus and perform the STFQ rank computation for each pkt
        """
        for pkt in pkts:
            # rank computation
            flowID = pkt.sport
            weight = 1
            if flowID in self.last_finish.keys():
                start = max(self.gstate.virtual_time, self.last_finish[flowID])
            else:
                start = self.gstate.virtual_time
            self.last_finish[flowID] = start + len(pkt) / weight 
            rank = start
            metadata = STFQ_Metadata(pkt_len=len(pkt), src_port=0b00000001, dst_port=0b00000100, rank=rank, q_id=flowID, start_time=start)

            meta = scapy_to_bin(metadata)
            pkt_str = str(pkt)
            pkt_words = []
            pkt_keeps = []
            while len(pkt_str) > self.data_width_bytes:
                # build the word
                word = BinaryValue(bits = self.data_width, bigEndian=False)
                word.set_buff(pkt_str[0:self.data_width_bytes])
                pkt_words.append(word)
                # build tkeep
                keep = BinaryValue(bits = self.keep_width, bigEndian=False)
                keep.set_binstr('1'*self.keep_width)
                pkt_keeps.append(keep)
                # update pkt_str
                pkt_str = pkt_str[self.data_width_bytes:]
            # build the last word
            word = BinaryValue(bits = self.data_width, bigEndian=False)
            word.set_buff(pkt_str + '\x00'*(self.data_width_bytes-len(pkt_str)))
            pkt_words.append(word)
            # build the final tkeep
            keep = BinaryValue(bits = self.keep_width, bigEndian=False)
            keep.set_binstr('0'*(self.keep_width-len(pkt_str)) + '1'*len(pkt_str))
            pkt_keeps.append(keep)
            # build tuser
            pkt_users = [meta] + [0]*(len(pkt_words)-1)
            # send the pkt
            yield self.write(pkt_words, keep=pkt_keeps, user=pkt_users)
            # wait a cycle
            yield RisingEdge(self.clock)

class STFQ_state(object):
    def __init__(self):
        self.virtual_time = 0

class STFQ_AXI4StreamEgress(AXI4StreamStats):
    def __init__(self, entity, name, clock, gstate, idle_timeout=5000*1000):
        super(STFQ_AXI4StreamEgress, self).__init__(entity, name, clock, idle_timeout)
        self.gstate = gstate
        self.finish = False

    @cocotb.coroutine
    def update_virtual_time(self):
        """Update the virtual time global state
        """
        self.finish = False
        while not self.finish:
            # wait for the first word of the pkt
            yield FallingEdge(self.clock)
            while not (self.bus.tvalid.value and self.bus.tready.value):
                yield RisingEdge(self.clock)
                yield FallingEdge(self.clock)
    
            # update the virtual time
            tuser = self.bus.tuser.value
            tuser.big_endian = False
            meta = STFQ_Metadata(tuser.get_buff())
            self.gstate.virutal_time = meta.start_time

            # wait for end of current packet
            while not (self.bus.tvalid.value and self.bus.tready.value and self.bus.tlast.value):
                yield RisingEdge(self.clock)
                yield FallingEdge(self.clock)
    
            yield RisingEdge(self.clock)

    def stop(self):
        self.finish = True

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
def test_stfq(dut):
    """Testing the simple_tm module with a stfq 
    """
    # start HW sim clock
    cocotb.fork(Clock(dut.axis_aclk, PERIOD).start())

    # start counter for stats
    counter = CycleCounter(dut.axis_aclk)
    counter_thread = cocotb.fork(counter.start())

    yield reset_dut(dut)
    yield ClockCycles(dut.axis_aclk, START_DELAY)

    # read the pkts and rank values
    pkts_in = rdpcap(PCAP_FILE)

    # global state that is accessed on ingress and updated on egress
    global_state = STFQ_state()

    # Attach an AXI4Stream Master to the input pkt interface
    pkt_master = STFQ_AXI4StreamMaster(dut, 's_axis', dut.axis_aclk, global_state)
    pkt_in_stats = AXI4StreamStats(dut, 's_axis', dut.axis_aclk, idle_timeout=IDLE_TIMEOUT)
    pkt_in_stats_thread = cocotb.fork(pkt_in_stats.record_n_start_times(len(pkts_in), counter))

    # Attach and AXI4StreamSlave to the output pkt interface
    tready_delay = 256/(EGRESS_LINK_RATE*5) - 1
    pkt_slave = AXI4StreamSlave(dut, 'm_axis', dut.axis_aclk, idle_timeout=IDLE_TIMEOUT, tready_delay=tready_delay)
    pkt_out_stats = AXI4StreamStats(dut, 'm_axis', dut.axis_aclk, idle_timeout=IDLE_TIMEOUT)
    pkt_out_stats_thread = cocotb.fork(pkt_out_stats.record_n_start_times(len(pkts_in), counter))
    # Attach STFQ Egress processing logic
    stfq_egress = STFQ_AXI4StreamEgress(dut, 'm_axis', dut.axis_aclk, global_state, idle_timeout=IDLE_TIMEOUT)
    stfq_egress_thread = cocotb.fork(stfq_egress.update_virtual_time())

    # start reading for pkts
    pkt_slave_thread = cocotb.fork(pkt_slave.read_n_pkts(len(pkts_in)))

    # Send pkts and metadata in the HW sim
    yield pkt_master.stfq_write_pkts(pkts_in)

    # Wait for the pkt_slave and stats to finish (or timeout)
    yield pkt_slave_thread.join()
    yield pkt_in_stats_thread.join()
    yield pkt_out_stats_thread.join()

    # stop the counter
    counter.finish = True
    yield counter_thread.join()

    t_in = pkt_in_stats.times
    t_out = pkt_out_stats.times

    pkts_out = pkt_slave.pkts
    meta_out = pkt_slave.metadata

    yield ClockCycles(dut.axis_aclk, 20)

    egress_link_rate = 50 # Gbps

    print 'len(t_in) = {}'.format(len(t_in))
    print 'len(pkts_in) = {}'.format(len(pkts_in))
    print 'len(t_out) = {}'.format(len(t_out))
    print 'len(pkts_out) = {}'.format(len(pkts_out))
    assert(len(t_in) == len(pkts_in) and len(t_out) == len(pkts_out))

    # plot input / output rates
    plot_stats(zip(t_in, pkts_in), zip(t_out, pkts_out), EGRESS_LINK_RATE)

    font = {'family' : 'normal',
            'weight' : 'bold',
            'size'   : 22}
    matplotlib.rc('font', **font)
    plt.show()


