
TOPLEVEL_LANG = verilog
TOPLEVEL = free_list_fifo

PWD=$(shell pwd)
NETFPGA_HW_LIB=$(SUME_FOLDER)/lib/hw/std/cores

VERILOG_SOURCES =  $(NETFPGA_HW_LIB)/fallthrough_small_fifo_v1_0_0/hdl/small_fifo.v
VERILOG_SOURCES += $(NETFPGA_HW_LIB)/fallthrough_small_fifo_v1_0_0/hdl/fallthrough_small_fifo.v
VERILOG_SOURCES += $(PWD)/../free_list_fifo.v
 
MODULE=test_free_list_fifo

# COCOTB is env variable pointing to installation location of cocotb repo
#COCOTB=/home/sibanez/projects/cocotb
include $(COCOTB)/makefiles/Makefile.inc
include $(COCOTB)/makefiles/Makefile.sim

