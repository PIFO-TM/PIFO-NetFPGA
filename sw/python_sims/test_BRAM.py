#!/usr/bin/env python

import simpy
from hwsim_utils import HW_sim_object, BRAM

"""
Testbench for the BRAM object
"""
class BRAM_tb(HW_sim_object):
    def __init__(self, env, period):
        super(BRAM_tb, self).__init__(env, period)

        # create the pipes used for communication with the BRAM object
        self.bram_r_in_pipe = simpy.Store(env)
        self.bram_r_out_pipe = simpy.Store(env)
        self.bram_w_in_pipe = simpy.Store(env)
        self.bram_w_out_pipe = simpy.Store(env)

        # instantiate the BRAM object
        self.bram = BRAM(env, period, self.bram_r_in_pipe, self.bram_r_out_pipe, self.bram_w_in_pipe, self.bram_w_out_pipe, depth=128, write_latency=2, read_latency=2)

        self.run()

    def run(self):
        """
        Register the testbench's processes with the simulation environment
        """
        self.env.process(self.rw_bram_sm())

    def rw_bram_sm(self):
        """
        State machine to write all test items then read them back
        """
        addresses = range(10)
        items = range(10)

        # write all items
        for (addr, item) in zip(addresses, items):
            print '@ {:04d} - writing item {} to address {}'.format(self.env.now, item, addr)
            self.bram_w_in_pipe.put((addr, item))
            yield self.bram_w_out_pipe.get()

        # read all items
        for addr in addresses:
            # submit read request
            self.bram_r_in_pipe.put(addr)
            item = yield self.bram_r_out_pipe.get()
            print '@ {:04d} - received item {} from address {}'.format(self.env.now, item, addr)


def main():
    # create the simulation environment
    env = simpy.Environment()
    period = 1 # amount of simulation time / clock cycle
    bram_tb = BRAM_tb(env, period)
 
    # run the simulation for 100 simulation seconds (100 clock cycles)
    env.run(until=100)


if __name__ == "__main__":
    main()

