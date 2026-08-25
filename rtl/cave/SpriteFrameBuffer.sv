// This file is a Codex-assisted rewrite based on the original work of
// Josh Bassett (nullobject).

module SpriteFrameBuffer(
  input         clock,
  input         reset,
  input         io_videoClock,
  input         io_enable,
`ifdef CAVEBANPRESTO_MET_SPRITE_PAGE_HW_DIAGNOSTIC
  input         io_met_sprite_page_diag_enable,
  input  [2:0]  io_met_sprite_page_diag_source,
  input  [8:0]  io_met_sprite_page_diag_video_pos_x,
  input         io_met_sprite_page_diag_mixer_sprite_wins,
  output [127:0] io_met_sprite_page_diag_probe,
  output        io_met_sprite_page_diag_overlay_valid,
  output [23:0] io_met_sprite_page_diag_overlay_rgb,
`endif
  input         io_ss_hold,
  input         io_ss_canonicalize,
  input         io_ss_preclear_target,
  input         io_swap,
  input  [8:0]  io_video_pos_y,
  input  [8:0]  io_video_regs_size_x,
  input  [8:0]  io_video_regs_size_y,
  input         io_video_hBlank,
  input         io_lineBuffer_earlyStart,
  input  [2:0]  io_lineBuffer_burstOffset,
  input  [8:0]  io_lineBuffer_addr,
  output [15:0] io_lineBuffer_dout,
  input         io_frameBuffer_wr,
  input  [16:0] io_frameBuffer_addr,
  input  [15:0] io_frameBuffer_din,
  output        io_frameBuffer_wait_n,
  output        io_ddr_rd,
  output        io_ddr_wr,
  output [31:0] io_ddr_addr,
  output [7:0]  io_ddr_mask,
  output [63:0] io_ddr_din,
  input  [63:0] io_ddr_dout,
  input         io_ddr_wait_n,
  input         io_ddr_valid,
  output [7:0]  io_ddr_burstLength,
  input         io_ddr_burstDone,
  output        io_ss_idle,
  output        io_ss_write_idle,
  output        io_ss_swap_accepted,
  output        io_ss_reconstruction_target_ready
);
  localparam [10:0] FRAMEBUFFER_BASE_PAGE = 11'h121;

  wire        lineBuffer_wr;
  wire [8:0]  lineBuffer_addr;
  wire [10:0] lineBuffer_readAddr;
  wire [63:0] lineBuffer_din;

  wire        lineBufferDma_start;
  wire        lineBufferDma_in_rd;
  wire [31:0] lineBufferDma_in_addr;
  wire [63:0] lineBufferDma_in_dout;
  wire        lineBufferDma_in_wait_n;
  wire        lineBufferDma_in_valid;
  wire        lineBufferDma_in_burstDone;
  wire [31:0] lineBufferDma_out_addr;
  wire        lineBufferDma_busy;

  wire        frameBufferDma_start;
  wire        frameBufferClearDma_start;
  wire        reconstructionClearStart;
  wire        frameBufferDma_out_wr;
  wire [31:0] frameBufferDma_out_addr;
  wire [63:0] frameBufferDma_out_din;
  wire [7:0]  frameBufferDma_out_burstLength;
  wire        frameBufferDma_out_wait_n;
  wire        frameBufferDma_out_burstDone;
  wire        frameBufferDma_busy;

  wire        queue_out_wr;
  wire [1:0]  queue_out_page;
  wire [31:0] queue_out_addr;
  wire [7:0]  queue_out_mask;
  wire [63:0] queue_out_din;
  wire        queue_out_wait_n;
  wire        queue_out_burstDone;
  wire        queue_idle;
  wire        ddrArbiter_idle;
