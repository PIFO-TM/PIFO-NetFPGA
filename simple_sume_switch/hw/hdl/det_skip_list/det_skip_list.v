`timescale 1ns/1ps

module det_skip_list
#(
	parameter L2_MAX_SIZE = 5,
	parameter RANK_WIDTH = 10,
	parameter META_WIDTH = 10,
    parameter L2_REG_WIDTH = 2
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
	output valid_out,
    output reg [L2_MAX_SIZE:0] num_entries,
	output busy,
	output reg full
);

	localparam MAX_SIZE = 2**L2_MAX_SIZE;
	localparam REG_WIDTH = 2**L2_REG_WIDTH;
    localparam NUM_LVLS = L2_MAX_SIZE;
    localparam L2_NUM_LVLS = log2(NUM_LVLS) + 1;
	localparam L2_SL_FILL_RANGES = 4;
	localparam SL_FILL_RANGES = 12;
    localparam MAX_CONS_NODES = 3;
	
	function integer log2;
    input integer number;
    begin
        log2=0;
        while(2**log2<number) begin
            log2=log2+1;
        end
    end
    endfunction // log2

	// Main state
    localparam INIT_HEAD      = 3'b000, 
	           INIT_TAIL      = 3'b001, 
			   INIT_FREE_LIST = 3'b010, 
			   RUN            = 3'b011,
			   INSERT         = 3'b100;

    // Search state
    localparam SRCH_IDLE      = 4'b0000, 
			   GO_DOWN        = 4'b0001, 
			   WAIT_MEM_RD1   = 4'b0010,
               GO_RIGHT1      = 4'b0011,
			   WAIT_MEM_RD2   = 4'b0100,
			   GO_RIGHT2      = 4'b0101,
			   WAIT_MEM_RD3   = 4'b0110,
			   SRCH_CONN_NEW  = 4'b0111,
			   SRCH_CONN_NEAR = 4'b1000;
			   
    // Insert state
	localparam INS_IDLE       = 2'b00,
	           INS_CONN_NEW   = 2'b01,
			   INS_CONN_NEAR  = 2'b10;
			   
	// Remove state
	localparam RMV_IDLE           = 3'b000,
	           RMV_CHK_BUSY       = 3'b001,
	           RMV_WAIT_MEM_RD1   = 3'b010,
	           RMV_DEQ_NODE       = 3'b011,
               RMV_WAIT_MEM_RD2   = 3'b100,
               RMV_CONN_LEFT_TAIL = 3'b101;


       reg [L2_MAX_SIZE-1:0] sl_fill_lo [0:SL_FILL_RANGES-1];
        initial begin
            sl_fill_lo[0]  = 12'd0;
            sl_fill_lo[1]  = 12'd1;
            sl_fill_lo[2]  = 12'd2;
            sl_fill_lo[3]  = 12'd4;
            sl_fill_lo[4]  = 12'd8;
            sl_fill_lo[5]  = 12'd16;
            sl_fill_lo[6]  = 12'd32;
            sl_fill_lo[7]  = 12'd64;
            sl_fill_lo[8]  = 12'd128;
            sl_fill_lo[9]  = 12'd256;
            sl_fill_lo[10] = 12'd512;
            sl_fill_lo[11] = 12'd1024;
        end

       reg [L2_MAX_SIZE-1:0] sl_fill_hi [0:SL_FILL_RANGES-1];
        initial begin
            sl_fill_hi[0]  = 12'd1;
            sl_fill_hi[1]  = 12'd2;
            sl_fill_hi[2]  = 12'd4;
            sl_fill_hi[3]  = 12'd8;
            sl_fill_hi[4]  = 12'd16;
            sl_fill_hi[5]  = 12'd32;
            sl_fill_hi[6]  = 12'd64;
            sl_fill_hi[7]  = 12'd128;
            sl_fill_hi[8]  = 12'd256;
            sl_fill_hi[9]  = 12'd512;
            sl_fill_hi[10] = 12'd1024;
            sl_fill_hi[11] = 12'd2048;
        end

       reg [L2_MAX_SIZE-1:0] pr_fill_levels [0:SL_FILL_RANGES-1];
        initial begin
            pr_fill_levels[0]  = 12'd0;
            pr_fill_levels[1]  = 12'd1;
            pr_fill_levels[2]  = 12'd2;
            pr_fill_levels[3]  = 12'd3;
            pr_fill_levels[4]  = 12'd4;
            pr_fill_levels[5]  = 12'd5;
            pr_fill_levels[6]  = 12'd6;
            pr_fill_levels[7]  = 12'd7;
            pr_fill_levels[8]  = 12'd8;
            pr_fill_levels[9]  = 12'd9;
            pr_fill_levels[10] = 12'd10;
            pr_fill_levels[11] = 12'd11;
        end

//	localparam [L2_MAX_SIZE-1:0] sl_fill_lo [0:SL_FILL_RANGES-1] =
//    '{0, 1, 2, 4,  8, 16, 32,  64, 128, 256,  512, 1024
//    };
//	localparam [L2_MAX_SIZE-1:0] sl_fill_hi [0:SL_FILL_RANGES-1] =
//    '{1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048
//    };
//	localparam [L2_MAX_SIZE-1:0] pr_fill_levels [0:SL_FILL_RANGES-1] =
//    '{0, 1, 2, 3,  4,  5,  6,   7,   8,   9,   10,   11
//    };
	
	localparam MIN_RANK = {RANK_WIDTH{1'b0}};
	localparam MAX_RANK = {RANK_WIDTH{1'b1}};

	reg free_list_wr;
	reg [L2_MAX_SIZE-1:0] free_list_din;
    reg start_search;
	reg insert_d1;
	reg pr_insert;
	reg pr_insert_d1;
	reg sl_insert;
	reg init_busy;
	reg ins_busy;
	reg rmv_busy;
	wire int_busy;
	reg [RANK_WIDTH-1:0] pr_rank_in;
	reg [META_WIDTH-1:0] pr_meta_in;
	reg [RANK_WIDTH-1:0] sl_rank_in;
	reg [META_WIDTH-1:0] sl_meta_in;
	reg [RANK_WIDTH-1:0] search_rank;
    reg [L2_NUM_LVLS-1:0] curr_max_lvl;
	reg [L2_MAX_SIZE-1:0] head [0:NUM_LVLS-1];
	reg [L2_MAX_SIZE-1:0] tail [0:NUM_LVLS-1];
    reg [L2_MAX_SIZE-1:0] n;
    reg [L2_MAX_SIZE-1:0] l;
    reg [L2_MAX_SIZE-1:0] u;
    reg [L2_MAX_SIZE-1:0] d;
    reg [L2_MAX_SIZE-1:0] uR;
	reg [L2_MAX_SIZE-1:0] dR;
	reg [L2_MAX_SIZE-1:0] dD;
	reg [L2_MAX_SIZE-1:0] lptr_tail;
	reg [L2_MAX_SIZE-1:0] rptr_head [0:NUM_LVLS-1];
	reg [L2_MAX_SIZE-1:0] dptr_head [0:NUM_LVLS-1];
	wire [L2_MAX_SIZE-1:0] new_node;
	reg [RANK_WIDTH-1:0] lVal;
	reg [2:0] main_state;
	reg [3:0] search_state;
	reg [1:0] ins_state;
	reg [2:0] rmv_state;
	reg [L2_NUM_LVLS-1:0] lvl_cntr;
	reg [L2_MAX_SIZE-1:0] node_cntr;
	reg [L2_MAX_SIZE:0] sl_num_entries;
	wire [L2_REG_WIDTH:0] pr_num_entries;
	reg [L2_MAX_SIZE-1:0] rank_raddr;
	reg [L2_MAX_SIZE-1:0] rank_waddr;
	reg [RANK_WIDTH-1:0] rank_din;
	wire [RANK_WIDTH-1:0] rank_dout;
	wire rank_rd;
	reg rank_wr;
	reg [L2_MAX_SIZE-1:0] meta_raddr;
	reg [L2_MAX_SIZE-1:0] meta_waddr;
	reg [META_WIDTH-1:0] meta_din;
	wire [META_WIDTH-1:0] meta_dout;
	wire meta_rd;
	reg meta_wr;
	reg [L2_MAX_SIZE-1:0] lvl_raddr;
	reg [L2_MAX_SIZE-1:0] lvl_waddr;
	reg [L2_NUM_LVLS-1:0] lvl_din;
	wire [L2_NUM_LVLS-1:0] lvl_dout;
	wire lvl_rd;
	reg lvl_wr;
	reg [L2_MAX_SIZE-1:0] rptr_raddr;
	reg [L2_MAX_SIZE-1:0] rptr_waddr;
	reg [L2_MAX_SIZE-1:0] rptr_din;
	wire [L2_MAX_SIZE-1:0] rptr_dout;
	wire rptr_rd;
	reg rptr_wr;
	reg [L2_MAX_SIZE-1:0] lptr_raddr;
	reg [L2_MAX_SIZE-1:0] lptr_waddr;
	reg [L2_MAX_SIZE-1:0] lptr_din;
	wire [L2_MAX_SIZE-1:0] lptr_dout;
	wire lptr_rd;
	reg lptr_wr;
	reg [L2_MAX_SIZE-1:0] uptr_raddr;
	reg [L2_MAX_SIZE-1:0] uptr_waddr;
	reg [L2_MAX_SIZE-1:0] uptr_din;
	wire [L2_MAX_SIZE-1:0] uptr_dout;
	wire uptr_rd;
	reg uptr_wr;
	reg [L2_MAX_SIZE-1:0] dptr_raddr;
	reg [L2_MAX_SIZE-1:0] dptr_waddr;
	reg [L2_MAX_SIZE-1:0] dptr_din;
	wire [L2_MAX_SIZE-1:0] dptr_dout;
	wire dptr_rd;
	reg dptr_wr;
	wire [RANK_WIDTH-1:0] pr_max_rank;
	wire [META_WIDTH-1:0] pr_max_meta;
	reg drop_down_node;
	wire pr_max_valid;
	reg get_next_node;
	reg search_done;
	reg insert_done;
	reg bram_rd;
	reg bram_rd1;
	reg [L2_NUM_LVLS-1:0] level;
	reg [1:0] cons_nodes;
	reg store_d;
	reg [L2_NUM_LVLS-1:0] rmv_lvl;
	wire pr_empty;
	wire pr_full;
	reg [L2_MAX_SIZE-1:0] deq_node;
	reg [L2_MAX_SIZE-1:0] rmv_node;
	wire free_nodes_avail;
	reg first_node;
	reg sl_blk_ins_if_rmv;
	reg [L2_SL_FILL_RANGES-1:0] sl_fill_idx;
    reg [L2_MAX_SIZE-1:0] pr_fill_thresh;
	reg pr_fill_busy;
	
	integer i;


	assign rank_rd = 1'b1;
	
    simple_dp_bram
    #(
        .RAM_WIDTH    (RANK_WIDTH),
    	.L2_RAM_DEPTH (L2_MAX_SIZE)
    )
    rank
    (
        .clka   (clk), 
        .wea    (rank_wr), 
        .addra  (rank_waddr), 
        .dina   (rank_din), 
    	.rstb   (rst),
        .clkb   (clk), 
        .enb    (rank_rd), 
        .addrb  (rank_raddr), 
        .doutb  (rank_dout)
    );

	assign meta_rd = 1'b1;
	
    simple_dp_bram
    #(
        .RAM_WIDTH    (META_WIDTH),
    	.L2_RAM_DEPTH (L2_MAX_SIZE)
    )
    hsp
    (
        .clka   (clk), 
        .wea    (meta_wr), 
        .addra  (meta_waddr), 
        .dina   (meta_din), 
    	.rstb   (rst),
        .clkb   (clk), 
        .enb    (meta_rd), 
        .addrb  (meta_raddr), 
        .doutb  (meta_dout)
    );

    assign lvl_rd = 1'b1;
	
    simple_dp_bram 
    #(
        .RAM_WIDTH    (L2_NUM_LVLS),
    	.L2_RAM_DEPTH (L2_MAX_SIZE)
    )
    node_lvl
    (
        .clka   (clk), 
        .wea    (lvl_wr), 
        .addra  (lvl_waddr), 
        .dina   (lvl_din), 
    	.rstb   (rst),
        .clkb   (clk), 
        .enb    (lvl_rd), 
        .addrb  (lvl_raddr), 
        .doutb  (lvl_dout)
    );

    assign rptr_rd = 1'b1;
	
    simple_dp_bram
    #(
        .RAM_WIDTH    (L2_MAX_SIZE),
    	.L2_RAM_DEPTH (L2_MAX_SIZE)
    )
    node_rptr
    (
        .clka   (clk), 
        .wea    (rptr_wr), 
        .addra  (rptr_waddr), 
        .dina   (rptr_din), 
    	.rstb   (rst),
        .clkb   (clk), 
        .enb    (rptr_rd), 
        .addrb  (rptr_raddr), 
        .doutb  (rptr_dout)
    );

    assign lptr_rd = 1'b1;
	
    simple_dp_bram
    #(
        .RAM_WIDTH    (L2_MAX_SIZE),
    	.L2_RAM_DEPTH (L2_MAX_SIZE)
    )
    node_lptr
    (
        .clka   (clk), 
        .wea    (lptr_wr), 
        .addra  (lptr_waddr), 
        .dina   (lptr_din), 
    	.rstb   (rst),
        .clkb   (clk), 
        .enb    (lptr_rd), 
        .addrb  (lptr_raddr), 
        .doutb  (lptr_dout)
    );

    assign uptr_rd = 1'b1;
	
    simple_dp_bram
    #(
        .RAM_WIDTH    (L2_MAX_SIZE),
    	.L2_RAM_DEPTH (L2_MAX_SIZE)
    )
    node_uptr
    (
        .clka   (clk), 
        .wea    (uptr_wr), 
        .addra  (uptr_waddr), 
        .dina   (uptr_din), 
    	.rstb   (rst),
        .clkb   (clk), 
        .enb    (uptr_rd), 
        .addrb  (uptr_raddr), 
        .doutb  (uptr_dout)
    );

	assign dptr_rd = 1'b1;
	
    simple_dp_bram 
    #(
        .RAM_WIDTH    (L2_MAX_SIZE),
    	.L2_RAM_DEPTH (L2_MAX_SIZE)
    )
    node_dptr
    (
        .clka   (clk), 
        .wea    (dptr_wr), 
        .addra  (dptr_waddr), 
        .dina   (dptr_din), 
    	.rstb   (rst),
        .clkb   (clk), 
        .enb    (dptr_rd), 
        .addrb  (dptr_raddr), 
        .doutb  (dptr_dout)
    );

    fallthrough_small_fifo
    #(
         .WIDTH(L2_MAX_SIZE),
         .MAX_DEPTH_BITS(L2_MAX_SIZE),
         .PROG_FULL_THRESHOLD(NUM_LVLS+1)
    )
    node_free_list
    (
        .reset       (rst),
        .clk         (clk),
        .din         (free_list_din),
        .wr_en       (free_list_wr),
        .rd_en       (get_next_node),
        .dout        (new_node),
        .full        (),
        .nearly_full (),
        .prog_full   (free_nodes_avail),
        .empty       ()
    );
    
	// Assert skip list full when not enough free nodes are available
    always @(posedge clk)
	begin
	    full <= ~free_nodes_avail;
	end
	
    pifo_reg
    #(
    	.L2_REG_WIDTH (L2_REG_WIDTH),
        .RANK_WIDTH  (RANK_WIDTH),
    	.META_WIDTH  (META_WIDTH)
    )
    pifo_reg
    (
        .rst           (rst),
        .clk           (clk),
        .insert        (pr_insert),
        .rank_in       (pr_rank_in),
        .meta_in       (pr_meta_in),
        .remove        (remove),
        .rank_out      (rank_out),
        .meta_out      (meta_out),
        .valid_out     (valid_out),
		.max_rank_out  (pr_max_rank),
		.max_meta_out  (pr_max_meta),
		.max_valid_out (pr_max_valid),
		.num_entries   (pr_num_entries),
		.empty         (pr_empty),
		.full          (pr_full)
    );

    // Main
	always @(posedge clk)
	begin
	    if (rst)
		begin
			main_state <= INIT_HEAD;
			ins_state <= INS_IDLE;
			search_state <= SRCH_IDLE;
			rmv_state <= RMV_IDLE;
			lvl_cntr <= {L2_NUM_LVLS{1'b0}};
			node_cntr <= {L2_MAX_SIZE{1'b0}};
			free_list_wr <= 1'b0;
			insert_d1 <= 1'b0;
			pr_insert <= 1'b0;
			pr_insert_d1 <= 1'b0;
			sl_insert <= 1'b0;
			sl_blk_ins_if_rmv <= 1'b0;
			init_busy <= 1'b1;
			ins_busy <= 1'b0;
			rmv_busy <= 1'b0;
			sl_num_entries <= 0;
            curr_max_lvl <= 0;
			rank_wr <= 1'b0;
			meta_wr <= 1'b0;
			lvl_wr <= 1'b0;
			rptr_wr <= 1'b0;
			lptr_wr <= 1'b0;
			uptr_wr <= 1'b0;
			dptr_wr <= 1'b0;
			bram_rd <= 1'b0;
			bram_rd1 <= 1'b0;
			start_search <= 1'b0;
		    search_done <= 1'b0;
			insert_done <= 1'b0;
			get_next_node <= 1'b0;
			store_d <= 1'b0;
			first_node <= 1'b0;
			pr_fill_busy <= 1'b0;
			
		end
		else
		begin
		    free_list_wr <= 1'b0;
			pr_insert <= 1'b0;
			sl_insert <= 1'b0;
			rank_wr <= 1'b0;
			meta_wr <= 1'b0;
			lvl_wr <= 1'b0;
			rptr_wr <= 1'b0;
			lptr_wr <= 1'b0;
			uptr_wr <= 1'b0;
			dptr_wr <= 1'b0;
            bram_rd <= 1'b0;
			start_search <= 1'b0;
			insert_done <= 1'b0;
			search_done <= 1'b0;
			get_next_node <= 1'b0;
			first_node <= 1'b0;
			sl_blk_ins_if_rmv <= 1'b0;
			
			bram_rd1     <= bram_rd;
			insert_d1    <= insert;
			pr_insert_d1 <= pr_insert;
			
		    case (main_state)
			INIT_HEAD: // 0
			begin
			    head[lvl_cntr] <= node_cntr;
				rank_waddr <= node_cntr;
				rank_din <= MAX_RANK;
				rank_wr <= 1'b1;
				meta_waddr <= node_cntr;
				meta_din <= {META_WIDTH{1'b1}};
				meta_wr <= 1'b1;
				lvl_waddr <= node_cntr;
				lvl_din <= lvl_cntr;
				lvl_wr <= 1'b1;
				rptr_waddr <= node_cntr;
				rptr_din <= node_cntr + 1;
				rptr_wr <= 1'b1;
			    rptr_head[lvl_cntr] <= node_cntr + 1;
				lptr_waddr <= node_cntr;
				lptr_din <= {L2_MAX_SIZE{1'b1}};
				lptr_wr <= 1'b1;
				
				if (lvl_cntr > 0)
				begin
					dptr_waddr <= node_cntr;
					dptr_din <= node_cntr - 2;
					dptr_wr <= 1'b1;
				    dptr_head[lvl_cntr] <= node_cntr - 2;
				end
				if (lvl_cntr < NUM_LVLS - 1)
				begin
				    uptr_waddr <= node_cntr;
					uptr_din <= node_cntr + 2;
					uptr_wr <= 1'b1;
				end
				node_cntr <= node_cntr + 1;
				main_state <= INIT_TAIL;
			end
			
			INIT_TAIL: // 1
			begin
			    tail[lvl_cntr] <= node_cntr;
				rank_waddr <= node_cntr;
				rank_din <= MIN_RANK;
				rank_wr <= 1'b1;
				meta_waddr <= node_cntr;
				meta_din <= {META_WIDTH{1'b1}};
				meta_wr <= 1'b1;
				lvl_waddr <= node_cntr;
				lvl_din <= lvl_cntr;
				lvl_wr <= 1'b1;
				rptr_waddr <= node_cntr;
				rptr_din <= {L2_MAX_SIZE{1'b1}};
				rptr_wr <= 1'b1;
				lptr_waddr <= node_cntr;
				lptr_din <= node_cntr - 1;
				lptr_wr <= 1'b1;
				if (lvl_cntr < NUM_LVLS - 1)
				begin
				    uptr_waddr <= node_cntr;
					uptr_din <= node_cntr + 2;
					uptr_wr <= 1'b1;
				end
				if (lvl_cntr > 0)
				begin
					dptr_waddr <= node_cntr;
					dptr_din <= node_cntr - 2;
					dptr_wr <= 1'b1;
				end
				node_cntr <= node_cntr + 1;
				
				if (lvl_cntr < NUM_LVLS - 1)
				begin
				    lvl_cntr <= lvl_cntr + 1;
					main_state <= INIT_HEAD;
				end
				else
				    main_state <= INIT_FREE_LIST;
			end
			
			INIT_FREE_LIST: // 2
			begin
                // Push all free nodes in free list FIFO
                free_list_din <= node_cntr;
				free_list_wr <= 1'b1;
				if (node_cntr == MAX_SIZE - 2)
				begin
				    main_state <= RUN;
					init_busy <= 1'b0;
				end
				else
                    node_cntr <= node_cntr + 1;
			end  
			
			RUN:  // 3
			    if (insert == 1'b1 && sl_num_entries < MAX_SIZE)
				    if (sl_num_entries == 0) 
					    if (pr_full == 1'b0)
						begin
							pr_rank_in <= rank_in;
							pr_meta_in <= meta_in;
					        pr_insert <= 1'b1;
						end
					    else
 						// No need to check for free nodes because sl_num_entries = 0
                        begin						
					        if (rank_in < pr_max_rank)
						    begin
							    // Send max value to skip list unless we are simultaneously removing an entry 
							    if (remove == 1'b0)
								begin
							        sl_rank_in <= pr_max_rank;
								    sl_meta_in <= pr_max_meta;
							        sl_insert <= 1'b1;
									sl_blk_ins_if_rmv <= 1'b1;
							        ins_busy <= 1'b1;
					                main_state <= INSERT;
								end
							    pr_rank_in <= rank_in;
								pr_meta_in <= meta_in;
					            pr_insert <= 1'b1;
							end
					        else
							begin
							    sl_rank_in <= rank_in;
								sl_meta_in <= meta_in;
					            sl_insert <= 1'b1;
							    ins_busy <= 1'b1;
					            main_state <= INSERT;
							end
						end
					else if (free_nodes_avail == 1'b1)
					begin
					    if (pr_full == 1'b1)
						begin
					        if (rank_in < pr_max_rank)
						    begin
							    // Send max value to skip list unless we are simultaneously removing an entry 
							    if (remove == 1'b0)
								begin
							        sl_rank_in <= pr_max_rank;
								    sl_meta_in <= pr_max_meta;
							        sl_insert <= 1'b1;
									sl_blk_ins_if_rmv <= 1'b1;
							        ins_busy <= 1'b1;
						            main_state <= INSERT;
								end
							    pr_rank_in <= rank_in;
								pr_meta_in <= meta_in;
					            pr_insert <= 1'b1;
							end
					        else
							begin
							    sl_rank_in <= rank_in;
								sl_meta_in <= meta_in;
					            sl_insert <= 1'b1;
							    ins_busy <= 1'b1;
						        main_state <= INSERT;
							end
						end
						else
						begin
							if ((pr_empty != 1'b1) && (rank_in < pr_max_rank))
						    begin
							    pr_rank_in <= rank_in;
								pr_meta_in <= meta_in;
					            pr_insert <= 1'b1;
							end
							else
							begin
							    sl_rank_in <= rank_in;
							    sl_meta_in <= meta_in;
						        sl_insert <= 1'b1;
						        ins_busy <= 1'b1;
						        main_state <= INSERT;
							end
						end
					end
				
			INSERT: // 4
			begin
			    // If a remove has just arrived, skip list insert will not take place
			    if (remove == 1'b1 && sl_blk_ins_if_rmv == 1'b1)
				    main_state <= RUN;
					
			    if (insert_done == 1'b1) 
				begin
					sl_num_entries <= sl_num_entries + 1;
					main_state <= RUN;
				end
			end
			
			default:
			    main_state <= INIT_HEAD;
			endcase
	
			// Search state machine
            case(search_state)
            SRCH_IDLE: // 0
			    if (start_search == 1'b1) 
				begin
                    level <= curr_max_lvl;
                    n <= head[curr_max_lvl];
                    u <= head[curr_max_lvl + 1];
				    d <= head[curr_max_lvl];
				    cons_nodes <= 0;
				    first_node <= 1'b1;
                    search_state <= GO_RIGHT1;
                end
			
            GO_DOWN: // 1
				if (level != {L2_NUM_LVLS{1'b1}})
				begin
                    cons_nodes <= 0;
                    // Read node n 
				    rank_raddr <= n;
                    rptr_raddr <= n;
                    uptr_raddr <= n;
                    dptr_raddr <= n;
					bram_rd <= 1'b1;
				    d <= n;
					store_d <= 1'b1;
				    search_state <= WAIT_MEM_RD1;
				end
				else
				begin
				    search_done <= 1'b1;
					search_state <= SRCH_IDLE;
				end
				
			WAIT_MEM_RD1: // 2
			    if (bram_rd1 == 1'b1)
					search_state <= GO_RIGHT1;
			
            GO_RIGHT1: // 3
			begin
			    if (first_node == 1'b1)
			    begin
				    dR <= rptr_head[curr_max_lvl];
					dD <= dptr_head[curr_max_lvl];

                    // Store current node in l
                    l <= n;
					lVal <= MAX_RANK;
                    // Move right
                    n <= rptr_head[curr_max_lvl];
					// Read node n
					rank_raddr <= rptr_head[curr_max_lvl];
					lvl_raddr <= rptr_head[curr_max_lvl];
					rptr_raddr <= rptr_head[curr_max_lvl];
                    uptr_raddr <= rptr_head[curr_max_lvl];
					dptr_raddr <= rptr_head[curr_max_lvl];
					bram_rd <= 1'b1;
					search_state <= WAIT_MEM_RD2;
			    end
			    else
			    begin
				    if (store_d == 1'b1)
				    begin
				        dR <= rptr_dout;
					    dD <= dptr_dout;
					    store_d = 1'b0;
				    end
                    if (rptr_dout != {L2_MAX_SIZE{1'b1}})
				    begin
                        // Store current node in l
                        l <= n;
					    lVal <= rank_dout;
                        // Move right
                        n <= rptr_dout;
					    // Read node n
					    rank_raddr <= rptr_dout;
					    lvl_raddr <= rptr_dout;
					    rptr_raddr <= rptr_dout;
                        uptr_raddr <= rptr_dout;
					    dptr_raddr <= rptr_dout;
					    bram_rd <= 1'b1;
					    search_state <= WAIT_MEM_RD2;
				    end
				    else
				    begin
				        u <= d;
                        n <= dptr_dout;
                        level <= level - 1;
					    search_state <= GO_DOWN;
				    end
			    end
			end
			
			WAIT_MEM_RD2: // 4
			    if (bram_rd1 == 1'b1)
					search_state <= GO_RIGHT2;
			
			GO_RIGHT2: // 5
			begin
                // Save the node at which we will drop down
			    if (rank_dout > search_rank)
				begin
				    d <= n;
				    dR <= rptr_dout;
					dD <= dptr_dout;
					// Note: blocking assignment used in case we hit drop down node AND a higher node stack at the same node/clock
					drop_down_node = 1'b1;
			    end
				else
				    drop_down_node = 1'b0;
				
                // Exit if reached a higher node stack
                if (uptr_dout != {L2_MAX_SIZE{1'b1}})
				begin
	                u <= d;
					// If drop down node (dD) was assigned this clock cycle, use output from dptr bram directly
                    if (drop_down_node == 1'b1)
					    n <= dptr_dout;
					else
					    // Otherwise use value stored in dD
					    n <= dD;
				    level <= level - 1;
                    search_state <= GO_DOWN;
				end
                else
                    // If max number of consecutive nodes found
                    if (cons_nodes == MAX_CONS_NODES-1)
			        begin
                        // Insert new node one level above
                        // Read node in level above
				        rptr_raddr <= u;
					    bram_rd <= 1'b1;

 					    search_state <= WAIT_MEM_RD3;
				    end
                    else
					    search_state <= GO_RIGHT1;
                // Count consecutive nodes except for head
                cons_nodes <= cons_nodes + 1;
			end
			
			WAIT_MEM_RD3: // 6
			    if (bram_rd1 == 1'b1)
					search_state <= SRCH_CONN_NEW;
			
            SRCH_CONN_NEW:  // 7
            begin			

				uR <= rptr_dout;
                // Connect new node
			    rank_waddr <= new_node;
			    rank_din <= lVal;
				rank_wr <= 1'b1;
                lvl_waddr <= new_node;
				lvl_din <= level + 1;
				lvl_wr <= 1'b1;
				rptr_waddr <= new_node;
				rptr_din <= rptr_dout;
				rptr_wr <= 1'b1;
				lptr_waddr <= new_node;
				lptr_din <= u;
				lptr_wr <= 1'b1;
				uptr_waddr <= new_node;
				uptr_din <= {L2_MAX_SIZE{1'b1}};
				uptr_wr <= 1'b1;
				dptr_waddr <= new_node;
				dptr_din <= l;
				dptr_wr <= 1'b1;
			    if (new_node == head[level+1])
                    dptr_head[level+1] <= new_node;
				search_state <= SRCH_CONN_NEAR;
            end
			
			SRCH_CONN_NEAR:  // 8
			begin
                // Connect right neighbor to new node
				lptr_waddr <= uR;
				lptr_din <= new_node;
				lptr_wr <= 1'b1;

                // Connect left neighbor to new node
				rptr_waddr <= u;
				rptr_din <= new_node;
				rptr_wr <= 1'b1;
			    if (u == head[level+1])
			        rptr_head[level+1] <= new_node;
			    
				
                // Connect node below to new node
				uptr_waddr <= l;
				uptr_din <= new_node;
				uptr_wr <= 1'b1;
				
				// Request next node
                get_next_node <= 1'b1;

                // Increment current level if we added a new level
                if (level + 1 > curr_max_lvl)
			    begin
                    curr_max_lvl <= curr_max_lvl + 1;
				    u <= d;
                    n <= dD;
                    level <= level - 1;

                    search_state <= GO_DOWN;
				end
				else
				    search_state <= GO_RIGHT1;
			end
			
            default : 
			    search_state <= SRCH_IDLE;
				
            endcase

            // Skip List Insert state machine 
		    case(ins_state)
            INS_IDLE: 
			begin
			    ins_busy <= 1'b0;
				// Start insert if no simultaneous remove arrived
		        if (sl_insert == 1'b1 && (sl_blk_ins_if_rmv & remove) == 1'b0)
				begin
				    ins_busy <= 1'b1;
			        start_search <= 1'b1;
				    search_rank <= sl_rank_in;
					ins_state <= INS_CONN_NEW;
				end
			end
			
			INS_CONN_NEW:
				if (search_done == 1'b1)
				begin
                    // Connect new node
			        rank_waddr <= new_node;
			        rank_din <= search_rank;
				    rank_wr <= 1'b1;
					meta_waddr <= new_node;
					meta_din <= sl_meta_in;
					meta_wr <= 1'b1;
                    lvl_waddr <= new_node;
				    lvl_din <= 0;
				    lvl_wr <= 1'b1;
				    rptr_waddr <= new_node;
				    rptr_din <= dR;
				    rptr_wr <= 1'b1;
				    lptr_waddr <= new_node;
				    lptr_din <= d;
				    lptr_wr <= 1'b1;
                    uptr_waddr <= new_node;
					uptr_din <= {L2_MAX_SIZE{1'b1}};
					uptr_wr <= 1'b1;
				    insert_done <= 1'b1;
				
				    ins_state <= INS_CONN_NEAR;
                end
				
			INS_CONN_NEAR:
			begin
                // Connect right neighbor to new node
				lptr_waddr <= dR;
				lptr_din <= new_node;
				lptr_wr <= 1'b1;
				if (dR == tail[0])
				begin
				    // rank_tail <= search_rank;
				    lptr_tail <= new_node;
                end
                // Connect left neighbor to new node
				rptr_waddr <= d;
				rptr_din <= new_node;
				rptr_wr <= 1'b1;				    
			    if (d == head[0])
			        rptr_head[0] <= new_node;
				
				// Request next node
                get_next_node <= 1'b1;
				
				ins_state <= INS_IDLE;
			end
			
			default:
			    ins_state <= INS_IDLE;
				
		    endcase
			
			// Remove from skip list
			case(rmv_state)
			RMV_IDLE: // 0
			begin
			    rmv_busy <= 1'b0;
			    if (pr_full == 1'b0 && sl_num_entries > 0 && int_busy == 1'b0 && insert == 1'b0 && pr_insert == 1'b0 && sl_insert == 1'b0)
				begin
					rmv_busy <= 1'b1;
					rmv_state <= RMV_CHK_BUSY;
				end
			end
			
			RMV_CHK_BUSY: // 1
			    // Check to make sure an Insert operation did not start simultaneously
			    if (ins_busy == 1'b0 && insert == 1'b0 && pr_insert == 1'b0 && sl_insert == 1'b0)
				begin
                    rank_raddr <= lptr_tail;
				    meta_raddr <= lptr_tail;
				    lptr_raddr <= lptr_tail;
				    uptr_raddr <= lptr_tail;
				    deq_node <= lptr_tail;
					bram_rd <= 1'b1;
				    sl_num_entries <= sl_num_entries - 1;
				    rmv_state <= RMV_WAIT_MEM_RD1;
				end
				else
				    // Could not get busy semaphore, go back to RMV_IDLE
					rmv_state <= RMV_IDLE;
			
            RMV_WAIT_MEM_RD1: // 2
                if (bram_rd1 == 1'b1)
                    rmv_state <= RMV_DEQ_NODE;
					
			RMV_DEQ_NODE: // 3
			begin
			    // Send node to PIFO reg
			    pr_rank_in <= rank_dout;
				pr_meta_in <= meta_dout;
				pr_insert <= 1'b1;
				// Connect left neighbor to tail
			    rptr_waddr <= lptr_dout;
			    rptr_din <= tail[0];
				rptr_wr <= 1'b1;
                // Update head rptr register if the last node was removed from this level
				if (lptr_dout == head[0])
				    rptr_head[0] <= tail[0];
				lptr_waddr <= tail[0];
				lptr_din <= lptr_dout;
				lptr_wr <= 1'b1;
				lptr_tail <= lptr_dout;
				// Clear dequeued node
				// No need to clear right/left pointers since they're always overwritten on insert
				uptr_waddr <= deq_node;
				uptr_din <= {L2_MAX_SIZE{1'b1}};
				uptr_wr <= 1'b1;
				dptr_waddr <= deq_node;
				dptr_din <= {L2_MAX_SIZE{1'b1}};
				dptr_wr <= 1'b1;
				// Return to free list
				free_list_din <= deq_node;
				free_list_wr <= 1'b1;
				// Read up neighbor if it exists
				if (uptr_dout != {L2_MAX_SIZE{1'b1}})
				begin
				    rptr_raddr <= uptr_dout;
					lptr_raddr <= uptr_dout;
				    uptr_raddr <= uptr_dout;
				    bram_rd <= 1'b1;
					rmv_node <= uptr_dout;
					rmv_lvl <= 1;
				    rmv_state <= RMV_WAIT_MEM_RD2;
				end
				else
				    rmv_state <= RMV_IDLE;
			end
			
			RMV_WAIT_MEM_RD2: // 4
			    if (bram_rd1 == 1'b1)
				    rmv_state <= RMV_CONN_LEFT_TAIL;			
				
			RMV_CONN_LEFT_TAIL: // 5
			begin
				// Connect left neighbor to tail
			    rptr_waddr <= lptr_dout;
			    rptr_din <= tail[rmv_lvl];
				rptr_wr <= 1'b1;
                // Update head rptr register if the last node was removed from this level
				if (lptr_dout == head[rmv_lvl])
				    rptr_head[rmv_lvl] <= tail[rmv_lvl];
				lptr_waddr <= tail[rmv_lvl];
				lptr_din <= lptr_dout;
				lptr_wr <= 1'b1;
				
				// Clear node and return it
				uptr_waddr <= rmv_node;
		        uptr_din <= {L2_MAX_SIZE{1'b1}};
			    uptr_wr <= 1'b1;
			    dptr_waddr <= rmv_node;
			    dptr_din <= {L2_MAX_SIZE{1'b1}};
			    dptr_wr <= 1'b1;
			    free_list_din <= rmv_node;
				free_list_wr <= 1'b1;
				if (uptr_dout != {L2_MAX_SIZE{1'b1}})
				begin
				    rptr_raddr <= uptr_dout;
					lptr_raddr <= uptr_dout;
			        uptr_raddr <= uptr_dout;
				    bram_rd <= 1'b1;
					rmv_node <= uptr_dout;
					rmv_lvl <= rmv_lvl + 1;
					rmv_state <= RMV_WAIT_MEM_RD2;
				end
				else
				begin
				    if (rptr_dout == tail[rmv_lvl] && lptr_dout == head[rmv_lvl])
					    curr_max_lvl <= curr_max_lvl - 1;

				    rmv_state <= RMV_IDLE;
				end
			end
			
			default:
			    rmv_state <= RMV_IDLE;
			endcase
		end
		
	    // Output total number of entries in both PIFO register and skip list
	    num_entries <= {{(L2_MAX_SIZE-L2_REG_WIDTH){1'b0}}, pr_num_entries} + sl_num_entries;
		
	    for (i = 0; i < SL_FILL_RANGES; i=i+1) 			
            if (sl_num_entries >= sl_fill_lo[i] && sl_num_entries < sl_fill_hi[i])
                pr_fill_thresh <= pr_fill_levels[i];
				
		if (pr_num_entries < pr_fill_thresh)
		    pr_fill_busy <= 1'b1;
		else
		    pr_fill_busy <= 1'b0;
		
	end
	
	
	// Internal busy not including throttling
	// pr_insert_d1 asserts busy for one clock cycle after an insertion into the PIFO reg to allow time for pr_max_rank to be valid
	assign int_busy = init_busy | ins_busy | insert_d1 | pr_insert_d1 | rmv_busy;
	// External busy including (PIFO Reg empty AND SL not empty) to prevent starvation of replenishment
	// of PIFO Reg from Skip List
	assign busy = int_busy | pr_fill_busy;
	// Output total number of entries in both PIFO register and skip list
	//assign num_entries = {{(L2_MAX_SIZE-L2_REG_WIDTH){1'b0}}, pr_num_entries} + sl_num_entries;
	
endmodule
