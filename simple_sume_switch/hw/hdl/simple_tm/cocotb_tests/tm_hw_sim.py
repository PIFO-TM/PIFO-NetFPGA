
import matplotlib
matplotlib.use('Agg')
from matplotlib.backends.backend_pdf import PdfPages
import matplotlib.pyplot as plt

import sys, os
import numpy as np
import json
import re
import subprocess

PARAMS_FILE = 'cocotb_tm_wrapper.v'
RESULTS_FILE = 'cocotb_results.json'

class TM_hw_sim(object):
    def __init__(self, outDir):
        self.outDir = outDir
        if not os.path.exists(outDir):
            os.makedirs(outDir)

        self.fig, axarr = plt.subplots(2, sharex=True)
        self.enq_ax = axarr[0]
        self.deq_ax = axarr[1]

    def test_pifo_depth(self, pifo_depths):
        print 'testing pifo depth...'
        results = []
        for pifo_depth in pifo_depths:
            sim_res = self.run_sim(pifo_depth)
            print 'finished sim for pifo_depth = {}'.format(pifo_depth)
            results.append(sim_res)
        self.plot_results(pifo_depths, results, 'pifo_depth', 'lower right', 'pkts')

    def run_sim(self, pifo_depth):
        # delete any existing RESULTS_FILE
        os.system('rm -f {}'.format(RESULTS_FILE))
        # set parameters
        self.params_file = open(PARAMS_FILE).read()
        self.set_param('PIFO_DEPTH', pifo_depth)
        with open(PARAMS_FILE, 'w') as f:
            f.write(self.params_file)
        # run cocotb simulation
        output = subprocess.check_output('make', shell=True)
        if 'ERROR:' in output:
            print output
        # collect the results
        sim_res = self.get_results()
        return sim_res

    def set_param(self, param, value):
        fmat = r'{} = \d*'.format(param)
        obj = re.search(fmat, self.params_file)
        if obj is None:
            print >> sys.stderr, "ERROR: could not find parameter in PARAMS_FILE"
            sys.exit(1)
        self.params_file = self.params_file.replace(obj.group(0), '{} = {}'.format(param, value))

    def get_results(self):
        with open(RESULTS_FILE) as f:
            data = json.load(f)
        enq_delays = data['enq_delays']
        deq_delays = data['deq_delays']
        sim_res = Sim_results(enq_delays, deq_delays)
        return sim_res

    def plot_results(self, xdata, results, variable, loc, units):
        avg_enq = [r.enq_avg for r in results]
        max_enq = [r.enq_max for r in results]

        avg_deq = [r.deq_avg for r in results]
        max_deq = [r.deq_max for r in results]

        labels = ['avg', 'max']

        # plot Enqueue Data
        self.plot_data([xdata, xdata], [avg_enq, max_enq], labels, '{} ({})'.format(variable, units), 'Enq Latency (cycles)', 'Enqueue Latency vs {}'.format(variable), loc, self.enq_ax)

        # plot Dequeue Data
        self.plot_data([xdata, xdata], [avg_deq, max_deq], labels, '{} ({})'.format(variable, units), 'Deq Latency (cycles)', 'Dequeue Latency vs {}'.format(variable), loc, self.deq_ax)

        filename = 'enq_deq_v_{}.pdf'.format(variable)
        fig = plt.gcf()
        pp = PdfPages(os.path.join(self.outDir, filename))
        pp.savefig(fig)
        pp.close()
        print 'saved plot: {}'.format(filename)

    def plot_data(self, xdata, ydata, labels, xlabel, ylabel, title, loc, ax):
        for (x, y, label) in zip(xdata, ydata, labels):
            ax.plot(x, y, marker='o', label=label)

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
      

