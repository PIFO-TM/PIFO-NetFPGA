#!/usr/bin/env python

#
# Copyright (c) 2017 Stephen Ibanez
# All rights reserved.
#
# This software was developed by Stanford University and the University of Cambridge Computer Laboratory 
# under National Science Foundation under Grant No. CNS-0855268,
# the University of Cambridge Computer Laboratory under EPSRC INTERNET Project EP/H040536/1 and
# by the University of Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249 ("MRC2"), 
# as part of the DARPA MRC research programme.
#
# @NETFPGA_LICENSE_HEADER_START@
#
# Licensed to NetFPGA C.I.C. (NetFPGA) under one or more contributor
# license agreements.  See the NOTICE file distributed with this work for
# additional information regarding copyright ownership.  NetFPGA licenses this
# file to you under the NetFPGA Hardware-Software License, Version 1.0 (the
# "License"); you may not use this file except in compliance with the
# License.  You may obtain a copy of the License at:
#
#   http://www.netfpga-cic.org
#
# Unless required by applicable law or agreed to in writing, Work distributed
# under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
# CONDITIONS OF ANY KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations under the License.
#
# @NETFPGA_LICENSE_HEADER_END@
#


from nf_sim_tools import *
import random
from collections import OrderedDict
import sss_sdnet_tuples

###########
# pkt generation tools
###########

pktsApplied = []
pktsExpected = []

# Pkt lists for SUME simulations
nf_applied = OrderedDict()
nf_applied[0] = []
nf_applied[1] = []
nf_applied[2] = []
nf_applied[3] = []
nf_expected = OrderedDict()
nf_expected[0] = []
nf_expected[1] = []
nf_expected[2] = []
nf_expected[3] = []

nf_port_map = {"nf0":0b00000001, "nf1":0b00000100, "nf2":0b00010000, "nf3":0b01000000, "dma0":0b00000010}
nf_id_map = {"nf0":0, "nf1":1, "nf2":2, "nf3":3}

sss_sdnet_tuples.clear_tuple_files()

pktTime = 0

def applyPkt(pkt, ingress):
    global pktTime
    pktsApplied.append(pkt)
    sss_sdnet_tuples.sume_tuple_in['pkt_len'] = len(pkt) 
    sss_sdnet_tuples.sume_tuple_in['src_port'] = nf_port_map[ingress]
    sss_sdnet_tuples.sume_tuple_expect['pkt_len'] = len(pkt) 
    sss_sdnet_tuples.sume_tuple_expect['src_port'] = nf_port_map[ingress]
    pkt.time = pktTime
    pktTime += 1
    nf_applied[nf_id_map[ingress]].append(pkt)

def expPkt(pkt, egress):
    pktsExpected.append(pkt)
    sss_sdnet_tuples.sume_tuple_expect['dst_port'] = nf_port_map[egress]
    sss_sdnet_tuples.write_tuples()
    if egress in ["nf0","nf1","nf2","nf3"]:
        nf_expected[nf_id_map[egress]].append(pkt)
    elif egress == 'bcast':
        nf_expected[0].append(pkt)
        nf_expected[1].append(pkt)
        nf_expected[2].append(pkt)
        nf_expected[3].append(pkt)

def write_pcap_files():
    wrpcap("src.pcap", pktsApplied)
    wrpcap("dst.pcap", pktsExpected)

    for i in nf_applied.keys():
        if (len(nf_applied[i]) > 0):
            wrpcap('nf{0}_applied.pcap'.format(i), nf_applied[i])

    for i in nf_expected.keys():
        if (len(nf_expected[i]) > 0):
            wrpcap('nf{0}_expected.pcap'.format(i), nf_expected[i])

    for i in nf_applied.keys():
        print "nf{0}_applied times: ".format(i), [p.time for p in nf_applied[i]]

#####################
# generate testdata #
#####################

def lookup_q_id(rank):
    if rank < (1 << 6):
        return 0
    elif rank < (1 << 11):
        return 1
    elif rank < (1 << 16):
        return 2
    else:
        return 0

dport = 1
init_seqNo = 12345
tos = 0x08
nf_MAC_map = {'nf0': '08:11:11:11:11:08', 'nf1': '08:22:22:22:22:08'}
nf_IP_map = {'nf0': '10.0.0.1', 'nf1': '10.0.0.2'}
tos_len_map = {0x08: 1000000}

# Test 1: SYN packet, towards nf0, dport=1, seqNo = 12345, tos=0x08 (1MB),
#   Expected: srpt_rank = 0, dst_port = nf0, log_pkt = 1
pkt = Ether(dst=nf_MAC_map['nf0'], src=nf_MAC_map['nf1']) / IP(tos=tos, src=nf_IP_map['nf1'], dst=nf_IP_map['nf0']) / TCP(dport=dport, seq=init_seqNo, flags='S')
pkt = pad_pkt(pkt, 64)
applyPkt(pkt, 'nf1')
sss_sdnet_tuples.sume_tuple_expect['bp_count'] = 0
sss_sdnet_tuples.sume_tuple_expect['rank_op'] = 0
srpt_rank = 0
sss_sdnet_tuples.sume_tuple_expect['srpt_rank'] = srpt_rank
sss_sdnet_tuples.sume_tuple_expect['q_id'] = lookup_q_id(srpt_rank)
sss_sdnet_tuples.sume_tuple_expect['log_pkt'] = 1
expPkt(pkt, 'nf0')

