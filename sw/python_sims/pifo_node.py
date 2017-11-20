
import Queue as q
import random as r
import math
import sys

maxsize = 128

class Node:
    def __init__(self, value=None, level=None, right=None, left=None, up=None, down=None):
        self.value = value
        self.level = level
        self.right = right
        self.left  = left
        self.up    = up
        self.down  = down
        
    def __str__(self):
        return str(self.value)


class SkipList():
    # FIFO for node free list
    fl = q.Queue()
    # Head and tail pointers for each level, representing -inf and +inf
    head = []
    tail = []
    numEntries = 0
    nodeCount = 0
    currMaxLevel = 0
    
    def __init__(self, size=maxsize):
        # log2_size is max height skip list will grow to
        log2_size = int(math.log(size, 2))
        # Initialize head and tail pointers up to log2(maxsize)
        for i in range (log2_size):
            self.head.append(Node())
            self.tail.append(Node())
            self.head[i].value = -sys.maxint - 1
            self.tail[i].value = sys.maxint
            self.head[i].level = i
            self.tail[i].level = 1
            self.head[i].right = self.tail[i]
            self.tail[i].left = self.head[i]
            if i > 0:
                self.head[i-1].up = self.head[i]
                self.tail[i-1].up = self.tail[i]
                self.head[i].down = self.head[i-1]
                self.tail[i].down = self.tail[i-1]

        # Load all free nodes in free list FIFO
        for i in range(size):
            n = Node();
            self.fl.put(n)

        # Set current size and max level to zero
        self.numEntries = 0
        self.nodeCount = 0
        self.currMaxLevel = 0
    
    def __str__(self):
        outStr = ""
        #  Loop through all used levels in descending order
        for i in range(self.currMaxLevel, -1, -1):
            # Level 0 nodes
            n0 = self.head[0].right
            # Level i nodes
            n = self.head[i].right
            # -inf
            outStr += "-oo--"
            # For every node in level 0...
            while n0.right != None:
                # Print value in level i if it exists in level 0
                if (n.value == n0.value):
                    outStr += str(n.value) + "--"
                    n = n.right
                else: # Otherwise, print dashes
                    if n0.value < 10:
                        outStr += "---"
                    elif n0.value < 100:
                        outStr += "----"
                    else:
                        outStr += "-----"
                n0 = n0.right
            # +inf
            outStr += "+oo\n"
        return outStr

    # Search for value starting at startNode and stopping at stopLevel
    def search (self, startNode, stopLevel, value):
        n = startNode
        while True:
            # Move right as long as value smaller than nodes on this level
            if n.value < value:
                if n.right != None:
                    n = n.right
            else:
                # Backtrack one
                n = n.left
                # Stop if stopLevel reached
                if n.level == stopLevel:
                    dn = n.down
                    break
                else:
                    # Otherwise, go down
                    n = n.down
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
        level = r.randint(0, self.currMaxLevel)
        # Start search from head of skip list
        startNode = sl.head[self.currMaxLevel]
        currNode = None
        # Insert new nodes at each level starting at randomly selected level and descending to level zero
        while level >= 0:
            # Find insertion point at this level starting from the closest preceding node
            (n, startNode) = self.search(startNode, level, value)
            # Get new node
            newNode = sl.fl.get()
            # Connect new node to neighbors on same level
            newNode.value, newNode.level, newNode.right, newNode.left = value, level, n.right, n
            # Connect right and left neighbor to new node
            n.right.left = n.right = newNode
            # Connect with level above if any
            if currNode != None:
                newNode.up = currNode
                currNode.down = newNode
            currNode = newNode
            self.nodeCount += 1
            # Next level down
            level -= 1
        return

    def dequeue (self):
        # Point to tail node in level 0
        i = 0
        m = self.tail[0].left
        while m != None and m.level <= self.currMaxLevel:
            n = m
            # Connect previous node to tail
            n.left.right = n.right
            self.tail[i].left = n.left
            self.nodeCount -= 1
            # Move up
            m = n.up
            # Clear node and return it to free list
            n.right, n.left, n.up, n.down = None, None, None, None
            sl.fl.put(n)
            i += 1
        # Adjust max level
        self.numEntries -= 1
        if self.numEntries > 0:
            maxLevel = int(math.log(self.numEntries, 2))
            # if levels decreased, remove any nodes left in the top level
            if maxLevel < self.currMaxLevel:
                p = sl.head[self.currMaxLevel]
                t = sl.tail[self.currMaxLevel]
                # Walk through all nodes at that level and free them
                while (p.right != t):
                    r = p.right
                    p.right, p.left, p.up, p.down = None, None, None, None
                    sl.fl.put(p)
                    self.nodeCount -= 1
                    p = r
                self.currMaxLevel = maxLevel
        return n

# Main
# Construct SkipList Class
sl = SkipList()
print sl


# Enqueue some values and print skip list
for i in range (32):
    v = r.randint(0,100)
    print "enq:", v
    sl.enqueue(v)
    print sl

# Dequeue all values and print skip list
while sl.nodeCount > 0:
    print "deq:", sl.dequeue()
    print sl