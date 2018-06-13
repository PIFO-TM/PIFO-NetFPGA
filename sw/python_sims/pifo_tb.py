
import sys, os, random
import simpy
from scapy.all import *
from hwsim_utils import HW_sim_object, Tuser, pad_pkt
from pifo_top import Pifo_top
from collections import OrderedDict
import numpy as np

WRITE_DELAY = 100
READ_DELAY = 100

MIN_PKT = 64
MAX_PKT = 1500

MAX_RANK = 64

MAX_SEGMENTS = 2048
MAX_PKTS = 2048

WARM_UP_PKTS = 1

class Pifo_tb(HW_sim_object):
    """The top level testbench for the PIFO
    """

    def __init__(self, env, period, snd_rate, fill_level, pkt_len, num_skipLists, num_samples, outreg_width, enq_fifo_depth, rd_latency=1, wr_latency=1, sl_impl='det', outreg_latency=1):
        super(Pifo_tb, self).__init__(env, period)

        self.num_samples = num_samples
        self.num_skipLists = num_skipLists
        self.sim_complete = False
        
        # Pkt in/out pipes
        self.pifo_pkt_in_pipe = simpy.Store(env)
        self.pifo_pkt_out_pipe = simpy.Store(env)

        # Pipe to read the enqueue stats
        self.pifo_enq_out_pipe = simpy.Store(env)

        # Pipe to submit read requests to Pifo
        self.pifo_deq_in_pipe = simpy.Store(env)

        # rate at which to send pkts into the Pifo (Gbps)
        self.snd_rate = snd_rate

        # desired fill level of the skip_list
        self.fill_level = fill_level # number of entries

        # clock rate (MHz)
        self.clk_rate = 200

        # length of pkts to send
        self.pkt_len = pkt_len

        # number of packets in a single schedule
        self.pkt_schedule_len = 100

        # State for statistics
        self.pkt_id = 0
        self.active_pkts = OrderedDict()

        # bool to indicate that dequeuing should start
        self.start_deq = False

        # latency measurements
        self.enq_latencies = []
        self.deq_latencies = []

        # Instantiate the top-level Pifo
        self.pifo = Pifo_top(env, period, self.pifo_pkt_in_pipe, self.pifo_pkt_out_pipe, self.pifo_enq_out_pipe, self.pifo_deq_in_pipe, MAX_SEGMENTS, MAX_PKTS, num_skipLists, outreg_width, enq_fifo_depth, rd_latency=rd_latency, wr_latency=wr_latency, sl_impl=sl_impl, outreg_latency=outreg_latency)

        # determine whether we want to gen/read pkts such that a constant fill level is maintained
        const_fill_level = True
        if fill_level is None:
            const_fill_level = False

        # register processes for simulation
        self.run(const_fill_level)


    def run(self, const_fill_level):
        self.env.process(self.generate_pkts(const_fill_level))
        self.env.process(self.receive_pkts(const_fill_level))


    def generate_pkts(self, const_fill_level):
        """Generate scapy pkts and insert into PIFO
        """
        # the last clk cycle at which a pkt was sent
        last_pkt_time = 0
        sched_index = 0
        pkt_schedule = None
        last_rank = None
        while not self.sim_complete:
            yield self.wait_clock()
#            if (sched_index == self.pkt_schedule_len or pkt_schedule is None):
#                # create the packet schedule so we can send at the appropriate rate
#                cycles_per_pkt = (self.pkt_len*8.0*self.clk_rate*1e6)/(self.snd_rate*1e9)
#                num_delayed_pkts = int(self.pkt_schedule_len*(cycles_per_pkt - int(cycles_per_pkt)) + 1) 
#                delayed_pkts = random.sample(range(self.pkt_schedule_len), num_delayed_pkts)
#                pkt_schedule = [int(cycles_per_pkt)+1 if (index in delayed_pkts) else int(cycles_per_pkt) for index in range(self.pkt_schedule_len)]
#                sched_index = 0
#            if self.env.now > last_pkt_time + pkt_schedule[sched_index]:

            # send a packet if the not at the desired fill level
            num_entries = self.pifo.skip_list_wrapper.num_entries

            # check condition to generate new pkt
            if not const_fill_level and self.pkt_id < self.num_samples + WARM_UP_PKTS:
                gen_pkt = True
            elif const_fill_level and num_entries < self.fill_level:
                gen_pkt = True
                yield self.env.timeout(WRITE_DELAY)
            else:
                gen_pkt = False

            if gen_pkt:
                # create pkt and metadata to send
                pkt = Ether()/IP()/TCP()
                pkt = pad_pkt(pkt, self.pkt_len)
                src_port = random.randint(0, (2**8)-1)
                dst_port = random.randint(0, (2**8)-1)
                rank = random.randint(0, MAX_RANK)
                pkt_id = self.pkt_id
                self.pkt_id += 1
                metadata = Tuser(len(pkt), src_port, dst_port, rank, pkt_id)
