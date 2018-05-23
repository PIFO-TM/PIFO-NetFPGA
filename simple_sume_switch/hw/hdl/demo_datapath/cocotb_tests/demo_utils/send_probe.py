#!/usr/bin/env python

import argparse
from scapy.all import *

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('iface', type=str, help="the interface to send out of")
    parser.add_argument('--sport', type=int, default=0, help="the TCP sport field to use")
    parser.add_argument('--reset', action='store_true', default=False, help="send pkt to reset RR rank pipe state")
    args = parser.parse_args()

    eth_src = 'ff:ff:ff:ff:ff:ff' if args.reset else '08:22:22:22:22:08'
    pkt = Ether(dst='08:11:11:11:11:08', src=eth_src) / IP(src='10.0.0.2', dst='10.0.0.1') / TCP(sport=args.sport) / ('\x00'*10)
    sendp(pkt, iface=args.iface)


if __name__ == '__main__':
    main()

