#!/usr/bin/env python

import sys, os
from scapy.all import *
from packet_storage import Pkt_storage, Tuser
from random import *

def pad_pkt(pkt, size):
    if len(pkt) >= size:
        return pkt
    else:
        return pkt / ('\x00'*(size - len(pkt)))

def main():
    ps = Pkt_storage()
    pkt_in_list = []
    for i in range(5):
        size = randint(64, 64)
        pkt = Ether(dst="08:11:11:11:11:08", src="08:22:22:22:22:08") / IP(src='10.0.0.2', dst='10.0.0.1') / TCP()
        pkt = pad_pkt(pkt, size)
        src_port = 0b00000100
        dst_port = 0b00000001
        tuser = Tuser(len(pkt), src_port, dst_port)
        pkt_in_list.append((pkt, tuser))

    pkt_ptrs = []
    for pkt, tuser in pkt_in_list:
        print "inserting: {}".format(pkt.summary())
        head_seg_ptr, meta_ptr = ps.insert(pkt, tuser)
        pkt_ptrs.append((head_seg_ptr, meta_ptr))
        print str(ps) + '\n'

    pkt_out_list = []
    for head_seg_ptr, meta_ptr in pkt_ptrs:
        pkt, tuser = ps.remove(head_seg_ptr, meta_ptr)
        pkt_out_list.append((pkt, tuser))
        print str(ps) + '\n'
        
    for (pkt_in, tuser_in), (pkt_out, tuser_out) in zip(pkt_in_list, pkt_out_list):
        print "input  : {} || {} ".format(pkt_in.summary(), tuser_in)
        print "output : {} || {} ".format(pkt_out.summary(), tuser_out)
        print ""

if __name__ == "__main__":
    main()


