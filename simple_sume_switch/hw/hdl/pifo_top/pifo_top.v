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
    output reg [RANK_WIDTH-1:0]      rank_out,
    output reg [META_WIDTH-1:0]      meta_out,
    output reg                       valid_out,
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

    localparam TSTAMP_BITS = 32;
    localparam L2_SKIP_LIST_SIZE = L2_MAX_SIZE - log2(NUM_SKIP_LISTS) + 1;
//    localparam L2_SKIP_LIST_SIZE = L2_MAX_SIZE;

    /*------------ Wires and Regs ------------*/
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

    // insertion selection signals
    reg [(2**NUM_LEVELS)-1:0]    sl_valid_lvls        [NUM_LEVELS:0];
    reg [L2_MAX_SIZE-1:0]        sl_num_entries_lvls  [NUM_LEVELS:0] [(2**NUM_LEVELS)-1:0];
    reg [L2_NUM_SL_FLOOR:0]      skip_list_sel        [NUM_LEVELS:0] [(2**NUM_LEVELS)-1:0];
 
    reg                     final_sel_valid;
    reg [L2_NUM_SL_FLOOR:0] final_sel_skip_list;

    reg [TSTAMP_BITS-1:0] tstamp_r;

    // removal selection signals
    reg [(2**NUM_LEVELS)-1:0]  valid_out_lvls    [NUM_LEVELS:0];
    reg [RANK_WIDTH-1:0]       rank_out_lvls     [NUM_LEVELS:0] [(2**NUM_LEVELS)-1:0];
    reg [TSTAMP_BITS-1:0]      tstamp_out_lvls   [NUM_LEVELS:0] [(2**NUM_LEVELS)-1:0];
    reg [L2_NUM_SL_FLOOR:0]    deq_sl_sel        [NUM_LEVELS:0] [(2**NUM_LEVELS)-1:0];

    reg                       final_deq_sel_valid;
    reg [L2_NUM_SL_FLOOR:0]   final_deq_sel_sl;
    reg [NUM_SKIP_LISTS-1:0]  val_or_empty;
    reg                       deq_condition;

