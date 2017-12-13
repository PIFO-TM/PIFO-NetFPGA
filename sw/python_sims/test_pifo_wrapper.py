from __future__ import print_function
import simpy
import random
from statistics import mean
from pifo_wrapper import SkipListWrapper

def test(env):
    NUM_SKIP_LISTS = 3
    PERIOD = 1
    MAX_NODES = 256
    CLK_FREQ = 200 # MHz
    PKT_RATE = 14.8 # MPkts/sec
    PKT_INTERVAL = int(CLK_FREQ/PKT_RATE)
    NumRuns = 50
    NumOps = 64
    enq_nclks_list = []
    deq_nclks_list = []

    enq_in_pipe  = simpy.Store(env)
    enq_out_pipe = simpy.Store(env)
    deq_in_pipe  = simpy.Store(env)
    deq_out_pipe = simpy.Store(env) 
    
    slw = SkipListWrapper(env, enq_in_pipe, enq_out_pipe, deq_in_pipe, deq_out_pipe, num_sl=NUM_SKIP_LISTS, period=PERIOD, size=MAX_NODES)
    print ('@ {:04d} - starting skip list init'.format(env.now))
    yield env.timeout(40)
    print ('@ {:04d} - done skip list init'.format(env.now))
    
    for j in range(NumRuns):
        print ("Run:", j)
        # Enqueue some values and print skip list
        for i in range (NumOps):
            val = random.randint(0,100)
            hsp = mdp = -1
            t1 = env.now
            slw.enq_in_pipe.put((val, hsp, mdp))
            enq_nclks = yield slw.enq_out_pipe.get()
            enq_nclks_list.append(enq_nclks)
            print ('enq: {} - {} clks'.format(val, enq_nclks))
            yield env.timeout(PKT_INTERVAL)
        
        # Dequeue all values and print skip list
        while slw.num_entries > 0:
            slw.deq_in_pipe.put(True)
            (val, hsp, mdp, deq_nclks) = yield slw.deq_out_pipe.get()
            print ('deq: {} - {} clks'.format(val, deq_nclks))
            deq_nclks_list.append(deq_nclks)
            yield env.timeout(PKT_INTERVAL)

    print ("Time measurements (min, avg, max) for {} runs of {} enq/deq ops".format(NumRuns, NumOps))
    print ("Enq:", min(enq_nclks_list), mean(enq_nclks_list), max(enq_nclks_list))
    print ("Deq:", min(deq_nclks_list), mean(deq_nclks_list), max(deq_nclks_list))


# Main
env = simpy.Environment()
env.process(test(env))
env.run()
