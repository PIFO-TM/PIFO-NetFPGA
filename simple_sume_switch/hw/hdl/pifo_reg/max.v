`timescale 1ns/1ps

module max
#(
	parameter REG_WIDTH = 4,
	parameter IDX_WIDTH = 2,
    parameter DATA_WIDTH = 8
)
(
	input [REG_WIDTH*DATA_WIDTH-1:0] data_in,
	input [REG_WIDTH*IDX_WIDTH-1:0] idx_in,
	input [REG_WIDTH-1:0] vld_in,
	output reg [(REG_WIDTH/2)*DATA_WIDTH-1:0] max_out,
	output reg [(REG_WIDTH/2)*IDX_WIDTH-1:0] idx_out,
	output reg [REG_WIDTH/2-1:0] vld_out
);

	integer i;
	
	always @*
	begin
	    for (i = 0; i < REG_WIDTH; i=i+2) 
		begin			
            if ((vld_in[i] == 1'b1) && (vld_in[i+1] == 1'b1))
	            if (data_in[(i+1)*DATA_WIDTH-1 -: DATA_WIDTH] > data_in[(i+2)*DATA_WIDTH-1 -: DATA_WIDTH])
		        begin
	                max_out[((i/2)+1)*DATA_WIDTH-1 -: DATA_WIDTH] <= data_in[(i+1)*DATA_WIDTH-1 -: DATA_WIDTH];
			        idx_out[((i/2)+1)*IDX_WIDTH-1 -: IDX_WIDTH]   <= idx_in[(i+1)*IDX_WIDTH-1 -: IDX_WIDTH];
			    end
		        else
			    begin
	                max_out[((i/2)+1)*DATA_WIDTH-1 -: DATA_WIDTH] <= data_in[(i+2)*DATA_WIDTH-1 -: DATA_WIDTH];
			        idx_out[((i/2)+1)*IDX_WIDTH-1 -: IDX_WIDTH]   <= idx_in[(i+2)*IDX_WIDTH-1 -: IDX_WIDTH];						
		        end	
			else if (vld_in[i] == 1'b1)
			begin
	            max_out[((i/2)+1)*DATA_WIDTH-1 -: DATA_WIDTH] <= data_in[(i+1)*DATA_WIDTH-1 -: DATA_WIDTH];
			    idx_out[((i/2)+1)*IDX_WIDTH-1 -: IDX_WIDTH]   <= idx_in[(i+1)*IDX_WIDTH-1 -: IDX_WIDTH];
			end
			else
			begin
	            max_out[((i/2)+1)*DATA_WIDTH-1 -: DATA_WIDTH] <= data_in[(i+2)*DATA_WIDTH-1 -: DATA_WIDTH];
			    idx_out[((i/2)+1)*IDX_WIDTH-1 -: IDX_WIDTH]   <= idx_in[(i+2)*IDX_WIDTH-1 -: IDX_WIDTH];						
			end
            vld_out[i/2] <= vld_in[i] | vld_in[i+1];
		end
	end
endmodule