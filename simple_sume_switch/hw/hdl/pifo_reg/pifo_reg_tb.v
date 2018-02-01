module pifo_reg_tb();

parameter RST_WIDTH = 20;
parameter CLK_PERIOD = 10;
parameter L2_MAX_SIZE = 3;
parameter RANK_WIDTH = 8;
parameter META_WIDTH = 8;
parameter ORDER = "MIN";

reg rst;
reg clk;
reg insert;
reg remove;
reg [RANK_WIDTH-1:0] rank_in;
reg [META_WIDTH-1:0] meta_in;
wire [RANK_WIDTH-1:0] rank_out;
wire [META_WIDTH-1:0] meta_out;
wire valid_out;

    initial
	    begin
		    rst = 1;
			#RST_WIDTH rst = 0;
		end

    initial
	    begin
		    clk = 1;
			forever #(CLK_PERIOD/2) clk = ~clk;
		end
		
	initial
	    begin
		    #1
		    insert = 0;
			remove = 0;
		    #50 insert = 1;
			    rank_in = 5;
				meta_in = 8'h10;
			#10 insert = 0;
		
            #20 remove = 1;
            #10 remove = 0;	

		    #10 insert = 1;
			    rank_in = 8;
				meta_in = 8'h20;
			#10 insert = 0;
			
			#10 insert = 1;
			    rank_in = 87;
				meta_in = 8'h30;
			#10 insert = 0;

		    #10 insert = 1;
			    rank_in = 54;
				meta_in = 8'h40;
			#10 insert = 0;
			
		    #10 insert = 1;
			    rank_in = 76;
				meta_in = 8'h50;
			#10 insert = 0;
			
		    #10 insert = 1;
			    rank_in = 47;
				meta_in = 8'h60;
			#10 insert = 0;
			
		    #10 insert = 1;
			    rank_in = 68;
				meta_in = 8'h70;
			#10 insert = 0;
			
		    #10 insert = 1;
			    rank_in = 29;
				meta_in = 8'h80;
			#10 insert = 0;
			
		    #10 insert = 1;
			    rank_in = 98;
				meta_in = 8'h90;
				remove = 1;
			#10 insert = 0;
			    remove = 0;

			#20 remove = 1;
            #10 remove = 0;	
            #20 remove = 1;
            #10 remove = 0;	
            #20 remove = 1;
            #10 remove = 0;	
            #20 remove = 1;
            #10 remove = 0;	
            #20 remove = 1;
            #10 remove = 0;	
            #20 remove = 1;
            #10 remove = 0;	
            #20 remove = 1;
            #10 remove = 0;	

		end
		
    // DUT
    pifo_reg 
	#(
	.L2_MAX_SIZE(L2_MAX_SIZE),
    .RANK_WIDTH(RANK_WIDTH),
	.META_WIDTH(META_WIDTH),
	.ORDER(ORDER)
    )
	pifo_reg_i
    (
    .rst(rst),
    .clk(clk),
    .insert(insert),
    .remove(remove),
	.rank_in(rank_in),
	.meta_in(meta_in),
	.rank_out(rank_out),
	.meta_out(meta_out),
	.valid_out(valid_out)
    );

endmodule