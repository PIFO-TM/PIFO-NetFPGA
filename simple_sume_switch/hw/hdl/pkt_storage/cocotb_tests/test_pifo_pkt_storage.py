
import logging
import cocotb

from cocotb.clock import Clock
from cocotb.triggers import Timer, ReadOnly, RisingEdge, ClockCycles
from cocotb.binary import BinaryValue
from cocotb.axi4stream import AXI4StreamMaster, AXI4StreamSlave

from Tuser import Tuser
from scapy.all import Ether, IP, UDP
# Supress SCAPY warning messages
logging.getLogger("scapy").setLevel(logging.ERROR)

PERIOD = 5000

@cocotb.test()
def test_pifo_pkt_storage(dut):
    """Testing pifo_pkt_storage module
    """
    # start HW sim clock
    cocotb.fork(Clock(dut.axis_aclk, PERIOD).start())

    # Wait to start
    dut._log.debug("Resetting DUT")
    dut.axis_resetn <= 0
    dut.m_axis_pkt_tready <= 0
    yield ClockCycles(dut.axis_aclk, 10)
    dut.axis_resetn <= 1
    dut.m_axis_pkt_tready <= 1
    dut._log.debug("Out of reset")

    dut.s_axis_ptr_tvalid <= 0
    dut.s_axis_ptr_tdata <= 0
    dut.s_axis_ptr_tkeep <= 0
    dut.s_axis_ptr_tlast <= 0

    # Attach and AXI4Stream Master
    pkt_master = AXI4StreamMaster(dut, 's_axis_pkt', dut.axis_aclk, data_width=32, user_width=16)

    # build a packet
    pkt = Ether(dst='ff:ff:ff:ff:ff:ff', src='08:22:22:22:22:08')
    pkt = pkt / ('\x00'*(160 - len(pkt)))

    # build the metadata 
    meta = Tuser(dst_port=0b00000100, src_port=0b00000001, pkt_len=len(pkt))
    tuser = BinaryValue(bits=len(meta)*8, bigEndian=False)
    tuser.set_buff(str(meta))

    yield pkt_master.write_pkts([pkt, pkt], [tuser, tuser])

#    dut.s_axis_pkt_tvalid <= 0
#    dut.s_axis_pkt_tdata <= 0
#    dut.s_axis_pkt_tkeep <= 0
#    dut.s_axis_pkt_tuser <= 0
#    dut.s_axis_pkt_tlast <= 0
 
    yield ClockCycles(dut.axis_aclk, 100)

