
import matplotlib
matplotlib.use('Agg')
from matplotlib.backends.backend_pdf import PdfPages
import matplotlib.pyplot as plt

import sys, os
import numpy as np
import simpy
from pifo_tb import Pifo_tb

LINE_STYLES = {'prob':'--', 'det':'-'}

class Pifo_sim(object):
    def __init__(self, outDir):
        self.outDir = outDir
        if not os.path.exists(outDir):
            os.makedirs(outDir)

        self.fig, axarr = plt.subplots(2, sharex=True)
        self.enq_ax = axarr[0]
        self.deq_ax = axarr[1]
        
#        self.enq_fig = plt.figure()
#        self.enq_ax = self.enq_fig.add_subplot(111)
#
#        self.deq_fig = plt.figure()
#        self.deq_ax = self.deq_fig.add_subplot(111)

    def test_fill_level(self, levels, pkt_len, num_skipLists, sl_impls):
        print 'testing fill level...'
        for impl in sl_impls:
            results = []
            for level in levels:
                sim_res = self.run_sim(level, pkt_len, num_skipLists, sl_impl=impl)
                print 'finished sim for level = {}'.format(level)
                results.append(sim_res)
            self.plot_results(levels, results, 'fill_level', 'lower right', 'nodes', impl)

    def test_num_skipLists(self, level, pkt_len, num_skipLists, outreg_width, enq_fifo_depth, sl_impls):
        print 'testing num_skipLists...'
        for impl in sl_impls:
            results = []
            for num_sl in num_skipLists:
                sim_res = self.run_sim(level, pkt_len, num_sl, outreg_width=outreg_width, enq_fifo_depth=enq_fifo_depth, sl_impl=impl)
                print 'finished sim for num_sl = {}'.format(num_sl)
                results.append(sim_res)
            print 'impl = {}, enq_avg = {}, deq_avg = {}'.format(impl, [r.enq_avg for r in results], [r.deq_avg for r in results])
            self.plot_results(num_skipLists, results, 'num_skip_lists', 'upper right', '', impl)

    def test_pkt_len(self, level, pkt_lens, num_skipLists, sl_impls):
        print 'testing pkt_len...'
        for impl in sl_impls:
            results = []
            for pkt_len in pkt_lens:
                sim_res = self.run_sim(level, pkt_len, num_skipLists, sl_impl=impl)
                print 'finished sim for pkt_len = {}'.format(pkt_len)
                results.append(sim_res)
            self.plot_results(pkt_lens, results, 'pkt_len', 'lower right', 'bytes', impl)

    def test_mem_latency(self, level, pkt_len, num_skipLists, mem_latencies, sl_impls):
        print 'testing mem latency...'
        for impl in sl_impls:
            results = []
            for lat in mem_latencies:
                sim_res = self.run_sim(level, pkt_len, num_skipLists, rd_latency=lat, wr_latency=lat, sl_impl=impl)
                print 'finished sim for mem latency = {}'.format(lat)
                results.append(sim_res)
            self.plot_results(mem_latencies, results, 'mem_latency', 'lower right', 'cycles', impl)

    def test_outreg_width(self, level, pkt_len, num_skipLists, outreg_widths, enq_fifo_depth, sl_impls):
        print 'testing outreg width...'
        for impl in sl_impls:
            results = []
            for width in outreg_widths:
                sim_res = self.run_sim(level, pkt_len, num_skipLists, outreg_width=width, enq_fifo_depth=enq_fifo_depth, sl_impl=impl)
                print 'finished sim for outreg width = {}'.format(width)
                results.append(sim_res)
            self.plot_results(outreg_widths, results, 'outreg_width', 'upper right', 'nodes', impl)

    def run_sim(self, fill_level, pkt_len, num_skipLists, num_samples=100, outreg_width=1, enq_fifo_depth=1, rd_latency=1, wr_latency=1, sl_impl='det'):
        env = simpy.Environment()
        period = 1
        snd_rate = 1 # not currently used
        # instantiate the testbench
        ps_tb = Pifo_tb(env, period, snd_rate, fill_level, pkt_len, num_skipLists, num_samples, outreg_width, enq_fifo_depth, rd_latency, wr_latency, sl_impl)
        # run the simulation
        env.run()
        # collect the results
        
        enq_latencies = np.array(ps_tb.enq_latencies)
        deq_latencies = np.array(ps_tb.deq_latencies)
        sim_res = Sim_results(enq_latencies, deq_latencies)
        return sim_res

    def plot_results(self, xdata, results, variable, loc, units, sl_impl):
        avg_enq = [r.enq_avg for r in results]
        max_enq = [r.enq_max for r in results]

        avg_deq = [r.deq_avg for r in results]
        max_deq = [r.deq_max for r in results]

        linestyle = LINE_STYLES[sl_impl]
        labels = ['{} ({})'.format(l, sl_impl) for l in ['avg', 'max']]

        # plot Enqueue Data
        self.plot_data([xdata, xdata], [avg_enq, max_enq], labels, '{} ({})'.format(variable, units), 'Enq Latency (cycles)', 'Enqueue Latency vs {}'.format(variable), loc, self.enq_ax, linestyle)

        # plot Dequeue Data
        self.plot_data([xdata, xdata], [avg_deq, max_deq], labels, '{} ({})'.format(variable, units), 'Deq Latency (cycles)', 'Dequeue Latency vs {}'.format(variable), loc, self.deq_ax, linestyle)

        filename = 'enq_deq_v_{}.pdf'.format(variable)
        fig = plt.gcf()
        pp = PdfPages(os.path.join(self.outDir, filename))
        pp.savefig(fig)
        pp.close()
        print 'saved plot: {}'.format(filename)

    def plot_data(self, xdata, ydata, labels, xlabel, ylabel, title, loc, ax, linestyle):
        for (x, y, label) in zip(xdata, ydata, labels):
            ax.plot(x, y, marker='o', label=label, linestyle=linestyle)

        ax.set_xlabel(xlabel)
        ax.set_ylabel(ylabel)
        ax.set_title(title)
        ax.legend(loc=loc)


class Sim_results(object):
    def __init__(self, enq_data, deq_data):
        self.enq_data = enq_data
        self.enq_avg = np.average(enq_data)
        self.enq_max = np.max(enq_data)

        self.deq_data = deq_data
        self.deq_avg = np.average(deq_data)
        self.deq_max = np.max(deq_data)
      

