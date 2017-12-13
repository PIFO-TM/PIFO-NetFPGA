
import sys, os, random
import simpy
from scapy.all import *
from hwsim_utils import HW_sim_object, Tuser, pad_pkt
from pifo_top import Pifo_top
from collections import OrderedDict
import numpy as np

MIN_PKT = 64
MAX_PKT = 1500

MAX_RANK = 64

MAX_SEGMENTS = 2048
MAX_PKTS = 2048
NUM_SKIP_LISTS = 5

class Pifo_tb(HW_sim_object):
    """The top level testbench for the PIFO
    """

    def __init__(self, env, period, snd_rate, fill_level, pkt_len=64):
        super(Pifo_tb, self).__init__(env, period)

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

        # number of cycles over which to measure throughput and latency
        self.stat_interval = 1000 # cycles

        # latency measurements
        self.latencies = []

        # Instantiate the top-level Pifo
        self.pifo = Pifo_top(env, period, self.pifo_pkt_in_pipe, self.pifo_pkt_out_pipe, self.pifo_enq_out_pipe, self.pifo_deq_in_pipe, MAX_SEGMENTS, MAX_PKTS, NUM_SKIP_LISTS)

        # register processes for simulation
        self.run()


    def run(self):
        self.env.process(self.generate_pkts())
        self.env.process(self.receive_pkts())


    def generate_pkts(self):
        """Generate scapy pkts and insert into PIFO
        """
        # the last clk cycle at which a pkt was sent
        last_pkt_time = 0
        sched_index = 0
        pkt_schedule = None
        while True:
            yield self.wait_clock()
            if (sched_index == self.pkt_schedule_len or pkt_schedule is None):
                # create the packet schedule so we can send at the appropriate rate
                cycles_per_pkt = (self.pkt_len*8.0*self.clk_rate*1e6)/(self.snd_rate*1e9)
                num_delayed_pkts = int(self.pkt_schedule_len*(cycles_per_pkt - int(cycles_per_pkt)) + 1) 
                delayed_pkts = random.sample(range(self.pkt_schedule_len), num_delayed_pkts)
                pkt_schedule = [int(cycles_per_pkt)+1 if (index in delayed_pkts) else int(cycles_per_pkt) for index in range(self.pkt_schedule_len)]
                sched_index = 0
            if self.env.now > last_pkt_time + pkt_schedule[sched_index]:
                # create pkt and metadata to send
                pkt = Ether()/IP()/TCP()
                pkt = pad_pkt(pkt, self.pkt_len)
                src_port = random.randint(0, (2**8)-1)
                dst_port = random.randint(0, (2**8)-1)
                rank = random.randint(0, MAX_RANK)
                pkt_id = self.pkt_id
                self.pkt_id += 1
                # record time at which pkt was inserted
                self.active_pkts[pkt_id] = self.env.now
                metadata = Tuser(len(pkt), src_port, dst_port, rank, pkt_id)
#                print '@{} - sending pkt: {}'.format(self.env.now, pkt.summary())
                # insert pkt into PIFO
                self.pifo_pkt_in_pipe.put((pkt, metadata))
                # move forward in the schedule
                sched_index += 1
                last_pkt_time = self.env.now
#                # wait for enqueue to complete, TODO: remove this delay!
#                enq_nclks = yield self.pifo_enq_out_pipe.get()

    def receive_pkts(self):
        """Receive pkts from PIFO
        """
        last_interval = 0
        rcvd_bytes = 0
        while True:
            # only submit read requests if the skip list is full enough
            if self.pifo.skip_list_wrapper.num_entries >= self.fill_level:
                # submit read request 
                self.pifo_deq_in_pipe.put(1)

                # wait to receive a response
                (pkt_out, meta_out) = yield self.pifo_pkt_out_pipe.get()
    
                if pkt_out is not None and meta_out is not None:
                    rcv_time = self.env.now
                    pkt_id = meta_out.pkt_id
                    snd_time = self.active_pkts.pop(pkt_id)
                    self.latencies.append(rcv_time - snd_time)
                    rcvd_bytes += len(pkt_out)
                    if self.env.now > last_interval + self.stat_interval:
                        # report stats
                        rate = rcvd_bytes*self.clk_rate*1e6*8/(float(self.stat_interval)*1e9)
                        print '@ {} - # pkts received = {}'.format(self.env.now, len(self.latencies))
                        print '@ {} - avg output rate = {} Gbps'.format(self.env.now, rate)
                        latencies = np.array(self.latencies)
                        print '@ {} - avg latency = {} cycles, max = {} cycles'.format(self.env.now, np.average(latencies), np.max(latencies))
                        # reset state
                        self.latencies = []
                        last_interval = rcv_time
                        rcvd_bytes = 0
                else:
                    print '@{} - pifo_tb: receive_pkts: pkt_out = {}, meta_out = {}'
            else:
                yield self.wait_clock()


