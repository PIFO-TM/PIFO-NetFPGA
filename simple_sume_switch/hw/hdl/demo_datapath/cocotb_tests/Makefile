
TOPLEVEL_LANG = verilog

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
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/pifo_reg/min.v
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/pifo_reg/max.v
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/det_skip_list/det_skip_list.v
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/pifo_top/pifo_top.v
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/axi_stream_fifo/axi_stream_fifo.v

# rank pipe files
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/rank_pipe/strict_rank.v
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/rank_pipe/rr_rank.v
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/rank_pipe/wrr_rank.v
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/rank_pipe/rank_pipe.v

# input arbiter files
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/input_arbiter/input_arbiter_drr.v

# top level source files -- packets are dropped
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/simple_rank_tm/simple_rank_tm.v
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/rate_limiter/rate_limiter.v
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/trim_ts/trim_ts.v
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/simple_output_queues/simple_output_queues.v
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/demo_datapath/demo_datapath.v
VERILOG_SOURCES += $(NF_DESIGN_DIR)/hw/hdl/demo_datapath/nf_datapath_sim.v

# ===================================== #

#TOPLEVEL = demo_datapath
TOPLEVEL = nf_datapath_sim

### Module for testing scheduling algorithms ####
MODULE=test_sched_alg_demo


include $(COCOTB)/makefiles/Makefile.inc
include $(COCOTB)/makefiles/Makefile.sim

