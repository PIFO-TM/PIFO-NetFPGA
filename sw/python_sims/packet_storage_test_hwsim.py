#!/usr/bin/env python

import simpy
from hwsim_utils import *
from packet_storage import *
from scapy.all import *

class Packet_storage_tb(HW_sim_object):
    def __init__(self, env, period):
        super(Packet_storage_tb, self).__init__(env, period)
        self.ptr_in_pipe = simpy.Store(env)
        self.ptr_out_pipe = simpy.Store(env)
        self.pkt_in_pipe = simpy.Store(env)
        self.pkt_out_pipe = simpy.Store(env)

        self.ps = Pkt_storage(env, period, self.pkt_in_pipe, self.pkt_out_pipe, self.ptr_in_pipe, self.ptr_out_pipe)

        self.run()

    def run(self):
        self.env.process(self.rw_ps_sm())

    def rw_ps_sm(self):
        """
        1. Write pkt and metadata into packet storage
        2. Read back head_seg_ptr and meta_ptr
        3. Wait 20 cycles
        4. Submit read request to packet storage using head_seg_ptr and meta_ptr
        5. Read output pkt and meta data 
        """
        # create the test packets
        pkt = Ether()/IP()/TCP()/'hello there pretty world!!!'
        tuser = Tuser(len(pkt), 0b00000001, 0b00000100)
        pkt_list = [(pkt, tuser)]
        for pkt, tuser in pkt_list:
            print '@ {} - Writing to storage: {} || {}'.format(self.env.now, pkt.summary(), tuser)
            # write the pkt and metadata into storage
            self.pkt_in_pipe.put((pkt, tuser))
            # read head_seg_ptr and metadata_ptr
            (head_seg_ptr, meta_ptr) = yield self.ptr_out_pipe.get()
            print '@ {} - Received pointers: head_seg_ptr = {} , meta_ptr = {}'.format(self.env.now, head_seg_ptr, meta_ptr)

            # wait for 20 cycles
            for i in range(20):
                yield self.wait_clock()

            print '@ {} - submitting read request: head_seg_ptr = {} , meta_ptr = {}'.format(self.env.now, head_seg_ptr, meta_ptr)
            # submit read request
            self.ptr_in_pipe.put((head_seg_ptr, meta_ptr))
            # wait to receive output pkt and metadata
            (pkt_out, tuser_out) = yield self.pkt_out_pipe.get()
            print '@ {} - Received from storage: {} || {}'.format(self.env.now, pkt_out.summary(), tuser_out)


def main():
    env = simpy.Environment()
    period = 1
    # instantiate the testbench
    ps_tb = Packet_storage_tb(env, period)
    # run the simulation 
    env.run(until=100)


if __name__ == "__main__":
    main()

