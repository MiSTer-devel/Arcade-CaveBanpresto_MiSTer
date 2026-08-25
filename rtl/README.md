# RTL Layout

This directory is the active core implementation for Quartus.

- `cave/` contains the Cave core SystemVerilog consumed by the build.
- `cave/CaveGameConfig.sv` is the hand-maintained table for the supported Z80
  sound-family game profiles.
- `cave/CaveBoardProfile.sv` clamps this split to Hotdog Storm, Mazinger Z, Air
  Gallet, and Pretty Soldier Sailor Moon.
- `cave/Cave.sv` is the hand-maintained core top-level integration shell that
  connects IOCTL, game config, memory, video, sound, GPU, and framebuffers.
- `cave/Main.sv` is the shared 68k board front-end for per-game CPU memory
  maps, inputs, IRQs, EEPROM serial pins, pause, and video register mirrors.
  Its decode lattice still follows the generated shape, but non-Banpresto board
  flags are constant-disabled in this split.
- `cave/MazingerMainMap.sv` groups the Mazinger Z 68k address decoder, IRQ read
  data, boot watchdog shadow RAM, and read-data mux.
- `cave/AirGalletMainMap.sv` groups the Air Gallet and Sailor Moon family 68k
  address decode support.
- `cave/CaveCpuWrappers.sv` wraps the existing `fx68k` main CPU and `T80s`
  sound CPU cores.
- `cave/Sound.sv` is the Z80 sound PCB integration wrapper for the YM2203,
  YM2151, two OKI lanes, banking, ROM arbitration, and mixer.
- `cave/YM2203.sv`, `cave/YM2151.sv`, `cave/CaveOKIM6295.sv`, and
  `cave/CaveClockEnable.sv` are the active sound helpers for this split.
- `cave/savestate/CaveBanprestoAudioMixerSaveState.sv` is the active
  physical PSG/FM-or-YM/OKI0/OKI1 mixer and serializes its registered output
  and fast-profile latency state.
- `cave/AudioMixer.sv` is an uninstantiated legacy reference and is
  intentionally absent from `files.qip` and `cave/filelist.f`.
- `cave/DDR.sv` is the burst bridge between the core shared burst-memory port
  and the MiSTer DDR service interface.
- `cave/SDRAM.sv` is the SDRAM command sequencer for the 16-bit MiSTer-side
  SDRAM interface.
- `cave/EEPROM.sv` is the serial EEPROM front-end for the NVRAM memory port
  used by the main CPU input path.
- `cave/MemSys.sv` routes ROM download, copy DMA, ROM/NVRAM caches, and
  DDR/SDRAM arbitration.
- `cave/CaveReadCache.sv` is the shared cache used directly by program ROM,
  sound ROM, and tile ROM reads.
- `cave/CaveNvramWriteBackCache.sv` is the two-way write-back cache used by the
  EEPROM/NVRAM memory path.
- `cave/GPU.sv` wires sprites, layers, the color mixer, RGB expansion, and
  framebuffer output.
- `cave/ColorMixer.sv` handles layer priority and palette address selection.
- `cave/CaveLayerProcessor.sv` renders the three background layers.
- `cave/CaveTileRomClockCrossing.sv` bridges tile ROM reads across clock
  domains.
- `cave/SpriteDecoder.sv`, `cave/SpriteBlitter.sv`,
  `cave/SpriteProcessor.sv`, and `cave/CaveSpriteHelpers.sv` implement the
  sprite path.
- `cave/MazingerSpriteDecryptDMA.sv` and
  `cave/SailorMoonSpriteDecryptDMA.sv` implement the sprite decode DMA paths
  used by those games. Air Gallet does not use that decoded sprite ROM path.
- `cave/SpriteFrameBuffer.sv` and `cave/SystemFrameBuffer.sv` integrate the
  sprite and HDMI-rotation framebuffers.
- `cave/CavePageFlippers.sv`, `cave/CaveRequestQueues.sv`,
  `cave/CaveBurstDMAs.sv`, `cave/CaveBurstBuffers.sv`,
  `cave/CaveBurstMemArbiters.sv`, and `cave/CaveAsyncMemArbiters.sv` are the
  shared framebuffer and burst-memory helpers.
- `cave/CaveSinglePortRam.sv`, `cave/CaveTrueDualPortRam.sv`,
  `cave/CaveDualClockFIFO.sv`, `cave/CaveSyncReadMem.sv`, and
  `cave/CaveSyncQueue.sv` wrap the local memory/FIFO primitives.
- `cave/CaveVideoTiming.sv` and `cave/VideoSys.sv` handle the shared video
  timing and register front-end.
- `cave/CaveDebugOverlay.sv` is available behind `CAVE_ENABLE_DEBUG_OVERLAY`.
- `arcadia/` contains VHDL memory helpers used by the Cave HDL.
- `fx68k/`, `t80/`, `jt03/`, `jt6295/`, and `modules/ikaopm/` are third-party
  CPU and sound blocks required by the supported games.
- The PLL and reset wrappers live at the `rtl/` root.
