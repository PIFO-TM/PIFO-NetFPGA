#!/usr/bin/env python

from tm_hw_sim import TM_hw_sim

def test_num_skip_lists():
    tm_sim = TM_hw_sim('out')
    num_skip_lists = [1, 2, 3, 4]
    tm_sim.test_num_skip_lists(num_skip_lists)

def test_pifo_depth():
    tm_sim = TM_hw_sim('out')
    pifo_depths = [16, 32, 64]
    tm_sim.test_pifo_depth(pifo_depths)


def main():
    test_num_skip_lists()
    #test_pifo_depth()


if __name__ == "__main__":
    main()

