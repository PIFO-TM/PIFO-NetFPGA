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
 *        port_selector.v
 *
 *  Library:
 *
 *  Module:
 *        port_selector
 *
 *  Author:
 *        Stephen Ibanez
 * 		
 *  Description:
 *       This module is responsible for selecting which input port to read from
 *       and then queueing the received pkts in a FIFO.
 */

// `timescale 1ns/1ps

module port_selector
#(
    // Pkt AXI Stream Data Width
    parameter C_M_AXIS_DATA_WIDTH  = 256,
    parameter C_S_AXIS_DATA_WIDTH  = 256,
    parameter C_M_AXIS_TUSER_WIDTH = 128,
    parameter C_S_AXIS_TUSER_WIDTH = 128,
    parameter DST_PORT_POS         = 24,
    parameter PORT_WIDTH           = 8,
    parameter L2_NUM_PORTS         = 2,
    parameter NUM_PORTS            = 2**L2_NUM_PORTS,
    parameter RANK_WIDTH           = 32,
    parameter BUFFER_SIZE          = 8192 // 8192B
)
(
    // Global Ports
    input                                      axis_aclk,
    input                                      axis_resetn,

    // Master Pkt Stream Ports (outgoing pkts) 
    output     [C_M_AXIS_DATA_WIDTH - 1:0]         m_axis_tdata,
    output     [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] m_axis_tkeep,
    output     [C_M_AXIS_TUSER_WIDTH-1:0]          m_axis_tuser,
    output reg                                     m_axis_tvalid,
    input                                          m_axis_tready,
    output                                         m_axis_tlast,

    // Slave Pkt Stream Ports (incomming pkts)
    input [C_S_AXIS_DATA_WIDTH - 1:0]              s_axis_tdata,
    input [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0]      s_axis_tkeep,
    input [C_S_AXIS_TUSER_WIDTH-1:0]               s_axis_tuser,
    input                                          s_axis_tvalid,
    output reg                                     s_axis_tready,
    input                                          s_axis_tlast,

    output reg                                     nf0_sel_valid,
    output reg                                     nf1_sel_valid,
    output reg                                     nf2_sel_valid,
    output reg                                     nf3_sel_valid,

    input                                          nf0_pifo_valid,
    input [RANK_WIDTH-1:0]                         nf0_pifo_rank, 
    input                                          nf1_pifo_valid,
    input [RANK_WIDTH-1:0]                         nf1_pifo_rank, 
    input                                          nf2_pifo_valid,
    input [RANK_WIDTH-1:0]                         nf2_pifo_rank, 
    input                                          nf3_pifo_valid,
    input [RANK_WIDTH-1:0]                         nf3_pifo_rank 

);

   function integer log2;
      input integer number;
      begin
         log2=0;
         while(2**log2<number) begin
            log2=log2+1;
         end
      end
   endfunction // log2

   //--------------------- Internal Parameters-------------------------
   localparam BUFFER_SIZE_BITS   = log2(BUFFER_SIZE/(C_M_AXIS_DATA_WIDTH/8));
   localparam MAX_PACKET_SIZE = 1600;
   localparam BUFFER_THRESHOLD = (BUFFER_SIZE-MAX_PACKET_SIZE)/(C_M_AXIS_DATA_WIDTH/8);

   localparam MIN_PACKET_SIZE = 64;
   localparam META_BUFFER_BITS = log2(BUFFER_SIZE/MIN_PACKET_SIZE);

   localparam IFSM_WAIT_START = 0;
   localparam IFSM_WAIT_END = 1;
   localparam IFSM_BITS = 1;

   localparam RFSM_WAIT_START = 0;
   localparam RFSM_WAIT_END = 1;
   localparam RFSM_BITS = 1;

   localparam CHOOSE_PORT  = 0;
   localparam WRITE_REQ    = 1;
   localparam WAIT_PKT_END = 2;
   localparam SEL_FSM_BITS = 2;

   //---------------------- Wires and Regs ---------------------------- 
   reg wr_en, rd_en;
   wire nearly_full_fifo, empty;

   reg metadata_wr_en, metadata_rd_en;
   wire metadata_nearly_full_fifo, metadata_empty;

   reg [IFSM_BITS-1:0] ifsm_state, ifsm_state_next;   
   reg [RFSM_BITS-1:0] rfsm_state, rfsm_state_next;

   reg                    nf_pifo_valid [L2_NUM_PORTS:0] [NUM_PORTS-1:0];
   reg [RANK_WIDTH-1:0]   nf_pifo_rank  [L2_NUM_PORTS:0] [NUM_PORTS-1:0];
   reg [L2_NUM_PORTS-1:0] nf_pifo_sel   [L2_NUM_PORTS:0] [NUM_PORTS-1:0];
   reg [L2_NUM_PORTS-1:0] rr_ctr, rr_ctr_next;

   reg                    final_sel_valid;
   reg [L2_NUM_PORTS-1:0] final_sel_port;
   
   reg [SEL_FSM_BITS-1:0] sel_state, sel_state_next;
   reg [L2_NUM_PORTS-1:0] final_sel_port_r, final_sel_port_r_next;
 
   //-------------------- Modules and Logic ---------------------------

   fallthrough_small_fifo
     #( .WIDTH(C_M_AXIS_DATA_WIDTH+C_M_AXIS_DATA_WIDTH/8+1),
        .MAX_DEPTH_BITS(BUFFER_SIZE_BITS),
        .PROG_FULL_THRESHOLD(BUFFER_THRESHOLD))
   output_fifo
     (// Outputs
      .dout                           ({m_axis_tlast, m_axis_tkeep, m_axis_tdata}),
      .full                           (),
      .nearly_full                    (),
      .prog_full                      (nearly_full_fifo),
      .empty                          (empty),
      // Inputs
      .din                            ({s_axis_tlast, s_axis_tkeep, s_axis_tdata}),
      .wr_en                          (wr_en),
      .rd_en                          (rd_en),
      .reset                          (~axis_resetn),
      .clk                            (axis_aclk)
     );

   fallthrough_small_fifo
     #( .WIDTH(C_M_AXIS_TUSER_WIDTH),
        .MAX_DEPTH_BITS(META_BUFFER_BITS))
   metadata_fifo
     (// Outputs
      .dout                           (m_axis_tuser),
      .full                           (),
      .nearly_full                    (metadata_nearly_full_fifo),
      .prog_full                      (),
      .empty                          (metadata_empty),
      // Inputs
      .din                            (s_axis_tuser),
      .wr_en                          (metadata_wr_en),
      .rd_en                          (metadata_rd_en),
      .reset                          (~axis_resetn),
      .clk                            (axis_aclk)
     );


   /* Insertion State machine to write pkts into FIFOs
    */
   always @(*) begin
       ifsm_state_next = ifsm_state;
       s_axis_tready = ~nearly_full_fifo & ~metadata_nearly_full_fifo;
       wr_en = 0;
       metadata_wr_en = 0;

       case(ifsm_state)
           IFSM_WAIT_START: begin
               if (s_axis_tvalid & s_axis_tready) begin
                   wr_en = 1;
                   metadata_wr_en = 1;
                   ifsm_state_next = IFSM_WAIT_END;
               end
           end

           IFSM_WAIT_END: begin
               // Finish writing the pkt into storage
               s_axis_tready = 1;
               if(s_axis_tvalid) begin
                   wr_en = 1;
                   if (s_axis_tlast) begin
                       ifsm_state_next = IFSM_WAIT_START;
                   end
               end
           end
       endcase
   end

   always @(posedge axis_aclk) begin
       if (~axis_resetn) begin
           ifsm_state <= IFSM_WAIT_START;
       end
       else begin
           ifsm_state <= ifsm_state_next;
       end
   end

   /* Removal state machine to read pkts out of FIFOs
    */
   always @(*) begin
       rfsm_state_next <= rfsm_state;
       m_axis_tvalid = ~empty;
       rd_en = m_axis_tready & ~empty; //TODO: should we also check: ~metadata_empty ?
       metadata_rd_en = 0;
       case(rfsm_state)
           RFSM_WAIT_START: begin
               if (rd_en) begin
                   metadata_rd_en = 1;
                   rfsm_state_next = RFSM_WAIT_END;
               end
           end

           RFSM_WAIT_END: begin
               if (rd_en & m_axis_tlast) begin
                   rfsm_state_next = RFSM_WAIT_START;
               end
           end
       endcase
   end

   always @(posedge axis_aclk) begin
       if (~axis_resetn) begin
           rfsm_state <= RFSM_WAIT_START;
       end
       else begin
           rfsm_state <= rfsm_state_next;
       end
   end

   integer i, j;
   always @(*) begin
       nf_pifo_valid[0][0] = nf0_pifo_valid;
       nf_pifo_valid[0][1] = nf1_pifo_valid;
       nf_pifo_valid[0][2] = nf2_pifo_valid;
       nf_pifo_valid[0][3] = nf3_pifo_valid;

       nf_pifo_rank[0][0] = nf0_pifo_rank;
       nf_pifo_rank[0][1] = nf1_pifo_rank;
       nf_pifo_rank[0][2] = nf2_pifo_rank;
       nf_pifo_rank[0][3] = nf3_pifo_rank;

       // adjust counter for round robin scheduling just in case all ranks are equal
       if (sel_state == CHOOSE_PORT & (nf0_pifo_valid | nf1_pifo_valid | nf2_pifo_valid | nf3_pifo_valid))
           rr_ctr_next = (rr_ctr == NUM_PORTS-1) ? 0 : rr_ctr + 1;
       else
           rr_ctr_next = rr_ctr;

       /* Make Selection */
       for (j=0; j<L2_NUM_PORTS; j=j+1) begin  // loop over each level
           for (i=0; i<2**(L2_NUM_PORTS-j); i=i+2) begin // loop over each comparator in each level
               nf_pifo_valid[j+1][i/2] = nf_pifo_valid[j][i] | nf_pifo_valid[j][i+1];
               if (nf_pifo_valid[j][i] & nf_pifo_valid[j][i+1]) begin
                   // both ports have valid pkts
                   if (nf_pifo_rank[j][i] < nf_pifo_rank[j][i+1]) begin
                       nf_pifo_rank[j+1][i/2] = nf_pifo_rank[j][i];
                       nf_pifo_sel[j+1][i/2] = i; //TODO: need to trim to appropriate size?
                   end
                   else if (nf_pifo_rank[j][i] > nf_pifo_rank[j][i+1]) begin
                       nf_pifo_rank[j+1][i/2] = nf_pifo_rank[j][i+1];
                       nf_pifo_sel[j+1][i/2] = i+1; //TODO: need to trim to appropriate size?
                   end
                   else begin
                       // the ranks are equal use round robin counter as tie-breaker 
                       nf_pifo_rank[j+1][i/2] = nf_pifo_rank[j][i];
                       if (rr_ctr[j])
                           nf_pifo_sel[j+1][i/2] = i+1; //TODO: need to trim to appropriate size?
                       else
                           nf_pifo_sel[j+1][i/2] = i; //TODO: need to trim to appropriate size?
                   end
               end
               else if (nf_pifo_valid[j][i]) begin
                   nf_pifo_rank[j+1][i/2] = nf_pifo_rank[j][i];
                   nf_pifo_sel[j+1][i/2] = i; //TODO: need to trim to appropriate size?
               end
               else if (nf_pifo_valid[j][i+1]) begin
                   nf_pifo_rank[j+1][i/2] = nf_pifo_rank[j][i+1];
                   nf_pifo_sel[j+1][i/2] = i+1; //TODO: need to trim to appropriate size?
               end
               else begin
                   // neiither port has valid data
                   nf_pifo_rank[j+1][i/2] = 0;
                   nf_pifo_sel[j+1][i/2] = 0;
               end
           end
       end

       final_sel_valid = nf_pifo_valid[L2_NUM_PORTS][0];
       final_sel_port = nf_pifo_sel[L2_NUM_PORTS][0];
 
   end

   always @(posedge axis_aclk) begin
       if (~axis_resetn) begin
           rr_ctr <= 0;
       end
       else begin
           rr_ctr <= rr_ctr_next;
       end
   end

   /* Selection state machine to choose which input port to read from
    */
   always @(*) begin
       sel_state_next = sel_state;

       final_sel_port_r_next = 0;

       nf0_sel_valid = 0;
       nf1_sel_valid = 0;
       nf2_sel_valid = 0;
       nf3_sel_valid = 0;

       case(sel_state)
           CHOOSE_PORT: begin
               final_sel_port_r_next = final_sel_port;
               if (final_sel_valid)
                   sel_state_next = WRITE_REQ;
           end

           WRITE_REQ: begin
               nf0_sel_valid = (final_sel_port_r == 0) ? 1 : 0;
               nf1_sel_valid = (final_sel_port_r == 1) ? 1 : 0;
               nf2_sel_valid = (final_sel_port_r == 2) ? 1 : 0;
               nf3_sel_valid = (final_sel_port_r == 3) ? 1 : 0;
               sel_state_next = WAIT_PKT_END;
           end

           /* Wait for selected pkt to finish before submitting next request */
           WAIT_PKT_END: begin
               if (s_axis_tvalid & s_axis_tready & s_axis_tlast)
                   sel_state_next = CHOOSE_PORT;
           end
       endcase
   end

   always @(posedge axis_aclk) begin
       if (~axis_resetn) begin
           sel_state <= CHOOSE_PORT;
           final_sel_port_r <= 0;
       end
       else begin
           sel_state <= sel_state_next;
           final_sel_port_r <= final_sel_port_r_next;
       end
   end

   
endmodule // port_selector

