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
 *        port_tm.v
 *
 *  Library:
 *
 *  Module:
 *        port_tm
 *
 *  Author:
 *        Stephen Ibanez
 * 		
 *  Description:
 *       This module ties together the pkt_storage Virtual Output PIFOs for a
 *       particular input port. 
 *
 */

// `timescale 1ns/1ps

module port_tm
#(
    // Pkt AXI Stream Data Width
    parameter C_M_AXIS_DATA_WIDTH  = 256,
    parameter C_S_AXIS_DATA_WIDTH  = 256,
    parameter C_M_AXIS_TUSER_WIDTH = 128,
    parameter C_S_AXIS_TUSER_WIDTH = 128,
    parameter SRC_PORT_POS         = 16,
    parameter DST_PORT_POS         = 24,
    parameter PORT_WIDTH           = 8,
    parameter RANK_POS             = 32,

    parameter L2_NUM_PORTS         = 2,
    parameter NUM_PORTS            = 2**L2_NUM_PORTS,
    parameter RANK_WIDTH           = 32,
    // max num pkts the pifo can store
    parameter PIFO_DEPTH           = 1024,
    parameter PIFO_REG_DEPTH       = 32,
    // max # 64B pkts that can fit in storage
    parameter STORAGE_MAX_PKTS     = 2048,
    parameter NUM_SKIP_LISTS       = 1
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
    input                                          s_axis_tlast,

    input                             nf0_sel_valid,
    input                             nf1_sel_valid,
    input                             nf2_sel_valid,
    input                             nf3_sel_valid,

    output reg                            nf0_pifo_valid,
    output reg [RANK_WIDTH-1:0]           nf0_pifo_rank, 
    output reg                            nf1_pifo_valid,
    output reg [RANK_WIDTH-1:0]           nf1_pifo_rank, 
    output reg                            nf2_pifo_valid,
    output reg [RANK_WIDTH-1:0]           nf2_pifo_rank, 
    output reg                            nf3_pifo_valid,
    output reg [RANK_WIDTH-1:0]           nf3_pifo_rank 

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

   //---------------------- Wires and Regs ---------------------------- 
   wire [C_M_AXIS_DATA_WIDTH - 1:0]              m_axis_tdata_out;
   wire [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0]      m_axis_tkeep_out;
   wire [C_M_AXIS_TUSER_WIDTH-1:0]               m_axis_tuser_out;
   wire                                          m_axis_tvalid_out;
   wire                                          m_axis_tready_out;
   wire                                          m_axis_tlast_out;

   reg  s_axis_tvalid_storage;
   wire s_axis_tready_storage;

   reg  [NUM_PORTS-1:0]    pifo_insert;
   reg  [NUM_PORTS-1:0]    pifo_remove;
   reg  [RANK_WIDTH-1:0]   pifo_rank_in   [NUM_PORTS-1:0];
   reg  [PTRS_WIDTH-1:0]   pifo_meta_in   [NUM_PORTS-1:0];
   wire [RANK_WIDTH-1:0]   pifo_rank_out  [NUM_PORTS-1:0];
   wire [PTRS_WIDTH-1:0]   pifo_meta_out  [NUM_PORTS-1:0];
   wire [NUM_PORTS-1:0]    pifo_valid_out;
   wire [NUM_PORTS-1:0]    pifo_busy;
   wire [NUM_PORTS-1:0]    pifo_full;
   
   reg  [IFSM_NUM_STATES-1:0]           ifsm_state, ifsm_state_next;
