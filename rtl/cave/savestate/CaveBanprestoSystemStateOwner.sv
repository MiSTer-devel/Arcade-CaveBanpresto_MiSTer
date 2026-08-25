`default_nettype none

// CaveBanpresto save-state owner 1: Cave.sv runtime/system state.
//
// One canonical 64-bit element:
//   [63:48]  16'h4731 ("G1")
//   [47:33]  reserved zero
//   [32]     videoSysIoctlDownloadReg
//   [31]     memSysIoctlDownloadReg
//   [30:15]  memSys_io_prog_nvram_ioctl_din_r
//   [14]     ioctlDownloadReg
//   [13]     gameIndexReg_latched
//   [12:9]   gameIndexReg
//   [8:7]    metmqstrSpriteBankDelay
//   [6:5]    metmqstrSpriteBankActive
//   [4]      airGalletSpriteFrameInFlight
//   [3]      airGalletSpriteStartPending
//   [2]      spriteFrameBufferSwapPrimed
//   [1]      videoVBlankPipe2
//   [0]      videoVBlankPipe1
//
// The first vblank synchronizer stage is not serialized.  On restore it is
// canonicalized to Pipe1 so no metastability-resolution history crosses a save
// file.  The game-index MCP transport is also derived: its source toggle,
// destination synchronizer stages, and seen toggle restore to zero while the
// destination game-index replica restores directly from gameIndexReg.
//
// Restore is strictly transactional.  Pass 1 retains and validates one
// canonical word without changing live state.  Pass 2 must repeat that word
// exactly and only stages it.  A legal final commit advances to a separate
// one-cycle apply state; restore_apply_o and restore_cdc_canonicalize_o then
// pulse together while the machine remains held.  The canonicalization pulse
// is in clk_i's domain and must be delivered to cpuClock through the ordered
// control-CDC integration; it is not itself a destination-domain pulse.
module CaveBanprestoSystemStateOwner #(
	parameter [7:0] OWNER_INDEX = 8'd1,
	parameter [15:0] FORMAT_TAG = 16'h4731
) (
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        state_enable_i,
	input  wire        restore_enable_i,
	input  wire        restore_begin_i,
	input  wire        restore_commit_i,
	input  wire        state_held_i,
	input  wire        ioctl_idle_i,
	input  wire  [3:0] active_profile_i,

	input  wire        live_video_vblank_pipe1_i,
	input  wire        live_video_vblank_pipe2_i,
	input  wire        live_sprite_framebuffer_swap_primed_i,
	input  wire        live_air_sprite_start_pending_i,
	input  wire        live_air_sprite_frame_inflight_i,
	input  wire  [1:0] live_met_sprite_bank_active_i,
	input  wire  [1:0] live_met_sprite_bank_delay_i,
	input  wire  [3:0] live_game_index_i,
	input  wire        live_game_index_latched_i,
	input  wire        live_ioctl_download_history_i,
	input  wire [15:0] live_nvram_ioctl_din_history_i,
	input  wire        live_memsys_ioctl_download_history_i,
	input  wire        live_videosys_ioctl_download_history_i,

	output wire        restore_apply_o,
	output wire        restore_cdc_canonicalize_o,
	output wire        restore_video_vblank_pipe0_o,
	output wire        restore_video_vblank_pipe1_o,
	output wire        restore_video_vblank_pipe2_o,
	output wire        restore_sprite_framebuffer_swap_primed_o,
	output wire        restore_air_sprite_start_pending_o,
	output wire        restore_air_sprite_frame_inflight_o,
	output wire  [1:0] restore_met_sprite_bank_active_o,
	output wire  [1:0] restore_met_sprite_bank_delay_o,
	output wire  [3:0] restore_game_index_o,
	output wire        restore_game_index_latched_o,
	output wire        restore_ioctl_download_history_o,
	output wire [15:0] restore_nvram_ioctl_din_history_o,
	output wire        restore_memsys_ioctl_download_history_o,
	output wire        restore_videosys_ioctl_download_history_o,

	output wire        restore_game_index_cpu_load_toggle_o,
	output wire        restore_game_index_cpu_toggle_sync0_o,
	output wire        restore_game_index_cpu_toggle_sync1_o,
	output wire        restore_game_index_cpu_toggle_seen_o,
	output wire  [3:0] restore_game_index_cpu_reg_o,

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

	// Justification (reg-d): prevents duplicate acknowledgement of a held bus
	// request and separates commit admission from architectural application.
	state_e state_q;

	// Justification (reg-a): the complete acknowledged request signature must
	// remain immutable until the requester releases it.
	logic [63:0] held_req_data_q;
	logic [31:0] held_req_addr_q;
	logic  [7:0] held_req_select_q;
	logic  [3:0] held_req_command_q;

	// Justification (reg-d): pass-1 evidence and pass-2 staging are distinct so
	// validation can never mutate live Cave state.
	logic [63:0] validated_word_q;
	logic [63:0] staged_word_q;

	// Justification (reg-d): transaction phase and sticky failure evidence make
	// malformed pass-2/control sequences fail closed.
	logic       attempt_active_q;
	logic       validation_failed_q;
	logic       write_failed_q;
	logic       write_started_q;
	logic [3:0] attempt_profile_q;

	logic  [3:0] request_command;
	logic        request_selected;
	logic        request_command_legal;
	logic        request_address_valid;
	logic        request_payload_known;
	logic        request_word_canonical;
	logic        bus_quiet;
	logic        held_request_matches;
	logic        profile_known;
	logic        profile_supported;
	logic        safe_window;
	logic        live_state_known;
	logic        live_identity_valid;
	logic [32:0] raw_live_state;
	logic [32:0] canonical_live_state;
	logic [32:0] request_state;
	logic [63:0] live_word;
	logic        restore_begin_safe;
	logic        validation_accept;
	logic        write_accept;
	logic        restore_commit_safe;
	logic        commit_apply_safe;
	logic        pass2_continuity_fault;

	function automatic logic profile_is_supported(
		input logic [3:0] profile_value
	);
		begin
			case (profile_value)
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

	function automatic logic [32:0] canonicalize_state(
		input logic [32:0] state_value,
		input logic  [3:0] profile_value
	);
		logic [32:0] result;
		begin
			result = state_value;
			case (profile_value)
				GAME_HOTDOGST: begin
					result[8:2] = 7'd0;
				end

				GAME_MAZINGER: begin
					result[8:3] = 6'd0;
				end

				GAME_AGALLET: begin
					result[2] = 1'b0;
					result[8:5] = 4'd0;
				end

				GAME_SAILORMN: begin
					result[8:2] = 7'd0;
				end

				GAME_METMQSTR: begin
					result[4:3] = 2'd0;
				end

				default: begin
					result = 33'd0;
				end
			endcase
			canonicalize_state = result;
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
		request_address_valid = ssbus.req_addr === 32'd0;
		request_payload_known =
			((ssbus.req_data == ssbus.req_data) === 1'b1);
		bus_quiet = request_command === 4'b0000;
		held_request_matches =
			(ssbus.req_data === held_req_data_q) &&
			(ssbus.req_addr === held_req_addr_q) &&
			(ssbus.req_select === held_req_select_q) &&
			(request_command === held_req_command_q);

		profile_known =
			((active_profile_i == active_profile_i) === 1'b1);
		profile_supported =
			profile_known &&
			profile_is_supported(active_profile_i);
		safe_window =
			(state_enable_i === 1'b1) &&
			(state_held_i === 1'b1) &&
			(ioctl_idle_i === 1'b1) &&
			profile_supported;

		raw_live_state = {
			live_videosys_ioctl_download_history_i,
			live_memsys_ioctl_download_history_i,
			live_nvram_ioctl_din_history_i,
			live_ioctl_download_history_i,
			live_game_index_latched_i,
			live_game_index_i,
			live_met_sprite_bank_delay_i,
			live_met_sprite_bank_active_i,
			live_air_sprite_frame_inflight_i,
			live_air_sprite_start_pending_i,
			live_sprite_framebuffer_swap_primed_i,
			live_video_vblank_pipe2_i,
			live_video_vblank_pipe1_i
		};
		canonical_live_state =
			canonicalize_state(raw_live_state, active_profile_i);
		live_state_known =
			((raw_live_state == raw_live_state) === 1'b1) &&
			((canonical_live_state == canonical_live_state) === 1'b1);
		live_identity_valid =
			(live_game_index_i === active_profile_i) &&
			(live_game_index_latched_i === 1'b1);
		live_word = {
			FORMAT_TAG,
			15'd0,
			canonical_live_state
		};

		request_state = ssbus.req_data[32:0];
		request_word_canonical =
			request_payload_known &&
			(ssbus.req_data[63:48] === FORMAT_TAG) &&
			(ssbus.req_data[47:33] === 15'd0) &&
			(request_state[12:9] === attempt_profile_q) &&
			(request_state[13] === 1'b1) &&
			(request_state ===
			 canonicalize_state(request_state, attempt_profile_q));

		// A validation-only epoch is write-free and may be abandoned by the
		// global controller.  A fresh BEGIN replaces it in the same boot.
		// Once pass 2 stages a word, global post-mutation recovery is
		// deliberately reset-only and a new epoch remains illegal.
		restore_begin_safe =
			(state_q === StIdle) &&
			bus_quiet &&
			safe_window &&
			(restore_commit_i === 1'b0) &&
			!terminal_fault_o &&
			(!attempt_active_q ||
			 validation_failed_q ||
			 !write_started_q);

		validation_accept =
			(state_q === StIdle) &&
			(restore_begin_i === 1'b0) &&
			(restore_commit_i === 1'b0) &&
			attempt_active_q &&
			!validation_complete_o &&
			!validation_failed_q &&
			!terminal_fault_o &&
			safe_window &&
			(active_profile_i === attempt_profile_q) &&
			request_address_valid &&
			request_word_canonical;

		write_accept =
			(state_q === StIdle) &&
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
			(active_profile_i === attempt_profile_q) &&
			request_address_valid &&
			request_word_canonical &&
			(ssbus.req_data === validated_word_q);

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
			(active_profile_i === attempt_profile_q);

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
			(active_profile_i === attempt_profile_q);

		pass2_continuity_fault =
			attempt_active_q &&
			write_started_q &&
			((state_enable_i !== 1'b1) ||
			 (restore_enable_i !== 1'b1) ||
			 (state_held_i !== 1'b1) ||
			 (ioctl_idle_i !== 1'b1) ||
			 (active_profile_i !== attempt_profile_q));
	end

	assign restore_apply_o =
		(reset_i === 1'b0) &&
		(commit_apply_safe === 1'b1);
	assign restore_cdc_canonicalize_o = restore_apply_o;

	assign restore_video_vblank_pipe0_o = staged_word_q[0];
	assign restore_video_vblank_pipe1_o = staged_word_q[0];
	assign restore_video_vblank_pipe2_o = staged_word_q[1];
	assign restore_sprite_framebuffer_swap_primed_o = staged_word_q[2];
	assign restore_air_sprite_start_pending_o = staged_word_q[3];
	assign restore_air_sprite_frame_inflight_o = staged_word_q[4];
	assign restore_met_sprite_bank_active_o = staged_word_q[6:5];
	assign restore_met_sprite_bank_delay_o = staged_word_q[8:7];
	assign restore_game_index_o = staged_word_q[12:9];
	assign restore_game_index_latched_o = staged_word_q[13];
	assign restore_ioctl_download_history_o = staged_word_q[14];
	assign restore_nvram_ioctl_din_history_o = staged_word_q[30:15];
	assign restore_memsys_ioctl_download_history_o = staged_word_q[31];
	assign restore_videosys_ioctl_download_history_o = staged_word_q[32];

	assign restore_game_index_cpu_load_toggle_o = 1'b0;
	assign restore_game_index_cpu_toggle_sync0_o = 1'b0;
	assign restore_game_index_cpu_toggle_sync1_o = 1'b0;
	assign restore_game_index_cpu_toggle_seen_o = 1'b0;
	assign restore_game_index_cpu_reg_o = staged_word_q[12:9];

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
			validated_word_q <= 64'd0;
			staged_word_q <= 64'd0;
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
					validated_word_q <= 64'd0;
					staged_word_q <= 64'd0;
					attempt_active_q <= 1'b1;
					validation_failed_q <= 1'b0;
					write_failed_q <= 1'b0;
					write_started_q <= 1'b0;
					attempt_profile_q <= active_profile_i;
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
								if (request_address_valid &&
								    request_payload_known) begin
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
								if (request_payload_known &&
								    request_address_valid &&
								    safe_window &&
								    !attempt_active_q &&
								    live_state_known &&
								    live_identity_valid) begin
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
								if (validation_accept) begin
									validated_word_q <=
										ssbus.req_data;
									validation_complete_o <=
										1'b1;
									validation_valid_o <=
										1'b1;
								end
								else begin
									ssbus.rsp_error <= 1'b1;
									validation_complete_o <=
										1'b1;
									validation_valid_o <=
										1'b0;
									validation_failed_q <=
										1'b1;
								end
							end
							else begin
								if (write_accept) begin
									staged_word_q <= ssbus.req_data;
									write_started_q <= 1'b1;
									write_complete_o <= 1'b1;
									write_valid_o <= 1'b1;
								end
								else begin
									ssbus.rsp_error <= 1'b1;
									validation_valid_o <=
										1'b0;
									write_complete_o <=
										1'b1;
									write_valid_o <=
										1'b0;
									write_failed_q <= 1'b1;
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
