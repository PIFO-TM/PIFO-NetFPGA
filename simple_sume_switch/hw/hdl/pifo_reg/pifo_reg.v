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
    reg [L2_MAX_SIZE-1:0] current_min_idx [0:MAX_SIZE];
    reg [RANK_WIDTH-1:0] current_min_rank [0:MAX_SIZE];
    reg valid_out_next;

    integer i;

    always @(*) begin
        // default values
        valid_out_next = valid_out;
        min_idx_next = min_idx;
        min_rank_next = min_rank;
        min_meta_next = min_meta;
        for(i=0; i<=MAX_SIZE; i=i+1) begin
            current_min_rank[i] = ~0;
            current_min_idx[i] = ~0;
        end

        if (insert || remove) begin
            valid_out_next = 0;
        end

        if (calc_min) begin
            for (i = 0; i < MAX_SIZE; i=i+1) begin
                if (valid[i] && (rank[i] < current_min_rank[i])) begin
                    current_min_rank[i+1] = rank[i];
                    current_min_idx[i+1] = i;
                end
                else begin
                    current_min_rank[i+1] = current_min_rank[i];
                    current_min_idx[i+1] = current_min_idx[i];
                end

                if (valid[i]) begin
                    valid_out_next = 1;
                end
            end
 
            // update min 
            min_idx_next = current_min_idx[MAX_SIZE];
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

    initial begin
      $dumpfile ("pifo_reg_waveform.vcd");
      $dumpvars (0,pifo_reg);
      #1 $display("Sim running...");
    end	
endmodule
