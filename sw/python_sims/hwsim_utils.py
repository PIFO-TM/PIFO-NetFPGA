
import sys, os
from scapy.all import *
import simpy
from collections import OrderedDict

class Tuser(object):
    def __init__(self, pkt_len, src_port, dst_port, rank, pkt_id):
        self.pkt_len = pkt_len
        self.src_port = src_port
        self.dst_port = dst_port
        self.rank = rank
        self.pkt_id = pkt_id # used for stats only

    def __str__(self):
        return '{{ pkt_len: {}, src_port: {:08b}, dst_port: {:08b}, rank: {}, pkt_id: {} }}'.format(self.pkt_len, self.src_port, self.dst_port, self.rank, self.pkt_id)

class Fifo(object):
    def __init__(self, maxsize):
        self.maxsize = maxsize
        self.items = []

    def push(self, item):
        if len(self.items) < self.maxsize:
            self.items.append(item)
        else:
            print >> sys.stderr, "ERROR: attempted to write to full FIFO"

    def pop(self):
        if len(self.items) > 0:
            item = self.items[0]
            self.items = self.items[1:]
            return item
        else:
            print >> sys.stderr, "ERROR: attempted to read from empty FIFO"
            return None

    def fill_level(self):
        return (len(self.items))

    def __str__(self):
        return str(self.items)

class AXI_S_message(object):
    def __init__(self, tdata, tvalid, tkeep, tlast, tuser):
        self.tdata = tdata
        self.tvalid = tvalid
        self.tkeep = tkeep
        self.tlast = tlast
        self.tuser = tuser

    def __str__(self):
        return "{{tdata: {}, tvalid: {}, tkeep: {:08x}, tlast: {}, tuser: {} }}".format(''.join('{:02x}'.format(ord(c)) for c in self.tdata), self.tvalid, self.tkeep, self.tlast, self.tuser)

class HW_sim_object(object):
    def __init__(self, env, period):
        self.env = env
        self.period = period

    def clock(self):
        yield self.env.timeout(self.period)

    def wait_clock(self):
        return self.env.process(self.clock())

class BRAM(HW_sim_object):
    def __init__(self, env, period, r_in_pipe, r_out_pipe, w_in_pipe, w_out_pipe=None, depth=128, write_latency=1, read_latency=1):
        super(BRAM, self).__init__(env, period)
        self.r_in_pipe = r_in_pipe
        self.r_out_pipe = r_out_pipe
        self.w_in_pipe = w_in_pipe
        self.w_out_pipe = w_out_pipe
        self.rd_count = 0
        self.wr_count = 0
        self.write_latency = write_latency
        self.read_latency = read_latency
        self.depth = depth
        self.mem = OrderedDict()
        for addr in range(depth):
            self.mem[addr] = None

        # register processes for simulation
        self.run()

    def run(self):
        self.env.process(self.write_sm())
        self.env.process(self.read_sm())

    def write_sm(self):
        """
        State machine to write incomming data into memory
        """
        while True:
            # wait to receive incoming data
            (addr, data) = yield self.w_in_pipe.get()
            # model write latency
            for i in range(self.write_latency):
                yield self.wait_clock()
            # try to write data into memory
            if addr in self.mem.keys():
                self.mem[addr] = data
            else:
                print >> sys.stderr, "ERROR: BRAM write_sm: specified address {} is out of range".format(addr)
            # indicate write_completion
            self.wr_count += 1
            if self.w_out_pipe is not None:
                done = 1
                self.w_out_pipe.put(done)    

    def read_sm(self):
        """
        State machine to read data from memory
        """
        while True:
            # wait to receive a read request
            addr = yield self.r_in_pipe.get()
            # model read latency
            for i in range(self.read_latency):
                yield self.wait_clock()
            # try to read data from memory
            if addr in self.mem.keys():
                data = self.mem[addr]
            else:
                print >> sys.stderr, "ERROR: BRAM read_sm: specified address {} is out of range".format(addr)
                data = None
            self.rd_count += 1
            # write data back
            self.r_out_pipe.put(data)

