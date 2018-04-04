#!/usr/bin/env python

from tm_hw_sim import TM_hw_sim

OUT_DIR = 'out'

def test_num_skip_lists():
    tm_sim = TM_hw_sim(OUT_DIR)
    num_skip_lists = range(1,13)
    tm_sim.test_num_skip_lists(num_skip_lists)

def test_pifo_depth():
    tm_sim = TM_hw_sim(OUT_DIR)
    pifo_depths = [16, 32, 64]
    tm_sim.test_pifo_depth(pifo_depths)

def test_reg_depth():
    tm_sim = TM_hw_sim(OUT_DIR)
    reg_depths = range(1,64,4) 
    tm_sim.test_pifo_reg_depth(reg_depths)

def test_fill_level():
    tm_sim = TM_hw_sim(OUT_DIR)
    fill_levels = range(1, 34, 2)
    #fill_levels = range(1, 64, 4)
    tm_sim.test_fill_level(fill_levels)

def main():
    #test_num_skip_lists()
    #test_pifo_depth()
    #test_reg_depth()
    test_fill_level()

if __name__ == "__main__":
    main()