//    // output regs
//    reg valid_out_r, valid_out_r_next;
//    reg [RANK_WIDTH-1:0] rank_out_r, rank_out_r_next;
//    reg [META_WIDTH-1:0] meta_out_r, meta_out_r_next;

    /*------------ Modules and Logic ------------*/

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
 
        /* Select a skip list to insert into */
        for (j=0; j<NUM_LEVELS; j=j+1) begin  // loop over each level
            for (i=0; i<2**(NUM_LEVELS-j); i=i+2) begin // loop over each comparator in each level
                sl_valid_lvls[j+1][i/2] = sl_valid_lvls[j][i] | sl_valid_lvls[j][i+1];
                if (sl_valid_lvls[j][i] & sl_valid_lvls[j][i+1]) begin
                    // both skip lists are available
                    if (sl_num_entries_lvls[j][i] <= sl_num_entries_lvls[j][i+1]) begin
                        sl_num_entries_lvls[j+1][i/2] = sl_num_entries_lvls[j][i];
                        skip_list_sel[j+1][i/2] = skip_list_sel[j][i];
                    end
                    else begin
                        sl_num_entries_lvls[j+1][i/2] = sl_num_entries_lvls[j][i+1];
                        skip_list_sel[j+1][i/2] = skip_list_sel[j][i+1];
                    end
                end
                else if (sl_valid_lvls[j][i]) begin
                    sl_num_entries_lvls[j+1][i/2] = sl_num_entries_lvls[j][i];
                    skip_list_sel[j+1][i/2] = skip_list_sel[j][i]; 
                end
                else if (sl_valid_lvls[j][i+1]) begin
                    sl_num_entries_lvls[j+1][i/2] = sl_num_entries_lvls[j][i+1];
                    skip_list_sel[j+1][i/2] = skip_list_sel[j][i+1]; 
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
                sl_insert[p] = insert;
                sl_rank_in[p] = rank_in;
                sl_meta_in[p] = {meta_in, tstamp_r};
            end
            else begin
                sl_insert[p] = 0;
                sl_rank_in[p] = 0;
                sl_meta_in[p] = 0;
            end
        end
    end

    // generate the busy and fill signals 
    always @(*) begin
        busy = ~final_sel_valid;
        full = &sl_full_out;
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
            val_or_empty[s] = sl_valid_out[s] | (sl_num_entries[s] == 0);
        end

        // initialize extra entries with valid = 0 so they are never chosen
        for (u=NUM_SKIP_LISTS; u<2**NUM_LEVELS; u=u+1) begin
            valid_out_lvls[0][u] = 0;
            rank_out_lvls[0][u] = -1;
            tstamp_out_lvls[0][u] = -1;
            deq_sl_sel[0][u] = u;
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
                        deq_sl_sel[r+1][q/2] = deq_sl_sel[r][q];
                    end
                    else if (rank_out_lvls[r][q] > rank_out_lvls[r][q+1]) begin
                        rank_out_lvls[r+1][q/2] = rank_out_lvls[r][q+1];
                        tstamp_out_lvls[r+1][q/2] = tstamp_out_lvls[r][q+1];
                        deq_sl_sel[r+1][q/2] = deq_sl_sel[r][q+1];
                    end
                    // next check timestamps
                    else if (tstamp_out_lvls[r][q] < tstamp_out_lvls[r][q+1]) begin
                        rank_out_lvls[r+1][q/2] = rank_out_lvls[r][q];
                        tstamp_out_lvls[r+1][q/2] = tstamp_out_lvls[r][q];
                        deq_sl_sel[r+1][q/2] = deq_sl_sel[r][q];
                    end
                    else begin
                        rank_out_lvls[r+1][q/2] = rank_out_lvls[r][q+1];
                        tstamp_out_lvls[r+1][q/2] = tstamp_out_lvls[r][q+1];
                        deq_sl_sel[r+1][q/2] = deq_sl_sel[r][q+1];
                    end
                end
                else if (valid_out_lvls[r][q]) begin
                    rank_out_lvls[r+1][q/2] = rank_out_lvls[r][q];
                    tstamp_out_lvls[r+1][q/2] = tstamp_out_lvls[r][q];
                    deq_sl_sel[r+1][q/2] = deq_sl_sel[r][q];
                end
                else if (valid_out_lvls[r][q+1]) begin
                    rank_out_lvls[r+1][q/2] = rank_out_lvls[r][q+1];
                    tstamp_out_lvls[r+1][q/2] = tstamp_out_lvls[r][q+1];
                    deq_sl_sel[r+1][q/2] = deq_sl_sel[r][q+1];
                end
                else begin
                    // neither skip list is available
                    rank_out_lvls[r+1][q/2] = -1;
                    tstamp_out_lvls[r+1][q/2] = -1;
                    deq_sl_sel[r+1][q/2] = -1;
                end
            end
        end

        deq_condition = &val_or_empty;
        // the output is valid if the selected skip list is asserting valid_out
        //    and all skip lists are either empty or asserting valid_out
        final_deq_sel_valid = valid_out_lvls[NUM_LEVELS][0] & deq_condition;
        final_deq_sel_sl = deq_sl_sel[NUM_LEVELS][0];

    end

    /* Removal logic: register the outputs and submit removal request */
    integer v;
    always @(*) begin
        valid_out = final_deq_sel_valid; //valid_out_r;
        rank_out = 0; //rank_out_r;
        meta_out = 0; //meta_out_r;

//        valid_out_r_next = 0;
//        rank_out_r_next = 0;
//        meta_out_r_next = 0;

        for (v=0; v<NUM_SKIP_LISTS; v=v+1) begin
            if (final_deq_sel_valid && v == final_deq_sel_sl) begin
                sl_remove[v] = remove;

                rank_out = sl_rank_out[v];
                meta_out = sl_meta_out[v][META_WIDTH+TSTAMP_BITS-1 : TSTAMP_BITS];

//                valid_out_r_next = 1;
//                rank_out_r_next = sl_rank_out[v];
//                meta_out_r_next = sl_meta_out[v][META_WIDTH+TSTAMP_BITS-1 : TSTAMP_BITS];
            end
            else begin
                sl_remove[v] = 0;
            end
        end
    end

//    always @(posedge clk) begin
//        if (rst) begin
//            valid_out_r <= 0;
//            rank_out_r <= 0;
//            meta_out_r <= 0;
//        end
//        else begin
//            valid_out_r <= valid_out_r_next;
//            rank_out_r <= rank_out_r_next; 
//            meta_out_r <= meta_out_r_next;
//        end
//    end

