from __future__ import print_function
import simpy
import random
import math
from hwsim_utils import HW_sim_object, BRAM, Tuser
from packet_storage_hwsim import Fifo

NEG_INF = -2**32
POS_INF = 2**32 - 1

# Position indexes
VAL = 0
LEFT = 5

class SkipList(HW_sim_object):
    def __init__(self, env, period, size, rd_latency, wr_latency):
        super(SkipList, self).__init__(env, period)
        self.env = env
        # Process communication pipes
        self.search_in_pipe = simpy.Store(env)
        self.search_out_pipe = simpy.Store(env)
        self.enq_in_pipe = simpy.Store(env)
        self.enq_out_pipe = simpy.Store(env)
        self.deq_in_pipe = simpy.Store(env)
        self.deq_out_pipe = simpy.Store(env)
        self.nodes_r_in_pipe = simpy.Store(env)
        self.nodes_r_out_pipe = simpy.Store(env)
        self.nodes_w_in_pipe = simpy.Store(env)
        self.nodes_w_out_pipe = simpy.Store(env)

        # Block RAM for node memory
        depth = size
        self.nodes = BRAM(self.env, period, self.nodes_r_in_pipe, self.nodes_r_out_pipe, self.nodes_w_in_pipe, self.nodes_w_out_pipe,
                          depth, wr_latency, rd_latency)
        # FIFO for free node list
        self.free_node_list = Fifo(size)
        # Set current size and max level to zero
        self.num_entries = 0
        self.nodeCount = 0
        self.currMaxLevel = 0

        # Push all free nodes in free list FIFO
        for addr in range(size):
            self.free_node_list.push(addr)

        # log2_size is max height skip list will grow to
        self.log2_size = int(math.log(size, 2))
        
        # Head and tail pointers for each level, representing -inf and +inf
        self.head = self.log2_size*[0]
        self.tail = self.log2_size*[0]
        
        # Busy flag
        self.busy = 1
        
        # Data available flag
        self.avail = 0
        
        # Value at tail of skip list
        self.value = -1
        
        # register processes for simulation
        self.run(env)

    def run(self, env):
        self.env.process(self.initSkipList())
        self.env.process(self.search())
        self.env.process(self.enqueue())
        self.env.process(self.dequeue())
    
    def __str__(self):
        outStr = ""
        # Level 0 head and tail
        n0 = self.head[0]
        t0 = self.tail[0]

        # Loop through all levels in descending order
        for i in range(self.currMaxLevel, -1, -1):
            val0, hsp0, mdp0, lvl0, r0, l0, u0, d0 = self.nodes.mem[n0]
            # -inf
            outStr += "-oo--"
            # For every node in level 0...
            while r0 != t0:
                val0, hsp0, mtp0, lvl0, r0, l0, u0, d0 = self.nodes.mem[r0]
                # Print value in level i if it exists in level 0
                j = 0
                u = u0
                while j < i:
                    if u == -1:
                        # print dashes if no connection between level 0 and level i
                        if val0 < 10:
                            outStr += "---"
                        elif val0 < 100:
                            outStr += "----"
                        else:
                            outStr += "-----"
                        break
                    else:
                        val, hsp, mdp, lvl, r, l, u, d = self.nodes.mem[u]
                        j += 1
                if i == j:
                    outStr += str(val0) + "--"
            # +inf
            outStr += "+oo\n"
        return outStr
    
    def initSkipList(self):
        prev_h = -1
        prev_t = -1
        # Initialize head and tail pointers up to log2(maxsize) levels
        for i in range (self.log2_size):
            h = self.free_node_list.pop()
            t = self.free_node_list.pop()
            self.head[i] = h
            self.tail[i] = t
            
            if i > 0:
                # Read head from lower level
                # Send read request
                self.nodes_r_in_pipe.put(prev_h)
                # Wait for response
                prev_val, prev_hsp, prev_mdp, prev_lvl, prev_r, prev_l, prev_u, prev_d = yield self.nodes_r_out_pipe.get()
                # Write back w/ up ptrs set to this level
                self.nodes_w_in_pipe.put((prev_h, [prev_val, prev_hsp, prev_mdp, prev_lvl, prev_r, prev_l, h, prev_d]))
                yield self.nodes_w_out_pipe.get()
                # Read tail from lower level
                self.nodes_r_in_pipe.put(prev_t)
                prev_val, prev_hsp, prev_mdp, prev_lvl, prev_r, prev_l, prev_u, prev_d = yield self.nodes_r_out_pipe.get()
                # Write back w/ up ptrs set to this level
                self.nodes_w_in_pipe.put((prev_t, [prev_val, prev_hsp, prev_mdp, prev_lvl, prev_r, prev_l, t, prev_d]))
                yield self.nodes_w_out_pipe.get()
            
            # Write current level's head/tail
            self.nodes_w_in_pipe.put((h, [POS_INF, -1, -1, i,  t, -1, -1, prev_h]))
            yield self.nodes_w_out_pipe.get()
            self.nodes_w_in_pipe.put((t, [NEG_INF, -1, -1, i, -1,  h, -1, prev_t]))
            yield self.nodes_w_out_pipe.get()

            prev_h = h
            prev_t = t
    
        self.busy = 0

    # Search for value starting at startNode and stopping at stopLevel
    def search (self):
        while True:
            # wait for search command
            (__startNode, __stopLevel, __value) = yield self.search_in_pipe.get()
            __t1 = self.env.now
            __n = __startNode
            self.nodes_r_in_pipe.put(__n)
            __val, __hsp, __mdp, __lvl, __r, __l, __u, __d = yield self.nodes_r_out_pipe.get()
            __dn = __d
            while True:
                # Move right as long as value is smaller than nodes on this level
                if __value < __val:
                    if __r != -1:
                        __dn = __d
                        __n = __r
                        self.nodes_r_in_pipe.put(__n)
                        __val, __hsp, __mdp, __lvl, __r, __l, __u, __d = yield self.nodes_r_out_pipe.get()
                else:
                    # Backtrack one
                    __n = __l
                    # Stop if stopLevel reached
                    if __lvl == __stopLevel:
                        break
                    else:
                        # Otherwise, go down
                        self.nodes_r_in_pipe.put(__dn)
                        __node = yield self.nodes_r_out_pipe.get()
                        if __node == None:
                            print ("srch 175: addr:", __dn, "data:", __node)
                        __val, __hsp, __mdp, __lvl, __r, __l, __u, __d = __node
            # Output result
            nclks = self.env.now - __t1
            self.search_out_pipe.put((__n, __dn, nclks))

    def enqueue (self):
        while True:
            # wait for enqueue command
            (__value, __hsp, __mdp) = yield self.enq_in_pipe.get()
            #print ("sl enq:", value, hsp, mdp)
            __t1 = self.env.now
            self.busy = 1
            # Exit if free list does not have enough elements to add nodes at all levels
            if len(self.free_node_list.items) < (self.currMaxLevel + 1):
                print ("Free list almost empty")
                self.enq_out_pipe.put((0, 0))
                continue
            # Update max level
            self.num_entries += 1
            self.currMaxLevel = int(math.log(self.num_entries, 2))
            # Generate random number between 0 and current max level (inclusive)
            __level = random.randint(0, self.currMaxLevel)
            # Start search from head of skip list
            __startNode = self.head[self.currMaxLevel]
            __uNode = -1
            # Insert new nodes at each level starting at randomly selected level and descending to level zero
            while __level >= 0:
                # Find insertion point at this level starting from the closest preceding node
                self.search_in_pipe.put((__startNode, __level, __value))
                (__n, __startNode, __search_nclks) = yield self.search_out_pipe.get()
                # Read node at insertion point
                self.nodes_r_in_pipe.put(__n)
                __lVal, __lHsp, __lMdp, __lLvl, __lR, __lL, __lU, __lD = yield self.nodes_r_out_pipe.get()
                # Get new node from free list
                __newNode = self.free_node_list.pop()
                # Connect left neighbor to new node
                self.nodes_w_in_pipe.put((__n, [__lVal, __lHsp, __lMdp, __lLvl, __newNode, __lL, __lU, __lD]))
                yield self.nodes_w_out_pipe.get()
                # Connect right neighbor
                self.nodes_r_in_pipe.put(__lR)
                __rNode = yield self.nodes_r_out_pipe.get()
                if __rNode == None:
                    print ("deq 215: addr:", __lR, "data:", __rNode)
                __rVal, __rHsp, __rMdp, __rLvl, __rR, __rL, __rU, __rD = __rNode
                self.nodes_w_in_pipe.put((__lR, [__rVal, __rHsp, __rMdp, __rLvl, __rR, __newNode, __rU, __rD]))
                yield self.nodes_w_out_pipe.get()
                # Connect with level above if any
                if __uNode != -1:
                    self.nodes_r_in_pipe.put(__uNode)
                    __uVal, __uHsp, __uMdp, __uLvl, __uR, __uL, __uU, __uD = yield self.nodes_r_out_pipe.get()
                    self.nodes_w_in_pipe.put((__uNode, [__uVal, __uHsp, __uMdp, __uLvl, __uR, __uL, __uU, __newNode]))
                    yield self.nodes_w_out_pipe.get()
                # Connect new node to l/r neighbors on same level and up.  Down ptr is connected in next cycle
                __newVal, __newHsp, __newMdp, __newLvl, __newR, __newL = __value, __hsp, __mdp, __level, __lR, __n
                self.nodes_w_in_pipe.put((__newNode, [__newVal, __newHsp, __newMdp, __newLvl, __newR, __newL, __uNode, -1]))
                yield self.nodes_w_out_pipe.get()
                __uNode = __newNode
                __uVal, __uHsp, __uMdp, __uLvl, __uR, __uL, __uU = __newVal, __newHsp, __newMdp, __newLvl, __newR, __newL, __newNode
                self.nodeCount += 1
                # Next level down
                __level -= 1
            # Output enq done
            pre_deq_node = self.nodes.mem[self.tail[0]][LEFT]
            self.value = self.nodes.mem[pre_deq_node][VAL]
            enq_nclks = self.env.now - __t1 - __search_nclks
            self.enq_out_pipe.put((__search_nclks, enq_nclks))
            self.busy = 0
            self.avail = 1

    def dequeue (self):
        while True:
            # wait for dequeue command
            yield self.deq_in_pipe.get()
            self.num_entries -= 1
            __t1 = self.env.now
            # Point to tail node in level 0
            __t = self.tail[0]
            # Read tail
            self.nodes_r_in_pipe.put(__t)
            __tVal, __tHsp, __tMdp, __tLvl, __tR, __tL, __tU, __tD = yield self.nodes_r_out_pipe.get()
            # Read node to dequeue
            self.nodes_r_in_pipe.put(__tL)
            __retVal, __retHsp, __retMdp, __lLvl, __lR, __lL, __lU, __lD = yield self.nodes_r_out_pipe.get()
            if __lL == -1:
                print ("deq 260: addr:", __tL, "data:", __retVal, __retHsp, __retMdp, __lLvl, __lR, __lL, __lU, __lD)
                print ("num_entries:", self.num_entries)
            # Clear node and return it to free list
            self.nodes_w_in_pipe.put((__tL, [-1, -1, -1, -1, -1, -1, -1, -1]))
            yield self.nodes_w_out_pipe.get()
            self.free_node_list.push(__tL)
            self.nodeCount -= 1
            # Read left neighbor
            self.nodes_r_in_pipe.put(__lL)
            __lNode = yield self.nodes_r_out_pipe.get()
            if __lNode == None:
                print ("deq 266: addr:", __lL, "data:", __lNode)
            __llVal, __llHsp, __llMdp, __llLvl, __llR, __llL, __llU, __llD = __lNode
            # Connect left neighbor to tail
            self.nodes_w_in_pipe.put((__lL,[__llVal, __llHsp, __llMdp, __llLvl, __t, __llL, __llU, __llD]))
            yield self.nodes_w_out_pipe.get()
            self.nodes_w_in_pipe.put((__t,[__tVal, __tHsp, __tMdp, __tLvl, __tR, __lL, __tU, __tD]))
            yield self.nodes_w_out_pipe.get()
            # Loop to free any nodes above
            while __lU != -1 and __lLvl <= self.currMaxLevel:
                # Read up neighbor
                self.nodes_r_in_pipe.put(__lU)
                __uVal, __uHsp, __uMdp, __uLvl, __uR, __uL, __uU, __uD = yield self.nodes_r_out_pipe.get()
                # Clear node and return it to free list
                self.nodes_w_in_pipe.put((__lU, [-1, -1, -1, -1, -1, -1, -1, -1]))
                yield self.nodes_w_out_pipe.get()
                self.free_node_list.push(__lU)
                self.nodeCount -= 1
                # Read tail connected to this node
                self.nodes_r_in_pipe.put(__uR)
                __tVal, __tHsp, __tMdp, __tLvl, __tR, __tL, __tU, __tD = yield self.nodes_r_out_pipe.get()
                # Read left neighbor
                self.nodes_r_in_pipe.put(__uL)
                __lVal, __lHsp, __lMdp, __lLvl, __lR, __lL, __lU, __lD = yield self.nodes_r_out_pipe.get()
                # Connect left neighbor to tail
                self.nodes_w_in_pipe.put((__uL,[__lVal, __lHsp, __lMdp, __lLvl, __uR, __lL, __lU, __lD]))
                self.nodes_w_out_pipe.get()
                self.nodes_w_in_pipe.put((__uR,[__tVal, __tHsp, __tMdp, __tLvl, __tR, __uL, __tU, __tD]))
                self.nodes_w_out_pipe.get()
                # Move up
                __lU = __uU
            # Adjust max level
            if self.num_entries > 0:
                __maxLevel = int(math.log(self.num_entries, 2))
                # if levels decreased, remove any nodes left in the top level
                if __maxLevel < self.currMaxLevel:
                    __n = self.head[self.currMaxLevel]
                    __t = self.tail[self.currMaxLevel]
                    self.nodes_r_in_pipe.put(__n)
                    __val, __hsp, __mdp, __lvl, __r, __l, __u, __d = yield self.nodes_r_out_pipe.get()
                    # Walk through all nodes at that level and free them
                    while (__r != __t):
                        # Read right node
                        self.nodes_r_in_pipe.put(__r)
                        __rVal, __rHsp, __rMdp, __rLvl, __rR, __rL, __rU, __rD = yield self.nodes_r_out_pipe.get()
                        if __rD == -1:
                            print ("deq 312: addr:", __r, "data:", __rVal, __rHsp, __rMdp, __rLvl, __rR, __rL, __rU, __rD)
                       
                        # Clear node and free it
                        self.nodes_w_in_pipe.put((__r,[-1, -1, -1, -1, -1, -1, -1, -1]))
                        self.nodes_w_out_pipe.get()
                        self.free_node_list.push(__r)
                        self.nodeCount -= 1
                        # Null out up ptrs in nodes below
                        self.nodes_r_in_pipe.put(__rD)
                        __dNode = yield self.nodes_r_out_pipe.get()
                        if __dNode == None:
                            print ("deq 315: addr:", __rD, "data:", __dNode)
                        __dVal, __dHsp, __dMdp, __dLvl, __dR, __dL, __dU, __dD = __dNode
                        self.nodes_w_in_pipe.put((__rD, [__dVal, __dHsp, __dMdp, __dLvl, __dR, __dL, -1, __dD]))
                        yield self.nodes_w_out_pipe.get()
                        # Move right
                        __r = __rR
                    # Reconnect head and tail in vacated level
                    self.nodes_w_in_pipe.put((__n,[POS_INF, -1, -1, __lvl, __t, -1, -1, __d]))
                    yield self.nodes_w_out_pipe.get()
                    if __lvl > 0:
                        __tD = -1
                    else:
                        __tD = self.tail[__lvl-1]
                    self.nodes_w_in_pipe.put((__t,[NEG_INF, -1, -1, __lvl, -1, __n, -1, self.tail[__lvl-1]]))
                    yield self.nodes_w_out_pipe.get()
                    self.currMaxLevel = __maxLevel
            else:
                self.avail = 0
            pre_deq_node = self.nodes.mem[self.tail[0]][LEFT]
            self.value = self.nodes.mem[pre_deq_node][VAL]
            deq_nclks = self.env.now - __t1
            self.deq_out_pipe.put((__retVal, __retHsp, __retMdp, deq_nclks))
