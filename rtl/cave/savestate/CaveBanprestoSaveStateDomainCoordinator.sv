`default_nettype none

// CaveBanpresto-local ordered Main/Sound save-state coordinator.
//
// This module is the system-clock barrier between the operation controller,
// quiesce coordinator, raw save-state stream, and the two CPU-clock endpoint
// sequencers.  Main and Sound share cpu_clk_i, but each owns an independent
// CaveBanprestoSaveStateControlCdc channel so an acknowledgement means that
// endpoint -- not merely the source clock -- applied the command.
//
// Command packet layout (COMMAND_WIDTH must cover every named field):
//   [4:0]                         opcode
//   [5 +: GAME_INDEX_WIDTH]       immutable gameIndex payload
//   [5+GAME_INDEX_WIDTH]          immutable stop-epoch restore intent
//   [COMMAND_WIDTH-1:
//      6+GAME_INDEX_WIDTH]        reserved, always zero
//
// The restore-intent bit is captured from Quiesce with the first STOP request:
// zero denotes a save epoch and one denotes a restore epoch.  Every later
// command repeats that frozen value.  Each endpoint must capture it on STOP
// and reject any later packet whose value disagrees with its captured epoch.
//
// The five-bit command enum is intentionally sparse and locally frozen:
//   0  NOP               (never transmitted)
//   1  STOP              capture/stop and acknowledge applied hold
//   2  BEGIN             begin restore staging, no live mutation
//   3  ENABLE            authorize endpoint pass-2 staging
//   4  ABORT             recover a transaction before mutation
//   5  NONCPU_COMMIT     Main owners 3/20/RAM/EEPROM
//   6  COMMIT            Sound devices and Sound staged state
//   7  CPU_FINAL_COMMIT  Main CPU context; globally last mutation
//
// RESPONSE_OK_VALUE is the only successful destination response.  Any other
// response, channel timeout, opposite-domain reset during a transaction,
// unsolicited completion, endpoint poison, high-level timeout, malformed raw
// stream transition, or abort after pass-2 mutation authorization enters the
// reset-only terminal state.
//
// CDC pattern: four-phase MCP word transfer.  CaveBanprestoSaveStateControlCdc
// latches each packet in sys_clk_i, holds it for the complete request/ack
// round trip, captures it in cpu_clk_i only after a synchronized request, and
// returns a held response.  No changing multi-bit bus is synchronized bit by
// bit.
module CaveBanprestoSaveStateDomainCoordinator #(
	parameter integer COMMAND_WIDTH = 16,
	parameter integer RESPONSE_WIDTH = 8,
	parameter integer GAME_INDEX_WIDTH = 4,
	parameter [RESPONSE_WIDTH-1:0] RESPONSE_OK_VALUE =
		{{(RESPONSE_WIDTH-1){1'b0}}, 1'b1},
	parameter integer CONTROL_SOURCE_TIMEOUT_CYCLES = 4096,
	parameter integer CONTROL_DESTINATION_TIMEOUT_CYCLES = 4096,
	parameter integer CONTROL_RESET_GUARD_CYCLES = 4,
	parameter integer SEQUENCE_TIMEOUT_CYCLES = 100_000_000
) (
	input  wire                         sys_clk_i,
	input  wire                         sys_async_reset_i,
	input  wire                         cpu_clk_i,
	input  wire                         cpu_async_reset_i,
	input  wire [GAME_INDEX_WIDTH-1:0]  game_index_i,

	// Level requests and applied acknowledgements for Quiesce.
	input  wire                         quiesce_request_restore_i,
	input  wire                         quiesce_main_stop_request_i,
	input  wire                         quiesce_sound_stop_request_i,
	output wire                         quiesce_main_stopped_o,
	output wire                         quiesce_sound_stopped_o,
	output logic                        quiesce_main_abort_ack_o,
	output logic                        quiesce_sound_abort_ack_o,

	// Controller commands.  Release is the controller's globally qualified
	// quiesce_resume authorization, not a raw stop-level falling edge.
	input  wire                         controller_stream_save_start_i,
	input  wire                         controller_stream_restore_start_i,
	input  wire                         controller_stream_abort_i,
	input  wire                         controller_release_request_i,

	// Commands presented to the raw stream.
	output wire                         stream_save_start_o,
	output wire                         stream_restore_start_o,
	output wire                         stream_pass2_enable_o,
	output wire                         stream_abort_o,

	// Raw stream observations.
	input  wire                         raw_stream_busy_i,
	input  wire                         raw_stream_done_i,
	input  wire                         raw_stream_success_i,
	input  wire                         raw_stream_format_error_i,
	input  wire                         raw_stream_pass1_complete_i,
	input  wire                         raw_stream_mutated_i,
	input  wire                         raw_stream_fatal_i,
	input  wire [7:0]                   raw_stream_error_code_i,
	input  wire [1:0]                   raw_stream_restore_pass_i,
	input  wire                         raw_stream_restore_begin_i,
	input  wire                         raw_stream_restore_commit_i,

	// Qualified stream observations presented to the operation controller.
	output wire                         controller_stream_busy_o,
	output wire                         controller_stream_done_o,
	output wire                         controller_stream_success_o,
	output wire                         controller_stream_format_error_o,
	output wire                         controller_stream_pass1_complete_o,
	output wire                         controller_stream_mutated_o,
	output wire                         controller_stream_fatal_o,
	output wire [7:0]                   controller_stream_error_code_o,
	output wire [1:0]                   controller_stream_restore_pass_o,
	output wire                         controller_stream_restore_begin_o,
	output wire                         controller_stream_restore_commit_o,

	// System-clock non-CPU owners commit before either CPU-domain commit.
	output wire                         system_noncpu_commit_o,
	input  wire                         system_commit_done_i,
	input  wire                         system_commit_fault_i,

	// Explicit endpoint release barrier.  release_restore_o becomes true only
	// after both endpoint ENABLE commands have accepted pass 2.  That proof is
	// retained for the rest of the quiesced epoch, well before the later release
	// MCP samples it.  Failed pass-1 recovery therefore remains non-restore.
	output wire                         main_release_request_o,
	output wire                         sound_release_request_o,
	output wire                         release_restore_o,
	input  wire                         main_release_complete_i,
	input  wire                         sound_release_complete_i,
	output logic                        quiesce_release_complete_o,
	output wire                         release_pending_o,

	// Main destination-side command contract, synchronous to cpu_clk_i.
	output wire                         main_command_valid_o,
	output wire [COMMAND_WIDTH-1:0]     main_command_o,
	input  wire                         main_command_complete_i,
	input  wire [RESPONSE_WIDTH-1:0]    main_command_response_i,
	input  wire                         main_command_terminal_fault_i,
	output wire                         main_command_busy_o,
	output wire                         main_command_channel_fault_o,

	// Sound destination-side command contract, synchronous to cpu_clk_i.
	// CmdCommit completion is the explicit device-plus-T80 applied commit
	// acknowledgement; later launch/release evidence cannot satisfy it.
	output wire                         sound_command_valid_o,
	output wire [COMMAND_WIDTH-1:0]     sound_command_o,
	input  wire                         sound_command_complete_i,
	input  wire [RESPONSE_WIDTH-1:0]    sound_command_response_i,
	input  wire                         sound_command_terminal_fault_i,
	output wire                         sound_command_busy_o,
	output wire                         sound_command_channel_fault_o,

	// Sticky fail-closed status, cleared only by sys_async_reset_i.
	output logic                        terminal_fault_o,
	output logic [7:0]                  last_fault_code_o,
	output wire                         operation_active_o,
	output wire                         operation_restore_o,
	output wire                         mutation_authorized_o,
	output wire [4:0]                   state_debug_o
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
	,
	output wire                         debug_result_latched_o,
	output wire                         debug_result_success_o,
	output wire                         debug_result_restore_commit_o,
	output wire [1:0]                   debug_result_restore_pass_o,
	output wire                         debug_restore_done_good_o,
	output wire                         debug_restore_pass2_capture_o,
	output wire                         debug_abort_requested_o,
	output wire [39:0]                  debug_first_protocol_fault_o
`endif
);

	localparam integer COMMAND_OPCODE_LSB = 0;
	localparam integer COMMAND_OPCODE_WIDTH = 5;
	localparam integer COMMAND_GAME_INDEX_LSB = 5;
	localparam integer COMMAND_RESTORE_MODE_BIT =
		COMMAND_GAME_INDEX_LSB + GAME_INDEX_WIDTH;
	localparam integer COMMAND_REQUIRED_WIDTH =
		COMMAND_RESTORE_MODE_BIT + 1;

	typedef enum logic [4:0] {
		CmdNop            = 5'd0,
		CmdStop           = 5'd1,
		CmdBegin          = 5'd2,
		CmdEnable         = 5'd3,
		CmdAbort          = 5'd4,
		CmdNoncpuCommit   = 5'd5,
		CmdCommit         = 5'd6,
		CmdCpuFinalCommit = 5'd7
	} command_opcode_e;

	typedef enum logic [4:0] {
		StIdle                = 5'd0,
		StStopMainIssue       = 5'd1,
		StStopMainWait        = 5'd2,
		StStopSoundIssue      = 5'd3,
		StStopSoundWait       = 5'd4,
		StSaveStart           = 5'd5,
		StSaveRun             = 5'd6,
		StRestoreBeginIssue   = 5'd7,
		StRestoreBeginWait    = 5'd8,
		StRestoreStart        = 5'd9,
		StRestorePass1        = 5'd10,
		StRestoreEnableIssue  = 5'd11,
		StRestoreEnableWait   = 5'd12,
		StRestorePass2Enable  = 5'd13,
		StRestorePass2        = 5'd14,
		StSystemCommitPulse   = 5'd15,
		StSystemCommitWait    = 5'd16,
		StMainNoncpuIssue     = 5'd17,
		StMainNoncpuWait      = 5'd18,
		StSoundCommitIssue    = 5'd19,
		StSoundCommitWait     = 5'd20,
		StMainCpuFinalIssue   = 5'd21,
		StMainCpuFinalWait    = 5'd22,
		StReportResult        = 5'd23,
		StAwaitRelease        = 5'd24,
		StReleaseIssue        = 5'd25,
		StReleaseWait         = 5'd26,
		StAbortIssue          = 5'd27,
		StAbortCommandWait    = 5'd28,
		StAbortStreamWait     = 5'd29,
		StAbortReport         = 5'd30,
		StFatalHold           = 5'd31
	} coordinator_state_e;

	localparam [7:0] FaultNone              = 8'h00;
	localparam [7:0] FaultProtocol          = 8'h01;
	localparam [7:0] FaultControlChannel    = 8'h02;
	localparam [7:0] FaultSequenceTimeout   = 8'h03;
	localparam [7:0] FaultEndpointResponse  = 8'h04;
	localparam [7:0] FaultPostMutationAbort = 8'h05;
	localparam [7:0] FaultSystemCommit      = 8'h06;
	localparam [7:0] FaultRawStream         = 8'h07;

	localparam integer SEQUENCE_TIMEOUT_WIDTH =
		(SEQUENCE_TIMEOUT_CYCLES <= 1)
			? 1 : $clog2(SEQUENCE_TIMEOUT_CYCLES);
	localparam integer SEQUENCE_TIMEOUT_LIMIT =
		(SEQUENCE_TIMEOUT_CYCLES <= 1)
			? 0 : SEQUENCE_TIMEOUT_CYCLES - 1;

	initial begin
		if (COMMAND_WIDTH < COMMAND_REQUIRED_WIDTH)
			$error(
				"CaveBanpresto domain coordinator: COMMAND_WIDTH too small"
			);
		if (RESPONSE_WIDTH < 1)
			$error(
				"CaveBanpresto domain coordinator: RESPONSE_WIDTH is zero"
			);
	end

	wire sys_reset;

	CaveBanprestoSaveStateResetSync sys_reset_sync (
		.clk_i         (sys_clk_i),
		.async_reset_i (sys_async_reset_i),
		.reset_o       (sys_reset)
	);

	coordinator_state_e state_q;
	coordinator_state_e state_d;
	logic coordinator_stream_busy_q;

	logic [GAME_INDEX_WIDTH-1:0] game_index_q;
	logic quiesce_request_restore_q;
	logic operation_active_q;
	logic operation_restore_q;
	logic main_stopped_q;
	logic sound_stopped_q;
	logic abort_pending_q;
	logic save_committed_q;
	logic restore_begin_seen_q;
	logic pass1_seen_q;
	logic mutation_authorized_q;
	logic mutation_seen_q;

	// Raw terminal result is retained while the ordered commit/release
	// barriers run.  Reporting cannot consume a one-cycle raw done pulse.
	logic result_latched_q;
	logic result_success_q;
	logic result_format_error_q;
	logic result_restore_commit_q;
	logic [7:0] result_error_code_q;
	logic [1:0] result_restore_pass_q;
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
	// First-fault-only hardware evidence.  This record never feeds control.
	logic        debug_first_protocol_fault_seen_q;
	logic [39:0] debug_first_protocol_fault_q;
