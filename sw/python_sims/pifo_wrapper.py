from __future__ import print_function
import simpy
import random
from statistics import mean
from pifo_skip_list import SkipList

class SkipListWrapper(SkipList):
    
    def __init__(self, env, enq_in_pipe, enq_out_pipe, deq_in_pipe, deq_out_pipe, num_sl, period, size, outreg_width, enq_fifo_depth, rd_latency, wr_latency):
        super(SkipListWrapper, self).__init__(env, period, size, outreg_width, enq_fifo_depth, rd_latency, wr_latency)
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
            self.sl.append(SkipList(env, self.period, size, outreg_width, enq_fifo_depth, rd_latency, wr_latency))

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
            # Select the skip list w/ min number of entries among the ready (not busy) skip lists
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
                # All skip lists busy, try again
                if sel_sl == None:
                    yield self.env.timeout(self.period)
            # Send enqueue request to selected skip list
            self.sl[sel_sl].enq_in_pipe.put(enq_req)
            yield self.env.timeout(self.period)
            self.num_entries += 1
            self.enq_out_pipe.put(self.env.now - t1)

    def dequeue(self):
        while True:
            # wait for dequeue request
            deq_req = yield self.deq_in_pipe.get()
            if self.num_entries > 0:
                self.num_entries -= 1
            else:
                print ("ERROR: Dequeue from empty PIFO!")
                continue
            
            t1 = self.env.now
            # From non-empty skip lists/regs, select the one with the min value
            sel_sl = None
            while sel_sl == None:
                for i in range(self.num_sl):
                    # Wait until out reg has valid data if there's data in the skip list
                    while (self.sl[i].num_entries > 0 and self.sl[i].outreg.next_valid == 0):
                        yield self.env.timeout(self.period)
                    if self.sl[i].outreg.next_valid == 1:
                        if sel_sl == None:
                            sel_sl = i
                            min_value = self.sl[i].outreg.next
                        else:
                            if self.sl[i].outreg.next < min_value:
                                sel_sl = i
                                min_value = self.sl[i].outreg.next
                if sel_sl == None:
                    yield self.env.timeout(self.period)
            # Send dequeue request to selected skip list
            self.sl[sel_sl].deq_in_pipe.put(deq_req)
            (deq_val, deq_hsp, deq_mdp, deq_nclks) = yield self.sl[sel_sl].deq_out_pipe.get()
            # Update deq nclks
            deq_nclks = self.env.now - t1
            self.deq_out_pipe.put((deq_val, deq_hsp, deq_mdp, deq_nclks))

