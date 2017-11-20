
import Queue as q
import random
import math
import sys

maxsize = 128

class Bram:
    # Read and write counters for stats
    rdCount = 0
    wrCount = 0
    
    def __init__(self, depth=maxsize, value=-1, level=-1, right=-1, left=-1, up=-1, down=-1):
        self.mem = depth*[value, level, right, left, up, down]

    def write(self, addr, data):
        self.mem[addr] = data
        self.wrCount += 1

    def read(self, addr):
        data = self.mem[addr]
        self.rdCount += 1
        return(data)

class SkipList:
    # Block RAM for node memory
    br = Bram()
    # FIFO for node free list
    fl = q.Queue()
    # Set current size and max level to zero
    numEntries = 0
    nodeCount = 0
    currMaxLevel = 0
    retNodes = [] # for debugging
    
    def __init__(self, size=maxsize):
        # Push all free nodes in free list FIFO
        for addr in range(size):
            self.fl.put(addr)

        # log2_size is max height skip list will grow to
        log2_size = int(math.log(size, 2))
        
        # Head and tail pointers for each level, representing -inf and +inf
        self.head = log2_size*[0]
        self.tail = log2_size*[0]
        prev_h = -1
        prev_t = -1
        
        # Initialize head and tail pointers up to log2(maxsize) levels
        for i in range (log2_size):
            h = self.fl.get()
            t = self.fl.get()
            self.head[i] = h
            self.tail[i] = t
            if i > 0:
                # Read head from lower level
                prev_val, prev_lvl, prev_r, prev_l, prev_u, prev_d = self.br.read(prev_h)
                # Write back w/ up ptrs set to this level
                self.br.write(prev_h, [prev_val, prev_lvl, prev_r, prev_l, h, prev_d])
                # Read tail from lower level
                prev_val, prev_lvl, prev_r, prev_l, prev_u, prev_d = self.br.read(prev_t)
                # Write back w/ up ptrs set to this level
                self.br.write(prev_t, [prev_val, prev_lvl, prev_r, prev_l, t, prev_d])
            # Write current level's head/tail
            self.br.write(h,[-sys.maxint-1, i,  t, -1, -1, prev_h])
            self.br.write(t,[ sys.maxint,   i, -1,  h, -1, prev_t])
            prev_h = h
            prev_t = t

    def __str__(self):
        outStr = ""
        # Level 0 head and tail
        n0 = self.head[0]
        t0 = self.tail[0]
        # Loop through all levels in descending order
        for i in range(self.currMaxLevel, -1, -1):
            val0, lvl0, r0, l0, u0, d0 = self.br.read(n0)
            # -inf
            outStr += "-oo--"
            # For every node in level 0...
            while r0 != t0:
                val0, lvl0, r0, l0, u0, d0 = self.br.read(r0)
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
                        val, lvl, r, l, u, d = self.br.read(u)
                        j += 1
                if i == j:
                    outStr += str(val0) + "--"
            # +inf
            outStr += "+oo\n"
        return outStr

    # Search for value starting at startNode and stopping at stopLevel
    def search (self, startNode, stopLevel, value):
        n = startNode
        val, lvl, r, l, u, d = self.br.read(n)
        dn = d
        while True:
            # Move right as long as value is larger than nodes on this level
            if val < value:
                if r != -1:
                    dn = d
                    n = r
                    val, lvl, r, l, u, d = self.br.read(n)
            else:
                # Backtrack one
                n = l
                # Stop if stopLevel reached
                if lvl == stopLevel:
                    break
                else:
                    # Otherwise, go down
                    val, lvl, r, l, u, d = self.br.read(dn)
        return (n, dn)

    def enqueue (self, value):
        # Exit if free list does not have enough elements to add nodes at all levels
        if self.fl.qsize() < self.currMaxLevel + 1:
            print "Free list almost empty"
            return
        # Update max level
        self.numEntries += 1
        self.currMaxLevel = int(math.log(self.numEntries, 2))
        # Generate random number between 0 and current max level (inclusive)
        level = random.randint(0, self.currMaxLevel)
        # Start search from head of skip list
        startNode = sl.head[self.currMaxLevel]
        uNode = -1
        # Insert new nodes at each level starting at randomly selected level and descending to level zero
        while level >= 0:
            # Find insertion point at this level starting from the closest preceding node
            (n, startNode) = self.search(startNode, level, value)
            # Read node at insertion point
            lVal, lLvl, lR, lL, lU, lD = self.br.read(n)
            # Get new node from free list
            newNode = sl.fl.get()
            # Connect left neighbor to new node
            self.br.write(n, [lVal, lLvl, newNode, lL, lU, lD])
            # Connect right neighbor
            rVal, rLvl, rR, rL, rU, rD = self.br.read(lR)
            self.br.write(lR, [rVal, rLvl, rR, newNode, rU, rD])
            # Connect with level above if any
            if uNode != -1:
                uVal, uLvl, uR, uL, uU, uD = self.br.read(uNode)
                self.br.write(uNode, [uVal, uLvl, uR, uL, uU, newNode])
            # Connect new node to l/r neighbors on same level and up.  Down ptr is connected in next cycle
            newVal, newLvl, newR, newL = value, level, lR, n
            self.br.write(newNode, [newVal, newLvl, newR, newL, uNode, -1])
            uNode = newNode
            uVal, uLvl, uR, uL, uU = newVal, newLvl, newR, newL, newNode
            self.nodeCount += 1
            # Next level down
            level -= 1
        return

    def dequeue (self):
        # Point to tail node in level 0
        t = self.tail[0]
        # Read tail
        tVal, tLvl, tR, tL, tU, tD = self.br.read(t)
        # Read node to dequeue
        retVal, lLvl, lR, lL, lU, lD = self.br.read(tL)
        # Clear node and return it to free list
        self.br.write(tL, [-1, -1, -1, -1, -1, -1])
        sl.fl.put(tL)
        if tL in self.retNodes:
            print "Returned duplicate 1:", tL
            print self.retNodes
        else:
            self.retNodes.append(tL)
        self.nodeCount -= 1
        # Read left neighbor
        llVal, llLvl, llR, llL, llU, llD = self.br.read(lL)
        # Connect left neighbor to tail
        self.br.write(lL,[llVal, llLvl, t, llL, llU, llD])
        self.br.write(t,[tVal, tLvl, tR, lL, tU, tD])
        # Loop to free any nodes above
        while lU != -1 and lLvl <= self.currMaxLevel:
            # Read up neighbor
            uVal, uLvl, uR, uL, uU, uD = self.br.read(lU)
            # Clear node and return it to free list
            self.br.write(lU, [-1, -1, -1, -1, -1, -1])
            sl.fl.put(lU)
            if lU in self.retNodes:
                print "Returned duplicate 2:", lU
                print self.retNodes
            else:
                self.retNodes.append(lU)
            self.nodeCount -= 1
            # Read tail connected to this node
            tVal, tLvl, tR, tL, tU, tD = self.br.read(uR)
            # Read left neighbor
            lVal, lLvl, lR, lL, lU, lD = self.br.read(uL)
            # Connect left neighbor to tail
            self.br.write(uL,[lVal, lLvl, uR, lL, lU, lD])
            self.br.write(uR,[tVal, tLvl, tR, uL, tU, tD])
            # Move up
            lU = uU
        # Adjust max level
        self.numEntries -= 1
        if self.numEntries > 0:
            maxLevel = int(math.log(self.numEntries, 2))
            # if levels decreased, remove any nodes left in the top level
            if maxLevel < self.currMaxLevel:
                n = self.head[self.currMaxLevel]
                t = self.tail[self.currMaxLevel]
                val, lvl, r, l, u, d = self.br.read(n)
                # Walk through all nodes at that level and free them
                while (r != t):
                    sl.fl.put(r,[-1,-1,-1,-1,-1])
                    if r in self.retNodes:
                        print "Returned duplicate 3:", r
                        print self.retNodes
                    else:
                        self.retNodes.append(lU)
                    self.nodeCount -= 1
                    n = r
                    val, lvl, r, l, u, d = self.br.read(n)
                self.currMaxLevel = maxLevel
        return retVal

# Main
# Construct SkipList Class
sl = SkipList()
print sl
print "Free list size:", sl.fl.qsize()

# Enqueue some values and print skip list

for i in range (32):
    v = random.randint(0,100)
    print "enq:", v
    sl.enqueue(v)
    print sl

print sl.fl.qsize()

# Dequeue all values and print skip list
while sl.numEntries > 0:
    print "deq:", sl.dequeue()
    print sl

print "Free list size:", sl.fl.qsize()