# Test 2: ACK packet, towards nf0, dport=1, seqNo = 12345 + 1024, tos=0x08 (1MB) 
#   Expected: srpt_rank = (1000000 - 1024) >> 6, dst_port = nf0, log_pkt = 0
pkt = Ether(dst=nf_MAC_map['nf0'], src=nf_MAC_map['nf1']) / IP(tos=tos, src=nf_IP_map['nf1'], dst=nf_IP_map['nf0']) / TCP(dport=dport, seq=init_seqNo+1024, flags='A')
pkt = pad_pkt(pkt, 1024)
applyPkt(pkt, 'nf1')
sss_sdnet_tuples.sume_tuple_expect['bp_count'] = 0
sss_sdnet_tuples.sume_tuple_expect['rank_op'] = 0
srpt_rank = (tos_len_map[tos] - 1024) >> 16
sss_sdnet_tuples.sume_tuple_expect['srpt_rank'] = srpt_rank
sss_sdnet_tuples.sume_tuple_expect['q_id'] = lookup_q_id(srpt_rank)
sss_sdnet_tuples.sume_tuple_expect['log_pkt'] = 0
expPkt(pkt, 'nf0')

# Test 3: SYN packet, towards nf1, dport=1, seqNo = 54321, tos=0x08 (1MB) 
#   Expected: srpt_rank = 0, dst_port = nf1, log_pkt = 1
pkt = Ether(dst=nf_MAC_map['nf1'], src=nf_MAC_map['nf0']) / IP(tos=tos, src=nf_IP_map['nf0'], dst=nf_IP_map['nf1']) / TCP(dport=dport, seq=54321, flags='S')
pkt = pad_pkt(pkt, 64)
applyPkt(pkt, 'nf0')
sss_sdnet_tuples.sume_tuple_expect['bp_count'] = 0
sss_sdnet_tuples.sume_tuple_expect['rank_op'] = 0
srpt_rank = 0
sss_sdnet_tuples.sume_tuple_expect['srpt_rank'] = srpt_rank
sss_sdnet_tuples.sume_tuple_expect['q_id'] = lookup_q_id(srpt_rank)
sss_sdnet_tuples.sume_tuple_expect['log_pkt'] = 1
expPkt(pkt, 'nf1')

# Test 4: ACK packet, towards nf0, dport=1, seqNo = 12345 + 2048, tos=0x08 (1MB)
#   Expected: srpt_rank = (1000000 - 2048) >> 6, dst_port = nf0, log_pkt = 0
pkt = Ether(dst=nf_MAC_map['nf0'], src=nf_MAC_map['nf1']) / IP(tos=tos, src=nf_IP_map['nf1'], dst=nf_IP_map['nf0']) / TCP(dport=dport, seq=init_seqNo+900000, flags='A')
pkt = pad_pkt(pkt, 1024)
applyPkt(pkt, 'nf1')
sss_sdnet_tuples.sume_tuple_expect['bp_count'] = 0
sss_sdnet_tuples.sume_tuple_expect['rank_op'] = 0
srpt_rank = (tos_len_map[tos] - 900000) >> 16
sss_sdnet_tuples.sume_tuple_expect['srpt_rank'] = srpt_rank
sss_sdnet_tuples.sume_tuple_expect['q_id'] = lookup_q_id(srpt_rank)
sss_sdnet_tuples.sume_tuple_expect['log_pkt'] = 0
expPkt(pkt, 'nf0')

# Test 5: FIN packet, towards nf0, dport=1, seqNo = 12345 + 3072, tos=0x08 (1MB)
#   Expected: srpt_rank = (1000000 = 3072) >> 6, dst_port = nf0, log_pkt = 1
pkt = Ether(dst=nf_MAC_map['nf0'], src=nf_MAC_map['nf1']) / IP(tos=tos, src=nf_IP_map['nf1'], dst=nf_IP_map['nf0']) / TCP(dport=dport, seq=init_seqNo+997000, flags='F')
pkt = pad_pkt(pkt, 1024)
applyPkt(pkt, 'nf1')
sss_sdnet_tuples.sume_tuple_expect['bp_count'] = 0
sss_sdnet_tuples.sume_tuple_expect['rank_op'] = 0
srpt_rank = (tos_len_map[tos] - 997000) >> 16
sss_sdnet_tuples.sume_tuple_expect['srpt_rank'] = srpt_rank
sss_sdnet_tuples.sume_tuple_expect['q_id'] = lookup_q_id(srpt_rank)
sss_sdnet_tuples.sume_tuple_expect['log_pkt'] = 1
expPkt(pkt, 'nf0')

write_pcap_files()

