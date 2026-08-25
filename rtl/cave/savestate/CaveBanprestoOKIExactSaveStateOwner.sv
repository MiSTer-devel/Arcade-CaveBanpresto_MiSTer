`default_nettype none

// CaveBanpresto owner 28/29 adapter for the exact local OKIM6295 path.
//
// Pass 1 is an ordered, write-free validation scan.  It checks every
// reserved bit and bounded state field and stores an immutable comparison
// image.  Pass 2 must reproduce that image exactly and writes each accepted
// word directly to the already-held device.  The FIR synchronous-read shadow
// is made live only by one final restore-prime pulse after the stream engine's
// globally ordered restore_commit_i event.
module CaveBanprestoOKIExactOwnerAdapter #(
  parameter [7:0] OWNER_INDEX = 8'd28,
  parameter integer INTERPOL = 1,
  parameter integer WRITE_HOLD_CYCLES = 8
) (
  input  wire        clock,
  input  wire        reset,
  input  wire [16:0] io_cen_step,
  input  wire        io_stretch_cpu_wr,
  input  wire        io_wait_for_rom,
  input  wire        io_ss_restore_enable_i,
  input  wire        restore_begin_i,
  input  wire        restore_commit_i,

  input  wire        device_state_idle_i,
  output wire        device_state_read_o,
  output wire        device_state_write_o,
  output logic [7:0] device_state_addr_o,
  output logic [31:0] device_state_wdata_o,
  input  wire [31:0] device_state_rdata_i,
  input  wire        device_state_ack_i,
  input  wire        device_state_error_i,
  output logic       device_restore_prime_o,

  output logic validation_complete_o,
  output logic validation_valid_o,
  output logic write_complete_o,
  output logic write_valid_o,
  output logic restore_prime_o,
  output logic restore_committed_o,
  output logic terminal_fault_o,
  output wire  owner_idle_o,

  cavebanpresto_ssbus_if.responder ssbus
);

  localparam [31:0] WORD_COUNT = 32'd106;
  localparam [1:0] WIDTH_CODE_32 = 2'd2;
  localparam [31:0] STATE_HEADER = 32'h4f4b_026a;
  localparam [31:0] FIR_COEFF_FINGERPRINT =
    INTERPOL == 1 ? 32'hc5ea_0a09 : 32'hc5ac_cc4e;
  localparam integer WRITE_HOLD_RELOAD =
    WRITE_HOLD_CYCLES <= 1 ? 0 :
    WRITE_HOLD_CYCLES > 16 ? 15 :
    WRITE_HOLD_CYCLES - 1;

  wire [31:0] expected_config = {
    3'd0,
    WRITE_HOLD_CYCLES[7:0],
    INTERPOL[1:0],
    io_wait_for_rom,
    io_stretch_cpu_wr,
    io_cen_step
  };

  typedef enum logic [2:0] {
    StIdle          = 3'd0,
    StPass2ReadWait = 3'd1,
    StPass2Compare  = 3'd2,
    StDeviceRead    = 3'd3,
    StDeviceWrite   = 3'd4,
    StWaitRelease   = 3'd5
  } state_e;

  state_e state_q;

  // Justification (reg-a): pass 1 is immutable evidence that every pass-2
  // element is bit-for-bit identical.  No device write is connected to this
  // storage path.
  // Pass-1 writes and pass-2 reads are mutually exclusive, so mixed-port
  // read-during-write behavior is architecturally irrelevant.  Keep this
  // evidence in M10Ks: the production design is LAB-constrained and has
  // sufficient spare M10K blocks for both validation images.
  (* ramstyle = "M10K, no_rw_check" *)
  logic [31:0] validate_image [0:105];
  logic [6:0]  validate_image_read_addr_q;
  logic [31:0] validate_image_rdata_q;

  // Justification (reg-a): holds a bus transaction while the local state port
  // incurs its registered and synchronous-memory latency.
  logic [31:0] request_addr_q;
  logic [63:0] request_data_q;

  // Justification (reg-a): a launched local state-port request is irrevocable
  // and remains asserted until acknowledgement.  Abort/abandonment after
  // launch poisons the request but cannot retract or roll it back.
  logic device_state_read_q;
  logic device_state_write_q;
  logic device_request_poisoned_q;
  logic device_write_started_q;
  logic attempt_active_q;

  // Justification (reg-b): strict monotonic cursors plus sticky failure state
  // reject missing, duplicate, out-of-order, and post-completion transfers.
  logic [6:0] validate_next_q;
  logic [6:0] write_next_q;
  logic       validation_failed_q;
  logic       write_failed_q;

  logic [3:0] request_command;
  logic       request_selected;
  logic       request_command_legal;
  logic       request_payload_known;
  logic       device_read_data_known;
  logic       address_valid;
  logic       validate_sequence_valid;
  logic       write_sequence_valid;
  logic       request_config_valid;
  logic       validation_accept;
  logic       request_matches_read;
  logic       request_matches_write;
  logic       restore_begin_idle_safe;
  logic       control_abort_now;
  logic       request_admission_safe;
  logic       read_launch_safe;
  logic       write_launch_safe;
  logic       pass2_request_safe;

  function automatic logic one_hot4(input logic [3:0] value);
    begin
      one_hot4 =
        (value != 4'd0) &&
        ((value & (value - 4'd1)) == 4'd0);
    end
  endfunction

  function automatic logic one_hot8(input logic [7:0] value);
    begin
      one_hot8 =
        (value != 8'd0) &&
        ((value & (value - 8'd1)) == 8'd0);
    end
  endfunction

  function automatic logic gain_valid(input logic [6:0] value);
    begin
      case (value)
        7'd0, 7'd2, 7'd3, 7'd4, 7'd6, 7'd8,
        7'd11, 7'd16, 7'd22, 7'd32:
          gain_valid = 1'b1;
        default:
          gain_valid = 1'b0;
      endcase
    end
  endfunction

  function automatic logic word_structure_valid(
    input logic [31:0] address,
    input logic [31:0] data
  );
    begin
      word_structure_valid = 1'b0;
      case (address)
        32'd0:
          word_structure_valid = data == STATE_HEADER;
        32'd1:
          word_structure_valid = data[31:29] == 3'd0;
        32'd2:
          word_structure_valid =
            (data[31:21] == 11'd0) &&
            (data[20:17] <= WRITE_HOLD_RELOAD[3:0]);
        32'd3:
          word_structure_valid = data[31:26] == 6'd0;
        32'd4:
          word_structure_valid = data[31:24] == 8'd0;
        32'd5:
          word_structure_valid = data[31:14] == 18'd0;
        32'd6:
          word_structure_valid =
            (data[31:13] == 19'd0) &&
            (data[2:0] <= 3'd3) &&
            (data[8:3] <= 6'd32);
        32'd7:
          word_structure_valid =
            (data[31:27] == 5'd0) &&
            one_hot8(data[7:0]);
        32'd8:
          word_structure_valid = data[31:18] == 14'd0;
        32'd9:
          word_structure_valid = data[31:23] == 9'd0;
        32'd10:
          word_structure_valid = data[31:28] == 4'd0;
        32'd11:
          word_structure_valid = data[31:26] == 6'd0;
        32'd12:
          word_structure_valid = data[31:25] == 7'd0;
        32'd13:
          word_structure_valid =
            (data[31:21] == 11'd0) &&
            one_hot4(data[3:0]);
        32'd14, 32'd15, 32'd16, 32'd17, 32'd18:
          word_structure_valid = 1'b1;
        32'd19:
          word_structure_valid = data[31:8] == 24'd0;
        32'd20, 32'd21, 32'd22, 32'd23:
          word_structure_valid = data[31:24] == 8'd0;
        32'd24:
          word_structure_valid =
            (data[31] == 1'b0) &&
            (data[24:19] <= 6'd48) &&
            (data[30:25] <= 6'd48) &&
            gain_valid(data[18:12]);
        32'd25:
          word_structure_valid =
            (data[31:29] == 3'd0) &&
            (data[11:6] <= 6'd48) &&
            ((data[17:12] == 6'd0) ||
             (data[17:12] == 6'd2) ||
             (data[17:12] == 6'd4) ||
             (data[17:12] == 6'd6) ||
             (data[17:12] == 6'd8));
        32'd26:
          word_structure_valid = data[31:20] == 12'd0;
        32'd27:
          word_structure_valid = 1'b1;
        32'd28:
          word_structure_valid = data[31:16] == 16'd0;
        32'd29:
          word_structure_valid = data[31:28] == 4'd0;
        32'd30:
          word_structure_valid = data[31:16] == 16'd0;
        32'd31:
          word_structure_valid =
            (data[31:26] == 6'd0) &&
            (data[7:0] < 8'd69) &&
            (data[15:8] < 8'd69) &&
            (data[23:16] <= 8'd69);
        32'd32:
          word_structure_valid = 1'b1;
        32'd33:
          word_structure_valid = data[31:20] == 12'd0;
        32'd34, 32'd35:
          word_structure_valid = 1'b1;
        default: begin
          if (address >= 32'd36 && address <= 32'd104)
            word_structure_valid = data[31:16] == 16'd0;
          else if (address == 32'd105)
            word_structure_valid =
              data == FIR_COEFF_FINGERPRINT;
        end
      endcase
    end
  endfunction

  assign request_command = {
    ssbus.req_query,
    ssbus.req_validate,
    ssbus.req_write,
    ssbus.req_read
  };
  assign request_selected =
    (ssbus.req_select === OWNER_INDEX) &&
    (request_command !== 4'b0000);
  assign request_command_legal =
    (request_command == 4'b0001) ||
    (request_command == 4'b0010) ||
    (request_command == 4'b0100) ||
    (request_command == 4'b1000);
  // Self-equality is constant true in two-state hardware, but becomes X in
  // four-state simulation if any payload bit is X/Z. The known-good admission
  // checks below compare their aggregate predicate explicitly with 1'b1.
  assign request_payload_known = ssbus.req_data == ssbus.req_data;
  assign device_read_data_known =
    device_state_rdata_i == device_state_rdata_i;
  assign address_valid = ssbus.req_addr < WORD_COUNT;
  assign validate_sequence_valid =
    address_valid &&
    (ssbus.req_addr == {25'd0, validate_next_q});
  assign write_sequence_valid =
    address_valid &&
    (ssbus.req_addr == {25'd0, write_next_q});
  assign request_config_valid =
    (ssbus.req_addr != 32'd1) ||
    (ssbus.req_data[31:0] == expected_config);

  assign validation_accept =
    (state_q == StIdle) &&
    !restore_begin_i &&
    !restore_commit_i &&
    attempt_active_q &&
    request_selected &&
    (request_command == 4'b0100) &&
    device_state_idle_i &&
    !device_state_error_i &&
    !terminal_fault_o &&
    !validation_failed_q &&
    !validation_complete_o &&
    validate_sequence_valid &&
    request_payload_known &&
    (ssbus.req_data[63:32] == 32'd0) &&
    request_config_valid &&
    word_structure_valid(ssbus.req_addr, ssbus.req_data[31:0]);

  assign request_matches_read =
    (ssbus.req_select == OWNER_INDEX) &&
    (request_command == 4'b0001) &&
    (ssbus.req_addr == request_addr_q) &&
    (ssbus.req_data == request_data_q);
  assign request_matches_write =
    (ssbus.req_select == OWNER_INDEX) &&
    (request_command == 4'b0010) &&
    (ssbus.req_addr == request_addr_q) &&
    (ssbus.req_data == request_data_q);

  // Every launch/advance predicate is checked against an explicitly known
  // one. In four-state simulation an X must therefore fail closed rather than
  // taking an `if (!predicate) ... else accept` success path.
  assign request_admission_safe =
    !control_abort_now &&
    !terminal_fault_o &&
    request_command_legal;
  assign read_launch_safe =
    address_valid &&
    request_payload_known &&
    device_state_idle_i &&
    !device_state_ack_i &&
    !device_state_error_i;
  assign write_launch_safe =
    attempt_active_q &&
    validation_complete_o &&
    validation_valid_o &&
    !validation_failed_q &&
    !write_failed_q &&
    !write_complete_o &&
    write_sequence_valid &&
    request_payload_known &&
    (ssbus.req_data[63:32] == 32'd0) &&
    request_config_valid &&
    word_structure_valid(ssbus.req_addr, ssbus.req_data[31:0]) &&
    device_state_idle_i &&
    !device_state_ack_i &&
    !device_state_error_i &&
    io_ss_restore_enable_i;
  assign pass2_request_safe =
    !control_abort_now &&
    !terminal_fault_o &&
    attempt_active_q &&
    !write_failed_q &&
    io_ss_restore_enable_i &&
    device_state_idle_i &&
    !device_state_ack_i &&
    !device_state_error_i &&
    request_matches_write;

  assign restore_begin_idle_safe =
    (state_q == StIdle) &&
    !(|request_command) &&
    device_state_idle_i &&
    !device_state_ack_i &&
    !device_state_error_i &&
    !device_state_read_q &&
    !device_state_write_q &&
    !device_write_started_q &&
    !restore_commit_i &&
    !terminal_fault_o;

  assign control_abort_now = restore_begin_i || restore_commit_i;

  // Once asserted, each exact-device request obeys the same no-valid-drop
  // rule as the owner bus: it remains asserted through acknowledgement.
  // Unsafe control is checked before launch; a later abort poisons and drains
  // the irrevocable request instead of retracting it.
  assign device_state_read_o = device_state_read_q;
  assign device_state_write_o = device_state_write_q;
  assign owner_idle_o =
    (state_q === StIdle) &&
    ((|request_command) === 1'b0) &&
    (device_state_idle_i === 1'b1) &&
    (device_state_ack_i === 1'b0) &&
    (device_state_read_q === 1'b0) &&
    (device_state_write_q === 1'b0) &&
    (restore_begin_i === 1'b0) &&
    (restore_commit_i === 1'b0);

  // Synchronous comparison-image read preserves a compact memory
  // implementation rather than building a 106-way asynchronous register mux.
  always_ff @(posedge clock) begin
    if (validation_accept === 1'b1)
      validate_image[ssbus.req_addr[6:0]] <= ssbus.req_data[31:0];

    validate_image_rdata_q <=
      validate_image[validate_image_read_addr_q];
  end

  always_ff @(posedge clock) begin
    if (reset) begin
      state_q <= StIdle;
      request_addr_q <= 32'd0;
      request_data_q <= 64'd0;
      validate_image_read_addr_q <= 7'd0;
      validate_next_q <= 7'd0;
      write_next_q <= 7'd0;
      validation_failed_q <= 1'b0;
      write_failed_q <= 1'b0;
      device_state_read_q <= 1'b0;
      device_state_write_q <= 1'b0;
      device_request_poisoned_q <= 1'b0;
      device_write_started_q <= 1'b0;
      attempt_active_q <= 1'b0;
      device_state_addr_o <= 8'd0;
      device_state_wdata_o <= 32'd0;
      device_restore_prime_o <= 1'b0;
      validation_complete_o <= 1'b0;
      validation_valid_o <= 1'b0;
      write_complete_o <= 1'b0;
      write_valid_o <= 1'b0;
      restore_prime_o <= 1'b0;
      restore_committed_o <= 1'b0;
      terminal_fault_o <= 1'b0;
      ssbus.rsp_data <= 64'd0;
      ssbus.rsp_ack <= 1'b0;
      ssbus.rsp_error <= 1'b0;
    end else begin
      ssbus.rsp_data <= 64'd0;
      ssbus.rsp_ack <= 1'b0;
      ssbus.rsp_error <= 1'b0;
      device_restore_prime_o <= 1'b0;
      restore_prime_o <= 1'b0;

      if (restore_begin_i && restore_begin_idle_safe) begin
        state_q <= StIdle;
        request_addr_q <= 32'd0;
        request_data_q <= 64'd0;
        validate_image_read_addr_q <= 7'd0;
        validate_next_q <= 7'd0;
        write_next_q <= 7'd0;
        validation_failed_q <= 1'b0;
        write_failed_q <= 1'b0;
        device_state_read_q <= 1'b0;
        device_state_write_q <= 1'b0;
        device_request_poisoned_q <= 1'b0;
        device_write_started_q <= 1'b0;
        attempt_active_q <= 1'b1;
        device_state_addr_o <= 8'd0;
        device_state_wdata_o <= 32'd0;
        validation_complete_o <= 1'b0;
        validation_valid_o <= 1'b0;
        write_complete_o <= 1'b0;
        write_valid_o <= 1'b0;
        restore_committed_o <= 1'b0;
      end else if (restore_commit_i && (state_q == StIdle)) begin
        if (!restore_begin_i &&
            attempt_active_q &&
            !(|request_command) &&
            device_state_idle_i &&
            !device_state_error_i &&
            io_ss_restore_enable_i &&
            validation_complete_o &&
            validation_valid_o &&
            write_complete_o &&
            write_valid_o &&
            !validation_failed_q &&
            !write_failed_q &&
            !restore_committed_o &&
            !terminal_fault_o) begin
          device_restore_prime_o <= 1'b1;
          restore_prime_o <= 1'b1;
          restore_committed_o <= 1'b1;
          device_write_started_q <= 1'b0;
          attempt_active_q <= 1'b0;
        end else begin
          validation_failed_q <= 1'b1;
          validation_valid_o <= 1'b0;
          write_failed_q <= 1'b1;
          write_valid_o <= 1'b0;
          terminal_fault_o <= 1'b1;
        end
      end else begin
        // Begin is legal only at the fully drained boundary handled above.
        // Commit outside idle is likewise an abort-like protocol fault.  Both
        // poison the current epoch but the state machine below still drains
        // an already accepted exact-device request.
        if (control_abort_now) begin
          validation_failed_q <= 1'b1;
          validation_valid_o <= 1'b0;
          write_failed_q <= 1'b1;
          write_valid_o <= 1'b0;
          terminal_fault_o <= 1'b1;
        end

        case (state_q)
          StIdle: begin
            device_state_read_q <= 1'b0;
            device_state_write_q <= 1'b0;
            device_request_poisoned_q <= 1'b0;

            if (request_selected) begin
              if (request_admission_safe !== 1'b1) begin
                ssbus.rsp_ack <= 1'b1;
                ssbus.rsp_error <= 1'b1;
                terminal_fault_o <= 1'b1;
                state_q <= StWaitRelease;
              end else if (ssbus.req_query) begin
                ssbus.rsp_data <= ssbus.query_descriptor(
                  OWNER_INDEX,
                  WORD_COUNT,
                  WIDTH_CODE_32
                );
                ssbus.rsp_ack <= 1'b1;
                state_q <= StWaitRelease;
              end else if (ssbus.req_validate) begin
                ssbus.rsp_ack <= 1'b1;
                if (validation_accept !== 1'b1) begin
                  ssbus.rsp_error <= 1'b1;
                  validation_failed_q <= 1'b1;
                  validation_valid_o <= 1'b0;
                end else begin
                  validate_next_q <= validate_next_q + 7'd1;
                  if (ssbus.req_addr == 32'd105) begin
                    validation_complete_o <= 1'b1;
                    validation_valid_o <= 1'b1;
                  end
                end
                state_q <= StWaitRelease;
              end else if (ssbus.req_read) begin
                if (read_launch_safe !== 1'b1) begin
                  ssbus.rsp_ack <= 1'b1;
                  ssbus.rsp_error <= 1'b1;
                  terminal_fault_o <= 1'b1;
                  state_q <= StWaitRelease;
                end else begin
                  request_addr_q <= ssbus.req_addr;
                  request_data_q <= ssbus.req_data;
                  device_state_addr_o <= ssbus.req_addr[7:0];
                  device_state_wdata_o <= 32'd0;
                  device_state_read_q <= 1'b1;
                  device_request_poisoned_q <= 1'b0;
                  state_q <= StDeviceRead;
                end
              end else begin
                if (write_launch_safe !== 1'b1) begin
                  ssbus.rsp_ack <= 1'b1;
                  ssbus.rsp_error <= 1'b1;
                  write_failed_q <= 1'b1;
                  write_valid_o <= 1'b0;
                  terminal_fault_o <= 1'b1;
                  state_q <= StWaitRelease;
                end else begin
                  request_addr_q <= ssbus.req_addr;
                  request_data_q <= ssbus.req_data;
                  validate_image_read_addr_q <= ssbus.req_addr[6:0];
                  device_request_poisoned_q <= 1'b0;
                  state_q <= StPass2ReadWait;
                end
              end
            end
          end

          StPass2ReadWait: begin
            if (pass2_request_safe !== 1'b1) begin
              if (request_matches_write === 1'b1) begin
                ssbus.rsp_ack <= 1'b1;
                ssbus.rsp_error <= 1'b1;
              end
              write_failed_q <= 1'b1;
              write_valid_o <= 1'b0;
              terminal_fault_o <= 1'b1;
              state_q <= StWaitRelease;
            end else begin
              state_q <= StPass2Compare;
            end
          end

          StPass2Compare: begin
            if (pass2_request_safe !== 1'b1) begin
              if (request_matches_write === 1'b1) begin
                ssbus.rsp_ack <= 1'b1;
                ssbus.rsp_error <= 1'b1;
              end
              write_failed_q <= 1'b1;
              write_valid_o <= 1'b0;
              terminal_fault_o <= 1'b1;
              state_q <= StWaitRelease;
            end else if (request_data_q[31:0] !==
                         validate_image_rdata_q) begin
              ssbus.rsp_ack <= 1'b1;
              ssbus.rsp_error <= 1'b1;
              write_failed_q <= 1'b1;
              write_valid_o <= 1'b0;
              terminal_fault_o <= 1'b1;
              state_q <= StWaitRelease;
            end else begin
              device_state_addr_o <= request_addr_q[7:0];
              device_state_wdata_o <= request_data_q[31:0];
              device_state_write_q <= 1'b1;
              device_request_poisoned_q <= 1'b0;
              device_write_started_q <= 1'b1;
              state_q <= StDeviceWrite;
            end
          end

          StDeviceRead: begin
            if ((control_abort_now !== 1'b0) ||
                (request_matches_read !== 1'b1)) begin
              device_request_poisoned_q <= 1'b1;
              if ((control_abort_now !== 1'b0) ||
                  ((|request_command) !== 1'b0) ||
                  (device_write_started_q !== 1'b0))
                terminal_fault_o <= 1'b1;
            end
            if (device_state_error_i !== 1'b0) begin
              device_request_poisoned_q <= 1'b1;
              terminal_fault_o <= 1'b1;
            end

            if (device_state_ack_i === 1'b1) begin
              device_state_read_q <= 1'b0;
              if (device_read_data_known !== 1'b1) begin
                device_request_poisoned_q <= 1'b1;
                terminal_fault_o <= 1'b1;
              end
              if (request_matches_read === 1'b1) begin
                ssbus.rsp_data <=
                  ((device_request_poisoned_q !== 1'b0) ||
                   (control_abort_now !== 1'b0) ||
                   (device_state_error_i !== 1'b0) ||
                   (device_read_data_known !== 1'b1))
                    ? 64'd0
                    : {32'd0, device_state_rdata_i};
                ssbus.rsp_ack <= 1'b1;
                ssbus.rsp_error <=
                  (device_request_poisoned_q !== 1'b0) ||
                  (control_abort_now !== 1'b0) ||
                  (device_state_error_i !== 1'b0) ||
                  (device_read_data_known !== 1'b1);
              end
              state_q <= StWaitRelease;
            end else if (device_state_ack_i !== 1'b0) begin
              device_request_poisoned_q <= 1'b1;
              terminal_fault_o <= 1'b1;
            end
          end

          StDeviceWrite: begin
            if ((control_abort_now !== 1'b0) ||
                (request_matches_write !== 1'b1) ||
                (io_ss_restore_enable_i !== 1'b1) ||
                (device_state_error_i !== 1'b0)) begin
              device_request_poisoned_q <= 1'b1;
              write_failed_q <= 1'b1;
              write_valid_o <= 1'b0;
              terminal_fault_o <= 1'b1;
            end

            if (device_state_ack_i === 1'b1) begin
              device_state_write_q <= 1'b0;
              if (request_matches_write === 1'b1) begin
                ssbus.rsp_ack <= 1'b1;
                ssbus.rsp_error <=
                  (device_request_poisoned_q !== 1'b0) ||
                  (control_abort_now !== 1'b0) ||
                  (io_ss_restore_enable_i !== 1'b1) ||
                  (device_state_error_i !== 1'b0);
              end

              if ((device_request_poisoned_q !== 1'b0) ||
                  (control_abort_now !== 1'b0) ||
                  (request_matches_write !== 1'b1) ||
                  (io_ss_restore_enable_i !== 1'b1) ||
                  (device_state_error_i !== 1'b0)) begin
                write_failed_q <= 1'b1;
                write_valid_o <= 1'b0;
                terminal_fault_o <= 1'b1;
              end else begin
                write_next_q <= write_next_q + 7'd1;
                if (request_addr_q == 32'd105) begin
                  write_complete_o <= 1'b1;
                  write_valid_o <= 1'b1;
                end
              end
              state_q <= StWaitRelease;
            end else if (device_state_ack_i !== 1'b0) begin
              device_request_poisoned_q <= 1'b1;
              write_failed_q <= 1'b1;
              write_valid_o <= 1'b0;
              terminal_fault_o <= 1'b1;
            end
          end

          StWaitRelease: begin
            device_state_read_q <= 1'b0;
            device_state_write_q <= 1'b0;
            if (((|request_command) === 1'b0) &&
                (device_state_ack_i === 1'b0)) begin
              device_request_poisoned_q <= 1'b0;
              state_q <= StIdle;
            end
          end

          default: begin
            device_request_poisoned_q <= 1'b1;
            terminal_fault_o <= 1'b1;
            // A corrupted FSM value must not retract an irrevocable local
            // request. Hold it until ack, then quarantine in WaitRelease.
            if ((device_state_read_q !== 1'b0) ||
                (device_state_write_q !== 1'b0)) begin
              if (device_state_ack_i === 1'b1) begin
                device_state_read_q <= 1'b0;
                device_state_write_q <= 1'b0;
                state_q <= StWaitRelease;
              end
            end else begin
              device_state_read_q <= 1'b0;
              device_state_write_q <= 1'b0;
              state_q <= StWaitRelease;
            end
          end
        endcase
      end
    end
  end

`ifdef SIMULATION
  initial begin
    if (OWNER_INDEX != 8'd28 && OWNER_INDEX != 8'd29)
      $fatal(1, "OKI exact owner index must be 28 or 29");
    if (INTERPOL != 1 && INTERPOL != 2)
      $fatal(1, "OKI exact owner INTERPOL must be 1 or 2");
    if (WRITE_HOLD_CYCLES < 1 || WRITE_HOLD_CYCLES > 16)
      $fatal(1, "OKI exact owner WRITE_HOLD_CYCLES must be 1..16");
  end
