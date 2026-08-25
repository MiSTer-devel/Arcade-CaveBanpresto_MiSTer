// This file is a Codex-assisted rewrite based on the original work of
// Josh Bassett (nullobject).

module MetmqstrMainMap(
  input         clock,
  input         game_active,
  input  [22:0] cpu_addr,
  input  [2:0]  cpu_fc,
  input         cpu_as,
  input         cpu_rw,
  input         read_strobe,
  input         write_strobe,
  input         prog_rom_valid,
  input         dtack_reg,
  input         agallet_irq,
  input         unknown_irq,
  input         video_irq,
  input  [15:0] cpu_dout,
  input  [15:0] input1_data,
  input  [15:0] input0_data,
  input  [15:0] palette_data,
  input  [15:0] layer0_regs_data,
  input  [15:0] layer1_regs_data,
  input  [15:0] layer2_regs_data,
  input  [15:0] layer0_vram16_data,
  input  [15:0] layer0_line_data,
  input  [15:0] layer0_vram8_data,
  input  [15:0] layer1_vram16_data,
  input  [15:0] layer1_line_data,
  input  [15:0] layer1_vram8_data,
  input  [15:0] layer2_vram16_data,
  input  [15:0] layer2_line_data,
  input  [15:0] layer2_vram8_data,
  input  [15:0] sound_data,
  input         sound_reply_empty,
  input  [15:0] sprite_ram_data,
  input  [15:0] prog_rom_data,
  input         ss_hold,
  input         ss_load,
  input  [95:0] ss_state_in,
  output [95:0] ss_state_out,
  output [23:0] cpu_byte_addr,
  output [21:0] prog_rom_packed_addr,
  output        prog_rom_select,
  output        palette_select,
  output [14:0] palette_ram_addr,
  output        sprite_ram_select,
  output        irq_read,
  output [1:0]  irq_word_offset,
  output        video_irq_clear,
  output        unknown_irq_clear,
  output        sound_flags_read,
  output        sound_read,
  output        sound_write,
  output        input0_read,
  output        input1_read,
  output        eeprom_write,
  output        sprite_swap_write,
  output        prog_rom_read,
  output        palette_read,
  output        palette_write,
  output        sprite_ram_read,
  output        sprite_ram_write,
  output        layer0_vram16_read,
  output        layer0_vram16_write,
  output        layer0_line_read,
  output        layer0_line_write,
  output        layer0_vram8_read,
  output        layer0_vram8_write,
  output        layer1_vram16_read,
  output        layer1_vram16_write,
  output        layer1_line_read,
  output        layer1_line_write,
  output        layer1_vram8_read,
  output        layer1_vram8_write,
  output        layer2_vram16_read,
  output        layer2_vram16_write,
  output        layer2_line_read,
  output        layer2_line_write,
  output        layer2_vram8_read,
  output        layer2_vram8_write,
  output        layer0_regs_write,
  output        layer1_regs_write,
  output        layer2_regs_write,
  output        sprite_regs_write,
  output        dtack,
  output        read_data_valid,
  output [15:0] read_data
);
  assign cpu_byte_addr = {cpu_addr, 1'b0};

  wire progRom0Select =
    (cpu_byte_addr >= 24'h000000) & (cpu_byte_addr < 24'h080000);
  wire progRom1Select =
    (cpu_byte_addr >= 24'h100000) & (cpu_byte_addr < 24'h180000);
  wire progRom2Select =
    (cpu_byte_addr >= 24'h200000) & (cpu_byte_addr < 24'h280000);
  assign prog_rom_select = progRom0Select | progRom1Select | progRom2Select;
  assign prog_rom_packed_addr =
    progRom2Select ? (cpu_byte_addr[21:0] - 22'h100000) :
    progRom1Select ? (cpu_byte_addr[21:0] - 22'h080000) :
                     cpu_byte_addr[21:0];

  assign palette_select =
    (cpu_byte_addr >= 24'h408000) & (cpu_byte_addr < 24'h409000);
  assign palette_ram_addr = {4'h0, cpu_addr[10:0]};

  wire watchdogReadSelect =
    (cpu_byte_addr >= 24'h600000) & (cpu_byte_addr < 24'h600002);
  wire watchdogWriteSelect =
    (cpu_byte_addr >= 24'ha80068) & (cpu_byte_addr < 24'ha8006a);

  wire layer2Vram16Select =
    (cpu_byte_addr >= 24'h880000) & (cpu_byte_addr < 24'h881000);
  wire layer2LineSelect =
    (cpu_byte_addr >= 24'h881000) & (cpu_byte_addr < 24'h881800);
  wire layer2Gap0Select =
    (cpu_byte_addr >= 24'h881800) & (cpu_byte_addr < 24'h884000);
  wire layer2Vram8Select =
    (cpu_byte_addr >= 24'h884000) & (cpu_byte_addr < 24'h888000);
  wire layer2Gap1Select =
    (cpu_byte_addr >= 24'h888000) & (cpu_byte_addr < 24'h890000);

  wire layer1Vram16Select =
    (cpu_byte_addr >= 24'h900000) & (cpu_byte_addr < 24'h901000);
  wire layer1LineSelect =
    (cpu_byte_addr >= 24'h901000) & (cpu_byte_addr < 24'h901800);
  wire layer1Gap0Select =
    (cpu_byte_addr >= 24'h901800) & (cpu_byte_addr < 24'h904000);
  wire layer1Vram8Select =
    (cpu_byte_addr >= 24'h904000) & (cpu_byte_addr < 24'h908000);
  wire layer1Gap1Select =
    (cpu_byte_addr >= 24'h908000) & (cpu_byte_addr < 24'h910000);

  wire layer0Vram16Select =
    (cpu_byte_addr >= 24'h980000) & (cpu_byte_addr < 24'h981000);
  wire layer0LineSelect =
    (cpu_byte_addr >= 24'h981000) & (cpu_byte_addr < 24'h981800);
  wire layer0Gap0Select =
    (cpu_byte_addr >= 24'h981800) & (cpu_byte_addr < 24'h984000);
  wire layer0Vram8Select =
    (cpu_byte_addr >= 24'h984000) & (cpu_byte_addr < 24'h988000);
  wire layer0Gap1Select =
    (cpu_byte_addr >= 24'h988000) & (cpu_byte_addr < 24'h990000);

  wire spriteRegsSelect =
    (cpu_byte_addr >= 24'ha80000) & (cpu_byte_addr < 24'ha80080);
  wire soundFlagsSelect =
    (cpu_byte_addr >= 24'ha8006c) & (cpu_byte_addr < 24'ha8006e);
  wire soundDataSelect =
    (cpu_byte_addr >= 24'ha8006e) & (cpu_byte_addr < 24'ha80070);
  wire videoRegsAckSelect =
    spriteRegsSelect & ~soundFlagsSelect & ~soundDataSelect;
  wire spriteRegsWriteSelect =
    videoRegsAckSelect & ~watchdogWriteSelect;
  wire layer2RegsSelect =
    (cpu_byte_addr >= 24'hb00000) & (cpu_byte_addr < 24'hb00006);
  wire layer1RegsSelect =
    (cpu_byte_addr >= 24'hb80000) & (cpu_byte_addr < 24'hb80006);
  wire layer0RegsSelect =
    (cpu_byte_addr >= 24'hc00000) & (cpu_byte_addr < 24'hc00006);
  wire input0Select =
    (cpu_byte_addr >= 24'hc80000) & (cpu_byte_addr < 24'hc80002);
  wire input1Select =
    (cpu_byte_addr >= 24'hc80002) & (cpu_byte_addr < 24'hc80004);
  wire eepromSelect = cpu_byte_addr == 24'hd00000;
  assign sprite_ram_select =
    (cpu_byte_addr >= 24'hf00000) & (cpu_byte_addr < 24'hf10000);

  assign irq_read =
    (cpu_byte_addr >= 24'ha80000) & (cpu_byte_addr < 24'ha80008) & read_strobe;
  assign irq_word_offset = cpu_byte_addr[2:1];
  assign video_irq_clear = game_active & irq_read & (irq_word_offset == 2'h2);
  assign unknown_irq_clear = game_active & irq_read & (irq_word_offset == 2'h3);
  assign sound_flags_read = soundFlagsSelect & read_strobe;
  assign sound_read = soundDataSelect & read_strobe;
  assign sound_write = soundDataSelect & write_strobe;
  assign sprite_swap_write = (cpu_byte_addr == 24'ha80008) & write_strobe;
  assign eeprom_write = eepromSelect & write_strobe;
  assign input0_read = input0Select & read_strobe;
  assign input1_read = input1Select & read_strobe;

  assign prog_rom_read = prog_rom_select & read_strobe;
  assign palette_read = palette_select & read_strobe;
  assign palette_write = palette_select & write_strobe;
  assign sprite_ram_read = sprite_ram_select & read_strobe;
  assign sprite_ram_write = sprite_ram_select & write_strobe;
  assign layer0_vram16_read = layer0Vram16Select & read_strobe;
  assign layer0_vram16_write = layer0Vram16Select & write_strobe;
  assign layer0_line_read = layer0LineSelect & read_strobe;
  assign layer0_line_write = layer0LineSelect & write_strobe;
  assign layer0_vram8_read = layer0Vram8Select & read_strobe;
  assign layer0_vram8_write = layer0Vram8Select & write_strobe;
  assign layer1_vram16_read = layer1Vram16Select & read_strobe;
  assign layer1_vram16_write = layer1Vram16Select & write_strobe;
  assign layer1_line_read = layer1LineSelect & read_strobe;
  assign layer1_line_write = layer1LineSelect & write_strobe;
  assign layer1_vram8_read = layer1Vram8Select & read_strobe;
  assign layer1_vram8_write = layer1Vram8Select & write_strobe;
  assign layer2_vram16_read = layer2Vram16Select & read_strobe;
  assign layer2_vram16_write = layer2Vram16Select & write_strobe;
  assign layer2_line_read = layer2LineSelect & read_strobe;
  assign layer2_line_write = layer2LineSelect & write_strobe;
  assign layer2_vram8_read = layer2Vram8Select & read_strobe;
  assign layer2_vram8_write = layer2Vram8Select & write_strobe;
  assign layer0_regs_write = layer0RegsSelect & write_strobe;
  assign layer1_regs_write = layer1RegsSelect & write_strobe;
  assign layer2_regs_write = layer2RegsSelect & write_strobe;
  assign sprite_regs_write = spriteRegsWriteSelect & write_strobe;

  reg [15:0] layer0Gap0Data;
  reg [15:0] layer0Gap1Data;
  reg [15:0] layer1Gap0Data;
  reg [15:0] layer1Gap1Data;
  reg [15:0] layer2Gap0Data;
  reg [15:0] layer2Gap1Data;

  assign ss_state_out = {
    layer0Gap0Data,
    layer0Gap1Data,
    layer1Gap0Data,
    layer1Gap1Data,
    layer2Gap0Data,
    layer2Gap1Data
  };

  always @(posedge clock) begin
    if (ss_load) begin
      layer0Gap0Data <= ss_state_in[95:80];
      layer0Gap1Data <= ss_state_in[79:64];
      layer1Gap0Data <= ss_state_in[63:48];
      layer1Gap1Data <= ss_state_in[47:32];
      layer2Gap0Data <= ss_state_in[31:16];
      layer2Gap1Data <= ss_state_in[15:0];
    end
    else if (ss_hold !== 1'b1) begin
      if (layer0Gap0Select & write_strobe)
        layer0Gap0Data <= cpu_dout;
      if (layer0Gap1Select & write_strobe)
        layer0Gap1Data <= cpu_dout;
      if (layer1Gap0Select & write_strobe)
        layer1Gap0Data <= cpu_dout;
      if (layer1Gap1Select & write_strobe)
        layer1Gap1Data <= cpu_dout;
      if (layer2Gap0Select & write_strobe)
        layer2Gap0Data <= cpu_dout;
      if (layer2Gap1Select & write_strobe)
        layer2Gap1Data <= cpu_dout;
    end
  end

  wire [15:0] irqData =
    {13'h0, ~((irq_word_offset == 2'h0) & agallet_irq), ~unknown_irq, ~video_irq};

  reg        readDataValidReg;
  reg [15:0] readDataReg;

  always @* begin
    readDataValidReg = 1'b1;
    if (sprite_ram_select)
      readDataReg = sprite_ram_data;
    else if (input1_read)
      readDataReg = input1_data;
    else if (input0_read)
      readDataReg = input0_data;
    else if (layer0RegsSelect)
      readDataReg = layer0_regs_data;
    else if (layer1RegsSelect)
      readDataReg = layer1_regs_data;
    else if (layer2RegsSelect)
      readDataReg = layer2_regs_data;
    else if (sound_read)
      readDataReg = sound_data;
    else if (sound_flags_read)
      readDataReg = sound_reply_empty ? 16'h0002 : 16'h0000;
    else if (irq_read)
      readDataReg = irqData;
    else if (videoRegsAckSelect & read_strobe)
      readDataReg = 16'h0000;
    else if (watchdogReadSelect & read_strobe)
      readDataReg = 16'h0000;
    else if (layer0Gap1Select & read_strobe)
      readDataReg = layer0Gap1Data;
    else if (layer0Vram8Select)
      readDataReg = layer0_vram8_data;
    else if (layer0Gap0Select & read_strobe)
      readDataReg = layer0Gap0Data;
    else if (layer0LineSelect)
      readDataReg = layer0_line_data;
    else if (layer0Vram16Select)
      readDataReg = layer0_vram16_data;
    else if (layer1Gap1Select & read_strobe)
      readDataReg = layer1Gap1Data;
    else if (layer1Vram8Select)
      readDataReg = layer1_vram8_data;
    else if (layer1Gap0Select & read_strobe)
      readDataReg = layer1Gap0Data;
    else if (layer1LineSelect)
      readDataReg = layer1_line_data;
    else if (layer1Vram16Select)
      readDataReg = layer1_vram16_data;
    else if (layer2Gap1Select & read_strobe)
      readDataReg = layer2Gap1Data;
    else if (layer2Vram8Select)
      readDataReg = layer2_vram8_data;
    else if (layer2Gap0Select & read_strobe)
      readDataReg = layer2Gap0Data;
    else if (layer2LineSelect)
      readDataReg = layer2_line_data;
    else if (layer2Vram16Select)
      readDataReg = layer2_vram16_data;
    else if (palette_select)
      readDataReg = palette_data;
    else if (prog_rom_select & cpu_rw & prog_rom_valid)
      readDataReg = prog_rom_data;
    else begin
      readDataValidReg = 1'b0;
      readDataReg = 16'h0000;
    end
  end

  assign read_data_valid = readDataValidReg;
  assign read_data = readDataReg;

  wire romWriteAck = prog_rom_select & ~cpu_rw;
  wire soundSelect = soundFlagsSelect | soundDataSelect;
  wire syncDtack =
    romWriteAck | watchdogReadSelect | watchdogWriteSelect | palette_select |
    layer0Vram16Select | layer0LineSelect | layer0Gap0Select |
    layer0Vram8Select | layer0Gap1Select | layer1Vram16Select |
    layer1LineSelect | layer1Gap0Select | layer1Vram8Select |
    layer1Gap1Select | layer2Vram16Select | layer2LineSelect |
    layer2Gap0Select | layer2Vram8Select | layer2Gap1Select |
    spriteRegsSelect | layer0RegsSelect | layer1RegsSelect | layer2RegsSelect |
    input0Select | input1Select | eepromSelect | sprite_ram_select | soundSelect;

  assign dtack =
    cpu_as & ((prog_rom_select & cpu_rw & prog_rom_valid) | syncDtack | dtack_reg);
endmodule
