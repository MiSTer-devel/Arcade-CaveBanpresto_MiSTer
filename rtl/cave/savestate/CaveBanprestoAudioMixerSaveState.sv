// Save-state-aware form of the original CaveBanpresto audio mixer.
//
// The arithmetic, fixed gains, clipping, and FM/BGM/SFX trim behavior below
// intentionally match rtl/cave/AudioMixer.sv. Save-state support only adds a
// reset/hold/restore shell around the four original pipeline registers.

`default_nettype none

module CaveBanprestoAudioMixerSaveState (
  input  wire         clock,
  input  wire         reset,
  input  wire         io_airgallet,
  input  wire         io_sailormoon,
  input  wire         io_mazinger,
  input  wire         io_metmqstr,
  input  wire [3:0]   io_audioTrim_fm,
  input  wire [3:0]   io_audioTrim_bgm,
  input  wire [3:0]   io_audioTrim_sfx,
  input  wire [13:0]  io_in_4,
  input  wire [13:0]  io_in_3,
  input  wire [15:0]  io_in_2,
  input  wire [15:0]  io_in_1,
  input  wire         io_ss_hold_i,
  input  wire         io_ss_restore_wr_i,
  input  wire [127:0] io_ss_restore_state_i,
  output wire [127:0] io_ss_live_state_o,
  output wire [15:0]  io_out
);
  localparam signed [32:0] MIN_SAMPLE = -33'sd32768;
  localparam signed [32:0] MAX_SAMPLE =  33'sd32767;

  function automatic signed [30:0] apply_trim;
    input signed [28:0] sample;
    input [3:0] trim;
    reg signed [30:0] ext;
    reg signed [4:0] scale;
    reg signed [35:0] product;
    reg signed [35:0] scaled;
    begin
      ext = {{2{sample[28]}}, sample};
      case (trim)
        4'd0: scale = 5'sd0;
        4'd1: scale = 5'sd1;
        4'd2: scale = 5'sd2;
        4'd3: scale = 5'sd3;
        4'd4: scale = 5'sd4;
        4'd5: scale = 5'sd5;
        4'd6: scale = 5'sd6;
        4'd7: scale = 5'sd7;
        4'd8: scale = 5'sd8;
        default: scale = 5'sd4;
      endcase
      product = ext * scale;
      scaled = product >>> 2;
      // The original 75% and 175% cases added two independently rounded
      // arithmetic shifts. A single quarter-scale multiply differs by one
      // only for the two's-complement residue 3; retain that exact behavior.
      if (((trim == 4'd3) || (trim == 4'd7)) && (sample[1:0] == 2'b11))
        scaled = scaled - 36'sd1;
      apply_trim = scaled[30:0];
    end
  endfunction

  function automatic signed [32:0] widen_trim;
    input signed [30:0] sample;
    begin
      widen_trim = {{2{sample[30]}}, sample};
    end
  endfunction

  wire signed [18:0] channel_1_sample =
    $signed({{3{io_in_1[15]}}, io_in_1});
  wire signed [21:0] channel_3_sample =
    $signed({{6{io_in_3[13]}}, io_in_3, 2'b00});
  wire signed [21:0] mazinger_fm_sample =
    $signed({{6{io_in_2[15]}}, io_in_2});
  wire signed [28:0] air_fm_sample =
    $signed({{13{io_in_2[15]}}, io_in_2});
  wire signed [28:0] air_bgm_sample =
    $signed({{13{io_in_3[13]}}, io_in_3, 2'b00});
  wire signed [28:0] air_sfx_sample =
    $signed({{13{io_in_4[13]}}, io_in_4, 2'b00});

  reg signed [28:0] air_bgm_sample_reg;
  wire signed [28:0] air_bgm_smoothed =
    (air_bgm_sample + air_bgm_sample_reg) >>> 1;

  wire signed [18:0] channel_1_gain =
    channel_1_sample + (channel_1_sample <<< 1);
  wire signed [21:0] channel_3_gain =
    (channel_3_sample <<< 4)
    + (channel_3_sample <<< 3)
    + (channel_3_sample <<< 1);
  wire signed [21:0] mazinger_fm_gain =
    (mazinger_fm_sample <<< 3) + (mazinger_fm_sample <<< 1);
  wire signed [25:0] mazinger_oki_gain =
    $signed({{5{io_in_4[13]}}, io_in_4, 7'b0000000})
    + $signed({{7{io_in_4[13]}}, io_in_4, 5'b00000});

  wire signed [28:0] base_psg_gain =
    $signed({{10{channel_1_gain[18]}}, channel_1_gain});
  wire signed [28:0] base_fm_gain =
    $signed({{9{io_in_2[15]}}, io_in_2, 4'b0000});
  wire signed [28:0] base_bgm_gain =
    $signed({{7{channel_3_gain[21]}}, channel_3_gain});
  wire signed [28:0] base_sfx_gain =
    $signed({{9{io_in_4[13]}}, io_in_4, 6'b000000});
  wire signed [28:0] mazinger_fm_gain_ext =
    $signed({{7{mazinger_fm_gain[21]}}, mazinger_fm_gain});
  wire signed [28:0] mazinger_oki_gain_ext =
    $signed({{3{mazinger_oki_gain[25]}}, mazinger_oki_gain});

  wire signed [28:0] air_fm_gain = air_fm_sample <<< 2; // x4
  wire signed [28:0] air_bgm_gain =
    (air_bgm_smoothed <<< 6)
    + (air_bgm_smoothed <<< 5)
    + (air_bgm_smoothed <<< 4)
    + air_bgm_smoothed; // x113
  wire signed [28:0] air_sfx_gain =
    (air_sfx_sample <<< 6) + (air_sfx_sample <<< 4); // x80
  wire signed [28:0] sailor_fm_gain = air_fm_sample <<< 3; // x8
  wire signed [28:0] sailor_bgm_gain =
    (air_bgm_smoothed <<< 6)
    + (air_bgm_smoothed <<< 4)
    + (air_bgm_smoothed <<< 3)
    + (air_bgm_smoothed <<< 1); // x90
  wire signed [28:0] sailor_sfx_gain = air_sfx_gain; // x80
  wire signed [28:0] metmqstr_fm_gain = air_fm_sample <<< 5; // x32
  wire signed [28:0] metmqstr_bgm_gain =
    (air_bgm_smoothed <<< 5) + (air_bgm_smoothed <<< 4); // x48
  wire signed [28:0] metmqstr_sfx_gain =
    (air_sfx_sample <<< 5) + (air_sfx_sample <<< 4); // x48

  // Only one board profile can be active for a loaded core. Select its raw
  // sources before the wide trim networks instead of materializing all five
  // complete mixers in parallel. The two FM-class terms remain separate so
  // the original per-term arithmetic-shift rounding stays bit-exact.
  wire signed [28:0] selected_fm_gain_0 =
    io_metmqstr  ? metmqstr_fm_gain :
    io_airgallet ? (io_sailormoon ? sailor_fm_gain : air_fm_gain) :
                   base_psg_gain;
  wire signed [28:0] selected_fm_gain_1 =
    io_airgallet ? 29'sd0 :
    io_mazinger  ? mazinger_fm_gain_ext :
                   base_fm_gain;
  wire signed [28:0] selected_bgm_gain =
    io_metmqstr  ? metmqstr_bgm_gain :
    io_airgallet ? (io_sailormoon ? sailor_bgm_gain : air_bgm_gain) :
    io_mazinger  ? 29'sd0 :
                   base_bgm_gain;
  wire signed [28:0] selected_sfx_gain =
    io_metmqstr  ? metmqstr_sfx_gain :
    io_airgallet ? air_sfx_gain :
    io_mazinger  ? mazinger_oki_gain_ext :
                   base_sfx_gain;
  wire signed [32:0] selected_mix_sum =
    widen_trim(apply_trim(selected_fm_gain_0, io_audioTrim_fm))
    + widen_trim(apply_trim(selected_fm_gain_1, io_audioTrim_fm))
    + widen_trim(apply_trim(selected_bgm_gain, io_audioTrim_bgm))
    + widen_trim(apply_trim(selected_sfx_gain, io_audioTrim_sfx));
  wire signed [32:0] fast_mix_ext_next = selected_mix_sum >>> 1;
  wire signed [32:0] mazinger_boosted_mix_sum =
    (selected_mix_sum <<< 1) + (selected_mix_sum >>> 2);

  reg signed [32:0] air_mix_ext_reg;
  reg signed [32:0] metmqstr_mix_ext_reg;
  wire signed [32:0] mix_sum =
    io_metmqstr  ? metmqstr_mix_ext_reg :
    io_airgallet ? air_mix_ext_reg :
    io_mazinger  ? mazinger_boosted_mix_sum :
                   selected_mix_sum;

  wire signed [32:0] scaled_sum = mix_sum >>> 4;
  wire signed [32:0] clipped_low =
    scaled_sum < MIN_SAMPLE ? MIN_SAMPLE : scaled_sum;
  wire signed [32:0] clipped =
    clipped_low < MAX_SAMPLE ? clipped_low : MAX_SAMPLE;

  reg signed [32:0] audio_reg;

  always @(posedge clock) begin
    if (reset) begin
      air_bgm_sample_reg   <= 29'sd0;
      air_mix_ext_reg      <= 33'sd0;
      metmqstr_mix_ext_reg <= 33'sd0;
      audio_reg            <= 33'sd0;
    end else if (io_ss_restore_wr_i) begin
      audio_reg            <= io_ss_restore_state_i[127:95];
      metmqstr_mix_ext_reg <= io_ss_restore_state_i[94:62];
      air_mix_ext_reg      <= io_ss_restore_state_i[61:29];
      air_bgm_sample_reg   <= io_ss_restore_state_i[28:0];
    end else if (!io_ss_hold_i) begin
      air_bgm_sample_reg   <= air_bgm_sample;
      air_mix_ext_reg      <= fast_mix_ext_next;
      metmqstr_mix_ext_reg <= fast_mix_ext_next;
      audio_reg            <= clipped;
    end
  end

  assign io_ss_live_state_o = {
    audio_reg,
    metmqstr_mix_ext_reg,
    air_mix_ext_reg,
    air_bgm_sample_reg
  };
  assign io_out = audio_reg[15:0];
endmodule

`default_nettype wire
