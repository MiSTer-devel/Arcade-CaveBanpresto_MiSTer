`default_nettype none

// CaveBanpresto save-state owner 25: Sound.sv state that is not owned by the
// T80 (23), sound RAM (24), sound chips (26..29), or drained ROM transport.
//
// The exact OKI owners include their bank registers and held mixer samples, so
// those fields are deliberately absent here.  The active YM held sample stays
// here because it is the Sound.sv sample-and-hold register downstream of the
// selected YM core.
//
// Eight 64-bit elements:
//   0: {24'h533245 ("S2E"), use_ym2151, request, z80_bank,
//       command_data, z80_io_write_d, z80_io_write_addr,
//       z80_io_write_data}
//   1: {reply_count, reply_write_ptr, reply_read_ptr, ym2151_sample,
//       ym2203_fm_sample, ym2203_psg_sample}
//       Inactive-YM samples are canonical zero.
//   2..5: reply FIFO entries 0..31, eight bytes per word, low byte first.
//         Bytes outside the logical [read_ptr, count] ring are canonical zero.
//   6: mixer_state[63:0], including the original BGM smoothing register
//   7: mixer_state[127:64]
//
// Restore pass 1 must present addresses 0..7 exactly once and in order.  The
// accepted 512-bit image is retained in MLABs so pass 2 can require the exact
// same ordered payload before exposing any direct live-register write pulse.
// A pass-1 failure remains write-free and permits a later restore_begin_i.
// Any pass-2, commit, control, or protocol inconsistency is reset-only fatal.
module CaveBanprestoSoundWrapperStatePort #(
	parameter [7:0] OWNER_INDEX = 8'd25,
	// S2E rejects the S2D image whose low 29 bits held OKI0 averaging history.
	parameter [23:0] FORMAT_TAG = 24'h5332_45
) (
	input  wire         clk_i,
	input  wire         reset_i,
	input  wire         state_enable_i,
	input  wire         restore_enable_i,
	input  wire         restore_begin_i,
	input  wire         restore_commit_i,

	input  wire         live_use_ym2151_i,
	input  wire         live_request_i,
	input  wire [15:0]  live_command_data_i,
	input  wire [4:0]   live_z80_bank_i,
	input  wire [15:0]  live_ym2203_psg_i,
	input  wire [15:0]  live_ym2203_fm_i,
	input  wire [15:0]  live_ym2151_i,
	input  wire         live_z80_io_write_d_i,
	input  wire [7:0]   live_z80_io_write_addr_i,
	input  wire [7:0]   live_z80_io_write_data_i,
	input  wire [255:0] live_reply_fifo_i,
	input  wire [4:0]   live_reply_read_ptr_i,
	input  wire [4:0]   live_reply_write_ptr_i,
	input  wire [5:0]   live_reply_count_i,
	input  wire [127:0] live_mixer_state_i,

	output logic        restore_word_wr_o,
	output logic [2:0]  restore_word_addr_o,
	output logic [63:0] restore_word_data_o,

	output logic        validation_complete_o,
	output logic        validation_valid_o,
	output logic        write_complete_o,
	output logic        write_valid_o,
	output logic        restore_committed_o,
	output logic        terminal_fault_o,
	output wire         owner_idle_o,

	cavebanpresto_ssbus_if.responder ssbus
);

	localparam [31:0] WORD_COUNT = 32'd8;
	localparam [1:0] WIDTH_CODE_64 = 2'd3;

	typedef enum logic [2:0] {
		StIdle          = 3'd0,
		StPass2ReadWait = 3'd1,
		StPass2Compare  = 3'd2,
		StWriteApply    = 3'd3,
		StWaitRelease   = 3'd4
	} state_e;

	// Justification (reg-a): retains an admitted owner-bus transaction through
	// the synchronous pass-1 image read and direct-register apply cycle.
	state_e state_q;
	logic [31:0] request_addr_q;
	logic [63:0] request_data_q;

	// Justification (reg-d): strict monotonic cursors and sticky epoch status
	// implement the two-pass restore protocol.
	logic [3:0] validate_next_q;
	logic [3:0] write_next_q;
	logic       validation_failed_q;
	logic       write_failed_q;
	logic       attempt_active_q;

	// Justification (reg-a): pass-1 word 0/1 context is needed to validate the
	// canonical inactive-YM and unused-FIFO fields in later words.
	logic       validate_mode_q;
	logic [4:0] validate_reply_read_q;
	logic [5:0] validate_reply_count_q;

	// Keep pass-1 evidence in M10Ks because the production design is
	// LAB-constrained.  The synchronous read also avoids an eight-way
	// asynchronous 64-bit register mux.
	(* ramstyle = "M10K, no_rw_check" *)
	logic [63:0] validate_image [0:7];
	logic [2:0] validate_image_read_addr_q;
	logic [63:0] validate_image_rdata_q;

	logic [3:0] request_command;
	logic       request_selected;
	logic       request_command_legal;
	logic       request_payload_known;
	logic       address_valid;
	logic       validate_sequence_valid;
	logic       write_sequence_valid;
	logic       validation_structure_valid;
	logic       validation_accept;
	logic       request_matches_write;
	logic       restore_begin_idle_safe;
	logic       control_abort_now;
	logic       request_admission_safe;
	logic       read_launch_safe;
	logic       write_launch_safe;
	logic       pass2_request_safe;
	logic       write_apply_safe;
	logic [63:0] live_word;
	logic [255:0] canonical_reply_fifo;
	logic       live_word_known;
	logic       live_reply_relation_valid;

	integer fifo_slot;
	integer validate_byte;
	logic [4:0] validate_slot;

	function automatic logic fifo_slot_active(
		input logic [4:0] slot,
		input logic [4:0] read_pointer,
		input logic [5:0] count
	);
		logic [4:0] distance;
		begin
			distance = slot - read_pointer;
			fifo_slot_active =
				(count == 6'd32) ||
				({1'b0, distance} < count);
		end
	endfunction

	function automatic logic reply_relation_valid(
		input logic [4:0] read_pointer,
		input logic [4:0] write_pointer,
		input logic [5:0] count
	);
		logic [5:0] write_sum;
		begin
			write_sum = {1'b0, read_pointer} + count;
			reply_relation_valid =
				(count <= 6'd32) &&
				(write_pointer == write_sum[4:0]);
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
	// Self-equality becomes X in four-state simulation if any bit is X/Z.
	assign request_payload_known = ssbus.req_data == ssbus.req_data;
	assign address_valid = ssbus.req_addr < WORD_COUNT;
	assign validate_sequence_valid =
		address_valid &&
		(ssbus.req_addr == {28'd0, validate_next_q});
	assign write_sequence_valid =
		address_valid &&
		(ssbus.req_addr == {28'd0, write_next_q});
	assign request_matches_write =
		(ssbus.req_select == OWNER_INDEX) &&
		(request_command == 4'b0010) &&
		(ssbus.req_addr == request_addr_q) &&
		(ssbus.req_data == request_data_q);

	always_comb begin
		canonical_reply_fifo = 256'd0;
		for (fifo_slot = 0; fifo_slot < 32;
		     fifo_slot = fifo_slot + 1) begin
			if (fifo_slot_active(
			    fifo_slot[4:0],
			    live_reply_read_ptr_i,
			    live_reply_count_i)) begin
				canonical_reply_fifo[fifo_slot*8 +: 8] =
					live_reply_fifo_i[fifo_slot*8 +: 8];
			end
		end
	end

	always_comb begin
		live_word = 64'd0;
		unique case (ssbus.req_addr)
			32'd0: begin
				live_word = {
					FORMAT_TAG,
					live_use_ym2151_i,
					live_request_i,
					live_z80_bank_i,
					live_command_data_i,
					live_z80_io_write_d_i,
					live_z80_io_write_addr_i,
					live_z80_io_write_data_i
				};
			end
			32'd1: begin
				live_word = {
					live_reply_count_i,
					live_reply_write_ptr_i,
					live_reply_read_ptr_i,
					live_use_ym2151_i
						? live_ym2151_i : 16'd0,
					live_use_ym2151_i
						? 16'd0 : live_ym2203_fm_i,
					live_use_ym2151_i
						? 16'd0 : live_ym2203_psg_i
				};
			end
			32'd2: live_word = canonical_reply_fifo[63:0];
			32'd3: live_word = canonical_reply_fifo[127:64];
			32'd4: live_word = canonical_reply_fifo[191:128];
			32'd5: live_word = canonical_reply_fifo[255:192];
			32'd6: live_word = live_mixer_state_i[63:0];
			32'd7: live_word = live_mixer_state_i[127:64];
			default: live_word = 64'd0;
		endcase
	end

	assign live_word_known = live_word == live_word;
	assign live_reply_relation_valid = reply_relation_valid(
		live_reply_read_ptr_i,
		live_reply_write_ptr_i,
		live_reply_count_i
	);

	// Cross-word canonical validation is possible because validation is
	// strictly ordered and word 0/1 context is staged above.
	always_comb begin
		validation_structure_valid = 1'b0;
		validate_slot = 5'd0;
		validate_byte = 0;

		unique case (ssbus.req_addr)
			32'd0: begin
				validation_structure_valid =
					(ssbus.req_data[63:40] === FORMAT_TAG) &&
					(ssbus.req_data[39] ===
					 live_use_ym2151_i);
			end

			32'd1: begin
				validation_structure_valid =
					reply_relation_valid(
						ssbus.req_data[52:48],
						ssbus.req_data[57:53],
						ssbus.req_data[63:58]
					);
				if (validate_mode_q === 1'b1) begin
					validation_structure_valid &=
						(ssbus.req_data[31:0] ===
						 32'd0);
				end else if (validate_mode_q === 1'b0) begin
					validation_structure_valid &=
						(ssbus.req_data[47:32] ===
						 16'd0);
				end else begin
					validation_structure_valid = 1'b0;
				end
			end

			32'd2, 32'd3, 32'd4, 32'd5: begin
				validation_structure_valid = 1'b1;
				for (validate_byte = 0; validate_byte < 8;
				     validate_byte = validate_byte + 1) begin
					validate_slot = {
						ssbus.req_addr[1:0] - 2'd2,
						3'b000
					} + validate_byte[4:0];
					if (!fifo_slot_active(
					    validate_slot,
					    validate_reply_read_q,
					    validate_reply_count_q) &&
					    (ssbus.req_data[
					      validate_byte*8 +: 8] !==
					     8'd0)) begin
						validation_structure_valid =
							1'b0;
					end
				end
			end

			32'd6: begin
				validation_structure_valid =
					(ssbus.req_data[28:0] === 29'd0);
			end

			32'd7: begin
				validation_structure_valid = 1'b1;
			end

			default: validation_structure_valid = 1'b0;
		endcase
	end

	assign validation_accept =
		(state_q == StIdle) &&
		!restore_begin_i &&
		!restore_commit_i &&
		attempt_active_q &&
		request_selected &&
		(request_command == 4'b0100) &&
		(state_enable_i === 1'b1) &&
		!terminal_fault_o &&
		!validation_failed_q &&
		!validation_complete_o &&
		validate_sequence_valid &&
		request_payload_known &&
		validation_structure_valid;

	assign control_abort_now =
		(restore_begin_i !== 1'b0) ||
		(restore_commit_i !== 1'b0);
	assign request_admission_safe =
		!control_abort_now &&
		!terminal_fault_o &&
		request_command_legal;
	assign read_launch_safe =
		address_valid &&
		request_payload_known &&
		(state_enable_i === 1'b1) &&
		live_word_known &&
		((ssbus.req_addr != 32'd1) ||
		 (live_reply_relation_valid === 1'b1));
	assign write_launch_safe =
		attempt_active_q &&
		validation_complete_o &&
		validation_valid_o &&
		!validation_failed_q &&
		!write_failed_q &&
		!write_complete_o &&
		write_sequence_valid &&
		request_payload_known &&
		(state_enable_i === 1'b1) &&
		(restore_enable_i === 1'b1);
	assign pass2_request_safe =
		!control_abort_now &&
		!terminal_fault_o &&
		attempt_active_q &&
		!write_failed_q &&
		(state_enable_i === 1'b1) &&
		(restore_enable_i === 1'b1) &&
		(request_matches_write === 1'b1);
	assign write_apply_safe =
		pass2_request_safe &&
		(request_data_q === validate_image_rdata_q);

	assign restore_begin_idle_safe =
		(state_q == StIdle) &&
		((|request_command) === 1'b0) &&
		(state_enable_i === 1'b1) &&
		(restore_commit_i === 1'b0) &&
		!terminal_fault_o;

	assign owner_idle_o =
		(state_q === StIdle) &&
		((|request_command) === 1'b0) &&
		(restore_begin_i === 1'b0) &&
		(restore_commit_i === 1'b0);

	// The enclosing Sound register bank samples this pulse on clk_i.
	always_comb begin
		restore_word_wr_o = 1'b0;
		restore_word_addr_o = request_addr_q[2:0];
		restore_word_data_o = request_data_q;

		if (!reset_i &&
		    (state_q == StWriteApply) &&
		    (write_apply_safe === 1'b1)) begin
			restore_word_wr_o = 1'b1;
		end
	end

	// Synchronous pass-1 evidence memory.
	always_ff @(posedge clk_i) begin
		if (validation_accept === 1'b1)
			validate_image[ssbus.req_addr[2:0]] <=
				ssbus.req_data;

		validate_image_rdata_q <=
			validate_image[validate_image_read_addr_q];
	end

	always_ff @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= StIdle;
			request_addr_q <= 32'd0;
			request_data_q <= 64'd0;
			validate_next_q <= 4'd0;
			write_next_q <= 4'd0;
			validation_failed_q <= 1'b0;
			write_failed_q <= 1'b0;
			attempt_active_q <= 1'b0;
			validate_mode_q <= 1'b0;
			validate_reply_read_q <= 5'd0;
			validate_reply_count_q <= 6'd0;
			validate_image_read_addr_q <= 3'd0;
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

			if ((restore_begin_i === 1'b1) &&
			    restore_begin_idle_safe) begin
				state_q <= StIdle;
				request_addr_q <= 32'd0;
				request_data_q <= 64'd0;
				validate_next_q <= 4'd0;
				write_next_q <= 4'd0;
				validation_failed_q <= 1'b0;
				write_failed_q <= 1'b0;
				attempt_active_q <= 1'b1;
				validate_mode_q <= 1'b0;
				validate_reply_read_q <= 5'd0;
				validate_reply_count_q <= 6'd0;
				validate_image_read_addr_q <= 3'd0;
				validation_complete_o <= 1'b0;
				validation_valid_o <= 1'b0;
				write_complete_o <= 1'b0;
				write_valid_o <= 1'b0;
				restore_committed_o <= 1'b0;
			end else if ((restore_commit_i === 1'b1) &&
			             (state_q == StIdle)) begin
				if ((restore_begin_i === 1'b0) &&
				    attempt_active_q &&
				    ((|request_command) === 1'b0) &&
				    (state_enable_i === 1'b1) &&
				    (restore_enable_i === 1'b1) &&
				    validation_complete_o &&
				    validation_valid_o &&
				    write_complete_o &&
				    write_valid_o &&
				    !validation_failed_q &&
				    !write_failed_q &&
				    !restore_committed_o &&
				    !terminal_fault_o) begin
					restore_committed_o <= 1'b1;
					attempt_active_q <= 1'b0;
				end else begin
					validation_failed_q <= 1'b1;
					validation_valid_o <= 1'b0;
					write_failed_q <= 1'b1;
					write_valid_o <= 1'b0;
					terminal_fault_o <= 1'b1;
				end
			end else begin
				if (control_abort_now) begin
					validation_failed_q <= 1'b1;
					validation_valid_o <= 1'b0;
					write_failed_q <= 1'b1;
					write_valid_o <= 1'b0;
					terminal_fault_o <= 1'b1;
				end

				unique case (state_q)
					StIdle: begin
						if (request_selected) begin
							if (request_admission_safe !==
							    1'b1) begin
								ssbus.rsp_ack <= 1'b1;
								ssbus.rsp_error <=
									1'b1;
								terminal_fault_o <=
									1'b1;
								state_q <=
									StWaitRelease;
							end else if (ssbus.req_query) begin
								ssbus.rsp_data <=
									ssbus.query_descriptor(
										OWNER_INDEX,
										WORD_COUNT,
										WIDTH_CODE_64
									);
								ssbus.rsp_ack <= 1'b1;
								state_q <=
									StWaitRelease;
							end else if (ssbus.req_validate) begin
								ssbus.rsp_ack <= 1'b1;
								if (validation_accept !==
								    1'b1) begin
									ssbus.rsp_error <=
										1'b1;
									validation_failed_q <=
										1'b1;
									validation_valid_o <=
										1'b0;
								end else begin
									if (ssbus.req_addr ==
									    32'd0) begin
										validate_mode_q <=
											ssbus.req_data[39];
									end
									if (ssbus.req_addr ==
									    32'd1) begin
										validate_reply_read_q <=
											ssbus.req_data[52:48];
										validate_reply_count_q <=
											ssbus.req_data[63:58];
									end
									validate_next_q <=
										validate_next_q +
										4'd1;
									if (ssbus.req_addr ==
									    32'd7) begin
										validation_complete_o <=
											1'b1;
										validation_valid_o <=
											1'b1;
									end
								end
								state_q <= StWaitRelease;
							end else if (ssbus.req_read) begin
								ssbus.rsp_ack <= 1'b1;
								if (read_launch_safe ===
								    1'b1) begin
									ssbus.rsp_data <=
										live_word;
								end else begin
									ssbus.rsp_error <=
										1'b1;
									terminal_fault_o <=
										1'b1;
								end
								state_q <= StWaitRelease;
							end else begin
								if (write_launch_safe !==
								    1'b1) begin
									ssbus.rsp_ack <=
										1'b1;
									ssbus.rsp_error <=
										1'b1;
									write_failed_q <=
										1'b1;
									write_valid_o <=
										1'b0;
									terminal_fault_o <=
										1'b1;
									state_q <=
										StWaitRelease;
								end else begin
									request_addr_q <=
										ssbus.req_addr;
									request_data_q <=
										ssbus.req_data;
									validate_image_read_addr_q <=
										ssbus.req_addr[2:0];
									state_q <=
										StPass2ReadWait;
								end
							end
						end
					end

					StPass2ReadWait: begin
						if (pass2_request_safe !== 1'b1) begin
							if (request_matches_write ===
							    1'b1) begin
								ssbus.rsp_ack <= 1'b1;
								ssbus.rsp_error <=
									1'b1;
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
							if (request_matches_write ===
							    1'b1) begin
								ssbus.rsp_ack <= 1'b1;
								ssbus.rsp_error <=
									1'b1;
							end
							write_failed_q <= 1'b1;
							write_valid_o <= 1'b0;
							terminal_fault_o <= 1'b1;
							state_q <= StWaitRelease;
						end else if (request_data_q !==
						            validate_image_rdata_q) begin
							ssbus.rsp_ack <= 1'b1;
							ssbus.rsp_error <= 1'b1;
							write_failed_q <= 1'b1;
							write_valid_o <= 1'b0;
							terminal_fault_o <= 1'b1;
							state_q <= StWaitRelease;
						end else begin
							state_q <= StWriteApply;
						end
					end

					StWriteApply: begin
						if (request_matches_write === 1'b1) begin
							ssbus.rsp_ack <= 1'b1;
							ssbus.rsp_error <=
								write_apply_safe !==
								1'b1;
						end

						if (write_apply_safe !== 1'b1) begin
							write_failed_q <= 1'b1;
							write_valid_o <= 1'b0;
							terminal_fault_o <= 1'b1;
						end else begin
							write_next_q <=
								write_next_q + 4'd1;
							if (request_addr_q == 32'd7) begin
								write_complete_o <=
									1'b1;
								write_valid_o <= 1'b1;
							end
						end
						state_q <= StWaitRelease;
					end

					StWaitRelease: begin
						if ((|request_command) === 1'b0)
							state_q <= StIdle;
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
