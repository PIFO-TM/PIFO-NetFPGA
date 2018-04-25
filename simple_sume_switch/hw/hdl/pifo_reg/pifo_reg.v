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
	output [RANK_WIDTH-1:0] rank_out,
	output [META_WIDTH-1:0] meta_out,
	output reg valid_out,
	output [RANK_WIDTH-1:0] max_rank_out,
	output [META_WIDTH-1:0] max_meta_out,
	output reg max_valid_out,
	output reg [L2_REG_WIDTH:0] num_entries,
	output reg empty,
	output reg full
);

	localparam REG_WIDTH = 2**L2_REG_WIDTH;
	localparam COMP_LVLS = L2_REG_WIDTH+1;

    reg [RANK_WIDTH-1:0] rank[0:REG_WIDTH-1];
	reg [META_WIDTH-1:0] meta[0:REG_WIDTH-1];
	reg valid[0:REG_WIDTH-1];
	reg [RANK_WIDTH-1:0] min_rank[0:COMP_LVLS-1][0:REG_WIDTH-1];
	reg [META_WIDTH-1:0] min_meta[0:COMP_LVLS-1][0:REG_WIDTH-1];
	reg [L2_REG_WIDTH-1:0] min_idx[0:COMP_LVLS-1][0:REG_WIDTH-1];
	reg [RANK_WIDTH-1:0] max_rank[0:COMP_LVLS-1][0:REG_WIDTH-1];
	reg [META_WIDTH-1:0] max_meta[0:COMP_LVLS-1][0:REG_WIDTH-1];
	reg [L2_REG_WIDTH-1:0] max_idx[0:COMP_LVLS-1][0:REG_WIDTH-1];
	reg mvalid[0:COMP_LVLS-1][0:REG_WIDTH-1];
	wire [L2_REG_WIDTH-1:0] idx;
	reg insert_ltch;
	reg calc_min_max;
	integer i, j;
	
	always @*
	begin
		for (j = 0; j < REG_WIDTH; j=j+1)
	    begin
	        min_rank[0][j] <= rank[j];
			min_meta[0][j] <= meta[j];
			min_idx[0][j] <= j;
	        max_rank[0][j] <= rank[j];
			max_meta[0][j] <= meta[j];
			max_idx[0][j] <= j;
	        mvalid[0][j] <= valid[j];
	    end

		for (i = 0; i < COMP_LVLS; i=i+1)
	        for (j = 0; j < REG_WIDTH/2**i; j=j+2) 
			begin
                if (((min_rank[i][j] <= min_rank[i][j+1]) && (mvalid[i][j] == 1'b1) && (mvalid[i][j+1] == 1'b1)) ||
				    ((mvalid[i][j] == 1'b1) && (mvalid[i][j+1] !== 1'b1)))
			    begin
		            min_rank[i+1][j/2] <= min_rank[i][j];
				    min_meta[i+1][j/2] <= min_meta[i][j];
		    	    min_idx[i+1][j/2]  <= min_idx[i][j];
				end
			    else if (((min_rank[i][j] > min_rank[i][j+1]) && (mvalid[i][j] == 1'b1) && (mvalid[i][j+1] == 1'b1)) ||
					     ((mvalid[i][j] !== 1'b1) && (mvalid[i][j+1] == 1'b1)))
				begin
	                min_rank[i+1][j/2] <= min_rank[i][j+1];
				    min_meta[i+1][j/2] <= min_meta[i][j+1];
		    	    min_idx[i+1][j/2]  <= min_idx[i][j+1];						
			    end
				
	            if (((max_rank[i][j] > max_rank[i][j+1]) && (mvalid[i][j] == 1'b1) && (mvalid[i][j+1] == 1'b1)) ||
				    ((mvalid[i][j] == 1'b1) && (mvalid[i][j+1] !== 1'b1)))
		        begin
	                max_rank[i+1][j/2] <= max_rank[i][j];
				    max_meta[i+1][j/2] <= max_meta[i][j];
		    	    max_idx[i+1][j/2]  <= max_idx[i][j];
				end
			    else if (((max_rank[i][j] <= max_rank[i][j+1]) && (mvalid[i][j] == 1'b1) && (mvalid[i][j+1] == 1'b1)) ||
		   			     ((mvalid[i][j] !== 1'b1) && (mvalid[i][j+1] == 1'b1)))
				begin
	                max_rank[i+1][j/2] <= max_rank[i][j+1];
				    max_meta[i+1][j/2] <= max_meta[i][j+1];
		    	    max_idx[i+1][j/2]  <= max_idx[i][j+1];						
			    end
				
				if ((mvalid[i][j] == 1'b1) || (mvalid[i][j+1] == 1'b1))
				    mvalid[i+1][j/2] <= 1'b1;
                else
				    mvalid[i+1][j/2] <= 1'b0;
			end
	end

	// Output min and max
	assign rank_out = min_rank[COMP_LVLS-1][0];
	assign meta_out = min_meta[COMP_LVLS-1][0];
	assign idx = min_idx[COMP_LVLS-1][0];
	assign max_rank_out = max_rank[COMP_LVLS-1][0];
	assign max_meta_out = max_meta[COMP_LVLS-1][0];
	
	// Min/max valig generation
    always @(posedge clk)
	begin
	    if (rst)
		begin
			valid_out <= 1'b0;
			max_valid_out <= 1'b0;
		end
		else
		begin
		    if (insert == 1'b1 || remove == 1'b1)
			begin
			    valid_out <= 1'b0;
				max_valid_out <= 1'b0;
			end

		    if (calc_min_max == 1'b1)
				if (num_entries > 0)
				begin
			        valid_out <= 1'b1;
					max_valid_out <= 1'b1;
				end
	    end
	end
		
    // Insert/Remove
    always @(posedge clk)
	begin
	    if (rst)
		begin
		    num_entries <= 0;
			calc_min_max <= 0;
			insert_ltch <= 0;
			empty <= 1'b0;
			full <= 1'b0;
		end
		else 
		begin
		    calc_min_max <= 0;
			
		    if (remove == 1'b1 && num_entries > 0)
		    begin
			    // Close gap 
				for (i = 0; i < REG_WIDTH; i=i+1)
				    if (i > idx)
					begin
				        rank[i-1] <= rank[i];
				        meta[i-1] <= meta[i];
						valid[i-1] <= valid[i];
					end
				valid[num_entries-1] <= 0;
				if (num_entries == 1)
				    empty <= 1'b1;
				full <= (insert == 0) ? 1'b0 : full;
				num_entries <= num_entries - 1;
			    calc_min_max <= 1;
				insert_ltch <= insert;
		    end
		    else if (insert == 1'b1 || insert_ltch == 1'b1)
		    begin
			    // Insert new value at end of register
				if (num_entries < REG_WIDTH)
				begin
		            rank[num_entries] <= rank_in;
			        meta[num_entries] <= meta_in;
				    valid[num_entries] <= 1;
					if (num_entries == REG_WIDTH-1)
					    full <= 1'b1;
					else
					    full <= 1'b0;
			        num_entries <= num_entries + 1;
				end
				else
				begin
				    // If new value is smaller than max
                    if (rank_in < max_rank[COMP_LVLS-1][0])
					begin
						// Replace largest value
						rank[max_idx[COMP_LVLS-1][0]] <= rank_in;
						meta[max_idx[COMP_LVLS-1][0]] <= meta_in;
					end
					full <= 1'b1;
				end
				empty <= 1'b0;
			    calc_min_max <= 1;
				insert_ltch <= 0;
			end
		end
	end
	
endmodule
