#!/usr/bin/env python

import simpy
from hwsim_utils import *
from scapy.all import *

env = simpy.Environment()
period = 1
pipe = simpy.Store(env)
bus_width = 32

pkt = Ether()/IP()/TCP()/'hello there pretty world!!!'
tuser = Tuser(len(pkt), 0b00000001, 0b00000100)
pkt_list = [(pkt, tuser)]*3

master = AXI_S_master(env, period, pipe, bus_width, pkt_list)
slave = AXI_S_slave(env, period, pipe, bus_width)

env.run(until=20)

