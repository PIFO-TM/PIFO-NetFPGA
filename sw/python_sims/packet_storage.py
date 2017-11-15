
import sys, os
from scapy.all import *

SEG_SIZE = 64 # bytes of packet data
MAX_SEGMENTS = 20
MAX_PKTS = 20

class Pkt_segment(object):
    def __init__(self, tdata, next_seg=None):
        # SEG_SIZE pkt segment
        self.tdata = tdata

        # pointer to the next pkt segment
        self.next_seg = next_seg

    def __str__(self):
        return "{{tdata: {}, next_seg: {} }}".format(''.join('{:02x}'.format(ord(c)) for c in self.tdata), self.next_seg)

class Tuser(object):
    def __init__(self, pkt_len, src_port, dst_port):
        self.pkt_len = pkt_len
        self.src_port = src_port
        self.dst_port = dst_port

    def __str__(self):
        return '{{ pkt_len: {}, src_port: {:08b}, dst_port: {:08b} }}'.format(self.pkt_len, self.src_port, self.dst_port)

class Fifo(object):
    def __init__(self, maxsize):
        self.maxsize = maxsize
        self.items = []

    def put(self, item):
        if len(self.items) < self.maxsize:
            self.items.append(item)
        else:
            print >> sys.stderr, "ERROR: attempted to add to full free list"

    def get(self):
        if len(self.items) > 0:
            item = self.items[0]
            self.items = self.items[1:]
            return item
        else:
            print >> sys.stderr, "ERROR: attempted to read from empty free list"
            return None 

    def __str__(self):
        return str(self.items)


class Pkt_storage(object):
    def __init__(self):
        # maps: segment ID --> Pkt_seg object
        self.segments = {}
        # maps: metadata ptr --> tuser object
        self.metadata = {}
        # stores ID of free segments
        self.free_seg_list = Fifo(MAX_SEGMENTS)
        # stores ID of free tuser blocks
        self.free_meta_list = Fifo(MAX_PKTS)

        self.init_segs_and_meta()

    """
    Initialize segments, metadata, and free lists
    """
    def init_segs_and_meta(self):
        # Add all segments to free_seg_list
        for i in range(MAX_SEGMENTS):
            self.free_seg_list.put(i)
            self.segments[i] = None

        # Add all metadata blocks to free_meta_list
        for i in range(MAX_PKTS):
            self.free_meta_list.put(i)
            self.metadata[i] = None

    """
    Inserts a packet into the packet storage
    inputs:
        - pkt: a scapy packet
    returns:
        - ptr to first segment of packet
        - ptr to metadata for packet
    """
    def insert(self, pkt, tuser):
        # get a free metadata block
        meta_ptr = self.free_meta_list.get()
        # write the metadata block
        self.metadata[meta_ptr] = tuser

        # get a free segment
        cur_seg_ptr = self.free_seg_list.get()
        head_seg_ptr = cur_seg_ptr
        # write the pkt
        pkt_str = str(pkt)
        while len(pkt_str) > SEG_SIZE:
            tdata = pkt_str[0:SEG_SIZE]
            next_seg_ptr = self.free_seg_list.get()
            # create the new segment
            self.segments[cur_seg_ptr] = Pkt_segment(tdata, next_seg_ptr)
            pkt_str = pkt_str[SEG_SIZE:]
            cur_seg_ptr = next_seg_ptr 
        tdata = pkt_str
        next_seg_ptr = None
        # create the final segment for the packet
        self.segments[cur_seg_ptr] = Pkt_segment(tdata, next_seg_ptr)
        return head_seg_ptr, meta_ptr

    """
    Removes a packet from the packet storage
    inputs:
        - head_seg_ptr: ptr to first segment of packet
        - meta_ptr: ptr to metadata for packet
    returns:
        - output scapy packet
        - output tuser
    """
    def remove(self, head_seg_ptr, meta_ptr):
        # read the metadata
        tuser = self.metadata[meta_ptr]
        self.metadata[meta_ptr] = None
        self.free_meta_list.put(meta_ptr)

        # read the packet
        pkt_str = ''
        cur_seg_ptr = head_seg_ptr
        while (cur_seg_ptr is not None):
            pkt_seg = self.segments[cur_seg_ptr]
            pkt_str += pkt_seg.tdata
            self.segments[cur_seg_ptr] = None
            self.free_seg_list.put(cur_seg_ptr)
            cur_seg_ptr = pkt_seg.next_seg

        # reconstruct the final scapy packet
        pkt = Ether(pkt_str)
        return pkt, tuser

    """
    Convert the packet storage to a string
    """
    def __str__(self):
        out_str = """
metadata:
--------
{}
free_meta_list:
--------------
{}
segments:
--------
{}
free_seg_list:
-------------
{}
"""
        metadata_str = ''
        for meta_ptr, tuser in self.metadata.items():            
            if tuser is not None:
                metadata_str += '{}: {}\n'.format(meta_ptr, str(tuser))

        free_meta_str = str(self.free_meta_list)

        segments_str = ''
        for seg_ptr, segment in self.segments.items():
            if segment is not None:
                segments_str += '{}: {}\n'.format(seg_ptr, str(segment))

        free_seg_str = str(self.free_seg_list)
        return out_str.format(metadata_str, free_meta_str, segments_str, free_seg_str)


