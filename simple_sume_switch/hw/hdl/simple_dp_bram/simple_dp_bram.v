
  //  Xilinx Simple Dual Port 2 Clock RAM
  //  This code implements a parameterizable SDP dual clock memory.
  //  If a reset or enable is not necessary, it may be tied off or removed from the code.

module simple_dp_bram
#(
    parameter RAM_WIDTH = 32,
    parameter L2_RAM_DEPTH = 10
)
(
    input                             clka,
    input                             wea,
    input [L2_RAM_DEPTH-1:0]          addra,
    input [RAM_WIDTH-1:0]             dina,

    input                             clkb,
    input                             enb,
    input                             rstb,
    input  [L2_RAM_DEPTH-1:0]         addrb,
    output [RAM_WIDTH-1:0]            doutb
);

  localparam INIT_FILE = "";                       // Specify name/location of RAM initialization file if using one (leave blank if not)
  localparam RAM_DEPTH = 2**L2_RAM_DEPTH;

  // output reg enable
  wire regceb = enb;

  reg [RAM_WIDTH-1:0] RAM [RAM_DEPTH-1:0];
  reg [RAM_WIDTH-1:0] RAM_data = {RAM_WIDTH{1'b0}};

  // The following code either initializes the memory values to a specified file or to all zeros to match hardware
  generate
    if (INIT_FILE != "") begin: use_init_file
      initial
        $readmemh(INIT_FILE, RAM, 0, RAM_DEPTH-1);
    end else begin: init_bram_to_zero
      integer ram_index;
      initial
        for (ram_index = 0; ram_index < RAM_DEPTH; ram_index = ram_index + 1)
          RAM[ram_index] = {RAM_WIDTH{1'b0}};
    end
  endgenerate

  always @(posedge clka)
    if (wea)
      RAM[addra] <= dina;

  always @(posedge clkb)
    if (enb)
      RAM_data <= RAM[addrb];

  // The following is a 2 clock cycle read latency with improve clock-to-out timing

  reg [RAM_WIDTH-1:0] doutb_reg = {RAM_WIDTH{1'b0}};

  always @(posedge clkb)
    if (rstb)
      doutb_reg <= {RAM_WIDTH{1'b0}};
    else if (regceb)
      doutb_reg <= RAM_data;

  assign doutb = doutb_reg;

endmodule
