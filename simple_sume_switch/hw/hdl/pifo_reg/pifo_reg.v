`timescale 1ns/1ps

module pifo_reg
#(
	parameter L2_REG_WIDTH = 2,
    parameter RANK_WIDTH = 8,
	parameter META_WIDTH = 8
)
(
    input rst,
    input clk,
    input insert,
	input [RANK_WIDTH-1:0] rank_in,
	input [META_WIDTH-1:0] meta_in,
    input remove,
	output reg [RANK_WIDTH-1:0] rank_out,
	output [META_WIDTH-1:0] meta_out,
	output reg valid_out,
	output [RANK_WIDTH-1:0] max_rank_out,
	output [META_WIDTH-1:0] max_meta_out,
	output max_valid_out,
	output reg [L2_REG_WIDTH:0] num_entries,
	output reg empty,
	output reg full
);

	localparam REG_WIDTH = 2**L2_REG_WIDTH;
	localparam IDX_WIDTH = L2_REG_WIDTH;
	localparam COMP_LVLS = L2_REG_WIDTH+1;

    reg [RANK_WIDTH-1:0] rank[REG_WIDTH-1:0];
	reg [META_WIDTH-1:0] meta[REG_WIDTH-1:0];
	reg valid[REG_WIDTH-1:0];
	wire [REG_WIDTH*RANK_WIDTH-1:0] min_data[0:COMP_LVLS-1];
	wire [REG_WIDTH*IDX_WIDTH-1:0] min_idx[0:COMP_LVLS-1];
	wire [REG_WIDTH-1:0] min_vld[0:COMP_LVLS-1];
	wire [REG_WIDTH*RANK_WIDTH-1:0] max_data[0:COMP_LVLS-1];
	wire [REG_WIDTH*IDX_WIDTH-1:0] max_idx[0:COMP_LVLS-1];
	wire [REG_WIDTH-1:0] max_vld[0:COMP_LVLS-1];
	reg  [IDX_WIDTH-1:0] idx;
	wire [IDX_WIDTH-1:0] max_idx_out;
	integer k;
	
    // Insert/Remove
    always @(posedge clk)
	begin
	    if (rst)
		begin
		    num_entries <= 0;
			empty <= 1'b0;
			full <= 1'b0;
			for (k = 0; k < REG_WIDTH; k=k+1)
				valid[k] <= 1'b0;
		end
		else 
		begin
			
		    if (remove == 1'b1 && num_entries > 0)
		    begin
			    if (insert == 1'b0)
				begin
			        // Close gap 
				    for (k = 0; k < REG_WIDTH; k=k+1)
				        if (k > idx)
					    begin
				            rank[k-1] <= rank[k];
				            meta[k-1] <= meta[k];
						    valid[k-1] <= valid[k];
					    end
				    valid[num_entries-1] <= 0;
				    if (num_entries == 1)
				        empty <= 1'b1;
				    full <= 1'b0;
				    num_entries <= num_entries - 1;
				end
				else  // Simultaneous insert/remove
				begin
					// Replace min value that is being removed
					rank[idx] <= rank_in;
					meta[idx] <= meta_in;
				end
		    end
		    else if (insert == 1'b1)
		    begin
			    // Insert new value at end of register
				if (num_entries < REG_WIDTH)
				begin
		            rank[num_entries] <= rank_in;
			        meta[num_entries] <= meta_in;
				    valid[num_entries] <= 1'b1;
					if (num_entries == REG_WIDTH-1)
					    full <= 1'b1;
					else
					    full <= 1'b0;
			        num_entries <= num_entries + 1;
				end
				else
				begin
				    // If new value is smaller than max
                    if (rank_in < max_rank_out)
					begin
						// Replace largest value
						rank[max_idx_out] <= rank_in;
						meta[max_idx_out] <= meta_in;
					end
					full <= 1'b1;
				end
				empty <= 1'b0;
			end
		end
	end

	// Connect rank array to first level of min/max trees
	genvar i;
    generate
        for (i = 0; i < REG_WIDTH; i = i+1)
		begin : conn_in
            assign min_data[0][(i+1)*RANK_WIDTH-1 -: RANK_WIDTH] = rank[i];
	        assign min_idx[0][(i+1)*IDX_WIDTH-1 -: IDX_WIDTH] = i;
	        assign min_vld[0][i] = valid[i];
	        assign max_data[0][(i+1)*RANK_WIDTH-1 -: RANK_WIDTH] = rank[i];
	        assign max_idx[0][(i+1)*IDX_WIDTH-1 -: IDX_WIDTH] = i;
	        assign max_vld[0][i] = valid[i];
		end	
	endgenerate
	
	// min/max trees
	genvar j;
    generate
        for (j = 0; j < COMP_LVLS-1; j = j+1) 
		begin : min_max
		    min
            #(
	            .REG_WIDTH(REG_WIDTH/2**j),
			    .IDX_WIDTH(IDX_WIDTH),
                .DATA_WIDTH(RANK_WIDTH)
            )
			min_i
            (
	            .data_in (min_data[j][REG_WIDTH*RANK_WIDTH/2**j-1:0]),
	            .idx_in  (min_idx[j][REG_WIDTH*IDX_WIDTH/2**j-1:0]),
	            .vld_in  (min_vld[j][REG_WIDTH/2**j-1:0]),
	            .min_out (min_data[j+1][REG_WIDTH*RANK_WIDTH/2**(j+1)-1:0]),
	            .idx_out (min_idx[j+1][REG_WIDTH*IDX_WIDTH/2**(j+1)-1:0]),
	            .vld_out (min_vld[j+1][REG_WIDTH/2**(j+1)-1:0])
            );

			max
            #(
	            .REG_WIDTH(REG_WIDTH/2**j),
			    .IDX_WIDTH(IDX_WIDTH),
                .DATA_WIDTH(RANK_WIDTH)
            )
			max_i
            (
	            .data_in (max_data[j][REG_WIDTH*RANK_WIDTH/2**j-1:0]),
	            .idx_in  (max_idx[j][REG_WIDTH*IDX_WIDTH/2**j-1:0]),
	            .vld_in  (max_vld[j][REG_WIDTH/2**j-1:0]),
	            .max_out (max_data[j+1][REG_WIDTH*RANK_WIDTH/2**(j+1)-1:0]),
	            .idx_out (max_idx[j+1][REG_WIDTH*IDX_WIDTH/2**(j+1)-1:0]),
	            .vld_out (max_vld[j+1][REG_WIDTH/2**(j+1)-1:0])
            );

        end
    endgenerate
 
	// Output min and max
	//assign idx = min_idx[COMP_LVLS-1][IDX_WIDTH-1:0];
	assign max_idx_out = max_idx[COMP_LVLS-1][IDX_WIDTH-1:0];
    always @(posedge clk)
	begin
	    if (rst)
		begin
			valid_out <= 1'b0;
			//max_valid_out <= 1'b0;
		end
		else
		begin
	        //max_rank_out <= max_data[COMP_LVLS-1][RANK_WIDTH-1:0];
	        //max_meta_out <= meta[max_idx_out];
	        //max_valid_out <= max_vld[COMP_LVLS-1];
	        rank_out <= min_data[COMP_LVLS-1][RANK_WIDTH-1:0];
	        idx <= min_idx[COMP_LVLS-1][IDX_WIDTH-1:0];
	        //meta_out <= meta[idx];
			if (insert == 1'b1 || remove == 1'b1)
			    valid_out <= 1'b0;
			else
	            valid_out <= min_vld[COMP_LVLS-1];
        end
	end
	assign meta_out = meta[idx];
	assign max_rank_out = max_data[COMP_LVLS-1][RANK_WIDTH-1:0];
	assign max_meta_out = meta[max_idx_out];
	assign max_valid_out = max_vld[COMP_LVLS-1];
	//assign rank_out = min_data[COMP_LVLS-1][RANK_WIDTH-1:0];
	//assign meta_out = meta[idx];
	//assign valid_out = min_vld[COMP_LVLS-1];
	
endmodule