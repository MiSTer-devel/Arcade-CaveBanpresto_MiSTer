// This file is a Codex-assisted rewrite based on the original work of
// Josh Bassett (nullobject).

module MazingerBootWatchdog(
  input         clock,
  input         reset,
  input         game_active,
  input         boot_ram_select,
  input         boot_ram_write,
  input         boot_ram_word,
  input  [1:0]  boot_ram_mask,
  input  [15:0] boot_ram_din,
  input         watchdog_write,
  input         ss_hold,
  input         ss_load,
  input  [43:0] ss_state_in,
  output [43:0] ss_state_out,
  output        cpu_reset,
  output [15:0] boot_ram_dout,
  output        watchdog_armed,
  output        watchdog_delay_active,
  output        watchdog_reset_active,
  output        boot_marker_write,
  output        watchdog_trip
);
  localparam [20:0] WATCHDOG_TIMEOUT_TICKS = 21'd1125000;

  reg  [5:0]  watchdogDelayCounter;
  reg  [4:0]  watchdogResetCounter;
  reg  [7:0]  watchdogPrescaler;
  reg  [20:0] watchdogCounter;
  reg         bootWatchdogArmed;
  reg  [15:0] bootRam0;
  reg  [15:0] bootRam1;

  wire watchdogTimedOut =
    game_active & (watchdogCounter == 21'd1) & (watchdogPrescaler == 8'hff);

  assign boot_marker_write =
    game_active & bootWatchdogArmed & boot_ram_select & boot_ram_write
    & (boot_ram_din == 16'h5555);
  assign watchdog_trip = (watchdogDelayCounter == 6'd1) | watchdogTimedOut;
  assign watchdog_armed = bootWatchdogArmed;
  assign watchdog_delay_active = |watchdogDelayCounter;
  assign watchdog_reset_active = |watchdogResetCounter;
  assign cpu_reset = reset | watchdog_reset_active;
  assign boot_ram_dout = boot_ram_word ? bootRam1 : bootRam0;
  assign ss_state_out = {
    watchdogDelayCounter,
    watchdogResetCounter,
    bootWatchdogArmed,
    bootRam0,
    bootRam1
  };

  always @(posedge clock) begin
    if (reset) begin
      watchdogDelayCounter <= 6'd0;
      watchdogResetCounter <= 5'd0;
      watchdogPrescaler <= 8'd0;
      watchdogCounter <= WATCHDOG_TIMEOUT_TICKS;
      bootWatchdogArmed <= 1'b1;
      bootRam0 <= 16'd0;
      bootRam1 <= 16'd0;
    end
    else if (ss_load) begin
      watchdogDelayCounter <= ss_state_in[43:38];
      watchdogResetCounter <= ss_state_in[37:33];
      // The upstream service-watchdog counter postdates the 44-bit save-state
      // image. Refresh this derived timer on restore instead of retaining an
      // unrelated live countdown that can reset the restored game at once.
      watchdogPrescaler <= 8'd0;
      watchdogCounter <= WATCHDOG_TIMEOUT_TICKS;
      bootWatchdogArmed <= ss_state_in[32];
      bootRam0 <= ss_state_in[31:16];
      bootRam1 <= ss_state_in[15:0];
    end
    else if (ss_hold !== 1'b1) begin
      if (~game_active) begin
        watchdogDelayCounter <= 6'd0;
        watchdogResetCounter <= 5'd0;
        watchdogPrescaler <= 8'd0;
        watchdogCounter <= WATCHDOG_TIMEOUT_TICKS;
        bootWatchdogArmed <= 1'b1;
      end
      else if (watchdog_write) begin
        watchdogPrescaler <= 8'd0;
        watchdogCounter <= WATCHDOG_TIMEOUT_TICKS;
      end
      else if (boot_marker_write & (watchdogDelayCounter == 6'd0))
        watchdogDelayCounter <= 6'd32;
      else if (watchdog_trip) begin
        watchdogDelayCounter <= 6'd0;
        watchdogResetCounter <= 5'd16;
        watchdogPrescaler <= 8'd0;
        watchdogCounter <= WATCHDOG_TIMEOUT_TICKS;
        bootWatchdogArmed <= 1'b0;
      end
      else if (watchdog_delay_active)
        watchdogDelayCounter <= watchdogDelayCounter - 6'd1;
      else if (watchdog_reset_active)
        watchdogResetCounter <= watchdogResetCounter - 5'd1;
      else begin
        watchdogPrescaler <= watchdogPrescaler + 8'd1;
        if (watchdogPrescaler == 8'hff)
          watchdogCounter <= watchdogCounter - 21'd1;
      end

      if (game_active & boot_ram_select & boot_ram_write) begin
        if (boot_ram_word) begin
          if (boot_ram_mask[1])
            bootRam1[15:8] <= boot_ram_din[15:8];
          if (boot_ram_mask[0])
            bootRam1[7:0] <= boot_ram_din[7:0];
        end
        else begin
          if (boot_ram_mask[1])
            bootRam0[15:8] <= boot_ram_din[15:8];
          if (boot_ram_mask[0])
            bootRam0[7:0] <= boot_ram_din[7:0];
        end
      end
    end
  end
endmodule

module MetmqstrBootWatchdog(
  input         clock,
  input         reset,
  input         game_active,
  input         sprite_ram_write,
  input  [14:0] sprite_ram_addr,
  input  [1:0]  sprite_ram_mask,
  input  [15:0] sprite_ram_din,
  input         ss_hold,
  input         ss_load,
  input  [13:0] ss_state_in,
  output [13:0] ss_state_out,
  output        cpu_reset,
  output        marker_seen,
  output        watchdog_delay_active,
  output        watchdog_reset_active,
  output        watchdog_trip
);
  reg [5:0] watchdogDelayCounter;
  reg [4:0] watchdogResetCounter;
  reg       marker0Seen;
  reg       marker1Seen;
  reg       bootWatchdogArmed;

  wire marker0Write =
    game_active & bootWatchdogArmed & sprite_ram_write &
    (sprite_ram_addr == 15'h4000) & (&sprite_ram_mask) &
    (sprite_ram_din == 16'h0123);
  wire marker1Write =
    game_active & bootWatchdogArmed & sprite_ram_write &
    (sprite_ram_addr == 15'h4001) & (&sprite_ram_mask) &
    (sprite_ram_din == 16'h4567);
  wire markerComplete =
    (marker0Seen | marker0Write) & (marker1Seen | marker1Write);

  assign marker_seen = markerComplete | ~bootWatchdogArmed;
  assign watchdog_trip = watchdogDelayCounter == 6'd1;
  assign watchdog_delay_active = |watchdogDelayCounter;
  assign watchdog_reset_active = |watchdogResetCounter;
  assign cpu_reset = reset | watchdog_reset_active;
  assign ss_state_out = {
    watchdogDelayCounter,
    watchdogResetCounter,
    marker0Seen,
    marker1Seen,
    bootWatchdogArmed
  };

  always @(posedge clock) begin
    if (reset) begin
      watchdogDelayCounter <= 6'd0;
      watchdogResetCounter <= 5'd0;
      marker0Seen <= 1'b0;
      marker1Seen <= 1'b0;
      bootWatchdogArmed <= 1'b1;
    end
    else if (ss_load) begin
      watchdogDelayCounter <= ss_state_in[13:8];
      watchdogResetCounter <= ss_state_in[7:3];
      marker0Seen <= ss_state_in[2];
      marker1Seen <= ss_state_in[1];
      bootWatchdogArmed <= ss_state_in[0];
    end
    else if (ss_hold !== 1'b1) begin
      if (~game_active) begin
        watchdogDelayCounter <= 6'd0;
        watchdogResetCounter <= 5'd0;
        marker0Seen <= 1'b0;
        marker1Seen <= 1'b0;
        bootWatchdogArmed <= 1'b1;
      end
      else begin
        if (marker0Write)
          marker0Seen <= 1'b1;
        if (marker1Write)
          marker1Seen <= 1'b1;

        if (bootWatchdogArmed & markerComplete & (watchdogDelayCounter == 6'd0))
          watchdogDelayCounter <= 6'd32;
        else if (watchdog_trip) begin
          watchdogDelayCounter <= 6'd0;
          watchdogResetCounter <= 5'd16;
          bootWatchdogArmed <= 1'b0;
        end
        else if (watchdog_delay_active)
          watchdogDelayCounter <= watchdogDelayCounter - 6'd1;
        else if (watchdog_reset_active)
          watchdogResetCounter <= watchdogResetCounter - 5'd1;
      end
    end
  end
endmodule
