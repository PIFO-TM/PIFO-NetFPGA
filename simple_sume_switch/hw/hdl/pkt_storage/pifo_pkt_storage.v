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
 *        pifo_pkt_storage.v
 *
 *  Library:
 *
 *  Module:
 *        pifo_pkt_storage
 *
 *  Author:
 *        Stephen Ibanez
 * 		
 *  Description:
 *        The packet storage memory architecture for the PIFO traffic manager.
 *
 */

module pifo_pkt_storage
#(
    // Pkt AXI Stream Data Width
    parameter C_M_AXIS_DATA_WIDTH  = 256,
    parameter C_S_AXIS_DATA_WIDTH  = 256,
    parameter C_M_AXIS_TUSER_WIDTH = 128,
    parameter C_S_AXIS_TUSER_WIDTH = 128,
    parameter SRC_PORT_POS         = 16,
    parameter DST_PORT_POS         = 24,
    parameter RANK_POS             = 32,

    // Ptr AXI Stream Data Width
    parameter C_M_AXIS_PTR_DATA_WIDTH  = 64,
    parameter C_S_AXIS_PTR_DATA_WIDTH  = 64,

    // Storage parameters
    parameter SEG_SIZE = 512

)
(
    // Global Ports
    input                                      axis_aclk,
    input                                      axis_resetn,

    // Master Pkt Stream Ports (outgoing pkts) 
    output [C_M_AXIS_DATA_WIDTH - 1:0]         m_axis_pkt_tdata,
    output [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] m_axis_pkt_tkeep,
    output reg [C_M_AXIS_TUSER_WIDTH-1:0]      m_axis_pkt_tuser,
    output                                     m_axis_pkt_tvalid,
    input                                      m_axis_pkt_tready,
    output                                     m_axis_pkt_tlast,

    // Slave Pkt Stream Ports (incomming pkts)
    input [C_S_AXIS_DATA_WIDTH - 1:0]          s_axis_pkt_tdata,
    input [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0]  s_axis_pkt_tkeep,
    input [C_S_AXIS_TUSER_WIDTH-1:0]           s_axis_pkt_tuser,
    input                                      s_axis_pkt_tvalid,
    output                                     s_axis_pkt_tready,
    input                                      s_axis_pkt_tlast,

    // Master Ptr Stream Ports (outgoing ptrs)
    output [C_M_AXIS_PTR_DATA_WIDTH - 1:0]         m_axis_ptr_tdata,
    output [((C_M_AXIS_PTR_DATA_WIDTH / 8)) - 1:0] m_axis_ptr_tkeep,
    output                                         m_axis_ptr_tvalid,
//    input                                          m_axis_ptr_tready,
    output                                         m_axis_ptr_tlast,

    // Slave Ptr Stream Ports (incomming ptrs for read request)
    input [C_S_AXIS_PTR_DATA_WIDTH - 1:0]          s_axis_ptr_tdata,
    input [((C_S_AXIS_PTR_DATA_WIDTH / 8)) - 1:0]  s_axis_ptr_tkeep,
    input                                          s_axis_ptr_tvalid,
//    output                                         s_axis_ptr_tready,
    input                                          s_axis_ptr_tlast

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
   localparam START_PKT          = 1;
   localparam FINISH_PKT         = 2;
   localparam IFSM_NUM_STATES    = 2;

   /* For Removal FSM */
   localparam WAIT_REQUEST         = 1;
   localparam WAIT_BOTH_BRAM       = 2;
   localparam WAIT_SEG_BRAM        = 4;
   localparam WRITE_OUT_WORD_TWO   = 8;
   localparam RFSM_NUM_STATES      = 4;

   // SEG_SIZE must be a multiple of the bus width
   // NOTE: currently assumed to be 2
   localparam WORDS_PER_SEG = SEG_SIZE/C_S_AXIS_DATA_WIDTH;

   // According to the Vivado block memory generator - 2 cycle read latency
   // NOTE: currently assumed to be 2
   localparam BRAM_READ_DLY = 2; 

   localparam TOTAL_SEG_SIZE = SEG_SIZE + SEG_ADDR_WIDTH + 2*(C_S_AXIS_DATA_WIDTH / 8);

   localparam SEG_BRAM_DEPTH = 1024;
   localparam META_BRAM_DEPTH = 1024;

   localparam NULL = -1; // Is this valid?

   //---------------------- Wires and Regs ---------------------------- 
   
   reg  [IFSM_NUM_STATES-1:0]           ifsm_state, ifsm_state_next;

   wire [SEG_ADDR_WIDTH-1:0] seg_fl_addr_in;
   wire seg_fl_wr_en;
   wire seg_fl_rd_en;
   wire seg_fl_empty;
   wire seg_fl_full;
   wire [SEG_ADDR_WIDTH-1:0] seg_fl_addr_out;

   wire [META_ADDR_WIDTH-1:0] meta_fl_addr_in;
   wire meta_fl_wr_en;
   wire meta_fl_rd_en;
   wire meta_fl_empty;
   wire meta_fl_full;
   wire [META_ADDR_WIDTH-1:0] meta_fl_addr_out;

   reg                                       seg_bram_wr_we;
   reg   [SEG_ADDR_WIDTH-1:0]                seg_bram_wr_addr;
   reg   [TOTAL_SEG_SIZE-1:0]                seg_bram_din;
   reg   [SEG_ADDR_WIDTH-1:0]                seg_bram_rd_addr;
   wire  [TOTAL_SEG_SIZE-1:0]                seg_bram_dout;

   reg                                       meta_bram_wr_we;
   reg   [META_ADDR_WIDTH-1:0]               meta_bram_wr_addr;
   reg   [C_S_AXIS_TUSER_WIDTH-1:0]          meta_bram_din;
   reg   [META_ADDR_WIDTH-1:0]               meta_bram_rd_addr;
   wire  [C_S_AXIS_TUSER_WIDTH-1:0]          meta_bram_dout;
 
   reg   [C_S_AXIS_DATA_WIDTH-1:0]           seg_word_one_tdata;
   reg   [C_S_AXIS_DATA_WIDTH-1:0]           seg_word_one_tdata_next;
   reg   [(C_S_AXIS_DATA_WIDTH/8)-1:0]       seg_word_one_tkeep;
   reg   [(C_S_AXIS_DATA_WIDTH/8)-1:0]       seg_word_one_tkeep_next;
   reg   [SEG_ADDR_WIDTH-1:0]                cur_seg_ptr;
   reg   [SEG_ADDR_WIDTH-1:0]                cur_seg_ptr_next;

   reg [RFSM_NUM_STATES-1:0] rfsm_state, rfsm_state_next;
   reg [META_ADDR_WIDTH-1:0] meta_rd_addr, meta_rd_addr_next;
   reg [SEG_ADDR_WIDTH-1:0] seg_rd_addr, seg_rd_addr_next;
   reg [META_ADDR_WIDTH-1:0] rfsm_cur_meta_ptr, rfsm_cur_meta_ptr_next;
   reg [SEG_ADDR_WIDTH-1:0] rfsm_cur_seg_ptr, rfsm_cur_seg_ptr_next;

   reg [C_S_AXIS_DATA_WIDTH-1:0] seg_word_one_tdata_out, seg_word_two_tdata_out;
   reg [(C_S_AXIS_DATA_WIDTH/8)-1:0] seg_word_one_tkeep_out, seg_word_two_tkeep_out;

   reg [SEG_ADDR_WIDTH-1:0] next_seg_ptr_out;
   reg [1:0] bram_rd_cycle_cnt_next, bram_rd_cycle_cnt;

   reg [C_S_AXIS_DATA_WIDTH-1:0] m_axis_pkt_tdata_reg, m_axis_pkt_tdata_reg_next;
   reg [(C_S_AXIS_DATA_WIDTH/8)-1:0] m_axis_pkt_tkeep_reg, m_axis_pkt_tkeep_reg_next;
   reg m_axis_pkt_tvalid_reg, m_axis_pkt_tvalid_reg_next;
   reg m_axis_pkt_tlast_reg, m_axis_pkt_tlast_reg_next;
   reg [C_S_AXIS_TUSER_WIDTH-1:0] m_axis_pkt_tuser_reg, m_axis_pkt_tuser_reg_next;

   reg [C_S_AXIS_DATA_WIDTH-1:0] seg_word_two_tdata, seg_word_two_tdata_next;
   reg [(C_S_AXIS_DATA_WIDTH/8)-1:0] seg_word_two_tkeep, seg_word_two_tkeep_next;
 
   //-------------------- Modules and Logic ---------------------------
  
   /* Segment free list */
   fallthrough_small_fifo #(.WIDTH(SEG_ADDR_WIDTH), .MAX_DEPTH_BITS(log2(SEG_BRAM_DEPTH)))
      seg_fl_fifo
        (.din         (seg_fl_addr_in),     // Data in
         .wr_en       (seg_fl_wr_en),                                // Write enable
         .rd_en       (seg_fl_rd_en),                                                // Read the next word
         .dout        (seg_fl_addr_out),
         .full        (seg_fl_full),
         .prog_full   (),
         .nearly_full (),
         .empty       (seg_fl_empty),
         .reset       (~axis_resetn),
         .clk         (axis_aclk)
         );

   /* Metadata free list */
   fallthrough_small_fifo #(.WIDTH(META_ADDR_WIDTH), .MAX_DEPTH_BITS(log2(META_BRAM_DEPTH)))
      meta_fl_fifo
        (.din         (meta_fl_addr_in),     // Data in
         .wr_en       (meta_fl_wr_en),                                // Write enable
         .rd_en       (meta_fl_rd_en),                                                // Read the next word
         .dout        (meta_fl_addr_out),
         .full        (meta_fl_full),
         .prog_full   (),
         .nearly_full (),
         .empty       (meta_fl_empty),
         .reset       (~axis_resetn),
         .clk         (axis_aclk)
         );


   /* Segments BRAM */
   segment_bram seg_bram_inst (
       .clka          (axis_aclk),    // input wire clka
       .wea           (seg_bram_wr_we),      // input wire [0 : 0] wea
       .addra         (seg_bram_wr_addr),  // input wire [9 : 0] addra
       .dina          (seg_bram_din),    // input wire [511 : 0] dina
       .clkb          (axis_aclk),    // input wire clkb
       .addrb         (seg_bram_rd_addr),  // input wire [9 : 0] addrb
       .doutb         (seg_bram_dout)  // output wire [511 : 0] doutb
   );

   /* Metadata BRAM */
   metadata_bram meta_bram_inst (
       .clka          (axis_aclk),    // input wire clka
       .wea           (meta_bram_wr_we),      // input wire [0 : 0] wea
       .addra         (meta_bram_wr_addr),  // input wire [9 : 0] addra
       .dina          (meta_bram_din),    // input wire [31 : 0] dina
       .clkb          (axis_aclk),    // input wire clkb
       .addrb         (meta_bram_rd_addr),  // input wire [9 : 0] addrb
       .doutb         (meta_bram_dout)  // output wire [31 : 0] doutb
   );


   /* Insertion State Machine:
    *   - Writes incomming packets into storage
    *   - The pkt is broken into segements and written into segments BRAM
    *   - The metadata is written into metadata BRAM
    *   - The address of the first pkt segment and metadata address are written
    *     onto the m_axis_ptr_* bus
    */

   // Want to make sure the free lists are not empty in the state that we are reading from them
   assign s_axis_pkt_tready = (~meta_fl_empty & ~seg_fl_empty & (ifsm_state==START_WORD || ifsm_state==WORD_TWO)) | ifsm_state==WORD_ONE;

   always @(*) begin
      // default values
      ifsm_state_next   = ifsm_state;
      seg_fl_rd_en = 0;
      meta_fl_rd_en = 0;
      meta_bram_wr_we = 0;
      meta_bram_wr_addr = 0;
      meta_bram_din = 0;
      seg_word_one_tdata_next = seg_word_one_tdata; 
      seg_word_one_tkeep_next = seg_word_one_tkeep;
      cur_seg_ptr_next = cur_seg_ptr;

      m_axis_ptr_tdata = 0;
      m_axis_ptr_tvalid = 0;
      m_axis_ptr_tkeep = 0;
      m_axis_ptr_tlast = 1;

      case(ifsm_state)
          START_WORD: begin
              // Wait for start of pkt (write simulation error if rst_done register is not set yet)
              if (s_axis_pkt_tvalid & s_axis_pkt_tready) begin
                  // Get head_seg_ptr and meta_ptr and write onto m_axis_ptr_* bus
                  m_axis_ptr_tdata = {seg_fl_addr_out, meta_fl_addr_out};
                  m_axis_ptr_tvalid = 1;
                  m_axis_ptr_tkeep = {SEG_ADDR_WIDTH{'b1}, META_ADDR_WIDTH{'b1}};
                  seg_fl_rd_en = 1;
                  meta_fl_rd_en = 1;
                  // Write the metadata into meta_bram
                  meta_bram_wr_we = 1;
                  meta_bram_wr_addr = meta_fl_addr_out;
                  meta_bram_din = s_axis_tuser;
                  // Register the first word of the segment, the tkeep data, and the address to write to
                  seg_word_one_tdata_next = s_axis_pkt_tdata;
                  seg_word_one_tkeep_next = s_axis_pkt_tkeep;
                  cur_seg_ptr_next = seg_fl_addr_out;
                  // Transistion to WORD_TWO state
                  ifsm_state_next = WORD_TWO;
              end
          end

          WORD_ONE: begin
              if (s_axis_pkt_tvalid & s_axis_pkt_tready) begin
                  // Register the first word of the segment and the tkeep data
                  seg_word_one_tdata_next = s_axis_pkt_tdata;
                  seg_word_one_tkeep_next = s_axis_pkt_tkeep;
                  if (s_axis_pkt_tlast) begin
                      // If this is the end of the pkt => write into segment_bram
                      seg_bram_wr_we = 1;
                      seg_bram_wr_addr = cur_seg_ptr;
                      seg_bram_wr_din = {s_axis_pkt_tdata, s_axis_pkt_tkeep, C_S_AXIS_DATA_WIDTH{1'b0}, (C_S_AXIS_DATA_WIDTH/8){1'b0}, NULL};
                      // transition to START_WORD
                      ifsm_state_next = START_WORD;
                  end
                  else begin
                      // Else ==> transition to WORD_TWO state
                      ifsm_state_next = WORD_TWO;
                  end
              end
          end

          WORD_TWO: begin
              if (s_axis_pkt_tvalid & s_axis_pkt_tready) begin
                  if (s_axis_pkt_tlast) begin
                      // If this is the last word of the pkt => set next_seg_ptr = NULL
                      next_seg_ptr = NULL;
                      // transition to START_WORD state
                      ifsm_state_next = START_WORD;
                  end 
                  else begin
                      // Else => set next_seg_ptr = seg_fl_addr_out, and read from seg free list
                      next_seg_ptr == seg_fl_addr_out;
                      seg_fl_rd_en = 1;
                      ifsm_state_next = WORD_ONE;
                  end
                  // Write current word of the pkt along with the registered word into segment_bram
                  seg_bram_wr_we = 1;
                  seg_bram_wr_addr = cur_seg_ptr;
                  seg_bram_wr_din = {seg_word_one_tdata, seg_word_one_tkeep, s_axis_pkt_tdata, s_axis_pkt_tkeep, next_seg_ptr};
                  // cur seg ptr to the next seg ptr
                  cur_seg_ptr_next = next_seg_ptr;
              end
          end
      endcase // case(ifsm_state)
   end // always @ (*)

   always @(posedge axis_aclk) begin
      if(~axis_resetn) begin
         ifsm_state <= START_WORD;
         seg_word_one_tdata <= 0;
         seg_word_one_tkeep <= 0;
         cur_seg_ptr <= 0;
      end
      else begin
         ifsm_state <= ifsm_state_next;
         seg_word_one_tdata <= seg_word_one_tdata_next;
         seg_word_one_tkeep <= seg_word_one_tkeep_next;
         cur_seg_ptr <= cur_seg_ptr_next;
      end
   end

   /* Removal State Machine:
    *   - Remove requested packet and metadata from storage
    *   - Read the s_axis_ptr_* bus and wait for read request (head_seg_ptr, meta_ptr)
    *   - Get the metadata and store it
    *   - Follow segments pointers until reaching the end of the packet
    *   - Write pkt in C_M_AXIS_DATA_WIDTH bit chunks onto the m_axis_pkt_* bus
    */

   always @(*) begin
      // default values
      rfsm_state_next   = rfsm_state;

      // want to hold the read addresses constant by default
      meta_rd_addr_next = meta_rd_addr;
      meta_bram_rd_addr = meta_rd_addr;
      seg_rd_addr_next = seg_rd_addr;
      seg_bram_rd_addr = seg_rd_addr;

      rfsm_cur_meta_ptr_next = rfsm_cur_meta_ptr; 
      rfsm_cur_seg_ptr_next = rfsm_cur_seg_ptr;

      seg_fl_addr_in = 0;
      seg_fl_wr_en = 0;
      meta_fl_addr_in = 0;
      meta_fl_wr_en = 0;

      seg_word_one_tdata_out = 0;
      seg_word_one_tkeep_out = 0;
      seg_word_two_tdata_out = 0;
      seg_word_two_tkeep_out = 0;
      next_seg_ptr_out = 0;

      bram_rd_cycle_cnt_next = 0;

      // register these values so we can hold them constant when unspecified
      m_axis_pkt_tvalid = m_axis_pkt_tvalid_reg;
      m_axis_pkt_tdata = m_axis_pkt_tdata_reg;
      m_axis_pkt_tkeep = m_axis_pkt_tkeep_reg;
      m_axis_pkt_tlast = m_axis_pkt_tlast_reg;
      m_axis_pkt_tuser = m_axis_pkt_tuser_reg;

      m_axis_pkt_tvalid_reg_next = m_axis_pkt_tvalid_reg;
      m_axis_pkt_tdata_reg_next = m_axis_pkt_tdata_reg;
      m_axis_pkt_tkeep_reg_next = m_axis_pkt_tkeep_reg;
      m_axis_pkt_tlast_reg_next = m_axis_pkt_tlast_reg;
      m_axis_pkt_tuser_reg_next = m_axis_pkt_tuser_reg;

      seg_word_two_tdata_next = seg_word_two_tdata;
      seg_word_two_tkeep_next = seg_word_two_tkeep;

      case(rfsm_state)
          WAIT_REQUEST: begin
              if (s_axis_ptr_tvalid) begin
                  // Wait for the read request to arrive on s_axis_ptr_* bus (write sim error if rst_done reg is not set yet)
                  // Submit read request to both segment_bram and metadata_bram using the provided addresses (register 
                  //   the read addresses so the output doesn't change)
                  {meta_bram_rd_addr, seg_bram_rd_addr} = s_axis_ptr_tdata;
                  meta_rd_addr_next = meta_bram_rd_addr;
                  seg_rd_addr_next = seg_bram_rd_addr;
                  // Register the addresses
                  rfsm_cur_meta_ptr_next = meta_bram_rd_addr;
                  rfsm_cur_seg_ptr_next = seg_bram_rd_addr;
                  // Transistion to WAIT_BOTH_BRAM state
                  rfsm_state_next = WAIT_BOTH_BRAM;
                  // no longer end of pkt
                  m_axis_pkt_tlast = 0;
                  m_axis_pkt_tlast_reg_next = 0;
                  // TODO: this is actually an inefficient implementation because we wait until returning to this state
                  //       before checking for another read request. Ideally, should do this one cycle earlier.
              end
          end

          WAIT_BOTH_BRAM: begin
              // Wait for BRAM_READ_DLY-1 cycles to get the segment data and metadata from BRAM
              if (bram_rd_cycle_cnt == BRAM_READ_DLY-1) begin
                  // Add head_seg_ptr and meta_ptr to free list fifos using registered values
                  seg_fl_addr_in = rfsm_cur_seg_ptr;
                  seg_fl_wr_en = 1;
                  meta_fl_addr_in = rfsm_cur_meta_ptr;
                  meta_fl_wr_en = 1;
                  // Write first word of pkt (and metadata) onto m_axis_pkt_* bus
                  {seg_word_one_tdata_out, seg_word_one_tkeep_out, seg_word_two_tdata_out, seg_word_two_tkeep_out, next_seg_ptr_out} = seg_bram_dout;

                  m_axis_pkt_tvalid = 1;
                  m_axis_pkt_tdata = seg_word_one_tdata_out;
                  m_axis_pkt_tkeep = seg_word_one_tkeep_out;
                  m_axis_pkt_tuser = meta_bram_dout;

                  m_axis_pkt_tvalid_reg_next = 1;
                  m_axis_pkt_tdata_reg_next = seg_word_one_tdata_out;
                  m_axis_pkt_tkeep_reg_next = seg_word_one_tkeep_out;
                  m_axis_pkt_tuser_reg_next = meta_bram_dout

                  // Register second word of pkt, tkeep data, and next_seg_ptr
                  seg_word_two_tdata_next = seg_word_two_tdata_out;
                  seg_word_two_tkeep_next = seg_word_two_tkeep_out;
                  rfsm_cur_seg_ptr_next = next_seg_ptr_out;
                  if (seg_word_two_tkeep_out == 0) begin
                      // If tkeep of second word is zero, this is the last word of the pkt
                      m_axis_pkt_tlast = 1;
                      m_axis_pkt_tlast_reg_next = 1;
                      if (m_axis_pkt_tready) begin
                          // transition to WAIT_REQUEST state
                          rfsm_state_next = WAIT_REQUEST;
                      end
                  end
                  else if (m_axis_pkt_tready) begin
                      // transition to WRITE_OUT_WORD_TWO state
                      rfsm_state_next = WRITE_OUT_WORD_TWO;
                  end

                  if (next_seg_ptr_out != NULL && m_axis_pkt_tready) begin
                      // submit the next read request to segment_bram
                      seg_bram_rd_addr = next_seg_ptr_out;
                      seg_rd_addr_next = next_seg_ptr_out;
                  end
             end

             // count cycles for BRAM read delay
             if (bram_rd_cycle_cnt == BRAM_READ_DLY-1) begin
                  bram_rd_cycle_cnt_next = bram_rd_cycle_cnt;
             end
             else begin
                 bram_rd_cycle_cnt_next = bram_rd_cycle_cnt + 1;
             end
          end

          WAIT_SEG_BRAM: begin
              // Actually, no need to wait because we are assuming BRAM_READ_DLY = 2 cycles and SEG_SIZE/BUS_WIDTH = 2
              //   this logic will need to change if these parameters change
              // Add next_seg_ptr to segment free list
              seg_fl_addr_in = rfsm_cur_seg_ptr;
              seg_fl_wr_en = 1;
              // Receive segment data from BRAM
              {seg_word_one_tdata_out, seg_word_one_tkeep_out, seg_word_two_tdata_out, seg_word_two_tkeep_out, next_seg_ptr_out} = seg_bram_dout;
              // Write first word of segment onto m_axis_pkt_* bus
              m_axis_pkt_tvalid = 1;
              m_axis_pkt_tdata = seg_word_one_tdata_out;
              m_axis_pkt_tkeep = seg_word_one_tkeep_out;

              m_axis_pkt_tvalid_reg_next = 1;
              m_axis_pkt_tdata_reg_next = seg_word_one_tdata_out;
              m_axis_pkt_tkeep_reg_next = seg_word_one_tkeep_out;

              // Register second word of pkt, tkeep data, and next_seg_ptr
              seg_word_two_tdata_next = seg_word_two_tdata_out;
              seg_word_two_tkeep_next = seg_word_two_tkeep_out;
              rfsm_cur_seg_ptr_next = next_seg_ptr_out;
              if (seg_word_two_tkeep_out == 0) begin
                  // If tkeep of second word is zero, this is the last word of the pkt
                  m_axis_pkt_tlast = 1;
                  m_axis_pkt_tlast_reg_next = 1;
                  if (m_axis_pkt_tready) begin
                      // transition to WAIT_REQUEST state
                      rfsm_state_next = WAIT_REQUEST;
                  end
              end
              else if (m_axis_pkt_tready) begin
                  // transition to WRITE_OUT_WORD_TWO state
                  rfsm_state_next = WRITE_OUT_WORD_TWO;
              end

              if (next_seg_ptr_out != NULL && m_axis_pkt_tready) begin
                  // submit the next read request to segment_bram
                  seg_bram_rd_addr = next_seg_ptr_out;
                  seg_rd_addr_next = next_seg_ptr_out;
              end
          end

          WRITE_OUT_WORD_TWO: begin
              // Write second word of segment to m_axis_pkt_* bus
              m_axis_pkt_tvalid = 1;
              m_axis_pkt_tdata = seg_word_two_tdata;
              m_axis_pkt_tkeep = seg_word_two_tkeep;

              m_axis_pkt_tvalid_reg_next = 1;
              m_axis_pkt_tdata_reg_next = seg_word_two_tdata;
              m_axis_pkt_tkeep_reg_next = seg_word_two_tkeep;

              if (rfsm_cur_seg_ptr == NULL) begin
                  // this is the last word of the pkt
                  m_axis_pkt_tlast = 1;
                  m_axis_pkt_tlast_reg_next = 1;
                  if (m_axis_pkt_tready) begin
                      // transition to WAIT_REQUEST state only if the pkt can move forward
                      rfsm_state_next = WAIT_REQUEST;
                  end
              end
              else if (m_axis_pkt_tready) begin
                  // transition to WAIT_SEG_BRAM state only if the pkt can move forward
                  rfsm_state_next = WAIT_SEG_BRAM;
              end
          end
      endcase // case(rfsm_state)
   end // always @ (*)

   always @(posedge axis_aclk) begin
      if(~axis_resetn) begin
         rfsm_state <= WAIT_REQUEST;

         meta_rd_addr <= 0;
         seg_rd_addr <= 0;
         
         rfsm_cur_meta_ptr <= 0;
         rfsm_cur_seg_ptr <= 0;
         
         bram_rd_cycle_cnt <= 0;
         
         m_axis_pkt_tvalid_reg <= 0;
         m_axis_pkt_tdata_reg <= 0;
         m_axis_pkt_tkeep_reg <= 0;
         m_axis_pkt_tlast_reg <= 0;
         m_axis_pkt_tuser_reg <= 0;
         
         seg_word_two_tdata <= 0;
         seg_word_two_tkeep <= 0;
      end
      else begin
         rfsm_state <= rfsm_state_next;

         meta_rd_addr <= meta_rd_addr_next;
         seg_rd_addr <= seg_rd_addr_next;
         
         rfsm_cur_meta_ptr <= rfsm_cur_meta_ptr_next;
         rfsm_cur_seg_ptr <= rfsm_cur_seg_ptr_next;
         
         bram_rd_cycle_cnt <= bram_rd_cycle_cnt_next;
         
         m_axis_pkt_tvalid_reg <= m_axis_pkt_tvalid_reg_next;
         m_axis_pkt_tdata_reg <= m_axis_pkt_tdata_reg_next;
         m_axis_pkt_tkeep_reg <= m_axis_pkt_tkeep_reg_next;
         m_axis_pkt_tlast_reg <= m_axis_pkt_tlast_reg_next;
         m_axis_pkt_tuser_reg <= m_axis_pkt_tuser_reg_next;
         
         seg_word_two_tdata <= seg_word_two_tdata_next;
         seg_word_two_tkeep <= seg_word_two_tkeep_next;
      end
   end
   
endmodule // pifo_pkt_storage

