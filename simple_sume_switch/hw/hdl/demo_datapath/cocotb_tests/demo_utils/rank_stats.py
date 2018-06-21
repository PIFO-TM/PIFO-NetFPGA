
import sys, os
import matplotlib
import matplotlib.pyplot as plt


class RankStats(object):
    def __init__(self, log_pkt_list, start_time):
        """
        log_pkt_list: a list of LogPkts which have attributes: flowID, length (B), time (ns)
        """

        self.flow_pkts = self.parse_pkt_list(log_pkt_list)
        self.flow_ranks = self.calc_flow_ranks(self.flow_pkts)
        self.start_time = start_time 

    def parse_pkt_list(self, log_pkt_list):
        """
        Read a log_pkt_list and parse into per-flow pkts
        """
        flow_pkts = {}
        for pkt in log_pkt_list:
            flowID = pkt.flowID
            if flowID not in flow_pkts.keys():
                flow_pkts[flowID] = [(pkt.time, pkt)]
            else:
                flow_pkts[flowID].append((pkt.time, pkt))
        return flow_pkts

    def calc_flow_ranks(self, flow_pkts):
        """
        Given dictionary mapping flowIDs to the flow's pkts with nanosecond timestamps, calculate a new
        dictionary mapping flowIDs to the flow's rank values
        """
        flow_ranks = {}
        for flowID, pkts in flow_pkts.items():
            flow_ranks[flowID] = []
            for (time, pkt) in pkts:
                flow_rates[flowID].append((time, pkt.rank))
        return flow_ranks


    def line_gen(self):
        lines = ['-', '--', ':', '-.']
        i = 0
        while True:
            yield lines[i]
            i += 1
            i = i % len(lines)

    def plot_ranks(self, title, ymax=None, linewidth=1):
        """
        Plots the flow ranks
        """
        line_generator = self.line_gen()
        max_rank = 0
        for flowID, rank_points in self.flow_ranks.items():
            times = [(point[0] - self.start_time)*1e-6 for point in rank_points]
            ranks = [point[1] for point in rank_points]
            if len(ranks) > 0:
                max_rank = max(ranks) if max(ranks) > max_rank else max_rank
            if flowID is not None:
                linestyle = line_generator.next()
                plt.plot(times, ranks, label='Flow {}'.format(flowID), linewidth=linewidth, linestyle=linestyle)
        plt.xlabel('time (ms)')
        plt.ylabel('rank (64KB remaining)')
        plt.title(title)
        plt.legend(loc='upper right')
        if ymax is not None:
            plt.ylim(0, max_rate)



