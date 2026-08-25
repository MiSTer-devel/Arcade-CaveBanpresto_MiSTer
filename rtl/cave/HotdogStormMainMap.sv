// This file is a Codex-assisted rewrite based on the original work of
// Josh Bassett (nullobject).

module HotdogStormMainMap(
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
  input  [15:0] sprite_ram_data,
  input  [15:0] main_ram_data,
  input  [15:0] prog_rom_data,
  input         ss_hold,
  input         ss_load,
  input  [95:0] ss_state_in,
  output [95:0] ss_state_out,
  output [23:0] cpu_byte_addr,
  output        prog_rom_select,
  output        main_ram_select,
  output        palette_select,
  output [14:0] palette_ram_addr,
  output        sprite_ram_select,
  output        irq_read,
  output [1:0]  irq_word_offset,
  output        video_irq_clear,
  output        unknown_irq_clear,
  output        sound_write,
  output        input0_read,
  output        input1_read,
  output        eeprom_write,
  output        sprite_swap_write,
  output        prog_rom_read,
  output        main_ram_read,
  output        main_ram_write,
  output        palette_read,
  output        palette_write,
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

  assign prog_rom_select = cpu_byte_addr < 24'h100000;
  wire noOpSelect =
    ((cpu_byte_addr > 24'h10ffff) & (cpu_byte_addr < 24'h200000)) |
    (cpu_byte_addr == 24'h600000);
  assign main_ram_select =
    (cpu_byte_addr > 24'h2fffff) & (cpu_byte_addr < 24'h310000);
  assign palette_select =
    (cpu_byte_addr > 24'h407fff) & (cpu_byte_addr < 24'h409000);
  assign palette_ram_addr = {4'h0, cpu_addr[10:0]};

  wire layer0Vram16Select =
    (cpu_byte_addr > 24'h87ffff) & (cpu_byte_addr < 24'h881000);
  wire layer0LineSelect =
    (cpu_byte_addr > 24'h880fff) & (cpu_byte_addr < 24'h881800);
  wire layer0Gap0Select =
    (cpu_byte_addr > 24'h8817ff) & (cpu_byte_addr < 24'h884000);
  wire layer0Vram8Select =
    (cpu_byte_addr > 24'h883fff) & (cpu_byte_addr < 24'h888000);
  wire layer0Gap1Select =
    (cpu_byte_addr > 24'h887fff) & (cpu_byte_addr < 24'h890000);

  wire layer1Vram16Select =
    (cpu_byte_addr > 24'h8fffff) & (cpu_byte_addr < 24'h901000);
  wire layer1LineSelect =
    (cpu_byte_addr > 24'h900fff) & (cpu_byte_addr < 24'h901800);
  wire layer1Gap0Select =
    (cpu_byte_addr > 24'h9017ff) & (cpu_byte_addr < 24'h904000);
  wire layer1Vram8Select =
    (cpu_byte_addr > 24'h903fff) & (cpu_byte_addr < 24'h908000);
  wire layer1Gap1Select =
    (cpu_byte_addr > 24'h907fff) & (cpu_byte_addr < 24'h910000);

  wire layer2Vram16Select =
    (cpu_byte_addr > 24'h97ffff) & (cpu_byte_addr < 24'h981000);
  wire layer2LineSelect =
    (cpu_byte_addr > 24'h980fff) & (cpu_byte_addr < 24'h981800);
  wire layer2Gap0Select =
    (cpu_byte_addr > 24'h9817ff) & (cpu_byte_addr < 24'h984000);
  wire layer2Vram8Select =
    (cpu_byte_addr > 24'h983fff) & (cpu_byte_addr < 24'h988000);
  wire layer2Gap1Select =
    (cpu_byte_addr > 24'h987fff) & (cpu_byte_addr < 24'h990000);

  wire spriteRegsSelect =
    (cpu_byte_addr > 24'ha7ffff) & (cpu_byte_addr < 24'ha80010);
  wire videoRegsAckSelect =
    (cpu_byte_addr > 24'ha80009) & (cpu_byte_addr < 24'ha80080);
  wire layer0RegsSelect =
    (cpu_byte_addr > 24'hafffff) & (cpu_byte_addr < 24'hb00006);
  wire layer1RegsSelect =
    (cpu_byte_addr > 24'hb7ffff) & (cpu_byte_addr < 24'hb80006);
  wire layer2RegsSelect =
    (cpu_byte_addr > 24'hbfffff) & (cpu_byte_addr < 24'hc00006);
  wire input0Select =
    (cpu_byte_addr > 24'hc7ffff) & (cpu_byte_addr < 24'hc80001);
  wire input1Select =
    (cpu_byte_addr > 24'hc80001) & (cpu_byte_addr < 24'hc80003);
  wire eepromSelect =
    (cpu_byte_addr > 24'hcfffff) & (cpu_byte_addr < 24'hd00001);
  wire eepromNoopSelect =
    (cpu_byte_addr > 24'hd00001) & (cpu_byte_addr < 24'hd00003);
  assign sprite_ram_select =
    (cpu_byte_addr > 24'hefffff) & (cpu_byte_addr < 24'hf10000);

  assign irq_read =
    (cpu_byte_addr > 24'ha7ffff) & (cpu_byte_addr < 24'ha80008) & read_strobe;
  assign irq_word_offset = cpu_byte_addr[2:1];
  assign video_irq_clear = game_active & irq_read & (irq_word_offset == 2'h2);
  assign unknown_irq_clear = game_active & irq_read & (irq_word_offset == 2'h3);
  assign sound_write =
    (cpu_byte_addr > 24'ha8006d) & (cpu_byte_addr < 24'ha8006f) & write_strobe;
  assign sprite_swap_write = (cpu_byte_addr == 24'ha80008) & write_strobe;
  assign eeprom_write = eepromSelect & write_strobe;
  assign input0_read = input0Select & read_strobe;
  assign input1_read = input1Select & read_strobe;

  assign prog_rom_read = prog_rom_select & read_strobe;
  assign main_ram_read = main_ram_select & read_strobe;
  assign main_ram_write = main_ram_select & write_strobe;
  assign palette_read = palette_select & read_strobe;
  assign palette_write = palette_select & write_strobe;
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
  assign sprite_regs_write = spriteRegsSelect & write_strobe;

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
    else if (eepromNoopSelect & read_strobe)
      readDataReg = 16'h0000;
    else if (input1_read)
      readDataReg = input1_data;
    else if (input0_read)
      readDataReg = input0_data;
    else if (layer2RegsSelect)
      readDataReg = layer2_regs_data;
    else if (layer1RegsSelect)
      readDataReg = layer1_regs_data;
    else if (layer0RegsSelect)
      readDataReg = layer0_regs_data;
    else if (videoRegsAckSelect & read_strobe)
      readDataReg = 16'h0000;
    else if (irq_read)
      readDataReg = irqData;
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
    else if (noOpSelect & read_strobe)
      readDataReg = 16'h0000;
    else if (palette_select)
      readDataReg = palette_data;
    else if (main_ram_select)
      readDataReg = main_ram_data;
    else if (prog_rom_select & cpu_rw & prog_rom_valid)
      readDataReg = prog_rom_data;
    else begin
      readDataValidReg = 1'b0;
      readDataReg = 16'h0000;
    end
  end

  assign read_data_valid = readDataValidReg;
  assign read_data = readDataReg;

  wire syncDtack =
    noOpSelect | main_ram_select | palette_select | layer0Vram16Select |
    layer0LineSelect | layer0Gap0Select | layer0Vram8Select | layer0Gap1Select |
    layer1Vram16Select | layer1LineSelect | layer1Gap0Select | layer1Vram8Select |
    layer1Gap1Select | layer2Vram16Select | layer2LineSelect | layer2Gap0Select |
    layer2Vram8Select | layer2Gap1Select | spriteRegsSelect | videoRegsAckSelect |
    layer0RegsSelect | layer1RegsSelect | layer2RegsSelect | input0Select |
    input1Select | eepromSelect | eepromNoopSelect | sprite_ram_select;

  assign dtack =
    cpu_as & ((prog_rom_select & cpu_rw & prog_rom_valid) | syncDtack | dtack_reg);
endmodule
