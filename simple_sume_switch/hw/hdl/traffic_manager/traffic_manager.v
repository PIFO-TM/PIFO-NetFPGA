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
 *        traffic_manager.v
 *
 *  Library:
 *
 *  Module:
 *        traffic_manager
 *
 *  Author:
 *        Stephen Ibanez
 * 		
 *  Description:
 *        Top level traffic management block.
 *
 */


module traffic_manager
#(
    // Master AXI Stream Data Width
    parameter C_M_AXIS_DATA_WIDTH=256,
    parameter C_S_AXIS_DATA_WIDTH=256,
    parameter C_M_AXIS_TUSER_WIDTH=128,
    parameter C_S_AXIS_TUSER_WIDTH=128,
    parameter SRC_PORT_POS         = 16,
    parameter DST_PORT_POS         = 24,
    parameter PORT_WIDTH           = 8,

    parameter L2_NUM_PORTS         = 2,
    parameter NUM_PORTS            = 2**L2_NUM_PORTS,
    parameter RANK_WIDTH           = 32,
    // max num pkts the pifo can store
    parameter PIFO_DEPTH           = 16,
    // max # 64B pkts that can fit in storage
    parameter STORAGE_MAX_PKTS     = 24 //4096
)
(
    // Part 1: System side signals
    // Global Ports
    input axis_aclk,
    input axis_resetn,

    // Slave Stream Ports (interface to data path)
    input [C_S_AXIS_DATA_WIDTH - 1:0] s_axis_tdata,
    input [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0] s_axis_tkeep,
    input [C_S_AXIS_TUSER_WIDTH-1:0] s_axis_tuser,
    input s_axis_tvalid,
    output reg s_axis_tready,
    input s_axis_tlast,

    // Master Stream Ports (interface to TX queues)
    output [C_M_AXIS_DATA_WIDTH - 1:0] m_axis_0_tdata,
    output [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] m_axis_0_tkeep,
    output [C_M_AXIS_TUSER_WIDTH-1:0] m_axis_0_tuser,
    output  m_axis_0_tvalid,
    input m_axis_0_tready,
    output  m_axis_0_tlast,

    output [C_M_AXIS_DATA_WIDTH - 1:0] m_axis_1_tdata,
    output [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] m_axis_1_tkeep,
    output [C_M_AXIS_TUSER_WIDTH-1:0] m_axis_1_tuser,
    output  m_axis_1_tvalid,
    input m_axis_1_tready,
    output  m_axis_1_tlast,

    output [C_M_AXIS_DATA_WIDTH - 1:0] m_axis_2_tdata,
    output [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] m_axis_2_tkeep,
    output [C_M_AXIS_TUSER_WIDTH-1:0] m_axis_2_tuser,
    output  m_axis_2_tvalid,
    input m_axis_2_tready,
    output  m_axis_2_tlast,

    output [C_M_AXIS_DATA_WIDTH - 1:0] m_axis_3_tdata,
    output [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] m_axis_3_tkeep,
    output [C_M_AXIS_TUSER_WIDTH-1:0] m_axis_3_tuser,
    output  m_axis_3_tvalid,
    input m_axis_3_tready,
    output  m_axis_3_tlast

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

   // ------------ Internal Params ---------------
   localparam IFSM_WAIT_PKT_START = 0;
   localparam IFSM_WAIT_PKT_END = 1;
   localparam IFSM_STATE_BITS = 2;

   localparam SEL_FSM_WAIT_REQ = 0;
   localparam SEL_FSM_WAIT_START = 1;
   localparam SEL_FSM_WAIT_PKT_END = 2;
   localparam SEL_FSM_WAIT_FINISH = 3;
   localparam SEL_FSM_BITS = 2;

   // ------------- Regs/ wires ------------------
   wire [C_S_AXIS_DATA_WIDTH - 1:0]          port_tm_m_axis_tdata    [NUM_PORTS-1:0];
   wire [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0]  port_tm_m_axis_tkeep    [NUM_PORTS-1:0];
   wire [C_S_AXIS_TUSER_WIDTH-1:0]           port_tm_m_axis_tuser    [NUM_PORTS-1:0];
   wire                                      port_tm_m_axis_tvalid   [NUM_PORTS-1:0];
   wire                                      port_tm_m_axis_tlast    [NUM_PORTS-1:0];
   reg                                       port_tm_m_axis_tready   [NUM_PORTS-1:0];

   reg [C_S_AXIS_DATA_WIDTH - 1:0]           port_tm_s_axis_tdata    [NUM_PORTS-1:0];
   reg [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0]   port_tm_s_axis_tkeep    [NUM_PORTS-1:0];
   reg [C_S_AXIS_TUSER_WIDTH-1:0]            port_tm_s_axis_tuser    [NUM_PORTS-1:0];
   reg                                       port_tm_s_axis_tvalid   [NUM_PORTS-1:0];
   reg                                       port_tm_s_axis_tlast    [NUM_PORTS-1:0];
   wire                                      port_tm_s_axis_tready   [NUM_PORTS-1:0];

   wire [C_S_AXIS_DATA_WIDTH - 1:0]          selector_m_axis_tdata    [NUM_PORTS-1:0];
   wire [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0]  selector_m_axis_tkeep    [NUM_PORTS-1:0];
   wire [C_S_AXIS_TUSER_WIDTH-1:0]           selector_m_axis_tuser    [NUM_PORTS-1:0];
   wire                                      selector_m_axis_tvalid   [NUM_PORTS-1:0];
   wire                                      selector_m_axis_tlast    [NUM_PORTS-1:0];
   wire                                      selector_m_axis_tready   [NUM_PORTS-1:0];

   reg [C_S_AXIS_DATA_WIDTH - 1:0]           selector_s_axis_tdata    [NUM_PORTS-1:0];
   reg [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0]   selector_s_axis_tkeep    [NUM_PORTS-1:0];
   reg [C_S_AXIS_TUSER_WIDTH-1:0]            selector_s_axis_tuser    [NUM_PORTS-1:0];
   reg                                       selector_s_axis_tvalid   [NUM_PORTS-1:0];
   reg                                       selector_s_axis_tlast    [NUM_PORTS-1:0];
   wire                                      selector_s_axis_tready   [NUM_PORTS-1:0];

   // selection signals
   wire [NUM_PORTS-1:0]                      nf_sel_valid  [NUM_PORTS-1:0];
   wire [NUM_PORTS-1:0]                      nf_pifo_valid [NUM_PORTS-1:0]; 
   wire [RANK_WIDTH-1:0]                     nf_pifo_rank [NUM_PORTS-1:0] [NUM_PORTS-1:0];

   reg [IFSM_STATE_BITS-1:0] ifsm_state, ifsm_state_next;
   reg [PORT_WIDTH-1:0]      sport_one_hot;
   reg [L2_NUM_PORTS-1:0]    sport, sport_r, sport_r_next;

   reg [SEL_FSM_BITS-1:0] sel_state              [NUM_PORTS-1:0];
   reg [SEL_FSM_BITS-1:0] sel_state_next         [NUM_PORTS-1:0];
   reg [L2_NUM_PORTS-1:0] input_selection        [NUM_PORTS-1:0];
   reg [L2_NUM_PORTS-1:0] input_selection_r      [NUM_PORTS-1:0];
   reg [L2_NUM_PORTS-1:0] input_selection_r_next [NUM_PORTS-1:0];
   reg [PORT_WIDTH-1:0]   dport_one_hot          [NUM_PORTS-1:0];
   reg [L2_NUM_PORTS-1:0] dport                  [NUM_PORTS-1:0];

   // ------------- Modules / Logic --------------

   genvar i;
   generate
       for (i=0; i<NUM_PORTS; i=i+1) begin: port_tms
           port_tm
           #(
               .C_M_AXIS_DATA_WIDTH  (C_M_AXIS_DATA_WIDTH),
               .C_S_AXIS_DATA_WIDTH  (C_S_AXIS_DATA_WIDTH),
               .C_M_AXIS_TUSER_WIDTH (C_M_AXIS_TUSER_WIDTH),
               .C_S_AXIS_TUSER_WIDTH (C_S_AXIS_TUSER_WIDTH),
               .SRC_PORT_POS         (SRC_PORT_POS),
               .PORT_WIDTH           (PORT_WIDTH),
           
               .L2_NUM_PORTS         (L2_NUM_PORTS),
               .RANK_WIDTH           (RANK_WIDTH),
               .PIFO_DEPTH           (PIFO_DEPTH),
               .STORAGE_MAX_PKTS     (STORAGE_MAX_PKTS)
           )
           port_tm_inst
           (
               // Global Ports
               .axis_aclk              (axis_aclk),
               .axis_resetn            (axis_resetn),
           
               
               .m_axis_tdata            (port_tm_m_axis_tdata[i]),
               .m_axis_tkeep            (port_tm_m_axis_tkeep[i]),
               .m_axis_tuser            (port_tm_m_axis_tuser[i]),
               .m_axis_tvalid           (port_tm_m_axis_tvalid[i]),
               .m_axis_tready           (port_tm_m_axis_tready[i]),
               .m_axis_tlast            (port_tm_m_axis_tlast[i]),

               .s_axis_tdata            (port_tm_s_axis_tdata[i]),
               .s_axis_tkeep            (port_tm_s_axis_tkeep[i]),
               .s_axis_tuser            (port_tm_s_axis_tuser[i]),
               .s_axis_tvalid           (port_tm_s_axis_tvalid[i]),
               .s_axis_tready           (port_tm_s_axis_tready[i]),
               .s_axis_tlast            (port_tm_s_axis_tlast[i]),

               // inputs
               .nf0_sel_valid           (nf_sel_valid[0][i]),
               .nf1_sel_valid           (nf_sel_valid[1][i]),
               .nf2_sel_valid           (nf_sel_valid[2][i]),
               .nf3_sel_valid           (nf_sel_valid[3][i]),

               // outputs
               .nf0_pifo_valid          (nf_pifo_valid[0][i]),
               .nf0_pifo_rank           (nf_pifo_rank [0][i]),
               .nf1_pifo_valid          (nf_pifo_valid[1][i]),
               .nf1_pifo_rank           (nf_pifo_rank [1][i]),
               .nf2_pifo_valid          (nf_pifo_valid[2][i]),
               .nf2_pifo_rank           (nf_pifo_rank [2][i]),
               .nf3_pifo_valid          (nf_pifo_valid[3][i]),
               .nf3_pifo_rank           (nf_pifo_rank [3][i])
           );
       end
   endgenerate


   genvar j;
   generate
       for (j=0; j<NUM_PORTS; j=j+1) begin: selectors
           port_selector
           #(
               .C_M_AXIS_DATA_WIDTH  (C_M_AXIS_DATA_WIDTH),
               .C_S_AXIS_DATA_WIDTH  (C_S_AXIS_DATA_WIDTH),
               .C_M_AXIS_TUSER_WIDTH (C_M_AXIS_TUSER_WIDTH),
               .C_S_AXIS_TUSER_WIDTH (C_S_AXIS_TUSER_WIDTH),
               .DST_PORT_POS         (DST_PORT_POS),
               .PORT_WIDTH           (PORT_WIDTH),
               .L2_NUM_PORTS         (L2_NUM_PORTS),
               .RANK_WIDTH           (RANK_WIDTH)
           )
           port_selector_inst
           (
               // Global Ports
               .axis_aclk              (axis_aclk),
               .axis_resetn            (axis_resetn),

               .m_axis_tdata            (selector_m_axis_tdata[j]),
               .m_axis_tkeep            (selector_m_axis_tkeep[j]),
               .m_axis_tuser            (selector_m_axis_tuser[j]),
               .m_axis_tvalid           (selector_m_axis_tvalid[j]),
               .m_axis_tready           (selector_m_axis_tready[j]),
               .m_axis_tlast            (selector_m_axis_tlast[j]),

               .s_axis_tdata            (selector_s_axis_tdata[j]),
               .s_axis_tkeep            (selector_s_axis_tkeep[j]),
               .s_axis_tuser            (selector_s_axis_tuser[j]),
               .s_axis_tvalid           (selector_s_axis_tvalid[j]),
               .s_axis_tready           (selector_s_axis_tready[j]),
               .s_axis_tlast            (selector_s_axis_tlast[j]),

               // outputs
               .nf0_sel_valid           (nf_sel_valid[j][0]),
               .nf1_sel_valid           (nf_sel_valid[j][1]),
               .nf2_sel_valid           (nf_sel_valid[j][2]),
               .nf3_sel_valid           (nf_sel_valid[j][3]),

               // inputs
               .nf0_pifo_valid          (nf_pifo_valid[j][0]),
               .nf0_pifo_rank           (nf_pifo_rank [j][0]),
               .nf1_pifo_valid          (nf_pifo_valid[j][1]),
               .nf1_pifo_rank           (nf_pifo_rank [j][1]),
               .nf2_pifo_valid          (nf_pifo_valid[j][2]),
               .nf2_pifo_rank           (nf_pifo_rank [j][2]),
               .nf3_pifo_valid          (nf_pifo_valid[j][3]),
               .nf3_pifo_rank           (nf_pifo_rank [j][3])
           );
       end
   endgenerate


   // -------------- Logic ---------------
   // must drive port_tm_s_axis_t* (based on pkt's src_port)
   // must drive selector_s_axis_t* (one state machine per selector to watch requests and connect appropriate pkt stream to input)

   /* Input state machine:
    *   Send arriving pkt to the appropriate port_tm based on the src_port
    */
   integer k;
   always @(*) begin
       // defaults
       ifsm_state_next = ifsm_state;

       // compute the source port 
       sport_one_hot = s_axis_tuser[SRC_PORT_POS+PORT_WIDTH-1 : SRC_PORT_POS];
       sport = (8'b0000_0001 & sport_one_hot) ? 0 :
               (8'b0000_0100 & sport_one_hot) ? 1 :
               (8'b0001_0000 & sport_one_hot) ? 2 :
               (8'b0100_0000 & sport_one_hot) ? 3 : 0;
       sport_r_next = sport_r;

       s_axis_tready = 0;

       for (k=0; k<NUM_PORTS; k=k+1) begin
           port_tm_s_axis_tdata[k] = 0;
           port_tm_s_axis_tkeep[k] = 0;
           port_tm_s_axis_tuser[k] = 0;
           port_tm_s_axis_tvalid[k] = 0;
           port_tm_s_axis_tlast[k] = 0;
       end

       case(ifsm_state)
           IFSM_WAIT_PKT_START: begin
               s_axis_tready = port_tm_s_axis_tready[sport];
               if (s_axis_tvalid & s_axis_tready) begin
                   sport_r_next = sport;
                   ifsm_state_next = IFSM_WAIT_PKT_END;
                   port_tm_s_axis_tdata[sport]  = s_axis_tdata;
                   port_tm_s_axis_tkeep[sport]  = s_axis_tkeep;
                   port_tm_s_axis_tuser[sport]  = s_axis_tuser;
                   port_tm_s_axis_tvalid[sport] = s_axis_tvalid;
                   port_tm_s_axis_tlast[sport]  = s_axis_tlast;
               end
           end

           IFSM_WAIT_PKT_END: begin
               s_axis_tready = port_tm_s_axis_tready[sport_r];
               port_tm_s_axis_tdata[sport_r]  = s_axis_tdata;
               port_tm_s_axis_tkeep[sport_r]  = s_axis_tkeep;
               port_tm_s_axis_tuser[sport_r]  = s_axis_tuser;
               port_tm_s_axis_tvalid[sport_r] = s_axis_tvalid;
               port_tm_s_axis_tlast[sport_r]  = s_axis_tlast;
               if (s_axis_tvalid & s_axis_tready & s_axis_tlast) begin
                   ifsm_state_next = IFSM_WAIT_PKT_START;
               end
           end
       endcase
   end

   always @(posedge axis_aclk) begin
       if(~axis_resetn) begin
           ifsm_state <= IFSM_WAIT_PKT_START;
           sport_r <= 0;
       end
       else begin
           ifsm_state <= ifsm_state_next;
           sport_r <= sport_r_next;
       end
   end

   /* Selector State Machines:
    *   One for each selector.
    *   Watches for a selector's choice and then connects the appropriate pkt stream to
    *   the selector's pkt stream input until the selected pkt has been transfered.
    */
   integer m;
   always @(*) begin
       for (m=0; m<NUM_PORTS; m=m+1) begin
           // defaults
           sel_state_next[m] = sel_state[m];

           // each selector may only select one input at a time
           input_selection[m] = (nf_sel_valid[m][0]) ? 0 :
                                (nf_sel_valid[m][1]) ? 1 :
                                (nf_sel_valid[m][2]) ? 2 :
                                (nf_sel_valid[m][3]) ? 3 : 0;
           input_selection_r_next[m] = input_selection_r[m];

           selector_s_axis_tdata[m]  = 0;
           selector_s_axis_tkeep[m]  = 0;
           selector_s_axis_tuser[m]  = 0;
           selector_s_axis_tvalid[m] = 0;
           selector_s_axis_tlast[m]  = 0;
           port_tm_m_axis_tready[m] = 0;

           dport_one_hot[m] = port_tm_m_axis_tuser[input_selection_r[m]][DST_PORT_POS+PORT_WIDTH-1 : DST_PORT_POS];
           dport[m] = (8'b0000_0001 & dport_one_hot[m]) ? 0 :
                      (8'b0000_0100 & dport_one_hot[m]) ? 1 :
                      (8'b0001_0000 & dport_one_hot[m]) ? 2 :
                      (8'b0100_0000 & dport_one_hot[m]) ? 3 : 0;

           case(sel_state[m])
               SEL_FSM_WAIT_REQ: begin
                   // wait for the selector to make a request
                   if (|nf_sel_valid[m]) begin
                       input_selection_r_next[m] = input_selection[m];
                       sel_state_next[m] = SEL_FSM_WAIT_START;
                   end
               end

               SEL_FSM_WAIT_START: begin
                   // wait for the start of the next pkt
                   if (port_tm_m_axis_tvalid[input_selection_r[m]] & selector_s_axis_tready[m]) begin
                       if (dport[m] == m) begin
                           // this is the pkt we are waiting for
                           sel_state_next[m] = SEL_FSM_WAIT_FINISH;
                           selector_s_axis_tdata[m]  = port_tm_m_axis_tdata[input_selection_r[m]];
                           selector_s_axis_tkeep[m]  = port_tm_m_axis_tkeep[input_selection_r[m]];
                           selector_s_axis_tuser[m]  = port_tm_m_axis_tuser[input_selection_r[m]];
                           selector_s_axis_tvalid[m] = port_tm_m_axis_tvalid[input_selection_r[m]];
                           selector_s_axis_tlast[m]  = port_tm_m_axis_tlast[input_selection_r[m]]; 
                           port_tm_m_axis_tready[input_selection_r[m]] = selector_s_axis_tready[m]; 
                       end
                       else begin
                           sel_state_next[m] = SEL_FSM_WAIT_PKT_END;
                       end
                   end
               end
    
               SEL_FSM_WAIT_PKT_END: begin
                   // wait for current pkt to finish
                   if (port_tm_m_axis_tvalid[input_selection_r[m]] & selector_s_axis_tready[m] & port_tm_m_axis_tlast[input_selection_r[m]]) begin
                       sel_state_next[m] = SEL_FSM_WAIT_START;
                   end
               end

               SEL_FSM_WAIT_FINISH: begin
                   // This is the pkt we are waiting for, wait for it to finish
                   selector_s_axis_tdata[m]  = port_tm_m_axis_tdata[input_selection_r[m]];
                   selector_s_axis_tkeep[m]  = port_tm_m_axis_tkeep[input_selection_r[m]];
                   selector_s_axis_tuser[m]  = port_tm_m_axis_tuser[input_selection_r[m]];
                   selector_s_axis_tvalid[m] = port_tm_m_axis_tvalid[input_selection_r[m]];
                   selector_s_axis_tlast[m]  = port_tm_m_axis_tlast[input_selection_r[m]]; 
                   port_tm_m_axis_tready[input_selection_r[m]] = selector_s_axis_tready[m];
                   if (port_tm_m_axis_tvalid[input_selection_r[m]] & selector_s_axis_tready[m] & port_tm_m_axis_tlast[input_selection_r[m]]) begin
                       sel_state_next[m] = SEL_FSM_WAIT_REQ;
                   end
               end
           endcase
       end
   end

   integer n;    
   always @(posedge axis_aclk) begin
       for (n=0; n<NUM_PORTS; n=n+1) begin
           if(~axis_resetn) begin
               sel_state[n] <= SEL_FSM_WAIT_REQ;
               input_selection_r[n] <= 0;
           end
           else begin
               sel_state[n] <= sel_state_next[n];
               input_selection_r[n] <= input_selection_r_next[n];
           end
       end
   end

   // drive outputs
   assign m_axis_0_tdata     = selector_m_axis_tdata[0];
   assign m_axis_0_tkeep     = selector_m_axis_tkeep[0];
   assign m_axis_0_tuser     = selector_m_axis_tuser[0];
   assign m_axis_0_tlast     = selector_m_axis_tlast[0];
   assign m_axis_0_tvalid    = selector_m_axis_tvalid[0];
   assign selector_m_axis_tready[0] = m_axis_0_tready;

   assign m_axis_1_tdata     = selector_m_axis_tdata[1];
   assign m_axis_1_tkeep     = selector_m_axis_tkeep[1];
   assign m_axis_1_tuser     = selector_m_axis_tuser[1];
   assign m_axis_1_tlast     = selector_m_axis_tlast[1];
   assign m_axis_1_tvalid    = selector_m_axis_tvalid[1];
   assign selector_m_axis_tready[1] = m_axis_1_tready;

   assign m_axis_2_tdata     = selector_m_axis_tdata[2];
   assign m_axis_2_tkeep     = selector_m_axis_tkeep[2];
   assign m_axis_2_tuser     = selector_m_axis_tuser[2];
   assign m_axis_2_tlast     = selector_m_axis_tlast[2];
   assign m_axis_2_tvalid    = selector_m_axis_tvalid[2];
   assign selector_m_axis_tready[2] = m_axis_2_tready;

   assign m_axis_3_tdata     = selector_m_axis_tdata[3];
   assign m_axis_3_tkeep     = selector_m_axis_tkeep[3];
   assign m_axis_3_tuser     = selector_m_axis_tuser[3];
   assign m_axis_3_tlast     = selector_m_axis_tlast[3];
   assign m_axis_3_tvalid    = selector_m_axis_tvalid[3];
   assign selector_m_axis_tready[3] = m_axis_3_tready;

`ifdef COCOTB_SIM
initial begin
  $dumpfile("traffic_manager_waveform.vcd");
  $dumpvars(0,traffic_manager);
  #1 $display("Sim running...");
end
`endif

endmodule