`endif

endmodule


// Integration wrapper used for either owner 28 or owner 29.  The external ROM
// requester/cache/CDC state is intentionally not claimed here; owner 34 must
// drain, canonicalize, or restore it before the global commit/release.
module CaveBanprestoOKIExactSaveStateOwner #(
  parameter [7:0] OWNER_INDEX = 8'd28,
  parameter integer INTERPOL = 1,
  parameter integer WRITE_HOLD_CYCLES = 8
) (
  input  wire        clock,
  input  wire        reset,
  input  wire [16:0] io_cen_step,
  input  wire        io_cpu_wr,
  input  wire [7:0]  io_cpu_din,
  input  wire        io_stretch_cpu_wr,
  input  wire        io_wait_for_rom,
  output wire [7:0]  io_cpu_dout,
  output wire        io_rom_rd,
  output wire [17:0] io_rom_addr,
  input  wire [24:0] io_rom_cache_addr,
  input  wire [7:0]  io_rom_dout,
  input  wire        io_rom_valid,
  output wire        io_audio_valid,
  output wire [13:0] io_audio_bits,
  output wire [13:0] io_audio_hold_bits,
  input  wire        io_bank_load,
  input  wire [3:0]  io_bank_hi_din,
  input  wire [3:0]  io_bank_lo_din,
  output wire [3:0]  io_bank_hi,
  output wire [3:0]  io_bank_lo,

  input  wire        io_ss_hold_i,
  input  wire        io_ss_restore_enable_i,
  input  wire        restore_begin_i,
  input  wire        restore_commit_i,
  output wire        io_ss_idle_o,
  output wire        validation_complete_o,
  output wire        validation_valid_o,
  output wire        write_complete_o,
  output wire        write_valid_o,
  output wire        restore_prime_o,
  output wire        restore_committed_o,
  output wire        terminal_fault_o,

  cavebanpresto_ssbus_if.responder ssbus
);

  wire        device_state_idle;
  wire        device_state_read;
  wire        device_state_write;
  wire [7:0]  device_state_addr;
  wire [31:0] device_state_wdata;
  wire [31:0] device_state_rdata;
  wire        device_state_ack;
  wire        device_state_error;
  wire        device_restore_prime;
  wire        owner_idle;

  assign io_ss_idle_o =
    (owner_idle === 1'b1) &&
    (device_state_idle === 1'b1) &&
    (device_state_read === 1'b0) &&
    (device_state_write === 1'b0) &&
    (device_state_ack === 1'b0);

  CaveBanprestoOKIExact #(
    .INTERPOL(INTERPOL),
    .WRITE_HOLD_CYCLES(WRITE_HOLD_CYCLES)
  ) device (
    .clock                  (clock),
    .reset                  (reset),
    .io_cen_step            (io_cen_step),
    .io_cpu_wr              (io_cpu_wr),
    .io_cpu_din             (io_cpu_din),
    .io_stretch_cpu_wr      (io_stretch_cpu_wr),
    .io_wait_for_rom        (io_wait_for_rom),
    .io_cpu_dout            (io_cpu_dout),
    .io_rom_rd              (io_rom_rd),
    .io_rom_addr            (io_rom_addr),
    .io_rom_cache_addr      (io_rom_cache_addr),
    .io_rom_dout            (io_rom_dout),
    .io_rom_valid           (io_rom_valid),
    .io_audio_valid         (io_audio_valid),
    .io_audio_bits          (io_audio_bits),
    .io_audio_hold_bits     (io_audio_hold_bits),
    .io_bank_load           (io_bank_load),
    .io_bank_hi_din         (io_bank_hi_din),
    .io_bank_lo_din         (io_bank_lo_din),
    .io_bank_hi             (io_bank_hi),
    .io_bank_lo             (io_bank_lo),
    .io_state_hold          (io_ss_hold_i),
    .io_state_restore_prime (device_restore_prime),
    .io_state_idle          (device_state_idle),
    .io_state_read          (device_state_read),
    .io_state_write         (device_state_write),
    .io_state_addr          (device_state_addr),
    .io_state_wdata         (device_state_wdata),
    .io_state_rdata         (device_state_rdata),
    .io_state_ack           (device_state_ack),
    .io_state_error         (device_state_error)
  );

  CaveBanprestoOKIExactOwnerAdapter #(
    .OWNER_INDEX(OWNER_INDEX),
    .INTERPOL(INTERPOL),
    .WRITE_HOLD_CYCLES(WRITE_HOLD_CYCLES)
  ) owner_adapter (
    .clock                    (clock),
    .reset                    (reset),
    .io_cen_step              (io_cen_step),
    .io_stretch_cpu_wr        (io_stretch_cpu_wr),
    .io_wait_for_rom          (io_wait_for_rom),
    .io_ss_restore_enable_i   (io_ss_restore_enable_i),
    .restore_begin_i          (restore_begin_i),
    .restore_commit_i         (restore_commit_i),
    .device_state_idle_i      (device_state_idle),
    .device_state_read_o      (device_state_read),
    .device_state_write_o     (device_state_write),
    .device_state_addr_o      (device_state_addr),
    .device_state_wdata_o     (device_state_wdata),
    .device_state_rdata_i     (device_state_rdata),
    .device_state_ack_i       (device_state_ack),
    .device_state_error_i     (device_state_error),
    .device_restore_prime_o   (device_restore_prime),
    .validation_complete_o    (validation_complete_o),
    .validation_valid_o       (validation_valid_o),
    .write_complete_o         (write_complete_o),
    .write_valid_o            (write_valid_o),
    .restore_prime_o          (restore_prime_o),
    .restore_committed_o      (restore_committed_o),
    .terminal_fault_o         (terminal_fault_o),
    .owner_idle_o             (owner_idle),
    .ssbus                    (ssbus)
  );

endmodule

`default_nettype wire
