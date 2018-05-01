
import matplotlib
import matplotlib.pyplot as plt

import sys, os

class QueueStats(object):
    def __init__(self, log_pkt_list):
        """
        log_pkt_list: log_pkt_list: a list of LogPkts which have attributes: qsizes (64B chunks) and time (ns)
        """
        self.qsizes, self.times = self.parse_pkt_list(log_pkt_list)

    def parse_pkt_list(self, log_pkt_list):
        try:
            assert(len(log_pkt_list) != 0)
        except AssertionError as e:
            print >> sys.stderr, "ERROR: QueueStats.parse_pkt_list: len(log_pkt_list) = 0"
            sys.exit(1)

        times = [pkt.time for pkt in log_pkt_list]
        num_queues = len(log_pkt_list[0].qsizes)
        qsizes = {i:[] for i in range(num_queues)}
        for pkt in log_pkt_list:
            for i, size in zip(range(num_queues), pkt.qsizes):            
                qsizes[i].append(size)
        return qsizes, times

    def line_gen(self):
        lines = ['-', '--', ':', '-.']
        i = 0
        while True:
            yield lines[i]
            i += 1
            i = i % len(lines)
    
    def plot_queues(self):
        line_generator = self.line_gen()
        plt.figure()
        for q_id, sizes in self.qsizes.items():
            linestyle = line_generator.next()
            plt.plot(self.times, sizes, linewidth=5, label='Queue {}'.format(q_id), linestyle=linestyle)
    #    plt.title('Queue Sizes')
        plt.xlabel('Time (ns)')
        plt.ylabel('Queue size (64B segments)')
        plt.legend()

