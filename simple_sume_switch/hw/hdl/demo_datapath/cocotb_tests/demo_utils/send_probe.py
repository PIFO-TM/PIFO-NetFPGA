#!/usr/bin/env python

import argparse
from scapy.all import *
from log_pkt_parser import LogPktParser
from threading import Thread
import time

class Prober(object):
    def __init__(self, send_iface, rcv_iface, sport, reset):
        self.log_pkt = None
    
        # start listening for packets
        sniff_thread = Thread(target=self.sniff_probe, args=(rcv_iface,))
        sniff_thread.setDaemon(True)
        sniff_thread.start()
        
        # send the probe
        eth_src = 'ff:ff:ff:ff:ff:ff' if reset else '08:11:11:11:11:08'
        pkt = Ether(dst='08:11:11:11:11:08', src=eth_src) / IP(src='10.0.0.1', dst='10.0.0.1') / TCP(sport=sport) / ('\x00'*10)
        time.sleep(1.0)
        sendp(pkt, iface=send_iface)
        sniff_thread.join(1.0)

    def record_log_pkt(self, pkt):
        pkt_buf = str(pkt)
        if len(pkt) >= 64:
            # Parse the logged pkt
            pkt_parser = LogPktParser()
            log_pkts = pkt_parser.parse_pkts([pkt_buf])
            print 'Recived Pkt: {}'.format(str(log_pkts[0]))
            self.log_pkt = log_pkts[0]
    
    def sniff_probe(self, iface):
        sniff(iface=iface, prn=self.record_log_pkt, count=2)

def send_probe(send_iface, rcv_iface, sport, reset):
    p = Prober(send_iface, rcv_iface, sport, reset)
    return p.log_pkt

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--riface', type=str, default='eth2', help="the interface to sniff on")
    parser.add_argument('--siface', type=str, default='eth2', help="the interface to send out of")
    parser.add_argument('--sport', type=int, default=0, help="the TCP sport field to use")
    parser.add_argument('--no_rst', action='store_true', default=False, help="do not reset RR rank pipe state")
    args = parser.parse_args()

    send_probe(args.siface, args.riface, args.sport, not args.no_rst)


if __name__ == '__main__':
    main()

