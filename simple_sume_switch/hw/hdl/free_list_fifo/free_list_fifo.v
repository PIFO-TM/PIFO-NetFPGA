//-
// Copyright (c) 2015 University of Cambridge
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
/////////////////////////////////////////////////////////////////////////////////
//
// Module: free_list_fifo.v
// Project: utils
// Description: A wrapper around the fallthrough_small_fifo module that just
//   initializes the free list upon reset.
//
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module free_list_fifo
    #(parameter WIDTH = 72,
      parameter MAX_DEPTH_BITS = 3,
      parameter PROG_FULL_THRESHOLD = 2**MAX_DEPTH_BITS - 1,
      // the number of values to add to the fifo upon reset
      parameter MAX_VAL = 2**MAX_DEPTH_BITS - 1)
    (

     input [WIDTH-1:0] din,     // Data in
     input          wr_en,   // Write enable

     input          rd_en,   // Read the next word

     output [WIDTH-1:0] dout,    // Data out
     output         full,
     output         nearly_full,
     output         prog_full,
     output         empty,

     input          reset,
     input          clk,
     output reg     reset_done
     );

   localparam RST_STATE     = 1;
   localparam NO_RST_STATE  = 2;
   localparam NUM_STATES    = 2;

   reg [NUM_STATES-1:0] state, state_next;

   reg [WIDTH-1:0] fifo_din;
   reg             fifo_wr_en;

   reg [MAX_DEPTH_BITS-1:0] cur_val_next, cur_val;

   /* Segment free list */
   fallthrough_small_fifo #(.WIDTH(WIDTH), .MAX_DEPTH_BITS(MAX_DEPTH_BITS))
      fifo
        (.din         (fifo_din),     // Data in
         .wr_en       (fifo_wr_en),       // Write enable
         .rd_en       (rd_en),       // Read the next word
         .dout        (dout),
         .full        (full),
         .prog_full   (prog_full),
         .nearly_full (nearly_full),
         .empty       (empty),
         .reset       (reset),
         .clk         (clk)
         );


   /* Reset State Machine:
    *   - Add default values to fifo
    */   

   always @(*) begin
      // default values
      state_next   = state;
      cur_val_next = cur_val;
      fifo_din = din;
      fifo_wr_en = wr_en;
      reset_done = 1;

      case(state)
          RST_STATE: begin
              reset_done = 0;
              fifo_din = cur_val;
              fifo_wr_en = 1;
              cur_val_next = cur_val + 1;
              if (cur_val == MAX_VAL) begin
                  state_next = NO_RST_STATE;
              end
          end

          NO_RST_STATE: begin
              cur_val_next = 0;
              if (reset) begin
                  state_next = RST_STATE;
              end
          end
      endcase // case(state)
   end // always @ (*)

   always @(posedge clk) begin
      if(reset) begin
         state <= RST_STATE;
         cur_val <= 0;
      end
      else begin
         state <= state_next;
         cur_val <= cur_val_next;
      end
   end

//`ifdef COCOTB_SIM
//initial begin
//  $dumpfile ("free_list_fifo_waveform.vcd");
//  $dumpvars (0,free_list_fifo);
//  #1 $display("Sim running...");
//end
//`endif

endmodule
