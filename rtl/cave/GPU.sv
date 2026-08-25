// This file is a Codex-assisted rewrite based on the original work of
// Josh Bassett (nullobject).

// Video pixel pipeline: layers, sprites, palette lookup, and framebuffer writeout.
module GPU(
  input          clock,
  input          reset,
  input          io_videoClock,
  input          io_ss_hold,
  input          io_ss_canonicalize,
  input          io_layerCtrl_0_enable,
  input  [1:0]   io_layerCtrl_0_format,
  input          io_layerCtrl_0_regs_tileSize,
  input          io_layerCtrl_0_regs_enable,
  input          io_layerCtrl_0_regs_flipX,
  input          io_layerCtrl_0_regs_flipY,
  input          io_layerCtrl_0_regs_rowScrollEnable,
  input          io_layerCtrl_0_regs_rowSelectEnable,
  input  [1:0]   io_layerCtrl_0_regs_priority,
  input  [8:0]   io_layerCtrl_0_regs_scroll_x,
  input  [8:0]   io_layerCtrl_0_regs_scroll_y,
  output [11:0]  io_layerCtrl_0_vram8x8_addr,
  input  [31:0]  io_layerCtrl_0_vram8x8_dout,
  output [9:0]   io_layerCtrl_0_vram16x16_addr,
  input  [31:0]  io_layerCtrl_0_vram16x16_dout,
  output [8:0]   io_layerCtrl_0_lineRam_addr,
  input  [31:0]  io_layerCtrl_0_lineRam_dout,
  output         io_layerCtrl_0_tileRom_rd,
  output [31:0]  io_layerCtrl_0_tileRom_addr,
  input  [63:0]  io_layerCtrl_0_tileRom_dout,
  input          io_layerCtrl_1_enable,
  input  [1:0]   io_layerCtrl_1_format,
  input          io_layerCtrl_1_regs_tileSize,
  input          io_layerCtrl_1_regs_enable,
  input          io_layerCtrl_1_regs_flipX,
  input          io_layerCtrl_1_regs_flipY,
  input          io_layerCtrl_1_regs_rowScrollEnable,
  input          io_layerCtrl_1_regs_rowSelectEnable,
  input  [1:0]   io_layerCtrl_1_regs_priority,
  input  [8:0]   io_layerCtrl_1_regs_scroll_x,
  input  [8:0]   io_layerCtrl_1_regs_scroll_y,
  output [11:0]  io_layerCtrl_1_vram8x8_addr,
  input  [31:0]  io_layerCtrl_1_vram8x8_dout,
  output [9:0]   io_layerCtrl_1_vram16x16_addr,
  input  [31:0]  io_layerCtrl_1_vram16x16_dout,
  output [8:0]   io_layerCtrl_1_lineRam_addr,
  input  [31:0]  io_layerCtrl_1_lineRam_dout,
  output         io_layerCtrl_1_tileRom_rd,
  output [31:0]  io_layerCtrl_1_tileRom_addr,
  input  [63:0]  io_layerCtrl_1_tileRom_dout,
  input          io_layerCtrl_2_enable,
  input  [1:0]   io_layerCtrl_2_format,
  input          io_layerCtrl_2_regs_tileSize,
  input          io_layerCtrl_2_regs_enable,
  input          io_layerCtrl_2_regs_flipX,
  input          io_layerCtrl_2_regs_flipY,
  input          io_layerCtrl_2_regs_rowScrollEnable,
  input          io_layerCtrl_2_regs_rowSelectEnable,
  input  [1:0]   io_layerCtrl_2_regs_priority,
  input  [8:0]   io_layerCtrl_2_regs_scroll_x,
  input  [8:0]   io_layerCtrl_2_regs_scroll_y,
  output [11:0]  io_layerCtrl_2_vram8x8_addr,
  input  [31:0]  io_layerCtrl_2_vram8x8_dout,
  output [9:0]   io_layerCtrl_2_vram16x16_addr,
  input  [31:0]  io_layerCtrl_2_vram16x16_dout,
  output [8:0]   io_layerCtrl_2_lineRam_addr,
  input  [31:0]  io_layerCtrl_2_lineRam_dout,
  output         io_layerCtrl_2_tileRom_rd,
  output [31:0]  io_layerCtrl_2_tileRom_addr,
  input  [63:0]  io_layerCtrl_2_tileRom_dout,
  input          io_spriteCtrl_enable,
  input  [1:0]   io_spriteCtrl_format,
  input          io_spriteCtrl_start,
  input          io_spriteCtrl_zoom,
  input  [8:0]   io_spriteCtrl_regs_offset_x,
  input  [8:0]   io_spriteCtrl_regs_offset_y,
  input  [1:0]   io_spriteCtrl_regs_bank,
  input          io_spriteCtrl_regs_fixed,
  input          io_spriteCtrl_regs_hFlip,
  output         io_spriteCtrl_vram_rd,
  output [11:0]  io_spriteCtrl_vram_addr,
  input  [127:0] io_spriteCtrl_vram_dout,
  output         io_spriteCtrl_tileRom_rd,
  output [31:0]  io_spriteCtrl_tileRom_addr,
  input  [63:0]  io_spriteCtrl_tileRom_dout,
  input          io_spriteCtrl_tileRom_wait_n,
  input          io_spriteCtrl_tileRom_valid,
  output [7:0]   io_spriteCtrl_tileRom_burstLength,
  input          io_spriteCtrl_tileRom_burstDone,
  input  [8:0]   io_gameConfig_granularity,
  input  [1:0]   io_gameConfig_layer_0_paletteBank,
  input  [1:0]   io_gameConfig_layer_1_paletteBank,
  input  [1:0]   io_gameConfig_layer_2_paletteBank,
  input          io_gameConfig_maskLeftColumn,
  input          io_gameConfig_airLayer2Direct6bpp,
  input          io_gameConfig_sailorMoonTilebank,
  input          io_gameConfig_metmqstrRenderCrop,
  input          io_options_rotate,
  input          io_options_rotateClockwise,
  input          io_options_flipVideo,
  input          io_video_clockEnable,
  input          io_video_displayEnable,
  input  [8:0]   io_video_pos_x,
  input  [8:0]   io_video_pos_y,
  input          io_video_vBlank,
  input  [8:0]   io_video_regs_size_x,
  input  [8:0]   io_video_regs_size_y,
  output [8:0]   io_spriteLineBuffer_addr,
  input  [15:0]  io_spriteLineBuffer_dout,
  output         io_spriteFrameBuffer_wr,
  output [16:0]  io_spriteFrameBuffer_addr,
  output [15:0]  io_spriteFrameBuffer_din,
  input          io_spriteFrameBuffer_wait_n,
  output         io_spriteCtrl_frameReady,
  output         io_systemFrameBuffer_wr,
  output [16:0]  io_systemFrameBuffer_addr,
  output [31:0]  io_systemFrameBuffer_din,
  output [14:0]  io_paletteRam_addr,
  input  [15:0]  io_paletteRam_dout,
  output [23:0]  io_rgb,
  output         io_ss_idle,
  output         io_ss_reconstruction_ready
`ifdef CAVEBANPRESTO_MET_SPRITE_PAGE_HW_DIAGNOSTIC
  ,
  input          io_met_sprite_diag_overlay_valid,
  input  [23:0]  io_met_sprite_diag_overlay_rgb,
  output         io_met_sprite_diag_mixerSpriteWins
`endif
`ifdef CAVE_ENABLE_DEBUG_OVERLAY
  ,
  output [63:0]  io_debug_video,
  output [63:0]  io_debug_readout,
  output [23:0]  io_debug_source_rgb
`endif
);
  wire [1:0]  layer0PenPriority;
  wire [5:0]  layer0PenPalette;
  wire [7:0]  layer0PenColor;
  wire [1:0]  layer1PenPriority;
  wire [5:0]  layer1PenPalette;
  wire [7:0]  layer1PenColor;
  wire [1:0]  layer2PenPriority;
  wire [5:0]  layer2PenPalette;
  wire [7:0]  layer2PenColor;
  reg         sailorMoonTilebankSync0;
  reg         sailorMoonTilebankSync1;

  wire [1:0]  spritePenPriority = io_spriteLineBuffer_dout[15:14];
  wire [5:0]  spritePenPalette = io_spriteLineBuffer_dout[13:8];
  wire [7:0]  spritePenColor = io_spriteLineBuffer_dout[7:0];
  wire [63:0] spriteProcessorDebug;
  wire [15:0] paletteColor;
  wire [23:0] videoRgb888 = {
    paletteColor[9:5],
    paletteColor[9:7],
    paletteColor[14:10],
    paletteColor[14:12],
    paletteColor[4:0],
    paletteColor[4:2]
  };
  wire [23:0] framebufferRgb888 = {
    paletteColor[4:0],
    paletteColor[4:2],
    paletteColor[14:10],
    paletteColor[14:12],
    paletteColor[9:5],
    paletteColor[9:7]
  };
  wire visiblePixel = ~(io_gameConfig_maskLeftColumn & (io_video_pos_x == 9'd0));
  wire [23:0] maskedVideoRgb888 = visiblePixel ? videoRgb888 : 24'h000000;
  wire [23:0] maskedFramebufferRgb888 =
    visiblePixel ? framebufferRgb888 : 24'h000000;
  wire [8:0] renderVideoPosX =
    io_gameConfig_metmqstrRenderCrop ? (io_video_pos_x + 9'h07D) : io_video_pos_x;
  wire [8:0] renderVideoSizeX =
    io_gameConfig_metmqstrRenderCrop ? 9'h1FF : io_video_regs_size_x;

  wire [8:0] flippedVideoX = io_video_regs_size_x - io_video_pos_x - 9'h001;
  wire [8:0] flippedVideoY = io_video_regs_size_y - io_video_pos_y - 9'h001;
  wire [17:0] videoX = {9'h000, io_video_pos_x};
  wire [17:0] videoY = {9'h000, io_video_pos_y};
  wire [17:0] videoSizeX = {9'h000, io_video_regs_size_x};
  wire [17:0] videoSizeY = {9'h000, io_video_regs_size_y};
  wire [17:0] flippedX = {9'h000, flippedVideoX};
  wire [17:0] flippedY = {9'h000, flippedVideoY};

  wire [17:0] normalFramebufferAddr =
    io_options_flipVideo
      ? (flippedY * videoSizeX) + flippedX
      : (videoY * videoSizeX) + videoX;
  wire        rotateClockwise = io_options_rotateClockwise ^ io_options_flipVideo;
  wire [17:0] rotatedFramebufferAddr =
    rotateClockwise
      ? (videoX * videoSizeY) + flippedY
      : (flippedX * videoSizeY) + videoY;
  wire [17:0] nextSystemFramebufferAddr =
    io_options_rotate ? rotatedFramebufferAddr : normalFramebufferAddr;

  reg        systemFramebufferWrReg;
  reg [17:0] systemFramebufferAddrReg;
  reg [31:0] systemFramebufferDinReg;
`ifdef CAVEBANPRESTO_MET_SPRITE_PAGE_HW_DIAGNOSTIC
  reg        metSpriteDiagOverlayValidReg;
  reg [23:0] metSpriteDiagOverlayRgbReg;

  // Match ColorMixer's registered palette-output stage so a diagnostic color
  // replaces the exact pixel whose sprite/tile decision it describes.
  always @(posedge io_videoClock) begin
    if (reset) begin
      metSpriteDiagOverlayValidReg <= 1'b0;
      metSpriteDiagOverlayRgbReg <= 24'd0;
    end else begin
      metSpriteDiagOverlayValidReg <= io_met_sprite_diag_overlay_valid;
      metSpriteDiagOverlayRgbReg <= io_met_sprite_diag_overlay_rgb;
    end
  end
`endif

  (* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
  reg ssHoldVideo0;
  (* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
  reg ssHoldVideo1;
  reg ssCanonicalRequestReg;
  reg ssCanonicalToggleSystem;
  (* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
  reg ssCanonicalToggleVideo0;
  (* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
  reg ssCanonicalToggleVideo1;
  reg ssCanonicalToggleVideoSeen;
  (* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
  reg ssVideoWriterIdleSystem0;
  (* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
  reg ssVideoWriterIdleSystem1;
  (* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
  reg ssFrameBuiltSystem0;
  (* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
  reg ssFrameBuiltSystem1;
  reg ssFrameHadWriteVideo;
  reg ssFrameBuiltVideo;
  reg ssVideoVBlankPrev;

  wire ssVideoCanonicalPulse =
    ssCanonicalToggleVideo1 != ssCanonicalToggleVideoSeen;
  wire ssVideoRenderEnable = ~ssHoldVideo1;
  wire ssVideoWriterIdle = ssHoldVideo1 & ~systemFramebufferWrReg;
  wire spriteProcessorIdle;

  wire activeDisplayPixel =
    io_video_clockEnable & io_video_displayEnable & ssVideoRenderEnable;

  always @(posedge io_videoClock) begin
    if (reset) begin
      sailorMoonTilebankSync0 <= 1'b0;
      sailorMoonTilebankSync1 <= 1'b0;
    end else begin
      sailorMoonTilebankSync0 <= io_gameConfig_sailorMoonTilebank;
      sailorMoonTilebankSync1 <= sailorMoonTilebankSync0;
    end
  end

`ifdef CAVE_ENABLE_DEBUG_OVERLAY
  wire [3:0]  mixerDebugSelectedPen;
  wire [5:0]  mixerDebugSelectedPalette;
  wire [7:0]  mixerDebugSelectedColor;
  wire [3:0]  mixerDebugVisibleMask;

  reg          debugLayer2VisibleReg;
  reg  [1:0]  debugLayer2PriorityReg;
  reg  [5:0]  debugLayer2PaletteReg;
  reg  [7:0]  debugLayer2ColorReg;
  reg          debugVideoVBlankReg;
  reg  [7:0]  debugTopRgbFrame;
  reg  [7:0]  debugMidRgbFrame;
  reg  [7:0]  debugMidLeftRgbFrame;
  reg  [7:0]  debugMidRightRgbFrame;
  reg  [7:0]  debugPrevMidRgb;
  reg  [7:0]  debugTopMixFrame;
  reg  [7:0]  debugTopPaletteColorFrame;
  reg  [7:0]  debugTopPaletteAddrFrame;
  reg          debugTopSampleValid;
  reg          debugMidSampleValid;
  reg          debugMidLeftSampleValid;
  reg          debugMidRightSampleValid;
  reg  [7:0]  debugFlashFlagsLatched;
  reg  [7:0]  debugTopRgbLatched;
  reg  [7:0]  debugMidRgbLatched;
  reg  [7:0]  debugPrevMidRgbLatched;
  reg  [7:0]  debugTopMixLatched;
  reg  [7:0]  debugTopPaletteColorLatched;
  reg  [7:0]  debugTopPaletteAddrLatched;
  reg  [7:0]  debugFlashMismatchHistory;
  reg  [7:0]  metSpriteDebugFlags;
  reg  [7:0]  metSpriteDebugColor;
  reg  [7:0]  metSpriteDebugMix;
  reg  [7:0]  metSpriteDebugFlagsLatched;
  reg  [7:0]  metSpriteDebugColorLatched;
  reg  [7:0]  metSpriteDebugMixLatched;
  reg  [63:0] spriteProcessorDebugLatched;
  wire        debugVideoVBlankRising = io_video_vBlank & ~debugVideoVBlankReg;
  wire        debugOutputBright =
    (|videoRgb888[23:21]) |
    (|videoRgb888[15:13]) |
    (|videoRgb888[7:5]);
  wire [7:0]  debugRgbCompact = {videoRgb888[23:21], videoRgb888[15:13], videoRgb888[7:6]};
  wire [8:0]  debugMidX = {1'b0, io_video_regs_size_x[8:1]};
  wire [8:0]  debugLeftX = {2'b00, io_video_regs_size_x[8:2]};
  wire [8:0]  debugRightX = debugMidX + debugLeftX;
  wire [8:0]  debugTopY = 9'h008;
  wire [8:0]  debugMidY = {1'b0, io_video_regs_size_y[8:1]};
  wire        debugTopSamplePixel =
    activeDisplayPixel &
    (io_video_pos_y == debugTopY) &
    (io_video_pos_x == debugMidX);
  wire        debugMidSamplePixel =
    activeDisplayPixel &
    (io_video_pos_y == debugMidY) &
    (io_video_pos_x == debugMidX);
  wire        debugMidLeftSamplePixel =
    activeDisplayPixel &
    (io_video_pos_y == debugMidY) &
    (io_video_pos_x == debugLeftX);
  wire        debugMidRightSamplePixel =
    activeDisplayPixel &
    (io_video_pos_y == debugMidY) &
    (io_video_pos_x == debugRightX);
  wire        debugMidUniform =
    debugMidSampleValid &
    debugMidLeftSampleValid &
    debugMidRightSampleValid &
    (debugMidRgbFrame == debugMidLeftRgbFrame) &
    (debugMidRgbFrame == debugMidRightRgbFrame);
  wire        debugTopVsMidMismatch =
    debugTopSampleValid &
    debugMidUniform &
    (debugTopRgbFrame != debugMidRgbFrame);
  wire        debugTopMatchesPrevMid =
    debugTopVsMidMismatch & (debugTopRgbFrame == debugPrevMidRgb);
  wire [23:0] debugFillRgb =
    (io_video_pos_x[3] ^ io_video_pos_y[3]) ? 24'h181818 : 24'h080808;
  wire [7:0] debugLayer2LowRgb = {debugLayer2ColorReg[3:0], debugLayer2ColorReg[3:0]};
  wire [7:0] debugLayer2HighRgb = {debugLayer2ColorReg[5:4], debugLayer2ColorReg[5:4],
                                   debugLayer2ColorReg[5:4], debugLayer2ColorReg[5:4]};
  wire [23:0] debugLayer2PenRgb =
    debugLayer2VisibleReg
      ? {
          debugLayer2LowRgb,
          debugLayer2HighRgb,
          debugLayer2PriorityReg, debugLayer2PriorityReg,
          debugLayer2PriorityReg, debugLayer2PriorityReg
        }
      : debugFillRgb;
  wire        metSpriteDebugSamplePixel =
    io_gameConfig_metmqstrRenderCrop &
    activeDisplayPixel &
    (io_video_pos_x >= 9'd48) &
    (io_video_pos_x <= 9'd340) &
    (io_video_pos_y >= 9'd48) &
    (io_video_pos_y <= 9'd236);
  wire        metSpriteDebugHasSprite = |spritePenColor;
  wire        metSpriteDebugHasLayer0 = |layer0PenColor;
  wire        metSpriteDebugHasLayer1 = |layer1PenColor;
  wire        metSpriteDebugHasLayer2 = |layer2PenColor;
  wire        metSpriteDebugHasTile =
    metSpriteDebugHasLayer0 | metSpriteDebugHasLayer1 | metSpriteDebugHasLayer2;
  wire        metSpriteDebugHasAnySource = metSpriteDebugHasSprite | metSpriteDebugHasTile;
  wire        metSpriteDebugHasPortraitCandidate =
    metSpriteDebugHasSprite | metSpriteDebugHasLayer1 | metSpriteDebugHasLayer2;
  wire        metSpriteDebugSpriteSelected = mixerDebugSelectedPen[0];
  wire        metSpriteDebugLayer0Selected = mixerDebugSelectedPen[1];
  wire        metSpriteDebugLayer1Selected = mixerDebugSelectedPen[2];
  wire        metSpriteDebugLayer2Selected = mixerDebugSelectedPen[3];
  wire        metSpriteDebugSpriteHiddenByTile =
    metSpriteDebugHasSprite & ~metSpriteDebugSpriteSelected & metSpriteDebugHasTile;
  wire        metSpriteDebugLayer0OverCandidate =
    metSpriteDebugLayer0Selected & metSpriteDebugHasPortraitCandidate;
  wire [7:0]  metSpriteDebugSelectedColor =
    metSpriteDebugSpriteSelected ? spritePenColor :
    metSpriteDebugLayer0Selected ? layer0PenColor :
    metSpriteDebugLayer1Selected ? layer1PenColor :
    metSpriteDebugLayer2Selected ? layer2PenColor :
                                   8'h00;
  wire [23:0] metSpriteDebugSourceRgb =
    metSpriteDebugHasSprite ? 24'h00ff00 :
    metSpriteDebugHasLayer1 ? 24'h2080ff :
    metSpriteDebugHasLayer2 ? 24'hff20ff :
    metSpriteDebugHasLayer0 ? 24'h202020 :
                              24'h000000;
  wire [63:0] debugStandardVideo = {
    debugFlashMismatchHistory,
    debugTopPaletteAddrLatched,
    debugTopPaletteColorLatched,
    debugTopMixLatched,
    debugPrevMidRgbLatched,
    debugMidRgbLatched,
    debugTopRgbLatched,
    debugFlashFlagsLatched
  };
  wire [63:0] debugMetSpriteVideo = {
    metSpriteDebugMixLatched,
    metSpriteDebugColorLatched,
    metSpriteDebugFlagsLatched,
    spriteProcessorDebugLatched[63:56],
    spriteProcessorDebugLatched[55:48],
    spriteProcessorDebugLatched[47:40],
    spriteProcessorDebugLatched[15:8],
    spriteProcessorDebugLatched[7:0]
  };
`endif

  always @(posedge clock) begin
    if (reset) begin
      ssCanonicalRequestReg <= 1'b0;
      ssCanonicalToggleSystem <= 1'b0;
      ssVideoWriterIdleSystem0 <= 1'b0;
      ssVideoWriterIdleSystem1 <= 1'b0;
      ssFrameBuiltSystem0 <= 1'b0;
      ssFrameBuiltSystem1 <= 1'b0;
    end
    else begin
      ssCanonicalRequestReg <= io_ss_canonicalize;
      if (io_ss_canonicalize & ~ssCanonicalRequestReg)
        ssCanonicalToggleSystem <= ~ssCanonicalToggleSystem;

      ssVideoWriterIdleSystem0 <= ssVideoWriterIdle;
      ssVideoWriterIdleSystem1 <= ssVideoWriterIdleSystem0;
      if (io_ss_canonicalize) begin
        ssFrameBuiltSystem0 <= 1'b0;
        ssFrameBuiltSystem1 <= 1'b0;
      end
      else begin
        ssFrameBuiltSystem0 <= ssFrameBuiltVideo;
        ssFrameBuiltSystem1 <= ssFrameBuiltSystem0;
      end
    end
  end

  always @(posedge io_videoClock) begin
    if (reset) begin
      ssHoldVideo0 <= 1'b0;
      ssHoldVideo1 <= 1'b0;
      ssCanonicalToggleVideo0 <= 1'b0;
      ssCanonicalToggleVideo1 <= 1'b0;
      ssCanonicalToggleVideoSeen <= 1'b0;
    end
    else begin
      ssHoldVideo0 <= io_ss_hold;
      ssHoldVideo1 <= ssHoldVideo0;
      ssCanonicalToggleVideo0 <= ssCanonicalToggleSystem;
      ssCanonicalToggleVideo1 <= ssCanonicalToggleVideo0;
      ssCanonicalToggleVideoSeen <= ssCanonicalToggleVideo1;
    end
  end

  always @(posedge io_videoClock) begin
    if (reset | ssVideoCanonicalPulse) begin
      systemFramebufferWrReg <= 1'b0;
      systemFramebufferAddrReg <= 18'd0;
      systemFramebufferDinReg <= 32'd0;
    end
    else begin
      systemFramebufferWrReg <= activeDisplayPixel;
      systemFramebufferAddrReg <= nextSystemFramebufferAddr;
      systemFramebufferDinReg <= {8'h00, maskedFramebufferRgb888};
    end
`ifdef CAVE_ENABLE_DEBUG_OVERLAY
    if (io_video_clockEnable) begin
      debugLayer2VisibleReg <= io_video_displayEnable & (|layer2PenColor);
      debugLayer2PriorityReg <= layer2PenPriority;
      debugLayer2PaletteReg <= layer2PenPalette;
      debugLayer2ColorReg <= layer2PenColor;
      debugVideoVBlankReg <= io_video_vBlank;

      if (reset) begin
        debugTopRgbFrame <= 8'h00;
        debugMidRgbFrame <= 8'h00;
        debugMidLeftRgbFrame <= 8'h00;
        debugMidRightRgbFrame <= 8'h00;
        debugPrevMidRgb <= 8'h00;
        debugTopMixFrame <= 8'h00;
        debugTopPaletteColorFrame <= 8'h00;
        debugTopPaletteAddrFrame <= 8'h00;
        debugTopSampleValid <= 1'b0;
        debugMidSampleValid <= 1'b0;
        debugMidLeftSampleValid <= 1'b0;
        debugMidRightSampleValid <= 1'b0;
        debugFlashFlagsLatched <= 8'h00;
        debugTopRgbLatched <= 8'h00;
        debugMidRgbLatched <= 8'h00;
        debugPrevMidRgbLatched <= 8'h00;
        debugTopMixLatched <= 8'h00;
        debugTopPaletteColorLatched <= 8'h00;
        debugTopPaletteAddrLatched <= 8'h00;
        debugFlashMismatchHistory <= 8'h00;
        metSpriteDebugFlags <= 8'h00;
        metSpriteDebugColor <= 8'h00;
        metSpriteDebugMix <= 8'h00;
        metSpriteDebugFlagsLatched <= 8'h00;
        metSpriteDebugColorLatched <= 8'h00;
        metSpriteDebugMixLatched <= 8'h00;
        spriteProcessorDebugLatched <= 64'h0000000000000000;
      end
      else if (debugVideoVBlankRising) begin
        metSpriteDebugFlagsLatched <= metSpriteDebugFlags;
        metSpriteDebugColorLatched <= metSpriteDebugColor;
        metSpriteDebugMixLatched <= metSpriteDebugMix;
        metSpriteDebugFlags <= 8'h00;
        metSpriteDebugColor <= 8'h00;
        metSpriteDebugMix <= 8'h00;
        spriteProcessorDebugLatched <= spriteProcessorDebug;
        debugFlashMismatchHistory <= {
          debugFlashMismatchHistory[6:0],
          debugTopVsMidMismatch
        };
        if (debugTopVsMidMismatch) begin
          debugFlashFlagsLatched <= {
            debugTopMatchesPrevMid,
            debugMidUniform,
            debugTopRgbFrame == debugMidRgbFrame,
            debugTopSampleValid,
            debugMidSampleValid,
            debugMidLeftSampleValid,
            debugMidRightSampleValid,
            1'b1
          };
          debugTopRgbLatched <= debugTopRgbFrame;
          debugMidRgbLatched <= debugMidRgbFrame;
          debugPrevMidRgbLatched <= debugPrevMidRgb;
          debugTopMixLatched <= debugTopMixFrame;
          debugTopPaletteColorLatched <= debugTopPaletteColorFrame;
          debugTopPaletteAddrLatched <= debugTopPaletteAddrFrame;
        end
        if (debugMidUniform)
          debugPrevMidRgb <= debugMidRgbFrame;
        debugTopRgbFrame <= 8'h00;
        debugMidRgbFrame <= 8'h00;
        debugMidLeftRgbFrame <= 8'h00;
        debugMidRightRgbFrame <= 8'h00;
        debugTopMixFrame <= 8'h00;
        debugTopPaletteColorFrame <= 8'h00;
        debugTopPaletteAddrFrame <= 8'h00;
        debugTopSampleValid <= 1'b0;
        debugMidSampleValid <= 1'b0;
        debugMidLeftSampleValid <= 1'b0;
        debugMidRightSampleValid <= 1'b0;
      end
      else begin
        if (debugTopSamplePixel & debugOutputBright) begin
          debugTopRgbFrame <= debugRgbCompact;
          debugTopMixFrame <= {mixerDebugSelectedPen, mixerDebugVisibleMask};
          debugTopPaletteColorFrame <= {mixerDebugSelectedPalette[3:0], mixerDebugSelectedColor[3:0]};
          debugTopPaletteAddrFrame <= io_paletteRam_addr[7:0];
          debugTopSampleValid <= 1'b1;
        end
        if (debugMidSamplePixel & debugOutputBright) begin
          debugMidRgbFrame <= debugRgbCompact;
          debugMidSampleValid <= 1'b1;
        end
        if (debugMidLeftSamplePixel & debugOutputBright) begin
          debugMidLeftRgbFrame <= debugRgbCompact;
          debugMidLeftSampleValid <= 1'b1;
        end
        if (debugMidRightSamplePixel & debugOutputBright) begin
          debugMidRightRgbFrame <= debugRgbCompact;
          debugMidRightSampleValid <= 1'b1;
        end
        if (metSpriteDebugSamplePixel) begin
          metSpriteDebugFlags[0] <= 1'b1;
          metSpriteDebugFlags[1] <= metSpriteDebugFlags[1] | metSpriteDebugHasSprite;
          metSpriteDebugFlags[2] <= metSpriteDebugFlags[2] | metSpriteDebugHasLayer0;
          metSpriteDebugFlags[3] <= metSpriteDebugFlags[3] | metSpriteDebugHasLayer1;
          metSpriteDebugFlags[4] <= metSpriteDebugFlags[4] | metSpriteDebugHasLayer2;
          metSpriteDebugFlags[5] <= metSpriteDebugFlags[5] | metSpriteDebugLayer0OverCandidate;
          metSpriteDebugFlags[7] <= metSpriteDebugFlags[7] | metSpriteDebugSpriteHiddenByTile;
          if (metSpriteDebugHasAnySource) begin
            metSpriteDebugFlags[6] <= metSpriteDebugFlags[6] | (|metSpriteDebugSelectedColor);
            metSpriteDebugColor <= metSpriteDebugSelectedColor;
            metSpriteDebugMix <= {mixerDebugSelectedPen, mixerDebugVisibleMask};
          end
        end
      end
    end
`endif
  end

  always @(posedge io_videoClock) begin
    if (reset | ssVideoCanonicalPulse) begin
      ssFrameHadWriteVideo <= 1'b0;
      ssFrameBuiltVideo <= 1'b0;
      ssVideoVBlankPrev <= io_video_vBlank;
    end
    else begin
      ssVideoVBlankPrev <= io_video_vBlank;
      if (ssHoldVideo1) begin
        ssFrameHadWriteVideo <= 1'b0;
        ssFrameBuiltVideo <= 1'b0;
      end
      else begin
        if (systemFramebufferWrReg)
          ssFrameHadWriteVideo <= 1'b1;
        if (io_video_vBlank & ~ssVideoVBlankPrev) begin
          ssFrameBuiltVideo <= ssFrameHadWriteVideo;
          ssFrameHadWriteVideo <= 1'b0;
        end
      end
    end
  end

  SpriteProcessor spriteProcessor (
    .clock                       (clock),
    .reset                       (reset | io_ss_canonicalize),
    .io_ctrl_enable              (io_spriteCtrl_enable),
    .io_ctrl_format              (io_spriteCtrl_format),
    .io_ctrl_start               (io_spriteCtrl_start & ~io_ss_hold),
    .io_ctrl_zoom                (io_spriteCtrl_zoom),
    .io_ctrl_regs_bank           (io_spriteCtrl_regs_bank),
    .io_ctrl_regs_fixed          (io_spriteCtrl_regs_fixed),
    .io_ctrl_regs_hFlip          (io_spriteCtrl_regs_hFlip),
    .io_ctrl_vram_rd             (io_spriteCtrl_vram_rd),
    .io_ctrl_vram_addr           (io_spriteCtrl_vram_addr),
    .io_ctrl_vram_dout           (io_spriteCtrl_vram_dout),
    .io_ctrl_tileRom_rd          (io_spriteCtrl_tileRom_rd),
    .io_ctrl_tileRom_addr        (io_spriteCtrl_tileRom_addr),
    .io_ctrl_tileRom_dout        (io_spriteCtrl_tileRom_dout),
    .io_ctrl_tileRom_wait_n      (io_spriteCtrl_tileRom_wait_n),
    .io_ctrl_tileRom_valid       (io_spriteCtrl_tileRom_valid),
    .io_ctrl_tileRom_burstLength (io_spriteCtrl_tileRom_burstLength),
    .io_ctrl_tileRom_burstDone   (io_spriteCtrl_tileRom_burstDone),
    .io_video_regs_size_x        (renderVideoSizeX),
    .io_video_regs_size_y        (io_video_regs_size_y),
    .io_frameBuffer_wr           (io_spriteFrameBuffer_wr),
    .io_frameBuffer_addr         (io_spriteFrameBuffer_addr),
    .io_frameBuffer_din          (io_spriteFrameBuffer_din),
    .io_frameBuffer_wait_n       (io_spriteFrameBuffer_wait_n),
    .io_ctrl_frameReady          (io_spriteCtrl_frameReady),
    .io_ss_idle                  (spriteProcessorIdle),
    .io_debug                    (spriteProcessorDebug)
  );

  CaveLayerProcessor #(
    .LAYER_OFFSET_LARGE (5'h12),
    .LAYER_OFFSET_SMALL (5'h0A)
  ) layerProcessor_0 (
    .clock                        (io_videoClock),
    .io_ctrl_enable               (io_layerCtrl_0_enable & ssVideoRenderEnable),
    .io_ctrl_format               (io_layerCtrl_0_format),
    .io_ctrl_regs_tileSize        (io_layerCtrl_0_regs_tileSize),
    .io_ctrl_regs_enable          (io_layerCtrl_0_regs_enable),
    .io_ctrl_regs_flipX           (io_layerCtrl_0_regs_flipX),
    .io_ctrl_regs_flipY           (io_layerCtrl_0_regs_flipY),
    .io_ctrl_regs_rowScrollEnable (io_layerCtrl_0_regs_rowScrollEnable),
    .io_ctrl_regs_rowSelectEnable (io_layerCtrl_0_regs_rowSelectEnable),
    .io_ctrl_regs_scroll_x        (io_layerCtrl_0_regs_scroll_x),
    .io_ctrl_regs_scroll_y        (io_layerCtrl_0_regs_scroll_y),
    .io_ctrl_vram8x8_addr         (io_layerCtrl_0_vram8x8_addr),
    .io_ctrl_vram8x8_dout         (io_layerCtrl_0_vram8x8_dout),
    .io_ctrl_vram16x16_addr       (io_layerCtrl_0_vram16x16_addr),
    .io_ctrl_vram16x16_dout       (io_layerCtrl_0_vram16x16_dout),
    .io_ctrl_lineRam_addr         (io_layerCtrl_0_lineRam_addr),
    .io_ctrl_lineRam_dout         (io_layerCtrl_0_lineRam_dout),
    .io_ctrl_tileRom_rd           (io_layerCtrl_0_tileRom_rd),
    .io_ctrl_tileRom_addr         (io_layerCtrl_0_tileRom_addr),
    .io_ctrl_tileRom_dout         (io_layerCtrl_0_tileRom_dout),
    .io_video_clockEnable         (io_video_clockEnable),
    .io_video_pos_x               (renderVideoPosX),
    .io_video_pos_y               (io_video_pos_y),
    .io_video_vBlank              (io_video_vBlank),
    .io_video_regs_size_x         (renderVideoSizeX),
    .io_video_regs_size_y         (io_video_regs_size_y),
    .io_spriteOffset_x            (io_spriteCtrl_regs_offset_x),
    .io_spriteOffset_y            (io_spriteCtrl_regs_offset_y),
    .io_direct6bppPixels          (1'b0),
    .io_sailorMoonTilebank        (1'b0),
    .io_pen_priority              (layer0PenPriority),
    .io_pen_palette               (layer0PenPalette),
    .io_pen_color                 (layer0PenColor)
  );

  CaveLayerProcessor #(
    .LAYER_OFFSET_LARGE (5'h11),
    .LAYER_OFFSET_SMALL (5'h09)
  ) layerProcessor_1 (
    .clock                        (io_videoClock),
    .io_ctrl_enable               (io_layerCtrl_1_enable & ssVideoRenderEnable),
    .io_ctrl_format               (io_layerCtrl_1_format),
    .io_ctrl_regs_tileSize        (io_layerCtrl_1_regs_tileSize),
    .io_ctrl_regs_enable          (io_layerCtrl_1_regs_enable),
    .io_ctrl_regs_flipX           (io_layerCtrl_1_regs_flipX),
    .io_ctrl_regs_flipY           (io_layerCtrl_1_regs_flipY),
    .io_ctrl_regs_rowScrollEnable (io_layerCtrl_1_regs_rowScrollEnable),
    .io_ctrl_regs_rowSelectEnable (io_layerCtrl_1_regs_rowSelectEnable),
    .io_ctrl_regs_scroll_x        (io_layerCtrl_1_regs_scroll_x),
    .io_ctrl_regs_scroll_y        (io_layerCtrl_1_regs_scroll_y),
    .io_ctrl_vram8x8_addr         (io_layerCtrl_1_vram8x8_addr),
    .io_ctrl_vram8x8_dout         (io_layerCtrl_1_vram8x8_dout),
    .io_ctrl_vram16x16_addr       (io_layerCtrl_1_vram16x16_addr),
    .io_ctrl_vram16x16_dout       (io_layerCtrl_1_vram16x16_dout),
    .io_ctrl_lineRam_addr         (io_layerCtrl_1_lineRam_addr),
    .io_ctrl_lineRam_dout         (io_layerCtrl_1_lineRam_dout),
    .io_ctrl_tileRom_rd           (io_layerCtrl_1_tileRom_rd),
    .io_ctrl_tileRom_addr         (io_layerCtrl_1_tileRom_addr),
    .io_ctrl_tileRom_dout         (io_layerCtrl_1_tileRom_dout),
    .io_video_clockEnable         (io_video_clockEnable),
    .io_video_pos_x               (renderVideoPosX),
    .io_video_pos_y               (io_video_pos_y),
    .io_video_vBlank              (io_video_vBlank),
    .io_video_regs_size_x         (renderVideoSizeX),
    .io_video_regs_size_y         (io_video_regs_size_y),
    .io_spriteOffset_x            (io_spriteCtrl_regs_offset_x),
    .io_spriteOffset_y            (io_spriteCtrl_regs_offset_y),
    .io_direct6bppPixels          (1'b0),
    .io_sailorMoonTilebank        (1'b0),
    .io_pen_priority              (layer1PenPriority),
    .io_pen_palette               (layer1PenPalette),
    .io_pen_color                 (layer1PenColor)
  );

  CaveLayerProcessor #(
    .LAYER_OFFSET_LARGE (5'h10),
    .LAYER_OFFSET_SMALL (5'h08)
  ) layerProcessor_2 (
    .clock                        (io_videoClock),
    .io_ctrl_enable               (io_layerCtrl_2_enable & ssVideoRenderEnable),
    .io_ctrl_format               (io_layerCtrl_2_format),
    .io_ctrl_regs_tileSize        (io_layerCtrl_2_regs_tileSize),
    .io_ctrl_regs_enable          (io_layerCtrl_2_regs_enable),
    .io_ctrl_regs_flipX           (io_layerCtrl_2_regs_flipX),
    .io_ctrl_regs_flipY           (io_layerCtrl_2_regs_flipY),
    .io_ctrl_regs_rowScrollEnable (io_layerCtrl_2_regs_rowScrollEnable),
    .io_ctrl_regs_rowSelectEnable (io_layerCtrl_2_regs_rowSelectEnable),
    .io_ctrl_regs_scroll_x        (io_layerCtrl_2_regs_scroll_x),
    .io_ctrl_regs_scroll_y        (io_layerCtrl_2_regs_scroll_y),
    .io_ctrl_vram8x8_addr         (io_layerCtrl_2_vram8x8_addr),
    .io_ctrl_vram8x8_dout         (io_layerCtrl_2_vram8x8_dout),
    .io_ctrl_vram16x16_addr       (io_layerCtrl_2_vram16x16_addr),
    .io_ctrl_vram16x16_dout       (io_layerCtrl_2_vram16x16_dout),
    .io_ctrl_lineRam_addr         (io_layerCtrl_2_lineRam_addr),
    .io_ctrl_lineRam_dout         (io_layerCtrl_2_lineRam_dout),
    .io_ctrl_tileRom_rd           (io_layerCtrl_2_tileRom_rd),
    .io_ctrl_tileRom_addr         (io_layerCtrl_2_tileRom_addr),
    .io_ctrl_tileRom_dout         (io_layerCtrl_2_tileRom_dout),
    .io_video_clockEnable         (io_video_clockEnable),
    .io_video_pos_x               (renderVideoPosX),
    .io_video_pos_y               (io_video_pos_y),
    .io_video_vBlank              (io_video_vBlank),
    .io_video_regs_size_x         (renderVideoSizeX),
    .io_video_regs_size_y         (io_video_regs_size_y),
    .io_spriteOffset_x            (io_spriteCtrl_regs_offset_x),
    .io_spriteOffset_y            (io_spriteCtrl_regs_offset_y),
    .io_direct6bppPixels          (io_gameConfig_airLayer2Direct6bpp),
    .io_sailorMoonTilebank        (sailorMoonTilebankSync1),
    .io_pen_priority              (layer2PenPriority),
    .io_pen_palette               (layer2PenPalette),
    .io_pen_color                 (layer2PenColor)
  );

  ColorMixer colorMixer (
    .clock                             (io_videoClock),
    .io_gameConfig_granularity         (io_gameConfig_granularity),
    .io_gameConfig_layer_0_format      (io_layerCtrl_0_format),
    .io_gameConfig_layer_0_paletteBank (io_gameConfig_layer_0_paletteBank),
    .io_gameConfig_layer_1_format      (io_layerCtrl_1_format),
    .io_gameConfig_layer_1_paletteBank (io_gameConfig_layer_1_paletteBank),
    .io_gameConfig_layer_2_format      (io_layerCtrl_2_format),
    .io_gameConfig_layer_2_paletteBank (io_gameConfig_layer_2_paletteBank),
    .io_gameConfig_useLayerPriority    (io_gameConfig_metmqstrRenderCrop),
    .io_gameConfig_opaqueForegroundZero(1'b0),
    .io_gameConfig_redFill             (1'b0),
    .io_spritePen_priority             (spritePenPriority),
    .io_spritePen_palette              (spritePenPalette),
    .io_spritePen_color                (spritePenColor),
    .io_layer0_layerPriority           (io_layerCtrl_0_regs_priority),
    .io_layer0Pen_priority             (layer0PenPriority),
    .io_layer0Pen_palette              (layer0PenPalette),
    .io_layer0Pen_color                (layer0PenColor),
    .io_layer1_layerPriority           (io_layerCtrl_1_regs_priority),
    .io_layer1Pen_priority             (layer1PenPriority),
    .io_layer1Pen_palette              (layer1PenPalette),
    .io_layer1Pen_color                (layer1PenColor),
    .io_layer1Pen_opaqueZeroEnable     (io_layerCtrl_1_enable & io_layerCtrl_1_regs_enable & (|io_layerCtrl_1_format)),
    .io_layer2_layerPriority           (io_layerCtrl_2_regs_priority),
    .io_layer2Pen_priority             (layer2PenPriority),
    .io_layer2Pen_palette              (layer2PenPalette),
    .io_layer2Pen_color                (layer2PenColor),
    .io_layer2Pen_opaqueZeroEnable     (io_layerCtrl_2_enable & io_layerCtrl_2_regs_enable & (|io_layerCtrl_2_format)),
    .io_paletteRam_addr                (io_paletteRam_addr),
    .io_paletteRam_dout                (io_paletteRam_dout),
    .io_dout                           (paletteColor)
`ifdef CAVEBANPRESTO_MET_SPRITE_PAGE_HW_DIAGNOSTIC
    ,
    .io_met_sprite_diag_spriteBeatsTiles (
      io_met_sprite_diag_mixerSpriteWins
    )
`endif
`ifdef CAVE_ENABLE_DEBUG_OVERLAY
    ,
    .io_debug_selectedPen              (mixerDebugSelectedPen),
    .io_debug_selectedPalette          (mixerDebugSelectedPalette),
    .io_debug_selectedColor            (mixerDebugSelectedColor),
    .io_debug_visibleMask              (mixerDebugVisibleMask)
`endif
  );

  assign io_spriteLineBuffer_addr = renderVideoPosX;
  assign io_systemFrameBuffer_wr = systemFramebufferWrReg;
  assign io_systemFrameBuffer_addr = systemFramebufferAddrReg[16:0];
  assign io_systemFrameBuffer_din = systemFramebufferDinReg;
`ifdef CAVEBANPRESTO_MET_SPRITE_PAGE_HW_DIAGNOSTIC
  assign io_rgb = metSpriteDiagOverlayValidReg
    ? metSpriteDiagOverlayRgbReg : maskedVideoRgb888;
`else
  assign io_rgb = maskedVideoRgb888;
`endif
  assign io_ss_idle = spriteProcessorIdle & ssVideoWriterIdleSystem1;
  assign io_ss_reconstruction_ready =
    io_spriteCtrl_frameReady & ssFrameBuiltSystem1;
`ifdef CAVE_ENABLE_DEBUG_OVERLAY
  assign io_debug_video = io_gameConfig_metmqstrRenderCrop ? debugMetSpriteVideo : debugStandardVideo;
  assign io_debug_readout = io_debug_video;
  assign io_debug_source_rgb =
    io_video_displayEnable
      ? (io_gameConfig_metmqstrRenderCrop ? metSpriteDebugSourceRgb : debugLayer2PenRgb)
      : 24'h000000;
`endif
endmodule
