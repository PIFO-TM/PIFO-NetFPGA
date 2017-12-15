#!/usr/bin/env python

import simpy
from pifo_tb import Pifo_tb

def main():
    env = simpy.Environment()
    period = 1
    snd_rate = 5 # Gbps  # TODO: this is disabled for now. Testbench will just send a pkt when it sees fill level is too low
    fill_level = 64 # pkts in skip list
    pkt_len = 64 # Bytes
    num_skipLists = 5
    # instantiate the testbench
    ps_tb = Pifo_tb(env, period, snd_rate, fill_level, pkt_len, num_skipLists)
    # run the simulation
    env.run(until=100000)


if __name__ == "__main__":
    main()

