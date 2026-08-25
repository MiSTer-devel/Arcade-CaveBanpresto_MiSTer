`default_nettype none

// CaveBanpresto-local save/restore operation coordinator.
//
// This block is intentionally disconnected from the production top.  Every
// input is synchronous to clk_i; integration must synchronize vblank and both
// reconstructed-frame pulses before this boundary.
//
// CaveBanprestoSaveStateQuiesce is the authority for admission, CPU stopping,
// drain qualification, abort recovery, and its reset-only fatal hold.  Its
// quiesced output is the stable-all_idle proof consumed here.  The proof must
// remain asserted for the complete stream transaction.
//
// CaveBanprestoSaveStateStream is the authority for the strict two-pass image
// walk.  This block independently polices the externally visible proof:
// restore_begin, complete pass 1, pass 2 mutation, and exactly one final
// restore_commit coincident with successful completion.  A pass-2 fault,
// missing/duplicate/illegal commit, or lost quiesce proof is reset-only.
//
// After a successful restore, the CPU holds are released so the renderers can
// rebuild derived pages.  hdmi_freeze_o remains asserted independently of the
// quiesce freeze until both post-reconstruction-start frame pulses have been
// observed and a later clean vblank edge arrives.
module CaveBanprestoSaveStateController #(
	parameter integer WATCHDOG_TIMEOUT_CYCLES = 100_000_000
) (
	input  wire       clk_i,
	input  wire       reset_i,

	input  wire       save_request_i,
	input  wire       restore_request_i,
	input  wire       abort_i,
	input  wire       vblank_i,

	// Observations from CaveBanprestoSaveStateQuiesce.
	input  wire       quiesce_busy_i,
	input  wire       quiesce_freeze_i,
	input  wire       quiesce_quiesced_i,
	input  wire       quiesce_request_accepted_i,
	input  wire       quiesce_request_rejected_i,
	input  wire       quiesce_timeout_i,
	input  wire       quiesce_fatal_hold_i,

	// Commands to CaveBanprestoSaveStateQuiesce.
	output wire       quiesce_request_o,
	output wire       quiesce_request_restore_o,
	output wire       quiesce_abort_o,
	output wire       quiesce_resume_o,
	output wire       quiesce_operation_fatal_o,

	// Observations from CaveBanprestoSaveStateStream.
	input  wire       stream_busy_i,
	input  wire       stream_done_i,
	input  wire       stream_success_i,
	input  wire       stream_format_error_i,
	input  wire       stream_pass1_complete_i,
	input  wire       stream_mutated_i,
	input  wire       stream_fatal_i,
	input  wire [7:0] stream_error_code_i,
	input  wire [1:0] stream_restore_pass_i,
	input  wire       stream_restore_begin_i,
	input  wire       stream_restore_commit_i,

	// Commands to CaveBanprestoSaveStateStream.
	output wire       stream_abort_o,
	output wire       stream_save_start_o,
	output wire       stream_restore_start_o,

	// Qualified owner-wide restore control.  These are the only versions that
	// may be distributed to staged CPU/device owners.
	output wire       restore_begin_o,
	output wire       restore_commit_o,

	// Derived-frame reconstruction boundary.
	input  wire       sprite_frame_complete_i,
	input  wire       system_frame_complete_i,
	output wire       reconstruction_start_o,
	output wire       reconstruction_active_o,
	output wire       hdmi_freeze_o,

	// Operation status.
	output wire       active_o,
	output wire       operation_restore_o,
	output wire       operation_done_o,
	output wire       operation_success_o,
	output wire       operation_aborted_o,
	output logic      request_accepted_o,
	output logic      request_rejected_o,
	output logic      timeout_pulse_o,
	output wire       fatal_hold_o,
	output wire [3:0] state_debug_o,
	output logic [7:0] last_error_o,
	output logic [7:0] last_stream_error_o
);

	localparam [7:0] ERR_NONE                = 8'h00;
	localparam [7:0] ERR_REQUEST_COLLISION   = 8'h01;
	localparam [7:0] ERR_ABORTED             = 8'h02;
	localparam [7:0] ERR_QUIESCE_REJECTED    = 8'h03;
	localparam [7:0] ERR_QUIESCE_TIMEOUT     = 8'h04;
	localparam [7:0] ERR_STREAM_FAILED       = 8'h05;
	localparam [7:0] ERR_STREAM_TIMEOUT      = 8'h06;
	localparam [7:0] ERR_RELEASE_TIMEOUT     = 8'h07;
	localparam [7:0] ERR_RECON_TIMEOUT       = 8'h08;
	localparam [7:0] ERR_ABORT_TIMEOUT       = 8'h09;
	localparam [7:0] ERR_PROTOCOL            = 8'h0a;
	localparam [7:0] ERR_COMMIT              = 8'h0b;
	localparam [7:0] ERR_STREAM_FATAL        = 8'h0c;
	localparam [7:0] ERR_QUIESCE_FATAL       = 8'h0d;
	localparam [7:0] ERR_POST_COMMIT_ABORT   = 8'h0e;
	localparam [7:0] ERR_FATAL_TIMEOUT       = 8'h0f;

	typedef enum logic [3:0] {
		StIdle             = 4'd0,
		StQuiesceIssue     = 4'd1,
		StQuiesceWaitAck   = 4'd2,
		StQuiesceWaitIdle  = 4'd3,
		StStreamStart      = 4'd4,
		StStreamWait       = 4'd5,
		StCleanRelease     = 4'd6,
		StResume           = 4'd7,
		StWaitResume       = 4'd8,
		StReconstructStart = 4'd9,
		StReconstructWait  = 4'd10,
		StRestoreRelease   = 4'd11,
		StAbortAssert      = 4'd12,
		StAbortWait        = 4'd13,
		StFatalHold        = 4'd14,
		StComplete         = 4'd15
	} controller_state_e;

	localparam integer WATCHDOG_COUNT_WIDTH =
		(WATCHDOG_TIMEOUT_CYCLES <= 1)
			? 1 : $clog2(WATCHDOG_TIMEOUT_CYCLES);
	localparam [WATCHDOG_COUNT_WIDTH-1:0]
		WATCHDOG_COUNT_PREEXPIRE =
			(WATCHDOG_TIMEOUT_CYCLES <= 1)
				? {WATCHDOG_COUNT_WIDTH{1'b0}}
				: WATCHDOG_COUNT_WIDTH'(
					WATCHDOG_TIMEOUT_CYCLES - 32'sd2
				  );

	controller_state_e state_q;
	controller_state_e state_d;

	// Justification: immutable operation identity from request through result.
	logic operation_restore_q;
	// Justification: final result is retained while release/recovery completes.
	logic result_success_q;
	logic result_aborted_q;
	// Justification: independent protocol witnesses prevent replayed pulses.
	logic restore_begin_seen_q;
	logic pass1_seen_q;
	logic mutation_seen_q;
	logic restore_commit_seen_q;
	logic stream_busy_seen_q;
	// Justification: only pulses observed after reconstruction_start count.
	logic sprite_frame_seen_q;
	logic system_frame_seen_q;
	// Justification: every externally blocked wait is independently bounded.
	logic [WATCHDOG_COUNT_WIDTH-1:0] watchdog_count_q;
	// Justification (reg-b): registered terminal-count proof breaks the
	// measured watchdog-to-stream-abort critical path without adding a cycle.
	logic watchdog_expired_q;
	// Justification: edge detector for clean release boundaries.
	logic vblank_d_q;

	wire any_request = save_request_i || restore_request_i;
	wire request_collision = save_request_i && restore_request_i;
	wire vblank_rising = vblank_i && !vblank_d_q;

	wire watchdog_state =
		(state_q == StQuiesceWaitAck) ||
		(state_q == StQuiesceWaitIdle) ||
		(state_q == StStreamWait) ||
		(state_q == StCleanRelease) ||
		(state_q == StWaitResume) ||
		(state_q == StReconstructStart) ||
		(state_q == StReconstructWait) ||
		(state_q == StRestoreRelease) ||
		(state_q == StAbortAssert) ||
		(state_q == StAbortWait);
	wire watchdog_preexpire =
		(WATCHDOG_TIMEOUT_CYCLES > 1) &&
		(watchdog_count_q == WATCHDOG_COUNT_PREEXPIRE);
	wire watchdog_expired =
		(WATCHDOG_TIMEOUT_CYCLES == 0) ? 1'b0 :
		(WATCHDOG_TIMEOUT_CYCLES == 1) ? 1'b1 :
		watchdog_expired_q;

	wire pass1_proven =
		pass1_seen_q || stream_pass1_complete_i;

	wire legal_restore_begin =
		(state_q == StStreamWait) &&
		operation_restore_q &&
		!restore_begin_seen_q &&
		(stream_restore_pass_i == 2'd1) &&
		quiesce_busy_i &&
		quiesce_quiesced_i &&
		stream_busy_i &&
		!stream_done_i &&
		!stream_format_error_i &&
		!stream_fatal_i &&
		!quiesce_fatal_hold_i &&
		!abort_i &&
		!watchdog_expired &&
		!stream_pass1_complete_i &&
		!stream_mutated_i &&
		!stream_restore_commit_i &&
		stream_restore_begin_i;

	wire legal_restore_commit =
		(state_q == StStreamWait) &&
		operation_restore_q &&
		restore_begin_seen_q &&
		pass1_seen_q &&
		!restore_commit_seen_q &&
		(stream_restore_pass_i == 2'd2) &&
		stream_done_i &&
		stream_success_i &&
		!stream_busy_i &&
		!stream_format_error_i &&
		!stream_fatal_i &&
		!quiesce_fatal_hold_i &&
		quiesce_busy_i &&
		quiesce_quiesced_i &&
		!stream_restore_begin_i &&
		!abort_i &&
		!watchdog_expired &&
		stream_restore_commit_i;

	wire unexpected_restore_begin =
		stream_restore_begin_i && !legal_restore_begin;
	wire unexpected_restore_commit =
		stream_restore_commit_i && !legal_restore_commit;
	wire pass1_without_begin =
		(state_q == StStreamWait) &&
		operation_restore_q &&
		stream_pass1_complete_i &&
		!restore_begin_seen_q;
	wire pass2_without_pass1 =
		(state_q == StStreamWait) &&
		operation_restore_q &&
		(stream_restore_pass_i == 2'd2) &&
		!pass1_seen_q &&
		!stream_pass1_complete_i;
	wire mutation_before_pass1 =
		(state_q == StStreamWait) &&
		operation_restore_q &&
		stream_mutated_i &&
		!pass1_seen_q;
	wire terminal_busy_collision =
		(state_q == StStreamWait) &&
		stream_done_i &&
		stream_busy_i;
	wire save_restore_signal_leak =
		(state_q == StStreamWait) &&
		!operation_restore_q &&
		(stream_restore_begin_i ||
		 stream_pass1_complete_i ||
		 stream_mutated_i ||
		 stream_restore_commit_i ||
		 (stream_restore_pass_i != 2'd0));
	wire quiesce_proof_lost =
		((state_q == StStreamStart) ||
		 (state_q == StStreamWait) ||
		 (state_q == StCleanRelease) ||
		 (state_q == StResume) ||
		 (state_q == StReconstructStart) ||
		 ((state_q == StAbortAssert) &&
		  stream_busy_seen_q)) &&
		(!quiesce_busy_i || !quiesce_quiesced_i);
	wire stream_completion_lost =
		(state_q == StStreamWait) &&
		stream_busy_seen_q &&
		!stream_busy_i &&
		!stream_done_i;
	wire quiesce_ack_collision =
		(state_q == StQuiesceWaitAck) &&
		quiesce_request_accepted_i &&
		quiesce_request_rejected_i;

	wire contract_fault =
		unexpected_restore_begin ||
		unexpected_restore_commit ||
		pass1_without_begin ||
		pass2_without_pass1 ||
		mutation_before_pass1 ||
		terminal_busy_collision ||
		save_restore_signal_leak ||
		quiesce_proof_lost ||
		stream_completion_lost ||
		quiesce_ack_collision;
	wire hard_fatal_event =
		quiesce_fatal_hold_i ||
		stream_fatal_i ||
		contract_fault;
	wire reconstruction_start_fire =
		(state_q == StReconstructStart) &&
		vblank_rising &&
		!hard_fatal_event &&
		!abort_i &&
		!watchdog_expired;

	wire restore_done_good =
		(state_q == StStreamWait) &&
		operation_restore_q &&
		stream_done_i &&
		stream_success_i &&
		!stream_format_error_i &&
		(stream_restore_pass_i == 2'd2) &&
		restore_begin_seen_q &&
		pass1_proven &&
		legal_restore_commit;
	wire restore_done_recoverable =
		(state_q == StStreamWait) &&
		operation_restore_q &&
		stream_done_i &&
		!stream_success_i &&
		!stream_busy_i &&
		!stream_fatal_i &&
		(stream_restore_pass_i == 2'd1) &&
		!stream_mutated_i &&
		!mutation_seen_q &&
		!stream_restore_commit_i &&
		!restore_commit_seen_q;
	wire restore_pass2_active =
		operation_restore_q &&
		((stream_restore_pass_i == 2'd2) ||
		 stream_mutated_i ||
		 mutation_seen_q ||
		 restore_commit_seen_q);
	wire save_done_committed =
		!operation_restore_q &&
		stream_busy_seen_q &&
		stream_done_i &&
		stream_success_i &&
		!stream_busy_i &&
		!stream_format_error_i &&
		!stream_fatal_i;
	wire save_commit_latched =
		!operation_restore_q &&
		result_success_q &&
		((state_q == StCleanRelease) ||
		 (state_q == StResume) ||
		 (state_q == StWaitResume));

	// Exact expansion of the two additional fatal transitions formerly
	// reached through `(state_d == StFatalHold)` in stream_abort_o.  Keeping
	// these terms explicit removes unrelated next-state decode from the
	// immediate abort fence while preserving its cycle and priority.
	wire stream_start_protocol_fatal =
		(state_q == StStreamStart) && stream_busy_i;
	wire stream_wait_terminal_fatal =
		(state_q == StStreamWait) &&
		operation_restore_q &&
		stream_done_i &&
		!restore_done_good &&
		!restore_done_recoverable;

	// Reset the watchdog at each normal phase exit without feeding the full
	// next-state/fatal cone back into every counter bit.  A hard-fatal exit is
	// deliberately absent: FatalHold does not observe the count and the next
	// non-watchdog cycle clears it.  All other exits are listed so a count from
	// one independently bounded phase can never leak into the next one.
	wire watchdog_phase_exit =
		((state_q == StQuiesceWaitAck) &&
		 (abort_i || quiesce_request_rejected_i ||
		  quiesce_request_accepted_i || watchdog_expired)) ||
		((state_q == StQuiesceWaitIdle) &&
		 (abort_i || quiesce_timeout_i ||
		  (quiesce_busy_i && quiesce_quiesced_i) ||
		  watchdog_expired)) ||
		((state_q == StStreamWait) &&
		 (save_done_committed || abort_i || watchdog_expired ||
		  stream_done_i)) ||
		((state_q == StCleanRelease) &&
		 ((abort_i && !save_commit_latched) || vblank_rising ||
		  watchdog_expired)) ||
		((state_q == StWaitResume) &&
		 (!quiesce_busy_i || watchdog_expired)) ||
		((state_q == StReconstructStart) &&
		 (abort_i || reconstruction_start_fire ||
		  watchdog_expired)) ||
		((state_q == StReconstructWait) &&
		 (abort_i || watchdog_expired ||
		  (!quiesce_busy_i && sprite_frame_seen_q &&
		   system_frame_seen_q))) ||
		((state_q == StRestoreRelease) &&
		 (abort_i || watchdog_expired || quiesce_busy_i ||
		  vblank_rising)) ||
		((state_q == StAbortAssert) &&
		 (save_done_committed || watchdog_expired ||
		  !stream_busy_i)) ||
		((state_q == StAbortWait) &&
		 (watchdog_expired || (!quiesce_busy_i && !stream_busy_i)));

	always_comb begin
		state_d = state_q;

		unique case (state_q)
			StIdle: begin
				if (hard_fatal_event)
					state_d = StFatalHold;
				else if (any_request)
					state_d =
						(request_collision || abort_i)
							? StComplete
							: StQuiesceIssue;
			end

			StQuiesceIssue: begin
				if (hard_fatal_event)
					state_d = StFatalHold;
				else if (abort_i)
					state_d = StAbortAssert;
				else
					state_d = StQuiesceWaitAck;
			end

			StQuiesceWaitAck: begin
				if (hard_fatal_event)
					state_d = StFatalHold;
				else if (abort_i)
					state_d = StAbortAssert;
				else if (quiesce_request_rejected_i)
					state_d = StComplete;
				else if (quiesce_request_accepted_i)
					state_d = StQuiesceWaitIdle;
				else if (watchdog_expired)
					state_d = StAbortAssert;
			end

			StQuiesceWaitIdle: begin
				if (hard_fatal_event)
					state_d = StFatalHold;
				else if (abort_i)
					state_d = StAbortAssert;
				else if (quiesce_timeout_i)
					state_d = StAbortAssert;
				else if (quiesce_busy_i && quiesce_quiesced_i)
					state_d = StStreamStart;
				else if (watchdog_expired)
					state_d = StAbortAssert;
			end

			StStreamStart: begin
				if (hard_fatal_event || stream_busy_i)
					state_d = StFatalHold;
				else if (abort_i)
					state_d = StAbortAssert;
				else
					state_d = StStreamWait;
			end

			StStreamWait: begin
				if (hard_fatal_event) begin
					state_d = StFatalHold;
				end else if (save_done_committed) begin
					// The stream owns the save linearization point.
					// Once the final detector was accepted, its success
					// wins over a coincident or earlier abort request.
					state_d = StCleanRelease;
				end else if (abort_i) begin
					state_d = restore_pass2_active
						? StFatalHold : StAbortAssert;
				end else if (watchdog_expired) begin
					state_d = restore_pass2_active
						? StFatalHold : StAbortAssert;
				end else if (stream_done_i) begin
					if (!operation_restore_q)
						state_d = StCleanRelease;
					else if (restore_done_good)
						state_d = StReconstructStart;
					else if (restore_done_recoverable)
						state_d = StCleanRelease;
					else
						state_d = StFatalHold;
				end
			end

			StCleanRelease: begin
				if (hard_fatal_event)
					state_d = StFatalHold;
				else if (abort_i && !save_commit_latched)
					state_d = StAbortAssert;
				else if (vblank_rising)
					state_d = StResume;
				else if (watchdog_expired)
					state_d = StAbortAssert;
			end

			StResume: begin
				if (hard_fatal_event)
					state_d = StFatalHold;
				else
					state_d = StWaitResume;
			end

			StWaitResume: begin
				if (hard_fatal_event || watchdog_expired)
					state_d = StFatalHold;
				else if (!quiesce_busy_i)
					state_d = StComplete;
			end

			StReconstructStart: begin
				if (hard_fatal_event || abort_i ||
				    watchdog_expired)
					state_d = StFatalHold;
				else if (reconstruction_start_fire)
					state_d = StReconstructWait;
			end

			StReconstructWait: begin
				if (hard_fatal_event || abort_i ||
				    watchdog_expired)
					state_d = StFatalHold;
				else if (!quiesce_busy_i &&
				         sprite_frame_seen_q &&
				         system_frame_seen_q)
					state_d = StRestoreRelease;
			end

			StRestoreRelease: begin
				if (hard_fatal_event || abort_i ||
				    watchdog_expired || quiesce_busy_i)
					state_d = StFatalHold;
				else if (vblank_rising)
					state_d = StComplete;
			end

			StAbortAssert: begin
				if (hard_fatal_event)
					state_d = StFatalHold;
				else if (save_done_committed)
					state_d = StCleanRelease;
				else if (watchdog_expired)
					state_d = StFatalHold;
				else if (!stream_busy_i)
					state_d = StAbortWait;
			end

			StAbortWait: begin
				if (hard_fatal_event || watchdog_expired)
					state_d = StFatalHold;
				else if (!quiesce_busy_i && !stream_busy_i)
					state_d = StComplete;
			end

			StFatalHold: begin
				state_d = StFatalHold;
			end

			StComplete: begin
				if (hard_fatal_event)
					state_d = StFatalHold;
				else
					state_d = StIdle;
			end

			default: begin
				state_d = StFatalHold;
			end
		endcase
	end

	assign quiesce_request_o =
		!reset_i &&
		(state_q == StQuiesceIssue) &&
		!abort_i &&
		!hard_fatal_event;
	assign quiesce_request_restore_o = operation_restore_q;
	assign quiesce_abort_o =
		!reset_i &&
		(state_q == StAbortWait);
	assign quiesce_resume_o =
		!reset_i &&
		((state_q == StResume) ||
		 reconstruction_start_fire);
	assign quiesce_operation_fatal_o =
		!reset_i &&
		((state_q == StFatalHold) ||
		 (state_d == StFatalHold));

	assign stream_save_start_o =
		!reset_i &&
		(state_q == StStreamStart) &&
		!operation_restore_q &&
		!stream_busy_i &&
		!abort_i &&
		!hard_fatal_event;
	assign stream_restore_start_o =
		!reset_i &&
		(state_q == StStreamStart) &&
		operation_restore_q &&
		!stream_busy_i &&
		!abort_i &&
		!hard_fatal_event;
	assign stream_abort_o =
		!reset_i &&
		((state_q == StAbortAssert) ||
		 (state_q == StAbortWait) ||
		 (state_q == StFatalHold) ||
		 (((state_q == StStreamStart) ||
		   (state_q == StStreamWait)) &&
		  (abort_i || watchdog_expired ||
		   hard_fatal_event)) ||
		 stream_start_protocol_fatal ||
		 stream_wait_terminal_fatal);

	assign restore_begin_o =
		!reset_i && legal_restore_begin;
	assign restore_commit_o =
		!reset_i && legal_restore_commit;

	assign reconstruction_start_o =
		!reset_i && reconstruction_start_fire;
	assign reconstruction_active_o =
		!reset_i &&
		((state_q == StReconstructStart) ||
		 (state_q == StReconstructWait) ||
		 (state_q == StRestoreRelease));
	assign hdmi_freeze_o =
		!reset_i &&
		(quiesce_freeze_i ||
		 reconstruction_active_o ||
		 (state_q == StFatalHold) ||
		 (state_d == StFatalHold));

	assign active_o = state_q != StIdle;
	assign operation_restore_o =
		operation_restore_q && (state_q != StIdle);
	assign operation_done_o = state_q == StComplete;
	assign operation_success_o =
		(state_q == StComplete) && result_success_q;
	assign operation_aborted_o =
		(state_q == StComplete) && result_aborted_q;
	assign fatal_hold_o =
		(state_q == StFatalHold) ||
		(state_d == StFatalHold);
	assign state_debug_o = state_q;

	always_ff @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= StIdle;
			operation_restore_q <= 1'b0;
			result_success_q <= 1'b0;
			result_aborted_q <= 1'b0;
			restore_begin_seen_q <= 1'b0;
			pass1_seen_q <= 1'b0;
			mutation_seen_q <= 1'b0;
			restore_commit_seen_q <= 1'b0;
			stream_busy_seen_q <= 1'b0;
			sprite_frame_seen_q <= 1'b0;
			system_frame_seen_q <= 1'b0;
			watchdog_count_q <=
				{WATCHDOG_COUNT_WIDTH{1'b0}};
			watchdog_expired_q <= 1'b0;
			vblank_d_q <= 1'b0;
			request_accepted_o <= 1'b0;
			request_rejected_o <= 1'b0;
			timeout_pulse_o <= 1'b0;
			last_error_o <= ERR_NONE;
			last_stream_error_o <= 8'd0;
		end else begin
			state_q <= state_d;
			vblank_d_q <= vblank_i;
			request_accepted_o <= 1'b0;
			request_rejected_o <= 1'b0;
			timeout_pulse_o <= 1'b0;

			if ((state_q != StIdle) && any_request)
				request_rejected_o <= 1'b1;

			if (state_q == StIdle) begin
				if (any_request) begin
					operation_restore_q <=
						restore_request_i &&
						!save_request_i;
					result_success_q <= 1'b0;
					result_aborted_q <= 1'b0;
					restore_begin_seen_q <= 1'b0;
					pass1_seen_q <= 1'b0;
					mutation_seen_q <= 1'b0;
					restore_commit_seen_q <= 1'b0;
					stream_busy_seen_q <= 1'b0;
					sprite_frame_seen_q <= 1'b0;
					system_frame_seen_q <= 1'b0;
					last_stream_error_o <= 8'd0;

					if (request_collision) begin
						request_rejected_o <= 1'b1;
						last_error_o <=
							ERR_REQUEST_COLLISION;
					end else if (abort_i) begin
						request_rejected_o <= 1'b1;
						result_aborted_q <= 1'b1;
						last_error_o <= ERR_ABORTED;
					end else begin
						last_error_o <= ERR_NONE;
					end
				end
			end

			if (state_q == StQuiesceWaitAck) begin
				if (quiesce_request_accepted_i) begin
					request_accepted_o <= 1'b1;
					request_rejected_o <= 1'b0;
				end
				if (quiesce_request_rejected_i) begin
					request_rejected_o <= 1'b1;
					result_success_q <= 1'b0;
					result_aborted_q <= 1'b0;
					last_error_o <= ERR_QUIESCE_REJECTED;
				end
				if (watchdog_expired) begin
					timeout_pulse_o <= 1'b1;
					result_success_q <= 1'b0;
					result_aborted_q <= 1'b0;
					last_error_o <= ERR_QUIESCE_TIMEOUT;
				end
			end

			if (state_q == StQuiesceWaitIdle) begin
				if (quiesce_timeout_i ||
				    watchdog_expired) begin
					timeout_pulse_o <= 1'b1;
					result_success_q <= 1'b0;
					result_aborted_q <= 1'b0;
					last_error_o <= ERR_QUIESCE_TIMEOUT;
				end
			end

			if (state_q == StStreamWait) begin
				if (stream_busy_i)
					stream_busy_seen_q <= 1'b1;
				if (legal_restore_begin)
					restore_begin_seen_q <= 1'b1;
				if (stream_pass1_complete_i)
					pass1_seen_q <= 1'b1;
				if (stream_mutated_i)
					mutation_seen_q <= 1'b1;
				if (legal_restore_commit)
					restore_commit_seen_q <= 1'b1;

				if (stream_done_i) begin
					last_stream_error_o <=
						stream_error_code_i;
					result_aborted_q <= 1'b0;
					if (operation_restore_q) begin
						result_success_q <=
							restore_done_good;
						last_error_o <=
							restore_done_good
								? ERR_NONE
								: ERR_STREAM_FAILED;
						sprite_frame_seen_q <= 1'b0;
						system_frame_seen_q <= 1'b0;
					end else begin
						result_success_q <=
							stream_success_i &&
							!stream_format_error_i;
						last_error_o <=
							(stream_success_i &&
							 !stream_format_error_i)
								? ERR_NONE
								: ERR_STREAM_FAILED;
					end
				end

				if (watchdog_expired) begin
					timeout_pulse_o <= 1'b1;
					result_success_q <= 1'b0;
					result_aborted_q <= 1'b0;
					last_error_o <= ERR_STREAM_TIMEOUT;
				end
			end

			// A save may report its already-linearized final detector while
			// the controller is fencing an abort. Preserve the stream's
			// authoritative success and do not misreport it as cancelled.
			if (((state_q == StStreamWait) ||
			     (state_q == StAbortAssert)) &&
			    save_done_committed) begin
				result_success_q <= 1'b1;
				result_aborted_q <= 1'b0;
				last_error_o <= ERR_NONE;
				last_stream_error_o <=
					stream_error_code_i;
			end

			if ((state_q == StCleanRelease) &&
			    watchdog_expired) begin
				timeout_pulse_o <= 1'b1;
				result_success_q <= 1'b0;
				result_aborted_q <= 1'b0;
				last_error_o <= ERR_RELEASE_TIMEOUT;
			end

			if ((state_q == StReconstructWait) &&
			    sprite_frame_complete_i)
				sprite_frame_seen_q <= 1'b1;
			if ((state_q == StReconstructWait) &&
			    system_frame_complete_i)
				system_frame_seen_q <= 1'b1;

			if (((state_q == StReconstructStart) ||
			     (state_q == StReconstructWait) ||
			     (state_q == StRestoreRelease)) &&
			    watchdog_expired) begin
				timeout_pulse_o <= 1'b1;
				result_success_q <= 1'b0;
				result_aborted_q <= 1'b0;
				last_error_o <= ERR_RECON_TIMEOUT;
			end

			if ((state_q == StAbortWait) &&
			    watchdog_expired) begin
				timeout_pulse_o <= 1'b1;
				result_success_q <= 1'b0;
				result_aborted_q <= 1'b0;
				last_error_o <= ERR_ABORT_TIMEOUT;
			end

			if (abort_i &&
			    (state_q != StIdle) &&
			    (state_q != StComplete) &&
			    (state_q != StFatalHold) &&
			    !save_done_committed &&
			    !save_commit_latched) begin
				result_success_q <= 1'b0;
				if (restore_pass2_active ||
				    (state_q == StReconstructStart) ||
				    (state_q == StReconstructWait) ||
				    (state_q == StRestoreRelease)) begin
					result_aborted_q <= 1'b0;
					last_error_o <=
						ERR_POST_COMMIT_ABORT;
				end else begin
					result_aborted_q <= 1'b1;
					last_error_o <= ERR_ABORTED;
				end
			end

			if ((state_q == StAbortAssert) &&
			    !result_aborted_q &&
			    (last_error_o == ERR_NONE))
				last_error_o <= ERR_ABORTED;

			if ((state_d == StFatalHold) &&
			    (state_q != StFatalHold)) begin
				result_success_q <= 1'b0;
				result_aborted_q <= 1'b0;
				if (stream_fatal_i) begin
					last_error_o <= ERR_STREAM_FATAL;
					last_stream_error_o <=
						stream_error_code_i;
				end else if (quiesce_fatal_hold_i) begin
					last_error_o <= ERR_QUIESCE_FATAL;
				end else if (unexpected_restore_commit ||
				             (stream_done_i &&
				              operation_restore_q &&
				              !restore_done_good &&
				              !restore_done_recoverable)) begin
					last_error_o <= ERR_COMMIT;
				end else if (contract_fault ||
				             ((state_q == StStreamStart) &&
				              stream_busy_i)) begin
					last_error_o <= ERR_PROTOCOL;
				end else if (watchdog_expired) begin
					timeout_pulse_o <= 1'b1;
					last_error_o <=
						((state_q == StReconstructStart) ||
						 (state_q == StReconstructWait) ||
						 (state_q == StRestoreRelease))
							? ERR_RECON_TIMEOUT
							: ERR_FATAL_TIMEOUT;
				end else if (abort_i) begin
					last_error_o <=
						ERR_POST_COMMIT_ABORT;
				end else begin
					last_error_o <= ERR_PROTOCOL;
				end
			end

			if (watchdog_phase_exit || !watchdog_state ||
			    (WATCHDOG_TIMEOUT_CYCLES <= 1)) begin
				watchdog_count_q <=
					{WATCHDOG_COUNT_WIDTH{1'b0}};
				watchdog_expired_q <= 1'b0;
			end else if (!watchdog_expired_q) begin
				watchdog_count_q <=
					watchdog_count_q + 1'b1;
				watchdog_expired_q <= watchdog_preexpire;
			end
		end
	end

endmodule

`default_nettype wire
