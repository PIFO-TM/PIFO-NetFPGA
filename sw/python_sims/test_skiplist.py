from __future__ import print_function
import simpy
import random
from statistics import mean
from pifo_simpy import SkipList


def test(env):
    PERIOD = 1
    MAX_NODES = 128
    NumRuns = 2
    NumOps = 32
    search_nclks_list = []
    enq_nclks_list = []
    tot_enq_nclks_list = []
    deq_nclks_list = []

    sl = SkipList(env, period=PERIOD, size=MAX_NODES)
    print ('@ {:04d} - starting skip list init'.format(env.now))
    yield env.timeout(40)
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
            print (sl)
            search_nclks_list.append(search_nclks)
            enq_nclks_list.append(enq_nclks)
            tot_enq_nclks_list.append(tot_enq_nclks)
    
        print ("Free list size:", len(sl.free_node_list.items))
        
        # Dequeue all values and print skip list
        while sl.numEntries > 0:
            sl.deq_in_pipe.put(True)
            (val, hsp, mdp, deq_nclks) = yield sl.deq_out_pipe.get()
            print ('deq: {} - {} clks'.format(val, deq_nclks))
            print (sl)
            deq_nclks_list.append(deq_nclks)

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