`endif
	logic main_release_seen_q;
	logic sound_release_seen_q;
	logic [SEQUENCE_TIMEOUT_WIDTH-1:0] sequence_timeout_count_q;

	// Source-side transaction engine.  A target bit remains pending until its
	// CDC accepts the held command, and a separate seen bit retains each
	// response until both targeted endpoints have acknowledged.
	logic transaction_active_q;
	logic [COMMAND_WIDTH-1:0] transaction_command_q;
	logic transaction_target_main_q;
	logic transaction_target_sound_q;
	logic transaction_send_main_q;
	logic transaction_send_sound_q;
	logic transaction_response_main_seen_q;
	logic transaction_response_sound_seen_q;
	logic transaction_done_q;

	logic issue_transaction;
	logic issue_target_main;
	logic issue_target_sound;
	command_opcode_e issue_opcode;
	wire abort_requested =
		(controller_stream_abort_i || abort_pending_q) &&
		!save_committed_q;
	// Controller response evidence must not depend combinationally on the
	// controller's abort command.  The live command still fences raw stream
	// launch/commit controls immediately; registered abort history suppresses
	// response evidence after the clock boundary.
	wire controller_feedback_abort_pending =
		abort_pending_q && !save_committed_q;

	wire main_src_command_ready;
	wire main_src_command_accepted;
	wire main_src_response_valid;
	wire [RESPONSE_WIDTH-1:0] main_src_response;
	wire main_src_busy;
	wire main_src_timeout;
	wire main_src_destination_reset;
	wire main_src_terminal_fault;
	wire main_dst_timeout;
	wire main_dst_source_reset;
	wire main_dst_unsolicited_complete;
	wire main_dst_terminal_fault;

	wire sound_src_command_ready;
	wire sound_src_command_accepted;
	wire sound_src_response_valid;
	wire [RESPONSE_WIDTH-1:0] sound_src_response;
	wire sound_src_busy;
	wire sound_src_timeout;
	wire sound_src_destination_reset;
	wire sound_src_terminal_fault;
	wire sound_dst_timeout;
	wire sound_dst_source_reset;
	wire sound_dst_unsolicited_complete;
	wire sound_dst_terminal_fault;

	wire main_cpu_fault_level =
		main_command_terminal_fault_i ||
		main_dst_timeout ||
		main_dst_source_reset ||
		main_dst_unsolicited_complete ||
		main_dst_terminal_fault;
	wire sound_cpu_fault_level =
		sound_command_terminal_fault_i ||
		sound_dst_timeout ||
		sound_dst_source_reset ||
		sound_dst_unsolicited_complete ||
		sound_dst_terminal_fault;
	wire main_cpu_fault_sync;
	wire sound_cpu_fault_sync;

	logic main_src_ready_d_q;
	logic sound_src_ready_d_q;

	function automatic [COMMAND_WIDTH-1:0] pack_command(
		input command_opcode_e opcode,
		input logic [GAME_INDEX_WIDTH-1:0] game_index,
		input logic restore_mode
	);
		logic [COMMAND_WIDTH-1:0] packet;
		begin
			packet = {COMMAND_WIDTH{1'b0}};
			packet[
				COMMAND_OPCODE_LSB +:
				COMMAND_OPCODE_WIDTH
			] = opcode;
			packet[
				COMMAND_GAME_INDEX_LSB +:
				GAME_INDEX_WIDTH
			] = game_index;
			packet[COMMAND_RESTORE_MODE_BIT] = restore_mode;
			pack_command = packet;
		end
	endfunction

	CaveBanprestoSaveStateControlCdc #(
		.COMMAND_WIDTH(COMMAND_WIDTH),
		.RESPONSE_WIDTH(RESPONSE_WIDTH),
		.SOURCE_TIMEOUT_CYCLES(
			CONTROL_SOURCE_TIMEOUT_CYCLES
		),
		.DESTINATION_TIMEOUT_CYCLES(
			CONTROL_DESTINATION_TIMEOUT_CYCLES
		),
		.RESET_GUARD_CYCLES(CONTROL_RESET_GUARD_CYCLES)
	) main_control_cdc (
		.src_clk_i                  (sys_clk_i),
		.src_async_reset_i          (sys_async_reset_i),
		.src_command_valid_i        (
			transaction_active_q &&
			transaction_target_main_q &&
			transaction_send_main_q
		),
		.src_command_ready_o        (main_src_command_ready),
		.src_command_i              (transaction_command_q),
		.src_command_accepted_o     (main_src_command_accepted),
		.src_response_valid_o       (main_src_response_valid),
		.src_response_o             (main_src_response),
		.src_busy_o                 (main_src_busy),
		.src_timeout_o              (main_src_timeout),
		.src_destination_reset_o    (
			main_src_destination_reset
		),
		.src_terminal_fault_o       (main_src_terminal_fault),
		.dst_clk_i                  (cpu_clk_i),
		.dst_async_reset_i          (cpu_async_reset_i),
		.dst_command_valid_o        (main_command_valid_o),
		.dst_command_o              (main_command_o),
		.dst_complete_i             (main_command_complete_i),
		.dst_response_i             (main_command_response_i),
		.dst_terminal_fault_i       (
			main_command_terminal_fault_i
		),
		.dst_busy_o                 (main_command_busy_o),
		.dst_timeout_o              (main_dst_timeout),
		.dst_source_reset_o         (main_dst_source_reset),
		.dst_unsolicited_complete_o (
			main_dst_unsolicited_complete
		),
		.dst_terminal_fault_o       (main_dst_terminal_fault)
	);

	CaveBanprestoSaveStateControlCdc #(
		.COMMAND_WIDTH(COMMAND_WIDTH),
		.RESPONSE_WIDTH(RESPONSE_WIDTH),
		.SOURCE_TIMEOUT_CYCLES(
			CONTROL_SOURCE_TIMEOUT_CYCLES
		),
		.DESTINATION_TIMEOUT_CYCLES(
			CONTROL_DESTINATION_TIMEOUT_CYCLES
		),
		.RESET_GUARD_CYCLES(CONTROL_RESET_GUARD_CYCLES)
	) sound_control_cdc (
		.src_clk_i                  (sys_clk_i),
		.src_async_reset_i          (sys_async_reset_i),
		.src_command_valid_i        (
			transaction_active_q &&
			transaction_target_sound_q &&
			transaction_send_sound_q
		),
		.src_command_ready_o        (sound_src_command_ready),
		.src_command_i              (transaction_command_q),
		.src_command_accepted_o     (sound_src_command_accepted),
		.src_response_valid_o       (sound_src_response_valid),
		.src_response_o             (sound_src_response),
		.src_busy_o                 (sound_src_busy),
		.src_timeout_o              (sound_src_timeout),
		.src_destination_reset_o    (
			sound_src_destination_reset
		),
		.src_terminal_fault_o       (sound_src_terminal_fault),
		.dst_clk_i                  (cpu_clk_i),
		.dst_async_reset_i          (cpu_async_reset_i),
		.dst_command_valid_o        (sound_command_valid_o),
		.dst_command_o              (sound_command_o),
		.dst_complete_i             (sound_command_complete_i),
		.dst_response_i             (sound_command_response_i),
		.dst_terminal_fault_i       (
			sound_command_terminal_fault_i
		),
		.dst_busy_o                 (sound_command_busy_o),
		.dst_timeout_o              (sound_dst_timeout),
		.dst_source_reset_o         (sound_dst_source_reset),
		.dst_unsolicited_complete_o (
			sound_dst_unsolicited_complete
		),
		.dst_terminal_fault_o       (sound_dst_terminal_fault)
	);

	CaveBanprestoSaveStateCdcBitSync main_fault_to_system (
		.clk_i   (sys_clk_i),
		.reset_i (sys_reset),
		.async_i (main_cpu_fault_level),
		.sync_o  (main_cpu_fault_sync)
	);

	CaveBanprestoSaveStateCdcBitSync sound_fault_to_system (
		.clk_i   (sys_clk_i),
		.reset_i (sys_reset),
		.async_i (sound_cpu_fault_level),
		.sync_o  (sound_cpu_fault_sync)
	);

	assign main_command_channel_fault_o = main_dst_terminal_fault;
	assign sound_command_channel_fault_o = sound_dst_terminal_fault;

	wire main_response_expected =
		transaction_active_q &&
		transaction_target_main_q &&
		!transaction_response_main_seen_q;
	wire sound_response_expected =
		transaction_active_q &&
		transaction_target_sound_q &&
		!transaction_response_sound_seen_q;
	wire main_response_bad =
		main_src_response_valid &&
		(!main_response_expected ||
		 (main_src_response !== RESPONSE_OK_VALUE));
	wire sound_response_bad =
		sound_src_response_valid &&
		(!sound_response_expected ||
		 (sound_src_response !== RESPONSE_OK_VALUE));
	wire endpoint_response_fault =
		main_response_bad || sound_response_bad;

	wire transaction_main_response_now =
		transaction_response_main_seen_q ||
		main_src_response_valid;
	wire transaction_sound_response_now =
		transaction_response_sound_seen_q ||
		sound_src_response_valid;
	wire transaction_complete_now =
		transaction_active_q &&
		(!transaction_target_main_q ||
		 transaction_main_response_now) &&
		(!transaction_target_sound_q ||
		 transaction_sound_response_now) &&
		!endpoint_response_fault;

	// A destination command completion raises the four-phase CDC response,
	// but the endpoint remains in its command-withdraw state until request and
	// acknowledge have both returned low.  Release uses an independent CDC and
	// must not overtake that re-arm phase: Main accepts its one-cycle release
	// authorization only from StReady, and Sound accepts release completion only
	// from StIdle.  Source readiness proves that the full command round trip,
	// including destination withdrawal, has completed for both endpoints.
	wire control_channels_rearmed =
		main_src_command_ready && sound_src_command_ready;

	always_comb begin
		issue_transaction = 1'b0;
		issue_target_main = 1'b0;
		issue_target_sound = 1'b0;
		issue_opcode = CmdNop;

		unique case (state_q)
			StStopMainIssue: begin
				issue_transaction = !abort_requested;
				issue_target_main = 1'b1;
				issue_opcode = CmdStop;
			end

			StStopSoundIssue: begin
				issue_transaction = !abort_requested;
				issue_target_sound = 1'b1;
				issue_opcode = CmdStop;
			end

			StRestoreBeginIssue: begin
				issue_transaction = !abort_requested;
				issue_target_main = 1'b1;
				issue_target_sound = 1'b1;
				issue_opcode = CmdBegin;
			end

			StRestoreEnableIssue: begin
				issue_transaction = !abort_requested;
				issue_target_main = 1'b1;
				issue_target_sound = 1'b1;
				issue_opcode = CmdEnable;
			end

			StMainNoncpuIssue: begin
				issue_transaction = !abort_requested;
				issue_target_main = 1'b1;
				issue_opcode = CmdNoncpuCommit;
			end

			StSoundCommitIssue: begin
				issue_transaction = !abort_requested;
				issue_target_sound = 1'b1;
				issue_opcode = CmdCommit;
			end

			StMainCpuFinalIssue: begin
				issue_transaction = !abort_requested;
				issue_target_main = 1'b1;
				issue_opcode = CmdCpuFinalCommit;
			end

			StAbortIssue: begin
				issue_transaction = 1'b1;
				issue_target_main = 1'b1;
				issue_target_sound = 1'b1;
				issue_opcode = CmdAbort;
			end

			default: begin
				issue_transaction = 1'b0;
			end
		endcase
	end

	wire transaction_issue_overlap =
		issue_transaction && transaction_active_q;
	wire transaction_start_safe =
		!terminal_fault_o &&
		!raw_stream_fatal_i &&
		!system_commit_fault_i &&
		!endpoint_response_fault &&
		!main_src_timeout &&
		!sound_src_timeout &&
		!main_src_destination_reset &&
		!sound_src_destination_reset &&
		!main_src_terminal_fault &&
		!sound_src_terminal_fault &&
		!main_cpu_fault_sync &&
		!sound_cpu_fault_sync &&
		(!abort_requested || (issue_opcode == CmdAbort)) &&
		!(((operation_active_q ||
		    main_stopped_q ||
		    sound_stopped_q ||
		    (state_q != StIdle)) &&
		   !transaction_active_q) &&
		  ((main_src_ready_d_q && !main_src_command_ready) ||
		   (sound_src_ready_d_q && !sound_src_command_ready)));

	always_ff @(posedge sys_clk_i) begin
		if (sys_reset) begin
			transaction_active_q <= 1'b0;
			transaction_command_q <=
				{COMMAND_WIDTH{1'b0}};
			transaction_target_main_q <= 1'b0;
			transaction_target_sound_q <= 1'b0;
			transaction_send_main_q <= 1'b0;
			transaction_send_sound_q <= 1'b0;
			transaction_response_main_seen_q <= 1'b0;
			transaction_response_sound_seen_q <= 1'b0;
			transaction_done_q <= 1'b0;
		end else begin
			transaction_done_q <= 1'b0;

			if (issue_transaction &&
			    !transaction_active_q &&
			    transaction_start_safe) begin
				transaction_active_q <= 1'b1;
				transaction_command_q <=
					pack_command(
						issue_opcode,
						game_index_q,
						quiesce_request_restore_q
					);
				transaction_target_main_q <= issue_target_main;
				transaction_target_sound_q <= issue_target_sound;
				transaction_send_main_q <= issue_target_main;
				transaction_send_sound_q <= issue_target_sound;
				transaction_response_main_seen_q <= 1'b0;
				transaction_response_sound_seen_q <= 1'b0;
			end

			if (main_src_command_accepted)
				transaction_send_main_q <= 1'b0;
			if (sound_src_command_accepted)
				transaction_send_sound_q <= 1'b0;

			if (main_src_response_valid &&
			    main_response_expected)
				transaction_response_main_seen_q <= 1'b1;
			if (sound_src_response_valid &&
			    sound_response_expected)
				transaction_response_sound_seen_q <= 1'b1;

			if (transaction_complete_now) begin
				transaction_active_q <= 1'b0;
				transaction_target_main_q <= 1'b0;
				transaction_target_sound_q <= 1'b0;
				transaction_send_main_q <= 1'b0;
				transaction_send_sound_q <= 1'b0;
				transaction_done_q <= 1'b1;
			end
		end
	end

	wire channel_fault_event =
		main_src_timeout ||
		sound_src_timeout ||
		main_src_destination_reset ||
		sound_src_destination_reset ||
		main_src_terminal_fault ||
		sound_src_terminal_fault ||
		main_cpu_fault_sync ||
		sound_cpu_fault_sync;

	wire active_context =
		operation_active_q ||
		main_stopped_q ||
		sound_stopped_q ||
		(state_q != StIdle);
	wire independent_cpu_reset_event =
		active_context &&
		!transaction_active_q &&
		((main_src_ready_d_q && !main_src_command_ready) ||
		 (sound_src_ready_d_q && !sound_src_command_ready));

	wire save_done_good_now =
		(state_q == StSaveRun) &&
		raw_stream_done_i &&
		raw_stream_success_i &&
		!raw_stream_busy_i &&
		!raw_stream_format_error_i &&
		!raw_stream_fatal_i &&
		!raw_stream_restore_begin_i &&
		!raw_stream_pass1_complete_i &&
		!raw_stream_mutated_i &&
		!raw_stream_restore_commit_i &&
		(raw_stream_restore_pass_i == 2'd0);
	wire save_done_failure_now =
		(state_q == StSaveRun) &&
		raw_stream_done_i &&
		!raw_stream_success_i &&
		!raw_stream_busy_i &&
		!raw_stream_fatal_i &&
		!raw_stream_restore_begin_i &&
		!raw_stream_pass1_complete_i &&
		!raw_stream_mutated_i &&
		!raw_stream_restore_commit_i &&
		(raw_stream_restore_pass_i == 2'd0);

	wire legal_restore_begin_now =
		(state_q == StRestorePass1) &&
		!restore_begin_seen_q &&
		raw_stream_restore_begin_i &&
		raw_stream_busy_i &&
		!raw_stream_done_i &&
		!raw_stream_mutated_i &&
		!raw_stream_restore_commit_i &&
		(raw_stream_restore_pass_i == 2'd1);
	wire legal_pass1_complete_now =
		(state_q == StRestorePass1) &&
		restore_begin_seen_q &&
		!pass1_seen_q &&
		raw_stream_pass1_complete_i &&
		raw_stream_busy_i &&
		!raw_stream_done_i &&
		!raw_stream_mutated_i &&
		!raw_stream_restore_commit_i &&
		(raw_stream_restore_pass_i == 2'd1);
	wire restore_failure_now =
		(state_q == StRestorePass1) &&
		raw_stream_done_i &&
		!raw_stream_success_i &&
		!raw_stream_busy_i &&
		!raw_stream_fatal_i &&
		restore_begin_seen_q &&
		!raw_stream_mutated_i &&
		!raw_stream_restore_commit_i &&
		(raw_stream_restore_pass_i == 2'd1);
	wire restore_done_good_now =
		(state_q == StRestorePass2) &&
		raw_stream_done_i &&
		raw_stream_success_i &&
		!raw_stream_busy_i &&
		!raw_stream_format_error_i &&
		!raw_stream_fatal_i &&
		restore_begin_seen_q &&
		pass1_seen_q &&
		mutation_authorized_q &&
		(mutation_seen_q || raw_stream_mutated_i) &&
		raw_stream_restore_commit_i &&
		(raw_stream_restore_pass_i == 2'd2);
	// These sequential bookkeeping events are intentionally derived from the
	// present phase and the proof local to that phase.  Feeding state_d back
	// into their enables would duplicate the complete fault/next-state cone at
	// each retained result bit.  A coincident unrelated terminal fault can only
	// update hidden retained fields; FatalHold suppresses every report, commit,
	// command, and release output.
	wire save_result_capture_event =
		save_done_good_now ||
		(save_done_failure_now && !abort_requested);
	wire restore_pass1_failure_capture_event =
		restore_failure_now && !abort_requested;
	wire restore_pass2_success_capture_event =
		restore_done_good_now && !abort_requested;

	wire post_mutation_abort =
		abort_requested && mutation_authorized_q;

	wire abort_state =
		(state_q == StAbortIssue) ||
		(state_q == StAbortCommandWait) ||
		(state_q == StAbortStreamWait) ||
		(state_q == StAbortReport);
	wire release_completion_allowed =
		(state_q == StReleaseIssue) ||
		(state_q == StReleaseWait) ||
		abort_state;
	wire release_complete_protocol_fault =
		(main_release_complete_i ||
		 sound_release_complete_i) &&
		!release_completion_allowed;
	wire system_done_protocol_fault =
		system_commit_done_i &&
		(state_q != StSystemCommitWait);
	wire controller_start_protocol_fault =
		(controller_stream_save_start_i &&
		 controller_stream_restore_start_i) ||
		((controller_stream_save_start_i ||
		  controller_stream_restore_start_i) &&
		 (state_q != StIdle));
	wire release_request_protocol_fault =
		controller_release_request_i &&
		(state_q != StAwaitRelease);
	wire raw_done_protocol_fault =
		raw_stream_done_i &&
		(state_q != StSaveRun) &&
		(state_q != StRestorePass1) &&
		(state_q != StRestorePass2) &&
		(state_q != StAbortIssue) &&
		(state_q != StAbortCommandWait) &&
		(state_q != StAbortStreamWait) &&
		(state_q != StAbortReport);
	wire raw_begin_protocol_fault =
		raw_stream_restore_begin_i &&
		!legal_restore_begin_now &&
		!abort_state;
	wire raw_commit_protocol_fault =
		raw_stream_restore_commit_i &&
		!restore_done_good_now &&
		!abort_state;
	wire raw_pass1_protocol_fault =
		raw_stream_pass1_complete_i &&
		!legal_pass1_complete_now &&
		(state_q != StRestoreEnableIssue) &&
		(state_q != StRestoreEnableWait) &&
		(state_q != StRestorePass2Enable) &&
		!abort_state;
	// mutated is transaction-sticky until the next stream start.  Police it
	// only while the stream is active so retained post-release proof is not
	// reinterpreted as a new unauthorized mutation.
	wire raw_mutation_protocol_fault =
		raw_stream_busy_i &&
		raw_stream_mutated_i &&
		!mutation_authorized_q &&
		!abort_state;
	wire game_index_protocol_fault =
		active_context &&
		(game_index_i !== game_index_q);
	wire quiesce_restore_input_invalid =
		(quiesce_request_restore_i !== 1'b0) &&
		(quiesce_request_restore_i !== 1'b1);
	wire quiesce_restore_mode_protocol_fault =
		quiesce_restore_input_invalid ||
		(active_context &&
		 !abort_state &&
		 (quiesce_request_restore_i !==
		  quiesce_request_restore_q)) ||
		(controller_stream_save_start_i &&
		 quiesce_request_restore_q) ||
		(controller_stream_restore_start_i &&
		 !quiesce_request_restore_q);

	wire transaction_wait_state =
		(state_q == StStopMainWait) ||
		(state_q == StStopSoundWait) ||
		(state_q == StRestoreBeginWait) ||
		(state_q == StRestoreEnableWait) ||
		(state_q == StMainNoncpuWait) ||
		(state_q == StSoundCommitWait) ||
		(state_q == StMainCpuFinalWait) ||
		(state_q == StAbortCommandWait);
	wire transaction_done_protocol_fault =
		transaction_done_q && !transaction_wait_state;

	wire protocol_fault_event =
		transaction_issue_overlap ||
		controller_start_protocol_fault ||
		release_request_protocol_fault ||
		release_complete_protocol_fault ||
		system_done_protocol_fault ||
		raw_done_protocol_fault ||
		raw_begin_protocol_fault ||
		raw_commit_protocol_fault ||
		raw_pass1_protocol_fault ||
		raw_mutation_protocol_fault ||
		game_index_protocol_fault ||
		quiesce_restore_mode_protocol_fault ||
		transaction_done_protocol_fault;

	wire sequence_wait_state =
		(state_q == StStopMainWait) ||
		(state_q == StStopSoundWait) ||
		(state_q == StSaveRun) ||
		(state_q == StRestoreBeginWait) ||
		(state_q == StRestorePass1) ||
		(state_q == StRestoreEnableWait) ||
		(state_q == StRestorePass2) ||
		(state_q == StSystemCommitWait) ||
		(state_q == StMainNoncpuWait) ||
		(state_q == StSoundCommitWait) ||
		(state_q == StMainCpuFinalWait) ||
		(state_q == StAwaitRelease) ||
		(state_q == StReleaseWait) ||
		(state_q == StAbortCommandWait) ||
		(state_q == StAbortStreamWait) ||
		(state_q == StAbortReport);
	wire sequence_timeout_expired =
		(SEQUENCE_TIMEOUT_CYCLES != 0) &&
		(sequence_timeout_count_q == SEQUENCE_TIMEOUT_LIMIT);
	wire sequence_timeout_event =
		sequence_wait_state && sequence_timeout_expired;
	// Every normal wait-state exit passes through a non-wait issue/report
	// state, which clears the counter before the next wait phase.  These are
	// the only two legal wait-to-wait transitions, so clear them explicitly.
	// Do not use state_d here: its complete protocol/fault cone would otherwise
	// feed every bit of this wide counter on the 96 MHz critical path.
	wire sequence_wait_phase_complete =
		((state_q == StAbortCommandWait) && transaction_done_q) ||
		((state_q == StAbortStreamWait) && !raw_stream_busy_i);

	wire raw_stream_fault_event = raw_stream_fatal_i;
	wire system_commit_fault_event = system_commit_fault_i;
	wire immediate_fatal_event =
		channel_fault_event ||
		independent_cpu_reset_event ||
		endpoint_response_fault ||
		protocol_fault_event ||
		sequence_timeout_event ||
		raw_stream_fault_event ||
		system_commit_fault_event ||
		post_mutation_abort;
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
	// FaultProtocol is also used for a state-machine fallback into FatalHold
	// when no immediate fault predicate fired. Capture that as a fourteenth
	// cause together with every term of restore_done_good_now.
	wire debug_fallback_to_fatal =
		!terminal_fault_o &&
		!immediate_fatal_event &&
		(state_d == StFatalHold) &&
		(state_q != StFatalHold);
	wire [13:0] debug_protocol_causes_now = {
		debug_fallback_to_fatal,
		transaction_issue_overlap,
		controller_start_protocol_fault,
		release_request_protocol_fault,
		release_complete_protocol_fault,
		system_done_protocol_fault,
		raw_done_protocol_fault,
		raw_begin_protocol_fault,
		raw_commit_protocol_fault,
		raw_pass1_protocol_fault,
		raw_mutation_protocol_fault,
		game_index_protocol_fault,
		quiesce_restore_mode_protocol_fault,
		transaction_done_protocol_fault
	};
	wire [39:0] debug_protocol_fault_context_now = {
		debug_protocol_causes_now,
		state_q,
		raw_stream_error_code_i,
		raw_stream_done_i,
		raw_stream_success_i,
		raw_stream_busy_i,
		raw_stream_format_error_i,
		raw_stream_fatal_i,
		restore_begin_seen_q,
		pass1_seen_q,
		mutation_authorized_q,
		mutation_seen_q,
		raw_stream_mutated_i,
		raw_stream_restore_commit_i,
		raw_stream_restore_pass_i
	};
`endif
	// Identity capture is inert if a new immediate fault wins this edge: the
	// global fatal priority below prevents any transaction or stream launch.
	// Keep only the already-registered terminal poison in the admission event
	// so the full immediate-fault cone does not feed the identity registers.
	wire identity_capture_event =
		(state_q == StIdle) &&
		!main_stopped_q &&
		!sound_stopped_q &&
		!terminal_fault_o &&
		(abort_requested || quiesce_main_stop_request_i ||
		 quiesce_sound_stop_request_i);

	always_comb begin
		state_d = state_q;

		if (terminal_fault_o || immediate_fatal_event) begin
			state_d = StFatalHold;
		end else begin
			unique case (state_q)
				StIdle: begin
					if (abort_requested) begin
						state_d = StAbortIssue;
					end else if (
						quiesce_main_stop_request_i &&
						!main_stopped_q
					) begin
						state_d = StStopMainIssue;
					end else if (
						quiesce_sound_stop_request_i &&
						!sound_stopped_q
					) begin
						state_d = StStopSoundIssue;
					end else if (
						controller_stream_save_start_i
					) begin
						state_d =
							(main_stopped_q &&
							 sound_stopped_q)
								? StSaveStart
								: StFatalHold;
					end else if (
						controller_stream_restore_start_i
					) begin
						state_d =
							(main_stopped_q &&
							 sound_stopped_q)
								? StRestoreBeginIssue
								: StFatalHold;
					end
				end

				StStopMainIssue: begin
					state_d = abort_requested
						? StAbortIssue
						: StStopMainWait;
				end

				StStopMainWait: begin
					if (transaction_done_q)
						state_d = abort_requested
							? StAbortIssue
							: StIdle;
				end

				StStopSoundIssue: begin
					state_d = abort_requested
						? StAbortIssue
						: StStopSoundWait;
				end

				StStopSoundWait: begin
					if (transaction_done_q)
						state_d = abort_requested
							? StAbortIssue
							: StIdle;
				end

				StSaveStart: begin
					state_d = abort_requested
						? StAbortIssue
						: StSaveRun;
				end

				StSaveRun: begin
					if (save_done_good_now)
						state_d = StReportResult;
					else if (abort_requested)
						state_d = StAbortIssue;
					else if (raw_stream_done_i)
						state_d = save_done_failure_now
							? StReportResult
							: StFatalHold;
				end

				StRestoreBeginIssue: begin
					state_d = abort_requested
						? StAbortIssue
						: StRestoreBeginWait;
				end

				StRestoreBeginWait: begin
					if (transaction_done_q)
						state_d = abort_requested
							? StAbortIssue
							: StRestoreStart;
				end

				StRestoreStart: begin
					state_d = abort_requested
						? StAbortIssue
						: StRestorePass1;
				end

				StRestorePass1: begin
					if (abort_requested)
						state_d = StAbortIssue;
					else if (raw_stream_done_i)
						state_d = restore_failure_now
							? StReportResult
							: StFatalHold;
					else if (legal_pass1_complete_now)
						state_d = StRestoreEnableIssue;
				end

				StRestoreEnableIssue: begin
					state_d = abort_requested
						? StAbortIssue
						: StRestoreEnableWait;
				end

				StRestoreEnableWait: begin
					if (transaction_done_q)
						state_d = abort_requested
							? StAbortIssue
							: StRestorePass2Enable;
				end

				StRestorePass2Enable: begin
					state_d = abort_requested
						? StAbortIssue
						: StRestorePass2;
				end

				StRestorePass2: begin
					if (raw_stream_done_i)
						state_d = restore_done_good_now
							? StSystemCommitPulse
							: StFatalHold;
				end

				StSystemCommitPulse: begin
					state_d = StSystemCommitWait;
				end

				StSystemCommitWait: begin
					if (system_commit_done_i)
						state_d = StMainNoncpuIssue;
				end

				StMainNoncpuIssue: begin
					state_d = StMainNoncpuWait;
				end

				StMainNoncpuWait: begin
					if (transaction_done_q)
						state_d = StSoundCommitIssue;
				end

				StSoundCommitIssue: begin
					state_d = StSoundCommitWait;
				end

				StSoundCommitWait: begin
					if (transaction_done_q)
						state_d = StMainCpuFinalIssue;
				end

				StMainCpuFinalIssue: begin
					state_d = StMainCpuFinalWait;
				end

				StMainCpuFinalWait: begin
					if (transaction_done_q)
						state_d = StReportResult;
				end

				StReportResult: begin
					if (abort_requested)
						state_d = StAbortIssue;
					else if (control_channels_rearmed)
						state_d = StAwaitRelease;
				end

				StAwaitRelease: begin
					if (abort_requested)
						state_d = StAbortIssue;
					else if (controller_release_request_i)
						state_d = StReleaseIssue;
				end

				StReleaseIssue: begin
					if (abort_requested)
						state_d = StAbortIssue;
					else
						state_d = StReleaseWait;
				end

				StReleaseWait: begin
					if (abort_requested)
						state_d = StAbortIssue;
					else if (
						(main_release_seen_q ||
						 main_release_complete_i) &&
						(sound_release_seen_q ||
						 sound_release_complete_i)
					) begin
						state_d = StIdle;
					end
				end

				StAbortIssue: begin
					state_d = StAbortCommandWait;
				end

				StAbortCommandWait: begin
					if (transaction_done_q)
						state_d = StAbortStreamWait;
				end

				StAbortStreamWait: begin
					if (!raw_stream_busy_i)
						state_d = StAbortReport;
				end

				StAbortReport: begin
					if (!controller_stream_abort_i &&
					    !quiesce_main_stop_request_i &&
					    !quiesce_sound_stop_request_i)
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

	// Timing register B: decode the next state so this register remains exactly
	// aligned with state_q after the same edge while breaking the measured
	// coordinator-state -> controller-abort -> DDR-arbiter feedback path.
	wire coordinator_stream_busy_d =
		(state_d == StSaveStart) ||
		(state_d == StSaveRun) ||
		(state_d == StRestoreBeginIssue) ||
		(state_d == StRestoreBeginWait) ||
		(state_d == StRestoreStart) ||
		(state_d == StRestorePass1) ||
		(state_d == StRestoreEnableIssue) ||
		(state_d == StRestoreEnableWait) ||
		(state_d == StRestorePass2Enable) ||
		(state_d == StRestorePass2) ||
		(state_d == StSystemCommitPulse) ||
		(state_d == StSystemCommitWait) ||
		(state_d == StMainNoncpuIssue) ||
		(state_d == StMainNoncpuWait) ||
		(state_d == StSoundCommitIssue) ||
		(state_d == StSoundCommitWait) ||
		(state_d == StMainCpuFinalIssue) ||
		(state_d == StMainCpuFinalWait) ||
		(state_d == StReportResult);

	assign stream_save_start_o =
		!sys_reset &&
		!terminal_fault_o &&
		!abort_requested &&
		(state_q == StSaveStart);
	assign stream_restore_start_o =
		!sys_reset &&
		!terminal_fault_o &&
		!abort_requested &&
		(state_q == StRestoreStart);
	assign stream_pass2_enable_o =
		!sys_reset &&
		!terminal_fault_o &&
		!abort_requested &&
		(state_q == StRestorePass2Enable);
	assign stream_abort_o =
		!sys_reset &&
		(controller_stream_abort_i ||
		 abort_pending_q ||
		 terminal_fault_o);

	assign controller_stream_busy_o =
		!sys_reset &&
		!terminal_fault_o &&
		(coordinator_stream_busy_q || raw_stream_busy_i) &&
		!controller_stream_done_o;
	assign controller_stream_done_o =
		!sys_reset &&
		!terminal_fault_o &&
		!controller_feedback_abort_pending &&
		(state_q == StReportResult) &&
		result_latched_q &&
		control_channels_rearmed;
	assign controller_stream_success_o =
		controller_stream_done_o && result_success_q;
	assign controller_stream_format_error_o =
		result_latched_q
			? result_format_error_q
			: raw_stream_format_error_i;
	assign controller_stream_pass1_complete_o =
		!sys_reset &&
		!terminal_fault_o &&
		!controller_feedback_abort_pending &&
		legal_pass1_complete_now;
	assign controller_stream_mutated_o =
		operation_restore_q &&
		mutation_authorized_q &&
		(mutation_seen_q || raw_stream_mutated_i);
	assign controller_stream_fatal_o =
		terminal_fault_o || raw_stream_fatal_i;
	assign controller_stream_error_code_o =
		result_latched_q
			? result_error_code_q
			: raw_stream_error_code_i;
	assign controller_stream_restore_pass_o =
		operation_restore_q
			? (result_latched_q
				? result_restore_pass_q
				: (raw_stream_busy_i
					? raw_stream_restore_pass_i
					: 2'd0))
			: 2'd0;
	assign controller_stream_restore_begin_o =
		!sys_reset &&
		!terminal_fault_o &&
		!controller_feedback_abort_pending &&
		legal_restore_begin_now;
	assign controller_stream_restore_commit_o =
		controller_stream_done_o &&
		operation_restore_q &&
		result_success_q &&
		result_restore_commit_q;

	assign system_noncpu_commit_o =
		!sys_reset &&
		!terminal_fault_o &&
		(state_q == StSystemCommitPulse);

	assign main_release_request_o =
		!sys_reset &&
		!terminal_fault_o &&
		!abort_requested &&
		(state_q == StReleaseIssue);
	assign sound_release_request_o = main_release_request_o;
	// Commit completion gates main_release_request_o.  The payload itself is
	// staged much earlier by the retained pass-2 authorization proof, so it is
	// stable throughout every commit and release-CDC round trip.  A pass-1
	// failure never sets mutation_authorized_q and therefore unwinds with zero.
	assign release_restore_o =
		operation_restore_q && mutation_authorized_q;
	assign release_pending_o =
		(state_q == StAwaitRelease) ||
		(state_q == StReleaseIssue) ||
		(state_q == StReleaseWait);

	assign quiesce_main_stopped_o = main_stopped_q;
	assign quiesce_sound_stopped_o = sound_stopped_q;
	assign operation_active_o = operation_active_q;
	assign operation_restore_o =
		operation_active_q && operation_restore_q;
	assign mutation_authorized_o = mutation_authorized_q;
	assign state_debug_o = state_q;
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
	assign debug_result_latched_o = result_latched_q;
	assign debug_result_success_o = result_success_q;
	assign debug_result_restore_commit_o = result_restore_commit_q;
	assign debug_result_restore_pass_o = result_restore_pass_q;
	assign debug_restore_done_good_o = restore_done_good_now;
	assign debug_restore_pass2_capture_o =
		restore_pass2_success_capture_event;
	assign debug_abort_requested_o = abort_requested;
	assign debug_first_protocol_fault_o =
		debug_first_protocol_fault_q;
`endif

	always_ff @(posedge sys_clk_i) begin
		if (sys_reset) begin
			state_q <= StIdle;
			coordinator_stream_busy_q <= 1'b0;
			game_index_q <= {GAME_INDEX_WIDTH{1'b0}};
			quiesce_request_restore_q <= 1'b0;
			operation_active_q <= 1'b0;
			operation_restore_q <= 1'b0;
			main_stopped_q <= 1'b0;
			sound_stopped_q <= 1'b0;
			abort_pending_q <= 1'b0;
			save_committed_q <= 1'b0;
			restore_begin_seen_q <= 1'b0;
			pass1_seen_q <= 1'b0;
			mutation_authorized_q <= 1'b0;
			mutation_seen_q <= 1'b0;
			result_latched_q <= 1'b0;
			result_success_q <= 1'b0;
			result_format_error_q <= 1'b0;
			result_restore_commit_q <= 1'b0;
			result_error_code_q <= 8'd0;
			result_restore_pass_q <= 2'd0;
			main_release_seen_q <= 1'b0;
			sound_release_seen_q <= 1'b0;
			sequence_timeout_count_q <=
				{SEQUENCE_TIMEOUT_WIDTH{1'b0}};
			main_src_ready_d_q <= 1'b0;
			sound_src_ready_d_q <= 1'b0;
			quiesce_main_abort_ack_o <= 1'b0;
			quiesce_sound_abort_ack_o <= 1'b0;
			quiesce_release_complete_o <= 1'b0;
			terminal_fault_o <= 1'b0;
			last_fault_code_o <= FaultNone;
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
			debug_first_protocol_fault_seen_q <= 1'b0;
			debug_first_protocol_fault_q <= 40'd0;
`endif
		end else begin
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
			if (!debug_first_protocol_fault_seen_q &&
			    !terminal_fault_o &&
			    (immediate_fatal_event || debug_fallback_to_fatal)) begin
				debug_first_protocol_fault_seen_q <= 1'b1;
				debug_first_protocol_fault_q <=
					debug_protocol_fault_context_now;
			end
`endif
			state_q <= state_d;
			coordinator_stream_busy_q <= coordinator_stream_busy_d;
			main_src_ready_d_q <= main_src_command_ready;
			sound_src_ready_d_q <= sound_src_command_ready;
			quiesce_main_abort_ack_o <= 1'b0;
			quiesce_sound_abort_ack_o <= 1'b0;
			quiesce_release_complete_o <= 1'b0;

			if (identity_capture_event) begin
				game_index_q <= game_index_i;
				quiesce_request_restore_q <=
					quiesce_request_restore_i;
			end

			if ((state_q == StStopMainWait) &&
			    transaction_done_q)
				main_stopped_q <= 1'b1;
			if ((state_q == StStopSoundWait) &&
			    transaction_done_q)
				sound_stopped_q <= 1'b1;

			if ((state_q == StIdle) &&
			    (state_d == StSaveStart)) begin
				operation_active_q <= 1'b1;
				operation_restore_q <= 1'b0;
				save_committed_q <= 1'b0;
				restore_begin_seen_q <= 1'b0;
				pass1_seen_q <= 1'b0;
				mutation_authorized_q <= 1'b0;
				mutation_seen_q <= 1'b0;
			end

			if ((state_q == StIdle) &&
			    (state_d == StRestoreBeginIssue)) begin
				operation_active_q <= 1'b1;
				operation_restore_q <= 1'b1;
				save_committed_q <= 1'b0;
				restore_begin_seen_q <= 1'b0;
				pass1_seen_q <= 1'b0;
				mutation_authorized_q <= 1'b0;
				mutation_seen_q <= 1'b0;
			end

			// The result cannot legally arrive in either launch phase.  Clearing
			// it from the registered present state preserves the externally
			// visible epoch while keeping state_d out of the result-register D
			// inputs.
			if ((state_q == StSaveStart) ||
			    (state_q == StRestoreBeginIssue)) begin
				result_latched_q <= 1'b0;
				result_success_q <= 1'b0;
				result_format_error_q <= 1'b0;
				result_restore_commit_q <= 1'b0;
				result_error_code_q <= 8'd0;
				result_restore_pass_q <= 2'd0;
			end

			if (legal_restore_begin_now)
				restore_begin_seen_q <= 1'b1;
			if (legal_pass1_complete_now)
				pass1_seen_q <= 1'b1;
			if (stream_pass2_enable_o)
				mutation_authorized_q <= 1'b1;
			if (raw_stream_mutated_i && mutation_authorized_q)
				mutation_seen_q <= 1'b1;

			// Latch the complete raw result before exposing done.  For save,
			// this is the release bookkeeping barrier: the later controller
			// release pulse cannot race or erase a one-cycle stream result.
			if (save_result_capture_event) begin
				result_latched_q <= 1'b1;
				result_success_q <= save_done_good_now;
				result_format_error_q <=
					raw_stream_format_error_i;
				result_restore_commit_q <= 1'b0;
				result_error_code_q <=
					raw_stream_error_code_i;
				result_restore_pass_q <= 2'd0;
				if (save_done_good_now) begin
					save_committed_q <= 1'b1;
					abort_pending_q <= 1'b0;
				end
			end

			if (restore_pass1_failure_capture_event) begin
				result_latched_q <= 1'b1;
				result_success_q <= 1'b0;
				result_format_error_q <=
					raw_stream_format_error_i;
				result_restore_commit_q <= 1'b0;
				result_error_code_q <=
					raw_stream_error_code_i;
				result_restore_pass_q <= 2'd1;
			end

			if (restore_pass2_success_capture_event) begin
				result_latched_q <= 1'b1;
				result_success_q <= 1'b1;
				result_format_error_q <= 1'b0;
				result_restore_commit_q <= 1'b1;
				result_error_code_q <=
					raw_stream_error_code_i;
				result_restore_pass_q <= 2'd2;
				mutation_seen_q <= 1'b1;
			end

			if (controller_stream_abort_i &&
			    !save_committed_q &&
			    !save_done_good_now)
				abort_pending_q <= 1'b1;

			if ((state_q != StReleaseIssue) &&
			    (state_d == StReleaseIssue)) begin
				main_release_seen_q <= 1'b0;
				sound_release_seen_q <= 1'b0;
			end else if (
				(state_q == StReleaseIssue) ||
				(state_q == StReleaseWait)
			) begin
				if (main_release_complete_i)
					main_release_seen_q <= 1'b1;
				if (sound_release_complete_i)
					sound_release_seen_q <= 1'b1;
			end

			if ((state_q == StReleaseWait) &&
			    (state_d == StIdle)) begin
				quiesce_release_complete_o <= 1'b1;
				operation_active_q <= 1'b0;
				operation_restore_q <= 1'b0;
				main_stopped_q <= 1'b0;
				sound_stopped_q <= 1'b0;
				abort_pending_q <= 1'b0;
				save_committed_q <= 1'b0;
				restore_begin_seen_q <= 1'b0;
				pass1_seen_q <= 1'b0;
				mutation_authorized_q <= 1'b0;
				mutation_seen_q <= 1'b0;
				result_latched_q <= 1'b0;
				main_release_seen_q <= 1'b0;
				sound_release_seen_q <= 1'b0;
				quiesce_request_restore_q <= 1'b0;
			end

			if ((state_q != StAbortReport) &&
			    (state_d == StAbortReport)) begin
				quiesce_main_abort_ack_o <= 1'b1;
				quiesce_sound_abort_ack_o <= 1'b1;
			end

			if ((state_q == StAbortReport) &&
			    (state_d == StIdle)) begin
				operation_active_q <= 1'b0;
				operation_restore_q <= 1'b0;
				main_stopped_q <= 1'b0;
				sound_stopped_q <= 1'b0;
				abort_pending_q <= 1'b0;
				save_committed_q <= 1'b0;
				restore_begin_seen_q <= 1'b0;
				pass1_seen_q <= 1'b0;
				mutation_authorized_q <= 1'b0;
				mutation_seen_q <= 1'b0;
				result_latched_q <= 1'b0;
				main_release_seen_q <= 1'b0;
				sound_release_seen_q <= 1'b0;
				quiesce_request_restore_q <= 1'b0;
			end

			if (!sequence_wait_state ||
			    sequence_wait_phase_complete ||
			    (SEQUENCE_TIMEOUT_CYCLES == 0)) begin
				sequence_timeout_count_q <=
					{SEQUENCE_TIMEOUT_WIDTH{1'b0}};
			end else if (!sequence_timeout_expired) begin
				sequence_timeout_count_q <=
					sequence_timeout_count_q + 1'b1;
			end

			if (!terminal_fault_o && immediate_fatal_event) begin
				terminal_fault_o <= 1'b1;
				if (post_mutation_abort)
					last_fault_code_o <=
						FaultPostMutationAbort;
				else if (system_commit_fault_event)
					last_fault_code_o <=
						FaultSystemCommit;
				else if (endpoint_response_fault)
					last_fault_code_o <=
						FaultEndpointResponse;
				else if (channel_fault_event ||
				         independent_cpu_reset_event)
					last_fault_code_o <=
						FaultControlChannel;
				else if (sequence_timeout_event)
					last_fault_code_o <=
						FaultSequenceTimeout;
				else if (raw_stream_fault_event)
					last_fault_code_o <=
						FaultRawStream;
				else
					last_fault_code_o <=
						FaultProtocol;
			end else if (
				!terminal_fault_o &&
				(state_d == StFatalHold) &&
				(state_q != StFatalHold)
			) begin
				terminal_fault_o <= 1'b1;
				last_fault_code_o <= FaultProtocol;
			end
		end
	end

endmodule

`default_nettype wire