//   reg  [RANK_WIDTH-1 : 0]              rank_in_r, rank_in_r_next;
//   reg  [PTRS_WIDTH-1 : 0]              ptrs_in_r, ptrs_in_r_next;
//   reg  [L2_NUM_PORTS-1 : 0]            dport_in_r, dport_in_r_next;
   reg [L2_NUM_PORTS-1 : 0]     dport_in;

   wire [PTRS_WIDTH - 1 : 0]    storage_ptr_out_tdata;
   wire                         storage_ptr_out_tvalid;
   wire                         storage_ptr_out_tlast;
   
   reg [PTRS_WIDTH - 1 : 0]     storage_ptr_in_tdata;
   reg                          storage_ptr_in_tvalid;
   wire                         storage_ptr_in_tready;
   reg                          storage_ptr_in_tlast;

   // Request FIFO signals
   reg [L2_NUM_PORTS-1:0]       req_fifo_din [NUM_PORTS-1:0];
   reg [NUM_PORTS-1:0]          req_fifo_wr_en;
   reg [NUM_PORTS-1:0]          req_fifo_rd_en;
   wire [L2_NUM_PORTS-1:0]      req_fifo_dout [NUM_PORTS-1:0];
   wire [NUM_PORTS-1:0]         req_fifo_full;
   wire [NUM_PORTS-1:0]         req_fifo_empty;   

   reg                          arb_rd_en;
   wire                         arb_valid;
   wire [L2_NUM_PORTS-1:0]      arb_queue;

   reg [PORT_WIDTH-1:0]         dst_port;
 
   //-------------------- Modules and Logic ---------------------------
   // input pipeline stage
   axi_stream_pipeline
     #(
        .C_M_AXIS_DATA_WIDTH  (C_M_AXIS_DATA_WIDTH),
        .C_S_AXIS_DATA_WIDTH  (C_S_AXIS_DATA_WIDTH),
        .C_M_AXIS_TUSER_WIDTH (C_M_AXIS_TUSER_WIDTH),
        .C_S_AXIS_TUSER_WIDTH (C_S_AXIS_TUSER_WIDTH)
      )
   output_axi_pipe
     (
       .axis_aclk   (axis_aclk),
       .axis_resetn (axis_resetn),

       .m_axis_tdata  (m_axis_tdata),
       .m_axis_tkeep  (m_axis_tkeep),
       .m_axis_tuser  (m_axis_tuser),
       .m_axis_tvalid (m_axis_tvalid),
       .m_axis_tready (m_axis_tready),
       .m_axis_tlast  (m_axis_tlast),

       .s_axis_tdata  (m_axis_tdata_out),
       .s_axis_tkeep  (m_axis_tkeep_out),
       .s_axis_tuser  (m_axis_tuser_out),
       .s_axis_tvalid (m_axis_tvalid_out),
       .s_axis_tready (m_axis_tready_out),
       .s_axis_tlast  (m_axis_tlast_out)
     );

    req_arbiter #(.L2_NUM_PORTS(L2_NUM_PORTS))
    req_arbiter_inst
    (
        // Global Ports
        .axis_aclk                 (axis_aclk),
        .axis_resetn               (axis_resetn),
    
        // input requests
        .nf0_sel_valid             (nf0_sel_valid),
        .nf1_sel_valid             (nf1_sel_valid),
        .nf2_sel_valid             (nf2_sel_valid),
        .nf3_sel_valid             (nf3_sel_valid),
    
        // serialized outputs
        .sel_out_rd_en             (arb_rd_en),
        .sel_out_valid             (arb_valid),
        .sel_out_queue             (arb_queue)
    );


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
       .m_axis_pkt_tdata (m_axis_tdata_out),
       .m_axis_pkt_tkeep (m_axis_tkeep_out),
       .m_axis_pkt_tuser (m_axis_tuser_out),
       .m_axis_pkt_tvalid (m_axis_tvalid_out),
       .m_axis_pkt_tready (m_axis_tready_out),
       .m_axis_pkt_tlast (m_axis_tlast_out),
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

    genvar i;
    generate
    for (i=0; i < NUM_PORTS; i=i+1) begin: virtual_output_pifos
        /* PIFO to store rank values and pointers */ 
        pifo_top
        #(
         .L2_MAX_SIZE(log2(PIFO_DEPTH)),
         .RANK_WIDTH(RANK_WIDTH),
         .META_WIDTH(PTRS_WIDTH),
         .L2_REG_WIDTH(log2(PIFO_REG_DEPTH)),
         .NUM_SKIP_LISTS(NUM_SKIP_LISTS)
        )
        pifo_inst
