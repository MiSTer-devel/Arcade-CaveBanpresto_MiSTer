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
    else begin
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

  always @(posedge clock) begin
    if (reset) begin
      watchdogDelayCounter <= 6'd0;
      watchdogResetCounter <= 5'd0;
      marker0Seen <= 1'b0;
      marker1Seen <= 1'b0;
      bootWatchdogArmed <= 1'b1;
    end
    else begin
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
