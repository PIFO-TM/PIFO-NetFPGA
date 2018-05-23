#!/usr/bin/env python

import matplotlib
import matplotlib.pyplot as plt
import argparse

from demo_utils.log_pkt_parser import LogPktParser
from demo_utils.flow_stats import FlowStats
from demo_utils.queue_stats import QueueStats

from demo_utils.scapy_patch import rdpcap_raw

RATE_AVG_INTERVAL = 100000 # ns
EGRESS_LINK_RATE = 5

def plot_stats(input_log_pkts, output_log_pkts):
    print "Calculating Input Rates ..."
    input_stats = FlowStats(input_log_pkts, avg_interval=RATE_AVG_INTERVAL)
    print "Calculating Output Rates ..."
    output_stats = FlowStats(output_log_pkts, avg_interval=RATE_AVG_INTERVAL)
    print 'Creating Plots ...'
    # create plots
    fig, axarr = plt.subplots(2)
    plt.sca(axarr[0])
    input_stats.plot_rates('', linewidth=5)
    plt.ylabel('Input Rate (Gb/s)')
    plt.sca(axarr[1])
    #output_stats.plot_rates('', ymax=EGRESS_LINK_RATE*1.5, linewidth=5)
    output_stats.plot_rates('', linewidth=5)
    plt.ylabel('Output Rate (Gb/s)')

    # plot queue sizes
    in_queue_stats = QueueStats(input_log_pkts)
    in_queue_stats.plot_queues()
    plt.title('Input Queue Sizes')
    out_queue_stats = QueueStats(output_log_pkts)
    out_queue_stats.plot_queues()
    plt.title('Output Queue Sizes')

def parse_log_pkts(pcap_file):
    try:
        log_pkts = []
        for (pkt, _) in rdpcap_raw(pcap_file):
            if pkt is not None:
                log_pkts.append(pkt)
    except IOError as e:
        print >> sys.stderr, "ERROR: failed to read pcap file: {}".format(pcap_file)
        sys.exit(1)

    # Parse the logged pkts
    pkt_parser = LogPktParser()
    log_pkts = pkt_parser.parse_pkts(log_pkts)
    return log_pkts

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('input_log_pkts', type=str, help="pcap file of the input log pkts")
    parser.add_argument('output_log_pkts', type=str, help="pcap file of the output log pkts")
    args = parser.parse_args()

    input_log_pkts = parse_log_pkts(args.input_log_pkts)
    output_log_pkts = parse_log_pkts(args.output_log_pkts)

    # plot input / output rates
    plot_stats(input_log_pkts, output_log_pkts)

    font = {'family' : 'normal',
            'weight' : 'bold',
            'size'   : 32}
    matplotlib.rc('font', **font)
    plt.show()

if __name__ == '__main__':
    main()