class FIFO(HW_sim_object):
    def __init__(self, env, period, r_in_pipe, r_out_pipe, w_in_pipe, w_out_pipe=None, maxsize=128, write_latency=1, read_latency=1, init_items=[]):
        super(FIFO, self).__init__(env, period)
        self.r_in_pipe = r_in_pipe
        self.r_out_pipe = r_out_pipe
        self.w_in_pipe = w_in_pipe
        self.w_out_pipe = w_out_pipe
        self.write_latency = write_latency
        self.read_latency = read_latency
        self.maxsize = maxsize
        self.items = init_items

        # register processes for simulation
        self.run()

    def run(self):
        self.env.process(self.push_sm())
        self.env.process(self.pop_sm())

    def push_sm(self):
        """
        State machine to push incoming data into the FIFO
        """
        while True:
            # wait to receive incoming data
            data = yield self.w_in_pipe.get()
            # model write latency
            for i in range(self.write_latency):
                yield self.wait_clock()
            # try to write data into FIFO
            if len(self.items) < self.maxsize:
                self.items.append(data)
            else:
                print >> sys.stderr, "ERROR: FIFO push_sm: FIFO full, cannot push {}".format(data)
            # indicate write_completion
            if self.w_out_pipe is not None:
                done = 1
                self.w_out_pipe.put(done)

    def pop_sm(self):
        """
        State machine to pop data out of the FIFO upon request
        """
        while True:
            # wait to receive a read request
            req = yield self.r_in_pipe.get()
            # model read latency
            for i in range(self.read_latency):
                yield self.wait_clock()
            # try to read head element
            if len(self.items) > 0:
                data = self.items[0]
                self.items = self.items[1:]
            else:
                print >> sys.stderr, "ERROR: FIFO pop_sm: attempted to read from empty FIFO"
                data = None
            # write data back
            self.r_out_pipe.put(data)

    def __str__(self):
        return str(self.items)

class AXI_S_master(HW_sim_object):
    def __init__(self, env, period, out_pipe, bus_width, pkt_list):
        super(AXI_S_master, self).__init__(env, period)
        self.out_pipe = out_pipe
        self.bus_width = bus_width # Bytes

        # register the processes for simulation 
        self.run(pkt_list)

    def run(self, pkt_list):
        self.env.process(self.write_pkts(pkt_list))

    def write_pkts(self, pkt_list):
        """Send pkt_list over AXI_stream interface
        Inputs:
          - pkt_list : list of tuples of the form (scapy pkt, Tuser object)
        """
        while True:
            # wait for the next transmission
            yield self.wait_clock()

            # send one word at a time
            if len(pkt_list) == 0:
                # no more data to send so send blanks
                tdata = '\x00'*self.bus_width
                tuser = Tuser(0, 0, 0)
                msg = AXI_S_message(tdata,0,0,0,tuser)
                self.out_pipe.put(msg)
            else:
                # send packets
                pkt = pkt_list[0]
                yield self.env.process(self.send_pkt(pkt))
                # remove the pkt we just sent from the pkt_list
                pkt_list = pkt_list[1:]

    def send_pkt(self, pkt_tuple):
        """Send a single packet (and associated metadata over AXI_stream interface)
        Input:
          - pkt_tuple: 0th element is a scapy packet, 1st element is a Tuser object
                       for that packet
        """
        pkt_str = str(pkt_tuple[0])
        tuser = pkt_tuple[1]
        while len(pkt_str) > self.bus_width:
            # at least one more word of this packet after this one
            tdata = pkt_str[0:self.bus_width]
            tvalid = 1
            tkeep = (1<<self.bus_width)-1
            tlast = 0
            msg = AXI_S_message(tdata, tvalid, tkeep, tlast, tuser)
            self.out_pipe.put(msg)
            yield self.wait_clock()
            pkt_str = pkt_str[self.bus_width:]
        # this is the last word of the packet
        tdata = pkt_str + '\x00'*(self.bus_width - len(pkt_str))
        tvalid = 1
        tkeep = (1<<len(pkt_str))-1
        tlast = 0
        msg = AXI_S_message(tdata, tvalid, tkeep, tlast, tuser)
        self.out_pipe.put(msg)

