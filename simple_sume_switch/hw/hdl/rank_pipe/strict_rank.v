`timescale 1ns/1ps

module strict_rank
#(
    parameter FLOW_ID_WIDTH = 16,
    parameter RANK_WIDTH = 16,
    parameter META_WIDTH = 16
)
(
    input                          rst,
    input                          clk,
    output                         busy,
    input                          insert,
    input      [META_WIDTH-1:0]    meta_in,
    input      [FLOW_ID_WIDTH-1:0] flowID_in,
    input                          remove,
    output reg                     valid_out,
    output     [RANK_WIDTH-1:0]    rank_out,
    output     [META_WIDTH-1:0]    meta_out
);

   //----------- localparams -------------

   localparam L2_MAX_DEPTH = 4; // 16 entries in FIFO

   //----------- wires and regs -------------

   reg  [META_WIDTH-1:0] fifo_meta_in;
   reg                   fifo_wr_en;
   reg                   fifo_rd_en;
   wire                  fifo_nearly_full;
   wire                  fifo_empty;

   //----------- modules and logic -------------

   fallthrough_small_fifo
      #(
          .WIDTH(RANK_WIDTH + META_WIDTH),
          .MAX_DEPTH_BITS(L2_MAX_DEPTH)
      )
      rank_fifo
        (.din         ({flowID_in, meta_in}),     // Data in
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

    // Insertion Logic
    always @(*) begin
        busy = ~fifo_nearly_full;
        if (insert) begin
            fifo_wr_en = 1;
        end
        else begin
            fifo_wr_en = 0;
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
