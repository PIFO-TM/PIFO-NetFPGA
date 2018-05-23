#!/usr/bin/env python

import argparse
from scapy.all import *
from log_pkt_parser import LogPktParser

def show_log_pkt(pkt):
    pkt_buf = str(pkt)
    if len(pkt) >= 64:
        # Parse the logged pkt
        pkt_parser = LogPktParser()
        log_pkts = pkt_parser.parse_pkts([pkt_buf])
        print 'Recived Pkt: {}'.format(str(log_pkts[0]))

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('iface', type=str, help="the interfaces to sniff on")
    args = parser.parse_args()

    sniff(iface=args.iface, prn=show_log_pkt, count=0)


if __name__ == '__main__':
    main()

