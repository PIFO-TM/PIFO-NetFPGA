from __future__ import print_function
import simpy
import random
from statistics import mean
from pifo_simpy import SkipList

NUM_SKIP_LISTS = 5
PERIOD = 1
NUM_NODES = 128

class SkipListWrapper(SkipList):
    def __init__(self, env, enq_in_pipe, enq_out_pipe, deq_in_pipe, deq_out_pipe, num_sl=NUM_SKIP_LISTS, period=PERIOD, size=NUM_NODES):
        super(SkipListWrapper, self).__init__(env, period, size)
        self.env = env
        self.num_sl = num_sl
        self.enq_in_pipe = enq_in_pipe
        self.enq_out_pipe = enq_out_pipe
        self.deq_in_pipe = deq_in_pipe
        self.deq_out_pipe = deq_out_pipe

        self.sl = []
        self.num_entries = 0
        
        for i in range(num_sl):
            self.sl.append(SkipList(env, period, size))

        # register processes for simulation
        self.run(env)

    def run(self, env):
        self.env.process(self.enqueue())
        self.env.process(self.dequeue())

    def enqueue(self):
        while True:
            # wait for enqueue command
            enq_req = yield self.enq_in_pipe.get()
            t1 = self.env.now
            sel_sl = None
            while sel_sl == None:
                for i in range(self.num_sl):
                    if (self.sl[i].busy == 0):
                        if sel_sl == None:
                            sel_sl = i
                            min_num_entries = self.sl[i].num_entries
                        else:
                            if self.sl[i].num_entries < min_num_entries:
                                sel_sl = i
                                min_num_entries = self.sl[i].num_entries
                if sel_sl == None:
                    yield self.env.timeout(PERIOD)
            self.sl[sel_sl].enq_in_pipe.put(enq_req)
            self.enq_out_pipe.put(self.env.now - t1)
            self.num_entries += 1


    def dequeue(self):
        while True:
            # wait for dequeue request
            deq_req = yield self.deq_in_pipe.get()
            t1 = self.env.now
            sel_sl = None
            while sel_sl == None:
                for i in range(self.num_sl):
                    if (self.sl[i].avail == 1):
                        if sel_sl == None:
                            sel_sl = i
                            min_value = self.sl[i].value
                        else:
                            if self.sl[i].value < min_value:
                                sel_sl = i
                                min_value = self.sl[i].value
                if sel_sl == None:
                    self.env.timeout(PERIOD)
            self.num_entries -= 1
            self.sl[sel_sl].deq_in_pipe.put(deq_req)
            deq_resp = yield self.sl[sel_sl].deq_out_pipe.get()
            self.deq_out_pipe.put(deq_resp)
