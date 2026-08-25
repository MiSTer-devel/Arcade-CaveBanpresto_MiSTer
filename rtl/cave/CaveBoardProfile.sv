// This file is a Codex-assisted rewrite based on the original work of
// Josh Bassett (nullobject).

module CaveBoardProfile(
  input  [3:0] game_index,
  input  [1:0] sound_device,
  output       game_is_dfeveron,
  output       game_is_dodonpachi,
  output       game_is_donpachi,
  output       game_is_esprade,
  output       game_is_uopoko,
  output       game_is_guwange,
  output       game_is_gaia,
  output       game_is_hotdogstorm,
  output       game_is_mazinger,
  output       game_is_airgallet,
  output       game_is_sailormoon,
  output       game_is_metmqstr,
  output       board_uses_z80_sound,
  output       board_is_vertical_clockwise,
  output       sound_is_ymz280b,
  output       sound_is_oki,
  output       sound_is_z80
);
  localparam [3:0] GAME_HOTDOGST = 4'h0;
  localparam [3:0] GAME_MAZINGER = 4'h1;
  localparam [3:0] GAME_AGALLET  = 4'h2;
  localparam [3:0] GAME_SAILORMN = 4'h3;
  localparam [3:0] GAME_METMQSTR = 4'h4;

  assign game_is_dfeveron = 1'b0;
  assign game_is_dodonpachi = 1'b0;
  assign game_is_donpachi = 1'b0;
  assign game_is_esprade = 1'b0;
  assign game_is_uopoko = 1'b0;
  assign game_is_guwange = 1'b0;
  assign game_is_gaia = 1'b0;
  assign game_is_hotdogstorm = game_index == GAME_HOTDOGST;
  assign game_is_mazinger = game_index == GAME_MAZINGER;
  assign game_is_airgallet = game_index == GAME_AGALLET;
  assign game_is_sailormoon = game_index == GAME_SAILORMN;
  assign game_is_metmqstr = game_index == GAME_METMQSTR;

  assign board_uses_z80_sound =
    game_is_hotdogstorm | game_is_mazinger | game_is_airgallet |
    game_is_sailormoon | game_is_metmqstr;
  assign board_is_vertical_clockwise =
    game_is_hotdogstorm | game_is_mazinger;

  assign sound_is_ymz280b = 1'b0;
  assign sound_is_oki = 1'b0;
  assign sound_is_z80 = board_uses_z80_sound & (sound_device == 2'h3);
endmodule
