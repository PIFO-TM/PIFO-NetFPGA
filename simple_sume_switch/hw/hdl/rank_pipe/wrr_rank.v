`timescale 1ns/1ps

module wrr_rank
#(
    parameter FLOW_ID_WIDTH = 16,
    parameter FLOW_WEIGHT_WIDTH = 8,
    parameter MAX_NUM_FLOWS = 4,
    parameter RANK_WIDTH = 16,
    parameter META_WIDTH = 16
)
(
    input                              rst,
    input                              clk,
    output reg                         busy,
    input                              insert,
    input      [META_WIDTH-1:0]        meta_in,
    input      [FLOW_ID_WIDTH-1:0]     flowID_in,
    input      [FLOW_WEIGHT_WIDTH-1:0] flow_weight_in,
    input                              remove,
    output reg                         valid_out,
    output     [RANK_WIDTH-1:0]        rank_out,
    output     [META_WIDTH-1:0]        meta_out
);

   //----------- localparams -------------

   localparam L2_MAX_DEPTH = 4; // 16 entries in FIFO

   //----------- wires and regs -------------

   reg  [RANK_WIDTH-1:0] fifo_rank_in;
   reg  [META_WIDTH-1:0] fifo_meta_in;
   reg                   fifo_wr_en;
   reg                   fifo_rd_en;
   wire                  fifo_nearly_full;
   wire                  fifo_empty;

   reg [RANK_WIDTH-1:0]    max_rank_r, max_rank_r_next;
   reg [MAX_NUM_FLOWS-1:0] num_active_flows_r, num_active_flows_r_next;
   reg [RANK_WIDTH-1:0] flow_last_rank_r [MAX_NUM_FLOWS-1:0];
   reg [RANK_WIDTH-1:0] flow_last_rank_r_next [MAX_NUM_FLOWS-1:0];

   reg [FLOW_WEIGHT_WIDTH-1:0] flow_cnt_r [MAX_NUM_FLOWS-1:0];
   reg [FLOW_WEIGHT_WIDTH-1:0] flow_cnt_r_next [MAX_NUM_FLOWS-1:0];

   //----------- modules and logic -------------

   fallthrough_small_fifo
      #(
          .WIDTH(RANK_WIDTH + META_WIDTH),
          .MAX_DEPTH_BITS(L2_MAX_DEPTH)
      )
      rank_fifo
        (.din         ({fifo_rank_in, meta_in}),     // Data in
         .wr_en       (fifo_wr_en),       // Write enable
         .rd_en       (fifo_rd_en),       // Read the next word
         .dout        ({rank_out, meta_out}),
         .full        (),
         .prog_full   (),
         .nearly_full (fifo_nearly_full),
         .empty       (fifo_empty),
         .reset       (rst),
         .clk         (clk)
         );

    integer i;
    always @(*) begin
        // defaults
        busy = fifo_nearly_full;
        fifo_wr_en = 0;
        fifo_rank_in = 0;

        max_rank_r_next = max_rank_r;
        num_active_flows_r_next = num_active_flows_r;
        for (i=0; i < MAX_NUM_FLOWS; i=i+1) begin
            flow_last_rank_r_next[i] = flow_last_rank_r[i];
            flow_cnt_r_next[i] = flow_cnt_r[i];
        end

        if (insert && flowID_in < MAX_NUM_FLOWS) begin
            fifo_wr_en = 1;
            if (flow_last_rank_r[flowID_in] == 0) begin
                // have not seen this flow before
                fifo_rank_in = max_rank_r + 1;
                num_active_flows_r_next = num_active_flows_r + 1;
                flow_cnt_r_next[flowID_in] = 1;
            end
            else begin
                // have seen this flow before
                if (flow_cnt_r[flowID_in] == flow_weight_in) begin
                    fifo_rank_in = flow_last_rank_r[flowID_in] + num_active_flows_r;
                    flow_cnt_r_next[flowID_in] = 1;
                end
                else begin
                    fifo_rank_in = flow_last_rank_r[flowID_in];
                    flow_cnt_r_next[flowID_in] = flow_cnt_r[flowID_in] + 1;
                end
            end
            // update state
            if (fifo_rank_in > max_rank_r) begin
                max_rank_r_next = fifo_rank_in;
            end
            flow_last_rank_r_next[flowID_in] = fifo_rank_in;
        end
        else begin
            if (flowID_in >= MAX_NUM_FLOWS)
                $display("ERROR: wrr_rank: flowID_in >= MAX_NUM_FLOWS, flowID_in = %d\n" % flowID_in);
        end
    end

    // State Update
    integer j;
    always @(posedge clk) begin
        if (rst) begin
            max_rank_r <= 0;
            num_active_flows_r <= 0;
        end
        else begin
            max_rank_r <= max_rank_r_next;
            num_active_flows_r <= num_active_flows_r_next;
        end

        for (j=0; j < MAX_NUM_FLOWS; j=j+1) begin
            if (rst) begin
                flow_last_rank_r[j] <= 0;
                flow_cnt_r[j] <= 0;
            end
            else begin
                flow_last_rank_r[j] <= flow_last_rank_r_next[j];
                flow_cnt_r[j] <= flow_cnt_r_next[j];
            end
        end
    end

    // Removal Logic
    always @(*) begin
        valid_out = ~fifo_empty;
        if (remove) begin
            fifo_rd_en = 1;
        end
        else begin
            fifo_rd_en = 0;
        end
    end
    
endmodule
