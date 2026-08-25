`default_nettype none

// CaveBanpresto save-state owner 20: mutable board register files.
//
// The canonical descriptor is eight 64-bit elements.  Physical 16-bit cells
// are serialized little-cell-first, including cells with no current consumer:
//
//   word 0 = Main cells 0..3
//   word 1 = Main cells 4..7
//   word 2 = Main cells 8..11
//   word 3 = Main cells 12..15
//   word 4 = {48'b0, Main cell 16}
//   word 5 = VideoSys cells 0..3
//   word 6 = VideoSys cells 4..7
//   word 7 = {16'h5232 ("R2"), 1'b0, replay_config[30:0], DIP[15:0]}
//
// Main cell order:
//   0..2   layer 0 registers 0..2
//   3..5   layer 1 registers 0..2
//   6..8   layer 2 registers 0..2
//   9..16  sprite registers 0..7
//
// replay_config is validation-only and is never driven back toward menu or
// status inputs:
//   [ 3: 0] horizontal offset
//   [ 7: 4] vertical offset
//   [     8] rotate
//   [     9] compatibility timing
//   [    10] layer 0 enable
//   [    11] layer 1 enable
//   [    12] layer 2 enable
//   [    13] sprite enable
//   [    14] video flip
//   [18:15] PSG boost
//   [22:19] FM-or-YM boost
//   [26:23] physical OKI0 boost
//   [30:27] physical OKI1 boost
//
// Restore is transactional. Pass 1 retains and validates the complete image
// without asserting restore_load_o. Pass 2 must repeat all eight words in
// order and exactly match pass 1. A legal commit advances to a separate apply
// cycle, where all Main, VideoSys, and DIP cells load atomically. Pass-1
// content/order failures are write-free and recoverable with a fresh begin.
// Pass-2, commit, held-request, blocked-normal-write, and configuration
// continuity failures are reset-only terminal.
module CaveBanprestoMainRegisterSaveStateOwner #(
	parameter [7:0]  OWNER_INDEX = 8'd20,
	parameter [15:0] FORMAT_TAG = 16'h5232
) (
	input  wire         clk_i,
	input  wire         reset_i,
	input  wire         state_enable_i,
	input  wire         restore_enable_i,
	input  wire         restore_begin_i,
	input  wire         restore_commit_i,
	input  wire         state_held_i,
	input  wire         blocked_normal_write_i,

	input  wire [271:0] main_state_i,
	input  wire [127:0] video_state_i,
	input  wire [15:0]  dip_state_i,

	input  wire [3:0] config_offset_x_i,
	input  wire [3:0] config_offset_y_i,
	input  wire       config_rotate_i,
	input  wire       config_compatibility_i,
	input  wire       config_layer0_enable_i,
	input  wire       config_layer1_enable_i,
	input  wire       config_layer2_enable_i,
	input  wire       config_sprite_enable_i,
	input  wire       config_flip_video_i,
	input  wire [3:0] config_psg_boost_i,
	input  wire [3:0] config_fm_boost_i,
	input  wire [3:0] config_oki0_boost_i,
	input  wire [3:0] config_oki1_boost_i,

	output wire         restore_load_o,
	output wire [271:0] restore_main_state_o,
	output wire [127:0] restore_video_state_o,
	output wire [15:0]  restore_dip_state_o,
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

	typedef enum logic [1:0] {
		StIdle        = 2'd0,
		StWaitRelease = 2'd1,
		StCommitApply = 2'd2
	} state_e;

	// Justification (reg-d): protocol phase state prevents duplicate command
	// acknowledgement and separates commit admission from architectural load.
	state_e state_q;

	// Justification (reg-a): the requester must hold the complete request
	// signature until release. Mutation after acknowledgement is terminal.
	logic [63:0] held_req_data_q;
	logic [31:0] held_req_addr_q;
	logic  [7:0] held_req_select_q;
	logic  [3:0] held_req_command_q;

	// Justification (reg-d): pass-1 evidence and pass-2 staging are separate
	// images so neither pass can write a physical register before commit.
	logic [63:0] validated_word_q [0:7];
	logic [63:0] staged_word_q [0:7];

	// Justification (reg-d): exact next addresses enforce ordered, complete,
	// duplicate-free validation and write passes.
	logic [3:0] validation_next_addr_q;
	logic [3:0] write_next_addr_q;

	// Justification (reg-d): these flags retain the current transaction's
	// validation/write disposition between individual bus requests.
	logic attempt_active_q;
	logic validation_failed_q;
	logic write_failed_q;
	logic write_started_q;

	// Justification (reg-a): restore compatibility inputs are snapshotted at
	// begin and must remain bit-exact through pass 2 and commit.
	logic [30:0] attempt_config_q;

	logic [3:0] request_command;
	logic       request_selected;
	logic       request_command_legal;
	logic       request_addr_known;
	logic       request_data_known;
	logic       request_addr_in_range;
	logic       bus_quiet;
	logic       held_request_matches;
	logic       safe_window;
	logic       config_known;
	logic       complete_live_image_known;
	logic       restore_begin_safe;
	logic       restore_commit_safe;
	logic       commit_apply_safe;
	logic       validation_word_canonical;
	logic       post_validation_config_fault;
	logic       pass2_continuity_fault;
	logic       blocked_write_fault;
	logic [30:0] replay_config;
	logic [63:0] live_word;

	integer word_index;

	function automatic logic [63:0] image_word(
		input logic [271:0] main_state_value,
		input logic [127:0] video_state_value,
		input logic  [15:0] dip_state_value,
		input logic  [30:0] config_value,
		input logic   [2:0] address_value
	);
		begin
			case (address_value)
				3'd0: image_word = main_state_value[63:0];
				3'd1: image_word = main_state_value[127:64];
				3'd2: image_word = main_state_value[191:128];
				3'd3: image_word = main_state_value[255:192];
				3'd4:
					image_word = {
						48'd0,
						main_state_value[271:256]
					};
				3'd5: image_word = video_state_value[63:0];
				3'd6: image_word = video_state_value[127:64];
				3'd7:
					image_word = {
						FORMAT_TAG,
						1'b0,
						config_value,
						dip_state_value
					};
				default: image_word = 64'd0;
			endcase
		end
	endfunction

	always_comb begin
		replay_config = {
			config_oki1_boost_i,
			config_oki0_boost_i,
			config_fm_boost_i,
			config_psg_boost_i,
			config_flip_video_i,
			config_sprite_enable_i,
			config_layer2_enable_i,
			config_layer1_enable_i,
			config_layer0_enable_i,
			config_compatibility_i,
			config_rotate_i,
			config_offset_y_i,
			config_offset_x_i
		};

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

		config_known =
			((replay_config == replay_config) === 1'b1);
		complete_live_image_known =
			((main_state_i == main_state_i) === 1'b1) &&
			((video_state_i == video_state_i) === 1'b1) &&
			((dip_state_i == dip_state_i) === 1'b1) &&
			config_known;
		safe_window =
			(state_enable_i === 1'b1) &&
			(state_held_i === 1'b1) &&
			config_known;

		live_word = image_word(
			main_state_i,
			video_state_i,
			dip_state_i,
			replay_config,
			ssbus.req_addr[2:0]
		);

		validation_word_canonical = 1'b1;
		case (validation_next_addr_q)
			4'd4:
				validation_word_canonical =
					request_data_known &&
					(ssbus.req_data[63:16] === 48'd0);
			4'd7:
				validation_word_canonical =
					request_data_known &&
					(ssbus.req_data[63:48] === FORMAT_TAG) &&
					(ssbus.req_data[47] === 1'b0) &&
					(ssbus.req_data[46:16] ===
					 attempt_config_q) &&
					(ssbus.req_data[46:16] ===
					 replay_config);
			default:
				validation_word_canonical =
					request_data_known;
		endcase

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
			(replay_config === attempt_config_q);

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
			(replay_config === attempt_config_q);

		post_validation_config_fault =
			attempt_active_q &&
			validation_complete_o &&
			validation_valid_o &&
			((config_known !== 1'b1) ||
			 (replay_config !== attempt_config_q));

		pass2_continuity_fault =
			attempt_active_q &&
			write_started_q &&
			((state_enable_i !== 1'b1) ||
			 (restore_enable_i !== 1'b1) ||
			 (state_held_i !== 1'b1));

		blocked_write_fault =
			(blocked_normal_write_i !== 1'b0) &&
			((state_enable_i !== 1'b0) ||
			 attempt_active_q ||
			 (state_q === StCommitApply));
	end

	assign restore_main_state_o = {
		staged_word_q[4][15:0],
		staged_word_q[3],
		staged_word_q[2],
		staged_word_q[1],
		staged_word_q[0]
	};
	assign restore_video_state_o = {
		staged_word_q[6],
		staged_word_q[5]
	};
	assign restore_dip_state_o = staged_word_q[7][15:0];

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
			for (
				word_index = 0;
				word_index < 8;
				word_index = word_index + 1
			) begin
				validated_word_q[word_index] <= 64'd0;
				staged_word_q[word_index] <= 64'd0;
			end
			validation_next_addr_q <= 4'd0;
			write_next_addr_q <= 4'd0;
			attempt_active_q <= 1'b0;
			validation_failed_q <= 1'b0;
			write_failed_q <= 1'b0;
			write_started_q <= 1'b0;
			attempt_config_q <= 31'd0;
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

			if (blocked_write_fault) begin
				validation_valid_o <= 1'b0;
				write_valid_o <= 1'b0;
				terminal_fault_o <= 1'b1;
			end
			else if (state_q === StCommitApply) begin
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
						word_index < 8;
						word_index = word_index + 1
					) begin
						validated_word_q[word_index] <=
							64'd0;
						staged_word_q[word_index] <=
							64'd0;
					end
					validation_next_addr_q <= 4'd0;
					write_next_addr_q <= 4'd0;
					attempt_active_q <= 1'b1;
					validation_failed_q <= 1'b0;
					write_failed_q <= 1'b0;
					write_started_q <= 1'b0;
					attempt_config_q <= replay_config;
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
			else if ((post_validation_config_fault ||
			          pass2_continuity_fault) &&
			         bus_quiet) begin
				validation_valid_o <= 1'b0;
				write_valid_o <= 1'b0;
				terminal_fault_o <= 1'b1;
			end
			else begin
				case (state_q)
					StIdle: begin
						if (request_selected) begin
							held_req_data_q <= ssbus.req_data;
							held_req_addr_q <= ssbus.req_addr;
							held_req_select_q <=
								ssbus.req_select;
							held_req_command_q <=
								request_command;
							ssbus.rsp_ack <= 1'b1;
							state_q <= StWaitRelease;

							if (!request_command_legal ||
							    terminal_fault_o) begin
								ssbus.rsp_error <= 1'b1;
								validation_valid_o <=
									1'b0;
								write_valid_o <= 1'b0;
								terminal_fault_o <=
									1'b1;
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
									ssbus.rsp_error <=
										1'b1;
									validation_valid_o <=
										1'b0;
									write_valid_o <=
										1'b0;
									terminal_fault_o <=
										1'b1;
								end
							end
							else if (ssbus.req_read) begin
								if (request_data_known &&
								    request_addr_in_range &&
								    safe_window &&
								    !attempt_active_q &&
								    complete_live_image_known) begin
									ssbus.rsp_data <= live_word;
								end
								else begin
									ssbus.rsp_error <=
										1'b1;
									validation_valid_o <=
										1'b0;
									write_valid_o <=
										1'b0;
									terminal_fault_o <=
										1'b1;
								end
							end
							else if (ssbus.req_validate) begin
								if (!attempt_active_q ||
								    validation_failed_q ||
								    validation_complete_o ||
								    !safe_window ||
								    !request_data_known ||
								    !request_addr_known ||
								    (ssbus.req_addr !==
								     {28'd0,
								      validation_next_addr_q}) ||
								    !validation_word_canonical) begin
									ssbus.rsp_error <=
										1'b1;
									validation_complete_o <=
										1'b1;
									validation_valid_o <=
										1'b0;
									validation_failed_q <=
										1'b1;
								end
								else begin
									validated_word_q[
										validation_next_addr_q
									] <= ssbus.req_data;
									if (
										validation_next_addr_q ==
										4'd7
									) begin
										validation_next_addr_q <=
											4'd8;
										validation_complete_o <=
											1'b1;
										validation_valid_o <=
											1'b1;
									end
									else begin
										validation_next_addr_q <=
											validation_next_addr_q +
											4'd1;
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
								    (restore_enable_i ===
								     1'b1) &&
								    (replay_config ===
								     attempt_config_q) &&
								    request_data_known &&
								    request_addr_known &&
								    (ssbus.req_addr ===
								     {28'd0,
								      write_next_addr_q}) &&
								    (ssbus.req_data ===
								     validated_word_q[
										write_next_addr_q
								     ])) begin
									staged_word_q[
										write_next_addr_q
									] <= ssbus.req_data;
									write_started_q <= 1'b1;
									if (
										write_next_addr_q ==
										4'd7
									) begin
										write_next_addr_q <=
											4'd8;
										write_complete_o <=
											1'b1;
										write_valid_o <=
											1'b1;
									end
									else begin
										write_next_addr_q <=
											write_next_addr_q +
											4'd1;
									end
								end
								else begin
									ssbus.rsp_error <=
										1'b1;
									validation_valid_o <=
										1'b0;
									write_complete_o <=
										1'b1;
									write_valid_o <=
										1'b0;
									write_failed_q <=
										1'b1;
									terminal_fault_o <=
										1'b1;
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
