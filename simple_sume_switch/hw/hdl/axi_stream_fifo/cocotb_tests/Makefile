
TOPLEVEL_LANG = verilog

#COMPILE_ARGS=-pfileline=1

NETFPGA_HW_LIB=$(SUME_FOLDER)/lib/hw/std/cores

# pkt_storage source files
VERILOG_SOURCES =  $(NETFPGA_HW_LIB)/fallthrough_small_fifo_v1_0_0/hdl/small_fifo.v
VERILOG_SOURCES += $(NETFPGA_HW_LIB)/fallthrough_small_fifo_v1_0_0/hdl/fallthrough_small_fifo.v

VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/axi_stream_fifo/axi_stream_fifo.v

TOPLEVEL = axi_stream_fifo

MODULE=test_axi_stream_fifo


include $(COCOTB)/makefiles/Makefile.inc
include $(COCOTB)/makefiles/Makefile.sim

