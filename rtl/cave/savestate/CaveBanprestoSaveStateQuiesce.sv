// SPDX-License-Identifier: GPL-2.0-or-later
//
// CaveBanpresto-local, support-disabled save-state quiesce coordinator.
//
// This module is intentionally not connected to the core. All inputs are
// synchronous to clk; any vblank, CPU, idle, or control signal originating in
// another clock domain must be synchronized before it reaches this boundary.
// The active-high reset input is likewise assumed to have been released
// synchronously to clk by the integration layer.
//
// A request is a one-cycle pulse. It is admitted only while idle and only when
// identity, profile support, IOCTL idleness, and boot completion are all true.
// After a vblank rendezvous, freeze and block_new_work remain asserted through
// CPU capture/stop, drain qualification, and the quiesced interval. During the
// release fence, CPU stop requests and generic block_new_work are removed so
// exact participant release and reconstruction can run, while freeze and the
// sound-ROM launch gate stay asserted until the integration layer returns one
// aggregate completion proof.
//
// operation_fatal represents an unrecoverable downstream save or restore
// fault. Examples include a pass-2 restore fault after mutation began and an
// accepted DDR read whose response timed out, leaving the maintenance path
// poisoned. Such a fault enters a reset-only fail-closed state that keeps the
// machine frozen. An abort after freeze enters an explicit recovery hold: the
// issued CPU holds and freeze remain asserted until every participant already
// known stopped has acknowledged safe recovery, followed by a fault-observation
// fence cycle. A pre-freeze abort still unwinds directly.
module CaveBanprestoSaveStateQuiesce #(
	parameter integer IDLE_ACK_COUNT = 1,
	parameter integer IDLE_STABLE_CYCLES = 4,
	parameter integer PHASE_TIMEOUT_CYCLES = 1_000_000,
	// At 96 MHz the native 448x272 frame is 1,671,168 clocks.  Keep the
	// transparent pre-freeze rendezvous longer than a complete frame without
	// weakening the tighter CPU-stop, drain, release, and abort bounds.
	parameter integer VBLANK_TIMEOUT_CYCLES = 2_000_000
) (
	input  wire                      clk,
	input  wire                      reset,

	input  wire                      request,
	input  wire                      request_restore,
	input  wire                      abort,
	input  wire                      resume,
	input  wire                      release_complete,
	input  wire                      operation_fatal,

	input  wire                      identity_valid,
	input  wire                      profile_supported,
	input  wire                      ioctl_idle,
	input  wire                      boot_ready,
	input  wire                      vblank,

	input  wire                      main_cpu_captured,
	input  wire                      sound_cpu_stopped,
	input  wire                      main_cpu_abort_ack,
	input  wire                      sound_cpu_abort_ack,
	input  wire [IDLE_ACK_COUNT-1:0] idle_ack,

	output wire                      busy,
	output wire                      freeze,
	output wire                      block_new_work,
	output wire                      main_cpu_capture_req,
	output wire                      sound_cpu_stop_req,
	output wire                      quiesced,
	output reg                       quiesced_pulse,
	output reg                       request_accepted,
	output reg                       request_rejected,
	output reg                       abort_pulse,
	output reg                       abort_complete_pulse,
	output reg                       timeout_pulse,
	output wire                      restore_active,
	output wire                      fatal_hold,
	output wire                      abort_active,
	output wire                      sound_rom_launch_block,
	output wire [3:0]                phase
);

	localparam integer MAX_TIMEOUT_CYCLES =
		(VBLANK_TIMEOUT_CYCLES > PHASE_TIMEOUT_CYCLES)
			? VBLANK_TIMEOUT_CYCLES : PHASE_TIMEOUT_CYCLES;
	localparam integer PHASE_COUNT_WIDTH =
		(MAX_TIMEOUT_CYCLES <= 1) ? 1 : $clog2(MAX_TIMEOUT_CYCLES);
	localparam integer IDLE_COUNT_WIDTH =
		(IDLE_STABLE_CYCLES <= 1) ? 1 : $clog2(IDLE_STABLE_CYCLES);

	localparam integer PHASE_COUNT_LIMIT =
		(PHASE_TIMEOUT_CYCLES <= 1) ? 0 : PHASE_TIMEOUT_CYCLES - 1;
	localparam integer VBLANK_COUNT_LIMIT =
		(VBLANK_TIMEOUT_CYCLES <= 1) ? 0 : VBLANK_TIMEOUT_CYCLES - 1;
	localparam integer IDLE_COUNT_LIMIT = IDLE_STABLE_CYCLES - 1;

	typedef enum logic [3:0] {
		StIdle        = 4'd0,
		StWaitVblank  = 4'd1,
		StWaitMainCpu = 4'd2,
		StWaitSoundCpu= 4'd3,
		StWaitIdle    = 4'd4,
		StQuiesced    = 4'd5,
		StReleaseHold = 4'd6,
		StFatalHold   = 4'd7,
		StAbortHold   = 4'd8
	} quiesce_state_e;

	quiesce_state_e state_q;
	quiesce_state_e state_d;

	// Justification: remembers whether the admitted operation is a restore.
	reg restore_q;
	// Justification: bounds each external wait independently.
	reg [PHASE_COUNT_WIDTH-1:0] phase_count_q;
	// Justification: rejects transient idle indications.
	reg [IDLE_COUNT_WIDTH-1:0] idle_count_q;
	// Justification: records which participants have actually reached a
	// stopped boundary during the current operation.
	reg main_stopped_seen_q;
	reg sound_stopped_seen_q;
	// Justification: freezes the recovery obligation and issued-request mask
	// when abort recovery begins.
	reg abort_need_main_q;
	reg abort_need_sound_q;
	reg abort_hold_main_q;
	reg abort_hold_sound_q;
	// Justification: accepts one-cycle participant acknowledgement pulses.
	reg abort_main_ack_seen_q;
	reg abort_sound_ack_seen_q;
	// Justification: holds one full cycle after all acknowledgements so a
	// terminal fault generated at an acknowledgement edge is observed.
	reg abort_fence_q;

	wire admission_ok =
		identity_valid && profile_supported && ioctl_idle && boot_ready;
	wire all_idle =
		main_cpu_captured && sound_cpu_stopped && (&idle_ack);
	wire waiting_phase =
		(state_q == StWaitVblank) ||
		(state_q == StWaitMainCpu) ||
		(state_q == StWaitSoundCpu) ||
		(state_q == StWaitIdle) ||
		(state_q == StReleaseHold) ||
		(state_q == StAbortHold);
	wire current_timeout_disabled =
		(state_q == StWaitVblank)
			? (VBLANK_TIMEOUT_CYCLES == 0)
			: (PHASE_TIMEOUT_CYCLES == 0);
	wire phase_timeout =
		(state_q == StWaitVblank)
			? ((VBLANK_TIMEOUT_CYCLES != 0) &&
			   (phase_count_q == VBLANK_COUNT_LIMIT))
			: ((PHASE_TIMEOUT_CYCLES != 0) &&
			   (phase_count_q == PHASE_COUNT_LIMIT));
	// Only transitions between independently bounded wait phases require the
	// counter to clear on the transition edge.  Transitions into a non-wait or
	// fatal state clear on the following cycle, where the count is unobserved.
	// Keep terminal-fault decode out of this wide counter's synchronous clear.
	wire wait_to_wait_transition =
		((state_q == StWaitVblank) && vblank) ||
		((state_q == StWaitMainCpu) &&
		 (abort || main_cpu_captured || phase_timeout)) ||
		((state_q == StWaitSoundCpu) &&
		 (abort || sound_cpu_stopped || phase_timeout)) ||
		((state_q == StWaitIdle) && (abort || phase_timeout)) ||
		((state_q == StReleaseHold) && abort);
	wire idle_stable =
		all_idle &&
		((IDLE_STABLE_CYCLES <= 1) ||
		 (idle_count_q == IDLE_COUNT_LIMIT));
	// These predicates have priority over phase_timeout in the next-state
	// decoder.  Suppress the registered timeout pulse on the same edge so the
	// controller observes the same outcome as this FSM instead of aborting a
	// phase that completed exactly at its deadline.
	wire phase_completion_wins =
		((((state_q == StWaitVblank) && vblank) ||
		  ((state_q == StWaitMainCpu) && main_cpu_captured) ||
		  ((state_q == StWaitSoundCpu) && sound_cpu_stopped) ||
		  ((state_q == StWaitIdle) && idle_stable) ||
		  ((state_q == StReleaseHold) && release_complete)) === 1'b1);
	// Abort has priority in every bounded normal wait, but AbortHold keeps the
	// request asserted as part of recovery.  Do not let that expected level
	// hide a genuine abort-recovery timeout.
	wire abort_wins_over_timeout =
		(state_q != StAbortHold) && (abort === 1'b1);
	// Terminal participant poison is reset-only even if it becomes visible
	// between operations. Never admit a new request through a sticky fault.
	wire fatal_operation_event = operation_fatal;
	wire abort_main_recovered =
		abort_main_ack_seen_q || main_cpu_abort_ack;
	wire abort_sound_recovered =
		abort_sound_ack_seen_q || sound_cpu_abort_ack;
	wire abort_recovery_done =
		((!abort_need_main_q && !main_cpu_captured) ||
		 abort_main_recovered) &&
		((!abort_need_sound_q && !sound_cpu_stopped) ||
		 abort_sound_recovered);

	assign busy = state_q != StIdle;
	assign freeze =
		(state_q == StWaitMainCpu) ||
		(state_q == StWaitSoundCpu) ||
		(state_q == StWaitIdle) ||
		(state_q == StQuiesced) ||
		(state_q == StReleaseHold) ||
		(state_q == StAbortHold) ||
		(state_q == StFatalHold);
	// Generic maintenance admission control. The continuously-prefetching
	// sound-ROM path must use sound_rom_launch_block instead. ReleaseHold
	// deliberately reopens reconstructible gameplay clients while HDMI remains
	// frozen and owner 34 retains its dedicated launch gate.
	assign block_new_work = freeze && (state_q != StReleaseHold);
	assign main_cpu_capture_req =
		(state_q == StWaitMainCpu) ||
		(state_q == StWaitSoundCpu) ||
		(state_q == StWaitIdle) ||
		(state_q == StQuiesced) ||
		((state_q == StAbortHold) && abort_hold_main_q) ||
		(state_q == StFatalHold);
	assign sound_cpu_stop_req =
		(state_q == StWaitSoundCpu) ||
		(state_q == StWaitIdle) ||
		(state_q == StQuiesced) ||
		((state_q == StAbortHold) && abort_hold_sound_q) ||
		(state_q == StFatalHold);
	assign quiesced = state_q == StQuiesced;
	assign restore_active = restore_q && (state_q != StIdle);
	assign fatal_hold = state_q == StFatalHold;
	assign abort_active = state_q == StAbortHold;
	// Owner 34 may continue its normal prefetch until the sound CPU has
	// actually stopped. Once asserted, this launch gate remains sticky through
	// drain, abort recovery, and any reset-only fatal hold.
	assign sound_rom_launch_block =
		((state_q == StWaitSoundCpu) ||
		 (state_q == StWaitIdle) ||
		 (state_q == StQuiesced) ||
		 (state_q == StReleaseHold) ||
		 (state_q == StAbortHold) ||
		 (state_q == StFatalHold)) &&
		(sound_stopped_seen_q || sound_cpu_stopped);
	assign phase = state_q;

	always_comb begin
		state_d = state_q;

		unique case (state_q)
			StIdle: begin
				if (fatal_operation_event)
					state_d = StFatalHold;
				else if (request && admission_ok)
					state_d = StWaitVblank;
			end

			StWaitVblank: begin
				if (fatal_operation_event)
					state_d = StFatalHold;
				else if (abort)
					state_d = StIdle;
				else if (vblank)
					state_d = StWaitMainCpu;
				else if (phase_timeout)
					state_d = StIdle;
			end

			StWaitMainCpu: begin
				if (fatal_operation_event)
					state_d = StFatalHold;
				else if (abort)
					state_d = StAbortHold;
				else if (main_cpu_captured)
					state_d = StWaitSoundCpu;
				else if (phase_timeout)
					state_d = StAbortHold;
			end

			StWaitSoundCpu: begin
				if (fatal_operation_event)
					state_d = StFatalHold;
				else if (abort)
					state_d = StAbortHold;
				else if (sound_cpu_stopped)
					state_d = StWaitIdle;
				else if (phase_timeout)
					state_d = StAbortHold;
			end

			StWaitIdle: begin
				if (fatal_operation_event)
					state_d = StFatalHold;
				else if (abort)
					state_d = StAbortHold;
				else if (idle_stable)
					state_d = StQuiesced;
				else if (phase_timeout)
					state_d = StAbortHold;
			end

			StQuiesced: begin
				if (fatal_operation_event)
					state_d = StFatalHold;
				else if (abort)
					state_d = StAbortHold;
				else if (resume)
					state_d = StReleaseHold;
			end

			StReleaseHold: begin
				if (fatal_operation_event)
					state_d = StFatalHold;
				else if (abort)
					state_d = StAbortHold;
				else if (release_complete)
					state_d = StIdle;
				else if (phase_timeout)
					state_d = StFatalHold;
			end

			StAbortHold: begin
				if (fatal_operation_event || phase_timeout)
					state_d = StFatalHold;
				else if (abort_fence_q && abort_recovery_done)
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

	always_ff @(posedge clk) begin
		if (reset) begin
			state_q <= StIdle;
			restore_q <= 1'b0;
			phase_count_q <= {PHASE_COUNT_WIDTH{1'b0}};
			idle_count_q <= {IDLE_COUNT_WIDTH{1'b0}};
			main_stopped_seen_q <= 1'b0;
			sound_stopped_seen_q <= 1'b0;
			abort_need_main_q <= 1'b0;
			abort_need_sound_q <= 1'b0;
			abort_hold_main_q <= 1'b0;
			abort_hold_sound_q <= 1'b0;
			abort_main_ack_seen_q <= 1'b0;
			abort_sound_ack_seen_q <= 1'b0;
			abort_fence_q <= 1'b0;
			quiesced_pulse <= 1'b0;
			request_accepted <= 1'b0;
			request_rejected <= 1'b0;
			abort_pulse <= 1'b0;
			abort_complete_pulse <= 1'b0;
			timeout_pulse <= 1'b0;
		end else begin
			state_q <= state_d;

			quiesced_pulse <= 1'b0;
			request_accepted <= 1'b0;
			request_rejected <= 1'b0;
			abort_pulse <= 1'b0;
			abort_complete_pulse <= 1'b0;
			timeout_pulse <= 1'b0;

			if (request) begin
				if ((state_q == StIdle) && admission_ok &&
				    !fatal_operation_event) begin
					request_accepted <= 1'b1;
					restore_q <= request_restore;
					main_stopped_seen_q <= 1'b0;
					sound_stopped_seen_q <= 1'b0;
					abort_need_main_q <= 1'b0;
					abort_need_sound_q <= 1'b0;
					abort_hold_main_q <= 1'b0;
					abort_hold_sound_q <= 1'b0;
					abort_main_ack_seen_q <= 1'b0;
					abort_sound_ack_seen_q <= 1'b0;
					abort_fence_q <= 1'b0;
				end else begin
					request_rejected <= 1'b1;
				end
			end

			if ((state_q != StIdle) && (state_d == StIdle)) begin
				restore_q <= 1'b0;
				main_stopped_seen_q <= 1'b0;
				sound_stopped_seen_q <= 1'b0;
				abort_need_main_q <= 1'b0;
				abort_need_sound_q <= 1'b0;
				abort_hold_main_q <= 1'b0;
				abort_hold_sound_q <= 1'b0;
				abort_main_ack_seen_q <= 1'b0;
				abort_sound_ack_seen_q <= 1'b0;
				abort_fence_q <= 1'b0;
			end

			if ((state_q != StIdle) && main_cpu_captured)
				main_stopped_seen_q <= 1'b1;
			if ((state_q != StIdle) && sound_cpu_stopped)
				sound_stopped_seen_q <= 1'b1;

			if ((state_q != StAbortHold) &&
			    (state_d == StAbortHold)) begin
				abort_need_main_q <=
					main_stopped_seen_q || main_cpu_captured;
				abort_need_sound_q <=
					sound_stopped_seen_q || sound_cpu_stopped;
				abort_hold_main_q <=
					(state_q == StWaitMainCpu) ||
					(state_q == StWaitSoundCpu) ||
					(state_q == StWaitIdle) ||
					(state_q == StQuiesced) ||
					(state_q == StReleaseHold);
				abort_hold_sound_q <=
					(state_q == StWaitSoundCpu) ||
					(state_q == StWaitIdle) ||
					(state_q == StQuiesced) ||
					(state_q == StReleaseHold);
				abort_main_ack_seen_q <= 1'b0;
				abort_sound_ack_seen_q <= 1'b0;
				abort_fence_q <= 1'b0;
			end else if (state_q == StAbortHold) begin
				// A request remains asserted during abort hold. If a
				// participant reaches stop after the abort edge, make
				// that late stop a recovery obligation before release.
				if (main_cpu_captured) begin
					abort_need_main_q <= 1'b1;
					if (!abort_main_recovered)
						abort_fence_q <= 1'b0;
				end
				if (sound_cpu_stopped) begin
					abort_need_sound_q <= 1'b1;
					if (!abort_sound_recovered)
						abort_fence_q <= 1'b0;
				end

				if (main_cpu_abort_ack)
					abort_main_ack_seen_q <= 1'b1;
				if (sound_cpu_abort_ack)
					abort_sound_ack_seen_q <= 1'b1;

				if (!abort_fence_q && abort_recovery_done &&
				    !fatal_operation_event && !phase_timeout)
					abort_fence_q <= 1'b1;
			end

			if ((state_q == StWaitIdle) &&
			    (state_d == StQuiesced))
				quiesced_pulse <= 1'b1;

			if ((state_q != StIdle) &&
			    (state_q != StFatalHold) &&
			    (state_q != StAbortHold) &&
			    abort && !fatal_operation_event)
				abort_pulse <= 1'b1;

			if ((state_q == StAbortHold) && (state_d == StIdle))
				abort_complete_pulse <= 1'b1;

			if (waiting_phase && phase_timeout &&
			    !phase_completion_wins &&
			    !fatal_operation_event &&
			    !abort_wins_over_timeout)
				timeout_pulse <= 1'b1;

			if (wait_to_wait_transition || !waiting_phase ||
			    current_timeout_disabled) begin
				phase_count_q <= {PHASE_COUNT_WIDTH{1'b0}};
			end else if (!phase_timeout) begin
				phase_count_q <= phase_count_q + 1'b1;
			end

			if ((state_q != StWaitIdle) || !all_idle ||
			    (IDLE_STABLE_CYCLES <= 1)) begin
				idle_count_q <= {IDLE_COUNT_WIDTH{1'b0}};
			end else begin
				idle_count_q <= idle_count_q + 1'b1;
			end
		end
	end

endmodule
