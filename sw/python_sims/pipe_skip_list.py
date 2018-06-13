
import sys, os
from scapy.all import *
import simpy
from hwsim_utils import HW_sim_object, BRAM, Tuser, Fifo

MAX_NODES = 20

HEAD_PTR = 'HEAD'
TAIL_PTR = 'TAIL'


class PSL_level0_node(object):
    """The object type that is stored in BRAM entries of level 0
    """
    def __init__(self, rank, timestamp, left, right, up, meta_ptrs, valid=True):
        self.rank = rank
        self.timestamp = timestamp
        self.left = left
        self.right = right
        self.up = up
        self.meta_ptrs = meta_ptrs
        self.valid = valid

    def __str__(self):
        return 'rank = {}, timestamp = {}, left = {}, right = {}, meta_ptrs = {}'.format(self.rank, self.timestamp, self.left, self.right, self.meta_ptrs)


class PSL_node(object):
    """The object type that is stored in BRAM entries of all levels above level 0
    """
    def __init__(self, rank, timestamp, left, right, up, down):
        self.rank = rank
        self.timestamp = timestamp
        self.left = left
        self.right = right
        self.up = up
        self.down = down

    def __str__(self):
        return 'rank = {}, timestamp = {}, left = {}, right = {}, down = {}'.format(self.rank, self.timestamp, self.left, self.right, self.down)

class PSL_push_down_req(object):
    """The object type of requests pushed from a level above to a level below.
       These push down requests occur during the search procedure.
    """
    def __init__(self, rank, timestamp, meta_ptrs, start, up, free_nodes, valid=True):
        """start - ptr to node in level below at which to start the search
           up - ptr to node in level above (the one issuing the request), the node at which it was decided to drop down a level
           free_nodes - a list of N free node ptrs in the level above (the one issuing the request), these are used to create the up pointers for any nodes that must be inserted in the level below
        """
        self.rank = rank
        self.timestamp = timestamp
        self.start = start
        self.up = up
        self.free_nodes = free_nodes
        self.valid = valid

class PSL_push_up_req(object):
    """The object type of requests pushed from a level below to a level above.
       These push up requests are insertion requests.
    """
    def __init__(self, rank, timestamp, target, down, free_nodes, valid=True):
        """target - ptr to the node in the receiving level to the right of which the new node must be inserted
           down - the down ptr of the newly inserted node
           free_nodes - a list of the free node ptrs for this level that were unused by the level below in the previous stage of processing
        """
        self.rank = rank
        self.timestamp = timestamp
        self.target = target
        self.down = down
        self.valid = valid

class PSL_rm_result(object):
    """The result returned by a removal request to level 0
    """
    def __init__(self, rank, timestamp, meta_ptrs):
        self.rank = rank
        self.timestamp = timestamp
        self.meta_ptrs = meta_ptrs


