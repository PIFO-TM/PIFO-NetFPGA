
import logging
import cocotb
import simpy
import random

from cocotb.clock import Clock
from cocotb.triggers import Timer, ReadOnly, RisingEdge, ClockCycles
from cocotb.binary import BinaryValue
from cocotb.axi4stream import AXI4StreamMaster, AXI4StreamSlave
from cocotb.result import TestFailure

from metadata import Metadata
from scapy.all import Ether, IP, UDP, hexdump
# Supress SCAPY warning messages
logging.getLogger("scapy").setLevel(logging.ERROR)

# Add include directory for python sims
import sys, os
sys.path.insert(0, os.path.expandvars('$P4_PROJECT_DIR/sw/python_sims'))
from packet_storage import Pkt_storage

PERIOD = 5000
MAX_SEGMENTS = 4096
MAX_PKTS = 4096
RD_LATENCY = 2
WR_LATENCY = 1
SEG_ADDR_WIDTH = 12
META_ADDR_WIDTH = 12

DEBUG = True

class PS_simpy_iface(object):
    def __init__(self, env):
        self.env = env
 
        # create the pipes to communicate with the simpy pkt storage
        self.ptr_in_pipe = simpy.Store(self.env)
        self.ptr_out_pipe = simpy.Store(self.env)
        self.pkt_in_pipe = simpy.Store(self.env)
        self.pkt_out_pipe = simpy.Store(self.env)
    
        # Instantiate the Packet Storage
        self.ps_simpy = Pkt_storage(self.env, 1, self.pkt_in_pipe, self.pkt_out_pipe, self.ptr_in_pipe, self.ptr_out_pipe, MAX_SEGMENTS, MAX_PKTS, rd_latency=RD_LATENCY, wr_latency=WR_LATENCY)

        self.test_failed = False
        # list to store pointers returned by packet_storage 
        self.ptrs = []

    def insert_pkts(self, all_pkts, all_meta, hw_results):
        """
        Insert all provided pkts and metadata into pkt storage and verify the results of the HW simulation
        """
        for (pkt, meta, hw_out_ptrs, i) in zip(all_pkts, all_meta, hw_results['out_ptrs'], range(len(all_pkts))):
            hw_hs_ptr = hw_out_ptrs [SEG_ADDR_WIDTH + META_ADDR_WIDTH-1 : SEG_ADDR_WIDTH]
            hw_m_ptr = hw_out_ptrs  [META_ADDR_WIDTH-1 : 0]

#            hw_hs_ptr = hw_out_ptrs[0 : SEG_ADDR_WIDTH-1]
#            hw_m_ptr = hw_out_ptrs[SEG_ADDR_WIDTH : SEG_ADDR_WIDTH + META_ADDR_WIDTH-1]

            # send the pkts in the simpy sim
            self.pkt_in_pipe.put((pkt, meta))
            # read head_seg_ptr and metadata_ptr
            (sw_hs_ptr, sw_m_ptr) = yield self.ptr_out_pipe.get()
            self.ptrs.append((sw_hs_ptr, sw_m_ptr))

            if DEBUG: 
                print 'Inserting len(pkt): {}, meta: {}'.format(len(pkt), meta.summary())
                print 'Expected: head_seg_ptr = {}, meta_ptr = {}'.format(sw_hs_ptr, sw_m_ptr)
 
            if (sw_hs_ptr != hw_hs_ptr):
                print 'ERROR in head_seg_ptr for pkt {}: HW sim = {}, Python sim = {}'.format(i, hw_hs_ptr, sw_hs_ptr)
                self.test_failed = True
 
            if (sw_m_ptr != hw_m_ptr):
                print 'ERROR in meta_ptr for pkt {}: HW sim = {}, Python sim = {}'.format(i, hw_m_ptr, sw_m_ptr)
                self.test_failed = True

