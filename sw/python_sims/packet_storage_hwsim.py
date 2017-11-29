
import sys, os
from scapy.all import *
from hwsim_utils import *

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
    def __init__(self, env, period, bus_width, axi_in_pipe, axi_out_pipe, ptr_in_pipe, ptr_out_pipe):
        super(Pkt_storage, self).__init__(env, period)
        self.bus_width = bus_width

        self.START = 0
        self.FINISH_PKT = 1
        # state for state machine
        self.state = self.START

        # the input packet stream
        self.axi_in_pipe = axi_in_pipe
        # the output packet stream
        self.axi_out_pipe = axi_out_pipe

        # write the head_seg_ptr and meta_ptr into here
        self.ptr_out_pipe = ptr_out_pipe
        # read head_seg_ptr and meta_ptr from here
        self.ptr_in_pipe = ptr_in_pipe

        self.segments_r_in_pipe = simpy.Store(env)
        self.segments_r_out_pipe = simpy.Store(env)
        self.segments_w_in_pipe = simpy.Store(env)
        # maps: segment ID --> Pkt_seg object
        self.segments = BRAM(env, period, self.segments_r_in_pipe, self.segments_r_out_pipe, self.segments_w_in_pipe)

        self.metadata_r_in_pipe = simpy.Store(env)
        self.metadata_r_out_pipe = simpy.Store(env)
        self.metadata_w_in_pipe = simpy.Store(env)
        # maps: metadata ptr --> tuser object
        self.metadata = BRAM(env, period, self.metadata_r_in_pipe, self.metadata_r_out_pipe, self.metadata_w_in_pipe)

        self.seg_fl_r_in_pipe = simpy.Store(env)
        self.seg_fl_r_out_pipe = simpy.Store(env)
        self.seg_fl_w_in_pipe = simpy.Store(env)
        # stores ID of free segments
        self.free_seg_list = FIFO(env, period, self.seg_fl_r_in_pipe, self.seg_fl_r_out_pipe, self.seg_fl_w_in_pipe, maxsize=MAX_SEGMENTS, init_items=range(MAX_SEGMENTS))

        self.meta_fl_r_in_pipe = simpy.Store(env)
        self.meta_fl_r_out_pipe = simpy.Store(env)
        self.meta_fl_w_in_pipe = simpy.Store(env)
        # stores ID of free tuser blocks
        self.free_meta_list = FIFO(env, period, self.meta_fl_r_in_pipe, self.meta_fl_r_out_pipe, self.meta_fl_w_in_pipe, maxsize=MAX_PKTS, init_items=range(MAX_PKTS))

        # register processes for simulation
        self.run()

    def run(self):
        self.env.process(self.insertion_sm())
        self.env.process(self.removal_sm())


    def insertion_sm(self):
        """
        State machine to write incoming packets into storage.
        Writes the following into self.ptr_out_pipe:
          - ptr to first segment of packet
          - ptr to metadata for packet
        """
        self.state = self.START
        while True:
            yield self.wait_clock()
            if (self.state == self.START):
                yield self.env.process(self.run_start_state())
            elif (self.state):
                yield self.env.process(self.run_finish_pkt_state())
            else:
                yield self.env.process(self.run_start_state())


    def run_start_state(self):
        """
        Get free metadata block and free segment
        Write ptrs to free metadata block and free segment
        Get first 2 words of packet and write the metadata and segment
        """
        # request a free metadata block
        self.meta_fl_r_in_pipe.put(True)
        # request a free segment
        self.seg_fl_r_in_pipe.put(True)

        # get the free metadata ptr
        meta_ptr = yield self.meta_fl_r_out_pipe.get()
        # get the free segments ptr
        head_seg_ptr = yield self.seg_fl_r_out_pipe.get()

        # write the head_seg_ptr and meta_ptr
        self.ptr_out_pipe.put((head_seg_ptr, meta_ptr))

        word_count = 0
        tdata = ''
        while word_count < 2:
            msg = yield self.axi_in_pipe.get()
            if msg.tvalid:
                word_count += 1
                tdata += msg.tdata
                if word_count == 1:
                    # write the tuser object
                    self.metadata_w_in_pipe.put((meta_ptr, msg.tuser))
                elif word_count == 2:
                    # check if this is the last word of the packet
                    if msg.tlast == 1:
                        self.state = self.START
                        next_seg_ptr = None
                    else:
                        self.state = self.FINISH_PKT
                        # request a free segment
                        self.seg_fl_r_in_pipe.put(True)
                        next_seg_ptr = yield self.seg_fl_r_out_pipe.get()
                    # create first packet segement
                    pkt_seg = Pkt_segment(tdata, next_seg_ptr)
                    self.segments_w_in_pipe.put((head_seg_ptr, pkt_seg))    

    def run_finish_pkt_state(self):
        """
        Write the remainder of the pkt into segments
        """
        pkt_done = False
        word_count = 0
        tdata = ''

        # request a free segment
        self.seg_fl_r_in_pipe.put(True)
        free_seg_ptr = yield self.seg_fl_r_out_pipe.get()
        while not pkt_done:
            msg = yield self.axi_in_pipe.get()
            if msg.tvalid:
                word_count += 1
                tdata += msg.tdata
                if msg.tlast:
                    pkt_done = True
                    self.state = self.START
                    pkt_seg = Pkt_segment(tdata, None) if word_count == 2 else Pkt_segment(tdata+'\x00'*self.bus_width, None)
                    self.segments_w_in_pipe.put((free_seg_ptr, pkt_seg))
                    pkt_done = True
                elif word_count == 2:
                    word_count = 0
                    # request a free segment
                    self.seg_fl_r_in_pipe.put(True)
                    next_seg_ptr = yield self.seg_fl_r_out_pipe.get()
                    pkt_seg = Pkt_segment(tdata, next_seg_ptr)
                    self.segments_w_in_pipe.put((free_seg_ptr, pkt_seg))
                    tdata = ''
                    free_seg_ptr = next_seg_ptr


    def removal_sm(self):
        """
        State machine to remove requested pkt and metadata from the storage
        """
        while True:
            # wait for a read request
            (head_seg_ptr, meta_ptr) = yield self.ptr_in_pipe.get()

            # read the metadata
            self.metadata_r_in_pipe.put(meta_ptr) # send read request
            tuser = yield self.metadata_r_out_pipe.get() # wait for response
            self.meta_fl_w_in_pipe.put(meta_ptr) # add meta_ptr to free list

            # read the packet
            pkt_buf = ''
            cur_seg_ptr = head_seg_ptr
            while cur_seg_ptr is not None:
                # read segment
                self.segments_r_in_pipe.put(cur_seg_ptr)
                pkt_seg = yield self.segments_r_out_pipe.get() # wait for result
                self.seg_fl_w_in_pipe.put(cur_seg_ptr) # add cur_seg_ptr to free list

                # write first word of segment to AXI Stream interface
                tdata = pkt_seg.tdata[0:self.bus_width]
                tvalid = 1
                tkeep = (1<<self.bus_width)-1
                tlast = 1 if (tuser.pkt_len % SEG_SIZE <= self.bus_width) else 0
                axi_msg = AXI_S_message(tdata, tvalid, tkeep, tlast, tuser)
                self.axi_out_pipe.put(axi_msg)

                yield self.wait_clock()

                # write the second word of segment to AXI Stream interface
                tdata = pkt_seg.tdata[self.bus_width:]
                tvalid = 1 if (tuser.pkt_len % SEG_SIZE > self.bus_width) else 0
                tkeep = (1<<self.bus_width)-1
                tlast = 1 if (tuser.pkt_len % SEG_SIZE > self.bus_width) else 0
                axi_msg = AXI_S_message(tdata, tvalid, tkeep, tlast, tuser)
                self.axi_out_pipe.put(axi_msg)               

                # update the segment pointer
                cur_seg_ptr = pkt_seg.next_seg

