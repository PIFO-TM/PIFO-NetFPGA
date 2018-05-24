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
    parameter FLOW_ID_WIDTH = 16,
    parameter FLOW_WEIGHT_WIDTH = 8,
    parameter MAX_NUM_FLOWS = 4,
    parameter RANK_CODE_BITS = 2,
    parameter RANK_WIDTH = 16,
    parameter META_WIDTH = 16,

    parameter STRICT_OP = 0,
//    parameter RR_OP     = 1,
//    parameter WRR_OP    = 2,

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
    input      [FLOW_ID_WIDTH-1:0]     flowID_in,
    input      [FLOW_WEIGHT_WIDTH-1:0] flow_weight_in,

    // Output Interface -- Can only remove on cycles where valid_out == 1
    input                              remove,
    output reg                         valid_out,
    output     [RANK_WIDTH-1:0]        rank_out,
    output     [META_WIDTH-1:0]        meta_out
);

    // ------- localparams ------
    localparam L2_MAX_DEPTH = 4; // 16 entries in FIFO
    localparam INPUT_FIFO_WIDTH = RANK_CODE_BITS + META_WIDTH + FLOW_ID_WIDTH + FLOW_WEIGHT_WIDTH;
    localparam OUTPUT_FIFO_WIDTH = RANK_WIDTH + META_WIDTH;

    // ------- Wires -------

    reg  [INPUT_FIFO_WIDTH-1:0]  i_fifo_data_in;
    wire [RANK_CODE_BITS-1:0]    i_fifo_rank_op_out;
    wire [META_WIDTH-1:0]        i_fifo_meta_out;
    wire [FLOW_ID_WIDTH-1:0]     i_fifo_flowID_out;
    wire [FLOW_WEIGHT_WIDTH-1:0] i_fifo_flow_weight_out;
    reg                          i_fifo_wr_en;
    reg                          i_fifo_rd_en;
    wire                         i_fifo_nearly_full;
    wire                         i_fifo_empty;

    reg  [OUTPUT_FIFO_WIDTH-1:0]  o_fifo_data_in;
    reg                           o_fifo_wr_en;
    reg                           o_fifo_rd_en;
    wire                          o_fifo_nearly_full;
    wire                          o_fifo_empty;

    // ranks pipe signals
    wire [NUM_RANK_OPS-1:0]      pipe_busy;
    reg  [NUM_RANK_OPS-1:0]      pipe_insert;
    reg  [META_WIDTH-1:0]        pipe_meta_in        [NUM_RANK_OPS-1:0];
    reg  [FLOW_ID_WIDTH-1:0]     pipe_flowID_in      [NUM_RANK_OPS-1:0];
    reg  [FLOW_WEIGHT_WIDTH-1:0] pipe_flow_weight_in [NUM_RANK_OPS-1:0];
    wire [NUM_RANK_OPS-1:0]      pipe_valid_out;
    reg  [NUM_RANK_OPS-1:0]      pipe_remove;
    wire [RANK_WIDTH-1:0]        pipe_rank_out [NUM_RANK_OPS-1:0];
    wire [META_WIDTH-1:0]        pipe_meta_out [NUM_RANK_OPS-1:0];

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
          .dout        ({i_fifo_rank_op_out, i_fifo_meta_out, i_fifo_flowID_out, i_fifo_flow_weight_out}),
          .full        (),
          .prog_full   (),
          .nearly_full (i_fifo_nearly_full),
          .empty       (i_fifo_empty),
          .reset       (rst),
          .clk         (clk)
          );

    strict_rank
    #(
        .FLOW_ID_WIDTH     (FLOW_ID_WIDTH),
        .RANK_WIDTH        (RANK_WIDTH),
        .META_WIDTH        (META_WIDTH)
    )
    strict_rank_pipe
    (
        .rst             (rst),
        .clk             (clk),
        .busy            (pipe_busy[STRICT_OP]), 
        .insert          (pipe_insert[STRICT_OP]),
        .meta_in         (pipe_meta_in[STRICT_OP]),
        .flowID_in       (pipe_flowID_in[STRICT_OP]),
        .remove          (pipe_remove[STRICT_OP]),
        .valid_out       (pipe_valid_out[STRICT_OP]),
        .rank_out        (pipe_rank_out[STRICT_OP]),
        .meta_out        (pipe_meta_out[STRICT_OP])
    );

