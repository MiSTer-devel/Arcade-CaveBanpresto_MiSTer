// This file is a Codex-assisted rewrite based on the original work of
// Josh Bassett (nullobject).

module ColorMixer(
  input         clock,
  input  [8:0]  io_gameConfig_granularity,
  input  [1:0]  io_gameConfig_layer_0_format,
  input  [1:0]  io_gameConfig_layer_0_paletteBank,
  input  [1:0]  io_gameConfig_layer_1_format,
  input  [1:0]  io_gameConfig_layer_1_paletteBank,
  input  [1:0]  io_gameConfig_layer_2_format,
  input  [1:0]  io_gameConfig_layer_2_paletteBank,
  input         io_gameConfig_useLayerPriority,
  input         io_gameConfig_opaqueForegroundZero,
  input         io_gameConfig_redFill,
  input  [1:0]  io_spritePen_priority,
  input  [5:0]  io_spritePen_palette,
  input  [7:0]  io_spritePen_color,
  input  [1:0]  io_layer0_layerPriority,
  input  [1:0]  io_layer0Pen_priority,
  input  [5:0]  io_layer0Pen_palette,
  input  [7:0]  io_layer0Pen_color,
  input  [1:0]  io_layer1_layerPriority,
  input  [1:0]  io_layer1Pen_priority,
  input  [5:0]  io_layer1Pen_palette,
  input  [7:0]  io_layer1Pen_color,
  input         io_layer1Pen_opaqueZeroEnable,
  input  [1:0]  io_layer2_layerPriority,
  input  [1:0]  io_layer2Pen_priority,
  input  [5:0]  io_layer2Pen_palette,
  input  [7:0]  io_layer2Pen_color,
  input         io_layer2Pen_opaqueZeroEnable,
  output [14:0] io_paletteRam_addr,
  input  [15:0] io_paletteRam_dout,
  output [15:0] io_dout
`ifdef CAVEBANPRESTO_MET_SPRITE_PAGE_HW_DIAGNOSTIC
  ,
  output        io_met_sprite_diag_spriteBeatsTiles
`endif
`ifdef CAVE_ENABLE_DEBUG_OVERLAY
  ,
  output [3:0]  io_debug_selectedPen,
  output [5:0]  io_debug_selectedPalette,
  output [7:0]  io_debug_selectedColor,
  output [3:0]  io_debug_visibleMask
`endif
);
  localparam [3:0] PEN_FILL   = 4'h0;
  localparam [3:0] PEN_SPRITE = 4'h1;
  localparam [3:0] PEN_LAYER0 = 4'h2;
  localparam [3:0] PEN_LAYER1 = 4'h4;
  localparam [3:0] PEN_LAYER2 = 4'h8;

  wire granularity16 = io_gameConfig_granularity == 9'h010;
  wire granularity64 = io_gameConfig_granularity == 9'h040;
  wire layer0Format6bpp = io_gameConfig_layer_0_format == 2'h2;
  wire layer1Format6bpp = io_gameConfig_layer_1_format == 2'h2;
  wire layer2Format6bpp = io_gameConfig_layer_2_format == 2'h2;

  wire layer0Visible = |io_layer0Pen_color;
  wire opaqueForegroundZero = io_gameConfig_opaqueForegroundZero;
  wire layer1Visible =
    (|io_layer1Pen_color) | (opaqueForegroundZero & io_layer1Pen_opaqueZeroEnable);
  wire layer2Visible =
    (|io_layer2Pen_color) | (opaqueForegroundZero & io_layer2Pen_opaqueZeroEnable);
  wire spriteVisible = |io_spritePen_color;

  wire [1:0] layer0Priority =
    io_gameConfig_useLayerPriority ? io_layer0_layerPriority : 2'd0;
  wire [1:0] layer1Priority =
    io_gameConfig_useLayerPriority ? io_layer1_layerPriority : 2'd0;
  wire [1:0] layer2Priority =
    io_gameConfig_useLayerPriority ? io_layer2_layerPriority : 2'd0;
  wire [5:0] layer0Sort = {io_layer0Pen_priority, layer0Priority, 2'd0};
  wire [5:0] layer1Sort = {io_layer1Pen_priority, layer1Priority, 2'd1};
  wire [5:0] layer2Sort = {io_layer2Pen_priority, layer2Priority, 2'd2};
  wire       layer1Beats0 =
    layer1Visible & (~layer0Visible | (layer1Sort > layer0Sort));
  wire       layer01Visible = layer0Visible | layer1Visible;
  wire [3:0] layer01Pen =
    layer1Beats0 ? PEN_LAYER1 : (layer0Visible ? PEN_LAYER0 : PEN_FILL);
  wire [1:0] layer01Priority =
    layer1Beats0 ? io_layer1Pen_priority : io_layer0Pen_priority;
  wire [5:0] layer01Sort =
    layer1Beats0 ? layer1Sort : layer0Sort;
  wire       layer2Beats01 =
    layer2Visible & (~layer01Visible | (layer2Sort > layer01Sort));
  wire       topTileVisible = layer01Visible | layer2Visible;
  wire [3:0] topTilePen =
    layer2Beats01 ? PEN_LAYER2 : layer01Pen;
  wire [1:0] topTilePriority =
    layer2Beats01 ? io_layer2Pen_priority : layer01Priority;
  wire       spriteBeatsTiles =
    spriteVisible & (~topTileVisible | (io_spritePen_priority > topTilePriority));
  wire [3:0] selectedPen = spriteBeatsTiles ? PEN_SPRITE : topTilePen;

  wire [14:0] fillAddr16 =
    {3'h0, io_gameConfig_layer_0_paletteBank, 6'h3f, 4'h0};
  wire [14:0] fillAddr64 =
    {1'b0, io_gameConfig_layer_0_paletteBank, 6'h3f, 6'h00};
  wire [14:0] fillAddr256 =
    {io_gameConfig_layer_0_paletteBank[0], 6'h3f, 8'h00};
  wire [14:0] fillAddr = granularity64 ? fillAddr64 : (granularity16 ? fillAddr16 : fillAddr256);

  wire [14:0] spriteAddr16 = {5'h00, io_spritePen_palette, io_spritePen_color[3:0]};
  wire [14:0] spriteAddr64 = {3'h0, io_spritePen_palette, io_spritePen_color[5:0]};
  wire [14:0] spriteAddr256 = {1'b0, io_spritePen_palette, io_spritePen_color};
  wire [14:0] spriteAddr = granularity64 ? spriteAddr64 : (granularity16 ? spriteAddr16 : spriteAddr256);

  wire [14:0] layer0Addr16 =
    {3'h0, io_gameConfig_layer_0_paletteBank, io_layer0Pen_palette, io_layer0Pen_color[3:0]};
  wire [14:0] layer0Addr64 =
    {1'b0, io_gameConfig_layer_0_paletteBank, io_layer0Pen_palette, io_layer0Pen_color[5:0]};
  wire [14:0] layer0Addr6bpp =
    {3'h0, io_gameConfig_layer_0_paletteBank, io_layer0Pen_palette[3:0], io_layer0Pen_color[5:0]};
  wire [14:0] layer0Addr256 =
    {io_gameConfig_layer_0_paletteBank[0], io_layer0Pen_palette, io_layer0Pen_color};
  wire [14:0] layer0Addr =
    layer0Format6bpp ? layer0Addr6bpp : (granularity64 ? layer0Addr64 : (granularity16 ? layer0Addr16 : layer0Addr256));

  wire [14:0] layer1Addr16 =
    {3'h0, io_gameConfig_layer_1_paletteBank, io_layer1Pen_palette, io_layer1Pen_color[3:0]};
  wire [14:0] layer1Addr64 =
    {1'b0, io_gameConfig_layer_1_paletteBank, io_layer1Pen_palette, io_layer1Pen_color[5:0]};
  wire [14:0] layer1Addr6bpp =
    {3'h0, io_gameConfig_layer_1_paletteBank, io_layer1Pen_palette[3:0], io_layer1Pen_color[5:0]};
  wire [14:0] layer1Addr256 =
    {io_gameConfig_layer_1_paletteBank[0], io_layer1Pen_palette, io_layer1Pen_color};
  wire [14:0] layer1Addr =
    layer1Format6bpp ? layer1Addr6bpp : (granularity64 ? layer1Addr64 : (granularity16 ? layer1Addr16 : layer1Addr256));

  wire [14:0] layer2Addr16 =
    {3'h0, io_gameConfig_layer_2_paletteBank, io_layer2Pen_palette, io_layer2Pen_color[3:0]};
  wire [14:0] layer2Addr64 =
    {1'b0, io_gameConfig_layer_2_paletteBank, io_layer2Pen_palette, io_layer2Pen_color[5:0]};
  wire [14:0] layer2Addr6bpp =
    {3'h0, io_gameConfig_layer_2_paletteBank, io_layer2Pen_palette[3:0], io_layer2Pen_color[5:0]};
  wire [14:0] layer2Addr256 =
    {io_gameConfig_layer_2_paletteBank[0], io_layer2Pen_palette, io_layer2Pen_color};
  wire [14:0] layer2Addr =
    layer2Format6bpp ? layer2Addr6bpp : (granularity64 ? layer2Addr64 : (granularity16 ? layer2Addr16 : layer2Addr256));

  wire [14:0] addrFill = selectedPen == PEN_FILL ? fillAddr : 15'h0000;
  wire [14:0] addrSprite = selectedPen == PEN_SPRITE ? spriteAddr : addrFill;
  wire [14:0] addrLayer0 = selectedPen == PEN_LAYER0 ? layer0Addr : addrSprite;
  wire [14:0] addrLayer1 = selectedPen == PEN_LAYER1 ? layer1Addr : addrLayer0;
  wire [14:0] paletteRamAddr = selectedPen == PEN_LAYER2 ? layer2Addr : addrLayer1;

`ifdef CAVE_ENABLE_DEBUG_OVERLAY
  wire [5:0] selectedPalette =
    selectedPen == PEN_SPRITE ? io_spritePen_palette :
    selectedPen == PEN_LAYER0 ? io_layer0Pen_palette :
    selectedPen == PEN_LAYER1 ? io_layer1Pen_palette :
    selectedPen == PEN_LAYER2 ? io_layer2Pen_palette :
                                6'h00;
  wire [7:0] selectedColor =
    selectedPen == PEN_SPRITE ? io_spritePen_color :
    selectedPen == PEN_LAYER0 ? io_layer0Pen_color :
    selectedPen == PEN_LAYER1 ? io_layer1Pen_color :
    selectedPen == PEN_LAYER2 ? io_layer2Pen_color :
                                8'h00;
  wire [3:0] visibleMask = {layer2Visible, layer1Visible, layer0Visible, spriteVisible};

  reg [3:0] debugSelectedPenReg;
  reg [5:0] debugSelectedPaletteReg;
  reg [7:0] debugSelectedColorReg;
  reg [3:0] debugVisibleMaskReg;
`endif

  reg [15:0] pixelReg;
  always @(posedge clock) begin
    pixelReg <= (io_gameConfig_redFill & (selectedPen == PEN_FILL)) ? 16'h03e0 : io_paletteRam_dout;
`ifdef CAVE_ENABLE_DEBUG_OVERLAY
    debugSelectedPenReg <= selectedPen;
    debugSelectedPaletteReg <= selectedPalette;
    debugSelectedColorReg <= selectedColor;
    debugVisibleMaskReg <= visibleMask;
`endif
  end

  assign io_paletteRam_addr = paletteRamAddr;
  assign io_dout = pixelReg;
`ifdef CAVEBANPRESTO_MET_SPRITE_PAGE_HW_DIAGNOSTIC
  assign io_met_sprite_diag_spriteBeatsTiles = spriteBeatsTiles;
`endif
`ifdef CAVE_ENABLE_DEBUG_OVERLAY
  assign io_debug_selectedPen = debugSelectedPenReg;
  assign io_debug_selectedPalette = debugSelectedPaletteReg;
  assign io_debug_selectedColor = debugSelectedColorReg;
  assign io_debug_visibleMask = debugVisibleMaskReg;
`endif
endmodule
