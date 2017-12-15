
import sys, os
from scapy.all import *
import simpy
from hwsim_utils import HW_sim_object, BRAM, Tuser, Fifo

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


class Pkt_storage(HW_sim_object):
    def __init__(self, env, period, pkt_in_pipe, pkt_out_pipe, ptr_in_pipe, ptr_out_pipe, max_segments=MAX_SEGMENTS, max_pkts=MAX_PKTS):
        super(Pkt_storage, self).__init__(env, period)

        # read the incomming pkt and metadata from here
        self.pkt_in_pipe = pkt_in_pipe
        # write the outgoing pkt and metadata into here
        self.pkt_out_pipe = pkt_out_pipe

        # read the incoming head_seg_ptr and metadata_ptr from here
        self.ptr_in_pipe = ptr_in_pipe
        # write the outgoing head_seg_ptr and metadata_ptr into here
        self.ptr_out_pipe = ptr_out_pipe

        self.segments_r_in_pipe = simpy.Store(env)
        self.segments_r_out_pipe = simpy.Store(env)
        self.segments_w_in_pipe = simpy.Store(env)
        # maps: segment ID --> Pkt_seg object
        self.segments = BRAM(env, period, self.segments_r_in_pipe, self.segments_r_out_pipe, self.segments_w_in_pipe, depth=max_segments)

        self.metadata_r_in_pipe = simpy.Store(env)
        self.metadata_r_out_pipe = simpy.Store(env)
        self.metadata_w_in_pipe = simpy.Store(env)
        # maps: metadata ptr --> tuser object
        self.metadata = BRAM(env, period, self.metadata_r_in_pipe, self.metadata_r_out_pipe, self.metadata_w_in_pipe, depth=max_pkts)

        self.max_segments = max_segments
        self.max_pkts = max_pkts

        # stores ID of free segments
        self.free_seg_list = Fifo(max_segments)
        # stores ID of free tuser blocks
        self.free_meta_list = Fifo(max_pkts)

        self.init_free_lists()

        self.run()

    """
    Initialize free lists
    """
    def init_free_lists(self):
        # Add all segments to free_seg_list
        for i in range(self.max_segments):
            self.free_seg_list.push(i)

        # Add all metadata blocks to free_meta_list
        for i in range(self.max_pkts):
            self.free_meta_list.push(i)

    def run(self):
        """Register the processes with the simulation environment
        """
        self.env.process(self.insertion_sm())
        self.env.process(self.removal_sm())


    def insertion_sm(self):
        """Constantly read the in_pipe and write incomming data into packet storage
           Items that come out of the in_pipe should be of the form: (scapy pkt, Tuser object)
           Reads:
             - self.pkt_in_pipe
           Writes:
             - self.ptr_out_pipe
        """
        while True:
            # wait for a pkt to come in
            (pkt, tuser) = yield self.pkt_in_pipe.get() 

            # get a free metadata block
            meta_ptr = self.free_meta_list.pop()
            # get a free segment
            cur_seg_ptr = self.free_seg_list.pop()

            head_seg_ptr = cur_seg_ptr
            # write the head_seg_ptr and meta_ptr so skip list can start insertion ASAP
            self.ptr_out_pipe.put((head_seg_ptr, meta_ptr))

            # write the metadata block into BRAM
            self.metadata_w_in_pipe.put((meta_ptr, tuser))

            # write the pkt into segments
            pkt_str = str(pkt)
            while len(pkt_str) > SEG_SIZE:
                tdata = pkt_str[0:SEG_SIZE]
                next_seg_ptr = self.free_seg_list.pop()
                # create the new segment
                self.segments_w_in_pipe.put((cur_seg_ptr, Pkt_segment(tdata, next_seg_ptr)))
                pkt_str = pkt_str[SEG_SIZE:]
                cur_seg_ptr = next_seg_ptr 
            tdata = pkt_str
            next_seg_ptr = None
            # create the final segment for the packet
            self.segments_w_in_pipe.put((cur_seg_ptr, Pkt_segment(tdata, next_seg_ptr)))


    def removal_sm(self):
        """
        Receives requests to dequeue pkts and metadata from storage
        Reads:
          - self.ptr_in_pipe
        Writes:
          - self.pkt_out_pipe
        """
        while True:
            # wait for a read request
            (head_seg_ptr, meta_ptr) = yield self.ptr_in_pipe.get()

            # read the metadata
            self.metadata_r_in_pipe.put(meta_ptr) # send read request
            tuser = yield self.metadata_r_out_pipe.get() # wait for response
            self.free_meta_list.push(meta_ptr) # add meta_ptr to free list
   
            # read the packet
            pkt_str = ''
            cur_seg_ptr = head_seg_ptr
            while (cur_seg_ptr is not None):
                # send the read request
                self.segments_r_in_pipe.put(cur_seg_ptr)
                # wait for response
                pkt_seg = yield self.segments_r_out_pipe.get()

                pkt_str += pkt_seg.tdata
                # add segment to free list
                self.free_seg_list.push(cur_seg_ptr)
                cur_seg_ptr = pkt_seg.next_seg
    
            # reconstruct the final scapy packet
            pkt = Ether(pkt_str)
            # Write the final pkt and metadata
            self.pkt_out_pipe.put((pkt, tuser))

