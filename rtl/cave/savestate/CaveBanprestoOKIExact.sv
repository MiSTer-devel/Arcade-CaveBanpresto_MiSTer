/*
 * Cave/Banpresto-local, exact save-state capable OKIM6295 path.
 *
 * This is a private instrumentation copy of the JT6295 implementation by
 * Jose Tejada Gomez.  The shared rtl/jt6295 sources and the normal Cave
 * integration remain untouched.
 *
 * The state clock is the normal emulation clock.  io_state_hold freezes
 * emulated state through enables; it never gates clock.  A requester must
 * assert exactly one of io_state_read/io_state_write, keep the request and
 * address/data stable until io_state_ack, then drop the request before the
 * next transfer.  State traffic is accepted only while io_state_idle is high.
 *
 * State schema 2 has STATE_WORDS (106) little-endian 32-bit words:
 *   0      schema header
 *   1      immutable configuration fingerprint
 *   2..5   wrapper clock/write/ROM/bank/held-sample state
 *   6      JT6295 timing
 *   7..8   JT6295 ROM scheduler
 *   9..12  JT6295 command/control
 *   13..19 JT6295 voice serializer and its 168-bit history
 *   20..28 JT6295 ADPCM pipeline and histories
 *   29..30 accumulator and interpolator input
 *   31..35 FIR pipeline, including the synchronous RAM read register
 *   36..104 FIR history samples 0..68 (one signed 16-bit sample per word)
 *   105    pinned FIR-coefficient identity
 *
 * GPL-3.0-or-later, matching the instrumented JT6295/JTFRAME sources.
 */

