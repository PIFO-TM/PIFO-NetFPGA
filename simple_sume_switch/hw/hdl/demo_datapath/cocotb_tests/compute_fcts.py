#!/usr/bin/env python

import sys, os
import matplotlib
import matplotlib.pyplot as plt

from demo_utils.log_pkt_parser import LogPktParser
from demo_utils.flow_stats import FlowStats
from demo_utils.scapy_patch import rdpcap_raw

RATE_AVG_INTERVAL = 100000 # ns
EGRESS_LINK_RATE = 5

MAX_FLOW_ID = 512

def print_fcts(input_log_pkts):
    start_time = input_log_pkts[0].time
    flow_stats = FlowStats(input_log_pkts, start_time)
    flow_stats.calc_fcts()


def parse_log_pkts(pcap_file):
    try:
        log_pkts = []
        for (pkt, _) in rdpcap_raw(pcap_file):
            if pkt is not None:
                log_pkts.append(pkt)
    except IOError as e:
        print >> sys.stderr, "ERROR: failed to read pcap file: {}".format(pcap_file)
        sys.exit(1)
    except:
        print >> sys.stderr, "ERROR: empty pcap file? {}".format(pcap_file)
        sys.exit(1)

    # Parse the logged pkts
    pkt_parser = LogPktParser()
    log_pkts = pkt_parser.parse_pkts(log_pkts, MAX_FLOW_ID)
    return log_pkts

def main():
    # parse the logged pcap files
    input_log_pkts = parse_log_pkts('fct_logs/eth2.pcap')

    # plot input / output rates
    print_fcts(input_log_pkts)


if __name__ == '__main__':
    main()

