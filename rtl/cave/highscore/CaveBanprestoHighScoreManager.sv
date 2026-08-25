// CaveBanpresto-local high-score persistence using MRA-described CPU byte
// ranges. The five board profiles place score data in either Main's 64 KiB
// main RAM or Metamoqester's 64 KiB sprite-RAM window; no shared framework
// module participates in this ownership path.
module CaveBanprestoHighScoreManager (
  input         sys_clock,
  input         sys_reset,
  input         cpu_clock,
  input         cpu_reset,
  input  [3:0]  game_index_sys,
  input  [3:0]  game_index_cpu,

  input         config_download,
  input         config_wr,
  input  [26:0] config_addr,
  input  [15:0] config_dout,

  input         nvram_download,
  input         nvram_upload,
  input         nvram_rd,
  input         nvram_wr,
  input  [26:0] nvram_addr,
  input  [15:0] nvram_dout,
  output [15:0] nvram_din,
  output        nvram_wait_n,

  input         ss_hold_cpu,
  input         cpu_idle,
  input         normal_ram_wr,
  input  [23:0] normal_byte_addr,
  input  [1:0]  normal_ram_mask,
  input  [15:0] normal_ram_din,

  output        cpu_hold,
  output        ram_owned,
  output        ram_rd,
  output        ram_wr,
  output [14:0] ram_addr,
  output [1:0]  ram_mask,
  output [15:0] ram_din,
  output        ram_target_sprite,
  input  [15:0] ram_dout,

  output        dirty_sys,
  output        active_sys
);

  localparam [2:0] STATE_IDLE          = 3'd0;
  localparam [2:0] STATE_RESTORE_HOLD  = 3'd1;
  localparam [2:0] STATE_RESTORE_READ  = 3'd2;
  localparam [2:0] STATE_RESTORE_WRITE = 3'd3;
  localparam [2:0] STATE_CAPTURE_HOLD  = 3'd4;
  localparam [2:0] STATE_CAPTURE_READ  = 3'd5;
  localparam [2:0] STATE_CAPTURE_WRITE = 3'd6;

  // Every versioned file is a fixed 392 bytes: the existing 128-byte EEPROM
  // prefix, a 256-byte maximum score window, and an eight-byte format trailer.
  // Keeping the trailer at a fixed address preserves the compact score-address
  // decode and makes padded legacy/current-unversioned files fail closed.
  localparam [26:0] NVRAM_METADATA_BASE = 27'd384;

  wire [15:0] config_word = {config_dout[7:0], config_dout[15:8]};

  reg         config_download_d;
  reg  [7:0]  config_written;
  reg         config_primary_match_sys;
  reg         config_secondary_match_sys;
  reg         config_valid_sys;
  reg  [2:0]  config_profile_sys;
  reg         config_toggle_sys;

  // The shipped MRAs carry one of six exact, MAME-derived descriptors. Keep
  // the packed matcher that Quartus maps more efficiently than a direct case
  // decoder; only game index 4 needs a secondary Ninja Master comparator.
  localparam [127:0] DESCRIPTOR_HOTDOG =
    128'h0000_0000_0000_0000_0014_0054_1100_0030;
  localparam [127:0] DESCRIPTOR_MAZINGER =
    128'h0000_0000_0000_0000_004e_0043_0022_0010;
  localparam [127:0] DESCRIPTOR_AIR =
    128'h021a_0002_0200_0010_0000_005a_0292_0010;
  localparam [127:0] DESCRIPTOR_SAILOR =
    128'h0000_0000_0000_0000_0205_0047_944f_0010;
  localparam [127:0] DESCRIPTOR_MET =
    128'h0000_0000_0000_0000_0a01_0100_80e0_00f0;
  localparam [127:0] DESCRIPTOR_NINJA =
    128'h0000_0000_0000_0000_3001_00e0_8100_00f0;

  wire [127:0] primary_descriptor_sys =
    game_index_sys == 4'd0 ? DESCRIPTOR_HOTDOG :
    game_index_sys == 4'd1 ? DESCRIPTOR_MAZINGER :
    game_index_sys == 4'd2 ? DESCRIPTOR_AIR :
    game_index_sys == 4'd3 ? DESCRIPTOR_SAILOR :
    game_index_sys == 4'd4 ? DESCRIPTOR_MET : 128'd0;
  wire [15:0] primary_expected_word_sys =
    primary_descriptor_sys[{config_addr[3:1], 4'b0000} +: 16];
  wire [15:0] secondary_expected_word_sys =
    DESCRIPTOR_NINJA[{config_addr[3:1], 4'b0000} +: 16];

  always @(posedge sys_clock) begin
    config_download_d <= config_download;

    if (sys_reset) begin
      config_download_d <= 1'b0;
      config_written <= 8'd0;
      config_primary_match_sys <= 1'b0;
      config_secondary_match_sys <= 1'b0;
      config_valid_sys <= 1'b0;
      config_profile_sys <= 3'd7;
      config_toggle_sys <= 1'b0;
    end else begin
      if (config_download && !config_download_d) begin
        config_written <= 8'd0;
        config_primary_match_sys <= game_index_sys <= 4'd4;
        config_secondary_match_sys <= game_index_sys == 4'd4;
        config_valid_sys <= 1'b0;
      end

      if (config_download && config_wr && (config_addr[26:4] == 23'd0)) begin
        config_written[config_addr[3:1]] <= 1'b1;
        config_primary_match_sys <= config_primary_match_sys &&
          (config_word == primary_expected_word_sys);
        config_secondary_match_sys <= config_secondary_match_sys &&
          (config_word == secondary_expected_word_sys);
      end

      if (!config_download && config_download_d) begin
        config_valid_sys <= 1'b0;
        config_profile_sys <= 3'd7;
        if ((game_index_sys <= 4'd4) && config_primary_match_sys &&
            (config_written ==
             (game_index_sys == 4'd2 ? 8'hff : 8'h0f))) begin
          config_valid_sys <= 1'b1;
          config_profile_sys <= game_index_sys[2:0];
        end else if ((game_index_sys == 4'd4) && config_secondary_match_sys &&
                     (config_written == 8'h0f)) begin
          config_valid_sys <= 1'b1;
          config_profile_sys <= 3'd5;
        end
        config_toggle_sys <= ~config_toggle_sys;
      end
    end
  end

  // Every supported exact profile is at most 256 score bytes. Addresses
  // 128..383 have complementary bits [8:7], allowing a small exact decoder.
  wire score_window_nvram_address =
    (nvram_addr[26:9] == 18'd0) &&
    (nvram_addr[8] ^ nvram_addr[7]);
  wire [7:0] score_byte_offset_sys = nvram_addr[7:0] ^ 8'h80;
  wire [6:0] score_word_address_sys = score_byte_offset_sys[7:1];
  wire [8:0] payload_length_sys =
    config_profile_sys == 3'd0 ? 9'd84 :
    config_profile_sys == 3'd1 ? 9'd67 :
    config_profile_sys == 3'd2 ? 9'd92 :
    config_profile_sys == 3'd3 ? 9'd71 :
    config_profile_sys == 3'd4 ? 9'd256 :
    config_profile_sys == 3'd5 ? 9'd224 : 9'd0;
  wire score_nvram_address =
    score_window_nvram_address &&
    ({1'b0, score_byte_offset_sys} < payload_length_sys);
  wire metadata_nvram_address =
    nvram_addr[26:3] == NVRAM_METADATA_BASE[26:3];
  wire [1:0] metadata_word_address_sys = nvram_addr[2:1];
  wire [15:0] nvram_file_word_sys =
    {nvram_dout[7:0], nvram_dout[15:8]};
  reg [15:0] expected_metadata_word_sys;
  always @* begin
    case (metadata_word_address_sys)
      2'd0: expected_metadata_word_sys = 16'h4342; // "CB"
      2'd1: expected_metadata_word_sys = 16'h4853; // "HS"
      2'd2: expected_metadata_word_sys = 16'h0108; // schema 1, 8 bytes
      default: expected_metadata_word_sys = {7'd0, payload_length_sys};
    endcase
  end
  wire [15:0] score_buffer_din_sys = nvram_file_word_sys;
  wire metadata_wr_sys =
    nvram_download && nvram_wr && metadata_nvram_address;
  wire load_buffer_wr_sys =
    nvram_download && nvram_wr && score_nvram_address;
  wire load_buffer_rd_sys =
    nvram_upload && nvram_rd && score_nvram_address;
  wire [15:0] load_buffer_q_sys;
  wire [7:0]  load_buffer_q_cpu;
  wire [15:0] save_buffer_q_sys;

  reg         nvram_download_d;
  reg  [3:0]  metadata_written_sys;
  reg         metadata_matches_sys;
  reg  [7:0]  score_word_count_sys;
  reg         score_sequence_error_sys;
  reg         nvram_payload_ready_sys;
  reg         nvram_validation_pending_sys;
  reg         nvram_has_data_sys;
  reg         nvram_load_toggle_sys;

  reg         nvram_upload_started_sys;
  reg         upload_ready_sys;
  reg         capture_pending_sys;
  reg         capture_complete_delay_sys;
  reg         capture_request_toggle_sys;
  reg         capture_done_meta_sys;
  reg         capture_done_sync_sys;
  reg         capture_done_seen_sys;
  reg         capture_valid_meta_sys;
  reg         capture_valid_sync_sys;
  reg         snapshot_valid_sys;

  reg         dirty_meta_sys;
  reg         dirty_sync_sys;
  reg         active_meta_sys;
  reg         active_sync_sys;

  wire        capture_done_toggle_cpu;
  wire        capture_valid_cpu;
  wire        dirty_cpu;
  wire        active_cpu;

  always @(posedge sys_clock) begin
    nvram_download_d <= nvram_download;
    capture_done_meta_sys <= capture_done_toggle_cpu;
    capture_done_sync_sys <= capture_done_meta_sys;
    capture_valid_meta_sys <= capture_valid_cpu;
    capture_valid_sync_sys <= capture_valid_meta_sys;
    dirty_meta_sys <= dirty_cpu;
    dirty_sync_sys <= dirty_meta_sys;
    active_meta_sys <= active_cpu;
    active_sync_sys <= active_meta_sys;

    if (sys_reset) begin
      nvram_download_d <= 1'b0;
      metadata_written_sys <= 4'd0;
      metadata_matches_sys <= 1'b0;
      score_word_count_sys <= 8'd0;
      score_sequence_error_sys <= 1'b0;
      nvram_payload_ready_sys <= 1'b0;
      nvram_validation_pending_sys <= 1'b0;
      nvram_has_data_sys <= 1'b0;
      nvram_load_toggle_sys <= 1'b0;
      nvram_upload_started_sys <= 1'b0;
      upload_ready_sys <= 1'b0;
      capture_pending_sys <= 1'b0;
      capture_complete_delay_sys <= 1'b0;
      capture_request_toggle_sys <= 1'b0;
      capture_done_meta_sys <= 1'b0;
      capture_done_sync_sys <= 1'b0;
      capture_done_seen_sys <= 1'b0;
      capture_valid_meta_sys <= 1'b0;
      capture_valid_sync_sys <= 1'b0;
      snapshot_valid_sys <= 1'b0;
      dirty_meta_sys <= 1'b0;
      dirty_sync_sys <= 1'b0;
      active_meta_sys <= 1'b0;
      active_sync_sys <= 1'b0;
    end else begin
      if (nvram_download && !nvram_download_d) begin
        metadata_written_sys <= 4'd0;
        metadata_matches_sys <= 1'b1;
        score_word_count_sys <= 8'd0;
        score_sequence_error_sys <= 1'b0;
        nvram_payload_ready_sys <= 1'b0;
        nvram_validation_pending_sys <= 1'b0;
        nvram_has_data_sys <= 1'b0;
        snapshot_valid_sys <= 1'b0;
      end
      if (metadata_wr_sys) begin
        metadata_written_sys[metadata_word_address_sys] <= 1'b1;
        metadata_matches_sys <= metadata_matches_sys &&
          (nvram_file_word_sys == expected_metadata_word_sys);
      end
      if (load_buffer_wr_sys && !score_sequence_error_sys) begin
        if ({1'b0, score_byte_offset_sys} ==
            {score_word_count_sys, 1'b0})
          score_word_count_sys <= score_word_count_sys + 8'd1;
        else
          score_sequence_error_sys <= 1'b1;
      end
      if (!nvram_download && nvram_download_d) begin
        nvram_payload_ready_sys <=
          (&metadata_written_sys) && metadata_matches_sys &&
          !score_sequence_error_sys &&
          (score_word_count_sys == payload_length_sys[8:1] +
           payload_length_sys[0]);
        nvram_validation_pending_sys <= 1'b1;
      end
      if (nvram_validation_pending_sys) begin
        nvram_has_data_sys <=
          config_valid_sys && nvram_payload_ready_sys;
        nvram_load_toggle_sys <= ~nvram_load_toggle_sys;
        nvram_validation_pending_sys <= 1'b0;
      end

      if (!nvram_upload) begin
        nvram_upload_started_sys <= 1'b0;
        upload_ready_sys <= 1'b0;
        capture_pending_sys <= 1'b0;
        capture_complete_delay_sys <= 1'b0;
      end else if (!nvram_upload_started_sys) begin
        nvram_upload_started_sys <= 1'b1;
        if (config_valid_sys) begin
          capture_request_toggle_sys <= ~capture_request_toggle_sys;
          capture_pending_sys <= 1'b1;
        end
      end

      if (capture_pending_sys &&
          (capture_done_sync_sys != capture_done_seen_sys)) begin
        capture_done_seen_sys <= capture_done_sync_sys;
        capture_complete_delay_sys <= 1'b1;
      end

      if (capture_complete_delay_sys) begin
        snapshot_valid_sys <= capture_valid_sync_sys;
        capture_pending_sys <= 1'b0;
        capture_complete_delay_sys <= 1'b0;
        upload_ready_sys <= 1'b1;
      end
    end
  end

  assign nvram_wait_n =
    !nvram_upload || !config_valid_sys || upload_ready_sys;
  wire [15:0] metadata_upload_word_sys = snapshot_valid_sys
    ? expected_metadata_word_sys : 16'h0000;
  // Odd-sized profiles occupy the high byte of their final file word.  The
  // low byte is outside the versioned payload and must be deterministic; it
  // must never expose an unwritten byte from the capture buffer.
  wire score_upload_odd_tail_sys =
    payload_length_sys[0] &&
    (score_word_address_sys == payload_length_sys[7:1]);
  wire [15:0] score_upload_word_sys = score_upload_odd_tail_sys
    ? {save_buffer_q_sys[15:8], 8'h00} : save_buffer_q_sys;
  assign nvram_din = metadata_nvram_address
    ? {metadata_upload_word_sys[7:0], metadata_upload_word_sys[15:8]}
    : score_nvram_address
      ? snapshot_valid_sys
        ? {score_upload_word_sys[7:0], score_upload_word_sys[15:8]}
        : {load_buffer_q_sys[7:0], load_buffer_q_sys[15:8]}
      : 16'h0000;
  assign dirty_sys = dirty_sync_sys;
  assign active_sys = active_sync_sys;

  reg         config_toggle_meta_cpu;
  reg         config_toggle_sync_cpu;
  reg         config_toggle_seen_cpu;
  reg         config_valid_meta_cpu;
  reg         config_valid_sync_cpu;
  reg  [2:0]  config_profile_meta_cpu;
  reg  [2:0]  config_profile_sync_cpu;

  reg         nvram_load_toggle_meta_cpu;
  reg         nvram_load_toggle_sync_cpu;
  reg         nvram_load_toggle_seen_cpu;
  reg         nvram_has_data_meta_cpu;
  reg         nvram_has_data_sync_cpu;
  reg         capture_request_meta_cpu;
  reg         capture_request_sync_cpu;

  always @(posedge cpu_clock) begin
    config_toggle_meta_cpu <= config_toggle_sys;
    config_toggle_sync_cpu <= config_toggle_meta_cpu;
    config_valid_meta_cpu <= config_valid_sys;
    config_valid_sync_cpu <= config_valid_meta_cpu;
    config_profile_meta_cpu <= config_profile_sys;
    config_profile_sync_cpu <= config_profile_meta_cpu;
    nvram_load_toggle_meta_cpu <= nvram_load_toggle_sys;
    nvram_load_toggle_sync_cpu <= nvram_load_toggle_meta_cpu;
    nvram_has_data_meta_cpu <= nvram_has_data_sys;
    nvram_has_data_sync_cpu <= nvram_has_data_meta_cpu;
    capture_request_meta_cpu <= capture_request_toggle_sys;
    capture_request_sync_cpu <= capture_request_meta_cpu;
  end

  reg  [2:0]  config_profile_cpu;
  reg         config_valid_cpu;
  reg         config_initialized_cpu;
  reg         load_data_available_cpu;

  reg         range0_first_match_cpu;
  reg         range0_last_match_cpu;
  reg         range1_first_match_cpu;
  reg         range1_last_match_cpu;
  reg         scores_ready_cpu;
  reg         restore_applied_cpu;
  reg         dirty_cpu_r;
  reg         capture_done_toggle_cpu_r;
  reg         capture_valid_cpu_r;
  reg  [2:0]  state_cpu;
  reg         range_select_cpu;
  reg  [7:0]  range_offset_cpu;
  reg  [7:0]  buffer_offset_cpu;

  wire [15:0] range0_start_cpu =
    config_profile_cpu == 3'd0 ? 16'h1100 :
    config_profile_cpu == 3'd1 ? 16'h0022 :
    config_profile_cpu == 3'd2 ? 16'h0292 :
    config_profile_cpu == 3'd3 ? 16'h944f :
    config_profile_cpu == 3'd4 ? 16'h80e0 :
    config_profile_cpu == 3'd5 ? 16'h8100 : 16'h0000;
  wire [7:0] range0_first_cpu =
    config_profile_cpu == 3'd3 ? 8'h02 :
    config_profile_cpu == 3'd4 ? 8'h0a :
    config_profile_cpu == 3'd5 ? 8'h30 : 8'h00;
  wire [7:0] range0_last_cpu =
    config_profile_cpu == 3'd0 ? 8'h14 :
    config_profile_cpu == 3'd1 ? 8'h4e :
    config_profile_cpu == 3'd2 ? 8'h00 :
    config_profile_cpu == 3'd3 ? 8'h05 : 8'h01;
  wire [15:0] range1_start_cpu = 16'h0200;
  wire [7:0] range1_first_cpu = 8'h02;
  wire [7:0] range1_last_cpu = 8'h1a;
  wire range1_valid_cpu = config_profile_cpu == 3'd2;
  wire [3:0] profile_game_cpu =
    config_profile_cpu >= 3'd4 ? 4'd4 : {1'b0, config_profile_cpu};

  wire [15:0] current_range_start_cpu =
    range_select_cpu ? range1_start_cpu : range0_start_cpu;
  wire [15:0] current_byte_offset_cpu =
    current_range_start_cpu + {8'd0, range_offset_cpu};
  wire [7:0] range0_last_offset_cpu =
    config_profile_cpu == 3'd0 ? 8'd83 :
    config_profile_cpu == 3'd1 ? 8'd66 :
    config_profile_cpu == 3'd2 ? 8'd89 :
    config_profile_cpu == 3'd3 ? 8'd70 :
    config_profile_cpu == 3'd4 ? 8'd255 :
    config_profile_cpu == 3'd5 ? 8'd223 : 8'd0;
  wire [7:0] current_range_last_offset_cpu =
    range_select_cpu ? 8'd1 : range0_last_offset_cpu;
  wire        range0_ready_cpu =
    range0_first_match_cpu && range0_last_match_cpu;
  wire        range1_ready_cpu =
    !range1_valid_cpu ||
    (range1_first_match_cpu && range1_last_match_cpu);
  wire profile_matches_cpu =
    (config_profile_cpu <= 3'd5) &&
    (profile_game_cpu == game_index_cpu);
  // Main presents an aligned 16-bit word address plus two byte enables. Decode
  // score writes once in that word domain rather than duplicating 16-bit byte
  // address adders and range comparators for the even and odd lanes.
  wire [14:0] normal_word_cpu = normal_byte_addr[15:1];
  wire [14:0] range0_start_word_cpu = range0_start_cpu[15:1];
  wire [14:0] range0_end_word_cpu =
    config_profile_cpu == 3'd0 ? 15'h08a9 :
    config_profile_cpu == 3'd1 ? 15'h0032 :
    config_profile_cpu == 3'd2 ? 15'h0175 :
    config_profile_cpu == 3'd3 ? 15'h4a4a :
    config_profile_cpu >= 3'd4 ? 15'h40ef : 15'h0000;
  wire        range0_end_odd_cpu = config_profile_cpu != 3'd1;
  wire        normal_word_in_range0 =
    (normal_word_cpu >= range0_start_word_cpu) &&
    (normal_word_cpu <= range0_end_word_cpu);
  wire        normal_even_in_range0 = normal_ram_mask[1] &&
    normal_word_in_range0 &&
    !(range0_start_cpu[0] &&
      (normal_word_cpu == range0_start_word_cpu));
  wire        normal_odd_in_range0 = normal_ram_mask[0] &&
    normal_word_in_range0 &&
    !(!range0_end_odd_cpu &&
      (normal_word_cpu == range0_end_word_cpu));
  wire        normal_write_in_range0 =
    normal_even_in_range0 || normal_odd_in_range0;
  wire        normal_write_in_range1 = range1_valid_cpu &&
    (normal_word_cpu == range1_start_cpu[15:1]) &&
    (|normal_ram_mask);

  always @(posedge cpu_clock) begin
    if (cpu_reset) begin
      config_toggle_seen_cpu <= ~config_toggle_sync_cpu;
      nvram_load_toggle_seen_cpu <= nvram_load_toggle_sync_cpu;
      config_profile_cpu <= 3'd7;
      config_valid_cpu <= 1'b0;
      config_initialized_cpu <= 1'b0;
      load_data_available_cpu <= 1'b0;
      range0_first_match_cpu <= 1'b0;
      range0_last_match_cpu <= 1'b0;
      range1_first_match_cpu <= 1'b0;
      range1_last_match_cpu <= 1'b0;
      scores_ready_cpu <= 1'b0;
      restore_applied_cpu <= 1'b0;
      dirty_cpu_r <= 1'b0;
      capture_done_toggle_cpu_r <= capture_request_sync_cpu;
      capture_valid_cpu_r <= 1'b0;
      state_cpu <= STATE_IDLE;
      range_select_cpu <= 1'b0;
      range_offset_cpu <= 8'd0;
      buffer_offset_cpu <= 8'd0;
    end else if ((config_toggle_sync_cpu != config_toggle_seen_cpu) ||
                 (!config_initialized_cpu && config_valid_sync_cpu)) begin
      config_toggle_seen_cpu <= config_toggle_sync_cpu;
      config_profile_cpu <= config_profile_sync_cpu;
      config_valid_cpu <= config_valid_sync_cpu;
      config_initialized_cpu <= 1'b1;
      range0_first_match_cpu <= 1'b0;
      range0_last_match_cpu <= 1'b0;
      range1_first_match_cpu <= 1'b0;
      range1_last_match_cpu <= 1'b0;
      scores_ready_cpu <= 1'b0;
      restore_applied_cpu <= 1'b0;
      dirty_cpu_r <= 1'b0;
      capture_valid_cpu_r <= 1'b0;
      state_cpu <= STATE_IDLE;
    end else begin
      if (nvram_load_toggle_sync_cpu != nvram_load_toggle_seen_cpu) begin
        nvram_load_toggle_seen_cpu <= nvram_load_toggle_sync_cpu;
        load_data_available_cpu <= nvram_has_data_sync_cpu;
        restore_applied_cpu <= 1'b0;
        capture_valid_cpu_r <= 1'b0;
      end else if (!load_data_available_cpu && nvram_has_data_sync_cpu) begin
        load_data_available_cpu <= 1'b1;
      end

      if (config_valid_cpu && profile_matches_cpu && normal_ram_wr) begin
        if (normal_word_cpu == range0_start_word_cpu) begin
          if (!range0_start_cpu[0] && normal_ram_mask[1])
            range0_first_match_cpu <= normal_ram_din[15:8] == range0_first_cpu;
          if (range0_start_cpu[0] && normal_ram_mask[0])
            range0_first_match_cpu <= normal_ram_din[7:0] == range0_first_cpu;
        end
        if (normal_word_cpu == range0_end_word_cpu) begin
          if (!range0_end_odd_cpu && normal_ram_mask[1])
            range0_last_match_cpu <= normal_ram_din[15:8] == range0_last_cpu;
          if (range0_end_odd_cpu && normal_ram_mask[0])
            range0_last_match_cpu <= normal_ram_din[7:0] == range0_last_cpu;
        end

        if (range1_valid_cpu) begin
          if ((normal_word_cpu == range1_start_cpu[15:1]) &&
              normal_ram_mask[1])
            range1_first_match_cpu <= normal_ram_din[15:8] == range1_first_cpu;
          if ((normal_word_cpu == range1_start_cpu[15:1]) &&
              normal_ram_mask[0])
            range1_last_match_cpu <= normal_ram_din[7:0] == range1_last_cpu;
        end
      end

      if (config_valid_cpu && profile_matches_cpu &&
          range0_ready_cpu && range1_ready_cpu)
        scores_ready_cpu <= 1'b1;

      if (scores_ready_cpu && normal_ram_wr &&
          (normal_write_in_range0 || normal_write_in_range1))
        dirty_cpu_r <= 1'b1;

      case (state_cpu)
        STATE_IDLE: begin
          if (config_valid_cpu && profile_matches_cpu &&
              load_data_available_cpu &&
              scores_ready_cpu && !restore_applied_cpu && !ss_hold_cpu) begin
            state_cpu <= STATE_RESTORE_HOLD;
          end else if (capture_request_sync_cpu !=
                       capture_done_toggle_cpu_r) begin
            if (config_valid_cpu && profile_matches_cpu &&
                scores_ready_cpu && !ss_hold_cpu) begin
              capture_valid_cpu_r <= 1'b0;
              state_cpu <= STATE_CAPTURE_HOLD;
            end else if (!ss_hold_cpu) begin
              capture_valid_cpu_r <= 1'b0;
              capture_done_toggle_cpu_r <= capture_request_sync_cpu;
            end
          end
        end

        STATE_RESTORE_HOLD: begin
          if (ss_hold_cpu) begin
            state_cpu <= STATE_IDLE;
          end else if (cpu_idle) begin
            range_select_cpu <= 1'b0;
            range_offset_cpu <= 8'd0;
            buffer_offset_cpu <= 8'd0;
            state_cpu <= STATE_RESTORE_READ;
          end
        end

        STATE_RESTORE_READ:
          state_cpu <= STATE_RESTORE_WRITE;

        STATE_RESTORE_WRITE: begin
          if (range_offset_cpu == current_range_last_offset_cpu) begin
            if (!range_select_cpu && range1_valid_cpu) begin
              range_select_cpu <= 1'b1;
              range_offset_cpu <= 8'd0;
              buffer_offset_cpu <= buffer_offset_cpu + 8'd1;
              state_cpu <= STATE_RESTORE_READ;
            end else begin
              restore_applied_cpu <= 1'b1;
              state_cpu <= STATE_IDLE;
            end
          end else begin
            range_offset_cpu <= range_offset_cpu + 8'd1;
            buffer_offset_cpu <= buffer_offset_cpu + 8'd1;
            state_cpu <= STATE_RESTORE_READ;
          end
        end

        STATE_CAPTURE_HOLD: begin
          if (ss_hold_cpu) begin
            state_cpu <= STATE_IDLE;
          end else if (cpu_idle) begin
            range_select_cpu <= 1'b0;
            range_offset_cpu <= 8'd0;
            buffer_offset_cpu <= 8'd0;
            state_cpu <= STATE_CAPTURE_READ;
          end
        end

        STATE_CAPTURE_READ:
          state_cpu <= STATE_CAPTURE_WRITE;

        STATE_CAPTURE_WRITE: begin
          if (range_offset_cpu == current_range_last_offset_cpu) begin
            if (!range_select_cpu && range1_valid_cpu) begin
              range_select_cpu <= 1'b1;
              range_offset_cpu <= 8'd0;
              buffer_offset_cpu <= buffer_offset_cpu + 8'd1;
              state_cpu <= STATE_CAPTURE_READ;
            end else begin
              dirty_cpu_r <= 1'b0;
              capture_valid_cpu_r <= 1'b1;
              capture_done_toggle_cpu_r <= capture_request_sync_cpu;
              state_cpu <= STATE_IDLE;
            end
          end else begin
            range_offset_cpu <= range_offset_cpu + 8'd1;
            buffer_offset_cpu <= buffer_offset_cpu + 8'd1;
            state_cpu <= STATE_CAPTURE_READ;
          end
        end

        default:
          state_cpu <= STATE_IDLE;
      endcase
    end
  end

  assign cpu_hold = state_cpu != STATE_IDLE;
  assign active_cpu = state_cpu != STATE_IDLE;
  assign ram_owned =
    (state_cpu == STATE_RESTORE_READ) ||
    (state_cpu == STATE_RESTORE_WRITE) ||
    (state_cpu == STATE_CAPTURE_READ) ||
    (state_cpu == STATE_CAPTURE_WRITE);
  assign ram_rd = state_cpu == STATE_CAPTURE_READ;
  assign ram_wr = state_cpu == STATE_RESTORE_WRITE;
  assign ram_addr = current_byte_offset_cpu[15:1];
  assign ram_mask = current_byte_offset_cpu[0] ? 2'b01 : 2'b10;
  assign ram_din = current_byte_offset_cpu[0]
    ? {8'd0, load_buffer_q_cpu}
    : {load_buffer_q_cpu, 8'd0};
  assign ram_target_sprite =
    config_profile_cpu >= 3'd4;
  assign dirty_cpu = dirty_cpu_r;
  assign capture_done_toggle_cpu = capture_done_toggle_cpu_r;
  assign capture_valid_cpu = capture_valid_cpu_r;

  wire load_buffer_rd_cpu = state_cpu == STATE_RESTORE_READ;
  wire save_buffer_wr_cpu = state_cpu == STATE_CAPTURE_WRITE;
  wire [7:0] buffer_address_cpu = buffer_offset_cpu ^ 8'd1;
  wire [7:0] save_buffer_din_cpu = current_byte_offset_cpu[0]
    ? ram_dout[7:0]
    : ram_dout[15:8];

  // Preserve independent directional memories: this topology is the only
  // score-buffer arrangement that has placed in the nearly full device.
  CaveTrueDualPortRam #(
    .ADDR_WIDTH_A (7),
    .ADDR_WIDTH_B (8),
    .DATA_WIDTH_A (16),
    .DATA_WIDTH_B (8),
    .DEPTH_A      (128),
    .DEPTH_B      (256),
    .MASK_ENABLE  (1)
  ) loadBuffer (
    .clock_a (sys_clock),
    .rd_a    (load_buffer_rd_sys),
    .wr_a    (load_buffer_wr_sys),
    .addr_a  (score_word_address_sys),
    .mask_a  (2'b11),
    .din_a   (score_buffer_din_sys),
    .dout_a  (load_buffer_q_sys),
    .clock_b (cpu_clock),
    .rd_b    (load_buffer_rd_cpu),
    .addr_b  (buffer_address_cpu),
    .dout_b  (load_buffer_q_cpu)
  );

  CaveTrueDualPortRam #(
    .ADDR_WIDTH_A (8),
    .ADDR_WIDTH_B (7),
    .DATA_WIDTH_A (8),
    .DATA_WIDTH_B (16),
    .DEPTH_A      (256),
    .DEPTH_B      (128),
    .MASK_ENABLE  (0)
  ) saveBuffer (
    .clock_a (cpu_clock),
    .rd_a    (1'b0),
    .wr_a    (save_buffer_wr_cpu),
    .addr_a  (buffer_address_cpu),
    .mask_a  (1'b1),
    .din_a   (save_buffer_din_cpu),
    .dout_a  (),
    .clock_b (sys_clock),
    .rd_b    (load_buffer_rd_sys),
    .addr_b  (score_word_address_sys),
    .dout_b  (save_buffer_q_sys)
  );

endmodule
