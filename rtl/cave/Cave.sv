// This file is a Codex-assisted rewrite based on the original work of
// Josh Bassett (nullobject).

// Core top-level shell connecting MiSTer-facing services to the Cave game hardware.
module Cave(
  input         clock,
  input         reset,
  input         cpuClock,
  input         cpuReset,
  input         videoClock,
  input         videoReset,
  input  [3:0]  options_offset_x,
  input  [3:0]  options_offset_y,
  input         options_rotate,
  input         options_compatibility,
  input         options_service,
  input         options_layer_0,
  input         options_layer_1,
  input         options_layer_2,
  input         options_sprite,
  input         options_flipVideo,
  input  [3:0]  options_gameIndex,
  input         options_debugVideo,
  input  [2:0]  options_debugView,
  input  [3:0]  options_audioTrim_fm,
  input  [3:0]  options_audioTrim_bgm,
  input  [3:0]  options_audioTrim_sfx,
  input         player_0_up,
  input         player_0_down,
  input         player_0_left,
  input         player_0_right,
  input  [3:0]  player_0_buttons,
  input         player_0_start,
  input         player_0_coin,
  input         player_0_pause,
  input         player_1_up,
  input         player_1_down,
  input         player_1_left,
  input         player_1_right,
  input  [3:0]  player_1_buttons,
  input         player_1_start,
  input         player_1_coin,
  input         player_1_pause,
  input         ss_save_request,
  input         ss_load_request,
  input  [1:0]  ss_slot,
  output        ss_available,
  output        ss_active,
  output        ss_busy,
  output        ss_hdmi_freeze,
  output [3:0]  game_index,
  input         ioctl_download,
  input         ioctl_upload,
  input         ioctl_rd,
  input         ioctl_wr,
  output        ioctl_wait_n,
  input  [7:0]  ioctl_index,
  input  [26:0] ioctl_addr,
  output [15:0] ioctl_din,
  input  [15:0] ioctl_dout,
  output        nvram_dirty,
  output        led_power,
  output        led_disk,
  output        led_user,
  output        frameBufferCtrl_enable,
  output [11:0] frameBufferCtrl_hSize,
  output [11:0] frameBufferCtrl_vSize,
  output [4:0]  frameBufferCtrl_format,
  output [31:0] frameBufferCtrl_baseAddr,
  output [13:0] frameBufferCtrl_stride,
  input         frameBufferCtrl_vBlank,
  input         frameBufferCtrl_lowLat,
  output        frameBufferCtrl_forceBlank,
  output        video_clockEnable,
  output        video_displayEnable,
  output [8:0]  video_pos_x,
  output [8:0]  video_pos_y,
  output        video_hSync,
  output        video_vSync,
  output        video_hBlank,
  output        video_vBlank,
  output [8:0]  video_regs_size_x,
  output [8:0]  video_regs_size_y,
  output [8:0]  video_regs_frontPorch_x,
  output [8:0]  video_regs_frontPorch_y,
  output [8:0]  video_regs_retrace_x,
  output [8:0]  video_regs_retrace_y,
  output        video_changeMode,
  output        video_rotated,
  output [23:0] rgb,
  output [15:0] audio,
  output        sdram_cke,
  output        sdram_cs_n,
  output        sdram_ras_n,
  output        sdram_cas_n,
  output        sdram_we_n,
  output        sdram_oe_n,
  output [1:0]  sdram_bank,
  output [12:0] sdram_addr,
  output [15:0] sdram_din,
  input  [15:0] sdram_dout,
  output        ddr_rd,
  output        ddr_wr,
  output [31:0] ddr_addr,
  output [7:0]  ddr_mask,
  output [63:0] ddr_din,
  input  [63:0] ddr_dout,
  input         ddr_wait_n,
  input         ddr_valid,
  output [7:0]  ddr_burstLength,
  input         ddr_burstDone
);

  localparam [47:0] SS_COMPILED_SUPPORT =
    48'h0000_3fff_ffff;
  localparam [47:0] SS_HOTDOG_SUPPORT =
    48'h0000_27ff_fe1f;
  localparam [47:0] SS_MAZINGER_SUPPORT =
    48'h0000_27f0_4e1f;
  localparam [47:0] SS_AIR_SUPPORT =
    48'h0000_3bff_ffff;
  localparam [47:0] SS_SAILOR_SUPPORT =
    48'h0000_3bff_ffff;
  localparam [47:0] SS_METMQSTR_SUPPORT =
    48'h0000_3bff_fe0f;
  localparam [47:0] SS_MAIN_SUPPORT =
    48'h0000_005f_fffc;
  localparam [47:0] SS_SOUND_SUPPORT =
    48'h0000_3f80_0000;
  localparam integer SS_IDLE_ACK_COUNT = 41;
  // The longest legal pre-stream dependency is owner 34's one-million-cycle
  // 96 MHz drain (10.42 ms).  A live Air Gallet release proved that Main can
  // legitimately need more than the former 16.38 ms destination and 18.75 ms
  // source budgets.  Keep the fail-closed watchdogs layered in wall time:
  // transport < 32 MHz endpoint < 96 MHz CDC source < quiesce phase.  Powers
  // of two also reduce each terminal-count comparison to a narrow carry/AND
  // structure instead of adding another wide arbitrary-constant cone.
  localparam integer SS_CONTROL_DESTINATION_TIMEOUT_CYCLES = 1_048_576;
  localparam integer SS_CONTROL_SOURCE_TIMEOUT_CYCLES = 4_194_304;
  localparam integer SS_QUIESCE_PHASE_TIMEOUT_CYCLES = 8_388_608;

  cavebanpresto_ssbus_if saveStateStreamBus();
  cavebanpresto_ssbus_if saveStateSystemBranches [5]();
  cavebanpresto_ssbus_if saveStateMainCpuBus();
  cavebanpresto_ssbus_if saveStateMainBranches [5]();

  wire [47:0] saveStateProfileSupport;
  wire [47:0] saveStateRuntimeSupport;
  reg  [47:0] saveStateOperationSupport;
  wire        saveStateProfileSupported;
  wire [31:0] saveStateSlotBase;
  reg  [1:0]  saveStateOperationSlot;
  wire [63:0] saveStateConfigFingerprint;
  reg  [63:0] saveStateOperationConfig;
  wire [63:0] saveStateRuntimeConfig;
  wire        saveStateOperationInFlight;
  wire        saveStateOperationRequest;
  wire        saveStateIoctlIdle;

  wire        saveStateIdentityMemRd;
  wire [31:0] saveStateIdentityMemAddr;
  wire        saveStateIdentityMemReady;
  wire        saveStateIdentityMemValid;
  wire [63:0] saveStateIdentityMemData;
  wire        saveStateIdentityBusy;
  wire        saveStateIdentityScanDone;
  wire        saveStateIdentityMetadataDone;
  wire        saveStateIdentityValid;
  wire        saveStateIdentityError;
  wire [7:0]  saveStateIdentityErrorFlags;
  wire [31:0] saveStateRomLength;
  wire [63:0] saveStateRomCrc64;
  wire [63:0] saveStateCanonicalSetId;
  wire [7:0]  saveStateMetadataBoardId;

  wire        saveStateMaintenanceAcquire;
  wire        saveStateMaintenanceGranted;
  wire        saveStateMaintenanceCmdValid;
  wire        saveStateMaintenanceCmdReady;
  wire        saveStateMaintenanceCmdWrite;
  wire [31:0] saveStateMaintenanceCmdAddr;
  wire [63:0] saveStateMaintenanceCmdData;
  wire [7:0]  saveStateMaintenanceCmdBe;
  wire [7:0]  saveStateMaintenanceCmdBurst;
  wire        saveStateMaintenanceRspValid;
  wire [63:0] saveStateMaintenanceRspData;
  wire        saveStateMaintenanceIdle;
  wire        saveStateMaintenanceActive;
  wire        saveStateMaintenanceIdentityOwner;
  wire        saveStateMaintenanceReleasing;
  wire        saveStateMaintenanceConflict;
  wire        saveStateMaintenanceProtocolError;
  wire        saveStateMaintenanceUnexpectedResponse;
  wire        saveStateMaintenanceTimeout;
  wire        saveStateMaintenanceTerminalFault;

  wire        saveStateStreamDdrCmdValid;
  wire        saveStateStreamDdrCmdReady;
  wire        saveStateStreamDdrCmdWrite;
  wire [31:0] saveStateStreamDdrCmdAddr;
  wire [63:0] saveStateStreamDdrCmdData;
  wire [7:0]  saveStateStreamDdrCmdBe;
  wire [7:0]  saveStateStreamDdrCmdBurst;
  wire        saveStateStreamDdrRspValid;
  wire [63:0] saveStateStreamDdrRspData;

  wire        saveStateGameDdrRd;
  wire        saveStateGameDdrWr;
  wire [31:0] saveStateGameDdrAddr;
  wire [7:0]  saveStateGameDdrMask;
  wire [63:0] saveStateGameDdrDin;
  wire [7:0]  saveStateGameDdrBurst;
  wire [63:0] saveStateGameDdrDout;
  wire        saveStateGameDdrWaitN;
  wire        saveStateGameDdrValid;
  wire        saveStateGameDdrWriteCommit;
  wire [31:0] saveStateGameDdrWriteCommitAddr;

  wire        saveStateRawStreamBusy;
  wire        saveStateRawStreamDone;
  wire        saveStateRawStreamSuccess;
  wire        saveStateRawStreamFormatError;
  wire        saveStateRawStreamPass1Complete;
  wire        saveStateRawStreamMutated;
  wire        saveStateRawStreamFatal;
  wire [7:0]  saveStateRawStreamError;
  wire [1:0]  saveStateRawStreamRestorePass;
  wire        saveStateRawStreamRestoreBegin;
  wire        saveStateRawStreamRestoreCommit;

  wire        saveStateControllerQuiesceRequest;
  wire        saveStateControllerQuiesceRestore;
  wire        saveStateControllerQuiesceAbort;
  wire        saveStateControllerQuiesceResume;
  wire        saveStateControllerOperationFatal;
  wire        saveStateControllerStreamAbort;
  wire        saveStateControllerStreamSaveStart;
  wire        saveStateControllerStreamRestoreStart;
  wire        saveStateControllerRestoreBegin;
  wire        saveStateControllerRestoreCommit;
  wire        saveStateControllerReconstructionStart;
  wire        saveStateControllerReconstructionActive;
  wire        saveStateControllerActive;
  wire        saveStateControllerRestore;
  wire        saveStateControllerDone;
  wire        saveStateControllerSuccess;
  wire        saveStateControllerAborted;
  wire        saveStateControllerAccepted;
  wire        saveStateControllerRejected;
  wire        saveStateControllerTimeout;
  wire        saveStateControllerFatal;
  wire [3:0]  saveStateControllerDebug;
  wire [7:0]  saveStateControllerLastError;
  wire [7:0]  saveStateControllerLastStreamError;

  wire        saveStateQuiesceBusy;
  wire        saveStateQuiesceFreeze;
  wire        saveStateQuiesceBlockNewWork;
  wire        saveStateQuiesceMainStopRequest;
  wire        saveStateQuiesceSoundStopRequest;
  wire        saveStateQuiesced;
  wire        saveStateQuiescedPulse;
  wire        saveStateQuiesceAccepted;
  wire        saveStateQuiesceRejected;
  wire        saveStateQuiesceAbortPulse;
  wire        saveStateQuiesceAbortComplete;
  wire        saveStateQuiesceTimeout;
  wire        saveStateQuiesceRestoreActive;
  wire        saveStateQuiesceFatal;
  wire        saveStateQuiesceAbortActive;
  wire        saveStateSoundRomLaunchBlock;
  wire [3:0]  saveStateQuiescePhase;
  wire [SS_IDLE_ACK_COUNT-1:0] saveStateIdleAck;

  wire        saveStateCoordinatorMainStopped;
  wire        saveStateCoordinatorSoundStopped;
  wire        saveStateCoordinatorMainAbortAck;
  wire        saveStateCoordinatorSoundAbortAck;
  wire        saveStateCoordinatorStreamSaveStart;
  wire        saveStateCoordinatorStreamRestoreStart;
  wire        saveStateCoordinatorStreamPass2Enable;
  wire        saveStateCoordinatorStreamAbort;
  wire        saveStateCoordinatorControllerStreamBusy;
  wire        saveStateCoordinatorControllerStreamDone;
  wire        saveStateCoordinatorControllerStreamSuccess;
  wire        saveStateCoordinatorControllerStreamFormatError;
  wire        saveStateCoordinatorControllerStreamPass1Complete;
  wire        saveStateCoordinatorControllerStreamMutated;
  wire        saveStateCoordinatorControllerStreamFatal;
  wire [7:0]  saveStateCoordinatorControllerStreamError;
  wire [1:0]  saveStateCoordinatorControllerRestorePass;
  wire        saveStateCoordinatorControllerRestoreBegin;
  wire        saveStateCoordinatorControllerRestoreCommit;
  wire        saveStateCoordinatorSystemCommit;
  wire        saveStateCoordinatorMainRelease;
  wire        saveStateCoordinatorSoundRelease;
  wire        saveStateCoordinatorReleaseRestore;
  wire        saveStateCoordinatorReleaseComplete;
  wire        saveStateCoordinatorReleasePending;
  wire        saveStateCoordinatorMainCommandValid;
  wire [15:0] saveStateCoordinatorMainCommand;
  wire        saveStateCoordinatorSoundCommandValid;
  wire [15:0] saveStateCoordinatorSoundCommand;
  wire        saveStateCoordinatorMainCommandBusy;
  wire        saveStateCoordinatorSoundCommandBusy;
  wire        saveStateCoordinatorMainCommandChannelFault;
  wire        saveStateCoordinatorSoundCommandChannelFault;
  wire        saveStateCoordinatorTerminalFault;
  wire [7:0]  saveStateCoordinatorLastFault;
  wire        saveStateCoordinatorActive;
  wire        saveStateCoordinatorRestore;
  wire        saveStateCoordinatorMutationAuthorized;
  wire [4:0]  saveStateCoordinatorDebug;
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
  wire        saveStateCoordinatorResultLatchedDebug;
  wire        saveStateCoordinatorResultSuccessDebug;
  wire        saveStateCoordinatorResultCommitDebug;
  wire [1:0]  saveStateCoordinatorResultPassDebug;
  wire        saveStateCoordinatorRestoreDoneGoodDebug;
  wire        saveStateCoordinatorPass2CaptureDebug;
  wire        saveStateCoordinatorAbortRequestedDebug;
  wire [39:0] saveStateCoordinatorFirstProtocolFaultDebug;
  wire [7:0]  saveStateRawOwnerFailureCountDebug;
  wire [5:0]  saveStateRawOwnerFailureStateDebug;
  wire        saveStateRawOwnerFailureRestoreDebug;
  wire [1:0]  saveStateRawOwnerFailurePassDebug;
  wire [2:0]  saveStateRawOwnerFailureCommandDebug;
  wire [7:0]  saveStateRawOwnerFailureSelectDebug;
  wire [31:0] saveStateRawOwnerFailureAddrDebug;
  wire [3:0]  saveStateRawOwnerFailureReasonDebug;
  wire [15:0] saveStateRawOwnerFailureDataLowDebug;
`endif

  wire        saveStateSystemRouterNoRoute;
  wire        saveStateSystemRouterMultipleRoute;
  wire        saveStateSystemRouterWrongResponse;
  wire        saveStateSystemRouterTimeout;
  wire        saveStateSystemRouterFault;
  wire        saveStateSystemRouterIdle;
  wire        saveStateMainRouterNoRoute;
  wire        saveStateMainRouterMultipleRoute;
  wire        saveStateMainRouterWrongResponse;
  wire        saveStateMainRouterTimeout;
  wire        saveStateMainRouterFault;
  wire        saveStateMainRouterIdle;

  wire        saveStateMainCdcReady;
  wire        saveStateMainCdcBusy;
  wire        saveStateMainCdcDraining;
  wire        saveStateMainCdcTimeout;
  wire        saveStateMainCdcAbandoned;
  wire        saveStateMainCdcAborted;
  wire        saveStateMainCdcLocalReject;
  wire        saveStateMainCdcDestinationReset;
  wire        saveStateMainCdcSourceFault;
  wire        saveStateMainCdcDestinationBusy;
  wire        saveStateMainCdcDestinationDraining;
  wire        saveStateMainCdcForcedDrop;
  wire        saveStateMainCdcLateResponse;
  wire        saveStateMainCdcDestinationFault;
  wire        saveStateSoundCdcReady;
  wire        saveStateSoundCdcBusy;
  wire        saveStateSoundCdcDraining;
  wire        saveStateSoundCdcTimeout;
  wire        saveStateSoundCdcAbandoned;
  wire        saveStateSoundCdcAborted;
  wire        saveStateSoundCdcLocalReject;
  wire        saveStateSoundCdcDestinationReset;
  wire        saveStateSoundCdcSourceFault;
  wire        saveStateSoundCdcDestinationBusy;
  wire        saveStateSoundCdcDestinationDraining;
  wire        saveStateSoundCdcForcedDrop;
  wire        saveStateSoundCdcLateResponse;
  wire        saveStateSoundCdcDestinationFault;

  wire        saveStateMainReleaseRequestCpu;
  wire        saveStateMainReleaseRestoreCpu;
  wire        saveStateMainReleaseCompleteSystem;
  wire        saveStateMainReleaseReady;
  wire        saveStateMainReleaseBusy;
  wire        saveStateMainReleaseSourceTimeout;
  wire        saveStateMainReleaseDestinationTimeout;
  wire        saveStateMainReleaseSourceProtocolFault;
  wire        saveStateMainReleaseDestinationProtocolFault;
  wire        saveStateMainReleaseSourceFault;
  wire        saveStateMainReleaseDestinationFault;
  wire [2:0]  saveStateMainReleaseSourceStateDebug;
  wire        saveStateMainReleaseSourceRestoreHoldDebug;
  wire        saveStateMainReleaseSourceCommandValidDebug;
  wire        saveStateMainReleaseSourceCommandAcceptedDebug;
  wire        saveStateMainReleaseSourceRestoreKnownDebug;
  wire [2:0]  saveStateMainReleaseDestinationStateDebug;
  wire        saveStateMainReleaseDestinationRestoreHoldDebug;
  wire        saveStateMainReleaseDestinationCommandValidDebug;
  wire        saveStateMainReleaseDestinationCommandDebug;
  wire        saveStateSoundReleaseRequestCpu;
  wire        saveStateSoundReleaseRestoreCpu;
  wire        saveStateSoundReleaseCompleteSystem;
  wire        saveStateSoundReleaseReady;
  wire        saveStateSoundReleaseBusy;
  wire        saveStateSoundReleaseSourceTimeout;
  wire        saveStateSoundReleaseDestinationTimeout;
  wire        saveStateSoundReleaseSourceProtocolFault;
  wire        saveStateSoundReleaseDestinationProtocolFault;
  wire        saveStateSoundReleaseSourceFault;
  wire        saveStateSoundReleaseDestinationFault;
  wire [2:0]  saveStateSoundReleaseSourceStateDebug;
  wire        saveStateSoundReleaseSourceRestoreHoldDebug;
  wire        saveStateSoundReleaseSourceCommandValidDebug;
  wire        saveStateSoundReleaseSourceCommandAcceptedDebug;
  wire        saveStateSoundReleaseSourceRestoreKnownDebug;
  wire [2:0]  saveStateSoundReleaseDestinationStateDebug;
  wire        saveStateSoundReleaseDestinationRestoreHoldDebug;
  wire        saveStateSoundReleaseDestinationCommandValidDebug;
  wire        saveStateSoundReleaseDestinationCommandDebug;

  wire        saveStateMetadataValidationComplete;
  wire        saveStateMetadataValidationValid;
  wire        saveStateMetadataCommit;
  wire        saveStateMetadataCommitted;
  wire        saveStateSystemRestoreApply;
  wire        saveStateSystemRestoreCdcLaunch;
  wire        saveStateSystemRestoreVideoVblankPipe0;
  wire        saveStateSystemRestoreVideoVblankPipe1;
  wire        saveStateSystemRestoreVideoVblankPipe2;
  wire        saveStateSystemRestoreSpriteSwapPrimed;
  wire        saveStateSystemRestoreAirStartPending;
  wire        saveStateSystemRestoreAirFrameInFlight;
  wire [1:0]  saveStateSystemRestoreMetBankActive;
  wire [1:0]  saveStateSystemRestoreMetBankDelay;
  wire [3:0]  saveStateSystemRestoreGameIndex;
  wire        saveStateSystemRestoreGameIndexLatched;
  wire        saveStateSystemRestoreIoctlDownload;
  wire [15:0] saveStateSystemRestoreNvramIoctlDin;
  wire        saveStateSystemRestoreMemSysIoctlDownload;
  wire        saveStateSystemRestoreVideoSysIoctlDownload;
  wire [3:0]  saveStateSystemRestoreGameIndexCpu;
  wire        saveStateSystemOwnerValidationComplete;
  wire        saveStateSystemOwnerValidationValid;
  wire        saveStateSystemOwnerWriteComplete;
  wire        saveStateSystemOwnerWriteValid;
  wire        saveStateSystemOwnerCommitted;
  wire        saveStateSystemOwnerTerminalFault;
  wire        saveStateSystemOwnerIdle;

  wire        saveStateSystemCpuReady;
  wire        saveStateSystemCpuAccepted;
  wire        saveStateSystemCpuComplete;
  wire        saveStateSystemCpuBusy;
  wire        saveStateSystemCpuSourceFault;
  wire        saveStateSystemCpuRestoreLoad;
  wire [3:0]  saveStateSystemCpuRestoreGameIndex;
  wire        saveStateSystemCpuDestinationBusy;
  wire        saveStateSystemCpuDestinationFault;
  reg         saveStateSystemCpuRestoreApplied;
  reg         saveStateSystemCommitPending;
  reg         saveStateSystemCommitDone;

  wire [127:0] saveStateVideoLiveState;
  wire         saveStateVideoBlockedWrite;
  wire         saveStateVideoRestoreApplied;
  wire [15:0]  saveStateDipLiveState;
  wire         saveStateDipBlockedWrite;
  wire         saveStateDipRestoreApplied;
  wire         saveStateVideoDipSourceReady;
  wire         saveStateVideoDipSourceComplete;
  wire         saveStateVideoDipSourceBusy;
  wire         saveStateVideoDipSourceFault;
  wire         saveStateVideoDipRestoreLoad;
  wire [127:0] saveStateVideoDipRestoreVideo;
  wire [15:0]  saveStateVideoDipRestoreDip;
  wire         saveStateVideoDipDestinationBusy;
  wire         saveStateVideoDipDestinationFault;

  wire        saveStateNvramSessionStart;
  reg         saveStateNvramSessionActive;
  wire        saveStateNvramAbort;
  wire        saveStateNvramOwnerTakeover;
  wire        saveStateNvramOwnerRd;
  wire        saveStateNvramOwnerWr;
  wire [6:0]  saveStateNvramOwnerAddr;
  wire [7:0]  saveStateNvramOwnerDin;
  wire [7:0]  saveStateNvramOwnerDout;
  wire        saveStateNvramOwnerWaitN;
  wire        saveStateNvramOwnerValid;
  wire        saveStateNvramOwnerBusy;
  wire        saveStateNvramOwnerDraining;
  wire        saveStateNvramOwnerPoisoned;
  wire        saveStateNvramOwnerTimeout;
  wire        saveStateNvramOwnerFatal;
  wire [1:0]  saveStateNvramOwnerFatalReason;
  wire        saveStateNvramPrepared;
  wire        saveStateNvramBusy;
  wire        saveStateNvramFlushDone;
  wire        saveStateNvramTimeout;
  wire        saveStateNvramFatal;
  wire [2:0]  saveStateNvramFatalReason;
  wire        saveStateRegisterWriteFaultEvent;
  reg         saveStateRegisterWriteFault;

  wire        saveStateGpuIdle;
  wire        saveStateGpuReconstructionReady;
  wire        saveStateGpuReconstructionComplete;
  wire        saveStateSpriteFrameBufferIdle;
  wire        saveStateSpriteFrameBufferWriteIdle;
  wire        saveStateSpriteFrameBufferSwapAccepted;
  wire        saveStateSpriteReconstructionTargetReady;
`ifdef CAVEBANPRESTO_MET_SPRITE_PAGE_HW_DIAGNOSTIC
  wire [2:0]   metmqstrSpritePageDiagSource;
  wire [127:0] metmqstrSpritePageDiagProbe;
  wire         metmqstrSpritePageDiagMixerSpriteWins;
  wire         metmqstrSpritePageDiagOverlayValid;
  wire [23:0]  metmqstrSpritePageDiagOverlayRgb;
`endif
  wire        saveStateSystemFrameBufferIdle;
  wire        saveStateSystemFrameBufferDdrCommit;
  wire        saveStateSystemFrameBufferPublicationComplete;
  wire [31:0] saveStateSystemFrameBufferPublicationDebug;
  wire [2:0]  saveStateTileRomIdle;
  wire        saveStateProgramRomFreezerIdle;
  wire        saveStateEepromFreezerIdle;
  wire        saveStateSdramIdle;
  wire        saveStateRenderIdleSystem;
  wire        saveStateRenderIdleCpu;
  wire        saveStateProgramRomBlockNewWork;
  wire        saveStateEepromBlockNewWork;
  wire        saveStateGameDdrBlockNewWork;
  reg         saveStateRenderIdleSource;

  wire        saveStateMainCommandComplete;
  wire [7:0]  saveStateMainCommandResponse;
  wire        saveStateMainCommandTerminalFault;
  wire        saveStateMainStopped;
  wire        saveStateMainAbortAck;
  wire        saveStateMainReleaseCompleteCpu;
  wire        saveStateMainCpuCaptured;
  wire        saveStateMainCpuCommitted;
  wire        saveStateMainCpuAbortAck;
  wire        saveStateMainCpuTerminalFault;
  wire        saveStateMainControlIdle;
  wire        saveStateMainControlCommitted;
  wire        saveStateMainControlTerminalFault;
  wire        saveStateMainRamIdle;
  wire        saveStateMainRamTerminalFault;
  wire        saveStateMainRamTakeover;
  wire        saveStateMainRamBlocked;
  wire        saveStateMainRegisterIdle;
  wire        saveStateMainRegisterCommitted;
  wire        saveStateMainRegisterTerminalFault;
  wire        saveStateMainRegisterRestoreLoad;
  wire [127:0] saveStateMainVideoRestoreState;
  wire [15:0]  saveStateMainDipRestoreState;
  wire        saveStateMainEepromIdle;
  wire        saveStateMainEepromCommitted;
  wire        saveStateMainEepromTerminalFault;
`ifdef CAVEBANPRESTO_SS_RELEASE_SLIM_HW_DIAGNOSTIC
  wire        saveStateMainCaptureAdmittedSeenCpu;
  wire        saveStateMainCaptureAdmittedSeenSystem;
