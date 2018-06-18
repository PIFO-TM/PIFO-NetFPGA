//-
// Copyright (C) 2010, 2011 The Board of Trustees of The Leland Stanford
//                          Junior University
// Copyright (C) 2010, 2011 Adam Covington
// Copyright (C) 2015 Noa Zilberman
// Copyright (C) 2017 Gianni Antichi
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
 *        input_arbiter_drr.v
 *
 *  Library:
 *        hw/std/cores/input_arbiter_drr
 *
 *  Module:
 *        input_arbiter_drr
 *
 *  Author:
 *        Adam Covington
 *        Modified by Noa Zilberman
 *        Modified by Gianni Antichi
 *
 *  Description:
 *        Deficit Round Robin arbiter (N inputs to 1 output)
 *        Inputs have a parameterizable width
 *
 */

module input_arbiter_drr
#(
    // Master AXI Stream Data Width
    parameter C_M_AXIS_DATA_WIDTH=256,
    parameter C_S_AXIS_DATA_WIDTH=256,
    parameter C_M_AXIS_TUSER_WIDTH=128,
    parameter C_S_AXIS_TUSER_WIDTH=128,
    parameter NUM_QUEUES=5,

    // AXI Registers Data Width
    parameter C_S_AXI_DATA_WIDTH    = 32,
    parameter C_S_AXI_ADDR_WIDTH    = 12,
    parameter C_BASEADDR            = 32'h00000000

)
(
    // Part 1: System side signals
    // Global Ports
    input axis_aclk,
    input axis_resetn,

    // Master Stream Ports (interface to data path)
    output [C_M_AXIS_DATA_WIDTH - 1:0] m_axis_tdata,
    output [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] m_axis_tkeep,
    output [C_M_AXIS_TUSER_WIDTH-1:0] m_axis_tuser,
    output m_axis_tvalid,
    input  m_axis_tready,
    output m_axis_tlast,

    // Slave Stream Ports (interface to RX queues)
    input [C_S_AXIS_DATA_WIDTH - 1:0] s_axis_0_tdata,
    input [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0] s_axis_0_tkeep,
    input [C_S_AXIS_TUSER_WIDTH-1:0] s_axis_0_tuser,
    input  s_axis_0_tvalid,
    output s_axis_0_tready,
    input  s_axis_0_tlast,

    input [C_S_AXIS_DATA_WIDTH - 1:0] s_axis_1_tdata,
    input [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0] s_axis_1_tkeep,
    input [C_S_AXIS_TUSER_WIDTH-1:0] s_axis_1_tuser,
    input  s_axis_1_tvalid,
    output s_axis_1_tready,
    input  s_axis_1_tlast,

    input [C_S_AXIS_DATA_WIDTH - 1:0] s_axis_2_tdata,
    input [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0] s_axis_2_tkeep,
    input [C_S_AXIS_TUSER_WIDTH-1:0] s_axis_2_tuser,
    input  s_axis_2_tvalid,
    output s_axis_2_tready,
    input  s_axis_2_tlast,

    input [C_S_AXIS_DATA_WIDTH - 1:0] s_axis_3_tdata,
    input [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0] s_axis_3_tkeep,
    input [C_S_AXIS_TUSER_WIDTH-1:0] s_axis_3_tuser,
    input  s_axis_3_tvalid,
    output s_axis_3_tready,
    input  s_axis_3_tlast,

    input [C_S_AXIS_DATA_WIDTH - 1:0] s_axis_4_tdata,
    input [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0] s_axis_4_tkeep,
    input [C_S_AXIS_TUSER_WIDTH-1:0] s_axis_4_tuser,
    input  s_axis_4_tvalid,
    output s_axis_4_tready,
    input  s_axis_4_tlast

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

   // ------------ Internal Params --------

   localparam  NUM_QUEUES_WIDTH = log2(NUM_QUEUES);


   localparam NUM_STATES = 1;
   localparam IDLE = 0;
   localparam WR_PKT = 1;

   localparam MAX_PKT_SIZE = 2000; // In bytes
   localparam IN_FIFO_DEPTH_BIT = log2(MAX_PKT_SIZE/(C_M_AXIS_DATA_WIDTH / 8));

   localparam QUANTUM = 500; //64;

   // ------------- Regs/ wires -----------

   wire [NUM_QUEUES-1:0]               nearly_full;
   wire [NUM_QUEUES-1:0]               empty;
   wire [C_M_AXIS_DATA_WIDTH-1:0]        in_tdata      [NUM_QUEUES-1:0];
   wire [((C_M_AXIS_DATA_WIDTH/8))-1:0]  in_tkeep      [NUM_QUEUES-1:0];
   wire [C_M_AXIS_TUSER_WIDTH-1:0]             in_tuser      [NUM_QUEUES-1:0];
   wire [NUM_QUEUES-1:0] 	       in_tvalid;
   wire [NUM_QUEUES-1:0]               in_tlast;
   wire [C_M_AXIS_TUSER_WIDTH-1:0]             fifo_out_tuser[NUM_QUEUES-1:0];
   wire [C_M_AXIS_DATA_WIDTH-1:0]        fifo_out_tdata[NUM_QUEUES-1:0];
   wire [((C_M_AXIS_DATA_WIDTH/8))-1:0]  fifo_out_tkeep[NUM_QUEUES-1:0];
   wire [NUM_QUEUES-1:0] 	       fifo_out_tlast;
   wire                                fifo_tvalid;
   wire                                fifo_tlast;
   reg [NUM_QUEUES-1:0]                rd_en;

   wire [NUM_QUEUES_WIDTH-1:0]         cur_queue_plus1;
   reg [NUM_QUEUES_WIDTH-1:0]          cur_queue;
   reg [NUM_QUEUES_WIDTH-1:0]          cur_queue_next;

   reg [NUM_STATES-1:0]                state;
   reg [NUM_STATES-1:0]                state_next;

   wire [NUM_QUEUES_WIDTH-1:0] in_arb_cur_queue = cur_queue;
   wire [NUM_STATES-1:0] in_arb_state = state;


   reg   [15:0]                           drr_count[0:NUM_QUEUES-1];
   reg   [15:0]                           drr_count_next[0:NUM_QUEUES-1];

   wire [15:0] dbg_ddr_count0 = drr_count[0];
   wire [15:0] dbg_ddr_count1 = drr_count[1];
   wire [15:0] dbg_ddr_count2 = drr_count[2];
   wire [15:0] dbg_ddr_count3 = drr_count[3];
   wire [15:0] dbg_ddr_count4 = drr_count[4];

   reg m_axis_tvalid_v;

   // ------------ Modules -------------

   generate
   genvar i;
   for(i=0; i<NUM_QUEUES; i=i+1) begin: in_arb_queues
     fallthrough_small_fifo
        #( .WIDTH(C_M_AXIS_DATA_WIDTH+C_M_AXIS_TUSER_WIDTH+C_M_AXIS_DATA_WIDTH/8+1),
           .MAX_DEPTH_BITS(IN_FIFO_DEPTH_BIT))
      in_arb_fifo
        (// Outputs
         .dout                           ({fifo_out_tlast[i], fifo_out_tuser[i], fifo_out_tkeep[i], fifo_out_tdata[i]}),
         .full                           (),
         .nearly_full                    (nearly_full[i]),
	 .prog_full                      (),
         .empty                          (empty[i]),
         // Inputs
         .din                            ({in_tlast[i], in_tuser[i], in_tkeep[i], in_tdata[i]}),
         .wr_en                          (in_tvalid[i] & ~nearly_full[i]),
         .rd_en                          (rd_en[i]),
         .reset                          (~axis_resetn),
         .clk                            (axis_aclk));

	 always @(posedge axis_aclk) begin
		if(~axis_resetn)
			drr_count[i] <= 0;
		else begin
			if(empty[i])
				drr_count[i] <= 0;
			else
				drr_count[i] <= drr_count_next[i];
		end
	end
      end
   endgenerate

   // ------------- Logic ------------

   assign in_tdata[0]        = s_axis_0_tdata;
   assign in_tkeep[0]        = s_axis_0_tkeep;
   assign in_tuser[0]        = s_axis_0_tuser;
   assign in_tvalid[0]       = s_axis_0_tvalid;
   assign in_tlast[0]        = s_axis_0_tlast;
   assign s_axis_0_tready    = !nearly_full[0];

   assign in_tdata[1]        = s_axis_1_tdata;
   assign in_tkeep[1]        = s_axis_1_tkeep;
   assign in_tuser[1]        = s_axis_1_tuser;
   assign in_tvalid[1]       = s_axis_1_tvalid;
   assign in_tlast[1]        = s_axis_1_tlast;
   assign s_axis_1_tready    = !nearly_full[1];

   assign in_tdata[2]        = s_axis_2_tdata;
   assign in_tkeep[2]        = s_axis_2_tkeep;
   assign in_tuser[2]        = s_axis_2_tuser;
   assign in_tvalid[2]       = s_axis_2_tvalid;
   assign in_tlast[2]        = s_axis_2_tlast;
   assign s_axis_2_tready    = !nearly_full[2];

   assign in_tdata[3]        = s_axis_3_tdata;
   assign in_tkeep[3]        = s_axis_3_tkeep;
   assign in_tuser[3]        = s_axis_3_tuser;
   assign in_tvalid[3]       = s_axis_3_tvalid;
   assign in_tlast[3]        = s_axis_3_tlast;
   assign s_axis_3_tready    = !nearly_full[3];

   assign in_tdata[4]        = s_axis_4_tdata;
   assign in_tkeep[4]        = s_axis_4_tkeep;
   assign in_tuser[4]        = s_axis_4_tuser;
   assign in_tvalid[4]       = s_axis_4_tvalid;
   assign in_tlast[4]        = s_axis_4_tlast;
   assign s_axis_4_tready    = !nearly_full[4];

   assign m_axis_tuser = fifo_out_tuser[cur_queue];
   assign m_axis_tdata = fifo_out_tdata[cur_queue];
   assign m_axis_tlast = fifo_out_tlast[cur_queue];
   assign m_axis_tkeep = fifo_out_tkeep[cur_queue];

   assign m_axis_tvalid = m_axis_tvalid_v;

   always @(*) begin
	state_next      = state;
      	cur_queue_next  = cur_queue;
      	rd_en           = 0;

      	//drr_count_next[cur_queue]  = drr_count[cur_queue];
	drr_count_next[0]  = drr_count[0];
	drr_count_next[1]  = drr_count[1];
	drr_count_next[2]  = drr_count[2];
	drr_count_next[3]  = drr_count[3];
	drr_count_next[4]  = drr_count[4];

	m_axis_tvalid_v = 0;
      	case(state)

	/* cycle between input queues until one is not empty */
	IDLE: begin
		if(!empty[cur_queue]) begin
			if(drr_count[cur_queue] >= fifo_out_tuser[cur_queue][15:0]) begin
				m_axis_tvalid_v = 1;
				if(m_axis_tready) begin
					drr_count_next[cur_queue] = drr_count[cur_queue]-fifo_out_tuser[cur_queue][15:0];
					state_next = WR_PKT;
					rd_en[cur_queue] = 1;
				end
			end
			else begin
				drr_count_next[cur_queue] = drr_count[cur_queue] + QUANTUM;
				if (cur_queue == NUM_QUEUES-1)
					cur_queue_next = 0;
				else
					cur_queue_next = cur_queue + 1;
			end
		end
		else
		begin
			if (cur_queue == NUM_QUEUES-1)
				cur_queue_next = 0;
			else
				cur_queue_next = cur_queue + 1;
		end
	end

	WR_PKT: begin
		/* if this is the last word then write it and get out */
           	if(m_axis_tready & m_axis_tlast) begin
              		m_axis_tvalid_v = 1;
			state_next = IDLE;
	      		rd_en[cur_queue] = 1;
              		//cur_queue_next = cur_queue_plus1;
           	end
           	/* otherwise read and write as usual */
           	else if (m_axis_tready & !empty[cur_queue]) begin
              		m_axis_tvalid_v = 1;
			rd_en[cur_queue] = 1;
           	end
	end
      endcase // case(state)
   end // always @ (*)

   always @(posedge axis_aclk) begin
      if(~axis_resetn) begin
         state <= IDLE;
         cur_queue <= 0;
      end
      else begin
         state <= state_next;
         cur_queue <= cur_queue_next;
      end
   end

endmodule
