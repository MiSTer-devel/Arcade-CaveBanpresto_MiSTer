// This file is a Codex-assisted rewrite based on the original work of
// Josh Bassett (nullobject).

// Signed audio mixer with fixed-point gain and 16-bit output clipping.
module AudioMixer (
  input         clock,
  input         io_airgallet,
  input         io_sailormoon,
  input         io_mazinger,
  input         io_metmqstr,
  input  [3:0]  io_audioTrim_fm,
  input  [3:0]  io_audioTrim_bgm,
  input  [3:0]  io_audioTrim_sfx,
  input  [13:0] io_in_4,
  input  [13:0] io_in_3,
  input  [15:0] io_in_2,
  input  [15:0] io_in_1,
  input  [15:0] io_in_0,
  output [15:0] io_out
);
  localparam signed [32:0] MIN_SAMPLE = -33'sd32768;
  localparam signed [32:0] MAX_SAMPLE =  33'sd32767;

  function automatic signed [30:0] apply_trim;
    input signed [28:0] sample;
    input [3:0] trim;
    reg signed [30:0] ext;
    begin
      ext = {{2{sample[28]}}, sample};
      case (trim)
        4'd0: apply_trim = 31'sd0;
        4'd1: apply_trim = ext >>> 2;
        4'd2: apply_trim = ext >>> 1;
        4'd3: apply_trim = (ext >>> 1) + (ext >>> 2);
        4'd4: apply_trim = ext;
        4'd5: apply_trim = ext + (ext >>> 2);
        4'd6: apply_trim = ext + (ext >>> 1);
        4'd7: apply_trim = ext + (ext >>> 1) + (ext >>> 2);
        4'd8: apply_trim = ext <<< 1;
        default: apply_trim = ext;
      endcase
    end
  endfunction

  function automatic signed [32:0] widen_trim;
    input signed [30:0] sample;
    begin
      widen_trim = {{2{sample[30]}}, sample};
    end
  endfunction

  wire signed [18:0] channel_1_sample = $signed({{3{io_in_1[15]}}, io_in_1});
  wire signed [21:0] channel_3_sample = $signed({{6{io_in_3[13]}}, io_in_3, 2'b00});
  wire signed [21:0] mazinger_fm_sample = $signed({{6{io_in_2[15]}}, io_in_2});
  wire signed [28:0] air_fm_sample = $signed({{13{io_in_2[15]}}, io_in_2});
  wire signed [28:0] air_bgm_sample = $signed({{13{io_in_3[13]}}, io_in_3, 2'b00});
  wire signed [28:0] air_sfx_sample = $signed({{13{io_in_4[13]}}, io_in_4, 2'b00});
  reg signed [28:0]  air_bgm_sample_reg;
  wire signed [28:0] air_bgm_smoothed = (air_bgm_sample + air_bgm_sample_reg) >>> 1;

  wire signed [18:0] channel_1_gain =
    channel_1_sample + (channel_1_sample <<< 1);
  wire signed [21:0] channel_3_gain =
    (channel_3_sample <<< 4) + (channel_3_sample <<< 3) + (channel_3_sample <<< 1);
  wire signed [21:0] mazinger_fm_gain =
    (mazinger_fm_sample <<< 3) + (mazinger_fm_sample <<< 1);
  wire signed [25:0] mazinger_oki_gain =
    $signed({{5{io_in_4[13]}}, io_in_4, 7'b0000000})
    + $signed({{7{io_in_4[13]}}, io_in_4, 5'b00000});

  wire signed [28:0] base_dac_gain = $signed({{9{io_in_0[15]}}, io_in_0, 4'b0000});
  wire signed [28:0] base_psg_gain = $signed({{10{channel_1_gain[18]}}, channel_1_gain});
  wire signed [28:0] base_fm_gain = $signed({{9{io_in_2[15]}}, io_in_2, 4'b0000});
  wire signed [28:0] base_bgm_gain = $signed({{7{channel_3_gain[21]}}, channel_3_gain});
  wire signed [28:0] base_sfx_gain = $signed({{9{io_in_4[13]}}, io_in_4, 6'b000000});
  wire signed [28:0] mazinger_psg_gain = base_psg_gain;
  wire signed [28:0] mazinger_fm_gain_ext = $signed({{7{mazinger_fm_gain[21]}}, mazinger_fm_gain});
  wire signed [28:0] mazinger_oki_gain_ext = $signed({{3{mazinger_oki_gain[25]}}, mazinger_oki_gain});
  wire signed [32:0] base_mix_ext =
    widen_trim(apply_trim(base_dac_gain, io_audioTrim_fm))
    + widen_trim(apply_trim(base_psg_gain, io_audioTrim_fm))
    + widen_trim(apply_trim(base_fm_gain, io_audioTrim_fm))
    + widen_trim(apply_trim(base_bgm_gain, io_audioTrim_bgm))
    + widen_trim(apply_trim(base_sfx_gain, io_audioTrim_sfx));
  wire signed [32:0] mazinger_mix_ext =
    widen_trim(apply_trim(mazinger_psg_gain, io_audioTrim_fm))
    + widen_trim(apply_trim(mazinger_fm_gain_ext, io_audioTrim_fm))
    + widen_trim(apply_trim(mazinger_oki_gain_ext, io_audioTrim_sfx));
  wire signed [28:0] air_fm_gain =
    air_fm_sample <<< 2;                                  // x4
  wire signed [28:0] air_bgm_gain =
    (air_bgm_smoothed <<< 6)
    + (air_bgm_smoothed <<< 5)
    + (air_bgm_smoothed <<< 4)
    + air_bgm_smoothed;                                   // x113
  wire signed [28:0] air_sfx_gain =
    (air_sfx_sample <<< 6)
    + (air_sfx_sample <<< 4);                             // x80
  wire signed [28:0] sailor_fm_gain =
    air_fm_sample <<< 3;                                  // x8
  wire signed [28:0] sailor_bgm_gain =
    (air_bgm_smoothed <<< 6)
    + (air_bgm_smoothed <<< 4)
    + (air_bgm_smoothed <<< 3)
    + (air_bgm_smoothed <<< 1);                           // x90
  wire signed [28:0] sailor_sfx_gain = air_sfx_gain;       // x80
  wire signed [28:0] metmqstr_fm_gain =
    air_fm_sample <<< 5;                                   // x32
  wire signed [28:0] metmqstr_bgm_gain =
    (air_bgm_smoothed <<< 5)
    + (air_bgm_smoothed <<< 4);                            // x48
  wire signed [28:0] metmqstr_sfx_gain =
    (air_sfx_sample <<< 5)
    + (air_sfx_sample <<< 4);                              // x48
  wire signed [32:0] air_mix_sum =
    widen_trim(apply_trim(air_fm_gain, io_audioTrim_fm))
    + widen_trim(apply_trim(air_bgm_gain, io_audioTrim_bgm))
    + widen_trim(apply_trim(air_sfx_gain, io_audioTrim_sfx));
  wire signed [32:0] sailor_mix_sum =
    widen_trim(apply_trim(sailor_fm_gain, io_audioTrim_fm))
    + widen_trim(apply_trim(sailor_bgm_gain, io_audioTrim_bgm))
    + widen_trim(apply_trim(sailor_sfx_gain, io_audioTrim_sfx));
  wire signed [32:0] metmqstr_mix_sum =
    widen_trim(apply_trim(metmqstr_fm_gain, io_audioTrim_fm))
    + widen_trim(apply_trim(metmqstr_bgm_gain, io_audioTrim_bgm))
    + widen_trim(apply_trim(metmqstr_sfx_gain, io_audioTrim_sfx));
  wire signed [32:0] air_family_mix_sum =
    io_sailormoon ? sailor_mix_sum : air_mix_sum;
  wire signed [32:0] air_mix_ext_next = air_family_mix_sum >>> 1;
  wire signed [32:0] metmqstr_mix_ext_next = metmqstr_mix_sum >>> 1;
  wire signed [32:0] mazinger_boosted_mix_sum =
    (mazinger_mix_ext <<< 1) + (mazinger_mix_ext >>> 2);
  reg signed [32:0] air_mix_ext_reg;
  reg signed [32:0] metmqstr_mix_ext_reg;
  wire signed [32:0] mix_sum =
    io_metmqstr  ? metmqstr_mix_ext_reg :
    io_airgallet ? air_mix_ext_reg :
    io_mazinger  ? mazinger_boosted_mix_sum :
                   base_mix_ext;

  wire signed [32:0] scaled_sum = mix_sum >>> 4;
  wire signed [32:0] clipped_low = scaled_sum < MIN_SAMPLE ? MIN_SAMPLE : scaled_sum;
  wire signed [32:0] clipped = clipped_low < MAX_SAMPLE ? clipped_low : MAX_SAMPLE;

  reg signed [32:0] audio_reg;

  always @(posedge clock) begin
    air_bgm_sample_reg <= air_bgm_sample;
    air_mix_ext_reg <= air_mix_ext_next;
    metmqstr_mix_ext_reg <= metmqstr_mix_ext_next;
    audio_reg <= clipped;
  end

  assign io_out = audio_reg[15:0];
endmodule
