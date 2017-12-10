from __future__ import print_function
import simpy
import random
import math
import sys
from statistics import mean
from hwsim_utils import HW_sim_object, BRAM, Tuser
from packet_storage_hwsim import Fifo

NEG_INF = -2**32
POS_INF = 2**32 - 1

class SkipList(HW_sim_object):
    def __init__(self, env, period, size):
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
        write_latency = 1
        read_latency = 1
        self.nodes = BRAM(env, period, self.nodes_r_in_pipe, self.nodes_r_out_pipe, self.nodes_w_in_pipe, self.nodes_w_out_pipe,
                          depth, write_latency, read_latency)
        # FIFO for free node list
        self.free_node_list = Fifo(size)
        # Set current size and max level to zero
        self.numEntries = 0
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
            self.nodes_w_in_pipe.put((h, [NEG_INF, None, None, i,  t, -1, -1, prev_h]))
            yield self.nodes_w_out_pipe.get()
            self.nodes_w_in_pipe.put((t, [POS_INF, None, None, i, -1,  h, -1, prev_t]))
            yield self.nodes_w_out_pipe.get()

            prev_h = h
            prev_t = t

    # Search for value starting at startNode and stopping at stopLevel
    def search (self):
        while True:
            # wait for search command
            (startNode, stopLevel, value) = yield self.search_in_pipe.get()
            t1 = self.env.now
            n = startNode
            self.nodes_r_in_pipe.put(n)
            val, hsp, mdp, lvl, r, l, u, d = yield self.nodes_r_out_pipe.get()
            dn = d
            while True:
                # Move right as long as value is larger than nodes on this level
                if val < value:
                    if r != -1:
                        dn = d
                        n = r
                        self.nodes_r_in_pipe.put(n)
                        val, hsp, mdp, lvl, r, l, u, d = yield self.nodes_r_out_pipe.get()
                else:
                    # Backtrack one
                    n = l
                    # Stop if stopLevel reached
                    if lvl == stopLevel:
                        break
                    else:
                        # Otherwise, go down
                        self.nodes_r_in_pipe.put(dn)
                        val, hsp, mdp, lvl, r, l, u, d = yield self.nodes_r_out_pipe.get()
            # Output result
            nclks = self.env.now - t1
            self.search_out_pipe.put((n, dn, nclks))

    def enqueue (self):
        while True:
            # wait for enqueue command
            (value, hsp, mdp) = yield self.enq_in_pipe.get()
            t1 = self.env.now
            # Exit if free list does not have enough elements to add nodes at all levels
            if len(self.free_node_list.items) < (self.currMaxLevel + 1):
                print ("Free list almost empty")
                self.enq_out_pipe.put((0, 0))
                continue
            # Update max level
            self.numEntries += 1
            self.currMaxLevel = int(math.log(self.numEntries, 2))
            # Generate random number between 0 and current max level (inclusive)
            level = random.randint(0, self.currMaxLevel)
            # Start search from head of skip list
            startNode = self.head[self.currMaxLevel]
            uNode = -1
            # Insert new nodes at each level starting at randomly selected level and descending to level zero
            while level >= 0:
                # Find insertion point at this level starting from the closest preceding node
                self.search_in_pipe.put((startNode, level, value))
                (n, startNode, search_nclks) = yield self.search_out_pipe.get()
                # Read node at insertion point
                self.nodes_r_in_pipe.put(n)
                lVal, lHsp, lMdp, lLvl, lR, lL, lU, lD = yield self.nodes_r_out_pipe.get()
                # Get new node from free list
                newNode = self.free_node_list.pop()
                # Connect left neighbor to new node
                self.nodes_w_in_pipe.put((n, [lVal, lHsp, lMdp, lLvl, newNode, lL, lU, lD]))
                yield self.nodes_w_out_pipe.get()
                # Connect right neighbor
                self.nodes_r_in_pipe.put(lR)
                rVal, rHsp, rMdp, rLvl, rR, rL, rU, rD = yield self.nodes_r_out_pipe.get()
                self.nodes_w_in_pipe.put((lR, [rVal, rHsp, rMdp, rLvl, rR, newNode, rU, rD]))
                yield self.nodes_w_out_pipe.get()
                # Connect with level above if any
                if uNode != -1:
                    self.nodes_r_in_pipe.put(uNode)
                    uVal, uHsp, uMdp, uLvl, uR, uL, uU, uD = yield self.nodes_r_out_pipe.get()
                    self.nodes_w_in_pipe.put((uNode, [uVal, uHsp, uMdp, uLvl, uR, uL, uU, newNode]))
                    yield self.nodes_w_out_pipe.get()
                # Connect new node to l/r neighbors on same level and up.  Down ptr is connected in next cycle
                newVal, newHsp, newMdp, newLvl, newR, newL = value, hsp, mdp, level, lR, n
                self.nodes_w_in_pipe.put((newNode, [newVal, newHsp, newMdp, newLvl, newR, newL, uNode, -1]))
                yield self.nodes_w_out_pipe.get()
                uNode = newNode
                uVal, uHsp, uMdp, uLvl, uR, uL, uU = newVal, newHsp, newMdp, newLvl, newR, newL, newNode
                self.nodeCount += 1
                # Next level down
                level -= 1
            # Output enq done
            enq_nclks = self.env.now - t1 - search_nclks
            self.enq_out_pipe.put((search_nclks, enq_nclks))

    def dequeue (self):
        while True:
            # wait for deqqueue command
            yield self.deq_in_pipe.get()
            t1 = self.env.now
            # Point to tail node in level 0
            t = self.tail[0]
            # Read tail
            self.nodes_r_in_pipe.put(t)
            tVal, tHsp, tMdp, tLvl, tR, tL, tU, tD = yield self.nodes_r_out_pipe.get()
            # Read node to dequeue
            self.nodes_r_in_pipe.put(tL)
            retVal, retHsp, retMdp, lLvl, lR, lL, lU, lD = yield self.nodes_r_out_pipe.get()
            # Clear node and return it to free list
            self.nodes_w_in_pipe.put((tL, [-1, -1, -1, -1, -1, -1, -1, -1]))
            yield self.nodes_w_out_pipe.get()
            self.free_node_list.push(tL)
            self.nodeCount -= 1
            # Read left neighbor
            self.nodes_r_in_pipe.put(lL)
            llVal, llHsp, llMdp, llLvl, llR, llL, llU, llD = yield self.nodes_r_out_pipe.get()
            # Connect left neighbor to tail
            self.nodes_w_in_pipe.put((lL,[llVal, llHsp, llMdp, llLvl, t, llL, llU, llD]))
            yield self.nodes_w_out_pipe.get()
            self.nodes_w_in_pipe.put((t,[tVal, tHsp, tMdp, tLvl, tR, lL, tU, tD]))
            yield self.nodes_w_out_pipe.get()
            # Loop to free any nodes above
            while lU != -1 and lLvl <= self.currMaxLevel:
                # Read up neighbor
                self.nodes_r_in_pipe.put(lU)
                uVal, uHsp, uMdp, uLvl, uR, uL, uU, uD = yield self.nodes_r_out_pipe.get()
                # Clear node and return it to free list
                self.nodes_w_in_pipe.put((lU, [-1, -1, -1, -1, -1, -1, -1, -1]))
                yield self.nodes_w_out_pipe.get()
                self.free_node_list.push(lU)
                self.nodeCount -= 1
                # Read tail connected to this node
                self.nodes_r_in_pipe.put(uR)
                tVal, tHsp, tMdp, tLvl, tR, tL, tU, tD = yield self.nodes_r_out_pipe.get()
                # Read left neighbor
                self.nodes_r_in_pipe.put(uL)
                lVal, lHsp, lMdp, lLvl, lR, lL, lU, lD = yield self.nodes_r_out_pipe.get()
                # Connect left neighbor to tail
                self.nodes_w_in_pipe.put((uL,[lVal, lHsp, lMdp, lLvl, uR, lL, lU, lD]))
                self.nodes_w_out_pipe.get()
                self.nodes_w_in_pipe.put((uR,[tVal, tHsp, tMdp, tLvl, tR, uL, tU, tD]))
                self.nodes_w_out_pipe.get()
                # Move up
                lU = uU
            self.numEntries -= 1
            # Adjust max level
            if self.numEntries > 0:
                maxLevel = int(math.log(self.numEntries, 2))
                # if levels decreased, remove any nodes left in the top level
                if maxLevel < self.currMaxLevel:
                    n = self.head[self.currMaxLevel]
                    t = self.tail[self.currMaxLevel]
                    self.nodes_r_in_pipe.put(n)
                    val, hsp, mdp, lvl, r, l, u, d = yield self.nodes_r_out_pipe.get()
                    # Walk through all nodes at that level and free them
                    while (r != t):
                        # Read right node
                        self.nodes_r_in_pipe.put(r)
                        rVal, rHsp, rMdp, rLvl, rR, rL, rU, rD = yield self.nodes_r_out_pipe.get()
                        # Clear node and free it
                        self.nodes_w_in_pipe.put((r,[-1, -1, -1, -1, -1, -1, -1, -1]))
                        self.nodes_w_out_pipe.get()
                        self.free_node_list.push(r)
                        self.nodeCount -= 1
                        # Null out up ptrs in nodes below
                        self.nodes_r_in_pipe.put(rD)
                        dVal, dHsp, dMdp, dLvl, dR, dL, dU, dD = yield self.nodes_r_out_pipe.get()
                        self.nodes_w_in_pipe.put((rD, [dVal, dHsp, dMdp, dLvl, dR, dL, -1, dD]))
                        yield self.nodes_w_out_pipe.get()
                        # Move right
                        r = rR
                    self.nodes_w_in_pipe.put((n,[val, hsp, mdp, lvl, t, l, u, d]))
                    yield self.nodes_w_out_pipe.get()
                    self.nodes_w_in_pipe.put((t,[val, hsp, mdp, lvl, r, n, u, d]))
                    yield self.nodes_w_out_pipe.get()
                    self.currMaxLevel = maxLevel
            deq_nclks = self.env.now - t1
            self.deq_out_pipe.put((retVal, retHsp, retMdp, deq_nclks))