module CaveBanprestoOKIExact #(
  parameter integer INTERPOL = 1,
  parameter integer WRITE_HOLD_CYCLES = 8
) (
  input         clock,
  input         reset,

  input  [16:0] io_cen_step,
  input         io_cpu_wr,
  input  [7:0]  io_cpu_din,
  input         io_stretch_cpu_wr,
  input         io_wait_for_rom,
  output [7:0]  io_cpu_dout,

  output        io_rom_rd,
  output [17:0] io_rom_addr,
  input  [24:0] io_rom_cache_addr,
  input  [7:0]  io_rom_dout,
  input         io_rom_valid,

  output        io_audio_valid,
  output [13:0] io_audio_bits,
  output [13:0] io_audio_hold_bits,

  input         io_bank_load,
  input  [3:0]  io_bank_hi_din,
  input  [3:0]  io_bank_lo_din,
  output [3:0]  io_bank_hi,
  output [3:0]  io_bank_lo,

  input         io_state_hold,
  input         io_state_restore_prime,
  output        io_state_idle,
  input         io_state_read,
  input         io_state_write,
  input  [7:0]  io_state_addr,
  input  [31:0] io_state_wdata,
  output reg [31:0] io_state_rdata,
  output reg        io_state_ack,
  output reg        io_state_error
);

  localparam [7:0] STATE_WORDS = 8'd106;
  localparam [31:0] STATE_HEADER = {16'h4f4b, 8'h02, STATE_WORDS};
  localparam [7:0] FIR_MEMORY_BASE = 8'd36;
  localparam [7:0] FIR_MEMORY_LAST = 8'd104;
  localparam FIR_COEFFS_PINNED =
    INTERPOL == 1 ? "jt6295_up4.hex" : "jt6295_up4_soft.hex";
  // First 32 bits of the selected coefficient file's pinned SHA-256.
  localparam [31:0] FIR_COEFF_FINGERPRINT =
    INTERPOL == 1 ? 32'hc5ea_0a09 : 32'hc5ac_cc4e;

  localparam integer WRITE_HOLD_RELOAD =
    WRITE_HOLD_CYCLES <= 1 ? 0 :
    WRITE_HOLD_CYCLES > 16 ? 15 :
    WRITE_HOLD_CYCLES - 1;

  wire [31:0] state_config = {
    3'd0,
    WRITE_HOLD_CYCLES[7:0],
    INTERPOL[1:0],
    io_wait_for_rom,
    io_stretch_cpu_wr,
    io_cen_step
  };

  reg        adpcm_cen;
  reg [15:0] cen_accumulator;
  reg [3:0]  write_hold;
  reg [7:0]  write_data;
  reg [24:0] requested_rom_addr;
  reg [7:0]  rom_data;
  reg        rom_data_ready;
  reg [3:0]  bank_hi;
  reg [3:0]  bank_lo;
  reg [13:0] audio_hold;
  reg [2:0]  hold_stable_count;

  wire [16:0] cen_next = {1'b0, cen_accumulator} + io_cen_step;
  wire        rom_addr_changed = io_rom_cache_addr != requested_rom_addr;
  wire        buffer_rom_for_wait = io_stretch_cpu_wr;
  wire        chip_rom_ok =
    (io_wait_for_rom && buffer_rom_for_wait) ? rom_data_ready : io_rom_valid;
  wire [7:0] chip_rom_data =
    (io_wait_for_rom && buffer_rom_for_wait) ? rom_data : io_rom_dout;
  wire hold_for_rom =
    io_wait_for_rom && cen_next[16] && !chip_rom_ok;
  wire stretch_cpu_wr =
    io_stretch_cpu_wr && (WRITE_HOLD_CYCLES > 1);
  wire chip_cpu_wr_unheld = stretch_cpu_wr
    ? (io_cpu_wr || (write_hold != 4'd0))
    : io_cpu_wr;
  wire [7:0] chip_cpu_din = stretch_cpu_wr
    ? (io_cpu_wr ? io_cpu_din : write_data)
    : io_cpu_din;

  wire core_cen = io_state_hold ? 1'b0 : adpcm_cen;
  wire chip_cpu_wr = io_state_hold ? 1'b0 : chip_cpu_wr_unheld;

  wire [31:0] core_state_rdata;
  wire [15:0] fir_memory_dout;
  reg  [6:0]  fir_memory_addr;

  localparam [2:0] PORT_IDLE = 3'd0;
  localparam [2:0] PORT_MEM_WAIT_0 = 3'd1;
  localparam [2:0] PORT_MEM_WAIT_1 = 3'd2;
  localparam [2:0] PORT_WAIT_DROP = 3'd3;

  reg [2:0] port_state;

  wire state_request = io_state_read || io_state_write;
  wire state_request_valid =
    io_state_idle && (io_state_read ^ io_state_write);
  wire state_accept =
    port_state == PORT_IDLE && state_request_valid;
  wire state_register_write =
    state_accept && io_state_write && !io_state_error &&
    io_state_addr >= 8'd2 &&
    io_state_addr < FIR_MEMORY_BASE;
  wire state_memory_write =
    state_accept && io_state_write && !io_state_error &&
    io_state_addr >= FIR_MEMORY_BASE &&
    io_state_addr <= FIR_MEMORY_LAST;
  wire [6:0] fir_memory_port_addr = state_memory_write
    ? io_state_addr[6:0] - FIR_MEMORY_BASE[6:0]
    : fir_memory_addr;

  wire [31:0] wrapper_state_rdata =
    io_state_addr == 8'd0 ? STATE_HEADER :
    io_state_addr == 8'd1 ? state_config :
    io_state_addr == 8'd2 ?
      {11'd0, write_hold, adpcm_cen, cen_accumulator} :
    io_state_addr == 8'd3 ?
      {6'd0, rom_data_ready, requested_rom_addr} :
    io_state_addr == 8'd4 ?
      {8'd0, bank_hi, bank_lo, write_data, rom_data} :
    io_state_addr == 8'd5 ?
      {18'd0, audio_hold} :
    io_state_addr == 8'd105 ? FIR_COEFF_FINGERPRINT :
    core_state_rdata;

  always @(posedge clock) begin
    if (reset || !io_state_hold)
      hold_stable_count <= 3'd0;
    else if (!(&hold_stable_count))
      hold_stable_count <= hold_stable_count + 3'd1;
  end

  // Idle is a full state-port drain fence, not merely an emulation-hold
  // acknowledgement.  PORT_WAIT_DROP remains busy until the requester has
  // removed its acknowledged command.
  assign io_state_idle =
    (io_state_hold === 1'b1) &&
    ((&hold_stable_count) === 1'b1) &&
    (port_state === PORT_IDLE);

  always @(posedge clock) begin
    io_state_ack <= 1'b0;

    if (reset) begin
      port_state <= PORT_IDLE;
      io_state_rdata <= 32'd0;
      io_state_error <= 1'b0;
      fir_memory_addr <= 7'd0;
    end else if (!io_state_hold) begin
      if (port_state !== PORT_IDLE)
        io_state_error <= 1'b1;
      port_state <= PORT_IDLE;
    end else begin
      case (port_state)
        PORT_IDLE: begin
          if (io_state_idle &&
              (state_request !== 1'b0) &&
              ((io_state_read ^ io_state_write) !== 1'b1)) begin
            io_state_error <= 1'b1;
            io_state_rdata <= 32'd0;
            io_state_ack <= 1'b1;
            port_state <= PORT_WAIT_DROP;
          end else if (state_request_valid === 1'b1) begin
            if ((io_state_addr < STATE_WORDS) !== 1'b1) begin
              io_state_error <= 1'b1;
              io_state_rdata <= 32'd0;
              io_state_ack <= 1'b1;
              port_state <= PORT_WAIT_DROP;
            end else if (io_state_read &&
                         io_state_addr >= FIR_MEMORY_BASE &&
                         io_state_addr <= FIR_MEMORY_LAST) begin
              fir_memory_addr <=
                io_state_addr[6:0] - FIR_MEMORY_BASE[6:0];
              port_state <= PORT_MEM_WAIT_0;
            end else begin
              if (io_state_read)
                io_state_rdata <= wrapper_state_rdata;
              else if (io_state_addr == 8'd0 &&
                       io_state_wdata !== STATE_HEADER)
                io_state_error <= 1'b1;
              else if (io_state_addr == 8'd1 &&
                       io_state_wdata !== state_config)
                io_state_error <= 1'b1;
              else if (io_state_addr == 8'd105 &&
                       io_state_wdata !== FIR_COEFF_FINGERPRINT)
                io_state_error <= 1'b1;
              io_state_ack <= 1'b1;
              port_state <= PORT_WAIT_DROP;
            end
          end
        end

        PORT_MEM_WAIT_0:
          port_state <= PORT_MEM_WAIT_1;

        PORT_MEM_WAIT_1: begin
          io_state_rdata <= {16'd0, fir_memory_dout};
          io_state_ack <= 1'b1;
          port_state <= PORT_WAIT_DROP;
        end

        PORT_WAIT_DROP: begin
          if (state_request === 1'b0)
            port_state <= PORT_IDLE;
        end

        default: begin
          // Invalid/X state encoding is a sticky protocol fault. If a request
          // is live, acknowledge it as failed before waiting for withdrawal;
          // never silently return a corrupted port FSM to Idle.
          io_state_error <= 1'b1;
          io_state_rdata <= 32'd0;
          if (state_request !== 1'b0)
            io_state_ack <= 1'b1;
          port_state <= PORT_WAIT_DROP;
        end
      endcase
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      cen_accumulator <= 16'd0;
      adpcm_cen <= 1'b0;
    end else if (state_register_write && io_state_addr == 8'd2) begin
      cen_accumulator <= io_state_wdata[15:0];
      adpcm_cen <= io_state_wdata[16];
    end else if (!io_state_hold) begin
      if (hold_for_rom) begin
        adpcm_cen <= 1'b0;
      end else begin
        cen_accumulator <= cen_next[15:0];
        adpcm_cen <= cen_next[16];
      end
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      requested_rom_addr <= 25'd0;
      rom_data <= 8'd0;
      rom_data_ready <= 1'b0;
    end else if (state_register_write) begin
      case (io_state_addr)
        8'd3: begin
          requested_rom_addr <= io_state_wdata[24:0];
          rom_data_ready <= io_state_wdata[25];
        end
        8'd4:
          rom_data <= io_state_wdata[7:0];
        default: begin
        end
      endcase
    end else if (!io_state_hold) begin
      if (rom_addr_changed) begin
        requested_rom_addr <= io_rom_cache_addr;
        rom_data_ready <= 1'b0;
      end else if (io_rom_valid) begin
        rom_data <= io_rom_dout;
        rom_data_ready <= 1'b1;
      end
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      write_hold <= 4'd0;
      write_data <= 8'd0;
    end else if (state_register_write) begin
      case (io_state_addr)
        8'd2:
          write_hold <= io_state_wdata[20:17];
        8'd4:
          write_data <= io_state_wdata[15:8];
        default: begin
        end
      endcase
    end else if (!io_state_hold) begin
      if (io_cpu_wr) begin
        write_hold <= WRITE_HOLD_RELOAD[3:0];
        write_data <= io_cpu_din;
      end else if (write_hold != 4'd0) begin
        write_hold <= write_hold - 4'd1;
      end
    end
  end

  always @(posedge clock) begin
    if (reset) begin
      bank_hi <= 4'd0;
      bank_lo <= 4'd0;
    end else if (state_register_write && io_state_addr == 8'd4) begin
      bank_lo <= io_state_wdata[19:16];
      bank_hi <= io_state_wdata[23:20];
    end else if (!io_state_hold && io_bank_load) begin
      bank_hi <= io_bank_hi_din;
      bank_lo <= io_bank_lo_din;
    end
  end

  always @(posedge clock) begin
    if (reset)
      audio_hold <= 14'd0;
    else if (state_register_write && io_state_addr == 8'd5)
      audio_hold <= io_state_wdata[13:0];
    else if (!io_state_hold && io_audio_valid)
      audio_hold <= io_audio_bits;
  end

  assign io_bank_hi = bank_hi;
  assign io_bank_lo = bank_lo;
  assign io_audio_hold_bits = audio_hold;
  assign io_rom_rd =
    (io_wait_for_rom && buffer_rom_for_wait)
      ? (rom_addr_changed || !rom_data_ready)
      : 1'b1;

  CaveBanprestoOkiExactCore #(
    .INTERPOL  (INTERPOL),
    .FIR_COEFFS(FIR_COEFFS_PINNED)
  ) core (
    .rst              (reset),
    .clk              (clock),
    .hold             (io_state_hold),
    .cen              (core_cen),
    .ss               (1'b1),
    .wrn              (~chip_cpu_wr),
    .din              (chip_cpu_din),
    .dout             (io_cpu_dout),
    .rom_addr         (io_rom_addr),
    .rom_data         (chip_rom_data),
    .rom_ok           (chip_rom_ok),
    .sound            (io_audio_bits),
    .sample           (io_audio_valid),
    .state_we         (state_register_write),
    .state_addr       (io_state_addr),
    .state_wdata      (io_state_wdata),
    .state_rdata      (core_state_rdata),
    .state_mem_addr   (fir_memory_port_addr),
    .state_mem_we     (state_memory_write),
    .state_mem_wdata  (io_state_wdata[15:0]),
    .state_mem_rdata  (fir_memory_dout),
    .state_prime      (io_state_restore_prime)
  );

`ifdef SIMULATION
  initial begin
    if (INTERPOL != 1 && INTERPOL != 2)
      $fatal(1, "CaveBanprestoOKIExact INTERPOL must be 1 or 2");
    if (WRITE_HOLD_CYCLES < 1 || WRITE_HOLD_CYCLES > 16)
      $fatal(1, "CaveBanprestoOKIExact WRITE_HOLD_CYCLES must be 1..16");
  end
`endif

endmodule


module CaveBanprestoOkiExactCore #(
  parameter integer INTERPOL = 1,
  parameter FIR_COEFFS =
    INTERPOL == 1 ? "jt6295_up4.hex" : "jt6295_up4_soft.hex"
) (
  input               rst,
  input               clk,
  input               hold,
  input               cen,
  input               ss,
  input               wrn,
  input        [7:0]  din,
  output       [7:0]  dout,
  output       [17:0] rom_addr,
  input        [7:0]  rom_data,
  input               rom_ok,
  output signed [13:0] sound,
  output              sample,
  input               state_we,
  input        [7:0]  state_addr,
  input        [31:0] state_wdata,
  output       [31:0] state_rdata,
  input        [6:0]  state_mem_addr,
  input               state_mem_we,
  input        [15:0] state_mem_wdata,
  output       [15:0] state_mem_rdata,
  input               state_prime
);

  wire cen_sr;
  wire cen_sr4;
  wire cen_sr32;
  wire [3:0] busy;
  wire [3:0] ack;
  wire [3:0] start;
  wire [3:0] stop;
  wire [17:0] start_addr;
  wire [17:0] stop_addr;
  wire [17:0] ch_addr;
  wire [9:0] ctrl_addr;
  wire [7:0] ch_data;
  wire [7:0] ctrl_data;
  wire [3:0] pipe_data;
  wire [3:0] att;
  wire [3:0] pipe_att;
  wire ctrl_ok;
  wire pipe_en;
  wire signed [11:0] pipe_snd;

  wire [31:0] timing_state_rdata;
  wire [31:0] rom_state_rdata;
  wire [31:0] ctrl_state_rdata;
  wire [31:0] serial_state_rdata;
  wire [31:0] adpcm_state_rdata;
  wire [31:0] acc_state_rdata;

  assign dout = {4'hf, busy | start};
  assign state_rdata =
    timing_state_rdata | rom_state_rdata | ctrl_state_rdata |
    serial_state_rdata | adpcm_state_rdata | acc_state_rdata;

  CaveBanprestoOkiExactTiming u_timing (
    .clk         (clk),
    .hold        (hold),
    .cen         (cen),
    .ss          (ss),
    .cen_sr      (cen_sr),
    .cen_sr4     (cen_sr4),
    .cen_sr4b    (),
    .cen_sr32    (cen_sr32),
    .state_we    (state_we),
    .state_addr  (state_addr),
    .state_wdata (state_wdata),
    .state_rdata (timing_state_rdata)
  );

  CaveBanprestoOkiExactRom u_rom (
    .clk         (clk),
    .hold        (hold),
    .cen4        (cen_sr4),
    .cen32       (cen_sr32),
    .adpcm_addr  (ch_addr),
    .ctrl_addr   ({8'd0, ctrl_addr}),
    .adpcm_dout  (ch_data),
    .ctrl_dout   (ctrl_data),
    .ctrl_ok     (ctrl_ok),
    .rom_addr    (rom_addr),
    .rom_data    (rom_data),
    .rom_ok      (rom_ok),
    .state_we    (state_we),
    .state_addr  (state_addr),
    .state_wdata (state_wdata),
    .state_rdata (rom_state_rdata)
  );

  CaveBanprestoOkiExactCtrl u_ctrl (
    .rst         (rst),
    .clk         (clk),
    .hold        (hold),
    .cen4        (cen_sr4),
    .wrn         (wrn),
    .din         (din),
    .start_addr  (start_addr),
    .stop_addr   (stop_addr),
    .att         (att),
    .rom_addr    (ctrl_addr),
    .rom_data    (ctrl_data),
    .rom_ok      (ctrl_ok),
    .start       (start),
    .stop        (stop),
    .busy        (busy),
    .ack         (ack),
    .state_we    (state_we),
    .state_addr  (state_addr),
    .state_wdata (state_wdata),
    .state_rdata (ctrl_state_rdata)
  );

  CaveBanprestoOkiExactSerial u_serial (
    .rst         (rst),
    .clk         (clk),
    .hold        (hold),
    .cen4        (cen_sr4),
    .start_addr  (start_addr),
    .stop_addr   (stop_addr),
    .att         (att),
    .start       (start),
    .stop        (stop),
    .busy        (busy),
    .ack         (ack),
    .rom_addr    (ch_addr),
    .rom_data    (ch_data),
    .pipe_en     (pipe_en),
    .pipe_att    (pipe_att),
    .pipe_data   (pipe_data),
    .state_we    (state_we),
    .state_addr  (state_addr),
    .state_wdata (state_wdata),
    .state_rdata (serial_state_rdata)
  );

  CaveBanprestoOkiExactAdpcm u_adpcm (
    .rst         (rst),
    .clk         (clk),
    .hold        (hold),
    .cen         (cen_sr4),
    .en          (pipe_en),
    .att         (pipe_att),
    .data        (pipe_data),
    .sound       (pipe_snd),
    .state_we    (state_we),
    .state_addr  (state_addr),
    .state_wdata (state_wdata),
    .state_rdata (adpcm_state_rdata)
  );

  CaveBanprestoOkiExactAcc #(
    .INTERPOL  (INTERPOL),
    .FIR_COEFFS(FIR_COEFFS)
  ) u_acc (
    .rst             (rst),
    .clk             (clk),
    .hold            (hold),
    .cen             (cen_sr),
    .cen4            (cen_sr4),
    .sound_in        (pipe_snd),
    .sound_out       (sound),
    .sample          (sample),
    .state_we        (state_we),
    .state_addr      (state_addr),
    .state_wdata     (state_wdata),
    .state_rdata     (acc_state_rdata),
    .state_mem_addr  (state_mem_addr),
    .state_mem_we    (state_mem_we),
    .state_mem_wdata (state_mem_wdata),
    .state_mem_rdata (state_mem_rdata),
    .state_prime     (state_prime)
  );

endmodule


module CaveBanprestoOkiExactTiming (
  input         clk,
  input         hold,
  input         cen,
  input         ss,
  output reg    cen_sr,
  output reg    cen_sr4,
  output reg    cen_sr4b,
  output reg    cen_sr32,
  input         state_we,
  input  [7:0]  state_addr,
  input  [31:0] state_wdata,
  output reg [31:0] state_rdata
);

  reg [2:0] base = 3'd0;
  reg [5:0] cnt = 6'd0;
  wire [2:0] lim = ss ? 3'h3 : 3'h4;

  always @(posedge clk) begin
    if (state_we && state_addr == 8'd6) begin
      base <= state_wdata[2:0];
      cnt <= state_wdata[8:3];
      cen_sr <= state_wdata[9];
      cen_sr4 <= state_wdata[10];
      cen_sr4b <= state_wdata[11];
      cen_sr32 <= state_wdata[12];
    end else if (!hold) begin
      cen_sr4 <= 1'b0;
      cen_sr4b <= 1'b0;
      cen_sr <= 1'b0;
      cen_sr32 <= 1'b0;
      if (cen) begin
        base <= base == lim ? 3'd0 : base + 3'd1;
        if (base == 3'd0)
          cnt <= cnt == 6'd32 ? 6'd0 : cnt + 6'd1;
        cen_sr32 <= !cnt[5] && base == 3'd0;
        cen_sr4 <= !cnt[5] && cnt[2:0] == 3'b000 && base == 3'd0;
        cen_sr4b <= !cnt[5] && cnt[2:0] == 3'b100 && base == 3'd0;
        cen_sr <= {cnt, base} == 9'd0;
      end
    end
  end

  always @* begin
    state_rdata = 32'd0;
    if (state_addr == 8'd6)
      state_rdata[12:0] =
        {cen_sr32, cen_sr4b, cen_sr4, cen_sr, cnt, base};
  end

endmodule


module CaveBanprestoOkiExactRom (
  input         clk,
  input         hold,
  input         cen4,
  input         cen32,
  input  [17:0] adpcm_addr,
  input  [17:0] ctrl_addr,
  output reg [7:0] adpcm_dout,
  output reg [7:0] ctrl_dout,
  output reg       ctrl_ok,
  output reg [17:0] rom_addr,
  input  [7:0] rom_data,
  input        rom_ok,
  input         state_we,
  input  [7:0]  state_addr,
  input  [31:0] state_wdata,
  output reg [31:0] state_rdata
);

  reg [7:0] st;
  reg [1:0] wait2;
  wire new_addr = rom_addr != ctrl_addr;

  always @(posedge clk) begin
    if (state_we && state_addr == 8'd7)
      st <= state_wdata[7:0];
    else if (!hold) begin
      if (cen4)
        st <= 8'h80;
      else if (cen32)
        st <= {st[6:0], st[7]};
    end
  end

  always @(posedge clk) begin
    if (state_we) begin
      case (state_addr)
        8'd7: begin
          wait2 <= state_wdata[9:8];
          adpcm_dout <= state_wdata[17:10];
          ctrl_dout <= state_wdata[25:18];
          ctrl_ok <= state_wdata[26];
        end
        8'd8:
          rom_addr <= state_wdata[17:0];
        default: begin
        end
      endcase
    end else if (!hold) begin
      case (st)
        8'b00000001, 8'b00000010: begin
          rom_addr <= adpcm_addr;
          adpcm_dout <= rom_data;
          ctrl_ok <= 1'b0;
          wait2 <= 2'b0;
        end
        default: begin
          rom_addr <= ctrl_addr;
          if (wait2 == 2'b11 && !new_addr) begin
            ctrl_ok <= rom_ok;
            ctrl_dout <= rom_data;
          end else begin
            ctrl_ok <= 1'b0;
          end
          if (new_addr)
            wait2 <= 2'b0;
          else
            wait2 <= {wait2[0], 1'b1};
        end
      endcase
    end
  end

  always @* begin
    state_rdata = 32'd0;
    case (state_addr)
      8'd7:
        state_rdata[26:0] =
          {ctrl_ok, ctrl_dout, adpcm_dout, wait2, st};
      8'd8:
        state_rdata[17:0] = rom_addr;
      default: begin
      end
    endcase
  end

endmodule


module CaveBanprestoOkiExactCtrl (
  input         rst,
  input         clk,
  input         hold,
  input         cen4,
  input         wrn,
  input  [7:0]  din,
  output reg [17:0] start_addr,
  output reg [17:0] stop_addr,
  output reg [3:0]  att,
  output [9:0] rom_addr,
  input  [7:0] rom_data,
  input        rom_ok,
  output reg [3:0] start,
  output reg [3:0] stop,
  input  [3:0] busy,
  input  [3:0] ack,
  input         state_we,
  input  [7:0]  state_addr,
  input  [31:0] state_wdata,
  output reg [31:0] state_rdata
);

  reg last_wrn;
  wire negedge_wrn = !wrn && last_wrn;
  reg [6:0] phrase;
  reg push;
  reg pull;
  reg [3:0] ch;
  reg [3:0] new_att;
  reg cmd;
  reg [17:0] new_start;
  reg [17:8] new_stop;
  reg [2:0] st;
  reg [2:0] addr_lsb;
  reg wrom;

  assign rom_addr = {phrase, addr_lsb};

  always @(posedge clk) begin
    if (state_we && state_addr == 8'd9)
      last_wrn <= state_wdata[0];
    else if (!hold)
      last_wrn <= wrn;
  end

  always @(posedge clk) begin
    if (rst) begin
      cmd <= 1'b0;
      stop <= 4'd0;
      ch <= 4'd0;
      new_att <= 4'd0;
      pull <= 1'b1;
      phrase <= 7'd0;
    end else if (state_we) begin
      case (state_addr)
        8'd9: begin
          phrase <= state_wdata[7:1];
          pull <= state_wdata[9];
          ch <= state_wdata[13:10];
          new_att <= state_wdata[17:14];
          cmd <= state_wdata[18];
          stop <= state_wdata[22:19];
        end
        default: begin
        end
      endcase
    end else if (!hold) begin
      if (cen4)
        stop <= stop & busy;
      if (push)
        pull <= 1'b0;
      if (negedge_wrn) begin
        if (cmd) begin
          ch <= din[7:4];
          new_att <= din[3:0];
          cmd <= 1'b0;
          pull <= 1'b1;
        end else if (din[7]) begin
          phrase <= din[6:0];
          cmd <= 1'b1;
          stop <= 4'd0;
        end else begin
          stop <= din[6:3];
        end
      end
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      st <= 3'd7;
      att <= 4'd0;
      start_addr <= 18'd0;
      stop_addr <= 18'd0;
      start <= 4'd0;
      push <= 1'b0;
      addr_lsb <= 3'd0;
    end else if (state_we) begin
      case (state_addr)
        8'd9:
          push <= state_wdata[8];
        8'd10: begin
          new_start <= state_wdata[17:0];
          new_stop <= state_wdata[27:18];
        end
        8'd11: begin
          start_addr <= state_wdata[17:0];
          start <= state_wdata[21:18];
          att <= state_wdata[25:22];
        end
        8'd12: begin
          stop_addr <= state_wdata[17:0];
          st <= state_wdata[20:18];
          addr_lsb <= state_wdata[23:21];
          wrom <= state_wdata[24];
        end
        default: begin
        end
      endcase
    end else if (!hold) begin
      if (st != 3'd7) begin
        wrom <= 1'b0;
        if (!wrom && rom_ok) begin
          st <= st + 3'd1;
          addr_lsb <= st;
          wrom <= 1'b1;
        end
      end
      case (st)
        3'd7: begin
          start <= start & ~ack;
          addr_lsb <= 3'd0;
          if (pull) begin
            st <= 3'd0;
            wrom <= 1'b1;
            push <= 1'b1;
          end
        end
        3'd0: begin
        end
        3'd1:
          new_start[17:16] <= rom_data[1:0];
        3'd2:
          new_start[15:8] <= rom_data;
        3'd3:
          new_start[7:0] <= rom_data;
        3'd4:
          new_stop[17:16] <= rom_data[1:0];
        3'd5:
          new_stop[15:8] <= rom_data;
        3'd6: begin
          start <= ch;
          start_addr <= new_start;
          stop_addr <= {new_stop[17:8], rom_data};
          att <= new_att;
          push <= 1'b0;
        end
        default: begin
        end
      endcase
    end
  end

  always @* begin
    state_rdata = 32'd0;
    case (state_addr)
      8'd9:
        state_rdata[22:0] = {
          stop, cmd, new_att, ch, pull, push, phrase, last_wrn
        };
      8'd10:
        state_rdata[27:0] = {new_stop, new_start};
      8'd11:
        state_rdata[25:0] = {att, start, start_addr};
      8'd12:
        state_rdata[24:0] = {wrom, addr_lsb, st, stop_addr};
      default: begin
      end
    endcase
  end

endmodule


module CaveBanprestoOkiExactSerial (
  input         rst,
  input         clk,
  input         hold,
  input         cen4,
  input  [17:0] start_addr,
  input  [17:0] stop_addr,
  input  [3:0]  att,
  input  [3:0]  start,
  input  [3:0]  stop,
  output reg [3:0] busy,
  output reg [3:0] ack,
  output [17:0] rom_addr,
  input  [7:0]  rom_data,
  output reg       pipe_en,
  output reg [3:0] pipe_att,
  output reg [3:0] pipe_data,
  input         state_we,
  input  [7:0]  state_addr,
  input  [31:0] state_wdata,
  output reg [31:0] state_rdata
);

  localparam integer CSRW = 42;

  reg [3:0] ch;
  reg up_start;
  reg up_stop;
  reg [167:0] csr_history;

  wire busy_out = csr_history[126];
  wire [3:0] att_out = csr_history[130:127];
  wire [18:0] cnt = csr_history[149:131];
  wire [17:0] stop_out = csr_history[167:150];
  wire over = rom_addr >= stop_out;
  wire update = up_start || up_stop;
  wire cont = busy_out && !over;
  wire [18:0] cnt_next = cont ? cnt + 19'd1 : cnt;
  wire [17:0] stop_in = up_start ? stop_addr : stop_out;
  wire [18:0] cnt_in =
    up_start ? {start_addr, 1'b0} : cnt_next;
  wire [3:0] att_in = up_start ? att : att_out;
  wire busy_in = update ? (up_start && !up_stop) : cont;
  wire [CSRW-1:0] csr_in = {stop_in, cnt_in, att_in, busy_in};

  assign rom_addr = cnt[18:1];

  always @* begin
    case (ch)
      4'b0001:
        {up_start, up_stop} = {start[0], stop[0]};
      4'b0010:
        {up_start, up_stop} = {start[1], stop[1]};
      4'b0100:
        {up_start, up_stop} = {start[2], stop[2]};
      4'b1000:
        {up_start, up_stop} = {start[3], stop[3]};
      default:
        {up_start, up_stop} = 2'b00;
    endcase
  end

  always @(posedge clk or posedge rst) begin
    if (rst)
      ch <= 4'b0001;
    else if (state_we && state_addr == 8'd13)
      ch <= state_wdata[3:0];
    else if (!hold && cen4)
      ch <= {ch[2:0], ch[3]};
  end

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      busy <= 4'd0;
    end else if (state_we && state_addr == 8'd13) begin
      busy <= state_wdata[7:4];
      ack <= state_wdata[11:8];
    end else if (!hold) begin
      case (ch)
        4'b0001:
          busy[0] <= busy_in;
        4'b0010:
          busy[1] <= busy_in;
        4'b0100:
          busy[2] <= busy_in;
        4'b1000:
          busy[3] <= busy_in;
        default:
          busy <= 4'd0;
      endcase
      if (cen4) begin
        case (ch)
          4'b0001, 4'b0010, 4'b0100, 4'b1000:
            ack <= up_start ? ch : 4'b0;
          default:
            ack <= 4'd0;
        endcase
      end
    end
  end

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      csr_history <= 168'd0;
    end else if (state_we) begin
      case (state_addr)
        8'd14:
          csr_history[31:0] <= state_wdata;
        8'd15:
          csr_history[63:32] <= state_wdata;
        8'd16:
          csr_history[95:64] <= state_wdata;
        8'd17:
          csr_history[127:96] <= state_wdata;
        8'd18:
          csr_history[159:128] <= state_wdata;
        8'd19:
          csr_history[167:160] <= state_wdata[7:0];
        default: begin
        end
      endcase
    end else if (!hold && cen4) begin
      csr_history <= {csr_history[125:0], csr_in};
    end
  end

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      pipe_data <= 4'd0;
      pipe_en <= 1'b0;
      pipe_att <= 4'd0;
    end else if (state_we && state_addr == 8'd13) begin
      pipe_en <= state_wdata[12];
      pipe_att <= state_wdata[16:13];
      pipe_data <= state_wdata[20:17];
    end else if (!hold && cen4) begin
      pipe_data <= !cnt[0] ? rom_data[7:4] : rom_data[3:0];
      pipe_att <= att_out;
      pipe_en <= busy_out;
    end
  end

  always @* begin
    state_rdata = 32'd0;
    case (state_addr)
      8'd13:
        state_rdata[20:0] =
          {pipe_data, pipe_att, pipe_en, ack, busy, ch};
      8'd14:
        state_rdata = csr_history[31:0];
      8'd15:
        state_rdata = csr_history[63:32];
      8'd16:
        state_rdata = csr_history[95:64];
      8'd17:
        state_rdata = csr_history[127:96];
      8'd18:
        state_rdata = csr_history[159:128];
      8'd19:
        state_rdata[7:0] = csr_history[167:160];
      default: begin
      end
    endcase
  end

endmodule


module CaveBanprestoOkiExactAdpcm (
  input                    rst,
  input                    clk,
  input                    hold,
  input                    cen,
  input                    en,
  input             [3:0]  att,
  input             [3:0]  data,
  output reg signed [11:0] sound,
  input                    state_we,
  input             [7:0]  state_addr,
  input             [31:0] state_wdata,
  output reg        [31:0] state_rdata
);

  reg [10:0] lut [0:63];
  reg signed [6:0] gain_lut [0:15];

  reg [5:0] idx_inc_II;
  reg [5:0] delta_idx_I;
  reg [5:0] delta_idx_II;
  reg [5:0] delta_idx_III;
  reg [5:0] delta_idx_IV;
  reg [2:0] factor_II;
  reg [2:0] factor_III;
  reg factor_IV;
  reg sign_II;
  reg sign_III;
  reg sign_IV;
  reg sign_V;
  reg [11:0] dn_II;
  reg [11:0] qn_II;
  reg [11:0] dn_III;
  reg [11:0] qn_III;
  reg [11:0] dn_IV;
  reg [11:0] qn_IV;
  reg [11:0] qn_V;
  reg signed [11:0] snd_VI;
  reg signed [6:0] gain_VI;
  reg signed [12:0] snd_V;

  reg [3:0] enable_history;
  reg [15:0] att_history;
  reg [47:0] sound_history;

  wire en_V = enable_history[3];
  wire [3:0] att_V = att_history[15:12];
  wire signed [11:0] snd_out = sound_history[47:36];
  wire signed [16:0] mul_VI = snd_VI * gain_VI;
  wire signed [12:0] lim_pos = 13'd2047;
  wire signed [12:0] lim_neg = -13'd2048;
  wire signed [11:0] snd_in =
    snd_V > lim_pos ? lim_pos[11:0] :
    snd_V < lim_neg ? lim_neg[11:0] :
    snd_V[11:0];

  function [12:0] extend_sample;
    input [11:0] value;
    begin
      extend_sample = {value[11], value};
    end
  endfunction

  always @* begin
    snd_V = !en_V
      ? 13'd0
      : sign_V
        ? extend_sample(snd_out) - {1'b0, qn_V}
        : extend_sample(snd_out) + {1'b0, qn_V};
  end

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      idx_inc_II <= 6'd0;
      delta_idx_I <= 6'd0;
      delta_idx_II <= 6'd0;
      delta_idx_III <= 6'd0;
      delta_idx_IV <= 6'd0;
      factor_II <= 3'd0;
      factor_III <= 3'd0;
      factor_IV <= 1'b0;
      sign_II <= 1'b0;
      sign_III <= 1'b0;
      sign_IV <= 1'b0;
      sign_V <= 1'b0;
      dn_II <= 12'd0;
      qn_II <= 12'd0;
      dn_III <= 12'd0;
      qn_III <= 12'd0;
      dn_IV <= 12'd0;
      qn_IV <= 12'd0;
      qn_V <= 12'd0;
    end else if (state_we) begin
      case (state_addr)
        8'd20: begin
          dn_II <= state_wdata[11:0];
          dn_III <= state_wdata[23:12];
        end
        8'd21: begin
          dn_IV <= state_wdata[11:0];
          qn_II <= state_wdata[23:12];
        end
        8'd22: begin
          qn_III <= state_wdata[11:0];
          qn_IV <= state_wdata[23:12];
        end
        8'd23:
          qn_V <= state_wdata[11:0];
        8'd24: begin
          delta_idx_I <= state_wdata[24:19];
          delta_idx_II <= state_wdata[30:25];
        end
        8'd25: begin
          delta_idx_III <= state_wdata[5:0];
          delta_idx_IV <= state_wdata[11:6];
          idx_inc_II <= state_wdata[17:12];
          factor_II <= state_wdata[20:18];
          factor_III <= state_wdata[23:21];
          factor_IV <= state_wdata[24];
          sign_II <= state_wdata[25];
          sign_III <= state_wdata[26];
          sign_IV <= state_wdata[27];
          sign_V <= state_wdata[28];
        end
        default: begin
        end
      endcase
    end else if (!hold && cen) begin
      case (data[1:0])
        2'd0:
          idx_inc_II <= 6'd2;
        2'd1:
          idx_inc_II <= 6'd4;
        2'd2:
          idx_inc_II <= 6'd6;
        2'd3:
          idx_inc_II <= 6'd8;
      endcase
      sign_II <= data[3];
      delta_idx_II <= en ? delta_idx_I : 6'd0;
      factor_II <= en ? data[2:0] : 3'd0;
      dn_II <= {1'b0, lut[delta_idx_I]};
      qn_II <= {1'b0, lut[delta_idx_I] >> 3};

      sign_III <= sign_II;
      delta_idx_III <= factor_II[2]
        ? delta_idx_II + idx_inc_II
        : delta_idx_II - 6'd1;
      qn_III <= factor_II[2] ? qn_II + dn_II : qn_II;
      dn_III <= dn_II >> 1;
      factor_III <= factor_II;

      sign_IV <= sign_III;
      qn_IV <= factor_III[1] ? qn_III + dn_III : qn_III;
      dn_IV <= dn_III >> 1;
      factor_IV <= factor_III[0];
      delta_idx_IV <= delta_idx_III > 6'd48
        ? (factor_III[2] ? 6'd48 : 6'd0)
        : delta_idx_III;

      sign_V <= sign_IV;
      qn_V <= factor_IV ? qn_IV + dn_IV : qn_IV;
      delta_idx_I <= delta_idx_IV;
    end
  end

  always @(posedge clk or posedge rst) begin
    if (rst)
      enable_history <= 4'd0;
    else if (state_we && state_addr == 8'd26)
      enable_history <= state_wdata[3:0];
    else if (!hold && cen)
      enable_history <= {enable_history[2:0], en};
  end

  always @(posedge clk or posedge rst) begin
    if (rst)
      att_history <= 16'd0;
    else if (state_we && state_addr == 8'd26)
      att_history <= state_wdata[19:4];
    else if (!hold && cen)
      att_history <= {att_history[11:0], att};
  end

  always @(posedge clk or posedge rst) begin
    if (rst)
      sound_history <= 48'd0;
    else if (state_we) begin
      case (state_addr)
        8'd27:
          sound_history[31:0] <= state_wdata;
        8'd28:
          sound_history[47:32] <= state_wdata[15:0];
        default: begin
        end
      endcase
    end else if (!hold && cen) begin
      sound_history <= {sound_history[35:0], snd_in};
    end
  end

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      snd_VI <= 12'd0;
      gain_VI <= 7'd0;
      sound <= 12'd0;
    end else if (state_we) begin
      case (state_addr)
        8'd23:
          snd_VI <= state_wdata[23:12];
        8'd24: begin
          sound <= state_wdata[11:0];
          gain_VI <= state_wdata[18:12];
        end
        default: begin
        end
      endcase
    end else if (!hold && cen) begin
      snd_VI <= snd_in;
      gain_VI <= gain_lut[att_V];
      sound <= mul_VI[16:5];
    end
  end

  always @* begin
    state_rdata = 32'd0;
    case (state_addr)
      8'd20:
        state_rdata[23:0] = {dn_III, dn_II};
      8'd21:
        state_rdata[23:0] = {qn_II, dn_IV};
      8'd22:
        state_rdata[23:0] = {qn_IV, qn_III};
      8'd23:
        state_rdata[23:0] = {snd_VI, qn_V};
      8'd24:
        state_rdata[30:0] =
          {delta_idx_II, delta_idx_I, gain_VI, sound};
      8'd25:
        state_rdata[28:0] = {
          sign_V,
          sign_IV,
          sign_III,
          sign_II,
          factor_IV,
          factor_III,
          factor_II,
          idx_inc_II,
          delta_idx_IV,
          delta_idx_III
        };
      8'd26:
        state_rdata[19:0] = {att_history, enable_history};
      8'd27:
        state_rdata = sound_history[31:0];
      8'd28:
        state_rdata[15:0] = sound_history[47:32];
      default: begin
      end
    endcase
  end

  initial begin
    lut[ 0] = 11'd0016; lut[ 1] = 11'd0017;
    lut[ 2] = 11'd0019; lut[ 3] = 11'd0021;
    lut[ 4] = 11'd0023; lut[ 5] = 11'd0025;
    lut[ 6] = 11'd0028; lut[ 7] = 11'd0031;
    lut[ 8] = 11'd0034; lut[ 9] = 11'd0037;
    lut[10] = 11'd0041; lut[11] = 11'd0045;
    lut[12] = 11'd0050; lut[13] = 11'd0055;
    lut[14] = 11'd0060; lut[15] = 11'd0066;
    lut[16] = 11'd0073; lut[17] = 11'd0080;
    lut[18] = 11'd0088; lut[19] = 11'd0097;
    lut[20] = 11'd0107; lut[21] = 11'd0118;
    lut[22] = 11'd0130; lut[23] = 11'd0143;
    lut[24] = 11'd0157; lut[25] = 11'd0173;
    lut[26] = 11'd0190; lut[27] = 11'd0209;
    lut[28] = 11'd0230; lut[29] = 11'd0253;
    lut[30] = 11'd0279; lut[31] = 11'd0307;
    lut[32] = 11'd0337; lut[33] = 11'd0371;
    lut[34] = 11'd0408; lut[35] = 11'd0449;
    lut[36] = 11'd0494; lut[37] = 11'd0544;
    lut[38] = 11'd0598; lut[39] = 11'd0658;
    lut[40] = 11'd0724; lut[41] = 11'd0796;
    lut[42] = 11'd0876; lut[43] = 11'd0963;
    lut[44] = 11'd1060; lut[45] = 11'd1166;
    lut[46] = 11'd1282; lut[47] = 11'd1411;
    lut[48] = 11'd1552;
    lut[49] = 11'd0; lut[50] = 11'd0;
    lut[51] = 11'd0; lut[52] = 11'd0;
    lut[53] = 11'd0; lut[54] = 11'd0;
    lut[55] = 11'd0; lut[56] = 11'd0;
    lut[57] = 11'd0; lut[58] = 11'd0;
    lut[59] = 11'd0; lut[60] = 11'd0;
    lut[61] = 11'd0; lut[62] = 11'd0;
    lut[63] = 11'd0;
  end

  initial begin
    gain_lut[0] = 7'd32;
    gain_lut[1] = 7'd22;
    gain_lut[2] = 7'd16;
    gain_lut[3] = 7'd11;
    gain_lut[4] = 7'd8;
    gain_lut[5] = 7'd6;
    gain_lut[6] = 7'd4;
    gain_lut[7] = 7'd3;
    gain_lut[8] = 7'd2;
    gain_lut[9] = 7'd0;
    gain_lut[10] = 7'd0;
    gain_lut[11] = 7'd0;
    gain_lut[12] = 7'd0;
    gain_lut[13] = 7'd0;
    gain_lut[14] = 7'd0;
    gain_lut[15] = 7'd0;
  end

endmodule


module CaveBanprestoOkiExactAcc #(
  parameter integer INTERPOL = 1,
  parameter FIR_COEFFS =
    INTERPOL == 1 ? "jt6295_up4.hex" : "jt6295_up4_soft.hex"
) (
  input                rst,
  input                clk,
  input                hold,
  input                cen,
  input                cen4,
  input signed [11:0]  sound_in,
  output signed [13:0] sound_out,
  output               sample,
  input                state_we,
  input        [7:0]   state_addr,
  input        [31:0]  state_wdata,
  output reg   [31:0]  state_rdata,
  input        [6:0]   state_mem_addr,
  input                state_mem_we,
  input        [15:0]  state_mem_wdata,
  output       [15:0]  state_mem_rdata,
  input                state_prime
);

  reg signed [13:0] acc;
  reg signed [13:0] sum;
  reg signed [15:0] fir_din;
  wire signed [15:0] fir_dout;
  wire [31:0] fir_state_rdata;

  always @(posedge clk or posedge rst) begin
    if (rst)
      acc <= 14'd0;
    else if (state_we && state_addr == 8'd29)
      acc <= state_wdata[13:0];
    else if (!hold && cen4)
      acc <= cen ? sound_in : acc + sound_in;
  end

  always @(posedge clk or posedge rst) begin
    if (rst)
      sum <= 14'd0;
    else if (state_we && state_addr == 8'd29)
      sum <= state_wdata[27:14];
    else if (!hold && cen)
      sum <= acc;
  end

  always @(posedge clk or posedge rst) begin
    if (rst)
      fir_din <= 16'd0;
    else if (state_we && state_addr == 8'd30)
      fir_din <= state_wdata[15:0];
    else if (!hold && cen4)
      fir_din <= cen ? {{1{sum[13]}}, sum, 1'b0} : 16'd0;
  end

  assign sample = cen4;
  assign sound_out = fir_dout[13:0];

  always @* begin
    state_rdata = fir_state_rdata;
    case (state_addr)
      8'd29:
        state_rdata[27:0] = {sum, acc};
      8'd30:
        state_rdata[15:0] = fir_din;
      default: begin
      end
    endcase
  end

  CaveBanprestoOkiExactFir #(
    .COEFFS(FIR_COEFFS),
    .KMAX  (8'd69)
  ) u_fir (
    .rst             (rst),
    .clk             (clk),
    .hold            (hold),
    .sample          (cen4),
    .din             (fir_din),
    .dout            (fir_dout),
    .state_we        (state_we),
    .state_addr      (state_addr),
    .state_wdata     (state_wdata),
    .state_rdata     (fir_state_rdata),
    .state_mem_addr  (state_mem_addr),
    .state_mem_we    (state_mem_we),
    .state_mem_wdata (state_mem_wdata),
    .state_mem_rdata (state_mem_rdata),
    .state_prime     (state_prime)
  );

endmodule


module CaveBanprestoOkiExactFir #(
  parameter COEFFS = "jt6295_up4.hex",
  parameter [7:0] KMAX = 8'd69
) (
  input                    rst,
  input                    clk,
  input                    hold,
  input                    sample,
  input signed      [15:0] din,
  output reg signed [15:0] dout,
  input                    state_we,
  input             [7:0]  state_addr,
  input             [31:0] state_wdata,
  output reg        [31:0] state_rdata,
  input             [6:0]  state_mem_addr,
  input                    state_mem_we,
  input             [15:0] state_mem_wdata,
  output            [15:0] state_mem_rdata,
  input                    state_prime
);

  reg [7:0] pt_wr;
  reg [7:0] pt_rd;
  reg [7:0] cnt;
  reg st;
  reg wt_ram;
  reg signed [35:0] acc;
  reg signed [15:0] coeff;
  reg signed [31:0] p;

  reg [8:0] rd_addr;
  reg [15:0] port0_q;
  reg signed [15:0] ram_q1;
  reg signed [15:0] restored_ram_dout;
  reg restored_ram_dout_valid;
  wire signed [15:0] ram_dout =
    restored_ram_dout_valid ? restored_ram_dout : ram_q1;

  wire [8:0] port0_addr = hold
    ? {2'b10, state_mem_addr}
    : {1'b1, pt_wr};
  wire [15:0] port0_data = hold ? state_mem_wdata : din;
  wire port0_we = hold ? state_mem_we : sample;

  (* ramstyle = "no_rw_check" *) reg [15:0] mem [0:511];

  integer init_index;
`ifdef SIMULATION
  initial begin
    for (init_index = 0; init_index < 512; init_index = init_index + 1)
      mem[init_index] = 16'd0;
    $readmemh(COEFFS, mem);
  end
`else
  initial begin
    if (COEFFS != "")
      $readmemh(COEFFS, mem);
  end
`endif

  function signed [35:0] extend_product;
    input signed [31:0] value;
    begin
      extend_product = {{4{value[31]}}, value};
    end
  endfunction

  function [7:0] loop_inc;
    input [7:0] value;
    begin
      loop_inc = value == KMAX - 8'd1 ? 8'd0 : value + 8'd1;
    end
  endfunction

  function signed [15:0] saturate;
    input [35:0] value;
    begin
      saturate = value[35:30] == {6{value[29]}}
        ? value[29:14]
        : {value[35], {15{~value[35]}}};
    end
  endfunction

  always @* begin
    rd_addr = st == 1'b0 ? {1'b0, cnt} : {1'b1, pt_rd};
  end

  always @(posedge clk) begin
    port0_q <= mem[port0_addr];
    if (port0_we)
      mem[port0_addr] <= port0_data;
  end

  always @(posedge clk) begin
    if (!hold)
      ram_q1 <= mem[rd_addr];
  end

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      restored_ram_dout <= 16'd0;
    end else if (state_we && state_addr == 8'd35) begin
      restored_ram_dout <= state_wdata[31:16];
    end
  end

  // Word 35 stages the logical synchronous-RAM read value during pass 2.
  // Only the globally ordered final commit may make that staged value live.
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      restored_ram_dout_valid <= 1'b0;
    end else if (state_prime) begin
      restored_ram_dout_valid <= 1'b1;
    end else if (!hold) begin
      restored_ram_dout_valid <= 1'b0;
    end
  end

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      dout <= 16'd0;
      pt_rd <= 8'd0;
      pt_wr <= 8'd0;
      cnt <= 8'd0;
      acc <= 36'd0;
      p <= 32'd0;
      coeff <= 16'd0;
    end else if (state_we) begin
      case (state_addr)
        8'd31: begin
          pt_wr <= state_wdata[7:0];
          pt_rd <= state_wdata[15:8];
          cnt <= state_wdata[23:16];
          st <= state_wdata[24];
          wt_ram <= state_wdata[25];
        end
        8'd32:
          acc[31:0] <= state_wdata;
        8'd33: begin
          acc[35:32] <= state_wdata[3:0];
          coeff <= state_wdata[19:4];
        end
        8'd34:
          p <= state_wdata;
        8'd35:
          dout <= state_wdata[15:0];
        default: begin
        end
      endcase
    end else if (!hold) begin
      if (sample) begin
        pt_rd <= pt_wr;
        cnt <= 8'd0;
        pt_wr <= loop_inc(pt_wr);
        acc <= 36'd0;
        p <= 32'd0;
        st <= 1'b0;
        wt_ram <= 1'b1;
      end else begin
        wt_ram <= ~wt_ram;
        if (!wt_ram) begin
          if (cnt < KMAX) begin
            st <= ~st;
            if (st == 1'b0) begin
              coeff <= ram_dout;
            end else begin
              p <= ram_dout * coeff;
              acc <= acc + extend_product(p);
              cnt <= cnt + 8'd1;
              pt_rd <= loop_inc(pt_rd);
            end
          end else begin
            dout <= saturate(acc);
          end
        end
      end
    end
  end

  assign state_mem_rdata = port0_q;

  always @* begin
    state_rdata = 32'd0;
    case (state_addr)
      8'd31:
        state_rdata[25:0] = {wt_ram, st, cnt, pt_rd, pt_wr};
      8'd32:
        state_rdata = acc[31:0];
      8'd33:
        state_rdata[19:0] = {coeff, acc[35:32]};
      8'd34:
        state_rdata = p;
      8'd35:
        state_rdata = {ram_dout, dout};
      default: begin
      end
    endcase
  end

endmodule
