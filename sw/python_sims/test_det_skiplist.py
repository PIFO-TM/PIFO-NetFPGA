from __future__ import print_function
import simpy
import random
from statistics import mean
from det_skip_list_simpy import SkipList


def test(env):
    PERIOD = 1
    MAX_NODES = 512
    RD_LATENCY = 1
    WR_LATENCY = 1
    OUTREG_WIDTH = 4
    ENQ_FIFO_DEPTH = 12
    NumRuns = 1
    NumOps = 32
    enq_nclks_list = []
    deq_nclks_list = []
    tot_search_nclks_list = []
    tot_enq_nclks_list = []
    tot_deq_nclks_list = []

    sl = SkipList(env, period=PERIOD, size=MAX_NODES, outreg_width=OUTREG_WIDTH, enq_fifo_depth=ENQ_FIFO_DEPTH, rd_latency=RD_LATENCY, wr_latency=WR_LATENCY)
    print ('@ {:04d} - starting skip list init'.format(env.now))
    yield env.timeout(50)
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
            yield sl.enq_out_pipe.get()
            enq_nclks = env.now - t1
            enq_nclks_list.append(enq_nclks)
            print ('enq: {} - {} clks'.format(val, enq_nclks))
            while sl.outreg.busy == 1:
                yield env.timeout(PERIOD)
            print (sl.outreg.val)
            yield env.timeout(130*PERIOD)
            while sl.busy == 1 or sl.outreg.busy == 1:
                yield env.timeout(PERIOD)
            print (sl)
        tot_search_nclks_list.extend(sl.bg_search_nclks_list)
        tot_enq_nclks_list.extend(sl.bg_enq_nclks_list)
    
        while sl.enq_fifo.fill_level() != 0 or sl.busy == 1:
            yield env.timeout(PERIOD)
        print ("Free list size:", len(sl.free_node_list.items))

        # Dequeue all values and print skip list
        while sl.num_entries > 0:
            t1 = env.now
            # Wait until out reg has valid data since there's data in the skip list
            while sl.outreg.next_valid == 0:
                yield env.timeout(PERIOD)
            sl.deq_in_pipe.put(True)
            (val, hsp, mdp, deq_nclks) = yield sl.deq_out_pipe.get()
            deq_nclks = env.now - t1
            print ('deq: {} - {} clks'.format(val, deq_nclks))
            print (sl.outreg.val)
            while sl.busy == 1:
                yield env.timeout(PERIOD)
            print (sl)
            deq_nclks_list.append(deq_nclks)
            yield env.timeout(13*PERIOD)
                
        tot_deq_nclks_list.extend(sl.bg_deq_nclks_list)

        print ("Free list size:", len(sl.free_node_list.items))

        del sl.bg_search_nclks_list[:]
        del sl.bg_enq_nclks_list[:]
        del sl.bg_deq_nclks_list[:]

    # Wait until skip list is done
    while sl.busy == 1:
        yield env.timeout(PERIOD)
    # Stop deq_sl process
    sl.enq_sl_proc.interrupt('Done')
    sl.deq_sl_proc.interrupt('Done')

    print ("Time measurements (min, avg, max) for {} runs of {} enq/deq ops".format(NumRuns, NumOps))
    print ("Srch (bg): {:5.2f} {:5.2f} {:5.2f}".format(min(tot_search_nclks_list), mean(tot_search_nclks_list), max(tot_search_nclks_list)))
    print ("Enq  (bg): {:5.2f} {:5.2f} {:5.2f}".format(min(tot_enq_nclks_list), mean(tot_enq_nclks_list), max(tot_enq_nclks_list)))
    print ("Deq  (bg): {:5.2f} {:5.2f} {:5.2f}".format(min(tot_deq_nclks_list), mean(tot_deq_nclks_list), max(tot_deq_nclks_list)))
    print ("Enq  (fg): {:5.2f} {:5.2f} {:5.2f}".format(min(enq_nclks_list), mean(enq_nclks_list), max(enq_nclks_list)))
    print ("Deq  (fg): {:5.2f} {:5.2f} {:5.2f}".format(min(deq_nclks_list), mean(deq_nclks_list), max(deq_nclks_list)))
    
    print ("Free list size:", len(sl.free_node_list.items))

# Main
env = simpy.Environment()
env.process(test(env))
env.run()