`endif
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
  wire        saveStateMainReleaseEligibleCpu;
  wire [3:0]  saveStateMainReleaseOwnerIdleCpu;
  wire [1:0]  saveStateMainReleaseDetailCpu;
  wire [4:0]  saveStateMainReleaseStateCpu;
  wire [31:0] saveStateMainReleaseFaultDebugCpu;
  wire [14:0] saveStateSoundReleaseDebugCpu;
  wire  [7:0] saveStateSoundOwnerFaultDebugCpu;
  reg   [3:0] saveStateSoundLastCommandDebug;
  reg   [7:0] saveStateSoundLastSelectDebug;
  reg  [31:0] saveStateSoundLastAddrDebug;
  reg  [15:0] saveStateSoundLastDataLowDebug;
  wire [18:0] saveStateSoundFaultStatusDebug;
  wire [86:0] saveStateSoundFaultContextDebug;
  wire [86:0] saveStateCoordinatorFaultContextDebug;
  wire [86:0] saveStateVideoPublicationContextDebug;
  wire [86:0] saveStatePass2FaultContextDebug;
  wire        saveStatePass2FaultContextValidDebug;
`endif
  wire        saveStateSoundCommandComplete;
  wire [7:0]  saveStateSoundCommandResponse;
  wire        saveStateSoundCommandTerminalFault;

  reg         saveStateMainCpuCapturedSource;
  reg         saveStateMainControlIdleSource;
  reg         saveStateMainRamIdleSource;
  reg         saveStateMainRegisterIdleSource;
  reg         saveStateMainEepromIdleSource;
  reg         saveStateMainRouterIdleSource;
  reg         saveStateSoundStoppedSource;
  reg         saveStateSoundIdleSource;
  reg         saveStateVideoDipReadySource;
  reg         saveStateMainCommandBusySource;
  reg         saveStateSoundCommandBusySource;
  wire        saveStateMainCapturedSystem;
  wire        saveStateSoundStoppedSystem;
  wire        saveStateMainControlIdleSystem;
  wire        saveStateMainRamIdleSystem;
  wire        saveStateMainRegisterIdleSystem;
  wire        saveStateMainEepromIdleSystem;
  wire        saveStateMainRouterIdleSystem;
  wire        saveStateSoundIdleSystem;
  wire        saveStateVideoDipReadySystem;
  wire        saveStateMainCommandBusySystem;
  wire        saveStateSoundCommandBusySystem;

  reg         saveStateSoundRomExternalIdleSource;
  reg         saveStateSoundRomDependenciesSource;
  reg         saveStateSoundRomFaultSource;
  reg         saveStateSoundFatalSource;
  wire        saveStateSoundRomExternalIdleCpu;
  wire        saveStateSoundRomDependenciesCpu;
  wire        saveStateSoundRomFaultCpu;
  wire        saveStateSoundFatalCpu;
  wire        saveStateInfrastructureFault;
  wire        saveStateSystemCommitFault;
  wire        saveStateSoundRomEarlyLaunchBlock;
  wire        saveStateSoundRomSlowProfile;
  wire        saveStateSoundRomAbortPrepareFire;
  wire        saveStateSoundRomPrepare;
  wire        saveStateSoundRomPrefetchRequired;
  reg         saveStateSoundRomAbortPrepareIssued;

  reg         saveStateRomLoadPending;
  reg         saveStateMemSysProgDone;

  wire         systemFrameBufferForceBlank;
  wire [63:0]  _gpu_io_layerCtrl_0_tileRom_dout;
  wire [63:0]  _gpu_io_layerCtrl_1_tileRom_dout;
  wire [63:0]  _gpu_io_layerCtrl_2_tileRom_dout;
  wire         _gpu_io_spriteCtrl_start;
  wire         _gpu_io_spriteCtrl_zoom;
  wire [1:0]   _gpu_io_gameConfig_layer_1_paletteBank;
  wire [15:0]  _gpu_io_spriteLineBuffer_dout;
  wire         _gpu_io_spriteFrameBuffer_wait_n;
  wire         _gpu_io_layerCtrl_0_tileRom_rd;
  wire [31:0]  _gpu_io_layerCtrl_0_tileRom_addr;
  wire         _gpu_io_layerCtrl_1_tileRom_rd;
  wire [31:0]  _gpu_io_layerCtrl_1_tileRom_addr;
  wire         _gpu_io_layerCtrl_2_tileRom_rd;
  wire [31:0]  _gpu_io_layerCtrl_2_tileRom_addr;
  wire [8:0]   _gpu_io_spriteLineBuffer_addr;
  wire         _gpu_io_spriteFrameBuffer_wr;
  wire [16:0]  _gpu_io_spriteFrameBuffer_addr;
  wire [15:0]  _gpu_io_spriteFrameBuffer_din;
  wire         _gpu_io_systemFrameBuffer_wr;
  wire [16:0]  _gpu_io_systemFrameBuffer_addr;
  wire [31:0]  _gpu_io_systemFrameBuffer_din;
  wire [7:0]   _sound_io_rom_0_dout;
  wire         _sound_io_rom_0_wait_n;
  wire         _sound_io_rom_0_valid;
  wire [7:0]   _sound_io_rom_1_dout;
  wire         _sound_io_rom_1_valid;
  wire [7:0]   _sound_io_rom_2_dout;
  wire         _sound_io_rom_2_valid;
  wire         _sound_io_rom_0_rd;
  wire         _sound_io_rom_1_rd;
  wire         _sound_io_rom_2_rd;
  wire [24:0]  _sound_io_rom_0_addr;
  wire [24:0]  _sound_io_rom_1_addr;
  wire [24:0]  _sound_io_rom_2_addr;
  wire         _sound_io_ss_stopped;
  wire         _sound_io_ss_abort_ack;
  wire         _sound_io_ss_restore_launch_done;
  wire         _sound_io_ss_idle;
  wire         _sound_io_ss_release_pending;
  wire         _sound_io_ss_release_complete;
  wire         _sound_io_ss_terminal_fault;
  cavebanpresto_ssbus_if soundSaveStateBus();
  cavebanpresto_ssbus_if soundRomSaveStateBus();
  wire [1:0]   soundRomTargetWaitUnused;
  wire         soundRomSaveStateCanonicalIdle;
  wire         soundRomSaveStateExternalIdle;
  wire         soundRomSaveStateDependenciesReady;
  wire         soundRomSaveStateReleasePathReady;
  wire         soundRomSaveStateRearmed;
  wire         soundRomSaveStateTerminalFault;
  wire [2:0]   soundRomSaveStateLaneSystemIdle;
  wire [2:0]   soundRomSaveStateLaneTargetEmpty;
  wire [11:0]  _main_io_gpuMem_layer_0_vram8x8_addr;
  wire [9:0]   _main_io_gpuMem_layer_0_vram16x16_addr;
  wire [8:0]   _main_io_gpuMem_layer_0_lineRam_addr;
  wire [11:0]  _main_io_gpuMem_layer_1_vram8x8_addr;
  wire [9:0]   _main_io_gpuMem_layer_1_vram16x16_addr;
  wire [8:0]   _main_io_gpuMem_layer_1_lineRam_addr;
  wire [11:0]  _main_io_gpuMem_layer_2_vram8x8_addr;
  wire [9:0]   _main_io_gpuMem_layer_2_vram16x16_addr;
  wire [8:0]   _main_io_gpuMem_layer_2_lineRam_addr;
  wire         _main_io_gpuMem_sprite_vram_rd;
  wire [11:0]  _main_io_gpuMem_sprite_vram_addr;
  wire [14:0]  _main_io_gpuMem_paletteRam_addr;
