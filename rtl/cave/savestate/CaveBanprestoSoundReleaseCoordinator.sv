`default_nettype none

// CaveBanpresto-local SoundZ80 release coordinator.
//
// release_authorize_i is the single, globally qualified release authorization
// for one save/restore operation.  The current controller supplies that pulse
// only after the ordered Sound commit command has completed.  Consequently,
// restore_commit_authorized_i and the resulting T80 restore_load_i may precede
// the global release authorization.  This coordinator retains that exact
// command-qualified preload proof while remaining stopped, then consumes the
// later release authorization without treating the legitimate preload as an
// unsolicited mutation.
//
// release_restore_i is sampled only with release_authorize_i.  It must map to
// reconstruction_start_o, not the immutable operation_restore_o: it is high
// only for a successfully committed restore release, and low for save and
// recoverable pass-1 unwind.  A committed restore authorization requires the
// retained command-qualified T80 load proof.  This block keeps sound_release_o
// low during that load, waits for the private canonical launch, and then waits
// for every external/dependency/owner proof before issuing one exact release
// pulse.
//
// All inputs are synchronous to clk_i.  reset_i is active high and is assumed
// to have been released synchronously by the integration layer.  abort_i is the
// same qualified level presented to CaveBanprestoSoundZ80SaveState.ss_abort_i.
// A pre-DIRSet abort cancels the authorization and waits for Sound recovery.
// An abort after an accepted restore_load_i is terminal because restored state
// has already mutated.  fatal_i and local protocol faults enter a reset-only
// fail-closed state.
module CaveBanprestoSoundReleaseCoordinator (
	input  wire       clk_i,
	input  wire       reset_i,

	input  wire       release_authorize_i,
	input  wire       release_restore_i,
	input  wire       restore_commit_authorized_i,

	input  wire       sound_stopped_i,
	input  wire       restore_load_i,
	input  wire       restore_launch_done_i,
	input  wire       external_idle_i,
	input  wire       restore_dependencies_ready_i,
	input  wire       owner_commit_idle_i,

	input  wire       abort_i,
	input  wire       sound_abort_ack_i,
	input  wire       fatal_i,

	output wire       sound_release_o,
	output wire       release_pending_o,
	output wire       release_ready_o,
	output logic      release_complete_o,
	output logic      terminal_fault_o,
	output wire [2:0] state_debug_o
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
	,
	output wire [5:0] proof_debug_o
`endif
);

	typedef enum logic [2:0] {
		StIdle        = 3'd0,
		StPending     = 3'd1,
		StPulse       = 3'd2,
		StWaitRunning = 3'd3,
		StAbortWait   = 3'd4,
		StFatalHold   = 3'd5
	} release_state_e;

	release_state_e state_q;
	release_state_e state_d;

	// Justification: the committed-restore qualifier and restore milestones
	// must survive the one-cycle global authorization and independently
	// arriving proofs.
	logic restore_mode_q;
	logic restore_commit_seen_q;
	logic restore_load_seen_q;
	logic restore_launch_seen_q;

	// Justification: Sound may stop after abort begins, so a late stop creates
	// an acknowledgement obligation before this coordinator can re-arm.
	logic abort_need_ack_q;
	logic abort_ack_seen_q;

	logic protocol_fault;

	wire common_release_proof =
		sound_stopped_i &&
		external_idle_i &&
		restore_dependencies_ready_i &&
		owner_commit_idle_i &&
		!restore_load_i;
	wire restore_release_proof =
		restore_load_seen_q &&
		(restore_launch_seen_q || restore_launch_done_i);
	wire post_mutation_abort =
		abort_i &&
		restore_load_seen_q &&
		((state_q == StIdle) ||
		 (state_q == StPending) ||
		 (state_q == StPulse) ||
		 (state_q == StWaitRunning));
	wire abort_recovered =
		(!abort_need_ack_q && !sound_stopped_i) ||
		abort_ack_seen_q ||
		sound_abort_ack_i;

	assign release_pending_o =
		(state_q == StPending) ||
		(state_q == StPulse) ||
		(state_q == StWaitRunning);
	assign release_ready_o =
		(state_q == StPending) &&
		common_release_proof &&
		(!restore_mode_q || restore_release_proof) &&
		!abort_i &&
		!fatal_i &&
		!terminal_fault_o;

	// The current-cycle masks are deliberate.  They suppress an authorization
	// that was scheduled one cycle earlier if reset, abort, fatal poison, or a
	// malformed late restore load races the sampling edge.
	assign sound_release_o =
		!reset_i &&
		!abort_i &&
		!fatal_i &&
		!protocol_fault &&
		!terminal_fault_o &&
		(state_q == StPulse) &&
		common_release_proof &&
		(!restore_mode_q || restore_release_proof);
	assign state_debug_o = state_q;
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
	assign proof_debug_o = {
		restore_mode_q,
		restore_commit_seen_q,
		restore_load_seen_q,
		restore_launch_seen_q,
		common_release_proof,
		restore_release_proof
	};
