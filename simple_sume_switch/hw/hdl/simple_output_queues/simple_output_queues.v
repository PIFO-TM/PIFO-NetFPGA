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
 *        simple_output_queues.v
 *
 *  Module:
 *        simple_output_queues
 *
 *  Author:
 *        Stephen Ibanez
 * 		
 *  Description:
 *        A very simple BRAM output queues module. 
 *
 */

module simple_output_queues 
#(
    // Pkt AXI Stream Data Width
    parameter C_M_AXIS_DATA_WIDTH  = 256,
    parameter C_S_AXIS_DATA_WIDTH  = 256,
    parameter C_M_AXIS_TUSER_WIDTH = 128,
    parameter C_S_AXIS_TUSER_WIDTH = 128,

    parameter DST_PORT_POS         = 24,
    parameter NUM_PORTS            = 2
)
(
    // Global Ports
    input                                      axis_aclk,
    input                                      axis_resetn,

    // Master Pkt Stream (Port 0) 
    output     [C_M_AXIS_DATA_WIDTH - 1:0]         m_axis_0_tdata,
    output     [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] m_axis_0_tkeep,
    output     [C_M_AXIS_TUSER_WIDTH-1:0]          m_axis_0_tuser,
    output                                         m_axis_0_tvalid,
    input                                          m_axis_0_tready,
    output                                         m_axis_0_tlast,

    // Master Pkt Stream (Port 1) 
    output     [C_M_AXIS_DATA_WIDTH - 1:0]         m_axis_1_tdata,
    output     [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] m_axis_1_tkeep,
    output     [C_M_AXIS_TUSER_WIDTH-1:0]          m_axis_1_tuser,
    output                                         m_axis_1_tvalid,
    input                                          m_axis_1_tready,
    output                                         m_axis_1_tlast,

    // Slave Pkt Stream Ports (incomming pkts)
    input [C_S_AXIS_DATA_WIDTH - 1:0]              s_axis_tdata,
    input [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0]      s_axis_tkeep,
    input [C_S_AXIS_TUSER_WIDTH-1:0]               s_axis_tuser,
    input                                          s_axis_tvalid,
    output                                         s_axis_tready,
    input                                          s_axis_tlast

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
   /* For Insertion FSM */
   localparam WAIT_START     = 0;
   localparam RCV_WORD       = 1;
   localparam DROP_PKT       = 2;
   localparam L2_IFSM_STATES = 2;

   /* For Removal FSM */
   localparam RFSM_START = 0;
   localparam RFSM_FINISH_PKT = 1;
   localparam L2_RFSM_STATES = 1;   

   localparam MAX_DEPTH = 256; // measured in 32B words
   localparam L2_MAX_DEPTH = log2(MAX_DEPTH);

   localparam MAX_PKTS = MAX_DEPTH/2; // min pkt size is 64B
   localparam L2_MAX_PKTS = log2(MAX_PKTS);

   localparam MAX_PKT_SIZE = 50; // measured in 32B words
   localparam BUFFER_THRESHOLD = MAX_DEPTH-MAX_PKT_SIZE;

   //---------------------- Wires and Regs ---------------------------- 
   reg  [NUM_PORTS-1:0]  d_fifo_wr_en;
   reg  [NUM_PORTS-1:0]  d_fifo_rd_en;
   wire [NUM_PORTS-1:0]  d_fifo_nearly_full;
   wire [NUM_PORTS-1:0]  d_fifo_empty;

   reg  [NUM_PORTS-1:0]  m_fifo_wr_en;
   reg  [NUM_PORTS-1:0]  m_fifo_rd_en;
   wire [NUM_PORTS-1:0]  m_fifo_nearly_full;
   wire [NUM_PORTS-1:0]  m_fifo_empty;

   reg [L2_IFSM_STATES-1:0] ifsm_state [NUM_PORTS-1:0];
   reg [L2_IFSM_STATES-1:0] ifsm_state_next [NUM_PORTS-1:0];
   reg [L2_RFSM_STATES-1:0] rfsm_state [NUM_PORTS-1:0];
   reg [L2_RFSM_STATES-1:0] rfsm_state_next [NUM_PORTS-1:0];

   wire  [C_M_AXIS_DATA_WIDTH - 1:0]         m_axis_tdata [NUM_PORTS-1:0];
   wire  [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] m_axis_tkeep [NUM_PORTS-1:0];
   wire  [C_M_AXIS_TUSER_WIDTH-1:0]          m_axis_tuser [NUM_PORTS-1:0];
   reg   [NUM_PORTS-1:0]                     m_axis_tvalid;
   wire  [NUM_PORTS-1:0]                     m_axis_tready;
   wire  [NUM_PORTS-1:0]                     m_axis_tlast;

   reg cur_queue_r_next, cur_queue_r;
 
   //-------------------- Modules and Logic ---------------------------
   // Do not propagate back pressure
   assign s_axis_tready = 1;

   genvar i;
   generate
   for (i=0; i<NUM_PORTS; i=i+1) begin: output_queues
       fallthrough_small_fifo 
          #(
              .WIDTH(C_M_AXIS_DATA_WIDTH+C_M_AXIS_DATA_WIDTH/8+1),
              .MAX_DEPTH_BITS(L2_MAX_DEPTH),
              .PROG_FULL_THRESHOLD(BUFFER_THRESHOLD)
          )
          data_fifo
            (.din         ({s_axis_tlast, s_axis_tkeep, s_axis_tdata}),     // Data in
             .wr_en       (d_fifo_wr_en[i]),       // Write enable
             .rd_en       (d_fifo_rd_en[i]),       // Read the next word
             .dout        ({m_axis_tlast[i], m_axis_tkeep[i], m_axis_tdata[i]}),
             .full        (),
             .prog_full   (d_fifo_nearly_full[i]),
             .nearly_full (),
             .empty       (d_fifo_empty[i]),
             .reset       (~axis_resetn),
             .clk         (axis_aclk)
             );

       fallthrough_small_fifo 
          #(
              .WIDTH(C_M_AXIS_TUSER_WIDTH),
              .MAX_DEPTH_BITS(L2_MAX_PKTS)
          )
          meta_fifo
            (.din         (s_axis_tuser),     // Data in
             .wr_en       (m_fifo_wr_en[i]),       // Write enable
             .rd_en       (m_fifo_rd_en[i]),       // Read the next word
             .dout        (m_axis_tuser[i]),
             .full        (),
             .prog_full   (),
             .nearly_full (m_fifo_nearly_full[i]),
             .empty       (m_fifo_empty[i]),
             .reset       (~axis_resetn),
             .clk         (axis_aclk)
             );

        /* Insertion State Machine */
        always @(*) begin
            //defaults
            ifsm_state_next[i] = ifsm_state[i];

            d_fifo_wr_en[i] = 0;
            m_fifo_wr_en[i] = 0;

            case(ifsm_state[i])
                WAIT_START: begin
                    if (s_axis_tvalid & s_axis_tready) begin
                        if (s_axis_tuser[DST_PORT_POS+(i+1)*2] & ~d_fifo_nearly_full[i] & ~m_fifo_nearly_full[i]) begin
                            d_fifo_wr_en[i] = 1;
                            m_fifo_wr_en[i] = 1;
                            ifsm_state_next[i] = RCV_WORD;
                        end
                        else begin
                            ifsm_state_next[i] = DROP_PKT;
                        end
                    end
                end

                RCV_WORD: begin
                    if (s_axis_tvalid & s_axis_tready) begin
                        d_fifo_wr_en[i] = 1;
                        if (s_axis_tlast) begin
                            ifsm_state_next[i] = WAIT_START;
                        end
                    end
                end

                DROP_PKT: begin
                    if (s_axis_tvalid & s_axis_tready & s_axis_tlast) begin
                        ifsm_state_next[i] = WAIT_START;
                    end
                end
            endcase
        end

        always @(posedge axis_aclk) begin
            if (~axis_resetn) begin
                ifsm_state[i] <= WAIT_START;
            end
            else begin
                ifsm_state[i] <= ifsm_state_next[i];
            end
        end

        /* Removal State Machine */
        always @(*) begin
            // defaults
            rfsm_state_next[i] = rfsm_state[i];

            d_fifo_rd_en[i] = 0;
            m_fifo_rd_en[i] = 0;

            m_axis_tvalid[i] = 0;

            case(rfsm_state[i])
                RFSM_START: begin
                   if (~d_fifo_empty[i] & ~m_fifo_empty[i]) begin
                       m_axis_tvalid[i] = 1;
                       if (m_axis_tready[i]) begin
                           d_fifo_rd_en[i] = 1;
                           m_fifo_rd_en[i] = 1;
                           rfsm_state_next[i] = RFSM_FINISH_PKT;
                       end
                   end 
                end

                RFSM_FINISH_PKT: begin
                   if (~d_fifo_empty[i]) begin
                       m_axis_tvalid[i] = 1;
                       if (m_axis_tready[i]) begin
                           d_fifo_rd_en[i] = 1;
                           if (m_axis_tlast[i])
                               rfsm_state_next[i] = RFSM_START;
                       end
                   end
                end
            endcase
        end

        always @(posedge axis_aclk) begin
            if (~axis_resetn) begin
                rfsm_state[i] <= RFSM_START;
            end
            else begin
                rfsm_state[i] <= rfsm_state_next[i];
            end
        end

    end
    endgenerate

    /* Wire up the outputs */
    assign m_axis_0_tdata = m_axis_tdata[0];
    assign m_axis_0_tkeep = m_axis_tkeep[0];
    assign m_axis_0_tuser = m_axis_tuser[0];
    assign m_axis_0_tvalid = m_axis_tvalid[0];
    assign m_axis_tready[0] = m_axis_0_tready;
    assign m_axis_0_tlast = m_axis_tlast[0];

    assign m_axis_1_tdata = m_axis_tdata[1];
    assign m_axis_1_tkeep = m_axis_tkeep[1];
    assign m_axis_1_tuser = m_axis_tuser[1];
    assign m_axis_1_tvalid = m_axis_tvalid[1];
    assign m_axis_tready[1] = m_axis_1_tready;
    assign m_axis_1_tlast = m_axis_tlast[1];
   
endmodule // simple_output_queues

