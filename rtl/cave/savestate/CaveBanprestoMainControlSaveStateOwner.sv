`default_nettype none

// CaveBanpresto save-state owner 3: Main-local CPU-domain control state.
//
// The exact 360-bit state image is stored in six canonical 64-bit words:
//   word 0 = state[63:0]
//   word 1 = state[127:64]
//   word 2 = state[191:128]
//   word 3 = state[255:192]
//   word 4 = state[319:256]
//   word 5 = {16'h4d33 ("M3"), profile[3:0], 4'b0000,
//             state[359:320]}
//
// State bit ownership:
//   [  2:  0] IRQ latches
//   [ 18:  3] CPU read-data history
//   [     19] DTACK history
//   [     20] Sailor Moon tile bank (profile 3 only)
//   [ 22: 21] pause edge/history state
//   [ 25: 23] EEPROM serial output pins
//   [ 28: 26] 68k bus-strobe history
//   [ 32: 29] vblank edge/history state
//   [ 56: 33] coin 1 pulse state
//   [ 80: 57] coin 2 pulse state
//   [109: 81] service pulse state
//   [153:110] Mazinger boot/watchdog state (profile 1 only)
//   [167:154] Metamoqester watchdog state (profile 4 only)
//   [263:168] Hotdog Storm open-bus gap cells (profile 0 only)
//   [359:264] Metamoqester open-bus gap cells (profile 4 only)
//
// Restore is transactional. Pass 1 retains all six words and validates the
// complete canonical image without writing live state. Pass 2 must repeat the
// same six words exactly and only stages them. A legal final commit advances
// to a separate one-cycle apply state, where restore_load_o can pulse exactly
// once while the Main domain remains held. Pass-1 errors are write-free and
// recoverable with a fresh restore_begin_i; pass-2/control/request-mutation
// errors are reset-only terminal.
module CaveBanprestoMainControlSaveStateOwner #(
	parameter [7:0] OWNER_INDEX = 8'd3,
	parameter [15:0] FORMAT_TAG = 16'h4d33
) (
	input  wire         clk_i,
	input  wire         reset_i,
	input  wire         state_enable_i,
	input  wire         restore_enable_i,
	input  wire         restore_begin_i,
	input  wire         restore_commit_i,
	input  wire         state_held_i,
	input  wire [3:0]   profile_i,
	input  wire [359:0] live_state_i,

	output wire         restore_load_o,
	output wire [359:0] restore_state_o,
	output logic        validation_complete_o,
	output logic        validation_valid_o,
	output logic        write_complete_o,
	output logic        write_valid_o,
	output logic        restore_committed_o,
	output logic        terminal_fault_o,
	output wire         owner_idle_o,

	cavebanpresto_ssbus_if.responder ssbus
);

	localparam [31:0] WORD_COUNT = 32'd6;
	localparam [1:0] WIDTH_CODE_64 = 2'd3;

	localparam [3:0] GAME_HOTDOGST = 4'h0;
	localparam [3:0] GAME_MAZINGER = 4'h1;
	localparam [3:0] GAME_AGALLET  = 4'h2;
	localparam [3:0] GAME_SAILORMN = 4'h3;
	localparam [3:0] GAME_METMQSTR = 4'h4;

	typedef enum logic [1:0] {
		StIdle        = 2'd0,
		StWaitRelease = 2'd1,
		StCommitApply = 2'd2
	} state_e;

	// Justification (reg-d): protocol phase state prevents duplicate command
	// acknowledgement and separates commit admission from architectural load.
	state_e state_q;

	// Justification (reg-a): the requester must hold the complete request
	// signature until release. Any post-ACK mutation is a reset-only fault.
	logic [63:0] held_req_data_q;
	logic [31:0] held_req_addr_q;
	logic  [7:0] held_req_select_q;
	logic  [3:0] held_req_command_q;

	// Justification (reg-d): pass-1 evidence and pass-2 staging are separate
	// full images so validation can never write live Main state.
	logic [63:0] validated_word_q [0:5];
	logic [63:0] staged_word_q [0:5];
	logic  [2:0] validation_next_addr_q;
	logic  [2:0] write_next_addr_q;
	logic        attempt_active_q;
	logic        validation_failed_q;
	logic        write_failed_q;
	logic        write_started_q;
	logic  [3:0] attempt_profile_q;

	logic [3:0] request_command;
	logic       request_selected;
	logic       request_command_legal;
	logic       request_addr_known;
	logic       request_data_known;
	logic       request_addr_in_range;
	logic       bus_quiet;
	logic       held_request_matches;
	logic       profile_known;
	logic       profile_supported;
	logic       safe_window;
	logic       restore_begin_safe;
	logic       restore_commit_safe;
	logic       commit_apply_safe;
	logic       pass2_continuity_fault;

	logic [359:0] canonical_live_state;
	logic         canonical_live_known;
	logic  [63:0] live_word;
	logic [359:0] validation_candidate_state;
	logic         validation_last_word_canonical;

	integer word_index;

	function automatic logic profile_is_supported(
		input logic [3:0] profile_value
	);
		begin
			unique case (profile_value)
				GAME_HOTDOGST,
				GAME_MAZINGER,
				GAME_AGALLET,
				GAME_SAILORMN,
				GAME_METMQSTR:
					profile_is_supported = 1'b1;
				default:
					profile_is_supported = 1'b0;
			endcase
		end
	endfunction

	function automatic logic [359:0] canonicalize_state(
		input logic [359:0] state_value,
		input logic   [3:0] profile_value
	);
		logic [359:0] result;
		begin
			result = state_value;
			unique case (profile_value)
				GAME_HOTDOGST: begin
					result[20] = 1'b0;
					result[167:110] = 58'd0;
					result[359:264] = 96'd0;
				end

				GAME_MAZINGER: begin
					result[20] = 1'b0;
					result[167:154] = 14'd0;
					result[359:168] = 192'd0;
				end

				GAME_AGALLET: begin
					result[20] = 1'b0;
					result[359:110] = 250'd0;
				end

				GAME_SAILORMN: begin
					result[359:110] = 250'd0;
				end

				GAME_METMQSTR: begin
					result[20] = 1'b0;
					result[153:110] = 44'd0;
					result[263:168] = 96'd0;
				end

				default:
					result = 360'd0;
			endcase
			canonicalize_state = result;
		end
	endfunction

	function automatic logic [63:0] image_word(
		input logic [359:0] state_value,
		input logic   [3:0] profile_value,
		input logic   [2:0] address_value
	);
		begin
			unique case (address_value)
				3'd0: image_word = state_value[63:0];
				3'd1: image_word = state_value[127:64];
				3'd2: image_word = state_value[191:128];
				3'd3: image_word = state_value[255:192];
				3'd4: image_word = state_value[319:256];
				3'd5: image_word = {
					FORMAT_TAG,
					profile_value,
					4'b0000,
					state_value[359:320]
				};
				default: image_word = 64'd0;
			endcase
		end
	endfunction

	always_comb begin
		request_command = {
			ssbus.req_query,
			ssbus.req_validate,
			ssbus.req_write,
			ssbus.req_read
		};
		request_selected =
			(ssbus.req_select === OWNER_INDEX) &&
			(request_command !== 4'b0000);
		request_command_legal =
			(request_command === 4'b0001) ||
			(request_command === 4'b0010) ||
			(request_command === 4'b0100) ||
			(request_command === 4'b1000);
		request_addr_known =
			((ssbus.req_addr == ssbus.req_addr) === 1'b1);
		request_data_known =
			((ssbus.req_data == ssbus.req_data) === 1'b1);
		request_addr_in_range =
			request_addr_known &&
			(ssbus.req_addr < WORD_COUNT);
		bus_quiet = request_command === 4'b0000;
		held_request_matches =
			(ssbus.req_data === held_req_data_q) &&
			(ssbus.req_addr === held_req_addr_q) &&
			(ssbus.req_select === held_req_select_q) &&
			(request_command === held_req_command_q);

		profile_known = ((profile_i == profile_i) === 1'b1);
		profile_supported = profile_is_supported(profile_i);
		safe_window =
			(state_enable_i === 1'b1) &&
			(state_held_i === 1'b1) &&
			profile_known &&
			profile_supported;

		canonical_live_state = canonicalize_state(live_state_i, profile_i);
		canonical_live_known =
			((canonical_live_state == canonical_live_state) === 1'b1);
		live_word = image_word(
			canonical_live_state,
			profile_i,
			ssbus.req_addr[2:0]
		);

		validation_candidate_state = {
			ssbus.req_data[39:0],
			validated_word_q[4],
			validated_word_q[3],
			validated_word_q[2],
			validated_word_q[1],
			validated_word_q[0]
		};
		validation_last_word_canonical =
			request_data_known &&
			(ssbus.req_data[63:48] === FORMAT_TAG) &&
			(ssbus.req_data[47:44] === attempt_profile_q) &&
			(ssbus.req_data[47:44] === profile_i) &&
			(ssbus.req_data[43:40] === 4'b0000) &&
			((validation_candidate_state ==
			  validation_candidate_state) === 1'b1) &&
			(validation_candidate_state ===
			 canonicalize_state(
				validation_candidate_state,
				attempt_profile_q
			 ));

		restore_begin_safe =
			(state_q === StIdle) &&
			bus_quiet &&
			safe_window &&
			(restore_commit_i === 1'b0) &&
			!terminal_fault_o &&
			(!attempt_active_q || validation_failed_q);

		restore_commit_safe =
			(state_q === StIdle) &&
			bus_quiet &&
			(restore_begin_i === 1'b0) &&
			attempt_active_q &&
			validation_complete_o &&
			validation_valid_o &&
			write_complete_o &&
			write_valid_o &&
			!validation_failed_q &&
			!write_failed_q &&
			!restore_committed_o &&
			!terminal_fault_o &&
			safe_window &&
			(restore_enable_i === 1'b1) &&
			(profile_i === attempt_profile_q);

		commit_apply_safe =
			(state_q === StCommitApply) &&
			bus_quiet &&
			(restore_begin_i === 1'b0) &&
			(restore_commit_i === 1'b0) &&
			attempt_active_q &&
			validation_complete_o &&
			validation_valid_o &&
			write_complete_o &&
			write_valid_o &&
			!validation_failed_q &&
			!write_failed_q &&
			!restore_committed_o &&
			!terminal_fault_o &&
			safe_window &&
			(restore_enable_i === 1'b1) &&
			(profile_i === attempt_profile_q);

		pass2_continuity_fault =
			attempt_active_q &&
			write_started_q &&
			((state_enable_i !== 1'b1) ||
			 (restore_enable_i !== 1'b1) ||
			 (state_held_i !== 1'b1) ||
			 (profile_i !== attempt_profile_q));
	end

	assign restore_state_o = {
		staged_word_q[5][39:0],
		staged_word_q[4],
		staged_word_q[3],
		staged_word_q[2],
		staged_word_q[1],
		staged_word_q[0]
	};
	assign restore_load_o =
		(reset_i === 1'b0) &&
		(commit_apply_safe === 1'b1);

	assign owner_idle_o =
		(state_q === StIdle) &&
		!terminal_fault_o &&
		bus_quiet &&
		(restore_begin_i === 1'b0) &&
		(restore_commit_i === 1'b0);

	always_ff @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= StIdle;
			held_req_data_q <= 64'd0;
			held_req_addr_q <= 32'd0;
			held_req_select_q <= 8'd0;
			held_req_command_q <= 4'd0;
			for (word_index = 0; word_index < 6; word_index = word_index + 1) begin
				validated_word_q[word_index] <= 64'd0;
				staged_word_q[word_index] <= 64'd0;
			end
			validation_next_addr_q <= 3'd0;
			write_next_addr_q <= 3'd0;
			attempt_active_q <= 1'b0;
			validation_failed_q <= 1'b0;
			write_failed_q <= 1'b0;
			write_started_q <= 1'b0;
			attempt_profile_q <= 4'd0;
			validation_complete_o <= 1'b0;
			validation_valid_o <= 1'b0;
			write_complete_o <= 1'b0;
			write_valid_o <= 1'b0;
			restore_committed_o <= 1'b0;
			terminal_fault_o <= 1'b0;
			ssbus.rsp_data <= 64'd0;
			ssbus.rsp_ack <= 1'b0;
			ssbus.rsp_error <= 1'b0;
		end
		else begin
			ssbus.rsp_data <= 64'd0;
			ssbus.rsp_ack <= 1'b0;
			ssbus.rsp_error <= 1'b0;

			if (state_q === StCommitApply) begin
				if (commit_apply_safe) begin
					state_q <= StIdle;
					attempt_active_q <= 1'b0;
					restore_committed_o <= 1'b1;
				end
				else begin
					state_q <= StIdle;
					validation_valid_o <= 1'b0;
					write_valid_o <= 1'b0;
					terminal_fault_o <= 1'b1;
				end
			end
			else if (restore_begin_i !== 1'b0) begin
				if ((restore_begin_i === 1'b1) &&
				    restore_begin_safe) begin
					state_q <= StIdle;
					held_req_data_q <= 64'd0;
					held_req_addr_q <= 32'd0;
					held_req_select_q <= 8'd0;
					held_req_command_q <= 4'd0;
					for (
						word_index = 0;
						word_index < 6;
						word_index = word_index + 1
					) begin
						validated_word_q[word_index] <= 64'd0;
						staged_word_q[word_index] <= 64'd0;
					end
					validation_next_addr_q <= 3'd0;
					write_next_addr_q <= 3'd0;
					attempt_active_q <= 1'b1;
					validation_failed_q <= 1'b0;
					write_failed_q <= 1'b0;
					write_started_q <= 1'b0;
					attempt_profile_q <= profile_i;
					validation_complete_o <= 1'b0;
					validation_valid_o <= 1'b0;
					write_complete_o <= 1'b0;
					write_valid_o <= 1'b0;
					restore_committed_o <= 1'b0;
				end
				else begin
					validation_valid_o <= 1'b0;
					write_valid_o <= 1'b0;
					terminal_fault_o <= 1'b1;
				end
			end
			else if (restore_commit_i !== 1'b0) begin
				if ((restore_commit_i === 1'b1) &&
				    restore_commit_safe) begin
					state_q <= StCommitApply;
				end
				else begin
					validation_valid_o <= 1'b0;
					write_valid_o <= 1'b0;
					terminal_fault_o <= 1'b1;
				end
			end
			else if (pass2_continuity_fault && bus_quiet) begin
				validation_valid_o <= 1'b0;
				write_valid_o <= 1'b0;
				terminal_fault_o <= 1'b1;
			end
			else begin
				unique case (state_q)
					StIdle: begin
						if (request_selected) begin
							held_req_data_q <= ssbus.req_data;
							held_req_addr_q <= ssbus.req_addr;
							held_req_select_q <= ssbus.req_select;
							held_req_command_q <= request_command;
							ssbus.rsp_ack <= 1'b1;
							state_q <= StWaitRelease;

							if (!request_command_legal ||
							    terminal_fault_o) begin
								ssbus.rsp_error <= 1'b1;
								validation_valid_o <= 1'b0;
								write_valid_o <= 1'b0;
								terminal_fault_o <= 1'b1;
							end
							else if (ssbus.req_query) begin
								if (request_addr_known &&
								    request_data_known) begin
									ssbus.rsp_data <=
										ssbus.query_descriptor(
											OWNER_INDEX,
											WORD_COUNT,
											WIDTH_CODE_64
										);
								end
								else begin
									ssbus.rsp_error <= 1'b1;
									validation_valid_o <= 1'b0;
									write_valid_o <= 1'b0;
									terminal_fault_o <= 1'b1;
								end
							end
							else if (ssbus.req_read) begin
								if (request_data_known &&
								    request_addr_in_range &&
								    safe_window &&
								    !attempt_active_q &&
								    canonical_live_known) begin
									ssbus.rsp_data <= live_word;
								end
								else begin
									ssbus.rsp_error <= 1'b1;
									validation_valid_o <= 1'b0;
									write_valid_o <= 1'b0;
									terminal_fault_o <= 1'b1;
								end
							end
							else if (ssbus.req_validate) begin
								if (!attempt_active_q ||
								    validation_failed_q ||
								    validation_complete_o ||
								    !safe_window ||
								    (profile_i !== attempt_profile_q) ||
								    !request_data_known ||
								    !request_addr_known ||
								    (ssbus.req_addr !==
								     {29'd0, validation_next_addr_q}) ||
								    ((validation_next_addr_q == 3'd5) &&
								     !validation_last_word_canonical)) begin
									ssbus.rsp_error <= 1'b1;
									validation_complete_o <= 1'b1;
									validation_valid_o <= 1'b0;
									validation_failed_q <= 1'b1;
								end
								else begin
									validated_word_q[
										validation_next_addr_q
									] <= ssbus.req_data;
									if (validation_next_addr_q == 3'd5) begin
										validation_next_addr_q <= 3'd6;
										validation_complete_o <= 1'b1;
										validation_valid_o <= 1'b1;
									end
									else begin
										validation_next_addr_q <=
											validation_next_addr_q + 3'd1;
									end
								end
							end
							else begin
								if (attempt_active_q &&
								    validation_complete_o &&
								    validation_valid_o &&
								    !validation_failed_q &&
								    !write_complete_o &&
								    !write_failed_q &&
								    safe_window &&
								    (restore_enable_i === 1'b1) &&
								    (profile_i === attempt_profile_q) &&
								    request_data_known &&
								    request_addr_known &&
								    (ssbus.req_addr ===
								     {29'd0, write_next_addr_q}) &&
								    (ssbus.req_data ===
								     validated_word_q[
										write_next_addr_q
								     ])) begin
									staged_word_q[
										write_next_addr_q
									] <= ssbus.req_data;
									write_started_q <= 1'b1;
									if (write_next_addr_q == 3'd5) begin
										write_next_addr_q <= 3'd6;
										write_complete_o <= 1'b1;
										write_valid_o <= 1'b1;
									end
									else begin
										write_next_addr_q <=
											write_next_addr_q + 3'd1;
									end
								end
								else begin
									ssbus.rsp_error <= 1'b1;
									validation_valid_o <= 1'b0;
									write_complete_o <= 1'b1;
									write_valid_o <= 1'b0;
									write_failed_q <= 1'b1;
									terminal_fault_o <= 1'b1;
								end
							end
						end
					end

					StWaitRelease: begin
						if (bus_quiet) begin
							state_q <= StIdle;
						end
						else if (!held_request_matches) begin
							validation_valid_o <= 1'b0;
							write_valid_o <= 1'b0;
							terminal_fault_o <= 1'b1;
						end
					end

					default: begin
						state_q <= StIdle;
						validation_valid_o <= 1'b0;
						write_valid_o <= 1'b0;
						terminal_fault_o <= 1'b1;
					end
				endcase
			end
		end
	end

endmodule

`default_nettype wire
