from __future__ import print_function
import simpy
import random
import math
from hwsim_utils import HW_sim_object, BRAM, Fifo, out_reg

NEG_INF = -2**32
POS_INF = 2**32 - 1

# Position indexes
VAL = 0
LEFT = 5

class SkipList(HW_sim_object):
    def __init__(self, env, period, size, outreg_width, enq_fifo_depth, rd_latency, wr_latency, outreg_latency):
        super(SkipList, self).__init__(env, period)

        self.env = env
        self.period = period
        self.outreg_width = outreg_width
        self.outreg_latency = outreg_latency
        self.enq_fifo_depth = enq_fifo_depth
        
        # Process communication pipes
        self.search_in_pipe = simpy.Store(env)
        self.search_out_pipe = simpy.Store(env)
        self.enq_in_pipe = simpy.Store(env)
        self.enq_out_pipe = simpy.Store(env)
        self.deq_in_pipe = simpy.Store(env)
        self.deq_out_pipe = simpy.Store(env)
        self.outreg_ins_in_pipe = simpy.Store(env)
        self.outreg_ins_out_pipe = simpy.Store(env)
        self.outreg_rem_in_pipe = simpy.Store(env)
        self.outreg_rem_out_pipe = simpy.Store(env)
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
        # Output register on dequeue side
        self.outreg = out_reg(self.env, period, self.outreg_ins_in_pipe, self.outreg_ins_out_pipe, self.outreg_rem_in_pipe, self.outreg_rem_out_pipe, outreg_width, outreg_latency)
        # FIFO for enqueing into the skip list
        self.enq_fifo = Fifo(enq_fifo_depth)
        
        # Set current size and max level to zero
        self.num_entries = 0
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
        
        # Next value to be output
        self.next_val = None
        
        # Lists to store time measurements
        self.bg_search_nclks_list = []
        self.bg_enq_nclks_list = []
        self.bg_deq_nclks_list = []
        
        # register processes for simulation
        self.run(env)

    def run(self, env):
        self.env.process(self.initSkipList())
        self.env.process(self.search())
        self.env.process(self.enqueue())
        self.env.process(self.dequeue())
        self.enq_sl_proc = self.env.process(self.enq_sl())
        self.deq_sl_proc = self.env.process(self.deq_sl())
    
    def __str__(self):
        outStr = ""
        # Level 0 head and tail
        h0 = self.head[0]
        t0 = self.tail[0]

        # Loop through all levels in descending order
        for i in range(self.currMaxLevel, -1, -1):
            val0, hsp0, mdp0, lvl0, r0, l0, u0, d0 = self.nodes.mem[h0]
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
#        print ("sl init done @", self.env.now)

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
                # Move right as long as value is smaller than nodes on this level
                if value < val:
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

    def enq_sl (self):
        while True:
            try:
                yield self.env.timeout(self.period)
                # If enq_fifo not empty and there's room in skip list, process entry
                if self.enq_fifo.fill_level() > 0 and self.free_node_list.fill_level() >= (self.currMaxLevel + 1) and self.busy == 0:
                    #print ("enq_sl:", self.env.now)
                    self.busy = 1
                    t1 = self.env.now
                    (value, (hsp, mdp)) = self.enq_fifo.pop()

                    # Update max level
                    self.currMaxLevel = int(math.log(self.num_entries-self.outreg.num_entries, 2))
                    # Generate random number between 0 and current max level (inclusive)
                    level = random.randint(0, self.currMaxLevel)
                    # Start search from head of skip list
                    startNode = self.head[self.currMaxLevel]
                    uNode = -1
                    search_nclks_tot = 0
                    # Insert new nodes at each level starting at randomly selected level and descending to level zero
                    while level >= 0:
                        # Find insertion point at this level starting from the closest preceding node
                        self.search_in_pipe.put((startNode, level, value))
                        (n, startNode, search_nclks) = yield self.search_out_pipe.get()
                        search_nclks_tot += search_nclks
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
                        # Next level down
                        level -= 1
                    # Write time measurements to lists
                    self.bg_search_nclks_list.append(search_nclks_tot)
                    enq_nclks = self.env.now - t1 - search_nclks_tot
                    self.bg_enq_nclks_list.append(enq_nclks)
                    self.busy = 0
            
            except simpy.Interrupt as i:
#                print ("enq_sl stopped")
                break

    def enqueue (self):
        while True:
            # Wait for enqueue command
            (value, hsp, mdp) = yield self.enq_in_pipe.get()
            t1 = self.env.now
            # Wait if out reg and enqueue FIFO are full
            while (self.outreg.num_entries == self.outreg.width and self.enq_fifo.fill_level() == self.enq_fifo_depth) or self.outreg.busy == 1:
                yield self.env.timeout(self.period)
            # Insert into output reg
            self.outreg_ins_in_pipe.put((value, [hsp, mdp]))
            (out_reg_val, out_reg_ptrs) = yield self.outreg_ins_out_pipe.get()
            if out_reg_val != -1:
                # out reg insert returned an entry (either same new entry or one that was evicted from out reg)
                # push entry into enqueue FIFO
                self.enq_fifo.push((out_reg_val, out_reg_ptrs))
                    
            enq_nclks = self.env.now - t1
            self.enq_out_pipe.put((0, enq_nclks))
            self.num_entries += 1

    def deq_sl (self):
        while True:
            try:
                # Wait one clock
                yield self.env.timeout(self.period)
                # If there's room in out reg and there are entries in skip list and it's not busy
                if (self.outreg.num_entries < self.outreg.width) and self.num_entries > self.outreg.num_entries and self.busy == 0:
                    t1 = self.env.now
                    self.busy = 1
                    # Point to tail node in level 0
                    t = self.tail[0]
                    # Read tail
                    self.nodes_r_in_pipe.put(t)
                    tVal, tHsp, tMdp, tLvl, tR, tL, tU, tD = yield self.nodes_r_out_pipe.get()
                    # Read node to dequeue
                    self.nodes_r_in_pipe.put(tL)
                    dqVal, dqHsp, dqMdp, dqLvl, dqR, dqL, dqU, dqD = yield self.nodes_r_out_pipe.get()

                    # Send dequeued value to out reg
                    self.outreg.ins_in_pipe.put((dqVal, [dqHsp, dqMdp]))
                    (tmpVal, tmpPtrs) = yield self.outreg_ins_out_pipe.get()
                    # tmpVal should be -1 because there was room available in out reg
                    if tmpVal != -1:
                        print ("Dequeue Error!: Received non-null value from out reg:", tmpVal, tmpPtrs)
                
                    # Read left neighbor
                    self.nodes_r_in_pipe.put(dqL)
                    llVal, llHsp, llMdp, llLvl, llR, llL, llU, llD = yield self.nodes_r_out_pipe.get()
                    # Connect left neighbor to tail
                    self.nodes_w_in_pipe.put((dqL,[llVal, llHsp, llMdp, llLvl, t, llL, llU, llD]))
                    yield self.nodes_w_out_pipe.get()
                    self.nodes_w_in_pipe.put((t,[tVal, tHsp, tMdp, tLvl, tR, dqL, tU, tD]))
                    yield self.nodes_w_out_pipe.get()
                
                    # Clear node and return it to free list
                    self.nodes_w_in_pipe.put((tL, [-1, -1, -1, -1, -1, -1, -1, -1]))
                    yield self.nodes_w_out_pipe.get()
                    self.free_node_list.push(tL)
                
                    # Loop to free any nodes above
                    while dqU != -1 and dqLvl <= self.currMaxLevel:
                        # Read up neighbor
                        self.nodes_r_in_pipe.put(dqU)
                        uVal, uHsp, uMdp, uLvl, uR, uL, uU, uD = yield self.nodes_r_out_pipe.get()
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
                        # Clear node and return it to free list
                        self.nodes_w_in_pipe.put((dqU, [-1, -1, -1, -1, -1, -1, -1, -1]))
                        yield self.nodes_w_out_pipe.get()
                        self.free_node_list.push(dqU)
                        # Move up
                        dqU = uU
                        
                    # Adjust max level
                    maxLevel = int(math.log(self.num_entries-self.outreg.num_entries+1, 2))
                    # if levels decreased, remove any nodes left in the top level
                    if maxLevel < self.currMaxLevel:
                        h = self.head[self.currMaxLevel]
                        t = self.tail[self.currMaxLevel]
                        self.nodes_r_in_pipe.put(h)
                        val, hsp, mdp, lvl, r, l, u, d = yield self.nodes_r_out_pipe.get()
                        # Connect head and tail in vacated level
                        self.nodes_w_in_pipe.put((h,[POS_INF, -1, -1, lvl, t, -1, -1, self.head[lvl-1]]))
                        yield self.nodes_w_out_pipe.get()
                        self.nodes_w_in_pipe.put((t,[NEG_INF, -1, -1, lvl, -1, h, -1, self.tail[lvl-1]]))
                        yield self.nodes_w_out_pipe.get()
                        self.currMaxLevel = maxLevel
                        # Walk through all nodes at that level and free them
                        while (r != t):
                            # Read right node
                            self.nodes_r_in_pipe.put(r)
                            rVal, rHsp, rMdp, rLvl, rR, rL, rU, rD = yield self.nodes_r_out_pipe.get()

                            # Null out up ptrs in nodes below
                            self.nodes_r_in_pipe.put(rD)
                            dVal, dHsp, dMdp, dLvl, dR, dL, dU, dD = yield self.nodes_r_out_pipe.get()
                            self.nodes_w_in_pipe.put((rD, [dVal, dHsp, dMdp, dLvl, dR, dL, -1, dD]))
                            yield self.nodes_w_out_pipe.get()

                            # Clear node and free it
                            self.nodes_w_in_pipe.put((r,[-1, -1, -1, -1, -1, -1, -1, -1]))
                            self.nodes_w_out_pipe.get()
                            self.free_node_list.push(r)
                            # Move right
                            r = rR
 
                    deq_nclks = self.env.now - t1
                    self.bg_deq_nclks_list.append(deq_nclks)
                    self.busy = 0

            except simpy.Interrupt as i:
#                print ("deq_sl stopped")
                break

    def dequeue (self):
        while True:
            # Wait for dequeue command
            yield self.deq_in_pipe.get()
            t1 = self.env.now
            # Send remove request to out reg
            self.outreg_rem_in_pipe.put(True)
            (retVal, (retHsp, retMdp)) = yield self.outreg_rem_out_pipe.get()
            self.num_entries -= 1
            # Output deq result
            deq_nclks = self.env.now - t1
            self.deq_out_pipe.put((retVal, retHsp, retMdp, deq_nclks))
           
