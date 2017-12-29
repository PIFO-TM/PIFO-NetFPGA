from __future__ import print_function
import simpy
import random
from statistics import mean
from pifo_simpy import SkipList

class SkipListWrapper(SkipList):
    
    def __init__(self, env, enq_in_pipe, enq_out_pipe, deq_in_pipe, deq_out_pipe, num_sl, period, size, outreg_width, rd_latency, wr_latency):
        super(SkipListWrapper, self).__init__(env, period, size, outreg_width, rd_latency, wr_latency)
        #print ("slw init start")
        self.env = env
        self.num_sl = num_sl
        self.period = period
        self.enq_in_pipe = enq_in_pipe
        self.enq_out_pipe = enq_out_pipe
        self.deq_in_pipe = deq_in_pipe
        self.deq_out_pipe = deq_out_pipe

        self.sl = []
        self.num_entries = 0
        
        for i in range(num_sl):
            self.sl.append(SkipList(env, self.period, size, outreg_width, rd_latency, wr_latency))

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
            #print ("pifo_wrapper enq start:", t1)
            # Select the skip list w/ min number of entries among the ready (not busy) skip lists
            __sel_sl = None
            while __sel_sl == None:
                for i in range(self.num_sl):
                    #print ("slw: i: {} busy: {}".format(i, self.sl[i].busy))
                    if (self.sl[i].busy == 0):
                        if __sel_sl == None:
                            __sel_sl = i
                            min_num_entries = self.sl[i].num_entries
                        else:
                            if self.sl[i].num_entries < min_num_entries:
                                __sel_sl = i
                                min_num_entries = self.sl[i].num_entries
                # All skip lists busy, try again
                if __sel_sl == None:
                    yield self.env.timeout(self.period)
            # Send enqueue request to selected skip list
            self.sl[__sel_sl].enq_in_pipe.put(enq_req)
            yield self.env.timeout(self.period)
            #print ("pifo_wrapper enq end:", self.env.now)
            #self.enq_out_pipe.put((self.env.now - t1, self.sl[__sel_sl].enq_out_pipe))
            self.enq_out_pipe.put(self.env.now - t1)
            self.num_entries += 1

    def dequeue(self):
        while True:
            # wait for dequeue request
            deq_req = yield self.deq_in_pipe.get()
            #print ("wrapper num_entries:", self.num_entries)
            t1 = self.env.now
            if self.num_entries > 0:
                self.num_entries -= 1
            else:
                continue
            sel_sl = None
            while sel_sl == None:
                for i in range(self.num_sl):
                    #print ("deq: i: {}, avail: {}, min: {}".format(i, self.sl[i].avail, self.sl[i].value))
                    if (self.sl[i].avail == 1):
                        if sel_sl == None:
                            sel_sl = i
                            min_value = self.sl[i].value
                        else:
                            if self.sl[i].value < min_value:
                                sel_sl = i
                                min_value = self.sl[i].value
                        #print ("sel_sl: {}, min: {}".format(sel_sl, min_value))
                if sel_sl == None:
                    self.env.timeout(self.period)
            # Send dequeue request to selected skip list
            self.sl[sel_sl].deq_in_pipe.put(deq_req)
            deq_resp = yield self.sl[sel_sl].deq_out_pipe.get()
            self.deq_out_pipe.put(deq_resp)

