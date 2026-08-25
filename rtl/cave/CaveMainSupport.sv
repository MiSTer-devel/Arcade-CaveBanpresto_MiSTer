// This file is a Codex-assisted rewrite based on the original work of
// Josh Bassett (nullobject).

module CaveCpuBusStrobes(
  input  wire clock,
  input  wire as,
  input  wire uds,
  input  wire lds,
  input  wire rw,
  input  wire       ss_hold,
  input  wire       ss_load,
  input  wire [2:0] ss_state_in,
  output wire [2:0] ss_state_out,
  output wire read_strobe,
  output wire write_strobe
);

  reg asPrev;
  reg udsPrev;
  reg ldsPrev;

  assign read_strobe = as & ~asPrev & rw;
  assign write_strobe =
    (as & uds & ~udsPrev & ~rw)
    | (as & lds & ~ldsPrev & ~rw);
  assign ss_state_out = {asPrev, udsPrev, ldsPrev};

  always @(posedge clock) begin
    if (ss_load) begin
      asPrev <= ss_state_in[2];
      udsPrev <= ss_state_in[1];
      ldsPrev <= ss_state_in[0];
    end
    else if (ss_hold !== 1'b1) begin
      asPrev <= as;
      udsPrev <= uds;
      ldsPrev <= lds;
    end
  end

endmodule

// Convert an asynchronous level pulse into exactly one pulse in the receiving
// clock domain. The source pulse must remain asserted long enough to cross
// the two synchronizer stages; Cave's 32 MHz CPU-domain sprite-swap pulse is
// three 96 MHz system clocks wide.
module CaveAsyncLevelToPulse(
  input  wire clock,
  input  wire reset,
  input  wire level_in,
  output wire pulse_out
);

  (* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
  reg level_meta_q;
  (* preserve, useioff = 0, altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
  reg level_sync_q;
  reg level_previous_q;

  assign pulse_out = level_sync_q & ~level_previous_q;

  always @(posedge clock) begin
    if (reset) begin
      level_meta_q <= 1'b0;
      level_sync_q <= 1'b0;
      level_previous_q <= 1'b0;
    end else begin
      level_meta_q <= level_in;
      level_sync_q <= level_meta_q;
      level_previous_q <= level_sync_q;
    end
  end

endmodule

module CaveEepromSerialPins(
  input  wire       clock,
  input  wire       reset,
  input  wire       write_enable,
  input  wire       guwange_layout,
  input  wire       metmqstr_layout,
  input  wire [15:0] data,
  input  wire       ss_hold,
  input  wire       ss_load,
  input  wire [2:0] ss_state_in,
  output wire [2:0] ss_state_out,
  output reg        serial_cs,
  output reg        serial_sck,
  output reg        serial_sdi
);

  assign ss_state_out = {serial_cs, serial_sck, serial_sdi};

  always @(posedge clock) begin
    if (reset) begin
      serial_cs <= 1'b0;
      serial_sck <= 1'b0;
      serial_sdi <= 1'b0;
    end
    else if (ss_load) begin
      serial_cs <= ss_state_in[2];
      serial_sck <= ss_state_in[1];
      serial_sdi <= ss_state_in[0];
    end
    else if ((ss_hold !== 1'b1) && write_enable) begin
      if (metmqstr_layout) begin
        if (~data[8]) begin
          serial_cs <= data[9];
          serial_sck <= data[10];
          serial_sdi <= data[11];
        end
      end
      else begin
        serial_cs <= guwange_layout ? data[5] : data[9];
        serial_sck <= guwange_layout ? data[6] : data[10];
        serial_sdi <= guwange_layout ? data[7] : data[11];
      end
    end
  end

endmodule

module CaveInputMapper(
  input  wire        game_is_guwange,
  input  wire        game_is_gaia,
  input  wire        game_is_metmqstr,
  input  wire        eeprom_sdo,
  input  wire        service_active,
  input  wire        coin1_active,
  input  wire        coin2_active,
  input  wire        player0_up,
  input  wire        player0_down,
  input  wire        player0_left,
  input  wire        player0_right,
  input  wire [3:0]  player0_buttons,
  input  wire        player0_start,
  input  wire        player1_up,
  input  wire        player1_down,
  input  wire        player1_left,
  input  wire        player1_right,
  input  wire [3:0]  player1_buttons,
  input  wire        player1_start,
  output wire [15:0] default_p1,
  output wire [15:0] default_p2,
  output wire [15:0] combined_players,
  output wire [15:0] guwange_p1,
  output wire [15:0] input0,
  output wire [15:0] default_or_guwange_p1,
  output wire [15:0] combined_or_guwange_p1,
  output wire [15:0] guwange_system,
  output wire [15:0] gaia_system,
  output wire [15:0] input1,
  output wire [15:0] default_or_guwange_p2,
  output wire [15:0] shared_system
);

  wire        metmqstrButton4P1 = game_is_metmqstr ? ~player0_buttons[3] : 1'b1;
  wire        metmqstrButton4P2 = game_is_metmqstr ? ~player1_buttons[3] : 1'b1;

  wire [11:0] input0Prefix =
    game_is_gaia
      ? {~player1_buttons,
         ~player1_right,
         ~player1_left,
         ~player1_down,
         ~player1_up,
         ~player0_buttons}
      : {5'h1F,
         metmqstrButton4P1,
         ~service_active,
         ~coin1_active,
         ~player0_start,
         ~(player0_buttons[2:0])};

  wire [12:0] sharedSystemPrefix =
    game_is_guwange
      ? {8'hFF, eeprom_sdo, 4'hF}
      : {10'h3F, ~player1_start, ~player0_start, 1'b1};

  assign default_p1 =
    {5'h1F,
     metmqstrButton4P1,
     ~service_active,
     ~coin1_active,
     ~player0_start,
     ~(player0_buttons[2:0]),
     ~player0_right,
     ~player0_left,
     ~player0_down,
     ~player0_up};

  assign default_p2 =
    {4'hF,
     eeprom_sdo,
     metmqstrButton4P2,
     1'b1,
     ~coin2_active,
     ~player1_start,
     ~(player1_buttons[2:0]),
     ~player1_right,
     ~player1_left,
     ~player1_down,
     ~player1_up};

  assign combined_players =
    {~player1_buttons,
     ~player1_right,
     ~player1_left,
     ~player1_down,
     ~player1_up,
     ~player0_buttons,
     ~player0_right,
     ~player0_left,
     ~player0_down,
     ~player0_up};

  assign guwange_p1 =
    {~(player1_buttons[2:0]),
     ~player1_right,
     ~player1_left,
     ~player1_down,
     ~player1_up,
     ~player1_start,
     ~(player0_buttons[2:0]),
     ~player0_right,
     ~player0_left,
     ~player0_down,
     ~player0_up,
     ~player0_start};

  assign input0 =
    game_is_guwange
      ? guwange_p1
      : {input0Prefix,
         ~player0_right,
         ~player0_left,
         ~player0_down,
         ~player0_up};

  assign default_or_guwange_p1 = game_is_guwange ? guwange_p1 : default_p1;
  assign combined_or_guwange_p1 = game_is_guwange ? guwange_p1 : combined_players;

  assign guwange_system =
    {8'hFF,
     eeprom_sdo,
     4'hF,
     ~service_active,
     ~coin2_active,
     ~coin1_active};

  assign gaia_system =
    {10'h3F,
     ~player1_start,
     ~player0_start,
     1'b1,
     ~service_active,
     ~coin2_active,
     ~coin1_active};

  assign input1 =
    game_is_guwange
      ? guwange_system
      : game_is_gaia ? gaia_system : default_p2;

  assign default_or_guwange_p2 = game_is_guwange ? guwange_system : default_p2;
  assign shared_system =
    {sharedSystemPrefix, ~service_active, ~coin2_active, ~coin1_active};

endmodule

module CavePauseToggle(
  input  wire clock,
  input  wire reset,
  input  wire pause_pressed,
  input  wire       ss_hold,
  input  wire       ss_load,
  input  wire [1:0] ss_state_in,
  output wire [1:0] ss_state_out,
  output reg  pause_active
);

  reg pausePressedPrev;
  assign ss_state_out = {pausePressedPrev, pause_active};

  always @(posedge clock) begin
    if (reset) begin
      pausePressedPrev <= pause_pressed;
      pause_active <= 1'b0;
    end
    else if (ss_load) begin
      pausePressedPrev <= ss_state_in[1];
      pause_active <= ss_state_in[0];
    end
    else if (ss_hold !== 1'b1) begin
      pausePressedPrev <= pause_pressed;
      pause_active <= (pause_pressed & ~pausePressedPrev) ^ pause_active;
    end
  end

endmodule

module CavePulseStretcher #(
  parameter integer COUNTER_WIDTH = 22,
  parameter [COUNTER_WIDTH-1:0] TERMINAL_COUNT = {COUNTER_WIDTH{1'b1}}
)(
  input  wire clock,
  input  wire reset,
  input  wire signal_in,
  input  wire                     ss_hold,
  input  wire                     ss_load,
  input  wire [COUNTER_WIDTH+1:0] ss_state_in,
  output wire [COUNTER_WIDTH+1:0] ss_state_out,
  output reg  pulse_active
);

  reg [COUNTER_WIDTH-1:0] counter;
  reg                     signalPrev;

  wire counterDone = counter == TERMINAL_COUNT;
  wire risingEdge = signal_in & ~signalPrev;
  assign ss_state_out = {counter, signalPrev, pulse_active};

  always @(posedge clock) begin
    if (reset) begin
      signalPrev <= signal_in;
      counter <= {COUNTER_WIDTH{1'b0}};
      pulse_active <= 1'b0;
    end
    else if (ss_load) begin
      counter <= ss_state_in[COUNTER_WIDTH+1:2];
      signalPrev <= ss_state_in[1];
      pulse_active <= ss_state_in[0];
    end
    else if (ss_hold !== 1'b1) begin
      signalPrev <= signal_in;
      if (pulse_active)
        counter <=
          counterDone
            ? {COUNTER_WIDTH{1'b0}}
            : counter + {{(COUNTER_WIDTH - 1){1'b0}}, 1'b1};
      pulse_active <= ~(pulse_active & counterDone) & (risingEdge | pulse_active);
    end
  end

endmodule

module CaveVBlankTracker(
  input  wire clock,
  input  wire vblank,
  input  wire       ss_hold,
  input  wire       ss_load,
  input  wire [3:0] ss_state_in,
  output wire [3:0] ss_state_out,
  output wire rising,
  output wire falling
);

  reg vblankPipe0;
  reg vblankPipe1;
  reg vblankRisingDelay;
  reg vblankPrevious;

  assign rising = vblankPipe1 & ~vblankRisingDelay;
  assign falling = ~vblankPipe1 & vblankPrevious;
  assign ss_state_out = {
    vblankPipe0,
    vblankPipe1,
    vblankRisingDelay,
    vblankPrevious
  };

  always @(posedge clock) begin
    if (ss_load) begin
      vblankPipe0 <= ss_state_in[3];
      vblankPipe1 <= ss_state_in[2];
      vblankRisingDelay <= ss_state_in[1];
      vblankPrevious <= ss_state_in[0];
    end
    else if (ss_hold !== 1'b1) begin
      vblankPipe0 <= vblank;
      vblankPipe1 <= vblankPipe0;
      vblankRisingDelay <= vblankPipe1;
      vblankPrevious <= vblankPipe1;
    end
  end

endmodule
