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
 *        req_arbiter.v
 *
 *  Library:
 *
 *  Module:
 *        req_arbiter
 *
 *  Author:
 *        Stephen Ibanez
 * 		
 *  Description:
 *       This module accepts read requests from various output ports and serializes
 *       them for the pkt_storage block using simple round robin scheduling.
 *
 */

module req_arbiter
#(
    parameter L2_NUM_PORTS         = 2,
    parameter NUM_PORTS            = 2**L2_NUM_PORTS
)
(
    // Global Ports
    input                                      axis_aclk,
    input                                      axis_resetn,

    // input requests
    input                                      nf0_sel_valid,
    input  [L2_NUM_PORTS-1:0]                  nf0_sel_queue,
    input                                      nf1_sel_valid,
    input  [L2_NUM_PORTS-1:0]                  nf1_sel_queue,
    input                                      nf2_sel_valid,
    input  [L2_NUM_PORTS-1:0]                  nf2_sel_queue,
    input                                      nf3_sel_valid,
    input  [L2_NUM_PORTS-1:0]                  nf3_sel_queue,

    input                                      sel_out_rd_en,
    output reg                                 sel_out_valid,
    output reg [L2_NUM_PORTS-1:0]              sel_out_queue
);

   //---------------------- Wires and Regs ---------------------------- 
   reg [NUM_PORTS-1:0]     sel_valid_in;
   reg [L2_NUM_PORTS-1:0]  sel_queue_in [NUM_PORTS-1:0];

   reg [NUM_PORTS-1:0]     sel_valid_in_r;
   reg [L2_NUM_PORTS-1:0]  sel_queue_in_r [NUM_PORTS-1:0];
  
   reg [L2_NUM_PORTS-1:0]  cur_port;
   reg [NUM_PORTS-1:0]     req_in_rd_en;

   reg                     sel_out_valid_next;
   reg [L2_NUM_PORTS-1:0]  sel_out_queue_next;
 
   //-------------------- Modules and Logic ---------------------------
   always @(*) begin
       sel_valid_in[0] = nf0_sel_valid;
       sel_queue_in[0] = nf0_sel_queue;
       sel_valid_in[1] = nf1_sel_valid;
       sel_queue_in[1] = nf1_sel_queue;
       sel_valid_in[2] = nf2_sel_valid;
       sel_queue_in[2] = nf2_sel_queue;
       sel_valid_in[3] = nf3_sel_valid;
       sel_queue_in[3] = nf3_sel_queue; 
   end

   integer i;
   // register the incomming requests
   always @ (posedge axis_aclk) begin
       if (~axis_resetn) begin
           for (i=0; i<NUM_PORTS; i=i+1) begin
               sel_valid_in_r[i] <= 0;
               sel_queue_in_r[i] <= 0;
           end
       end
       else begin
           for (i=0; i<NUM_PORTS; i=i+1) begin
               if (sel_valid_in[i]) begin
                   // new request arrived, overwrite existing one
                   sel_valid_in_r[i] <= 1;
                   sel_queue_in_r[i] <= sel_queue_in[i];
               end
               else if (req_in_rd_en[i]) begin
                   // read this request out so no longer valid
                   sel_valid_in_r[i] <= 0;
                   sel_queue_in_r[i] <= sel_queue_in_r[i];
               end
               else begin
                   // no change
                   sel_valid_in_r[i] <= sel_valid_in_r[i];
                   sel_queue_in_r[i] <= sel_queue_in_r[i];
               end
           end
       end
   end

   // update cur_port
   always @ (posedge axis_aclk) begin
      if (~axis_resetn) begin
          cur_port <= 0;
      end
      else begin
          // only move to next port when reading from current port or current port has no data 
          if (req_in_rd_en[cur_port] | ~sel_valid_in_r[cur_port]) begin
              cur_port <= (cur_port == NUM_PORTS-1) ? 0 : cur_port + 1;
          end
          else begin
              cur_port <= cur_port;
          end
      end
   end

   // update outputs and req_in_rd_en
   always @(*) begin
       req_in_rd_en = 0;
       sel_out_valid_next = sel_out_valid;
       sel_out_queue_next = sel_out_queue;

       if (~sel_out_valid | (sel_out_valid & sel_out_rd_en)) begin
           // the output is current invalid or it is valid but we are about to read it
           if (sel_valid_in_r[cur_port]) begin
               // the cur_port has valid data
               req_in_rd_en[cur_port] = 1;
               sel_out_valid_next = 1;
               sel_out_queue_next = sel_queue_in_r[cur_port];
           end
           else if (sel_out_valid & sel_out_rd_en) begin
               // the cur_port does not have valid data and we are reading the output
               sel_out_valid_next = 0;
           end
       end
   end

   always @(posedge axis_aclk) begin
       if (~axis_resetn) begin
           sel_out_valid <= 0;
           sel_out_queue <= 0;
       end
       else begin
           sel_out_valid <= sel_out_valid_next;
           sel_out_queue <= sel_out_queue_next;
       end
   end

`ifdef COCOTB_SIM
initial begin
  $dumpfile ("req_arbiter_waveform.vcd");
  $dumpvars (0,req_arbiter);
  #1 $display("Sim running...");
end
`endif
   
endmodule // req_arbiter

