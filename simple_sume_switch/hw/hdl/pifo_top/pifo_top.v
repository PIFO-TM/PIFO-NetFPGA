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
    input                            rst,
    input                            clk,
    input                            insert,
    input                            remove,
    input      [RANK_WIDTH-1:0]      rank_in,
    input      [META_WIDTH-1:0]      meta_in,
    output     [RANK_WIDTH-1:0]      rank_out,
    output     [META_WIDTH-1:0]      meta_out,
    output                           valid_out,
    output reg                       busy,
    output reg                       full
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

    localparam L2_IFSM_STATES = 2;
    localparam IFSM_IDLE      = 0;
    localparam INSERT_REG     = 1;
    localparam INSERT_SEARCH  = 2;
    localparam INSERT_SL      = 3;

    localparam TSTAMP_BITS = 32;
    localparam L2_SKIP_LIST_SIZE = L2_MAX_SIZE - log2(NUM_SKIP_LISTS) + 1;
//    localparam L2_SKIP_LIST_SIZE = L2_MAX_SIZE;

    /*------------ Wires and Regs ------------*/
    reg                               pr_insert;
    reg  [RANK_WIDTH-1:0]             pr_rank_in;
    reg  [META_WIDTH+TSTAMP_BITS-1:0] pr_meta_in;
    wire [RANK_WIDTH-1:0]             pr_max_rank;
    wire [META_WIDTH+TSTAMP_BITS-1:0] pr_max_meta;
    wire                              pr_max_valid;
    wire [L2_REG_WIDTH:0]             pr_num_entries;
    wire                              pr_empty;
    wire                              pr_full;
    wire [META_WIDTH+TSTAMP_BITS-1:0] pr_meta_out;

    reg pr_insert_last_r, pr_insert_last_r_next; 
    reg direct_pr_insert;

    reg [NUM_SKIP_LISTS-1:0]            sl_insert;
    reg [NUM_SKIP_LISTS-1:0]            sl_remove;
    reg [RANK_WIDTH-1:0]                sl_rank_in [NUM_SKIP_LISTS-1:0];
    reg [META_WIDTH+TSTAMP_BITS-1:0]    sl_meta_in [NUM_SKIP_LISTS-1:0];
    wire [RANK_WIDTH-1:0]               sl_rank_out [NUM_SKIP_LISTS-1:0];
    wire [META_WIDTH+TSTAMP_BITS-1:0]   sl_meta_out [NUM_SKIP_LISTS-1:0];
    wire [NUM_SKIP_LISTS-1:0]           sl_valid_out;
    wire [NUM_SKIP_LISTS-1:0]           sl_busy_out;
    wire [NUM_SKIP_LISTS-1:0]           sl_full_out;
    wire [L2_SKIP_LIST_SIZE:0]          sl_num_entries [NUM_SKIP_LISTS-1:0];
    reg  [NUM_SKIP_LISTS-1:0]           sl_empty;

    // insertion selection signals
    reg [(2**NUM_LEVELS)-1:0]    sl_valid_lvls        [NUM_LEVELS:0];
    reg [L2_MAX_SIZE-1:0]        sl_num_entries_lvls  [NUM_LEVELS:0] [(2**NUM_LEVELS)-1:0];
    reg [L2_NUM_SL_FLOOR:0]      skip_list_sel        [NUM_LEVELS:0] [(2**NUM_LEVELS)-1:0];
 
    reg                     final_enq_sel_valid_r, final_enq_sel_valid_r_next;
    reg [L2_NUM_SL_FLOOR:0] final_enq_sel_sl_r, final_enq_sel_sl_r_next;

    reg [TSTAMP_BITS-1:0] tstamp_r;

    reg [L2_IFSM_STATES-1:0] ifsm_state, ifsm_state_next;
    reg [RANK_WIDTH-1:0]     rank_in_r, rank_in_r_next;
    reg [META_WIDTH+TSTAMP_BITS-1:0]     meta_in_r, meta_in_r_next;

    reg                  sl_min_rank_valid;
    reg [RANK_WIDTH-1:0] sl_min_rank;
    reg                  insert_reg;
    reg                  insert_unknown;

    reg [RANK_WIDTH-1:0] rank_in_val;

    // removal selection signals
    reg [(2**NUM_LEVELS)-1:0]  valid_out_lvls    [NUM_LEVELS:0];
    reg [RANK_WIDTH-1:0]       rank_out_lvls     [NUM_LEVELS:0] [(2**NUM_LEVELS)-1:0];
    reg [TSTAMP_BITS-1:0]      tstamp_out_lvls   [NUM_LEVELS:0] [(2**NUM_LEVELS)-1:0];
    reg [L2_NUM_SL_FLOOR:0]    deq_sl_sel        [NUM_LEVELS:0] [(2**NUM_LEVELS)-1:0];

    reg                       final_deq_sel_valid_r, final_deq_sel_valid_r_next;
    reg [L2_NUM_SL_FLOOR:0]   final_deq_sel_sl_r;
    reg [L2_NUM_SL_FLOOR:0]   final_deq_sel_sl_r_next;
    reg [NUM_SKIP_LISTS-1:0]  val_or_empty;
    reg                       deq_condition;

    /*------------ Modules and Logic ------------*/

    pifo_reg
    #(
        .L2_REG_WIDTH (L2_REG_WIDTH),
        .RANK_WIDTH  (RANK_WIDTH),
        .META_WIDTH  (META_WIDTH + TSTAMP_BITS)
    )
    pifo_reg_top
    (
        .rst           (rst),
        .clk           (clk),
        .insert        (pr_insert),
        .rank_in       (pr_rank_in),
        .meta_in       (pr_meta_in),
        .remove        (remove),
        .rank_out      (rank_out),
        .meta_out      (pr_meta_out),
        .valid_out     (valid_out),
        .max_rank_out  (pr_max_rank),
        .max_meta_out  (pr_max_meta),
        .max_valid_out (pr_max_valid),
        .num_entries   (pr_num_entries),
        .empty         (pr_empty),
        .full          (pr_full)
    );
    assign meta_out = pr_meta_out[META_WIDTH+TSTAMP_BITS-1:TSTAMP_BITS];

    /* Parallel skip lists */
    genvar k;
    generate
        for (k=0; k<NUM_SKIP_LISTS; k=k+1) begin: skip_lists
            det_skip_list
            #(
             .L2_MAX_SIZE(L2_SKIP_LIST_SIZE),
             .RANK_WIDTH(RANK_WIDTH),
             .META_WIDTH(META_WIDTH + TSTAMP_BITS),
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
             .busy         (sl_busy_out[k]),
             .full         (sl_full_out[k]),
             .num_entries  (sl_num_entries[k])
            );
        end
    endgenerate

    /* Logic to select which skip list to enqueue into */ 
    integer i, j, m, n;
    always @(*) begin
        // initialize level 0 with skip lists signals
        for (m=0; m<NUM_SKIP_LISTS; m=m+1) begin
            sl_valid_lvls[0][m] = ~sl_busy_out[m] & ~sl_full_out[m];
            sl_num_entries_lvls[0][m] = sl_num_entries[m];
            skip_list_sel[0][m] = m;
        end
 
        // initialize extra entries with valid = 0 so they are never chosen
        for (n=NUM_SKIP_LISTS; n<2**NUM_LEVELS; n=n+1) begin
            sl_valid_lvls[0][n] = 0;
            sl_num_entries_lvls[0][n] = -1;
            skip_list_sel[0][n] = n;
        end
    end

    always @(posedge clk) begin 
        /* Select a skip list to insert into */
        if (rst) begin
            for (j=0; j<NUM_LEVELS; j=j+1) begin  // loop over each level
                for (i=0; i<2**(NUM_LEVELS-j); i=i+2) begin // loop over each comparator in each level
                    sl_valid_lvls[j+1][i/2] <= 0;
                    sl_num_entries_lvls[j+1][i/2] <= 0;
                    skip_list_sel[j+1][i/2] <= 0;
                end
            end
        end
        else begin
            for (j=0; j<NUM_LEVELS; j=j+1) begin  // loop over each level
                for (i=0; i<2**(NUM_LEVELS-j); i=i+2) begin // loop over each comparator in each level
                    sl_valid_lvls[j+1][i/2] <= sl_valid_lvls[j][i] | sl_valid_lvls[j][i+1];
                    if (sl_valid_lvls[j][i] & sl_valid_lvls[j][i+1]) begin
                        // both skip lists are available
                        if (sl_num_entries_lvls[j][i] <= sl_num_entries_lvls[j][i+1]) begin
                            sl_num_entries_lvls[j+1][i/2] <= sl_num_entries_lvls[j][i];
                            skip_list_sel[j+1][i/2] <= skip_list_sel[j][i];
                        end
                        else begin
                            sl_num_entries_lvls[j+1][i/2] <= sl_num_entries_lvls[j][i+1];
                            skip_list_sel[j+1][i/2] <= skip_list_sel[j][i+1];
                        end
                    end
                    else if (sl_valid_lvls[j][i]) begin
                        sl_num_entries_lvls[j+1][i/2] <= sl_num_entries_lvls[j][i];
                        skip_list_sel[j+1][i/2] <= skip_list_sel[j][i]; 
                    end
                    else if (sl_valid_lvls[j][i+1]) begin
                        sl_num_entries_lvls[j+1][i/2] <= sl_num_entries_lvls[j][i+1];
                        skip_list_sel[j+1][i/2] <= skip_list_sel[j][i+1]; 
                    end
                    else begin
                        // neither skip list is available
                        sl_num_entries_lvls[j+1][i/2] <= -1;
                        skip_list_sel[j+1][i/2] <= -1;
                    end
                end
            end
        end
    end

    always @(*) begin 
        final_enq_sel_valid_r_next = sl_valid_lvls[NUM_LEVELS][0];
        final_enq_sel_sl_r_next = skip_list_sel[NUM_LEVELS][0];
    end

    // register the enqueue skip list selection
    always @(posedge clk) begin
        if (rst) begin
            final_enq_sel_valid_r <= 0;
            final_enq_sel_sl_r <= 0;
        end
        else begin
            final_enq_sel_valid_r <= final_enq_sel_valid_r_next;
            final_enq_sel_sl_r    <= final_enq_sel_sl_r_next;
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
            deq_sl_sel[0][s] = s;
            // wait for each skip list to either assert valid_out or be empty before removing anything