//wire [(2**NUM_LEVELS)-1:0] valid_out_lvls_0 = valid_out_lvls[0];
//wire [(2**NUM_LEVELS)-1:0] valid_out_lvls_1 = valid_out_lvls[1];
//wire [(2**NUM_LEVELS)-1:0] valid_out_lvls_2 = valid_out_lvls[2];
//
//wire [RANK_WIDTH-1:0] rank_out_lvls_0_0 = rank_out_lvls[0][0];
//wire [RANK_WIDTH-1:0] rank_out_lvls_0_1 = rank_out_lvls[0][1];
//wire [RANK_WIDTH-1:0] rank_out_lvls_0_2 = rank_out_lvls[0][2];
//wire [RANK_WIDTH-1:0] rank_out_lvls_0_3 = rank_out_lvls[0][3];
//wire [RANK_WIDTH-1:0] rank_out_lvls_1_0 = rank_out_lvls[1][0];
//wire [RANK_WIDTH-1:0] rank_out_lvls_1_1 = rank_out_lvls[1][1];
//wire [RANK_WIDTH-1:0] rank_out_lvls_2_0 = rank_out_lvls[2][0];
//
//wire [L2_NUM_SL_FLOOR:0] deq_sl_sel_0_0 = deq_sl_sel[0][0];
//wire [L2_NUM_SL_FLOOR:0] deq_sl_sel_0_1 = deq_sl_sel[0][1];
//wire [L2_NUM_SL_FLOOR:0] deq_sl_sel_0_2 = deq_sl_sel[0][2];
//wire [L2_NUM_SL_FLOOR:0] deq_sl_sel_0_3 = deq_sl_sel[0][3];
//wire [L2_NUM_SL_FLOOR:0] deq_sl_sel_1_0 = deq_sl_sel[1][0];
//wire [L2_NUM_SL_FLOOR:0] deq_sl_sel_1_1 = deq_sl_sel[1][1];
//wire [L2_NUM_SL_FLOOR:0] deq_sl_sel_2_0 = deq_sl_sel[2][0];
//
//wire [L2_MAX_SIZE-1:0] sl_num_entries_lvls_0_0 = sl_num_entries_lvls[0][0];
//wire [L2_MAX_SIZE-1:0] sl_num_entries_lvls_0_1 = sl_num_entries_lvls[0][1];
//wire [L2_MAX_SIZE-1:0] sl_num_entries_lvls_0_2 = sl_num_entries_lvls[0][2];
//wire [L2_MAX_SIZE-1:0] sl_num_entries_lvls_0_3 = sl_num_entries_lvls[0][3];
//wire [L2_MAX_SIZE-1:0] sl_num_entries_lvls_1_0 = sl_num_entries_lvls[1][0];
//wire [L2_MAX_SIZE-1:0] sl_num_entries_lvls_1_1 = sl_num_entries_lvls[1][1];
//wire [L2_MAX_SIZE-1:0] sl_num_entries_lvls_2_0 = sl_num_entries_lvls[2][0];
//
//wire [L2_NUM_SL_FLOOR:0] skip_list_sel_0_0 = skip_list_sel[0][0];
//wire [L2_NUM_SL_FLOOR:0] skip_list_sel_0_1 = skip_list_sel[0][1];
//wire [L2_NUM_SL_FLOOR:0] skip_list_sel_0_2 = skip_list_sel[0][2];
//wire [L2_NUM_SL_FLOOR:0] skip_list_sel_0_3 = skip_list_sel[0][3];
//wire [L2_NUM_SL_FLOOR:0] skip_list_sel_1_0 = skip_list_sel[1][0];
//wire [L2_NUM_SL_FLOOR:0] skip_list_sel_1_1 = skip_list_sel[1][1];
//wire [L2_NUM_SL_FLOOR:0] skip_list_sel_2_0 = skip_list_sel[2][0];

wire [RANK_WIDTH-1:0]               sl_rank_in_0  =  sl_rank_in[0];
wire [META_WIDTH+TSTAMP_BITS-1:0]   sl_meta_in_0  =  sl_meta_in[0];
wire [RANK_WIDTH-1:0]               sl_rank_out_0 =  sl_rank_out[0];
wire [META_WIDTH+TSTAMP_BITS-1:0]   sl_meta_out_0 =  sl_meta_out[0];

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

