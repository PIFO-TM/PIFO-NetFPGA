// Copyright 1986-2016 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2016.4 (lin64) Build 1756540 Mon Jan 23 19:11:19 MST 2017
// Date        : Wed Jan 17 22:28:28 2018
// Host        : sibanez-netfpga running 64-bit Ubuntu 14.04.5 LTS
// Command     : write_verilog -force -mode synth_stub
//               /home/sibanez/projects/PIFO-TM/P4-NetFPGA-PIFO-TM/contrib-projects/sume-sdnet-switch/projects/pifo/simple_sume_switch/hw/vivado_ip/segment_bram/segment_bram_stub.v
// Design      : segment_bram
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7vx485tffg1157-1
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "blk_mem_gen_v8_3_5,Vivado 2016.4" *)
module segment_bram(clka, wea, addra, dina, clkb, enb, addrb, doutb)
/* synthesis syn_black_box black_box_pad_pin="clka,wea[0:0],addra[11:0],dina[587:0],clkb,enb,addrb[11:0],doutb[587:0]" */;
  input clka;
  input [0:0]wea;
  input [11:0]addra;
  input [587:0]dina;
  input clkb;
  input enb;
  input [11:0]addrb;
  output [587:0]doutb;
endmodule