//            val_or_empty[s] = sl_valid_out[s] | (sl_num_entries[s] == 0);
            sl_empty[s] = (sl_num_entries[s] == 0);
        end

        // initialize extra entries with valid = 0 so they are never chosen
        for (u=NUM_SKIP_LISTS; u<2**NUM_LEVELS; u=u+1) begin
            valid_out_lvls[0][u] = 0;
            rank_out_lvls[0][u] = -1;
            tstamp_out_lvls[0][u] = -1;
            deq_sl_sel[0][u] = u;
        end
    end

    always @(posedge clk) begin
        /* Select a skip list to remove from */
        if (rst) begin
            for (r=0; r<NUM_LEVELS; r=r+1) begin  // loop over each level
                for (q=0; q<2**(NUM_LEVELS-r); q=q+2) begin // loop over each comparator in each level
                    valid_out_lvls[r+1][q/2] <= 0;
                    rank_out_lvls[r+1][q/2] <= 0;
                    tstamp_out_lvls[r+1][q/2] <= 0;
                    deq_sl_sel[r+1][q/2] <= 0;
                end
            end
        end
        else begin
            for (r=0; r<NUM_LEVELS; r=r+1) begin  // loop over each level
                for (q=0; q<2**(NUM_LEVELS-r); q=q+2) begin // loop over each comparator in each level
                    valid_out_lvls[r+1][q/2] <= valid_out_lvls[r][q] | valid_out_lvls[r][q+1];
                    if (valid_out_lvls[r][q] & valid_out_lvls[r][q+1]) begin
                        // both skip lists are available
                        // first check rank values
                        if (rank_out_lvls[r][q] < rank_out_lvls[r][q+1]) begin
                            rank_out_lvls[r+1][q/2] <= rank_out_lvls[r][q];
                            tstamp_out_lvls[r+1][q/2] <= tstamp_out_lvls[r][q];
                            deq_sl_sel[r+1][q/2] <= deq_sl_sel[r][q];
                        end
                        else if (rank_out_lvls[r][q] > rank_out_lvls[r][q+1]) begin
                            rank_out_lvls[r+1][q/2] <= rank_out_lvls[r][q+1];
                            tstamp_out_lvls[r+1][q/2] <= tstamp_out_lvls[r][q+1];
                            deq_sl_sel[r+1][q/2] <= deq_sl_sel[r][q+1];
                        end
                        // next check timestamps
                        else if (tstamp_out_lvls[r][q] < tstamp_out_lvls[r][q+1]) begin
                            rank_out_lvls[r+1][q/2] <= rank_out_lvls[r][q];
                            tstamp_out_lvls[r+1][q/2] <= tstamp_out_lvls[r][q];
                            deq_sl_sel[r+1][q/2] <= deq_sl_sel[r][q];
                        end
                        else begin
                            rank_out_lvls[r+1][q/2] <= rank_out_lvls[r][q+1];
                            tstamp_out_lvls[r+1][q/2] <= tstamp_out_lvls[r][q+1];
                            deq_sl_sel[r+1][q/2] <= deq_sl_sel[r][q+1];
                        end
                    end
                    else if (valid_out_lvls[r][q]) begin
                        rank_out_lvls[r+1][q/2] <= rank_out_lvls[r][q];
                        tstamp_out_lvls[r+1][q/2] <= tstamp_out_lvls[r][q];
                        deq_sl_sel[r+1][q/2] <= deq_sl_sel[r][q];
                    end
                    else if (valid_out_lvls[r][q+1]) begin
                        rank_out_lvls[r+1][q/2] <= rank_out_lvls[r][q+1];
                        tstamp_out_lvls[r+1][q/2] <= tstamp_out_lvls[r][q+1];
                        deq_sl_sel[r+1][q/2] <= deq_sl_sel[r][q+1];
                    end
                    else begin
                        // neither skip list is available
                        rank_out_lvls[r+1][q/2] <= -1;
                        tstamp_out_lvls[r+1][q/2] <= -1;
                        deq_sl_sel[r+1][q/2] <= -1;
                    end
                end
            end
        end
    end

    // dequeue selection comparison tree result
    always @(*) begin