#                print '@{} - sending pkt: {}'.format(self.env.now, pkt.summary())

                start_time = self.env.now
                # insert pkt into PIFO
                self.pifo_pkt_in_pipe.put((pkt, metadata))
                # move forward in the schedule
                sched_index += 1
                last_pkt_time = self.env.now
                # wait for enqueue to complete
                #(slw_enq_nclks, sl_enq_out_pipe) = yield self.pifo_enq_out_pipe.get()
                slw_enq_nclks = yield self.pifo_enq_out_pipe.get()
                # wait for selected skip list to complete enqueue
                #yield sl_enq_out_pipe.get()
                end_time = self.env.now

                enq_nclks = end_time - start_time

#                if enq_nclks > 30:
#                    print 'enq_nclks > 30, after inserting rank = {}, cur pkt_id = {}'.format(last_rank, self.pkt_id)
#                    for sl_id, sl in zip(range(len(self.pifo.skip_list_wrapper.sl)), self.pifo.skip_list_wrapper.sl):
#                        print '-----------------------------------'
#                        print 'sl id = {}'.format(sl_id)
#                        print sl
#                last_rank = rank

                if not const_fill_level:
                    # record enq delay for all but the first pkt
                    if pkt_id != 0:
                        self.active_pkts[pkt_id] = enq_nclks
                    # start dequeuing when all pkts have been sent
                    if self.pkt_id >= self.num_samples + WARM_UP_PKTS:
                        self.start_deq = True
                elif const_fill_level and num_entries == self.fill_level - 1:
                    # record enq delay for only pkts dequeued at the desired fill level
                    self.active_pkts[pkt_id] = enq_nclks



    def receive_pkts(self, const_fill_level):
        """Receive pkts from PIFO
        """
        while not self.sim_complete:
            # check condition to submit read request
            if not const_fill_level and self.start_deq:
                read_pkt = True
            elif const_fill_level and self.pifo.skip_list_wrapper.num_entries >= self.fill_level:
                read_pkt = True
                yield self.env.timeout(READ_DELAY)
            else:
                read_pkt = False

            if read_pkt:
                start_time = self.env.now
                # submit read request 
                self.pifo_deq_in_pipe.put(1)

                # wait to receive a response
                (pkt_out, meta_out) = yield self.pifo_pkt_out_pipe.get()
                end_time = self.env.now
                deq_nclks = end_time - start_time    

                if pkt_out is not None and meta_out is not None:
                    rcv_time = self.env.now
                    pkt_id = meta_out.pkt_id
                    enq_nclks = self.active_pkts.pop(pkt_id, None)
                    # only care about packets for which we have recorded enq delay
                    if enq_nclks is not None:
                        self.enq_latencies.append(enq_nclks)
                        self.deq_latencies.append(deq_nclks)
                        self.sim_complete = len(self.enq_latencies) >= self.num_samples
                else:
                    print '@{} - pifo_tb: receive_pkts: pkt_out = {}, meta_out = {}'
            else:
                yield self.wait_clock()

        # Wait until skip lists are done
        for i in range(self.num_skipLists):
            while self.pifo.skip_list_wrapper.sl[i].busy == 1:
                yield self.wait_clock()
            # Stop deq_sl processes
            self.pifo.skip_list_wrapper.sl[i].enq_sl_proc.interrupt('Done')
            self.pifo.skip_list_wrapper.sl[i].deq_sl_proc.interrupt('Done')

