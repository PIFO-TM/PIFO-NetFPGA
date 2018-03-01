
TOPLEVEL_LANG = verilog
TOPLEVEL = cocotb_tm_wrapper


VIVADO_IP_DIR=$(NF_DESIGN_DIR)/hw/vivado_ip
NETFPGA_HW_LIB=$(SUME_FOLDER)/lib/hw/std/cores


# pkt_storage source files
VERILOG_SOURCES =  $(NETFPGA_HW_LIB)/fallthrough_small_fifo_v1_0_0/hdl/small_fifo.v
VERILOG_SOURCES += $(NETFPGA_HW_LIB)/fallthrough_small_fifo_v1_0_0/hdl/fallthrough_small_fifo.v
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/free_list_fifo/free_list_fifo.v
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/simple_dp_bram/simple_dp_bram.v
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/pkt_storage/pifo_pkt_storage.v

# pifo source files
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/pifo_reg/pifo_reg.v

# top level source files
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/tm_top/tm_top.v
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/tm_top/cocotb_tests/cocotb_tm_wrapper.v

MODULE=test_tm_top

include $(COCOTB)/makefiles/Makefile.inc
include $(COCOTB)/makefiles/Makefile.sim

