#!/usr/bin/env python

import argparse
from scapy.all import *

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('iface', type=str, help="the interface to send out of")
    parser.add_argument('--sport', type=int, default=0, help="the TCP sport field to use")
    args = parser.parse_args()

    pkt = Ether(dst='08:11:11:11:11:08', src='08:22:22:22:22:08') / IP(src='10.0.0.2', dst='10.0.0.1') / TCP(sport=args.sport) / ('\x00'*10)
    sendp(pkt, iface=args.iface)


if __name__ == '__main__':
    main()

