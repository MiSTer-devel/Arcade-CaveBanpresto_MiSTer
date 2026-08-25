// This file is a Codex-assisted rewrite based on the original work of
// Josh Bassett (nullobject).

// Shared synchronous-read memory used by the retired Chisel memory wrappers.
module CaveSyncReadMem #(
  parameter ADDR_WIDTH = 1,
  parameter DATA_WIDTH = 8,
  parameter DEPTH = (1 << ADDR_WIDTH)
) (
  input  [ADDR_WIDTH-1:0] read_addr,
  input                   read_en,
  input                   read_clk,
  output [DATA_WIDTH-1:0] read_data,
  input  [ADDR_WIDTH-1:0] write_addr,
  input                   write_en,
  input                   write_clk,
  input  [DATA_WIDTH-1:0] write_data
);
  reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];
  reg                  read_en_d;
  reg [ADDR_WIDTH-1:0] read_addr_d;
  reg [DATA_WIDTH-1:0] read_data_mux;

  always @(posedge read_clk) begin
    read_en_d <= read_en;
    read_addr_d <= read_addr;
  end

  always @(posedge write_clk) begin
    if (write_en)
      memory[write_addr] <= write_data;
  end

  // Preserve the disabled/unknown output contract without asking the
  // simulator to index the array before the registered address is known.
  // For a known asserted enable this is identical to the former ternary.
  always @(*) begin
    read_data_mux = {DATA_WIDTH{1'bx}};
    case (read_en_d)
      1'b1: begin
        if ((^read_addr_d !== 1'bx) &&
            (read_addr_d < DEPTH))
          read_data_mux = memory[read_addr_d];
      end
      default: ;
    endcase
  end

  assign read_data = read_data_mux;
endmodule