@cocotb.test()
def test_pifo_pkt_storage(dut):
    """Testing pifo_pkt_storage module
    """

    # instantiate the interface to the simpy implemenation
    env = simpy.Environment()
    ps_simpy = PS_simpy_iface(env)

    # start HW sim clock
    cocotb.fork(Clock(dut.axis_aclk, PERIOD).start())

    # Reset the DUT
    dut._log.debug("Resetting DUT")
    dut.axis_resetn <= 0
    dut.m_axis_pkt_tready <= 0
    yield ClockCycles(dut.axis_aclk, 10)
    dut.axis_resetn <= 1
    dut.m_axis_pkt_tready <= 1
    dut._log.debug("Out of reset")

    # initialize the read request pointers
    dut.s_axis_ptr_tvalid <= 0
    dut.s_axis_ptr_tdata <= 0
    dut.s_axis_ptr_tlast <= 0

    # Attach an AXI4Stream Master to the input pkt interface
    pkt_master = AXI4StreamMaster(dut, 's_axis_pkt', dut.axis_aclk)

    # Attach and AXI4StreamSlave to the output ptr interface
    ptr_slave = AXI4StreamSlave(dut, 'm_axis_ptr', dut.axis_aclk)

    hw_results = {}
    hw_results['out_ptrs'] = []

    # build the list of pkts and metadata to insert
    all_pkts = []
    all_meta = []
    for i in range(5):
        pkt_len = random.randint(14, 1000)
        # build a packet
        pkt = Ether(dst='aa:aa:aa:aa:aa:aa', src='bb:bb:bb:bb:bb:bb')
        pkt = pkt / ('\x11'*18 + '\x22'*32 + '\x33'*32 + '\x44'*32 + '\x55'*16)
#        pkt = pkt / ('\x11'*(pkt_len - 14))

    
        # build the metadata 
        meta = Metadata(pkt_len=len(pkt), src_port=0b00000001, dst_port=0b00000100)

        all_pkts.append(pkt)
        all_meta.append(meta)

    # send pkts / metadata and read resulting pointers
    for p, m in zip(all_pkts, all_meta):
        # Start reading for output ptrs
        ptr_slave_thread = cocotb.fork(ptr_slave.read())
    
        # send the pkts in the HW sim
        tuser = BinaryValue(bits=len(meta)*8, bigEndian=False)
        tuser.set_buff(str(m))
        yield pkt_master.write_pkts([p], [tuser])
    
        # wait to finish reading pointers
        yield ptr_slave_thread.join()
   
    # ptr_slave.data is all of the ptr words that have been read so far
    hw_results['out_ptrs'] = ptr_slave.data

    # check results with simpy simulation
    env.process(ps_simpy.insert_pkts(all_pkts, all_meta, hw_results))
    env.run()

    if ps_simpy.test_failed:
        raise TestFailure('Test Failed')

    # pause between pkt insertions and removals
    yield ClockCycles(dut.axis_aclk, 10)

    # Attach an AXI Stream master to read request interface
    ptr_master = AXI4StreamMaster(dut, 's_axis_ptr', dut.axis_aclk)

    # Attach an AXI Stream slave to the output packet interface
    pkt_slave = AXI4StreamSlave(dut, 'm_axis_pkt', dut.axis_aclk) 

    # remove the inserted pkts 
    hw_results['out_pkts'] = []
    for ptrs in hw_results['out_ptrs']:
        # start reading for output pkts

        pkt_slave_thread = cocotb.fork(pkt_slave.read_pkt())
 
        # submit read request
        yield ptr_master.write([ptrs])

        # wait to finish reading pkt
        yield pkt_slave_thread.join()

        yield RisingEdge(dut.axis_aclk)

    hw_results['out_pkts'] = pkt_slave.pkts
    hw_results['out_meta'] = [Metadata(m.get_buff()) for m in pkt_slave.metadata]

    # verify that the removed pkts are the same as the ones that were inserted
    if len(all_pkts) != len(hw_results['out_pkts']):
        print 'ERROR: {} pkts inserted, {} pkts removed'.format(len(all_pkts), len(hw_results['out_pkts']))
        raise TestFailure('Test Failed')

    for (pkt_in, pkt_out, meta_in, meta_out, i) in zip(all_pkts, hw_results['out_pkts'], all_meta, hw_results['out_meta'], range(len(all_pkts))):
        if str(pkt_in) != str(pkt_out):
            print 'ERROR: pkt_in != pkt_out for pkt {}'.format(i)
            print 'len(pkt_in) = {}, pkt_in: {}'.format(len(pkt_in), pkt_in.summary())
            print 'len(pkt_out) = {}, pkt_out: {}'.format(len(pkt_out), pkt_out.summary())
            raise TestFailure('Test Failed')
        if str(meta_in) != str(meta_out):
            print 'ERROR: meta_in != meta_out for pkt {}'.format(i)
            raise TestFailure('Test Failed')


    yield ClockCycles(dut.axis_aclk, 20)



