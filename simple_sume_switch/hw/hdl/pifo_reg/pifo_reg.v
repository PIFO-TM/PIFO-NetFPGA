module pifo_reg
#(
	parameter L2_MAX_SIZE = 3,
	parameter MAX_SIZE = 2**L2_MAX_SIZE,
    parameter RANK_WIDTH = 8,
	parameter META_WIDTH = 8,
	parameter ORDER = "MIN"
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
	reg valid[0:MAX_SIZE-1];
	reg [RANK_WIDTH-1:0] min_rank;
	reg [META_WIDTH-1:0] min_meta;
	reg [L2_MAX_SIZE-1:0] min_idx;
	reg min_valid;
	reg [RANK_WIDTH-1:0] max_rank;
	reg [META_WIDTH-1:0] max_meta;
	reg [L2_MAX_SIZE-1:0] max_idx;
	reg max_valid;
	wire [L2_MAX_SIZE-1:0] idx;
	reg [L2_MAX_SIZE-1:0] num_entries;
	reg insert_ltch;
	reg calc_min_max;
	integer i;
	
	// Find min/max
    always @(posedge clk or posedge rst)
	begin
	    if (rst)
		begin
			valid_out = 1'b0;
		    min_rank = {RANK_WIDTH{1'b0}}; 
		    min_meta = {META_WIDTH{1'b0}}; 
			max_rank = {RANK_WIDTH{1'b0}};
			max_meta = {META_WIDTH{1'b0}};
			min_idx = {L2_MAX_SIZE{1'b0}};
			max_idx = {L2_MAX_SIZE{1'b0}};
			min_valid = 1'b0;
			max_valid = 1'b0;
		end
		else
		begin
		    if (insert || remove)
			    valid_out = 1'b0;
				min_valid = 1'b0;
				max_valid = 1'b0;
				
		    if (calc_min_max)
	            for (i = 0; i < MAX_SIZE; i=i+1)
			        if (valid[i])
					begin
		                if ((rank[i] < min_rank) || (min_valid == 1'b0))
					    begin
			                min_rank = rank[i];
							min_meta = meta[i];
					    	min_idx = i;
							min_valid = 1'b1;
					    end
				
			            if ((rank[i] > max_rank) || (max_valid == 1'b0))
					    begin
			                max_rank = rank[i];
							max_meta = meta[i];
					    	max_idx = i;
							max_valid = 1'b1;
					    end
					    valid_out = 1'b1;
					end
		end
	end

	// Output min or max depending on ORDER param
	assign rank_out = (ORDER == "MIN") ? min_rank : max_rank;
	assign meta_out = (ORDER == "MIN") ? min_meta : max_meta;
	assign idx = (ORDER == "MIN") ? min_idx : max_idx;
	
    // Insert/Remove
    always @(posedge clk or posedge rst)
	begin
	    if (rst)
		begin
		    num_entries = 0;
			calc_min_max = 0;
			insert_ltch = 0;
		end
		else 
		begin
		    calc_min_max = 0;
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
			    calc_min_max = 1;
				insert_ltch = insert;
		    end
		    else if (insert | insert_ltch)
		    begin
			    // Insert new value at end of register
		        rank[num_entries] = rank_in;
			    meta[num_entries] = meta_in;
				valid[num_entries] = 1;
			    num_entries = num_entries + 1;
			    calc_min_max = 1;
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
