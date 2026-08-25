// This file is a Codex-assisted rewrite based on the original work of
// Josh Bassett (nullobject).

// Admit an unpaused capture only at a natural level-1 interrupt acknowledge.
// This avoids raising the private level-7 capture request across an arbitrary
// in-flight program fetch. A user-paused CPU is already stopped at a stable
// boundary, so it may enter the private capture path without waiting for an
// interrupt that cannot occur while HALT is asserted.
module CaveBanprestoCaptureBoundaryGate(
  input  wire request_i,
  input  wire level1_iack_i,
  input  wire paused_i,
  output wire request_o
);
  assign request_o = request_i && (level1_iack_i || paused_i);
endmodule

module CaveMain68kCpu #(
  parameter integer SS_RESET_CYCLES = 32
) (
  input         clock,
  input         reset,
  input         io_halt,
  input         io_external_hold,
  output        io_external_hold_ack,
  input         io_ss_state_enable,
  input         io_ss_capture_request,
  input         io_ss_restore_load,
  input  [31:0] io_ss_restore_ssp,
  input [511:0] io_ss_restore_context,
  input         io_ss_abort,
  input         io_ss_owner_abort_safe,
  output        io_ss_capture_done,
  output [31:0] io_ss_saved_ssp,
  output [511:0] io_ss_saved_context,
  output reg    io_ss_restore_done,
  output reg    io_ss_abort_ack,
  output        io_ss_terminal_fault,
  output        io_as,
  output        io_rw,
  output        io_uds,
  output        io_lds,
  input         io_dtack,
  input         io_vpa,
  input  [2:0]  io_ipl,
  output [2:0]  io_fc,
  output [22:0] io_addr,
  input  [15:0] io_din,
  output [15:0] io_dout
);
  localparam [23:0] SS_HANDLER_FIRST = 24'hff0000;
  // fx68k issues one sequential prefetch after the private RTE. Keep that word
  // private so only the subsequent resumed-PC fetch can
  // satisfy the normal-fetch checkpoint.
  localparam [23:0] SS_HANDLER_LAST = 24'hff0021;
  localparam [23:0] SS_FRAME_SSP_FIRST = 24'hff0140;
  localparam [23:0] SS_FRAME_SSP_LAST = 24'hff0143;
  localparam [23:0] SS_CONTEXT_FIRST = 24'hff0100;
  localparam [23:0] SS_CONTEXT_LAST = 24'hff013f;
  localparam [31:0] SS_CONTEXT_BOTTOM = 32'h00ff0100;
  localparam [31:0] SS_RESTORE_ENTRY = 32'h00ff0014;

  typedef enum logic [2:0] {
    StRun          = 3'd0,
    StCapture      = 3'd1,
    StHeld         = 3'd2,
    StRestoreReset = 3'd3,
    StRestore      = 3'd4,
    StFault        = 3'd5,
    StCaptureReturn = 3'd6
  } ss_cpu_state_e;

  // Justification (reg-d): an explicit phase FSM separates externally visible
  // execution, private capture, safe CE hold, reset-vector reconstruction,
  // and reset-only fail-close.
  ss_cpu_state_e ss_state_q;
  ss_cpu_state_e ss_state_d;

  // Justification (reg-d): these are the original fx68k phase clock enables.
  // They freeze with the CPU instead of creating a fabric-gated clock.
  reg phi1_enable;
  reg phi2_enable;
  reg external_hold_active_q;

  // Justification (reg-a): the private handler exports the natural interrupt
  // frame SSP plus a private 64-byte D0-D7/A0-A6/USP image. Keeping the latter
  // inside this wrapper makes a save operation transparent to game RAM.
  reg [31:0] ss_saved_ssp_q;
  reg [31:0] ss_restore_ssp_q;
  reg [511:0] ss_saved_context_q;
  reg [511:0] ss_restore_context_q;

  // Justification (reg-d): private-bus progress, reset duration, and request
  // re-arm state make capture/abort acknowledgements singular and ordered.
  reg        ss_exit_armed_q;
  reg        ss_ssp_hi_seen_q;
  reg        ss_normal_fetch_returned_q;
  reg        ss_restore_mutated_q;
  reg        ss_capture_rearm_q;
  reg        ss_abort_rearm_q;
  reg [15:0] ss_reset_count_q;

  wire raw_as_n;
  wire raw_uds_n;
  wire raw_lds_n;
  wire raw_rw;
  wire raw_fc0;
  wire raw_fc1;
  wire raw_fc2;
  wire [22:0] raw_addr;
  wire [15:0] raw_dout;
  wire [23:0] raw_byte_addr = {raw_addr, 1'b0};
  wire raw_bus_active =
    !raw_as_n && (!raw_uds_n || !raw_lds_n);
  wire raw_bus_idle =
    raw_as_n && raw_uds_n && raw_lds_n;

  wire controls_known =
    ((io_ss_state_enable === 1'b0) ||
     (io_ss_state_enable === 1'b1)) &&
    ((io_ss_capture_request === 1'b0) ||
     (io_ss_capture_request === 1'b1)) &&
    ((io_ss_restore_load === 1'b0) ||
     (io_ss_restore_load === 1'b1)) &&
    ((io_ss_abort === 1'b0) ||
     (io_ss_abort === 1'b1)) &&
    ((io_ss_owner_abort_safe === 1'b0) ||
     (io_ss_owner_abort_safe === 1'b1));

  wire ss_capture_event =
    (io_ss_capture_request === 1'b1) &&
    !ss_capture_rearm_q;
  wire ss_restore_ssp_valid =
    ((io_ss_restore_ssp == io_ss_restore_ssp) === 1'b1) &&
    (io_ss_restore_ssp != 32'd0) &&
    (io_ss_restore_ssp[31:24] == 8'd0) &&
    !io_ss_restore_ssp[0];
  wire ss_restore_context_valid =
    ((io_ss_restore_context == io_ss_restore_context) === 1'b1);
  wire ss_restore_load_legal =
    (ss_state_q == StHeld) &&
    (io_ss_state_enable === 1'b1) &&
    (io_ss_abort === 1'b0) &&
    !ss_restore_mutated_q &&
    ss_restore_ssp_valid &&
    ss_restore_context_valid &&
    raw_bus_idle;

  wire ss_override_active =
    ((ss_state_q == StCapture) ||
     (ss_state_q == StCaptureReturn) ||
     (ss_state_q == StRestoreReset) ||
     (ss_state_q == StRestore)) &&
    !ss_normal_fetch_returned_q;
  wire ss_handler_cs =
    ss_override_active &&
    raw_bus_active &&
    (raw_byte_addr >= SS_HANDLER_FIRST) &&
    (raw_byte_addr <= SS_HANDLER_LAST);
  wire ss_frame_ssp_cs =
    ss_override_active &&
    raw_bus_active &&
    (raw_byte_addr >= SS_FRAME_SSP_FIRST) &&
    (raw_byte_addr <= SS_FRAME_SSP_LAST);
  wire ss_context_cs =
    ss_override_active &&
    raw_bus_active &&
    (raw_byte_addr >= SS_CONTEXT_FIRST) &&
    (raw_byte_addr <= SS_CONTEXT_LAST);
  wire ss_reset_vector_cs =
    ((ss_state_q == StRestoreReset) ||
     (ss_state_q == StRestore)) &&
    !ss_normal_fetch_returned_q &&
    raw_bus_active &&
    raw_rw &&
    (raw_byte_addr < 24'h000008);
  wire ss_irq_vector_cs =
    (ss_state_q == StCapture) &&
    !ss_normal_fetch_returned_q &&
    raw_bus_active &&
    raw_rw &&
    ((raw_byte_addr == 24'h00007c) ||
     (raw_byte_addr == 24'h00007e));
  wire ss_special_cs =
    ss_handler_cs || ss_frame_ssp_cs || ss_context_cs ||
    ss_reset_vector_cs || ss_irq_vector_cs;
  // The immutable private handler writes the natural interrupt-frame A7 as one
  // ordered longword at ff0140/ff0142. Sample every active clock rather than relying on a
  // sampled-low gap. High-seen witnesses the first half; the existing
  // registered exit arm additionally requires the final private context word.
  wire ss_capture_ssp_pair_accept =
    (ss_state_q == StCapture) &&
    ss_frame_ssp_cs &&
    !raw_rw;
  wire ss_capture_ssp_hi_accept =
    ss_capture_ssp_pair_accept && !raw_addr[0];
  wire ss_capture_ssp_lo_accept =
    ss_capture_ssp_pair_accept && raw_addr[0];
  wire ss_capture_context_accept =
    (ss_state_q == StCapture) &&
    ss_context_cs &&
    !raw_rw;
  wire ss_capture_context_final_accept =
    ss_capture_context_accept &&
    (raw_byte_addr == 24'hff0102);

  wire ss_normal_program_fetch =
    ((ss_state_q == StCapture) ||
     (ss_state_q == StCaptureReturn) ||
     (ss_state_q == StRestore)) &&
    ss_override_active &&
    ss_exit_armed_q &&
    raw_bus_active &&
    raw_rw &&
    raw_fc1 &&
    !raw_fc0 &&
    !ss_special_cs;
  wire ss_normal_fetch_accept =
    ss_normal_program_fetch && (io_dtack === 1'b1);

  // Capture/restore completes only after the returned normal fetch has been
  // accepted and AS/UDS/LDS are inactive. Including the admission term in the
  // CE expression prevents the core from launching a new cycle on that edge.
  wire ss_hold_admit_now =
    ((ss_state_q == StCapture) ||
     (ss_state_q == StCaptureReturn) ||
     (ss_state_q == StRestore)) &&
    ss_normal_fetch_returned_q &&
    raw_bus_idle &&
    (io_ss_state_enable === 1'b1) &&
    (io_ss_abort === 1'b0);
  // High-score RAM ownership uses the same kind of clock-enable boundary as
  // save-state holding, but it does not enter the save-state CPU FSM.  The
  // combinational admission term prevents a new fx68k phase from launching on
  // the exact idle edge that acknowledges the request.
  wire external_hold_permitted =
    (ss_state_q == StRun) &&
    (io_ss_state_enable === 1'b0) &&
    (io_ss_capture_request === 1'b0);
  wire external_hold_admit_now =
    (io_external_hold === 1'b1) &&
    external_hold_permitted &&
    raw_bus_idle;
  wire ss_clock_hold =
    (ss_state_q == StHeld) ||
    (ss_state_q == StFault) ||
    ss_hold_admit_now ||
    external_hold_active_q ||
    external_hold_admit_now;

  // Keep the same shallow IPL cone as the last fitting production image.
  // CaptureReturn continues the private handler after the final context write,
  // but its distinct state code lowers IPL before the handler executes RTE.
  wire [2:0] cpu_ipl =
    (ss_state_q == StCapture) ? 3'b111 : io_ipl;
  wire halt_n =
    ~(io_halt && !ss_override_active);
  wire dtack_n =
    ~(ss_special_cs ? 1'b1 : io_dtack);
  wire vpa_n =
    ~(ss_special_cs ? 1'b0 : io_vpa);
  wire ss_external_bus_suppressed =
    ss_special_cs ||
    (ss_state_q == StRestoreReset) ||
    (ss_state_q == StFault);

  reg [15:0] ss_special_data;

  function automatic [15:0] ss_handler_word(
    input [4:0] index
  );
    begin
      case (index)
        5'd0: ss_handler_word = 16'h23cf;
        5'd1: ss_handler_word = 16'h00ff;
        5'd2: ss_handler_word = 16'h0140;
        5'd3: ss_handler_word = 16'h4ff9;
        5'd4: ss_handler_word = 16'h00ff;
        5'd5: ss_handler_word = 16'h0140;
        5'd6: ss_handler_word = 16'h48e7;
        5'd7: ss_handler_word = 16'hfffe;
        5'd8: ss_handler_word = 16'h4e6e;
        5'd9: ss_handler_word = 16'h2f0e;
        5'd10: ss_handler_word = 16'h2c5f;
        5'd11: ss_handler_word = 16'h4e66;
        5'd12: ss_handler_word = 16'h4cdf;
        5'd13: ss_handler_word = 16'h7fff;
        5'd14: ss_handler_word = 16'h2e57;
        5'd15: ss_handler_word = 16'h4e73;
        default: ss_handler_word = 16'h4e71;
      endcase
    end
  endfunction

  always @* begin
    ss_special_data = 16'hffff;

    if (ss_handler_cs) begin
      ss_special_data = ss_handler_word(raw_byte_addr[5:1]);
    end
    else if (ss_frame_ssp_cs && raw_rw) begin
      ss_special_data = raw_addr[0] ?
        ((ss_state_q == StRestore) ?
          ss_restore_ssp_q[15:0] : ss_saved_ssp_q[15:0]) :
        ((ss_state_q == StRestore) ?
          ss_restore_ssp_q[31:16] : ss_saved_ssp_q[31:16]);
    end
    else if (ss_context_cs && raw_rw) begin
      ss_special_data = (ss_state_q == StRestore) ?
        ss_restore_context_q[raw_addr[4:0] * 16 +: 16] :
        ss_saved_context_q[raw_addr[4:0] * 16 +: 16];
    end
    else if (ss_reset_vector_cs) begin
      case (raw_byte_addr[2:1])
        2'd0: ss_special_data = SS_CONTEXT_BOTTOM[31:16];
        2'd1: ss_special_data = SS_CONTEXT_BOTTOM[15:0];
        2'd2: ss_special_data = SS_RESTORE_ENTRY[31:16];
        default: ss_special_data = SS_RESTORE_ENTRY[15:0];
      endcase
    end
    else if (ss_irq_vector_cs) begin
      ss_special_data =
        raw_byte_addr[1] ? 16'h0000 : 16'h00ff;
    end
  end

  wire ss_abort_recovery_ready =
    (io_ss_owner_abort_safe === 1'b1) &&
    !ss_restore_mutated_q &&
    (((ss_state_q == StRun) && raw_bus_idle) ||
     (ss_state_q == StHeld) ||
     (((ss_state_q == StCapture) ||
       (ss_state_q == StCaptureReturn)) &&
      ss_normal_fetch_returned_q &&
      raw_bus_idle));
  wire ss_reset_complete_now =
    (ss_reset_count_q + 16'd1) >= SS_RESET_CYCLES;

  // Two-block FSM. Abort may unwind only before the CPU restore load; a late
  // abort cannot expose a partially restored multi-owner machine.
  always @* begin
    ss_state_d = ss_state_q;

    if (!controls_known) begin
      ss_state_d = StFault;
    end
    else if (io_ss_abort === 1'b1) begin
      if (ss_restore_mutated_q) begin
        ss_state_d = StFault;
      end
      else begin
        case (ss_state_q)
          StRun,
          StHeld: begin
            if (ss_abort_recovery_ready)
              ss_state_d = StRun;
          end

          StCapture: begin
            // A pending recoverable abort must not hold synthetic IPL7 across
            // the handler's RTE. Finish the private context boundary first,
            // then let CaptureReturn drain to the normal fetch and acknowledge.
            if (ss_capture_context_final_accept &&
                ss_ssp_hi_seen_q)
              ss_state_d = StCaptureReturn;
            else if (ss_abort_recovery_ready)
              ss_state_d = StRun;
          end

          StCaptureReturn: begin
            if (ss_abort_recovery_ready)
              ss_state_d = StRun;
          end

          default:
            ss_state_d = StFault;
        endcase
      end
    end
    else begin
      case (ss_state_q)
        StRun: begin
          if (io_ss_restore_load !== 1'b0) begin
            ss_state_d = StFault;
          end
          else if (ss_capture_event) begin
            // The request may arrive during an ordinary external cycle.
            // Entering capture only raises the private IPL7 request; the
            // in-flight cycle still receives its normal DTACK and completes
            // before the CPU begins interrupt entry.
            if (io_ss_state_enable === 1'b1)
              ss_state_d = StCapture;
            else
              ss_state_d = StFault;
          end
        end

        StCapture: begin
          if ((io_ss_state_enable !== 1'b1) ||
              (io_ss_restore_load !== 1'b0)) begin
            ss_state_d = StFault;
          end
          else if (ss_capture_context_final_accept &&
                   ss_ssp_hi_seen_q) begin
            ss_state_d = StCaptureReturn;
          end
        end

        StCaptureReturn: begin
          if ((io_ss_state_enable !== 1'b1) ||
              (io_ss_restore_load !== 1'b0)) begin
            ss_state_d = StFault;
          end
          else if (ss_hold_admit_now) begin
            ss_state_d = StHeld;
          end
        end

        StHeld: begin
          if (io_ss_restore_load === 1'b1) begin
            if (ss_restore_load_legal)
              ss_state_d = StRestoreReset;
            else
              ss_state_d = StFault;
          end
          else if (ss_capture_event) begin
            ss_state_d = StFault;
          end
          else if (io_ss_state_enable === 1'b0) begin
            ss_state_d = StRun;
          end
        end

        StRestoreReset: begin
          if ((io_ss_state_enable !== 1'b1) ||
              (io_ss_restore_load !== 1'b0)) begin
            ss_state_d = StFault;
          end
          else if (ss_reset_complete_now) begin
            ss_state_d = StRestore;
          end
        end

        StRestore: begin
          if ((io_ss_state_enable !== 1'b1) ||
              (io_ss_restore_load !== 1'b0)) begin
            ss_state_d = StFault;
          end
          else if (ss_hold_admit_now) begin
            ss_state_d = StHeld;
          end
        end

        StFault:
          ss_state_d = StFault;

        default:
          ss_state_d = StFault;
      endcase
    end
  end

  // Preserve the original alternating fx68k phase cadence while running.
  // Holding freezes the phase enables; restore starts them from a deterministic
  // zero phase and clocks the core normally while extReset is asserted.
  always @(posedge clock) begin
    if (reset) begin
      phi1_enable <= 1'b0;
      phi2_enable <= 1'b0;
    end
    else if ((ss_state_q == StHeld) &&
             (ss_state_d == StRestoreReset)) begin
      phi1_enable <= 1'b0;
      phi2_enable <= 1'b0;
    end
    else if (!ss_clock_hold) begin
      phi1_enable <= ~phi1_enable;
      phi2_enable <= phi1_enable;
    end
  end

  always @(posedge clock) begin
    if (reset || (io_external_hold !== 1'b1) ||
        !external_hold_permitted)
      external_hold_active_q <= 1'b0;
    else if (external_hold_admit_now)
      external_hold_active_q <= 1'b1;
  end

  always @(posedge clock) begin
    if (reset) begin
      ss_state_q <= StRun;
      ss_saved_ssp_q <= 32'd0;
      ss_restore_ssp_q <= 32'd0;
      ss_saved_context_q <= 512'd0;
      ss_restore_context_q <= 512'd0;
      ss_exit_armed_q <= 1'b0;
      ss_ssp_hi_seen_q <= 1'b0;
      ss_normal_fetch_returned_q <= 1'b0;
      ss_restore_mutated_q <= 1'b0;
      ss_capture_rearm_q <= 1'b0;
      ss_abort_rearm_q <= 1'b0;
      ss_reset_count_q <= 16'd0;
      io_ss_restore_done <= 1'b0;
      io_ss_abort_ack <= 1'b0;
    end
    else begin
      ss_state_q <= ss_state_d;
      io_ss_restore_done <= 1'b0;
      io_ss_abort_ack <= 1'b0;

      if (io_ss_capture_request === 1'b0)
        ss_capture_rearm_q <= 1'b0;
      else if (io_ss_capture_request === 1'b1)
        ss_capture_rearm_q <= 1'b1;

      if (io_ss_abort === 1'b0)
        ss_abort_rearm_q <= 1'b0;

      if (ss_capture_ssp_hi_accept) begin
        ss_saved_ssp_q[31:16] <= raw_dout;
        ss_ssp_hi_seen_q <= 1'b1;
      end

      if (ss_capture_ssp_lo_accept) begin
        ss_saved_ssp_q[15:0] <= raw_dout;
      end

      if (ss_capture_context_accept)
        ss_saved_context_q[raw_addr[4:0] * 16 +: 16] <= raw_dout;

      if (ss_capture_context_final_accept && ss_ssp_hi_seen_q)
        ss_exit_armed_q <= 1'b1;

      if (ss_normal_fetch_accept)
        ss_normal_fetch_returned_q <= 1'b1;

      if ((ss_state_q == StRun) &&
          (ss_state_d == StCapture)) begin
        ss_saved_ssp_q <= 32'd0;
        ss_saved_context_q <= 512'd0;
        ss_exit_armed_q <= 1'b0;
        ss_ssp_hi_seen_q <= 1'b0;
        ss_normal_fetch_returned_q <= 1'b0;
      end

      if ((ss_state_q == StHeld) &&
          (ss_state_d == StRestoreReset)) begin
        ss_restore_ssp_q <= io_ss_restore_ssp;
        ss_restore_context_q <= io_ss_restore_context;
        ss_exit_armed_q <= 1'b1;
        ss_normal_fetch_returned_q <= 1'b0;
        ss_restore_mutated_q <= 1'b1;
        ss_reset_count_q <= 16'd0;
      end
      else if (ss_state_q == StRestoreReset) begin
        if (ss_reset_complete_now)
          ss_reset_count_q <= 16'd0;
        else
          ss_reset_count_q <= ss_reset_count_q + 16'd1;
      end

      if ((ss_state_q == StRestore) &&
          (ss_state_d == StHeld)) begin
        io_ss_restore_done <= 1'b1;
      end

      if ((ss_state_q == StHeld) &&
          (ss_state_d == StRun) &&
          (io_ss_abort === 1'b0)) begin
        ss_restore_mutated_q <= 1'b0;
        ss_exit_armed_q <= 1'b0;
        ss_normal_fetch_returned_q <= 1'b0;
      end

      if ((io_ss_abort === 1'b1) &&
          ss_abort_recovery_ready &&
          !ss_abort_rearm_q) begin
        ss_abort_rearm_q <= 1'b1;
        io_ss_abort_ack <= 1'b1;
        ss_exit_armed_q <= 1'b0;
        ss_normal_fetch_returned_q <= 1'b0;
      end
    end
  end

  fx68k cpu (
    .clk      (clock),
    .enPhi1   (phi1_enable && !ss_clock_hold),
    .enPhi2   (phi2_enable && !ss_clock_hold),
    .extReset (reset || (ss_state_q == StRestoreReset)),
    .pwrUp    (reset || (ss_state_q == StRestoreReset)),
    .HALTn    (halt_n),
    .ASn      (raw_as_n),
    .eRWn     (raw_rw),
    .UDSn     (raw_uds_n),
    .LDSn     (raw_lds_n),
    .DTACKn   (dtack_n),
    .BERRn    (1'b1),
    .E        (),
    .VPAn     (vpa_n),
    .VMAn     (),
    .BRn      (1'b1),
    .BGn      (),
    .BGACKn   (1'b1),
    .oRESETn  (),
    .oHALTEDn (),
    .IPL0n    (~cpu_ipl[0]),
    .IPL1n    (~cpu_ipl[1]),
    .IPL2n    (~cpu_ipl[2]),
    .FC0      (raw_fc0),
    .FC1      (raw_fc1),
    .FC2      (raw_fc2),
    .eab      (raw_addr),
    .iEdb     (ss_special_cs ? ss_special_data : io_din),
    .oEdb     (raw_dout)
  );

  assign io_as =
    ~raw_as_n && !ss_external_bus_suppressed;
  assign io_rw = raw_rw;
  assign io_uds =
    ~raw_uds_n && !ss_external_bus_suppressed;
  assign io_lds =
    ~raw_lds_n && !ss_external_bus_suppressed;
  assign io_fc = {raw_fc2, raw_fc1, raw_fc0};
  assign io_addr = raw_addr;
  assign io_dout = raw_dout;
  assign io_ss_capture_done =
    (ss_state_q == StHeld) && (ss_state_q != StFault);
  assign io_ss_saved_ssp = ss_saved_ssp_q;
  assign io_ss_saved_context = ss_saved_context_q;
  assign io_ss_terminal_fault = ss_state_q == StFault;
  assign io_external_hold_ack =
    external_hold_active_q && external_hold_permitted && raw_bus_idle;
endmodule

module CaveSoundZ80Cpu(
  input         clock,
  input         reset,
  output [15:0] io_addr,
  input  [7:0]  io_din,
  output [7:0]  io_dout,
  output        io_rd,
  output        io_wr,
  output        io_rfsh,
  output        io_mreq,
  output        io_iorq,
  input         io_fast_clock,
  input         io_wait_n,
  input         io_int,
  input         io_nmi
);
  reg [2:0] clock_divider;
  wire cpu_clock_enable = io_fast_clock ? &clock_divider[1:0] : &clock_divider;

  wire mreq_n;
  wire iorq_n;
  wire rd_n;
  wire wr_n;
  wire rfsh_n;

  always @(posedge clock) begin
    if (reset)
      clock_divider <= 3'd0;
    else
      clock_divider <= clock_divider + 3'd1;
  end

  T80s cpu (
    .RESET_n (~reset),
    .CLK     (clock),
    .CEN     (cpu_clock_enable),
    .WAIT_n  (io_wait_n),
    .INT_n   (~io_int),
    .NMI_n   (~io_nmi),
    .BUSRQ_n (1'b1),
    .M1_n    (),
    .MREQ_n  (mreq_n),
    .IORQ_n  (iorq_n),
    .RD_n    (rd_n),
    .WR_n    (wr_n),
    .RFSH_n  (rfsh_n),
    .HALT_n  (),
    .BUSAK_n (),
    .A       (io_addr),
    .DI      (io_din),
    .DO      (io_dout),
    .REG     ()
  );

  assign io_rd = ~rd_n;
  assign io_wr = ~wr_n;
  assign io_rfsh = ~rfsh_n;
  assign io_mreq = ~mreq_n;
  assign io_iorq = ~iorq_n;
endmodule
