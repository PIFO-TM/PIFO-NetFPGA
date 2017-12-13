#!/usr/bin/env python

import simpy
from pifo_tb import Pifo_tb

def main():
    env = simpy.Environment()
    period = 1
    snd_rate = 1 # Gbps
    fill_level = 10 # pkts in skip list
    pkt_len = 64 # Bytes
    # instantiate the testbench
    ps_tb = Pifo_tb(env, period, snd_rate, fill_level, pkt_len)
    # run the simulation
    env.run(until=10000)


if __name__ == "__main__":
    main()

