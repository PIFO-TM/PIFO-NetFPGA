
TOPLEVEL_LANG = verilog
TOPLEVEL = pifo_pkt_storage


PWD=$(shell pwd)
VIVADO_IP_DIR=$(PWD)/../../../vivado_ip
NETFPGA_HW_LIB=$(SUME_FOLDER)/lib/hw/std/cores


VERILOG_SOURCES =  $(NETFPGA_HW_LIB)/fallthrough_small_fifo_v1_0_0/hdl/small_fifo.v
VERILOG_SOURCES += $(NETFPGA_HW_LIB)/fallthrough_small_fifo_v1_0_0/hdl/fallthrough_small_fifo.v
VERILOG_SOURCES += $(PWD)/../../free_list_fifo/free_list_fifo.v
VERILOG_SOURCES += $(VIVADO_IP_DIR)/metadata_bram/simulation/blk_mem_gen_v8_3.v
VERILOG_SOURCES += $(VIVADO_IP_DIR)/metadata_bram/sim/metadata_bram.v
VERILOG_SOURCES += $(VIVADO_IP_DIR)/segment_bram/sim/segment_bram.v
VERILOG_SOURCES += $(PWD)/../pifo_pkt_storage.v

MODULE=test_pifo_pkt_storage

# PYTHONPATH=$(PWD)/../../../../../sw/python_sims:$(PYTHONPATH)

include $(COCOTB)/makefiles/Makefile.inc
include $(COCOTB)/makefiles/Makefile.sim

