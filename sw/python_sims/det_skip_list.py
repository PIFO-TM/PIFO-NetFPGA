
import Queue as q
import random as r
import math
import sys

MAX_CONS_NODES = 3
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
            self.head[i].value = sys.maxint
            self.tail[i].value = -sys.maxint - 1
            self.head[i].level = i
            self.tail[i].level = i
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
            outStr += "+oo--"
            # For every node in level 0...
            while n0.right != None:
                # Print value in level i if it exists in level 0
                if (n.value == n0.value and (i == 0 or n0.up != None)):
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
            # -inf
            outStr += "-oo\n"
        return outStr

    # Search for insertion point for new value
    def search (self, value):
        level = self.currMaxLevel
        n = self.head[level]
        u = self.head[level + 1]
        # Loop until bottom level
        while level >= 0:
            print "level:", level
            cons_nodes = 0
            d = n
            # While traversing this level searcing for consecutive nodes...
            while n.right != None:
                # Move right
                l = n
                n = n.right
                # Save the node at which we will drop down
                if n.value > value:
                    d = n
                # Exit if reached a higher node stack
                if n.up != None:
                    break;
                # Check if consecutive nodes need to be adjusted
                cons_nodes += 1
                print "cons_modes:", cons_nodes
                # If max number of consecutive nodes found
                if cons_nodes == MAX_CONS_NODES:
                    # Insert new node one level above
                    # Get new node
                    m = self.fl.get()
                    # Connect new node to neighbors on same level
                    m.value, m.level, m.right, m.left, m.down= l.value, level + 1, u.right, u, l
                    print "adding node: val:", l.value, "level:", level+1
                    # Connect right and left neighbor to new node
                    u.right.left = m
                    u.right = m
                    # Connect node below to new node
                    l.up = m
                    # Increment current level if we added a new level
                    if level + 1 > self.currMaxLevel:
                        self.currMaxLevel += 1
                    self.nodeCount += 1
                    break
                
            # Otherwise, drop one level
            u = d
            n = d.down
            level -= 1

        return (d)

    def enqueue (self, value):
        # Exit if free list does not have enough elements to add nodes at all levels
        if self.fl.qsize() < self.currMaxLevel + 1:
            print "Free list almost empty"
            return
        # Find insertion point
        n = self.search(value)
        # Insert new node at level 0
        m = sl.fl.get()
        # Connect new node to neighbors on same level
        m.value = value
        m.level = 0
        m.right = n.right
        m.left = n
        # Connect right and left neighbor to new node
        n.right.left = m
        n.right = m
        self.nodeCount += 1
        
        # Update number of entries
        self.numEntries += 1

        return

    def dequeue (self):
        # Point to tail node in level 0
        level = 0
        n = self.tail[0].left
        v = n.value
        while True:
            # Connect previous node to tail
            n.left.right = self.tail[level]
            self.tail[level].left = n.left
            self.nodeCount -= 1
            # Clear node and return it to free list
            u = n.up
            n.right, n.left, n.up, n.down = None, None, None, None
            sl.fl.put(n)
            # Move up
            if u != None:
                n = u
                level += 1
            else:
                break
        # Decrement number of entries
        self.numEntries -= 1
        # If level is empty, decrement current max level
        if level > 0 and self.tail[level].left == self.head[level]:
            self.currMaxLevel -= 1
        return v

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
while sl.numEntries > 0:
    print "deq:", sl.dequeue()
    print sl