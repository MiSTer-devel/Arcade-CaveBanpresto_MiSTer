// Hotdog Storm natural-attract audio diagnostic.
//
// This fit-conscious probe deliberately exposes only four live modulo counters.
// Exact ISSP identity/width validation supplies the schema binding; software
// toggles source_i to clear all counters before a capture.
module CaveHotdogAudioHardwareDiagnostic (
  input  wire        clk_i,
  input  wire        reset_i,
  input  wire        enable_i,
  input  wire        source_i,
  input  wire        z80_m1_fetch_i,
  input  wire        ym_write_i,
  input  wire        oki_write_i,
  input  wire [15:0] mixer_sample_i,
  output wire [63:0] probe_o
);
  (* preserve, useioff = 0,
     altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
  reg source_meta_q;
  (* preserve, useioff = 0,
     altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
  reg source_sync_q;
  reg source_seen_q;

  reg [15:0] z80_m1_fetch_count_q;
  reg [15:0] ym_write_count_q;
  reg [15:0] oki_write_count_q;
  reg [15:0] mixer_change_count_q;
  reg [15:0] last_mixer_sample_q;

  wire clear_event_w = source_sync_q != source_seen_q;

  assign probe_o = {
    z80_m1_fetch_count_q,
    ym_write_count_q,
    oki_write_count_q,
    mixer_change_count_q
  };

  always @(posedge clk_i) begin
    source_meta_q <= source_i;
    source_sync_q <= source_meta_q;

    if (reset_i) begin
      source_meta_q <= 1'b0;
      source_sync_q <= 1'b0;
      source_seen_q <= 1'b0;
      z80_m1_fetch_count_q <= 16'd0;
      ym_write_count_q <= 16'd0;
      oki_write_count_q <= 16'd0;
      mixer_change_count_q <= 16'd0;
      last_mixer_sample_q <= 16'd0;
    end else if (clear_event_w) begin
      source_seen_q <= source_sync_q;
      z80_m1_fetch_count_q <= 16'd0;
      ym_write_count_q <= 16'd0;
      oki_write_count_q <= 16'd0;
      mixer_change_count_q <= 16'd0;
      last_mixer_sample_q <= mixer_sample_i;
    end else if (enable_i) begin
      if (z80_m1_fetch_i)
        z80_m1_fetch_count_q <= z80_m1_fetch_count_q + 16'd1;
      if (ym_write_i)
        ym_write_count_q <= ym_write_count_q + 16'd1;
      if (oki_write_i)
        oki_write_count_q <= oki_write_count_q + 16'd1;
      if (mixer_sample_i != last_mixer_sample_q)
        mixer_change_count_q <= mixer_change_count_q + 16'd1;
      last_mixer_sample_q <= mixer_sample_i;
    end
  end
endmodule
