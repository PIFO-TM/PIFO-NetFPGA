
PIFO Implementation on NetFPGA
==============================

Python Discrete Event Simulations
----------------------------------

These simulations model the full PIFO implementation including the skip list,
skip list wrapper, and packet storage.

To run simulations:

* Enter simuation directory: `$ cd sw/python_sims`
* Configure parameters in `run_pifo_sim.py`
* Run the simulation: `$ ./run_pifo_sim.py`
* View results in `sw/python_sims/out`

Hardware Simulations
--------------------

The hardware simulations are run on top of cocotb. Here are some steps to run the packet storage simulation:

* Install Icarus verilog from github:
```
$ sudo apt-get install autoconf gperf
$ git clone https://github.com/steveicarus/iverilog.git
$ cd iverilog
$ git checkout --track -b v10-branch origin/v10-branch
$ sh autoconf.sh
$ ./configure
$ make
$ sudo make install
```

* Clone my fork of the cocotb repository: `$ git clone https://github.com/sibanez12/cocotb.git`
* Update the `$SUME_FOLDER/tools/settings.sh` so that the `COCOTB` environment variable is pointing to the cloned repository
* Enter the packet storage directory: `$ cd simple_sume_switch/hw/hdl/pkt_storage/cocotb_tests`
* Run the simulation: `$ make`



