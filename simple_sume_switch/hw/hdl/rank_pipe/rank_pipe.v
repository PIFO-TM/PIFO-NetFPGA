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

`timescale 1ns/1ps

module rank_pipe
#(
    parameter RANK_CODE_BITS = 2,
    parameter RANK_WIDTH = 16,
    parameter META_WIDTH = 16,

    parameter SRPT_OP = 0,

    parameter NUM_RANK_OPS = 1
)
(
    input                              rst,
    input                              clk,

    // Input Interface -- Can only insert on cycles where busy == 0
    output reg                         busy,
    input                              insert,
    input      [META_WIDTH-1:0]        meta_in,
    input      [RANK_CODE_BITS-1:0]    rank_op_in,
    input      [RANK_WIDTH-1:0]        srpt_rank_in,

    // Output Interface -- Can only remove on cycles where valid_out == 1
    input                              remove,
    output reg                         valid_out,
    output     [RANK_WIDTH-1:0]        rank_out,
    output     [META_WIDTH-1:0]        meta_out
);

    // ------- localparams ------
    localparam L2_MAX_DEPTH = 6; // 64 entries in FIFO
    localparam INPUT_FIFO_WIDTH = RANK_CODE_BITS + META_WIDTH + RANK_WIDTH;
    localparam OUTPUT_FIFO_WIDTH = RANK_WIDTH + META_WIDTH;

    // ------- Wires -------

    reg  [INPUT_FIFO_WIDTH-1:0]  i_fifo_data_in;
    wire [RANK_CODE_BITS-1:0]    i_fifo_rank_op_out;
    wire [META_WIDTH-1:0]        i_fifo_meta_out;
    wire [RANK_WIDTH-1:0]        i_fifo_srpt_rank_out;
    reg                          i_fifo_wr_en;
    reg                          i_fifo_rd_en;
    wire                         i_fifo_nearly_full;
    wire                         i_fifo_empty;

    reg  [OUTPUT_FIFO_WIDTH-1:0]  o_fifo_data_in;
    reg                           o_fifo_wr_en;
    reg                           o_fifo_rd_en;
    wire                          o_fifo_nearly_full;
    wire                          o_fifo_empty;

    // -------- Modules --------
    fallthrough_small_fifo
       #(
           .WIDTH(INPUT_FIFO_WIDTH),
           .MAX_DEPTH_BITS(L2_MAX_DEPTH)
       )
       input_fifo
         (.din         (i_fifo_data_in),     // Data in
          .wr_en       (i_fifo_wr_en),       // Write enable
          .rd_en       (i_fifo_rd_en),       // Read the next word
          .dout        ({i_fifo_rank_op_out, i_fifo_meta_out, i_fifo_srpt_rank_out}),
          .full        (),
          .prog_full   (),
          .nearly_full (i_fifo_nearly_full),
          .empty       (i_fifo_empty),
          .reset       (rst),
          .clk         (clk)
          );


    fallthrough_small_fifo
       #(
           .WIDTH(OUTPUT_FIFO_WIDTH),
           .MAX_DEPTH_BITS(L2_MAX_DEPTH)
       )
       output_fifo
         (.din         (o_fifo_data_in),     // Data in
          .wr_en       (o_fifo_wr_en),       // Write enable
          .rd_en       (o_fifo_rd_en),       // Read the next word
          .dout        ({rank_out, meta_out}),
          .full        (),
          .prog_full   (),
          .nearly_full (o_fifo_nearly_full),
          .empty       (o_fifo_empty),
          .reset       (rst),
          .clk         (clk)
          );

    // -------- Logic --------

    // Insertion Logic 
    integer i;
    always @(*) begin
        // Logic to insert into FIFO
        busy = i_fifo_nearly_full;
        i_fifo_wr_en = insert;
        i_fifo_data_in = {rank_op_in, meta_in, srpt_rank_in};
    end

    // Removal Logic
    integer j;
    always @(*) begin
        // Logic to remove from input FIFO and insert into output FIFO
        i_fifo_rd_en = 0;
        o_fifo_data_in = 0;
        o_fifo_wr_en = 0;

        if (~o_fifo_nearly_full & ~i_fifo_empty) begin
            i_fifo_rd_en = 1;
            o_fifo_wr_en = 1;
            o_fifo_data_in = {i_fifo_srpt_rank_out, i_fifo_meta_out};
        end

        // Logic to remove from output FIFO
        valid_out = ~o_fifo_empty;
        o_fifo_rd_en = remove;
    end
endmodule
