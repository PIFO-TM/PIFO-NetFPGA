from __future__ import print_function
import simpy
import random
from statistics import mean
from pifo_simpy import SkipList


def test(env):
    PERIOD = 1
    MAX_NODES = 256
    RD_LATENCY = 1
    WR_LATENCY = 1
    OUTREG_WIDTH = 16
    NumRuns = 1
    NumOps = 64
    search_nclks_list = []
    enq_nclks_list = []
    tot_enq_nclks_list = []
    deq_nclks_list = []

    sl = SkipList(env, period=PERIOD, size=MAX_NODES, outreg_width=OUTREG_WIDTH, rd_latency=RD_LATENCY, wr_latency=WR_LATENCY)
    print ('@ {:04d} - starting skip list init'.format(env.now))
    yield env.timeout(45)
    print ('@ {:04d} - done skip list init'.format(env.now))

    for j in range(NumRuns):
        print ("Run:", j)
        print (sl)
        print ("Free list size:", len(sl.free_node_list.items))
        # Enqueue some values and print skip list
        for i in range (NumOps):
            val = random.randint(0,100)
            hsp = mdp = -1
            t1 = env.now
            sl.enq_in_pipe.put((val, hsp, mdp))
            (search_nclks, enq_nclks) = yield sl.enq_out_pipe.get()
            tot_enq_nclks = env.now - t1
            print ('enq: {} - search: {}, enq: {}, tot: {} clks'.format(val, search_nclks, enq_nclks, tot_enq_nclks))
            print (sl.outreg.val)
            while (sl.busy == 1):
                print ("waiting before print")
                yield env.timeout(1)
            print (sl)
            search_nclks_list.append(search_nclks)
            enq_nclks_list.append(enq_nclks)
            tot_enq_nclks_list.append(tot_enq_nclks)
    
        print ("Free list size:", len(sl.free_node_list.items))
        
        # Dequeue all values and print skip list
        while sl.num_entries > 0:
            sl.deq_in_pipe.put(True)
            (val, hsp, mdp, deq_nclks) = yield sl.deq_out_pipe.get()
            print ('deq: {} - {} clks'.format(val, deq_nclks))
            #yield env.timeout(13*PERIOD)
            #print (sl.outreg.val)
            print (sl)
            deq_nclks_list.append(deq_nclks)

    # Wait until skip list is done
    while sl.busy == 1:
        yield env.timeout(PERIOD)
    # Stop deq_sl process
    sl.deq_sl_proc.interrupt('Done')

    print ("Time measurements (min, avg, max) for {} runs of {} enq/deq ops".format(NumRuns, NumOps))
    print ("Search:", min(search_nclks_list), mean(search_nclks_list), max(search_nclks_list))
    print ("Enq:", min(enq_nclks_list), mean(enq_nclks_list), max(enq_nclks_list))
    print ("Tot Enq:", min(tot_enq_nclks_list), mean(tot_enq_nclks_list), max(tot_enq_nclks_list))
    print ("Deq:", min(deq_nclks_list), mean(deq_nclks_list), max(deq_nclks_list))
    
    print ("Free list size:", len(sl.free_node_list.items))

# Main
env = simpy.Environment()
env.process(test(env))
env.run()