class AXI_S_slave(HW_sim_object):
    def __init__(self, env, period, in_pipe, bus_width):
        super(AXI_S_slave, self).__init__(env, period)
        self.in_pipe = in_pipe
        self.bus_width = bus_width # Bytes

        # register the processes for simulation
        self.run()

    def run(self):
        self.env.process(self.read_pkts())

    def read_pkts(self):
        while True:
            msg = yield self.in_pipe.get()
            print ('slave @ {:03d} msg received : {}'.format(self.env.now, msg))


class out_reg(HW_sim_object):
    def __init__(self, env, period, ins_in_pipe, ins_out_pipe, rem_in_pipe, rem_out_pipe, width=16):
        super(out_reg, self).__init__(env, period)
        self.val = width*[None]
        self.ptrs = width*[None]
        self.ins_in_pipe = ins_in_pipe
        self.ins_out_pipe = ins_out_pipe
        self.rem_in_pipe = rem_in_pipe
        self.rem_out_pipe = rem_out_pipe
        self.width = width
        self.num_entries = 0
        self.next = -1
        self.next_valid = 0
        self.busy = 0
        
        # register processes for simulation
        self.run()
    
    def run(self):
        self.env.process(self.insert())
        self.env.process(self.remove())

    def insert(self):
        while True:
            # Wait for insert request
            (val, ptrs) = yield self.ins_in_pipe.get()
            self.busy = 1
            self.next_valid = 0
            yield self.wait_clock()
            # Room available in register, just add the entry to the register
            if self.num_entries < self.width:
                self.val[self.num_entries] = val
                self.ptrs[self.num_entries] = ptrs
                self.num_entries += 1
                # -1 signals to the caller that there was room in the register to insert the entry without displacing another one
                self.ins_out_pipe.put((-1, [-1, -1]))
            else:
                # No room available
                # Find max value in register
                max_idx = self.val.index(max(self.val))
                max_val = self.val[max_idx]
                max_ptrs = self.ptrs[max_idx]
                # If new value is smaller than max
                if val < max_val:
                    # Replace max value with new value
                    self.val[max_idx] = val
                    self.ptrs[max_idx] = ptrs
                    # Return removed max value and data through pipe
                    # so can they can be inserted in skip list
                    self.ins_out_pipe.put((max_val, max_ptrs))
                else:
                    # Send new val and data through pipe so they can be inserted in skip list
                    self.ins_out_pipe.put((val, ptrs))
            # Output min value
            self.next = min(self.val[:self.num_entries])
            self.next_valid = 1
            self.busy = 0
            
    def remove(self):
        while True:
            # Wait for remove request
            yield self.rem_in_pipe.get()
            self.busy = 1
            self.next_valid = 0
            yield self.wait_clock()
            # Find min value in register
            min_idx = self.val.index(min(self.val[:self.num_entries]))
            min_val = self.val[min_idx]
            min_ptrs = self.ptrs[min_idx]
            # Shift up values below "hole" to pack the register
            self.val[min_idx:self.num_entries-1] = self.val[min_idx+1:self.num_entries]
            self.ptrs[min_idx:self.num_entries-1] = self.ptrs[min_idx+1:self.num_entries]
            self.val[self.num_entries-1] = None
            self.num_entries -= 1
            if self.num_entries > 0:
                self.next = min(self.val[:self.num_entries])
                self.next_valid = 1
            self.busy = 0
           
            # Send removed value through pipe
            self.rem_out_pipe.put((min_val, min_ptrs))

def pad_pkt(pkt, size):
    if len(pkt) >= size:
        return pkt
    else:
        return pkt / ('\x00'*(size - len(pkt)))

