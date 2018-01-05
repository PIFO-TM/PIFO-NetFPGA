from __future__ import print_function
import simpy
import random
from statistics import mean
from pifo_wrapper import SkipListWrapper

def test(env):
    NUM_SKIP_LISTS = 2
    PERIOD = 1
    MAX_NODES = 512
    OUTREG_WIDTH = 16
    ENQ_FIFO_DEPTH = 16
    CLK_FREQ = 200 # MHz
    PKT_RATE = 14.8 # MPkts/sec
    PKT_INTERVAL = int(CLK_FREQ/PKT_RATE)
    NumRuns = 1
    NumOps = 128
    enq_nclks_list = []
    deq_nclks_list = []

    enq_in_pipe  = simpy.Store(env)
    enq_out_pipe = simpy.Store(env)
    deq_in_pipe  = simpy.Store(env)
    deq_out_pipe = simpy.Store(env) 

    print ('@ {:04d} - starting skip list init'.format(env.now))

    slw = SkipListWrapper(env, enq_in_pipe, enq_out_pipe, deq_in_pipe, deq_out_pipe, num_sl=NUM_SKIP_LISTS, period=PERIOD, size=MAX_NODES, outreg_width=OUTREG_WIDTH, enq_fifo_depth=ENQ_FIFO_DEPTH, rd_latency=1, wr_latency=1)
    
    for i in range(NUM_SKIP_LISTS):
        while slw.sl[i].busy == 1:
            yield env.timeout(PERIOD)

    print ('@ {:04d} - done skip list init'.format(env.now))
    
    for j in range(NumRuns):
        print ("Run:", j)
        # Enqueue some values and print skip list
        for i in range (NumOps):
            val = random.randint(0,100)
            hsp = mdp = -1
            t1 = env.now
            slw.enq_in_pipe.put((val, hsp, mdp))
            yield slw.enq_out_pipe.get()
            enq_nclks = env.now - t1
            enq_nclks_list.append(enq_nclks)
            print ('enq: {} - {} clks'.format(val, enq_nclks))
            yield env.timeout(PKT_INTERVAL)
        
        for i in range(NUM_SKIP_LISTS):
            while slw.sl[i].enq_fifo.fill_level() != 0 or slw.sl[i].busy == 1:
                yield env.timeout(PERIOD)
        
        # Dequeue all values and print skip list
        while slw.num_entries > 0:
            t1 = env.now
            slw.deq_in_pipe.put(True)
            (val, hsp, mdp, deq_nclks) = yield slw.deq_out_pipe.get()
            deq_nclks = env.now - t1
            print ('deq: {} - {} clks'.format(val, deq_nclks))
            deq_nclks_list.append(deq_nclks)
            yield env.timeout(PKT_INTERVAL)

    # Wait until skip lists are done
    for i in range(NUM_SKIP_LISTS):
        while slw.sl[i].busy == 1:
            yield env.timeout(PERIOD)
        # Stop deq_sl processes
        slw.sl[i].enq_sl_proc.interrupt('Done')
        slw.sl[i].deq_sl_proc.interrupt('Done')

    print ("Time measurements (min, avg, max) for {} runs of {} enq/deq ops".format(NumRuns, NumOps))
    print ("Enq: {:5.2f} {:5.2f} {:5.2f}".format(min(enq_nclks_list), mean(enq_nclks_list), max(enq_nclks_list)))
    print ("Deq: {:5.2f} {:5.2f} {:5.2f}".format(min(deq_nclks_list), mean(deq_nclks_list), max(deq_nclks_list)))


# Main
env = simpy.Environment()
env.process(test(env))
env.run()
