`timescale 1ns/1ps

module pifo_top
#(
    parameter L2_MAX_SIZE = 5,
    parameter RANK_WIDTH = 10,
    parameter META_WIDTH = 20,
    parameter L2_REG_WIDTH = 2,
    parameter NUM_SKIP_LISTS = 5
)
(
    input                        rst,
    input                        clk,
    input                        insert,
    input                        remove,
    input  [RANK_WIDTH-1:0]      rank_in,
    input  [META_WIDTH-1:0]      meta_in,
    output [RANK_WIDTH-1:0]      rank_out,
    output [META_WIDTH-1:0]      meta_out,
    output                       valid_out,
    output reg                   busy
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

    /*------------ local parameters ------------*/
    localparam L2_NUM_SL_FLOOR = log2(NUM_SKIP_LISTS);
    localparam NUM_LEVELS = L2_NUM_SL_FLOOR + 1;

    localparam TSTAMP_BITS = 32;

    /*------------ Wires and Regs ------------*/
    reg [NUM_SKIP_LISTS-1:0]            sl_insert;
    reg [NUM_SKIP_LISTS-1:0]            sl_remove;
    reg [RANK_WIDTH-1:0]                sl_rank_in [NUM_SKIP_LISTS-1:0];
    reg [META_WIDTH+TSTAMP_BITS-1:0]    sl_meta_in [NUM_SKIP_LISTS-1:0];
    wire [RANK_WIDTH-1:0]               sl_rank_out [NUM_SKIP_LISTS-1:0];
    wire [META_WIDTH+TSTAMP_BITS-1:0]   sl_meta_out [NUM_SKIP_LISTS-1:0];
    wire [NUM_SKIP_LISTS-1:0]           sl_valid_out;
    wire [NUM_SKIP_LISTS-1:0]           sl_busy_out;
    wire [L2_MAX_SIZE-1:0]              sl_num_entries [NUM_SKIP_LISTS-1:0];

    // insertion selection signals
    reg                     sl_valid_lvls        [NUM_LEVELS:0] [(2**NUM_LEVELS)-1:0];
    reg [L2_MAX_SIZE-1:0]   sl_num_entries_lvls  [NUM_LEVELS:0] [(2**NUM_LEVELS)-1:0];
    reg [L2_NUM_SL_FLOOR:0] skip_list_sel        [NUM_LEVELS:0] [(2**NUM_LEVELS)-1:0];
 
    reg                     final_sel_valid;
    reg [L2_NUM_SL_FLOOR:0] final_sel_skip_list;

    reg [TSTAMP_BITS-1:0] tstamp_r;

    // removal selection signals
    reg                     valid_out_lvls    [NUM_LEVELS:0] [(2**NUM_LEVELS)-1:0];
    reg [L2_MAX_SIZE-1:0]   rank_out_lvls     [NUM_LEVELS:0] [(2**NUM_LEVELS)-1:0];
    reg [TSTAMP_BITS-1:0]   tstamp_out_lvls   [NUM_LEVELS:0] [(2**NUM_LEVELS)-1:0];
    reg [L2_NUM_SL_FLOOR:0] deq_sl_sel        [NUM_LEVELS:0] [(2**NUM_LEVELS)-1:0];

    reg                     final_deq_sel_valid;
    reg [L2_NUM_SL_FLOOR:0] final_deq_sel_sl;

    // output regs
    reg valid_out_r, valid_out_r_next;
    reg [RANK_WIDTH-1:0] rank_out_r, rank_out_r_next;
    reg [META_WIDTH-1:0] meta_out_r, meta_out_r_next;

    /*------------ Modules and Logic ------------*/

    /* Parallel skip lists */
    genvar k;
    generate
        for (k=0; k<NUM_SKIP_LISTS; k=k+1) begin: skip_lists
            det_skip_list
            #(
             .L2_MAX_SIZE(L2_MAX_SIZE),
             .RANK_WIDTH(RANK_WIDTH),
             .HSP_WIDTH(HSP_WIDTH),
             .MDP_WIDTH(MDP_WIDTH + TSTAMP_BITS),
             .L2_REG_WIDTH(L2_REG_WIDTH)
            )
            det_skip_list_inst
            (
             .rst          (rst),
             .clk          (clk),
             .insert       (sl_insert[k]),
             .remove       (sl_remove[k]),
             .rank_in      (sl_rank_in[k]),
             .meta_in      (sl_meta_in[k]),
             .rank_out     (sl_rank_out[k]),
             .meta_out     (sl_meta_out[k]),
             .valid_out    (sl_valid_out[k]),
             .busy         (sl_busy[k]),
             .num_entries  (sl_num_entries[k])
            );
        end
    endgenerate

    /* Logic to select which skip list to enqueue into */ 
    integer i, j, m, n;
    always @(*) begin
        // initialize level 0 with skip lists signals
        for (m=0; m<NUM_SKIP_LISTS; m=m+1) begin
            sl_valid_lvls[0][m] = ~sl_busy[m];
            sl_num_entries_lvls[0][m] = sl_num_entries[m];
        end
 
        // initialize extra entries with valid = 0 so they are never chosen
        for (n=NUM_SKIP_LISTS; n<2**NUM_LEVELS; n=n+1) begin
            sl_valid_lvls[0][n] = 0;
            sl_num_entries_lvls[0][n] = -1;
        end
 
        /* Select a skip list to insert into */
        for (j=0; j<NUM_LEVELS; j=j+1) begin  // loop over each level
            for (i=0; i<2**(NUM_LEVELS-j); i=i+2) begin // loop over each comparator in each level
                sl_valid_lvls[j+1][i/2] = sl_valid_lvls[j][i] | sl_valid_lvls[j][i+1];
                if (sl_valid_lvls[j][i] & sl_valid_lvls[j][i+1]) begin
                    // both skip lists are available
                    if (sl_num_entries_lvls[j][i] =< sl_num_entries_lvls[j][i+1]) begin
                        sl_num_entries_lvls[j+1][i/2] = sl_num_entries_lvls[j][i];
                        skip_list_sel[j+1][i/2] = i; //TODO: need to trim to appropriate size?
                    end
                    else begin
                        sl_num_entries_lvls[j+1][i/2] = sl_num_entries_lvls[j][i+1];
                        skip_list_sel[j+1][i/2] = i+1; //TODO: need to trim to appropriate size?
                    end
                end
                else if (sl_valid_lvls[j][i]) begin
                    sl_num_entries_lvls[j+1][i/2] = sl_num_entries_lvls[j][i];
                    skip_list_sel[j+1][i/2] = i; //TODO: need to trim to appropriate size?
                end
                else if (sl_valid_lvls[j][i+1]) begin
                    sl_num_entries_lvls[j+1][i/2] = sl_num_entries_lvls[j][i+1];
                    skip_list_sel[j+1][i/2] = i+1; //TODO: need to trim to appropriate size?
                end
                else begin
                    // neither skip list is available
                    sl_num_entries_lvls[j+1][i/2] = -1;
                    skip_list_sel[j+1][i/2] = -1;
                end
            end
        end
 
        final_sel_valid = sl_valid_lvls[NUM_LEVELS][0];
        final_sel_skip_list = skip_list_sel[NUM_LEVELS][0];
 
    end

    /* Insertion Logic: Writes input requests into the (available) skip list with the min # entries */
    integer p;
    always @(*) begin
        // TODO: do we need to register the skip list inputs?
        for (p=0; p<NUM_SKIP_LISTS; p=p+1) begin
            if (final_sel_valid && p == final_sel_skip_list) begin
                sel_insert[p] = insert;
                sel_rank_in[p] = rank_in;
                sel_meta_in[p] = {meta_in, tstamp_r};
            end
            else begin
                sel_insert[p] = 0;
                sel_rank_in[p] = 0;
                sel_meta_in[p] = 0;
            end
        end
    end

    // register the busy signal
    always @(posedge clk) begin
        if (rst) begin
            busy <= 0;
            tstamp_r <= 0;
        end
        else begin
            busy <= ~final_sel_valid;
            tstamp_r <= tstamp_r + 1;
        end
    end


    /* Logic to choose which Skip List to dequeue from */
    integer q, r, s, u;
    always @(*) begin
        // initialize level 0 with skip lists signals
        for (s=0; s<NUM_SKIP_LISTS; s=s+1) begin
            valid_out_lvls[0][s]  = sl_valid_out[s];
            rank_out_lvls[0][s]   = sl_rank_out[s];
            tstamp_out_lvls[0][s] = sl_meta_out[s][TSTAMP_BITS-1:0];
        end

        // initialize extra entries with valid = 0 so they are never chosen
        for (u=NUM_SKIP_LISTS; u<2**NUM_LEVELS; u=u+1) begin
            valid_out_lvls[0][u] = 0;
            rank_out_lvls[0][u] = -1;
            tstamp_out_lvls[0][u] = -1;
        end

        /* Select a skip list to remove from */
        for (r=0; r<NUM_LEVELS; r=r+1) begin  // loop over each level
            for (q=0; q<2**(NUM_LEVELS-r); q=q+2) begin // loop over each comparator in each level
                valid_out_lvls[r+1][q/2] = valid_out_lvls[r][q] | valid_out_lvls[r][q+1];
                if (valid_out_lvls[r][q] & valid_out_lvls[r][q+1]) begin
                    // both skip lists are available
                    // first check rank values
                    if (rank_out_lvls[r][q] < rank_out_lvls[r][q+1]) begin
                        rank_out_lvls[r+1][q/2] = rank_out_lvls[r][q];
                        tstamp_out_lvls[r+1][q/2] = tstamp_out_lvls[r][q];
                        deq_sl_sel[r+1][q/2] = q; //TODO: need to trim to appropriate size?
                    end
                    else if (rank_out_lvls[r][q] > rank_out_lvls[r][q+1]) begin
                        rank_out_lvls[r+1][q/2] = rank_out_lvls[r][q+1];
                        tstamp_out_lvls[r+1][q/2] = tstamp_out_lvls[r][q+1];
                        deq_sl_sel[r+1][q/2] = q+1; //TODO: need to trim to appropriate size?
                    end
                    // next check timestamps
                    else if (tstamp_out_lvls[r][q] < tstamp_out_lvls[r][q+1]) begin
                        rank_out_lvls[r+1][q/2] = rank_out_lvls[r][q];
                        tstamp_out_lvls[r+1][q/2] = tstamp_out_lvls[r][q];
                        deq_sl_sel[r+1][q/2] = q; //TODO: need to trim to appropriate size?
                    end
                    else begin
                        rank_out_lvls[r+1][q/2] = rank_out_lvls[r][q+1];
                        tstamp_out_lvls[r+1][q/2] = tstamp_out_lvls[r][q+1];
                        deq_sl_sel[r+1][q/2] = q+1; //TODO: need to trim to appropriate size?
                    end
                end
                else if (valid_out_lvls[r][q]) begin
                    rank_out_lvls[r+1][q/2] = rank_out_lvls[r][q];
                    tstamp_out_lvls[r+1][q/2] = tstamp_out_lvls[r][q];
                    deq_sl_sel[r+1][q/2] = q; //TODO: need to trim to appropriate size?
                end
                else if (valid_out_lvls[r][q+1]) begin
                    rank_out_lvls[r+1][q/2] = rank_out_lvls[r][q+1];
                    tstamp_out_lvls[r+1][q/2] = tstamp_out_lvls[r][q+1];
                    deq_sl_sel[r+1][q/2] = q+1; //TODO: need to trim to appropriate size?
                end
                else begin
                    // neither skip list is available
                    rank_out_lvls[r+1][q/2] = -1;
                    tstamp_out_lvls[r+1][q/2] = -1;
                    deq_sl_sel[r+1][q/2] = -1;
                end
            end
        end

        final_deq_sel_valid = valid_out_lvls[NUM_LEVELS][0];
        final_deq_sel_sl = deq_sl_sel[NUM_LEVELS][0];

    end

    /* Removal logic: register the outputs and submit removal request */
    integer v;
    always @(*) begin
        valid_out = valid_out_r;
        rank_out = rank_out_r;
        meta_out = meta_out_r;

        valid_out_r_next = 0;
        rank_out_r_next = 0;
        meta_out_r_next = 0;

        for (v=0; v<NUM_SKIP_LISTS; v=v+1) begin
            if (final_deq_sel_valid && v == final_deq_sel_sl) begin
                sel_remove[v] = remove;

                valid_out_r_next = 1;
                rank_out_r_next = sel_rank_out[v];
                meta_out_r_next = sel_meta_out[v];
            end
            else begin
                sel_remove_r_next[v] = 0;
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            valid_out_r <= 0;
            rank_out_r <= 0;
            meta_out_r <= 0;
        end
        else begin
            valid_out_r <= valid_out_r_next;
            rank_out_r <= rank_out_r_next; 
            meta_out_r <= meta_out_r_next;
        end
    end

endmodule

