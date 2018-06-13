#!/usr/bin/env python

import sys, os
import matplotlib
import matplotlib.pyplot as plt
import argparse
from threading import Thread
import subprocess, shlex
import time

from demo_utils.log_pkt_parser import LogPktParser
from demo_utils.flow_stats import FlowStats
from demo_utils.queue_stats import QueueStats
from demo_utils.send_probe import send_probe

from demo_utils.scapy_patch import rdpcap_raw

RATE_AVG_INTERVAL = 100000 # ns
EGRESS_LINK_RATE = 5

class PIFO_demo(object):
    """
    - Capture the logged packets with tcpdump
    - Check for errors (i.e. make sure all queues drain)
    - Plot the results
    """
    def __init__(self, input_log_iface, output_log_iface):
        self.input_log_iface = input_log_iface
        self.output_log_iface = output_log_iface

    def start_process(self, command):
        print "----------------------------------------"
        print "Starting Process:\n"
        print "-->$ ", command
        print "----------------------------------------"
        return subprocess.Popen(shlex.split(command), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    def check_empty_queues(self):
        probe = send_probe(self.output_log_iface, self.input_log_iface, 0, True)
        if (probe.qsizes != [0]*len(probe.qsizes)):
            print >> sys.stderr, "ERROR: queues are not empty:\n{}".format(probe)
            sys.exit(1)

    def run(self):
        # check to make sure all queues are empty
        self.check_empty_queues()

        # start logging packets
        self.input_log = self.start_process('tcpdump -i {0} -w hw_data/{0}.pcap -B 1000000'.format(self.input_log_iface))
        self.output_log = self.start_process('tcpdump -i {0} -w hw_data/{0}.pcap -B 1000000'.format(self.output_log_iface))

        # wait for Ctrl-C
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt as e:
            pass

        # kill tcpdump processes
        self.input_log.terminate()
        self.output_log.terminate()

        # check that the queues are still empty
        self.check_empty_queues()

        # parse the logged pcap files
        input_log_pkts = parse_log_pkts('hw_data/{}.pcap'.format(self.input_log_iface))
        output_log_pkts = parse_log_pkts('hw_data/{}.pcap'.format(self.output_log_iface))

        # plot input / output rates
        plot_stats(input_log_pkts, output_log_pkts)

        font = {'family' : 'normal',
                'weight' : 'bold',
                'size'   : 32}
        matplotlib.rc('font', **font)
        plt.show()


def plot_stats(input_log_pkts, output_log_pkts):
    start_time = input_log_pkts[0].time
    print "Calculating Input Rates ..."
    input_stats = FlowStats(input_log_pkts, start_time, avg_interval=RATE_AVG_INTERVAL)
    print "Calculating Output Rates ..."
    output_stats = FlowStats(output_log_pkts, start_time, avg_interval=RATE_AVG_INTERVAL)
    print 'Creating Plots ...'
    # create plots
    fig, axarr = plt.subplots(2)
    plt.sca(axarr[0])
    input_stats.plot_rates('', ymax=18, linewidth=5)
    plt.ylabel('Input Rate (Gb/s)')
    plt.sca(axarr[1])
    output_stats.plot_rates('', ymax=18, linewidth=5)
    plt.ylabel('Output Rate (Gb/s)')

    # plot queue sizes
#    in_queue_stats = QueueStats(input_log_pkts, start_time)
#    in_queue_stats.plot_queues()
#    plt.title('Input Queue Sizes')
    out_queue_stats = QueueStats(output_log_pkts, start_time)
    out_queue_stats.plot_queues()
    plt.title('Queue Sizes')

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
    log_pkts = pkt_parser.parse_pkts(log_pkts)
    return log_pkts

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--in_iface', type=str, default='eth1', help="the interface on which to receive input log pkts")
    parser.add_argument('--out_iface', type=str, default='eth2', help="the interface on which to receive output log pkts")
    args = parser.parse_args()

    demo = PIFO_demo(args.in_iface, args.out_iface)
    demo.run()

#    # parse the logged pcap files
#    input_log_pkts = parse_log_pkts('hw_data/eth1.pcap')
#    output_log_pkts = parse_log_pkts('hw_data/eth2.pcap')
#
#    # plot input / output rates
#    plot_stats(input_log_pkts, output_log_pkts)
#
#    font = {'family' : 'normal',
#            'weight' : 'bold',
#            'size'   : 32}
#    matplotlib.rc('font', **font)
#    plt.show()
    

if __name__ == '__main__':
    main()

