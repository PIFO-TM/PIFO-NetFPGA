
import logging
import cocotb
import simpy
import random

from cocotb.clock import Clock
from cocotb.triggers import Timer, ReadOnly, RisingEdge, ClockCycles
from cocotb.binary import BinaryValue
from cocotb.result import TestFailure
from cocotb.axi4stream import AXI4StreamMaster, AXI4StreamSlave
from req_bus_driver import ReqMaster, ReqSlave

from metadata import Metadata
from scapy.all import Ether, IP, UDP, hexdump

PERIOD = 5000
NUM_PORTS = 4

@cocotb.test()
def test_port_tm(dut):
    """Testing port_tm 
    """
    # start HW sim clock
    cocotb.fork(Clock(dut.axis_aclk, PERIOD).start())


    # Reset the DUT
    dut._log.debug("Resetting DUT")
    dut.axis_resetn <= 0
    yield ClockCycles(dut.axis_aclk, 10)
    dut.axis_resetn <= 1
    dut._log.debug("Out of reset")

    print "FINISHED RESET..."

    dut.m_axis_tready <= 0

    dst_port = 0b00000100

    # build the list of pkts and metadata to insert
    pkts_meta_in = []
    for i in range(10):
#        pkt_len = random.randint(50, 1000)
        # build a packet
        pkt = Ether(dst='aa:aa:aa:aa:aa:aa', src='bb:bb:bb:bb:bb:bb')
        pkt = pkt / ('\x11'*18 + '\x22'*32)
#        pkt = pkt / ('\x11'*18 + '\x22'*32 + '\x33'*32 + '\x44'*32 + '\x55'*16)
#        pkt = pkt / ('\x11'*(pkt_len - 14))

        rank = random.randint(0, 100)

        # build the metadata
        meta = Metadata(pkt_len=len(pkt), src_port=0b00000001, dst_port=dst_port, rank=rank)
        tuser = BinaryValue(bits=len(meta)*8, bigEndian=False)
        tuser.set_buff(str(meta))

        pkts_meta_in.append((rank, pkt, tuser))

    ranks_in = [tup[0] for tup in pkts_meta_in]
    pkts_in = [tup[1] for tup in pkts_meta_in]
    meta_in = [tup[2] for tup in pkts_meta_in]

    # Attach an AXI4Stream Master to the input pkt interface
    pkt_master = AXI4StreamMaster(dut, 's_axis', dut.axis_aclk)

    # Send pkts and metadata in the HW sim
    yield pkt_master.write_pkts(pkts_in, meta_in)

    # delay between writing pkts and reading them out
    yield ClockCycles(dut.axis_aclk, 10)

    # Attach and AXI4StreamSlave to the output pkt interface
    pkt_slave = AXI4StreamSlave(dut, 'm_axis', dut.axis_aclk)

    # Read output pkts
    pkt_slave_thread = cocotb.fork(pkt_slave.read_n_pkts(len(pkts_in)))

    # Create the requests
    requests = [1 for r in ranks_in]

    # Attach ReqMaster to each input interface
    nf0_req_master = ReqMaster(dut, 'nf0_sel', dut.axis_aclk)
    nf1_req_master = ReqMaster(dut, 'nf1_sel', dut.axis_aclk)
    nf2_req_master = ReqMaster(dut, 'nf2_sel', dut.axis_aclk)
    nf3_req_master = ReqMaster(dut, 'nf3_sel', dut.axis_aclk)


    # start submitting requests
    delay = 20
    #nf0_req_thread = cocotb.fork(nf0_req_master.write_reqs(requests, delay))
    nf1_req_thread = cocotb.fork(nf1_req_master.write_reqs(requests, delay))
    #nf2_req_thread = cocotb.fork(nf2_req_master.write_reqs(requests, delay))
    #nf3_req_thread = cocotb.fork(nf3_req_master.write_reqs(requests, delay))

    # wait for all pkts 
    yield pkt_slave_thread.join()

    sorted_pkts_meta = sorted(pkts_meta_in, key=lambda x: x[0])

    expected_ranks = [tup[0] for tup in sorted_pkts_meta]
    expected_pkts = [tup[1] for tup in sorted_pkts_meta]
    expected_meta = [tup[2] for tup in sorted_pkts_meta]

    pkts_out = pkt_slave.pkts
    meta_out = pkt_slave.metadata

    actual_ranks = [Metadata(m.get_buff()).rank for m in meta_out]

    print 'input ranks           = {}'.format(ranks_in)
    print 'expected output ranks = {}'.format(expected_ranks)
    print 'actual output ranks   = {}'.format(actual_ranks)
    print ''
    print 'pkt_in_delays = {}'.format(pkt_in_stats.delays)
    print 'pkt_out_delays = {}'.format(pkt_out_stats.delays)

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



