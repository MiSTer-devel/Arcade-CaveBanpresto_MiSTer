// This file is a Codex-assisted rewrite based on the original work of
// Josh Bassett (nullobject).

// Framebuffer write request queues.

// Queues 16-bit framebuffer writes and coalesces adjacent pixels onto the 64-bit DDR write bus.
module CaveSpriteFramebufferRequestQueue (
  input         clock,
  input         reset,
  input         io_enable,
  input         io_readClock,
  input         io_in_wr,
  input  [1:0]  io_in_page,
  input  [16:0] io_in_addr,
  input  [15:0] io_in_din,
  output        io_in_wait_n,
  output        io_idle,
`ifdef CAVEBANPRESTO_MET_SPRITE_PAGE_HW_DIAGNOSTIC
  output        io_diag_pending_valid,
  output [1:0]  io_diag_pending_page,
`endif
  output        io_out_wr,
  output [1:0]  io_out_page,
  output [31:0] io_out_addr,
  output [7:0]  io_out_mask,
  output [63:0] io_out_din,
  input         io_out_wait_n,
  input         io_out_burstDone
);
  reg         pendingValid;
  reg  [1:0]  pendingPage;
  reg  [14:0] pendingAddr;
  reg  [7:0]  pendingMask;
  reg  [63:0] pendingDin;
  reg  [5:0]  enqueuedNotCommitted;

  function [7:0] expand_mask;
    input [1:0] lane;
    begin
      case (lane)
        2'h0: expand_mask = 8'b00000011;
        2'h1: expand_mask = 8'b00001100;
        2'h2: expand_mask = 8'b00110000;
        2'h3: expand_mask = 8'b11000000;
        default: expand_mask = 8'b00000011;
      endcase
    end
  endfunction

  function [63:0] expand_bit_mask;
    input [1:0] lane;
    begin
      case (lane)
        2'h0: expand_bit_mask = 64'h0000_0000_0000_ffff;
        2'h1: expand_bit_mask = 64'h0000_0000_ffff_0000;
        2'h2: expand_bit_mask = 64'h0000_ffff_0000_0000;
        2'h3: expand_bit_mask = 64'hffff_0000_0000_0000;
        default: expand_bit_mask = 64'h0000_0000_0000_ffff;
      endcase
    end
  endfunction

  function [63:0] expand_data;
    input [1:0]  lane;
    input [15:0] din;
    begin
      case (lane)
        2'h0: expand_data = {48'h0, din};
        2'h1: expand_data = {32'h0, din, 16'h0};
        2'h2: expand_data = {16'h0, din, 32'h0};
        2'h3: expand_data = {din, 48'h0};
        default: expand_data = {48'h0, din};
      endcase
    end
  endfunction

  wire        fifo_enq_ready;
  wire        fifo_deq_valid;
  wire [88:0] fifo_deq_bits;
  wire [88:0] fifo_enq_bits = {
    pendingPage, pendingAddr, pendingDin, pendingMask
  };
  wire [1:0]  fifo_deq_page = fifo_deq_bits[88:87];
  wire [14:0] fifo_deq_addr = fifo_deq_bits[86:72];
  wire [63:0] fifo_deq_din = fifo_deq_bits[71:8];
  wire [7:0]  fifo_deq_mask = fifo_deq_bits[7:0];

  wire [14:0] inWordAddr = io_in_addr[16:2];
  wire [7:0]  inByteMask = expand_mask(io_in_addr[1:0]);
  wire [63:0] inBitMask = expand_bit_mask(io_in_addr[1:0]);
  wire [63:0] inDin = expand_data(io_in_addr[1:0], io_in_din);
  wire        samePending = pendingValid &
    (pendingPage == io_in_page) & (pendingAddr == inWordAddr);
  wire        flushPending = pendingValid & (~io_in_wr | ~samePending);
  wire        enqueueValid = flushPending & io_enable & ~reset;
  wire        enqueueAccepted =
    enqueueValid & fifo_enq_ready;
  wire        acceptInput =
    io_in_wr & (samePending | ~pendingValid | fifo_enq_ready);

  always @(posedge clock) begin
    if (reset | ~io_enable) begin
      pendingValid <= 1'b0;
      pendingPage <= 2'd0;
      pendingAddr <= 15'd0;
      pendingMask <= 8'd0;
      pendingDin <= 64'd0;
    end
    else if (flushPending & fifo_enq_ready) begin
      if (io_in_wr) begin
        pendingValid <= 1'b1;
        pendingPage <= io_in_page;
        pendingAddr <= inWordAddr;
        pendingMask <= inByteMask;
        pendingDin <= inDin;
      end
      else begin
        pendingValid <= 1'b0;
      end
    end
    else if (acceptInput) begin
      if (samePending) begin
        pendingMask <= pendingMask | inByteMask;
        pendingDin <= (pendingDin & ~inBitMask) | (inDin & inBitMask);
      end
      else begin
        pendingValid <= 1'b1;
        pendingPage <= io_in_page;
        pendingAddr <= inWordAddr;
        pendingMask <= inByteMask;
        pendingDin <= inDin;
      end
    end
  end

  // A FIFO word is not physically complete merely because it disappeared
  // from the read side.  Retain the accepted-minus-committed count through
  // the source-2-qualified DDR burst-done pulse for quiesce/reconstruction
  // drain proof.  Normal page flips cannot retarget an outstanding word:
  // pendingPage and fifo_deq_page carry its producer-time physical owner.
  always @(posedge clock) begin
    if (reset | ~io_enable) begin
      enqueuedNotCommitted <= 6'd0;
    end
    else begin
      case ({enqueueAccepted, io_out_burstDone})
        2'b10: enqueuedNotCommitted <= enqueuedNotCommitted + 6'd1;
        2'b01: begin
          if (enqueuedNotCommitted != 6'd0)
            enqueuedNotCommitted <= enqueuedNotCommitted - 6'd1;
        end
        default: begin
        end
      endcase
    end
  end

  CaveDualClockFIFO #(
    .DATA_WIDTH (89),
    .DEPTH      (16)
  ) fifo (
    .write_clock (clock),
    .read_clock  (io_readClock),
    .deq_ready   (io_out_wait_n),
    .deq_valid   (fifo_deq_valid),
    .deq_bits    (fifo_deq_bits),
    .enq_ready   (fifo_enq_ready),
    .enq_valid   (enqueueValid),
    .enq_bits    (fifo_enq_bits)
  );

  assign io_in_wait_n = samePending | ~pendingValid | fifo_enq_ready;
  assign io_out_wr = io_enable & fifo_deq_valid;
  assign io_out_page = fifo_deq_page;
  assign io_out_addr = {14'b0, fifo_deq_addr, 3'b000};
  assign io_out_mask = fifo_deq_mask;
  assign io_out_din = fifo_deq_din;
  assign io_idle = ~pendingValid & (enqueuedNotCommitted == 6'd0);
`ifdef CAVEBANPRESTO_MET_SPRITE_PAGE_HW_DIAGNOSTIC
  // Read-only visibility for the temporary CB54 page-publication observer.
  assign io_diag_pending_valid = pendingValid;
  assign io_diag_pending_page = pendingPage;
`endif
endmodule

// Queues 32-bit framebuffer writes and expands them onto the 64-bit DDR write bus.
module CaveSystemFramebufferRequestQueue (
  input         clock,
  input         reset,
  input         io_enable,
  input         io_readClock,
  input         io_in_wr,
  input  [16:0] io_in_addr,
  input  [31:0] io_in_din,
  input  [1:0]  io_in_page,
  output        io_idle,
  output [5:0]  io_outstanding,
  output        io_out_wr,
  output [31:0] io_out_addr,
  output [1:0]  io_out_page,
  output [7:0]  io_out_mask,
  output [63:0] io_out_din,
  input         io_out_wait_n,
  input         io_out_commit
);
  wire        fifo_deq_valid;
  wire [55:0] fifo_deq_bits;
  wire [55:0] fifo_enq_bits = {
    io_in_page, io_in_wr, io_in_addr, io_in_din, 4'hF
  };
  wire        fifo_enq_ready_unused;
  wire [1:0]  fifo_deq_page = fifo_deq_bits[55:54];
  wire        fifo_deq_wr = fifo_deq_bits[53];
  wire [16:0] fifo_deq_addr = fifo_deq_bits[52:36];
  wire [31:0] fifo_deq_din = fifo_deq_bits[35:4];
  wire [3:0]  fifo_deq_mask = fifo_deq_bits[3:0];
  wire        output_write_accept =
    io_enable & fifo_deq_valid & fifo_deq_wr & io_out_wait_n;

  reg [5:0] outstanding_writes;

  always @(posedge io_readClock) begin
    if (reset | ~io_enable) begin
      outstanding_writes <= 6'd0;
    end
    else begin
      case ({output_write_accept, io_out_commit})
        2'b10: outstanding_writes <= outstanding_writes + 6'd1;
        2'b01: begin
          if (outstanding_writes != 6'd0)
            outstanding_writes <= outstanding_writes - 6'd1;
        end
        default: begin
        end
      endcase
    end
  end

  CaveDualClockFIFO #(
    .DATA_WIDTH (56),
    .DEPTH      (16)
  ) fifo (
    .write_clock (clock),
    .read_clock  (io_readClock),
    .deq_ready   (io_out_wait_n),
    .deq_valid   (fifo_deq_valid),
    .deq_bits    (fifo_deq_bits),
    .enq_ready   (fifo_enq_ready_unused),
    .enq_valid   (io_in_wr & io_enable & ~reset),
    .enq_bits    (fifo_enq_bits)
  );

  assign io_out_wr = io_enable & fifo_deq_valid & fifo_deq_wr;
  assign io_out_addr = {13'b0, fifo_deq_addr, 2'b00};
  assign io_out_page = fifo_deq_page;
  assign io_out_mask = fifo_deq_addr[0] ? {fifo_deq_mask, 4'b0000} : {4'b0000, fifo_deq_mask};
  assign io_out_din = {2{fifo_deq_din}};
  assign io_idle = ~fifo_deq_valid & (outstanding_writes == 6'd0);
  assign io_outstanding = outstanding_writes;
endmodule
