
import cocotb
from cocotb.triggers import FallingEdge

import matplotlib
import matplotlib.pyplot as plt

class QueueStats(object):
    """
    Records queue sizes
    """
    def __init__(self, dut, num_queues):
        self.dut = dut
        self.clock = dut.axis_aclk
        self.q_sizes = {}
        self.num_queues = num_queues
        for i in range(num_queues):
            self.q_sizes[i] = []
        self.finish = False

    @cocotb.coroutine
    def start(self):
        while not self.finish:
            yield FallingEdge(self.clock)
            if 0 in range(self.num_queues):
                # measure size of queue 0
                q_size_0 = self.dut.simple_tm_inst.q_size_0.value.integer
                self.q_sizes[0].append(q_size_0)
            if 1 in range(self.num_queues):
                # measure size of queue 1
                q_size_1 = self.dut.simple_tm_inst.q_size_1.value.integer
                self.q_sizes[1].append(q_size_1)
            if 2 in range(self.num_queues):
                # measure size of queue 2
                q_size_2 = self.dut.simple_tm_inst.q_size_2.value.integer
                self.q_sizes[2].append(q_size_2)
            if 3 in range(self.num_queues):
                # measure size of queue 3
                q_size_3 = self.dut.simple_tm_inst.q_size_3.value.integer
                self.q_sizes[3].append(q_size_3)

    def stop(self):
        self.finish = True

def line_gen():
    lines = ['-', '--', ':', '-.']
    i = 0
    while True:
        yield lines[i]
        i += 1
        i = i % len(lines)

def plot_queues(q_sizes):
    """ q_sizes is a dict that maps q_id to a list of queue size samples from every clock cycle
    """
    line_generator = line_gen()
    cycles = range(len(q_sizes[0]))
    plt.figure()
    for q_id, sizes in q_sizes.items():
        linestyle = line_generator.next()
        plt.plot(range(len(sizes)), sizes, linewidth=5, label='Queue {}'.format(q_id), linestyle=linestyle)
#    plt.title('Queue Sizes')
    plt.xlabel('Time (Clock Cycles)')
    plt.ylabel('Queue size (64B segments)')
    plt.legend()

