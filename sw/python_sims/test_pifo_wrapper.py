from __future__ import print_function
import simpy
import random
from statistics import mean
from pifo_wrapper import SkipListWrapper

def test(env):
    NUM_SKIP_LISTS = 4
    PERIOD = 1
    MAX_NODES = 512
    OUTREG_WIDTH = 2
    CLK_FREQ = 200 # MHz
    PKT_RATE = 14.8 # MPkts/sec
    PKT_INTERVAL = int(CLK_FREQ/PKT_RATE)
    NumRuns = 10
    NumOps = 128
    enq_nclks_list = []
    deq_nclks_list = []

    enq_in_pipe  = simpy.Store(env)
    enq_out_pipe = simpy.Store(env)
    deq_in_pipe  = simpy.Store(env)
    deq_out_pipe = simpy.Store(env) 
    
    slw = SkipListWrapper(env, enq_in_pipe, enq_out_pipe, deq_in_pipe, deq_out_pipe, num_sl=NUM_SKIP_LISTS, period=PERIOD, size=MAX_NODES, outreg_width=OUTREG_WIDTH, rd_latency=1, wr_latency=1)
    
    print ('@ {:04d} - starting skip list init'.format(env.now))
    yield env.timeout(50)
    print ('@ {:04d} - done skip list init'.format(env.now))
    
    for j in range(NumRuns):
        print ("Run:", j)
        # Enqueue some values and print skip list
        for i in range (NumOps):
            val = random.randint(0,100)
            hsp = mdp = -1
            slw.enq_in_pipe.put((val, hsp, mdp))
            enq_nclks = yield slw.enq_out_pipe.get()
            enq_nclks_list.append(enq_nclks)
            print ('enq: {} - {} clks'.format(val, enq_nclks))
            yield env.timeout(PKT_INTERVAL)
        
        #yield env.timeout(100)
        
        # Dequeue all values and print skip list
        while slw.num_entries > 0:
            slw.deq_in_pipe.put(True)
            (val, hsp, mdp, deq_nclks) = yield slw.deq_out_pipe.get()
            print ('deq: {} - {} clks'.format(val, deq_nclks))
            deq_nclks_list.append(deq_nclks)
            yield env.timeout(PKT_INTERVAL)

    # Wait until skip lists are done
    for i in range(NUM_SKIP_LISTS):
        while slw.sl[i].busy == 1:
            yield env.timeout(PERIOD)
            # Stop deq_sl processes
        slw.sl[i].deq_sl_proc.interrupt('Done')

    print ("Time measurements (min, avg, max) for {} runs of {} enq/deq ops".format(NumRuns, NumOps))
    print ("Enq:", min(enq_nclks_list), mean(enq_nclks_list), max(enq_nclks_list))
    print ("Deq:", min(deq_nclks_list), mean(deq_nclks_list), max(deq_nclks_list))


# Main
env = simpy.Environment()
env.process(test(env))
env.run()
