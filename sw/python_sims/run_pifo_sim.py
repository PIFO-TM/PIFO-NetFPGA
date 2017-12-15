#!/usr/bin/env python

from pifo_sim import Pifo_sim

def test_fill_level():
    psim = Pifo_sim('out')
    levels = range(1, 200, 20)
    pkt_len = 64
    num_skipLists = 1
    psim.test_fill_level(levels, pkt_len, num_skipLists)

def test_num_skipLists():
    psim = Pifo_sim('out')
    level = 100
    pkt_len = 64
    num_skipLists = range(1, 20, 2)
    psim.test_num_skipLists(level, pkt_len, num_skipLists)

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


def main():
    test_fill_level()
    #test_num_skipLists()
    #test_pkt_len()
    #test_mem_latency()


if __name__ == "__main__":
    main()

