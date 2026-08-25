`default_nettype none

// CaveBanpresto save-state owner 22: the exact 48 live bits in EEPROM.sv.
//
// One canonical 64-bit element:
//   {16'h4545 ("EE"),
//    state[2:0], counter[16:0], address[5:0], data[15:0], opcode[1:0],
//    serial_out, write_all, write_enable, previous_sck}
//
// EEPROM.sv drains STATE_READ, STATE_READ_WAIT, and STATE_WRITE before
// device_idle_i can assert.  Consequently those three transient states are
// non-canonical in a saved word; every other serial state remains exactly
// restorable.
//
// Restore is strictly transactional:
// - pass 1 validates and retains one canonical word without changing live
//   EEPROM state;
// - pass 2 must present the same word and only stages it;
// - exactly one legal restore_commit_i edge emits restore_load_o;
// - malformed pass 1 is write-free and recoverable through a fresh
//   restore_begin_i;
// - every pass-2/control/post-mutation inconsistency is reset-only terminal.
module CaveBanprestoEEPROMStatePort #(
	parameter [7:0] OWNER_INDEX = 8'd22,
	parameter [15:0] FORMAT_TAG = 16'h4545
) (
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        state_enable_i,
	input  wire        restore_enable_i,
	input  wire        restore_begin_i,
	input  wire        restore_commit_i,
	input  wire        device_idle_i,
	input  wire [47:0] live_state_i,

	output wire        restore_load_o,
	output wire [47:0] restore_state_o,
	output logic       validation_complete_o,
	output logic       validation_valid_o,
	output logic       write_complete_o,
	output logic       write_valid_o,
	output logic       restore_committed_o,
	output logic       terminal_fault_o,
	output wire        owner_idle_o,

	cavebanpresto_ssbus_if.responder ssbus
);

	localparam [31:0] WORD_COUNT = 32'd1;
	localparam [1:0] WIDTH_CODE_64 = 2'd3;

	localparam [2:0] EEPROM_STATE_IDLE = 3'd0;
	localparam [2:0] EEPROM_STATE_START = 3'd1;
	localparam [2:0] EEPROM_STATE_COMMAND = 3'd2;
	localparam [2:0] EEPROM_STATE_SHIFT_IN = 3'd6;
	localparam [2:0] EEPROM_STATE_SHIFT_OUT = 3'd7;

	typedef enum logic [0:0] {
		StIdle        = 1'b0,
		StWaitRelease = 1'b1
	} state_e;

	// Justification (reg-d): one-bit protocol state prevents a held requester
	// from being acknowledged more than once.
	state_e state_q;

	// Justification (reg-a): a requester must hold every command and payload
	// bit until release.  These registers make any mutation after ACK a
	// reset-only protocol fault.
	logic [63:0] held_req_data_q;
	logic [31:0] held_req_addr_q;
	logic  [7:0] held_req_select_q;
	logic  [3:0] held_req_command_q;

	// Justification (reg-d): pass-1 evidence and pass-2 staging are distinct
	// so neither pass can mutate the live EEPROM before global commit.
	logic [63:0] validated_word_q;
	logic [63:0] staged_word_q;
	logic        attempt_active_q;
	logic        validation_failed_q;
	logic        write_failed_q;

	logic [3:0] request_command;
	logic       request_selected;
	logic       request_command_legal;
	logic       request_address_valid;
	logic       request_payload_known;
	logic       request_state_canonical;
	logic       request_word_canonical;
	logic       live_state_known;
	logic       live_state_canonical;
	logic       safe_window;
	logic       bus_quiet;
	logic       held_request_matches;
	logic       restore_begin_safe;
	logic       validation_accept;
	logic       write_accept;
	logic       commit_apply_safe;
	logic [63:0] live_word;

	function automatic logic eeprom_state_canonical(
		input logic [2:0] state_value
	);
		begin
			unique case (state_value)
				EEPROM_STATE_IDLE,
				EEPROM_STATE_START,
				EEPROM_STATE_COMMAND,
				EEPROM_STATE_SHIFT_IN,
				EEPROM_STATE_SHIFT_OUT:
					eeprom_state_canonical = 1'b1;
				default:
					eeprom_state_canonical = 1'b0;
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
		(request_command === 4'b0001) ||
		(request_command === 4'b0010) ||
		(request_command === 4'b0100) ||
		(request_command === 4'b1000);
	assign request_address_valid = ssbus.req_addr === 32'd0;
	// Logical equality intentionally becomes X for any X/Z payload bit.
	assign request_payload_known = ssbus.req_data == ssbus.req_data;
	assign request_state_canonical =
		eeprom_state_canonical(ssbus.req_data[47:45]);
	assign request_word_canonical =
		(request_payload_known === 1'b1) &&
		(ssbus.req_data[63:48] === FORMAT_TAG) &&
		(request_state_canonical === 1'b1);

	assign live_state_known = live_state_i == live_state_i;
	assign live_state_canonical =
		eeprom_state_canonical(live_state_i[47:45]);
	assign live_word = {FORMAT_TAG, live_state_i};

	assign safe_window =
		(state_enable_i === 1'b1) &&
		(device_idle_i === 1'b1);
	assign bus_quiet = request_command === 4'b0000;
	assign held_request_matches =
		(ssbus.req_data === held_req_data_q) &&
		(ssbus.req_addr === held_req_addr_q) &&
		(ssbus.req_select === held_req_select_q) &&
		(request_command === held_req_command_q);

	assign restore_begin_safe =
		(state_q == StIdle) &&
		bus_quiet &&
		safe_window &&
		(restore_commit_i === 1'b0) &&
		!terminal_fault_o;

	assign validation_accept =
		(state_q == StIdle) &&
		(restore_begin_i === 1'b0) &&
		(restore_commit_i === 1'b0) &&
		attempt_active_q &&
		!validation_complete_o &&
		!validation_failed_q &&
		!terminal_fault_o &&
		safe_window &&
		request_address_valid &&
		request_word_canonical;

	assign write_accept =
		(state_q == StIdle) &&
		(restore_begin_i === 1'b0) &&
		(restore_commit_i === 1'b0) &&
		attempt_active_q &&
		validation_complete_o &&
		validation_valid_o &&
		!validation_failed_q &&
		!write_complete_o &&
		!write_failed_q &&
		!terminal_fault_o &&
		safe_window &&
		(restore_enable_i === 1'b1) &&
		request_address_valid &&
		request_word_canonical &&
		(ssbus.req_data === validated_word_q);

	assign commit_apply_safe =
		(state_q == StIdle) &&
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
		(restore_enable_i === 1'b1);

	assign restore_load_o =
		!reset_i &&
		(restore_commit_i === 1'b1) &&
		commit_apply_safe;
	assign restore_state_o = staged_word_q[47:0];

	assign owner_idle_o =
		(state_q === StIdle) &&
		bus_quiet &&
		(device_idle_i === 1'b1) &&
		(restore_begin_i === 1'b0) &&
		(restore_commit_i === 1'b0);

	always_ff @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= StIdle;
			held_req_data_q <= 64'd0;
			held_req_addr_q <= 32'd0;
			held_req_select_q <= 8'd0;
			held_req_command_q <= 4'd0;
			validated_word_q <= 64'd0;
			staged_word_q <= 64'd0;
			attempt_active_q <= 1'b0;
			validation_failed_q <= 1'b0;
			write_failed_q <= 1'b0;
			validation_complete_o <= 1'b0;
			validation_valid_o <= 1'b0;
			write_complete_o <= 1'b0;
			write_valid_o <= 1'b0;
			restore_committed_o <= 1'b0;
			terminal_fault_o <= 1'b0;
			ssbus.rsp_data <= 64'd0;
			ssbus.rsp_ack <= 1'b0;
			ssbus.rsp_error <= 1'b0;
		end else begin
			ssbus.rsp_data <= 64'd0;
			ssbus.rsp_ack <= 1'b0;
			ssbus.rsp_error <= 1'b0;

			if (restore_begin_i !== 1'b0) begin
				if ((restore_begin_i === 1'b1) &&
				    restore_begin_safe) begin
					state_q <= StIdle;
					held_req_data_q <= 64'd0;
					held_req_addr_q <= 32'd0;
					held_req_select_q <= 8'd0;
					held_req_command_q <= 4'd0;
					validated_word_q <= 64'd0;
					staged_word_q <= 64'd0;
					attempt_active_q <= 1'b1;
					validation_failed_q <= 1'b0;
					write_failed_q <= 1'b0;
					validation_complete_o <= 1'b0;
					validation_valid_o <= 1'b0;
					write_complete_o <= 1'b0;
					write_valid_o <= 1'b0;
					restore_committed_o <= 1'b0;
				end else begin
					validation_valid_o <= 1'b0;
					write_valid_o <= 1'b0;
					terminal_fault_o <= 1'b1;
				end
			end else if (restore_commit_i !== 1'b0) begin
				if ((restore_commit_i === 1'b1) &&
				    commit_apply_safe) begin
					attempt_active_q <= 1'b0;
					restore_committed_o <= 1'b1;
				end else begin
					validation_valid_o <= 1'b0;
					write_valid_o <= 1'b0;
					terminal_fault_o <= 1'b1;
				end
			end else begin
				unique case (state_q)
					StIdle: begin
						if (request_selected) begin
							held_req_data_q <=
								ssbus.req_data;
							held_req_addr_q <=
								ssbus.req_addr;
							held_req_select_q <=
								ssbus.req_select;
							held_req_command_q <=
								request_command;
							ssbus.rsp_ack <= 1'b1;

							if (!request_command_legal ||
							    terminal_fault_o) begin
								ssbus.rsp_error <=
									1'b1;
								terminal_fault_o <=
									1'b1;
							end else if (ssbus.req_query) begin
								ssbus.rsp_data <=
									ssbus.query_descriptor(
										OWNER_INDEX,
										WORD_COUNT,
										WIDTH_CODE_64
									);
							end else if (ssbus.req_read) begin
								if (safe_window &&
								    request_address_valid &&
								    (live_state_known ===
								     1'b1) &&
								    (live_state_canonical ===
								     1'b1)) begin
									ssbus.rsp_data <=
										live_word;
								end else begin
									ssbus.rsp_error <=
										1'b1;
									terminal_fault_o <=
										1'b1;
								end
							end else if (ssbus.req_validate) begin
								if (validation_accept) begin
									validated_word_q <=
										ssbus.req_data;
									validation_complete_o <=
										1'b1;
									validation_valid_o <=
										1'b1;
								end else begin
									ssbus.rsp_error <=
										1'b1;
									validation_failed_q <=
										1'b1;
									validation_valid_o <=
										1'b0;
									if (restore_committed_o)
										terminal_fault_o <=
											1'b1;
								end
							end else begin
								if (write_accept) begin
									staged_word_q <=
										ssbus.req_data;
									write_complete_o <=
										1'b1;
									write_valid_o <=
										1'b1;
								end else begin
									ssbus.rsp_error <=
										1'b1;
									write_failed_q <=
										1'b1;
									write_valid_o <=
										1'b0;
									terminal_fault_o <=
										1'b1;
								end
							end

							state_q <= StWaitRelease;
						end
					end

					StWaitRelease: begin
						if (bus_quiet) begin
							state_q <= StIdle;
						end else if (!held_request_matches) begin
							validation_valid_o <= 1'b0;
							write_valid_o <= 1'b0;
							terminal_fault_o <= 1'b1;
						end
					end

					default: begin
						validation_valid_o <= 1'b0;
						write_valid_o <= 1'b0;
						terminal_fault_o <= 1'b1;
						state_q <= StWaitRelease;
					end
				endcase
			end
		end
	end

endmodule

`default_nettype wire
