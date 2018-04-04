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
 *        cocotb_tm_wrapper.v
 *
 *  Library:
 *
 *  Module:
 *        cocotb_tm_wrapper
 *
 *  Author:
 *        Stephen Ibanez
 * 		
 *  Description:
 *        This is the top-level module that ties together the skiplist(s) and packet
 *        storage.
 *
 */

module cocotb_tm_bp_wrapper
#(
    // Pkt AXI Stream Data Width
    parameter C_M_AXIS_DATA_WIDTH  = 256,
    parameter C_S_AXIS_DATA_WIDTH  = 256,
    parameter C_M_AXIS_TUSER_WIDTH = 128,
    parameter C_S_AXIS_TUSER_WIDTH = 128,

    // max num pkts the pifo can store
    parameter PIFO_DEPTH = 64,
    parameter PIFO_REG_DEPTH = 4,
    parameter STORAGE_MAX_PKTS = 2048,
    parameter NUM_SKIP_LISTS = 1
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
    output                                         s_axis_tready,
    input                                          s_axis_tlast

);

   simple_tm_sl_bp
   #(
       .PIFO_DEPTH       (PIFO_DEPTH),
       .PIFO_REG_DEPTH   (PIFO_REG_DEPTH),
       .STORAGE_MAX_PKTS (STORAGE_MAX_PKTS),
       .NUM_SKIP_LISTS   (NUM_SKIP_LISTS)
   )
   simple_tm_inst
   (
       // Global Ports
       .axis_aclk (axis_aclk),
       .axis_resetn (axis_resetn),
       // pkt_storage output pkts
       .m_axis_tdata  (m_axis_tdata),
       .m_axis_tkeep  (m_axis_tkeep),
       .m_axis_tuser  (m_axis_tuser),
       .m_axis_tvalid (m_axis_tvalid),
       .m_axis_tready (m_axis_tready),
       .m_axis_tlast  (m_axis_tlast),
       // pkt_storage input pkts
       .s_axis_tdata  (s_axis_tdata),
       .s_axis_tkeep  (s_axis_tkeep),
       .s_axis_tuser  (s_axis_tuser),
       .s_axis_tvalid (s_axis_tvalid),
       .s_axis_tready (s_axis_tready),
       .s_axis_tlast  (s_axis_tlast)
   );

endmodule // cocotb_tm_wrapper