class PSL_level0(HW_sim_object):
    def __init__(self, env, period, pd_in_pipe, pu_out_pipe, rm_req_pipe, rm_result_pipe, max_nodes=MAX_NODES, rd_latency=2, wr_latency=1):
        """pd_in_pipe - the pipe on which push down requests will be received
           pu_out_pipe - the pipe on which push up requests will be inserted
        """
        super(PSL_level0, self).__init__(env, period)

        # the pipe on which push down requests will be received 
        self.pd_in_pipe = pd_in_pipe
        # the pipe on which push up requests will be inserted 
        self.pu_out_pipe = pu_out_pipe

        # the pipe on which removal requests will be placed
        self.rm_req_pipe = rm_req_pipe
        # the pipe on which removal results will be written
        self.rm_result_pipe = rm_result_pipe

        self.nodes_r_in_pipe = simpy.Store(env)
        self.nodes_r_out_pipe = simpy.Store(env)
        self.nodes_w_in_pipe = simpy.Store(env)
        # maps: node ptr --> PSL_level0_node object
        self.node_bram = BRAM(env, period, self.nodes_r_in_pipe,
                                           self.nodes_r_out_pipe,
                                           self.nodes_w_in_pipe, depth=max_nodes, write_latency=wr_latency, read_latency=rd_latency)

        self.max_nodes = max_nodes

        # stores free node ptrs
        self.node_free_list = Fifo(max_nodes)
        self.init_free_lists()

        # set up the tail pointer to point to the HEAD node 
        self.tail_ptr = HEAD_PTR

        # The head node is stored in register to provide fall through functionality
        #   If the head node is invalid then that means there is nothing in the level
        left = TAIL_PTR
        self.head_node = PSL_level0_node(0, 0, left, 0, 0, 0, valid=False)

        self.run()

    """
    Initialize free lists
    """
    def init_free_lists(self):
        # Add all segments to node free list 
        for i in range(self.max_nodes):
            self.node_free_list.push(i)

    def run(self):
        """Register the processes with the simulation environment
        """
        self.env.process(self.process_level_sm())

    def process_level_sm(self):
        """This process must read incomming push down requests and removal requests,
           then update the head node and produce any push up requests
        """
        while True:
            pd_req = PSL_push_down_req(0, 0, 0, 0, 0, [], valid=False)
            # check if there are any push down requests
            if len(self.pd_in_pipe.items) > 0:
                pd_req = yield self.pd_in_pipe.get()

            rm_req = None
            # check of there are any removal requests
            if len(self.rm_req_pipe.items) > 0:
                rm_req = yield self.rm_req_pipe.get()

            # now use the push down request and removal request to update head_node and produce a push up request if necessary

            # check if a node needs to be removed
            if rm_req is not None:
                # write out the removal result
                yield self.env.process(self.process_remove(pd_req))

            # check if pd_req still needs to be inserted
            if pd_req.valid:
                yield self.env.process(self.insert_pd_req(pd_req))
                
            yield self.wait_clock()

    def insert_pd_req(self, pd_req):
        """Start looking for where to insert the pd_req.
           Keep track of:
             - The last up ptr we saw that is not None, starting with the up ptr in the pd_req
             - The number of nodes we've traversed: for a 1-2 skip list, should not traverse more than 2.
               If we are on our second node and the pd_req is still smaller then insert the pd_re immediately after this node and submit a push up req for the node we are at
        """



    def process_remove(self, pd_req):
        """A removal request has been asserted. Need to decide whether to remove the current head node
           or the push down request
        """
        if pd_req.valid and self.head_node.valid:
            # either need to return the head node or the pd node depending on which is smaller
            if pd_req.rank < self.head_node.rank:
                # return the pd_request
                rm_result = PSL_rm_result(pd_req.rank, pd_req.timestamp, pd_req.meta_ptrs)
                # no longer need to insert pd_req
                pd_req.valid = False
            else:
                # return the head_node
                rm_result = PSL_rm_result(self.head_node.rank, self.head_node.timestamp, self.head_node.meta_ptrs)
                # head node need to be replaced
                yield self.env.process(self.replace_head(pd_req))
        elif pd_req.valid:
            # return the pd_request
            rm_result = PSL_rm_result(pd_req.rank, pd_req.timestamp, pd_req.meta_ptrs)
            # no longer need to insert pd_req
            pd_req.valid = False
        elif self.head_node.valid:
            # return the head_node
            rm_result = PSL_rm_result(self.head_node.rank, self.head_node.timestamp, self.head_node.meta_ptrs)
            # head node need to be replaced
            yield self.env.process(self.replace_head(pd_req))
        else:
            print "ERROR: removal request received but head node and pd_request are invalid"
            sys.exit(1)
        # write out the removal result
        self.rm_result_pipe.put(rm_result)
        yield self.wait_clock()

    def replace_head(self, pd_req):
        """ We just removed the head node so it must be replaced.
            The pd_req still needs to be processed. If the pd_request's start node == self.head_node.left
            then we just need to replace the head_node with the pd_req :)
        """
        if pd_req.valid and (self.head_node.left == pd_req.start or self.head_node.left == TAIL_PTR):
            # replace head node with pd_req :)
            yield self.env.process(self.replace_head_with_pd_req(pd_req))
        else:
            # replace head with left neighbor
            if (self.head_node.left == TAIL_PTR):
                # this level is now empty
                self.head_node.valid = False
                self.tail_ptr = HEAD_PTR
            else:
                yield self.env.process(self.replace_head_with_neighbor(pd_req))

        yield self.wait_clock()

    def replace_head_with_pd_req(self, pd_req):
        """Replace the head node with the pd_request
        """
        left = self.head_node.left
        right = None
        up = None # no need to add a level above this node
        self.head_node = PSL_level0_node(pd_req.rank, pd_req.timestamp, left, right, up, pd_req.meta_ptrs)
        pd_req.valid = False # no need for further processing
        yield self.wait_clock()

    def replace_head_with_neighbor(self, pd_req):
        """The head node needs to be replaced with it's left neighbor
        """
        # replace head node with its left neighbor
        left_addr = self.head_node.left
        self.nodes_r_in_pipe.put(left_addr)
        self.head_node = yield self.nodes_r_out_pipe.get()
        # return the new head's old address to the free list
        self.node_free_list.push(left_addr)

        # Update the head node's left neighbor appropriately
        #    This may just require updating the left neighbor's right pointer to point to the HEAD
        #    Or we may want to insert the pd_req as the new head's left neighbor
        if self.head_node.left != TAIL_PTR:
            left_ptr = self.head_node.left
            self.nodes_r_in_pipe.put(left_ptr)
            left_neighbor = yield self.nodes_r_out_pipe.get()
            if self.head_node.left == pd_req.start and pd_req.valid:
                # the pd request must be inserted here (between the head's current left and the head)
                new_addr = self.node_free_list.pop()
                left = pd_req.start
                right = HEAD_PTR
                up = None # no need to add level above this yet
                new_node = PSL_level0_node(pd_req.rank, pd_req.timestamp, left, right, up, pd_req.meta_ptrs)
                left_neighbor.right = new_addr
                self.head_node.left = new_addr
                # write the new node
                self.nodes_w_in_pipe.put((new_addr, new_node))
                pd_req.valid = False # no need for further processing
            else:
                # replace the left neighbor's right pointer with the HEAD ptr
                left_neighbor.right = HEAD_PTR
            self.nodes_w_in_pipe.put((left_ptr, left_neighbor))
        else:
            # TODO: insert pd
        yield self.wait_clock()




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