//    rr_rank
//    #(
//        .FLOW_ID_WIDTH     (FLOW_ID_WIDTH),
//        .MAX_NUM_FLOWS     (MAX_NUM_FLOWS),
//        .RANK_WIDTH        (RANK_WIDTH),
//        .META_WIDTH        (META_WIDTH)
//    )
//    rr_rank_pipe
//    (
//        .rst             (rst),
//        .clk             (clk),
//        .busy            (pipe_busy[RR_OP]),
//        .insert          (pipe_insert[RR_OP]),
//        .meta_in         (pipe_meta_in[RR_OP]),
//        .flowID_in       (pipe_flowID_in[RR_OP]),
//        .remove          (pipe_remove[RR_OP]),
//        .valid_out       (pipe_valid_out[RR_OP]),
//        .rank_out        (pipe_rank_out[RR_OP]),
//        .meta_out        (pipe_meta_out[RR_OP])
//    );

//    wrr_rank
//    #(
//        .FLOW_ID_WIDTH     (FLOW_ID_WIDTH),
//        .FLOW_WEIGHT_WIDTH (FLOW_WEIGHT_WIDTH),
//        .MAX_NUM_FLOWS     (MAX_NUM_FLOWS),
//        .RANK_WIDTH        (RANK_WIDTH),
//        .META_WIDTH        (META_WIDTH)
//    )
//    wrr_rank_pipe
//    (
//        .rst             (rst),
//        .clk             (clk),
//        .busy            (pipe_busy[WRR_OP]),
//        .insert          (pipe_insert[WRR_OP]),
//        .meta_in         (pipe_meta_in[WRR_OP]),
//        .flowID_in       (pipe_flowID_in[WRR_OP]),
//        .flow_weight_in  (pipe_flow_weight_in[WRR_OP]),
//        .remove          (pipe_remove[WRR_OP]),
//        .valid_out       (pipe_valid_out[WRR_OP]),
//        .rank_out        (pipe_rank_out[WRR_OP]),
//        .meta_out        (pipe_meta_out[WRR_OP])
//    );

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
        if (rank_op_in < NUM_RANK_OPS) begin
            i_fifo_data_in = {rank_op_in, meta_in, flowID_in, flow_weight_in};
        end
        else begin
            // do not drop metadata, set default rank_op
            i_fifo_data_in = { {RANK_CODE_BITS{1'b0}}, meta_in, flowID_in, flow_weight_in};
        end

        // Logic to insert into rank pipe 
        i_fifo_rd_en = 0;
        for (i=0; i<NUM_RANK_OPS; i=i+1) begin
            if ((i == i_fifo_rank_op_out) && ~i_fifo_empty && ~pipe_busy[i]) begin
                i_fifo_rd_en = 1;
                pipe_insert[i_fifo_rank_op_out] = 1;
                pipe_meta_in[i_fifo_rank_op_out] = i_fifo_meta_out;
                pipe_flowID_in[i_fifo_rank_op_out] = i_fifo_flowID_out;
                pipe_flow_weight_in[i_fifo_rank_op_out] = i_fifo_flow_weight_out;
            end
            else begin
                pipe_insert[i] = 0;
                pipe_meta_in[i] = 0;
                pipe_flowID_in[i] = 0;
                pipe_flow_weight_in[i] = 0;
            end
        end
    end

    // Removal Logic
    integer j;
    always @(*) begin
        // Logic to remove from rank pipe and insert into output FIFO

        o_fifo_data_in = 0;
        o_fifo_wr_en = 0;

        for (j=0; j<NUM_RANK_OPS; j=j+1) begin
            pipe_remove[j] = 0;
        end

        if (pipe_valid_out[STRICT_OP]) begin
            pipe_remove[STRICT_OP] = 1;
            o_fifo_wr_en = 1;
            o_fifo_data_in = {pipe_rank_out[STRICT_OP], pipe_meta_out[STRICT_OP]};
        end
//        else if (pipe_valid_out[RR_OP]) begin
//            pipe_remove[RR_OP] = 1;
//            o_fifo_wr_en = 1;
//            o_fifo_data_in = {pipe_rank_out[RR_OP], pipe_meta_out[RR_OP]};
//        end
//        else if (pipe_valid_out[WRR_OP]) begin
//            pipe_remove[WRR_OP] = 1;
//            o_fifo_wr_en = 1;
//            o_fifo_data_in = {pipe_rank_out[WRR_OP], pipe_meta_out[WRR_OP]};
//        end

        // Logic to remove from output FIFO
        valid_out = ~o_fifo_empty;
        if (remove) begin
            o_fifo_rd_en = 1;
        end
        else begin
            o_fifo_rd_en = 0;
        end
    end
endmodule
