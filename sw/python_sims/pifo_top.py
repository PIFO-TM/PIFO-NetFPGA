
"""
This is the top level module that combines together the packet storage
and top level skip list
"""

import simpy
from hwsim_utils import HW_sim_object, Tuser
from packet_storage import Pkt_storage
from pifo_wrapper import SkipListWrapper

class Pifo_top(HW_sim_object):

    def __init__(self, env, period, pkt_in_pipe, pkt_out_pipe, enq_out_pipe, deq_in_pipe, max_segments, max_pkts, num_skip_lists, outreg_width, rd_latency=1, wr_latency=1):
        super(Pifo_top, self).__init__(env, period)

        # Pipes to pass packets around
        self.top_pkt_in_pipe = pkt_in_pipe
        self.top_pkt_out_pipe = pkt_out_pipe
        self.ps_pkt_in_pipe = simpy.Store(env)

        # Pipes to R/W ptrs from/to pkt storage 
        self.ps_ptr_in_pipe = simpy.Store(env)
        self.ps_ptr_out_pipe = simpy.Store(env)

        # Pipes to R/W ptrs from/to skip list 
        self.sl_enq_in_pipe = simpy.Store(env)
        self.sl_enq_out_pipe = enq_out_pipe
        self.top_deq_in_pipe = deq_in_pipe
        self.sl_deq_out_pipe = simpy.Store(env)

        # Instantiate the Packet Storage
        self.pkt_store = Pkt_storage(env, period, self.ps_pkt_in_pipe, self.top_pkt_out_pipe, self.ps_ptr_in_pipe, self.ps_ptr_out_pipe, max_segments, max_pkts, rd_latency=rd_latency, wr_latency=wr_latency)

        # Instantiate the top-level Skip List
        self.skip_list_wrapper = SkipListWrapper(env, self.sl_enq_in_pipe, self.sl_enq_out_pipe, self.top_deq_in_pipe, self.sl_deq_out_pipe, num_sl=num_skip_lists, period=period, size=max_pkts, outreg_width=outreg_width, rd_latency=rd_latency, wr_latency=wr_latency)

        # register processes for simulation
        self.run()


    def run(self):
        self.env.process(self.write_pkt())
        self.env.process(self.read_pkt())


    def write_pkt(self):
        """Write incomming packet into packet storage and skip list
        """
        while True:
            # wait to receive incomming pkt and metadata
            (pkt_in, meta_in) = yield self.top_pkt_in_pipe.get()
            rank = meta_in.rank

            # write incomming pkt and metadata into storage
            self.ps_pkt_in_pipe.put((pkt_in, meta_in))

            # wait to receive ptrs from packet storage
            (head_seg_ptr, meta_ptr) = yield self.ps_ptr_out_pipe.get()

            # write rank, head_seg_ptr, and meta_ptr into skip list
            self.sl_enq_in_pipe.put((rank, head_seg_ptr, meta_ptr))

    def read_pkt(self):
        """Read out any available packets
        """
        while True:
            # wait to receive head_seg_ptr and meta_ptr from skipList
            (rank, head_seg_ptr, meta_ptr, deq_nclks) = yield self.sl_deq_out_pipe.get()
            # TODO: want to do anything with the deq_n_clks data?

            # submit read request to storage
            self.ps_ptr_in_pipe.put((head_seg_ptr, meta_ptr))


