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
 *        axi_stream_pipeline.v
 *
 *  Library:
 *
 *  Module:
 *        axi_stream_pipeline
 *
 *  Author:
 *        Stephen Ibanez
 * 		
 *  Description:
 *       This module implements a simple AXI4 Stream pipeline stage 
 */

// `timescale 1ns/1ps

module axi_stream_pipeline
#(
    // Pkt AXI Stream Data Width
    parameter C_M_AXIS_DATA_WIDTH  = 256,
    parameter C_S_AXIS_DATA_WIDTH  = 256,
    parameter C_M_AXIS_TUSER_WIDTH = 128,
    parameter C_S_AXIS_TUSER_WIDTH = 128
)
(
    // Global Ports
    input                                      axis_aclk,
    input                                      axis_resetn,

    // Master Pkt Stream Ports (outgoing pkts) 
    output reg    [C_M_AXIS_DATA_WIDTH - 1:0]         m_axis_tdata,
    output reg    [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] m_axis_tkeep,
    output reg    [C_M_AXIS_TUSER_WIDTH-1:0]          m_axis_tuser,
    output reg                                        m_axis_tvalid,
    input                                             m_axis_tready,
    output reg                                        m_axis_tlast,

    // Slave Pkt Stream Ports (incomming pkts)
    input [C_S_AXIS_DATA_WIDTH - 1:0]              s_axis_tdata,
    input [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0]      s_axis_tkeep,
    input [C_S_AXIS_TUSER_WIDTH-1:0]               s_axis_tuser,
    input                                          s_axis_tvalid,
    output reg                                     s_axis_tready,
    input                                          s_axis_tlast

);

    always @(*) begin
        s_axis_tready = m_axis_tready;
    end

    always @(posedge axis_aclk) begin
        if (~axis_resetn) begin
            m_axis_tvalid <= 0;
            m_axis_tdata <= 0;
            m_axis_tkeep <= 0;
            m_axis_tuser <= 0;
            m_axis_tlast <= 0;
        end
        else begin
            m_axis_tvalid <= (m_axis_tready) ? s_axis_tvalid : m_axis_tvalid;
            m_axis_tdata <= (m_axis_tready) ? s_axis_tdata : m_axis_tdata;
            m_axis_tkeep <= (m_axis_tready) ? s_axis_tkeep : m_axis_tkeep;
            m_axis_tuser <= (m_axis_tready) ? s_axis_tuser : m_axis_tuser;
            m_axis_tlast <= (m_axis_tready) ? s_axis_tlast : m_axis_tlast;
        end
    end

//`ifdef COCOTB_SIM
//initial begin
//  $dumpfile("axi_stream_pipeline_waveform.vcd");
//  $dumpvars(0,axi_stream_pipeline);
//  #1 $display("Sim running...");
//end
//`endif
   
endmodule // axi_stream_pipeline

