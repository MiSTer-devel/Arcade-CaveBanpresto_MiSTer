`default_nettype none

// CaveBanpresto version-1 save-state stream engine.
//
// This file is intentionally not connected to emu.sv yet.  SUPPORT_ENABLED
// defaults to zero so merely compiling the block cannot advertise incomplete
// save-state support.  Restore is strictly two-pass: pass 1 issues validate
// commands only, and no write command is possible until the complete footer,
// CRC, owner set, padding, and metadata result have passed.  A successful
// pass 1 then pauses at a write-free gate until the ordered external
// restore-enable sequence returns one known, single-cycle acknowledgment.
module CaveBanprestoSaveStateStream #(
	parameter integer SUPPORT_ENABLED = 0,
	parameter [31:0] DDR_TIMEOUT_CYCLES = 32'd1_000_000,
	parameter [31:0] OWNER_TIMEOUT_CYCLES = 32'd1_000_000,
	parameter [31:0] PASS2_ENABLE_TIMEOUT_CYCLES = 32'd1_000_000
) (
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        abort_i,
	input  wire        save_start_i,
	input  wire        restore_start_i,
	input  wire        pass2_enable_i,
	input  wire [31:0] slot_base_i,
	input  wire [31:0] slot_length_i,
	input  wire [47:0] runtime_support_i,

	// Owner zero asserts these only after all seven metadata words have been
	// seen exactly once and matched the current core identity.
	input  wire        metadata_validation_complete_i,
	input  wire        metadata_validation_valid_i,

	output logic       restore_begin_o,
	output wire        busy_o,
	output logic       done_o,
	output logic       success_o,
	output logic       format_error_o,
	output logic       pass1_complete_o,
	output logic       mutated_o,
	output logic       fatal_o,
	output logic [7:0] error_code_o,
	output wire  [1:0] restore_pass_o,
	output logic       restore_commit_o,
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
	output logic [7:0] debug_owner_failure_count_o,
	output logic [5:0] debug_owner_failure_state_o,
	output logic       debug_owner_failure_restore_o,
	output logic [1:0] debug_owner_failure_pass_o,
	output logic [2:0] debug_owner_failure_command_o,
	output logic [7:0] debug_owner_failure_select_o,
	output logic [31:0] debug_owner_failure_addr_o,
	output logic [3:0] debug_owner_failure_reason_o,
	output logic [15:0] debug_owner_failure_data_low_o,
`endif

	output wire        save_cmd_valid,
	input  wire        save_cmd_ready,
	output wire        save_cmd_write,
	output wire [31:0] save_cmd_byte_addr,
	output wire [63:0] save_cmd_wdata,
	output wire  [7:0] save_cmd_be,
	output wire  [7:0] save_cmd_burstcnt,
	input  wire        save_rsp_valid,
	input  wire [63:0] save_rsp_rdata,

	cavebanpresto_ssbus_if.requester ssbus
);

	localparam [63:0] STREAM_MAGIC = 64'h4342_5053_5354_3031;
	localparam [63:0] FOOTER_MAGIC = 64'h4342_5053_454e_3031;
	localparam [15:0] FORMAT_VERSION = 16'h0001;

	localparam [2:0] CMD_READ     = 3'd0;
	localparam [2:0] CMD_WRITE    = 3'd1;
	localparam [2:0] CMD_VALIDATE = 3'd2;
	localparam [2:0] CMD_QUERY    = 3'd3;

	localparam [7:0] ERR_NONE       = 8'h00;
	localparam [7:0] ERR_DISABLED   = 8'h01;
	localparam [7:0] ERR_ARGUMENT   = 8'h02;
	localparam [7:0] ERR_DDR        = 8'h03;
	localparam [7:0] ERR_OWNER      = 8'h04;
	localparam [7:0] ERR_FORMAT     = 8'h05;
	localparam [7:0] ERR_METADATA   = 8'h06;
	localparam [7:0] ERR_ABORTED    = 8'h07;
	localparam [7:0] ERR_INTERNAL   = 8'h08;
	localparam [7:0] ERR_ENABLE     = 8'h09;

	localparam integer PASS2_ENABLE_TIMEOUT_WIDTH =
		(PASS2_ENABLE_TIMEOUT_CYCLES <= 1)
			? 1 : $clog2(PASS2_ENABLE_TIMEOUT_CYCLES);

	typedef enum logic [5:0] {
		ST_IDLE,
		ST_DDR_LAUNCH,
		ST_DDR_WAIT,
		ST_OWNER_LAUNCH,
		ST_OWNER_WAIT,
		ST_CRC_LAUNCH,
		ST_CRC_WAIT,
		ST_FAIL_DRAIN,
		ST_FATAL,
		ST_HEADER_DONE,
		ST_EMIT_AFTER_DDR,
		ST_EMIT_AFTER_CRC,
		ST_CONSUME_AFTER_CRC,
		ST_SAVE_MAGIC_NEXT,
		ST_SAVE_SUPPORT_NEXT,
		ST_SAVE_FIND_OWNER,
		ST_SAVE_QUERY_DONE,
		ST_SAVE_DESCRIPTOR_DONE,
		ST_SAVE_ELEMENT_ISSUE,
		ST_SAVE_ELEMENT_DONE,
		ST_SAVE_PAYLOAD_WORD_DONE,
		ST_SAVE_FOOTER_DONE,
		ST_SAVE_CRC_DONE,
		ST_SAVE_SIZE_DONE,
		ST_SAVE_SIZE_FENCE_CHECK,
		ST_SAVE_CHANGE_DONE,
		ST_RESTORE_MAGIC_CHECK,
		ST_RESTORE_SUPPORT_READ,
		ST_RESTORE_SUPPORT_CHECK,
		ST_RESTORE_FIND_OWNER,
		ST_RESTORE_DESCRIPTOR_READ,
		ST_RESTORE_DESCRIPTOR_CHECK,
		ST_RESTORE_QUERY_DONE,
		ST_RESTORE_DESCRIPTOR_DONE,
		ST_RESTORE_PAYLOAD_READ,
		ST_RESTORE_PAYLOAD_READY,
		ST_RESTORE_ELEMENT_ISSUE,
		ST_RESTORE_ELEMENT_DONE,
		ST_RESTORE_FOOTER_CHECK,
		ST_RESTORE_CRC_READ,
		ST_RESTORE_CRC_CHECK,
		ST_RESTORE_WAIT_PASS2_ENABLE,
		ST_RESTORE_PASS2_HEADER_CHECK
	} state_t;

	// Justification (reg-a): protocol state retained between independently
	// acknowledged DDR, owner, and CRC operations.
	state_t state_q;
	state_t ddr_return_state_q;
	state_t owner_return_state_q;
	state_t crc_return_state_q;
	state_t emit_return_state_q;
	state_t consume_return_state_q;

	// Justification (reg-a): operation identity and strict restore phase.
	logic       operation_restore_q;
	logic [1:0] restore_pass_q;

	// Justification (reg-a): immutable operation inputs and checked slot bounds.
	logic [31:0] slot_base_q;
	logic [31:0] slot_length_q;
	logic [32:0] slot_end_q;
	logic [47:0] support_q;
	logic [63:0] header_q;
	logic [32:0] stream_start_q;
	logic [32:0] stream_addr_q;
	logic [32:0] stream_end_q;
	// Justification (reg-a): binds pass 2 to the exact image accepted by pass 1,
	// even if a concurrently changed image is independently well-formed.
	logic [63:0] validated_crc_q;
	// Justification (reg-a): bounds the externally acknowledged write-enable
	// gate.  No owner command or DDR request is launched while this advances.
	logic [PASS2_ENABLE_TIMEOUT_WIDTH-1:0] pass2_enable_timeout_q;

	// Justification (reg-a): serialization context shared by save and restore.
	logic [63:0] crc_q;
	logic  [5:0] owner_scan_q;
	logic [63:0] descriptor_q;
	// Justification (reg-b): predecodes the measured descriptor space bound
	// during the existing owner-query bubble.
	logic        descriptor_fits_q;
	logic  [1:0] owner_width_q;
	logic [31:0] owner_remaining_q;
	logic [31:0] owner_addr_q;
	logic  [2:0] lane_q;
	// Justification (reg-b): predecodes the measured lane/add word-boundary
	// branch before the owner transaction, removing it from pack/emit enables.
	logic        save_word_complete_q;
	logic [63:0] payload_word_q;
	logic [31:0] word_elements_q;

	// Justification (reg-a): staged save word is cleared at every DDR-word
	// boundary, guaranteeing deterministic zero padding.
	logic [63:0] pack_word_q;
	logic [31:0] final_size_words_q;

	// Justification (reg-a): registered helper requests remain stable for the
	// complete helper transaction.
	logic        ddr_write_q;
	logic [31:0] ddr_addr_q;
	logic [63:0] ddr_wdata_q;
	logic  [7:0] ddr_be_q;
	logic  [7:0] ddr_burstcnt_q;
	logic  [2:0] owner_command_q;
	logic  [7:0] owner_select_q;
	logic [31:0] owner_command_addr_q;
	logic [63:0] owner_command_data_q;
	logic [63:0] crc_input_q;
	logic [63:0] crc_word_q;

	// Justification (reg-a): captures helper results before the return state
	// consumes them on a later edge.
	logic [63:0] io_word_q;
	logic [63:0] io_crc_q;

	wire ddr_launch = state_q == ST_DDR_LAUNCH;
	wire owner_launch = state_q == ST_OWNER_LAUNCH;
	wire crc_launch = state_q == ST_CRC_LAUNCH;

	wire ddr_busy;
	wire ddr_done;
	wire ddr_error;
	wire [63:0] ddr_rdata;
	wire owner_busy;
	wire owner_done;
	wire owner_error;
	wire [63:0] owner_response_data;
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
	wire [3:0] owner_debug_error_reason;
