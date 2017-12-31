
import matplotlib
matplotlib.use('Agg')
from matplotlib.backends.backend_pdf import PdfPages
import matplotlib.pyplot as plt

import sys, os
import numpy as np
import simpy
from pifo_tb import Pifo_tb

class Pifo_sim(object):
    def __init__(self, outDir):
        self.outDir = outDir
        if not os.path.exists(outDir):
            os.makedirs(outDir)

    def test_fill_level(self, levels, pkt_len, num_skipLists):
        print 'testing fill level...'
        results = []
        for level in levels:
            sim_res = self.run_sim(level, pkt_len, num_skipLists)
            print 'finished sim for level = {}'.format(level)
            results.append(sim_res)
        self.plot_results(levels, results, 'fill_level', 'lower right', 'nodes')

    def test_num_skipLists(self, level, pkt_len, num_skipLists):
        print 'testing num_skipLists...'
        results = []
        for num_sl in num_skipLists:
            sim_res = self.run_sim(level, pkt_len, num_sl)
            print 'finished sim for num_sl = {}'.format(num_sl)
            results.append(sim_res)
        self.plot_results(num_skipLists, results, 'num_skip_lists', 'upper right', '')

    def test_pkt_len(self, level, pkt_lens, num_skipLists):
        print 'testing pkt_len...'
        results = []
        for pkt_len in pkt_lens:
            sim_res = self.run_sim(level, pkt_len, num_skipLists)
            print 'finished sim for pkt_len = {}'.format(pkt_len)
            results.append(sim_res)
        self.plot_results(pkt_lens, results, 'pkt_len', 'lower right', 'bytes')

    def test_mem_latency(self, level, pkt_len, num_skipLists, mem_latencies):
        print 'testing mem latency...'
        results = []
        for lat in mem_latencies:
            sim_res = self.run_sim(level, pkt_len, num_skipLists, rd_latency=lat, wr_latency=lat)
            print 'finished sim for mem latency = {}'.format(lat)
            results.append(sim_res)
        self.plot_results(mem_latencies, results, 'mem_latency', 'lower right', 'cycles')

    def test_outreg_width(self, level, pkt_len, num_skipLists, outreg_widths):
        print 'testing outreg width...'
        results = []
        for width in outreg_widths:
            sim_res = self.run_sim(level, pkt_len, num_skipLists, outreg_width=width)
            print 'finished sim for outreg width = {}'.format(width)
            results.append(sim_res)
        self.plot_results(outreg_widths, results, 'outreg_width', 'upper right', 'nodes')

    def run_sim(self, fill_level, pkt_len, num_skipLists, num_samples=100, outreg_width=1, rd_latency=1, wr_latency=1):
        env = simpy.Environment()
        period = 1
        snd_rate = 1 # not currently used
        # instantiate the testbench
        ps_tb = Pifo_tb(env, period, snd_rate, fill_level, pkt_len, num_skipLists, num_samples, outreg_width, rd_latency, wr_latency)
        # run the simulation
        env.run()
        # collect the results
        enq_latencies = np.array(ps_tb.enq_latencies)
        deq_latencies = np.array(ps_tb.deq_latencies)
        sim_res = Sim_results(enq_latencies, deq_latencies)
        return sim_res

    def plot_results(self, xdata, results, variable, loc, units):
        avg_enq = [r.enq_avg for r in results]
        max_enq = [r.enq_max for r in results]

        avg_deq = [r.deq_avg for r in results]
        max_deq = [r.deq_max for r in results]

        # plot Enqueue Data
        self.plot_data([xdata, xdata], [avg_enq, max_enq], ['avg', 'max'], '{} ({})'.format(variable, units), 'Enq Latency (cycles)', 'Enqueue Latency vs {}'.format(variable), 'enq_v_{}.pdf'.format(variable), loc)

        # plot Dequeue Data
        self.plot_data([xdata, xdata], [avg_deq, max_deq], ['avg', 'max'], '{} ({})'.format(variable, units), 'Deq Latency (cycles)', 'Dequeue Latency vs {}'.format(variable), 'deq_v_{}.pdf'.format(variable), loc)



    def plot_data(self, xdata, ydata, labels, xlabel, ylabel, title, filename, loc):
        fig = plt.figure()
        for (x, y, label) in zip(xdata, ydata, labels):
            plt.plot(x, y, marker='o', label=label)

        plt.xlabel(xlabel)
        plt.ylabel(ylabel)
        plt.title(title)
        plt.legend(loc=loc)

        pp = PdfPages(os.path.join(self.outDir, filename))
        pp.savefig(fig)
        pp.close()
        print 'saved plot: {}'.format(filename)



class Sim_results(object):
    def __init__(self, enq_data, deq_data):
        self.enq_data = enq_data
        self.enq_avg = np.average(enq_data)
        self.enq_max = np.max(enq_data)

        self.deq_data = deq_data
        self.deq_avg = np.average(deq_data)
        self.deq_max = np.max(deq_data)
      

