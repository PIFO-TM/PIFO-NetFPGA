#!/usr/bin/env python

import simpy
from hwsim_utils import *
from packet_storage_hwsim import *
from scapy.all import *

class Packet_storage_tb(HW_sim_object):
    def __init__(self, env, period, ptr_in_pipe, ptr_out_pipe):
        super(Packet_storage_tb, self).__init__(env, period)
        self.ptr_in_pipe = ptr_in_pipe
        self.ptr_out_pipe = ptr_out_pipe

        self.run()

    def run(self):
        self.env.process(self.rw_ptrs_sm())

    def rw_ptrs_sm(self):
        while True:
            # read head_seg_ptr and metadata_ptr
            (head_seg_ptr, meta_ptr) = yield self.ptr_in_pipe.get()

            # wait for 20 cycles
            for i in range(20):
                yield self.wait_clock()

            # submit read request
            self.ptr_out_pipe.put((head_seg_ptr, meta_ptr))

def main():
    env = simpy.Environment()
    period = 1
    master_ps_axi_pipe = simpy.Store(env)
    slave_ps_axi_pipe = simpy.Store(env)
    ps_ptr_in_pipe = simpy.Store(env)
    ps_ptr_out_pipe = simpy.Store(env)
    bus_width = 32
    
    pkt = Ether()/IP()/TCP()/'hello there pretty world!!!'
    tuser = Tuser(len(pkt), 0b00000001, 0b00000100)
    pkt_list = [(pkt, tuser)]
    
    master = AXI_S_master(env, period, master_ps_axi_pipe, bus_width, pkt_list)
    ps = Pkt_storage(env, period, bus_width, master_ps_axi_pipe, slave_ps_axi_pipe, ps_ptr_in_pipe, ps_ptr_out_pipe)
    slave = AXI_S_slave(env, period, slave_ps_axi_pipe, bus_width)
    
    ps_tb = Packet_storage_tb(env, period, ps_ptr_out_pipe, ps_ptr_in_pipe)
    
    env.run(until=100)


if __name__ == "__main__":
    main()

