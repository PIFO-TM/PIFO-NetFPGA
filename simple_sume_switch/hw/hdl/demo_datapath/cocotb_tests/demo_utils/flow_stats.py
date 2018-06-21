
import sys, os
import numpy as np
import matplotlib
import matplotlib.pyplot as plt


class FlowStats(object):
    def __init__(self, log_pkt_list, start_time, avg_interval=1000):
        """
        log_pkt_list: a list of LogPkts which have attributes: flowID, length (B), time (ns)
        avg_interval: # of ns to avg rates over
        """

        self.avg_interval = avg_interval
        self.flow_pkts = self.parse_pkt_list(log_pkt_list)
        self.flow_rates = self.calc_flow_rates(self.flow_pkts)
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

    def calc_fcts(self):
        """
        Compute the flow completion time stats (ms)
        """
        flow_fcts = {}
        print "Computing FCTS:"
        for flowID, pkts in self.flow_pkts.items():
            fct = (pkts[-1][0] - pkts[0][0])*1e-6
            flow_fcts[flowID] = fct 
            print '\tflow {:>3} FCT = {:<8.2f} ms'.format(flowID, fct)
        avg_fct = np.average(flow_fcts.values())
        std_fct = np.std(flow_fcts.values())
        print 'Average FCT = {:>8.3f} +/- {:<8.3f} ms'.format(avg_fct, std_fct)

    def calc_flow_rates(self, flow_pkts):
        """
        Given dictionary mapping flowIDs to the flow's pkts with nanosecond timestamps, calculate a new
        dictionary mapping flowIDs to the flow's measured rate
        """
        flow_rates = {}
        for flowID, pkts in flow_pkts.items():
            prev_time = pkts[0][0]
            byte_cnt = 0
            flow_rates[flowID] = []
            for (cur_time, pkt) in pkts:
                if cur_time <= prev_time + self.avg_interval:
                    # increment
                    byte_cnt += pkt.length
                else:
#                    # insert 0 samples if needed
#                    for t in range(prev_time, cur_time, self.avg_interval)[0:-2]:
#                        avg_time = (t + self.avg_interval/2.0)
#                        flow_rates[flowID].append((avg_time, 0))
#                        prev_time = t + self.avg_interval
                    # update
                    interval = cur_time - prev_time # ns
                    rate = (byte_cnt*8.0)/float(interval)  # Gbps
                    avg_time = (cur_time + prev_time)/2.0
                    flow_rates[flowID].append((avg_time, rate))
                    # reset
                    prev_time = cur_time
                    byte_cnt = 0
        return flow_rates

    def calc_flow_ranks(self, flow_pkts):
        """
        Given dictionary mapping flowIDs to the flow's pkts with nanosecond timestamps, calculate a new
        dictionary mapping flowIDs to the flow's rank values
        """
        flow_ranks = {}
        for flowID, pkts in flow_pkts.items():
            flow_ranks[flowID] = []
            for (time, pkt) in pkts:
                flow_ranks[flowID].append((time, pkt.rank))
        return flow_ranks

    def line_gen(self):
        lines = ['-', '--', ':', '-.']
        i = 0
        while True:
            yield lines[i]
            i += 1
            i = i % len(lines)

    def marker_gen(self):
        markers = ['o', 'v', '*', 'x']
        i = 0
        while True:
            yield markers[i]
            i += 1
            i = i % len(markers)

    def plot_rates(self, title, ymax=None, linewidth=1):
        """
        Plots the flow rates
        """
        line_generator = self.line_gen()
        max_rate = 0
        for flowID, rate_points in self.flow_rates.items():
            times = [(point[0] - self.start_time)*1e-6 for point in rate_points]
            rates = [point[1] for point in rate_points]
            if len(rates) > 0:
                max_rate = max(rates) if max(rates) > max_rate else max_rate
            if flowID is not None:
                linestyle = line_generator.next()
                plt.plot(times, rates, label='Flow {}'.format(flowID), linewidth=linewidth, linestyle=linestyle)
        plt.xlabel('time (ms)')
        plt.ylabel('rate (Gbps)')
        plt.title(title)
        #plt.legend(loc='lower right')
        plt.legend(loc='upper left')
        if ymax is not None:
            plt.ylim(0, max_rate)


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
                plt.plot(times, ranks, label='Flow {}'.format(flowID), linewidth=linewidth, linestyle=linestyle, marker='o')
        plt.xlabel('time (ms)')
        plt.ylabel('rank (64KB remaining)')
        plt.title(title)
        plt.legend(loc='upper right')
        if ymax is not None:
            plt.ylim(0, max_rank)

    def plot_pkt_sizes(self, title, ymax=None, linewidth=1):
        """
        Plots the flow pkt sizes
        """
        line_generator = self.line_gen()
        max_size = 0
        for flowID, pkt_points in self.flow_pkts.items():
            times = [(point[0] - self.start_time)*1e-6 for point in pkt_points]
            sizes = [point[1].length for point in pkt_points]
            if len(sizes) > 0:
                max_size = max(sizes) if max(sizes) > max_size else max_size
            if flowID is not None:
                linestyle = line_generator.next()
                plt.plot(times, sizes, label='Flow {}'.format(flowID), linewidth=linewidth, linestyle=linestyle, marker='o')
        plt.xlabel('time (ms)')
        plt.ylabel('size (bytes)')
        plt.title(title)
        plt.legend(loc='upper left')
        if ymax is not None:
            plt.ylim(0, max_size)

    def plot_q_sizes(self, title, ymax=None, linewidth=1):
        """
        Plots per flow queue size measurements
        """
        marker_generator = self.marker_gen()
        max_size = 0
        for flowID, pkt_points in self.flow_pkts.items():
            times = [(point[0] - self.start_time)*1e-6 for point in pkt_points]
            sizes = [point[1].qsizes[0] for point in pkt_points]
            if len(sizes) > 0:
                max_size = max(sizes) if max(sizes) > max_size else max_size
            if flowID is not None:
                marker = marker_generator.next()
                plt.plot(times, sizes, label='Flow {}'.format(flowID), linewidth=linewidth, linestyle='', marker=marker)
        plt.xlabel('time (ms)')
        plt.ylabel('queue size (64B segments)')
        plt.title(title)
        plt.legend(loc='upper left')
        if ymax is not None:
            plt.ylim(0, max_size*1.1)

