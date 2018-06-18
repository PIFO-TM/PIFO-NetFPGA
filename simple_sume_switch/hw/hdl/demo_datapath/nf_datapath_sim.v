`timescale 1ns / 1ps
//-
// Copyright (c) 2018 Stephen Ibanez 
// All rights reserved.
//
// This software was developed by Stanford University and the University of Cambridge Computer Laboratory 
// under National Science Foundation under Grant No. CNS-0855268,
// the University of Cambridge Computer Laboratory under EPSRC INTERNET Project EP/H040536/1 and
// by the University of Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249 ("MRC2"), 
// as part of the DARPA MRC research programme.
//
//  File:
//        nf_datapath_sim.v
//
//  Module:
//        nf_datapath_sim
//
//  Author: Stephen Ibanez
//
//  Description:
//        NetFPGA user data path wrapper, wrapping input arbiter, output port lookup and output queues
//
//
// @NETFPGA_LICENSE_HEADER_START@
//
// Licensed to NetFPGA C.I.C. (NetFPGA) under one or more contributor
// license agreements.  See the NOTICE file distributed with this work for
// additional information regarding copyright ownership.  NetFPGA licenses this
// file to you under the NetFPGA Hardware-Software License, Version 1.0 (the
// "License"); you may not use this file except in compliance with the
// License.  You may obtain a copy of the License at:
//
//   http://www.netfpga-cic.org
//
// Unless required by applicable law or agreed to in writing, Work distributed
// under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations under the License.
//
// @NETFPGA_LICENSE_HEADER_END@
//


module nf_datapath_sim #(
    //Slave AXI parameters
    parameter C_S_AXI_DATA_WIDTH    = 32,          
    parameter C_S_AXI_ADDR_WIDTH    = 32,          
     parameter C_BASEADDR            = 32'h00000000,

    // Master AXI Stream Data Width
    parameter C_M_AXIS_DATA_WIDTH=256,
    parameter C_S_AXIS_DATA_WIDTH=256,
    parameter C_M_AXIS_TUSER_WIDTH=128,
    parameter C_S_AXIS_TUSER_WIDTH=128
)
(
    //Datapath clock
    input                                     axis_aclk,
    input                                     axis_resetn,
    
    // Slave Stream Ports (interface from Rx queues)
    input [C_S_AXIS_DATA_WIDTH - 1:0]         s_axis_0_tdata,
    input [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0] s_axis_0_tkeep,
    input [C_S_AXIS_TUSER_WIDTH-1:0]          s_axis_0_tuser,
    input                                     s_axis_0_tvalid,
    output                                    s_axis_0_tready,
    input                                     s_axis_0_tlast,
    input [C_S_AXIS_DATA_WIDTH - 1:0]         s_axis_1_tdata,
    input [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0] s_axis_1_tkeep,
    input [C_S_AXIS_TUSER_WIDTH-1:0]          s_axis_1_tuser,
    input                                     s_axis_1_tvalid,
    output                                    s_axis_1_tready,
    input                                     s_axis_1_tlast,
    input [C_S_AXIS_DATA_WIDTH - 1:0]         s_axis_2_tdata,
    input [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0] s_axis_2_tkeep,
    input [C_S_AXIS_TUSER_WIDTH-1:0]          s_axis_2_tuser,
    input                                     s_axis_2_tvalid,
    output                                    s_axis_2_tready,
    input                                     s_axis_2_tlast,
    input [C_S_AXIS_DATA_WIDTH - 1:0]         s_axis_3_tdata,
    input [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0] s_axis_3_tkeep,
    input [C_S_AXIS_TUSER_WIDTH-1:0]          s_axis_3_tuser,
    input                                     s_axis_3_tvalid,
    output                                    s_axis_3_tready,
    input                                     s_axis_3_tlast,
    input [C_S_AXIS_DATA_WIDTH - 1:0]         s_axis_4_tdata,
    input [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0] s_axis_4_tkeep,
    input [C_S_AXIS_TUSER_WIDTH-1:0]          s_axis_4_tuser,
    input                                     s_axis_4_tvalid,
    output                                    s_axis_4_tready,
    input                                     s_axis_4_tlast,


    // Master Stream Ports (interface to TX queues)
    output [C_M_AXIS_DATA_WIDTH - 1:0]         nf0_m_axis_tdata,
    output [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] nf0_m_axis_tkeep,
    output [C_M_AXIS_TUSER_WIDTH-1:0]          nf0_m_axis_tuser,
    output                                     nf0_m_axis_tvalid,
    input                                      nf0_m_axis_tready,
    output                                     nf0_m_axis_tlast,

    output [C_M_AXIS_DATA_WIDTH - 1:0]         nf1_m_axis_tdata,
    output [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] nf1_m_axis_tkeep,
    output [C_M_AXIS_TUSER_WIDTH-1:0]          nf1_m_axis_tuser,
    output                                     nf1_m_axis_tvalid,
    input                                      nf1_m_axis_tready,
    output                                     nf1_m_axis_tlast,

    output [C_M_AXIS_DATA_WIDTH - 1:0]         nf2_m_axis_tdata,
    output [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] nf2_m_axis_tkeep,
    output [C_M_AXIS_TUSER_WIDTH-1:0]          nf2_m_axis_tuser,
    output                                     nf2_m_axis_tvalid,
    input                                      nf2_m_axis_tready,
    output                                     nf2_m_axis_tlast,

    output [C_M_AXIS_DATA_WIDTH - 1:0]         nf3_m_axis_tdata,
    output [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] nf3_m_axis_tkeep,
    output [C_M_AXIS_TUSER_WIDTH-1:0]          nf3_m_axis_tuser,
    output                                     nf3_m_axis_tvalid,
    input                                      nf3_m_axis_tready,
    output                                     nf3_m_axis_tlast

    );
    
    //internal connectivity
     
    wire [C_M_AXIS_DATA_WIDTH - 1:0]         s_axis_opl_tdata;
    wire [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] s_axis_opl_tkeep;
    wire [C_M_AXIS_TUSER_WIDTH-1:0]          s_axis_opl_tuser;
    wire                                     s_axis_opl_tvalid;
    wire                                     s_axis_opl_tready;
    wire                                     s_axis_opl_tlast;

 
  //Input Arbiter
  input_arbiter_drr 
 input_arbiter_v1_0 (
      .axis_aclk(axis_aclk), 
      .axis_resetn(axis_resetn), 
      .m_axis_tdata (s_axis_opl_tdata), 
      .m_axis_tkeep (s_axis_opl_tkeep), 
      .m_axis_tuser (s_axis_opl_tuser), 
      .m_axis_tvalid(s_axis_opl_tvalid), 
      .m_axis_tready(s_axis_opl_tready), 
      .m_axis_tlast (s_axis_opl_tlast), 
      .s_axis_0_tdata (s_axis_0_tdata), 
      .s_axis_0_tkeep (s_axis_0_tkeep), 
      .s_axis_0_tuser (s_axis_0_tuser), 
      .s_axis_0_tvalid(s_axis_0_tvalid), 
      .s_axis_0_tready(s_axis_0_tready), 
      .s_axis_0_tlast (s_axis_0_tlast), 
      .s_axis_1_tdata (s_axis_1_tdata), 
      .s_axis_1_tkeep (s_axis_1_tkeep), 
      .s_axis_1_tuser (s_axis_1_tuser), 
      .s_axis_1_tvalid(s_axis_1_tvalid), 
      .s_axis_1_tready(s_axis_1_tready), 
      .s_axis_1_tlast (s_axis_1_tlast), 
      .s_axis_2_tdata (s_axis_2_tdata), 
      .s_axis_2_tkeep (s_axis_2_tkeep), 
      .s_axis_2_tuser (s_axis_2_tuser), 
      .s_axis_2_tvalid(s_axis_2_tvalid), 
      .s_axis_2_tready(s_axis_2_tready), 
      .s_axis_2_tlast (s_axis_2_tlast), 
      .s_axis_3_tdata (s_axis_3_tdata), 
      .s_axis_3_tkeep (s_axis_3_tkeep), 
      .s_axis_3_tuser (s_axis_3_tuser), 
      .s_axis_3_tvalid(s_axis_3_tvalid), 
      .s_axis_3_tready(s_axis_3_tready), 
      .s_axis_3_tlast (s_axis_3_tlast), 
      .s_axis_4_tdata (s_axis_4_tdata), 
      .s_axis_4_tkeep (s_axis_4_tkeep), 
      .s_axis_4_tuser (s_axis_4_tuser), 
      .s_axis_4_tvalid(s_axis_4_tvalid), 
      .s_axis_4_tready(s_axis_4_tready), 
      .s_axis_4_tlast (s_axis_4_tlast)
    );    
       
   demo_datapath
   #(
       .C_M_AXIS_DATA_WIDTH(C_M_AXIS_DATA_WIDTH),
       .C_S_AXIS_DATA_WIDTH(C_S_AXIS_DATA_WIDTH),
       .C_M_AXIS_TUSER_WIDTH(C_M_AXIS_TUSER_WIDTH),
       .C_S_AXIS_TUSER_WIDTH(C_S_AXIS_TUSER_WIDTH),
       .PIFO_DEPTH  (4096),
       .PIFO_REG_DEPTH (16),
       .STORAGE_MAX_PKTS (2048),
       .NUM_SKIP_LISTS (8),
       .NUM_QUEUES (3)
   )
   demo_datapath_inst
   (
       // Global Ports
       .axis_aclk (axis_aclk),
       .axis_resetn (axis_resetn),

       // Input Pkt Logs
       .nf3_m_axis_tdata   (nf3_m_axis_tdata),
       .nf3_m_axis_tkeep   (nf3_m_axis_tkeep),
       .nf3_m_axis_tuser   (nf3_m_axis_tuser),
       .nf3_m_axis_tvalid  (nf3_m_axis_tvalid),
       .nf3_m_axis_tready  (nf3_m_axis_tready),
       .nf3_m_axis_tlast   (nf3_m_axis_tlast),

       // Output Pkt Logs
       .nf2_m_axis_tdata   (nf2_m_axis_tdata),
       .nf2_m_axis_tkeep   (nf2_m_axis_tkeep),
       .nf2_m_axis_tuser   (nf2_m_axis_tuser),
       .nf2_m_axis_tvalid  (nf2_m_axis_tvalid),
       .nf2_m_axis_tready  (nf2_m_axis_tready),
       .nf2_m_axis_tlast   (nf2_m_axis_tlast),

       // Output Pkts nf1
       .nf1_m_axis_tdata   (nf1_m_axis_tdata),
       .nf1_m_axis_tkeep   (nf1_m_axis_tkeep),
       .nf1_m_axis_tuser   (nf1_m_axis_tuser),
       .nf1_m_axis_tvalid  (nf1_m_axis_tvalid),
       .nf1_m_axis_tready  (nf1_m_axis_tready),
       .nf1_m_axis_tlast   (nf1_m_axis_tlast),

       // Output Pkts nf0
       .nf0_m_axis_tdata   (nf0_m_axis_tdata),
       .nf0_m_axis_tkeep   (nf0_m_axis_tkeep),
       .nf0_m_axis_tuser   (nf0_m_axis_tuser),
       .nf0_m_axis_tvalid  (nf0_m_axis_tvalid),
       .nf0_m_axis_tready  (nf0_m_axis_tready),
       .nf0_m_axis_tlast   (nf0_m_axis_tlast),

       // input pkts
       .s_axis_tdata  (s_axis_opl_tdata),
       .s_axis_tkeep  (s_axis_opl_tkeep),
       .s_axis_tuser  (s_axis_opl_tuser),
       .s_axis_tvalid (s_axis_opl_tvalid),
       .s_axis_tready (s_axis_opl_tready),
       .s_axis_tlast  (s_axis_opl_tlast)
   );

`ifdef COCOTB_SIM
initial begin
  $dumpfile ("nf_datapath_sim_waveform.vcd");
  $dumpvars (0, nf_datapath_sim);
  #1 $display("Sim running...");
end
`endif

endmodule

