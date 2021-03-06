#!/usr/bin/env python

from pifo_sim import Pifo_sim

def test_fill_level():
    psim = Pifo_sim('out')
    levels = range(1, 200, 5)
    pkt_len = 64
    num_skipLists = 1
    psim.test_fill_level(levels, pkt_len, num_skipLists)

def test_num_skipLists():
    psim = Pifo_sim('out')
#    level = 100
    level = None
    pkt_len = 64
    outreg_width = 16
    enq_fifo_depth = 16
    sl_impls = ['det']
    num_skipLists = range(1, 20, 1)
#    num_skipLists = range(10, 12)
    outreg_latency = 1
    psim.test_num_skipLists(level, pkt_len, num_skipLists, outreg_width, enq_fifo_depth, sl_impls, outreg_latency)

def test_outreg_latency():
    psim = Pifo_sim('out')
#    level = 100
    level = None
    pkt_len = 64
    outreg_width = 16
    enq_fifo_depth = 16
    sl_impls = ['det']
    num_skipLists = 5 
    outreg_latencies = range(1, 30, 2)
    psim.test_outreg_latency(level, pkt_len, num_skipLists, outreg_width, enq_fifo_depth, sl_impls, outreg_latencies)

def test_pkt_len():
    psim = Pifo_sim('out')
    level = 100
    pkt_len = range(64, 1000, 100)
    num_skipLists = 5
    psim.test_pkt_len(level, pkt_len, num_skipLists)

def test_mem_latency():
    psim = Pifo_sim('out')
    level = 10
    pkt_len = 64
    num_skipLists = 5
    mem_latencies = range(1,7)
    psim.test_mem_latency(level, pkt_len, num_skipLists, mem_latencies)

def test_outreg_width():
    psim = Pifo_sim('out')
    level = None # do not use specific fill level 
    pkt_len = 64
    num_skipLists = 5
    outreg_widths = range(1,16,1)
    enq_fifo_depth = 16
    sl_impls = ['det']
    outreg_latency = 1
    psim.test_outreg_width(level, pkt_len, num_skipLists, outreg_widths, enq_fifo_depth, sl_impls)

def main():
    #test_fill_level()
    #test_num_skipLists()
    #test_outreg_latency()
    #test_pkt_len()
    #test_mem_latency()
    test_outreg_width()


if __name__ == "__main__":
    main()

