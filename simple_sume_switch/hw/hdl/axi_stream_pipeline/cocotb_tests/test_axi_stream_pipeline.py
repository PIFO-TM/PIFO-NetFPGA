
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

PERIOD = 5000

@cocotb.test()
def test_axi_stream_pipeline(dut):
    """Testing axi_stream_pipeline 
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
    pkt_slave = AXI4StreamSlave(dut, 'm_axis', dut.axis_aclk)

    # build the list of pkts and metadata to insert
    pkts_meta_in = [] 
    for i in range(20):
        pkt_len = random.randint(50, 1000)
        # build a packet
        pkt = Ether(dst='aa:aa:aa:aa:aa:aa', src='bb:bb:bb:bb:bb:bb')
#        pkt = pkt / ('\x11'*18 + '\x22'*32)
#        pkt = pkt / ('\x11'*18 + '\x22'*32 + '\x33'*32 + '\x44'*32 + '\x55'*16)
        pkt = pkt / ('\x11'*(pkt_len - 14))

        rank = random.randint(0, 100)
    
        # build the metadata 
        meta = Metadata(pkt_len=len(pkt), src_port=0b00000001, dst_port=0b00000100, rank=rank)
        tuser = BinaryValue(bits=len(meta)*8, bigEndian=False)
        tuser.set_buff(str(meta))

        pkts_meta_in.append((pkt, tuser))

    pkts_in = [tup[0] for tup in pkts_meta_in]
    meta_in = [tup[1] for tup in pkts_meta_in]

    # Read pkts out
    slave_thread = cocotb.fork(pkt_slave.read_n_pkts(len(pkts_in)))

    # Send pkts and metadata in the HW sim
    yield pkt_master.write_pkts(pkts_in, meta_in)

    yield slave_thread.join()

    expected_pkts = pkts_in
    expected_meta = meta_in

    pkts_out = pkt_slave.pkts
    meta_out = pkt_slave.metadata

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



