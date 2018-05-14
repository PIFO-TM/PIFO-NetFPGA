//-
// Copyright (C) 2010, 2011 The Board of Trustees of The Leland Stanford
//                          Junior University
// Copyright (C) 2018 Stephen Ibanez
// All rights reserved.
//
// This software was developed by
// Stanford University and the University of Cambridge Computer Laboratory
// under National Science Foundation under Grant No. CNS-0855268,
// the University of Cambridge Computer Laboratory under EPSRC INTERNET Project EP/H040536/1 and
// by the University of Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249 ("MRC2"), 
// as part of the DARPA MRC research programme.
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
/*******************************************************************************
 *  File:
 *        demo_datapath.v
 *
 *  Library:
 *
 *  Module:
 *        demo_datapath 
 *
 *  Author:
 *        Stephen Ibanez
 * 		
 *  Description:
 *        The datapath for the PIFO demo.
 *
 */

module demo_datapath
#(
    // Pkt AXI Stream Data Width
    parameter C_M_AXIS_DATA_WIDTH  = 256,
    parameter C_S_AXIS_DATA_WIDTH  = 256,
    parameter C_M_AXIS_TUSER_WIDTH = 128,
    parameter C_S_AXIS_TUSER_WIDTH = 128,
    parameter BP_COUNT_POS         = 32,
    parameter BP_COUNT_WIDTH       = 16,
    parameter Q_ID_POS             = BP_COUNT_POS+BP_COUNT_WIDTH,
    parameter Q_ID_WIDTH           = 8,
    parameter RANK_OP_POS          = Q_ID_POS+Q_ID_WIDTH,
    parameter RANK_OP_WIDTH        = 8,
    parameter FLOW_ID_POS          = RANK_OP_POS+RANK_OP_WIDTH,
    parameter FLOW_ID_WIDTH        = 16,
    parameter FLOW_WEIGHT_POS      = FLOW_ID_POS+FLOW_ID_WIDTH,
    parameter FLOW_WEIGHT_WIDTH    = 8,
    parameter RANK_RST_POS         = FLOW_WEIGHT_POS+FLOW_WEIGHT_WIDTH,
    parameter RANK_RST_WIDTH       = 8,

    parameter MAX_NUM_FLOWS        = 4,

    // max num pkts the pifo can store
    parameter PIFO_DEPTH = 4096,
    parameter PIFO_REG_DEPTH = 16,
    parameter STORAGE_MAX_PKTS = 2048,
    parameter NUM_SKIP_LISTS = 11,
    parameter NUM_QUEUES =  4
)
(
    // Global Ports
    input                                      axis_aclk,
    input                                      axis_resetn,

    // nf3 Pkt Stream Ports (Input Pkt Headers)
    output     [C_M_AXIS_DATA_WIDTH - 1:0]         nf3_m_axis_tdata,
    output     [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] nf3_m_axis_tkeep,
    output     [C_M_AXIS_TUSER_WIDTH-1:0]          nf3_m_axis_tuser,
    output                                         nf3_m_axis_tvalid,
    input                                          nf3_m_axis_tready,
    output                                         nf3_m_axis_tlast,

    // nf2 Pkt Stream Ports (Output Pkt Headers)
    output     [C_M_AXIS_DATA_WIDTH - 1:0]         nf2_m_axis_tdata,
    output     [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] nf2_m_axis_tkeep,
    output     [C_M_AXIS_TUSER_WIDTH-1:0]          nf2_m_axis_tuser,
    output                                         nf2_m_axis_tvalid,
    input                                          nf2_m_axis_tready,
    output                                         nf2_m_axis_tlast,

    // Master Pkt Stream Ports (outgoing pkts)
    output     [C_M_AXIS_DATA_WIDTH - 1:0]         m_axis_tdata,
    output     [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] m_axis_tkeep,
    output     [C_M_AXIS_TUSER_WIDTH-1:0]          m_axis_tuser,
    output                                         m_axis_tvalid,
    input                                          m_axis_tready,
    output                                         m_axis_tlast,

    // Slave Pkt Stream Ports (incomming pkts)
    input [C_S_AXIS_DATA_WIDTH - 1:0]              s_axis_tdata,
    input [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0]      s_axis_tkeep,
    input [C_S_AXIS_TUSER_WIDTH-1:0]               s_axis_tuser,
    input                                          s_axis_tvalid,
    output                                         s_axis_tready,
    input                                          s_axis_tlast

);

   // ------------- wires ---------------

   wire [C_S_AXIS_DATA_WIDTH - 1:0]              tm_m_axis_tdata;
   wire [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0]      tm_m_axis_tkeep;
   wire [C_S_AXIS_TUSER_WIDTH-1:0]               tm_m_axis_tuser;
   wire                                          tm_m_axis_tvalid;
   wire                                          tm_m_axis_tready;
   wire                                          tm_m_axis_tlast;

   localparam Q_SIZE_BITS = 16;

   wire [Q_SIZE_BITS-1:0]   qsize_0;
   wire [Q_SIZE_BITS-1:0]   qsize_1;
   wire [Q_SIZE_BITS-1:0]   qsize_2;
   wire [Q_SIZE_BITS-1:0]   qsize_3;

   // ------------- Modules ---------------

   simple_rank_tm
   #(
       .BP_COUNT_POS      (BP_COUNT_POS), 
       .BP_COUNT_WIDTH    (BP_COUNT_WIDTH), 
       .Q_ID_POS          (Q_ID_POS), 
       .Q_ID_WIDTH        (Q_ID_WIDTH), 
       .RANK_OP_POS       (RANK_OP_POS), 
       .RANK_OP_WIDTH     (RANK_OP_WIDTH), 
       .FLOW_ID_POS       (FLOW_ID_POS), 
       .FLOW_ID_WIDTH     (FLOW_ID_WIDTH), 
       .FLOW_WEIGHT_POS   (FLOW_WEIGHT_POS), 
       .FLOW_WEIGHT_WIDTH (FLOW_WEIGHT_WIDTH),
       .RANK_RST_POS      (RANK_RST_POS), 
       .RANK_RST_WIDTH    (RANK_RST_WIDTH),

       .MAX_NUM_FLOWS     (MAX_NUM_FLOWS),
       .PIFO_DEPTH       (PIFO_DEPTH),
       .PIFO_REG_DEPTH   (PIFO_REG_DEPTH),
       .STORAGE_MAX_PKTS (STORAGE_MAX_PKTS),
       .NUM_SKIP_LISTS   (NUM_SKIP_LISTS),
       .NUM_QUEUES       (NUM_QUEUES),
       .Q_SIZE_BITS      (Q_SIZE_BITS)
   )
   simple_tm_inst
   (
       // Global Ports
       .axis_aclk (axis_aclk),
       .axis_resetn (axis_resetn),
       // pkt_storage output pkts
       .m_axis_tdata  (tm_m_axis_tdata),
       .m_axis_tkeep  (tm_m_axis_tkeep),
       .m_axis_tuser  (tm_m_axis_tuser),
       .m_axis_tvalid (tm_m_axis_tvalid),
       .m_axis_tready (tm_m_axis_tready),
       .m_axis_tlast  (tm_m_axis_tlast),
       // pkt_storage input pkts
       .s_axis_tdata  (s_axis_tdata),
       .s_axis_tkeep  (s_axis_tkeep),
       .s_axis_tuser  (s_axis_tuser),
       .s_axis_tvalid (s_axis_tvalid),
       .s_axis_tready (s_axis_tready),
       .s_axis_tlast  (s_axis_tlast),
       // queue size info
       .qsize_0       (qsize_0),
       .qsize_1       (qsize_1),
       .qsize_2       (qsize_2),
       .qsize_3       (qsize_3)
   );

   rate_limiter
   #(
       .BP_COUNT_POS   (BP_COUNT_POS),
       .BP_COUNT_WIDTH (BP_COUNT_WIDTH)
   )
   rate_limiter_inst
   (
       // Global Ports
       .axis_aclk (axis_aclk),
       .axis_resetn (axis_resetn),
       // pkt_storage output pkts
       .m_axis_tdata  (m_axis_tdata),
       .m_axis_tkeep  (m_axis_tkeep),
       .m_axis_tuser  (m_axis_tuser),
       .m_axis_tvalid (m_axis_tvalid),
       .m_axis_tready (m_axis_tready),
       .m_axis_tlast  (m_axis_tlast),
       // pkt_storage input pkts
       .s_axis_tdata  (tm_m_axis_tdata),
       .s_axis_tkeep  (tm_m_axis_tkeep),
       .s_axis_tuser  (tm_m_axis_tuser),
       .s_axis_tvalid (tm_m_axis_tvalid),
       .s_axis_tready (tm_m_axis_tready),
       .s_axis_tlast  (tm_m_axis_tlast)
   );

   trim_ts
   #(
       .Q_SIZE_BITS      (Q_SIZE_BITS)
   )
   input_trim_ts
   (
       // Global Ports
       .axis_aclk (axis_aclk),
       .axis_resetn (axis_resetn),
       // pkt_storage output pkts
       .m_axis_tdata  (nf3_m_axis_tdata),
       .m_axis_tkeep  (nf3_m_axis_tkeep),
       .m_axis_tuser  (nf3_m_axis_tuser),
       .m_axis_tvalid (nf3_m_axis_tvalid),
       .m_axis_tready (nf3_m_axis_tready),
       .m_axis_tlast  (nf3_m_axis_tlast),
       // pkt_storage input pkts
       .s_axis_tdata  (s_axis_tdata),
       .s_axis_tkeep  (s_axis_tkeep),
       .s_axis_tuser  (s_axis_tuser),
       .s_axis_tvalid (s_axis_tvalid & s_axis_tready),
       .s_axis_tready (),
       .s_axis_tlast  (s_axis_tlast),
       // queue size data
       .qsize_0       (qsize_0),
       .qsize_1       (qsize_1),
       .qsize_2       (qsize_2),
       .qsize_3       (qsize_3)
   );

   trim_ts
   #(
       .Q_SIZE_BITS      (Q_SIZE_BITS)
   )
   output_trim_ts
   (
       // Global Ports
       .axis_aclk (axis_aclk),
       .axis_resetn (axis_resetn),
       // pkt_storage output pkts
       .m_axis_tdata  (nf2_m_axis_tdata),
       .m_axis_tkeep  (nf2_m_axis_tkeep),
       .m_axis_tuser  (nf2_m_axis_tuser),
       .m_axis_tvalid (nf2_m_axis_tvalid),
       .m_axis_tready (nf2_m_axis_tready),
       .m_axis_tlast  (nf2_m_axis_tlast),
       // pkt_storage input pkts
       .s_axis_tdata  (tm_m_axis_tdata),
       .s_axis_tkeep  (tm_m_axis_tkeep),
       .s_axis_tuser  (tm_m_axis_tuser),
       .s_axis_tvalid (tm_m_axis_tvalid & tm_m_axis_tready),
       .s_axis_tready (),
       .s_axis_tlast  (tm_m_axis_tlast),
       // queue size data
       .qsize_0       (qsize_0),
       .qsize_1       (qsize_1),
       .qsize_2       (qsize_2),
       .qsize_3       (qsize_3)
   );

`ifdef COCOTB_SIM
initial begin
  $dumpfile ("demo_datapath_waveform.vcd");
  $dumpvars (0, demo_datapath);
  #1 $display("Sim running...");
end
`endif

endmodule // demo_datapath

