#!/usr/bin/env python

import sys, os
import matplotlib
import matplotlib.pyplot as plt
import argparse

from demo_utils.log_pkt_parser import LogPktParser
from demo_utils.flow_stats import FlowStats
from demo_utils.queue_stats import QueueStats

from demo_utils.scapy_patch import rdpcap_raw

RATE_AVG_INTERVAL = 100000 # ns
EGRESS_LINK_RATE = 5

MAX_FLOW_ID = 512

def plot_stats(input_log_pkts):
    start_time = input_log_pkts[0].time
    print "Calculating Input Rates ..."
    flow_stats = FlowStats(input_log_pkts, start_time, avg_interval=RATE_AVG_INTERVAL)
    print 'Creating Plots ...'
    # create plots
    # plot rate
    plt.figure()
    flow_stats.plot_rates('', ymax=18, linewidth=5)
    plt.ylabel('Input Rate (Gb/s)')

    # plot ranks
    plt.figure()
    flow_stats.plot_ranks('Computed Ranks', ymax=18, linewidth=5)

    # plot queue sizes
    in_queue_stats = QueueStats(input_log_pkts, start_time)
    in_queue_stats.plot_queues()
    plt.title('Queue Sizes')

    # plot pkt sizes
    plt.figure()
    flow_stats.plot_pkt_sizes('Packet Sizes', ymax=18, linewidth=5)

    # plot per flow queue size measurements
    plt.figure()
    flow_stats.plot_q_sizes('Queue Size', ymax=18, linewidth=5)

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
    parser = argparse.ArgumentParser()
    parser.add_argument('--pcap', type=str, default='fct_logs/eth2.pcap', help="the pcap trace to plot")
    args = parser.parse_args()

    # parse the logged pcap files
    input_log_pkts = parse_log_pkts(args.pcap)

    # plot input / output rates
    plot_stats(input_log_pkts)

    font = {'family' : 'normal',
            'weight' : 'bold',
            'size'   : 32}
    matplotlib.rc('font', **font)
    plt.show()
    

if __name__ == '__main__':
    main()