`endif

	// Strict local protocol policing.  Controls coincident with abort/fatal are
	// consumed by those higher-priority paths and therefore are not separately
	// diagnosed here.
	always_comb begin
		protocol_fault = 1'b0;

		if (!reset_i && !abort_i && !fatal_i) begin
			unique case (state_q)
				StIdle: begin
					if (release_authorize_i) begin
						if (!sound_stopped_i ||
						    restore_commit_authorized_i ||
						    (release_restore_i &&
						     !restore_load_seen_q) ||
						    (!release_restore_i &&
						     (restore_commit_seen_q ||
						      restore_load_seen_q ||
						      restore_load_i ||
						      restore_launch_done_i)))
							protocol_fault = 1'b1;
					end else begin
						if (restore_commit_authorized_i &&
						    (!sound_stopped_i ||
						     restore_commit_seen_q ||
						     restore_load_seen_q ||
						     restore_load_i ||
						     restore_launch_done_i))
							protocol_fault = 1'b1;

						if (restore_load_i &&
						    (!sound_stopped_i ||
						     !restore_commit_seen_q ||
						     restore_load_seen_q))
							protocol_fault = 1'b1;

						if (restore_launch_done_i &&
						    !(restore_load_seen_q ||
						      restore_load_i))
							protocol_fault = 1'b1;
					end
				end

				StPending: begin
					if (release_authorize_i ||
					    restore_commit_authorized_i ||
					    !sound_stopped_i) begin
						protocol_fault = 1'b1;
					end

					if (restore_load_i) begin
						protocol_fault = 1'b1;
					end

					if (restore_launch_done_i &&
					    (!restore_mode_q ||
					     !restore_load_seen_q)) begin
						protocol_fault = 1'b1;
					end
				end

				StPulse: begin
					if (release_authorize_i ||
					    restore_commit_authorized_i ||
					    restore_load_i ||
					    !sound_stopped_i)
						protocol_fault = 1'b1;
				end

				StWaitRunning: begin
					if (release_authorize_i ||
					    restore_commit_authorized_i ||
					    restore_load_i)
						protocol_fault = 1'b1;
				end

				StAbortWait: begin
					if (!abort_i &&
					    (release_authorize_i ||
					     restore_commit_authorized_i ||
					     restore_load_i))
						protocol_fault = 1'b1;
				end

				StFatalHold: begin
					protocol_fault = 1'b0;
				end

				default: begin
					protocol_fault = 1'b1;
				end
			endcase
		end
	end

	always_comb begin
		state_d = state_q;

		if (fatal_i || protocol_fault || post_mutation_abort) begin
			state_d = StFatalHold;
		end else begin
			unique case (state_q)
				StIdle: begin
					if (abort_i)
						state_d = StAbortWait;
					else if (release_authorize_i)
						state_d = StPending;
				end

				StPending: begin
					if (abort_i)
						state_d = StAbortWait;
					else if (release_ready_o)
						state_d = StPulse;
				end

				StPulse: begin
					if (abort_i)
						state_d = StAbortWait;
					else if (sound_release_o)
						state_d = StWaitRunning;
					else
						state_d = StPending;
				end

				StWaitRunning: begin
					if (abort_i)
						state_d = StAbortWait;
					else if (!sound_stopped_i)
						state_d = StIdle;
				end

				StAbortWait: begin
					if (!abort_i && abort_recovered)
						state_d = StIdle;
				end

				StFatalHold: begin
					state_d = StFatalHold;
				end

				default: begin
					state_d = StFatalHold;
				end
			endcase
		end
	end

	always_ff @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= StIdle;
			restore_mode_q <= 1'b0;
			restore_commit_seen_q <= 1'b0;
			restore_load_seen_q <= 1'b0;
			restore_launch_seen_q <= 1'b0;
			abort_need_ack_q <= 1'b0;
			abort_ack_seen_q <= 1'b0;
			release_complete_o <= 1'b0;
			terminal_fault_o <= 1'b0;
		end else begin
			state_q <= state_d;
			release_complete_o <= 1'b0;

			if (fatal_i || protocol_fault ||
			    post_mutation_abort)
				terminal_fault_o <= 1'b1;

			if ((state_q == StIdle) &&
			    !abort_i &&
			    !fatal_i &&
			    !protocol_fault &&
			    !post_mutation_abort) begin
				if (state_d == StPending) begin
					restore_mode_q <= release_restore_i;
					if (!release_restore_i) begin
						restore_commit_seen_q <= 1'b0;
						restore_load_seen_q <= 1'b0;
						restore_launch_seen_q <= 1'b0;
					end else if (restore_launch_done_i) begin
						restore_launch_seen_q <= 1'b1;
					end
				end else begin
					if (restore_commit_authorized_i)
						restore_commit_seen_q <= 1'b1;
					if (restore_load_i &&
					    restore_commit_seen_q)
						restore_load_seen_q <= 1'b1;
					if (restore_launch_done_i &&
					    (restore_load_seen_q ||
					     restore_load_i))
						restore_launch_seen_q <= 1'b1;
				end
			end else if (state_q == StPending) begin
				if (restore_mode_q &&
				    restore_load_seen_q &&
				    restore_launch_done_i)
					restore_launch_seen_q <= 1'b1;
			end

			if ((state_q != StAbortWait) &&
			    (state_d == StAbortWait)) begin
				abort_need_ack_q <= sound_stopped_i;
				abort_ack_seen_q <= sound_abort_ack_i;
			end else if (state_q == StAbortWait) begin
				if (sound_stopped_i)
					abort_need_ack_q <= 1'b1;
				if (sound_abort_ack_i)
					abort_ack_seen_q <= 1'b1;
			end

			if ((state_q == StWaitRunning) &&
			    (state_d == StIdle))
				release_complete_o <= 1'b1;

			if ((state_q != StIdle) &&
			    (state_d == StIdle)) begin
				restore_mode_q <= 1'b0;
				restore_commit_seen_q <= 1'b0;
				restore_load_seen_q <= 1'b0;
				restore_launch_seen_q <= 1'b0;
				abort_need_ack_q <= 1'b0;
				abort_ack_seen_q <= 1'b0;
			end
		end
	end

endmodule

`default_nettype wire
