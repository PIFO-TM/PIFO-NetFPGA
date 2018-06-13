
TOPLEVEL_LANG = verilog
TOPLEVEL := traffic_manager

#COMPILE_ARGS=-pfileline=1

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
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/pifo_top/pifo_top.v

# port_tm source files
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/axi_stream_pipeline/axi_stream_pipeline.v
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/port_tm/req_arbiter.v
#VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/port_tm/port_tm.v
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/port_tm/port_tm_bp.v

# top level source files
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/traffic_manager/port_selector.v
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/traffic_manager/traffic_manager.v

MODULE := test_traffic_manager

include $(COCOTB)/makefiles/Makefile.inc
include $(COCOTB)/makefiles/Makefile.sim

