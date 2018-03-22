//-
// Copyright (C) 2010, 2011 The Board of Trustees of The Leland Stanford
//                          Junior University
// Copyright (C) 2017 Stephen Ibanez
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
 *        simple_tm_sl_drop.v
 *
 *  Library:
 *
 *  Module:
 *        simple_tm
 *
 *  Author:
 *        Stephen Ibanez
 * 		
 *  Description:
 *        This is the top-level module that ties together the skiplist(s) and packet
 *        storage. It does not assert back pressure and instead drops the packet.
 *
 */

module simple_tm_sl_drop
#(
    // Pkt AXI Stream Data Width
    parameter C_M_AXIS_DATA_WIDTH  = 256,
    parameter C_S_AXIS_DATA_WIDTH  = 256,
    parameter C_M_AXIS_TUSER_WIDTH = 128,
    parameter C_S_AXIS_TUSER_WIDTH = 128,
    parameter SRC_PORT_POS         = 16,
    parameter DST_PORT_POS         = 24,
    parameter RANK_POS             = 32,
    parameter Q_ID_POS             = 64,

    // max num pkts the pifo can store
    parameter PIFO_DEPTH           = 2048,
    parameter PIFO_REG_DEPTH       = 32,
    // max # 64B pkts that can fit in storage
    parameter STORAGE_MAX_PKTS     = 2048,
    parameter NUM_SKIP_LISTS       = 1,
    // Queue params
    parameter NUM_QUEUES           = 2,
    parameter QUEUE_LIMIT          = STORAGE_MAX_PKTS/NUM_QUEUES 
)
(
    // Global Ports
    input                                      axis_aclk,
    input                                      axis_resetn,

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
    output reg                                     s_axis_tready,
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
   localparam WAIT_START           = 1;
   localparam FINISH_PKT           = 2;
   localparam DROP_PKT             = 4;
   localparam IFSM_NUM_STATES      = 3;

   localparam SEG_ADDR_WIDTH = log2(STORAGE_MAX_PKTS);
   localparam META_ADDR_WIDTH = log2(STORAGE_MAX_PKTS);
   localparam PTRS_WIDTH = SEG_ADDR_WIDTH + META_ADDR_WIDTH;

   localparam RANK_WIDTH = 32;
   localparam Q_ID_WIDTH = 32;
   localparam Q_SIZE_BITS = 32;

   localparam MAX_PKT_SIZE = 24; // measured in 64B chunks

   //---------------------- Wires and Regs ---------------------------- 

   reg  s_axis_tvalid_storage;
   wire s_axis_tready_storage;

   reg                     pifo_insert;
   reg                     pifo_remove;
   reg  [RANK_WIDTH-1:0]   pifo_rank_in;
   reg  [PTRS_WIDTH-1:0]   pifo_meta_in;
   wire [RANK_WIDTH-1:0]   pifo_rank_out;
   wire [PTRS_WIDTH-1:0]   pifo_meta_out;
   wire                    pifo_valid_out;
   wire                    pifo_busy;
   wire                    pifo_full;

   
   reg  [IFSM_NUM_STATES-1:0]           ifsm_state, ifsm_state_next;
   reg  [RANK_WIDTH-1 : 0]              rank_in, rank_in_next;
   reg  [PTRS_WIDTH-1 : 0]              ptrs_in, ptrs_in_next;

   wire [PTRS_WIDTH - 1 : 0]    storage_ptr_out_tdata;
   wire                         storage_ptr_out_tvalid;
   wire                         storage_ptr_out_tlast;
   
   reg [PTRS_WIDTH - 1 : 0]     storage_ptr_in_tdata;
   reg                          storage_ptr_in_tvalid;
   wire                         storage_ptr_in_tready;
   reg                          storage_ptr_in_tlast;

   reg [Q_SIZE_BITS-1:0] q_size_r      [NUM_QUEUES-1:0];
   reg [Q_SIZE_BITS-1:0] q_size_r_next [NUM_QUEUES-1:0];
   reg [Q_ID_WIDTH-1:0]  q_id, q_id_r, q_id_r_next;
   reg update_q_size_r, update_q_size_r_next;
 
   //-------------------- Modules and Logic ---------------------------

   /* Pkt storage */
   pifo_pkt_storage
   #(
       .C_M_AXIS_DATA_WIDTH      (C_M_AXIS_DATA_WIDTH),
       .C_S_AXIS_DATA_WIDTH      (C_S_AXIS_DATA_WIDTH),
       .C_M_AXIS_TUSER_WIDTH     (C_M_AXIS_TUSER_WIDTH),
       .C_S_AXIS_TUSER_WIDTH     (C_S_AXIS_TUSER_WIDTH),
       .SRC_PORT_POS             (SRC_PORT_POS),
       .DST_PORT_POS             (DST_PORT_POS),
       .RANK_POS                 (RANK_POS),
       .C_M_AXIS_PTR_DATA_WIDTH  (PTRS_WIDTH),
       .C_S_AXIS_PTR_DATA_WIDTH  (PTRS_WIDTH),
       .MAX_PKTS                 (STORAGE_MAX_PKTS)
   )
   pkt_storage
   (
       // Global Ports
       .axis_aclk (axis_aclk),
       .axis_resetn (axis_resetn),
       // pkt_storage output pkts
       .m_axis_pkt_tdata (m_axis_tdata),
       .m_axis_pkt_tkeep (m_axis_tkeep),
       .m_axis_pkt_tuser (m_axis_tuser),
       .m_axis_pkt_tvalid (m_axis_tvalid),
       .m_axis_pkt_tready (m_axis_tready),
       .m_axis_pkt_tlast (m_axis_tlast),
       // pkt_storage input pkts
       .s_axis_pkt_tdata  (s_axis_tdata),
       .s_axis_pkt_tkeep  (s_axis_tkeep),
       .s_axis_pkt_tuser  (s_axis_tuser),
       .s_axis_pkt_tvalid (s_axis_tvalid_storage),
       .s_axis_pkt_tready (s_axis_tready_storage),
       .s_axis_pkt_tlast  (s_axis_tlast),
       // pkt_storage output pointers (write result output interface)
       .m_axis_ptr_tdata  (storage_ptr_out_tdata),
       .m_axis_ptr_tvalid (storage_ptr_out_tvalid),
       .m_axis_ptr_tlast  (storage_ptr_out_tlast), 
       // pkt storage input pointers (read request input interface)
       .s_axis_ptr_tdata  (storage_ptr_in_tdata),
       .s_axis_ptr_tvalid (storage_ptr_in_tvalid),
       .s_axis_ptr_tready (storage_ptr_in_tready),
       .s_axis_ptr_tlast  (storage_ptr_in_tlast)
   );

    /* PIFO to store rank values and pointers */ 
    det_skip_list
    #(
     .L2_MAX_SIZE(log2(PIFO_DEPTH)),
     .RANK_WIDTH(RANK_WIDTH),
     .HSP_WIDTH(PTRS_WIDTH/2),
     .MDP_WIDTH(PTRS_WIDTH/2),
     .L2_REG_WIDTH(log2(PIFO_REG_DEPTH))
    )
    det_skip_list_i
    (
     .rst       (~axis_resetn),
     .clk       (axis_aclk),
     .insert    (pifo_insert),
     .remove    (pifo_remove),
     .rank_in   (pifo_rank_in),
     .meta_in   (pifo_meta_in),
     .rank_out  (pifo_rank_out),
     .meta_out  (pifo_meta_out),
     .valid_out (pifo_valid_out),
     .busy      (pifo_busy),
     .full      (pifo_full)
    );


   /* Insertion State Machine:
    *   - registers the rank of the incoming pkts and the ptrs returned by pkt storage
    *   - submits a write request to the pifo consisting of the rank and ptrs 
    */

   integer j;
   always @(*) begin
      // default values
      ifsm_state_next   = ifsm_state;

      s_axis_tready = 1;

      pifo_insert = 0;
      pifo_rank_in = 0;
      pifo_meta_in = 0;

      q_id = s_axis_tuser[Q_ID_POS+Q_ID_WIDTH-1 : Q_ID_POS];
      if (q_id >= NUM_QUEUES)
          $display("WARNING: q_id on tuser bus packet out of allowable range, q_id = %d\n", q_id);

      // default: don't update q_size
      for (j=0; j<NUM_QUEUES; j=j+1) begin
          q_size_r_next[j] = q_size_r[j]; 
      end

      q_id_r_next = q_id_r;
      update_q_size_r_next = update_q_size_r;

      case(ifsm_state)
          WAIT_START: begin
              // Wait until the first word of the pkt
              if (s_axis_tready && s_axis_tvalid) begin
                  if (s_axis_tready_storage & ~pifo_busy & ~pifo_full & (q_size_r[q_id] < QUEUE_LIMIT - MAX_PKT_SIZE)) begin
                      s_axis_tvalid_storage = 1;
                      // register the rank, and pointers returned from pkt_storage
                      pifo_insert = 1;
                      pifo_rank_in = s_axis_tuser[RANK_POS+RANK_WIDTH-1 : RANK_POS];
                      pifo_meta_in = storage_ptr_out_tdata;
                      // TODO: static simulation check that storage_ptr_out_tvalid == 1
                      // It should always be 1 here because the pointers should always be returned one the same cycle as the first word

                      // update q_size
                      q_size_r_next[q_id] = q_size_r_next[q_id] + 1;
                      update_q_size_r_next = 0;
                      q_id_r_next = q_id;

                      // transition to WRITE_PIFO state
                      ifsm_state_next = FINISH_PKT;
                  end
                  else begin
                      // drop the pkt
                      s_axis_tvalid_storage = 0;
                      ifsm_state_next = DROP_PKT;
                  end
              end
              else begin
                      s_axis_tvalid_storage = 0;
              end
          end

          FINISH_PKT: begin
              // Wait until the end of the pkt before going back to WAIT_START state
              s_axis_tvalid_storage = s_axis_tvalid;

              // count 64B chunks of the packet (i.e. increment every other word, starting with the first word of the pkt)
              if (s_axis_tvalid & s_axis_tready) begin
                  if (update_q_size_r) begin
                      q_size_r_next[q_id_r] = q_size_r_next[q_id_r] + 1;
                      update_q_size_r_next = 0;
                  end
                  else begin
                      update_q_size_r_next = 1;
                  end
              end
 
              if (s_axis_tready && s_axis_tvalid && s_axis_tlast) begin
                  ifsm_state_next = WAIT_START;
              end
              else begin
                  ifsm_state_next = FINISH_PKT;
              end
          end

          DROP_PKT: begin
              s_axis_tvalid_storage = 0;
              // Wait until the end of the pkt before going back to WRITE_STORAGE state
              if (s_axis_tready && s_axis_tvalid && s_axis_tlast) begin
                  ifsm_state_next = WAIT_START;
              end
              else begin
                  ifsm_state_next = DROP_PKT;
              end
          end

      endcase // case(ifsm_state)
   end // always @ (*)

   integer i;
   always @(posedge axis_aclk) begin
      if(~axis_resetn) begin
         ifsm_state <= WAIT_START;

         q_id_r <= 0;
         update_q_size_r <= 0;
         for (i=0; i<NUM_QUEUES; i=i+1) begin
             q_size_r[i] <= 0; 
         end
      end
      else begin
         ifsm_state <= ifsm_state_next;

         q_id_r <= q_id_r_next;
         update_q_size_r <= update_q_size_r_next;
         for (i=0; i<NUM_QUEUES; i=i+1) begin
             q_size_r[i] <= q_size_r_next[i]; 
         end
      end
   end

   /* Removal Logic: 
    *   - Read ptrs out of the PIFO and submit read requests to pkt storage
    */

   always @(*) begin
       storage_ptr_in_tlast = 1;
       // Wait for the PIFO to produce valid data and the pkt_storage to be ready to accept read requests
       // And we actually want to read the pkts out
       if (pifo_valid_out && storage_ptr_in_tready && m_axis_tready) begin
//       if (pifo_valid_out && storage_ptr_in_tready) begin
           // read PIFO and submit read request to pkt_storage
           pifo_remove = 1;
           storage_ptr_in_tdata = pifo_meta_out;
           storage_ptr_in_tvalid = 1;
       end
       else begin
           pifo_remove = 0;
           storage_ptr_in_tdata = 0;
           storage_ptr_in_tvalid = 0;
       end
   end // always @ (*)

// debugging signals
wire [Q_SIZE_BITS-1:0] q_size_0 = q_size_r[0];
wire [Q_SIZE_BITS-1:0] q_size_1 = q_size_r[1];


`ifdef COCOTB_SIM
initial begin
  $dumpfile ("simple_tm_sl_drop_waveform.vcd");
  $dumpvars (0,simple_tm_sl_drop);
  #1 $display("Sim running...");
end
`endif
   
endmodule // tm_top

