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
    parameter DST_PORT_POS         = 24,
    parameter BP_COUNT_POS         = 32,
    parameter BP_COUNT_WIDTH       = 16,
    parameter Q_ID_POS             = BP_COUNT_POS+BP_COUNT_WIDTH,
    parameter Q_ID_WIDTH           = 8,
    parameter RANK_OP_POS          = Q_ID_POS+Q_ID_WIDTH,
    parameter RANK_OP_WIDTH        = 8,
    parameter SRPT_RANK_POS        = RANK_OP_POS+RANK_OP_WIDTH,
    parameter SRPT_RANK_WIDTH      = 16,
    parameter LOG_PKT_POS          = SRPT_RANK_POS+SRPT_RANK_WIDTH,
    parameter LOG_PKT_WIDTH         = 8,

    // max num pkts the pifo can store
    parameter PIFO_DEPTH = 4096,
    parameter PIFO_REG_DEPTH = 16,
    parameter STORAGE_MAX_PKTS = 2048,
    parameter NUM_SKIP_LISTS = 8,
    parameter NUM_QUEUES =  3
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

    // nf1 Pkt Stream Ports (Output Pkts)
    output     [C_M_AXIS_DATA_WIDTH - 1:0]         nf1_m_axis_tdata,
    output     [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] nf1_m_axis_tkeep,
    output     [C_M_AXIS_TUSER_WIDTH-1:0]          nf1_m_axis_tuser,
    output                                         nf1_m_axis_tvalid,
    input                                          nf1_m_axis_tready,
    output                                         nf1_m_axis_tlast,

    // nf0 Pkt Stream Ports (Output Pkts)
    output     [C_M_AXIS_DATA_WIDTH - 1:0]         nf0_m_axis_tdata,
    output     [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] nf0_m_axis_tkeep,
    output     [C_M_AXIS_TUSER_WIDTH-1:0]          nf0_m_axis_tuser,
    output                                         nf0_m_axis_tvalid,
    input                                          nf0_m_axis_tready,
    output                                         nf0_m_axis_tlast,

    // Slave Pkt Stream Ports (incomming pkts)
    input [C_S_AXIS_DATA_WIDTH - 1:0]              s_axis_tdata,
    input [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0]      s_axis_tkeep,
    input [C_S_AXIS_TUSER_WIDTH-1:0]               s_axis_tuser,
    input                                          s_axis_tvalid,
    output                                         s_axis_tready,
    input                                          s_axis_tlast

);

   // ------------- localparams ---------------

   localparam Q_SIZE_BITS = 16;

   localparam IDLE          = 0;
   localparam FINISH_PKT    = 1;
   localparam L2_NUM_STATES = 1;

   // ------------- wires ---------------

   wire [C_S_AXIS_DATA_WIDTH - 1:0]              tm_m_axis_tdata;
   wire [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0]      tm_m_axis_tkeep;
   wire [C_S_AXIS_TUSER_WIDTH-1:0]               tm_m_axis_tuser;
   wire                                          tm_m_axis_tvalid;
   wire                                          tm_m_axis_tready;
   wire                                          tm_m_axis_tlast;

   wire [C_S_AXIS_DATA_WIDTH - 1:0]              rl_m_axis_tdata;
   wire [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0]      rl_m_axis_tkeep;
   wire [C_S_AXIS_TUSER_WIDTH-1:0]               rl_m_axis_tuser;
   wire                                          rl_m_axis_tvalid;
   wire                                          rl_m_axis_tready;
   wire                                          rl_m_axis_tlast;

   reg [L2_NUM_STATES-1:0] tm_state, tm_state_next;
   reg s_axis_tm_tvalid;

   reg [L2_NUM_STATES-1:0] log_state, log_state_next;
   reg s_axis_log_tvalid;

   wire [Q_SIZE_BITS-1:0]   qsize_0;
   wire [Q_SIZE_BITS-1:0]   qsize_1;
   wire [Q_SIZE_BITS-1:0]   qsize_2;

   // ------------- Modules ---------------

   // slave interface  - top level slave interface
   // master interface - rate limiter slave interface
   simple_rank_tm
   #(
       .BP_COUNT_POS      (BP_COUNT_POS), 
       .BP_COUNT_WIDTH    (BP_COUNT_WIDTH), 
       .Q_ID_POS          (Q_ID_POS), 
       .Q_ID_WIDTH        (Q_ID_WIDTH), 
       .RANK_OP_POS       (RANK_OP_POS), 
       .RANK_OP_WIDTH     (RANK_OP_WIDTH), 
       .SRPT_RANK_POS     (SRPT_RANK_POS), 
       .SRPT_RANK_WIDTH   (SRPT_RANK_WIDTH),

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
       .s_axis_tvalid (s_axis_tm_tvalid), // only accept pkts towards nf0
       .s_axis_tready (s_axis_tready),
       .s_axis_tlast  (s_axis_tlast),
       // queue size info
       .qsize_0       (qsize_0),
       .qsize_1       (qsize_1),
       .qsize_2       (qsize_2)
   );

   // slave interface  - simple_tm master interface
   // master interface - top level nf0 interface
   // TODO: need to add a packet aggregation module after this?
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
       .m_axis_tdata (nf0_m_axis_tdata),
       .m_axis_tkeep (nf0_m_axis_tkeep),
       .m_axis_tuser (nf0_m_axis_tuser),
       .m_axis_tvalid(nf0_m_axis_tvalid),
       .m_axis_tready(nf0_m_axis_tready),
       .m_axis_tlast (nf0_m_axis_tlast),
       // pkt_storage input pkts
       .s_axis_tdata  (tm_m_axis_tdata),
       .s_axis_tkeep  (tm_m_axis_tkeep),
       .s_axis_tuser  (tm_m_axis_tuser),
       .s_axis_tvalid (tm_m_axis_tvalid),
       .s_axis_tready (tm_m_axis_tready),
       .s_axis_tlast  (tm_m_axis_tlast)
   );

   // Output queues
   // slave interface  - top level slave interface
   // master interface - top level nf1 and nf2 interfaces
    simple_output_queues
    #(
        .DST_PORT_POS(DST_PORT_POS)
    )
    bram_output_queues
    (
        .axis_aclk(axis_aclk),
        .axis_resetn(axis_resetn),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tkeep  (s_axis_tkeep),
        .s_axis_tuser  (s_axis_tuser),
        .s_axis_tvalid (s_axis_tvalid & s_axis_tready),
        .s_axis_tready (), // does not assert back-pressure
        .s_axis_tlast  (s_axis_tlast),
        .m_axis_0_tdata (nf1_m_axis_tdata),
        .m_axis_0_tkeep (nf1_m_axis_tkeep),
        .m_axis_0_tuser (nf1_m_axis_tuser),
        .m_axis_0_tvalid(nf1_m_axis_tvalid),
        .m_axis_0_tready(nf1_m_axis_tready),
        .m_axis_0_tlast (nf1_m_axis_tlast),
        .m_axis_1_tdata (nf2_m_axis_tdata),
        .m_axis_1_tkeep (nf2_m_axis_tkeep),
        .m_axis_1_tuser (nf2_m_axis_tuser),
        .m_axis_1_tvalid(nf2_m_axis_tvalid),
        .m_axis_1_tready(nf2_m_axis_tready),
        .m_axis_1_tlast (nf2_m_axis_tlast)
    );

   // slave interface  - top level slave interface
   // master interface - top level nf3 interface
   trim_ts
   #(
       .Q_ID_POS         (Q_ID_POS),
       .Q_ID_WIDTH       (Q_ID_WIDTH),
       .SRPT_RANK_POS    (SRPT_RANK_POS),
       .SRPT_RANK_WIDTH  (SRPT_RANK_WIDTH),

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
       .s_axis_tvalid (s_axis_log_tvalid & s_axis_tready), // only record pkts with log_pkt bit set
       .s_axis_tready (),
       .s_axis_tlast  (s_axis_tlast),
       // queue size data
       .qsize_0       (qsize_0),
       .qsize_1       (qsize_1),
       .qsize_2       (qsize_2)
   );


   /* TM tvalid generation logic */
   always @(*) begin
       tm_state_next = tm_state;

       case(tm_state)
           IDLE: begin
               // only generate valid for pkts towards nf0
               if (s_axis_tvalid & s_axis_tuser[DST_PORT_POS]) begin
                   s_axis_tm_tvalid = 1;
                   tm_state_next = FINISH_PKT;
               end
               else begin
                   s_axis_tm_tvalid = 0;
               end
           end

           FINISH_PKT: begin
               s_axis_tm_tvalid = s_axis_tvalid;
               if (s_axis_tvalid & s_axis_tready & s_axis_tlast) begin
                   tm_state_next = IDLE;
               end
           end
       endcase
   end

   always @(posedge axis_aclk) begin
       if (~axis_resetn) begin
           tm_state <= IDLE;
       end
       else begin
           tm_state <= tm_state_next;
       end
   end


   /* Log Pkt tvalid generation logic */
   always @(*) begin
       log_state_next = log_state;

       case(log_state)
           IDLE: begin
               // only generate valid for pkts that have log_pkt bit set 
               if (s_axis_tvalid & s_axis_tuser[LOG_PKT_POS]) begin
                   s_axis_log_tvalid = 1;
                   log_state_next = FINISH_PKT;
               end
               else begin
                   s_axis_log_tvalid = 0;
               end
           end

           FINISH_PKT: begin
               s_axis_log_tvalid = s_axis_tvalid;
               if (s_axis_tvalid & s_axis_tready & s_axis_tlast) begin
                   log_state_next = IDLE;
               end
           end
       endcase
   end

   always @(posedge axis_aclk) begin
       if (~axis_resetn) begin
           log_state <= IDLE;
       end
       else begin
           log_state <= log_state_next;
       end
   end


`ifdef COCOTB_SIM
initial begin
  $dumpfile ("demo_datapath_waveform.vcd");
  $dumpvars (0, demo_datapath);
  #1 $display("Sim running...");
end
`endif

endmodule // demo_datapath

