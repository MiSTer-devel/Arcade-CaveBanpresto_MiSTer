`default_nettype none

// The diagnostic mirror deliberately stores only the information needed to
// distinguish a transparent pixel from an opaque pixel and to compare sprite
// priority.  Four 3-bit summaries share one 16-bit word.  The 512x16 memory is
// 8192 bits and therefore fits in one Cyclone V M10K.
module CaveMetmqstrSpriteLineFetchSummaryRam (
  input  wire         write_clock_i,
  input  wire         write_i,
  input  wire [8:0]   write_addr_i,
  input  wire [15:0]  write_data_i,
  input  wire         read_clock_i,
  input  wire [8:0]   read_addr_i,
  output reg  [15:0]  read_data_o
);
  (* ramstyle = "M10K, no_rw_check" *) reg [15:0] memory_q [0:511];

  always @(posedge write_clock_i) begin
    if (write_i)
      memory_q[write_addr_i] <= write_data_i;
  end

  always @(posedge read_clock_i) begin
    read_data_o <= memory_q[read_addr_i];
  end
endmodule

// Temporary, read-only Metamoqester sprite line-fetch discriminator.
//
// The system-clock side observes only source-qualified line-DMA traffic.  It
// latches the logical base, physical page, and intended target Y when a burst
// is accepted, then mirrors each returned 64-bit word before the functional
// FIFO.  The video-clock side reads the mirror in parallel with the functional
// sprite line buffer and classifies the result:
//
//   blue    raw DDR opaque, functional line buffer transparent
//   red     raw DDR transparent, functional line buffer opaque
//   cyan    both opaque, priority differs
//   yellow  summaries agree and are opaque, mixer selects a tile
//   green   summaries agree and are opaque, mixer selects the sprite
//   black   both summaries transparent
//   orange  previously warmed display bank has no matching valid page/Y tag
//   magenta border: at least one transport/tag invariant failed
//
// source_i[2] clears all diagnostic state. source_i[1:0] selects:
//   0: original video (except a magenta invariant-fault border)
//   1: replace completed mirrored lines with a white/black raw-opacity mask
//   2: stable blue/red/cyan/yellow discriminator overlay used for capture
//   3: replace completed mirrored lines with the full stage classification
//
// visual-fiducial-v1: when clear is low, active pixels x=16..31/y=16..31
// carry a fixed 2x2 checker. TL/BR are black; TR/BL encode source 0..3 as
// blue/red/cyan/yellow. The invariant-fault border retains first priority.
//
// This module never feeds gameplay, DMA, DDR, line-buffer, or mixer control.
module CaveMetmqstrSpritePageHardwareDiagnostic (
  input  wire         clock_i,
  input  wire         reset_i,
  input  wire         video_clock_i,
  input  wire         enable_i,
  input  wire [2:0]   source_i,

  input  wire         line_start_i,
  input  wire         line_start_accepted_i,
  input  wire         line_dma_busy_i,
  input  wire [8:0]   line_start_target_y_i,
  input  wire [8:0]   line_live_target_y_i,
  input  wire [31:0]  line_start_page_base_i,
  input  wire [31:0]  read_page_base_i,
  input  wire [1:0]   display_read_page_i,

  input  wire         read_accept_i,
  input  wire [31:0]  read_logical_addr_i,
  input  wire [31:0]  read_physical_addr_i,
  input  wire         raw_valid_i,
  input  wire [63:0]  raw_data_i,
  input  wire         raw_burst_done_i,

  input  wire         functional_write_i,
  input  wire [8:0]   functional_write_addr_i,

  input  wire [8:0]   video_line_addr_i,
  input  wire [8:0]   video_pos_x_i,
  input  wire [8:0]   video_pos_y_i,
  input  wire [8:0]   video_size_x_i,
  input  wire [8:0]   video_size_y_i,
  input  wire [15:0]  functional_pixel_i,
  input  wire         mixer_sprite_wins_i,

  output wire [127:0] probe_o,
  output reg          overlay_valid_o,
  output reg  [23:0]  overlay_rgb_o
);
  localparam [15:0] PROBE_SIGNATURE = 16'hCB55;
  localparam [3:0]  PROBE_VERSION = 4'd2;

  localparam integer FAULT_REJECTED_START       = 0;
  localparam integer FAULT_ACCEPTED_RESIDUAL    = 1;
  localparam integer FAULT_READ_OVERLAP         = 2;
  localparam integer FAULT_ORPHAN_VALID         = 3;
  localparam integer FAULT_ORPHAN_DONE          = 4;
  localparam integer FAULT_BURST_LENGTH         = 5;
  localparam integer FAULT_LOGICAL_BASE         = 6;
  localparam integer FAULT_DUPLICATE_BASE       = 7;
  localparam integer FAULT_PHYSICAL_ADDRESS     = 8;
  localparam integer FAULT_TARGET_DRIFT         = 9;
  localparam integer FAULT_WRITE_BANK_DRIFT     = 10;
  localparam integer FAULT_LINE_REQUEST_COUNT   = 11;
  localparam integer FAULT_LINE_RAW_COUNT       = 12;
  localparam integer FAULT_LINE_WRITE_COUNT     = 13;
  localparam integer FAULT_LINE_PROTOCOL        = 14;
  localparam integer FAULT_COUNTER_SATURATION   = 15;

  function [15:0] pack_summary;
    input [63:0] data;
    begin
      pack_summary = 16'd0;
      pack_summary[2:0] = {data[15:14], |data[7:0]};
      pack_summary[6:4] = {data[31:30], |data[23:16]};
      pack_summary[10:8] = {data[47:46], |data[39:32]};
      pack_summary[14:12] = {data[63:62], |data[55:48]};
    end
  endfunction

  wire clear_w = source_i[2];
  wire line_start_accepted_w = line_start_i && line_start_accepted_i;
  wire line_start_rejected_w = line_start_i && !line_start_accepted_i;

  reg         armed_q;
  reg         line_active_q;
  reg         line_seen_busy_q;
  reg         line_publishable_q;
  reg [8:0]   line_target_y_q;
  reg [31:0]  line_page_base_q;
  reg [1:0]   line_page_q;
  reg [3:0]   line_request_count_q;
  reg [7:0]   line_base_seen_q;
  reg [7:0]   line_raw_word_count_q;
  reg [7:0]   line_functional_write_count_q;

  reg         burst_active_q;
  reg [6:0]   burst_base_word_q;
  reg [1:0]   burst_target_bank_q;
  reg [4:0]   burst_beat_count_q;

  reg [15:0]  fault_sticky_q;
  reg [15:0]  accepted_line_count_q;
  reg [15:0]  rejected_start_count_q;
  reg [15:0]  accepted_residual_count_q;
  reg [15:0]  malformed_burst_count_q;
  reg [15:0]  accepted_read_count_q;
  reg [7:0]   completed_line_count_q;
  reg [7:0]   last_completed_raw_count_q;
  reg [7:0]   last_completed_write_count_q;
  reg [7:0]   line_generation_q;

  reg [3:0]   bank_valid_q;
  reg [3:0]   bank_ever_valid_q;
  reg [8:0]   bank_y_q [0:3];
  reg [1:0]   bank_page_q [0:3];
  reg [7:0]   bank_generation_q [0:3];

  wire [5:0] burst_beat_count_after_w =
    {1'b0, burst_beat_count_q} +
    ((raw_valid_i && burst_active_q) ? 6'd1 : 6'd0);
  wire [31:0] expected_physical_addr_w =
    line_page_base_q +
    {13'h0000, line_target_y_q, 10'h000} +
    read_logical_addr_i;
  wire [2:0] accepted_base_index_w = read_logical_addr_i[9:7];
  wire [6:0] accepted_base_word_w = read_logical_addr_i[9:3];
  wire line_complete_w =
    line_active_q && line_seen_busy_q && !line_dma_busy_i;
  wire line_complete_good_w =
    line_publishable_q &&
    (line_request_count_q == 4'd8) &&
    (line_base_seen_q == 8'hff) &&
    (line_raw_word_count_q == 8'd128) &&
    (line_functional_write_count_q == 8'd128) &&
    !burst_active_q &&
    (line_live_target_y_i == line_target_y_q);
  wire accepted_residual_w =
    line_start_accepted_w && line_dma_busy_i;
  wire malformed_burst_event_w =
    (read_accept_i && (!line_active_q || burst_active_q)) ||
    (read_accept_i &&
     ((read_logical_addr_i[31:10] != 22'd0) ||
      (read_logical_addr_i[6:0] != 7'd0) ||
      line_base_seen_q[accepted_base_index_w])) ||
    (raw_valid_i && !burst_active_q) ||
    (raw_valid_i && burst_active_q &&
     (burst_beat_count_q >= 5'd16)) ||
    (raw_burst_done_i && !burst_active_q) ||
    (raw_burst_done_i && burst_active_q &&
     (burst_beat_count_after_w != 6'd16));

  wire mirror_write_w =
    enable_i && armed_q && burst_active_q && raw_valid_i &&
    (burst_beat_count_q < 5'd16);
  wire [8:0] mirror_write_addr_w = {
    burst_target_bank_q,
    burst_base_word_q + burst_beat_count_q[3:0]
  };
  wire [15:0] mirror_write_data_w = pack_summary(raw_data_i);
  wire observer_idle_boundary_w =
    !line_dma_busy_i &&
    !line_start_i &&
    !line_start_accepted_i &&
    !read_accept_i &&
    !raw_valid_i &&
    !raw_burst_done_i &&
    !functional_write_i;

  integer bank_index;
  always @(posedge clock_i) begin
    if (reset_i || !enable_i || clear_w) begin
      armed_q <= 1'b0;
      line_active_q <= 1'b0;
      line_seen_busy_q <= 1'b0;
      line_publishable_q <= 1'b0;
      line_target_y_q <= 9'd0;
      line_page_base_q <= 32'd0;
      line_page_q <= 2'd0;
      line_request_count_q <= 4'd0;
      line_base_seen_q <= 8'd0;
      line_raw_word_count_q <= 8'd0;
      line_functional_write_count_q <= 8'd0;
      burst_active_q <= 1'b0;
      burst_base_word_q <= 7'd0;
      burst_target_bank_q <= 2'd0;
      burst_beat_count_q <= 5'd0;
      fault_sticky_q <= 16'd0;
      accepted_line_count_q <= 16'd0;
      rejected_start_count_q <= 16'd0;
      accepted_residual_count_q <= 16'd0;
      malformed_burst_count_q <= 16'd0;
      accepted_read_count_q <= 16'd0;
      completed_line_count_q <= 8'd0;
      last_completed_raw_count_q <= 8'd0;
      last_completed_write_count_q <= 8'd0;
      line_generation_q <= 8'd0;
      bank_valid_q <= 4'd0;
      bank_ever_valid_q <= 4'd0;
      for (bank_index = 0; bank_index < 4; bank_index = bank_index + 1) begin
        bank_y_q[bank_index] <= 9'd0;
        bank_page_q[bank_index] <= 2'd0;
        bank_generation_q[bank_index] <= 8'd0;
      end
    end else if (!armed_q) begin
      // Clear may be released while the functional DMA is still draining.
      // Stay entirely inert until a quiet boundary, then observe the next
      // accepted line rather than misclassifying residual traffic as orphaned.
      if (observer_idle_boundary_w)
        armed_q <= 1'b1;
    end else begin
      if (line_start_rejected_w) begin
        rejected_start_count_q <= rejected_start_count_q + 16'd1;
        fault_sticky_q[FAULT_REJECTED_START] <= 1'b1;
      end

      if ((line_start_accepted_i && !line_start_i) ||
          (line_start_rejected_w && !line_dma_busy_i)) begin
        fault_sticky_q[FAULT_LINE_PROTOCOL] <= 1'b1;
        if (line_active_q)
          line_publishable_q <= 1'b0;
      end

      if (accepted_residual_w) begin
        accepted_residual_count_q <= accepted_residual_count_q + 16'd1;
      end

      if (malformed_burst_event_w) begin
        malformed_burst_count_q <= malformed_burst_count_q + 16'd1;
      end

      if (line_complete_w) begin
        line_active_q <= 1'b0;
        line_seen_busy_q <= 1'b0;
        line_publishable_q <= 1'b0;
        bank_valid_q[line_target_y_q[1:0]] <= line_complete_good_w;
        if (line_complete_good_w)
          bank_ever_valid_q[line_target_y_q[1:0]] <= 1'b1;
        bank_y_q[line_target_y_q[1:0]] <= line_target_y_q;
        bank_page_q[line_target_y_q[1:0]] <= line_page_q;
        bank_generation_q[line_target_y_q[1:0]] <= line_generation_q;
        last_completed_raw_count_q <= line_raw_word_count_q;
        last_completed_write_count_q <= line_functional_write_count_q;
        line_generation_q <= line_generation_q + 8'd1;
        completed_line_count_q <= completed_line_count_q + 8'd1;
        if ((line_request_count_q != 4'd8) ||
            (line_base_seen_q != 8'hff))
          fault_sticky_q[FAULT_LINE_REQUEST_COUNT] <= 1'b1;
        if (line_raw_word_count_q != 8'd128)
          fault_sticky_q[FAULT_LINE_RAW_COUNT] <= 1'b1;
        if (line_functional_write_count_q != 8'd128)
          fault_sticky_q[FAULT_LINE_WRITE_COUNT] <= 1'b1;
        if (burst_active_q)
          fault_sticky_q[FAULT_LINE_PROTOCOL] <= 1'b1;
      end

      if (line_start_accepted_w) begin
        if (accepted_residual_w) begin
          fault_sticky_q[FAULT_ACCEPTED_RESIDUAL] <= 1'b1;
        end
        line_active_q <= 1'b1;
        line_seen_busy_q <= 1'b0;
        line_publishable_q <= !accepted_residual_w;
        line_target_y_q <= line_start_target_y_i;
        line_page_base_q <= line_start_page_base_i;
        line_page_q <= line_start_page_base_i[20:19];
        line_request_count_q <= 4'd0;
        line_base_seen_q <= 8'd0;
        line_raw_word_count_q <= 8'd0;
        line_functional_write_count_q <= 8'd0;
        bank_valid_q[line_start_target_y_i[1:0]] <= 1'b0;
        accepted_line_count_q <= accepted_line_count_q + 16'd1;
      end else if (line_active_q && line_dma_busy_i) begin
        line_seen_busy_q <= 1'b1;
      end

      if (line_active_q && !line_start_accepted_w &&
          (line_live_target_y_i != line_target_y_q)) begin
        fault_sticky_q[FAULT_TARGET_DRIFT] <= 1'b1;
        line_publishable_q <= 1'b0;
      end

      if (read_accept_i) begin
        accepted_read_count_q <= accepted_read_count_q + 16'd1;
        if (!line_active_q || burst_active_q)
          fault_sticky_q[FAULT_READ_OVERLAP] <= 1'b1;
        if ((read_logical_addr_i[31:10] != 22'd0) ||
            (read_logical_addr_i[6:0] != 7'd0))
          fault_sticky_q[FAULT_LOGICAL_BASE] <= 1'b1;
        if (line_base_seen_q[accepted_base_index_w])
          fault_sticky_q[FAULT_DUPLICATE_BASE] <= 1'b1;
        if ((read_page_base_i != line_page_base_q) ||
            (read_physical_addr_i != expected_physical_addr_w))
          fault_sticky_q[FAULT_PHYSICAL_ADDRESS] <= 1'b1;
        if (line_live_target_y_i != line_target_y_q)
          fault_sticky_q[FAULT_TARGET_DRIFT] <= 1'b1;
        if (!line_active_q || burst_active_q ||
            (read_logical_addr_i[31:10] != 22'd0) ||
            (read_logical_addr_i[6:0] != 7'd0) ||
            line_base_seen_q[accepted_base_index_w] ||
            (read_page_base_i != line_page_base_q) ||
            (read_physical_addr_i != expected_physical_addr_w) ||
            (line_live_target_y_i != line_target_y_q)) begin
          line_publishable_q <= 1'b0;
        end
        burst_active_q <= 1'b1;
        burst_base_word_q <= accepted_base_word_w;
        burst_target_bank_q <= line_target_y_q[1:0];
        burst_beat_count_q <= 5'd0;
        if (line_request_count_q != 4'hf)
          line_request_count_q <= line_request_count_q + 4'd1;
        else
          fault_sticky_q[FAULT_COUNTER_SATURATION] <= 1'b1;
        line_base_seen_q[accepted_base_index_w] <= 1'b1;
      end

      if (raw_valid_i) begin
        if (!burst_active_q) begin
          fault_sticky_q[FAULT_ORPHAN_VALID] <= 1'b1;
          if (line_active_q)
            line_publishable_q <= 1'b0;
        end else begin
          if (burst_beat_count_q < 5'd16)
            burst_beat_count_q <= burst_beat_count_q + 5'd1;
          else
            fault_sticky_q[FAULT_BURST_LENGTH] <= 1'b1;
          if (burst_beat_count_q >= 5'd16)
            line_publishable_q <= 1'b0;
          if (line_raw_word_count_q != 8'hff)
            line_raw_word_count_q <= line_raw_word_count_q + 8'd1;
          else
            fault_sticky_q[FAULT_COUNTER_SATURATION] <= 1'b1;
        end
      end

      if (raw_burst_done_i) begin
        if (!burst_active_q) begin
          fault_sticky_q[FAULT_ORPHAN_DONE] <= 1'b1;
          if (line_active_q)
            line_publishable_q <= 1'b0;
        end else begin
          if (burst_beat_count_after_w != 6'd16) begin
            fault_sticky_q[FAULT_BURST_LENGTH] <= 1'b1;
            line_publishable_q <= 1'b0;
          end
          burst_active_q <= 1'b0;
          burst_beat_count_q <= 5'd0;
        end
      end

      if (functional_write_i) begin
        if (!line_active_q) begin
          fault_sticky_q[FAULT_LINE_PROTOCOL] <= 1'b1;
        end else begin
          if (functional_write_addr_i[8:7] != line_target_y_q[1:0]) begin
            fault_sticky_q[FAULT_WRITE_BANK_DRIFT] <= 1'b1;
            line_publishable_q <= 1'b0;
          end
          if (line_functional_write_count_q != 8'hff)
            line_functional_write_count_q <=
              line_functional_write_count_q + 8'd1;
          else
            fault_sticky_q[FAULT_COUNTER_SATURATION] <= 1'b1;
        end
      end
    end
  end

  wire [8:0] mirror_read_addr_w = {
    video_pos_y_i[1:0],
    video_line_addr_i[8:2]
  };
  wire [15:0] mirror_read_data_w;

  CaveMetmqstrSpriteLineFetchSummaryRam summaryRam (
    .write_clock_i (clock_i),
    .write_i       (mirror_write_w),
    .write_addr_i  (mirror_write_addr_w),
    .write_data_i  (mirror_write_data_w),
    .read_clock_i  (video_clock_i),
    .read_addr_i   (mirror_read_addr_w),
    .read_data_o   (mirror_read_data_w)
  );

  wire [19:0] bank_tag_0_w = {
    bank_valid_q[0], bank_page_q[0], bank_y_q[0], bank_generation_q[0]
  };
  wire [19:0] bank_tag_1_w = {
    bank_valid_q[1], bank_page_q[1], bank_y_q[1], bank_generation_q[1]
  };
  wire [19:0] bank_tag_2_w = {
    bank_valid_q[2], bank_page_q[2], bank_y_q[2], bank_generation_q[2]
  };
  wire [19:0] bank_tag_3_w = {
    bank_valid_q[3], bank_page_q[3], bank_y_q[3], bank_generation_q[3]
  };
  wire [79:0] bank_tags_w = {
    bank_tag_3_w, bank_tag_2_w, bank_tag_1_w, bank_tag_0_w
  };

  // The video domain needs the generation only as a publish-change witness,
  // not as the eight-bit JTAG epoch.  A bank can publish at most once every
  // four scanlines, so its low-bit toggle cannot wrap between the two video
  // synchronizer samples.  Keep the full epochs in bank_tags_w/probe_o while
  // avoiding 56 redundant video-domain registers.
  wire [12:0] bank_video_tag_0_w = {
    bank_valid_q[0], bank_page_q[0], bank_y_q[0], bank_generation_q[0][0]
  };
  wire [12:0] bank_video_tag_1_w = {
    bank_valid_q[1], bank_page_q[1], bank_y_q[1], bank_generation_q[1][0]
  };
  wire [12:0] bank_video_tag_2_w = {
    bank_valid_q[2], bank_page_q[2], bank_y_q[2], bank_generation_q[2][0]
  };
  wire [12:0] bank_video_tag_3_w = {
    bank_valid_q[3], bank_page_q[3], bank_y_q[3], bank_generation_q[3][0]
  };
  wire [51:0] bank_video_tags_w = {
    bank_video_tag_3_w, bank_video_tag_2_w,
    bank_video_tag_1_w, bank_video_tag_0_w
  };

  reg [51:0] bank_tags_video_1_q;
  reg [51:0] bank_tags_video_2_q;
  reg [3:0]  bank_ever_video_1_q;
  reg [3:0]  bank_ever_video_2_q;
  reg [15:0] fault_video_1_q;
  reg [15:0] fault_video_2_q;
  reg [3:0]  control_video_1_q;
  reg [3:0]  control_video_2_q;
  reg [1:0]  display_page_video_1_q;
  reg [1:0]  display_page_video_2_q;
  reg [1:0]  video_line_x_low_q;
  reg [8:0]  video_pos_x_q;
  reg [8:0]  video_pos_y_q;
  reg [8:0]  video_size_x_q;
  reg [8:0]  video_size_y_q;
  reg [6:0]  video_class_sticky_q;

  reg [12:0] displayed_tag_stage1_r;
  reg [12:0] displayed_tag_r;
  always @* begin
    case (video_pos_y_q[1:0])
      2'd0: begin
        displayed_tag_stage1_r = bank_tags_video_1_q[12:0];
        displayed_tag_r = bank_tags_video_2_q[12:0];
      end
      2'd1: begin
        displayed_tag_stage1_r = bank_tags_video_1_q[25:13];
        displayed_tag_r = bank_tags_video_2_q[25:13];
      end
      2'd2: begin
        displayed_tag_stage1_r = bank_tags_video_1_q[38:26];
        displayed_tag_r = bank_tags_video_2_q[38:26];
      end
      default: begin
        displayed_tag_stage1_r = bank_tags_video_1_q[51:39];
        displayed_tag_r = bank_tags_video_2_q[51:39];
      end
    endcase
  end

  reg [2:0] raw_summary_r;
  always @* begin
    case (video_line_x_low_q)
      2'd0: raw_summary_r = mirror_read_data_w[2:0];
      2'd1: raw_summary_r = mirror_read_data_w[6:4];
      2'd2: raw_summary_r = mirror_read_data_w[10:8];
      default: raw_summary_r = mirror_read_data_w[14:12];
    endcase
  end

  wire [2:0] functional_summary_w = {
    functional_pixel_i[15:14], |functional_pixel_i[7:0]
  };
  wire displayed_tag_valid_w = displayed_tag_r[12];
  wire [1:0] displayed_tag_page_w = displayed_tag_r[11:10];
  wire [8:0] displayed_tag_y_w = displayed_tag_r[9:1];
  wire displayed_tag_stable_w =
    displayed_tag_stage1_r == displayed_tag_r;
  wire display_page_stable_w =
    display_page_video_1_q == display_page_video_2_q;
  wire displayed_tag_match_w =
    displayed_tag_stable_w &&
    display_page_stable_w &&
    displayed_tag_stage1_r[12] &&
    displayed_tag_valid_w &&
    (displayed_tag_page_w == display_page_video_2_q) &&
    (displayed_tag_y_w == video_pos_y_q);
  wire all_banks_warm_w =
    (bank_ever_video_1_q == bank_ever_video_2_q) &&
    (&bank_ever_video_2_q);
  wire displayed_tag_mismatch_w =
    all_banks_warm_w && !displayed_tag_match_w;
  wire raw_opaque_w = raw_summary_r[0];
  wire functional_opaque_w = functional_summary_w[0];
  wire class_blue_w =
    displayed_tag_match_w && raw_opaque_w && !functional_opaque_w;
  wire class_red_w =
    displayed_tag_match_w && !raw_opaque_w && functional_opaque_w;
  wire class_cyan_w =
    displayed_tag_match_w && raw_opaque_w && functional_opaque_w &&
    (raw_summary_r[2:1] != functional_summary_w[2:1]);
  wire class_yellow_w =
    displayed_tag_match_w && raw_opaque_w && functional_opaque_w &&
    (raw_summary_r == functional_summary_w) && !mixer_sprite_wins_i;
  wire class_green_w =
    displayed_tag_match_w && raw_opaque_w && functional_opaque_w &&
    (raw_summary_r == functional_summary_w) && mixer_sprite_wins_i;

  wire video_visible_w =
    (video_pos_x_q < video_size_x_q) &&
    (video_pos_y_q < video_size_y_q);
  wire fault_border_w = video_visible_w && (|fault_video_2_q) &&
    ((video_pos_x_q < 9'd4) || (video_pos_y_q < 9'd4) ||
     ({1'b0, video_pos_x_q} + 10'd4 >= {1'b0, video_size_x_q}) ||
     ({1'b0, video_pos_y_q} + 10'd4 >= {1'b0, video_size_y_q}));
  wire source_fiducial_region_w =
    (~|video_pos_x_q[8:5]) && video_pos_x_q[4] &&
    (~|video_pos_y_q[8:5]) && video_pos_y_q[4];
  wire source_fiducial_color_phase_w =
    video_pos_x_q[3] ^ video_pos_y_q[3];
  wire [23:0] source_fiducial_rgb_w = {
    {8{control_video_2_q[0]}},
    {8{control_video_2_q[1]}},
    {8{~control_video_2_q[0]}}
  };

  always @(posedge video_clock_i) begin
    bank_tags_video_1_q <= bank_video_tags_w;
    bank_tags_video_2_q <= bank_tags_video_1_q;
    bank_ever_video_1_q <= bank_ever_valid_q;
    bank_ever_video_2_q <= bank_ever_video_1_q;
    fault_video_1_q <= fault_sticky_q;
    fault_video_2_q <= fault_video_1_q;
    control_video_1_q <= {enable_i, source_i};
    control_video_2_q <= control_video_1_q;
    display_page_video_1_q <= display_read_page_i;
    display_page_video_2_q <= display_page_video_1_q;
    video_line_x_low_q <= video_line_addr_i[1:0];
    video_pos_x_q <= video_pos_x_i;
    video_pos_y_q <= video_pos_y_i;
    video_size_x_q <= video_size_x_i;
    video_size_y_q <= video_size_y_i;

    if (reset_i || !control_video_2_q[3] || control_video_2_q[2]) begin
      video_class_sticky_q <= 7'd0;
    end else if (video_visible_w) begin
      if (class_blue_w)
        video_class_sticky_q[0] <= 1'b1;
      if (class_red_w)
        video_class_sticky_q[1] <= 1'b1;
      if (class_cyan_w)
        video_class_sticky_q[2] <= 1'b1;
      if (class_yellow_w)
        video_class_sticky_q[3] <= 1'b1;
      if (displayed_tag_mismatch_w)
        video_class_sticky_q[4] <= 1'b1;
      if (displayed_tag_match_w)
        video_class_sticky_q[5] <= 1'b1;
      if (class_green_w)
        video_class_sticky_q[6] <= 1'b1;
    end
  end

  always @* begin
    overlay_valid_o = 1'b0;
    overlay_rgb_o = 24'h000000;

    if (control_video_2_q[3] && fault_border_w) begin
      overlay_valid_o = 1'b1;
      overlay_rgb_o = 24'hff00ff;
    end else if (control_video_2_q[3] && !control_video_2_q[2] &&
                 video_visible_w && source_fiducial_region_w) begin
      overlay_valid_o = 1'b1;
      overlay_rgb_o = source_fiducial_color_phase_w
        ? source_fiducial_rgb_w : 24'h000000;
    end else if (control_video_2_q[3] && video_visible_w) begin
      if (control_video_2_q[1] && displayed_tag_mismatch_w) begin
        overlay_valid_o = 1'b1;
        overlay_rgb_o = 24'hff8000;
      end else case (control_video_2_q[1:0])
        2'd1: begin
          if (displayed_tag_match_w) begin
            overlay_valid_o = 1'b1;
            overlay_rgb_o = raw_opaque_w ? 24'hffffff : 24'h000000;
          end
        end
        2'd2: begin
          if (class_blue_w) begin
            overlay_valid_o = 1'b1;
            overlay_rgb_o = 24'h0000ff;
          end else if (class_red_w) begin
            overlay_valid_o = 1'b1;
            overlay_rgb_o = 24'hff0000;
          end else if (class_cyan_w) begin
            overlay_valid_o = 1'b1;
            overlay_rgb_o = 24'h00ffff;
          end else if (class_yellow_w) begin
            overlay_valid_o = 1'b1;
            overlay_rgb_o = 24'hffff00;
          end
        end
        2'd3: begin
          if (displayed_tag_match_w) begin
            overlay_valid_o = 1'b1;
            if (class_blue_w)
              overlay_rgb_o = 24'h0000ff;
            else if (class_red_w)
              overlay_rgb_o = 24'hff0000;
            else if (class_cyan_w)
              overlay_rgb_o = 24'h00ffff;
            else if (class_yellow_w)
              overlay_rgb_o = 24'hffff00;
            else if (class_green_w)
              overlay_rgb_o = 24'h00ff00;
            else
              overlay_rgb_o = 24'h000000;
          end
        end
        default: begin
        end
      endcase
    end
  end

  reg [8:0] video_y_system_1_q;
  reg [8:0] video_y_system_2_q;
  reg [6:0] video_status_system_1_q;
  reg [6:0] video_status_system_2_q;
  wire [6:0] video_status_w = video_class_sticky_q;

  always @(posedge clock_i) begin
    if (reset_i || !enable_i || clear_w) begin
      video_y_system_1_q <= 9'd0;
      video_y_system_2_q <= 9'd0;
      video_status_system_1_q <= 7'd0;
      video_status_system_2_q <= 7'd0;
    end else begin
      video_y_system_1_q <= video_pos_y_q;
      video_y_system_2_q <= video_y_system_1_q;
      video_status_system_1_q <= video_status_w;
      video_status_system_2_q <= video_status_system_1_q;
    end
  end

  reg [19:0] displayed_tag_system_r;
  always @* begin
    case (video_y_system_2_q[1:0])
      2'd0: displayed_tag_system_r = bank_tag_0_w;
      2'd1: displayed_tag_system_r = bank_tag_1_w;
      2'd2: displayed_tag_system_r = bank_tag_2_w;
      default: displayed_tag_system_r = bank_tag_3_w;
    endcase
  end

  reg [127:0] page_zero_r;
  reg [127:0] page_one_r;
  reg [127:0] page_two_r;
  reg [127:0] page_three_r;
  always @* begin
    page_zero_r = 128'd0;
    page_one_r = 128'd0;
    page_two_r = 128'd0;
    page_three_r = 128'd0;

    page_zero_r[127:112] = PROBE_SIGNATURE;
    page_zero_r[111:108] = PROBE_VERSION;
    page_zero_r[107:106] = source_i[1:0];
    page_zero_r[105] = source_i[2];
    page_zero_r[104] = enable_i && armed_q;
    page_zero_r[103] = line_active_q;
    page_zero_r[102] = burst_active_q;
    page_zero_r[101] = line_dma_busy_i;
    page_zero_r[100:85] = fault_sticky_q;
    page_zero_r[84:76] = line_target_y_q;
    page_zero_r[75:74] = line_page_q;
    page_zero_r[73:67] = burst_base_word_q;
    page_zero_r[66:62] = burst_beat_count_q;
    page_zero_r[61:58] = line_request_count_q;
    page_zero_r[57:50] = line_raw_word_count_q;
    page_zero_r[49:42] = line_functional_write_count_q;
    page_zero_r[41:33] = line_live_target_y_i;
    page_zero_r[32:24] = video_y_system_2_q;
    page_zero_r[23:4] = displayed_tag_system_r;
    page_zero_r[3:0] = video_status_system_2_q[3:0];

    page_one_r[127:112] = PROBE_SIGNATURE;
    page_one_r[111:108] = PROBE_VERSION;
    page_one_r[107:106] = source_i[1:0];
    page_one_r[105] = source_i[2];
    page_one_r[104] = enable_i && armed_q;
    page_one_r[103:88] = accepted_line_count_q;
    page_one_r[87:72] = rejected_start_count_q;
    page_one_r[71:56] = accepted_residual_count_q;
    page_one_r[55:40] = malformed_burst_count_q;
    page_one_r[39:24] = accepted_read_count_q;
    page_one_r[23:16] = completed_line_count_q;
    page_one_r[15:8] = last_completed_raw_count_q;
    page_one_r[7:0] = last_completed_write_count_q;

    page_two_r[127:112] = PROBE_SIGNATURE;
    page_two_r[111:108] = PROBE_VERSION;
    page_two_r[107:106] = source_i[1:0];
    page_two_r[105] = source_i[2];
    page_two_r[104] = enable_i && armed_q;
    page_two_r[103:84] = bank_tag_3_w;
    page_two_r[83:64] = bank_tag_2_w;
    page_two_r[63:44] = bank_tag_1_w;
    page_two_r[43:24] = bank_tag_0_w;
    page_two_r[23:16] = line_generation_q;
    page_two_r[15:0] = fault_sticky_q;

    page_three_r[127:112] = PROBE_SIGNATURE;
    page_three_r[111:108] = PROBE_VERSION;
    page_three_r[107:106] = source_i[1:0];
    page_three_r[105] = source_i[2];
    page_three_r[104] = enable_i && armed_q;
    page_three_r[103:97] = video_status_system_2_q;
    page_three_r[96] = &bank_ever_valid_q;
    page_three_r[95:92] = bank_ever_valid_q;
    page_three_r[91:72] = displayed_tag_system_r;
    page_three_r[71:63] = video_y_system_2_q;
    page_three_r[62:47] = fault_sticky_q;
    page_three_r[46:31] = accepted_line_count_q;
    page_three_r[30:15] = rejected_start_count_q;
    page_three_r[14:7] = line_generation_q;
    page_three_r[6:0] = 7'd0;
  end

  assign probe_o =
    (source_i[1:0] == 2'd1) ? page_one_r :
    (source_i[1:0] == 2'd2) ? page_two_r :
    (source_i[1:0] == 2'd3) ? page_three_r : page_zero_r;
endmodule

`default_nettype wire
