// This file is a Codex-assisted rewrite based on the original work of
// Josh Bassett (nullobject).

// Sound PCB integration: sound CPU, sample chips, banking, ROM arbitration, and mixing.
module Sound(
  input         clock,
  input         reset,
  input         io_ctrl_oki_0_wr,
  input  [15:0] io_ctrl_oki_0_din,
  output [15:0] io_ctrl_oki_0_dout,
  input         io_ctrl_oki_1_wr,
  input  [15:0] io_ctrl_oki_1_din,
  output [15:0] io_ctrl_oki_1_dout,
  input         io_ctrl_nmk_wr,
  input  [22:0] io_ctrl_nmk_addr,
  input  [15:0] io_ctrl_nmk_din,
  input         io_ctrl_ymz_rd,
  input         io_ctrl_ymz_wr,
  input  [22:0] io_ctrl_ymz_addr,
  input  [15:0] io_ctrl_ymz_din,
  output [15:0] io_ctrl_ymz_dout,
  input         io_ctrl_req,
  input  [15:0] io_ctrl_data,
  input         io_ctrl_reply_rd,
  output [15:0] io_ctrl_reply,
  output        io_ctrl_reply_empty,
  output        io_ctrl_irq,
  input  [3:0]  io_gameIndex,
  input  [1:0]  io_gameConfig_sound_0_device,
  input         io_audioConfigClock,
  input         io_audioConfigReset,
  input  [3:0]  io_audioTrim_fm,
  input  [3:0]  io_audioTrim_bgm,
  input  [3:0]  io_audioTrim_sfx,
  output        io_rom_0_rd,
  output [24:0] io_rom_0_addr,
  input  [7:0]  io_rom_0_dout,
  input         io_rom_0_wait_n,
  input         io_rom_0_valid,
  output        io_rom_1_rd,
  output [24:0] io_rom_1_addr,
  input  [7:0]  io_rom_1_dout,
  input         io_rom_1_valid,
  output        io_rom_2_rd,
  output [24:0] io_rom_2_addr,
  input  [7:0]  io_rom_2_dout,
  input         io_rom_2_valid,
  input tri0    io_ss_command_valid,
  input tri0 [15:0] io_ss_command,
  output        io_ss_command_complete,
  output [7:0]  io_ss_command_response,
  output        io_ss_command_terminal_fault,
  input         io_ss_stop_request,
  input         io_ss_restore_mode,
  input         io_ss_external_idle,
  input         io_ss_abort,
  input         io_ss_release_authorize,
  input         io_ss_release_restore,
  input         io_ss_restore_dependencies_ready,
  input         io_ss_state_enable,
  input         io_ss_restore_enable,
  input         io_ss_restore_begin,
  input         io_ss_restore_commit,
  input         io_ss_fatal,
  input  [47:0] io_ss_runtime_support,
  output        io_ss_stopped,
  output        io_ss_abort_ack,
  output        io_ss_restore_launch_done,
  output        io_ss_idle,
  output        io_ss_release_pending,
  output        io_ss_release_complete,
  output        io_ss_terminal_fault,
  cavebanpresto_ssbus_if.responder io_ssbus,
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
  output [14:0] io_ss_release_debug,
  output  [7:0] io_ss_owner_fault_debug,
`endif
  output [63:0] io_debug,
  output [15:0] io_audio
);
  wire        hotdogZ80;
  wire        mazingerZ80;
  wire        airgalletZ80;
  wire        sailormoonZ80;
  wire        metmqstrZ80;
  wire        airFamilyZ80Sound;
  wire        fastZ80Sound;
  wire        z80Game;
  wire        soundDeviceIsZ80;

  CaveBoardProfile boardProfile(
    .game_index                  (io_gameIndex),
    .sound_device                (io_gameConfig_sound_0_device),
    .game_is_dfeveron            (),
    .game_is_dodonpachi          (),
    .game_is_donpachi            (),
    .game_is_esprade             (),
    .game_is_uopoko              (),
    .game_is_guwange             (),
    .game_is_gaia                (),
    .game_is_hotdogstorm         (hotdogZ80),
    .game_is_mazinger            (mazingerZ80),
    .game_is_airgallet           (airgalletZ80),
    .game_is_sailormoon          (sailormoonZ80),
    .game_is_metmqstr            (metmqstrZ80),
    .board_uses_z80_sound        (z80Game),
    .board_is_vertical_clockwise (),
    .sound_is_ymz280b            (),
    .sound_is_oki                (),
    .sound_is_z80                (soundDeviceIsZ80)
  );

  assign airFamilyZ80Sound = airgalletZ80 | sailormoonZ80;
  assign fastZ80Sound = airFamilyZ80Sound | metmqstrZ80;

  reg         reqReg;
  reg  [15:0] dataReg;
  reg  [4:0]  z80BankReg;
  reg  [15:0] ym2203PsgAudioReg;
  reg  [15:0] ym2203FmAudioReg;
  reg  [15:0] ym2151AudioReg;
`ifdef CAVE_ENABLE_DEBUG_OVERLAY
  reg  [7:0]  debugLastSoundCommand;
  reg  [7:0]  debugLastReply;
  reg  [7:0]  debugLastLatchRead;
  reg  [7:0]  debugLastOkiBank;
  reg  [7:0]  debugLastOkiPhrase;
  reg  [7:0]  debugLastOkiStart;
  reg  [7:0]  debugLastYmAddr;
  reg  [7:0]  debugLastYmData;
  reg  [7:0]  debugLastIoAddr;
  reg  [7:0]  debugLastIoData;
  reg  [7:0]  debugLastOkiRomAddr;
  reg  [7:0]  debugLastOkiRomData;
  reg  [7:0]  debugLastZ80RomAddrHi;
  reg  [7:0]  debugLastZ80RomAddrLo;
  reg  [7:0]  debugLastZ80RomData;
  reg  [7:0]  debugFlags;
  reg  [15:0] debugMetZ80ProgressCount;
  reg  [15:0] debugMetOki0WaitCount;
  reg  [15:0] debugMetOki1WaitCount;
  reg         debugOkiPhrasePending;
`endif
  reg         z80IoWrD;
  reg  [7:0]  z80IoWrAddrD;
  reg  [7:0]  z80IoWrDataD;
  reg  [7:0]  replyFifo [0:31];
  reg  [4:0]  replyReadPtr;
  reg  [4:0]  replyWritePtr;
  reg  [5:0]  replyCount;
  reg  [63:0] mixerRestoreLowReg;
  reg         ssDeviceHoldReg;
  reg         ssReleaseRequiresCommitReg;

  wire [255:0] replyFifoState;
  wire [127:0] mixerLiveState;
  wire         wrapperRestoreWordWr;
  wire [2:0]   wrapperRestoreWordAddr;
  wire [63:0]  wrapperRestoreWordData;
  wire         mixerRestoreWr =
    wrapperRestoreWordWr & (wrapperRestoreWordAddr == 3'd7);
  wire [127:0] mixerRestoreState = {
    wrapperRestoreWordData,
    mixerRestoreLowReg
  };

  genvar replyStateIndex;
  generate
    for (replyStateIndex = 0; replyStateIndex < 32;
         replyStateIndex = replyStateIndex + 1) begin : gen_reply_state
      assign replyFifoState[replyStateIndex*8 +: 8] =
        replyFifo[replyStateIndex];
    end
  endgenerate

  wire [15:0] cpuAddr;
  wire [7:0]  cpuDout;
  wire        cpuM1;
  wire        cpuRd;
  wire        cpuWr;
  wire        cpuRfsh;
  wire        cpuMreq;
  wire        cpuIorq;
  wire        cpuInt;
  wire        ym2203Irq;
  wire        ym2151Irq;

  wire [211:0] ssT80LiveReg;
  wire  [26:0] ssT80LiveAux;
  wire   [2:0] ssT80LiveDivider;
  wire [211:0] ssT80RestoreReg;
  wire  [26:0] ssT80RestoreAux;
  wire   [2:0] ssT80RestoreDivider;
  wire         ssT80RestoreLoad;
  wire         ssT80BoundarySafe;
  wire         ssT80CpuCen;
  wire         ssT80CpuTerminalFault;
  wire         ssT80OwnerTerminalFault;
  wire         ssT80ValidationComplete;
  wire         ssT80ValidationValid;
  wire         ssT80WriteComplete;
  wire         ssT80WriteValid;
  wire         ssT80RestoreCommitted;

  wire         ssWrapperValidationComplete;
  wire         ssWrapperValidationValid;
  wire         ssWrapperWriteComplete;
  wire         ssWrapperWriteValid;
  wire         ssWrapperRestoreCommitted;
  wire         ssWrapperTerminalFault;
  wire         ssWrapperIdle;

  wire         ssYm2203Idle;
  wire         ssYm2151Idle;
  wire         ssOki0Idle;
  wire         ssOki1Idle;
  wire         ssOki0ValidationComplete;
  wire         ssOki0ValidationValid;
  wire         ssOki0WriteComplete;
  wire         ssOki0WriteValid;
  wire         ssOki0RestorePrime;
  wire         ssOki0RestoreCommitted;
  wire         ssOki0TerminalFault;
  wire         ssOki1ValidationComplete;
  wire         ssOki1ValidationValid;
  wire         ssOki1WriteComplete;
  wire         ssOki1WriteValid;
  wire         ssOki1RestorePrime;
  wire         ssOki1RestoreCommitted;
  wire         ssOki1TerminalFault;

  wire         ssBusMultipleAck;
  wire         ssBusTimeout;
  wire         ssBusFault;
  wire         ssBusIdle;
  wire         ssSoundRelease;
  wire         ssReleaseReady;
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
  wire [3:0]   ssCommandStateDebug;
  wire [2:0]   ssReleaseStateDebug;
  wire [5:0]   ssReleaseProofDebug;
`endif
  wire         ssReleaseTerminalFault;
  wire         ssSoundOwnerFatal;
  wire         ssOwnerCommitIdle;
  wire         ssAllDevicesIdle;
  wire         audioConfigIdle;
  wire         ssSoundRamTakeover;
  wire         ssOwner23Required;
  wire         ssOwner25Required;
  wire         ssOwner28Required;
  wire         ssOwner29Required;
  wire  [6:0]  ssOwnerRequiredEvidence;
  wire  [6:0]  ssOwnerIdleEvidence;
  wire  [6:0]  ssOwnerCommitReadyEvidence;
  wire  [6:0]  ssOwnerCommittedEvidence;
  wire  [6:0]  ssOwnerPrimeEvidence;

  wire         ssCommandStopRequest;
  wire         ssCommandRestoreMode;
  wire         ssCommandStateEnable;
  wire         ssCommandRestoreEnable;
  wire         ssCommandAbort;
  wire         ssCommandRestoreBegin;
  wire         ssCommandDeviceRestoreCommit;
  wire         ssCommandT80RestoreCommit;

  // Retain the lower-level direct controls for focused owner bring-up.  The
  // ordered command path adds a split device/T80 commit without changing that
  // legacy direct-control behavior.
  wire         ssStopRequest =
    io_ss_stop_request | ssCommandStopRequest;
  wire         ssRestoreMode =
    ssCommandStopRequest ? ssCommandRestoreMode : io_ss_restore_mode;
  wire         ssStateEnable =
    io_ss_state_enable | ssCommandStateEnable;
  wire         ssRestoreEnable =
    io_ss_restore_enable | ssCommandRestoreEnable;
  wire         ssAbort =
    io_ss_abort | ssCommandAbort;
  wire         ssRestoreBegin =
    io_ss_restore_begin | ssCommandRestoreBegin;
  wire         ssDeviceRestoreCommit =
    io_ss_restore_commit | ssCommandDeviceRestoreCommit;
  wire         ssT80RestoreCommit =
    io_ss_restore_commit | ssCommandT80RestoreCommit;

  cavebanpresto_ssbus_if soundOwnerBus [7] ();

  wire        z80ProgRomSelect = cpuAddr < 16'h4000;
  wire        z80BankRomSelect = (|cpuAddr[15:14]) & ~cpuAddr[15];
  wire        z80RamSelect =
    (hotdogZ80 | metmqstrZ80) ? cpuAddr > 16'hDFFF :
    mazingerZ80 ? ((cpuAddr > 16'hBFFF) & (cpuAddr < 16'hC800)) | (cpuAddr > 16'hF7FF) :
    airFamilyZ80Sound ? cpuAddr >= 16'hC000 :
                  1'b0;
  wire [15:0] cpuIoAddr = {8'h00, cpuAddr[7:0]};
  wire        z80IoWr = z80Game & cpuIorq & cpuWr;
  wire        z80IoWrChanged =
    z80IoWr & ((cpuIoAddr[7:0] != z80IoWrAddrD) | (cpuDout != z80IoWrDataD));
  wire        z80IoWrPulse = z80IoWr & (~z80IoWrD | (fastZ80Sound & z80IoWrChanged));
  wire        latchLowRead = z80Game & (cpuIoAddr == 16'h0030) & cpuIorq & cpuRd;
  wire        latchHighRead = (hotdogZ80 | fastZ80Sound) & (cpuIoAddr == 16'h0040) & cpuIorq & cpuRd;
  wire        soundFlagsRead = fastZ80Sound & (cpuIoAddr == 16'h0020) & cpuIorq & cpuRd;
  wire        airYm2151Access = fastZ80Sound & (cpuIoAddr > 16'h004F) & (cpuIoAddr < 16'h0052) & cpuIorq;
  wire        airYm2151Write = airYm2151Access & z80IoWrPulse;
  wire        airYm2151Read = airYm2151Access & cpuRd;
  wire        ym2203ClassicWrite =
    ~fastZ80Sound & z80Game &
    (cpuIoAddr > 16'h004F) & (cpuIoAddr < 16'h0052) & z80IoWrPulse;
  wire        ym2203ClassicRead =
    ((hotdogZ80 & (cpuIoAddr > 16'h004F) & (cpuIoAddr < 16'h0052)) |
     (mazingerZ80 & (cpuIoAddr > 16'h0051) & (cpuIoAddr < 16'h0054))) & cpuIorq & cpuRd;
  wire        ym2203Write = ym2203ClassicWrite;
  wire        ym2203Read = ym2203ClassicRead;
  wire        oki0Access =
    (fastZ80Sound & (cpuIoAddr == 16'h0060)) & cpuIorq;
  wire        oki1Access =
    ((hotdogZ80 & (cpuIoAddr == 16'h0060)) |
     (fastZ80Sound & (cpuIoAddr == 16'h0080)) |
     (mazingerZ80 & (cpuIoAddr == 16'h0070))) & cpuIorq;
  wire        airgalletOki0BankWrite = fastZ80Sound & (cpuIoAddr == 16'h0070) & z80IoWrPulse;
  wire        airgalletOki1BankWrite =
    ((airFamilyZ80Sound & (cpuIoAddr == 16'h00C0)) |
     (metmqstrZ80 & (cpuIoAddr == 16'h0090))) & z80IoWrPulse;
  wire        hotdogOkiBankWrite = hotdogZ80 & (cpuIoAddr == 16'h0070) & z80IoWrPulse;
  wire        mazingerOkiBankWrite = mazingerZ80 & (cpuIoAddr == 16'h0074) & z80IoWrPulse;
  wire        oki0BankWrite = airgalletOki0BankWrite;
  wire        oki1BankWrite = airgalletOki1BankWrite | hotdogOkiBankWrite | mazingerOkiBankWrite;
  wire        soundReplyWrite = (mazingerZ80 | airFamilyZ80Sound) & (cpuIoAddr == 16'h0010) & z80IoWrPulse;
  wire        replyPop = io_ctrl_reply_rd & (replyCount != 6'd0);
  wire        replyPush = soundReplyWrite & ((replyCount != 6'd32) | replyPop);

  wire [7:0]  soundRamDout;
  wire        soundRamRd = z80Game & z80RamSelect & ~cpuRfsh;
  wire        soundRamWr = z80Game & z80RamSelect & cpuMreq & cpuWr;

  wire [7:0]  progRomDout;
  wire        progRomValid;
  wire [7:0]  bankRomDout;
  wire        bankRomValid;
  wire        z80RomRead = z80Game & cpuMreq & cpuRd & ~cpuRfsh & (z80ProgRomSelect | z80BankRomSelect);
  wire        z80ProgRomArbiterRead =
    soundDeviceIsZ80 & z80Game & z80ProgRomSelect & ~cpuRfsh &
    (fastZ80Sound ? (cpuMreq & cpuRd) : 1'b1);
  wire        z80BankRomArbiterRead =
    soundDeviceIsZ80 & z80Game & z80BankRomSelect & ~cpuRfsh &
    (fastZ80Sound ? (cpuMreq & cpuRd) : 1'b1);
  wire        z80RomValid = z80BankRomSelect ? bankRomValid : progRomValid;
  // z80RomRead is already qualified by z80Game.  Wait every Z80 profile for
  // the address-tagged response without adding a second copy of that decode.
  // The legacy slow profiles previously consumed a stale held response before
  // its address matched.
  wire        z80WaitN = ~z80RomRead | z80RomValid;
  wire [7:0]  romOrBankDout = z80BankRomSelect & cpuMreq & cpuRd ? bankRomDout : progRomDout;

  wire [7:0]  oki0CpuDout;
  wire        oki0RomRead;
  wire [17:0] oki0RomAddr;
  wire [7:0]  oki0RomDout;
  wire        oki0RomValid;
  wire        oki0AudioValid;
  wire [13:0] oki0Audio;
  wire [13:0] oki0AudioHold;
  wire [3:0]  oki0BankHi;
  wire [3:0]  oki0BankLo;
  wire        z80Oki0CpuWr = oki0Access & z80IoWrPulse;
  wire        oki0CpuWrRaw =
    fastZ80Sound ? z80Oki0CpuWr : io_ctrl_oki_0_wr;
  wire [7:0]  oki0CpuDinRaw =
    fastZ80Sound ? cpuDout : io_ctrl_oki_0_din[7:0];
  wire        oki0CpuWr = oki0CpuWrRaw;
  wire [7:0]  oki0CpuDin = oki0CpuDinRaw;
  // The 32 MHz master-clock accumulator steps are fixed by the MAME 0.288
  // board profiles: 0x0873 ~= 1.056 MHz, 0x1000 = 2.000 MHz, and
  // 0x10E5 ~= 2.112 MHz.
  wire [16:0] oki0CenStep =
    metmqstrZ80 ? 17'h1000 :
    fastZ80Sound ? 17'h10E5 :
                   17'h0873;

  wire [7:0]  oki1CpuDout;
  wire        oki1RomRead;
  wire [17:0] oki1RomAddr;
  wire        oki1AudioValid;
  wire [13:0] oki1Audio;
  wire [13:0] oki1AudioHold;
  wire [3:0]  oki1BankHi;
  wire [3:0]  oki1BankLo;
  wire        z80Oki1CpuWr = oki1Access & z80IoWrPulse;
  wire        oki1CpuWrRaw = z80Game ? z80Oki1CpuWr : io_ctrl_oki_1_wr;
  wire [7:0]  oki1CpuDinRaw = z80Game ? cpuDout : io_ctrl_oki_1_din[7:0];
  wire        oki1CpuWr = oki1CpuWrRaw;
  wire [7:0]  oki1CpuDin = oki1CpuDinRaw;
  wire [16:0] oki1CenStep =
    (hotdogZ80 | metmqstrZ80) ? 17'h1000 :
    mazingerZ80 ? 17'h0873 :
                  17'h10E5;
  wire [7:0]  ym2203CpuDout;
  wire        ym2203AudioValid;
  wire [15:0] ym2203PsgAudio;
  wire [15:0] ym2203FmAudio;
  wire [7:0]  ym2151CpuDout;
  wire        ym2151AudioValid;
  wire [15:0] ym2151Audio;
  wire [7:0]  cpuDin =
    oki0Access & cpuRd    ? oki0CpuDout :
    oki1Access & cpuRd    ? oki1CpuDout :
    airYm2151Read         ? ym2151CpuDout :
    ym2203Read            ? ym2203CpuDout :
    soundFlagsRead        ? 8'h00 :
    latchHighRead         ? dataReg[15:8] :
    latchLowRead          ? dataReg[7:0] :
    z80RamSelect & cpuMreq & cpuRd ? soundRamDout :
    romOrBankDout;

  wire [3:0]  oki0Bank = oki0RomAddr[17] ? oki0BankHi : oki0BankLo;
  wire [3:0]  oki1Bank = oki1RomAddr[17] ? oki1BankHi : oki1BankLo;
  wire [3:0]  oki0BankHiDin =
    metmqstrZ80 ? {1'b0, cpuDout[6:4]} : cpuDout[7:4];
  wire [3:0]  oki0BankLoDin =
    metmqstrZ80 ? {1'b0, cpuDout[2:0]} : cpuDout[3:0];
  wire [3:0]  oki1BankHiDin =
    metmqstrZ80 ? {1'b0, cpuDout[6:4]} :
    airFamilyZ80Sound ? cpuDout[7:4] :
                        {2'b00, cpuDout[5:4]};
  wire [3:0]  oki1BankLoDin =
    metmqstrZ80 ? {1'b0, cpuDout[2:0]} :
    airFamilyZ80Sound ? cpuDout[3:0] :
                        {2'b00, cpuDout[1:0]};
  wire [24:0] defaultOki0MappedAddr = {4'h0, oki0Bank, oki0RomAddr[16:0]};
  wire [24:0] airOki0MappedAddr = defaultOki0MappedAddr;
  wire [24:0] airOki1MappedAddr = {4'h0, oki1Bank, oki1RomAddr[16:0]};
  wire [24:0] sailorMoonOki1MappedAddr = {6'h00, oki1Bank[1:0], oki1RomAddr[16:0]};
  wire [24:0] fastOki1MappedAddr =
    sailormoonZ80 ? sailorMoonOki1MappedAddr : airOki1MappedAddr;
  wire [24:0] oki0MappedAddr = defaultOki0MappedAddr;
  wire [24:0] oki1MappedAddr = {4'h0, oki1Bank, oki1RomAddr[16:0]};
  wire [7:0]  oki0RomData = fastZ80Sound ? io_rom_1_dout : oki0RomDout;
  wire        oki0RomDataValid = fastZ80Sound ? io_rom_1_valid : oki0RomValid;
  wire [7:0]  oki1RomData = fastZ80Sound ? io_rom_2_dout : io_rom_1_dout;
  wire        oki1RomDataValid = fastZ80Sound ? io_rom_2_valid : io_rom_1_valid;
`ifdef CAVE_ENABLE_DEBUG_OVERLAY
  wire        debugOki1RomDataValid = mazingerZ80 ? io_rom_1_valid : oki1RomDataValid;
  wire        z80WaitingForRom = z80RomRead & ~z80RomValid;
  wire        oki0WaitingForRom = oki0RomRead & ~oki0RomDataValid;
  wire        oki1WaitingForRom = oki1RomRead & ~oki1RomDataValid;
  wire        z80Progress =
    (z80RomRead & z80RomValid) |
    z80IoWrPulse |
    (cpuIorq & cpuRd) |
    (z80RamSelect & cpuMreq & (cpuRd | cpuWr));
  wire [7:0]  metDebugFlags = {
    ym2151AudioValid,
    oki1AudioValid,
    oki0AudioValid,
    z80Progress,
    z80WaitingForRom,
    reqReg,
    oki1WaitingForRom,
    oki0WaitingForRom
  };
`endif

  always @(posedge clock) begin
    if (reset) begin
      reqReg <= 1'b0;
      dataReg <= 16'h0000;
      z80BankReg <= 5'h0;
      ym2203PsgAudioReg <= 16'h0000;
      ym2203FmAudioReg <= 16'h0000;
      ym2151AudioReg <= 16'h0000;
      mixerRestoreLowReg <= 64'h0000_0000_0000_0000;
`ifdef CAVE_ENABLE_DEBUG_OVERLAY
      debugLastSoundCommand <= 8'h00;
      debugLastReply <= 8'h00;
      debugLastLatchRead <= 8'h00;
      debugLastOkiBank <= 8'h00;
      debugLastOkiPhrase <= 8'h00;
      debugLastOkiStart <= 8'h00;
      debugLastYmAddr <= 8'h00;
      debugLastYmData <= 8'h00;
      debugLastIoAddr <= 8'h00;
      debugLastIoData <= 8'h00;
      debugLastOkiRomAddr <= 8'h00;
      debugLastOkiRomData <= 8'h00;
      debugLastZ80RomAddrHi <= 8'h00;
      debugLastZ80RomAddrLo <= 8'h00;
      debugLastZ80RomData <= 8'h00;
      debugFlags <= 8'h00;
      debugMetZ80ProgressCount <= 16'h0000;
      debugMetOki0WaitCount <= 16'h0000;
      debugMetOki1WaitCount <= 16'h0000;
      debugOkiPhrasePending <= 1'b0;
`endif
      z80IoWrD <= 1'b0;
      z80IoWrAddrD <= 8'h00;
      z80IoWrDataD <= 8'h00;
      replyReadPtr <= 5'd0;
      replyWritePtr <= 5'd0;
      replyCount <= 6'd0;
    end
    else if (wrapperRestoreWordWr) begin
      unique case (wrapperRestoreWordAddr)
        3'd0: begin
          reqReg <= wrapperRestoreWordData[38];
          z80BankReg <= wrapperRestoreWordData[37:33];
          dataReg <= wrapperRestoreWordData[32:17];
          z80IoWrD <= wrapperRestoreWordData[16];
          z80IoWrAddrD <= wrapperRestoreWordData[15:8];
          z80IoWrDataD <= wrapperRestoreWordData[7:0];
        end
        3'd1: begin
          replyCount <= wrapperRestoreWordData[63:58];
          replyWritePtr <= wrapperRestoreWordData[57:53];
          replyReadPtr <= wrapperRestoreWordData[52:48];
          ym2151AudioReg <= wrapperRestoreWordData[47:32];
          ym2203FmAudioReg <= wrapperRestoreWordData[31:16];
          ym2203PsgAudioReg <= wrapperRestoreWordData[15:0];
        end
        3'd2: begin
          replyFifo[0] <= wrapperRestoreWordData[7:0];
          replyFifo[1] <= wrapperRestoreWordData[15:8];
          replyFifo[2] <= wrapperRestoreWordData[23:16];
          replyFifo[3] <= wrapperRestoreWordData[31:24];
          replyFifo[4] <= wrapperRestoreWordData[39:32];
          replyFifo[5] <= wrapperRestoreWordData[47:40];
          replyFifo[6] <= wrapperRestoreWordData[55:48];
          replyFifo[7] <= wrapperRestoreWordData[63:56];
        end
        3'd3: begin
          replyFifo[8] <= wrapperRestoreWordData[7:0];
          replyFifo[9] <= wrapperRestoreWordData[15:8];
          replyFifo[10] <= wrapperRestoreWordData[23:16];
          replyFifo[11] <= wrapperRestoreWordData[31:24];
          replyFifo[12] <= wrapperRestoreWordData[39:32];
          replyFifo[13] <= wrapperRestoreWordData[47:40];
          replyFifo[14] <= wrapperRestoreWordData[55:48];
          replyFifo[15] <= wrapperRestoreWordData[63:56];
        end
        3'd4: begin
          replyFifo[16] <= wrapperRestoreWordData[7:0];
          replyFifo[17] <= wrapperRestoreWordData[15:8];
          replyFifo[18] <= wrapperRestoreWordData[23:16];
          replyFifo[19] <= wrapperRestoreWordData[31:24];
          replyFifo[20] <= wrapperRestoreWordData[39:32];
          replyFifo[21] <= wrapperRestoreWordData[47:40];
          replyFifo[22] <= wrapperRestoreWordData[55:48];
          replyFifo[23] <= wrapperRestoreWordData[63:56];
        end
        3'd5: begin
          replyFifo[24] <= wrapperRestoreWordData[7:0];
          replyFifo[25] <= wrapperRestoreWordData[15:8];
          replyFifo[26] <= wrapperRestoreWordData[23:16];
          replyFifo[27] <= wrapperRestoreWordData[31:24];
          replyFifo[28] <= wrapperRestoreWordData[39:32];
          replyFifo[29] <= wrapperRestoreWordData[47:40];
          replyFifo[30] <= wrapperRestoreWordData[55:48];
          replyFifo[31] <= wrapperRestoreWordData[63:56];
        end
        3'd6: begin
          mixerRestoreLowReg <= wrapperRestoreWordData;
        end
        default: begin
        end
      endcase
    end
    else if (!ssDeviceHoldReg) begin
      z80IoWrD <= z80IoWr;
      if (z80IoWr) begin
        z80IoWrAddrD <= cpuIoAddr[7:0];
        z80IoWrDataD <= cpuDout;
      end

      reqReg <= ~(z80Game & (latchHighRead | latchLowRead)) & (io_ctrl_req | reqReg);
`ifdef CAVE_ENABLE_DEBUG_OVERLAY
      debugFlags <= debugFlags | (mazingerZ80 ? {
        oki1AudioValid,
        |oki1AudioHold,
        oki1RomDataValid,
        oki1RomRead,
        z80Oki1CpuWr,
        oki1CpuWr,
        oki1Access & cpuRd,
        ym2203Read
      } : {
        debugOki1RomDataValid,
        oki1RomRead,
        z80Oki1CpuWr,
        ym2203Write,
        soundReplyWrite,
        latchHighRead,
        latchLowRead,
        io_ctrl_req
      });

      if (io_ctrl_req)
        debugLastSoundCommand <= io_ctrl_data[7:0];

      if (z80IoWrPulse & (cpuIoAddr[7:0] != 8'h10) & (~mazingerZ80 | ym2203Write | z80Oki1CpuWr | oki1BankWrite)) begin
        debugLastIoAddr <= cpuIoAddr[7:0];
        debugLastIoData <= cpuDout;
      end

      if (latchLowRead)
        debugLastLatchRead <= dataReg[7:0];
      else if (latchHighRead)
        debugLastLatchRead <= dataReg[15:8];

      if (oki1BankWrite)
        debugLastOkiBank <= cpuDout;

      if (z80Oki1CpuWr) begin
        if (cpuDout[7]) begin
          debugLastOkiPhrase <= cpuDout;
          debugOkiPhrasePending <= 1'b1;
        end
        else if (debugOkiPhrasePending) begin
          debugLastOkiStart <= cpuDout;
          debugOkiPhrasePending <= 1'b0;
        end
        else begin
          debugLastOkiStart <= cpuDout;
        end
      end

      if (ym2203Write) begin
        if (cpuIoAddr[0])
          debugLastYmData <= cpuDout;
        else
          debugLastYmAddr <= cpuDout;
      end

      if (mazingerZ80 & oki1RomRead)
        debugLastOkiRomAddr <= oki1RomAddr[7:0];
      else if (oki1RomDataValid)
        debugLastOkiRomAddr <= oki1MappedAddr[23:16];

      if (debugOki1RomDataValid) begin
        debugLastOkiRomData <= oki1RomData;
      end

      if (mazingerZ80 & z80RomRead & z80RomValid) begin
        debugLastZ80RomAddrHi <= cpuAddr[15:8];
        debugLastZ80RomAddrLo <= cpuAddr[7:0];
        debugLastZ80RomData <= romOrBankDout;
      end

      if (metmqstrZ80) begin
        if (z80Progress)
          debugMetZ80ProgressCount <= debugMetZ80ProgressCount + 16'h0001;
        if (oki0WaitingForRom)
          debugMetOki0WaitCount <= debugMetOki0WaitCount + 16'h0001;
        if (oki1WaitingForRom)
          debugMetOki1WaitCount <= debugMetOki1WaitCount + 16'h0001;
      end
`endif

      if (z80Game & (cpuIoAddr == 16'h0000) & z80IoWrPulse)
        z80BankReg <=
          metmqstrZ80 ? {1'b0, cpuDout[3:0]} :
          airFamilyZ80Sound ? cpuDout[4:0] :
          mazingerZ80 ? {2'b00, cpuDout[2:0]} :
                        {1'b0, cpuDout[3:0]};

      if (replyPush) begin
        replyFifo[replyWritePtr] <= cpuDout;
        replyWritePtr <= replyWritePtr + 5'd1;
`ifdef CAVE_ENABLE_DEBUG_OVERLAY
        debugLastReply <= cpuDout;
`endif
      end

      if (replyPop)
        replyReadPtr <= replyReadPtr + 5'd1;

      case ({replyPush, replyPop})
        2'b10: replyCount <= replyCount + 6'd1;
        2'b01: replyCount <= replyCount - 6'd1;
        default: begin
        end
      endcase

      if (io_ctrl_req)
        dataReg <= io_ctrl_data;

      if (ym2203AudioValid) begin
        ym2203PsgAudioReg <= ym2203PsgAudio;
        ym2203FmAudioReg <= ym2203FmAudio;
      end

      if (ym2151AudioValid)
        ym2151AudioReg <= ym2151Audio;
    end
  end

  // The device/RAM hold is admitted only after the exact T80 is stopped and
  // owner 34 proves every previously accepted ROM transaction has retired.
  // Once acquired, it remains sticky through owner traffic and dependency
  // prefetch; only the exact CPU release or a write-free abort clears it.
  always @(posedge clock) begin
    if (reset)
      ssDeviceHoldReg <= 1'b0;
    else if (ssSoundRelease || io_ss_abort_ack)
      ssDeviceHoldReg <= 1'b0;
    else if (io_ss_stopped && io_ss_external_idle)
      ssDeviceHoldReg <= 1'b1;
  end

  always @(posedge clock) begin
    if (reset)
      ssReleaseRequiresCommitReg <= 1'b0;
    else if (ssSoundRelease || io_ss_abort_ack)
      ssReleaseRequiresCommitReg <= 1'b0;
    else if (io_ss_release_authorize)
      ssReleaseRequiresCommitReg <= io_ss_release_restore;
  end

  CaveBanprestoSoundZ80SaveState cpu (
    .clock                              (clock),
    .reset                              (reset),
    .io_addr                            (cpuAddr),
    .io_din                             (cpuDin),
    .io_dout                            (cpuDout),
    .io_m1                              (cpuM1),
    .io_rd                              (cpuRd),
    .io_wr                              (cpuWr),
    .io_rfsh                            (cpuRfsh),
    .io_mreq                            (cpuMreq),
    .io_iorq                            (cpuIorq),
    .io_fast_clock                      (fastZ80Sound),
    .io_wait_n                          (z80WaitN),
    .io_int                             (cpuInt),
    .io_nmi                             (reqReg),
    .ss_stop_request_i                  (ssStopRequest),
    .ss_restore_mode_i                  (ssRestoreMode),
    .ss_external_idle_i                 (io_ss_external_idle),
    .ss_abort_i                         (ssAbort),
    .ss_release_i                       (ssSoundRelease),
    .ss_release_restore_i               (ssReleaseRequiresCommitReg),
    .ss_restore_dependencies_ready_i    (
      io_ss_restore_dependencies_ready
    ),
    .ss_restore_load_i                  (ssT80RestoreLoad),
    .ss_restore_reg_i                   (ssT80RestoreReg),
    .ss_restore_aux_i                   (ssT80RestoreAux),
    .ss_restore_divider_i               (ssT80RestoreDivider),
    .ss_live_reg_o                      (ssT80LiveReg),
    .ss_live_aux_o                      (ssT80LiveAux),
    .ss_live_divider_o                  (ssT80LiveDivider),
    .ss_boundary_safe_o                 (ssT80BoundarySafe),
    .ss_stopped_o                       (io_ss_stopped),
    .ss_abort_ack_o                     (io_ss_abort_ack),
    .ss_restore_launch_done_o           (
      io_ss_restore_launch_done
    ),
    .ss_terminal_fault_o                (ssT80CpuTerminalFault),
    .ss_cpu_cen_o                       (ssT80CpuCen)
  );

  CaveBanprestoT80SaveStateOwner #(
    .OWNER_INDEX(8'd23)
  ) soundCpuOwner (
    .clk_i                 (clock),
    .reset_i               (reset),
    .restore_begin_i       (
      ssRestoreBegin & io_ss_runtime_support[23]
    ),
    .restore_commit_i      (
      ssT80RestoreCommit & io_ss_runtime_support[23]
    ),
    .live_reg_i            (ssT80LiveReg),
    .live_aux_i            (ssT80LiveAux),
    .live_divider_i        (ssT80LiveDivider),
    .restore_reg_o         (ssT80RestoreReg),
    .restore_aux_o         (ssT80RestoreAux),
    .restore_divider_o     (ssT80RestoreDivider),
    .restore_load_o        (ssT80RestoreLoad),
    .validation_complete_o (ssT80ValidationComplete),
    .validation_valid_o    (ssT80ValidationValid),
    .write_complete_o      (ssT80WriteComplete),
    .write_valid_o         (ssT80WriteValid),
    .restore_committed_o   (ssT80RestoreCommitted),
    .terminal_fault_o      (ssT80OwnerTerminalFault),
    .ssbus                 (soundOwnerBus[0])
  );

  CaveBanprestoSoundRamSaveStateOwner soundRam (
    .clk_i                 (clock),
    .reset_i               (reset),
    .takeover_permitted_i  (ssDeviceHoldReg),
    .runtime_rd_i          (soundRamRd),
    .runtime_wr_i          (soundRamWr),
    .runtime_addr_i        (cpuAddr[12:0]),
    .runtime_din_i         (cpuDout),
    .runtime_dout_o        (soundRamDout),
    .state_takeover_o      (ssSoundRamTakeover),
    .ssbus                 (soundOwnerBus[1])
  );

  CaveBanprestoSoundWrapperStatePort soundWrapperOwner (
    .clk_i                       (clock),
    .reset_i                     (reset),
    .state_enable_i              (ssStateEnable),
    .restore_enable_i            (ssRestoreEnable),
    .restore_begin_i             (
      ssRestoreBegin & io_ss_runtime_support[25]
    ),
    .restore_commit_i            (
      ssDeviceRestoreCommit & io_ss_runtime_support[25]
    ),
    .live_use_ym2151_i           (fastZ80Sound),
    .live_request_i              (reqReg),
    .live_command_data_i         (dataReg),
    .live_z80_bank_i             (z80BankReg),
    .live_ym2203_psg_i           (ym2203PsgAudioReg),
    .live_ym2203_fm_i            (ym2203FmAudioReg),
    .live_ym2151_i               (ym2151AudioReg),
    .live_z80_io_write_d_i       (z80IoWrD),
    .live_z80_io_write_addr_i    (z80IoWrAddrD),
    .live_z80_io_write_data_i    (z80IoWrDataD),
    .live_reply_fifo_i           (replyFifoState),
    .live_reply_read_ptr_i       (replyReadPtr),
    .live_reply_write_ptr_i      (replyWritePtr),
    .live_reply_count_i          (replyCount),
    .live_mixer_state_i          (mixerLiveState),
    .restore_word_wr_o           (wrapperRestoreWordWr),
    .restore_word_addr_o         (wrapperRestoreWordAddr),
    .restore_word_data_o         (wrapperRestoreWordData),
    .validation_complete_o       (ssWrapperValidationComplete),
    .validation_valid_o          (ssWrapperValidationValid),
    .write_complete_o            (ssWrapperWriteComplete),
    .write_valid_o               (ssWrapperWriteValid),
    .restore_committed_o         (ssWrapperRestoreCommitted),
    .terminal_fault_o            (ssWrapperTerminalFault),
    .owner_idle_o                (ssWrapperIdle),
    .ssbus                       (soundOwnerBus[2])
  );

  CaveBanprestoOKIExactSaveStateOwner #(
    .OWNER_INDEX(8'd28),
    .INTERPOL(1),
    .WRITE_HOLD_CYCLES(8)
  ) oki_0 (
    .clock           (clock),
    .reset           (reset),
    .io_cen_step     (oki0CenStep),
    .io_cpu_wr       (oki0CpuWr),
    .io_cpu_din      (oki0CpuDin),
    .io_stretch_cpu_wr (fastZ80Sound),
    .io_wait_for_rom (fastZ80Sound),
    .io_cpu_dout     (oki0CpuDout),
    .io_rom_rd       (oki0RomRead),
    .io_rom_addr     (oki0RomAddr),
    .io_rom_cache_addr (fastZ80Sound ? airOki0MappedAddr : oki0MappedAddr),
    .io_rom_dout     (oki0RomData),
    .io_rom_valid    (oki0RomDataValid),
    .io_audio_valid  (oki0AudioValid),
    .io_audio_bits   (oki0Audio),
    .io_audio_hold_bits (oki0AudioHold),
    .io_bank_load    (oki0BankWrite & ~ssDeviceHoldReg),
    .io_bank_hi_din  (oki0BankHiDin),
    .io_bank_lo_din  (oki0BankLoDin),
    .io_bank_hi      (oki0BankHi),
    .io_bank_lo      (oki0BankLo),
    .io_ss_hold_i    (ssDeviceHoldReg),
    .io_ss_restore_enable_i (ssRestoreEnable),
    .restore_begin_i (
      ssRestoreBegin & io_ss_runtime_support[28]
    ),
    .restore_commit_i (
      ssDeviceRestoreCommit & io_ss_runtime_support[28]
    ),
    .io_ss_idle_o    (ssOki0Idle),
    .validation_complete_o (ssOki0ValidationComplete),
    .validation_valid_o (ssOki0ValidationValid),
    .write_complete_o (ssOki0WriteComplete),
    .write_valid_o   (ssOki0WriteValid),
    .restore_prime_o (ssOki0RestorePrime),
    .restore_committed_o (ssOki0RestoreCommitted),
    .terminal_fault_o (ssOki0TerminalFault),
    .ssbus           (soundOwnerBus[5])
  );

  CaveBanprestoOKIExactSaveStateOwner #(
    .OWNER_INDEX(8'd29),
    .INTERPOL(1),
    .WRITE_HOLD_CYCLES(8)
  ) oki_1 (
    .clock           (clock),
    .reset           (reset),
    .io_cen_step     (oki1CenStep),
    .io_cpu_wr       (oki1CpuWr),
    .io_cpu_din      (oki1CpuDin),
    .io_stretch_cpu_wr (fastZ80Sound),
    // Every Z80 board uses the tagged lane-1 transport.  Reuse the existing
    // board predicate so Hotdog Storm cannot advance on the prior address's
    // byte without synthesizing another five-game decode.
    .io_wait_for_rom (z80Game),
    .io_cpu_dout     (oki1CpuDout),
    .io_rom_rd       (oki1RomRead),
    .io_rom_addr     (oki1RomAddr),
    .io_rom_cache_addr (fastZ80Sound ? fastOki1MappedAddr : oki1MappedAddr),
    .io_rom_dout     (oki1RomData),
    .io_rom_valid    (oki1RomDataValid),
    .io_audio_valid  (oki1AudioValid),
    .io_audio_bits   (oki1Audio),
    .io_audio_hold_bits (oki1AudioHold),
    .io_bank_load    (oki1BankWrite & ~ssDeviceHoldReg),
    .io_bank_hi_din  (oki1BankHiDin),
    .io_bank_lo_din  (oki1BankLoDin),
    .io_bank_hi      (oki1BankHi),
    .io_bank_lo      (oki1BankLo),
    .io_ss_hold_i    (ssDeviceHoldReg),
    .io_ss_restore_enable_i (ssRestoreEnable),
    .restore_begin_i (
      ssRestoreBegin & io_ss_runtime_support[29]
    ),
    .restore_commit_i (
      ssDeviceRestoreCommit & io_ss_runtime_support[29]
    ),
    .io_ss_idle_o    (ssOki1Idle),
    .validation_complete_o (ssOki1ValidationComplete),
    .validation_valid_o (ssOki1ValidationValid),
    .write_complete_o (ssOki1WriteComplete),
    .write_valid_o   (ssOki1WriteValid),
    .restore_prime_o (ssOki1RestorePrime),
    .restore_committed_o (ssOki1RestoreCommitted),
    .terminal_fault_o (ssOki1TerminalFault),
    .ssbus           (soundOwnerBus[6])
  );

  assign io_ctrl_irq = 1'b0;

  CaveBanprestoYM2203SaveState #(
    .OWNER_INDEX(8'd26)
  ) ym2203 (
    .clock             (clock),
    .reset             (reset),
    .io_cpu_wr         (ym2203Write),
    .io_cpu_addr       (cpuAddr[0]),
    .io_cpu_din        (cpuDout),
    .io_cpu_dout       (ym2203CpuDout),
    .io_irq            (ym2203Irq),
    .io_audio_valid    (ym2203AudioValid),
    .io_audio_bits_psg (ym2203PsgAudio),
    .io_audio_bits_fm  (ym2203FmAudio),
    .io_ss_hold_i      (ssDeviceHoldReg),
    .io_ss_restore_enable_i (ssRestoreEnable),
    .io_ss_idle_o      (ssYm2203Idle),
    .io_ssbus          (soundOwnerBus[3])
  );

  CaveBanprestoYM2151SaveState #(
    .OWNER_INDEX(8'd27),
    .WRITE_HOLD_CYCLES(16)
  ) ym2151 (
    .clock          (clock),
    .reset          (reset),
    .io_cpu_wr      (airYm2151Write),
    .io_cpu_addr    (cpuAddr[0]),
    .io_cpu_din     (cpuDout),
    .io_cpu_dout    (ym2151CpuDout),
    .io_irq         (ym2151Irq),
    .io_audio_valid (ym2151AudioValid),
    .io_audio_bits  (ym2151Audio),
    .io_ss_hold_i   (ssDeviceHoldReg),
    .io_ss_restore_enable_i (ssRestoreEnable),
    .io_ss_idle_o   (ssYm2151Idle),
    .io_ssbus       (soundOwnerBus[4])
  );

  CaveSoundRomReadArbiter arbiter (
    .clock          (clock),
    .reset          (reset),
    .io_in_0_rd     (1'b0),
    .io_in_0_addr   (oki0MappedAddr),
    .io_in_0_dout   (oki0RomDout),
    .io_in_0_valid  (oki0RomValid),
    .io_in_1_rd     (1'b0),
    .io_in_1_addr   (25'h0000000),
    .io_in_1_dout   (),
    .io_in_1_wait_n (),
    .io_in_1_valid  (),
    .io_in_2_rd     (z80ProgRomArbiterRead),
    .io_in_2_addr   ({9'h000, cpuAddr}),
    .io_in_2_dout   (progRomDout),
    .io_in_2_valid  (progRomValid),
    .io_in_3_rd     (z80BankRomArbiterRead),
    .io_in_3_addr   ({6'h00, z80BankReg, cpuAddr[13:0]}),
    .io_in_3_dout   (bankRomDout),
    .io_in_3_valid  (bankRomValid),
    .io_out_rd      (io_rom_0_rd),
    .io_out_addr    (io_rom_0_addr),
    .io_out_dout    (io_rom_0_dout),
    .io_out_wait_n  (io_rom_0_wait_n),
    .io_out_valid   (io_rom_0_valid)
  );

  wire [15:0] fmMixInput = fastZ80Sound ? ym2151AudioReg : ym2203FmAudioReg;
  wire [15:0] psgMixInput = fastZ80Sound ? 16'h0000 : ym2203PsgAudioReg;
  wire [11:0] audioConfigCpu;

  // Menu/save-operation configuration originates in the system-clock domain
  // while the mixer runs on the sound CPU clock. Transfer the three trims as
  // one held payload so no physical path can observe a torn menu update.
  CaveBanprestoAudioConfigCdc audioConfigCdc (
    .src_clk_i      (io_audioConfigClock),
    .src_reset_i    (io_audioConfigReset),
    .src_config_i   ({io_audioTrim_sfx, io_audioTrim_bgm, io_audioTrim_fm}),
    .dst_clk_i      (clock),
    // Reset both mailbox halves from the same system-domain reset. A
    // sound-CPU-only reset must not clear a settled nonzero menu payload when
    // request/ack parity is already equal and therefore has no resend edge.
    .dst_reset_i    (io_audioConfigReset),
    .dst_config_o   (audioConfigCpu),
    .dst_idle_o     (audioConfigIdle)
  );

  CaveBanprestoAudioMixerSaveState io_audio_mixer (
    .clock   (clock),
    .reset   (reset),
    .io_airgallet (fastZ80Sound),
    .io_sailormoon (sailormoonZ80),
    .io_mazinger (mazingerZ80),
    .io_metmqstr (metmqstrZ80),
    .io_audioTrim_fm (audioConfigCpu[3:0]),
    .io_audioTrim_bgm (audioConfigCpu[7:4]),
    .io_audioTrim_sfx (audioConfigCpu[11:8]),
    .io_in_4 (oki1AudioHold),
    .io_in_3 (oki0AudioHold),
    .io_in_2 (fmMixInput),
    .io_in_1 (psgMixInput),
    .io_ss_hold_i (ssDeviceHoldReg),
    .io_ss_restore_wr_i (mixerRestoreWr),
    .io_ss_restore_state_i (mixerRestoreState),
    .io_ss_live_state_o (mixerLiveState),
    .io_out  (io_audio)
  );

  CaveBanprestoSaveStateBusMux #(
    .OWNER_COUNT(7),
    .OWNER_BASE(23),
    .SUPPORT_WIDTH(48),
    .COMPILED_SUPPORT_BITMAP(48'h0000_3f80_0000),
    .RESPONSE_TIMEOUT_CYCLES(4096)
  ) soundOwnerMux (
    .clk_i             (clock),
    .reset_i           (reset),
    .runtime_support_i (io_ss_runtime_support),
    .owners            (soundOwnerBus),
    .upstream          (io_ssbus),
    .multiple_ack_o    (ssBusMultipleAck),
    .timeout_o         (ssBusTimeout),
    .faulted_o         (ssBusFault),
    .idle_o            (ssBusIdle)
  );

  assign ssOwner23Required = io_ss_runtime_support[23];
  assign ssOwner25Required = io_ss_runtime_support[25];
  assign ssOwner28Required = io_ss_runtime_support[28];
  assign ssOwner29Required = io_ss_runtime_support[29];
  assign ssOwnerRequiredEvidence = io_ss_runtime_support[29:23];
  assign ssOwnerIdleEvidence = {
    ssOki1Idle,
    ssOki0Idle,
    ssYm2151Idle,
    ssYm2203Idle,
    ssWrapperIdle,
    ~ssSoundRamTakeover,
    io_ss_stopped
  };
  assign ssOwnerCommitReadyEvidence = {
    ssOki1ValidationComplete & ssOki1ValidationValid &
      ssOki1WriteComplete & ssOki1WriteValid,
    ssOki0ValidationComplete & ssOki0ValidationValid &
      ssOki0WriteComplete & ssOki0WriteValid,
    1'b1,
    1'b1,
    ssWrapperValidationComplete & ssWrapperValidationValid &
      ssWrapperWriteComplete & ssWrapperWriteValid,
    1'b1,
    ssT80ValidationComplete & ssT80ValidationValid &
      ssT80WriteComplete & ssT80WriteValid
  };
  assign ssOwnerCommittedEvidence = {
    ssOki1RestoreCommitted,
    ssOki0RestoreCommitted,
    1'b1,
    1'b1,
    ssWrapperRestoreCommitted,
    1'b1,
    ssT80RestoreCommitted
  };
  assign ssOwnerPrimeEvidence = {
    ssOki1RestorePrime,
    ssOki0RestorePrime,
    1'b1,
    1'b1,
    1'b1,
    1'b1,
    ssT80RestoreLoad
  };
  assign ssAllDevicesIdle =
    ssWrapperIdle &
    ssYm2203Idle &
    ssYm2151Idle &
    ssOki0Idle &
    ssOki1Idle &
    audioConfigIdle &
    ssBusIdle;
  assign ssSoundOwnerFatal =
    io_ss_fatal |
    ssT80CpuTerminalFault |
    ssT80OwnerTerminalFault |
    ssWrapperTerminalFault |
    ssOki0TerminalFault |
    ssOki1TerminalFault |
    ssBusFault;
  assign ssOwnerCommitIdle =
    ssDeviceHoldReg &
    ssAllDevicesIdle &
    (!ssReleaseRequiresCommitReg ||
     ((!ssOwner23Required || ssT80RestoreCommitted) &&
      (!ssOwner25Required || ssWrapperRestoreCommitted) &&
      (!ssOwner28Required || ssOki0RestoreCommitted) &&
      (!ssOwner29Required || ssOki1RestoreCommitted)));

  CaveBanprestoSoundCommandEndpoint soundCommandEndpoint (
    .clk_i                       (clock),
    .reset_i                     (reset),
    .command_valid_i             (io_ss_command_valid),
    .command_i                   (io_ss_command),
    .current_game_index_i        (io_gameIndex),
    .owner_required_i            (ssOwnerRequiredEvidence),
    .owner_idle_i                (ssOwnerIdleEvidence),
    .owner_bus_idle_i            (ssBusIdle),
    .owner_commit_ready_i        (ssOwnerCommitReadyEvidence),
    .owner_committed_i           (ssOwnerCommittedEvidence),
    .owner_prime_i               (ssOwnerPrimeEvidence),
    .sound_stopped_i             (io_ss_stopped),
    .external_idle_i             (io_ss_external_idle),
    .sound_abort_ack_i           (io_ss_abort_ack),
    .release_complete_i          (io_ss_release_complete),
    .lower_terminal_fault_i      (
      ssSoundOwnerFatal | ssReleaseTerminalFault
    ),
    .command_complete_o          (io_ss_command_complete),
    .command_response_o          (io_ss_command_response),
    .terminal_fault_o            (io_ss_command_terminal_fault),
    .stop_request_o              (ssCommandStopRequest),
    .restore_mode_o              (ssCommandRestoreMode),
    .state_enable_o              (ssCommandStateEnable),
    .restore_enable_o            (ssCommandRestoreEnable),
    .abort_o                     (ssCommandAbort),
    .restore_begin_o             (ssCommandRestoreBegin),
    .device_restore_commit_o     (
      ssCommandDeviceRestoreCommit
    ),
    .t80_restore_commit_o        (ssCommandT80RestoreCommit),
    .state_debug_o               (
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
      ssCommandStateDebug
`endif
    )
  );

  CaveBanprestoSoundReleaseCoordinator soundReleaseCoordinator (
    .clk_i                        (clock),
    .reset_i                      (reset),
    .release_authorize_i          (io_ss_release_authorize),
    .release_restore_i            (io_ss_release_restore),
    .restore_commit_authorized_i  (ssCommandT80RestoreCommit),
    .sound_stopped_i              (io_ss_stopped),
    .restore_load_i               (ssT80RestoreLoad),
    .restore_launch_done_i        (io_ss_restore_launch_done),
    .external_idle_i              (io_ss_external_idle),
    .restore_dependencies_ready_i (
      io_ss_restore_dependencies_ready
    ),
    .owner_commit_idle_i          (ssOwnerCommitIdle),
    .abort_i                      (ssAbort),
    .sound_abort_ack_i            (io_ss_abort_ack),
    .fatal_i                      (
      ssSoundOwnerFatal | io_ss_command_terminal_fault
    ),
    .sound_release_o              (ssSoundRelease),
    .release_pending_o            (io_ss_release_pending),
    .release_ready_o              (ssReleaseReady),
    .release_complete_o           (io_ss_release_complete),
    .terminal_fault_o             (ssReleaseTerminalFault),
    .state_debug_o                (
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
      ssReleaseStateDebug
`endif
    )
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
    ,
    .proof_debug_o                (ssReleaseProofDebug)
`endif
  );

`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
  assign io_ss_release_debug = {
    ssCommandStateDebug,
    ssReleaseStateDebug,
    ssReleaseProofDebug,
    ssReleaseReady,
    ssOwnerCommitIdle
  };
  // Live sticky-source vector for the hardware-only pass-2 fault recorder.
  // The enclosing Cave block retains the last owner-bus request separately,
  // so this diagnostic adds no control feedback across the clock boundary.
  assign io_ss_owner_fault_debug = {
    io_ss_fatal,
    ssT80CpuTerminalFault,
    ssT80OwnerTerminalFault,
    ssWrapperTerminalFault,
    ssOki0TerminalFault,
    ssOki1TerminalFault,
    ssBusMultipleAck,
    ssBusTimeout
  };
`endif

  assign io_ss_idle =
    io_ss_stopped &
    ssDeviceHoldReg &
    io_ss_external_idle &
    ssAllDevicesIdle &
    ~ssSoundOwnerFatal &
    ~ssReleaseTerminalFault;
  assign io_ss_terminal_fault =
    ssSoundOwnerFatal |
    ssReleaseTerminalFault |
    io_ss_command_terminal_fault;

  assign cpuInt = fastZ80Sound ? ym2151Irq : ym2203Irq;

`ifdef CAVEBANPRESTO_HOTDOG_AUDIO_HW_DIAGNOSTIC
  wire        hotdogAudioDiagSource;
  wire [63:0] hotdogAudioDiagProbe;

  CaveHotdogAudioHardwareDiagnostic hotdogAudioHardwareDiagnostic (
    .clk_i               (clock),
    .reset_i             (reset),
    .enable_i            (hotdogZ80),
    .source_i            (hotdogAudioDiagSource),
    .z80_m1_fetch_i      (cpuM1 & z80RomRead),
    .ym_write_i          (ym2203Write),
    .oki_write_i         (z80Oki1CpuWr),
    .mixer_sample_i      (io_audio),
    .probe_o             (hotdogAudioDiagProbe)
  );

  altsource_probe #(
    .sld_auto_instance_index ("NO"),
    .sld_instance_index      (3),
    .instance_id             ("HDA"),
    .probe_width             (64),
    .source_width            (1),
    .source_initial_value    ("0"),
    .enable_metastability    ("NO")
  ) hotdogAudioProbe (
    .probe  (hotdogAudioDiagProbe),
    .source (hotdogAudioDiagSource)
  );
`endif

  assign io_ctrl_oki_0_dout = {8'h00, oki0CpuDout};
  assign io_ctrl_oki_1_dout = {8'h00, oki1CpuDout};
  assign io_ctrl_ymz_dout = 16'h0000;
  assign io_ctrl_reply = (replyCount == 6'd0) ? 16'h00ff : {8'h00, replyFifo[replyReadPtr]};
  assign io_ctrl_reply_empty = replyCount == 6'd0;
`ifdef CAVE_ENABLE_DEBUG_OVERLAY
  wire [7:0] debugH0 = mazingerZ80 ? oki1CpuDout : debugLastYmAddr;
  wire [7:0] debugH1 = mazingerZ80 ? oki1AudioHold[13:6] : debugLastYmData;
  wire [7:0] debugH2 = debugFlags;
  wire [7:0] debugStartOrLatch = mazingerZ80 ? debugLastOkiStart : debugLastOkiStart;

  wire [63:0] debugCommandBits = {
    debugH2,
    debugH1,
    debugH0,
    debugStartOrLatch,
    debugLastOkiPhrase,
    debugLastOkiBank,
    debugLastReply,
    debugLastSoundCommand
  };

  wire [63:0] metmqstrDebugBits = {
    debugMetOki1WaitCount,
    debugMetOki0WaitCount,
    debugMetZ80ProgressCount,
    metDebugFlags,
    debugLastSoundCommand
  };

  assign io_debug = metmqstrZ80 ? metmqstrDebugBits : debugCommandBits;
`else
  assign io_debug = 64'd0;
`endif
  assign io_rom_1_rd =
    fastZ80Sound ? oki0RomRead :
                         1'b1;
  assign io_rom_1_addr =
    fastZ80Sound ? airOki0MappedAddr :
                   oki1MappedAddr;
  assign io_rom_2_rd = fastZ80Sound & oki1RomRead;
  assign io_rom_2_addr = fastOki1MappedAddr;
endmodule

// Coherent multi-bit mailbox for the infrequent audio-menu configuration.
// The source holds payload_q unchanged from request launch until the
// destination acknowledges capture. Only the request, acknowledgement, and
// pending levels use two-flop synchronizers; the payload is an MCP bundle.
module CaveBanprestoAudioConfigCdc (
  input  wire        src_clk_i,
  input  wire        src_reset_i,
  input  wire [11:0] src_config_i,
  input  wire        dst_clk_i,
  input  wire        dst_reset_i,
  output reg  [11:0] dst_config_o,
  output wire        dst_idle_o
);
  reg [11:0] src_payload_q;
  reg        src_request_toggle_q;
  reg        src_pending_q;
  reg [2:0]  src_rearm_count_q;
  reg        src_rearmed_q;
  (* preserve, useioff = 0,
     altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
  reg src_ack_meta_q;
  (* preserve, useioff = 0,
     altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
  reg src_ack_sync_q;

  (* preserve, useioff = 0,
     altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
  reg dst_request_meta_q;
  (* preserve, useioff = 0,
     altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
  reg dst_request_sync_q;
  (* preserve, useioff = 0,
     altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
  reg dst_pending_meta_q;
  (* preserve, useioff = 0,
     altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
  reg dst_pending_sync_q;
  reg        dst_ack_toggle_q;
  wire       src_config_known =
    ((src_config_i == src_config_i) === 1'b1);

  always @(posedge src_clk_i) begin
    if (src_reset_i) begin
      // Keep the private source payload distinct from the public 100%
      // destination reset value so the current trims are always resent after
      // source rearming, including when the current setting is exactly 100%.
      src_payload_q <= 12'h000;
      src_request_toggle_q <= 1'b0;
      src_pending_q <= 1'b1;
      src_rearm_count_q <= 3'd0;
      src_rearmed_q <= 1'b0;
      src_ack_meta_q <= 1'b0;
      src_ack_sync_q <= 1'b0;
    end else begin
      src_ack_meta_q <= dst_ack_toggle_q;
      src_ack_sync_q <= src_ack_meta_q;

      // A source-only reset forces request back to zero. Wait for that zero
      // to make a complete destination/acknowledgement round trip before
      // launching the current payload, so a short reset cannot collapse two
      // toggle transitions into one invisible event.
      if (!src_rearmed_q) begin
        src_pending_q <= 1'b1;
        if (src_request_toggle_q == src_ack_sync_q) begin
          if (src_rearm_count_q == 3'd7)
            src_rearmed_q <= 1'b1;
          else
            src_rearm_count_q <= src_rearm_count_q + 3'd1;
        end else begin
          src_rearm_count_q <= 3'd0;
        end
      end else if (!src_config_known) begin
        src_pending_q <= 1'b1;
      end else if (src_request_toggle_q != src_ack_sync_q) begin
        src_pending_q <= 1'b1;
      end else if (src_payload_q != src_config_i) begin
        src_payload_q <= src_config_i;
        src_request_toggle_q <= ~src_request_toggle_q;
        src_pending_q <= 1'b1;
      end else begin
        src_pending_q <= 1'b0;
      end
    end
  end

  always @(posedge dst_clk_i) begin
    if (dst_reset_i) begin
      dst_request_meta_q <= 1'b0;
      dst_request_sync_q <= 1'b0;
      dst_pending_meta_q <= 1'b1;
      dst_pending_sync_q <= 1'b1;
      dst_ack_toggle_q <= 1'b0;
      dst_config_o <= 12'h444;
    end else begin
      dst_request_meta_q <= src_request_toggle_q;
      dst_request_sync_q <= dst_request_meta_q;
      dst_pending_meta_q <= src_pending_q;
      dst_pending_sync_q <= dst_pending_meta_q;

      if (dst_request_sync_q != dst_ack_toggle_q) begin
        dst_config_o <= src_payload_q;
        dst_ack_toggle_q <= dst_request_sync_q;
      end
    end
  end

  assign dst_idle_o =
    (dst_request_sync_q == dst_ack_toggle_q) &&
    !dst_pending_sync_q;
endmodule
