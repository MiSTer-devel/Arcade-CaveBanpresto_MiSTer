//============================================================================
//  Copyright (C) 2026 Martin Donlon
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//============================================================================

// Cave-local adaptation of Wickerwaka's horizontal scaler from
// MiSTer-devel/Arcade-IGSPGM_MiSTer rtl/video_hscale.sv at commit
// cb193301d9ea8ef3c284d8e0c7d2893c46355642. The scaling algorithm is
// unchanged; only the module name, deterministic startup values, and the
// line-buffer wrapper differ.

// Horizontal scaler for consumer CRT width correction.
//
//   * line total       - clocks between hblank rising edges
//   * hblank width     - clocks hb_in stays high
//   * active width     - ce_pix_in pulses while hb_in is low
//   * hsync start/width- hs_in leading/trailing edges
//   * pixel period     - clocks per ce_pix_in pulse
module CaveVideoHScale(
  input               clk,

  input               enable,
  input signed  [4:0] scale,
  input signed  [4:0] offset,

  output reg          en_lat = 1'b0,

  input               ce_pix_in,
  input         [7:0] r_in,
  input         [7:0] g_in,
  input         [7:0] b_in,
  input               hs_in,
  input               hb_in,
  input               vb_in,
  input               vs_in,

  output reg    [7:0] r_out = 8'd0,
  output reg    [7:0] g_out = 8'd0,
  output reg    [7:0] b_out = 8'd0,
  output reg          hs_out = 1'b0,
  output reg          hb_out = 1'b1,
  output reg          vs_out = 1'b0,
  output reg          vb_out = 1'b1
);

  localparam [11:0] RD_LEAD = 12'd16;

  // Start in blank so an already-active reset blank does not look like a
  // complete measured line or frame.
  reg hb_in_d = 1'b1;
  reg vb_in_d = 1'b1;
  reg hs_in_d = 1'b0;
  wire line_start = hb_in & ~hb_in_d;

  reg [11:0] line_clk = 12'd0;

  reg [11:0] m_total = 12'd0;
  reg [11:0] m_hbw   = 12'd0;
  reg [9:0]  m_actpx = 10'd0;
  reg [11:0] m_hss   = 12'd0;
  reg [11:0] m_hsw   = 12'd0;
  reg [3:0]  m_clkpp = 4'd0;

  reg [11:0] meas_lc       = 12'd0;
  reg [9:0]  meas_apx      = 10'd0;
  reg [11:0] meas_hss      = 12'd0;
  reg [3:0]  meas_cpp      = 4'd0;
  reg        meas_cpp_seen = 1'b0;

  // Geometry changes only at a frame boundary.
  reg [7:0]  step       = 8'd0;
  reg [12:0] active_len = 13'd0;
  reg [11:0] rd_start   = 12'd0;
  reg [11:0] hs_start   = 12'd0;
  reg [11:0] hs_end     = 12'd0;
  reg [11:0] blank_lc   = 12'd0;
  reg [11:0] f_total    = 12'd0;

  wire signed [5:0] k = {scale[4], scale};
  wire [5:0] abs_k = scale[4] ? -k[5:0] : k[5:0];
  wire signed [9:0] step_s = $signed({1'b0, m_clkpp, 4'b0})
                            + $signed({{4{k[5]}}, k});
  wire [7:0] step_w = step_s[7:0];
  wire [17:0] al_prod = m_actpx * step_w;
  wire [15:0] sc_prod = m_actpx * {10'b0, abs_k};
  wire signed [12:0] hs_pos = $signed({1'b0, m_hss})
                             + $signed({2'b0, sc_prod[15:5]})
                             + $signed({1'b0, m_clkpp}) * $signed(offset);

  always_ff @(posedge clk) begin
    vb_in_d <= vb_in;
    if (vb_in & ~vb_in_d) begin
      en_lat    <= enable;
      f_total   <= m_total;
      step      <= step_w;
      active_len <= al_prod[16:4];
      rd_start  <= m_hbw + RD_LEAD + (scale[4] ? sc_prod[15:4] : 12'd0);
      hs_start  <= hs_pos[11:0];
      hs_end    <= hs_pos[11:0] + m_hsw;
      blank_lc  <= RD_LEAD + (scale[4] ? 12'd0 : sc_prod[15:4]);
    end
  end

  reg vbl_line = 1'b1;
  reg vsl_line = 1'b0;

  reg [8:0] wr_idx = 9'd0;
  wire wr_en = ce_pix_in & ~hb_in;

  reg [12:0] active_cnt = 13'd0;
  reg [8:0] rd_idx = 9'd0;
  reg [7:0] acc = 8'd0;
  reg reading_cur_line = 1'b0;

  wire rd_active = |active_cnt;
  wire rd_load = (line_clk == rd_start) & ~vbl_line;

  wire [23:0] rd_q;

  CaveTrueDualPortRam #(
    .ADDR_WIDTH_A (7),
    .ADDR_WIDTH_B (7),
    .DATA_WIDTH_A (24),
    .DATA_WIDTH_B (24),
    .DEPTH_A      (128),
    .DEPTH_B      (128),
    .MASK_ENABLE  (0)
  ) lineBuffer (
    .clock_a (clk),
    .rd_a    (1'b0),
    .wr_a    (wr_en),
    .addr_a  (wr_idx[6:0]),
    .mask_a  (3'b111),
    .din_a   ({r_in, g_in, b_in}),
    .dout_a  (),
    .clock_b (clk),
    .rd_b    (1'b1),
    .addr_b  (rd_idx[6:0]),
    .dout_b  (rd_q)
  );

  reg rd_active_d1 = 1'b0;
  reg hs_d1 = 1'b0;
  reg hs_d2 = 1'b0;

  reg debug_underrun = 1'b0 /* verilator public_flat */;
  reg debug_overflow = 1'b0 /* verilator public_flat */;

  always_ff @(posedge clk) begin
    hb_in_d <= hb_in;
    hs_in_d <= hs_in;

    if (line_start) begin
      meas_lc <= 12'd0;
      m_total <= meas_lc + 12'd1;
      m_actpx <= meas_apx;
      meas_apx <= 10'd0;
    end else begin
      meas_lc <= meas_lc + 12'd1;
      if (wr_en) meas_apx <= meas_apx + 10'd1;
    end

    if (hb_in_d & ~hb_in) m_hbw <= meas_lc;
    if (hs_in & ~hs_in_d) begin
      m_hss <= meas_lc;
      meas_hss <= meas_lc;
    end
    if (~hs_in & hs_in_d) m_hsw <= meas_lc - meas_hss;

    if (ce_pix_in) begin
      if (meas_cpp_seen) m_clkpp <= meas_cpp + 4'd1;
      meas_cpp <= 4'd0;
      meas_cpp_seen <= 1'b1;
    end else begin
      meas_cpp <= meas_cpp + 4'd1;
    end

    if (line_start) begin
      line_clk <= 12'd0;
      wr_idx <= 9'd0;
      reading_cur_line <= 1'b0;
      vbl_line <= vb_in;
      vsl_line <= vs_in;
    end else begin
      line_clk <= (line_clk >= f_total - 12'd1) ? 12'd0 : line_clk + 12'd1;
    end

    if (line_clk == blank_lc) begin
      vb_out <= vbl_line;
      vs_out <= vsl_line;
    end

    if (wr_en) wr_idx <= wr_idx + 9'd1;

    if (rd_load) begin
      active_cnt <= active_len;
      rd_idx <= 9'd0;
      acc <= 8'd0;
      reading_cur_line <= 1'b1;
    end else if (rd_active) begin
      active_cnt <= active_cnt - 13'd1;
      if (acc + 8'd16 >= step) begin
        acc <= acc + 8'd16 - step;
        rd_idx <= rd_idx + 9'd1;
      end else begin
        acc <= acc + 8'd16;
      end
    end

    if (reading_cur_line & rd_active & (rd_idx >= wr_idx))
      debug_underrun <= 1'b1;
    if (reading_cur_line & ((wr_idx - rd_idx) >= 9'd128))
      debug_overflow <= 1'b1;

    rd_active_d1 <= rd_active;
    hs_d1 <= line_clk >= hs_start && line_clk < hs_end;
    hs_d2 <= hs_d1;

    {r_out, g_out, b_out} <= rd_q;
    hb_out <= ~rd_active_d1;
    hs_out <= hs_d2;
  end

endmodule

// Stateless output selector kept separate so scaler-off behavior can be
// exhaustively regression tested against the original Cave equations.
module CaveVideoHScaleMux(
  input               hscale_en_lat,
  input         [2:0] scandoubler_fx,
  input               forced_scandoubler,
  input               mixer_ce_pixel,
  input         [7:0] mixer_r,
  input         [7:0] mixer_g,
  input         [7:0] mixer_b,
  input               mixer_hs,
  input               mixer_vs,
  input               mixer_de,
  input         [7:0] hscale_r,
  input         [7:0] hscale_g,
  input         [7:0] hscale_b,
  input               hscale_hs,
  input               hscale_vs,
  input               hscale_hb,
  input               hscale_vb,
  output              mixer_scandoubler,
  output              mixer_hq2x,
  output              ce_pixel,
  output        [7:0] video_r,
  output        [7:0] video_g,
  output        [7:0] video_b,
  output              video_hs,
  output              video_vs,
  output              video_de
);

  assign mixer_scandoubler = ~hscale_en_lat
                             && ((|scandoubler_fx) || forced_scandoubler);
  assign mixer_hq2x = ~hscale_en_lat && (scandoubler_fx == 3'd1);

  assign ce_pixel = hscale_en_lat ? 1'b1 : mixer_ce_pixel;
  assign video_r  = hscale_en_lat ? hscale_r : mixer_r;
  assign video_g  = hscale_en_lat ? hscale_g : mixer_g;
  assign video_b  = hscale_en_lat ? hscale_b : mixer_b;
  assign video_hs = hscale_en_lat ? hscale_hs : mixer_hs;
  assign video_vs = hscale_en_lat ? hscale_vs : mixer_vs;
  assign video_de = hscale_en_lat ? ~(hscale_hb | hscale_vb) : mixer_de;

endmodule