`ifdef CAVE_ENABLE_DEBUG_OVERLAY
  wire [63:0]  _main_io_debug_pipeline;
  wire [63:0]  _main_io_debug_cpu;
  wire [63:0]  _main_io_debug_writes;
  wire [63:0]  _main_io_debug_data;
  wire [63:0]  _main_io_debug_live;
  wire [63:0]  _main_io_debug_palette;
  wire [63:0]  _sound_io_debug;
  wire [63:0]  _gpu_io_debug_video;
  wire [63:0]  _gpu_io_debug_readout;
  wire [23:0]  _gpu_io_debug_source_rgb;
`endif
  wire [23:0]  _gpu_rgb;
  wire [15:0]  _main_io_soundCtrl_oki_0_dout;
  wire [15:0]  _main_io_soundCtrl_oki_1_dout;
  wire [15:0]  _main_io_soundCtrl_ymz_dout;
  wire [15:0]  _main_io_soundCtrl_reply;
  wire         _main_io_soundCtrl_reply_empty;
  wire         _main_io_soundCtrl_irq;
  wire [15:0]  _main_io_progRom_dout;
  wire         _main_io_progRom_valid;
  wire [15:0]  _main_io_eeprom_dout;
  wire         _main_io_eeprom_wait_n;
  wire         _main_io_eeprom_valid;
  wire [15:0]  _main_io_hs_nvram_din;
  wire         _main_io_hs_nvram_wait_n;
  wire         _main_io_hs_dirty;
  wire         _main_io_hs_active;
  wire         _main_io_gpuMem_layer_0_regs_tileSize;
  wire         _main_io_gpuMem_layer_0_regs_enable;
  wire         _main_io_gpuMem_layer_0_regs_flipX;
  wire         _main_io_gpuMem_layer_0_regs_flipY;
  wire         _main_io_gpuMem_layer_0_regs_rowScrollEnable;
  wire         _main_io_gpuMem_layer_0_regs_rowSelectEnable;
  wire [1:0]   _main_io_gpuMem_layer_0_regs_priority;
  wire [8:0]   _main_io_gpuMem_layer_0_regs_scroll_x;
  wire [8:0]   _main_io_gpuMem_layer_0_regs_scroll_y;
  wire [31:0]  _main_io_gpuMem_layer_0_vram8x8_dout;
  wire [31:0]  _main_io_gpuMem_layer_0_vram16x16_dout;
  wire [31:0]  _main_io_gpuMem_layer_0_lineRam_dout;
  wire         _main_io_gpuMem_layer_1_regs_tileSize;
  wire         _main_io_gpuMem_layer_1_regs_enable;
  wire         _main_io_gpuMem_layer_1_regs_flipX;
  wire         _main_io_gpuMem_layer_1_regs_flipY;
  wire         _main_io_gpuMem_layer_1_regs_rowScrollEnable;
  wire         _main_io_gpuMem_layer_1_regs_rowSelectEnable;
  wire [1:0]   _main_io_gpuMem_layer_1_regs_priority;
  wire [8:0]   _main_io_gpuMem_layer_1_regs_scroll_x;
  wire [8:0]   _main_io_gpuMem_layer_1_regs_scroll_y;
  wire [31:0]  _main_io_gpuMem_layer_1_vram8x8_dout;
  wire [31:0]  _main_io_gpuMem_layer_1_vram16x16_dout;
  wire [31:0]  _main_io_gpuMem_layer_1_lineRam_dout;
  wire         _main_io_gpuMem_layer_2_regs_tileSize;
  wire         _main_io_gpuMem_layer_2_regs_enable;
  wire         _main_io_gpuMem_layer_2_regs_flipX;
  wire         _main_io_gpuMem_layer_2_regs_flipY;
  wire         _main_io_gpuMem_layer_2_regs_rowScrollEnable;
  wire         _main_io_gpuMem_layer_2_regs_rowSelectEnable;
  wire [1:0]   _main_io_gpuMem_layer_2_regs_priority;
  wire [8:0]   _main_io_gpuMem_layer_2_regs_scroll_x;
  wire [8:0]   _main_io_gpuMem_layer_2_regs_scroll_y;
  wire [31:0]  _main_io_gpuMem_layer_2_vram8x8_dout;
  wire [31:0]  _main_io_gpuMem_layer_2_vram16x16_dout;
  wire [31:0]  _main_io_gpuMem_layer_2_lineRam_dout;
  wire [8:0]   _main_io_gpuMem_sprite_regs_offset_x;
  wire [8:0]   _main_io_gpuMem_sprite_regs_offset_y;
  wire [1:0]   _main_io_gpuMem_sprite_regs_bank;
  wire         _main_io_gpuMem_sprite_regs_fixed;
  wire         _main_io_gpuMem_sprite_regs_hFlip;
  wire [127:0] _main_io_gpuMem_sprite_vram_dout;
  wire [15:0]  _main_io_gpuMem_paletteRam_dout;
  wire         _main_io_soundCtrl_oki_0_wr;
  wire [15:0]  _main_io_soundCtrl_oki_0_din;
  wire         _main_io_soundCtrl_oki_1_wr;
  wire [15:0]  _main_io_soundCtrl_oki_1_din;
  wire         _main_io_soundCtrl_nmk_wr;
  wire [22:0]  _main_io_soundCtrl_nmk_addr;
  wire [15:0]  _main_io_soundCtrl_nmk_din;
  wire         _main_io_soundCtrl_ymz_rd;
  wire         _main_io_soundCtrl_ymz_wr;
  wire [22:0]  _main_io_soundCtrl_ymz_addr;
  wire [15:0]  _main_io_soundCtrl_ymz_din;
  wire         _main_io_soundCtrl_req;
  wire [15:0]  _main_io_soundCtrl_data;
  wire         _main_io_soundCtrl_reply_rd;
  wire         _main_io_progRom_rd;
  wire [21:0]  _main_io_progRom_addr;
  wire         _main_io_eeprom_rd;
  wire         _main_io_eeprom_wr;
  wire [6:0]   _main_io_eeprom_addr;
  wire [15:0]  _main_io_eeprom_din;
  wire         _main_io_spriteFrameBufferSwap;
  wire         _gpu_io_spriteCtrl_frameReady;
  wire         _videoSys_io_prog_video_wr;
  wire         _videoSys_io_prog_done;
  wire         _videoSys_io_video_clockEnable;
  wire         _videoSys_io_video_displayEnable;
  wire [8:0]   _videoSys_io_video_pos_x;
  wire [8:0]   _videoSys_io_video_pos_y;
  wire         _videoSys_io_video_hBlank;
  wire         _videoSys_io_video_vBlank;
  wire [8:0]   _videoSys_io_video_regs_size_x;
  wire [8:0]   _videoSys_io_video_regs_size_y;
  wire         _memSys_io_prog_rom_wr;
  wire         _memSys_io_prog_nvram_rd;
  wire         _memSys_io_prog_nvram_wr;
  wire         _memSys_io_prog_done;
  wire         _memSys_io_progRom_rd;
  wire [21:0]  _memSys_io_progRom_addr;
  wire         _memSys_io_eeprom_rd;
  wire         _memSys_io_eeprom_wr;
  wire [6:0]   _memSys_io_eeprom_addr;
  wire [15:0]  _memSys_io_eeprom_din;
  wire         _memSys_io_soundRom_0_rd;
  wire [24:0]  _memSys_io_soundRom_0_addr;
  wire         _memSys_io_soundRom_1_rd;
  wire [24:0]  _memSys_io_soundRom_1_addr;
  wire         _memSys_io_soundRom_2_rd;
  wire [24:0]  _memSys_io_soundRom_2_addr;
  wire         _memSys_io_layerTileRom_0_rd;
  wire [31:0]  _memSys_io_layerTileRom_0_addr;
  wire         _memSys_io_layerTileRom_1_rd;
  wire [31:0]  _memSys_io_layerTileRom_1_addr;
  wire         _memSys_io_layerTileRom_2_rd;
  wire [31:0]  _memSys_io_layerTileRom_2_addr;
  wire         _memSys_io_spriteTileRom_rd;
  wire [31:0]  _memSys_io_spriteTileRom_addr;
  wire [7:0]   _memSys_io_spriteTileRom_burstLength;
  wire         _memSys_io_spriteFrameBuffer_rd;
  wire         _memSys_io_spriteFrameBuffer_wr;
  wire [31:0]  _memSys_io_spriteFrameBuffer_addr;
  wire [7:0]   _memSys_io_spriteFrameBuffer_mask;
  wire [63:0]  _memSys_io_spriteFrameBuffer_din;
  wire [7:0]   _memSys_io_spriteFrameBuffer_burstLength;
  wire         _memSys_io_systemFrameBuffer_wr;
  wire [31:0]  _memSys_io_systemFrameBuffer_addr;
  wire [7:0]   _memSys_io_systemFrameBuffer_mask;
  wire [63:0]  _memSys_io_systemFrameBuffer_din;
  wire         _memSys_io_prog_rom_wait_n;
  wire [15:0]  _memSys_io_prog_nvram_dout;
  wire         _memSys_io_prog_nvram_wait_n;
  wire         _memSys_io_prog_nvram_valid;
  wire [15:0]  _memSys_io_progRom_dout;
  wire         _memSys_io_progRom_wait_n;
  wire         _memSys_io_progRom_valid;
  wire [15:0]  _memSys_io_eeprom_dout;
  wire         _memSys_io_eeprom_wait_n;
  wire         _memSys_io_eeprom_valid;
  wire [7:0]   _memSys_io_soundRom_0_dout;
  wire         _memSys_io_soundRom_0_wait_n;
  wire         _memSys_io_soundRom_0_valid;
  wire [7:0]   _memSys_io_soundRom_1_dout;
  wire         _memSys_io_soundRom_1_wait_n;
  wire         _memSys_io_soundRom_1_valid;
  wire [7:0]   _memSys_io_soundRom_2_dout;
  wire         _memSys_io_soundRom_2_wait_n;
  wire         _memSys_io_soundRom_2_valid;
  wire [63:0]  _memSys_io_layerTileRom_0_dout;
  wire         _memSys_io_layerTileRom_0_wait_n;
  wire         _memSys_io_layerTileRom_0_valid;
  wire [63:0]  _memSys_io_layerTileRom_1_dout;
  wire         _memSys_io_layerTileRom_1_wait_n;
  wire         _memSys_io_layerTileRom_1_valid;
  wire [63:0]  _memSys_io_layerTileRom_2_dout;
  wire         _memSys_io_layerTileRom_2_wait_n;
  wire         _memSys_io_layerTileRom_2_valid;
  wire [63:0]  _memSys_io_spriteTileRom_dout;
  wire         _memSys_io_spriteTileRom_wait_n;
  wire         _memSys_io_spriteTileRom_valid;
  wire         _memSys_io_spriteTileRom_burstDone;
  wire [63:0]  _memSys_io_spriteFrameBuffer_dout;
  wire         _memSys_io_spriteFrameBuffer_wait_n;
  wire         _memSys_io_spriteFrameBuffer_valid;
  wire         _memSys_io_spriteFrameBuffer_burstDone;
  wire         _memSys_io_systemFrameBuffer_wait_n;
  wire         _memSys_io_ready;
  wire         _sdram_1_io_mem_rd;
  wire         _sdram_1_io_mem_wr;
  wire [24:0]  _sdram_1_io_mem_addr;
  wire [15:0]  _sdram_1_io_mem_din;
  wire [15:0]  _sdram_1_io_mem_dout;
  wire         _sdram_1_io_mem_wait_n;
  wire         _sdram_1_io_mem_valid;
  wire         _sdram_1_io_mem_burstDone;
  wire         _ddr_1_io_mem_rd;
  wire         _ddr_1_io_mem_wr;
  wire [31:0]  _ddr_1_io_mem_addr;
  wire [7:0]   _ddr_1_io_mem_mask;
  wire [63:0]  _ddr_1_io_mem_din;
  wire [7:0]   _ddr_1_io_mem_burstLength;
  wire [63:0]  _ddr_1_io_mem_dout;
  wire         _ddr_1_io_mem_wait_n;
  wire         _ddr_1_io_mem_valid;
  wire         _ddr_1_io_mem_burstDone;
  wire         _ddr_1_io_idle;
  wire         dipsRegsWr;
  wire [1:0]   dipsRegsAddr;
  wire [15:0]  _dipsRegs_io_regs_0;
  reg          videoVBlankPipe0;
  reg          videoVBlankPipe1;
  reg          videoVBlankPipe2;
  reg          videoVBlankObserverPipe0;
  reg          videoVBlankObserverPipe1;
  reg          spriteFrameBufferSwapPrimed;
  reg          airGalletSpriteStartPending;
  reg          airGalletSpriteFrameInFlight;
  reg          airGalletReconstructionDrainSeen;
  reg          airGalletReconstructionSpritePublished;
  wire [1:0]   metmqstrSpriteBankActive;
  wire [1:0]   metmqstrSpriteBankDelay;
  wire         metmqstrSpriteProcessorStart;
  reg  [3:0]   gameIndexReg;
  reg          gameIndexReg_latched;
  reg          gameIndexCpuLoadToggle = 1'b0;
  (* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
  reg          gameIndexCpuToggleSync0 = 1'b0;
  (* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
  reg          gameIndexCpuToggleSync1 = 1'b0;
  reg          gameIndexCpuToggleSeen = 1'b0;
  reg  [3:0]   gameIndexCpuReg = 4'h0;
  reg          ioctlDownloadReg;
  wire [8:0]   gameConfig_granularity;
  wire [31:0]  gameConfig_eepromOffset;
  wire [1:0]   gameConfig_sound_0_device;
  wire [1:0]   gameConfigCpu_sound_0_device;
  wire [31:0]  gameConfig_sound_0_romOffset;
  wire [31:0]  gameConfig_sound_1_romOffset;
  wire [31:0]  gameConfig_sound_2_romOffset;
  wire [1:0]   gpu_io_layerCtrl_0_format;
  wire [31:0]  gameConfig_layer_0_romOffset;
  wire [1:0]   gameConfig_layer_0_paletteBank;
  wire [1:0]   gpu_io_layerCtrl_1_format;
  wire [31:0]  gameConfig_layer_1_romOffset;
  wire [1:0]   gameConfig_layer_1_paletteBank;
  wire [1:0]   gpu_io_layerCtrl_2_format;
  wire [31:0]  gameConfig_layer_2_romOffset;
  wire [1:0]   gameConfig_layer_2_paletteBank;
  wire [1:0]   gpu_io_spriteCtrl_format;
  wire [31:0]  gameConfig_sprite_romOffset;
  wire         gameConfig_sprite_zoom;
  wire         rotateClockwise;
  wire         gameIsHotdogStorm;
  wire         gameIsMazinger;
  wire         gameIsAirGallet;
  wire         gameIsSailorMoon;
  wire         gameIsAirFamily = gameIsAirGallet | gameIsSailorMoon;
  wire         gameIsMetmqstr;
  wire         _main_io_sailorMoonTilebank;
  wire [8:0]   spriteFrameBufferSizeX;
  wire         spriteLineBufferEarlyStart;
  wire [2:0]   spriteLineBufferBurstOffset;
  wire [1:0]   spriteRegsBankForGpu;

  CaveGameConfig gameConfig (
    .game_index           (gameIndexReg),
    .granularity          (gameConfig_granularity),
    .eeprom_offset        (gameConfig_eepromOffset),
    .sound_0_device       (gameConfig_sound_0_device),
    .sound_0_rom_offset   (gameConfig_sound_0_romOffset),
    .sound_1_rom_offset   (gameConfig_sound_1_romOffset),
    .sound_2_rom_offset   (gameConfig_sound_2_romOffset),
    .layer_0_format       (gpu_io_layerCtrl_0_format),
    .layer_0_rom_offset   (gameConfig_layer_0_romOffset),
    .layer_0_palette_bank (gameConfig_layer_0_paletteBank),
    .layer_1_format       (gpu_io_layerCtrl_1_format),
    .layer_1_rom_offset   (gameConfig_layer_1_romOffset),
    .layer_1_palette_bank (gameConfig_layer_1_paletteBank),
    .layer_2_format       (gpu_io_layerCtrl_2_format),
    .layer_2_rom_offset   (gameConfig_layer_2_romOffset),
    .layer_2_palette_bank (gameConfig_layer_2_paletteBank),
    .sprite_format        (gpu_io_spriteCtrl_format),
    .sprite_rom_offset    (gameConfig_sprite_romOffset),
    .sprite_zoom          (gameConfig_sprite_zoom)
  );

  CaveGameConfig gameConfigCpu (
    .game_index           (gameIndexCpuReg),
    .granularity          (),
    .eeprom_offset        (),
    .sound_0_device       (gameConfigCpu_sound_0_device),
    .sound_0_rom_offset   (),
    .sound_1_rom_offset   (),
    .sound_2_rom_offset   (),
    .layer_0_format       (),
    .layer_0_rom_offset   (),
    .layer_0_palette_bank (),
    .layer_1_format       (),
    .layer_1_rom_offset   (),
    .layer_1_palette_bank (),
    .layer_2_format       (),
    .layer_2_rom_offset   (),
    .layer_2_palette_bank (),
    .sprite_format        (),
    .sprite_rom_offset    (),
    .sprite_zoom          ()
  );

  CaveBoardProfile boardProfile(
    .game_index                  (gameIndexReg),
    .sound_device                (2'd0),
    .game_is_dfeveron            (),
    .game_is_dodonpachi          (),
    .game_is_donpachi            (),
    .game_is_esprade             (),
    .game_is_uopoko              (),
    .game_is_guwange             (),
    .game_is_gaia                (),
    .game_is_hotdogstorm         (gameIsHotdogStorm),
    .game_is_mazinger            (gameIsMazinger),
    .game_is_airgallet           (gameIsAirGallet),
    .game_is_sailormoon          (gameIsSailorMoon),
    .game_is_metmqstr            (gameIsMetmqstr),
    .board_uses_z80_sound        (),
    .board_is_vertical_clockwise (rotateClockwise),
    .sound_is_ymz280b            (),
    .sound_is_oki                (),
    .sound_is_z80                ()
  );
  assign spriteFrameBufferSizeX =
    gameIsMetmqstr ? 9'h1FF : _videoSys_io_video_regs_size_x;
  assign spriteLineBufferEarlyStart = gameIsMetmqstr;
  assign spriteLineBufferBurstOffset =
    gameIsMetmqstr ? 3'h1 : 3'h0;
  assign spriteRegsBankForGpu =
    gameIsMetmqstr ? metmqstrSpriteBankActive : _main_io_gpuMem_sprite_regs_bank;
  wire         ioctlRomIndexSelected = ioctl_index == 8'h0;
  wire         memSys_io_prog_rom_writeEnable = ioctl_download & ioctlRomIndexSelected;
  wire         ioctlNvramIndexSelected = ioctl_index == 8'h2;
  wire         ioctlNvramEepromAddress = ioctl_addr < 27'd128;
  wire         ioctlNvramEepromReadEnable =
    ioctl_upload & ioctlNvramIndexSelected & ioctlNvramEepromAddress;
  wire         ioctlNvramEepromWriteEnable =
    ioctl_download & ioctlNvramIndexSelected & ioctlNvramEepromAddress;
  wire         ioctlNvramHighScoreReadEnable =
    ioctl_upload & ioctlNvramIndexSelected & ~ioctlNvramEepromAddress;
  wire         memSys_io_prog_nvram_readEnable =
    ioctlNvramEepromReadEnable;
  wire         memSys_io_prog_nvram_writeEnable =
    ioctlNvramEepromWriteEnable;
  wire         ioctlNvramAccess =
    (ioctl_upload | ioctl_download) & ioctlNvramIndexSelected;
  wire         ioctlNvramWaitN =
    _main_io_hs_nvram_wait_n &
    (~ioctlNvramEepromAddress | _memSys_io_prog_nvram_wait_n);
  wire         ioctlMemoryWaitN =
    ioctlNvramAccess
      ? ioctlNvramWaitN
      : ~memSys_io_prog_rom_writeEnable | _memSys_io_prog_rom_wait_n;
  reg  [15:0]  memSys_io_prog_nvram_ioctl_din_r;
  reg          memSysIoctlDownloadReg;
  wire         ioctlVideoIndexSelected = ioctl_index == 8'h3;
  wire         videoSys_io_prog_video_writeEnable =
    ioctl_download & ioctlVideoIndexSelected;
  reg          videoSysIoctlDownloadReg;
  // Index 4 is already the fixed CBID save-state identity record.
  wire         ioctlHighScoreConfigSelected = ioctl_index == 8'h5;
  reg          eepromDirtyReg;
  reg          nvramUploadReg;
  wire         cpuDomainReset = cpuReset | ~_memSys_io_ready;
  wire         ioctlGameIndexWrite = ioctl_download & ioctl_wr & ioctl_index == 8'h1;
  wire         optionGameIndexFallback =
    ~ioctl_download & ioctlDownloadReg & ~gameIndexReg_latched;
  wire         effectiveRotate = options_rotate;
  wire         effectiveCompatibilityTiming = options_compatibility;
  wire         videoVBlankRising = videoVBlankPipe1 & ~videoVBlankPipe2;
  wire         videoVBlankFalling = ~videoVBlankPipe1 & videoVBlankPipe2;
  wire         mainSpriteFrameBufferSwapPulse;
  CaveAsyncLevelToPulse mainSpriteFrameBufferSwapCrossing (
    .clock     (clock),
    .reset     (reset),
    .level_in  (_main_io_spriteFrameBufferSwap),
    .pulse_out (mainSpriteFrameBufferSwapPulse)
  );
  // Air Gallet's sprite call is inverted: b80008 arms drawing, vblank swaps pages.
  wire         airGalletInvertedSpriteCall = gameIsAirGallet;
  // Sailor Moon uses the native CPU-write-driven swap during normal play.  A
  // paused restore cannot issue that write, so reconstruction alone borrows
  // Air Gallet's bounded preclear/render/drain/accepted-swap publication path.
  wire         airFamilyPrivateSpriteCall =
    airGalletInvertedSpriteCall |
    (saveStateControllerReconstructionActive & gameIsSailorMoon);
  wire         airGalletSpriteFrameReady =
    airGalletSpriteFrameInFlight &
    _gpu_io_spriteCtrl_frameReady &
    (~saveStateControllerReconstructionActive |
     airGalletReconstructionDrainSeen);
  wire         airGalletSpriteStart =
    videoVBlankFalling & airGalletSpriteStartPending &
    ~airGalletSpriteFrameInFlight &
    (~saveStateControllerReconstructionActive |
     saveStateSpriteReconstructionTargetReady);
  wire         spriteDelayedFrameSwap = gameIsMazinger | gameIsMetmqstr;
  wire         spriteSwapNeedsFrameReady = spriteDelayedFrameSwap;
  wire         spriteStartAllowed = ~spriteDelayedFrameSwap | spriteFrameBufferSwapPrimed;
  CaveMetmqstrSpriteScheduler metmqstrSpriteScheduler (
    .clock_i               (clock),
    .reset_i               (reset),
    .ready_i               (_memSys_io_ready),
    .enable_i              (gameIsMetmqstr),
    .block_new_work_i      (saveStateQuiesceBlockNewWork),
    .restore_load_i        (saveStateSystemRestoreApply),
    .restore_active_bank_i (saveStateSystemRestoreMetBankActive),
    .restore_delayed_bank_i(saveStateSystemRestoreMetBankDelay),
    .start_allowed_i       (spriteStartAllowed),
    .vblank_rising_i       (videoVBlankRising),
    .vblank_falling_i      (videoVBlankFalling),
    .selector_bank_i       (_main_io_gpuMem_sprite_regs_bank),
    .active_bank_o         (metmqstrSpriteBankActive),
    .delayed_bank_o        (metmqstrSpriteBankDelay),
    .sprite_start_o        (metmqstrSpriteProcessorStart)
  );
  wire         spriteFrameBufferSwapReady =
    ~spriteFrameBufferSwapPrimed | _gpu_io_spriteCtrl_frameReady;
  wire         spriteFrameBufferSwapRequest =
    airFamilyPrivateSpriteCall
      ? (videoVBlankRising & airGalletSpriteFrameReady)
      : mainSpriteFrameBufferSwapPulse;
  wire         spriteFrameBufferSwap =
    spriteFrameBufferSwapRequest &
    (~spriteSwapNeedsFrameReady | spriteFrameBufferSwapReady);
  wire         airGalletSpriteSwapCompleted =
    saveStateControllerReconstructionActive
      ? saveStateSpriteFrameBufferSwapAccepted
      : spriteFrameBufferSwap;
  assign saveStateGpuReconstructionComplete =
    saveStateGpuReconstructionReady &
    (~gameIsAirFamily | airGalletReconstructionSpritePublished);
  wire         spriteProcessorStart =
    airFamilyPrivateSpriteCall ? airGalletSpriteStart :
    gameIsMetmqstr ? metmqstrSpriteProcessorStart :
    videoVBlankFalling & spriteStartAllowed;

  // Save-state profile, slot, and replay configuration are captured before
  // quiesce begins and remain immutable until the complete release fence ends.
  assign saveStateProfileSupport =
    gameIsHotdogStorm ? SS_HOTDOG_SUPPORT :
    gameIsMazinger    ? SS_MAZINGER_SUPPORT :
    gameIsAirGallet   ? SS_AIR_SUPPORT :
    gameIsSailorMoon  ? SS_SAILOR_SUPPORT :
    gameIsMetmqstr    ? SS_METMQSTR_SUPPORT :
                        48'd0;
  assign saveStateProfileSupported =
    (saveStateProfileSupport != 48'd0) &&
    ((saveStateProfileSupport & ~SS_COMPILED_SUPPORT) == 48'd0);
  assign saveStateConfigFingerprint = {
    16'h4347,
    21'd0,
    options_audioTrim_sfx,
    options_audioTrim_bgm,
    options_audioTrim_fm,
    options_flipVideo,
    options_sprite,
    options_layer_2,
    options_layer_1,
    options_layer_0,
    effectiveCompatibilityTiming,
    effectiveRotate,
    options_offset_y,
    options_offset_x
  };
  assign saveStateOperationInFlight =
    saveStateControllerActive |
    saveStateQuiesceBusy |
    saveStateCoordinatorActive |
    saveStateRawStreamBusy;
  assign saveStateRuntimeSupport =
    saveStateOperationInFlight
      ? saveStateOperationSupport
      : saveStateProfileSupport;
  assign saveStateRuntimeConfig =
    saveStateOperationInFlight
      ? saveStateOperationConfig
      : saveStateConfigFingerprint;
  assign saveStateSlotBase =
    {8'h3e, saveStateOperationSlot, 22'd0};
  assign saveStateIoctlIdle = ~ioctl_download & ~ioctl_upload;
  assign saveStateOperationRequest =
    (ss_save_request ^ ss_load_request) & ss_available;

  always @(posedge clock) begin
    if (reset) begin
      saveStateOperationSupport <= 48'd0;
      saveStateOperationSlot <= 2'd0;
      saveStateOperationConfig <= 64'd0;
    end
    else if (saveStateOperationRequest) begin
      saveStateOperationSupport <= saveStateProfileSupport;
      saveStateOperationSlot <= ss_slot;
      saveStateOperationConfig <= saveStateConfigFingerprint;
    end
  end

  assign ss_available =
    !saveStateOperationInFlight &&
    saveStateIdentityValid &&
    saveStateProfileSupported &&
    saveStateIoctlIdle &&
    _memSys_io_ready &&
    saveStateMaintenanceIdle &&
    saveStateSystemRouterIdle &&
    saveStateSystemOwnerIdle &&
    saveStateMainCdcReady &&
    !saveStateMainCdcBusy &&
    !saveStateMainCdcDraining &&
    saveStateSoundCdcReady &&
    !saveStateSoundCdcBusy &&
    !saveStateSoundCdcDraining &&
    saveStateMainReleaseReady &&
    !saveStateMainReleaseBusy &&
    saveStateSoundReleaseReady &&
    !saveStateSoundReleaseBusy &&
    saveStateSystemCpuReady &&
    !saveStateSystemCpuBusy &&
    saveStateVideoDipReadySystem &&
    !saveStateNvramSessionActive &&
    !_main_io_hs_active &&
    soundRomSaveStateRearmed &&
    !saveStateInfrastructureFault &&
    !saveStateCoordinatorTerminalFault &&
    !saveStateControllerFatal &&
    !saveStateQuiesceFatal;
  assign ss_active = saveStateOperationInFlight;
  assign ss_busy =
    saveStateOperationInFlight |
    saveStateIdentityBusy |
    saveStateMaintenanceActive;

  CaveBanprestoRomIdentity #(
    .ROM_DDR_BASE(32'h3000_0000)
  ) saveStateIdentity (
    .clk                  (clock),
    .reset                (reset),
    .abort                (1'b0),
    .ioctl_download       (ioctl_download),
    .ioctl_wr             (ioctl_wr),
    .ioctl_index          (ioctl_index),
    .ioctl_addr           (ioctl_addr),
    .ioctl_dout           (ioctl_dout),
    .runtime_board_id     ({4'd0, gameIndexReg}),
    .runtime_board_valid  (gameIndexReg_latched),
    .mem_rd               (saveStateIdentityMemRd),
    .mem_addr             (saveStateIdentityMemAddr),
    .mem_dout             (saveStateIdentityMemData),
    .mem_wait_n           (saveStateIdentityMemReady),
    .mem_valid            (saveStateIdentityMemValid),
    .busy                 (saveStateIdentityBusy),
    .scan_done            (saveStateIdentityScanDone),
    .metadata_done        (saveStateIdentityMetadataDone),
    .identity_valid       (saveStateIdentityValid),
    .identity_error       (saveStateIdentityError),
    .error_flags          (saveStateIdentityErrorFlags),
    .rom_length           (saveStateRomLength),
    .rom_crc64            (saveStateRomCrc64),
    .canonical_set_id     (saveStateCanonicalSetId),
    .metadata_board_id    (saveStateMetadataBoardId)
  );

  CaveBanprestoSaveStateMaintenanceMux saveStateMaintenanceMux (
    .clk_i                      (clock),
    .reset_i                    (reset),
    .identity_acquire_i         (saveStateIdentityBusy),
    .identity_cmd_valid_i       (saveStateIdentityMemRd),
    .identity_cmd_ready_o       (saveStateIdentityMemReady),
    .identity_cmd_byte_addr_i   (saveStateIdentityMemAddr),
    .identity_rsp_valid_o       (saveStateIdentityMemValid),
    .identity_rsp_rdata_o       (saveStateIdentityMemData),
    .stream_acquire_i           (
      saveStateCoordinatorStreamSaveStart |
      saveStateCoordinatorStreamRestoreStart |
      saveStateRawStreamBusy
    ),
    .stream_cmd_valid_i         (saveStateStreamDdrCmdValid),
    .stream_cmd_ready_o         (saveStateStreamDdrCmdReady),
    .stream_cmd_write_i         (saveStateStreamDdrCmdWrite),
    .stream_cmd_byte_addr_i     (saveStateStreamDdrCmdAddr),
    .stream_cmd_wdata_i         (saveStateStreamDdrCmdData),
    .stream_cmd_be_i            (saveStateStreamDdrCmdBe),
    .stream_cmd_burstcnt_i      (saveStateStreamDdrCmdBurst),
    .stream_rsp_valid_o         (saveStateStreamDdrRspValid),
    .stream_rsp_rdata_o         (saveStateStreamDdrRspData),
    .save_acquire_o             (saveStateMaintenanceAcquire),
    .save_granted_i             (saveStateMaintenanceGranted),
    .save_cmd_valid_o           (saveStateMaintenanceCmdValid),
    .save_cmd_ready_i           (saveStateMaintenanceCmdReady),
    .save_cmd_write_o           (saveStateMaintenanceCmdWrite),
    .save_cmd_byte_addr_o       (saveStateMaintenanceCmdAddr),
    .save_cmd_wdata_o           (saveStateMaintenanceCmdData),
    .save_cmd_be_o              (saveStateMaintenanceCmdBe),
    .save_cmd_burstcnt_o        (saveStateMaintenanceCmdBurst),
    .save_rsp_valid_i           (saveStateMaintenanceRspValid),
    .save_rsp_rdata_i           (saveStateMaintenanceRspData),
    .idle_o                     (saveStateMaintenanceIdle),
    .active_o                   (saveStateMaintenanceActive),
    .owner_identity_o           (saveStateMaintenanceIdentityOwner),
    .releasing_o                (saveStateMaintenanceReleasing),
    .conflict_o                 (saveStateMaintenanceConflict),
    .protocol_error_o           (saveStateMaintenanceProtocolError),
    .unexpected_response_o      (
      saveStateMaintenanceUnexpectedResponse
    ),
    .timeout_o                  (saveStateMaintenanceTimeout),
    .terminal_fault_o           (saveStateMaintenanceTerminalFault)
  );

  CaveBanprestoSaveStateDdrArbiter saveStateDdrArbiter (
    .clock                    (clock),
    .reset                    (reset),
    .game_idle                (_ddr_1_io_idle),
    .game_cmd_valid           (
      saveStateGameDdrRd | saveStateGameDdrWr
    ),
    .game_cmd_ready           (saveStateGameDdrWaitN),
    .game_cmd_write           (saveStateGameDdrWr),
    .game_cmd_byte_addr       (saveStateGameDdrAddr),
    .game_cmd_wdata           (saveStateGameDdrDin),
    .game_cmd_be              (saveStateGameDdrMask),
    .game_cmd_burstcnt        (saveStateGameDdrBurst),
    .game_rsp_valid           (saveStateGameDdrValid),
    .game_rsp_rdata           (saveStateGameDdrDout),
    .game_write_commit        (saveStateGameDdrWriteCommit),
    .game_write_commit_byte_addr(
      saveStateGameDdrWriteCommitAddr
    ),
    .save_acquire             (saveStateMaintenanceAcquire),
    .save_granted             (saveStateMaintenanceGranted),
    .save_cmd_valid           (saveStateMaintenanceCmdValid),
    .save_cmd_ready           (saveStateMaintenanceCmdReady),
    .save_cmd_write           (saveStateMaintenanceCmdWrite),
    .save_cmd_byte_addr       (saveStateMaintenanceCmdAddr),
    .save_cmd_wdata           (saveStateMaintenanceCmdData),
    .save_cmd_be              (saveStateMaintenanceCmdBe),
    .save_cmd_burstcnt        (saveStateMaintenanceCmdBurst),
    .save_rsp_valid           (saveStateMaintenanceRspValid),
    .save_rsp_rdata           (saveStateMaintenanceRspData),
    .ddr_rd                   (ddr_rd),
    .ddr_wr                   (ddr_wr),
    .ddr_byte_addr            (ddr_addr),
    .ddr_wdata                (ddr_din),
    .ddr_be                   (ddr_mask),
    .ddr_burstcnt             (ddr_burstLength),
    .ddr_wait_n               (ddr_wait_n),
    .ddr_rdata                (ddr_dout),
    .ddr_rdata_valid          (ddr_valid)
  );

  // A queued SystemFrameBuffer write is complete only when the registered
  // game-side command is accepted by the physical DDR boundary.  Page 3 is
  // outside the three framebuffer pages and must never retire this queue.
  assign saveStateSystemFrameBufferDdrCommit =
    saveStateGameDdrWriteCommit &&
    (saveStateGameDdrWriteCommitAddr[31:21] == 11'h120) &&
    (saveStateGameDdrWriteCommitAddr[20:19] != 2'b11);

  CaveBanprestoSaveStateStream #(
    .SUPPORT_ENABLED(1)
  ) saveStateStream (
    .clk_i                          (clock),
    .reset_i                        (reset),
    .abort_i                        (saveStateCoordinatorStreamAbort),
    .save_start_i                   (
      saveStateCoordinatorStreamSaveStart
    ),
    .restore_start_i                (
      saveStateCoordinatorStreamRestoreStart
    ),
    .pass2_enable_i                 (
      saveStateCoordinatorStreamPass2Enable
    ),
    .slot_base_i                    (saveStateSlotBase),
    .slot_length_i                  (32'h0040_0000),
    .runtime_support_i              (saveStateRuntimeSupport),
    .metadata_validation_complete_i (
      saveStateMetadataValidationComplete
    ),
    .metadata_validation_valid_i    (
      saveStateMetadataValidationValid
    ),
    .restore_begin_o                (saveStateRawStreamRestoreBegin),
    .busy_o                         (saveStateRawStreamBusy),
    .done_o                         (saveStateRawStreamDone),
    .success_o                      (saveStateRawStreamSuccess),
    .format_error_o                 (saveStateRawStreamFormatError),
    .pass1_complete_o               (
      saveStateRawStreamPass1Complete
    ),
    .mutated_o                      (saveStateRawStreamMutated),
    .fatal_o                        (saveStateRawStreamFatal),
    .error_code_o                   (saveStateRawStreamError),
    .restore_pass_o                 (saveStateRawStreamRestorePass),
    .restore_commit_o               (saveStateRawStreamRestoreCommit),
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
    .debug_owner_failure_count_o    (
      saveStateRawOwnerFailureCountDebug
    ),
    .debug_owner_failure_state_o    (
      saveStateRawOwnerFailureStateDebug
    ),
    .debug_owner_failure_restore_o  (
      saveStateRawOwnerFailureRestoreDebug
    ),
    .debug_owner_failure_pass_o     (
      saveStateRawOwnerFailurePassDebug
    ),
    .debug_owner_failure_command_o  (
      saveStateRawOwnerFailureCommandDebug
    ),
    .debug_owner_failure_select_o   (
      saveStateRawOwnerFailureSelectDebug
    ),
    .debug_owner_failure_addr_o     (
      saveStateRawOwnerFailureAddrDebug
    ),
    .debug_owner_failure_reason_o   (
      saveStateRawOwnerFailureReasonDebug
    ),
    .debug_owner_failure_data_low_o (
      saveStateRawOwnerFailureDataLowDebug
    ),
`endif
    .save_cmd_valid                 (saveStateStreamDdrCmdValid),
    .save_cmd_ready                 (saveStateStreamDdrCmdReady),
    .save_cmd_write                 (saveStateStreamDdrCmdWrite),
    .save_cmd_byte_addr             (saveStateStreamDdrCmdAddr),
    .save_cmd_wdata                 (saveStateStreamDdrCmdData),
    .save_cmd_be                    (saveStateStreamDdrCmdBe),
    .save_cmd_burstcnt              (saveStateStreamDdrCmdBurst),
    .save_rsp_valid                 (saveStateStreamDdrRspValid),
    .save_rsp_rdata                 (saveStateStreamDdrRspData),
    .ssbus                          (saveStateStreamBus)
  );

  CaveBanprestoSaveStateController saveStateController (
    .clk_i                         (clock),
    .reset_i                       (reset),
    .save_request_i                (
      ss_save_request & saveStateOperationRequest
    ),
    .restore_request_i             (
      ss_load_request & saveStateOperationRequest
    ),
    .abort_i                       (1'b0),
    .vblank_i                      (videoVBlankObserverPipe1),
    .quiesce_busy_i                (saveStateQuiesceBusy),
    .quiesce_freeze_i              (saveStateQuiesceFreeze),
    .quiesce_quiesced_i            (saveStateQuiesced),
    .quiesce_request_accepted_i    (saveStateQuiesceAccepted),
    .quiesce_request_rejected_i    (saveStateQuiesceRejected),
    .quiesce_timeout_i             (saveStateQuiesceTimeout),
    .quiesce_fatal_hold_i          (saveStateQuiesceFatal),
    .quiesce_request_o             (
      saveStateControllerQuiesceRequest
    ),
    .quiesce_request_restore_o     (
      saveStateControllerQuiesceRestore
    ),
    .quiesce_abort_o               (saveStateControllerQuiesceAbort),
    .quiesce_resume_o              (saveStateControllerQuiesceResume),
    .quiesce_operation_fatal_o     (
      saveStateControllerOperationFatal
    ),
    .stream_busy_i                 (
      saveStateCoordinatorControllerStreamBusy
    ),
    .stream_done_i                 (
      saveStateCoordinatorControllerStreamDone
    ),
    .stream_success_i              (
      saveStateCoordinatorControllerStreamSuccess
    ),
    .stream_format_error_i         (
      saveStateCoordinatorControllerStreamFormatError
    ),
    .stream_pass1_complete_i       (
      saveStateCoordinatorControllerStreamPass1Complete
    ),
    .stream_mutated_i              (
      saveStateCoordinatorControllerStreamMutated
    ),
    .stream_fatal_i                (
      saveStateCoordinatorControllerStreamFatal
    ),
    .stream_error_code_i           (
      saveStateCoordinatorControllerStreamError
    ),
    .stream_restore_pass_i         (
      saveStateCoordinatorControllerRestorePass
    ),
    .stream_restore_begin_i        (
      saveStateCoordinatorControllerRestoreBegin
    ),
    .stream_restore_commit_i       (
      saveStateCoordinatorControllerRestoreCommit
    ),
    .stream_abort_o                (saveStateControllerStreamAbort),
    .stream_save_start_o           (
      saveStateControllerStreamSaveStart
    ),
    .stream_restore_start_o        (
      saveStateControllerStreamRestoreStart
    ),
    .restore_begin_o               (saveStateControllerRestoreBegin),
    .restore_commit_o              (saveStateControllerRestoreCommit),
    .sprite_frame_complete_i       (
      saveStateGpuReconstructionComplete
    ),
    .system_frame_complete_i       (
      saveStateSystemFrameBufferPublicationComplete
    ),
    .reconstruction_start_o        (
      saveStateControllerReconstructionStart
    ),
    .reconstruction_active_o       (
      saveStateControllerReconstructionActive
    ),
    .hdmi_freeze_o                 (ss_hdmi_freeze),
    .active_o                      (saveStateControllerActive),
    .operation_restore_o           (saveStateControllerRestore),
    .operation_done_o              (saveStateControllerDone),
    .operation_success_o           (saveStateControllerSuccess),
    .operation_aborted_o           (saveStateControllerAborted),
    .request_accepted_o            (saveStateControllerAccepted),
    .request_rejected_o            (saveStateControllerRejected),
    .timeout_pulse_o               (saveStateControllerTimeout),
    .fatal_hold_o                  (saveStateControllerFatal),
    .state_debug_o                 (saveStateControllerDebug),
    .last_error_o                  (saveStateControllerLastError),
    .last_stream_error_o           (
      saveStateControllerLastStreamError
    )
  );

  CaveBanprestoSaveStateQuiesce #(
    .IDLE_ACK_COUNT(SS_IDLE_ACK_COUNT),
    .PHASE_TIMEOUT_CYCLES(SS_QUIESCE_PHASE_TIMEOUT_CYCLES)
  ) saveStateQuiesce (
    .clk                    (clock),
    .reset                  (reset),
    .request                (saveStateControllerQuiesceRequest),
    .request_restore        (saveStateControllerQuiesceRestore),
    .abort                  (saveStateControllerQuiesceAbort),
    .resume                 (saveStateControllerQuiesceResume),
    .release_complete       (saveStateCoordinatorReleaseComplete),
    .operation_fatal        (saveStateControllerOperationFatal),
    .identity_valid         (saveStateIdentityValid),
    .profile_supported      (saveStateProfileSupported),
    .ioctl_idle             (saveStateIoctlIdle),
    .boot_ready             (_memSys_io_ready),
    .vblank                 (videoVBlankObserverPipe1),
    .main_cpu_captured      (saveStateCoordinatorMainStopped),
    .sound_cpu_stopped      (saveStateCoordinatorSoundStopped),
    .main_cpu_abort_ack     (saveStateCoordinatorMainAbortAck),
    .sound_cpu_abort_ack    (saveStateCoordinatorSoundAbortAck),
    .idle_ack               (saveStateIdleAck),
    .busy                   (saveStateQuiesceBusy),
    .freeze                 (saveStateQuiesceFreeze),
    .block_new_work         (saveStateQuiesceBlockNewWork),
    .main_cpu_capture_req   (saveStateQuiesceMainStopRequest),
    .sound_cpu_stop_req     (saveStateQuiesceSoundStopRequest),
    .quiesced               (saveStateQuiesced),
    .quiesced_pulse         (saveStateQuiescedPulse),
    .request_accepted       (saveStateQuiesceAccepted),
    .request_rejected       (saveStateQuiesceRejected),
    .abort_pulse            (saveStateQuiesceAbortPulse),
    .abort_complete_pulse   (saveStateQuiesceAbortComplete),
    .timeout_pulse          (saveStateQuiesceTimeout),
    .restore_active         (saveStateQuiesceRestoreActive),
    .fatal_hold             (saveStateQuiesceFatal),
    .abort_active           (saveStateQuiesceAbortActive),
    .sound_rom_launch_block (saveStateSoundRomLaunchBlock),
    .phase                  (saveStateQuiescePhase)
  );

  CaveBanprestoSaveStateDomainCoordinator #(
    .CONTROL_SOURCE_TIMEOUT_CYCLES(
      SS_CONTROL_SOURCE_TIMEOUT_CYCLES
    ),
    .CONTROL_DESTINATION_TIMEOUT_CYCLES(
      SS_CONTROL_DESTINATION_TIMEOUT_CYCLES
    )
  ) saveStateCoordinator (
    .sys_clk_i                         (clock),
    .sys_async_reset_i                 (reset),
    .cpu_clk_i                         (cpuClock),
    .cpu_async_reset_i                 (cpuDomainReset),
    .game_index_i                      (gameIndexReg),
    .quiesce_request_restore_i         (
      saveStateQuiesceRestoreActive
    ),
    .quiesce_main_stop_request_i       (
      saveStateQuiesceMainStopRequest
    ),
    .quiesce_sound_stop_request_i      (
      saveStateQuiesceSoundStopRequest
    ),
    .quiesce_main_stopped_o            (
      saveStateCoordinatorMainStopped
    ),
    .quiesce_sound_stopped_o           (
      saveStateCoordinatorSoundStopped
    ),
    .quiesce_main_abort_ack_o          (
      saveStateCoordinatorMainAbortAck
    ),
    .quiesce_sound_abort_ack_o         (
      saveStateCoordinatorSoundAbortAck
    ),
    .controller_stream_save_start_i    (
      saveStateControllerStreamSaveStart
    ),
    .controller_stream_restore_start_i (
      saveStateControllerStreamRestoreStart
    ),
    .controller_stream_abort_i         (
      saveStateControllerStreamAbort
    ),
    .controller_release_request_i      (
      saveStateControllerQuiesceResume
    ),
    .stream_save_start_o               (
      saveStateCoordinatorStreamSaveStart
    ),
    .stream_restore_start_o            (
      saveStateCoordinatorStreamRestoreStart
    ),
    .stream_pass2_enable_o             (
      saveStateCoordinatorStreamPass2Enable
    ),
    .stream_abort_o                    (
      saveStateCoordinatorStreamAbort
    ),
    .raw_stream_busy_i                 (saveStateRawStreamBusy),
    .raw_stream_done_i                 (saveStateRawStreamDone),
    .raw_stream_success_i              (saveStateRawStreamSuccess),
    .raw_stream_format_error_i         (
      saveStateRawStreamFormatError
    ),
    .raw_stream_pass1_complete_i       (
      saveStateRawStreamPass1Complete
    ),
    .raw_stream_mutated_i              (saveStateRawStreamMutated),
    .raw_stream_fatal_i                (saveStateRawStreamFatal),
    .raw_stream_error_code_i           (saveStateRawStreamError),
    .raw_stream_restore_pass_i         (
      saveStateRawStreamRestorePass
    ),
    .raw_stream_restore_begin_i        (
      saveStateRawStreamRestoreBegin
    ),
    .raw_stream_restore_commit_i       (
      saveStateRawStreamRestoreCommit
    ),
    .controller_stream_busy_o          (
      saveStateCoordinatorControllerStreamBusy
    ),
    .controller_stream_done_o          (
      saveStateCoordinatorControllerStreamDone
    ),
    .controller_stream_success_o       (
      saveStateCoordinatorControllerStreamSuccess
    ),
    .controller_stream_format_error_o  (
      saveStateCoordinatorControllerStreamFormatError
    ),
    .controller_stream_pass1_complete_o(
      saveStateCoordinatorControllerStreamPass1Complete
    ),
    .controller_stream_mutated_o       (
      saveStateCoordinatorControllerStreamMutated
    ),
    .controller_stream_fatal_o         (
      saveStateCoordinatorControllerStreamFatal
    ),
    .controller_stream_error_code_o    (
      saveStateCoordinatorControllerStreamError
    ),
    .controller_stream_restore_pass_o  (
      saveStateCoordinatorControllerRestorePass
    ),
    .controller_stream_restore_begin_o (
      saveStateCoordinatorControllerRestoreBegin
    ),
    .controller_stream_restore_commit_o(
      saveStateCoordinatorControllerRestoreCommit
    ),
    .system_noncpu_commit_o            (
      saveStateCoordinatorSystemCommit
    ),
    .system_commit_done_i              (saveStateSystemCommitDone),
    .system_commit_fault_i             (saveStateSystemCommitFault),
    .main_release_request_o            (
      saveStateCoordinatorMainRelease
    ),
    .sound_release_request_o           (
      saveStateCoordinatorSoundRelease
    ),
    .release_restore_o                 (
      saveStateCoordinatorReleaseRestore
    ),
    .main_release_complete_i           (
      saveStateMainReleaseCompleteSystem
    ),
    .sound_release_complete_i          (
      saveStateSoundReleaseCompleteSystem
    ),
    .quiesce_release_complete_o        (
      saveStateCoordinatorReleaseComplete
    ),
    .release_pending_o                 (
      saveStateCoordinatorReleasePending
    ),
    .main_command_valid_o              (
      saveStateCoordinatorMainCommandValid
    ),
    .main_command_o                    (
      saveStateCoordinatorMainCommand
    ),
    .main_command_complete_i           (
      saveStateMainCommandComplete
    ),
    .main_command_response_i           (
      saveStateMainCommandResponse
    ),
    .main_command_terminal_fault_i     (
      saveStateMainCommandTerminalFault
    ),
    .main_command_busy_o               (
      saveStateCoordinatorMainCommandBusy
    ),
    .main_command_channel_fault_o      (
      saveStateCoordinatorMainCommandChannelFault
    ),
    .sound_command_valid_o             (
      saveStateCoordinatorSoundCommandValid
    ),
    .sound_command_o                   (
      saveStateCoordinatorSoundCommand
    ),
    .sound_command_complete_i          (
      saveStateSoundCommandComplete
    ),
    .sound_command_response_i          (
      saveStateSoundCommandResponse
    ),
    .sound_command_terminal_fault_i    (
      saveStateSoundCommandTerminalFault
    ),
    .sound_command_busy_o              (
      saveStateCoordinatorSoundCommandBusy
    ),
    .sound_command_channel_fault_o     (
      saveStateCoordinatorSoundCommandChannelFault
    ),
    .terminal_fault_o                  (
      saveStateCoordinatorTerminalFault
    ),
    .last_fault_code_o                 (
      saveStateCoordinatorLastFault
    ),
    .operation_active_o                (saveStateCoordinatorActive),
    .operation_restore_o               (saveStateCoordinatorRestore),
    .mutation_authorized_o             (
      saveStateCoordinatorMutationAuthorized
    ),
    .state_debug_o                     (saveStateCoordinatorDebug)
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
    ,
    .debug_result_latched_o            (
      saveStateCoordinatorResultLatchedDebug
    ),
    .debug_result_success_o            (
      saveStateCoordinatorResultSuccessDebug
    ),
    .debug_result_restore_commit_o     (
      saveStateCoordinatorResultCommitDebug
    ),
    .debug_result_restore_pass_o       (
      saveStateCoordinatorResultPassDebug
    ),
    .debug_restore_done_good_o         (
      saveStateCoordinatorRestoreDoneGoodDebug
    ),
    .debug_restore_pass2_capture_o     (
      saveStateCoordinatorPass2CaptureDebug
    ),
    .debug_abort_requested_o           (
      saveStateCoordinatorAbortRequestedDebug
    ),
    .debug_first_protocol_fault_o      (
      saveStateCoordinatorFirstProtocolFaultDebug
    )
`endif
  );

  CaveBanprestoSaveStateBusRouter #(
    .BRANCH_COUNT(5),
    .SUPPORT_WIDTH(48),
    .COMPILED_SUPPORT_BITMAP(SS_COMPILED_SUPPORT),
    .BRANCH_OWNER_MASKS({
      SS_SOUND_SUPPORT,
      48'h0000_0020_0000,
      SS_MAIN_SUPPORT,
      48'h0000_0000_0002,
      48'h0000_0000_0001
    }),
    .RESPONSE_TIMEOUT_CYCLES(4096)
  ) saveStateSystemRouter (
    .clk_i                   (clock),
    .reset_i                 (reset),
    .runtime_support_i       (saveStateRuntimeSupport),
    .branches                (saveStateSystemBranches),
    .upstream                (saveStateStreamBus),
    .no_route_o              (saveStateSystemRouterNoRoute),
    .multiple_route_o        (saveStateSystemRouterMultipleRoute),
    .wrong_branch_response_o (saveStateSystemRouterWrongResponse),
    .timeout_o               (saveStateSystemRouterTimeout),
    .faulted_o               (saveStateSystemRouterFault),
    .idle_o                  (saveStateSystemRouterIdle)
  );

  CaveBanprestoSaveStateBusCdc #(
    .OWNER_COUNT(48),
    .SUPPORT_WIDTH(48),
    .COMPILED_SUPPORT_BITMAP(SS_MAIN_SUPPORT)
  ) saveStateMainBusCdc (
    .src_clk_i                (clock),
    .src_async_reset_i        (reset),
    .runtime_support_i        (saveStateRuntimeSupport),
    .src_abort_i              (saveStateCoordinatorStreamAbort),
    .src_bus                  (saveStateSystemBranches[2]),
    .src_ready_o              (saveStateMainCdcReady),
    .src_busy_o               (saveStateMainCdcBusy),
    .src_draining_o           (saveStateMainCdcDraining),
    .src_timeout_o            (saveStateMainCdcTimeout),
    .src_abandoned_o          (saveStateMainCdcAbandoned),
    .src_aborted_o            (saveStateMainCdcAborted),
    .src_local_reject_o       (saveStateMainCdcLocalReject),
    .src_destination_reset_o  (
      saveStateMainCdcDestinationReset
    ),
    .src_terminal_fault_o     (saveStateMainCdcSourceFault),
    .dst_clk_i                (cpuClock),
    .dst_async_reset_i        (cpuDomainReset),
    .dst_terminal_fault_i     (
      saveStateMainRouterFault |
      saveStateMainCommandTerminalFault |
      saveStateMainCpuTerminalFault |
      saveStateMainControlTerminalFault |
      saveStateMainRamTerminalFault |
      saveStateMainRegisterTerminalFault |
      saveStateMainEepromTerminalFault
    ),
    .dst_bus                  (saveStateMainCpuBus),
    .dst_busy_o               (saveStateMainCdcDestinationBusy),
    .dst_draining_o           (saveStateMainCdcDestinationDraining),
    .dst_forced_drop_o        (saveStateMainCdcForcedDrop),
    .dst_late_response_o      (saveStateMainCdcLateResponse),
    .dst_terminal_fault_o     (saveStateMainCdcDestinationFault)
  );

  CaveBanprestoSaveStateBusRouter #(
    .BRANCH_COUNT(5),
    .SUPPORT_WIDTH(48),
    .COMPILED_SUPPORT_BITMAP(SS_MAIN_SUPPORT),
    .BRANCH_OWNER_MASKS({
      48'h0000_0040_0000,
      48'h0000_0010_0000,
      48'h0000_000f_fff0,
      48'h0000_0000_0008,
      48'h0000_0000_0004
    }),
    .RESPONSE_TIMEOUT_CYCLES(4096)
  ) saveStateMainRouter (
    .clk_i                   (cpuClock),
    .reset_i                 (cpuDomainReset),
    .runtime_support_i       (saveStateRuntimeSupport),
    .branches                (saveStateMainBranches),
    .upstream                (saveStateMainCpuBus),
    .no_route_o              (saveStateMainRouterNoRoute),
    .multiple_route_o        (saveStateMainRouterMultipleRoute),
    .wrong_branch_response_o (saveStateMainRouterWrongResponse),
    .timeout_o               (saveStateMainRouterTimeout),
    .faulted_o               (saveStateMainRouterFault),
    .idle_o                  (saveStateMainRouterIdle)
  );

  CaveBanprestoSaveStateBusCdc #(
    .OWNER_COUNT(48),
    .SUPPORT_WIDTH(48),
    .COMPILED_SUPPORT_BITMAP(SS_SOUND_SUPPORT)
  ) saveStateSoundBusCdc (
    .src_clk_i                (clock),
    .src_async_reset_i        (reset),
    .runtime_support_i        (saveStateRuntimeSupport),
    .src_abort_i              (saveStateCoordinatorStreamAbort),
    .src_bus                  (saveStateSystemBranches[4]),
    .src_ready_o              (saveStateSoundCdcReady),
    .src_busy_o               (saveStateSoundCdcBusy),
    .src_draining_o           (saveStateSoundCdcDraining),
    .src_timeout_o            (saveStateSoundCdcTimeout),
    .src_abandoned_o          (saveStateSoundCdcAbandoned),
    .src_aborted_o            (saveStateSoundCdcAborted),
    .src_local_reject_o       (saveStateSoundCdcLocalReject),
    .src_destination_reset_o  (
      saveStateSoundCdcDestinationReset
    ),
    .src_terminal_fault_o     (saveStateSoundCdcSourceFault),
    .dst_clk_i                (cpuClock),
    .dst_async_reset_i        (cpuDomainReset),
    .dst_terminal_fault_i     (_sound_io_ss_terminal_fault),
    .dst_bus                  (soundSaveStateBus),
    .dst_busy_o               (saveStateSoundCdcDestinationBusy),
    .dst_draining_o           (saveStateSoundCdcDestinationDraining),
    .dst_forced_drop_o        (saveStateSoundCdcForcedDrop),
    .dst_late_response_o      (saveStateSoundCdcLateResponse),
    .dst_terminal_fault_o     (saveStateSoundCdcDestinationFault)
  );

`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
  // Retain the final system-domain request offered to Sound.  A downstream
  // terminal fault causes the CDC to withdraw its destination request before
  // the slow JTAG observer can sample it, so a last-value recorder is needed
  // to identify the exact pass-2 owner and address on hardware.
  always @(posedge clock) begin
    if (reset) begin
      saveStateSoundLastCommandDebug <= 4'd0;
      saveStateSoundLastSelectDebug <= 8'd0;
      saveStateSoundLastAddrDebug <= 32'd0;
      saveStateSoundLastDataLowDebug <= 16'd0;
    end else if (saveStateSystemBranches[4].command_active()) begin
      saveStateSoundLastCommandDebug <= {
        saveStateSystemBranches[4].req_query,
        saveStateSystemBranches[4].req_validate,
        saveStateSystemBranches[4].req_write,
        saveStateSystemBranches[4].req_read
      };
      saveStateSoundLastSelectDebug <=
        saveStateSystemBranches[4].req_select;
      saveStateSoundLastAddrDebug <=
        saveStateSystemBranches[4].req_addr;
      saveStateSoundLastDataLowDebug <=
        saveStateSystemBranches[4].req_data[15:0];
    end
  end

  assign saveStateSoundFaultStatusDebug = {
    _sound_io_ss_terminal_fault,
    saveStateSoundCommandTerminalFault,
    saveStateSoundCdcReady,
    saveStateSoundCdcBusy,
    saveStateSoundCdcDraining,
    saveStateSoundCdcTimeout,
    saveStateSoundCdcAbandoned,
    saveStateSoundCdcAborted,
    saveStateSoundCdcLocalReject,
    saveStateSoundCdcDestinationReset,
    saveStateSoundCdcSourceFault,
    saveStateSoundCdcDestinationBusy,
    saveStateSoundCdcDestinationDraining,
    saveStateSoundCdcForcedDrop,
    saveStateSoundCdcLateResponse,
    saveStateSoundCdcDestinationFault,
    _sound_io_ss_idle,
    _sound_io_ss_stopped,
    saveStateCoordinatorStreamAbort
  };
  assign saveStateSoundFaultContextDebug = {
    2'b01,
    saveStateSoundOwnerFaultDebugCpu,
    saveStateSoundLastCommandDebug,
    saveStateSoundLastSelectDebug,
    saveStateSoundLastAddrDebug,
    saveStateSoundLastDataLowDebug,
    saveStateSoundFaultStatusDebug[18:2]
  };
  assign saveStateCoordinatorFaultContextDebug = {
    2'b10,
    saveStateCoordinatorFirstProtocolFaultDebug,
    saveStateSoundLastCommandDebug,
    saveStateSoundLastSelectDebug,
    saveStateSoundLastAddrDebug,
    1'b0
  };
  // Tag 3 is a diagnostic-only framebuffer-publication record.  Its owner
  // failure-count field remains zero so the existing hardware gate stays
  // fail-closed on every real owner failure while the raw page preserves the
  // V26 reconstruction sequence for offline decoding.
  assign saveStateVideoPublicationContextDebug = {
    2'b11,
    8'd0,
    6'd0,
    1'b0,
    2'b00,
    3'b000,
    8'd0,
    saveStateSystemFrameBufferPublicationDebug,
    4'h0,
    16'd0,
    5'd0
  };
  assign saveStatePass2FaultContextDebug =
    ((saveStateCoordinatorLastFault == 8'h01) &&
     (saveStateCoordinatorFirstProtocolFaultDebug != 40'd0) &&
     (saveStateSoundOwnerFaultDebugCpu[6:0] == 7'd0))
      ? saveStateCoordinatorFaultContextDebug
      : (saveStateSoundOwnerFaultDebugCpu != 8'd0)
        ? saveStateSoundFaultContextDebug
        : saveStateVideoPublicationContextDebug;
  assign saveStatePass2FaultContextValidDebug =
    (saveStateCoordinatorFirstProtocolFaultDebug != 40'd0) ||
    (saveStateSoundOwnerFaultDebugCpu != 8'd0) ||
    (saveStateRawOwnerFailureCountDebug == 8'd0);
`endif

  CaveBanprestoSaveStateReleaseCdc #(
    .SOURCE_TIMEOUT_CYCLES(SS_CONTROL_SOURCE_TIMEOUT_CYCLES),
    .DESTINATION_TIMEOUT_CYCLES(
      SS_CONTROL_DESTINATION_TIMEOUT_CYCLES
    )
  ) saveStateMainReleaseCdc (
    .src_clk_i                   (clock),
    .src_async_reset_i           (reset),
    .src_release_request_i       (saveStateCoordinatorMainRelease),
    .src_release_restore_i       (
      saveStateCoordinatorReleaseRestore
    ),
    .src_release_complete_o      (
      saveStateMainReleaseCompleteSystem
    ),
    .src_ready_o                 (saveStateMainReleaseReady),
    .src_busy_o                  (saveStateMainReleaseBusy),
    .src_timeout_o               (saveStateMainReleaseSourceTimeout),
    .src_destination_reset_o     (),
    .src_protocol_fault_o        (
      saveStateMainReleaseSourceProtocolFault
    ),
    .src_terminal_fault_o        (saveStateMainReleaseSourceFault),
    .src_debug_state_o           (saveStateMainReleaseSourceStateDebug),
    .src_debug_restore_hold_o    (
      saveStateMainReleaseSourceRestoreHoldDebug
    ),
    .src_debug_command_valid_o   (
      saveStateMainReleaseSourceCommandValidDebug
    ),
    .src_debug_command_accepted_o (
      saveStateMainReleaseSourceCommandAcceptedDebug
    ),
    .src_debug_restore_known_o   (
      saveStateMainReleaseSourceRestoreKnownDebug
    ),
    .dst_clk_i                   (cpuClock),
    .dst_async_reset_i           (cpuDomainReset),
    .dst_release_request_o       (saveStateMainReleaseRequestCpu),
    .dst_release_restore_o       (saveStateMainReleaseRestoreCpu),
    .dst_release_complete_i      (
      saveStateMainReleaseCompleteCpu
    ),
    .dst_terminal_fault_i        (
      saveStateMainCommandTerminalFault |
      saveStateMainCpuTerminalFault |
      saveStateMainControlTerminalFault |
      saveStateMainRamTerminalFault |
      saveStateMainRegisterTerminalFault |
      saveStateMainEepromTerminalFault
    ),
    .dst_busy_o                  (),
    .dst_timeout_o               (saveStateMainReleaseDestinationTimeout),
    .dst_source_reset_o          (),
    .dst_unsolicited_complete_o  (),
    .dst_protocol_fault_o        (
      saveStateMainReleaseDestinationProtocolFault
    ),
    .dst_terminal_fault_o        (
      saveStateMainReleaseDestinationFault
    ),
    .dst_debug_state_o           (
      saveStateMainReleaseDestinationStateDebug
    ),
    .dst_debug_restore_hold_o    (
      saveStateMainReleaseDestinationRestoreHoldDebug
    ),
    .dst_debug_command_valid_o   (
      saveStateMainReleaseDestinationCommandValidDebug
    ),
    .dst_debug_command_o         (
      saveStateMainReleaseDestinationCommandDebug
    )
  );

  CaveBanprestoSaveStateReleaseCdc #(
    .SOURCE_TIMEOUT_CYCLES(SS_CONTROL_SOURCE_TIMEOUT_CYCLES),
    .DESTINATION_TIMEOUT_CYCLES(
      SS_CONTROL_DESTINATION_TIMEOUT_CYCLES
    )
  ) saveStateSoundReleaseCdc (
    .src_clk_i                   (clock),
    .src_async_reset_i           (reset),
    .src_release_request_i       (saveStateCoordinatorSoundRelease),
    .src_release_restore_i       (
      saveStateCoordinatorReleaseRestore
    ),
    .src_release_complete_o      (
      saveStateSoundReleaseCompleteSystem
    ),
    .src_ready_o                 (saveStateSoundReleaseReady),
    .src_busy_o                  (saveStateSoundReleaseBusy),
    .src_timeout_o               (saveStateSoundReleaseSourceTimeout),
    .src_destination_reset_o     (),
    .src_protocol_fault_o        (
      saveStateSoundReleaseSourceProtocolFault
    ),
    .src_terminal_fault_o        (saveStateSoundReleaseSourceFault),
    .src_debug_state_o           (saveStateSoundReleaseSourceStateDebug),
    .src_debug_restore_hold_o    (
      saveStateSoundReleaseSourceRestoreHoldDebug
    ),
    .src_debug_command_valid_o   (
      saveStateSoundReleaseSourceCommandValidDebug
    ),
    .src_debug_command_accepted_o (
      saveStateSoundReleaseSourceCommandAcceptedDebug
    ),
    .src_debug_restore_known_o   (
      saveStateSoundReleaseSourceRestoreKnownDebug
    ),
    .dst_clk_i                   (cpuClock),
    .dst_async_reset_i           (cpuDomainReset),
    .dst_release_request_o       (saveStateSoundReleaseRequestCpu),
    .dst_release_restore_o       (saveStateSoundReleaseRestoreCpu),
    .dst_release_complete_i      (_sound_io_ss_release_complete),
    .dst_terminal_fault_i        (_sound_io_ss_terminal_fault),
    .dst_busy_o                  (),
    .dst_timeout_o               (saveStateSoundReleaseDestinationTimeout),
    .dst_source_reset_o          (),
    .dst_unsolicited_complete_o  (),
    .dst_protocol_fault_o        (
      saveStateSoundReleaseDestinationProtocolFault
    ),
    .dst_terminal_fault_o        (
      saveStateSoundReleaseDestinationFault
    ),
    .dst_debug_state_o           (
      saveStateSoundReleaseDestinationStateDebug
    ),
    .dst_debug_restore_hold_o    (
      saveStateSoundReleaseDestinationRestoreHoldDebug
    ),
    .dst_debug_command_valid_o   (
      saveStateSoundReleaseDestinationCommandValidDebug
    ),
    .dst_debug_command_o         (
      saveStateSoundReleaseDestinationCommandDebug
    )
  );

  CaveBanprestoSaveStateMetadata saveStateMetadata (
    .clk_i                        (clock),
    .reset_i                      (reset),
    .restore_begin_i              (saveStateControllerRestoreBegin),
    .current_game_id_i            ({4'd0, gameIndexReg}),
    .current_set_id_i             (saveStateCanonicalSetId),
    .current_rom_length_i         (saveStateRomLength),
    .current_rom_crc64_i          (saveStateRomCrc64),
    .current_support_i            (saveStateRuntimeSupport),
    .current_config_fingerprint_i (saveStateRuntimeConfig),
    .validation_complete_o        (
      saveStateMetadataValidationComplete
    ),
    .validation_valid_o           (saveStateMetadataValidationValid),
    .metadata_commit_o            (saveStateMetadataCommit),
    .metadata_committed_o         (saveStateMetadataCommitted),
    .ssbus                        (saveStateSystemBranches[0])
  );

  CaveBanprestoSystemStateOwner saveStateSystemOwner (
    .clk_i                                  (clock),
    .reset_i                                (reset),
    .state_enable_i                         (saveStateQuiesced),
    .restore_enable_i                       (
      saveStateCoordinatorMutationAuthorized
    ),
    .restore_begin_i                        (
      saveStateControllerRestoreBegin
    ),
    .restore_commit_i                       (
      saveStateCoordinatorSystemCommit
    ),
    .state_held_i                           (saveStateQuiesced),
    .ioctl_idle_i                           (saveStateIoctlIdle),
    .active_profile_i                       (gameIndexReg),
    .live_video_vblank_pipe1_i              (videoVBlankPipe1),
    .live_video_vblank_pipe2_i              (videoVBlankPipe2),
    .live_sprite_framebuffer_swap_primed_i  (
      spriteFrameBufferSwapPrimed
    ),
    .live_air_sprite_start_pending_i        (
      airGalletSpriteStartPending
    ),
    .live_air_sprite_frame_inflight_i       (
      airGalletSpriteFrameInFlight
    ),
    .live_met_sprite_bank_active_i          (
      metmqstrSpriteBankActive
    ),
    .live_met_sprite_bank_delay_i           (
      metmqstrSpriteBankDelay
    ),
    .live_game_index_i                      (gameIndexReg),
    .live_game_index_latched_i              (gameIndexReg_latched),
    .live_ioctl_download_history_i          (ioctlDownloadReg),
    .live_nvram_ioctl_din_history_i         (
      memSys_io_prog_nvram_ioctl_din_r
    ),
    .live_memsys_ioctl_download_history_i   (
      memSysIoctlDownloadReg
    ),
    .live_videosys_ioctl_download_history_i (
      videoSysIoctlDownloadReg
    ),
    .restore_apply_o                        (saveStateSystemRestoreApply),
    .restore_cdc_canonicalize_o             (
      saveStateSystemRestoreCdcLaunch
    ),
    .restore_video_vblank_pipe0_o           (
      saveStateSystemRestoreVideoVblankPipe0
    ),
    .restore_video_vblank_pipe1_o           (
      saveStateSystemRestoreVideoVblankPipe1
    ),
    .restore_video_vblank_pipe2_o           (
      saveStateSystemRestoreVideoVblankPipe2
    ),
    .restore_sprite_framebuffer_swap_primed_o(
      saveStateSystemRestoreSpriteSwapPrimed
    ),
    .restore_air_sprite_start_pending_o     (
      saveStateSystemRestoreAirStartPending
    ),
    .restore_air_sprite_frame_inflight_o    (
      saveStateSystemRestoreAirFrameInFlight
    ),
    .restore_met_sprite_bank_active_o       (
      saveStateSystemRestoreMetBankActive
    ),
    .restore_met_sprite_bank_delay_o        (
      saveStateSystemRestoreMetBankDelay
    ),
    .restore_game_index_o                   (
      saveStateSystemRestoreGameIndex
    ),
    .restore_game_index_latched_o           (
      saveStateSystemRestoreGameIndexLatched
    ),
    .restore_ioctl_download_history_o       (
      saveStateSystemRestoreIoctlDownload
    ),
    .restore_nvram_ioctl_din_history_o      (
      saveStateSystemRestoreNvramIoctlDin
    ),
    .restore_memsys_ioctl_download_history_o(
      saveStateSystemRestoreMemSysIoctlDownload
    ),
    .restore_videosys_ioctl_download_history_o(
      saveStateSystemRestoreVideoSysIoctlDownload
    ),
    .restore_game_index_cpu_load_toggle_o   (),
    .restore_game_index_cpu_toggle_sync0_o  (),
    .restore_game_index_cpu_toggle_sync1_o  (),
    .restore_game_index_cpu_toggle_seen_o   (),
    .restore_game_index_cpu_reg_o           (
      saveStateSystemRestoreGameIndexCpu
    ),
    .validation_complete_o                  (
      saveStateSystemOwnerValidationComplete
    ),
    .validation_valid_o                     (
      saveStateSystemOwnerValidationValid
    ),
    .write_complete_o                       (
      saveStateSystemOwnerWriteComplete
    ),
    .write_valid_o                          (
      saveStateSystemOwnerWriteValid
    ),
    .restore_committed_o                    (
      saveStateSystemOwnerCommitted
    ),
    .terminal_fault_o                       (
      saveStateSystemOwnerTerminalFault
    ),
    .owner_idle_o                           (saveStateSystemOwnerIdle),
    .ssbus                                  (saveStateSystemBranches[1])
  );

  CaveBanprestoSystemCpuRestoreCdc saveStateSystemCpuRestoreCdc (
    .src_clk_i                  (clock),
    .src_async_reset_i          (reset),
    .src_restore_load_i         (saveStateSystemRestoreCdcLaunch),
    .src_game_index_i           (saveStateSystemRestoreGameIndexCpu),
    .src_ready_o                (saveStateSystemCpuReady),
    .src_accepted_o             (saveStateSystemCpuAccepted),
    .src_complete_o             (saveStateSystemCpuComplete),
    .src_busy_o                 (saveStateSystemCpuBusy),
    .src_duplicate_request_o    (),
    .src_timeout_o              (),
    .src_destination_reset_o    (),
    .src_terminal_fault_o       (saveStateSystemCpuSourceFault),
    .dst_clk_i                  (cpuClock),
    .dst_async_reset_i          (cpuDomainReset),
    .dst_restore_load_o         (saveStateSystemCpuRestoreLoad),
    .dst_game_index_o           (saveStateSystemCpuRestoreGameIndex),
    .dst_restore_applied_i      (saveStateSystemCpuRestoreApplied),
    .dst_busy_o                 (saveStateSystemCpuDestinationBusy),
    .dst_unsolicited_applied_o  (),
    .dst_timeout_o              (),
    .dst_source_reset_o         (),
    .dst_terminal_fault_o       (
      saveStateSystemCpuDestinationFault
    )
  );

  CaveBanprestoVideoDipRestoreCdc saveStateVideoDipRestoreCdc (
    .src_clk_i                  (cpuClock),
    .src_async_reset_i          (cpuDomainReset),
    .src_restore_load_i         (saveStateMainRegisterRestoreLoad),
    .src_video_state_i          (saveStateMainVideoRestoreState),
    .src_dip_state_i            (saveStateMainDipRestoreState),
    .src_ready_o                (saveStateVideoDipSourceReady),
    .src_accepted_o             (),
    .src_complete_o             (saveStateVideoDipSourceComplete),
    .src_busy_o                 (saveStateVideoDipSourceBusy),
    .src_duplicate_request_o    (),
    .src_timeout_o              (),
    .src_destination_reset_o    (),
    .src_terminal_fault_o       (saveStateVideoDipSourceFault),
    .dst_clk_i                  (clock),
    .dst_async_reset_i          (reset),
    .dst_restore_load_o         (saveStateVideoDipRestoreLoad),
    .dst_video_state_o          (saveStateVideoDipRestoreVideo),
    .dst_dip_state_o            (saveStateVideoDipRestoreDip),
    .dst_restore_applied_i      (
      saveStateVideoRestoreApplied &
      saveStateDipRestoreApplied
    ),
    .dst_busy_o                 (saveStateVideoDipDestinationBusy),
    .dst_unsolicited_applied_o  (),
    .dst_timeout_o              (),
    .dst_source_reset_o         (),
    .dst_terminal_fault_o       (
      saveStateVideoDipDestinationFault
    )
  );

  CaveBanprestoSaveStateNvramOwner saveStateNvramOwner (
    .clk_i                (clock),
    .reset_i              (reset),
    .takeover_permitted_i (
      saveStateNvramSessionActive &
      saveStateNvramPrepared &
      saveStateQuiesced
    ),
    .abort_i              (saveStateNvramAbort),
    .mem_takeover_o       (saveStateNvramOwnerTakeover),
    .mem_rd_o             (saveStateNvramOwnerRd),
    .mem_wr_o             (saveStateNvramOwnerWr),
    .mem_addr_o           (saveStateNvramOwnerAddr),
    .mem_din_o            (saveStateNvramOwnerDin),
    .mem_dout_i           (saveStateNvramOwnerDout),
    .mem_wait_n_i         (saveStateNvramOwnerWaitN),
    .mem_valid_i          (saveStateNvramOwnerValid),
    .busy_o               (saveStateNvramOwnerBusy),
    .draining_o           (saveStateNvramOwnerDraining),
    .poisoned_o           (saveStateNvramOwnerPoisoned),
    .timeout_o            (saveStateNvramOwnerTimeout),
    .fatal_o              (saveStateNvramOwnerFatal),
    .fatal_reason_o       (saveStateNvramOwnerFatalReason),
    .ssbus                (saveStateSystemBranches[3])
  );

  // Every 2FF level synchronizer is launched directly by a register in the
  // source domain.  This prevents combinational idle/ready glitches from
  // becoming real destination-domain quiesce evidence.
  always @(posedge cpuClock) begin
    if (cpuDomainReset) begin
      saveStateMainCpuCapturedSource <= 1'b0;
      saveStateMainControlIdleSource <= 1'b0;
      saveStateMainRamIdleSource <= 1'b0;
      saveStateMainRegisterIdleSource <= 1'b0;
      saveStateMainEepromIdleSource <= 1'b0;
      saveStateMainRouterIdleSource <= 1'b0;
      saveStateSoundStoppedSource <= 1'b0;
      saveStateSoundIdleSource <= 1'b0;
      saveStateVideoDipReadySource <= 1'b0;
      saveStateMainCommandBusySource <= 1'b0;
      saveStateSoundCommandBusySource <= 1'b0;
    end
    else begin
      saveStateMainCpuCapturedSource <= saveStateMainCpuCaptured;
      saveStateMainControlIdleSource <= saveStateMainControlIdle;
      saveStateMainRamIdleSource <= saveStateMainRamIdle;
      saveStateMainRegisterIdleSource <= saveStateMainRegisterIdle;
      saveStateMainEepromIdleSource <= saveStateMainEepromIdle;
      saveStateMainRouterIdleSource <= saveStateMainRouterIdle;
      saveStateSoundStoppedSource <= _sound_io_ss_stopped;
      saveStateSoundIdleSource <= _sound_io_ss_idle;
      saveStateVideoDipReadySource <= saveStateVideoDipSourceReady;
      saveStateMainCommandBusySource <=
        saveStateCoordinatorMainCommandBusy;
      saveStateSoundCommandBusySource <=
        saveStateCoordinatorSoundCommandBusy;
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      saveStateRenderIdleSource <= 1'b0;
      saveStateSoundRomExternalIdleSource <= 1'b0;
      saveStateSoundRomDependenciesSource <= 1'b0;
      saveStateSoundRomFaultSource <= 1'b0;
      saveStateSoundFatalSource <= 1'b0;
    end
    else begin
      saveStateRenderIdleSource <= saveStateRenderIdleSystem;
      saveStateSoundRomExternalIdleSource <=
        soundRomSaveStateExternalIdle;
      saveStateSoundRomDependenciesSource <=
        soundRomSaveStateDependenciesReady;
      saveStateSoundRomFaultSource <=
        soundRomSaveStateTerminalFault;
      saveStateSoundFatalSource <=
        saveStateControllerFatal |
        saveStateQuiesceFatal |
        saveStateCoordinatorTerminalFault;
    end
  end

  CaveBanprestoSaveStateCdcBitSync saveStateMainCapturedSync (
    .clk_i   (clock),
    .reset_i (reset),
    .async_i (saveStateMainCpuCapturedSource),
    .sync_o  (saveStateMainCapturedSystem)
  );

  CaveBanprestoSaveStateCdcBitSync saveStateMainControlIdleSync (
    .clk_i   (clock),
    .reset_i (reset),
    .async_i (saveStateMainControlIdleSource),
    .sync_o  (saveStateMainControlIdleSystem)
  );

  CaveBanprestoSaveStateCdcBitSync saveStateMainRamIdleSync (
    .clk_i   (clock),
    .reset_i (reset),
    .async_i (saveStateMainRamIdleSource),
    .sync_o  (saveStateMainRamIdleSystem)
  );

  CaveBanprestoSaveStateCdcBitSync saveStateMainRegisterIdleSync (
    .clk_i   (clock),
    .reset_i (reset),
    .async_i (saveStateMainRegisterIdleSource),
    .sync_o  (saveStateMainRegisterIdleSystem)
  );

  CaveBanprestoSaveStateCdcBitSync saveStateMainEepromIdleSync (
    .clk_i   (clock),
    .reset_i (reset),
    .async_i (saveStateMainEepromIdleSource),
    .sync_o  (saveStateMainEepromIdleSystem)
  );

  CaveBanprestoSaveStateCdcBitSync saveStateMainRouterIdleSync (
    .clk_i   (clock),
    .reset_i (reset),
    .async_i (saveStateMainRouterIdleSource),
    .sync_o  (saveStateMainRouterIdleSystem)
  );

  CaveBanprestoSaveStateCdcBitSync saveStateSoundStoppedSync (
    .clk_i   (clock),
    .reset_i (reset),
    .async_i (saveStateSoundStoppedSource),
    .sync_o  (saveStateSoundStoppedSystem)
  );

  CaveBanprestoSaveStateCdcBitSync saveStateSoundIdleSync (
    .clk_i   (clock),
    .reset_i (reset),
    .async_i (saveStateSoundIdleSource),
    .sync_o  (saveStateSoundIdleSystem)
  );

  CaveBanprestoSaveStateCdcBitSync saveStateVideoDipReadySync (
    .clk_i   (clock),
    .reset_i (reset),
    .async_i (saveStateVideoDipReadySource),
    .sync_o  (saveStateVideoDipReadySystem)
  );

  CaveBanprestoSaveStateCdcBitSync saveStateMainCommandBusySync (
    .clk_i   (clock),
    .reset_i (reset),
    .async_i (saveStateMainCommandBusySource),
    .sync_o  (saveStateMainCommandBusySystem)
  );

  CaveBanprestoSaveStateCdcBitSync saveStateSoundCommandBusySync (
    .clk_i   (clock),
    .reset_i (reset),
    .async_i (saveStateSoundCommandBusySource),
    .sync_o  (saveStateSoundCommandBusySystem)
  );

  CaveBanprestoSaveStateCdcBitSync saveStateRenderIdleSync (
    .clk_i   (cpuClock),
    .reset_i (cpuDomainReset),
    .async_i (saveStateRenderIdleSource),
    .sync_o  (saveStateRenderIdleCpu)
  );

  CaveBanprestoSaveStateCdcBitSync saveStateSoundRomExternalIdleSync (
    .clk_i   (cpuClock),
    .reset_i (cpuDomainReset),
    .async_i (saveStateSoundRomExternalIdleSource),
    .sync_o  (saveStateSoundRomExternalIdleCpu)
  );

  CaveBanprestoSaveStateCdcBitSync saveStateSoundRomDependenciesSync (
    .clk_i   (cpuClock),
    .reset_i (cpuDomainReset),
    .async_i (saveStateSoundRomDependenciesSource),
    .sync_o  (saveStateSoundRomDependenciesCpu)
  );

  CaveBanprestoSaveStateCdcBitSync saveStateSoundRomFaultSync (
    .clk_i   (cpuClock),
    .reset_i (cpuDomainReset),
    .async_i (saveStateSoundRomFaultSource),
    .sync_o  (saveStateSoundRomFaultCpu)
  );

  CaveBanprestoSaveStateCdcBitSync saveStateSoundFatalSync (
    .clk_i   (cpuClock),
    .reset_i (cpuDomainReset),
    .async_i (saveStateSoundFatalSource),
    .sync_o  (saveStateSoundFatalCpu)
  );

  assign saveStateRenderIdleSystem =
    saveStateGpuIdle &
    saveStateSpriteFrameBufferIdle &
    saveStateSystemFrameBufferIdle &
    (&saveStateTileRomIdle);

  // The main CPU must retain program-ROM access until its architectural
  // capture has consumed the final ordinary fetch and reached the held bus
  // boundary. Actual captured state deliberately drops during CPU restore,
  // reopening the transport for the restore return fetch.
  assign saveStateProgramRomBlockNewWork =
    saveStateQuiesceBlockNewWork & saveStateMainCapturedSystem;

  // CPU capture can precede the EEPROM device's autonomous multi-beat drain.
  // Close this normal transport only after the complete stable-idle proof has
  // advanced Quiesce into its registered quiesced phase.
  assign saveStateEepromBlockNewWork = saveStateQuiesced;

  // Render producers first observe the global quiesce block and drain their
  // accepted queues.  Close the final DDR admission boundary only after every
  // producer on that path reports idle, avoiding a queue/fence circular wait.
  assign saveStateGameDdrBlockNewWork =
    saveStateQuiesceBlockNewWork & saveStateRenderIdleSystem;

  assign saveStateNvramSessionStart =
    saveStateQuiesceBlockNewWork &
    saveStateMainCapturedSystem &
    saveStateEepromFreezerIdle &
    !saveStateNvramSessionActive;
  assign saveStateNvramAbort =
    saveStateCoordinatorStreamAbort |
    saveStateQuiesceAbortActive;

  always @(posedge clock) begin
    if (reset)
      saveStateNvramSessionActive <= 1'b0;
    else if (saveStateNvramSessionStart)
      saveStateNvramSessionActive <= 1'b1;
    else if (saveStateNvramSessionActive &&
             !saveStateQuiesceBlockNewWork &&
             !saveStateNvramBusy &&
             !saveStateNvramOwnerBusy &&
             !saveStateNvramOwnerDraining)
      saveStateNvramSessionActive <= 1'b0;
  end

  assign saveStateSoundRomEarlyLaunchBlock =
    saveStateSoundRomLaunchBlock |
    (saveStateQuiesceSoundStopRequest &
     saveStateSoundStoppedSystem);
  assign saveStateSoundRomSlowProfile =
    gameIsHotdogStorm | gameIsMazinger;
  assign saveStateSoundRomAbortPrepareFire =
    saveStateCoordinatorStreamAbort &&
    !saveStateControllerFatal &&
    !saveStateQuiesceFatal &&
    !saveStateCoordinatorTerminalFault &&
    !saveStateInfrastructureFault &&
    saveStateSoundStoppedSystem &&
    soundRomSaveStateCanonicalIdle &&
    !saveStateSoundRomAbortPrepareIssued;
  assign saveStateSoundRomPrepare =
    saveStateCoordinatorSoundRelease |
    saveStateSoundRomAbortPrepareFire;
  assign saveStateSoundRomPrefetchRequired =
    saveStateSoundRomPrepare &
    saveStateSoundRomSlowProfile;

  always @(posedge clock) begin
    if (reset)
      saveStateSoundRomAbortPrepareIssued <= 1'b0;
    else if (soundRomSaveStateRearmed)
      saveStateSoundRomAbortPrepareIssued <= 1'b0;
    else if (saveStateSoundRomAbortPrepareFire)
      saveStateSoundRomAbortPrepareIssued <= 1'b1;
  end

  assign saveStateRegisterWriteFaultEvent =
    saveStateVideoBlockedWrite |
    saveStateDipBlockedWrite;

  always @(posedge clock) begin
    if (reset)
      saveStateRegisterWriteFault <= 1'b0;
    else if (saveStateRegisterWriteFaultEvent)
      saveStateRegisterWriteFault <= 1'b1;
  end

  assign saveStateInfrastructureFault =
    saveStateSystemRouterFault |
    saveStateMaintenanceTerminalFault |
    saveStateMainCdcSourceFault |
    saveStateSoundCdcSourceFault |
    saveStateMainReleaseSourceFault |
    saveStateSoundReleaseSourceFault |
    saveStateSystemOwnerTerminalFault |
    saveStateSystemCpuSourceFault |
    saveStateVideoDipDestinationFault |
    saveStateNvramOwnerFatal |
    saveStateNvramFatal |
    soundRomSaveStateTerminalFault |
    saveStateRegisterWriteFault;
  assign saveStateSystemCommitFault = saveStateInfrastructureFault;

  always @(posedge clock) begin
    if (reset) begin
      saveStateSystemCommitPending <= 1'b0;
      saveStateSystemCommitDone <= 1'b0;
    end
    else begin
      saveStateSystemCommitDone <= 1'b0;
      if (saveStateCoordinatorSystemCommit)
        saveStateSystemCommitPending <= 1'b1;
      if (saveStateSystemCommitPending &&
          saveStateMetadataCommitted &&
          saveStateSystemOwnerCommitted &&
          saveStateSystemCpuComplete) begin
        saveStateSystemCommitPending <= 1'b0;
        saveStateSystemCommitDone <= 1'b1;
      end
      else if (saveStateSystemCommitFault)
        saveStateSystemCommitPending <= 1'b0;
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      saveStateRomLoadPending <= 1'b0;
      saveStateMemSysProgDone <= 1'b0;
    end
    else begin
      saveStateMemSysProgDone <= 1'b0;
      if (!ioctl_download &&
          memSysIoctlDownloadReg &&
          ioctlRomIndexSelected)
        saveStateRomLoadPending <= 1'b1;
      if (saveStateRomLoadPending &&
          saveStateIdentityValid &&
          !saveStateIdentityBusy &&
          saveStateMaintenanceIdle) begin
        saveStateRomLoadPending <= 1'b0;
        saveStateMemSysProgDone <= 1'b1;
      end
    end
  end

  assign saveStateIdleAck[0] = saveStateGpuIdle;
  assign saveStateIdleAck[1] = saveStateSpriteFrameBufferIdle;
  assign saveStateIdleAck[2] = saveStateSystemFrameBufferIdle;
  assign saveStateIdleAck[3] = saveStateTileRomIdle[0];
  assign saveStateIdleAck[4] = saveStateTileRomIdle[1];
  assign saveStateIdleAck[5] = saveStateTileRomIdle[2];
  assign saveStateIdleAck[6] = saveStateProgramRomFreezerIdle;
  assign saveStateIdleAck[7] = saveStateEepromFreezerIdle;
  assign saveStateIdleAck[8] = saveStateSdramIdle;
  assign saveStateIdleAck[9] = _ddr_1_io_idle;
  assign saveStateIdleAck[10] = saveStateMaintenanceIdle;
  assign saveStateIdleAck[11] = !saveStateIdentityBusy;
  assign saveStateIdleAck[12] = !saveStateMaintenanceGranted;
  assign saveStateIdleAck[13] =
    saveStateNvramSessionActive & saveStateNvramPrepared;
  assign saveStateIdleAck[14] = !saveStateNvramBusy;
  assign saveStateIdleAck[15] =
    !saveStateNvramOwnerBusy & !saveStateNvramOwnerDraining;
  assign saveStateIdleAck[16] = saveStateSystemOwnerIdle;
  assign saveStateIdleAck[17] = saveStateSystemRouterIdle;
  assign saveStateIdleAck[18] = saveStateMainCdcReady;
  assign saveStateIdleAck[19] =
    !saveStateMainCdcBusy & !saveStateMainCdcDraining;
  assign saveStateIdleAck[20] = saveStateSoundCdcReady;
  assign saveStateIdleAck[21] =
    !saveStateSoundCdcBusy & !saveStateSoundCdcDraining;
  assign saveStateIdleAck[22] = saveStateSystemCpuReady;
  assign saveStateIdleAck[23] = !saveStateSystemCpuBusy;
  assign saveStateIdleAck[24] = saveStateVideoDipReadySystem;
  assign saveStateIdleAck[25] = !saveStateVideoDipDestinationBusy;
  assign saveStateIdleAck[26] = saveStateMainReleaseReady;
  assign saveStateIdleAck[27] = !saveStateMainReleaseBusy;
  assign saveStateIdleAck[28] = saveStateSoundReleaseReady;
  assign saveStateIdleAck[29] = !saveStateSoundReleaseBusy;
  assign saveStateIdleAck[30] = soundRomSaveStateCanonicalIdle;
  assign saveStateIdleAck[31] = saveStateCoordinatorMainStopped;
  assign saveStateIdleAck[32] = saveStateCoordinatorSoundStopped;
  assign saveStateIdleAck[33] = !saveStateMainCommandBusySystem;
  assign saveStateIdleAck[34] = !saveStateSoundCommandBusySystem;
  assign saveStateIdleAck[35] = saveStateMainControlIdleSystem;
  assign saveStateIdleAck[36] = saveStateMainRamIdleSystem;
  assign saveStateIdleAck[37] = saveStateMainRegisterIdleSystem;
  assign saveStateIdleAck[38] = saveStateMainEepromIdleSystem;
  assign saveStateIdleAck[39] = saveStateMainRouterIdleSystem;
  assign saveStateIdleAck[40] = saveStateSoundIdleSystem;

  always @(posedge cpuClock) begin
    saveStateSystemCpuRestoreApplied <= 1'b0;
    if (saveStateSystemCpuRestoreLoad) begin
      gameIndexCpuToggleSync0 <= 1'b0;
      gameIndexCpuToggleSync1 <= 1'b0;
      gameIndexCpuToggleSeen <= 1'b0;
      gameIndexCpuReg <= saveStateSystemCpuRestoreGameIndex;
      saveStateSystemCpuRestoreApplied <= 1'b1;
    end
    else begin
      gameIndexCpuToggleSync0 <= gameIndexCpuLoadToggle;
      gameIndexCpuToggleSync1 <= gameIndexCpuToggleSync0;
      if (gameIndexCpuToggleSync1 != gameIndexCpuToggleSeen) begin
        gameIndexCpuReg <= gameIndexReg;
        gameIndexCpuToggleSeen <= gameIndexCpuToggleSync1;
      end
    end
  end

  always @(posedge clock) begin
    // The controller and quiesce FSMs need a live vblank even while the
    // serialized architectural pipeline is held.  This observer is never
    // saved; it only supplies clean-boundary and clean-release timing.
    if (reset) begin
      videoVBlankObserverPipe0 <= 1'b0;
      videoVBlankObserverPipe1 <= 1'b0;
    end
    else begin
      videoVBlankObserverPipe0 <= _videoSys_io_video_vBlank;
      videoVBlankObserverPipe1 <= videoVBlankObserverPipe0;
    end

    // SpriteProcessor.frameReady is earlier than the physical framebuffer
    // write linearization point: the coalescing FIFO and DDR arbiter may still
    // own producer-page-tagged tail writes.  The queue therefore retains an
    // accepted-minus-physical-commit count.  For the
    // private Air-family reconstruction kick, latch that dedicated write-drain
    // proof after raw frameReady, then retain the actually accepted page swap
    // as the proof consumed by both the controller and SystemFramebuffer fence.
    if (reset | ~saveStateControllerReconstructionActive |
        saveStateControllerReconstructionStart) begin
      airGalletReconstructionDrainSeen <= 1'b0;
      airGalletReconstructionSpritePublished <= 1'b0;
    end
    else begin
      if (!airGalletReconstructionDrainSeen & gameIsAirFamily &
          airGalletSpriteFrameInFlight & _gpu_io_spriteCtrl_frameReady &
          saveStateSpriteFrameBufferWriteIdle)
        airGalletReconstructionDrainSeen <= 1'b1;
      if (gameIsAirFamily & saveStateSpriteFrameBufferSwapAccepted)
        airGalletReconstructionSpritePublished <= 1'b1;
    end

    // Owner 1 advertises state_held_i while quiesced, so every field in its
    // live word must actually remain immutable.  Keep normal architectural
    // evolution stopped from the admission fence through endpoint release.
    // Reset retains its pre-save-state priority and behavior.
    if (reset | ~saveStateQuiesceBlockNewWork) begin
      videoVBlankPipe0 <= _videoSys_io_video_vBlank;
      videoVBlankPipe1 <= videoVBlankPipe0;
      videoVBlankPipe2 <= videoVBlankPipe1;
      if (reset | ~_memSys_io_ready | ~spriteDelayedFrameSwap) begin
        spriteFrameBufferSwapPrimed <= 1'b0;
      end
      else begin
        if (spriteFrameBufferSwap)
          spriteFrameBufferSwapPrimed <= 1'b1;
      end
      if (reset | ~_memSys_io_ready | ~airFamilyPrivateSpriteCall) begin
        airGalletSpriteStartPending <= 1'b0;
        airGalletSpriteFrameInFlight <= 1'b0;
      end
      else begin
        // Only Air's normal inverted call may re-arm this tracker.  Sailor's
        // CPU-driven native swap is suppressed during reconstruction and must
        // not schedule a second private frame behind the forced one.
        if (gameIsAirGallet & mainSpriteFrameBufferSwapPulse)
          airGalletSpriteStartPending <= 1'b1;
        if (airGalletSpriteStart) begin
          airGalletSpriteStartPending <= 1'b0;
          airGalletSpriteFrameInFlight <= 1'b1;
        end
        if (airGalletSpriteSwapCompleted)
          airGalletSpriteFrameInFlight <= 1'b0;
      end
      if (optionGameIndexFallback)
        gameIndexReg <= options_gameIndex;
      else if (ioctlGameIndexWrite)
        gameIndexReg <= ioctl_dout[3:0];
      if (reset)
        gameIndexCpuLoadToggle <= 1'b0;
      else if (optionGameIndexFallback | ioctlGameIndexWrite)
        gameIndexCpuLoadToggle <= ~gameIndexCpuLoadToggle;
      ioctlDownloadReg <= ioctl_download;
      if (_memSys_io_prog_nvram_valid)
        memSys_io_prog_nvram_ioctl_din_r <=
          _memSys_io_prog_nvram_dout;
      memSysIoctlDownloadReg <= ioctl_download;
      videoSysIoctlDownloadReg <= ioctl_download;
      if (reset)
        gameIndexReg_latched <= 1'b0;
      else
        gameIndexReg_latched <=
          optionGameIndexFallback |
          ioctlGameIndexWrite |
          gameIndexReg_latched;
    end
    if (!reset && saveStateSystemRestoreApply) begin
      videoVBlankPipe0 <= saveStateSystemRestoreVideoVblankPipe0;
      videoVBlankPipe1 <= saveStateSystemRestoreVideoVblankPipe1;
      videoVBlankPipe2 <= saveStateSystemRestoreVideoVblankPipe2;
      spriteFrameBufferSwapPrimed <=
        saveStateSystemRestoreSpriteSwapPrimed;
      airGalletSpriteStartPending <=
        saveStateSystemRestoreAirStartPending;
      airGalletSpriteFrameInFlight <=
        saveStateSystemRestoreAirFrameInFlight;
      gameIndexReg <= saveStateSystemRestoreGameIndex;
      gameIndexReg_latched <=
        saveStateSystemRestoreGameIndexLatched;
      gameIndexCpuLoadToggle <= 1'b0;
      ioctlDownloadReg <= saveStateSystemRestoreIoctlDownload;
      memSys_io_prog_nvram_ioctl_din_r <=
        saveStateSystemRestoreNvramIoctlDin;
      memSysIoctlDownloadReg <=
        saveStateSystemRestoreMemSysIoctlDownload;
      videoSysIoctlDownloadReg <=
        saveStateSystemRestoreVideoSysIoctlDownload;
    end
    // Air Gallet normally needs a 68K write to arm its inverted sprite call;
    // Sailor Moon normally needs a CPU write to publish the rendered page.  A
    // paused checkpoint can issue neither after restore, while reconstruction
    // has canonicalized the derived sprite engine.  Start one fresh Air-family
    // frame from restored architectural RAM/registers.  Sailor returns to its
    // untouched native path as soon as reconstruction_active falls.
    if (!reset && saveStateControllerReconstructionStart && gameIsAirFamily) begin
      airGalletSpriteStartPending <= 1'b1;
      airGalletSpriteFrameInFlight <= 1'b0;
    end
  end // always @(posedge)

  // EEPROM writes and configured score-range writes share one MiSTer NVRAM
  // dirty indication. Clear it only when Main begins an index-2 upload; the
  // high-score manager clears its own dirty bit after its snapshot completes.
  always @(posedge clock) begin
    if (reset) begin
      nvramUploadReg <= 1'b0;
      eepromDirtyReg <= 1'b0;
    end else begin
      nvramUploadReg <= ioctl_upload & ioctlNvramIndexSelected;
      if ((ioctl_upload & ioctlNvramIndexSelected) & ~nvramUploadReg)
        eepromDirtyReg <= 1'b0;
      if (_memSys_io_eeprom_wr)
        eepromDirtyReg <= 1'b1;
    end
  end

  assign dipsRegsWr =
    ioctl_download & ioctl_index == 8'hFE & ioctl_addr[26:3] == 24'h0 & ioctl_wr;
  assign dipsRegsAddr = ioctl_addr[2:1];
  CaveBanprestoDipRegisterFile dipsRegs (
    .clock                     (clock),
    .reset                     (reset),
    .io_mem_wr                 (dipsRegsWr),
    .io_mem_addr               (dipsRegsAddr),
    .io_mem_din                (ioctl_dout),
    .ss_hold_i                 (saveStateQuiesceBlockNewWork),
    .ss_restore_load_i         (saveStateVideoDipRestoreLoad),
    .ss_state_i                (saveStateVideoDipRestoreDip),
    .ss_state_o                (saveStateDipLiveState),
    .ss_blocked_normal_write_o (saveStateDipBlockedWrite),
    .ss_restore_applied_o      (saveStateDipRestoreApplied),
    .io_regs_0                 (_dipsRegs_io_regs_0)
  );
  DDR ddr_1 (
    .clock              (clock),
    .reset              (reset),
    .io_block_new_requests(saveStateGameDdrBlockNewWork),
    .io_mem_rd          (_ddr_1_io_mem_rd),
    .io_mem_wr          (_ddr_1_io_mem_wr),
    .io_mem_addr        (_ddr_1_io_mem_addr),
    .io_mem_mask        (_ddr_1_io_mem_mask),
    .io_mem_din         (_ddr_1_io_mem_din),
    .io_mem_dout        (_ddr_1_io_mem_dout),
    .io_mem_wait_n      (_ddr_1_io_mem_wait_n),
    .io_mem_valid       (_ddr_1_io_mem_valid),
    .io_mem_burstLength (_ddr_1_io_mem_burstLength),
    .io_mem_burstDone   (_ddr_1_io_mem_burstDone),
    .io_ddr_rd          (saveStateGameDdrRd),
    .io_ddr_wr          (saveStateGameDdrWr),
    .io_ddr_addr        (saveStateGameDdrAddr),
    .io_ddr_mask        (saveStateGameDdrMask),
    .io_ddr_din         (saveStateGameDdrDin),
    .io_ddr_dout        (saveStateGameDdrDout),
    .io_ddr_wait_n      (saveStateGameDdrWaitN),
    .io_ddr_valid       (saveStateGameDdrValid),
    .io_ddr_burstLength (saveStateGameDdrBurst),
    .io_idle            (_ddr_1_io_idle)
  );
  SDRAM sdram_1 (
    .clock            (clock),
    .reset            (reset),
    .io_mem_rd        (_sdram_1_io_mem_rd),
    .io_mem_wr        (_sdram_1_io_mem_wr),
    .io_mem_addr      (_sdram_1_io_mem_addr),
    .io_mem_din       (_sdram_1_io_mem_din),
    .io_mem_dout      (_sdram_1_io_mem_dout),
    .io_mem_wait_n    (_sdram_1_io_mem_wait_n),
    .io_mem_valid     (_sdram_1_io_mem_valid),
    .io_mem_burstDone (_sdram_1_io_mem_burstDone),
    .io_idle          (saveStateSdramIdle),
    .io_sdram_cs_n    (sdram_cs_n),
    .io_sdram_ras_n   (sdram_ras_n),
    .io_sdram_cas_n   (sdram_cas_n),
    .io_sdram_we_n    (sdram_we_n),
    .io_sdram_oe_n    (sdram_oe_n),
    .io_sdram_bank    (sdram_bank),
    .io_sdram_addr    (sdram_addr),
    .io_sdram_din     (sdram_din),
    .io_sdram_dout    (sdram_dout)
  );
  assign _memSys_io_prog_rom_wr = memSys_io_prog_rom_writeEnable & ioctl_wr;
  assign _memSys_io_prog_nvram_rd = memSys_io_prog_nvram_readEnable & ioctl_rd;
  assign _memSys_io_prog_nvram_wr = memSys_io_prog_nvram_writeEnable & ioctl_wr;
  assign _memSys_io_prog_done = saveStateMemSysProgDone;
  MemSys memSys (
    .clock                            (clock),
    .reset                            (reset),
    .io_gameIndex                     (gameIndexReg),
    .io_gameConfig_eepromOffset       (gameConfig_eepromOffset),
    .io_gameConfig_sound_0_romOffset  (gameConfig_sound_0_romOffset),
    .io_gameConfig_sound_1_romOffset  (gameConfig_sound_1_romOffset),
    .io_gameConfig_sound_2_romOffset  (gameConfig_sound_2_romOffset),
    .io_gameConfig_layer_0_romOffset  (gameConfig_layer_0_romOffset),
    .io_gameConfig_layer_1_romOffset  (gameConfig_layer_1_romOffset),
    .io_gameConfig_layer_2_romOffset  (gameConfig_layer_2_romOffset),
    .io_gameConfig_sprite_romOffset   (gameConfig_sprite_romOffset),
    .io_prog_rom_wr                   (_memSys_io_prog_rom_wr),
    .io_prog_rom_addr                 (ioctl_addr),
    .io_prog_rom_din                  (ioctl_dout),
    .io_prog_rom_wait_n               (_memSys_io_prog_rom_wait_n),
    .io_prog_nvram_rd                 (_memSys_io_prog_nvram_rd),
    .io_prog_nvram_wr                 (_memSys_io_prog_nvram_wr),
    .io_prog_nvram_addr               (ioctl_addr),
    .io_prog_nvram_din                (ioctl_dout),
    .io_prog_nvram_dout               (_memSys_io_prog_nvram_dout),
    .io_prog_nvram_wait_n             (_memSys_io_prog_nvram_wait_n),
    .io_prog_nvram_valid              (_memSys_io_prog_nvram_valid),
    .io_prog_done                     (_memSys_io_prog_done),
    .io_progRom_rd                    (_memSys_io_progRom_rd),
    .io_progRom_addr                  (_memSys_io_progRom_addr),
    .io_progRom_dout                  (_memSys_io_progRom_dout),
    .io_progRom_wait_n                (_memSys_io_progRom_wait_n),
    .io_progRom_valid                 (_memSys_io_progRom_valid),
    .io_eeprom_rd                     (_memSys_io_eeprom_rd),
    .io_eeprom_wr                     (_memSys_io_eeprom_wr),
    .io_eeprom_addr                   (_memSys_io_eeprom_addr),
    .io_eeprom_din                    (_memSys_io_eeprom_din),
    .io_eeprom_dout                   (_memSys_io_eeprom_dout),
    .io_eeprom_wait_n                 (_memSys_io_eeprom_wait_n),
    .io_eeprom_valid                  (_memSys_io_eeprom_valid),
    .io_ss_nvram_session_active       (
      saveStateNvramSessionActive
    ),
    .io_ss_nvram_abort                (saveStateNvramAbort),
    .io_ss_nvram_rd                   (saveStateNvramOwnerRd),
    .io_ss_nvram_wr                   (saveStateNvramOwnerWr),
    .io_ss_nvram_addr                 (saveStateNvramOwnerAddr),
    .io_ss_nvram_din                  (saveStateNvramOwnerDin),
    .io_ss_nvram_dout                 (saveStateNvramOwnerDout),
    .io_ss_nvram_wait_n               (saveStateNvramOwnerWaitN),
    .io_ss_nvram_valid                (saveStateNvramOwnerValid),
    .io_ss_nvram_prepared             (saveStateNvramPrepared),
    .io_ss_nvram_busy                 (saveStateNvramBusy),
    .io_ss_nvram_flush_done           (saveStateNvramFlushDone),
    .io_ss_nvram_timeout              (saveStateNvramTimeout),
    .io_ss_nvram_fatal                (saveStateNvramFatal),
    .io_ss_nvram_fatal_reason         (saveStateNvramFatalReason),
    .io_soundRom_0_rd                 (_memSys_io_soundRom_0_rd),
    .io_soundRom_0_addr               (_memSys_io_soundRom_0_addr),
    .io_soundRom_0_dout               (_memSys_io_soundRom_0_dout),
    .io_soundRom_0_wait_n             (_memSys_io_soundRom_0_wait_n),
    .io_soundRom_0_valid              (_memSys_io_soundRom_0_valid),
    .io_soundRom_1_rd                 (_memSys_io_soundRom_1_rd),
    .io_soundRom_1_addr               (_memSys_io_soundRom_1_addr),
    .io_soundRom_1_dout               (_memSys_io_soundRom_1_dout),
    .io_soundRom_1_wait_n             (_memSys_io_soundRom_1_wait_n),
    .io_soundRom_1_valid              (_memSys_io_soundRom_1_valid),
    .io_soundRom_2_rd                 (_memSys_io_soundRom_2_rd),
    .io_soundRom_2_addr               (_memSys_io_soundRom_2_addr),
    .io_soundRom_2_dout               (_memSys_io_soundRom_2_dout),
    .io_soundRom_2_wait_n             (_memSys_io_soundRom_2_wait_n),
    .io_soundRom_2_valid              (_memSys_io_soundRom_2_valid),
    .io_layerTileRom_0_rd             (_memSys_io_layerTileRom_0_rd),
    .io_layerTileRom_0_addr           (_memSys_io_layerTileRom_0_addr),
    .io_layerTileRom_0_dout           (_memSys_io_layerTileRom_0_dout),
    .io_layerTileRom_0_wait_n         (_memSys_io_layerTileRom_0_wait_n),
    .io_layerTileRom_0_valid          (_memSys_io_layerTileRom_0_valid),
    .io_layerTileRom_1_rd             (_memSys_io_layerTileRom_1_rd),
    .io_layerTileRom_1_addr           (_memSys_io_layerTileRom_1_addr),
    .io_layerTileRom_1_dout           (_memSys_io_layerTileRom_1_dout),
    .io_layerTileRom_1_wait_n         (_memSys_io_layerTileRom_1_wait_n),
    .io_layerTileRom_1_valid          (_memSys_io_layerTileRom_1_valid),
    .io_layerTileRom_2_rd             (_memSys_io_layerTileRom_2_rd),
    .io_layerTileRom_2_addr           (_memSys_io_layerTileRom_2_addr),
    .io_layerTileRom_2_dout           (_memSys_io_layerTileRom_2_dout),
    .io_layerTileRom_2_wait_n         (_memSys_io_layerTileRom_2_wait_n),
    .io_layerTileRom_2_valid          (_memSys_io_layerTileRom_2_valid),
    .io_spriteTileRom_rd              (_memSys_io_spriteTileRom_rd),
    .io_spriteTileRom_addr            (_memSys_io_spriteTileRom_addr),
    .io_spriteTileRom_dout            (_memSys_io_spriteTileRom_dout),
    .io_spriteTileRom_wait_n          (_memSys_io_spriteTileRom_wait_n),
    .io_spriteTileRom_valid           (_memSys_io_spriteTileRom_valid),
    .io_spriteTileRom_burstLength     (_memSys_io_spriteTileRom_burstLength),
    .io_spriteTileRom_burstDone       (_memSys_io_spriteTileRom_burstDone),
    .io_ddr_rd                        (_ddr_1_io_mem_rd),
    .io_ddr_wr                        (_ddr_1_io_mem_wr),
    .io_ddr_addr                      (_ddr_1_io_mem_addr),
    .io_ddr_mask                      (_ddr_1_io_mem_mask),
    .io_ddr_din                       (_ddr_1_io_mem_din),
    .io_ddr_dout                      (_ddr_1_io_mem_dout),
    .io_ddr_wait_n                    (_ddr_1_io_mem_wait_n),
    .io_ddr_valid                     (_ddr_1_io_mem_valid),
    .io_ddr_burstLength               (_ddr_1_io_mem_burstLength),
    .io_ddr_burstDone                 (_ddr_1_io_mem_burstDone),
    .io_sdram_rd                      (_sdram_1_io_mem_rd),
    .io_sdram_wr                      (_sdram_1_io_mem_wr),
    .io_sdram_addr                    (_sdram_1_io_mem_addr),
    .io_sdram_din                     (_sdram_1_io_mem_din),
    .io_sdram_dout                    (_sdram_1_io_mem_dout),
    .io_sdram_wait_n                  (_sdram_1_io_mem_wait_n),
    .io_sdram_valid                   (_sdram_1_io_mem_valid),
    .io_sdram_burstDone               (_sdram_1_io_mem_burstDone),
    .io_spriteFrameBuffer_rd          (_memSys_io_spriteFrameBuffer_rd),
    .io_spriteFrameBuffer_wr          (_memSys_io_spriteFrameBuffer_wr),
    .io_spriteFrameBuffer_addr        (_memSys_io_spriteFrameBuffer_addr),
    .io_spriteFrameBuffer_mask        (_memSys_io_spriteFrameBuffer_mask),
    .io_spriteFrameBuffer_din         (_memSys_io_spriteFrameBuffer_din),
    .io_spriteFrameBuffer_dout        (_memSys_io_spriteFrameBuffer_dout),
    .io_spriteFrameBuffer_wait_n      (_memSys_io_spriteFrameBuffer_wait_n),
    .io_spriteFrameBuffer_valid       (_memSys_io_spriteFrameBuffer_valid),
    .io_spriteFrameBuffer_burstLength (_memSys_io_spriteFrameBuffer_burstLength),
    .io_spriteFrameBuffer_burstDone   (_memSys_io_spriteFrameBuffer_burstDone),
    .io_systemFrameBuffer_wr          (_memSys_io_systemFrameBuffer_wr),
    .io_systemFrameBuffer_addr        (_memSys_io_systemFrameBuffer_addr),
    .io_systemFrameBuffer_mask        (_memSys_io_systemFrameBuffer_mask),
    .io_systemFrameBuffer_din         (_memSys_io_systemFrameBuffer_din),
    .io_systemFrameBuffer_wait_n      (_memSys_io_systemFrameBuffer_wait_n),
    .io_ready                         (_memSys_io_ready)
  );
  assign _videoSys_io_prog_video_wr = videoSys_io_prog_video_writeEnable & ioctl_wr;
  assign _videoSys_io_prog_done =
    ~ioctl_download & videoSysIoctlDownloadReg & ioctlVideoIndexSelected;
  VideoSys videoSys (
    .clock                      (clock),
    .reset                      (reset),
    .io_videoClock              (videoClock),
    .io_videoReset              (videoReset),
    .io_prog_video_wr           (_videoSys_io_prog_video_wr),
    .io_prog_video_addr         (ioctl_addr),
    .io_prog_video_din          (ioctl_dout),
    .io_prog_done               (_videoSys_io_prog_done),
    .io_options_offset_x        (options_offset_x),
    .io_options_offset_y        (options_offset_y),
    .io_options_compatibility   (effectiveCompatibilityTiming),
    .io_options_wideTiming      (gameIsHotdogStorm | gameIsMazinger | gameIsMetmqstr),
    .io_video_clockEnable       (_videoSys_io_video_clockEnable),
    .io_video_displayEnable     (_videoSys_io_video_displayEnable),
    .io_video_pos_x             (_videoSys_io_video_pos_x),
    .io_video_pos_y             (_videoSys_io_video_pos_y),
    .io_video_hSync             (video_hSync),
    .io_video_vSync             (video_vSync),
    .io_video_hBlank            (_videoSys_io_video_hBlank),
    .io_video_vBlank            (_videoSys_io_video_vBlank),
    .io_video_regs_size_x       (_videoSys_io_video_regs_size_x),
    .io_video_regs_size_y       (_videoSys_io_video_regs_size_y),
    .io_video_regs_frontPorch_x (video_regs_frontPorch_x),
    .io_video_regs_frontPorch_y (video_regs_frontPorch_y),
    .io_video_regs_retrace_x    (video_regs_retrace_x),
    .io_video_regs_retrace_y    (video_regs_retrace_y),
    .io_video_changeMode        (video_changeMode),
    .io_ss_hold                 (saveStateQuiesceBlockNewWork),
    .io_ss_restore_load         (saveStateVideoDipRestoreLoad),
    .io_ss_restore_state        (saveStateVideoDipRestoreVideo),
    .io_ss_state                (saveStateVideoLiveState),
    .io_ss_blocked_normal_write (saveStateVideoBlockedWrite),
    .io_ss_restore_applied      (saveStateVideoRestoreApplied)
  );
  Main main (
    .clock                                  (cpuClock),
    .reset                                  (cpuDomainReset),
    .io_systemClock                         (clock),
    .io_systemReset                         (reset),
    .io_videoClock                          (videoClock),
    .io_spriteClock                         (clock),
    .io_gameIndex                           (gameIndexCpuReg),
    .io_options_service                     (options_service),
    .io_player_0_up                         (player_0_up),
    .io_player_0_down                       (player_0_down),
    .io_player_0_left                       (player_0_left),
    .io_player_0_right                      (player_0_right),
    .io_player_0_buttons                    (player_0_buttons),
    .io_player_0_start                      (player_0_start),
    .io_player_0_coin                       (player_0_coin),
    .io_player_0_pause                      (player_0_pause),
    .io_player_1_up                         (player_1_up),
    .io_player_1_down                       (player_1_down),
    .io_player_1_left                       (player_1_left),
    .io_player_1_right                      (player_1_right),
    .io_player_1_buttons                    (player_1_buttons),
    .io_player_1_start                      (player_1_start),
    .io_player_1_coin                       (player_1_coin),
    .io_player_1_pause                      (player_1_pause),
    .io_dips_0                              (_dipsRegs_io_regs_0),
    .io_video_vBlank                        (_videoSys_io_video_vBlank),
    .io_gpuMem_layer_0_regs_tileSize        (_main_io_gpuMem_layer_0_regs_tileSize),
    .io_gpuMem_layer_0_regs_enable          (_main_io_gpuMem_layer_0_regs_enable),
    .io_gpuMem_layer_0_regs_flipX           (_main_io_gpuMem_layer_0_regs_flipX),
    .io_gpuMem_layer_0_regs_flipY           (_main_io_gpuMem_layer_0_regs_flipY),
    .io_gpuMem_layer_0_regs_rowScrollEnable
      (_main_io_gpuMem_layer_0_regs_rowScrollEnable),
    .io_gpuMem_layer_0_regs_rowSelectEnable
      (_main_io_gpuMem_layer_0_regs_rowSelectEnable),
    .io_gpuMem_layer_0_regs_priority        (_main_io_gpuMem_layer_0_regs_priority),
    .io_gpuMem_layer_0_regs_scroll_x        (_main_io_gpuMem_layer_0_regs_scroll_x),
    .io_gpuMem_layer_0_regs_scroll_y        (_main_io_gpuMem_layer_0_regs_scroll_y),
    .io_gpuMem_layer_0_vram8x8_addr         (_main_io_gpuMem_layer_0_vram8x8_addr),
    .io_gpuMem_layer_0_vram8x8_dout         (_main_io_gpuMem_layer_0_vram8x8_dout),
    .io_gpuMem_layer_0_vram16x16_addr       (_main_io_gpuMem_layer_0_vram16x16_addr),
    .io_gpuMem_layer_0_vram16x16_dout       (_main_io_gpuMem_layer_0_vram16x16_dout),
    .io_gpuMem_layer_0_lineRam_addr         (_main_io_gpuMem_layer_0_lineRam_addr),
    .io_gpuMem_layer_0_lineRam_dout         (_main_io_gpuMem_layer_0_lineRam_dout),
    .io_gpuMem_layer_1_regs_tileSize        (_main_io_gpuMem_layer_1_regs_tileSize),
    .io_gpuMem_layer_1_regs_enable          (_main_io_gpuMem_layer_1_regs_enable),
    .io_gpuMem_layer_1_regs_flipX           (_main_io_gpuMem_layer_1_regs_flipX),
    .io_gpuMem_layer_1_regs_flipY           (_main_io_gpuMem_layer_1_regs_flipY),
    .io_gpuMem_layer_1_regs_rowScrollEnable
      (_main_io_gpuMem_layer_1_regs_rowScrollEnable),
    .io_gpuMem_layer_1_regs_rowSelectEnable
      (_main_io_gpuMem_layer_1_regs_rowSelectEnable),
    .io_gpuMem_layer_1_regs_priority        (_main_io_gpuMem_layer_1_regs_priority),
    .io_gpuMem_layer_1_regs_scroll_x        (_main_io_gpuMem_layer_1_regs_scroll_x),
    .io_gpuMem_layer_1_regs_scroll_y        (_main_io_gpuMem_layer_1_regs_scroll_y),
    .io_gpuMem_layer_1_vram8x8_addr         (_main_io_gpuMem_layer_1_vram8x8_addr),
    .io_gpuMem_layer_1_vram8x8_dout         (_main_io_gpuMem_layer_1_vram8x8_dout),
    .io_gpuMem_layer_1_vram16x16_addr       (_main_io_gpuMem_layer_1_vram16x16_addr),
    .io_gpuMem_layer_1_vram16x16_dout       (_main_io_gpuMem_layer_1_vram16x16_dout),
    .io_gpuMem_layer_1_lineRam_addr         (_main_io_gpuMem_layer_1_lineRam_addr),
    .io_gpuMem_layer_1_lineRam_dout         (_main_io_gpuMem_layer_1_lineRam_dout),
    .io_gpuMem_layer_2_regs_tileSize        (_main_io_gpuMem_layer_2_regs_tileSize),
    .io_gpuMem_layer_2_regs_enable          (_main_io_gpuMem_layer_2_regs_enable),
    .io_gpuMem_layer_2_regs_flipX           (_main_io_gpuMem_layer_2_regs_flipX),
    .io_gpuMem_layer_2_regs_flipY           (_main_io_gpuMem_layer_2_regs_flipY),
    .io_gpuMem_layer_2_regs_rowScrollEnable
      (_main_io_gpuMem_layer_2_regs_rowScrollEnable),
    .io_gpuMem_layer_2_regs_rowSelectEnable
      (_main_io_gpuMem_layer_2_regs_rowSelectEnable),
    .io_gpuMem_layer_2_regs_priority        (_main_io_gpuMem_layer_2_regs_priority),
    .io_gpuMem_layer_2_regs_scroll_x        (_main_io_gpuMem_layer_2_regs_scroll_x),
    .io_gpuMem_layer_2_regs_scroll_y        (_main_io_gpuMem_layer_2_regs_scroll_y),
    .io_gpuMem_layer_2_vram8x8_addr         (_main_io_gpuMem_layer_2_vram8x8_addr),
    .io_gpuMem_layer_2_vram8x8_dout         (_main_io_gpuMem_layer_2_vram8x8_dout),
    .io_gpuMem_layer_2_vram16x16_addr       (_main_io_gpuMem_layer_2_vram16x16_addr),
    .io_gpuMem_layer_2_vram16x16_dout       (_main_io_gpuMem_layer_2_vram16x16_dout),
    .io_gpuMem_layer_2_lineRam_addr         (_main_io_gpuMem_layer_2_lineRam_addr),
    .io_gpuMem_layer_2_lineRam_dout         (_main_io_gpuMem_layer_2_lineRam_dout),
    .io_gpuMem_sprite_regs_offset_x         (_main_io_gpuMem_sprite_regs_offset_x),
    .io_gpuMem_sprite_regs_offset_y         (_main_io_gpuMem_sprite_regs_offset_y),
    .io_gpuMem_sprite_regs_bank             (_main_io_gpuMem_sprite_regs_bank),
    .io_gpuMem_sprite_regs_fixed            (_main_io_gpuMem_sprite_regs_fixed),
    .io_gpuMem_sprite_regs_hFlip            (_main_io_gpuMem_sprite_regs_hFlip),
    .io_gpuMem_sprite_vram_rd               (_main_io_gpuMem_sprite_vram_rd),
    .io_gpuMem_sprite_vram_addr             (_main_io_gpuMem_sprite_vram_addr),
    .io_gpuMem_sprite_vram_dout             (_main_io_gpuMem_sprite_vram_dout),
    .io_gpuMem_paletteRam_addr              (_main_io_gpuMem_paletteRam_addr),
    .io_gpuMem_paletteRam_dout              (_main_io_gpuMem_paletteRam_dout),
    .io_soundCtrl_oki_0_wr                  (_main_io_soundCtrl_oki_0_wr),
    .io_soundCtrl_oki_0_din                 (_main_io_soundCtrl_oki_0_din),
    .io_soundCtrl_oki_0_dout                (_main_io_soundCtrl_oki_0_dout),
    .io_soundCtrl_oki_1_wr                  (_main_io_soundCtrl_oki_1_wr),
    .io_soundCtrl_oki_1_din                 (_main_io_soundCtrl_oki_1_din),
    .io_soundCtrl_oki_1_dout                (_main_io_soundCtrl_oki_1_dout),
    .io_soundCtrl_nmk_wr                    (_main_io_soundCtrl_nmk_wr),
    .io_soundCtrl_nmk_addr                  (_main_io_soundCtrl_nmk_addr),
    .io_soundCtrl_nmk_din                   (_main_io_soundCtrl_nmk_din),
    .io_soundCtrl_ymz_rd                    (_main_io_soundCtrl_ymz_rd),
    .io_soundCtrl_ymz_wr                    (_main_io_soundCtrl_ymz_wr),
    .io_soundCtrl_ymz_addr                  (_main_io_soundCtrl_ymz_addr),
    .io_soundCtrl_ymz_din                   (_main_io_soundCtrl_ymz_din),
    .io_soundCtrl_ymz_dout                  (_main_io_soundCtrl_ymz_dout),
    .io_soundCtrl_req                       (_main_io_soundCtrl_req),
    .io_soundCtrl_data                      (_main_io_soundCtrl_data),
    .io_soundCtrl_reply_rd                  (_main_io_soundCtrl_reply_rd),
    .io_soundCtrl_reply                     (_main_io_soundCtrl_reply),
    .io_soundCtrl_reply_empty               (_main_io_soundCtrl_reply_empty),
    .io_soundCtrl_irq                       (_main_io_soundCtrl_irq),
    .io_progRom_rd                          (_main_io_progRom_rd),
    .io_progRom_addr                        (_main_io_progRom_addr),
    .io_progRom_dout                        (_main_io_progRom_dout),
    .io_progRom_valid                       (_main_io_progRom_valid),
    .io_eeprom_rd                           (_main_io_eeprom_rd),
    .io_eeprom_wr                           (_main_io_eeprom_wr),
    .io_eeprom_addr                         (_main_io_eeprom_addr),
    .io_eeprom_din                          (_main_io_eeprom_din),
    .io_eeprom_dout                         (_main_io_eeprom_dout),
    .io_eeprom_wait_n                       (_main_io_eeprom_wait_n),
    .io_eeprom_valid                        (_main_io_eeprom_valid),
    .io_hs_config_download                  (
      ioctl_download & ioctlHighScoreConfigSelected
    ),
    .io_hs_config_wr                        (ioctl_wr),
    .io_hs_config_addr                      (ioctl_addr),
    .io_hs_config_dout                      (ioctl_dout),
    .io_hs_game_index_sys                   (gameIndexReg),
    .io_hs_nvram_download                   (
      ioctl_download & ioctlNvramIndexSelected
    ),
    .io_hs_nvram_upload                     (
      ioctl_upload & ioctlNvramIndexSelected
    ),
    .io_hs_nvram_rd                         (ioctl_rd),
    .io_hs_nvram_wr                         (ioctl_wr),
    .io_hs_nvram_addr                       (ioctl_addr),
    .io_hs_nvram_dout                       (ioctl_dout),
    .io_hs_nvram_din                        (_main_io_hs_nvram_din),
    .io_hs_nvram_wait_n                     (_main_io_hs_nvram_wait_n),
    .io_hs_dirty                            (_main_io_hs_dirty),
    .io_hs_active                           (_main_io_hs_active),
    .io_ss_command_valid                    (
      saveStateCoordinatorMainCommandValid
    ),
    .io_ss_command                          (
      saveStateCoordinatorMainCommand
    ),
    .io_ss_command_complete                 (
      saveStateMainCommandComplete
    ),
    .io_ss_command_response                 (
      saveStateMainCommandResponse
    ),
    .io_ss_command_terminal_fault           (
      saveStateMainCommandTerminalFault
    ),
    .io_ss_release_request                  (
      saveStateMainReleaseRequestCpu
    ),
    .io_ss_release_restore                  (
      saveStateMainReleaseRestoreCpu
    ),
    .io_ss_stopped                          (saveStateMainStopped),
    .io_ss_abort_ack                        (saveStateMainAbortAck),
    .io_ss_release_complete                 (
      saveStateMainReleaseCompleteCpu
    ),
    .io_ss_state_enable                     (1'b0),
    .io_ss_restore_enable                   (1'b0),
    .io_ss_restore_begin                    (1'b0),
    .io_ss_restore_commit                   (1'b0),
    .io_ss_cpu_capture_req                  (1'b0),
    .io_ss_cpu_restore_begin                (1'b0),
    .io_ss_cpu_restore_commit               (1'b0),
    .io_ss_cpu_abort                        (1'b0),
    .io_ss_cpu_captured                     (saveStateMainCpuCaptured),
    .io_ss_cpu_restore_committed            (
      saveStateMainCpuCommitted
    ),
    .io_ss_cpu_abort_ack                    (saveStateMainCpuAbortAck),
    .io_ss_cpu_terminal_fault               (
      saveStateMainCpuTerminalFault
    ),
    .io_ss_cpu_idle                         (1'b0),
    .io_ss_render_idle                      (saveStateRenderIdleCpu),
    .io_ss_runtime_support                  (saveStateRuntimeSupport),
    .io_ss_control_idle                     (saveStateMainControlIdle),
    .io_ss_control_restore_committed        (
      saveStateMainControlCommitted
    ),
    .io_ss_control_terminal_fault           (
      saveStateMainControlTerminalFault
    ),
    .io_ss_ram_idle                         (saveStateMainRamIdle),
    .io_ss_ram_terminal_fault               (
      saveStateMainRamTerminalFault
    ),
    .io_ss_ram_takeover_active              (saveStateMainRamTakeover),
    .io_ss_ram_blocked_access               (saveStateMainRamBlocked),
    .io_ss_video_register_state             (saveStateVideoLiveState),
    .io_ss_config_offset_x                  (saveStateRuntimeConfig[3:0]),
    .io_ss_config_offset_y                  (saveStateRuntimeConfig[7:4]),
    .io_ss_config_rotate                    (saveStateRuntimeConfig[8]),
    .io_ss_config_compatibility             (
      saveStateRuntimeConfig[9]
    ),
    .io_ss_config_layer0_enable             (
      saveStateRuntimeConfig[10]
    ),
    .io_ss_config_layer1_enable             (
      saveStateRuntimeConfig[11]
    ),
    .io_ss_config_layer2_enable             (
      saveStateRuntimeConfig[12]
    ),
    .io_ss_config_sprite_enable             (
      saveStateRuntimeConfig[13]
    ),
    .io_ss_config_flip_video                (
      saveStateRuntimeConfig[14]
    ),
    .io_ss_config_psg_boost                 (
      saveStateRuntimeConfig[18:15]
    ),
    .io_ss_config_fm_boost                  (
      saveStateRuntimeConfig[22:19]
    ),
    .io_ss_config_oki0_boost                (
      saveStateRuntimeConfig[26:23]
    ),
    .io_ss_config_oki1_boost                (
      saveStateRuntimeConfig[30:27]
    ),
    .io_ss_register_idle                    (saveStateMainRegisterIdle),
    .io_ss_register_restore_committed       (
      saveStateMainRegisterCommitted
    ),
    .io_ss_register_terminal_fault          (
      saveStateMainRegisterTerminalFault
    ),
    .io_ss_register_restore_load            (
      saveStateMainRegisterRestoreLoad
    ),
    .io_ss_register_restore_applied         (
      saveStateVideoDipSourceComplete
    ),
    .io_ss_register_restore_bridge_fault    (
      saveStateVideoDipSourceFault
    ),
    .io_ss_video_register_restore_state     (
      saveStateMainVideoRestoreState
    ),
    .io_ss_dip_register_restore_state       (
      saveStateMainDipRestoreState
    ),
    .io_ss_eeprom_idle                      (saveStateMainEepromIdle),
    .io_ss_eeprom_restore_committed         (
      saveStateMainEepromCommitted
    ),
    .io_ss_eeprom_terminal_fault            (
      saveStateMainEepromTerminalFault
    ),
    .io_ss_cpu_bus                          (saveStateMainBranches[0]),
    .io_ss_control_bus                      (saveStateMainBranches[1]),
    .io_ss_register_bus                     (saveStateMainBranches[3]),
    .io_ss_eeprom_bus                       (saveStateMainBranches[4]),
    .io_ss_ram_bus                          (saveStateMainBranches[2]),
    .io_sailorMoonTilebank                  (_main_io_sailorMoonTilebank),
    .io_spriteFrameBufferSwap               (_main_io_spriteFrameBufferSwap)
`ifdef CAVEBANPRESTO_SS_RELEASE_SLIM_HW_DIAGNOSTIC
    ,
    .io_ss_capture_admitted_seen            (
      saveStateMainCaptureAdmittedSeenCpu
    )
`endif
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
    ,
    .io_ss_release_eligible                 (
      saveStateMainReleaseEligibleCpu
    ),
    .io_ss_release_owner_idle               (
      saveStateMainReleaseOwnerIdleCpu
    ),
    .io_ss_release_detail                   (
      saveStateMainReleaseDetailCpu
    ),
    .io_ss_release_state                    (
      saveStateMainReleaseStateCpu
    ),
    .io_ss_release_fault_debug              (
      saveStateMainReleaseFaultDebugCpu
    )
`endif
`ifdef CAVE_ENABLE_DEBUG_OVERLAY
    ,
    .io_debug_pipeline                      (_main_io_debug_pipeline),
    .io_debug_cpu                           (_main_io_debug_cpu),
    .io_debug_writes                        (_main_io_debug_writes),
    .io_debug_data                          (_main_io_debug_data),
    .io_debug_live                          (_main_io_debug_live),
    .io_debug_palette                       (_main_io_debug_palette)
`endif
  );
  CaveProgramRomReadFreezer main_io_progRom_freezer (
    .clock          (clock),
    .reset          (reset),
    .io_block_new_requests(saveStateProgramRomBlockNewWork),
    .io_targetClock (cpuClock),
    .io_in_rd       (_main_io_progRom_rd),
    .io_in_addr     (_main_io_progRom_addr),
    .io_in_dout     (_main_io_progRom_dout),
    .io_in_valid    (_main_io_progRom_valid),
    .io_idle        (saveStateProgramRomFreezerIdle),
    .io_out_rd      (_memSys_io_progRom_rd),
    .io_out_addr    (_memSys_io_progRom_addr),
    .io_out_dout    (_memSys_io_progRom_dout),
    .io_out_wait_n  (_memSys_io_progRom_wait_n),
    .io_out_valid   (_memSys_io_progRom_valid)
  );
  CaveEepromDataFreezer main_io_eeprom_freezer (
    .clock          (clock),
    .reset          (reset),
    .io_block_new_requests(saveStateEepromBlockNewWork),
    .io_targetClock (cpuClock),
    .io_in_rd       (_main_io_eeprom_rd),
    .io_in_wr       (_main_io_eeprom_wr),
    .io_in_addr     (_main_io_eeprom_addr),
    .io_in_din      (_main_io_eeprom_din),
    .io_in_dout     (_main_io_eeprom_dout),
    .io_in_wait_n   (_main_io_eeprom_wait_n),
    .io_in_valid    (_main_io_eeprom_valid),
    .io_idle        (saveStateEepromFreezerIdle),
    .io_out_rd      (_memSys_io_eeprom_rd),
    .io_out_wr      (_memSys_io_eeprom_wr),
    .io_out_addr    (_memSys_io_eeprom_addr),
    .io_out_din     (_memSys_io_eeprom_din),
    .io_out_dout    (_memSys_io_eeprom_dout),
    .io_out_wait_n  (_memSys_io_eeprom_wait_n),
    .io_out_valid   (_memSys_io_eeprom_valid)
  );

  // Owner 34 is a zero-payload transport fence, so it is deliberately absent
  // from the serialized owner bitmap. Keep only its dedicated requester idle.
  assign soundRomSaveStateBus.req_data = 64'd0;
  assign soundRomSaveStateBus.req_addr = 32'd0;
  assign soundRomSaveStateBus.req_select = 8'd0;
  assign soundRomSaveStateBus.req_read = 1'b0;
  assign soundRomSaveStateBus.req_write = 1'b0;
  assign soundRomSaveStateBus.req_validate = 1'b0;
  assign soundRomSaveStateBus.req_query = 1'b0;

  Sound sound (
    .clock                        (cpuClock),
    .reset                        (cpuDomainReset),
    .io_ctrl_oki_0_wr             (_main_io_soundCtrl_oki_0_wr),
    .io_ctrl_oki_0_din            (_main_io_soundCtrl_oki_0_din),
    .io_ctrl_oki_0_dout           (_main_io_soundCtrl_oki_0_dout),
    .io_ctrl_oki_1_wr             (_main_io_soundCtrl_oki_1_wr),
    .io_ctrl_oki_1_din            (_main_io_soundCtrl_oki_1_din),
    .io_ctrl_oki_1_dout           (_main_io_soundCtrl_oki_1_dout),
    .io_ctrl_nmk_wr               (_main_io_soundCtrl_nmk_wr),
    .io_ctrl_nmk_addr             (_main_io_soundCtrl_nmk_addr),
    .io_ctrl_nmk_din              (_main_io_soundCtrl_nmk_din),
    .io_ctrl_ymz_rd               (_main_io_soundCtrl_ymz_rd),
    .io_ctrl_ymz_wr               (_main_io_soundCtrl_ymz_wr),
    .io_ctrl_ymz_addr             (_main_io_soundCtrl_ymz_addr),
    .io_ctrl_ymz_din              (_main_io_soundCtrl_ymz_din),
    .io_ctrl_ymz_dout             (_main_io_soundCtrl_ymz_dout),
    .io_ctrl_req                  (_main_io_soundCtrl_req),
    .io_ctrl_data                 (_main_io_soundCtrl_data),
    .io_ctrl_reply_rd             (_main_io_soundCtrl_reply_rd),
    .io_ctrl_reply                (_main_io_soundCtrl_reply),
    .io_ctrl_reply_empty          (_main_io_soundCtrl_reply_empty),
    .io_ctrl_irq                  (_main_io_soundCtrl_irq),
    .io_gameIndex                 (gameIndexCpuReg),
    .io_gameConfig_sound_0_device (gameConfigCpu_sound_0_device),
    .io_audioConfigClock          (clock),
    .io_audioConfigReset          (reset),
    .io_audioTrim_fm              (saveStateRuntimeConfig[18:15]),
    .io_audioTrim_bgm             (saveStateRuntimeConfig[22:19]),
    .io_audioTrim_sfx             (saveStateRuntimeConfig[26:23]),
    .io_rom_0_rd                  (_sound_io_rom_0_rd),
    .io_rom_0_addr                (_sound_io_rom_0_addr),
    .io_rom_0_dout                (_sound_io_rom_0_dout),
    .io_rom_0_wait_n              (_sound_io_rom_0_wait_n),
    .io_rom_0_valid               (_sound_io_rom_0_valid),
    .io_rom_1_rd                  (_sound_io_rom_1_rd),
    .io_rom_1_addr                (_sound_io_rom_1_addr),
    .io_rom_1_dout                (_sound_io_rom_1_dout),
    .io_rom_1_valid               (_sound_io_rom_1_valid),
    .io_rom_2_rd                  (_sound_io_rom_2_rd),
    .io_rom_2_addr                (_sound_io_rom_2_addr),
    .io_rom_2_dout                (_sound_io_rom_2_dout),
    .io_rom_2_valid               (_sound_io_rom_2_valid),
    .io_ss_command_valid          (
      saveStateCoordinatorSoundCommandValid
    ),
    .io_ss_command                (
      saveStateCoordinatorSoundCommand
    ),
    .io_ss_command_complete       (saveStateSoundCommandComplete),
    .io_ss_command_response       (saveStateSoundCommandResponse),
    .io_ss_command_terminal_fault (
      saveStateSoundCommandTerminalFault
    ),
    .io_ss_stop_request           (1'b0),
    .io_ss_restore_mode           (1'b0),
    .io_ss_external_idle          (saveStateSoundRomExternalIdleCpu),
    .io_ss_abort                  (1'b0),
    .io_ss_release_authorize      (saveStateSoundReleaseRequestCpu),
    .io_ss_release_restore        (saveStateSoundReleaseRestoreCpu),
    .io_ss_restore_dependencies_ready (
      saveStateSoundRomDependenciesCpu
    ),
    .io_ss_state_enable           (1'b0),
    .io_ss_restore_enable         (1'b0),
    .io_ss_restore_begin          (1'b0),
    .io_ss_restore_commit         (1'b0),
    .io_ss_fatal                  (
      saveStateSoundFatalCpu | saveStateSoundRomFaultCpu
    ),
    .io_ss_runtime_support        (saveStateRuntimeSupport),
    .io_ss_stopped               (_sound_io_ss_stopped),
    .io_ss_abort_ack              (_sound_io_ss_abort_ack),
    .io_ss_restore_launch_done    (
      _sound_io_ss_restore_launch_done
    ),
    .io_ss_idle                   (_sound_io_ss_idle),
    .io_ss_release_pending        (_sound_io_ss_release_pending),
    .io_ss_release_complete       (_sound_io_ss_release_complete),
    .io_ss_terminal_fault         (_sound_io_ss_terminal_fault),
    .io_ssbus                     (soundSaveStateBus),
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
    .io_ss_release_debug          (saveStateSoundReleaseDebugCpu),
    .io_ss_owner_fault_debug      (saveStateSoundOwnerFaultDebugCpu),
`endif
`ifdef CAVE_ENABLE_DEBUG_OVERLAY
    .io_debug                     (_sound_io_debug),
`endif
    .io_audio                     (audio)
  );
  // Owner 34 replaces all three legacy freezers as one fenced transport
  // boundary. Every lane is level-requested by its upstream consumer and keeps
  // its address-tagged response asserted until that consumer retires it.
  CaveBanprestoSoundRomTransportSaveState soundRomSaveState (
    .system_clock_i                 (clock),
    .system_reset_i                 (reset),
    .target_clock_i                 (cpuClock),
    .target_reset_i                 (cpuDomainReset),
    .ss_launch_block_i              (saveStateSoundRomEarlyLaunchBlock),
    .ss_sound_cpu_stopped_i         (saveStateSoundStoppedSystem),
    .ss_prepare_release_i           (saveStateSoundRomPrepare),
    .ss_prefetch_required_i         (
      saveStateSoundRomPrefetchRequired
    ),
    .ss_abort_i                     (saveStateCoordinatorStreamAbort),
    .hold_response_i                (3'b111),
    .target_rd_i                    ({
      _sound_io_rom_2_rd,
      _sound_io_rom_1_rd,
      _sound_io_rom_0_rd
    }),
    .target_addr_i                  ({
      _sound_io_rom_2_addr,
      _sound_io_rom_1_addr,
      _sound_io_rom_0_addr
    }),
    .target_dout_o                  ({
      _sound_io_rom_2_dout,
      _sound_io_rom_1_dout,
      _sound_io_rom_0_dout
    }),
    .target_wait_n_o                ({
      soundRomTargetWaitUnused,
      _sound_io_rom_0_wait_n
    }),
    .target_valid_o                 ({
      _sound_io_rom_2_valid,
      _sound_io_rom_1_valid,
      _sound_io_rom_0_valid
    }),
    .memory_rd_o                    ({
      _memSys_io_soundRom_2_rd,
      _memSys_io_soundRom_1_rd,
      _memSys_io_soundRom_0_rd
    }),
    .memory_addr_o                  ({
      _memSys_io_soundRom_2_addr,
      _memSys_io_soundRom_1_addr,
      _memSys_io_soundRom_0_addr
    }),
    .memory_dout_i                  ({
      _memSys_io_soundRom_2_dout,
      _memSys_io_soundRom_1_dout,
      _memSys_io_soundRom_0_dout
    }),
    .memory_wait_n_i                ({
      _memSys_io_soundRom_2_wait_n,
      _memSys_io_soundRom_1_wait_n,
      _memSys_io_soundRom_0_wait_n
    }),
    .memory_valid_i                 ({
      _memSys_io_soundRom_2_valid,
      _memSys_io_soundRom_1_valid,
      _memSys_io_soundRom_0_valid
    }),
    .ssbus                          (soundRomSaveStateBus),
    .ss_canonical_idle_o            (
      soundRomSaveStateCanonicalIdle
    ),
    .ss_external_idle_o             (
      soundRomSaveStateExternalIdle
    ),
    .ss_restore_dependencies_ready_o(
      soundRomSaveStateDependenciesReady
    ),
    .ss_release_path_ready_o        (
      soundRomSaveStateReleasePathReady
    ),
    .ss_rearmed_o                   (
      soundRomSaveStateRearmed
    ),
    .ss_terminal_fault_o            (
      soundRomSaveStateTerminalFault
    ),
    .ss_lane_system_idle_o          (
      soundRomSaveStateLaneSystemIdle
    ),
    .ss_lane_target_empty_o         (
      soundRomSaveStateLaneTargetEmpty
    )
  );
  assign _gpu_io_spriteCtrl_start = spriteProcessorStart;
  assign _gpu_io_spriteCtrl_zoom = gameConfig_sprite_zoom;
  assign _gpu_io_gameConfig_layer_1_paletteBank = gameConfig_layer_1_paletteBank;
  GPU gpu (
    .clock                               (clock),
    .reset                               (reset),
    .io_videoClock                       (videoClock),
    .io_ss_hold                          (saveStateQuiesceBlockNewWork),
    .io_ss_canonicalize                  (
      saveStateControllerReconstructionStart
    ),
    .io_layerCtrl_0_enable               (options_layer_0),
    .io_layerCtrl_0_format               (gpu_io_layerCtrl_0_format),
    .io_layerCtrl_0_regs_tileSize        (_main_io_gpuMem_layer_0_regs_tileSize),
    .io_layerCtrl_0_regs_enable          (_main_io_gpuMem_layer_0_regs_enable),
    .io_layerCtrl_0_regs_flipX           (_main_io_gpuMem_layer_0_regs_flipX),
    .io_layerCtrl_0_regs_flipY           (_main_io_gpuMem_layer_0_regs_flipY),
    .io_layerCtrl_0_regs_rowScrollEnable (_main_io_gpuMem_layer_0_regs_rowScrollEnable),
    .io_layerCtrl_0_regs_rowSelectEnable (_main_io_gpuMem_layer_0_regs_rowSelectEnable),
    .io_layerCtrl_0_regs_priority        (_main_io_gpuMem_layer_0_regs_priority),
    .io_layerCtrl_0_regs_scroll_x        (_main_io_gpuMem_layer_0_regs_scroll_x),
    .io_layerCtrl_0_regs_scroll_y        (_main_io_gpuMem_layer_0_regs_scroll_y),
    .io_layerCtrl_0_vram8x8_addr         (_main_io_gpuMem_layer_0_vram8x8_addr),
    .io_layerCtrl_0_vram8x8_dout         (_main_io_gpuMem_layer_0_vram8x8_dout),
    .io_layerCtrl_0_vram16x16_addr       (_main_io_gpuMem_layer_0_vram16x16_addr),
    .io_layerCtrl_0_vram16x16_dout       (_main_io_gpuMem_layer_0_vram16x16_dout),
    .io_layerCtrl_0_lineRam_addr         (_main_io_gpuMem_layer_0_lineRam_addr),
    .io_layerCtrl_0_lineRam_dout         (_main_io_gpuMem_layer_0_lineRam_dout),
    .io_layerCtrl_0_tileRom_rd           (_gpu_io_layerCtrl_0_tileRom_rd),
    .io_layerCtrl_0_tileRom_addr         (_gpu_io_layerCtrl_0_tileRom_addr),
    .io_layerCtrl_0_tileRom_dout         (_gpu_io_layerCtrl_0_tileRom_dout),
    .io_layerCtrl_1_enable               (options_layer_1),
    .io_layerCtrl_1_format               (gpu_io_layerCtrl_1_format),
    .io_layerCtrl_1_regs_tileSize        (_main_io_gpuMem_layer_1_regs_tileSize),
    .io_layerCtrl_1_regs_enable          (_main_io_gpuMem_layer_1_regs_enable),
    .io_layerCtrl_1_regs_flipX           (_main_io_gpuMem_layer_1_regs_flipX),
    .io_layerCtrl_1_regs_flipY           (_main_io_gpuMem_layer_1_regs_flipY),
    .io_layerCtrl_1_regs_rowScrollEnable (_main_io_gpuMem_layer_1_regs_rowScrollEnable),
    .io_layerCtrl_1_regs_rowSelectEnable (_main_io_gpuMem_layer_1_regs_rowSelectEnable),
    .io_layerCtrl_1_regs_priority        (_main_io_gpuMem_layer_1_regs_priority),
    .io_layerCtrl_1_regs_scroll_x        (_main_io_gpuMem_layer_1_regs_scroll_x),
    .io_layerCtrl_1_regs_scroll_y        (_main_io_gpuMem_layer_1_regs_scroll_y),
    .io_layerCtrl_1_vram8x8_addr         (_main_io_gpuMem_layer_1_vram8x8_addr),
    .io_layerCtrl_1_vram8x8_dout         (_main_io_gpuMem_layer_1_vram8x8_dout),
    .io_layerCtrl_1_vram16x16_addr       (_main_io_gpuMem_layer_1_vram16x16_addr),
    .io_layerCtrl_1_vram16x16_dout       (_main_io_gpuMem_layer_1_vram16x16_dout),
    .io_layerCtrl_1_lineRam_addr         (_main_io_gpuMem_layer_1_lineRam_addr),
    .io_layerCtrl_1_lineRam_dout         (_main_io_gpuMem_layer_1_lineRam_dout),
    .io_layerCtrl_1_tileRom_rd           (_gpu_io_layerCtrl_1_tileRom_rd),
    .io_layerCtrl_1_tileRom_addr         (_gpu_io_layerCtrl_1_tileRom_addr),
    .io_layerCtrl_1_tileRom_dout         (_gpu_io_layerCtrl_1_tileRom_dout),
    .io_layerCtrl_2_enable               (options_layer_2),
    .io_layerCtrl_2_format               (gpu_io_layerCtrl_2_format),
    .io_layerCtrl_2_regs_tileSize        (_main_io_gpuMem_layer_2_regs_tileSize),
    .io_layerCtrl_2_regs_enable          (_main_io_gpuMem_layer_2_regs_enable),
    .io_layerCtrl_2_regs_flipX           (_main_io_gpuMem_layer_2_regs_flipX),
    .io_layerCtrl_2_regs_flipY           (_main_io_gpuMem_layer_2_regs_flipY),
    .io_layerCtrl_2_regs_rowScrollEnable (_main_io_gpuMem_layer_2_regs_rowScrollEnable),
    .io_layerCtrl_2_regs_rowSelectEnable (_main_io_gpuMem_layer_2_regs_rowSelectEnable),
    .io_layerCtrl_2_regs_priority        (_main_io_gpuMem_layer_2_regs_priority),
    .io_layerCtrl_2_regs_scroll_x        (_main_io_gpuMem_layer_2_regs_scroll_x),
    .io_layerCtrl_2_regs_scroll_y        (_main_io_gpuMem_layer_2_regs_scroll_y),
    .io_layerCtrl_2_vram8x8_addr         (_main_io_gpuMem_layer_2_vram8x8_addr),
    .io_layerCtrl_2_vram8x8_dout         (_main_io_gpuMem_layer_2_vram8x8_dout),
    .io_layerCtrl_2_vram16x16_addr       (_main_io_gpuMem_layer_2_vram16x16_addr),
    .io_layerCtrl_2_vram16x16_dout       (_main_io_gpuMem_layer_2_vram16x16_dout),
    .io_layerCtrl_2_lineRam_addr         (_main_io_gpuMem_layer_2_lineRam_addr),
    .io_layerCtrl_2_lineRam_dout         (_main_io_gpuMem_layer_2_lineRam_dout),
    .io_layerCtrl_2_tileRom_rd           (_gpu_io_layerCtrl_2_tileRom_rd),
    .io_layerCtrl_2_tileRom_addr         (_gpu_io_layerCtrl_2_tileRom_addr),
    .io_layerCtrl_2_tileRom_dout         (_gpu_io_layerCtrl_2_tileRom_dout),
    .io_spriteCtrl_enable                (options_sprite),
    .io_spriteCtrl_format                (gpu_io_spriteCtrl_format),
    .io_spriteCtrl_start                 (_gpu_io_spriteCtrl_start),
    .io_spriteCtrl_zoom                  (_gpu_io_spriteCtrl_zoom),
    .io_spriteCtrl_regs_offset_x         (_main_io_gpuMem_sprite_regs_offset_x),
    .io_spriteCtrl_regs_offset_y         (_main_io_gpuMem_sprite_regs_offset_y),
    .io_spriteCtrl_regs_bank             (spriteRegsBankForGpu),
    .io_spriteCtrl_regs_fixed            (_main_io_gpuMem_sprite_regs_fixed),
    .io_spriteCtrl_regs_hFlip            (_main_io_gpuMem_sprite_regs_hFlip),
    .io_spriteCtrl_vram_rd               (_main_io_gpuMem_sprite_vram_rd),
    .io_spriteCtrl_vram_addr             (_main_io_gpuMem_sprite_vram_addr),
    .io_spriteCtrl_vram_dout             (_main_io_gpuMem_sprite_vram_dout),
    .io_spriteCtrl_tileRom_rd            (_memSys_io_spriteTileRom_rd),
    .io_spriteCtrl_tileRom_addr          (_memSys_io_spriteTileRom_addr),
    .io_spriteCtrl_tileRom_dout          (_memSys_io_spriteTileRom_dout),
    .io_spriteCtrl_tileRom_wait_n        (_memSys_io_spriteTileRom_wait_n),
    .io_spriteCtrl_tileRom_valid         (_memSys_io_spriteTileRom_valid),
    .io_spriteCtrl_tileRom_burstLength   (_memSys_io_spriteTileRom_burstLength),
    .io_spriteCtrl_tileRom_burstDone     (_memSys_io_spriteTileRom_burstDone),
    .io_gameConfig_granularity           (gameConfig_granularity),
    .io_gameConfig_layer_0_paletteBank   (gameConfig_layer_0_paletteBank),
    .io_gameConfig_layer_1_paletteBank   (_gpu_io_gameConfig_layer_1_paletteBank),
    .io_gameConfig_layer_2_paletteBank   (gameConfig_layer_2_paletteBank),
    .io_gameConfig_maskLeftColumn        (gameIsAirGallet | gameIsSailorMoon),
    .io_gameConfig_airLayer2Direct6bpp   (gameIsAirGallet | gameIsSailorMoon),
    .io_gameConfig_sailorMoonTilebank    (_main_io_sailorMoonTilebank),
    .io_gameConfig_metmqstrRenderCrop    (gameIsMetmqstr),
    .io_options_rotate                   (effectiveRotate),
    .io_options_rotateClockwise          (rotateClockwise),
    .io_options_flipVideo                (options_flipVideo),
    .io_video_clockEnable                (_videoSys_io_video_clockEnable),
    .io_video_displayEnable              (_videoSys_io_video_displayEnable),
    .io_video_pos_x                      (_videoSys_io_video_pos_x),
    .io_video_pos_y                      (_videoSys_io_video_pos_y),
    .io_video_vBlank                     (_videoSys_io_video_vBlank),
    .io_video_regs_size_x                (_videoSys_io_video_regs_size_x),
    .io_video_regs_size_y                (_videoSys_io_video_regs_size_y),
    .io_spriteLineBuffer_addr            (_gpu_io_spriteLineBuffer_addr),
    .io_spriteLineBuffer_dout            (_gpu_io_spriteLineBuffer_dout),
    .io_spriteFrameBuffer_wr             (_gpu_io_spriteFrameBuffer_wr),
    .io_spriteFrameBuffer_addr           (_gpu_io_spriteFrameBuffer_addr),
    .io_spriteFrameBuffer_din            (_gpu_io_spriteFrameBuffer_din),
    .io_spriteFrameBuffer_wait_n         (_gpu_io_spriteFrameBuffer_wait_n),
    .io_spriteCtrl_frameReady            (_gpu_io_spriteCtrl_frameReady),
    .io_systemFrameBuffer_wr             (_gpu_io_systemFrameBuffer_wr),
    .io_systemFrameBuffer_addr           (_gpu_io_systemFrameBuffer_addr),
    .io_systemFrameBuffer_din            (_gpu_io_systemFrameBuffer_din),
    .io_paletteRam_addr                  (_main_io_gpuMem_paletteRam_addr),
    .io_paletteRam_dout                  (_main_io_gpuMem_paletteRam_dout),
    .io_rgb                              (_gpu_rgb),
    .io_ss_idle                          (saveStateGpuIdle),
    .io_ss_reconstruction_ready          (
      saveStateGpuReconstructionReady
    )
`ifdef CAVEBANPRESTO_MET_SPRITE_PAGE_HW_DIAGNOSTIC
    ,
    .io_met_sprite_diag_overlay_valid    (
      metmqstrSpritePageDiagOverlayValid
    ),
    .io_met_sprite_diag_overlay_rgb      (
      metmqstrSpritePageDiagOverlayRgb
    ),
    .io_met_sprite_diag_mixerSpriteWins  (
      metmqstrSpritePageDiagMixerSpriteWins
    )
`endif
`ifdef CAVE_ENABLE_DEBUG_OVERLAY
    ,
    .io_debug_video                      (_gpu_io_debug_video),
    .io_debug_readout                    (_gpu_io_debug_readout),
    .io_debug_source_rgb                 (_gpu_io_debug_source_rgb)
`endif
  );

`ifdef CAVE_ENABLE_DEBUG_OVERLAY
  wire [63:0] debugBits =
    options_debugView == 3'd1 ? _main_io_debug_cpu :
    options_debugView == 3'd2 ? _main_io_debug_writes :
    options_debugView == 3'd3 ? _main_io_debug_live :
    options_debugView == 3'd4 ? _main_io_debug_palette :
    options_debugView == 3'd5 ? _main_io_debug_data :
    options_debugView == 3'd6 ? _gpu_io_debug_video :
    options_debugView == 3'd7 ? _sound_io_debug :
                                 _main_io_debug_pipeline;
  wire [23:0] debugRgb;

  CaveDebugOverlay debugOverlay (
    .io_video_pos_x (_videoSys_io_video_pos_x),
    .io_video_pos_y (_videoSys_io_video_pos_y),
    .io_debug_view  (options_debugView),
    .io_debug_bits  (debugBits),
    .io_rgb         (debugRgb)
  );

  assign rgb =
    (options_debugView == 3'd6)
      ? (options_debugVideo ? _gpu_io_debug_source_rgb : debugRgb) :
    options_debugVideo ? debugRgb : _gpu_rgb;
`else
  assign rgb = _gpu_rgb;
`endif
  CaveTileRomClockCrossing gpu_io_layerCtrl_0_tileRom_crossing (
    .clock          (clock),
    .reset          (reset),
    .io_targetClock (videoClock),
    .io_block_new_requests(saveStateQuiesceBlockNewWork),
    .io_in_rd       (_gpu_io_layerCtrl_0_tileRom_rd),
    .io_in_addr     (_gpu_io_layerCtrl_0_tileRom_addr),
    .io_in_dout     (_gpu_io_layerCtrl_0_tileRom_dout),
    .io_out_rd      (_memSys_io_layerTileRom_0_rd),
    .io_out_addr    (_memSys_io_layerTileRom_0_addr),
    .io_out_dout    (_memSys_io_layerTileRom_0_dout),
    .io_out_wait_n  (_memSys_io_layerTileRom_0_wait_n),
    .io_out_valid   (_memSys_io_layerTileRom_0_valid),
    .io_idle        (saveStateTileRomIdle[0])
  );
  CaveTileRomClockCrossing gpu_io_layerCtrl_1_tileRom_crossing (
    .clock          (clock),
    .reset          (reset),
    .io_targetClock (videoClock),
    .io_block_new_requests(saveStateQuiesceBlockNewWork),
    .io_in_rd       (_gpu_io_layerCtrl_1_tileRom_rd),
    .io_in_addr     (_gpu_io_layerCtrl_1_tileRom_addr),
    .io_in_dout     (_gpu_io_layerCtrl_1_tileRom_dout),
    .io_out_rd      (_memSys_io_layerTileRom_1_rd),
    .io_out_addr    (_memSys_io_layerTileRom_1_addr),
    .io_out_dout    (_memSys_io_layerTileRom_1_dout),
    .io_out_wait_n  (_memSys_io_layerTileRom_1_wait_n),
    .io_out_valid   (_memSys_io_layerTileRom_1_valid),
    .io_idle        (saveStateTileRomIdle[1])
  );
  CaveTileRomClockCrossing gpu_io_layerCtrl_2_tileRom_crossing (
    .clock          (clock),
    .reset          (reset),
    .io_targetClock (videoClock),
    .io_block_new_requests(saveStateQuiesceBlockNewWork),
    .io_in_rd       (_gpu_io_layerCtrl_2_tileRom_rd),
    .io_in_addr     (_gpu_io_layerCtrl_2_tileRom_addr),
    .io_in_dout     (_gpu_io_layerCtrl_2_tileRom_dout),
    .io_out_rd      (_memSys_io_layerTileRom_2_rd),
    .io_out_addr    (_memSys_io_layerTileRom_2_addr),
    .io_out_dout    (_memSys_io_layerTileRom_2_dout),
    .io_out_wait_n  (_memSys_io_layerTileRom_2_wait_n),
    .io_out_valid   (_memSys_io_layerTileRom_2_valid),
    .io_idle        (saveStateTileRomIdle[2])
  );
  SpriteFrameBuffer spriteFrameBuffer (
    .clock                 (clock),
    .reset                 (reset),
    .io_videoClock         (videoClock),
    .io_enable             (_memSys_io_ready),
`ifdef CAVEBANPRESTO_MET_SPRITE_PAGE_HW_DIAGNOSTIC
    .io_met_sprite_page_diag_enable (gameIsMetmqstr),
    .io_met_sprite_page_diag_source (metmqstrSpritePageDiagSource),
    .io_met_sprite_page_diag_video_pos_x (
      _videoSys_io_video_pos_x
    ),
    .io_met_sprite_page_diag_mixer_sprite_wins (
      metmqstrSpritePageDiagMixerSpriteWins
    ),
    .io_met_sprite_page_diag_probe  (metmqstrSpritePageDiagProbe),
    .io_met_sprite_page_diag_overlay_valid (
      metmqstrSpritePageDiagOverlayValid
    ),
    .io_met_sprite_page_diag_overlay_rgb (
      metmqstrSpritePageDiagOverlayRgb
    ),
`endif
    .io_ss_hold            (saveStateQuiesceBlockNewWork),
    .io_ss_canonicalize    (saveStateControllerReconstructionStart),
    .io_ss_preclear_target (
      saveStateControllerReconstructionStart & gameIsAirFamily
    ),
    .io_swap               (spriteFrameBufferSwap),
    .io_video_pos_y        (_videoSys_io_video_pos_y),
    .io_video_regs_size_x  (spriteFrameBufferSizeX),
    .io_video_regs_size_y  (_videoSys_io_video_regs_size_y),
    .io_video_hBlank       (_videoSys_io_video_hBlank),
    .io_lineBuffer_earlyStart (spriteLineBufferEarlyStart),
    .io_lineBuffer_burstOffset (spriteLineBufferBurstOffset),
    .io_lineBuffer_addr    (_gpu_io_spriteLineBuffer_addr),
    .io_lineBuffer_dout    (_gpu_io_spriteLineBuffer_dout),
    .io_frameBuffer_wr     (_gpu_io_spriteFrameBuffer_wr),
    .io_frameBuffer_addr   (_gpu_io_spriteFrameBuffer_addr),
    .io_frameBuffer_din    (_gpu_io_spriteFrameBuffer_din),
    .io_frameBuffer_wait_n (_gpu_io_spriteFrameBuffer_wait_n),
    .io_ddr_rd             (_memSys_io_spriteFrameBuffer_rd),
    .io_ddr_wr             (_memSys_io_spriteFrameBuffer_wr),
    .io_ddr_addr           (_memSys_io_spriteFrameBuffer_addr),
    .io_ddr_mask           (_memSys_io_spriteFrameBuffer_mask),
    .io_ddr_din            (_memSys_io_spriteFrameBuffer_din),
    .io_ddr_dout           (_memSys_io_spriteFrameBuffer_dout),
    .io_ddr_wait_n         (_memSys_io_spriteFrameBuffer_wait_n),
    .io_ddr_valid          (_memSys_io_spriteFrameBuffer_valid),
    .io_ddr_burstLength    (_memSys_io_spriteFrameBuffer_burstLength),
    .io_ddr_burstDone      (_memSys_io_spriteFrameBuffer_burstDone),
    .io_ss_idle            (saveStateSpriteFrameBufferIdle),
    .io_ss_write_idle      (saveStateSpriteFrameBufferWriteIdle),
    .io_ss_swap_accepted   (saveStateSpriteFrameBufferSwapAccepted),
    .io_ss_reconstruction_target_ready (
      saveStateSpriteReconstructionTargetReady
    )
  );
  assign systemFrameBufferForceBlank = ~_memSys_io_ready;
  SystemFrameBuffer systemFrameBuffer (
    .clock                         (clock),
    .reset                         (reset),
    .io_videoClock                 (videoClock),
    .io_enable                     (_memSys_io_ready),
    .io_ss_hold                    (saveStateQuiesceBlockNewWork),
    .io_ss_canonicalize            (
      saveStateControllerReconstructionStart
    ),
    .io_ss_reconstruction_active   (
      saveStateControllerReconstructionActive
    ),
    .io_ss_reconstruction_ready    (
      saveStateGpuReconstructionComplete
    ),
    .io_rotate                     (effectiveRotate),
    .io_forceBlank                 (systemFrameBufferForceBlank),
    .io_video_vBlank               (_videoSys_io_video_vBlank),
    .io_video_regs_size_x          (_videoSys_io_video_regs_size_x),
    .io_video_regs_size_y          (_videoSys_io_video_regs_size_y),
    .io_frameBufferCtrl_enable     (frameBufferCtrl_enable),
    .io_frameBufferCtrl_hSize      (frameBufferCtrl_hSize),
    .io_frameBufferCtrl_vSize      (frameBufferCtrl_vSize),
    .io_frameBufferCtrl_baseAddr   (frameBufferCtrl_baseAddr),
    .io_frameBufferCtrl_stride     (frameBufferCtrl_stride),
    .io_frameBufferCtrl_vBlank     (frameBufferCtrl_vBlank),
    .io_frameBufferCtrl_lowLat     (frameBufferCtrl_lowLat),
    .io_frameBufferCtrl_forceBlank (frameBufferCtrl_forceBlank),
    .io_frameBuffer_wr             (_gpu_io_systemFrameBuffer_wr),
    .io_frameBuffer_addr           (_gpu_io_systemFrameBuffer_addr),
    .io_frameBuffer_din            (_gpu_io_systemFrameBuffer_din),
    .io_ddr_wr                     (_memSys_io_systemFrameBuffer_wr),
    .io_ddr_addr                   (_memSys_io_systemFrameBuffer_addr),
    .io_ddr_mask                   (_memSys_io_systemFrameBuffer_mask),
    .io_ddr_din                    (_memSys_io_systemFrameBuffer_din),
    .io_ddr_wait_n                 (_memSys_io_systemFrameBuffer_wait_n),
    .io_ddr_commit                 (saveStateSystemFrameBufferDdrCommit),
    .io_ss_idle                    (saveStateSystemFrameBufferIdle),
    .io_ss_publication_complete    (
      saveStateSystemFrameBufferPublicationComplete
    ),
    .io_ss_publication_debug       (
      saveStateSystemFrameBufferPublicationDebug
    )
  );
  assign ioctl_wait_n = videoSys_io_prog_video_writeEnable | ioctlMemoryWaitN;
  assign ioctl_din =
    memSys_io_prog_nvram_readEnable ? memSys_io_prog_nvram_ioctl_din_r :
    ioctlNvramHighScoreReadEnable ? _main_io_hs_nvram_din : 16'h0;
  assign nvram_dirty = eepromDirtyReg | _main_io_hs_dirty;
  assign led_power = 1'b0;
  assign led_disk = ioctl_download;
  assign led_user = _memSys_io_ready;
  assign frameBufferCtrl_format = 5'h6;
  assign game_index = gameIndexReg;
  assign video_clockEnable = _videoSys_io_video_clockEnable;
  assign video_displayEnable = _videoSys_io_video_displayEnable;
  assign video_pos_x = _videoSys_io_video_pos_x;
  assign video_pos_y = _videoSys_io_video_pos_y;
  assign video_hBlank = _videoSys_io_video_hBlank;
  assign video_vBlank = _videoSys_io_video_vBlank;
  assign video_regs_size_x = _videoSys_io_video_regs_size_x;
  assign video_regs_size_y = _videoSys_io_video_regs_size_y;
  assign video_rotated = effectiveRotate;

`ifdef CAVEBANPRESTO_SS_RELEASE_LEGACY_HW_DIAGNOSTIC
  wire [1:0]   saveStateReleaseDiagSource;
  wire [127:0] saveStateReleaseDiagProbe;
  wire         saveStateReleaseLaneDiagSource;
  wire [127:0] saveStateReleaseLaneDiagProbe;
  reg          saveStateMainReleaseSourceTimeoutSeen;
  reg          saveStateSoundReleaseSourceTimeoutSeen;
  reg          saveStateMainReleaseDestinationTimeoutSeenCpu;
  reg          saveStateSoundReleaseDestinationTimeoutSeenCpu;
  reg          saveStateMainReleaseCompleteSeenCpu;
  reg          saveStateSoundReleaseCompleteSeenCpu;
  wire         saveStateMainReleaseDestinationTimeoutSeenSystem;
  wire         saveStateSoundReleaseDestinationTimeoutSeenSystem;
  wire         saveStateMainReleaseCompleteSeenSystem;
  wire         saveStateSoundReleaseCompleteSeenSystem;
  wire         saveStateMainReleaseDestinationProtocolFaultSystem;
  wire         saveStateSoundReleaseDestinationProtocolFaultSystem;

  always @(posedge clock) begin
    if (reset) begin
      saveStateMainReleaseSourceTimeoutSeen <= 1'b0;
      saveStateSoundReleaseSourceTimeoutSeen <= 1'b0;
    end else begin
      if (saveStateMainReleaseSourceTimeout)
        saveStateMainReleaseSourceTimeoutSeen <= 1'b1;
      if (saveStateSoundReleaseSourceTimeout)
        saveStateSoundReleaseSourceTimeoutSeen <= 1'b1;
    end
  end

  always @(posedge cpuClock) begin
    if (cpuDomainReset) begin
      saveStateMainReleaseDestinationTimeoutSeenCpu <= 1'b0;
      saveStateSoundReleaseDestinationTimeoutSeenCpu <= 1'b0;
      saveStateMainReleaseCompleteSeenCpu <= 1'b0;
      saveStateSoundReleaseCompleteSeenCpu <= 1'b0;
    end else begin
      if (saveStateMainReleaseDestinationTimeout)
        saveStateMainReleaseDestinationTimeoutSeenCpu <= 1'b1;
      if (saveStateSoundReleaseDestinationTimeout)
        saveStateSoundReleaseDestinationTimeoutSeenCpu <= 1'b1;
      if (saveStateMainReleaseCompleteCpu)
        saveStateMainReleaseCompleteSeenCpu <= 1'b1;
      if (_sound_io_ss_release_complete)
        saveStateSoundReleaseCompleteSeenCpu <= 1'b1;
    end
  end

  CaveBanprestoSaveStateCdcBitSync
    saveStateMainReleaseDestinationTimeoutSeenSync (
    .clk_i   (clock),
    .reset_i (reset),
    .async_i (saveStateMainReleaseDestinationTimeoutSeenCpu),
    .sync_o  (saveStateMainReleaseDestinationTimeoutSeenSystem)
  );

  CaveBanprestoSaveStateCdcBitSync
    saveStateSoundReleaseDestinationTimeoutSeenSync (
    .clk_i   (clock),
    .reset_i (reset),
    .async_i (saveStateSoundReleaseDestinationTimeoutSeenCpu),
    .sync_o  (saveStateSoundReleaseDestinationTimeoutSeenSystem)
  );

  CaveBanprestoSaveStateCdcBitSync
    saveStateMainReleaseCompleteSeenSync (
    .clk_i   (clock),
    .reset_i (reset),
    .async_i (saveStateMainReleaseCompleteSeenCpu),
    .sync_o  (saveStateMainReleaseCompleteSeenSystem)
  );

  CaveBanprestoSaveStateCdcBitSync
    saveStateSoundReleaseCompleteSeenSync (
    .clk_i   (clock),
    .reset_i (reset),
    .async_i (saveStateSoundReleaseCompleteSeenCpu),
    .sync_o  (saveStateSoundReleaseCompleteSeenSystem)
  );

  CaveBanprestoSaveStateCdcBitSync
    saveStateMainReleaseDestinationProtocolFaultSync (
    .clk_i   (clock),
    .reset_i (reset),
    .async_i (saveStateMainReleaseDestinationProtocolFault),
    .sync_o  (saveStateMainReleaseDestinationProtocolFaultSystem)
  );

  CaveBanprestoSaveStateCdcBitSync
    saveStateSoundReleaseDestinationProtocolFaultSync (
    .clk_i   (clock),
    .reset_i (reset),
    .async_i (saveStateSoundReleaseDestinationProtocolFault),
    .sync_o  (saveStateSoundReleaseDestinationProtocolFaultSystem)
  );

  CaveBanprestoSaveStateReleaseHardwareDiagnostic
    saveStateReleaseHardwareDiagnostic (
    .clk_i                     (clock),
    .reset_i                   (reset),
    .page_select_i             (saveStateReleaseDiagSource),
    .game_index_i              (gameIndexReg),
    .controller_state_i        (saveStateControllerDebug),
    .quiesce_state_i           (saveStateQuiescePhase),
    .coordinator_state_i       (saveStateCoordinatorDebug),
    .controller_error_i        (saveStateControllerLastError),
    .stream_error_i            (saveStateControllerLastStreamError),
    .coordinator_fault_i       (saveStateCoordinatorLastFault),
    .current_flags_i           ({
      reset,
      ss_available,
      ss_active,
      ss_busy,
      saveStateControllerActive,
      saveStateControllerRestore,
      saveStateControllerDone,
      saveStateControllerSuccess,
      saveStateControllerFatal,
      saveStateRawStreamBusy,
      saveStateRawStreamDone,
      saveStateRawStreamSuccess,
      saveStateRawStreamFormatError,
      saveStateRawStreamFatal,
      saveStateQuiesceBusy,
      saveStateQuiesceFreeze,
      saveStateQuiesceBlockNewWork,
      saveStateQuiesced,
      saveStateQuiesceTimeout,
      saveStateQuiesceFatal,
      saveStateQuiesceAbortActive,
      saveStateControllerQuiesceResume,
      saveStateCoordinatorActive,
      saveStateCoordinatorRestore,
      saveStateCoordinatorMainStopped,
      saveStateCoordinatorSoundStopped,
      saveStateCoordinatorReleasePending,
      saveStateCoordinatorMainRelease,
      saveStateCoordinatorSoundRelease,
      saveStateCoordinatorReleaseRestore,
      saveStateCoordinatorReleaseComplete,
      saveStateCoordinatorTerminalFault,
      saveStateMainReleaseCompleteSystem,
      saveStateMainReleaseReady,
      saveStateMainReleaseBusy,
      saveStateMainReleaseSourceFault,
      saveStateMainReleaseDestinationFault,
      saveStateSoundReleaseCompleteSystem,
      saveStateSoundReleaseReady,
      saveStateSoundReleaseBusy,
      saveStateSoundReleaseSourceFault,
      saveStateSoundReleaseDestinationFault,
      saveStateMainReleaseRequestCpu,
      saveStateMainReleaseRestoreCpu,
      saveStateMainReleaseCompleteCpu,
      saveStateSoundReleaseRequestCpu,
      saveStateSoundReleaseRestoreCpu,
      _sound_io_ss_release_complete,
      saveStateMainCdcReady,
      saveStateMainCdcBusy,
      saveStateMainCdcDraining,
      saveStateMainCdcSourceFault,
      saveStateMainCdcDestinationFault,
      saveStateSoundCdcReady,
      saveStateSoundCdcBusy,
      saveStateSoundCdcDraining,
      saveStateSoundCdcSourceFault,
      saveStateSoundCdcDestinationFault,
      videoVBlankObserverPipe1,
      saveStateMainCommandTerminalFault,
      saveStateSoundCommandTerminalFault,
      saveStateInfrastructureFault,
      saveStateControllerOperationFatal
    }),
    .detail_flags_i            ({
      saveStateMaintenanceTerminalFault,
      saveStateSystemRouterFault,
      saveStateMainRouterFault,
      saveStateMainCommandTerminalFault,
      saveStateMainCpuTerminalFault,
      saveStateMainControlTerminalFault,
      saveStateMainRamTerminalFault,
      saveStateMainRegisterTerminalFault,
      saveStateMainEepromTerminalFault,
      saveStateSoundCommandTerminalFault,
      saveStateSoundFatalCpu,
      saveStateSoundRomFaultCpu,
      saveStateMainReleaseSourceFault,
      saveStateMainReleaseDestinationFault,
      saveStateSoundReleaseSourceFault,
      saveStateSoundReleaseDestinationFault,
      saveStateCoordinatorMainCommandChannelFault,
      saveStateCoordinatorSoundCommandChannelFault,
      saveStateControllerFatal,
      saveStateQuiesceFatal,
      saveStateCoordinatorTerminalFault,
      saveStateRawStreamFatal,
      saveStateInfrastructureFault
    }),
    .release_detail_i          ({
      2'd0,
      saveStateMainCdcSourceFault,
      saveStateSoundCdcSourceFault,
      saveStateSystemOwnerTerminalFault,
      saveStateSystemCpuSourceFault,
      saveStateVideoDipDestinationFault,
      saveStateNvramOwnerFatal,
      saveStateNvramFatal,
      saveStateRegisterWriteFault,
      saveStateMainReleaseCompleteSeenSystem,
      saveStateSoundReleaseCompleteSeenSystem,
      saveStateMainReleaseSourceTimeoutSeen,
      saveStateMainReleaseDestinationTimeoutSeenSystem,
      saveStateMainReleaseSourceProtocolFault,
      saveStateMainReleaseDestinationProtocolFaultSystem,
      saveStateSoundReleaseSourceTimeoutSeen,
      saveStateSoundReleaseDestinationTimeoutSeenSystem,
      saveStateSoundReleaseSourceProtocolFault,
      saveStateSoundReleaseDestinationProtocolFaultSystem,
      saveStateMainCapturedSystem,
      saveStateMainControlIdleSystem,
      saveStateMainRamIdleSystem,
      saveStateMainRegisterIdleSystem,
      saveStateMainEepromIdleSystem,
      saveStateMainRouterIdleSystem,
      saveStateMainCommandBusySystem,
      saveStateCoordinatorMainStopped,
      saveStateMainStopped,
      saveStateMainCpuCaptured,
      saveStateMainControlIdle,
      saveStateMainRamIdle,
      saveStateMainRegisterIdle,
      saveStateMainEepromIdle,
      saveStateMainReleaseRequestCpu,
      saveStateMainReleaseRestoreCpu,
      saveStateMainReleaseCompleteCpu,
      saveStateCoordinatorMainRelease,
      saveStateCoordinatorReleasePending,
      saveStateMainReleaseReady,
      saveStateMainReleaseBusy,
      saveStateMainReleaseSourceFault,
      saveStateMainReleaseDestinationFault,
      saveStateMainReleaseCompleteSystem,
      saveStateQuiesceFreeze,
      saveStateControllerActive,
      saveStateIdleAck
    }),
    .coordinator_release_request_i (
      saveStateCoordinatorMainRelease
    ),
    .coordinator_release_restore_i (
      saveStateCoordinatorReleaseRestore
    ),
    .pass2_enable_i            (saveStateCoordinatorStreamPass2Enable),
    .operation_restore_i       (saveStateCoordinatorRestore),
    .mutation_authorized_i     (
      saveStateCoordinatorMutationAuthorized
    ),
    .raw_done_i                (saveStateRawStreamDone),
    .raw_success_i             (saveStateRawStreamSuccess),
    .raw_restore_commit_i      (saveStateRawStreamRestoreCommit),
    .raw_restore_pass_i        (saveStateRawStreamRestorePass),
    .controller_abort_i        (saveStateControllerStreamAbort),
    .result_latched_i          (
      saveStateCoordinatorResultLatchedDebug
    ),
    .result_success_i          (
      saveStateCoordinatorResultSuccessDebug
    ),
    .result_restore_commit_i   (
      saveStateCoordinatorResultCommitDebug
    ),
    .result_restore_pass_i     (
      saveStateCoordinatorResultPassDebug
    ),
    .restore_done_good_i       (
      saveStateCoordinatorRestoreDoneGoodDebug
    ),
    .restore_pass2_capture_i   (
      saveStateCoordinatorPass2CaptureDebug
    ),
    .abort_requested_i         (
      saveStateCoordinatorAbortRequestedDebug
    ),
    .save_request_i            (ss_save_request),
    .load_request_i            (ss_load_request),
    .operation_request_i       (saveStateOperationRequest),
    .controller_accepted_i     (saveStateControllerAccepted),
    .controller_rejected_i     (saveStateControllerRejected),
    .controller_done_i         (saveStateControllerDone),
    .controller_success_i      (saveStateControllerSuccess),
    .controller_aborted_i      (saveStateControllerAborted),
    .owner_failure_count_i     (saveStateRawOwnerFailureCountDebug),
    .owner_failure_state_i     (saveStateRawOwnerFailureStateDebug),
    .owner_failure_restore_i   (saveStateRawOwnerFailureRestoreDebug),
    .owner_failure_pass_i      (saveStateRawOwnerFailurePassDebug),
    .owner_failure_command_i   (saveStateRawOwnerFailureCommandDebug),
    .owner_failure_select_i    (saveStateRawOwnerFailureSelectDebug),
    .owner_failure_addr_i      (saveStateRawOwnerFailureAddrDebug),
    .owner_failure_reason_i    (saveStateRawOwnerFailureReasonDebug),
    .owner_failure_data_low_i  (saveStateRawOwnerFailureDataLowDebug),
    .sound_fault_context_i     (saveStatePass2FaultContextDebug),
    .fault_context_valid_i     (saveStatePass2FaultContextValidDebug),
    .probe_o                   (saveStateReleaseDiagProbe)
  );

  altsource_probe #(
    .sld_auto_instance_index ("NO"),
    .sld_instance_index      (0),
    .instance_id             ("CBR"),
    .probe_width             (128),
    .source_width            (2),
    .source_initial_value    ("0"),
    .enable_metastability    ("NO")
  ) saveStateReleaseHardwareProbe (
    .probe  (saveStateReleaseDiagProbe),
    .source (saveStateReleaseDiagSource)
  );

  CaveBanprestoSaveStateReleaseLaneHardwareDiagnostic
    saveStateReleaseLaneHardwareDiagnostic (
    .clk_i                       (cpuClock),
    .reset_i                     (cpuDomainReset),
    .game_index_i                (gameIndexCpuReg),
    .main_request_i              (saveStateMainReleaseRequestCpu),
    .main_restore_i              (saveStateMainReleaseRestoreCpu),
    .main_complete_i             (saveStateMainReleaseCompleteCpu),
    .main_state_i                (saveStateMainReleaseStateCpu),
    .main_fault_debug_i          (saveStateMainReleaseFaultDebugCpu),
    .main_eligible_i             (saveStateMainReleaseEligibleCpu),
    .main_owner_idle_i           (saveStateMainReleaseOwnerIdleCpu),
    .main_detail_i               (saveStateMainReleaseDetailCpu),
    .main_stopped_i              (saveStateMainStopped),
    .main_captured_i             (saveStateMainCpuCaptured),
    .main_control_idle_i         (saveStateMainControlIdle),
    .main_ram_idle_i             (saveStateMainRamIdle),
    .main_register_idle_i        (saveStateMainRegisterIdle),
    .main_eeprom_idle_i          (saveStateMainEepromIdle),
    .main_terminal_i             (saveStateMainCommandTerminalFault),
    .main_destination_timeout_i  (saveStateMainReleaseDestinationTimeout),
    .main_destination_protocol_i (
      saveStateMainReleaseDestinationProtocolFault
    ),
    .main_destination_terminal_i (
      saveStateMainReleaseDestinationFault
    ),
    .main_release_cdc_state_i  (
      saveStateMainReleaseDestinationStateDebug
    ),
    .main_release_cdc_restore_hold_i (
      saveStateMainReleaseDestinationRestoreHoldDebug
    ),
    .main_release_cdc_command_valid_i (
      saveStateMainReleaseDestinationCommandValidDebug
    ),
    .main_release_cdc_command_i (
      saveStateMainReleaseDestinationCommandDebug
    ),
    .sound_request_i             (saveStateSoundReleaseRequestCpu),
    .sound_restore_i             (saveStateSoundReleaseRestoreCpu),
    .sound_complete_i            (_sound_io_ss_release_complete),
    .sound_command_state_i       (saveStateSoundReleaseDebugCpu[14:11]),
    .sound_release_state_i       (saveStateSoundReleaseDebugCpu[10:8]),
    .sound_proof_i               (saveStateSoundReleaseDebugCpu[7:2]),
    .sound_ready_i               (saveStateSoundReleaseDebugCpu[1]),
    .sound_pending_i             (_sound_io_ss_release_pending),
    .sound_stopped_i             (_sound_io_ss_stopped),
    .sound_external_idle_i       (saveStateSoundRomExternalIdleCpu),
    .sound_dependencies_ready_i  (saveStateSoundRomDependenciesCpu),
    .sound_owner_commit_idle_i   (saveStateSoundReleaseDebugCpu[0]),
    .sound_launch_done_i         (_sound_io_ss_restore_launch_done),
    .sound_terminal_i            (_sound_io_ss_terminal_fault),
    .sound_destination_timeout_i (
      saveStateSoundReleaseDestinationTimeout
    ),
    .sound_destination_protocol_i (
      saveStateSoundReleaseDestinationProtocolFault
    ),
    .sound_destination_terminal_i (
      saveStateSoundReleaseDestinationFault
    ),
    .probe_o                      (saveStateReleaseLaneDiagProbe)
  );

  altsource_probe #(
    .sld_auto_instance_index ("NO"),
    .sld_instance_index      (1),
    .instance_id             ("CBL"),
    .probe_width             (128),
    .source_width            (1),
    .source_initial_value    ("0"),
    .enable_metastability    ("NO")
  ) saveStateReleaseLaneHardwareProbe (
    .probe  (saveStateReleaseLaneDiagProbe),
    .source (saveStateReleaseLaneDiagSource)
  );
`endif
`ifdef CAVEBANPRESTO_SS_RELEASE_SLIM_HW_DIAGNOSTIC
  wire        saveStateReleaseSlimDiagSource;
  wire [15:0] saveStateReleaseSlimDiagProbe;

  CaveBanprestoSaveStateCdcBitSync
    saveStateMainCaptureAdmittedSeenSync (
    .clk_i   (clock),
    .reset_i (reset),
    .async_i (saveStateMainCaptureAdmittedSeenCpu),
    .sync_o  (saveStateMainCaptureAdmittedSeenSystem)
  );

  CaveBanprestoSaveStateReleaseSlimHardwareDiagnostic
    saveStateReleaseSlimHardwareDiagnostic (
    .clk_i                       (clock),
    .reset_i                     (reset),
    .page_select_i               ({1'b0, saveStateReleaseSlimDiagSource}),
    .game_index_i                (gameIndexReg),
    .controller_state_i          (saveStateControllerDebug),
    .quiesce_state_i             (saveStateQuiescePhase),
    .coordinator_state_i         (saveStateCoordinatorDebug),
    .ss_active_i                 (ss_active),
    .controller_active_i         (saveStateControllerActive),
    .quiesce_busy_i              (saveStateQuiesceBusy),
    .release_pending_i           (saveStateCoordinatorReleasePending),
    .main_request_i              (saveStateCoordinatorMainRelease),
    .main_restore_i              (saveStateCoordinatorReleaseRestore),
    .main_complete_i             (saveStateMainReleaseCompleteSystem),
    .main_ready_i                (saveStateMainReleaseReady),
    .main_busy_i                 (saveStateMainReleaseBusy),
    .sound_request_i             (saveStateCoordinatorSoundRelease),
    .sound_restore_i             (saveStateCoordinatorReleaseRestore),
    .sound_complete_i            (saveStateSoundReleaseCompleteSystem),
    .sound_ready_i               (saveStateSoundReleaseReady),
    .sound_busy_i                (saveStateSoundReleaseBusy),
    .controller_done_i           (saveStateControllerDone),
    .controller_success_i        (saveStateControllerSuccess),
    .raw_stream_done_i           (saveStateRawStreamDone),
    .raw_stream_success_i        (saveStateRawStreamSuccess),
    .quiesce_freeze_i            (saveStateQuiesceFreeze),
    .quiesce_resume_i            (saveStateControllerQuiesceResume),
    .release_complete_i          (saveStateCoordinatorReleaseComplete),
    .controller_accepted_event_i (saveStateControllerAccepted),
    .controller_rejected_event_i (saveStateControllerRejected),
    .controller_done_event_i     (saveStateControllerDone),
    .controller_success_event_i  (saveStateControllerSuccess),
    .controller_aborted_event_i  (saveStateControllerAborted),
    .main_request_event_i        (saveStateCoordinatorMainRelease),
    .main_complete_event_i       (saveStateMainReleaseCompleteSystem),
    .sound_request_event_i       (saveStateCoordinatorSoundRelease),
    .sound_complete_event_i      (saveStateSoundReleaseCompleteSystem),
    .capture_admitted_seen_i     (
      saveStateMainCaptureAdmittedSeenSystem
    ),
    .fault_flags_i               ({
      (saveStateControllerLastError != 8'd0),
      (saveStateControllerLastStreamError != 8'd0),
      (saveStateCoordinatorLastFault != 8'd0),
      saveStateInfrastructureFault,
      saveStateControllerOperationFatal,
      saveStateControllerFatal,
      saveStateQuiesceFatal,
      saveStateCoordinatorTerminalFault,
      saveStateRawStreamFatal,
      saveStateMainCommandTerminalFault,
      saveStateSoundCommandTerminalFault,
      saveStateMainReleaseSourceFault,
      saveStateMainReleaseDestinationFault,
      saveStateSoundReleaseSourceFault,
      saveStateSoundReleaseDestinationFault,
      saveStateMainCdcDestinationFault,
      saveStateSoundCdcDestinationFault
    }),
    .probe_o                     (saveStateReleaseSlimDiagProbe)
  );

  altsource_probe #(
    .sld_auto_instance_index ("NO"),
    .sld_instance_index      (0),
    .instance_id             ("CBS"),
    .probe_width             (16),
    .source_width            (1),
    .source_initial_value    ("0"),
    .enable_metastability    ("NO")
  ) saveStateReleaseSlimHardwareProbe (
    .probe  (saveStateReleaseSlimDiagProbe),
    .source (saveStateReleaseSlimDiagSource)
  );
`endif
`ifdef CAVEBANPRESTO_MET_SPRITE_PAGE_HW_DIAGNOSTIC
  altsource_probe #(
    .sld_auto_instance_index ("NO"),
    .sld_instance_index      (2),
    .instance_id             ("CBP"),
    .probe_width             (128),
    .source_width            (3),
    .source_initial_value    ("0"),
    .enable_metastability    ("NO")
  ) metmqstrSpritePageHardwareProbe (
    .probe  (metmqstrSpritePageDiagProbe),
    .source (metmqstrSpritePageDiagSource)
  );
`endif

  assign sdram_cke = 1'b1;
endmodule

// Metamoqester's CPU finishes populating the one-ahead delayed sprite bank
// after the ordinary falling-vblank render point. CB60 hardware timing bounds
// the last distinct-bank write at 6.776 ms and the worst full render at
// 6.756 ms before the fixed 15.360 ms swap. A 7.680 ms start balances the
// measured quiet/render margins at 0.904/0.924 ms without changing any other
// game's scheduler.
module CaveMetmqstrSpriteScheduler #(
  parameter integer START_DELAY_CYCLES = 737280
) (
  input  wire       clock_i,
  input  wire       reset_i,
  input  wire       ready_i,
  input  wire       enable_i,
  input  wire       block_new_work_i,
  input  wire       restore_load_i,
  input  wire [1:0] restore_active_bank_i,
  input  wire [1:0] restore_delayed_bank_i,
  input  wire       start_allowed_i,
  input  wire       vblank_rising_i,
  input  wire       vblank_falling_i,
  input  wire [1:0] selector_bank_i,
  output reg  [1:0] active_bank_o,
  output reg  [1:0] delayed_bank_o,
  output reg        sprite_start_o
);
  localparam integer DELAY_COUNTER_WIDTH =
    START_DELAY_CYCLES <= 1 ? 1 : $clog2(START_DELAY_CYCLES);

  reg [DELAY_COUNTER_WIDTH-1:0] delay_counter_q;
  reg                           start_pending_q;

  always @(posedge clock_i) begin
    sprite_start_o <= 1'b0;
    if (reset_i | ~ready_i | ~enable_i) begin
      active_bank_o <= 2'd0;
      delayed_bank_o <= 2'd0;
      delay_counter_q <= {DELAY_COUNTER_WIDTH{1'b0}};
      start_pending_q <= 1'b0;
    end
    else if (restore_load_i) begin
      active_bank_o <= restore_active_bank_i;
      delayed_bank_o <= restore_delayed_bank_i;
      delay_counter_q <= {DELAY_COUNTER_WIDTH{1'b0}};
      start_pending_q <= 1'b0;
    end
    else if (block_new_work_i) begin
      delay_counter_q <= {DELAY_COUNTER_WIDTH{1'b0}};
      start_pending_q <= 1'b0;
    end
    else begin
      if (vblank_rising_i)
        delayed_bank_o <= selector_bank_i;

      if (vblank_rising_i) begin
        delay_counter_q <= {DELAY_COUNTER_WIDTH{1'b0}};
        start_pending_q <= 1'b0;
      end
      else if (vblank_falling_i) begin
        if (start_allowed_i) begin
          delay_counter_q <= START_DELAY_CYCLES - 1;
          start_pending_q <= 1'b1;
        end
        else begin
          delay_counter_q <= {DELAY_COUNTER_WIDTH{1'b0}};
          start_pending_q <= 1'b0;
        end
      end
      else if (start_pending_q) begin
        if (delay_counter_q == {DELAY_COUNTER_WIDTH{1'b0}}) begin
          active_bank_o <= delayed_bank_o;
          sprite_start_o <= 1'b1;
          start_pending_q <= 1'b0;
        end
        else begin
          delay_counter_q <= delay_counter_q - 1'b1;
        end
      end
    end
  end
endmodule
