`default_nettype none

// Diagnostic-only, compact save-release discriminator.
//
// The earlier diagnostic used two 128-bit ISSP instances plus broad state
// snapshots.  At this nearly-full Cyclone V that instrumentation alone made
// the image unfit.  This observer retains only the decisive post-stream facts:
// the three controller states, the live Main/Sound release endpoints, exact
// one-versus-duplicate event counts, the Mazinger IRQ1 admission witness, and
// terminal/fault classes.  Page selection is observational only.
module CaveBanprestoSaveStateReleaseSlimHardwareDiagnostic (
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire [1:0]  page_select_i,
	input  wire [3:0]  game_index_i,

	input  wire [3:0]  controller_state_i,
	input  wire [3:0]  quiesce_state_i,
	input  wire [4:0]  coordinator_state_i,
	input  wire        ss_active_i,
	input  wire        controller_active_i,
	input  wire        quiesce_busy_i,
	input  wire        release_pending_i,

	input  wire        main_request_i,
	input  wire        main_restore_i,
	input  wire        main_complete_i,
	input  wire        main_ready_i,
	input  wire        main_busy_i,
	input  wire        sound_request_i,
	input  wire        sound_restore_i,
	input  wire        sound_complete_i,
	input  wire        sound_ready_i,
	input  wire        sound_busy_i,
	input  wire        controller_done_i,
	input  wire        controller_success_i,
	input  wire        raw_stream_done_i,
	input  wire        raw_stream_success_i,
	input  wire        quiesce_freeze_i,
	input  wire        quiesce_resume_i,
	input  wire        release_complete_i,

	input  wire        controller_accepted_event_i,
	input  wire        controller_rejected_event_i,
	input  wire        controller_done_event_i,
	input  wire        controller_success_event_i,
	input  wire        controller_aborted_event_i,
	input  wire        main_request_event_i,
	input  wire        main_complete_event_i,
	input  wire        sound_request_event_i,
	input  wire        sound_complete_event_i,
	input  wire        capture_admitted_seen_i,

	input  wire [16:0] fault_flags_i,
	output wire [15:0] probe_o
);

	// B8/v2 is a single-word, source-independent terminal ledger. Reducing
	// the probe from four 32-bit pages to one 16-bit word removes JTAG shift
	// and page-mux pressure while retaining every fact needed to distinguish
	// capture admission, endpoint completion, and fail-closed termination.
	localparam [3:0] PROBE_SIGNATURE = 4'hB;
	localparam [1:0] PROBE_VERSION = 2'd2;

	logic controller_accepted_seen_q;
	logic controller_done_seen_q;
	logic controller_success_seen_q;
	logic main_request_seen_q;
	logic main_complete_seen_q;
	logic sound_request_seen_q;
	logic sound_complete_seen_q;
	logic release_complete_seen_q;
	logic fault_seen_q;

	always_ff @(posedge clk_i) begin
		if (reset_i) begin
			controller_accepted_seen_q <= 1'b0;
			controller_done_seen_q <= 1'b0;
			controller_success_seen_q <= 1'b0;
			main_request_seen_q <= 1'b0;
			main_complete_seen_q <= 1'b0;
			sound_request_seen_q <= 1'b0;
			sound_complete_seen_q <= 1'b0;
			release_complete_seen_q <= 1'b0;
			fault_seen_q <= 1'b0;
		end else begin
			if (controller_accepted_event_i)
				controller_accepted_seen_q <= 1'b1;
			if (controller_done_event_i)
				controller_done_seen_q <= 1'b1;
			if (controller_success_event_i)
				controller_success_seen_q <= 1'b1;
			if (main_request_event_i)
				main_request_seen_q <= 1'b1;
			if (main_complete_event_i)
				main_complete_seen_q <= 1'b1;
			if (sound_request_event_i)
				sound_request_seen_q <= 1'b1;
			if (sound_complete_event_i)
				sound_complete_seen_q <= 1'b1;
			if (release_complete_i)
				release_complete_seen_q <= 1'b1;
			if (controller_rejected_event_i ||
			    controller_aborted_event_i ||
			    (|fault_flags_i))
				fault_seen_q <= 1'b1;
		end
	end

	assign probe_o = {
		PROBE_SIGNATURE,
		PROBE_VERSION,
		controller_accepted_seen_q,
		controller_done_seen_q,
		controller_success_seen_q,
		main_request_seen_q,
		main_complete_seen_q,
		sound_request_seen_q,
		sound_complete_seen_q,
		capture_admitted_seen_i,
		release_complete_seen_q,
		fault_seen_q
	};

endmodule

`default_nettype wire
