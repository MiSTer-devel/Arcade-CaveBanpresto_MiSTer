// This file is a Codex-assisted rewrite based on the original work of
// Josh Bassett (nullobject).

// Main owns the 68k-facing Banpresto/Z80 board logic: per-game CPU memory
// maps, input packing, IRQs, EEPROM serial pins, pause, and video-domain
// register mirrors.
module Main(
  input          clock,
  input          reset,
  input          io_systemClock,
  input          io_systemReset,
  input          io_videoClock,
  input          io_spriteClock,
  input  [3:0]   io_gameIndex,
  input          io_options_service,
  input          io_player_0_up,
  input          io_player_0_down,
  input          io_player_0_left,
  input          io_player_0_right,
  input  [3:0]   io_player_0_buttons,
  input          io_player_0_start,
  input          io_player_0_coin,
  input          io_player_0_pause,
  input          io_player_1_up,
  input          io_player_1_down,
  input          io_player_1_left,
  input          io_player_1_right,
  input  [3:0]   io_player_1_buttons,
  input          io_player_1_start,
  input          io_player_1_coin,
  input          io_player_1_pause,
  input  [15:0]  io_dips_0,
  input          io_video_vBlank,
  output         io_gpuMem_layer_0_regs_tileSize,
  output         io_gpuMem_layer_0_regs_enable,
  output         io_gpuMem_layer_0_regs_flipX,
  output         io_gpuMem_layer_0_regs_flipY,
  output         io_gpuMem_layer_0_regs_rowScrollEnable,
  output         io_gpuMem_layer_0_regs_rowSelectEnable,
  output [1:0]   io_gpuMem_layer_0_regs_priority,
  output [8:0]   io_gpuMem_layer_0_regs_scroll_x,
  output [8:0]   io_gpuMem_layer_0_regs_scroll_y,
  input  [11:0]  io_gpuMem_layer_0_vram8x8_addr,
  output [31:0]  io_gpuMem_layer_0_vram8x8_dout,
  input  [9:0]   io_gpuMem_layer_0_vram16x16_addr,
  output [31:0]  io_gpuMem_layer_0_vram16x16_dout,
  input  [8:0]   io_gpuMem_layer_0_lineRam_addr,
  output [31:0]  io_gpuMem_layer_0_lineRam_dout,
  output         io_gpuMem_layer_1_regs_tileSize,
  output         io_gpuMem_layer_1_regs_enable,
  output         io_gpuMem_layer_1_regs_flipX,
  output         io_gpuMem_layer_1_regs_flipY,
  output         io_gpuMem_layer_1_regs_rowScrollEnable,
  output         io_gpuMem_layer_1_regs_rowSelectEnable,
  output [1:0]   io_gpuMem_layer_1_regs_priority,
  output [8:0]   io_gpuMem_layer_1_regs_scroll_x,
  output [8:0]   io_gpuMem_layer_1_regs_scroll_y,
  input  [11:0]  io_gpuMem_layer_1_vram8x8_addr,
  output [31:0]  io_gpuMem_layer_1_vram8x8_dout,
  input  [9:0]   io_gpuMem_layer_1_vram16x16_addr,
  output [31:0]  io_gpuMem_layer_1_vram16x16_dout,
  input  [8:0]   io_gpuMem_layer_1_lineRam_addr,
  output [31:0]  io_gpuMem_layer_1_lineRam_dout,
  output         io_gpuMem_layer_2_regs_tileSize,
  output         io_gpuMem_layer_2_regs_enable,
  output         io_gpuMem_layer_2_regs_flipX,
  output         io_gpuMem_layer_2_regs_flipY,
  output         io_gpuMem_layer_2_regs_rowScrollEnable,
  output         io_gpuMem_layer_2_regs_rowSelectEnable,
  output [1:0]   io_gpuMem_layer_2_regs_priority,
  output [8:0]   io_gpuMem_layer_2_regs_scroll_x,
  output [8:0]   io_gpuMem_layer_2_regs_scroll_y,
  input  [11:0]  io_gpuMem_layer_2_vram8x8_addr,
  output [31:0]  io_gpuMem_layer_2_vram8x8_dout,
  input  [9:0]   io_gpuMem_layer_2_vram16x16_addr,
  output [31:0]  io_gpuMem_layer_2_vram16x16_dout,
  input  [8:0]   io_gpuMem_layer_2_lineRam_addr,
  output [31:0]  io_gpuMem_layer_2_lineRam_dout,
  output [8:0]   io_gpuMem_sprite_regs_offset_x,
  output [8:0]   io_gpuMem_sprite_regs_offset_y,
  output [1:0]   io_gpuMem_sprite_regs_bank,
  output         io_gpuMem_sprite_regs_fixed,
  output         io_gpuMem_sprite_regs_hFlip,
  input          io_gpuMem_sprite_vram_rd,
  input  [11:0]  io_gpuMem_sprite_vram_addr,
  output [127:0] io_gpuMem_sprite_vram_dout,
  input  [14:0]  io_gpuMem_paletteRam_addr,
  output [15:0]  io_gpuMem_paletteRam_dout,
  output         io_soundCtrl_oki_0_wr,
  output [15:0]  io_soundCtrl_oki_0_din,
  input  [15:0]  io_soundCtrl_oki_0_dout,
  output         io_soundCtrl_oki_1_wr,
  output [15:0]  io_soundCtrl_oki_1_din,
  input  [15:0]  io_soundCtrl_oki_1_dout,
  output         io_soundCtrl_nmk_wr,
  output [22:0]  io_soundCtrl_nmk_addr,
  output [15:0]  io_soundCtrl_nmk_din,
  output         io_soundCtrl_ymz_rd,
  output         io_soundCtrl_ymz_wr,
  output [22:0]  io_soundCtrl_ymz_addr,
  output [15:0]  io_soundCtrl_ymz_din,
  input  [15:0]  io_soundCtrl_ymz_dout,
  output         io_soundCtrl_req,
  output [15:0]  io_soundCtrl_data,
  output         io_soundCtrl_reply_rd,
  input  [15:0]  io_soundCtrl_reply,
  input          io_soundCtrl_reply_empty,
  input          io_soundCtrl_irq,
  output         io_progRom_rd,
  output [21:0]  io_progRom_addr,
  input  [15:0]  io_progRom_dout,
  input          io_progRom_valid,
  output         io_eeprom_rd,
  output         io_eeprom_wr,
  output [6:0]   io_eeprom_addr,
  output [15:0]  io_eeprom_din,
  input  [15:0]  io_eeprom_dout,
  input          io_eeprom_wait_n,
  input          io_eeprom_valid,
  input          io_hs_config_download,
  input          io_hs_config_wr,
  input  [26:0]  io_hs_config_addr,
  input  [15:0]  io_hs_config_dout,
  input  [3:0]   io_hs_game_index_sys,
  input          io_hs_nvram_download,
  input          io_hs_nvram_upload,
  input          io_hs_nvram_rd,
  input          io_hs_nvram_wr,
  input  [26:0]  io_hs_nvram_addr,
  input  [15:0]  io_hs_nvram_dout,
  output [15:0]  io_hs_nvram_din,
  output         io_hs_nvram_wait_n,
  output         io_hs_dirty,
  output         io_hs_active,
  input          io_ss_command_valid,
  input  [15:0]  io_ss_command,
  output         io_ss_command_complete,
  output [7:0]   io_ss_command_response,
  output         io_ss_command_terminal_fault,
  input          io_ss_release_request,
  input          io_ss_release_restore,
  output         io_ss_stopped,
  output         io_ss_abort_ack,
  output         io_ss_release_complete,
  input          io_ss_state_enable,
  input          io_ss_restore_enable,
  input          io_ss_restore_begin,
  input          io_ss_restore_commit,
  input          io_ss_cpu_capture_req,
  input          io_ss_cpu_restore_begin,
  input          io_ss_cpu_restore_commit,
  input          io_ss_cpu_abort,
  output         io_ss_cpu_captured,
  output         io_ss_cpu_restore_committed,
  output         io_ss_cpu_abort_ack,
  output         io_ss_cpu_terminal_fault,
  input          io_ss_cpu_idle,
  input          io_ss_render_idle,
  input  [47:0]  io_ss_runtime_support,
  output         io_ss_control_idle,
  output         io_ss_control_restore_committed,
  output         io_ss_control_terminal_fault,
  output         io_ss_ram_idle,
  output         io_ss_ram_terminal_fault,
  output         io_ss_ram_takeover_active,
  output         io_ss_ram_blocked_access,
  input  [127:0] io_ss_video_register_state,
  input  [3:0]   io_ss_config_offset_x,
  input  [3:0]   io_ss_config_offset_y,
  input          io_ss_config_rotate,
  input          io_ss_config_compatibility,
  input          io_ss_config_layer0_enable,
  input          io_ss_config_layer1_enable,
  input          io_ss_config_layer2_enable,
  input          io_ss_config_sprite_enable,
  input          io_ss_config_flip_video,
  input  [3:0]   io_ss_config_psg_boost,
  input  [3:0]   io_ss_config_fm_boost,
  input  [3:0]   io_ss_config_oki0_boost,
  input  [3:0]   io_ss_config_oki1_boost,
  output         io_ss_register_idle,
  output         io_ss_register_restore_committed,
  output         io_ss_register_terminal_fault,
  output         io_ss_register_restore_load,
  input          io_ss_register_restore_applied,
  input          io_ss_register_restore_bridge_fault,
  output [127:0] io_ss_video_register_restore_state,
  output [15:0]  io_ss_dip_register_restore_state,
  output         io_ss_eeprom_idle,
  output         io_ss_eeprom_restore_committed,
  output         io_ss_eeprom_terminal_fault,
  cavebanpresto_ssbus_if.responder io_ss_cpu_bus,
  cavebanpresto_ssbus_if.responder io_ss_control_bus,
  cavebanpresto_ssbus_if.responder io_ss_register_bus,
  cavebanpresto_ssbus_if.responder io_ss_eeprom_bus,
  cavebanpresto_ssbus_if.responder io_ss_ram_bus,
  output         io_sailorMoonTilebank,
  output         io_spriteFrameBufferSwap,
`ifdef CAVEBANPRESTO_SS_RELEASE_SLIM_HW_DIAGNOSTIC
  output reg     io_ss_capture_admitted_seen,
`endif
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
  output         io_ss_release_eligible,
  output [3:0]   io_ss_release_owner_idle,
  output [1:0]   io_ss_release_detail,
  output [4:0]   io_ss_release_state,
  output [31:0]  io_ss_release_fault_debug,
`endif
  output [63:0] io_debug_pipeline,
  output [63:0] io_debug_cpu,
  output [63:0] io_debug_writes,
  output [63:0] io_debug_data,
  output [63:0] io_debug_live,
  output [63:0] io_debug_palette
);


  localparam [3:0] GAME_HOTDOGST = 4'h0;
  localparam [3:0] GAME_MAZINGER = 4'h1;
  localparam [3:0] GAME_AGALLET  = 4'h2;
  localparam [3:0] GAME_SAILORMN = 4'h3;
  localparam [3:0] GAME_METMQSTR = 4'h4;

  wire        gameIsHotdogStorm = io_gameIndex == GAME_HOTDOGST;
  wire        gameIsMazinger = io_gameIndex == GAME_MAZINGER;
  wire        gameIsAirGallet = io_gameIndex == GAME_AGALLET;
  wire        gameIsSailorMoon = io_gameIndex == GAME_SAILORMN;
  wire        gameIsMetmqstr = io_gameIndex == GAME_METMQSTR;
  wire        gameIsAirFamily = gameIsAirGallet | gameIsSailorMoon;

  // Owners 4-19 are the complete Main mutable-RAM group.  The local profile
  // mask independently enforces physical presence in addition to the global
  // metadata/runtime mask:
  //   Hotdog: 4, 9-19
  //   Mazinger: 4, 9-11, 14
  //   Air Gallet/Sailor Moon: 4-19
  //   Metamoqester: 9-19
  localparam [47:0] SS_RAM_COMPILED_SUPPORT =
    48'h0000_000F_FFF0;
  wire [15:0] ssGameRamSupport =
    gameIsHotdogStorm ? 16'hFFE1 :
    gameIsMazinger    ? 16'h04E1 :
    gameIsAirFamily   ? 16'hFFFF :
    gameIsMetmqstr    ? 16'hFFE0 :
                        16'h0000;
  wire [47:0] ssRamRuntimeSupport =
    io_ss_runtime_support & {28'd0, ssGameRamSupport, 4'd0};

  // The held command endpoint is the sole authority for Main save-state
  // control.  The legacy scalar command inputs remain at this integration
  // boundary only until the parent coordinator is migrated.
  wire mainStateHold;
  wire mainRestoreEnable;
  wire mainRestoreBegin;
  wire mainCpuCaptureRequest;
  wire mainCpuCaptureRequestToCpu;
  wire mainCpuFinalRestoreCommit;
  wire mainCpuAbort;
  wire mainOwner3RestoreCommit;
  wire mainOwner20RestoreCommit;
  wire mainOwner22RestoreCommit;
  wire mainNoncpuOwnerReset;
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
  localparam [4:0] SS_MAIN_COMMAND_RELEASE_WAIT = 5'd20;
  wire [4:0] mainCommandStateDebug;
  wire [31:0] mainCommandFaultDebug;
`endif
  wire mainNoncpuOwnerResetWire = reset | mainNoncpuOwnerReset;

  wire ssRamTakeoverPermitted =
    mainStateHold & io_ss_cpu_captured & io_ss_render_idle;
  wire mainControlStateHold =
    (mainStateHold === 1'b1) &&
    (io_ss_cpu_captured === 1'b1);
  wire mainRegisterStateHold =
    (mainStateHold === 1'b1) &&
    (io_ss_cpu_captured === 1'b1) &&
    (io_ss_render_idle === 1'b1);

  cavebanpresto_ssbus_if mainRamOwnerBus [16] ();
  wire [15:0] ssRamTakeover;
  wire [15:0] ssRamBlockedNormalAccess;
  wire        ssRamBusMultipleAck;
  wire        ssRamBusTimeout;
  wire        ssRamBusFault;
  wire        ssRamBusIdle;
  reg         ssRamSafetyFault;

  wire [1:0]  _spriteRegs_io_mem_mask;
  wire [15:0] _spriteRegs_io_regs_0;
  wire [15:0] _spriteRegs_io_regs_1;
  wire [15:0] _spriteRegs_io_regs_4;
  wire [15:0] _spriteRegs_io_regs_5;
  wire [1:0]  _layerRegs_2_io_mem_addr;
  wire [15:0] _layerRegs_2_io_mem_dout;
  wire [15:0] _layerRegs_2_io_regs_0;
  wire [15:0] _layerRegs_2_io_regs_1;
  wire [15:0] _layerRegs_2_io_regs_2;
  wire [1:0]  _layerRegs_1_io_mem_addr;
  wire [15:0] _layerRegs_1_io_mem_dout;
  wire [15:0] _layerRegs_1_io_regs_0;
  wire [15:0] _layerRegs_1_io_regs_1;
  wire [15:0] _layerRegs_1_io_regs_2;
  wire [1:0]  _layerRegs_0_io_mem_addr;
  wire [15:0] _layerRegs_0_io_mem_dout;
  wire [15:0] _layerRegs_0_io_regs_0;
  wire [15:0] _layerRegs_0_io_regs_1;
  wire [15:0] _layerRegs_0_io_regs_2;
  wire [15:0] _paletteRam_io_portA_dout;
  wire [9:0]  _lineRam_2_io_portA_addr;
  wire [15:0] _lineRam_2_io_portA_dout;
  wire [9:0]  _lineRam_1_io_portA_addr;
  wire [15:0] _lineRam_1_io_portA_dout;
  wire [9:0]  _lineRam_0_io_portA_addr;
  wire [15:0] _lineRam_0_io_portA_dout;
  wire [10:0] _vram16x16_2_io_portA_addr;
  wire [15:0] _vram16x16_2_io_portA_dout;
  wire [10:0] _vram16x16_1_io_portA_addr;
  wire [15:0] _vram16x16_1_io_portA_dout;
  wire [10:0] _vram16x16_0_io_portA_addr;
  wire [15:0] _vram16x16_0_io_portA_dout;
  wire [15:0] _vram8x8_2_io_portA_dout;
  wire [12:0] _vram8x8_1_io_portA_addr;
  wire [15:0] _vram8x8_1_io_portA_dout;
  wire [12:0] _vram8x8_0_io_portA_addr;
  wire [15:0] _vram8x8_0_io_portA_dout;
  wire [14:0] _spriteRam_io_portA_addr;
  wire [15:0] _spriteRam_io_portA_dout;
  wire [14:0] _mainRam_io_addr;
  wire [15:0] _mainRam_io_dout;
  wire        _eeprom_io_serial_sdo;
  wire        _cpu_io_vpa;
  wire [2:0]  _cpu_io_ipl;
  wire        _cpu_io_as;
  wire        _cpu_io_rw;
  wire        _cpu_io_uds;
  wire        _cpu_io_lds;
  wire [2:0]  _cpu_io_fc;
  wire [22:0] _cpu_io_addr;
  wire [15:0] _cpu_io_dout;
  wire        videoVBlankRising;
  wire        videoVBlankFalling;
  wire        pausePressed = io_player_0_pause | io_player_1_pause;
  wire        pauseActive;
  reg         videoIrq;
  reg         agalletIrq;
  reg         unknownIrq;
  reg  [15:0] dinReg;
  reg         dtackReg;
  reg         sailorMoonTilebankReg;
  wire        readStrobe;
  wire        writeStrobe;
  wire        eepromSerialCs;
  wire        eepromSerialSck;
  wire        eepromSerialSdi;
  wire [2:0]  eepromSerialPinState;
  wire        eepromMem_wr;
  wire [2:0]  cpuBusStrobeState;
  wire [3:0]  vblankTrackerState;
  wire [23:0] coin1PulseState;
  wire [23:0] coin2PulseState;
  wire [28:0] servicePulseState;
  wire [1:0]  pauseState;
  wire [43:0] mazingerControlState;
  wire [13:0] metmqstrWatchdogState;
  wire [95:0] hotdogGapState;
  wire [95:0] metmqstrGapState;
  wire [359:0] mainControlLiveState;
  wire [359:0] mainControlRestoreState;
  wire         mainControlRestoreLoad;
  wire         mainControlOwnerIdle;
  wire         mainControlValidationComplete;
  wire         mainControlValidationValid;
  wire         mainControlWriteComplete;
  wire         mainControlWriteValid;
  wire [31:0]  mainCpuSavedSsp;
  wire [31:0]  mainCpuRestoreSsp;
  wire [511:0] mainCpuSavedContext;
  wire [511:0] mainCpuRestoreContext;
  wire         mainCpuRestoreLoad;
  wire         mainCpuRestoreDone;
  wire         mainCpuOwnerAbortSafe;
  wire         mainCpuOwnerIdle;
  wire         mainCpuWrapperTerminalFault;
  wire         mainCpuValidationComplete;
  wire         mainCpuValidationValid;
  wire         mainCpuWriteComplete;
  wire         mainCpuWriteValid;
  wire [47:0]  mainLayer0RegisterState;
  wire [47:0]  mainLayer1RegisterState;
  wire [47:0]  mainLayer2RegisterState;
  wire [127:0] mainSpriteRegisterState;
  wire [271:0] mainRegisterLiveState;
  wire [271:0] mainRegisterRestoreState;
  wire [3:0]   mainRegisterBlockedWrite;
  wire         mainRegisterRestoreLoad;
  wire         mainRegisterOwnerIdle;
  wire         mainRegisterValidationComplete;
  wire         mainRegisterValidationValid;
  wire         mainRegisterWriteComplete;
  wire         mainRegisterWriteValid;
  wire [47:0]  eepromLiveState;
  wire [47:0]  eepromRestoreState;
  wire         eepromRestoreLoad;
  wire         eepromDeviceIdle;
  wire         eepromOwnerIdle;
  wire         eepromValidationComplete;
  wire         eepromValidationValid;
  wire         eepromWriteComplete;
  wire         eepromWriteValid;
  reg         io_gpuMem_layer_0_regs_r_tileSize;
  reg         io_gpuMem_layer_0_regs_r_enable;
  reg         io_gpuMem_layer_0_regs_r_flipX;
  reg         io_gpuMem_layer_0_regs_r_flipY;
  reg         io_gpuMem_layer_0_regs_r_rowScrollEnable;
  reg         io_gpuMem_layer_0_regs_r_rowSelectEnable;
  reg  [1:0]  io_gpuMem_layer_0_regs_r_priority;
  reg  [8:0]  io_gpuMem_layer_0_regs_r_scroll_x;
  reg  [8:0]  io_gpuMem_layer_0_regs_r_scroll_y;
  reg         io_gpuMem_layer_0_regs_r_1_tileSize;
  reg         io_gpuMem_layer_0_regs_r_1_enable;
  reg         io_gpuMem_layer_0_regs_r_1_flipX;
  reg         io_gpuMem_layer_0_regs_r_1_flipY;
  reg         io_gpuMem_layer_0_regs_r_1_rowScrollEnable;
  reg         io_gpuMem_layer_0_regs_r_1_rowSelectEnable;
  reg  [1:0]  io_gpuMem_layer_0_regs_r_1_priority;
  reg  [8:0]  io_gpuMem_layer_0_regs_r_1_scroll_x;
  reg  [8:0]  io_gpuMem_layer_0_regs_r_1_scroll_y;
  reg         io_gpuMem_layer_1_regs_r_tileSize;
  reg         io_gpuMem_layer_1_regs_r_enable;
  reg         io_gpuMem_layer_1_regs_r_flipX;
  reg         io_gpuMem_layer_1_regs_r_flipY;
  reg         io_gpuMem_layer_1_regs_r_rowScrollEnable;
  reg         io_gpuMem_layer_1_regs_r_rowSelectEnable;
  reg  [1:0]  io_gpuMem_layer_1_regs_r_priority;
  reg  [8:0]  io_gpuMem_layer_1_regs_r_scroll_x;
  reg  [8:0]  io_gpuMem_layer_1_regs_r_scroll_y;
  reg         io_gpuMem_layer_1_regs_r_1_tileSize;
  reg         io_gpuMem_layer_1_regs_r_1_enable;
  reg         io_gpuMem_layer_1_regs_r_1_flipX;
  reg         io_gpuMem_layer_1_regs_r_1_flipY;
  reg         io_gpuMem_layer_1_regs_r_1_rowScrollEnable;
  reg         io_gpuMem_layer_1_regs_r_1_rowSelectEnable;
  reg  [1:0]  io_gpuMem_layer_1_regs_r_1_priority;
  reg  [8:0]  io_gpuMem_layer_1_regs_r_1_scroll_x;
  reg  [8:0]  io_gpuMem_layer_1_regs_r_1_scroll_y;
  reg         io_gpuMem_layer_2_regs_r_tileSize;
  reg         io_gpuMem_layer_2_regs_r_enable;
  reg         io_gpuMem_layer_2_regs_r_flipX;
  reg         io_gpuMem_layer_2_regs_r_flipY;
  reg         io_gpuMem_layer_2_regs_r_rowScrollEnable;
  reg         io_gpuMem_layer_2_regs_r_rowSelectEnable;
  reg  [1:0]  io_gpuMem_layer_2_regs_r_priority;
  reg  [8:0]  io_gpuMem_layer_2_regs_r_scroll_x;
  reg  [8:0]  io_gpuMem_layer_2_regs_r_scroll_y;
  reg         io_gpuMem_layer_2_regs_r_1_tileSize;
  reg         io_gpuMem_layer_2_regs_r_1_enable;
  reg         io_gpuMem_layer_2_regs_r_1_flipX;
  reg         io_gpuMem_layer_2_regs_r_1_flipY;
  reg         io_gpuMem_layer_2_regs_r_1_rowScrollEnable;
  reg         io_gpuMem_layer_2_regs_r_1_rowSelectEnable;
  reg  [1:0]  io_gpuMem_layer_2_regs_r_1_priority;
  reg  [8:0]  io_gpuMem_layer_2_regs_r_1_scroll_x;
  reg  [8:0]  io_gpuMem_layer_2_regs_r_1_scroll_y;
  wire        coin1PulseActive;
  wire        coin2PulseActive;
  wire        servicePulseActive;
  wire [15:0] inputPort0;
  wire [15:0] inputPort1;
  wire [23:0] cpuByteAddr = {_cpu_io_addr, 1'b0};
  wire [1:0]  mainRam_io_mask = {_cpu_io_uds, _cpu_io_lds};
  wire [7:0]  cpuWriteByte = _cpu_io_uds ? _cpu_io_dout[15:8] : _cpu_io_dout[7:0];
  wire        highScoreCpuHold;
  wire        highScoreCpuHoldAck;
  wire        highScoreRamOwned;
  wire        highScoreRamTargetSprite;
  wire        highScoreRamRd;
  wire        highScoreRamWr;
  wire [14:0] highScoreRamAddr;
  wire [1:0]  highScoreRamMask;
  wire [15:0] highScoreRamDin;

  CaveVBlankTracker vblankTracker(
    .clock        (clock),
    .vblank       (io_video_vBlank),
    .ss_hold      (mainControlStateHold),
    .ss_load      (mainControlRestoreLoad),
    .ss_state_in  (mainControlRestoreState[32:29]),
    .ss_state_out (vblankTrackerState),
    .rising       (videoVBlankRising),
    .falling      (videoVBlankFalling)
  );

  CaveCpuBusStrobes cpuBusStrobes(
    .clock        (clock),
    .as           (_cpu_io_as),
    .uds          (_cpu_io_uds),
    .lds          (_cpu_io_lds),
    .rw           (_cpu_io_rw),
    .ss_hold      (mainControlStateHold),
    .ss_load      (mainControlRestoreLoad),
    .ss_state_in  (mainControlRestoreState[28:26]),
    .ss_state_out (cpuBusStrobeState),
    .read_strobe  (readStrobe),
    .write_strobe (writeStrobe)
  );

  CavePulseStretcher #(
    .COUNTER_WIDTH(22),
    .TERMINAL_COUNT(22'h30D3FF)
  ) coin1Pulse (
    .clock(clock),
    .reset(reset),
    .signal_in(io_player_0_coin),
    .ss_hold(mainControlStateHold),
    .ss_load(mainControlRestoreLoad),
    .ss_state_in(mainControlRestoreState[56:33]),
    .ss_state_out(coin1PulseState),
    .pulse_active(coin1PulseActive)
  );

  CavePulseStretcher #(
    .COUNTER_WIDTH(22),
    .TERMINAL_COUNT(22'h30D3FF)
  ) coin2Pulse (
    .clock(clock),
    .reset(reset),
    .signal_in(io_player_1_coin),
    .ss_hold(mainControlStateHold),
    .ss_load(mainControlRestoreLoad),
    .ss_state_in(mainControlRestoreState[80:57]),
    .ss_state_out(coin2PulseState),
    .pulse_active(coin2PulseActive)
  );

  CavePulseStretcher #(
    .COUNTER_WIDTH(27),
    .TERMINAL_COUNT(27'h4C4B3FF)
  ) servicePulse (
    .clock(clock),
    .reset(reset),
    .signal_in(io_options_service),
    .ss_hold(mainControlStateHold),
    .ss_load(mainControlRestoreLoad),
    .ss_state_in(mainControlRestoreState[109:81]),
    .ss_state_out(servicePulseState),
    .pulse_active(servicePulseActive)
  );

  CaveInputMapper inputMapper(
    .game_is_guwange            (1'b0),
    .game_is_gaia               (1'b0),
    .game_is_metmqstr           (gameIsMetmqstr),
    .eeprom_sdo                 (_eeprom_io_serial_sdo),
    .service_active             (servicePulseActive),
    .coin1_active               (coin1PulseActive),
    .coin2_active               (coin2PulseActive),
    .player0_up                 (io_player_0_up),
    .player0_down               (io_player_0_down),
    .player0_left               (io_player_0_left),
    .player0_right              (io_player_0_right),
    .player0_buttons            (io_player_0_buttons),
    .player0_start              (io_player_0_start),
    .player1_up                 (io_player_1_up),
    .player1_down               (io_player_1_down),
    .player1_left               (io_player_1_left),
    .player1_right              (io_player_1_right),
    .player1_buttons            (io_player_1_buttons),
    .player1_start              (io_player_1_start),
    .default_p1                 (),
    .default_p2                 (),
    .combined_players           (),
    .guwange_p1                 (),
    .input0                     (inputPort0),
    .default_or_guwange_p1      (),
    .combined_or_guwange_p1     (),
    .guwange_system             (),
    .gaia_system                (),
    .input1                     (inputPort1),
    .default_or_guwange_p2      (),
    .shared_system              ()
  );

  CaveEepromSerialPins eepromSerialPins(
    .clock          (clock),
    .reset          (reset),
    .write_enable   (eepromMem_wr),
    .guwange_layout (1'b0),
    .metmqstr_layout(gameIsMetmqstr),
    .data           (_cpu_io_dout),
    .ss_hold        (mainControlStateHold),
    .ss_load        (mainControlRestoreLoad),
    .ss_state_in    (mainControlRestoreState[25:23]),
    .ss_state_out   (eepromSerialPinState),
    .serial_cs      (eepromSerialCs),
    .serial_sck     (eepromSerialSck),
    .serial_sdi     (eepromSerialSdi)
  );

  CavePauseToggle pauseToggle(
    .clock         (clock),
    .reset         (reset),
    .pause_pressed (pausePressed),
    .ss_hold       (mainControlStateHold),
    .ss_load       (mainControlRestoreLoad),
    .ss_state_in   (mainControlRestoreState[22:21]),
    .ss_state_out  (pauseState),
    .pause_active  (pauseActive)
  );

  wire        mazingerProgRomSelect;
  wire        mazingerVideoRegsSelect;
  wire        mazingerIrqSelect;
  wire        mazingerSpriteRegsSelect;
  wire        mazingerMainRamSelect;
  wire        mazingerSpriteRamSelect;
  wire        mazingerSpriteSwapWrite;
  wire        mazingerSoundSelect;
  wire        mazingerInput0Cycle;
  wire        mazingerInput1Cycle;
  wire        mazingerEepromCycle;
  wire        mazingerProgRomAccess;
  wire        mazingerSyncDtack;
  wire        mazingerUnmappedCycle;
  wire        mazingerCpuSpace;
  wire        mazingerSoundRead;
  wire        mazingerSoundWrite;
  wire        mazingerLayer1Vram8Select;
  wire        mazingerLayer0Vram8Select;
  wire        mazingerLayer1RegsSelect;
  wire        mazingerLayer0RegsSelect;
  wire        mazingerInput0Read;
  wire        mazingerInput1Read;
  wire        mazingerEepromWrite;
  wire        mazingerPaletteSelect;
  wire [14:0] mazingerPaletteRamAddr;
  wire        mazingerExtraRomSelect;
  wire        mazingerNoOpSelect;
  wire        mazingerProgRomReady;
  wire        mazingerIrqRead;
  wire        mazingerVideoIrqClear;
  wire        mazingerUnknownIrqClear;
  wire        mazingerCycle;
  wire        mazingerProgRomRead;
  wire        mazingerMainRamRead;
  wire        mazingerMainRamWrite;
  wire        mazingerSpriteRamRead;
  wire        mazingerSpriteRamWrite;
  wire        mazingerLayer0Vram8Read;
  wire        mazingerLayer1Vram8Read;
  wire        mazingerLayer0Vram8Write;
  wire        mazingerLayer1Vram8Write;
  wire        mazingerVideoRegsRead;
  wire        mazingerVideoRegsWrite;
  wire        mazingerLayer0RegsRead;
  wire        mazingerLayer1RegsRead;
  wire        mazingerLayer0RegsWrite;
  wire        mazingerLayer1RegsWrite;
  wire        mazingerPaletteRead;
  wire        mazingerPaletteWrite;
  wire        mazingerSpriteRegsWrite;
  wire        mazingerOpenBusSelect;
  wire        mazingerDtack;
  wire        mazingerReadDataValid;
  wire [15:0] mazingerReadData;
  wire        mazingerCpuReset;
  wire        mazingerBootRamSelect;
  wire [15:0] mazingerBootRamDout;
  wire        mazingerBootWatchdogArmed;
  wire        mazingerBootWatchdogDelayActive;
  wire        mazingerBootWatchdogResetActive;
  wire        mazingerBootMarkerWrite;
  wire        mazingerBootWatchdogTrip;

  wire [23:0] airGalletCpuByteAddr;
  wire        airGalletProgRomSelect;
  wire        airGalletMainRamSelect;
  wire        airGalletSpriteRamSelect;
  wire        airGalletSoundFlagsRead;
  wire        airGalletSoundRead;
  wire        airGalletSoundWrite;
  wire        airGalletLayer0Vram8Select;
  wire        airGalletLayer1Vram8Select;
  wire        airGalletLayer2Vram8Select;
  wire        airGalletLayer0RegsSelect;
  wire        airGalletLayer1RegsSelect;
  wire        airGalletLayer2RegsSelect;
  wire        airGalletInput0Read;
  wire        airGalletInput1Read;
  wire        airGalletEepromWrite;
  wire        airGalletPaletteSelect;
  wire [14:0] airGalletPaletteRamAddr;
  wire        airGalletExtraRomSelect;
  wire        airGalletWorkRamSelect;
  wire [14:0] airGalletWorkRamAddr;
  wire        airGalletProgRomReady;
  wire        airGalletIrqRead;
  wire [1:0]  airGalletIrqWordOffset;
  wire        airGalletVideoIrqClear;
  wire        airGalletUnknownIrqClear;
  wire        airGalletSpriteSwapWrite;
  wire        airGalletSyncDtack;
  wire        airGalletCycle;
  wire        airGalletUnmappedCycle;
  wire        airGalletProgRomRead;
  wire        airGalletWorkRamRead;
  wire        airGalletWorkRamWrite;
  wire        airGalletMainRamRead;
  wire        airGalletMainRamWrite;
  wire        airGalletSpriteRamRead;
  wire        airGalletSpriteRamWrite;
  wire        airGalletLayer0Vram8Read;
  wire        airGalletLayer1Vram8Read;
  wire        airGalletLayer2Vram8Read;
  wire        airGalletLayer0Vram8Write;
  wire        airGalletLayer1Vram8Write;
  wire        airGalletLayer2Vram8Write;
  wire        airGalletLayer0RegsWrite;
  wire        airGalletLayer1RegsWrite;
  wire        airGalletLayer2RegsWrite;
  wire        airGalletPaletteRead;
  wire        airGalletPaletteWrite;
  wire        airGalletSpriteRegsWrite;
  wire        airGalletCpuSpace;
  wire        airGalletOpenBusSelect;
  wire        airGalletDtack;
  wire        airGalletReadDataValid;
  wire [15:0] airGalletReadData;

  wire [23:0] hotdogCpuByteAddr;
  wire        hotdogProgRomSelect;
  wire        hotdogMainRamSelect;
  wire        hotdogPaletteSelect;
  wire [14:0] hotdogPaletteRamAddr;
  wire        hotdogSpriteRamSelect;
  wire        hotdogSpriteRamRead;
  wire        hotdogSpriteRamWrite;
  wire        hotdogIrqRead;
  wire [1:0]  hotdogIrqWordOffset;
  wire        hotdogVideoIrqClear;
  wire        hotdogUnknownIrqClear;
  wire        hotdogSoundWrite;
  wire        hotdogInput0Read;
  wire        hotdogInput1Read;
  wire        hotdogEepromWrite;
  wire        hotdogSpriteSwapWrite;
  wire        hotdogProgRomRead;
  wire        hotdogMainRamRead;
  wire        hotdogMainRamWrite;
  wire        hotdogPaletteRead;
  wire        hotdogPaletteWrite;
  wire        hotdogLayer0Vram16Read;
  wire        hotdogLayer0Vram16Write;
  wire        hotdogLayer0LineRead;
  wire        hotdogLayer0LineWrite;
  wire        hotdogLayer0Vram8Read;
  wire        hotdogLayer0Vram8Write;
  wire        hotdogLayer1Vram16Read;
  wire        hotdogLayer1Vram16Write;
  wire        hotdogLayer1LineRead;
  wire        hotdogLayer1LineWrite;
  wire        hotdogLayer1Vram8Read;
  wire        hotdogLayer1Vram8Write;
  wire        hotdogLayer2Vram16Read;
  wire        hotdogLayer2Vram16Write;
  wire        hotdogLayer2LineRead;
  wire        hotdogLayer2LineWrite;
  wire        hotdogLayer2Vram8Read;
  wire        hotdogLayer2Vram8Write;
  wire        hotdogLayer0RegsWrite;
  wire        hotdogLayer1RegsWrite;
  wire        hotdogLayer2RegsWrite;
  wire        hotdogSpriteRegsWrite;
  wire        hotdogDtack;
  wire        hotdogReadDataValid;
  wire [15:0] hotdogReadData;

  wire [23:0] metmqstrCpuByteAddr;
  wire [21:0] metmqstrProgRomPackedAddr;
  wire        metmqstrProgRomSelect;
  wire        metmqstrPaletteSelect;
  wire [14:0] metmqstrPaletteRamAddr;
  wire        metmqstrSpriteRamSelect;
  wire        metmqstrIrqRead;
  wire [1:0]  metmqstrIrqWordOffset;
  wire        metmqstrVideoIrqClear;
  wire        metmqstrUnknownIrqClear;
  wire        metmqstrSoundFlagsRead;
  wire        metmqstrSoundRead;
  wire        metmqstrSoundWrite;
  wire        metmqstrInput0Read;
  wire        metmqstrInput1Read;
  wire        metmqstrEepromWrite;
  wire        metmqstrSpriteSwapWrite;
  wire        metmqstrProgRomRead;
  wire        metmqstrPaletteRead;
  wire        metmqstrPaletteWrite;
  wire        metmqstrSpriteRamRead;
  wire        metmqstrSpriteRamWrite;
  wire        metmqstrLayer0Vram16Read;
  wire        metmqstrLayer0Vram16Write;
  wire        metmqstrLayer0LineRead;
  wire        metmqstrLayer0LineWrite;
  wire        metmqstrLayer0Vram8Read;
  wire        metmqstrLayer0Vram8Write;
  wire        metmqstrLayer1Vram16Read;
  wire        metmqstrLayer1Vram16Write;
  wire        metmqstrLayer1LineRead;
  wire        metmqstrLayer1LineWrite;
  wire        metmqstrLayer1Vram8Read;
  wire        metmqstrLayer1Vram8Write;
  wire        metmqstrLayer2Vram16Read;
  wire        metmqstrLayer2Vram16Write;
  wire        metmqstrLayer2LineRead;
  wire        metmqstrLayer2LineWrite;
  wire        metmqstrLayer2Vram8Read;
  wire        metmqstrLayer2Vram8Write;
  wire        metmqstrLayer0RegsWrite;
  wire        metmqstrLayer1RegsWrite;
  wire        metmqstrLayer2RegsWrite;
  wire        metmqstrSpriteRegsWrite;
  wire        metmqstrDtack;
  wire        metmqstrReadDataValid;
  wire [15:0] metmqstrReadData;
  wire        metmqstrCpuReset;
  wire        metmqstrBootMarkerSeen;
  wire        metmqstrBootWatchdogDelayActive;
  wire        metmqstrBootWatchdogResetActive;
  wire        metmqstrBootWatchdogTrip;

  wire [14:0] airGalletTilemapOffset = airGalletCpuByteAddr[14:0];
  wire        airGalletTilemapVram16 = airGalletTilemapOffset < 15'h1000;
  wire        airGalletTilemapLine =
    (airGalletTilemapOffset >= 15'h1000) & (airGalletTilemapOffset < 15'h1800);
  wire        airGalletTilemapScratch =
    (airGalletTilemapOffset >= 15'h1800) & (airGalletTilemapOffset < 15'h4000);
  wire        airGalletTilemapVram8 = airGalletTilemapOffset >= 15'h4000;
  wire [12:0] airGalletTilemapScratchAddr = airGalletTilemapOffset[13:1] - 13'h0c00;
  wire        airGalletLayer0Vram16Read = airGalletLayer0Vram8Read & airGalletTilemapVram16;
  wire        airGalletLayer0Vram16Write = airGalletLayer0Vram8Write & airGalletTilemapVram16;
  wire        airGalletLayer0LineRead = airGalletLayer0Vram8Read & airGalletTilemapLine;
  wire        airGalletLayer0LineWrite = airGalletLayer0Vram8Write & airGalletTilemapLine;
  wire        airGalletLayer0ScratchRead = airGalletLayer0Vram8Read & airGalletTilemapScratch;
  wire        airGalletLayer0ScratchWrite = airGalletLayer0Vram8Write & airGalletTilemapScratch;
  wire        airGalletLayer0Vram8OnlyRead = airGalletLayer0Vram8Read & airGalletTilemapVram8;
  wire        airGalletLayer0Vram8OnlyWrite = airGalletLayer0Vram8Write & airGalletTilemapVram8;
  wire        airGalletLayer1Vram16Read = airGalletLayer1Vram8Read & airGalletTilemapVram16;
  wire        airGalletLayer1Vram16Write = airGalletLayer1Vram8Write & airGalletTilemapVram16;
  wire        airGalletLayer1LineRead = airGalletLayer1Vram8Read & airGalletTilemapLine;
  wire        airGalletLayer1LineWrite = airGalletLayer1Vram8Write & airGalletTilemapLine;
  wire        airGalletLayer1ScratchRead = airGalletLayer1Vram8Read & airGalletTilemapScratch;
  wire        airGalletLayer1ScratchWrite = airGalletLayer1Vram8Write & airGalletTilemapScratch;
  wire        airGalletLayer1Vram8OnlyRead = airGalletLayer1Vram8Read & airGalletTilemapVram8;
  wire        airGalletLayer1Vram8OnlyWrite = airGalletLayer1Vram8Write & airGalletTilemapVram8;
  wire        airGalletLayer2Vram16Read = airGalletLayer2Vram8Read & airGalletTilemapVram16;
  wire        airGalletLayer2Vram16Write = airGalletLayer2Vram8Write & airGalletTilemapVram16;
  wire        airGalletLayer2LineRead = airGalletLayer2Vram8Read & airGalletTilemapLine;
  wire        airGalletLayer2LineWrite = airGalletLayer2Vram8Write & airGalletTilemapLine;
  wire        airGalletLayer2ScratchRead = airGalletLayer2Vram8Read & airGalletTilemapScratch;
  wire        airGalletLayer2ScratchWrite = airGalletLayer2Vram8Write & airGalletTilemapScratch;
  wire        airGalletLayer2Vram8OnlyRead = airGalletLayer2Vram8Read & airGalletTilemapVram8;
  wire        airGalletLayer2Vram8OnlyWrite = airGalletLayer2Vram8Write & airGalletTilemapVram8;
  wire [15:0] airGalletLayer0ScratchData;
  wire [15:0] airGalletLayer1ScratchData;
  wire [15:0] airGalletLayer2ScratchData;
  wire [15:0] airGalletLayer0VramData =
    airGalletTilemapVram16 ? _vram16x16_0_io_portA_dout :
    airGalletTilemapLine   ? _lineRam_0_io_portA_dout :
    airGalletTilemapScratch ? airGalletLayer0ScratchData :
    airGalletTilemapVram8  ? _vram8x8_0_io_portA_dout :
    16'h0000;
  wire [15:0] airGalletLayer1VramData =
    airGalletTilemapVram16 ? _vram16x16_1_io_portA_dout :
    airGalletTilemapLine   ? _lineRam_1_io_portA_dout :
    airGalletTilemapScratch ? airGalletLayer1ScratchData :
    airGalletTilemapVram8  ? _vram8x8_1_io_portA_dout :
    16'h0000;
  wire [15:0] airGalletLayer2VramData =
    airGalletTilemapVram16 ? _vram16x16_2_io_portA_dout :
    airGalletTilemapLine   ? _lineRam_2_io_portA_dout :
    airGalletTilemapScratch ? airGalletLayer2ScratchData :
    airGalletTilemapVram8  ? _vram8x8_2_io_portA_dout :
    16'h0000;
  wire [15:0] airGalletWorkRamData;

  assign airGalletVideoIrqClear =
    gameIsAirFamily & airGalletIrqRead & (airGalletIrqWordOffset == 2'h2);
  assign airGalletUnknownIrqClear =
    gameIsAirFamily & airGalletIrqRead & (airGalletIrqWordOffset == 2'h3);

  MazingerMainMap mazingerMainMap(
    .clock                (clock),
    .reset                (reset),
    .game_active          (gameIsMazinger),
    .cpu_addr             (_cpu_io_addr),
    .cpu_fc               (_cpu_io_fc),
    .cpu_as               (_cpu_io_as),
    .cpu_rw               (_cpu_io_rw),
    .read_strobe          (readStrobe),
    .write_strobe         (writeStrobe),
    .prog_rom_valid       (io_progRom_valid),
    .dtack_reg            (dtackReg),
    .main_ram_addr        (_mainRam_io_addr),
    .main_ram_mask        (mainRam_io_mask),
    .cpu_dout             (_cpu_io_dout),
    .agallet_irq          (agalletIrq),
    .unknown_irq          (unknownIrq),
    .video_irq            (videoIrq),
    .input1_data          (inputPort1),
    .input0_data          (inputPort0),
    .palette_data         (_paletteRam_io_portA_dout),
    .layer0_regs_data     (_layerRegs_0_io_mem_dout),
    .layer1_regs_data     (_layerRegs_1_io_mem_dout),
    .layer0_vram8_data    (_vram8x8_0_io_portA_dout),
    .layer1_vram8_data    (_vram8x8_1_io_portA_dout),
    .sound_data           (io_soundCtrl_reply),
    .sprite_ram_data      (_spriteRam_io_portA_dout),
    .main_ram_data        (_mainRam_io_dout),
    .prog_rom_data        (io_progRom_dout),
    .ss_hold              (mainControlStateHold),
    .ss_load              (mainControlRestoreLoad),
    .ss_state_in          (mainControlRestoreState[153:110]),
    .ss_state_out         (mazingerControlState),
    .cpu_byte_addr        (),
    .prog_rom_select      (mazingerProgRomSelect),
    .main_ram_select      (mazingerMainRamSelect),
    .sprite_ram_select    (mazingerSpriteRamSelect),
    .video_regs_select    (mazingerVideoRegsSelect),
    .irq_select           (mazingerIrqSelect),
    .sprite_regs_select   (mazingerSpriteRegsSelect),
    .sprite_swap_write    (mazingerSpriteSwapWrite),
    .sound_select         (mazingerSoundSelect),
    .sound_read           (mazingerSoundRead),
    .sound_write          (mazingerSoundWrite),
    .layer1_vram8_select  (mazingerLayer1Vram8Select),
    .layer0_vram8_select  (mazingerLayer0Vram8Select),
    .layer1_regs_select   (mazingerLayer1RegsSelect),
    .layer0_regs_select   (mazingerLayer0RegsSelect),
    .input0_cycle         (mazingerInput0Cycle),
    .input1_cycle         (mazingerInput1Cycle),
    .input0_read          (mazingerInput0Read),
    .input1_read          (mazingerInput1Read),
    .eeprom_cycle         (mazingerEepromCycle),
    .eeprom_write         (mazingerEepromWrite),
    .palette_select       (mazingerPaletteSelect),
    .palette_ram_addr     (mazingerPaletteRamAddr),
    .extra_rom_select     (mazingerExtraRomSelect),
    .no_op_select         (mazingerNoOpSelect),
    .prog_rom_access      (mazingerProgRomAccess),
    .prog_rom_ready       (mazingerProgRomReady),
    .irq_read             (mazingerIrqRead),
    .irq_word_offset      (),
    .video_irq_clear      (mazingerVideoIrqClear),
    .unknown_irq_clear    (mazingerUnknownIrqClear),
    .sync_dtack           (mazingerSyncDtack),
    .cycle                (mazingerCycle),
    .unmapped_cycle       (mazingerUnmappedCycle),
    .prog_rom_read        (mazingerProgRomRead),
    .main_ram_read        (mazingerMainRamRead),
    .main_ram_write       (mazingerMainRamWrite),
    .sprite_ram_read      (mazingerSpriteRamRead),
    .sprite_ram_write     (mazingerSpriteRamWrite),
    .layer0_vram8_read    (mazingerLayer0Vram8Read),
    .layer1_vram8_read    (mazingerLayer1Vram8Read),
    .layer0_vram8_write   (mazingerLayer0Vram8Write),
    .layer1_vram8_write   (mazingerLayer1Vram8Write),
    .video_regs_read      (mazingerVideoRegsRead),
    .video_regs_write     (mazingerVideoRegsWrite),
    .layer0_regs_read     (mazingerLayer0RegsRead),
    .layer1_regs_read     (mazingerLayer1RegsRead),
    .layer0_regs_write    (mazingerLayer0RegsWrite),
    .layer1_regs_write    (mazingerLayer1RegsWrite),
    .palette_read         (mazingerPaletteRead),
    .palette_write        (mazingerPaletteWrite),
    .sprite_regs_write    (mazingerSpriteRegsWrite),
    .cpu_space            (mazingerCpuSpace),
    .open_bus_select      (mazingerOpenBusSelect),
    .dtack                (mazingerDtack),
    .cpu_reset            (mazingerCpuReset),
    .boot_ram_select      (mazingerBootRamSelect),
    .boot_ram_dout        (mazingerBootRamDout),
    .boot_watchdog_armed        (mazingerBootWatchdogArmed),
    .boot_watchdog_delay_active (mazingerBootWatchdogDelayActive),
    .boot_watchdog_reset_active (mazingerBootWatchdogResetActive),
    .boot_marker_write          (mazingerBootMarkerWrite),
    .boot_watchdog_trip         (mazingerBootWatchdogTrip),
    .read_data_valid      (mazingerReadDataValid),
    .read_data            (mazingerReadData)
  );

  AirGalletMainMap airGalletMainMap(
    .game_active          (gameIsAirFamily),
    .cpu_addr             (_cpu_io_addr),
    .cpu_fc               (_cpu_io_fc),
    .cpu_as               (_cpu_io_as),
    .cpu_rw               (_cpu_io_rw),
    .read_strobe          (readStrobe),
    .write_strobe         (writeStrobe),
    .extra_rom_has_data   (gameIsSailorMoon),
    .prog_rom_valid       (io_progRom_valid),
    .dtack_reg            (dtackReg),
    .agallet_irq          (agalletIrq),
    .unknown_irq          (unknownIrq),
    .video_irq            (videoIrq),
    .input1_data          (inputPort1),
    .input0_data          (inputPort0),
    .palette_data         (_paletteRam_io_portA_dout),
    .layer0_regs_data     (_layerRegs_0_io_mem_dout),
    .layer1_regs_data     (_layerRegs_1_io_mem_dout),
    .layer2_regs_data     (_layerRegs_2_io_mem_dout),
    .layer0_vram8_data    (airGalletLayer0VramData),
    .layer1_vram8_data    (airGalletLayer1VramData),
    .layer2_vram8_data    (airGalletLayer2VramData),
    .sound_data           (io_soundCtrl_reply),
    .sound_reply_empty    (io_soundCtrl_reply_empty),
    .sprite_ram_data      (_spriteRam_io_portA_dout),
    .work_ram_data        (airGalletWorkRamData),
    .main_ram_data        (_mainRam_io_dout),
    .prog_rom_data        (io_progRom_dout),
    .cpu_byte_addr        (airGalletCpuByteAddr),
    .prog_rom_select      (airGalletProgRomSelect),
    .main_ram_select      (airGalletMainRamSelect),
    .sprite_ram_select    (airGalletSpriteRamSelect),
    .sound_flags_read     (airGalletSoundFlagsRead),
    .sound_read           (airGalletSoundRead),
    .sound_write          (airGalletSoundWrite),
    .layer0_vram8_select  (airGalletLayer0Vram8Select),
    .layer1_vram8_select  (airGalletLayer1Vram8Select),
    .layer2_vram8_select  (airGalletLayer2Vram8Select),
    .layer0_regs_select   (airGalletLayer0RegsSelect),
    .layer1_regs_select   (airGalletLayer1RegsSelect),
    .layer2_regs_select   (airGalletLayer2RegsSelect),
    .input0_read          (airGalletInput0Read),
    .input1_read          (airGalletInput1Read),
    .eeprom_write         (airGalletEepromWrite),
    .palette_select       (airGalletPaletteSelect),
    .palette_ram_addr     (airGalletPaletteRamAddr),
    .extra_rom_select     (airGalletExtraRomSelect),
    .work_ram_select      (airGalletWorkRamSelect),
    .work_ram_addr        (airGalletWorkRamAddr),
    .prog_rom_ready       (airGalletProgRomReady),
    .irq_read             (airGalletIrqRead),
    .irq_word_offset      (airGalletIrqWordOffset),
    .sprite_swap_write    (airGalletSpriteSwapWrite),
    .sync_dtack           (airGalletSyncDtack),
    .cycle                (airGalletCycle),
    .unmapped_cycle       (airGalletUnmappedCycle),
    .prog_rom_read        (airGalletProgRomRead),
    .work_ram_read        (airGalletWorkRamRead),
    .work_ram_write       (airGalletWorkRamWrite),
    .main_ram_read        (airGalletMainRamRead),
    .main_ram_write       (airGalletMainRamWrite),
    .sprite_ram_read      (airGalletSpriteRamRead),
    .sprite_ram_write     (airGalletSpriteRamWrite),
    .layer0_vram8_read    (airGalletLayer0Vram8Read),
    .layer1_vram8_read    (airGalletLayer1Vram8Read),
    .layer2_vram8_read    (airGalletLayer2Vram8Read),
    .layer0_vram8_write   (airGalletLayer0Vram8Write),
    .layer1_vram8_write   (airGalletLayer1Vram8Write),
    .layer2_vram8_write   (airGalletLayer2Vram8Write),
    .layer0_regs_write    (airGalletLayer0RegsWrite),
    .layer1_regs_write    (airGalletLayer1RegsWrite),
    .layer2_regs_write    (airGalletLayer2RegsWrite),
    .palette_read         (airGalletPaletteRead),
    .palette_write        (airGalletPaletteWrite),
    .sprite_regs_write    (airGalletSpriteRegsWrite),
    .cpu_space            (airGalletCpuSpace),
    .open_bus_select      (airGalletOpenBusSelect),
    .dtack                (airGalletDtack),
    .read_data_valid      (airGalletReadDataValid),
    .read_data            (airGalletReadData)
  );

  HotdogStormMainMap hotdogStormMainMap(
    .clock                (clock),
    .game_active          (gameIsHotdogStorm),
    .cpu_addr             (_cpu_io_addr),
    .cpu_fc               (_cpu_io_fc),
    .cpu_as               (_cpu_io_as),
    .cpu_rw               (_cpu_io_rw),
    .read_strobe          (readStrobe),
    .write_strobe         (writeStrobe),
    .prog_rom_valid       (io_progRom_valid),
    .dtack_reg            (dtackReg),
    .agallet_irq          (agalletIrq),
    .unknown_irq          (unknownIrq),
    .video_irq            (videoIrq),
    .cpu_dout             (_cpu_io_dout),
    .input1_data          (inputPort1),
    .input0_data          (inputPort0),
    .palette_data         (_paletteRam_io_portA_dout),
    .layer0_regs_data     (_layerRegs_0_io_mem_dout),
    .layer1_regs_data     (_layerRegs_1_io_mem_dout),
    .layer2_regs_data     (_layerRegs_2_io_mem_dout),
    .layer0_vram16_data   (_vram16x16_0_io_portA_dout),
    .layer0_line_data     (_lineRam_0_io_portA_dout),
    .layer0_vram8_data    (_vram8x8_0_io_portA_dout),
    .layer1_vram16_data   (_vram16x16_1_io_portA_dout),
    .layer1_line_data     (_lineRam_1_io_portA_dout),
    .layer1_vram8_data    (_vram8x8_1_io_portA_dout),
    .layer2_vram16_data   (_vram16x16_2_io_portA_dout),
    .layer2_line_data     (_lineRam_2_io_portA_dout),
    .layer2_vram8_data    (_vram8x8_2_io_portA_dout),
    .sprite_ram_data      (_spriteRam_io_portA_dout),
    .main_ram_data        (_mainRam_io_dout),
    .prog_rom_data        (io_progRom_dout),
    .ss_hold              (mainControlStateHold),
    .ss_load              (mainControlRestoreLoad),
    .ss_state_in          (mainControlRestoreState[263:168]),
    .ss_state_out         (hotdogGapState),
    .cpu_byte_addr        (hotdogCpuByteAddr),
    .prog_rom_select      (hotdogProgRomSelect),
    .main_ram_select      (hotdogMainRamSelect),
    .palette_select       (hotdogPaletteSelect),
    .palette_ram_addr     (hotdogPaletteRamAddr),
    .sprite_ram_select    (hotdogSpriteRamSelect),
    .irq_read             (hotdogIrqRead),
    .irq_word_offset      (hotdogIrqWordOffset),
    .video_irq_clear      (hotdogVideoIrqClear),
    .unknown_irq_clear    (hotdogUnknownIrqClear),
    .sound_write          (hotdogSoundWrite),
    .input0_read          (hotdogInput0Read),
    .input1_read          (hotdogInput1Read),
    .eeprom_write         (hotdogEepromWrite),
    .sprite_swap_write    (hotdogSpriteSwapWrite),
    .prog_rom_read        (hotdogProgRomRead),
    .main_ram_read        (hotdogMainRamRead),
    .main_ram_write       (hotdogMainRamWrite),
    .palette_read         (hotdogPaletteRead),
    .palette_write        (hotdogPaletteWrite),
    .layer0_vram16_read   (hotdogLayer0Vram16Read),
    .layer0_vram16_write  (hotdogLayer0Vram16Write),
    .layer0_line_read     (hotdogLayer0LineRead),
    .layer0_line_write    (hotdogLayer0LineWrite),
    .layer0_vram8_read    (hotdogLayer0Vram8Read),
    .layer0_vram8_write   (hotdogLayer0Vram8Write),
    .layer1_vram16_read   (hotdogLayer1Vram16Read),
    .layer1_vram16_write  (hotdogLayer1Vram16Write),
    .layer1_line_read     (hotdogLayer1LineRead),
    .layer1_line_write    (hotdogLayer1LineWrite),
    .layer1_vram8_read    (hotdogLayer1Vram8Read),
    .layer1_vram8_write   (hotdogLayer1Vram8Write),
    .layer2_vram16_read   (hotdogLayer2Vram16Read),
    .layer2_vram16_write  (hotdogLayer2Vram16Write),
    .layer2_line_read     (hotdogLayer2LineRead),
    .layer2_line_write    (hotdogLayer2LineWrite),
    .layer2_vram8_read    (hotdogLayer2Vram8Read),
    .layer2_vram8_write   (hotdogLayer2Vram8Write),
    .layer0_regs_write    (hotdogLayer0RegsWrite),
    .layer1_regs_write    (hotdogLayer1RegsWrite),
    .layer2_regs_write    (hotdogLayer2RegsWrite),
    .sprite_regs_write    (hotdogSpriteRegsWrite),
    .dtack                (hotdogDtack),
    .read_data_valid      (hotdogReadDataValid),
    .read_data            (hotdogReadData)
  );

  MetmqstrMainMap metmqstrMainMap(
    .clock                (clock),
    .game_active          (gameIsMetmqstr),
    .cpu_addr             (_cpu_io_addr),
    .cpu_fc               (_cpu_io_fc),
    .cpu_as               (_cpu_io_as),
    .cpu_rw               (_cpu_io_rw),
    .read_strobe          (readStrobe),
    .write_strobe         (writeStrobe),
    .prog_rom_valid       (io_progRom_valid),
    .dtack_reg            (dtackReg),
    .agallet_irq          (agalletIrq),
    .unknown_irq          (unknownIrq),
    .video_irq            (videoIrq),
    .cpu_dout             (_cpu_io_dout),
    .input1_data          (inputPort1),
    .input0_data          (inputPort0),
    .palette_data         (_paletteRam_io_portA_dout),
    .layer0_regs_data     (_layerRegs_0_io_mem_dout),
    .layer1_regs_data     (_layerRegs_1_io_mem_dout),
    .layer2_regs_data     (_layerRegs_2_io_mem_dout),
    .layer0_vram16_data   (_vram16x16_0_io_portA_dout),
    .layer0_line_data     (_lineRam_0_io_portA_dout),
    .layer0_vram8_data    (_vram8x8_0_io_portA_dout),
    .layer1_vram16_data   (_vram16x16_1_io_portA_dout),
    .layer1_line_data     (_lineRam_1_io_portA_dout),
    .layer1_vram8_data    (_vram8x8_1_io_portA_dout),
    .layer2_vram16_data   (_vram16x16_2_io_portA_dout),
    .layer2_line_data     (_lineRam_2_io_portA_dout),
    .layer2_vram8_data    (_vram8x8_2_io_portA_dout),
    .sound_data           (io_soundCtrl_reply),
    .sound_reply_empty    (io_soundCtrl_reply_empty),
    .sprite_ram_data      (_spriteRam_io_portA_dout),
    .prog_rom_data        (io_progRom_dout),
    .ss_hold              (mainControlStateHold),
    .ss_load              (mainControlRestoreLoad),
    .ss_state_in          (mainControlRestoreState[359:264]),
    .ss_state_out         (metmqstrGapState),
    .cpu_byte_addr        (metmqstrCpuByteAddr),
    .prog_rom_packed_addr (metmqstrProgRomPackedAddr),
    .prog_rom_select      (metmqstrProgRomSelect),
    .palette_select       (metmqstrPaletteSelect),
    .palette_ram_addr     (metmqstrPaletteRamAddr),
    .sprite_ram_select    (metmqstrSpriteRamSelect),
    .irq_read             (metmqstrIrqRead),
    .irq_word_offset      (metmqstrIrqWordOffset),
    .video_irq_clear      (metmqstrVideoIrqClear),
    .unknown_irq_clear    (metmqstrUnknownIrqClear),
    .sound_flags_read     (metmqstrSoundFlagsRead),
    .sound_read           (metmqstrSoundRead),
    .sound_write          (metmqstrSoundWrite),
    .input0_read          (metmqstrInput0Read),
    .input1_read          (metmqstrInput1Read),
    .eeprom_write         (metmqstrEepromWrite),
    .sprite_swap_write    (metmqstrSpriteSwapWrite),
    .prog_rom_read        (metmqstrProgRomRead),
    .palette_read         (metmqstrPaletteRead),
    .palette_write        (metmqstrPaletteWrite),
    .sprite_ram_read      (metmqstrSpriteRamRead),
    .sprite_ram_write     (metmqstrSpriteRamWrite),
    .layer0_vram16_read   (metmqstrLayer0Vram16Read),
    .layer0_vram16_write  (metmqstrLayer0Vram16Write),
    .layer0_line_read     (metmqstrLayer0LineRead),
    .layer0_line_write    (metmqstrLayer0LineWrite),
    .layer0_vram8_read    (metmqstrLayer0Vram8Read),
    .layer0_vram8_write   (metmqstrLayer0Vram8Write),
    .layer1_vram16_read   (metmqstrLayer1Vram16Read),
    .layer1_vram16_write  (metmqstrLayer1Vram16Write),
    .layer1_line_read     (metmqstrLayer1LineRead),
    .layer1_line_write    (metmqstrLayer1LineWrite),
    .layer1_vram8_read    (metmqstrLayer1Vram8Read),
    .layer1_vram8_write   (metmqstrLayer1Vram8Write),
    .layer2_vram16_read   (metmqstrLayer2Vram16Read),
    .layer2_vram16_write  (metmqstrLayer2Vram16Write),
    .layer2_line_read     (metmqstrLayer2LineRead),
    .layer2_line_write    (metmqstrLayer2LineWrite),
    .layer2_vram8_read    (metmqstrLayer2Vram8Read),
    .layer2_vram8_write   (metmqstrLayer2Vram8Write),
    .layer0_regs_write    (metmqstrLayer0RegsWrite),
    .layer1_regs_write    (metmqstrLayer1RegsWrite),
    .layer2_regs_write    (metmqstrLayer2RegsWrite),
    .sprite_regs_write    (metmqstrSpriteRegsWrite),
    .dtack                (metmqstrDtack),
    .read_data_valid      (metmqstrReadDataValid),
    .read_data            (metmqstrReadData)
  );

  assign hotdogSpriteRamRead = hotdogSpriteRamSelect & readStrobe;
  assign hotdogSpriteRamWrite = hotdogSpriteRamSelect & writeStrobe;

  wire mainRam_io_rd =
    (gameIsAirFamily & airGalletMainRamRead) |
    (gameIsMazinger & mazingerMainRamRead) |
    (gameIsHotdogStorm & hotdogMainRamRead);
  wire mainRam_io_wr =
    (gameIsAirFamily & airGalletMainRamWrite) |
    (gameIsMazinger & mazingerMainRamWrite) |
    (gameIsHotdogStorm & hotdogMainRamWrite);

  wire spriteRam_io_portA_rd =
    (gameIsAirFamily & airGalletSpriteRamRead) |
    (gameIsMazinger & mazingerSpriteRamRead) |
    (gameIsHotdogStorm & hotdogSpriteRamRead) |
    (gameIsMetmqstr & metmqstrSpriteRamRead);
  wire spriteRam_io_portA_wr =
    (gameIsAirFamily & airGalletSpriteRamWrite) |
    (gameIsMazinger & mazingerSpriteRamWrite) |
    (gameIsHotdogStorm & hotdogSpriteRamWrite) |
    (gameIsMetmqstr & metmqstrSpriteRamWrite);

  wire vram8x8_0_io_portA_rd =
    (gameIsAirFamily & airGalletLayer0Vram8OnlyRead) |
    (gameIsMazinger & mazingerLayer0Vram8Read) |
    (gameIsHotdogStorm & hotdogLayer0Vram8Read) |
    (gameIsMetmqstr & metmqstrLayer0Vram8Read);
  wire vram8x8_0_io_portA_wr =
    (gameIsAirFamily & airGalletLayer0Vram8OnlyWrite) |
    (gameIsMazinger & mazingerLayer0Vram8Write) |
    (gameIsHotdogStorm & hotdogLayer0Vram8Write) |
    (gameIsMetmqstr & metmqstrLayer0Vram8Write);
  wire vram8x8_1_io_portA_rd =
    (gameIsAirFamily & airGalletLayer1Vram8OnlyRead) |
    (gameIsMazinger & mazingerLayer1Vram8Read) |
    (gameIsHotdogStorm & hotdogLayer1Vram8Read) |
    (gameIsMetmqstr & metmqstrLayer1Vram8Read);
  wire vram8x8_1_io_portA_wr =
    (gameIsAirFamily & airGalletLayer1Vram8OnlyWrite) |
    (gameIsMazinger & mazingerLayer1Vram8Write) |
    (gameIsHotdogStorm & hotdogLayer1Vram8Write) |
    (gameIsMetmqstr & metmqstrLayer1Vram8Write);
  wire vram8x8_2_io_portA_rd =
    (gameIsAirFamily & airGalletLayer2Vram8OnlyRead) |
    (gameIsHotdogStorm & hotdogLayer2Vram8Read) |
    (gameIsMetmqstr & metmqstrLayer2Vram8Read);
  wire vram8x8_2_io_portA_wr =
    (gameIsAirFamily & airGalletLayer2Vram8OnlyWrite) |
    (gameIsHotdogStorm & hotdogLayer2Vram8Write) |
    (gameIsMetmqstr & metmqstrLayer2Vram8Write);
  wire [12:0] vram8x8_2_io_portA_addr = _cpu_io_addr[12:0];

  wire vram16x16_0_io_portA_rd =
    (gameIsAirFamily & airGalletLayer0Vram16Read) |
    (gameIsHotdogStorm & hotdogLayer0Vram16Read) |
    (gameIsMetmqstr & metmqstrLayer0Vram16Read);
  wire vram16x16_0_io_portA_wr =
    (gameIsAirFamily & airGalletLayer0Vram16Write) |
    (gameIsHotdogStorm & hotdogLayer0Vram16Write) |
    (gameIsMetmqstr & metmqstrLayer0Vram16Write);
  wire vram16x16_1_io_portA_rd =
    (gameIsAirFamily & airGalletLayer1Vram16Read) |
    (gameIsHotdogStorm & hotdogLayer1Vram16Read) |
    (gameIsMetmqstr & metmqstrLayer1Vram16Read);
  wire vram16x16_1_io_portA_wr =
    (gameIsAirFamily & airGalletLayer1Vram16Write) |
    (gameIsHotdogStorm & hotdogLayer1Vram16Write) |
    (gameIsMetmqstr & metmqstrLayer1Vram16Write);
  wire vram16x16_2_io_portA_rd =
    (gameIsAirFamily & airGalletLayer2Vram16Read) |
    (gameIsHotdogStorm & hotdogLayer2Vram16Read) |
    (gameIsMetmqstr & metmqstrLayer2Vram16Read);
  wire vram16x16_2_io_portA_wr =
    (gameIsAirFamily & airGalletLayer2Vram16Write) |
    (gameIsHotdogStorm & hotdogLayer2Vram16Write) |
    (gameIsMetmqstr & metmqstrLayer2Vram16Write);

  wire lineRam_0_io_portA_rd =
    (gameIsAirFamily & airGalletLayer0LineRead) |
    (gameIsHotdogStorm & hotdogLayer0LineRead) |
    (gameIsMetmqstr & metmqstrLayer0LineRead);
  wire lineRam_0_io_portA_wr =
    (gameIsAirFamily & airGalletLayer0LineWrite) |
    (gameIsHotdogStorm & hotdogLayer0LineWrite) |
    (gameIsMetmqstr & metmqstrLayer0LineWrite);
  wire lineRam_1_io_portA_rd =
    (gameIsAirFamily & airGalletLayer1LineRead) |
    (gameIsHotdogStorm & hotdogLayer1LineRead) |
    (gameIsMetmqstr & metmqstrLayer1LineRead);
  wire lineRam_1_io_portA_wr =
    (gameIsAirFamily & airGalletLayer1LineWrite) |
    (gameIsHotdogStorm & hotdogLayer1LineWrite) |
    (gameIsMetmqstr & metmqstrLayer1LineWrite);
  wire lineRam_2_io_portA_rd =
    (gameIsAirFamily & airGalletLayer2LineRead) |
    (gameIsHotdogStorm & hotdogLayer2LineRead) |
    (gameIsMetmqstr & metmqstrLayer2LineRead);
  wire lineRam_2_io_portA_wr =
    (gameIsAirFamily & airGalletLayer2LineWrite) |
    (gameIsHotdogStorm & hotdogLayer2LineWrite) |
    (gameIsMetmqstr & metmqstrLayer2LineWrite);

  wire paletteRam_io_portA_rd =
    (gameIsAirFamily & airGalletPaletteRead) |
    (gameIsMazinger & mazingerPaletteRead) |
    (gameIsHotdogStorm & hotdogPaletteRead) |
    (gameIsMetmqstr & metmqstrPaletteRead);
  wire paletteRam_io_portA_wr =
    (gameIsAirFamily & airGalletPaletteWrite) |
    (gameIsMazinger & mazingerPaletteWrite) |
    (gameIsHotdogStorm & hotdogPaletteWrite) |
    (gameIsMetmqstr & metmqstrPaletteWrite);
  wire [14:0] paletteRam_io_portA_addr =
    gameIsAirFamily ? airGalletPaletteRamAddr :
    gameIsMazinger ? mazingerPaletteRamAddr :
    gameIsHotdogStorm ? hotdogPaletteRamAddr :
    gameIsMetmqstr ? metmqstrPaletteRamAddr : 15'd0;

  wire layerRegs_0_io_mem_wr =
    (gameIsAirFamily & airGalletLayer0RegsWrite) |
    (gameIsMazinger & mazingerLayer0RegsWrite) |
    (gameIsHotdogStorm & hotdogLayer0RegsWrite) |
    (gameIsMetmqstr & metmqstrLayer0RegsWrite);
  wire layerRegs_1_io_mem_wr =
    (gameIsAirFamily & airGalletLayer1RegsWrite) |
    (gameIsMazinger & mazingerLayer1RegsWrite) |
    (gameIsHotdogStorm & hotdogLayer1RegsWrite) |
    (gameIsMetmqstr & metmqstrLayer1RegsWrite);
  wire layerRegs_2_io_mem_wr =
    (gameIsAirFamily & airGalletLayer2RegsWrite) |
    (gameIsHotdogStorm & hotdogLayer2RegsWrite) |
    (gameIsMetmqstr & metmqstrLayer2RegsWrite);

  wire spriteRegs_io_mem_wr =
    (gameIsAirFamily & airGalletSpriteRegsWrite) |
    (gameIsMazinger & mazingerSpriteRegsWrite) |
    (gameIsHotdogStorm & hotdogSpriteRegsWrite) |
    (gameIsMetmqstr & metmqstrSpriteRegsWrite);
  wire [2:0] spriteRegs_io_mem_addr = _cpu_io_addr[2:0];

  assign eepromMem_wr =
    (gameIsAirFamily & airGalletEepromWrite) |
    (gameIsMazinger & mazingerEepromWrite) |
    (gameIsHotdogStorm & hotdogEepromWrite) |
    (gameIsMetmqstr & metmqstrEepromWrite);
  assign io_sailorMoonTilebank = sailorMoonTilebankReg;

  always @(posedge clock) begin
    if (reset)
      sailorMoonTilebankReg <= 1'b0;
    else if (mainControlRestoreLoad)
      sailorMoonTilebankReg <= mainControlRestoreState[20];
    else if (!mainControlStateHold) begin
      if (~gameIsSailorMoon)
        sailorMoonTilebankReg <= 1'b0;
      else if (airGalletEepromWrite)
        sailorMoonTilebankReg <= cpuWriteByte[0];
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      videoIrq <= 1'b0;
      agalletIrq <= 1'b0;
      unknownIrq <= 1'b0;
      dinReg <= 16'h0000;
      dtackReg <= 1'b0;
    end
    else if (mainControlRestoreLoad) begin
      videoIrq <= mainControlRestoreState[0];
      agalletIrq <= mainControlRestoreState[1];
      unknownIrq <= mainControlRestoreState[2];
      dinReg <= mainControlRestoreState[18:3];
      dtackReg <= mainControlRestoreState[19];
    end
    else if (!mainControlStateHold) begin
      agalletIrq <= videoVBlankRising | (~videoVBlankFalling & agalletIrq);

      if (gameIsAirFamily) begin
        videoIrq <= (videoIrq | videoVBlankRising) & ~airGalletVideoIrqClear;
        unknownIrq <= unknownIrq & ~airGalletUnknownIrqClear;
      end
      else if (gameIsMazinger) begin
        videoIrq <= videoVBlankRising | (videoIrq & ~mazingerVideoIrqClear);
        unknownIrq <= (unknownIrq | videoVBlankRising) & ~mazingerUnknownIrqClear;
      end
      else if (gameIsHotdogStorm) begin
        videoIrq <= (videoIrq | videoVBlankRising) & ~hotdogVideoIrqClear;
        unknownIrq <= unknownIrq & ~hotdogUnknownIrqClear;
      end
      else if (gameIsMetmqstr) begin
        videoIrq <= (videoIrq | videoVBlankRising) & ~metmqstrVideoIrqClear;
        unknownIrq <= (unknownIrq | videoVBlankFalling) & ~metmqstrUnknownIrqClear;
      end
      else begin
        videoIrq <= 1'b0;
        unknownIrq <= 1'b0;
      end

      if (gameIsAirFamily) begin
        if (airGalletReadDataValid)
          dinReg <= airGalletReadData;
      end
      else if (gameIsMazinger) begin
        if (mazingerReadDataValid)
          dinReg <= mazingerReadData;
      end
      else if (gameIsHotdogStorm) begin
        if (hotdogReadDataValid)
          dinReg <= hotdogReadData;
      end
      else if (gameIsMetmqstr) begin
        if (metmqstrReadDataValid)
          dinReg <= metmqstrReadData;
      end
      else
        dinReg <= 16'h0000;

      dtackReg <=
        gameIsAirFamily ? airGalletDtack :
        gameIsMazinger ? mazingerDtack :
        gameIsHotdogStorm ? hotdogDtack :
        gameIsMetmqstr ? metmqstrDtack : 1'b0;
    end
  end // always @(posedge)

  wire mainCpuReset =
    gameIsMazinger ? mazingerCpuReset :
    gameIsMetmqstr ? metmqstrCpuReset :
                     reset;
`ifdef CAVE_ENABLE_DEBUG_OVERLAY
  reg  [63:0] mazingerDebugSeen;
  reg  [23:0] mazingerDebugLastAddr;
  reg  [23:0] mazingerDebugPrevAddr;
  reg  [23:0] mazingerDebugFirstUnmappedAddr;
  reg  [23:0] mazingerDebugFirstUnmappedProgAddr;
  reg  [23:0] mazingerDebugLastProgAddr;
  reg  [15:0] mazingerDebugLastDout;
  reg  [15:0] mazingerDebugLastDin;
  reg  [15:0] mazingerDebugVector0;
  reg  [15:0] mazingerDebugVector1;
  reg  [15:0] mazingerDebugVector2;
  reg  [15:0] mazingerDebugVector3;
  reg  [7:0]  mazingerDebugLastCtrl;
  reg  [7:0]  mazingerDebugLastUnmappedCtrl;
  reg  [7:0]  mazingerDebugFirstUnmappedStatus;
  reg  [7:0]  mazingerDebugLastSelect;
  reg  [7:0]  mazingerDebugReadSeen;
  reg  [7:0]  mazingerDebugWriteSeen;
  reg  [7:0]  mazingerDebugIrqSeen;
  reg  [7:0]  mazingerDebugMilestones;
  reg  [15:0] mazingerDebugSelfTestStatus;
  reg  [15:0] mazingerDebugFirstSpriteRamAddr;
  reg  [14:0] mazingerDebugFirstPaletteAddr;
  reg  [14:0] mazingerDebugLastPaletteAddr;
  reg  [14:0] mazingerDebugFirstPaletteAnyAddr;
  reg  [15:0] mazingerDebugFirstPaletteData;
  reg  [15:0] mazingerDebugLastPaletteData;
  reg  [15:0] mazingerDebugFirstPaletteAnyData;
  reg  [15:0] mazingerDebugFirstLayer0Reg0Data;
  reg  [15:0] mazingerDebugFirstLayer0Reg1Data;
  reg  [15:0] mazingerDebugFirstLayer1Reg0Data;
  reg  [15:0] mazingerDebugFirstLayer1Reg1Data;
  reg  [15:0] mazingerDebugPaletteSlot0Data;
  reg  [15:0] mazingerDebugPaletteSlot1Data;
  reg  [15:0] mazingerDebugPaletteSlot2Data;
  reg  [15:0] mazingerDebugPaletteSlot3Data;
  reg         mazingerDebugFirstUnmappedValid;
  reg         mazingerDebugSelfTestStatusValid;
  reg         mazingerDebugProgChecksumValid;
  reg         mazingerDebugExtraChecksumValid;
  reg         mazingerDebugFirstSpriteRamValid;
  reg         mazingerDebugFirstPaletteValid;
  reg         mazingerDebugFirstPaletteAnyValid;
  reg         mazingerDebugFirstLayer0Reg0Valid;
  reg         mazingerDebugFirstLayer0Reg1Valid;
  reg         mazingerDebugFirstLayer1Reg0Valid;
  reg         mazingerDebugFirstLayer1Reg1Valid;
  reg         mazingerDebugPaletteSlot0Valid;
  reg         mazingerDebugPaletteSlot1Valid;
  reg         mazingerDebugPaletteSlot2Valid;
  reg         mazingerDebugPaletteSlot3Valid;
  wire [7:0]  mazingerDebugSelectNow = {
    mazingerUnmappedCycle,
    mazingerPaletteSelect,
    mazingerLayer0Vram8Select | mazingerLayer1Vram8Select,
    mazingerLayer0RegsSelect | mazingerLayer1RegsSelect,
    mazingerVideoRegsSelect,
    mazingerSpriteRamSelect,
    mazingerMainRamSelect,
    mazingerProgRomAccess
  };
  wire [7:0]  mazingerDebugReadNow = {
    mazingerPaletteRead,
    mazingerLayer1RegsRead,
    mazingerLayer0RegsRead,
    mazingerLayer1Vram8Read,
    mazingerLayer0Vram8Read,
    mazingerSoundRead,
    mazingerInput1Read | mazingerInput0Read,
    mazingerIrqRead
  };
  wire [7:0]  mazingerDebugWriteNow = {
    mazingerVideoRegsWrite,
    mazingerSpriteRegsWrite,
    mazingerPaletteWrite,
    mazingerLayer1RegsWrite,
    mazingerLayer0RegsWrite,
    mazingerLayer1Vram8Write | mazingerLayer0Vram8Write,
    mazingerSpriteRamWrite,
    mazingerMainRamWrite
  };
  wire [7:0]  mazingerDebugIrqNow = {
    pauseActive,
    _cpu_io_vpa,
    |(_cpu_io_ipl),
    io_video_vBlank,
    videoVBlankRising,
    agalletIrq,
    unknownIrq,
    videoIrq
  };
  wire [7:0]  mazingerDebugPipelineRow0 = {
    cpuByteAddr != mazingerDebugPrevAddr,
    mazingerProgRomReady,
    io_progRom_valid,
    io_progRom_rd,
    dtackReg,
    writeStrobe,
    readStrobe,
    mazingerCycle
  };
  wire [7:0]  mazingerDebugPipelineRow5 = {
    mazingerBootWatchdogArmed,
    mazingerBootWatchdogResetActive,
    mazingerBootWatchdogDelayActive,
    mazingerBootMarkerWrite,
    mazingerSoundRead,
    mazingerVideoRegsRead,
    mazingerVideoRegsWrite,
    mazingerEepromWrite
  };
  wire [7:0]  mazingerDebugPipelineRow6 = {
    io_soundCtrl_irq,
    io_eeprom_wait_n,
    io_eeprom_valid,
    io_progRom_valid,
    mazingerDtack,
    mazingerSyncDtack,
    mazingerProgRomReady,
    mazingerUnmappedCycle
  };
  wire [63:0] mazingerDebugEventBits = {
    mazingerDebugMilestones,
    mazingerDebugPipelineRow6,
    mazingerDebugPipelineRow5,
    mazingerDebugIrqNow,
    mazingerDebugWriteNow,
    mazingerDebugReadNow,
    mazingerDebugSelectNow,
    mazingerDebugPipelineRow0
  };
  wire [63:0] mazingerDebugCpuBits = {
    mazingerDebugIrqSeen,
    mazingerDebugWriteSeen,
    mazingerDebugReadSeen,
    mazingerDebugLastSelect,
    mazingerDebugLastCtrl,
    mazingerDebugLastAddr[7:0],
    mazingerDebugLastAddr[15:8],
    mazingerDebugLastAddr[23:16]
  };
  wire [63:0] mazingerDebugWriteBits = {
    mazingerDebugFirstSpriteRamAddr[7:0],
    mazingerDebugFirstSpriteRamAddr[15:8],
    mazingerDebugSelfTestStatus[7:0],
    mazingerDebugSelfTestStatus[15:8],
    {1'b0, mazingerDebugExtraChecksumValid, mazingerDebugProgChecksumValid,
     mazingerDebugSelfTestStatusValid, mazingerDebugFirstSpriteRamValid,
     mazingerDebugIrqSeen[2:0]},
    mazingerDebugWriteSeen,
    mazingerDebugReadSeen,
    mazingerDebugLastSelect
  };
  wire [7:0]  mazingerDebugFaultStatusNow = {
    mazingerDebugFirstUnmappedValid | mazingerOpenBusSelect,
    mazingerOpenBusSelect,
    mazingerUnmappedCycle,
    mazingerCpuSpace,
    mazingerNoOpSelect,
    mazingerEepromCycle,
    mazingerInput0Cycle | mazingerInput1Cycle,
    mazingerMainRamSelect
  };
  wire [7:0]  mazingerDebugPostFlags = {
    mazingerDebugFirstUnmappedValid,
    mazingerOpenBusSelect,
    mazingerSoundRead,
    mazingerSpriteSwapWrite,
    mazingerVideoRegsWrite,
    mazingerPaletteWrite,
    |(_cpu_io_ipl),
    io_video_vBlank
  };
  wire [63:0] mazingerDebugDataBits = {
    mazingerDebugMilestones,
    mazingerDebugPostFlags,
    mazingerDebugLastAddr[7:0],
    mazingerDebugLastAddr[15:8],
    mazingerDebugLastAddr[23:16],
    mazingerDebugLastProgAddr[7:0],
    mazingerDebugLastProgAddr[15:8],
    mazingerDebugLastProgAddr[23:16]
  };
  wire [63:0] mazingerDebugPaletteBits = {
    mazingerDebugPaletteSlot3Data[15:8],
    mazingerDebugPaletteSlot3Data[7:0],
    mazingerDebugPaletteSlot2Data[15:8],
    mazingerDebugPaletteSlot2Data[7:0],
    mazingerDebugPaletteSlot1Data[15:8],
    mazingerDebugPaletteSlot1Data[7:0],
    mazingerDebugPaletteSlot0Data[15:8],
    mazingerDebugPaletteSlot0Data[7:0]
  };
  wire [63:0] mazingerDebugLiveBits = {
    mazingerDebugFirstLayer1Reg1Data[15:8],
    mazingerDebugFirstLayer1Reg1Data[7:0],
    mazingerDebugFirstLayer1Reg0Data[15:8],
    mazingerDebugFirstLayer1Reg0Data[7:0],
    mazingerDebugFirstLayer0Reg1Data[15:8],
    mazingerDebugFirstLayer0Reg1Data[7:0],
    mazingerDebugFirstLayer0Reg0Data[15:8],
    mazingerDebugFirstLayer0Reg0Data[7:0]
  };

  reg  [63:0] airGalletDebugSeen;
  reg  [23:0] airGalletDebugLastAddr;
  reg  [23:0] airGalletDebugPrevAddr;
  reg  [23:0] airGalletDebugLastProgAddr;
  reg  [15:0] airGalletDebugLastDout;
  reg  [15:0] airGalletDebugLastDin;
  reg  [7:0]  airGalletDebugLastSelect;
  reg  [7:0]  airGalletDebugReadSeen;
  reg  [7:0]  airGalletDebugWriteSeen;
  reg  [7:0]  airGalletDebugIrqSeen;
  reg  [7:0]  airGalletDebugMilestones;
  reg  [7:0]  airGalletDebugLayer0Seen;
  reg  [7:0]  airGalletDebugLayer1Seen;
  reg  [7:0]  airGalletDebugLayer2Seen;
  reg         airGalletDebugFirstUnmappedValid;
  reg  [23:0] airGalletDebugFirstUnmappedAddr;
  reg  [7:0]  airGalletDebugLastSelectExt;
  reg  [7:0]  airGalletDebugSelectExtSeen;
  reg  [7:0]  airGalletDebugLastControl;
  reg  [7:0]  airGalletDebugControlSeen;
  reg  [7:0]  airGalletDebugAddrChangeCount;
  reg  [7:0]  airGalletDebugSameAddrCount;
  reg  [23:0] airGalletDebugLastNoDtackAddr;
  reg  [7:0]  airGalletDebugLastNoDtackSelect;
  reg  [7:0]  airGalletDebugLastNoDtackSelectExt;
  reg  [7:0]  airGalletDebugLastNoDtackControl;

  wire [7:0] airGalletDebugPipelineRow0 = {
    airGalletCpuByteAddr != airGalletDebugPrevAddr,
    airGalletProgRomReady,
    io_progRom_valid,
    io_progRom_rd,
    airGalletDtack,
    writeStrobe,
    readStrobe,
    airGalletCycle
  };
  wire [7:0] airGalletDebugSelectNow = {
    airGalletProgRomSelect,
    airGalletExtraRomSelect,
    airGalletMainRamSelect,
    airGalletSpriteRamSelect,
    airGalletPaletteSelect,
    airGalletLayer0Vram8Select,
    airGalletLayer1Vram8Select,
    airGalletLayer2Vram8Select
  };
  wire [7:0] airGalletDebugSelectExtNow = {
    airGalletWorkRamSelect,
    airGalletLayer0RegsSelect,
    airGalletLayer1RegsSelect,
    airGalletLayer2RegsSelect,
    airGalletSpriteRegsWrite,
    airGalletSoundWrite | airGalletSoundRead | airGalletSoundFlagsRead,
    airGalletInput0Read | airGalletInput1Read,
    airGalletOpenBusSelect
  };
  wire [7:0] airGalletDebugControlNow = {
    _cpu_io_fc,
    _cpu_io_as,
    _cpu_io_rw,
    _cpu_io_uds,
    _cpu_io_lds,
    airGalletDtack
  };
  wire [7:0] airGalletDebugReadNow = {
    airGalletInput0Read,
    airGalletInput1Read,
    airGalletPaletteRead,
    airGalletIrqRead,
    airGalletSoundFlagsRead,
    airGalletSoundRead,
    io_soundCtrl_reply != 16'h00ff,
    airGalletOpenBusSelect
  };
  wire [7:0] airGalletDebugWriteNow = {
    airGalletMainRamWrite,
    airGalletSpriteRamWrite,
    airGalletPaletteWrite,
    airGalletLayer0Vram8Write,
    airGalletLayer1Vram8Write,
    airGalletLayer2Vram8Write,
    airGalletSoundWrite,
    airGalletEepromWrite | airGalletSpriteSwapWrite
  };
  wire [7:0] airGalletDebugIrqNow = {
    pauseActive,
    _cpu_io_vpa,
    |(_cpu_io_ipl),
    io_video_vBlank,
    videoVBlankRising,
    agalletIrq,
    unknownIrq,
    videoIrq
  };
  wire [7:0] airGalletDebugPipelineRow5 = {
    io_soundCtrl_req,
    io_soundCtrl_reply_rd,
    io_soundCtrl_irq,
    io_eeprom_wait_n,
    io_eeprom_valid,
    airGalletSpriteSwapWrite,
    airGalletSyncDtack,
    airGalletUnmappedCycle
  };
  wire [7:0] airGalletDebugLayer0Now = {
    airGalletLayer0RegsWrite,
    airGalletLayer0Vram8OnlyWrite,
    airGalletLayer0ScratchWrite,
    airGalletLayer0LineWrite,
    airGalletLayer0Vram16Write,
    io_gpuMem_layer_0_regs_r_1_enable,
    io_gpuMem_layer_0_regs_r_1_tileSize,
    io_gpuMem_layer_0_regs_r_1_rowSelectEnable
  };
  wire [7:0] airGalletDebugLayer1Now = {
    airGalletLayer1RegsWrite,
    airGalletLayer1Vram8OnlyWrite,
    airGalletLayer1ScratchWrite,
    airGalletLayer1LineWrite,
    airGalletLayer1Vram16Write,
    io_gpuMem_layer_1_regs_r_1_enable,
    io_gpuMem_layer_1_regs_r_1_tileSize,
    io_gpuMem_layer_1_regs_r_1_rowSelectEnable
  };
  wire [7:0] airGalletDebugLayer2Now = {
    airGalletLayer2RegsWrite,
    airGalletLayer2Vram8OnlyWrite,
    airGalletLayer2ScratchWrite,
    airGalletLayer2LineWrite,
    airGalletLayer2Vram16Write,
    io_gpuMem_layer_2_regs_r_1_enable,
    io_gpuMem_layer_2_regs_r_1_tileSize,
    io_gpuMem_layer_2_regs_r_1_rowSelectEnable
  };
  wire [7:0] airGalletDebugLayerStatus = {
    io_gpuMem_layer_2_regs_r_1_enable,
    io_gpuMem_layer_2_regs_r_1_tileSize,
    io_gpuMem_layer_1_regs_r_1_enable,
    io_gpuMem_layer_1_regs_r_1_tileSize,
    io_gpuMem_layer_0_regs_r_1_enable,
    io_gpuMem_layer_0_regs_r_1_tileSize,
    airGalletTilemapVram8,
    airGalletTilemapVram16 | airGalletTilemapLine | airGalletTilemapScratch
  };
  wire [63:0] airGalletDebugEventBits = {
    airGalletDebugMilestones,
    airGalletDebugPipelineRow5,
    airGalletDebugIrqNow,
    airGalletDebugWriteNow,
    airGalletDebugReadNow,
    airGalletDebugSelectExtNow,
    airGalletDebugSelectNow,
    airGalletDebugPipelineRow0
  };
  wire [63:0] airGalletDebugCpuBits = {
    airGalletDebugLastNoDtackAddr[23:16],
    airGalletDebugLastNoDtackAddr[15:8],
    airGalletDebugLastNoDtackAddr[7:0],
    airGalletDebugLastAddr[23:16],
    airGalletDebugLastAddr[15:8],
    airGalletDebugLastAddr[7:0],
    airGalletDebugLastNoDtackSelect,
    airGalletDebugLastNoDtackSelectExt
  };
  wire [63:0] airGalletDebugWriteBits = {
    airGalletDebugLastDout[15:8],
    airGalletDebugLastDout[7:0],
    airGalletDebugLastDin[15:8],
    airGalletDebugLastDin[7:0],
    airGalletDebugLastSelect,
    airGalletDebugLastSelectExt,
    airGalletDebugReadSeen,
    airGalletDebugWriteSeen
  };
  wire [63:0] airGalletDebugDataBits = {
    airGalletDebugFirstUnmappedAddr[23:16],
    airGalletDebugFirstUnmappedAddr[15:8],
    airGalletDebugFirstUnmappedAddr[7:0],
    airGalletDebugLastProgAddr[23:16],
    airGalletDebugLastProgAddr[15:8],
    airGalletDebugLastProgAddr[7:0],
    airGalletDebugMilestones,
    {7'h0, airGalletDebugFirstUnmappedValid}
  };
  wire [63:0] airGalletDebugLiveBits = {
    airGalletDebugLayerStatus,
    airGalletDebugLayer2Now,
    airGalletDebugLayer2Seen,
    airGalletDebugSelectExtSeen,
    airGalletDebugLastControl,
    airGalletDebugLastNoDtackControl,
    airGalletDebugMilestones,
    airGalletDebugIrqSeen
  };
  wire [63:0] airGalletDebugPaletteBits = {
    _layerRegs_2_io_regs_0[15:8],
    _layerRegs_2_io_regs_0[7:0],
    _layerRegs_2_io_regs_1[15:8],
    _layerRegs_2_io_regs_1[7:0],
    _layerRegs_2_io_regs_2[15:8],
    _layerRegs_2_io_regs_2[7:0],
    airGalletDebugLayer0Now,
    airGalletDebugLayer1Now
  };

  reg  [63:0] hotdogDebugSeen;
  reg  [23:0] hotdogDebugLastAddr;
  reg  [23:0] hotdogDebugPrevAddr;
  reg  [23:0] hotdogDebugLastProgAddr;
  reg  [15:0] hotdogDebugLastDout;
  reg  [15:0] hotdogDebugLastDin;
  reg  [15:0] hotdogDebugVector0;
  reg  [15:0] hotdogDebugVector1;
  reg  [15:0] hotdogDebugVector2;
  reg  [15:0] hotdogDebugVector3;
  reg  [7:0]  hotdogDebugLastSelect;
  reg  [7:0]  hotdogDebugLastSelectExt;
  reg  [7:0]  hotdogDebugReadSeen;
  reg  [7:0]  hotdogDebugWriteSeen;
  reg  [7:0]  hotdogDebugIrqSeen;
  reg  [7:0]  hotdogDebugMilestones;
  reg  [7:0]  hotdogDebugLastControl;
  reg  [7:0]  hotdogDebugControlSeen;
  reg  [7:0]  hotdogDebugAddrChangeCount;
  reg  [7:0]  hotdogDebugSameAddrCount;

  wire        hotdogLayerRead =
    hotdogLayer0Vram16Read | hotdogLayer0LineRead | hotdogLayer0Vram8Read |
    hotdogLayer1Vram16Read | hotdogLayer1LineRead | hotdogLayer1Vram8Read |
    hotdogLayer2Vram16Read | hotdogLayer2LineRead | hotdogLayer2Vram8Read;
  wire        hotdogLayerWrite =
    hotdogLayer0Vram16Write | hotdogLayer0LineWrite | hotdogLayer0Vram8Write |
    hotdogLayer1Vram16Write | hotdogLayer1LineWrite | hotdogLayer1Vram8Write |
    hotdogLayer2Vram16Write | hotdogLayer2LineWrite | hotdogLayer2Vram8Write;
  wire        hotdogLayerRegsWrite =
    hotdogLayer0RegsWrite | hotdogLayer1RegsWrite | hotdogLayer2RegsWrite;
  wire [7:0] hotdogDebugPipelineRow0 = {
    hotdogCpuByteAddr != hotdogDebugPrevAddr,
    hotdogProgRomSelect,
    io_progRom_valid,
    io_progRom_rd,
    hotdogDtack,
    writeStrobe,
    readStrobe,
    gameIsHotdogStorm
  };
  wire [7:0] hotdogDebugSelectNow = {
    hotdogPaletteSelect,
    hotdogSpriteRamSelect,
    hotdogMainRamSelect,
    hotdogProgRomSelect,
    hotdogIrqRead,
    hotdogInput0Read | hotdogInput1Read,
    hotdogEepromWrite,
    hotdogSoundWrite
  };
  wire [7:0] hotdogDebugSelectExtNow = {
    hotdogLayer2RegsWrite,
    hotdogLayer1RegsWrite,
    hotdogLayer0RegsWrite,
    hotdogLayer2Vram16Read | hotdogLayer2LineRead | hotdogLayer2Vram8Read |
      hotdogLayer2Vram16Write | hotdogLayer2LineWrite | hotdogLayer2Vram8Write,
    hotdogLayer1Vram16Read | hotdogLayer1LineRead | hotdogLayer1Vram8Read |
      hotdogLayer1Vram16Write | hotdogLayer1LineWrite | hotdogLayer1Vram8Write,
    hotdogLayer0Vram16Read | hotdogLayer0LineRead | hotdogLayer0Vram8Read |
      hotdogLayer0Vram16Write | hotdogLayer0LineWrite | hotdogLayer0Vram8Write,
    hotdogSpriteRegsWrite,
    hotdogSpriteSwapWrite
  };
  wire [7:0] hotdogDebugReadNow = {
    hotdogInput0Read,
    hotdogInput1Read,
    hotdogPaletteRead,
    hotdogIrqRead,
    hotdogLayerRead,
    hotdogSpriteRamRead,
    hotdogMainRamRead,
    hotdogProgRomRead & io_progRom_valid
  };
  wire [7:0] hotdogDebugWriteNow = {
    hotdogSoundWrite,
    hotdogEepromWrite,
    hotdogPaletteWrite,
    hotdogSpriteRegsWrite,
    hotdogLayerRegsWrite,
    hotdogLayerWrite,
    hotdogSpriteRamWrite,
    hotdogMainRamWrite
  };
  wire [7:0] hotdogDebugIrqNow = {
    pauseActive,
    _cpu_io_vpa,
    |(_cpu_io_ipl),
    io_video_vBlank,
    videoVBlankRising,
    agalletIrq,
    unknownIrq,
    videoIrq
  };
  wire [7:0] hotdogDebugControlNow = {
    _cpu_io_fc,
    _cpu_io_as,
    _cpu_io_rw,
    _cpu_io_uds,
    _cpu_io_lds,
    hotdogDtack
  };
  wire [7:0] hotdogDebugPipelineRow5 = {
    io_soundCtrl_req,
    io_soundCtrl_irq,
    io_eeprom_wait_n,
    io_eeprom_valid,
    hotdogSpriteSwapWrite,
    videoVBlankRising,
    unknownIrq,
    videoIrq
  };
  wire [63:0] hotdogDebugEventBits = {
    hotdogDebugMilestones,
    hotdogDebugPipelineRow5,
    hotdogDebugIrqNow,
    hotdogDebugWriteNow,
    hotdogDebugReadNow,
    hotdogDebugSelectExtNow,
    hotdogDebugSelectNow,
    hotdogDebugPipelineRow0
  };
  wire [63:0] hotdogDebugCpuBits = {
    hotdogDebugLastSelectExt,
    hotdogDebugLastSelect,
    hotdogDebugLastAddr[7:0],
    hotdogDebugLastAddr[15:8],
    hotdogDebugLastAddr[23:16],
    hotdogDebugLastProgAddr[7:0],
    hotdogDebugLastProgAddr[15:8],
    hotdogDebugLastProgAddr[23:16]
  };
  wire [63:0] hotdogDebugWriteBits = {
    hotdogDebugMilestones,
    hotdogDebugIrqSeen,
    hotdogDebugLastDin[7:0],
    hotdogDebugLastDin[15:8],
    hotdogDebugLastDout[7:0],
    hotdogDebugLastDout[15:8],
    hotdogDebugReadSeen,
    hotdogDebugWriteSeen
  };
  wire [63:0] hotdogDebugDataBits = {
    hotdogDebugVector3[7:0],
    hotdogDebugVector3[15:8],
    hotdogDebugVector2[7:0],
    hotdogDebugVector2[15:8],
    hotdogDebugVector1[7:0],
    hotdogDebugVector1[15:8],
    hotdogDebugVector0[7:0],
    hotdogDebugVector0[15:8]
  };
  wire [63:0] hotdogDebugLiveBits = {
    hotdogDebugAddrChangeCount,
    hotdogDebugSameAddrCount,
    hotdogDebugMilestones,
    hotdogDebugIrqSeen,
    hotdogDebugLastControl,
    hotdogDebugControlSeen,
    hotdogDebugReadSeen,
    hotdogDebugWriteSeen
  };
  wire [63:0] hotdogDebugPaletteBits = {
    _layerRegs_2_io_regs_0[15:8],
    _layerRegs_2_io_regs_0[7:0],
    _layerRegs_1_io_regs_0[15:8],
    _layerRegs_1_io_regs_0[7:0],
    _layerRegs_0_io_regs_0[15:8],
    _layerRegs_0_io_regs_0[7:0],
    _spriteRegs_io_regs_0[15:8],
    _spriteRegs_io_regs_0[7:0]
  };
`endif
`ifdef CAVE_ENABLE_DEBUG_OVERLAY
  always @(posedge clock) begin
    if (reset | ~gameIsMazinger) begin
      mazingerDebugSeen <= 64'd0;
      mazingerDebugLastAddr <= 24'd0;
      mazingerDebugPrevAddr <= 24'd0;
      mazingerDebugFirstUnmappedAddr <= 24'd0;
      mazingerDebugFirstUnmappedProgAddr <= 24'd0;
      mazingerDebugLastProgAddr <= 24'd0;
      mazingerDebugLastDout <= 16'd0;
      mazingerDebugLastDin <= 16'd0;
      mazingerDebugVector0 <= 16'hffff;
      mazingerDebugVector1 <= 16'hffff;
      mazingerDebugVector2 <= 16'hffff;
      mazingerDebugVector3 <= 16'hffff;
      mazingerDebugLastCtrl <= 8'd0;
      mazingerDebugLastUnmappedCtrl <= 8'd0;
      mazingerDebugFirstUnmappedStatus <= 8'd0;
      mazingerDebugLastSelect <= 8'd0;
      mazingerDebugReadSeen <= 8'd0;
      mazingerDebugWriteSeen <= 8'd0;
      mazingerDebugIrqSeen <= 8'd0;
      mazingerDebugMilestones <= 8'd0;
      mazingerDebugSelfTestStatus <= 16'd0;
      mazingerDebugFirstSpriteRamAddr <= 16'd0;
      mazingerDebugFirstPaletteAddr <= 15'd0;
      mazingerDebugLastPaletteAddr <= 15'd0;
      mazingerDebugFirstPaletteAnyAddr <= 15'd0;
      mazingerDebugFirstPaletteData <= 16'd0;
      mazingerDebugLastPaletteData <= 16'd0;
      mazingerDebugFirstPaletteAnyData <= 16'd0;
      mazingerDebugFirstLayer0Reg0Data <= 16'd0;
      mazingerDebugFirstLayer0Reg1Data <= 16'd0;
      mazingerDebugFirstLayer1Reg0Data <= 16'd0;
      mazingerDebugFirstLayer1Reg1Data <= 16'd0;
      mazingerDebugPaletteSlot0Data <= 16'hffff;
      mazingerDebugPaletteSlot1Data <= 16'hffff;
      mazingerDebugPaletteSlot2Data <= 16'hffff;
      mazingerDebugPaletteSlot3Data <= 16'hffff;
      mazingerDebugFirstUnmappedValid <= 1'b0;
      mazingerDebugSelfTestStatusValid <= 1'b0;
      mazingerDebugProgChecksumValid <= 1'b0;
      mazingerDebugExtraChecksumValid <= 1'b0;
      mazingerDebugFirstSpriteRamValid <= 1'b0;
      mazingerDebugFirstPaletteValid <= 1'b0;
      mazingerDebugFirstPaletteAnyValid <= 1'b0;
      mazingerDebugFirstLayer0Reg0Valid <= 1'b0;
      mazingerDebugFirstLayer0Reg1Valid <= 1'b0;
      mazingerDebugFirstLayer1Reg0Valid <= 1'b0;
      mazingerDebugFirstLayer1Reg1Valid <= 1'b0;
      mazingerDebugPaletteSlot0Valid <= 1'b0;
      mazingerDebugPaletteSlot1Valid <= 1'b0;
      mazingerDebugPaletteSlot2Valid <= 1'b0;
      mazingerDebugPaletteSlot3Valid <= 1'b0;
    end
    else begin
      mazingerDebugSeen <= mazingerDebugSeen | mazingerDebugEventBits;
      mazingerDebugReadSeen <= mazingerDebugReadSeen | mazingerDebugReadNow;
      mazingerDebugWriteSeen <= mazingerDebugWriteSeen | mazingerDebugWriteNow;
      mazingerDebugIrqSeen <= mazingerDebugIrqSeen | mazingerDebugIrqNow;

      if (mazingerCycle) begin
        mazingerDebugPrevAddr <= mazingerDebugLastAddr;
        mazingerDebugLastAddr <= cpuByteAddr;
        mazingerDebugLastCtrl <= {
          _cpu_io_fc,
          dtackReg,
          _cpu_io_lds,
          _cpu_io_uds,
          _cpu_io_rw,
          _cpu_io_as
        };
        mazingerDebugLastSelect <= mazingerDebugSelectNow;
      end

      if (mazingerOpenBusSelect) begin
        mazingerDebugMilestones[7] <= 1'b1;
        if (~mazingerDebugFirstUnmappedValid) begin
          mazingerDebugFirstUnmappedValid <= 1'b1;
          mazingerDebugFirstUnmappedAddr <= cpuByteAddr;
          mazingerDebugFirstUnmappedProgAddr <= mazingerDebugLastProgAddr;
          mazingerDebugFirstUnmappedStatus <= mazingerDebugFaultStatusNow;
        end
        mazingerDebugLastUnmappedCtrl <= {
          _cpu_io_fc,
          dtackReg,
          _cpu_io_lds,
          _cpu_io_uds,
          _cpu_io_rw,
          _cpu_io_as
        };
      end

      if (mazingerBootWatchdogTrip)
        mazingerDebugMilestones[1] <= 1'b1;

      if (readStrobe | writeStrobe)
        mazingerDebugLastDout <= _cpu_io_dout;
      if (readStrobe)
        mazingerDebugLastDin <= dinReg;
      if (mazingerLayer0RegsWrite & (cpuByteAddr[3:1] == 3'h0) & ~mazingerDebugFirstLayer0Reg0Valid) begin
        mazingerDebugFirstLayer0Reg0Valid <= 1'b1;
        mazingerDebugFirstLayer0Reg0Data <= _cpu_io_dout;
      end
      if (mazingerLayer0RegsWrite & (cpuByteAddr[3:1] == 3'h1) & ~mazingerDebugFirstLayer0Reg1Valid) begin
        mazingerDebugFirstLayer0Reg1Valid <= 1'b1;
        mazingerDebugFirstLayer0Reg1Data <= _cpu_io_dout;
      end
      if (mazingerLayer1RegsWrite & (cpuByteAddr[3:1] == 3'h0) & ~mazingerDebugFirstLayer1Reg0Valid) begin
        mazingerDebugFirstLayer1Reg0Valid <= 1'b1;
        mazingerDebugFirstLayer1Reg0Data <= _cpu_io_dout;
      end
      if (mazingerLayer1RegsWrite & (cpuByteAddr[3:1] == 3'h1) & ~mazingerDebugFirstLayer1Reg1Valid) begin
        mazingerDebugFirstLayer1Reg1Valid <= 1'b1;
        mazingerDebugFirstLayer1Reg1Data <= _cpu_io_dout;
      end
      if (mazingerPaletteWrite) begin
        mazingerDebugLastPaletteAddr <= mazingerPaletteRamAddr;
        mazingerDebugLastPaletteData <= _cpu_io_dout;
        if (~mazingerDebugFirstPaletteAnyValid) begin
          mazingerDebugFirstPaletteAnyValid <= 1'b1;
          mazingerDebugFirstPaletteAnyAddr <= mazingerPaletteRamAddr;
          mazingerDebugFirstPaletteAnyData <= _cpu_io_dout;
        end
        if ((|_cpu_io_dout) & ~mazingerDebugFirstPaletteValid) begin
          mazingerDebugFirstPaletteValid <= 1'b1;
          mazingerDebugFirstPaletteAddr <= mazingerPaletteRamAddr;
          mazingerDebugFirstPaletteData <= _cpu_io_dout;
        end
        case (mazingerPaletteRamAddr)
          15'h0000:
            if (~mazingerDebugPaletteSlot0Valid) begin
              mazingerDebugPaletteSlot0Valid <= 1'b1;
              mazingerDebugPaletteSlot0Data <= _cpu_io_dout;
            end
          15'h0001:
            if (~mazingerDebugPaletteSlot1Valid) begin
              mazingerDebugPaletteSlot1Valid <= 1'b1;
              mazingerDebugPaletteSlot1Data <= _cpu_io_dout;
            end
          15'h0002:
            if (~mazingerDebugPaletteSlot2Valid) begin
              mazingerDebugPaletteSlot2Valid <= 1'b1;
              mazingerDebugPaletteSlot2Data <= _cpu_io_dout;
            end
          15'h0003:
            if (~mazingerDebugPaletteSlot3Valid) begin
              mazingerDebugPaletteSlot3Valid <= 1'b1;
              mazingerDebugPaletteSlot3Data <= _cpu_io_dout;
            end
          default: begin
          end
        endcase
      end
      if (mazingerSpriteRamWrite & ~mazingerDebugFirstSpriteRamValid) begin
        mazingerDebugFirstSpriteRamValid <= 1'b1;
        mazingerDebugFirstSpriteRamAddr <= cpuByteAddr[15:0];
      end
      if (mazingerMainRamWrite) begin
        if (
          (cpuByteAddr == 24'h1040c0) & mazingerDebugProgChecksumValid
          & mazingerDebugExtraChecksumValid & ~mazingerDebugSelfTestStatusValid
        ) begin
          mazingerDebugSelfTestStatus <= _cpu_io_dout;
          mazingerDebugSelfTestStatusValid <= 1'b1;
        end
        if ((cpuByteAddr == 24'h1040c2) & ~mazingerDebugProgChecksumValid)
          mazingerDebugProgChecksumValid <= 1'b1;
        if ((cpuByteAddr == 24'h1040c4) & ~mazingerDebugExtraChecksumValid)
          mazingerDebugExtraChecksumValid <= 1'b1;
      end
      if (mazingerProgRomReady) begin
        mazingerDebugLastProgAddr <= {2'h0, io_progRom_addr};
        case (io_progRom_addr)
          20'h001D94:
            mazingerDebugMilestones[0] <= 1'b1;
          20'h001E62:
            mazingerDebugMilestones[2] <= 1'b1;
          20'h001F5E:
            mazingerDebugMilestones[3] <= 1'b1;
          20'h002064:
            mazingerDebugMilestones[4] <= 1'b1;
          20'h0020A8:
            mazingerDebugMilestones[5] <= 1'b1;
          20'h006EA8, 20'h006EAA:
            mazingerDebugMilestones[6] <= 1'b1;
          default: begin
          end
        endcase
        case (io_progRom_addr)
          20'h00000: mazingerDebugVector0 <= io_progRom_dout;
          20'h00002: mazingerDebugVector1 <= io_progRom_dout;
          20'h00004: mazingerDebugVector2 <= io_progRom_dout;
          20'h00006: mazingerDebugVector3 <= io_progRom_dout;
          default: begin
          end
        endcase
      end
    end
  end
  always @(posedge clock) begin
    if (reset | ~gameIsAirFamily) begin
      airGalletDebugSeen <= 64'd0;
      airGalletDebugLastAddr <= 24'd0;
      airGalletDebugPrevAddr <= 24'd0;
      airGalletDebugLastProgAddr <= 24'd0;
      airGalletDebugLastDout <= 16'd0;
      airGalletDebugLastDin <= 16'd0;
      airGalletDebugLastSelect <= 8'd0;
      airGalletDebugReadSeen <= 8'd0;
      airGalletDebugWriteSeen <= 8'd0;
      airGalletDebugIrqSeen <= 8'd0;
      airGalletDebugMilestones <= 8'd0;
      airGalletDebugLayer0Seen <= 8'd0;
      airGalletDebugLayer1Seen <= 8'd0;
      airGalletDebugLayer2Seen <= 8'd0;
      airGalletDebugFirstUnmappedValid <= 1'b0;
      airGalletDebugFirstUnmappedAddr <= 24'd0;
      airGalletDebugLastSelectExt <= 8'd0;
      airGalletDebugSelectExtSeen <= 8'd0;
      airGalletDebugLastControl <= 8'd0;
      airGalletDebugControlSeen <= 8'd0;
      airGalletDebugAddrChangeCount <= 8'd0;
      airGalletDebugSameAddrCount <= 8'd0;
      airGalletDebugLastNoDtackAddr <= 24'd0;
      airGalletDebugLastNoDtackSelect <= 8'd0;
      airGalletDebugLastNoDtackSelectExt <= 8'd0;
      airGalletDebugLastNoDtackControl <= 8'd0;
    end
    else begin
      airGalletDebugSeen <= airGalletDebugSeen | airGalletDebugEventBits;
      airGalletDebugReadSeen <= airGalletDebugReadSeen | airGalletDebugReadNow;
      airGalletDebugWriteSeen <= airGalletDebugWriteSeen | airGalletDebugWriteNow;
      airGalletDebugIrqSeen <= airGalletDebugIrqSeen | airGalletDebugIrqNow;
      airGalletDebugLayer0Seen <= airGalletDebugLayer0Seen | airGalletDebugLayer0Now;
      airGalletDebugLayer1Seen <= airGalletDebugLayer1Seen | airGalletDebugLayer1Now;
      airGalletDebugLayer2Seen <= airGalletDebugLayer2Seen | airGalletDebugLayer2Now;
      airGalletDebugSelectExtSeen <= airGalletDebugSelectExtSeen | airGalletDebugSelectExtNow;
      airGalletDebugControlSeen <= airGalletDebugControlSeen | airGalletDebugControlNow;

      if (airGalletCycle) begin
        if (airGalletCpuByteAddr != airGalletDebugLastAddr)
          airGalletDebugAddrChangeCount <= airGalletDebugAddrChangeCount + 8'd1;
        else
          airGalletDebugSameAddrCount <= airGalletDebugSameAddrCount + 8'd1;
        airGalletDebugPrevAddr <= airGalletDebugLastAddr;
        airGalletDebugLastAddr <= airGalletCpuByteAddr;
        airGalletDebugLastSelect <= airGalletDebugSelectNow;
        airGalletDebugLastSelectExt <= airGalletDebugSelectExtNow;
        airGalletDebugLastControl <= airGalletDebugControlNow;
        if (~airGalletDtack) begin
          airGalletDebugLastNoDtackAddr <= airGalletCpuByteAddr;
          airGalletDebugLastNoDtackSelect <= airGalletDebugSelectNow;
          airGalletDebugLastNoDtackSelectExt <= airGalletDebugSelectExtNow;
          airGalletDebugLastNoDtackControl <= airGalletDebugControlNow;
        end
      end

      if (readStrobe | writeStrobe)
        airGalletDebugLastDout <= _cpu_io_dout;
      if (readStrobe)
        airGalletDebugLastDin <= dinReg;

      if (io_progRom_rd & io_progRom_valid) begin
        airGalletDebugLastProgAddr <= {2'h0, io_progRom_addr};
        airGalletDebugMilestones[0] <= 1'b1;
      end
      if (airGalletSoundWrite)
        airGalletDebugMilestones[1] <= 1'b1;
      if (airGalletSoundRead | airGalletSoundFlagsRead)
        airGalletDebugMilestones[2] <= 1'b1;
      if (airGalletPaletteWrite)
        airGalletDebugMilestones[3] <= 1'b1;
      if (airGalletSpriteRamWrite)
        airGalletDebugMilestones[4] <= 1'b1;
      if (airGalletLayer0Vram8Write | airGalletLayer1Vram8Write | airGalletLayer2Vram8Write)
        airGalletDebugMilestones[5] <= 1'b1;
      if (airGalletSpriteSwapWrite)
        airGalletDebugMilestones[6] <= 1'b1;
      if (airGalletOpenBusSelect) begin
        airGalletDebugMilestones[7] <= 1'b1;
        if (~airGalletDebugFirstUnmappedValid) begin
          airGalletDebugFirstUnmappedValid <= 1'b1;
          airGalletDebugFirstUnmappedAddr <= airGalletCpuByteAddr;
        end
      end
    end
  end
  always @(posedge clock) begin
    if (reset | ~gameIsHotdogStorm) begin
      hotdogDebugSeen <= 64'd0;
      hotdogDebugLastAddr <= 24'd0;
      hotdogDebugPrevAddr <= 24'd0;
      hotdogDebugLastProgAddr <= 24'd0;
      hotdogDebugLastDout <= 16'd0;
      hotdogDebugLastDin <= 16'd0;
      hotdogDebugVector0 <= 16'hffff;
      hotdogDebugVector1 <= 16'hffff;
      hotdogDebugVector2 <= 16'hffff;
      hotdogDebugVector3 <= 16'hffff;
      hotdogDebugLastSelect <= 8'd0;
      hotdogDebugLastSelectExt <= 8'd0;
      hotdogDebugReadSeen <= 8'd0;
      hotdogDebugWriteSeen <= 8'd0;
      hotdogDebugIrqSeen <= 8'd0;
      hotdogDebugMilestones <= 8'd0;
      hotdogDebugLastControl <= 8'd0;
      hotdogDebugControlSeen <= 8'd0;
      hotdogDebugAddrChangeCount <= 8'd0;
      hotdogDebugSameAddrCount <= 8'd0;
    end
    else begin
      hotdogDebugSeen <= hotdogDebugSeen | hotdogDebugEventBits;
      hotdogDebugReadSeen <= hotdogDebugReadSeen | hotdogDebugReadNow;
      hotdogDebugWriteSeen <= hotdogDebugWriteSeen | hotdogDebugWriteNow;
      hotdogDebugIrqSeen <= hotdogDebugIrqSeen | hotdogDebugIrqNow;
      hotdogDebugControlSeen <= hotdogDebugControlSeen | hotdogDebugControlNow;

      if (_cpu_io_as & (_cpu_io_uds | _cpu_io_lds)) begin
        if (hotdogCpuByteAddr != hotdogDebugLastAddr)
          hotdogDebugAddrChangeCount <= hotdogDebugAddrChangeCount + 8'd1;
        else
          hotdogDebugSameAddrCount <= hotdogDebugSameAddrCount + 8'd1;
        hotdogDebugPrevAddr <= hotdogDebugLastAddr;
        hotdogDebugLastAddr <= hotdogCpuByteAddr;
        hotdogDebugLastSelect <= hotdogDebugSelectNow;
        hotdogDebugLastSelectExt <= hotdogDebugSelectExtNow;
        hotdogDebugLastControl <= hotdogDebugControlNow;
      end

      if (readStrobe | writeStrobe)
        hotdogDebugLastDout <= _cpu_io_dout;
      if (readStrobe)
        hotdogDebugLastDin <= dinReg;

      if (io_progRom_rd & io_progRom_valid) begin
        hotdogDebugLastProgAddr <= {2'h0, io_progRom_addr};
        hotdogDebugMilestones[0] <= 1'b1;
        case (io_progRom_addr)
          22'h000000: begin
            hotdogDebugVector0 <= io_progRom_dout;
            hotdogDebugMilestones[1] <= 1'b1;
          end
          22'h000002: begin
            hotdogDebugVector1 <= io_progRom_dout;
            hotdogDebugMilestones[1] <= 1'b1;
          end
          22'h000004: begin
            hotdogDebugVector2 <= io_progRom_dout;
            hotdogDebugMilestones[1] <= 1'b1;
          end
          22'h000006: begin
            hotdogDebugVector3 <= io_progRom_dout;
            hotdogDebugMilestones[1] <= 1'b1;
          end
          default: begin
          end
        endcase
      end

      if (hotdogMainRamWrite)
        hotdogDebugMilestones[2] <= 1'b1;
      if (hotdogPaletteWrite)
        hotdogDebugMilestones[3] <= 1'b1;
      if (hotdogLayerWrite | hotdogLayerRegsWrite)
        hotdogDebugMilestones[4] <= 1'b1;
      if (hotdogSpriteRamWrite | hotdogSpriteRegsWrite)
        hotdogDebugMilestones[5] <= 1'b1;
      if (hotdogInput0Read | hotdogInput1Read | hotdogIrqRead)
        hotdogDebugMilestones[6] <= 1'b1;
      if (hotdogSoundWrite | hotdogEepromWrite | hotdogSpriteSwapWrite)
        hotdogDebugMilestones[7] <= 1'b1;
    end
  end
`endif
  always @(posedge io_videoClock) begin
    io_gpuMem_layer_0_regs_r_tileSize <= _layerRegs_0_io_regs_1[13];
    io_gpuMem_layer_0_regs_r_enable <= ~(_layerRegs_0_io_regs_2[4]);
    io_gpuMem_layer_0_regs_r_flipX <= ~(_layerRegs_0_io_regs_0[15]);
    io_gpuMem_layer_0_regs_r_flipY <= ~(_layerRegs_0_io_regs_1[15]);
    io_gpuMem_layer_0_regs_r_rowScrollEnable <= _layerRegs_0_io_regs_0[14];
    io_gpuMem_layer_0_regs_r_rowSelectEnable <= _layerRegs_0_io_regs_1[14];
    io_gpuMem_layer_0_regs_r_priority <= _layerRegs_0_io_regs_2[1:0];
    io_gpuMem_layer_0_regs_r_scroll_x <= _layerRegs_0_io_regs_0[8:0];
    io_gpuMem_layer_0_regs_r_scroll_y <= _layerRegs_0_io_regs_1[8:0];
    io_gpuMem_layer_0_regs_r_1_tileSize <= io_gpuMem_layer_0_regs_r_tileSize;
    io_gpuMem_layer_0_regs_r_1_enable <= io_gpuMem_layer_0_regs_r_enable;
    io_gpuMem_layer_0_regs_r_1_flipX <= io_gpuMem_layer_0_regs_r_flipX;
    io_gpuMem_layer_0_regs_r_1_flipY <= io_gpuMem_layer_0_regs_r_flipY;
    io_gpuMem_layer_0_regs_r_1_rowScrollEnable <=
      io_gpuMem_layer_0_regs_r_rowScrollEnable;
    io_gpuMem_layer_0_regs_r_1_rowSelectEnable <=
      io_gpuMem_layer_0_regs_r_rowSelectEnable;
    io_gpuMem_layer_0_regs_r_1_priority <= io_gpuMem_layer_0_regs_r_priority;
    io_gpuMem_layer_0_regs_r_1_scroll_x <= io_gpuMem_layer_0_regs_r_scroll_x;
    io_gpuMem_layer_0_regs_r_1_scroll_y <= io_gpuMem_layer_0_regs_r_scroll_y;
    io_gpuMem_layer_1_regs_r_tileSize <= _layerRegs_1_io_regs_1[13];
    io_gpuMem_layer_1_regs_r_enable <= ~(_layerRegs_1_io_regs_2[4]);
    io_gpuMem_layer_1_regs_r_flipX <= ~(_layerRegs_1_io_regs_0[15]);
    io_gpuMem_layer_1_regs_r_flipY <= ~(_layerRegs_1_io_regs_1[15]);
    io_gpuMem_layer_1_regs_r_rowScrollEnable <= _layerRegs_1_io_regs_0[14];
    io_gpuMem_layer_1_regs_r_rowSelectEnable <= _layerRegs_1_io_regs_1[14];
    io_gpuMem_layer_1_regs_r_priority <= _layerRegs_1_io_regs_2[1:0];
    io_gpuMem_layer_1_regs_r_scroll_x <= _layerRegs_1_io_regs_0[8:0];
    io_gpuMem_layer_1_regs_r_scroll_y <= _layerRegs_1_io_regs_1[8:0];
    io_gpuMem_layer_1_regs_r_1_tileSize <= io_gpuMem_layer_1_regs_r_tileSize;
    io_gpuMem_layer_1_regs_r_1_enable <= io_gpuMem_layer_1_regs_r_enable;
    io_gpuMem_layer_1_regs_r_1_flipX <= io_gpuMem_layer_1_regs_r_flipX;
    io_gpuMem_layer_1_regs_r_1_flipY <= io_gpuMem_layer_1_regs_r_flipY;
    io_gpuMem_layer_1_regs_r_1_rowScrollEnable <=
      io_gpuMem_layer_1_regs_r_rowScrollEnable;
    io_gpuMem_layer_1_regs_r_1_rowSelectEnable <=
      io_gpuMem_layer_1_regs_r_rowSelectEnable;
    io_gpuMem_layer_1_regs_r_1_priority <= io_gpuMem_layer_1_regs_r_priority;
    io_gpuMem_layer_1_regs_r_1_scroll_x <= io_gpuMem_layer_1_regs_r_scroll_x;
    io_gpuMem_layer_1_regs_r_1_scroll_y <= io_gpuMem_layer_1_regs_r_scroll_y;
    io_gpuMem_layer_2_regs_r_tileSize <= _layerRegs_2_io_regs_1[13];
    io_gpuMem_layer_2_regs_r_enable <= ~(_layerRegs_2_io_regs_2[4]);
    io_gpuMem_layer_2_regs_r_flipX <= ~(_layerRegs_2_io_regs_0[15]);
    io_gpuMem_layer_2_regs_r_flipY <= ~(_layerRegs_2_io_regs_1[15]);
    io_gpuMem_layer_2_regs_r_rowScrollEnable <= _layerRegs_2_io_regs_0[14];
    io_gpuMem_layer_2_regs_r_rowSelectEnable <= _layerRegs_2_io_regs_1[14];
    io_gpuMem_layer_2_regs_r_priority <= _layerRegs_2_io_regs_2[1:0];
    io_gpuMem_layer_2_regs_r_scroll_x <= _layerRegs_2_io_regs_0[8:0];
    io_gpuMem_layer_2_regs_r_scroll_y <= _layerRegs_2_io_regs_1[8:0];
    io_gpuMem_layer_2_regs_r_1_tileSize <= io_gpuMem_layer_2_regs_r_tileSize;
    io_gpuMem_layer_2_regs_r_1_enable <= io_gpuMem_layer_2_regs_r_enable;
    io_gpuMem_layer_2_regs_r_1_flipX <= io_gpuMem_layer_2_regs_r_flipX;
    io_gpuMem_layer_2_regs_r_1_flipY <= io_gpuMem_layer_2_regs_r_flipY;
    io_gpuMem_layer_2_regs_r_1_rowScrollEnable <=
      io_gpuMem_layer_2_regs_r_rowScrollEnable;
    io_gpuMem_layer_2_regs_r_1_rowSelectEnable <=
      io_gpuMem_layer_2_regs_r_rowSelectEnable;
    io_gpuMem_layer_2_regs_r_1_priority <= io_gpuMem_layer_2_regs_r_priority;
    io_gpuMem_layer_2_regs_r_1_scroll_x <= io_gpuMem_layer_2_regs_r_scroll_x;
    io_gpuMem_layer_2_regs_r_1_scroll_y <= io_gpuMem_layer_2_regs_r_scroll_y;
  end // always @(posedge)
  assign _cpu_io_vpa = _cpu_io_as & (&_cpu_io_fc);
  assign _cpu_io_ipl = {2'h0, videoIrq | io_soundCtrl_irq | unknownIrq};
  CaveBanprestoCaptureBoundaryGate
  captureBoundaryGate (
    .request_i           (mainCpuCaptureRequest),
    .level1_iack_i       (
      _cpu_io_as && (&_cpu_io_fc) && (_cpu_io_ipl == 3'b001)
    ),
    .paused_i            (pauseActive),
    .request_o           (mainCpuCaptureRequestToCpu)
  );

`ifdef CAVEBANPRESTO_SS_RELEASE_SLIM_HW_DIAGNOSTIC
  // A one-cycle admitted request is too short for slow JTAG sampling.  Keep a
  // diagnostic-only sticky witness in the same clock domain as the gate; the
  // top level synchronizes this level before placing it in the compact probe.
  always @(posedge clock) begin
    if (reset)
      io_ss_capture_admitted_seen <= 1'b0;
    else if (mainCpuCaptureRequestToCpu)
      io_ss_capture_admitted_seen <= 1'b1;
  end
`endif
  CaveMain68kCpu cpu (
    .clock                  (clock),
    .reset                  (mainCpuReset),
    .io_halt                (pauseActive),
    .io_external_hold       (highScoreCpuHold),
    .io_external_hold_ack   (highScoreCpuHoldAck),
    .io_ss_state_enable     (mainStateHold),
    .io_ss_capture_request  (mainCpuCaptureRequestToCpu),
    .io_ss_restore_load     (mainCpuRestoreLoad),
    .io_ss_restore_ssp      (mainCpuRestoreSsp),
    .io_ss_restore_context  (mainCpuRestoreContext),
    .io_ss_abort            (mainCpuAbort),
    .io_ss_owner_abort_safe (mainCpuOwnerAbortSafe),
    .io_ss_capture_done     (io_ss_cpu_captured),
    .io_ss_saved_ssp        (mainCpuSavedSsp),
    .io_ss_saved_context    (mainCpuSavedContext),
    .io_ss_restore_done     (mainCpuRestoreDone),
    .io_ss_abort_ack        (io_ss_cpu_abort_ack),
    .io_ss_terminal_fault   (mainCpuWrapperTerminalFault),
    .io_as                  (_cpu_io_as),
    .io_rw                  (_cpu_io_rw),
    .io_uds                 (_cpu_io_uds),
    .io_lds                 (_cpu_io_lds),
    .io_dtack               (dtackReg),
    .io_vpa                 (_cpu_io_vpa),
    .io_ipl                 (_cpu_io_ipl),
    .io_fc                  (_cpu_io_fc),
    .io_addr                (_cpu_io_addr),
    .io_din                 (dinReg),
    .io_dout                (_cpu_io_dout)
  );

  // High-score ownership is independent of save-state serialization. It may
  // begin only while Main's save-state hold is absent. The CPU wrapper freezes
  // fx68k's phase enables on an idle external-bus boundary and acknowledges
  // that frozen state before either RAM port is selected below.
  wire highScoreNormalRamWr =
    gameIsMetmqstr ? spriteRam_io_portA_wr : mainRam_io_wr;
  wire [15:0] highScoreRamDout =
    highScoreRamTargetSprite ?
      _spriteRam_io_portA_dout : _mainRam_io_dout;

  CaveBanprestoHighScoreManager highScoreManager (
    .sys_clock         (io_systemClock),
    .sys_reset         (io_systemReset),
    .cpu_clock         (clock),
    .cpu_reset         (mainCpuReset),
    .game_index_sys    (io_hs_game_index_sys),
    .game_index_cpu    (io_gameIndex),
    .config_download   (io_hs_config_download),
    .config_wr         (io_hs_config_wr),
    .config_addr       (io_hs_config_addr),
    .config_dout       (io_hs_config_dout),
    .nvram_download    (io_hs_nvram_download),
    .nvram_upload      (io_hs_nvram_upload),
    .nvram_rd          (io_hs_nvram_rd),
    .nvram_wr          (io_hs_nvram_wr),
    .nvram_addr        (io_hs_nvram_addr),
    .nvram_dout        (io_hs_nvram_dout),
    .nvram_din         (io_hs_nvram_din),
    .nvram_wait_n      (io_hs_nvram_wait_n),
    .ss_hold_cpu       (mainStateHold),
    .cpu_idle          (highScoreCpuHoldAck),
    .normal_ram_wr     (highScoreNormalRamWr),
    .normal_byte_addr  (cpuByteAddr),
    .normal_ram_mask   (mainRam_io_mask),
    .normal_ram_din    (_cpu_io_dout),
    .cpu_hold          (highScoreCpuHold),
    .ram_owned         (highScoreRamOwned),
    .ram_rd            (highScoreRamRd),
    .ram_wr            (highScoreRamWr),
    .ram_addr          (highScoreRamAddr),
    .ram_mask          (highScoreRamMask),
    .ram_din           (highScoreRamDin),
    .ram_target_sprite (highScoreRamTargetSprite),
    .ram_dout          (highScoreRamDout),
    .dirty_sys         (io_hs_dirty),
    .active_sys        (io_hs_active)
  );

  EEPROM #(
    .SAVE_STATE_ENABLE(1'b1)
  ) eeprom (
    .clock           (clock),
    .reset           (reset),
    .io_ss_hold      (mainStateHold),
    .io_ss_load      (eepromRestoreLoad),
    .io_ss_state_in  (eepromRestoreState),
    .io_ss_state_out (eepromLiveState),
    .io_ss_idle      (eepromDeviceIdle),
    .io_mem_rd       (io_eeprom_rd),
    .io_mem_wr       (io_eeprom_wr),
    .io_mem_addr     (io_eeprom_addr),
    .io_mem_din      (io_eeprom_din),
    .io_mem_dout     (io_eeprom_dout),
    .io_mem_wait_n   (io_eeprom_wait_n),
    .io_mem_valid    (io_eeprom_valid),
    .io_serial_cs    (eepromSerialCs),
    .io_serial_sck   (eepromSerialSck),
    .io_serial_sdi   (eepromSerialSdi),
    .io_serial_sdo   (_eeprom_io_serial_sdo)
  );
  MetmqstrBootWatchdog metmqstrBootWatchdog (
    .clock                  (clock),
    .reset                  (reset),
    .game_active            (gameIsMetmqstr),
    .sprite_ram_write       (metmqstrSpriteRamWrite),
    .sprite_ram_addr        (_cpu_io_addr[14:0]),
    .sprite_ram_mask        (mainRam_io_mask),
    .sprite_ram_din         (_cpu_io_dout),
    .ss_hold                (mainControlStateHold),
    .ss_load                (mainControlRestoreLoad),
    .ss_state_in            (mainControlRestoreState[167:154]),
    .ss_state_out           (metmqstrWatchdogState),
    .cpu_reset              (metmqstrCpuReset),
    .marker_seen            (metmqstrBootMarkerSeen),
    .watchdog_delay_active  (metmqstrBootWatchdogDelayActive),
    .watchdog_reset_active  (metmqstrBootWatchdogResetActive),
    .watchdog_trip          (metmqstrBootWatchdogTrip)
  );

  // Owner 3 contains only Main-local CPU-clocked control state. The ordering
  // here is the serialized ABI documented by
  // CaveBanprestoMainControlSaveStateOwner; per-profile inactive fields are
  // canonicalized by that owner rather than allowed to leak stale gap/watchdog
  // registers into a save image.
  assign mainControlLiveState = {
    metmqstrGapState,
    hotdogGapState,
    metmqstrWatchdogState,
    mazingerControlState,
    servicePulseState,
    coin2PulseState,
    coin1PulseState,
    vblankTrackerState,
    cpuBusStrobeState,
    eepromSerialPinState,
    pauseState,
    sailorMoonTilebankReg,
    dtackReg,
    dinReg,
    unknownIrq,
    agalletIrq,
    videoIrq
  };

  CaveBanprestoFx68kSaveStateOwner #(
    .OWNER_INDEX(8'd2),
    .FORMAT_TAG(32'h3638_4b32)
  ) mainCpuSaveStateOwner (
    .clk_i                   (clock),
    .reset_i                 (reset),
    .state_enable_i          (mainStateHold),
    .restore_enable_i        (mainRestoreEnable),
    .restore_begin_i         (mainRestoreBegin),
    .cpu_restore_commit_i    (mainCpuFinalRestoreCommit),
    .abort_i                 (mainCpuAbort),
    .state_held_i            (io_ss_cpu_captured),
    .profile_i               (io_gameIndex),
    .live_ssp_i              (mainCpuSavedSsp),
    .live_context_i          (mainCpuSavedContext),
    .cpu_restore_done_i      (mainCpuRestoreDone),
    .cpu_terminal_fault_i    (mainCpuWrapperTerminalFault),
    .restore_ssp_o           (mainCpuRestoreSsp),
    .restore_context_o       (mainCpuRestoreContext),
    .restore_load_o          (mainCpuRestoreLoad),
    .abort_safe_o            (mainCpuOwnerAbortSafe),
    .validation_complete_o   (mainCpuValidationComplete),
    .validation_valid_o      (mainCpuValidationValid),
    .write_complete_o        (mainCpuWriteComplete),
    .write_valid_o           (mainCpuWriteValid),
    .restore_committed_o     (io_ss_cpu_restore_committed),
    .terminal_fault_o        (io_ss_cpu_terminal_fault),
    .owner_idle_o            (mainCpuOwnerIdle),
    .ssbus                   (io_ss_cpu_bus)
  );

  CaveBanprestoMainControlSaveStateOwner #(
    .OWNER_INDEX(8'd3),
    .FORMAT_TAG(16'h4d33)
  ) mainControlSaveStateOwner (
    .clk_i                 (clock),
    .reset_i               (mainNoncpuOwnerResetWire),
    .state_enable_i        (mainStateHold),
    .restore_enable_i      (mainRestoreEnable),
    .restore_begin_i       (mainRestoreBegin),
    .restore_commit_i      (mainOwner3RestoreCommit),
    .state_held_i          (mainControlStateHold),
    .profile_i             (io_gameIndex),
    .live_state_i          (mainControlLiveState),
    .restore_load_o        (mainControlRestoreLoad),
    .restore_state_o       (mainControlRestoreState),
    .validation_complete_o (mainControlValidationComplete),
    .validation_valid_o    (mainControlValidationValid),
    .write_complete_o      (mainControlWriteComplete),
    .write_valid_o         (mainControlWriteValid),
    .restore_committed_o   (io_ss_control_restore_committed),
    .terminal_fault_o      (io_ss_control_terminal_fault),
    .owner_idle_o          (mainControlOwnerIdle),
    .ssbus                 (io_ss_control_bus)
  );

  assign io_ss_control_idle =
    mainControlOwnerIdle &&
    ((mainStateHold !== 1'b1) || mainControlStateHold);

  // Owner 20 is deliberately disjoint from owner 3.  Main supplies only its
  // seventeen physical layer/sprite cells here; VideoSys contributes all eight
  // of its cells through the explicit external bundle, and the existing
  // io_dips_0 path is the live physical DIP cell.  Configuration inputs are
  // validation-only and have no restore output.
  assign mainRegisterLiveState = {
    mainSpriteRegisterState,
    mainLayer2RegisterState,
    mainLayer1RegisterState,
    mainLayer0RegisterState
  };

  CaveBanprestoMainRegisterSaveStateOwner #(
    .OWNER_INDEX(8'd20),
    .FORMAT_TAG(16'h5232)
  ) mainRegisterSaveStateOwner (
    .clk_i                       (clock),
    .reset_i                     (mainNoncpuOwnerResetWire),
    .state_enable_i              (mainStateHold),
    .restore_enable_i            (mainRestoreEnable),
    .restore_begin_i             (mainRestoreBegin),
    .restore_commit_i            (mainOwner20RestoreCommit),
    .state_held_i                (mainRegisterStateHold),
    .blocked_normal_write_i      (|mainRegisterBlockedWrite),
    .main_state_i                (mainRegisterLiveState),
    .video_state_i               (io_ss_video_register_state),
    .dip_state_i                 (io_dips_0),
    .config_offset_x_i           (io_ss_config_offset_x),
    .config_offset_y_i           (io_ss_config_offset_y),
    .config_rotate_i             (io_ss_config_rotate),
    .config_compatibility_i      (io_ss_config_compatibility),
    .config_layer0_enable_i      (io_ss_config_layer0_enable),
    .config_layer1_enable_i      (io_ss_config_layer1_enable),
    .config_layer2_enable_i      (io_ss_config_layer2_enable),
    .config_sprite_enable_i      (io_ss_config_sprite_enable),
    .config_flip_video_i         (io_ss_config_flip_video),
    .config_psg_boost_i          (io_ss_config_psg_boost),
    .config_fm_boost_i           (io_ss_config_fm_boost),
    .config_oki0_boost_i         (io_ss_config_oki0_boost),
    .config_oki1_boost_i         (io_ss_config_oki1_boost),
    .restore_load_o              (mainRegisterRestoreLoad),
    .restore_main_state_o        (mainRegisterRestoreState),
    .restore_video_state_o       (
      io_ss_video_register_restore_state
    ),
    .restore_dip_state_o         (io_ss_dip_register_restore_state),
    .validation_complete_o       (mainRegisterValidationComplete),
    .validation_valid_o          (mainRegisterValidationValid),
    .write_complete_o            (mainRegisterWriteComplete),
    .write_valid_o               (mainRegisterWriteValid),
    .restore_committed_o         (
      io_ss_register_restore_committed
    ),
    .terminal_fault_o            (io_ss_register_terminal_fault),
    .owner_idle_o                (mainRegisterOwnerIdle),
    .ssbus                       (io_ss_register_bus)
  );

  assign io_ss_register_restore_load = mainRegisterRestoreLoad;
  assign io_ss_register_idle =
    mainRegisterOwnerIdle &&
    ((mainStateHold !== 1'b1) || mainRegisterStateHold);

  // Owner 22 serializes the EEPROM controller's exact 48-bit live state.  Its
  // dedicated bus remains disjoint from the mutable-RAM owner mux below.
  CaveBanprestoEEPROMStatePort #(
    .OWNER_INDEX(8'd22),
    .FORMAT_TAG(16'h4545)
  ) eepromSaveStateOwner (
    .clk_i                 (clock),
    .reset_i               (mainNoncpuOwnerResetWire),
    .state_enable_i        (mainStateHold),
    .restore_enable_i      (mainRestoreEnable),
    .restore_begin_i       (mainRestoreBegin),
    .restore_commit_i      (mainOwner22RestoreCommit),
    .device_idle_i         (eepromDeviceIdle),
    .live_state_i          (eepromLiveState),
    .restore_load_o        (eepromRestoreLoad),
    .restore_state_o       (eepromRestoreState),
    .validation_complete_o (eepromValidationComplete),
    .validation_valid_o    (eepromValidationValid),
    .write_complete_o      (eepromWriteComplete),
    .write_valid_o         (eepromWriteValid),
    .restore_committed_o   (io_ss_eeprom_restore_committed),
    .terminal_fault_o      (io_ss_eeprom_terminal_fault),
    .owner_idle_o          (eepromOwnerIdle),
    .ssbus                 (io_ss_eeprom_bus)
  );

  assign io_ss_eeprom_idle = eepromOwnerIdle;

`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
  // Development-only visibility of the exact StReleaseWait hold-withdrawal
  // predicate.  Bits [3:0] are owner 22, owner 20, owner 3, and CPU.
  assign io_ss_release_owner_idle = {
    (eepromOwnerIdle === 1'b1),
    (mainRegisterOwnerIdle === 1'b1),
    (io_ss_control_idle === 1'b1),
    (mainCpuOwnerIdle === 1'b1)
  };
  // Detail bits are render-idle and CPU-owner-bus-quiet respectively.
  assign io_ss_release_detail = {
    (io_ss_render_idle === 1'b1),
    ({
      io_ss_cpu_bus.req_query,
      io_ss_cpu_bus.req_validate,
      io_ss_cpu_bus.req_write,
      io_ss_cpu_bus.req_read
    } === 4'b0000)
  };
  assign io_ss_release_eligible =
    (mainCommandStateDebug === SS_MAIN_COMMAND_RELEASE_WAIT) &&
    (mainStateHold === 1'b1) &&
    (io_ss_cpu_captured === 1'b1) &&
    (&io_ss_release_owner_idle);
  assign io_ss_release_state = mainCommandStateDebug;
  assign io_ss_release_fault_debug = mainCommandFaultDebug;
`endif

  // Commands cross into Main as one held packet.  This endpoint captures the
  // STOP epoch, owns the persistent hold, and admits restore mutation only in
  // the fixed owner order 3 -> 20 -> 22 -> CPU-final.
  CaveBanprestoMainCommandEndpoint mainCommandEndpoint (
    .clk_i                            (clock),
    .reset_i                          (reset),
    .command_valid_i                  (io_ss_command_valid),
    .command_i                        (io_ss_command),
    .command_complete_o               (io_ss_command_complete),
    .command_response_o               (io_ss_command_response),
    .terminal_fault_o                 (
      io_ss_command_terminal_fault
    ),
    .game_index_i                     (io_gameIndex),
    .release_request_i                (io_ss_release_request),
    .release_restore_i                (io_ss_release_restore),
    .release_complete_o               (io_ss_release_complete),
    .state_hold_o                     (mainStateHold),
    .restore_enable_o                 (mainRestoreEnable),
    .cpu_capture_request_o            (mainCpuCaptureRequest),
    .restore_begin_o                  (mainRestoreBegin),
    .owner3_restore_commit_o          (mainOwner3RestoreCommit),
    .owner20_restore_commit_o         (mainOwner20RestoreCommit),
    .owner22_restore_commit_o         (mainOwner22RestoreCommit),
    .cpu_final_restore_commit_o       (
      mainCpuFinalRestoreCommit
    ),
    .cpu_abort_o                      (mainCpuAbort),
    .noncpu_owner_reset_o             (mainNoncpuOwnerReset),
    .cpu_captured_i                   (io_ss_cpu_captured),
    .cpu_restore_done_i               (mainCpuRestoreDone),
    .cpu_abort_ack_i                  (io_ss_cpu_abort_ack),
    .cpu_validation_complete_i        (
      mainCpuValidationComplete
    ),
    .cpu_validation_valid_i           (mainCpuValidationValid),
    .cpu_write_complete_i             (mainCpuWriteComplete),
    .cpu_write_valid_i                (mainCpuWriteValid),
    .cpu_restore_committed_i          (
      io_ss_cpu_restore_committed
    ),
    .cpu_owner_idle_i                 (mainCpuOwnerIdle),
    .cpu_terminal_fault_i             (io_ss_cpu_terminal_fault),
    .owner3_validation_complete_i     (
      mainControlValidationComplete
    ),
    .owner3_validation_valid_i        (
      mainControlValidationValid
    ),
    .owner3_write_complete_i          (mainControlWriteComplete),
    .owner3_write_valid_i             (mainControlWriteValid),
    .owner3_restore_load_i            (mainControlRestoreLoad),
    .owner3_restore_committed_i       (
      io_ss_control_restore_committed
    ),
    // The endpoint separately proves CPU capture in every normal held phase.
    // Abort recovery deliberately releases the CPU before it drains owner 3,
    // so this lane must use the owner's raw idle rather than the aggregate
    // idle that is gated by mainControlStateHold.
    .owner3_idle_i                    (mainControlOwnerIdle),
    .owner3_terminal_fault_i          (
      io_ss_control_terminal_fault
    ),
    .owner20_validation_complete_i    (
      mainRegisterValidationComplete
    ),
    .owner20_validation_valid_i       (
      mainRegisterValidationValid
    ),
    .owner20_write_complete_i         (mainRegisterWriteComplete),
    .owner20_write_valid_i            (mainRegisterWriteValid),
    .owner20_restore_load_i           (mainRegisterRestoreLoad),
    .owner20_restore_committed_i      (
      io_ss_register_restore_committed
    ),
    .owner20_external_applied_i       (
      io_ss_register_restore_applied
    ),
    // Release must observe the owner's transaction state directly.  The
    // render-gated aggregate remains the quiesce/admission signal, but can
    // fall after new video work is unblocked and must not recapture release.
    .owner20_idle_i                   (mainRegisterOwnerIdle),
    .owner20_terminal_fault_i         (
      io_ss_register_terminal_fault
    ),
    .owner20_bridge_terminal_fault_i  (
      io_ss_register_restore_bridge_fault
    ),
    .owner22_validation_complete_i    (
      eepromValidationComplete
    ),
    .owner22_validation_valid_i       (eepromValidationValid),
    .owner22_write_complete_i         (eepromWriteComplete),
    .owner22_write_valid_i            (eepromWriteValid),
    .owner22_restore_load_i           (eepromRestoreLoad),
    .owner22_restore_committed_i      (
      io_ss_eeprom_restore_committed
    ),
    .owner22_idle_i                   (eepromOwnerIdle),
    .owner22_terminal_fault_i         (
      io_ss_eeprom_terminal_fault
    ),
    .main_stopped_o                   (io_ss_stopped),
    .main_abort_ack_o                 (io_ss_abort_ack),
    .state_debug_o                    (
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
      mainCommandStateDebug
`endif
    ),
    .fault_debug_o                    (
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
      mainCommandFaultDebug
`endif
    )
  );

  CaveBanprestoSaveStateBusMux #(
    .OWNER_COUNT(16),
    .OWNER_BASE(4),
    .SUPPORT_WIDTH(48),
    .COMPILED_SUPPORT_BITMAP(SS_RAM_COMPILED_SUPPORT),
    .RESPONSE_TIMEOUT_CYCLES(4096)
  ) mainRamOwnerMux (
    .clk_i             (clock),
    .reset_i           (reset),
    .runtime_support_i (ssRamRuntimeSupport),
    .owners            (mainRamOwnerBus),
    .upstream          (io_ss_ram_bus),
    .multiple_ack_o    (ssRamBusMultipleAck),
    .timeout_o         (ssRamBusTimeout),
    .faulted_o         (ssRamBusFault),
    .idle_o            (ssRamBusIdle)
  );

  // A claimed-idle client issuing a RAM cycle is a quiesce-contract failure.
  // Every port wrapper blocks that cycle, while this reset-only fence prevents
  // a partially captured/restored machine from being released as valid.
  always @(posedge clock) begin
    if (reset) begin
      ssRamSafetyFault <= 1'b0;
    end
    else if ((|ssRamBlockedNormalAccess) ||
             ((|ssRamTakeover) && !ssRamTakeoverPermitted)) begin
      ssRamSafetyFault <= 1'b1;
    end
  end

  assign io_ss_ram_takeover_active = |ssRamTakeover;
  assign io_ss_ram_blocked_access = |ssRamBlockedNormalAccess;
  assign io_ss_ram_idle =
    ssRamBusIdle & !io_ss_ram_takeover_active;
  assign io_ss_ram_terminal_fault =
    ssRamBusFault |
    ssRamSafetyFault |
    ssRamBusMultipleAck |
    ssRamBusTimeout;

  assign _mainRam_io_addr = _cpu_io_addr[14:0];
  wire        mainRamSaveStateRd;
  wire        mainRamSaveStateWr;
  wire [1:0]  mainRamSaveStateMask;
  wire [14:0] mainRamSaveStateAddr;
  wire [15:0] mainRamSaveStateDin;
  wire        mainRamPhysicalRd;
  wire        mainRamPhysicalWr;
  wire [1:0]  mainRamPhysicalMask;
  wire [14:0] mainRamPhysicalAddr;
  wire [15:0] mainRamPhysicalDin;
  CaveBanprestoMainRamSaveStatePort #(
    .OWNER_INDEX(8'd4),
    .ADDR_WIDTH(15),
    .ELEMENT_COUNT(32768)
  ) mainRamSaveStatePort (
    .clk_i(clock),
    .reset_i(reset),
    .takeover_permitted_i(ssRamTakeoverPermitted),
    .normal_rd_i(mainRam_io_rd),
    .normal_wr_i(mainRam_io_wr),
    .normal_mask_i(mainRam_io_mask),
    .normal_addr_i(_mainRam_io_addr),
    .normal_din_i(_cpu_io_dout),
    .ram_rd_o(mainRamSaveStateRd),
    .ram_wr_o(mainRamSaveStateWr),
    .ram_mask_o(mainRamSaveStateMask),
    .ram_addr_o(mainRamSaveStateAddr),
    .ram_din_o(mainRamSaveStateDin),
    .ram_dout_i(_mainRam_io_dout),
    .takeover_active_o(ssRamTakeover[0]),
    .blocked_normal_access_o(ssRamBlockedNormalAccess[0]),
    .ssbus(mainRamOwnerBus[0])
  );
  assign mainRamPhysicalRd =
    highScoreRamOwned && !highScoreRamTargetSprite ?
      highScoreRamRd : mainRamSaveStateRd;
  assign mainRamPhysicalWr =
    highScoreRamOwned && !highScoreRamTargetSprite ?
      highScoreRamWr : mainRamSaveStateWr;
  assign mainRamPhysicalMask =
    highScoreRamOwned && !highScoreRamTargetSprite ?
      highScoreRamMask : mainRamSaveStateMask;
  assign mainRamPhysicalAddr =
    highScoreRamOwned && !highScoreRamTargetSprite ?
      highScoreRamAddr : mainRamSaveStateAddr;
  assign mainRamPhysicalDin =
    highScoreRamOwned && !highScoreRamTargetSprite ?
      highScoreRamDin : mainRamSaveStateDin;
  CaveSinglePortRam #(
    .ADDR_WIDTH  (15),
    .DATA_WIDTH  (16),
    .DEPTH       (0),
    .MASK_ENABLE (1)
  ) mainRam (
    .clock (clock),
    .rd    (mainRamPhysicalRd),
    .wr    (mainRamPhysicalWr),
    .addr  (mainRamPhysicalAddr),
    .mask  (mainRamPhysicalMask),
    .din   (mainRamPhysicalDin),
    .dout  (_mainRam_io_dout)
  );
  wire        airGalletWorkRamPhysicalRd;
  wire        airGalletWorkRamPhysicalWr;
  wire [1:0]  airGalletWorkRamPhysicalMask;
  wire [14:0] airGalletWorkRamPhysicalAddr;
  wire [15:0] airGalletWorkRamPhysicalDin;
  CaveBanprestoMainRamSaveStatePort #(
    .OWNER_INDEX(8'd5),
    .ADDR_WIDTH(15),
    .ELEMENT_COUNT(32768)
  ) airGalletWorkRamSaveStatePort (
    .clk_i(clock),
    .reset_i(reset),
    .takeover_permitted_i(ssRamTakeoverPermitted),
    .normal_rd_i(airGalletWorkRamRead),
    .normal_wr_i(airGalletWorkRamWrite),
    .normal_mask_i(mainRam_io_mask),
    .normal_addr_i(airGalletWorkRamAddr),
    .normal_din_i(_cpu_io_dout),
    .ram_rd_o(airGalletWorkRamPhysicalRd),
    .ram_wr_o(airGalletWorkRamPhysicalWr),
    .ram_mask_o(airGalletWorkRamPhysicalMask),
    .ram_addr_o(airGalletWorkRamPhysicalAddr),
    .ram_din_o(airGalletWorkRamPhysicalDin),
    .ram_dout_i(airGalletWorkRamData),
    .takeover_active_o(ssRamTakeover[1]),
    .blocked_normal_access_o(ssRamBlockedNormalAccess[1]),
    .ssbus(mainRamOwnerBus[1])
  );
  CaveSinglePortRam #(
    .ADDR_WIDTH  (15),
    .DATA_WIDTH  (16),
    .DEPTH       (0),
    .MASK_ENABLE (1)
  ) airGalletWorkRam (
    .clock (clock),
    .rd    (airGalletWorkRamPhysicalRd),
    .wr    (airGalletWorkRamPhysicalWr),
    .addr  (airGalletWorkRamPhysicalAddr),
    .mask  (airGalletWorkRamPhysicalMask),
    .din   (airGalletWorkRamPhysicalDin),
    .dout  (airGalletWorkRamData)
  );
  wire        airGalletLayer0ScratchRamPhysicalRd;
  wire        airGalletLayer0ScratchRamPhysicalWr;
  wire [1:0]  airGalletLayer0ScratchRamPhysicalMask;
  wire [12:0] airGalletLayer0ScratchRamPhysicalAddr;
  wire [15:0] airGalletLayer0ScratchRamPhysicalDin;
  CaveBanprestoMainRamSaveStatePort #(
    .OWNER_INDEX(8'd6),
    .ADDR_WIDTH(13),
    .ELEMENT_COUNT(5120)
  ) airGalletLayer0ScratchRamSaveStatePort (
    .clk_i(clock),
    .reset_i(reset),
    .takeover_permitted_i(ssRamTakeoverPermitted),
    .normal_rd_i(airGalletLayer0ScratchRead),
    .normal_wr_i(airGalletLayer0ScratchWrite),
    .normal_mask_i(mainRam_io_mask),
    .normal_addr_i(airGalletTilemapScratchAddr),
    .normal_din_i(_cpu_io_dout),
    .ram_rd_o(airGalletLayer0ScratchRamPhysicalRd),
    .ram_wr_o(airGalletLayer0ScratchRamPhysicalWr),
    .ram_mask_o(airGalletLayer0ScratchRamPhysicalMask),
    .ram_addr_o(airGalletLayer0ScratchRamPhysicalAddr),
    .ram_din_o(airGalletLayer0ScratchRamPhysicalDin),
    .ram_dout_i(airGalletLayer0ScratchData),
    .takeover_active_o(ssRamTakeover[2]),
    .blocked_normal_access_o(ssRamBlockedNormalAccess[2]),
    .ssbus(mainRamOwnerBus[2])
  );
  CaveSinglePortRam #(
    .ADDR_WIDTH  (13),
    .DATA_WIDTH  (16),
    .DEPTH       (5120),
    .MASK_ENABLE (1)
  ) airGalletLayer0ScratchRam (
    .clock (clock),
    .rd    (airGalletLayer0ScratchRamPhysicalRd),
    .wr    (airGalletLayer0ScratchRamPhysicalWr),
    .addr  (airGalletLayer0ScratchRamPhysicalAddr),
    .mask  (airGalletLayer0ScratchRamPhysicalMask),
    .din   (airGalletLayer0ScratchRamPhysicalDin),
    .dout  (airGalletLayer0ScratchData)
  );
  wire        airGalletLayer1ScratchRamPhysicalRd;
  wire        airGalletLayer1ScratchRamPhysicalWr;
  wire [1:0]  airGalletLayer1ScratchRamPhysicalMask;
  wire [12:0] airGalletLayer1ScratchRamPhysicalAddr;
  wire [15:0] airGalletLayer1ScratchRamPhysicalDin;
  CaveBanprestoMainRamSaveStatePort #(
    .OWNER_INDEX(8'd7),
    .ADDR_WIDTH(13),
    .ELEMENT_COUNT(5120)
  ) airGalletLayer1ScratchRamSaveStatePort (
    .clk_i(clock),
    .reset_i(reset),
    .takeover_permitted_i(ssRamTakeoverPermitted),
    .normal_rd_i(airGalletLayer1ScratchRead),
    .normal_wr_i(airGalletLayer1ScratchWrite),
    .normal_mask_i(mainRam_io_mask),
    .normal_addr_i(airGalletTilemapScratchAddr),
    .normal_din_i(_cpu_io_dout),
    .ram_rd_o(airGalletLayer1ScratchRamPhysicalRd),
    .ram_wr_o(airGalletLayer1ScratchRamPhysicalWr),
    .ram_mask_o(airGalletLayer1ScratchRamPhysicalMask),
    .ram_addr_o(airGalletLayer1ScratchRamPhysicalAddr),
    .ram_din_o(airGalletLayer1ScratchRamPhysicalDin),
    .ram_dout_i(airGalletLayer1ScratchData),
    .takeover_active_o(ssRamTakeover[3]),
    .blocked_normal_access_o(ssRamBlockedNormalAccess[3]),
    .ssbus(mainRamOwnerBus[3])
  );
  CaveSinglePortRam #(
    .ADDR_WIDTH  (13),
    .DATA_WIDTH  (16),
    .DEPTH       (5120),
    .MASK_ENABLE (1)
  ) airGalletLayer1ScratchRam (
    .clock (clock),
    .rd    (airGalletLayer1ScratchRamPhysicalRd),
    .wr    (airGalletLayer1ScratchRamPhysicalWr),
    .addr  (airGalletLayer1ScratchRamPhysicalAddr),
    .mask  (airGalletLayer1ScratchRamPhysicalMask),
    .din   (airGalletLayer1ScratchRamPhysicalDin),
    .dout  (airGalletLayer1ScratchData)
  );
  wire        airGalletLayer2ScratchRamPhysicalRd;
  wire        airGalletLayer2ScratchRamPhysicalWr;
  wire [1:0]  airGalletLayer2ScratchRamPhysicalMask;
  wire [12:0] airGalletLayer2ScratchRamPhysicalAddr;
  wire [15:0] airGalletLayer2ScratchRamPhysicalDin;
  CaveBanprestoMainRamSaveStatePort #(
    .OWNER_INDEX(8'd8),
    .ADDR_WIDTH(13),
    .ELEMENT_COUNT(5120)
  ) airGalletLayer2ScratchRamSaveStatePort (
    .clk_i(clock),
    .reset_i(reset),
    .takeover_permitted_i(ssRamTakeoverPermitted),
    .normal_rd_i(airGalletLayer2ScratchRead),
    .normal_wr_i(airGalletLayer2ScratchWrite),
    .normal_mask_i(mainRam_io_mask),
    .normal_addr_i(airGalletTilemapScratchAddr),
    .normal_din_i(_cpu_io_dout),
    .ram_rd_o(airGalletLayer2ScratchRamPhysicalRd),
    .ram_wr_o(airGalletLayer2ScratchRamPhysicalWr),
    .ram_mask_o(airGalletLayer2ScratchRamPhysicalMask),
    .ram_addr_o(airGalletLayer2ScratchRamPhysicalAddr),
    .ram_din_o(airGalletLayer2ScratchRamPhysicalDin),
    .ram_dout_i(airGalletLayer2ScratchData),
    .takeover_active_o(ssRamTakeover[4]),
    .blocked_normal_access_o(ssRamBlockedNormalAccess[4]),
    .ssbus(mainRamOwnerBus[4])
  );
  CaveSinglePortRam #(
    .ADDR_WIDTH  (13),
    .DATA_WIDTH  (16),
    .DEPTH       (5120),
    .MASK_ENABLE (1)
  ) airGalletLayer2ScratchRam (
    .clock (clock),
    .rd    (airGalletLayer2ScratchRamPhysicalRd),
    .wr    (airGalletLayer2ScratchRamPhysicalWr),
    .addr  (airGalletLayer2ScratchRamPhysicalAddr),
    .mask  (airGalletLayer2ScratchRamPhysicalMask),
    .din   (airGalletLayer2ScratchRamPhysicalDin),
    .dout  (airGalletLayer2ScratchData)
  );
  assign _spriteRam_io_portA_addr = _cpu_io_addr[14:0];
  wire        spriteRamSaveStateRd;
  wire        spriteRamSaveStateWr;
  wire [1:0]  spriteRamSaveStateMask;
  wire [14:0] spriteRamSaveStateAddr;
  wire [15:0] spriteRamSaveStateDin;
  wire        spriteRamPhysicalRd;
  wire        spriteRamPhysicalWr;
  wire [1:0]  spriteRamPhysicalMask;
  wire [14:0] spriteRamPhysicalAddr;
  wire [15:0] spriteRamPhysicalDin;
  CaveBanprestoMainRamSaveStatePort #(
    .OWNER_INDEX(8'd9),
    .ADDR_WIDTH(15),
    .ELEMENT_COUNT(32768)
  ) spriteRamSaveStatePort (
    .clk_i(clock),
    .reset_i(reset),
    .takeover_permitted_i(ssRamTakeoverPermitted),
    .normal_rd_i(spriteRam_io_portA_rd),
    .normal_wr_i(spriteRam_io_portA_wr),
    .normal_mask_i(mainRam_io_mask),
    .normal_addr_i(_spriteRam_io_portA_addr),
    .normal_din_i(_cpu_io_dout),
    .ram_rd_o(spriteRamSaveStateRd),
    .ram_wr_o(spriteRamSaveStateWr),
    .ram_mask_o(spriteRamSaveStateMask),
    .ram_addr_o(spriteRamSaveStateAddr),
    .ram_din_o(spriteRamSaveStateDin),
    .ram_dout_i(_spriteRam_io_portA_dout),
    .takeover_active_o(ssRamTakeover[5]),
    .blocked_normal_access_o(ssRamBlockedNormalAccess[5]),
    .ssbus(mainRamOwnerBus[5])
  );
  assign spriteRamPhysicalRd =
    highScoreRamOwned && highScoreRamTargetSprite ?
      highScoreRamRd : spriteRamSaveStateRd;
  assign spriteRamPhysicalWr =
    highScoreRamOwned && highScoreRamTargetSprite ?
      highScoreRamWr : spriteRamSaveStateWr;
  assign spriteRamPhysicalMask =
    highScoreRamOwned && highScoreRamTargetSprite ?
      highScoreRamMask : spriteRamSaveStateMask;
  assign spriteRamPhysicalAddr =
    highScoreRamOwned && highScoreRamTargetSprite ?
      highScoreRamAddr : spriteRamSaveStateAddr;
  assign spriteRamPhysicalDin =
    highScoreRamOwned && highScoreRamTargetSprite ?
      highScoreRamDin : spriteRamSaveStateDin;
  CaveTrueDualPortRam #(
    .ADDR_WIDTH_A (15),
    .ADDR_WIDTH_B (12),
    .DATA_WIDTH_A (16),
    .DATA_WIDTH_B (128),
    .DEPTH_A      (0),
    .DEPTH_B      (0),
    .MASK_ENABLE  (1)
  ) spriteRam (
    .clock_a (clock),
    .rd_a    (spriteRamPhysicalRd),
    .wr_a    (spriteRamPhysicalWr),
    .addr_a  (spriteRamPhysicalAddr),
    .mask_a  (spriteRamPhysicalMask),
    .din_a   (spriteRamPhysicalDin),
    .dout_a  (_spriteRam_io_portA_dout),
    .clock_b (io_spriteClock),
    .rd_b    (io_gpuMem_sprite_vram_rd),
    .addr_b  (io_gpuMem_sprite_vram_addr),
    .dout_b  (io_gpuMem_sprite_vram_dout)
  );
  assign _vram8x8_0_io_portA_addr = _cpu_io_addr[12:0];
  wire        vram8x8_0PhysicalRd;
  wire        vram8x8_0PhysicalWr;
  wire [1:0]  vram8x8_0PhysicalMask;
  wire [12:0] vram8x8_0PhysicalAddr;
  wire [15:0] vram8x8_0PhysicalDin;
  CaveBanprestoMainRamSaveStatePort #(
    .OWNER_INDEX(8'd11),
    .ADDR_WIDTH(13),
    .ELEMENT_COUNT(8192)
  ) vram8x8_0SaveStatePort (
    .clk_i(clock),
    .reset_i(reset),
    .takeover_permitted_i(ssRamTakeoverPermitted),
    .normal_rd_i(vram8x8_0_io_portA_rd),
    .normal_wr_i(vram8x8_0_io_portA_wr),
    .normal_mask_i(mainRam_io_mask),
    .normal_addr_i(_vram8x8_0_io_portA_addr),
    .normal_din_i(_cpu_io_dout),
    .ram_rd_o(vram8x8_0PhysicalRd),
    .ram_wr_o(vram8x8_0PhysicalWr),
    .ram_mask_o(vram8x8_0PhysicalMask),
    .ram_addr_o(vram8x8_0PhysicalAddr),
    .ram_din_o(vram8x8_0PhysicalDin),
    .ram_dout_i(_vram8x8_0_io_portA_dout),
    .takeover_active_o(ssRamTakeover[7]),
    .blocked_normal_access_o(ssRamBlockedNormalAccess[7]),
    .ssbus(mainRamOwnerBus[7])
  );
  CaveTrueDualPortRam #(
    .ADDR_WIDTH_A (13),
    .ADDR_WIDTH_B (12),
    .DATA_WIDTH_A (16),
    .DATA_WIDTH_B (32),
    .DEPTH_A      (0),
    .DEPTH_B      (0),
    .MASK_ENABLE  (1)
  ) vram8x8_0 (
    .clock_a (clock),
    .rd_a    (vram8x8_0PhysicalRd),
    .wr_a    (vram8x8_0PhysicalWr),
    .addr_a  (vram8x8_0PhysicalAddr),
    .mask_a  (vram8x8_0PhysicalMask),
    .din_a   (vram8x8_0PhysicalDin),
    .dout_a  (_vram8x8_0_io_portA_dout),
    .clock_b (io_videoClock),
    .rd_b    (1'b1),
    .addr_b  (io_gpuMem_layer_0_vram8x8_addr),
    .dout_b  (io_gpuMem_layer_0_vram8x8_dout)
  );
  assign _vram8x8_1_io_portA_addr = _cpu_io_addr[12:0];
  wire        vram8x8_1PhysicalRd;
  wire        vram8x8_1PhysicalWr;
  wire [1:0]  vram8x8_1PhysicalMask;
  wire [12:0] vram8x8_1PhysicalAddr;
  wire [15:0] vram8x8_1PhysicalDin;
  CaveBanprestoMainRamSaveStatePort #(
    .OWNER_INDEX(8'd14),
    .ADDR_WIDTH(13),
    .ELEMENT_COUNT(8192)
  ) vram8x8_1SaveStatePort (
    .clk_i(clock),
    .reset_i(reset),
    .takeover_permitted_i(ssRamTakeoverPermitted),
    .normal_rd_i(vram8x8_1_io_portA_rd),
    .normal_wr_i(vram8x8_1_io_portA_wr),
    .normal_mask_i(mainRam_io_mask),
    .normal_addr_i(_vram8x8_1_io_portA_addr),
    .normal_din_i(_cpu_io_dout),
    .ram_rd_o(vram8x8_1PhysicalRd),
    .ram_wr_o(vram8x8_1PhysicalWr),
    .ram_mask_o(vram8x8_1PhysicalMask),
    .ram_addr_o(vram8x8_1PhysicalAddr),
    .ram_din_o(vram8x8_1PhysicalDin),
    .ram_dout_i(_vram8x8_1_io_portA_dout),
    .takeover_active_o(ssRamTakeover[10]),
    .blocked_normal_access_o(ssRamBlockedNormalAccess[10]),
    .ssbus(mainRamOwnerBus[10])
  );
  CaveTrueDualPortRam #(
    .ADDR_WIDTH_A (13),
    .ADDR_WIDTH_B (12),
    .DATA_WIDTH_A (16),
    .DATA_WIDTH_B (32),
    .DEPTH_A      (0),
    .DEPTH_B      (0),
    .MASK_ENABLE  (1)
  ) vram8x8_1 (
    .clock_a (clock),
    .rd_a    (vram8x8_1PhysicalRd),
    .wr_a    (vram8x8_1PhysicalWr),
    .addr_a  (vram8x8_1PhysicalAddr),
    .mask_a  (vram8x8_1PhysicalMask),
    .din_a   (vram8x8_1PhysicalDin),
    .dout_a  (_vram8x8_1_io_portA_dout),
    .clock_b (io_videoClock),
    .rd_b    (1'b1),
    .addr_b  (io_gpuMem_layer_1_vram8x8_addr),
    .dout_b  (io_gpuMem_layer_1_vram8x8_dout)
  );
  wire        vram8x8_2PhysicalRd;
  wire        vram8x8_2PhysicalWr;
  wire [1:0]  vram8x8_2PhysicalMask;
  wire [12:0] vram8x8_2PhysicalAddr;
  wire [15:0] vram8x8_2PhysicalDin;
  CaveBanprestoMainRamSaveStatePort #(
    .OWNER_INDEX(8'd17),
    .ADDR_WIDTH(13),
    .ELEMENT_COUNT(8192)
  ) vram8x8_2SaveStatePort (
    .clk_i(clock),
    .reset_i(reset),
    .takeover_permitted_i(ssRamTakeoverPermitted),
    .normal_rd_i(vram8x8_2_io_portA_rd),
    .normal_wr_i(vram8x8_2_io_portA_wr),
    .normal_mask_i(mainRam_io_mask),
    .normal_addr_i(vram8x8_2_io_portA_addr),
    .normal_din_i(_cpu_io_dout),
    .ram_rd_o(vram8x8_2PhysicalRd),
    .ram_wr_o(vram8x8_2PhysicalWr),
    .ram_mask_o(vram8x8_2PhysicalMask),
    .ram_addr_o(vram8x8_2PhysicalAddr),
    .ram_din_o(vram8x8_2PhysicalDin),
    .ram_dout_i(_vram8x8_2_io_portA_dout),
    .takeover_active_o(ssRamTakeover[13]),
    .blocked_normal_access_o(ssRamBlockedNormalAccess[13]),
    .ssbus(mainRamOwnerBus[13])
  );
  CaveTrueDualPortRam #(
    .ADDR_WIDTH_A (13),
    .ADDR_WIDTH_B (12),
    .DATA_WIDTH_A (16),
    .DATA_WIDTH_B (32),
    .DEPTH_A      (0),
    .DEPTH_B      (0),
    .MASK_ENABLE  (1)
  ) vram8x8_2 (
    .clock_a (clock),
    .rd_a    (vram8x8_2PhysicalRd),
    .wr_a    (vram8x8_2PhysicalWr),
    .addr_a  (vram8x8_2PhysicalAddr),
    .mask_a  (vram8x8_2PhysicalMask),
    .din_a   (vram8x8_2PhysicalDin),
    .dout_a  (_vram8x8_2_io_portA_dout),
    .clock_b (io_videoClock),
    .rd_b    (1'b1),
    .addr_b  (io_gpuMem_layer_2_vram8x8_addr),
    .dout_b  (io_gpuMem_layer_2_vram8x8_dout)
  );
  assign _vram16x16_0_io_portA_addr = _cpu_io_addr[10:0];
  wire        vram16x16_0PhysicalRd;
  wire        vram16x16_0PhysicalWr;
  wire [1:0]  vram16x16_0PhysicalMask;
  wire [10:0] vram16x16_0PhysicalAddr;
  wire [15:0] vram16x16_0PhysicalDin;
  CaveBanprestoMainRamSaveStatePort #(
    .OWNER_INDEX(8'd12),
    .ADDR_WIDTH(11),
    .ELEMENT_COUNT(2048)
  ) vram16x16_0SaveStatePort (
    .clk_i(clock),
    .reset_i(reset),
    .takeover_permitted_i(ssRamTakeoverPermitted),
    .normal_rd_i(vram16x16_0_io_portA_rd),
    .normal_wr_i(vram16x16_0_io_portA_wr),
    .normal_mask_i(mainRam_io_mask),
    .normal_addr_i(_vram16x16_0_io_portA_addr),
    .normal_din_i(_cpu_io_dout),
    .ram_rd_o(vram16x16_0PhysicalRd),
    .ram_wr_o(vram16x16_0PhysicalWr),
    .ram_mask_o(vram16x16_0PhysicalMask),
    .ram_addr_o(vram16x16_0PhysicalAddr),
    .ram_din_o(vram16x16_0PhysicalDin),
    .ram_dout_i(_vram16x16_0_io_portA_dout),
    .takeover_active_o(ssRamTakeover[8]),
    .blocked_normal_access_o(ssRamBlockedNormalAccess[8]),
    .ssbus(mainRamOwnerBus[8])
  );
  CaveTrueDualPortRam #(
    .ADDR_WIDTH_A (11),
    .ADDR_WIDTH_B (10),
    .DATA_WIDTH_A (16),
    .DATA_WIDTH_B (32),
    .DEPTH_A      (0),
    .DEPTH_B      (0),
    .MASK_ENABLE  (1)
  ) vram16x16_0 (
    .clock_a (clock),
    .rd_a    (vram16x16_0PhysicalRd),
    .wr_a    (vram16x16_0PhysicalWr),
    .addr_a  (vram16x16_0PhysicalAddr),
    .mask_a  (vram16x16_0PhysicalMask),
    .din_a   (vram16x16_0PhysicalDin),
    .dout_a  (_vram16x16_0_io_portA_dout),
    .clock_b (io_videoClock),
    .rd_b    (1'b1),
    .addr_b  (io_gpuMem_layer_0_vram16x16_addr),
    .dout_b  (io_gpuMem_layer_0_vram16x16_dout)
  );
  assign _vram16x16_1_io_portA_addr = _cpu_io_addr[10:0];
  wire        vram16x16_1PhysicalRd;
  wire        vram16x16_1PhysicalWr;
  wire [1:0]  vram16x16_1PhysicalMask;
  wire [10:0] vram16x16_1PhysicalAddr;
  wire [15:0] vram16x16_1PhysicalDin;
  CaveBanprestoMainRamSaveStatePort #(
    .OWNER_INDEX(8'd15),
    .ADDR_WIDTH(11),
    .ELEMENT_COUNT(2048)
  ) vram16x16_1SaveStatePort (
    .clk_i(clock),
    .reset_i(reset),
    .takeover_permitted_i(ssRamTakeoverPermitted),
    .normal_rd_i(vram16x16_1_io_portA_rd),
    .normal_wr_i(vram16x16_1_io_portA_wr),
    .normal_mask_i(mainRam_io_mask),
    .normal_addr_i(_vram16x16_1_io_portA_addr),
    .normal_din_i(_cpu_io_dout),
    .ram_rd_o(vram16x16_1PhysicalRd),
    .ram_wr_o(vram16x16_1PhysicalWr),
    .ram_mask_o(vram16x16_1PhysicalMask),
    .ram_addr_o(vram16x16_1PhysicalAddr),
    .ram_din_o(vram16x16_1PhysicalDin),
    .ram_dout_i(_vram16x16_1_io_portA_dout),
    .takeover_active_o(ssRamTakeover[11]),
    .blocked_normal_access_o(ssRamBlockedNormalAccess[11]),
    .ssbus(mainRamOwnerBus[11])
  );
  CaveTrueDualPortRam #(
    .ADDR_WIDTH_A (11),
    .ADDR_WIDTH_B (10),
    .DATA_WIDTH_A (16),
    .DATA_WIDTH_B (32),
    .DEPTH_A      (0),
    .DEPTH_B      (0),
    .MASK_ENABLE  (1)
  ) vram16x16_1 (
    .clock_a (clock),
    .rd_a    (vram16x16_1PhysicalRd),
    .wr_a    (vram16x16_1PhysicalWr),
    .addr_a  (vram16x16_1PhysicalAddr),
    .mask_a  (vram16x16_1PhysicalMask),
    .din_a   (vram16x16_1PhysicalDin),
    .dout_a  (_vram16x16_1_io_portA_dout),
    .clock_b (io_videoClock),
    .rd_b    (1'b1),
    .addr_b  (io_gpuMem_layer_1_vram16x16_addr),
    .dout_b  (io_gpuMem_layer_1_vram16x16_dout)
  );
  assign _vram16x16_2_io_portA_addr = _cpu_io_addr[10:0];
  wire        vram16x16_2PhysicalRd;
  wire        vram16x16_2PhysicalWr;
  wire [1:0]  vram16x16_2PhysicalMask;
  wire [10:0] vram16x16_2PhysicalAddr;
  wire [15:0] vram16x16_2PhysicalDin;
  CaveBanprestoMainRamSaveStatePort #(
    .OWNER_INDEX(8'd18),
    .ADDR_WIDTH(11),
    .ELEMENT_COUNT(2048)
  ) vram16x16_2SaveStatePort (
    .clk_i(clock),
    .reset_i(reset),
    .takeover_permitted_i(ssRamTakeoverPermitted),
    .normal_rd_i(vram16x16_2_io_portA_rd),
    .normal_wr_i(vram16x16_2_io_portA_wr),
    .normal_mask_i(mainRam_io_mask),
    .normal_addr_i(_vram16x16_2_io_portA_addr),
    .normal_din_i(_cpu_io_dout),
    .ram_rd_o(vram16x16_2PhysicalRd),
    .ram_wr_o(vram16x16_2PhysicalWr),
    .ram_mask_o(vram16x16_2PhysicalMask),
    .ram_addr_o(vram16x16_2PhysicalAddr),
    .ram_din_o(vram16x16_2PhysicalDin),
    .ram_dout_i(_vram16x16_2_io_portA_dout),
    .takeover_active_o(ssRamTakeover[14]),
    .blocked_normal_access_o(ssRamBlockedNormalAccess[14]),
    .ssbus(mainRamOwnerBus[14])
  );
  CaveTrueDualPortRam #(
    .ADDR_WIDTH_A (11),
    .ADDR_WIDTH_B (10),
    .DATA_WIDTH_A (16),
    .DATA_WIDTH_B (32),
    .DEPTH_A      (0),
    .DEPTH_B      (0),
    .MASK_ENABLE  (1)
  ) vram16x16_2 (
    .clock_a (clock),
    .rd_a    (vram16x16_2PhysicalRd),
    .wr_a    (vram16x16_2PhysicalWr),
    .addr_a  (vram16x16_2PhysicalAddr),
    .mask_a  (vram16x16_2PhysicalMask),
    .din_a   (vram16x16_2PhysicalDin),
    .dout_a  (_vram16x16_2_io_portA_dout),
    .clock_b (io_videoClock),
    .rd_b    (1'b1),
    .addr_b  (io_gpuMem_layer_2_vram16x16_addr),
    .dout_b  (io_gpuMem_layer_2_vram16x16_dout)
  );
  assign _lineRam_0_io_portA_addr = _cpu_io_addr[9:0];
  wire       lineRam_0PhysicalRd;
  wire       lineRam_0PhysicalWr;
  wire [1:0] lineRam_0PhysicalMask;
  wire [9:0] lineRam_0PhysicalAddr;
  wire [15:0] lineRam_0PhysicalDin;
  CaveBanprestoMainRamSaveStatePort #(
    .OWNER_INDEX(8'd13),
    .ADDR_WIDTH(10),
    .ELEMENT_COUNT(1024)
  ) lineRam_0SaveStatePort (
    .clk_i(clock),
    .reset_i(reset),
    .takeover_permitted_i(ssRamTakeoverPermitted),
    .normal_rd_i(lineRam_0_io_portA_rd),
    .normal_wr_i(lineRam_0_io_portA_wr),
    .normal_mask_i(mainRam_io_mask),
    .normal_addr_i(_lineRam_0_io_portA_addr),
    .normal_din_i(_cpu_io_dout),
    .ram_rd_o(lineRam_0PhysicalRd),
    .ram_wr_o(lineRam_0PhysicalWr),
    .ram_mask_o(lineRam_0PhysicalMask),
    .ram_addr_o(lineRam_0PhysicalAddr),
    .ram_din_o(lineRam_0PhysicalDin),
    .ram_dout_i(_lineRam_0_io_portA_dout),
    .takeover_active_o(ssRamTakeover[9]),
    .blocked_normal_access_o(ssRamBlockedNormalAccess[9]),
    .ssbus(mainRamOwnerBus[9])
  );
  CaveTrueDualPortRam #(
    .ADDR_WIDTH_A (10),
    .ADDR_WIDTH_B (9),
    .DATA_WIDTH_A (16),
    .DATA_WIDTH_B (32),
    .DEPTH_A      (0),
    .DEPTH_B      (0),
    .MASK_ENABLE  (1)
  ) lineRam_0 (
    .clock_a (clock),
    .rd_a    (lineRam_0PhysicalRd),
    .wr_a    (lineRam_0PhysicalWr),
    .addr_a  (lineRam_0PhysicalAddr),
    .mask_a  (lineRam_0PhysicalMask),
    .din_a   (lineRam_0PhysicalDin),
    .dout_a  (_lineRam_0_io_portA_dout),
    .clock_b (io_videoClock),
    .rd_b    (1'b1),
    .addr_b  (io_gpuMem_layer_0_lineRam_addr),
    .dout_b  (io_gpuMem_layer_0_lineRam_dout)
  );
  assign _lineRam_1_io_portA_addr = _cpu_io_addr[9:0];
  wire       lineRam_1PhysicalRd;
  wire       lineRam_1PhysicalWr;
  wire [1:0] lineRam_1PhysicalMask;
  wire [9:0] lineRam_1PhysicalAddr;
  wire [15:0] lineRam_1PhysicalDin;
  CaveBanprestoMainRamSaveStatePort #(
    .OWNER_INDEX(8'd16),
    .ADDR_WIDTH(10),
    .ELEMENT_COUNT(1024)
  ) lineRam_1SaveStatePort (
    .clk_i(clock),
    .reset_i(reset),
    .takeover_permitted_i(ssRamTakeoverPermitted),
    .normal_rd_i(lineRam_1_io_portA_rd),
    .normal_wr_i(lineRam_1_io_portA_wr),
    .normal_mask_i(mainRam_io_mask),
    .normal_addr_i(_lineRam_1_io_portA_addr),
    .normal_din_i(_cpu_io_dout),
    .ram_rd_o(lineRam_1PhysicalRd),
    .ram_wr_o(lineRam_1PhysicalWr),
    .ram_mask_o(lineRam_1PhysicalMask),
    .ram_addr_o(lineRam_1PhysicalAddr),
    .ram_din_o(lineRam_1PhysicalDin),
    .ram_dout_i(_lineRam_1_io_portA_dout),
    .takeover_active_o(ssRamTakeover[12]),
    .blocked_normal_access_o(ssRamBlockedNormalAccess[12]),
    .ssbus(mainRamOwnerBus[12])
  );
  CaveTrueDualPortRam #(
    .ADDR_WIDTH_A (10),
    .ADDR_WIDTH_B (9),
    .DATA_WIDTH_A (16),
    .DATA_WIDTH_B (32),
    .DEPTH_A      (0),
    .DEPTH_B      (0),
    .MASK_ENABLE  (1)
  ) lineRam_1 (
    .clock_a (clock),
    .rd_a    (lineRam_1PhysicalRd),
    .wr_a    (lineRam_1PhysicalWr),
    .addr_a  (lineRam_1PhysicalAddr),
    .mask_a  (lineRam_1PhysicalMask),
    .din_a   (lineRam_1PhysicalDin),
    .dout_a  (_lineRam_1_io_portA_dout),
    .clock_b (io_videoClock),
    .rd_b    (1'b1),
    .addr_b  (io_gpuMem_layer_1_lineRam_addr),
    .dout_b  (io_gpuMem_layer_1_lineRam_dout)
  );
  assign _lineRam_2_io_portA_addr = _cpu_io_addr[9:0];
  wire       lineRam_2PhysicalRd;
  wire       lineRam_2PhysicalWr;
  wire [1:0] lineRam_2PhysicalMask;
  wire [9:0] lineRam_2PhysicalAddr;
  wire [15:0] lineRam_2PhysicalDin;
  CaveBanprestoMainRamSaveStatePort #(
    .OWNER_INDEX(8'd19),
    .ADDR_WIDTH(10),
    .ELEMENT_COUNT(1024)
  ) lineRam_2SaveStatePort (
    .clk_i(clock),
    .reset_i(reset),
    .takeover_permitted_i(ssRamTakeoverPermitted),
    .normal_rd_i(lineRam_2_io_portA_rd),
    .normal_wr_i(lineRam_2_io_portA_wr),
    .normal_mask_i(mainRam_io_mask),
    .normal_addr_i(_lineRam_2_io_portA_addr),
    .normal_din_i(_cpu_io_dout),
    .ram_rd_o(lineRam_2PhysicalRd),
    .ram_wr_o(lineRam_2PhysicalWr),
    .ram_mask_o(lineRam_2PhysicalMask),
    .ram_addr_o(lineRam_2PhysicalAddr),
    .ram_din_o(lineRam_2PhysicalDin),
    .ram_dout_i(_lineRam_2_io_portA_dout),
    .takeover_active_o(ssRamTakeover[15]),
    .blocked_normal_access_o(ssRamBlockedNormalAccess[15]),
    .ssbus(mainRamOwnerBus[15])
  );
  CaveTrueDualPortRam #(
    .ADDR_WIDTH_A (10),
    .ADDR_WIDTH_B (9),
    .DATA_WIDTH_A (16),
    .DATA_WIDTH_B (32),
    .DEPTH_A      (0),
    .DEPTH_B      (0),
    .MASK_ENABLE  (1)
  ) lineRam_2 (
    .clock_a (clock),
    .rd_a    (lineRam_2PhysicalRd),
    .wr_a    (lineRam_2PhysicalWr),
    .addr_a  (lineRam_2PhysicalAddr),
    .mask_a  (lineRam_2PhysicalMask),
    .din_a   (lineRam_2PhysicalDin),
    .dout_a  (_lineRam_2_io_portA_dout),
    .clock_b (io_videoClock),
    .rd_b    (1'b1),
    .addr_b  (io_gpuMem_layer_2_lineRam_addr),
    .dout_b  (io_gpuMem_layer_2_lineRam_dout)
  );
  wire        paletteRamPhysicalRd;
  wire        paletteRamPhysicalWr;
  wire [1:0]  paletteRamPhysicalMask;
  wire [14:0] paletteRamPhysicalAddr;
  wire [15:0] paletteRamPhysicalDin;
  CaveBanprestoMainRamSaveStatePort #(
    .OWNER_INDEX(8'd10),
    .ADDR_WIDTH(15),
    .ELEMENT_COUNT(32768)
  ) paletteRamSaveStatePort (
    .clk_i(clock),
    .reset_i(reset),
    .takeover_permitted_i(ssRamTakeoverPermitted),
    .normal_rd_i(paletteRam_io_portA_rd),
    .normal_wr_i(paletteRam_io_portA_wr),
    .normal_mask_i(mainRam_io_mask),
    .normal_addr_i(paletteRam_io_portA_addr),
    .normal_din_i(_cpu_io_dout),
    .ram_rd_o(paletteRamPhysicalRd),
    .ram_wr_o(paletteRamPhysicalWr),
    .ram_mask_o(paletteRamPhysicalMask),
    .ram_addr_o(paletteRamPhysicalAddr),
    .ram_din_o(paletteRamPhysicalDin),
    .ram_dout_i(_paletteRam_io_portA_dout),
    .takeover_active_o(ssRamTakeover[6]),
    .blocked_normal_access_o(ssRamBlockedNormalAccess[6]),
    .ssbus(mainRamOwnerBus[6])
  );
  CaveTrueDualPortRam #(
    .ADDR_WIDTH_A (15),
    .ADDR_WIDTH_B (15),
    .DATA_WIDTH_A (16),
    .DATA_WIDTH_B (16),
    .DEPTH_A      (0),
    .DEPTH_B      (0),
    .MASK_ENABLE  (1)
  ) paletteRam (
    .clock_a (clock),
    .rd_a    (paletteRamPhysicalRd),
    .wr_a    (paletteRamPhysicalWr),
    .addr_a  (paletteRamPhysicalAddr),
    .mask_a  (paletteRamPhysicalMask),
    .din_a   (paletteRamPhysicalDin),
    .dout_a  (_paletteRam_io_portA_dout),
    .clock_b (io_videoClock),
    .rd_b    (1'b1),
    .addr_b  (io_gpuMem_paletteRam_addr),
    .dout_b  (io_gpuMem_paletteRam_dout)
  );
  assign _layerRegs_0_io_mem_addr = _cpu_io_addr[1:0];
  CaveBanprestoMainLayerRegisterFile layerRegs_0 (
    .clock                     (clock),
    .io_mem_wr                 (layerRegs_0_io_mem_wr),
    .io_mem_addr               (_layerRegs_0_io_mem_addr),
    .io_mem_mask               (mainRam_io_mask),
    .io_mem_din                (_cpu_io_dout),
    .ss_hold_i                 (mainRegisterStateHold),
    .ss_restore_load_i         (mainRegisterRestoreLoad),
    .ss_state_i                (mainRegisterRestoreState[47:0]),
    .ss_state_o                (mainLayer0RegisterState),
    .ss_blocked_normal_write_o (mainRegisterBlockedWrite[0]),
    .io_mem_dout               (_layerRegs_0_io_mem_dout),
    .io_regs_0                 (_layerRegs_0_io_regs_0),
    .io_regs_1                 (_layerRegs_0_io_regs_1),
    .io_regs_2                 (_layerRegs_0_io_regs_2)
  );
  assign _layerRegs_1_io_mem_addr = _cpu_io_addr[1:0];
  CaveBanprestoMainLayerRegisterFile layerRegs_1 (
    .clock                     (clock),
    .io_mem_wr                 (layerRegs_1_io_mem_wr),
    .io_mem_addr               (_layerRegs_1_io_mem_addr),
    .io_mem_mask               (mainRam_io_mask),
    .io_mem_din                (_cpu_io_dout),
    .ss_hold_i                 (mainRegisterStateHold),
    .ss_restore_load_i         (mainRegisterRestoreLoad),
    .ss_state_i                (mainRegisterRestoreState[95:48]),
    .ss_state_o                (mainLayer1RegisterState),
    .ss_blocked_normal_write_o (mainRegisterBlockedWrite[1]),
    .io_mem_dout               (_layerRegs_1_io_mem_dout),
    .io_regs_0                 (_layerRegs_1_io_regs_0),
    .io_regs_1                 (_layerRegs_1_io_regs_1),
    .io_regs_2                 (_layerRegs_1_io_regs_2)
  );
  assign _layerRegs_2_io_mem_addr = _cpu_io_addr[1:0];
  CaveBanprestoMainLayerRegisterFile layerRegs_2 (
    .clock                     (clock),
    .io_mem_wr                 (layerRegs_2_io_mem_wr),
    .io_mem_addr               (_layerRegs_2_io_mem_addr),
    .io_mem_mask               (mainRam_io_mask),
    .io_mem_din                (_cpu_io_dout),
    .ss_hold_i                 (mainRegisterStateHold),
    .ss_restore_load_i         (mainRegisterRestoreLoad),
    .ss_state_i                (mainRegisterRestoreState[143:96]),
    .ss_state_o                (mainLayer2RegisterState),
    .ss_blocked_normal_write_o (mainRegisterBlockedWrite[2]),
    .io_mem_dout               (_layerRegs_2_io_mem_dout),
    .io_regs_0                 (_layerRegs_2_io_regs_0),
    .io_regs_1                 (_layerRegs_2_io_regs_1),
    .io_regs_2                 (_layerRegs_2_io_regs_2)
  );
  assign _spriteRegs_io_mem_mask = {_cpu_io_uds, _cpu_io_lds};
  CaveBanprestoMainSpriteRegisterFile spriteRegs (
    .clock                     (clock),
    .io_mem_wr                 (spriteRegs_io_mem_wr),
    .io_mem_addr               (spriteRegs_io_mem_addr),
    .io_mem_mask               (_spriteRegs_io_mem_mask),
    .io_mem_din                (_cpu_io_dout),
    .ss_hold_i                 (mainRegisterStateHold),
    .ss_restore_load_i         (mainRegisterRestoreLoad),
    .ss_state_i                (mainRegisterRestoreState[271:144]),
    .ss_state_o                (mainSpriteRegisterState),
    .ss_blocked_normal_write_o (mainRegisterBlockedWrite[3]),
    .io_regs_0                 (_spriteRegs_io_regs_0),
    .io_regs_1                 (_spriteRegs_io_regs_1),
    .io_regs_2                 (/* unused */),
    .io_regs_3                 (/* unused */),
    .io_regs_4                 (_spriteRegs_io_regs_4),
    .io_regs_5                 (_spriteRegs_io_regs_5)
  );
  assign io_gpuMem_layer_0_regs_tileSize = io_gpuMem_layer_0_regs_r_1_tileSize;
  assign io_gpuMem_layer_0_regs_enable = io_gpuMem_layer_0_regs_r_1_enable;
  assign io_gpuMem_layer_0_regs_flipX = io_gpuMem_layer_0_regs_r_1_flipX;
  assign io_gpuMem_layer_0_regs_flipY = io_gpuMem_layer_0_regs_r_1_flipY;
  assign io_gpuMem_layer_0_regs_rowScrollEnable =
    io_gpuMem_layer_0_regs_r_1_rowScrollEnable;
  assign io_gpuMem_layer_0_regs_rowSelectEnable =
    io_gpuMem_layer_0_regs_r_1_rowSelectEnable;
  assign io_gpuMem_layer_0_regs_priority = io_gpuMem_layer_0_regs_r_1_priority;
  assign io_gpuMem_layer_0_regs_scroll_x = io_gpuMem_layer_0_regs_r_1_scroll_x;
  assign io_gpuMem_layer_0_regs_scroll_y = io_gpuMem_layer_0_regs_r_1_scroll_y;
  assign io_gpuMem_layer_1_regs_tileSize = io_gpuMem_layer_1_regs_r_1_tileSize;
  assign io_gpuMem_layer_1_regs_enable = io_gpuMem_layer_1_regs_r_1_enable;
  assign io_gpuMem_layer_1_regs_flipX = io_gpuMem_layer_1_regs_r_1_flipX;
  assign io_gpuMem_layer_1_regs_flipY = io_gpuMem_layer_1_regs_r_1_flipY;
  assign io_gpuMem_layer_1_regs_rowScrollEnable =
    io_gpuMem_layer_1_regs_r_1_rowScrollEnable;
  assign io_gpuMem_layer_1_regs_rowSelectEnable =
    io_gpuMem_layer_1_regs_r_1_rowSelectEnable;
  assign io_gpuMem_layer_1_regs_priority = io_gpuMem_layer_1_regs_r_1_priority;
  assign io_gpuMem_layer_1_regs_scroll_x = io_gpuMem_layer_1_regs_r_1_scroll_x;
  assign io_gpuMem_layer_1_regs_scroll_y = io_gpuMem_layer_1_regs_r_1_scroll_y;
  assign io_gpuMem_layer_2_regs_tileSize = io_gpuMem_layer_2_regs_r_1_tileSize;
  assign io_gpuMem_layer_2_regs_enable = io_gpuMem_layer_2_regs_r_1_enable;
  assign io_gpuMem_layer_2_regs_flipX = io_gpuMem_layer_2_regs_r_1_flipX;
  assign io_gpuMem_layer_2_regs_flipY = io_gpuMem_layer_2_regs_r_1_flipY;
  assign io_gpuMem_layer_2_regs_rowScrollEnable =
    io_gpuMem_layer_2_regs_r_1_rowScrollEnable;
  assign io_gpuMem_layer_2_regs_rowSelectEnable =
    io_gpuMem_layer_2_regs_r_1_rowSelectEnable;
  assign io_gpuMem_layer_2_regs_priority = io_gpuMem_layer_2_regs_r_1_priority;
  assign io_gpuMem_layer_2_regs_scroll_x = io_gpuMem_layer_2_regs_r_1_scroll_x;
  assign io_gpuMem_layer_2_regs_scroll_y = io_gpuMem_layer_2_regs_r_1_scroll_y;
  assign io_gpuMem_sprite_regs_offset_x = _spriteRegs_io_regs_0[8:0];
  assign io_gpuMem_sprite_regs_offset_y = _spriteRegs_io_regs_1[8:0];
  assign io_gpuMem_sprite_regs_bank = _spriteRegs_io_regs_4[1:0];
  assign io_gpuMem_sprite_regs_fixed = |(_spriteRegs_io_regs_5[13:12]);
  assign io_gpuMem_sprite_regs_hFlip = _spriteRegs_io_regs_0[15];
`ifdef CAVE_ENABLE_DEBUG_OVERLAY
  assign io_debug_pipeline =
    gameIsAirFamily ? airGalletDebugSeen :
    gameIsMazinger ? mazingerDebugSeen :
    gameIsHotdogStorm ? hotdogDebugSeen : 64'd0;
  assign io_debug_cpu =
    gameIsAirFamily ? airGalletDebugCpuBits :
    gameIsMazinger ? mazingerDebugCpuBits :
    gameIsHotdogStorm ? hotdogDebugCpuBits : 64'd0;
  assign io_debug_writes =
    gameIsAirFamily ? airGalletDebugWriteBits :
    gameIsMazinger ? mazingerDebugWriteBits :
    gameIsHotdogStorm ? hotdogDebugWriteBits : 64'd0;
  assign io_debug_data =
    gameIsAirFamily ? airGalletDebugDataBits :
    gameIsMazinger ? mazingerDebugDataBits :
    gameIsHotdogStorm ? hotdogDebugDataBits : 64'd0;
  assign io_debug_live =
    gameIsAirFamily ? airGalletDebugLiveBits :
    gameIsMazinger ? mazingerDebugLiveBits :
    gameIsHotdogStorm ? hotdogDebugLiveBits : 64'd0;
  assign io_debug_palette =
    gameIsAirFamily ? airGalletDebugPaletteBits :
    gameIsMazinger ? mazingerDebugPaletteBits :
    gameIsHotdogStorm ? hotdogDebugPaletteBits : 64'd0;
`else
  assign io_debug_pipeline = 64'd0;
  assign io_debug_cpu = 64'd0;
  assign io_debug_writes = 64'd0;
  assign io_debug_data = 64'd0;
  assign io_debug_live = 64'd0;
  assign io_debug_palette = 64'd0;
`endif
  assign io_soundCtrl_oki_0_wr = 1'b0;
  assign io_soundCtrl_oki_0_din = _cpu_io_dout;
  assign io_soundCtrl_oki_1_wr = 1'b0;
  assign io_soundCtrl_oki_1_din = _cpu_io_dout;
  assign io_soundCtrl_nmk_wr = 1'b0;
  assign io_soundCtrl_nmk_addr = _cpu_io_addr;
  assign io_soundCtrl_nmk_din = _cpu_io_dout;
  assign io_soundCtrl_ymz_rd = 1'b0;
  assign io_soundCtrl_ymz_wr = 1'b0;
  assign io_soundCtrl_ymz_addr = _cpu_io_addr;
  assign io_soundCtrl_ymz_din = _cpu_io_dout;
  assign io_soundCtrl_req =
    (gameIsAirFamily & airGalletSoundWrite) |
    (gameIsMazinger & mazingerSoundWrite) |
    (gameIsHotdogStorm & hotdogSoundWrite) |
    (gameIsMetmqstr & metmqstrSoundWrite);
  assign io_soundCtrl_data = _cpu_io_dout;
  assign io_soundCtrl_reply_rd =
    (gameIsAirFamily & airGalletSoundRead) |
    (gameIsMazinger & mazingerSoundRead) |
    (gameIsMetmqstr & metmqstrSoundRead);
  assign io_progRom_rd =
    (gameIsAirFamily & airGalletProgRomRead) |
    (gameIsMazinger & mazingerProgRomRead) |
    (gameIsHotdogStorm & hotdogProgRomRead) |
    (gameIsMetmqstr & metmqstrProgRomRead);
  wire [21:0] sailorMoonExtraProgRomAddr = airGalletCpuByteAddr[21:0] - 22'h180000;
  assign io_progRom_addr =
    (gameIsSailorMoon & airGalletExtraRomSelect)
      ? sailorMoonExtraProgRomAddr
      : gameIsAirFamily
      ? airGalletCpuByteAddr[21:0]
      : (gameIsMazinger & mazingerExtraRomSelect)
      ? {2'b00, 1'b1, cpuByteAddr[18:0]}
      : gameIsHotdogStorm
      ? hotdogCpuByteAddr[21:0]
      : gameIsMetmqstr
      ? metmqstrProgRomPackedAddr
      : {2'b00, _cpu_io_addr[18:0], 1'b0};
  assign io_spriteFrameBufferSwap =
    (gameIsAirFamily & airGalletSpriteSwapWrite) |
    (gameIsMazinger & videoVBlankRising) |
    (gameIsHotdogStorm & (hotdogSpriteSwapWrite | videoVBlankRising)) |
    (gameIsMetmqstr & videoVBlankRising);
endmodule