//        deq_condition = &val_or_empty;
        // the output is valid if the selected skip list is asserting valid_out
        //    and all skip lists are either empty or asserting valid_out

        final_deq_sel_valid_r_next = valid_out_lvls[NUM_LEVELS][0]; 
        final_deq_sel_sl_r_next = deq_sl_sel[NUM_LEVELS][0];
    end

    always @(posedge clk) begin
        if (rst) begin
            final_deq_sel_valid_r <= 0;
            final_deq_sel_sl_r <= 0;
        end
        else begin
            final_deq_sel_valid_r <= final_deq_sel_valid_r_next;
            final_deq_sel_sl_r <= final_deq_sel_sl_r_next;
        end
    end


    /* Insertion Logic and pifo_reg replenishment logic */
    integer p;
    always @(*) begin
        /* Insertion State Machine:
         *   - Insert into the pifo_reg if the new value is less than the current max
         *   - If the pifo_reg is full when inserting into it then insert the old max into the skip lists
         *   - If the new value is greater than the current max in the pifo_reg then insert directly into the skip lists 
         */

        // default values
        ifsm_state_next = ifsm_state;

        full = &sl_full_out & pr_full;

        // don't perform any insertions if we don't have a skip list to try enqueueing into
        // or the pifo_reg is not empty and the max_valid signal is low
        busy = ~final_enq_sel_valid_r | ((pr_num_entries != 0) && ~pr_max_valid);

        // input regs hold value by default
        rank_in_r_next = rank_in_r;
        meta_in_r_next = meta_in_r;

        // default don't insert into reg
        pr_rank_in = rank_in_r;
        pr_meta_in = meta_in_r;
        pr_insert = 0;

        // default don't insert into skip lists
        for (p=0; p<NUM_SKIP_LISTS; p=p+1) begin
            sl_insert[p] = 0;
            sl_rank_in[p] = rank_in_r;
            sl_meta_in[p] = meta_in_r;
            sl_remove[p] = 0;
        end

        sl_min_rank_valid = final_deq_sel_valid_r;
        sl_min_rank = (sl_min_rank_valid) ? sl_rank_out[final_deq_sel_sl_r] : 0;

        rank_in_val = rank_in;
        insert_reg = (pr_max_valid && (rank_in_val < pr_max_rank)) || (sl_min_rank_valid && (rank_in_val < sl_min_rank) && ~pr_full) || (&sl_empty & ~pr_full);
        insert_unknown = (pr_num_entries != 0 && ~pr_max_valid) || (~&sl_empty & ~sl_min_rank_valid & ~pr_full);

        case (ifsm_state)
            IFSM_IDLE: begin
                if (insert) begin
                    rank_in_r_next = rank_in;
                    meta_in_r_next = {meta_in, tstamp_r};
                    // insert into the reg if (rank_in < pr_max_rank) or (rank_in < sl_min_rank) or (skip lists are all empty and pr is not full)
                    if (insert_reg) begin
                        // insert into reg
                        ifsm_state_next = INSERT_REG;
                    end
                    else if (insert_unknown) begin
                        // don't know where to insert into so take some more time to figure it out
                        ifsm_state_next = INSERT_SEARCH;
                    end
                    else begin
                        // insert into the skip list(s)
                        ifsm_state_next = INSERT_SL;
                    end
                end
            end

            INSERT_REG: begin
                busy = 1;
                // only insert into the pifo_reg_top if we didn't do so on the previous cycle
                if (~pr_insert_last_r) begin
                    pr_rank_in = rank_in_r;
                    pr_meta_in = meta_in_r;
                    pr_insert = 1;
                    ifsm_state_next = IFSM_IDLE;
                    if (pr_full & ~remove) begin
                        // kick the pr's max value to the skip lists
                        rank_in_r_next = pr_max_rank;
                        meta_in_r_next = pr_max_meta;
                        ifsm_state_next = INSERT_SL;
                    end
                end
            end

            INSERT_SEARCH: begin
                // don't know where to insert yet so keep looking
                busy = 1;
                ifsm_state_next = IFSM_IDLE; // default next state
                rank_in_val = rank_in_r; // used to compute insert_reg, TODO: is this going to work?
                if (insert_reg) begin
                    // insert into reg
                    ifsm_state_next = INSERT_REG;
                end
                else if (insert_unknown) begin
                    // don't know where to insert into so take some more time to figure it out
                    ifsm_state_next = INSERT_SEARCH;
                end
                else begin
                    // insert into the skip list(s)
                    ifsm_state_next = INSERT_SL;
                end
            end

            INSERT_SL: begin
                // continue attempting to perform the insertion until busy on the selected skip list is deasserted
                busy = 1;
                if (final_enq_sel_valid_r & ~sl_busy_out[final_enq_sel_sl_r] & ~sl_full_out[final_enq_sel_sl_r]) begin
                    sl_rank_in[final_enq_sel_sl_r] = rank_in_r;
                    sl_meta_in[final_enq_sel_sl_r] = meta_in_r;
                    sl_insert[final_enq_sel_sl_r] = 1;
                    ifsm_state_next = IFSM_IDLE;
                end
            end
        endcase


        /* pifo_reg replenishment logic:
         *   - If there is room in the pifo_reg 
         *       && it's not busy
         *       && the skip list output selection is valid
         *       && we are not directly inserting into the pifo_reg
         */
        direct_pr_insert = (ifsm_state == INSERT_REG);
        if (~pr_full & ~direct_pr_insert & ~pr_insert_last_r) begin // NOTE: removed ~remove check
            // we should replenish the reg if the skip list dequeue selection is valid
            if (final_deq_sel_valid_r & sl_valid_out[final_deq_sel_sl_r]) begin  // TODO: can we remove the dependency on final_deq_sel_valid_r_next?
                pr_insert = 1;
                pr_rank_in = sl_rank_out[final_deq_sel_sl_r];
                pr_meta_in = sl_meta_out[final_deq_sel_sl_r];
                sl_remove[final_deq_sel_sl_r] = 1;
            end
        end

        // keep track of whether or not we inserted into the pifo_reg_top on the last cycle
        pr_insert_last_r_next = pr_insert;

    end

    // ifsm state update 
    always @(posedge clk) begin
        if (rst) begin
            ifsm_state <= IFSM_IDLE;
            rank_in_r <= 0;
            meta_in_r <= 0;
            pr_insert_last_r <= 0;
        end
        else begin
            ifsm_state <= ifsm_state_next;
            rank_in_r <= rank_in_r_next;
            meta_in_r <= meta_in_r_next;
            pr_insert_last_r <= pr_insert_last_r_next;
        end
    end

    // increment timestamp counter 
    always @(posedge clk) begin
        if (rst) begin
            tstamp_r <= 0;
        end
        else begin
            tstamp_r <= tstamp_r + 1;
        end
    end

//integer idx;
//
//`ifdef COCOTB_SIM
///initial begin
//  $dumpfile ("pifo_top_waveform.vcd");
//  for (idx=0; idx<NUM_LEVELS+1; idx=idx+1) begin
//      $dumpvars (0, pifo_top, sl_valid_lvls[idx], valid_out_lvls[idx]);
//  end
//  #1 $display("Sim running...");
//end
//`endif

endmodule

