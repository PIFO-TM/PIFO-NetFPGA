
# PIFO Implementation on NetFPGA

This project will be contributed to the open source [P4-NetFPGA](https://github.com/NetFPGA/P4-NetFPGA-public/wiki) repository.

This repository contains the following elements:
* Python SimPy based discrete event simulations of our PIFO implementation
* Verilog code for our PIFO-based programmable traffic manager
* P4 code which implements the queue classification logic for our traffic manager, as well as the the rank computation logic for our implementation of the Shortest-Remaining-Processing-Time (SRPT) scheduling policy.
* [CocoTB](https://cocotb.readthedocs.io/en/latest/introduction.html) based hardware simulation testbenches for our programmable traffic manager

The following sections provide more details about each of these components.

## Python Discrete Event Simulations

These simulations model the full PIFO implementation including the skip list,
skip list wrapper, and packet storage.

To run simulations:

* Enter simuation directory: `$ cd sw/python_sims`
* Configure parameters in `run_pifo_sim.py`
* Run the simulation: `$ ./run_pifo_sim.py`
* View results in `sw/python_sims/out`

## Verilog Traffic Manger

The verilog source files for our traffic manager is located at [simple_sume_switch/hw/hdl/](./simple_sume_switch/hw/hdl/).

## P4 Code

The P4 code is located at [src/](./src/).

## CocoTB Hardware Simulations

The hardware simulations are run on top of [cocotb](https://cocotb.readthedocs.io/en/latest/introduction.html). Here are some steps to run the packet storage simulation:

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
* Make sure to source the `settings.sh` file: `$ source $SUME_FOLDER/tools/settings.sh`
* Enter the packet storage directory: `$ cd simple_sume_switch/hw/hdl/pkt_storage/cocotb_tests`
* Run the simulation: `$ make`

Simulations for the other Verilog modules can be run in a similar fashion, but from within their respective directories.

