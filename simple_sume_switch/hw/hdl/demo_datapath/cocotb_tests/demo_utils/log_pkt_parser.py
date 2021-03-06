
import sys, os 
import struct, socket

"""
File: log_pkt_parser.py

Description: Parses the logged pkts

"""

class LogPkt():
    def __init__(self, flowID, length, time, rank, qsizes):
        self.flowID = flowID
        self.length = length
        self.time = time*5 # convert to ns
        self.rank = rank
        self.qsizes = qsizes

    def __str__(self):
        return 'flowID = {0: <4}, length = {1: <4}, time = {2: <6}, rank = {3: <6}, qsizes = {4}'.format(self.flowID, self.length, self.time, self.rank, self.qsizes)

class LogPktParser(object):

    def __init__(self):
        pass


    def parse_pkts(self, pkt_bufs, max_fid=None):
        """
        Inputs:
            pkt_bufs - a list of raw pkt buffers
        """
        parsed_pkts = []
        for buf in pkt_bufs:
            pkt = self.parse_pkt(buf)
            if pkt is not None and (max_fid is None or (max_fid is not None and pkt.flowID < max_fid)):
                parsed_pkts.append(pkt)
        parsed_pkts.sort(key=lambda x: x.time)
        return parsed_pkts

    def parse_pkt(self, pkt):
        try:
            tos = struct.unpack(">B", pkt[15])[0]
            ip_len = struct.unpack(">H", pkt[16:18])[0]
            proto = struct.unpack(">B", pkt[23])[0]
            src_ip = socket.inet_ntoa(pkt[26:30])
            dst_ip = socket.inet_ntoa(pkt[30:34])
            src_port = struct.unpack(">H", pkt[34:36])[0]
            dst_port = struct.unpack(">H", pkt[36:38])[0]
            seqNo = struct.unpack(">L", pkt[38:42])[0]
            tcp_flags = struct.unpack(">B", pkt[47])[0]
            qsize_0 = struct.unpack("<H", pkt[48:50])[0]
            qsize_1 = struct.unpack("<H", pkt[50:52])[0]
            qsize_2 = struct.unpack("<H", pkt[52:54])[0]
            rank = struct.unpack("<H", pkt[54:56])[0]
            timestamp = struct.unpack("<Q", pkt[56:64])[0]
            flowID = dst_port
            return LogPkt(flowID, ip_len+14, timestamp, rank, [qsize_0, qsize_1, qsize_2])
        except struct.error as e:
            print >> sys.stderr, "WARNING: could not unpack packet to obtain all fields, len(pkt) = {}".format(len(pkt))
            print e
            return None
        except socket.error as e:
            print >> sys.stderr, "WARNING: packed IP wrong length for inet_ntoa"
            return None

