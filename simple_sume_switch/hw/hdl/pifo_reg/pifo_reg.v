
module min_comparator
#(
    parameter VAL_WIDTH = 8,
    parameter INDEX_WIDTH = 8
)
(
    input wire [VAL_WIDTH-1:0]        X1,
    input wire [INDEX_WIDTH-1:0]      indexX1,
    input wire [VAL_WIDTH-1:0]        X2,
    input wire [INDEX_WIDTH-1:0]      indexX2,
    output reg [VAL_WIDTH-1:0]        Y,
    output reg [INDEX_WIDTH-1:0]      indexY
);

    always @(*) begin
        if (X1 < X2) begin
            Y = X1;
            indexY = indexX1;
        end
        else begin
            Y = X2;
            indexY = indexX2;
        end
    end
endmodule

module pifo_reg
#(
	parameter L2_MAX_SIZE = 3,
	parameter MAX_SIZE = 2**L2_MAX_SIZE,
    parameter RANK_WIDTH = 8,
	parameter META_WIDTH = 8
)
(
    input rst,
    input clk,
    input insert,
    input remove,
    input [RANK_WIDTH-1:0] rank_in,
    input [META_WIDTH-1:0] meta_in,
    output [RANK_WIDTH-1:0] rank_out,
    output [META_WIDTH-1:0] meta_out,
    output reg valid_out
);

    reg [RANK_WIDTH-1:0] rank[0:MAX_SIZE-1];
    reg [META_WIDTH-1:0] meta[0:MAX_SIZE-1];
    reg [MAX_SIZE-1:0] valid;
    reg [RANK_WIDTH-1:0] min_rank, min_rank_next;
    reg [META_WIDTH-1:0] min_meta, min_meta_next;
    reg [L2_MAX_SIZE-1:0] min_idx, min_idx_next;
    wire [L2_MAX_SIZE-1:0] idx;
    reg [L2_MAX_SIZE-1:0] num_entries;
    reg insert_ltch;
    reg calc_min;
    reg valid_out_next;

    wire [L2_MAX_SIZE-1:0] min_idx_vals [L2_MAX_SIZE:0] [2**(L2_MAX_SIZE)-1:0];
    wire [RANK_WIDTH-1:0] min_rank_vals [L2_MAX_SIZE:0] [2**(L2_MAX_SIZE)-1:0];

    genvar j, k;
    generate
    // generate each level of comparators
    for (j=0; j < L2_MAX_SIZE; j=j+1) begin: comps_all_levels
        for (k=0; k < 2**(L2_MAX_SIZE-j); k=k+2) begin: comps_one_level
            if (j == 0) begin: level0
                min_comparator #(.VAL_WIDTH(RANK_WIDTH), .INDEX_WIDTH(L2_MAX_SIZE)) 
                    cmp (rank[k],
                         k,
                         rank[k+1],
                         k+1,
                         min_rank_vals[j+1][k/2],
                         min_idx_vals[j+1][k/2]);
            end
            else begin: level1_plus 
                min_comparator #(.VAL_WIDTH(RANK_WIDTH), .INDEX_WIDTH(L2_MAX_SIZE)) 
                    cmp (min_rank_vals[j][k],
                         min_idx_vals[j][k],
                         min_rank_vals[j][k+1],
                         min_idx_vals[j][k+1],
                         min_rank_vals[j+1][k/2],
                         min_idx_vals[j+1][k/2]);
            end
        end
    end
    endgenerate

    integer i;
    always @(*) begin
        // default values
        valid_out_next = valid_out;
        min_idx_next = min_idx;
        min_rank_next = min_rank;
        min_meta_next = min_meta;

        if (insert || remove) begin
            valid_out_next = 0;
        end

        if (calc_min) begin
            valid_out_next = |valid;
 
            // update min 
            min_idx_next = min_idx_vals[L2_MAX_SIZE][0];
            min_rank_next = rank[min_idx_next];
            min_meta_next = meta[min_idx_next];
        end
    end // always @ (*)
 
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            valid_out <= 0;
            min_idx <= 0;
            min_rank <= 0;
            min_meta <= 0;
        end
        else begin
            valid_out <= valid_out_next;
            min_idx <= min_idx_next;
            min_rank <= min_rank_next;
            min_meta <= min_meta_next;
        end
    end

    // Output min or max depending on ORDER param
    assign rank_out = min_rank;
    assign meta_out = min_meta;
    assign idx = min_idx;

    // Insert/Remove
    always @(posedge clk or posedge rst)
    begin
        if (rst)
        begin
            num_entries = 0;
            calc_min = 0;
            insert_ltch = 0;
            for (i = 0; i < MAX_SIZE; i=i+1) begin
                valid[i] = 0;
                rank[i] = ~0; // largest possible value
                meta[i] = 0;
            end
        end
        else
        begin
            calc_min = 0;
            if (remove)
            begin
                // Close gap
                for (i = 0; i < MAX_SIZE; i=i+1)
                    if (i > idx)
                        begin
                            rank[i-1] = rank[i];
                            meta[i-1] = meta[i];
                        end
                valid[num_entries-1] = 0;
                num_entries = num_entries - 1;
                calc_min = 1;
                insert_ltch = insert;
            end
            else if (insert | insert_ltch)
            begin
                // Insert new value at end of register
                rank[num_entries] = rank_in;
                meta[num_entries] = meta_in;
                valid[num_entries] = 1;
                num_entries = num_entries + 1;
                calc_min = 1;
                insert_ltch = 0;
            end
        end
    end

//    initial begin
//      $dumpfile ("pifo_reg_waveform.vcd");
//      $dumpvars (0,pifo_reg);
//      #1 $display("Sim running...");
//    end	
endmodule