`ifdef CAVEBANPRESTO_MET_SPRITE_PAGE_HW_DIAGNOSTIC
  wire        queue_diag_pending_valid;
  wire [1:0]  queue_diag_pending_page;
  wire        lineBufferDma_diag_start_accepted;
`endif

  wire [31:0] page_addrRead;
  wire [31:0] page_addrWrite;
  wire [31:0] ddr_lineBuffer_addr;
  wire [31:0] ddr_frameBufferClear_addr;
  wire [31:0] ddr_frameBufferQueue_addr;
  wire [9:0]  clearWidthPlus3 = {1'b0, io_video_regs_size_x} + 10'd3;
  wire [7:0]  clearWordsPerLine = clearWidthPlus3[9:2];
  wire [8:0]  clearLines = io_video_regs_size_y;

  reg hBlank_r;
  reg hBlank;
  reg hBlankPrev;
  reg [8:0] lineBufferDmaTargetY;
  reg enableReg;
  reg reconstructionClearPending;
  reg reconstructionClearInFlight;
  reg reconstructionTargetReady;
  wire [8:0] lineBufferNextTargetY =
    io_video_pos_y + (io_lineBuffer_earlyStart ? 9'h002 : 9'h001);

  wire localReset = reset | io_ss_canonicalize;

  always @(posedge clock) begin
    if (reset)
      enableReg <= 1'b0;
    else
      enableReg <= io_enable;
  end

  assign frameBufferDma_start = enableReg & ~io_ss_hold & io_swap;
  assign reconstructionClearStart =
    reconstructionClearPending & enableReg & ~io_ss_hold &
    ~frameBufferDma_busy & (|clearWordsPerLine) & (|clearLines);
  assign frameBufferClearDma_start =
    frameBufferDma_start | reconstructionClearStart;
  assign io_ss_swap_accepted = frameBufferDma_start;
  assign io_ss_reconstruction_target_ready = reconstructionTargetReady;

  // Canonical page ownership is read0/write1, but DDR page1 can contain
  // opaque pixels from the pre-restore core.  Transparent sprite pixels do
  // not overwrite them, so Air's private reconstruction draw must begin only
  // after page1 has been deterministically cleared and the clear burst has
  // physically completed.  This preclear never flips page ownership.
  always @(posedge clock) begin
    if (reset) begin
      reconstructionClearPending <= 1'b0;
      reconstructionClearInFlight <= 1'b0;
      reconstructionTargetReady <= 1'b0;
    end
    else if (io_ss_canonicalize) begin
      reconstructionClearPending <= io_ss_preclear_target;
      reconstructionClearInFlight <= 1'b0;
      reconstructionTargetReady <= 1'b0;
    end
    else begin
      if (reconstructionClearStart) begin
        reconstructionClearPending <= 1'b0;
        reconstructionClearInFlight <= 1'b1;
        reconstructionTargetReady <= 1'b0;
      end
      else if (reconstructionClearInFlight & ~frameBufferDma_busy) begin
        reconstructionClearInFlight <= 1'b0;
        reconstructionTargetReady <= 1'b1;
      end
    end
  end

  always @(posedge clock) begin
    if (localReset) begin
      hBlank_r <= 1'b0;
      hBlank <= 1'b0;
      hBlankPrev <= 1'b0;
      lineBufferDmaTargetY <= 9'h000;
    end
    else begin
      hBlank_r <= io_video_hBlank;
      hBlank <= hBlank_r;
      hBlankPrev <= hBlank;
      if (lineBufferDma_start)
        lineBufferDmaTargetY <= lineBufferNextTargetY;
    end
  end

  wire lineBufferStartEdge =
    io_lineBuffer_earlyStart ? (~hBlank & hBlankPrev) : (hBlank & ~hBlankPrev);
  wire [1:0] lineBufferWriteBank =
    io_lineBuffer_earlyStart ? lineBufferDmaTargetY[1:0] : 2'b00;
  wire [1:0] lineBufferReadBank =
    io_lineBuffer_earlyStart ? io_video_pos_y[1:0] : 2'b00;

  assign lineBufferDma_start =
    enableReg & ~io_ss_hold & lineBufferStartEdge;
  assign lineBuffer_addr = {lineBufferWriteBank, lineBufferDma_out_addr[9:3]};
  assign lineBuffer_readAddr = {lineBufferReadBank, io_lineBuffer_addr};

  CaveTrueDualPortRam #(
    .ADDR_WIDTH_A (9),
    .ADDR_WIDTH_B (11),
    .DATA_WIDTH_A (64),
    .DATA_WIDTH_B (16),
    .DEPTH_A      (512),
    .DEPTH_B      (2048),
    .MASK_ENABLE  (0)
  ) lineBuffer (
    .clock_a (clock),
    .rd_a    (1'b0),
    .wr_a    (lineBuffer_wr),
    .addr_a  (lineBuffer_addr),
    .mask_a  (8'hFF),
    .din_a   (lineBuffer_din),
    .dout_a  (),
    .clock_b (io_videoClock),
    .rd_b    (1'b1),
    .addr_b  (lineBuffer_readAddr),
    .dout_b  (io_lineBuffer_dout)
  );

  CavePageFlipper #(
    .BASE_PAGE             (FRAMEBUFFER_BASE_PAGE),
    .SUPPORT_TRIPLE_BUFFER (1'b0)
  ) pageFlipper (
    .clock        (clock),
    .reset        (localReset),
    .io_mode      (1'b0),
    .io_swapRead  (1'b0),
    .io_swapWrite (frameBufferDma_start),
    .io_addrRead  (page_addrRead),
    .io_addrWrite (page_addrWrite)
  );

  CaveFramebufferLineReadDma lineBufferDma (
    .clock           (clock),
    .reset           (localReset),
    .io_start        (lineBufferDma_start),
    .io_burstOffset  (io_lineBuffer_burstOffset),
    .io_busy         (lineBufferDma_busy),
    .io_in_rd        (lineBufferDma_in_rd),
    .io_in_addr      (lineBufferDma_in_addr),
    .io_in_dout      (lineBufferDma_in_dout),
    .io_in_wait_n    (lineBufferDma_in_wait_n),
    .io_in_valid     (lineBufferDma_in_valid),
    .io_in_burstDone (lineBufferDma_in_burstDone),
    .io_out_wr       (lineBuffer_wr),
    .io_out_addr     (lineBufferDma_out_addr),
    .io_out_din      (lineBuffer_din)
`ifdef CAVEBANPRESTO_MET_SPRITE_PAGE_HW_DIAGNOSTIC
    ,
    .io_diag_start_accepted (lineBufferDma_diag_start_accepted)
`endif
  );

  CaveSpriteFramebufferRequestQueue queue (
    .clock         (clock),
    .reset         (localReset),
    .io_enable     (enableReg),
    .io_readClock  (clock),
    .io_in_wr      (io_frameBuffer_wr),
    .io_in_page    (page_addrWrite[20:19]),
    .io_in_addr    (io_frameBuffer_addr),
    .io_in_din     (io_frameBuffer_din),
    .io_in_wait_n  (io_frameBuffer_wait_n),
    .io_idle       (queue_idle),
`ifdef CAVEBANPRESTO_MET_SPRITE_PAGE_HW_DIAGNOSTIC
    .io_diag_pending_valid (queue_diag_pending_valid),
    .io_diag_pending_page  (queue_diag_pending_page),
`endif
    .io_out_wr     (queue_out_wr),
    .io_out_page   (queue_out_page),
    .io_out_addr   (queue_out_addr),
    .io_out_mask   (queue_out_mask),
    .io_out_din    (queue_out_din),
    .io_out_wait_n (queue_out_wait_n),
    .io_out_burstDone (queue_out_burstDone)
  );

  CaveFramebufferClearDma frameBufferDma (
    .clock            (clock),
    .reset            (localReset),
    .io_start         (frameBufferClearDma_start),
    .io_wordsPerLine  (clearWordsPerLine),
    .io_lines         (clearLines),
    .io_busy          (frameBufferDma_busy),
    .io_out_wr        (frameBufferDma_out_wr),
    .io_out_addr      (frameBufferDma_out_addr),
    .io_out_din       (frameBufferDma_out_din),
    .io_out_burstLength (frameBufferDma_out_burstLength),
    .io_out_wait_n    (frameBufferDma_out_wait_n),
    .io_out_burstDone (frameBufferDma_out_burstDone)
  );

  assign ddr_lineBuffer_addr =
    32'(lineBufferDma_in_addr
        + 32'(page_addrRead + {13'h0, lineBufferDmaTargetY, 10'h0}));
  assign ddr_frameBufferClear_addr = 32'(frameBufferDma_out_addr + page_addrWrite);
  assign ddr_frameBufferQueue_addr =
    32'(queue_out_addr + {FRAMEBUFFER_BASE_PAGE, queue_out_page, 19'h0});

  CaveSpriteFramebufferDdrArbiter ddrArbiter (
    .clock              (clock),
    .reset              (localReset),
    .io_in_0_rd         (lineBufferDma_in_rd),
    .io_in_0_addr       (ddr_lineBuffer_addr),
    .io_in_0_dout       (lineBufferDma_in_dout),
    .io_in_0_wait_n     (lineBufferDma_in_wait_n),
    .io_in_0_valid      (lineBufferDma_in_valid),
    .io_in_0_burstDone  (lineBufferDma_in_burstDone),
    .io_in_1_wr         (frameBufferDma_out_wr),
    .io_in_1_addr       (ddr_frameBufferClear_addr),
    .io_in_1_din        (frameBufferDma_out_din),
    .io_in_1_burstLength (frameBufferDma_out_burstLength),
    .io_in_1_wait_n     (frameBufferDma_out_wait_n),
    .io_in_1_burstDone  (frameBufferDma_out_burstDone),
    .io_in_2_wr         (queue_out_wr),
    .io_in_2_addr       (ddr_frameBufferQueue_addr),
    .io_in_2_mask       (queue_out_mask),
    .io_in_2_din        (queue_out_din),
    .io_in_2_wait_n     (queue_out_wait_n),
    .io_in_2_burstDone  (queue_out_burstDone),
    .io_out_rd          (io_ddr_rd),
    .io_out_wr          (io_ddr_wr),
    .io_out_addr        (io_ddr_addr),
    .io_out_mask        (io_ddr_mask),
    .io_out_din         (io_ddr_din),
    .io_out_dout        (io_ddr_dout),
    .io_out_wait_n      (io_ddr_wait_n),
    .io_out_valid       (io_ddr_valid),
    .io_out_burstLength (io_ddr_burstLength),
    .io_out_burstDone   (io_ddr_burstDone),
    .io_idle            (ddrArbiter_idle)
  );
`ifdef CAVEBANPRESTO_MET_SPRITE_PAGE_HW_DIAGNOSTIC
  // PageFlipper publishes the pre-edge write page as the new read page on a
  // swap. A same-edge line start therefore belongs to page_addrWrite, while
  // every ordinary line start belongs to the current page_addrRead.
  wire [31:0] met_sprite_line_start_page_base =
    frameBufferDma_start ? page_addrWrite : page_addrRead;

  CaveMetmqstrSpritePageHardwareDiagnostic
    metmqstrSpritePageHardwareDiagnostic (
    .clock_i                    (clock),
    .reset_i                    (localReset),
    .video_clock_i              (io_videoClock),
    .enable_i                   (io_met_sprite_page_diag_enable),
    .source_i                   (io_met_sprite_page_diag_source),
    .line_start_i               (lineBufferDma_start),
    .line_start_accepted_i      (lineBufferDma_diag_start_accepted),
    .line_dma_busy_i            (lineBufferDma_busy),
    .line_start_target_y_i      (lineBufferNextTargetY),
    .line_live_target_y_i       (lineBufferDmaTargetY),
    .line_start_page_base_i     (met_sprite_line_start_page_base),
    .read_page_base_i           (page_addrRead),
    .display_read_page_i        (page_addrRead[20:19]),
    .read_accept_i              (
      lineBufferDma_in_rd & lineBufferDma_in_wait_n
    ),
    .read_logical_addr_i        (lineBufferDma_in_addr),
    .read_physical_addr_i       (ddr_lineBuffer_addr),
    .raw_valid_i                (lineBufferDma_in_valid),
    .raw_data_i                 (lineBufferDma_in_dout),
    .raw_burst_done_i           (lineBufferDma_in_burstDone),
    .functional_write_i         (lineBuffer_wr),
    .functional_write_addr_i    (lineBuffer_addr),
    .video_line_addr_i          (io_lineBuffer_addr),
    .video_pos_x_i              (io_met_sprite_page_diag_video_pos_x),
    .video_pos_y_i              (io_video_pos_y),
    .video_size_x_i             (io_video_regs_size_x),
    .video_size_y_i             (io_video_regs_size_y),
    .functional_pixel_i         (io_lineBuffer_dout),
    .mixer_sprite_wins_i        (
      io_met_sprite_page_diag_mixer_sprite_wins
    ),
    .probe_o                    (io_met_sprite_page_diag_probe),
    .overlay_valid_o            (
      io_met_sprite_page_diag_overlay_valid
    ),
    .overlay_rgb_o              (io_met_sprite_page_diag_overlay_rgb)
  );
`endif

  assign io_ss_idle =
    ~lineBufferDma_busy &
    ~frameBufferDma_busy &
    queue_idle &
    ddrArbiter_idle;
  assign io_ss_write_idle = queue_idle;
endmodule
