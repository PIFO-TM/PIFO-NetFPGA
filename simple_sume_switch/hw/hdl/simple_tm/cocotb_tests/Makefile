
TOPLEVEL_LANG = verilog

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
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/det_skip_list/det_skip_list.v

# ===================================== #

TOPLEVEL = cocotb_tm_bp_wrapper

# top level source files -- backpressure is asserted
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/simple_tm/simple_tm_sl_bp.v
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/simple_tm/cocotb_tests/cocotb_tm_bp_wrapper.v

#### Module for testing enq followed by dequeue ####
MODULE=test_simple_tm

# ===================================== #

#TOPLEVEL = cocotb_tm_drop_wrapper

# top level source files -- packets are dropped
#VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/simple_tm/simple_tm_sl_drop.v
#VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/simple_tm/cocotb_tests/cocotb_tm_drop_wrapper.v

#### Module for testing scheduling algorithms ####
#MODULE=test_sched_alg

include $(COCOTB)/makefiles/Makefile.inc
include $(COCOTB)/makefiles/Makefile.sim