//        pifo_reg
//        #(
//         .L2_MAX_SIZE(log2(PIFO_DEPTH)),
//         .RANK_WIDTH(RANK_WIDTH),
//         .META_WIDTH(PTRS_WIDTH)
//        )
//        pifo_reg_inst
        (
         .rst       (~axis_resetn),
         .clk       (axis_aclk),
         .insert    (pifo_insert[i]),
         .remove    (pifo_remove[i]),
         .rank_in   (pifo_rank_in[i]),
         .meta_in   (pifo_meta_in[i]),
         .rank_out  (pifo_rank_out[i]),
         .meta_out  (pifo_meta_out[i]),
         .valid_out (pifo_valid_out[i]),
         .busy      (pifo_busy[i]),
         .full      (pifo_full[i])
        );
    end
    endgenerate

    always @(*) begin
        nf0_pifo_valid = pifo_valid_out[0];
        nf0_pifo_rank = pifo_rank_out[0];
        nf1_pifo_valid = pifo_valid_out[1];
        nf1_pifo_rank = pifo_rank_out[1];
        nf2_pifo_valid = pifo_valid_out[2];
        nf2_pifo_rank = pifo_rank_out[2];
        nf3_pifo_valid = pifo_valid_out[3];
        nf3_pifo_rank = pifo_rank_out[3];
    end


   /* Insertion State Machine:
    *   - registers the rank and dst_port of the incoming pkts and the ptrs returned by pkt storage
    *   - submits a write request to the appropriate virtual output pifo consisting of the rank and ptrs 
    */

   integer j;
   always @(*) begin
      // default values
      ifsm_state_next   = ifsm_state;

      s_axis_tready = 1;

      dst_port = s_axis_tuser[DST_PORT_POS+PORT_WIDTH-1 : DST_PORT_POS];
      // compute the dst_port from one-hot (assuming no broadcasting)
      dport_in = (8'b0000_0001 & dst_port) ? 0 :
                 (8'b0000_0100 & dst_port) ? 1 :
                 (8'b0001_0000 & dst_port) ? 2 : 
                 (8'b0100_0000 & dst_port) ? 3 : 0;

//      rank_in_r_next = rank_in_r;
//      dport_in_r_next = dport_in_r;
//      ptrs_in_r_next = ptrs_in_r;

      for (j=0; j < NUM_PORTS; j=j+1) begin
          pifo_insert[j]  = 0;
          pifo_rank_in[j] = 0;
          pifo_meta_in[j] = 0;
      end

      case(ifsm_state)
          WAIT_START: begin
              // Wait until the first word of the pkt
              if (s_axis_tready && s_axis_tvalid) begin
                  if (dst_port == 0 | ~s_axis_tready_storage | pifo_busy | pifo_full) begin
                      // drop the pkt
                      s_axis_tvalid_storage = 0;
                      ifsm_state_next = DROP_PKT;
                  end
                  else begin 
                      // write to storage
                      s_axis_tvalid_storage = 1;

                      // write to PIFO
                      pifo_insert[dport_in] = 1;
                      pifo_rank_in[dport_in] = s_axis_tuser[RANK_POS+RANK_WIDTH-1 : RANK_POS];
                      pifo_meta_in[dport_in] = storage_ptr_out_tdata;

                      // transition to WRITE_PIFO state
                      ifsm_state_next = FINISH_PKT;
                  end
              end
              else begin
                  s_axis_tvalid_storage = 0;
              end
          end

          FINISH_PKT: begin
              s_axis_tvalid_storage = s_axis_tvalid;
              // Wait until the end of the pkt before going back to WAIT_START state
              if (s_axis_tready && s_axis_tvalid && s_axis_tlast) begin
                  ifsm_state_next = WAIT_START;
              end
          end

          DROP_PKT: begin
              s_axis_tvalid_storage = 0;
              // Wait until the end of the pkt before going back to WAIT_START state
              if (s_axis_tready && s_axis_tvalid && s_axis_tlast) begin
                  ifsm_state_next = WAIT_START;
              end
          end

      endcase // case(ifsm_state)
   end // always @ (*)

   always @(posedge axis_aclk) begin
      if(~axis_resetn) begin
         ifsm_state <= WAIT_START;
      end
      else begin
         ifsm_state <= ifsm_state_next;
      end
   end

   /* Removal Logic: 
    *   - Read ptrs out of the PIFO and submit read requests to pkt storage
    */
   integer k;
   always @(*) begin
       storage_ptr_in_tlast = 1;

       // default
       for (k=0; k<NUM_PORTS; k=k+1) begin
           pifo_remove[k] = 0;
       end

       // Wait for the req_arbiter to produce valid data
       // And the pkt_storage to be ready to accept read requests
       // And we actually want to read the pkts out
//       if (arb_valid && storage_ptr_in_tready && m_axis_tready_out) begin
       if (arb_valid && storage_ptr_in_tready) begin
           // read PIFO and submit read request to pkt_storage
           pifo_remove[arb_queue] = 1;
           arb_rd_en = 1;
           storage_ptr_in_tdata = pifo_meta_out[arb_queue];
           storage_ptr_in_tvalid = 1;
       end
       else begin
           pifo_remove[arb_queue] = 0;
           arb_rd_en = 0;
           storage_ptr_in_tdata = 0;
           storage_ptr_in_tvalid = 0;
       end
   end // always @ (*)

//`ifdef COCOTB_SIM
//initial begin
//  $dumpfile("port_tm_waveform.vcd");
//  $dumpvars(0,port_tm);
//  #1 $display("Sim running...");
//end
//`endif
   
endmodule // port_tm

