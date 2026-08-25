`default_nettype none

// CaveBanpresto save-state owner 2: exact MC68000 architectural context.
//
// The CPU wrapper's private level-7 handler leaves only the natural SR/PC
// interrupt frame in profile-owned work/sprite RAM. D0-D7, A0-A6, and USP are
// captured in a private wrapper window so saving cannot corrupt game RAM:
//
//   word 0 = {32'h3638_4b32 ("68K2"), interrupt-frame SSP}
//   words 1..8 = private 512-bit D0-D7/A0-A6/USP context
//
// The saved pointer denotes the bottom of the natural six-byte SR/PC frame.
// Validation proves that frame is even-aligned and contained in owner 4 for
// Hotdog Storm/Mazinger/Air Gallet/Sailor Moon, or owner 9 for Metamoqester.
//
// Restore is strictly transactional. Pass 1 validates and retains the word
// without touching the CPU. Pass 2 must present the identical word and only
// stages it. The generic non-CPU commit is deliberately absent: only the
// distinct cpu_restore_commit_i control may launch reset-vector reconstruction.
// A pre-launch abort is recoverable after the owner bus is quiet. Once the
// wrapper load pulse has been accepted, abort or protocol loss is reset-only
// terminal.
module CaveBanprestoFx68kSaveStateOwner #(
	parameter [7:0]  OWNER_INDEX = 8'd2,
	parameter [31:0] FORMAT_TAG = 32'h3638_4b32
) (
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        state_enable_i,
	input  wire        restore_enable_i,
	input  wire        restore_begin_i,
	input  wire        cpu_restore_commit_i,
	input  wire        abort_i,
	input  wire        state_held_i,
	input  wire  [3:0] profile_i,
	input  wire [31:0] live_ssp_i,
	input  wire [511:0] live_context_i,
	input  wire        cpu_restore_done_i,
	input  wire        cpu_terminal_fault_i,

	output wire [31:0] restore_ssp_o,
	output wire [511:0] restore_context_o,
	output wire        restore_load_o,
	output wire        abort_safe_o,
	output logic       validation_complete_o,
	output logic       validation_valid_o,
	output logic       write_complete_o,
	output logic       write_valid_o,
	output logic       restore_committed_o,
	output wire        terminal_fault_o,
	output wire        owner_idle_o,

	cavebanpresto_ssbus_if.responder ssbus
);

	localparam [31:0] WORD_COUNT = 32'd9;
	localparam [1:0] WIDTH_CODE_64 = 2'd3;
	localparam [31:0] FRAME_BYTES = 32'h0000_0006;

	localparam [3:0] GAME_HOTDOGST = 4'h0;
	localparam [3:0] GAME_MAZINGER = 4'h1;
	localparam [3:0] GAME_AGALLET  = 4'h2;
	localparam [3:0] GAME_SAILORMN = 4'h3;
	localparam [3:0] GAME_METMQSTR = 4'h4;

	typedef enum logic [2:0] {
		StIdle         = 3'd0,
		StWaitRelease  = 3'd1,
		StCommitLaunch = 3'd2,
		StWaitCpu      = 3'd3,
		StCommitted    = 3'd4,
		StFault        = 3'd5
	} state_e;

	// Justification (reg-d): protocol phase prevents duplicate ACK/load and
	// makes the CPU-final mutation boundary explicit.
	state_e state_q;
	state_e state_d;

	// Justification (reg-a): an acknowledged request must remain bit-for-bit
	// stable until the requester releases all command strobes.
	logic [63:0] held_req_data_q;
	logic [31:0] held_req_addr_q;
	logic  [7:0] held_req_select_q;
	logic  [3:0] held_req_command_q;

	// Justification (reg-a): pass-1 evidence and pass-2 staging remain
	// physically distinct so dry-run validation cannot feed the CPU.
	logic [63:0] validated_word_q [0:8];
	logic [63:0] staged_word_q [0:8];
	logic  [3:0] validation_next_addr_q;
	logic  [3:0] write_next_addr_q;

	// Justification (reg-d): sticky attempt and mutation evidence distinguish
	// a recoverable pre-launch abort from reset-only post-mutation failure.
	logic       attempt_active_q;
	logic       validation_failed_q;
	logic       write_failed_q;
	logic       write_started_q;
	logic       mutation_started_q;
	logic [3:0] attempt_profile_q;
	logic       terminal_fault_q;

	logic  [3:0] request_command;
	logic        request_selected;
	logic        request_command_legal;
	logic        request_address_valid;
	logic        request_payload_known;
	logic        request_word_valid;
	logic        bus_quiet;
	logic        held_request_matches;
	logic        controls_known;
	logic        profile_known;
	logic        profile_supported;
	logic        live_ssp_known;
	logic        live_context_known;
	logic        live_frame_valid;
	logic        safe_window;
	logic        restore_begin_safe;
	logic        validation_accept;
	logic        write_accept;
	logic        cpu_commit_safe;
	logic        commit_launch_safe;
	logic        pass2_continuity_fault;
	logic [63:0] live_word;
	integer word_index;

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

	// The upper bound is the highest legal frame bottom: RAM end + 1 - 0x06.
	// Hotdog's frame is in owner 4 at 0x300000-0x30ffff; Mazinger,
	// Air Gallet, and Sailor Moon use owner 4 at 0x100000-0x10ffff;
	// Metamoqester uses owner 9 at 0xf00000-0xf0ffff.
	function automatic logic ssp_frame_in_profile(
		input logic  [3:0] profile_value,
		input logic [31:0] ssp_value
	);
		logic [31:0] frame_base;
		logic [31:0] frame_limit;
		begin
			frame_base = 32'd0;
			frame_limit = 32'd0;
			case (profile_value)
				GAME_HOTDOGST: begin
					frame_base = 32'h0030_0000;
					frame_limit =
						32'h0031_0000 - FRAME_BYTES;
				end

				GAME_MAZINGER,
				GAME_AGALLET,
				GAME_SAILORMN: begin
					frame_base = 32'h0010_0000;
					frame_limit =
						32'h0011_0000 - FRAME_BYTES;
				end

				GAME_METMQSTR: begin
					frame_base = 32'h00f0_0000;
					frame_limit =
						32'h00f1_0000 - FRAME_BYTES;
				end

				default: begin
					frame_base = 32'd1;
					frame_limit = 32'd0;
				end
			endcase

			ssp_frame_in_profile =
				((ssp_value == ssp_value) === 1'b1) &&
				(ssp_value[0] === 1'b0) &&
				(ssp_value >= frame_base) &&
				(ssp_value <= frame_limit);
		end
	endfunction

	function automatic logic [63:0] image_word(
		input logic [31:0] ssp_value,
		input logic [511:0] context_value,
		input logic [3:0] address_value
	);
		begin
			case (address_value)
				4'd0: image_word = {FORMAT_TAG, ssp_value};
				4'd1: image_word = context_value[63:0];
				4'd2: image_word = context_value[127:64];
				4'd3: image_word = context_value[191:128];
				4'd4: image_word = context_value[255:192];
				4'd5: image_word = context_value[319:256];
				4'd6: image_word = context_value[383:320];
				4'd7: image_word = context_value[447:384];
				4'd8: image_word = context_value[511:448];
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
		request_address_valid =
			((ssbus.req_addr == ssbus.req_addr) === 1'b1) &&
			(ssbus.req_addr < WORD_COUNT);
		request_payload_known =
			((ssbus.req_data == ssbus.req_data) === 1'b1);
		bus_quiet = request_command === 4'b0000;
		held_request_matches =
			(ssbus.req_data === held_req_data_q) &&
			(ssbus.req_addr === held_req_addr_q) &&
			(ssbus.req_select === held_req_select_q) &&
			(request_command === held_req_command_q);

		controls_known =
			((state_enable_i === 1'b0) ||
			 (state_enable_i === 1'b1)) &&
			((restore_enable_i === 1'b0) ||
			 (restore_enable_i === 1'b1)) &&
			((restore_begin_i === 1'b0) ||
			 (restore_begin_i === 1'b1)) &&
			((cpu_restore_commit_i === 1'b0) ||
			 (cpu_restore_commit_i === 1'b1)) &&
			((abort_i === 1'b0) || (abort_i === 1'b1)) &&
			((state_held_i === 1'b0) ||
			 (state_held_i === 1'b1)) &&
			((cpu_restore_done_i === 1'b0) ||
			 (cpu_restore_done_i === 1'b1)) &&
			((cpu_terminal_fault_i === 1'b0) ||
			 (cpu_terminal_fault_i === 1'b1));

		profile_known =
			((profile_i == profile_i) === 1'b1);
		profile_supported =
			profile_known &&
			profile_is_supported(profile_i);
		live_ssp_known =
			((live_ssp_i == live_ssp_i) === 1'b1);
		live_context_known =
			((live_context_i == live_context_i) === 1'b1);
		live_frame_valid =
			live_ssp_known &&
			live_context_known &&
			ssp_frame_in_profile(profile_i, live_ssp_i);
		safe_window =
			(state_enable_i === 1'b1) &&
			(state_held_i === 1'b1) &&
			profile_supported;

		live_word = image_word(
			live_ssp_i,
			live_context_i,
			ssbus.req_addr[3:0]
		);
		request_word_valid =
			request_payload_known &&
			(ssbus.req_data[63:32] === FORMAT_TAG) &&
			ssp_frame_in_profile(
				attempt_profile_q,
				ssbus.req_data[31:0]
			);

		restore_begin_safe =
			(state_q === StIdle) &&
			bus_quiet &&
			safe_window &&
			(abort_i === 1'b0) &&
			(cpu_restore_commit_i === 1'b0) &&
			!terminal_fault_o &&
			(!attempt_active_q || validation_failed_q);

		validation_accept =
			(state_q === StIdle) &&
			(restore_begin_i === 1'b0) &&
			(cpu_restore_commit_i === 1'b0) &&
			(abort_i === 1'b0) &&
			attempt_active_q &&
			!validation_complete_o &&
			!validation_failed_q &&
			!terminal_fault_o &&
			safe_window &&
			(profile_i === attempt_profile_q) &&
			request_address_valid &&
			(ssbus.req_addr === {28'd0, validation_next_addr_q}) &&
			((validation_next_addr_q != 4'd0) || request_word_valid);

		write_accept =
			(state_q === StIdle) &&
			(restore_begin_i === 1'b0) &&
			(cpu_restore_commit_i === 1'b0) &&
			(abort_i === 1'b0) &&
			attempt_active_q &&
			validation_complete_o &&
			validation_valid_o &&
			!validation_failed_q &&
			!write_complete_o &&
			!write_failed_q &&
			!terminal_fault_o &&
			safe_window &&
			(restore_enable_i === 1'b1) &&
			(profile_i === attempt_profile_q) &&
			request_address_valid &&
			(ssbus.req_addr === {28'd0, write_next_addr_q}) &&
			(ssbus.req_data === validated_word_q[write_next_addr_q]);

		cpu_commit_safe =
			(state_q === StIdle) &&
			bus_quiet &&
			(restore_begin_i === 1'b0) &&
			(abort_i === 1'b0) &&
			attempt_active_q &&
			validation_complete_o &&
			validation_valid_o &&
			write_complete_o &&
			write_valid_o &&
			!validation_failed_q &&
			!write_failed_q &&
			!mutation_started_q &&
			!restore_committed_o &&
			!terminal_fault_o &&
			safe_window &&
			(restore_enable_i === 1'b1) &&
			(profile_i === attempt_profile_q);

		commit_launch_safe =
			(state_q === StCommitLaunch) &&
			bus_quiet &&
			(restore_begin_i === 1'b0) &&
			(cpu_restore_commit_i === 1'b0) &&
			(abort_i === 1'b0) &&
			attempt_active_q &&
			validation_complete_o &&
			validation_valid_o &&
			write_complete_o &&
			write_valid_o &&
			!validation_failed_q &&
			!write_failed_q &&
			!mutation_started_q &&
			!restore_committed_o &&
			!terminal_fault_o &&
			safe_window &&
			(restore_enable_i === 1'b1) &&
			(profile_i === attempt_profile_q);

		pass2_continuity_fault =
			attempt_active_q &&
			write_started_q &&
			!mutation_started_q &&
			(abort_i === 1'b0) &&
			((state_enable_i !== 1'b1) ||
			 (restore_enable_i !== 1'b1) ||
			 (state_held_i !== 1'b1) ||
			 (profile_i !== attempt_profile_q));
	end

	assign restore_ssp_o = staged_word_q[0][31:0];
	assign restore_context_o = {
		staged_word_q[8],
		staged_word_q[7],
		staged_word_q[6],
		staged_word_q[5],
		staged_word_q[4],
		staged_word_q[3],
		staged_word_q[2],
		staged_word_q[1]
	};
	assign restore_load_o =
		(reset_i === 1'b0) &&
		(commit_launch_safe === 1'b1);
	assign terminal_fault_o =
		terminal_fault_q |
		(cpu_terminal_fault_i !== 1'b0);
	assign abort_safe_o =
		(reset_i === 1'b0) &&
		(abort_i === 1'b1) &&
		!mutation_started_q &&
		!terminal_fault_o &&
		bus_quiet &&
		((state_q === StIdle) ||
		 (state_q === StCommitLaunch));
	assign owner_idle_o =
		((state_q === StIdle) || (state_q === StCommitted)) &&
		!terminal_fault_o &&
		bus_quiet &&
		(restore_begin_i === 1'b0) &&
		(cpu_restore_commit_i === 1'b0);

	// Two-block FSM: all state transitions are explicit and malformed controls
	// converge on the reset-only fault state.
	always_comb begin
		state_d = state_q;

		if (!controls_known || terminal_fault_o) begin
			state_d = StFault;
		end
		else if (abort_i === 1'b1) begin
			if (mutation_started_q) begin
				state_d = StFault;
			end
			else begin
				case (state_q)
					StIdle: begin
						if (request_selected)
							state_d = StWaitRelease;
					end

					StWaitRelease: begin
						if (!held_request_matches &&
						    !bus_quiet)
							state_d = StFault;
						else if (bus_quiet)
							state_d = StIdle;
					end

					StCommitLaunch:
						state_d = StIdle;

					StCommitted: begin
						if (state_enable_i === 1'b0)
							state_d = StIdle;
					end

					default:
						state_d = StFault;
				endcase
			end
		end
		else begin
			case (state_q)
				StIdle: begin
					if (cpu_restore_done_i === 1'b1) begin
						state_d = StFault;
					end
					else if (restore_begin_i === 1'b1) begin
						if (!restore_begin_safe)
							state_d = StFault;
					end
					else if (cpu_restore_commit_i === 1'b1) begin
						if (cpu_commit_safe)
							state_d = StCommitLaunch;
						else
							state_d = StFault;
					end
					else if (pass2_continuity_fault) begin
						state_d = StFault;
					end
					else if (request_selected) begin
						state_d = StWaitRelease;
					end
				end

				StWaitRelease: begin
					if ((restore_begin_i !== 1'b0) ||
					    (cpu_restore_commit_i !== 1'b0) ||
					    (cpu_restore_done_i !== 1'b0)) begin
						state_d = StFault;
					end
					else if (!held_request_matches &&
					         !bus_quiet) begin
						state_d = StFault;
					end
					else if (bus_quiet) begin
						state_d = StIdle;
					end
				end

				StCommitLaunch: begin
					if (commit_launch_safe)
						state_d = StWaitCpu;
					else
						state_d = StFault;
				end

				StWaitCpu: begin
					if ((restore_begin_i !== 1'b0) ||
					    (cpu_restore_commit_i !== 1'b0) ||
					    (state_enable_i !== 1'b1) ||
					    (restore_enable_i !== 1'b1) ||
					    (profile_i !== attempt_profile_q)) begin
						state_d = StFault;
					end
					else if (cpu_restore_done_i === 1'b1) begin
						state_d = StCommitted;
					end
				end

				StCommitted: begin
					if ((restore_begin_i !== 1'b0) ||
					    (cpu_restore_commit_i !== 1'b0) ||
					    request_selected) begin
						state_d = StFault;
					end
					else if (state_enable_i === 1'b0) begin
						state_d = StIdle;
					end
				end

				StFault:
					state_d = StFault;

				default:
					state_d = StFault;
			endcase
		end
	end

	always_ff @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= StIdle;
			held_req_data_q <= 64'd0;
			held_req_addr_q <= 32'd0;
			held_req_select_q <= 8'd0;
			held_req_command_q <= 4'd0;
			for (word_index = 0; word_index < 9; word_index = word_index + 1) begin
				validated_word_q[word_index] <= 64'd0;
				staged_word_q[word_index] <= 64'd0;
			end
			validation_next_addr_q <= 4'd0;
			write_next_addr_q <= 4'd0;
			attempt_active_q <= 1'b0;
			validation_failed_q <= 1'b0;
			write_failed_q <= 1'b0;
			write_started_q <= 1'b0;
			mutation_started_q <= 1'b0;
			attempt_profile_q <= 4'd0;
			terminal_fault_q <= 1'b0;
			validation_complete_o <= 1'b0;
			validation_valid_o <= 1'b0;
			write_complete_o <= 1'b0;
			write_valid_o <= 1'b0;
			restore_committed_o <= 1'b0;
			ssbus.rsp_data <= 64'd0;
			ssbus.rsp_ack <= 1'b0;
			ssbus.rsp_error <= 1'b0;
		end
		else begin
			state_q <= state_d;
			ssbus.rsp_data <= 64'd0;
			ssbus.rsp_ack <= 1'b0;
			ssbus.rsp_error <= 1'b0;

			if (state_d === StFault)
				terminal_fault_q <= 1'b1;

			if ((state_q === StCommitted) &&
			    (state_enable_i === 1'b0)) begin
				mutation_started_q <= 1'b0;
				attempt_active_q <= 1'b0;
			end

			if (abort_safe_o) begin
				held_req_data_q <= 64'd0;
				held_req_addr_q <= 32'd0;
				held_req_select_q <= 8'd0;
				held_req_command_q <= 4'd0;
				for (word_index = 0; word_index < 9; word_index = word_index + 1) begin
					validated_word_q[word_index] <= 64'd0;
					staged_word_q[word_index] <= 64'd0;
				end
				validation_next_addr_q <= 4'd0;
				write_next_addr_q <= 4'd0;
				attempt_active_q <= 1'b0;
				validation_failed_q <= 1'b0;
				write_failed_q <= 1'b0;
				write_started_q <= 1'b0;
				validation_complete_o <= 1'b0;
				validation_valid_o <= 1'b0;
				write_complete_o <= 1'b0;
				write_valid_o <= 1'b0;
				restore_committed_o <= 1'b0;
			end
			else if ((restore_begin_i === 1'b1) &&
			         restore_begin_safe) begin
				held_req_data_q <= 64'd0;
				held_req_addr_q <= 32'd0;
				held_req_select_q <= 8'd0;
				held_req_command_q <= 4'd0;
				for (word_index = 0; word_index < 9; word_index = word_index + 1) begin
					validated_word_q[word_index] <= 64'd0;
					staged_word_q[word_index] <= 64'd0;
				end
				validation_next_addr_q <= 4'd0;
				write_next_addr_q <= 4'd0;
				attempt_active_q <= 1'b1;
				validation_failed_q <= 1'b0;
				write_failed_q <= 1'b0;
				write_started_q <= 1'b0;
				mutation_started_q <= 1'b0;
				attempt_profile_q <= profile_i;
				validation_complete_o <= 1'b0;
				validation_valid_o <= 1'b0;
				write_complete_o <= 1'b0;
				write_valid_o <= 1'b0;
				restore_committed_o <= 1'b0;
			end

			if (restore_load_o)
				mutation_started_q <= 1'b1;

			if ((state_q === StWaitCpu) &&
			    (cpu_restore_done_i === 1'b1) &&
			    (state_d === StCommitted)) begin
				restore_committed_o <= 1'b1;
			end

			if ((state_q === StIdle) &&
			    request_selected &&
			    (restore_begin_i === 1'b0) &&
			    (cpu_restore_commit_i === 1'b0)) begin
				held_req_data_q <= ssbus.req_data;
				held_req_addr_q <= ssbus.req_addr;
				held_req_select_q <= ssbus.req_select;
				held_req_command_q <= request_command;
				ssbus.rsp_ack <= 1'b1;

				if (abort_i === 1'b1) begin
					// Abort is recoverable, but an already-present
					// request is explicitly rejected before release.
					ssbus.rsp_error <= 1'b1;
				end
				else if (!request_command_legal ||
				         terminal_fault_o) begin
					ssbus.rsp_error <= 1'b1;
					validation_valid_o <= 1'b0;
					write_valid_o <= 1'b0;
					terminal_fault_q <= 1'b1;
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
						terminal_fault_q <= 1'b1;
					end
				end
				else if (ssbus.req_read) begin
					if (request_address_valid &&
					    request_payload_known &&
					    safe_window &&
					    !attempt_active_q &&
					    live_frame_valid) begin
						ssbus.rsp_data <= live_word;
					end
					else begin
						ssbus.rsp_error <= 1'b1;
						terminal_fault_q <= 1'b1;
					end
				end
				else if (ssbus.req_validate) begin
					if (validation_accept) begin
						validated_word_q[validation_next_addr_q] <=
							ssbus.req_data;
						if (validation_next_addr_q == 4'd8) begin
							validation_next_addr_q <= 4'd8;
							validation_complete_o <= 1'b1;
							validation_valid_o <= 1'b1;
						end
						else begin
							validation_next_addr_q <=
								validation_next_addr_q + 4'd1;
						end
					end
					else begin
						ssbus.rsp_error <= 1'b1;
						validation_complete_o <= 1'b1;
						validation_valid_o <= 1'b0;
						validation_failed_q <= 1'b1;
					end
				end
				else begin
					if (write_accept) begin
						staged_word_q[write_next_addr_q] <= ssbus.req_data;
						write_started_q <= 1'b1;
						if (write_next_addr_q == 4'd8) begin
							write_next_addr_q <= 4'd8;
							write_complete_o <= 1'b1;
							write_valid_o <= 1'b1;
						end
						else begin
							write_next_addr_q <=
								write_next_addr_q + 4'd1;
						end
					end
					else begin
						ssbus.rsp_error <= 1'b1;
						write_complete_o <= 1'b1;
						validation_valid_o <= 1'b0;
						write_valid_o <= 1'b0;
						write_failed_q <= 1'b1;
						terminal_fault_q <= 1'b1;
					end
				end
			end
		end
	end

endmodule

`default_nettype wire