`endif
	wire crc_busy;
	wire crc_done;
	wire [63:0] crc_result;
	wire final_detector_completed =
		(state_q == ST_DDR_WAIT) &&
		ddr_done && !ddr_error &&
		!operation_restore_q &&
		(ddr_return_state_q == ST_SAVE_CHANGE_DONE);
	wire pass2_enable_known =
		(pass2_enable_i === 1'b0) ||
		(pass2_enable_i === 1'b1);
	wire pass2_enable_asserted = pass2_enable_i === 1'b1;
	wire pass2_enable_waiting =
		state_q == ST_RESTORE_WAIT_PASS2_ENABLE;
	wire pass2_enable_protocol_fault =
		(state_q != ST_FATAL) &&
		(!pass2_enable_known ||
		 (pass2_enable_asserted && !pass2_enable_waiting));
	wire pass2_enable_timeout =
		(PASS2_ENABLE_TIMEOUT_CYCLES <= 1)
			? 1'b1
			: (pass2_enable_timeout_q >=
			   PASS2_ENABLE_TIMEOUT_CYCLES - 1'b1);

	wire [32:0] input_slot_end =
		{1'b0, slot_base_i} + {1'b0, slot_length_i};
	wire [33:0] header_stream_bytes =
		{2'd0, io_word_q[63:32]} << 2;
	wire [63:0] support_word = {FORMAT_VERSION, support_q};
	wire [63:0] queried_descriptor = io_word_q;
	wire [63:0] queried_descriptor_payload_bytes =
		{32'd0, queried_descriptor[31:0]} << queried_descriptor[33:32];
	wire [63:0] queried_descriptor_rounded_bytes =
		(queried_descriptor_payload_bytes + 64'd7) & ~64'd7;
	wire queried_descriptor_fits =
		({31'd0, stream_addr_q} + 64'd8 +
		 queried_descriptor_rounded_bytes + 64'd16) <=
		{31'd0, stream_end_q};

	function automatic [3:0] element_bytes;
		input [1:0] width_code;
		begin
			case (width_code)
				2'd0: element_bytes = 4'd1;
				2'd1: element_bytes = 4'd2;
				2'd2: element_bytes = 4'd4;
				default: element_bytes = 4'd8;
			endcase
		end
	endfunction

	function automatic [31:0] elements_per_word;
		input [1:0] width_code;
		begin
			case (width_code)
				2'd0: elements_per_word = 32'd8;
				2'd1: elements_per_word = 32'd4;
				2'd2: elements_per_word = 32'd2;
				default: elements_per_word = 32'd1;
			endcase
		end
	endfunction

	function automatic [63:0] element_mask;
		input [1:0] width_code;
		begin
			case (width_code)
				2'd0: element_mask = 64'h0000_0000_0000_00ff;
				2'd1: element_mask = 64'h0000_0000_0000_ffff;
				2'd2: element_mask = 64'h0000_0000_ffff_ffff;
				default: element_mask = 64'hffff_ffff_ffff_ffff;
			endcase
		end
	endfunction

	function automatic [63:0] low_byte_mask;
		input [3:0] byte_count;
		begin
			case (byte_count)
				4'd0: low_byte_mask = 64'h0000_0000_0000_0000;
				4'd1: low_byte_mask = 64'h0000_0000_0000_00ff;
				4'd2: low_byte_mask = 64'h0000_0000_0000_ffff;
				4'd3: low_byte_mask = 64'h0000_0000_00ff_ffff;
				4'd4: low_byte_mask = 64'h0000_0000_ffff_ffff;
				4'd5: low_byte_mask = 64'h0000_00ff_ffff_ffff;
				4'd6: low_byte_mask = 64'h0000_ffff_ffff_ffff;
				4'd7: low_byte_mask = 64'h00ff_ffff_ffff_ffff;
				default: low_byte_mask = 64'hffff_ffff_ffff_ffff;
			endcase
		end
	endfunction

	function automatic count_shift_overflow;
		input [31:0] element_count;
		input  [1:0] width_code;
		begin
			case (width_code)
				2'd0: count_shift_overflow = 1'b0;
				2'd1: count_shift_overflow = element_count[31];
				2'd2: count_shift_overflow = |element_count[31:30];
				default: count_shift_overflow = |element_count[31:29];
			endcase
		end
	endfunction

	wire [3:0] current_element_bytes = element_bytes(owner_width_q);
	wire [31:0] current_elements_per_word =
		elements_per_word(owner_width_q);
	wire [31:0] current_word_elements =
		(owner_remaining_q < current_elements_per_word)
			? owner_remaining_q : current_elements_per_word;
	wire [31:0] current_word_used_bytes =
		current_word_elements << owner_width_q;
	wire [5:0] lane_bit_shift = {lane_q, 3'b000};
	wire [4:0] lane_after_element =
		{1'b0, lane_q} + {1'b0, current_element_bytes};
	wire [63:0] save_pack_next =
		pack_word_q |
		((io_word_q & element_mask(owner_width_q)) << lane_bit_shift);
	wire [63:0] restore_element_data =
		(payload_word_q >> lane_bit_shift) &
		element_mask(owner_width_q);
	wire [32:0] save_stream_bytes_with_crc =
		stream_addr_q + 33'd8 - stream_start_q;
	wire [31:0] save_size_words =
		{2'd0, save_stream_bytes_with_crc[31:2]};
	wire descriptor_syntax_valid =
		(descriptor_q[63:56] == {2'd0, owner_scan_q}) &&
		(descriptor_q[55:34] == 22'd0);
	wire queried_descriptor_syntax_valid =
		(queried_descriptor[63:56] == {2'd0, owner_scan_q}) &&
		(queried_descriptor[55:34] == 22'd0);

	assign busy_o = state_q != ST_IDLE;
	assign restore_pass_o = restore_pass_q;

	CaveBanprestoSaveStateDdrBeat #(
		.TIMEOUT_CYCLES(DDR_TIMEOUT_CYCLES)
	) ddr_beat (
		.clk(clk_i),
		.reset(reset_i),
		.abort(abort_i),
		.launch(ddr_launch),
		.launch_write(ddr_write_q),
		.launch_byte_addr(ddr_addr_q),
		.launch_wdata(ddr_wdata_q),
		.launch_be(ddr_be_q),
		.launch_burstcnt(ddr_burstcnt_q),
		.busy(ddr_busy),
		.done(ddr_done),
		.error(ddr_error),
		.rdata(ddr_rdata),
		.cmd_valid(save_cmd_valid),
		.cmd_ready(save_cmd_ready),
		.cmd_write(save_cmd_write),
		.cmd_byte_addr(save_cmd_byte_addr),
		.cmd_wdata(save_cmd_wdata),
		.cmd_be(save_cmd_be),
		.cmd_burstcnt(save_cmd_burstcnt),
		.rsp_valid(save_rsp_valid),
		.rsp_rdata(save_rsp_rdata)
	);

	CaveBanprestoSaveStateOwnerCommand #(
		.TIMEOUT_CYCLES(OWNER_TIMEOUT_CYCLES)
	) owner_command (
		.clk(clk_i),
		.reset(reset_i),
		.abort(abort_i),
		.launch(owner_launch),
		.launch_command(owner_command_q),
		.launch_select(owner_select_q),
		.launch_addr(owner_command_addr_q),
		.launch_data(owner_command_data_q),
		.busy(owner_busy),
		.done(owner_done),
		.error(owner_error),
		.response_data(owner_response_data),
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
		.debug_error_reason(owner_debug_error_reason),
`endif
		.ssbus(ssbus)
	);

	CaveBanprestoCrc64Word crc_word (
		.clk(clk_i),
		.reset(reset_i),
		.abort(abort_i),
		.start(crc_launch),
		.crc_in(crc_input_q),
		.word_in(crc_word_q),
		.busy(crc_busy),
		.done(crc_done),
		.crc_out(crc_result)
	);

	// A semantic pass-2 failure is unrecoverable because earlier owners may
	// already have accepted writes.  The controller must keep the machine
	// frozen until reset.
	task automatic enter_format_failure;
		begin
			success_o <= 1'b0;
			format_error_o <= 1'b1;
			error_code_o <= ERR_FORMAT;
			if (operation_restore_q && (restore_pass_q == 2'd2)) begin
				fatal_o <= 1'b1;
				done_o <= 1'b1;
				state_q <= ST_FATAL;
			end else begin
				state_q <= ST_FAIL_DRAIN;
			end
		end
	endtask

	task automatic enter_metadata_failure;
		begin
			success_o <= 1'b0;
			format_error_o <= 1'b1;
			error_code_o <= ERR_METADATA;
			if (operation_restore_q && (restore_pass_q == 2'd2)) begin
				fatal_o <= 1'b1;
				done_o <= 1'b1;
				state_q <= ST_FATAL;
			end else begin
				state_q <= ST_FAIL_DRAIN;
			end
		end
	endtask

	// The external enable is the proof that every ordered destination-domain
	// restore-enable command has completed.  An ambiguous, unsolicited,
	// duplicate, or missing proof is therefore reset-only terminal even
	// though the stream itself has not yet issued a pass-2 owner write.
	task automatic enter_enable_failure;
		begin
			success_o <= 1'b0;
			format_error_o <= 1'b0;
			error_code_o <= ERR_ENABLE;
			fatal_o <= 1'b1;
			done_o <= 1'b1;
			state_q <= ST_FATAL;
		end
	endtask

	// These are retained serializer data, not protocol/control state.  Once an
	// abort or pass-2-enable fault is accepted, the control block below makes
	// their next values unobservable.  Updating them from present state in this
	// separate block preserves all visible cycles while keeping the terminal
	// priority cone out of their clock enables.
	always_ff @(posedge clk_i) begin
		if (reset_i) begin
			stream_end_q <= 33'd0;
			pack_word_q <= 64'd0;
		end else begin
			case (state_q)
				ST_IDLE: begin
					if ((save_start_i || restore_start_i) &&
					    SUPPORT_ENABLED &&
					    !(save_start_i && restore_start_i) &&
					    runtime_support_i[0] &&
					    (slot_base_i[2:0] == 3'd0) &&
					    (slot_length_i >= 32'd8) &&
					    (input_slot_end <= 33'h1_0000_0000)) begin
						stream_end_q <= 33'd0;
						pack_word_q <= 64'd0;
					end
				end

				ST_HEADER_DONE: begin
					if (operation_restore_q &&
					    (io_word_q[31:0] != 32'd0) &&
					    (io_word_q[63:32] >= 32'd8) &&
					    !io_word_q[32] &&
					    (header_stream_bytes <=
					     {2'd0, slot_length_q} - 34'd8) &&
					    ({1'b0, slot_base_q} + 34'd8 +
					     header_stream_bytes <= 34'h1_0000_0000)) begin
						stream_end_q <=
							{1'b0, slot_base_q} + 33'd8 +
							header_stream_bytes[32:0];
					end
				end

				ST_SAVE_QUERY_DONE: begin
					if (queried_descriptor_syntax_valid &&
					    !count_shift_overflow(
					    	queried_descriptor[31:0],
					    	queried_descriptor[33:32]) &&
					    ((stream_addr_q + 33'd8) <= slot_end_q)) begin
						pack_word_q <= 64'd0;
					end
				end

				ST_SAVE_ELEMENT_DONE: begin
					if (save_word_complete_q) begin
						if ((stream_addr_q + 33'd8) <= slot_end_q)
							pack_word_q <= 64'd0;
					end else begin
						pack_word_q <= save_pack_next;
					end
				end

				default: begin
				end
			endcase
		end
	end

	always_ff @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= ST_IDLE;
			ddr_return_state_q <= ST_IDLE;
			owner_return_state_q <= ST_IDLE;
			crc_return_state_q <= ST_IDLE;
			emit_return_state_q <= ST_IDLE;
			consume_return_state_q <= ST_IDLE;
			operation_restore_q <= 1'b0;
			restore_pass_q <= 2'd0;
			slot_base_q <= 32'd0;
			slot_length_q <= 32'd0;
			slot_end_q <= 33'd0;
			support_q <= 48'd0;
			header_q <= 64'd0;
			stream_start_q <= 33'd0;
			stream_addr_q <= 33'd0;
			validated_crc_q <= 64'd0;
			pass2_enable_timeout_q <=
				{PASS2_ENABLE_TIMEOUT_WIDTH{1'b0}};
			crc_q <= 64'd0;
			owner_scan_q <= 6'd0;
			descriptor_q <= 64'd0;
			descriptor_fits_q <= 1'b0;
			owner_width_q <= 2'd0;
			owner_remaining_q <= 32'd0;
			owner_addr_q <= 32'd0;
			lane_q <= 3'd0;
			save_word_complete_q <= 1'b0;
			payload_word_q <= 64'd0;
			word_elements_q <= 32'd0;
			final_size_words_q <= 32'd0;
			ddr_write_q <= 1'b0;
			ddr_addr_q <= 32'd0;
			ddr_wdata_q <= 64'd0;
			ddr_be_q <= 8'hff;
			ddr_burstcnt_q <= 8'd1;
			owner_command_q <= CMD_READ;
			owner_select_q <= 8'd0;
			owner_command_addr_q <= 32'd0;
			owner_command_data_q <= 64'd0;
			crc_input_q <= 64'd0;
			crc_word_q <= 64'd0;
			io_word_q <= 64'd0;
			io_crc_q <= 64'd0;
			restore_begin_o <= 1'b0;
			done_o <= 1'b0;
			success_o <= 1'b0;
			format_error_o <= 1'b0;
			pass1_complete_o <= 1'b0;
			mutated_o <= 1'b0;
			fatal_o <= 1'b0;
			error_code_o <= ERR_NONE;
			restore_commit_o <= 1'b0;
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
			debug_owner_failure_count_o <= 8'd0;
			debug_owner_failure_state_o <= 6'd0;
			debug_owner_failure_restore_o <= 1'b0;
			debug_owner_failure_pass_o <= 2'd0;
			debug_owner_failure_command_o <= 3'd0;
			debug_owner_failure_select_o <= 8'd0;
			debug_owner_failure_addr_o <= 32'd0;
			debug_owner_failure_reason_o <= 4'd0;
			debug_owner_failure_data_low_o <= 16'd0;
`endif
		end else begin
			done_o <= 1'b0;
			restore_begin_o <= 1'b0;
			restore_commit_o <= 1'b0;
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
			// Sticky same-clock flight record.  owner_done is the registered
			// terminal pulse, so the helper's reason and the stream's held
			// request payload are stable on this sampling edge.
			if (owner_done && owner_error) begin
				if (debug_owner_failure_count_o != 8'hff)
					debug_owner_failure_count_o <=
						debug_owner_failure_count_o + 1'b1;
				debug_owner_failure_state_o <= state_q;
				debug_owner_failure_restore_o <= operation_restore_q;
				debug_owner_failure_pass_o <= restore_pass_q;
				debug_owner_failure_command_o <= owner_command_q;
				debug_owner_failure_select_o <= owner_select_q;
				debug_owner_failure_addr_o <= owner_command_addr_q;
				debug_owner_failure_reason_o <= owner_debug_error_reason;
				debug_owner_failure_data_low_o <=
					owner_command_data_q[15:0];
			end
`endif

			if (pass2_enable_protocol_fault) begin
				enter_enable_failure();
			end else if (abort_i &&
			    (state_q != ST_IDLE) &&
			    (state_q != ST_FATAL) &&
			    (state_q != ST_FAIL_DRAIN) &&
			    (state_q != ST_SAVE_CHANGE_DONE) &&
			    !final_detector_completed) begin
				success_o <= 1'b0;
				error_code_o <= ERR_ABORTED;
				if (operation_restore_q &&
				    (restore_pass_q == 2'd2)) begin
					fatal_o <= 1'b1;
					done_o <= 1'b1;
					state_q <= ST_FATAL;
				end else begin
					state_q <= ST_FAIL_DRAIN;
				end
			end else begin
				case (state_q)
					ST_IDLE: begin
						if (save_start_i || restore_start_i) begin
							success_o <= 1'b0;
							format_error_o <= 1'b0;
							pass1_complete_o <= 1'b0;
							mutated_o <= 1'b0;
							error_code_o <= ERR_NONE;
							restore_pass_q <= restore_start_i
								? 2'd1 : 2'd0;
							operation_restore_q <= restore_start_i;

							if (!SUPPORT_ENABLED) begin
								done_o <= 1'b1;
								error_code_o <= ERR_DISABLED;
							end else if (save_start_i &&
							             restore_start_i) begin
								done_o <= 1'b1;
								error_code_o <= ERR_ARGUMENT;
							end else if (!runtime_support_i[0] ||
							             (slot_base_i[2:0] != 3'd0) ||
							             (slot_length_i < 32'd8) ||
							             (input_slot_end >
							              33'h1_0000_0000)) begin
								done_o <= 1'b1;
								error_code_o <= ERR_ARGUMENT;
							end else begin
								slot_base_q <= slot_base_i;
								slot_length_q <= slot_length_i;
								slot_end_q <= input_slot_end;
								support_q <= runtime_support_i;
								stream_start_q <=
									{1'b0, slot_base_i} + 33'd8;
								stream_addr_q <=
									{1'b0, slot_base_i} + 33'd8;
								validated_crc_q <= 64'd0;
								pass2_enable_timeout_q <=
									{PASS2_ENABLE_TIMEOUT_WIDTH{1'b0}};
								crc_q <= 64'd0;
								owner_scan_q <= 6'd0;
								lane_q <= 3'd0;
								if (restore_start_i)
									restore_begin_o <= 1'b1;

								ddr_write_q <= 1'b0;
								ddr_addr_q <= slot_base_i;
								ddr_wdata_q <= 64'd0;
								ddr_be_q <= 8'hff;
								ddr_burstcnt_q <= 8'd1;
								ddr_return_state_q <=
									ST_HEADER_DONE;
								state_q <= ST_DDR_LAUNCH;
							end
						end
					end

					ST_DDR_LAUNCH: begin
						state_q <= ST_DDR_WAIT;
					end

					ST_DDR_WAIT: begin
						if (ddr_done) begin
							if (ddr_error) begin
								success_o <= 1'b0;
								error_code_o <= ERR_DDR;
								if ((operation_restore_q &&
								     (restore_pass_q == 2'd2)) ||
								    ddr_busy) begin
									fatal_o <= 1'b1;
									done_o <= 1'b1;
									state_q <= ST_FATAL;
								end else begin
									state_q <= ST_FAIL_DRAIN;
								end
							end else begin
								io_word_q <= ddr_rdata;
								state_q <= ddr_return_state_q;
							end
						end
					end

					ST_OWNER_LAUNCH: begin
						state_q <= ST_OWNER_WAIT;
					end

					ST_OWNER_WAIT: begin
						if (owner_done) begin
							if (owner_error) begin
								success_o <= 1'b0;
								error_code_o <= ERR_OWNER;
								if (operation_restore_q &&
								    (restore_pass_q == 2'd2)) begin
									fatal_o <= 1'b1;
									done_o <= 1'b1;
									state_q <= ST_FATAL;
								end else begin
									state_q <= ST_FAIL_DRAIN;
								end
							end else begin
								io_word_q <= owner_response_data;
								state_q <= owner_return_state_q;
							end
						end
					end

					ST_CRC_LAUNCH: begin
						state_q <= ST_CRC_WAIT;
					end

					ST_CRC_WAIT: begin
						if (crc_done) begin
							io_crc_q <= crc_result;
							state_q <= crc_return_state_q;
						end
					end

					ST_FAIL_DRAIN: begin
						if (ddr_done && ddr_error && ddr_busy) begin
							// An accepted read has timed out while draining.
							// Returning idle would let its stale response be
							// consumed by a later operation.
							error_code_o <= ERR_DDR;
							fatal_o <= 1'b1;
							done_o <= 1'b1;
							state_q <= ST_FATAL;
						end else if (!ddr_busy &&
						             !owner_busy && !crc_busy) begin
							done_o <= 1'b1;
							success_o <= 1'b0;
							state_q <= ST_IDLE;
						end
					end

					ST_FATAL: begin
						// Deliberately frozen. reset_i is the only recovery.
						state_q <= ST_FATAL;
					end

					ST_HEADER_DONE: begin
						header_q <= io_word_q;
						if (operation_restore_q) begin
							if ((io_word_q[31:0] == 32'd0) ||
							    (io_word_q[63:32] < 32'd8) ||
							    io_word_q[32] ||
							    (header_stream_bytes >
							     {2'd0, slot_length_q} - 34'd8) ||
							    ({1'b0, slot_base_q} + 34'd8 +
							     header_stream_bytes >
							     34'h1_0000_0000)) begin
								enter_format_failure();
							end else begin
								stream_addr_q <= stream_start_q;
								crc_q <= 64'd0;
								owner_scan_q <= 6'd0;
								ddr_write_q <= 1'b0;
								ddr_addr_q <= stream_start_q[31:0];
								ddr_wdata_q <= 64'd0;
								ddr_be_q <= 8'hff;
								ddr_burstcnt_q <= 8'd1;
								ddr_return_state_q <=
									ST_RESTORE_MAGIC_CHECK;
								state_q <= ST_DDR_LAUNCH;
							end
						end else begin
							if ((stream_addr_q + 33'd8) >
							    slot_end_q) begin
								enter_format_failure();
							end else begin
								emit_return_state_q <=
									ST_SAVE_MAGIC_NEXT;
								ddr_write_q <= 1'b1;
								ddr_addr_q <=
									stream_addr_q[31:0];
								ddr_wdata_q <= STREAM_MAGIC;
								ddr_be_q <= 8'hff;
								ddr_burstcnt_q <= 8'd1;
								ddr_return_state_q <=
									ST_EMIT_AFTER_DDR;
								state_q <= ST_DDR_LAUNCH;
							end
						end
					end

					// A save emission writes first, then folds the exact word
					// held in the DDR request register into the CRC, then
					// advances the byte address.
					ST_EMIT_AFTER_DDR: begin
						crc_input_q <= crc_q;
						crc_word_q <= ddr_wdata_q;
						crc_return_state_q <= ST_EMIT_AFTER_CRC;
						state_q <= ST_CRC_LAUNCH;
					end

					ST_EMIT_AFTER_CRC: begin
						crc_q <= io_crc_q;
						stream_addr_q <= stream_addr_q + 33'd8;
						state_q <= emit_return_state_q;
					end

					// A restore consumption has already checked the word's
					// semantics. Fold it into the CRC before advancing.
					ST_CONSUME_AFTER_CRC: begin
						crc_q <= io_crc_q;
						stream_addr_q <= stream_addr_q + 33'd8;
						state_q <= consume_return_state_q;
					end

					ST_SAVE_MAGIC_NEXT: begin
						if ((stream_addr_q + 33'd8) > slot_end_q) begin
							enter_format_failure();
						end else begin
							emit_return_state_q <=
								ST_SAVE_SUPPORT_NEXT;
							ddr_write_q <= 1'b1;
							ddr_addr_q <= stream_addr_q[31:0];
							ddr_wdata_q <= support_word;
							ddr_be_q <= 8'hff;
							ddr_burstcnt_q <= 8'd1;
							ddr_return_state_q <= ST_EMIT_AFTER_DDR;
							state_q <= ST_DDR_LAUNCH;
						end
					end

					ST_SAVE_SUPPORT_NEXT: begin
						owner_scan_q <= 6'd0;
						state_q <= ST_SAVE_FIND_OWNER;
					end

					ST_SAVE_FIND_OWNER: begin
						if (owner_scan_q == 6'd48) begin
							if ((stream_addr_q + 33'd16) >
							    slot_end_q) begin
								enter_format_failure();
							end else begin
								emit_return_state_q <=
									ST_SAVE_FOOTER_DONE;
								ddr_write_q <= 1'b1;
								ddr_addr_q <=
									stream_addr_q[31:0];
								ddr_wdata_q <= FOOTER_MAGIC;
								ddr_be_q <= 8'hff;
								ddr_burstcnt_q <= 8'd1;
								ddr_return_state_q <=
									ST_EMIT_AFTER_DDR;
								state_q <= ST_DDR_LAUNCH;
							end
						end else if (support_q[owner_scan_q]) begin
							owner_command_q <= CMD_QUERY;
							owner_select_q <= {2'd0, owner_scan_q};
							owner_command_addr_q <= 32'd0;
							owner_command_data_q <= 64'd0;
							owner_return_state_q <=
								ST_SAVE_QUERY_DONE;
							state_q <= ST_OWNER_LAUNCH;
						end else begin
							owner_scan_q <= owner_scan_q + 6'd1;
						end
					end

					ST_SAVE_QUERY_DONE: begin
						if (!queried_descriptor_syntax_valid ||
						    count_shift_overflow(
						    	queried_descriptor[31:0],
						    	queried_descriptor[33:32]) ||
						    ((stream_addr_q + 33'd8) >
						     slot_end_q)) begin
							enter_format_failure();
						end else begin
							descriptor_q <= queried_descriptor;
							owner_width_q <=
								queried_descriptor[33:32];
							owner_remaining_q <=
								queried_descriptor[31:0];
							owner_addr_q <= 32'd0;
							lane_q <= 3'd0;
							emit_return_state_q <=
								ST_SAVE_DESCRIPTOR_DONE;
							ddr_write_q <= 1'b1;
							ddr_addr_q <= stream_addr_q[31:0];
							ddr_wdata_q <= queried_descriptor;
							ddr_be_q <= 8'hff;
							ddr_burstcnt_q <= 8'd1;
							ddr_return_state_q <=
								ST_EMIT_AFTER_DDR;
							state_q <= ST_DDR_LAUNCH;
						end
					end

					ST_SAVE_DESCRIPTOR_DONE: begin
						if (owner_remaining_q == 32'd0) begin
							owner_scan_q <= owner_scan_q + 6'd1;
							state_q <= ST_SAVE_FIND_OWNER;
						end else begin
							state_q <= ST_SAVE_ELEMENT_ISSUE;
						end
					end

					ST_SAVE_ELEMENT_ISSUE: begin
						save_word_complete_q <=
							(lane_after_element == 5'd8) ||
							(owner_remaining_q == 32'd1);
						owner_command_q <= CMD_READ;
						owner_select_q <= {2'd0, owner_scan_q};
						owner_command_addr_q <= owner_addr_q;
						owner_command_data_q <= 64'd0;
						owner_return_state_q <=
							ST_SAVE_ELEMENT_DONE;
						state_q <= ST_OWNER_LAUNCH;
					end

					ST_SAVE_ELEMENT_DONE: begin
						owner_remaining_q <=
							owner_remaining_q - 32'd1;
						owner_addr_q <= owner_addr_q + 32'd1;
						if (save_word_complete_q) begin
							if ((stream_addr_q + 33'd8) >
							    slot_end_q) begin
								enter_format_failure();
							end else begin
								lane_q <= 3'd0;
								emit_return_state_q <=
									ST_SAVE_PAYLOAD_WORD_DONE;
								ddr_write_q <= 1'b1;
								ddr_addr_q <=
									stream_addr_q[31:0];
								ddr_wdata_q <= save_pack_next;
								ddr_be_q <= 8'hff;
								ddr_burstcnt_q <= 8'd1;
								ddr_return_state_q <=
									ST_EMIT_AFTER_DDR;
								state_q <= ST_DDR_LAUNCH;
							end
						end else begin
							lane_q <= lane_after_element[2:0];
							state_q <= ST_SAVE_ELEMENT_ISSUE;
						end
					end

					ST_SAVE_PAYLOAD_WORD_DONE: begin
						if (owner_remaining_q == 32'd0) begin
							owner_scan_q <= owner_scan_q + 6'd1;
							state_q <= ST_SAVE_FIND_OWNER;
						end else begin
							state_q <= ST_SAVE_ELEMENT_ISSUE;
						end
					end

					ST_SAVE_FOOTER_DONE: begin
						// The CRC word is excluded from the CRC itself.
						final_size_words_q <= save_size_words;
						ddr_write_q <= 1'b1;
						ddr_addr_q <= stream_addr_q[31:0];
						ddr_wdata_q <= crc_q;
						ddr_be_q <= 8'hff;
						ddr_burstcnt_q <= 8'd1;
						ddr_return_state_q <= ST_SAVE_CRC_DONE;
						state_q <= ST_DDR_LAUNCH;
					end

					ST_SAVE_CRC_DONE: begin
						stream_addr_q <= stream_addr_q + 33'd8;
						ddr_write_q <= 1'b1;
						ddr_addr_q <= slot_base_q;
						ddr_wdata_q <=
							{final_size_words_q, 32'd0};
						ddr_be_q <= 8'hf0;
						ddr_burstcnt_q <= 8'd1;
						ddr_return_state_q <= ST_SAVE_SIZE_DONE;
						state_q <= ST_DDR_LAUNCH;
					end

					ST_SAVE_SIZE_DONE: begin
						// A readback is the ordering fence between all stream
						// and size writes and the externally visible detector.
						ddr_write_q <= 1'b0;
						ddr_addr_q <= slot_base_q;
						ddr_wdata_q <= 64'd0;
						ddr_be_q <= 8'hff;
						ddr_burstcnt_q <= 8'd1;
						ddr_return_state_q <=
							ST_SAVE_SIZE_FENCE_CHECK;
						state_q <= ST_DDR_LAUNCH;
					end

					ST_SAVE_SIZE_FENCE_CHECK: begin
						if (io_word_q[63:32] !=
						    final_size_words_q) begin
							success_o <= 1'b0;
							error_code_o <= ERR_DDR;
							state_q <= ST_FAIL_DRAIN;
						end else begin
						ddr_write_q <= 1'b1;
						ddr_addr_q <= slot_base_q;
						ddr_wdata_q <= {
							32'd0,
							(&header_q[31:0])
								? 32'd1
								: header_q[31:0] + 32'd1
						};
						ddr_be_q <= 8'h0f;
						ddr_burstcnt_q <= 8'd1;
						ddr_return_state_q <= ST_SAVE_CHANGE_DONE;
						state_q <= ST_DDR_LAUNCH;
						end
					end

					ST_SAVE_CHANGE_DONE: begin
						success_o <= 1'b1;
						error_code_o <= ERR_NONE;
						done_o <= 1'b1;
						state_q <= ST_IDLE;
					end

					ST_RESTORE_MAGIC_CHECK: begin
						if (io_word_q != STREAM_MAGIC) begin
							enter_format_failure();
						end else begin
							crc_input_q <= crc_q;
							crc_word_q <= io_word_q;
							crc_return_state_q <=
								ST_CONSUME_AFTER_CRC;
							consume_return_state_q <=
								ST_RESTORE_SUPPORT_READ;
							state_q <= ST_CRC_LAUNCH;
						end
					end

					ST_RESTORE_SUPPORT_READ: begin
						ddr_write_q <= 1'b0;
						ddr_addr_q <= stream_addr_q[31:0];
						ddr_wdata_q <= 64'd0;
						ddr_be_q <= 8'hff;
						ddr_burstcnt_q <= 8'd1;
						ddr_return_state_q <=
							ST_RESTORE_SUPPORT_CHECK;
						state_q <= ST_DDR_LAUNCH;
					end

					ST_RESTORE_SUPPORT_CHECK: begin
						if (io_word_q != support_word) begin
							enter_format_failure();
						end else begin
							owner_scan_q <= 6'd0;
							crc_input_q <= crc_q;
							crc_word_q <= io_word_q;
							crc_return_state_q <=
								ST_CONSUME_AFTER_CRC;
							consume_return_state_q <=
								ST_RESTORE_FIND_OWNER;
							state_q <= ST_CRC_LAUNCH;
						end
					end

					ST_RESTORE_FIND_OWNER: begin
						if (owner_scan_q == 6'd48) begin
							if ((stream_addr_q + 33'd16) >
							    stream_end_q) begin
								enter_format_failure();
							end else begin
								ddr_write_q <= 1'b0;
								ddr_addr_q <=
									stream_addr_q[31:0];
								ddr_wdata_q <= 64'd0;
								ddr_be_q <= 8'hff;
								ddr_burstcnt_q <= 8'd1;
								ddr_return_state_q <=
									ST_RESTORE_FOOTER_CHECK;
								state_q <= ST_DDR_LAUNCH;
							end
						end else if (support_q[owner_scan_q]) begin
							state_q <=
								ST_RESTORE_DESCRIPTOR_READ;
						end else begin
							owner_scan_q <= owner_scan_q + 6'd1;
						end
					end

					ST_RESTORE_DESCRIPTOR_READ: begin
						if ((stream_addr_q + 33'd24) >
						    stream_end_q) begin
							enter_format_failure();
						end else begin
							ddr_write_q <= 1'b0;
							ddr_addr_q <= stream_addr_q[31:0];
							ddr_wdata_q <= 64'd0;
							ddr_be_q <= 8'hff;
							ddr_burstcnt_q <= 8'd1;
							ddr_return_state_q <=
								ST_RESTORE_DESCRIPTOR_CHECK;
							state_q <= ST_DDR_LAUNCH;
						end
					end

					ST_RESTORE_DESCRIPTOR_CHECK: begin
						descriptor_q <= io_word_q;
						descriptor_fits_q <=
							queried_descriptor_fits;
						if ((io_word_q[63:56] !=
						     {2'd0, owner_scan_q}) ||
						    (io_word_q[55:34] != 22'd0) ||
						    count_shift_overflow(
						    	io_word_q[31:0],
						    	io_word_q[33:32])) begin
							enter_format_failure();
						end else begin
							owner_command_q <= CMD_QUERY;
							owner_select_q <= {2'd0, owner_scan_q};
							owner_command_addr_q <= 32'd0;
							owner_command_data_q <= 64'd0;
							owner_return_state_q <=
								ST_RESTORE_QUERY_DONE;
							state_q <= ST_OWNER_LAUNCH;
						end
					end

					ST_RESTORE_QUERY_DONE: begin
						if (!descriptor_syntax_valid ||
						    (io_word_q != descriptor_q) ||
						    !descriptor_fits_q) begin
							enter_format_failure();
						end else begin
							owner_width_q <= descriptor_q[33:32];
							owner_remaining_q <=
								descriptor_q[31:0];
							owner_addr_q <= 32'd0;
							lane_q <= 3'd0;
							crc_input_q <= crc_q;
							crc_word_q <= descriptor_q;
							crc_return_state_q <=
								ST_CONSUME_AFTER_CRC;
							consume_return_state_q <=
								ST_RESTORE_DESCRIPTOR_DONE;
							state_q <= ST_CRC_LAUNCH;
						end
					end

					ST_RESTORE_DESCRIPTOR_DONE: begin
						if (owner_remaining_q == 32'd0) begin
							owner_scan_q <= owner_scan_q + 6'd1;
							state_q <= ST_RESTORE_FIND_OWNER;
						end else begin
							state_q <= ST_RESTORE_PAYLOAD_READ;
						end
					end

					ST_RESTORE_PAYLOAD_READ: begin
						if ((stream_addr_q + 33'd24) >
						    stream_end_q) begin
							enter_format_failure();
						end else begin
							ddr_write_q <= 1'b0;
							ddr_addr_q <= stream_addr_q[31:0];
							ddr_wdata_q <= 64'd0;
							ddr_be_q <= 8'hff;
							ddr_burstcnt_q <= 8'd1;
							ddr_return_state_q <=
								ST_RESTORE_PAYLOAD_READY;
							state_q <= ST_DDR_LAUNCH;
						end
					end

					ST_RESTORE_PAYLOAD_READY: begin
						payload_word_q <= io_word_q;
						word_elements_q <= current_word_elements;
						lane_q <= 3'd0;
						if ((io_word_q &
						     ~low_byte_mask(
						     	current_word_used_bytes[3:0]))
						    != 64'd0) begin
							enter_format_failure();
						end else begin
							crc_input_q <= crc_q;
							crc_word_q <= io_word_q;
							crc_return_state_q <=
								ST_CONSUME_AFTER_CRC;
							consume_return_state_q <=
								ST_RESTORE_ELEMENT_ISSUE;
							state_q <= ST_CRC_LAUNCH;
						end
					end

					ST_RESTORE_ELEMENT_ISSUE: begin
						owner_command_q <=
							(restore_pass_q == 2'd1)
								? CMD_VALIDATE : CMD_WRITE;
						owner_select_q <= {2'd0, owner_scan_q};
						owner_command_addr_q <= owner_addr_q;
						owner_command_data_q <=
							restore_element_data;
						owner_return_state_q <=
							ST_RESTORE_ELEMENT_DONE;
						state_q <= ST_OWNER_LAUNCH;
					end

					ST_RESTORE_ELEMENT_DONE: begin
						if (restore_pass_q == 2'd2)
							mutated_o <= 1'b1;
						owner_remaining_q <=
							owner_remaining_q - 32'd1;
						owner_addr_q <= owner_addr_q + 32'd1;
						word_elements_q <= word_elements_q - 32'd1;
						if (word_elements_q == 32'd1) begin
							lane_q <= 3'd0;
							if (owner_remaining_q == 32'd1) begin
								owner_scan_q <=
									owner_scan_q + 6'd1;
								state_q <=
									ST_RESTORE_FIND_OWNER;
							end else begin
								state_q <=
									ST_RESTORE_PAYLOAD_READ;
							end
						end else begin
							lane_q <= lane_q +
								current_element_bytes[2:0];
							state_q <=
								ST_RESTORE_ELEMENT_ISSUE;
						end
					end

					ST_RESTORE_FOOTER_CHECK: begin
						if (io_word_q != FOOTER_MAGIC) begin
							enter_format_failure();
						end else begin
							crc_input_q <= crc_q;
							crc_word_q <= io_word_q;
							crc_return_state_q <=
								ST_CONSUME_AFTER_CRC;
							consume_return_state_q <=
								ST_RESTORE_CRC_READ;
							state_q <= ST_CRC_LAUNCH;
						end
					end

					ST_RESTORE_CRC_READ: begin
						if ((stream_addr_q + 33'd8) >
						    stream_end_q) begin
							enter_format_failure();
						end else begin
							ddr_write_q <= 1'b0;
							ddr_addr_q <= stream_addr_q[31:0];
							ddr_wdata_q <= 64'd0;
							ddr_be_q <= 8'hff;
							ddr_burstcnt_q <= 8'd1;
							ddr_return_state_q <=
								ST_RESTORE_CRC_CHECK;
							state_q <= ST_DDR_LAUNCH;
						end
					end

					ST_RESTORE_CRC_CHECK: begin
						if ((io_word_q != crc_q) ||
						    ((restore_pass_q == 2'd2) &&
						     (io_word_q != validated_crc_q)) ||
						    ((stream_addr_q + 33'd8) !=
						     stream_end_q)) begin
							enter_format_failure();
						end else if ((restore_pass_q == 2'd1) &&
						             (!metadata_validation_complete_i ||
						              !metadata_validation_valid_i)) begin
							enter_metadata_failure();
						end else if (restore_pass_q == 2'd1) begin
							pass1_complete_o <= 1'b1;
							validated_crc_q <= io_word_q;
							pass2_enable_timeout_q <=
								{PASS2_ENABLE_TIMEOUT_WIDTH{1'b0}};
							state_q <=
								ST_RESTORE_WAIT_PASS2_ENABLE;
						end else begin
							success_o <= 1'b1;
							error_code_o <= ERR_NONE;
							restore_commit_o <= 1'b1;
							done_o <= 1'b1;
							state_q <= ST_IDLE;
						end
					end

					ST_RESTORE_WAIT_PASS2_ENABLE: begin
						// Pass 1 is fully accepted, but restore_pass_q remains
						// one and no DDR/owner helper is launched until the
						// ordered external application proof arrives.
						if (pass2_enable_asserted) begin
							pass1_complete_o <= 1'b0;
							restore_pass_q <= 2'd2;
							pass2_enable_timeout_q <=
								{PASS2_ENABLE_TIMEOUT_WIDTH{1'b0}};
							crc_q <= 64'd0;
							owner_scan_q <= 6'd0;
							stream_addr_q <= stream_start_q;
							ddr_write_q <= 1'b0;
							ddr_addr_q <= slot_base_q;
							ddr_wdata_q <= 64'd0;
							ddr_be_q <= 8'hff;
							ddr_burstcnt_q <= 8'd1;
							ddr_return_state_q <=
								ST_RESTORE_PASS2_HEADER_CHECK;
							state_q <= ST_DDR_LAUNCH;
						end else if (pass2_enable_timeout) begin
							enter_enable_failure();
						end else begin
							pass2_enable_timeout_q <=
								pass2_enable_timeout_q + 1'b1;
						end
					end

					ST_RESTORE_PASS2_HEADER_CHECK: begin
						if (io_word_q != header_q) begin
							enter_format_failure();
						end else begin
							stream_addr_q <= stream_start_q;
							ddr_write_q <= 1'b0;
							ddr_addr_q <= stream_start_q[31:0];
							ddr_wdata_q <= 64'd0;
							ddr_be_q <= 8'hff;
							ddr_burstcnt_q <= 8'd1;
							ddr_return_state_q <=
								ST_RESTORE_MAGIC_CHECK;
							state_q <= ST_DDR_LAUNCH;
						end
					end

					default: begin
						success_o <= 1'b0;
						fatal_o <= 1'b1;
						error_code_o <= ERR_INTERNAL;
						done_o <= 1'b1;
						state_q <= ST_FATAL;
					end
				endcase
			end
		end
	end

endmodule

`default_nettype wire
