// This file is a Codex-assisted rewrite based on the original work of
// Josh Bassett (nullobject).

module SystemFrameBuffer(
  input         clock,
  input         reset,
  input         io_videoClock,
  input         io_enable,
  input         io_ss_hold,
  input         io_ss_canonicalize,
  input         io_ss_reconstruction_active,
  input         io_ss_reconstruction_ready,
  input         io_rotate,
  input         io_forceBlank,
  input         io_video_vBlank,
  input  [8:0]  io_video_regs_size_x,
  input  [8:0]  io_video_regs_size_y,
  output        io_frameBufferCtrl_enable,
  output [11:0] io_frameBufferCtrl_hSize,
  output [11:0] io_frameBufferCtrl_vSize,
  output [31:0] io_frameBufferCtrl_baseAddr,
  output [13:0] io_frameBufferCtrl_stride,
  input         io_frameBufferCtrl_vBlank,
  input         io_frameBufferCtrl_lowLat,
  output        io_frameBufferCtrl_forceBlank,
  input         io_frameBuffer_wr,
  input  [16:0] io_frameBuffer_addr,
  input  [31:0] io_frameBuffer_din,
  output        io_ddr_wr,
  output [31:0] io_ddr_addr,
  output [7:0]  io_ddr_mask,
  output [63:0] io_ddr_din,
  input         io_ddr_wait_n,
  input         io_ddr_commit,
  output        io_ss_idle,
  output        io_ss_publication_complete,
  output [31:0] io_ss_publication_debug
);
  wire [8:0]  frameWidth = io_rotate ? io_video_regs_size_y : io_video_regs_size_x;
  wire [8:0]  frameHeight = io_rotate ? io_video_regs_size_x : io_video_regs_size_y;

  wire        pageMode = ~io_frameBufferCtrl_lowLat;
  wire        pageSwapRead;
  wire        pageSwapWrite;
  wire [31:0] pageAddrWrite;
  wire [1:0]  pageIndexWrite = pageAddrWrite[20:19];

  wire [31:0] queueAddr;
  wire [1:0]  queuePage;
  wire        queueIdle;
  wire [5:0]  queueOutstanding;
  wire        frameCtrlVBlankRise;
  wire        publishNow;

  reg frameCtrlVBlank_r;
  reg frameCtrlVBlank;
  reg frameCtrlVBlankPrev;

  reg [1:0] pageIndexWriteCdcData;
  reg       pageIndexWriteCdcToggle;
  (* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
  reg       pageIndexWriteCdcToggleVideoMeta;
  (* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
  reg       pageIndexWriteCdcToggleVideo;
  reg       pageIndexWriteCdcToggleVideoSeen;
  reg [1:0] pageIndexWriteVideo;

  (* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
  reg       ssHoldVideoMeta;
  (* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
  reg       ssHoldVideoSync;
  reg       ssHoldVideo;
  reg       videoVBlankPrev;
  reg       frameHadWriteVideo;
  reg       videoFrameEndToggle;
  (* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
  reg       videoFrameEndToggleMeta;
  (* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
  reg       videoFrameEndToggleSync;
  reg       videoFrameEndToggleSeen;

  reg       reconstructionActivePrev;
  reg       publicationFence;
  reg       publicationArmed;
  reg       reconstructionReadySeen;
  reg       postReadyFrameSeen;
  reg       publicationReady;
  reg       publicationComplete;
  reg [3:0] publicationIdleCount;
  reg       publicationOutputWindow;

  reg [3:0] publicationWriteSwapCount;
  reg [3:0] publicationCoincidenceCount;
  reg [1:0] publicationPublishCount;
  reg       publicationReadSwapSeen;
  reg       publicationCommitSeen;
  reg [4:0] publicationMaxOutstanding;

  wire localReset = reset | io_ss_canonicalize;
  assign frameCtrlVBlankRise =
    frameCtrlVBlank & ~frameCtrlVBlankPrev;

  always @(posedge clock) begin
    if (localReset) begin
      frameCtrlVBlank_r <= 1'b0;
      frameCtrlVBlank <= 1'b0;
      frameCtrlVBlankPrev <= 1'b0;
    end
    else begin
      frameCtrlVBlank_r <= io_frameBufferCtrl_vBlank;
      frameCtrlVBlank <= frameCtrlVBlank_r;
      frameCtrlVBlankPrev <= frameCtrlVBlank;
    end
  end

  // The write-page payload is held stable before a toggle crosses into the
  // native video domain.  Canonicalization always advertises reset page 1,
  // even when the prior transaction happened to leave that same payload.
  always @(posedge clock) begin
    if (reset) begin
      pageIndexWriteCdcData <= 2'h1;
      pageIndexWriteCdcToggle <= 1'b0;
    end
    else if (io_ss_canonicalize) begin
      pageIndexWriteCdcData <= 2'h1;
      pageIndexWriteCdcToggle <= ~pageIndexWriteCdcToggle;
    end
    else if (pageIndexWrite != pageIndexWriteCdcData) begin
      pageIndexWriteCdcData <= pageIndexWrite;
      pageIndexWriteCdcToggle <= ~pageIndexWriteCdcToggle;
    end
  end

  // Hold deassertion deliberately uses one more video-clock stage than the
  // page toggle.  The first accepted post-restore write therefore cannot use
  // the previous transaction's page payload.
  always @(posedge io_videoClock) begin
    if (reset) begin
      pageIndexWriteCdcToggleVideoMeta <= 1'b0;
      pageIndexWriteCdcToggleVideo <= 1'b0;
      pageIndexWriteCdcToggleVideoSeen <= 1'b0;
      pageIndexWriteVideo <= 2'h1;
      ssHoldVideoMeta <= 1'b1;
      ssHoldVideoSync <= 1'b1;
      ssHoldVideo <= 1'b1;
      videoVBlankPrev <= io_video_vBlank;
      frameHadWriteVideo <= 1'b0;
      videoFrameEndToggle <= 1'b0;
    end
    else begin
      pageIndexWriteCdcToggleVideoMeta <= pageIndexWriteCdcToggle;
      pageIndexWriteCdcToggleVideo <= pageIndexWriteCdcToggleVideoMeta;
      ssHoldVideoMeta <= io_ss_hold;
      ssHoldVideoSync <= ssHoldVideoMeta;
      ssHoldVideo <= ssHoldVideoSync;
      videoVBlankPrev <= io_video_vBlank;

      if (pageIndexWriteCdcToggleVideo !=
          pageIndexWriteCdcToggleVideoSeen) begin
        pageIndexWriteVideo <= pageIndexWriteCdcData;
        pageIndexWriteCdcToggleVideoSeen <=
          pageIndexWriteCdcToggleVideo;
      end

      if (!io_enable || ssHoldVideo) begin
        frameHadWriteVideo <= 1'b0;
      end
      else if (io_video_vBlank & ~videoVBlankPrev) begin
        if (frameHadWriteVideo | io_frameBuffer_wr)
          videoFrameEndToggle <= ~videoFrameEndToggle;
        frameHadWriteVideo <= 1'b0;
      end
      else if (io_frameBuffer_wr) begin
        frameHadWriteVideo <= 1'b1;
      end
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      videoFrameEndToggleMeta <= 1'b0;
      videoFrameEndToggleSync <= 1'b0;
      videoFrameEndToggleSeen <= 1'b0;
    end
    else begin
      videoFrameEndToggleMeta <= videoFrameEndToggle;
      videoFrameEndToggleSync <= videoFrameEndToggleMeta;
      if (videoFrameEndToggleSync != videoFrameEndToggleSeen)
        videoFrameEndToggleSeen <= videoFrameEndToggleSync;
    end
  end

  assign pageSwapWrite =
    videoFrameEndToggleSync != videoFrameEndToggleSeen;

  // Reconstruction must advance through one full native frame after the
  // GPU's first sprite/system proof.  This excludes Air Gallet's adjacent
  // generation in which the restored sprite page becomes visible only at the
  // first proof edge.  Publication then waits for every tagged write to reach
  // the physical DDR command boundary and for a fresh output-frame vblank.
  always @(posedge clock) begin
    if (reset) begin
      reconstructionActivePrev <= 1'b0;
      publicationFence <= 1'b0;
      publicationArmed <= 1'b0;
      reconstructionReadySeen <= 1'b0;
      postReadyFrameSeen <= 1'b0;
      publicationReady <= 1'b0;
      publicationComplete <= 1'b0;
      publicationIdleCount <= 4'd0;
      publicationOutputWindow <= 1'b0;
    end
    else begin
      reconstructionActivePrev <= io_ss_reconstruction_active;

      if (io_ss_reconstruction_active &&
          !reconstructionActivePrev) begin
        publicationFence <= 1'b1;
        publicationArmed <= 1'b0;
        reconstructionReadySeen <= 1'b0;
        postReadyFrameSeen <= 1'b0;
        publicationReady <= 1'b0;
        publicationComplete <= 1'b0;
        publicationIdleCount <= 4'd0;
        publicationOutputWindow <= 1'b0;
      end

      if (!io_ss_reconstruction_active) begin
        publicationArmed <= 1'b0;
        publicationReady <= 1'b0;
        publicationOutputWindow <= 1'b0;
      end

      if (io_ss_canonicalize) begin
        publicationFence <= 1'b1;
        publicationArmed <= 1'b1;
        reconstructionReadySeen <= 1'b0;
        postReadyFrameSeen <= 1'b0;
        publicationReady <= 1'b0;
        publicationComplete <= 1'b0;
        publicationIdleCount <= 4'd0;
        publicationOutputWindow <= 1'b0;
      end
      else if (io_ss_reconstruction_active &&
               publicationArmed &&
               !publicationComplete) begin
        if (!frameCtrlVBlank)
          publicationOutputWindow <= 1'b0;
        else if (frameCtrlVBlankRise &&
                 publicationReady &&
                 queueIdle)
          publicationOutputWindow <= 1'b1;

        if (!reconstructionReadySeen) begin
          publicationReady <= 1'b0;
          publicationIdleCount <= 4'd0;
          if (io_ss_reconstruction_ready)
            reconstructionReadySeen <= 1'b1;
        end
        else begin
          if (pageSwapWrite) begin
            postReadyFrameSeen <= 1'b1;
            publicationReady <= 1'b0;
            publicationIdleCount <= 4'd0;
          end
          else if (!postReadyFrameSeen || !queueIdle) begin
            publicationReady <= 1'b0;
            publicationIdleCount <= 4'd0;
          end
          else if (!publicationReady) begin
            if (publicationIdleCount == 4'd7) begin
              publicationIdleCount <= 4'd8;
              publicationReady <= 1'b1;
            end
            else begin
              publicationIdleCount <= publicationIdleCount + 4'd1;
            end
          end
        end

        if (publishNow) begin
          publicationFence <= 1'b0;
          publicationArmed <= 1'b0;
          publicationReady <= 1'b0;
          publicationComplete <= 1'b1;
          publicationOutputWindow <= 1'b0;
        end
      end
    end
  end

  // Diagnostic shadows are transaction-local while active and remain sticky
  // afterward so the slow ISSP sampler can prove the completed publication.
  always @(posedge clock) begin
    if (reset) begin
      publicationWriteSwapCount <= 4'd0;
      publicationCoincidenceCount <= 4'd0;
      publicationPublishCount <= 2'd0;
      publicationReadSwapSeen <= 1'b0;
      publicationCommitSeen <= 1'b0;
      publicationMaxOutstanding <= 5'd0;
    end
    else if ((io_ss_reconstruction_active &&
              !reconstructionActivePrev) ||
             io_ss_canonicalize) begin
      publicationWriteSwapCount <= 4'd0;
      publicationCoincidenceCount <= 4'd0;
      publicationPublishCount <= 2'd0;
      publicationReadSwapSeen <= 1'b0;
      publicationCommitSeen <= 1'b0;
      publicationMaxOutstanding <= 5'd0;
    end
    else if (io_ss_reconstruction_active) begin
      if (pageSwapWrite && publicationWriteSwapCount != 4'hF)
        publicationWriteSwapCount <= publicationWriteSwapCount + 4'd1;
      if (frameCtrlVBlankRise && pageSwapWrite &&
          publicationReady && queueIdle &&
          publicationCoincidenceCount != 4'hF)
        publicationCoincidenceCount <=
          publicationCoincidenceCount + 4'd1;
      if (publishNow && publicationPublishCount != 2'h3)
        publicationPublishCount <= publicationPublishCount + 2'd1;
      if (pageSwapRead)
        publicationReadSwapSeen <= 1'b1;
      if (io_ddr_commit)
        publicationCommitSeen <= 1'b1;
      if (queueOutstanding[5])
        publicationMaxOutstanding <= 5'h1F;
      else if (queueOutstanding[4:0] > publicationMaxOutstanding)
        publicationMaxOutstanding <= queueOutstanding[4:0];
    end
  end

  assign publishNow =
    io_ss_reconstruction_active &
    publicationArmed &
    publicationOutputWindow &
    publicationReady &
    queueIdle &
    ~pageSwapWrite &
    frameCtrlVBlank;

  assign pageSwapRead =
    ~io_ss_hold &
    ((!io_ss_reconstruction_active & frameCtrlVBlankRise) |
     publishNow);

  CavePageFlipper #(
    .BASE_PAGE             (11'h120),
    .SUPPORT_TRIPLE_BUFFER (1'b1)
  ) pageFlipper (
    .clock        (clock),
    .reset        (localReset),
    .io_mode      (pageMode),
    .io_swapRead  (pageSwapRead),
    .io_swapWrite (pageSwapWrite),
    .io_addrRead  (io_frameBufferCtrl_baseAddr),
    .io_addrWrite (pageAddrWrite)
  );

  CaveSystemFramebufferRequestQueue queue (
    .clock         (io_videoClock),
    .reset         (localReset),
    .io_enable     (io_enable),
    .io_readClock  (clock),
    .io_in_wr      (io_frameBuffer_wr & ~ssHoldVideo),
    .io_in_addr    (io_frameBuffer_addr),
    .io_in_din     (io_frameBuffer_din),
    .io_in_page    (pageIndexWriteVideo),
    .io_idle       (queueIdle),
    .io_outstanding(queueOutstanding),
    .io_out_wr     (io_ddr_wr),
    .io_out_addr   (queueAddr),
    .io_out_page   (queuePage),
    .io_out_mask   (io_ddr_mask),
    .io_out_din    (io_ddr_din),
    .io_out_wait_n (io_ddr_wait_n),
    .io_out_commit (io_ddr_commit)
  );

  assign io_frameBufferCtrl_enable = io_enable;
  assign io_frameBufferCtrl_hSize = {3'h0, frameWidth};
  assign io_frameBufferCtrl_vSize = {3'h0, frameHeight};
  assign io_frameBufferCtrl_stride = {3'h0, frameWidth, 2'h0};
  assign io_frameBufferCtrl_forceBlank = io_forceBlank | publicationFence;
  assign io_ddr_addr = 32'(queueAddr + {11'h120, queuePage, 19'h0});
  assign io_ss_idle = queueIdle;
  assign io_ss_publication_complete = publicationComplete;
  // The successful transaction witnesses intentionally remain readable after
  // reconstruction_active falls and clear only when the next transaction
  // begins.  This output is observational and never feeds functional control.
  assign io_ss_publication_debug = {
    4'h6,
    reconstructionReadySeen,
    postReadyFrameSeen,
    publicationComplete,
    publicationFence,
    queueIdle,
    publicationOutputWindow,
    pageMode,
    io_frameBufferCtrl_baseAddr[20:19],
    pageIndexWrite,
    publicationWriteSwapCount,
    publicationCoincidenceCount,
    publicationPublishCount,
    publicationReadSwapSeen,
    publicationCommitSeen,
    publicationMaxOutstanding
  };
endmodule
