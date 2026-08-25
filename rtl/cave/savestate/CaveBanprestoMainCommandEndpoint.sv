`default_nettype none

// Main-domain destination for the held 16-bit coordinator command packet.
//
// Packet:
//   [4:0]   opcode
//   [8:5]   immutable game index
//   [9]     immutable STOP-epoch restore intent
//   [15:10] reserved, must be zero
//
// The producer holds command_valid_i and every packet bit until the one-cycle
// command_complete_o pulse.  This endpoint then waits for valid withdrawal
// before accepting another packet.  A changed, duplicated, malformed, or
// out-of-order packet is reset-only terminal.
//
// STOP owns the persistent Main hold.  Restore sequencing is:
//   BEGIN -> ENABLE -> owner 3 -> owner 20 + external applied proof
//         -> owner 22 -> CPU FINAL.
// No live restore load is admitted by BEGIN.  ENABLE authorizes the raw stream
// to write mutable RAM, so ABORT is accepted only before ENABLE.  A legal abort
// drives the fx68k architectural abort, clears the non-CPU save-state endpoints
// with a local synchronous session reset, and releases the persistent hold
// without resetting any emulated core.
//
// release_request_i is the one-cycle destination authorization emitted by
// CaveBanprestoSaveStateReleaseCdc.  release_restore_i is its held MCP
// payload.  Main samples both in StReady, retains the epoch intent locally,
// and rejects a repeated authorization or changed payload while draining and
// rearming; it never requires the authorization pulse to remain asserted.
module CaveBanprestoMainCommandEndpoint (
	input  wire        clk_i,
	input  wire        reset_i,

	input  wire        command_valid_i,
	input  wire [15:0] command_i,
	output logic       command_complete_o,
	output logic [7:0] command_response_o,
	output logic       terminal_fault_o,

	input  wire [3:0]  game_index_i,
	input  wire        release_request_i,
	input  wire        release_restore_i,
	output logic       release_complete_o,

	output wire        state_hold_o,
	output wire        restore_enable_o,
	output wire        cpu_capture_request_o,
	output wire        restore_begin_o,
	output wire        owner3_restore_commit_o,
	output wire        owner20_restore_commit_o,
	output wire        owner22_restore_commit_o,
	output wire        cpu_final_restore_commit_o,
	output wire        cpu_abort_o,
	output wire        noncpu_owner_reset_o,

	input  wire        cpu_captured_i,
	input  wire        cpu_restore_done_i,
	input  wire        cpu_abort_ack_i,
	input  wire        cpu_validation_complete_i,
	input  wire        cpu_validation_valid_i,
	input  wire        cpu_write_complete_i,
	input  wire        cpu_write_valid_i,
	input  wire        cpu_restore_committed_i,
	input  wire        cpu_owner_idle_i,
	input  wire        cpu_terminal_fault_i,

	input  wire        owner3_validation_complete_i,
	input  wire        owner3_validation_valid_i,
	input  wire        owner3_write_complete_i,
	input  wire        owner3_write_valid_i,
	input  wire        owner3_restore_load_i,
	input  wire        owner3_restore_committed_i,
	input  wire        owner3_idle_i,
	input  wire        owner3_terminal_fault_i,

	input  wire        owner20_validation_complete_i,
	input  wire        owner20_validation_valid_i,
	input  wire        owner20_write_complete_i,
	input  wire        owner20_write_valid_i,
	input  wire        owner20_restore_load_i,
	input  wire        owner20_restore_committed_i,
	input  wire        owner20_external_applied_i,
	input  wire        owner20_idle_i,
	input  wire        owner20_terminal_fault_i,
	input  wire        owner20_bridge_terminal_fault_i,

	input  wire        owner22_validation_complete_i,
	input  wire        owner22_validation_valid_i,
	input  wire        owner22_write_complete_i,
	input  wire        owner22_write_valid_i,
	input  wire        owner22_restore_load_i,
	input  wire        owner22_restore_committed_i,
	input  wire        owner22_idle_i,
	input  wire        owner22_terminal_fault_i,

	output wire        main_stopped_o,
	output logic       main_abort_ack_o,
	output wire [4:0]  state_debug_o,
	output wire [31:0] fault_debug_o
);

	localparam [7:0] RESPONSE_OK = 8'h01;

	localparam [4:0] CmdStop           = 5'd1;
	localparam [4:0] CmdBegin          = 5'd2;
	localparam [4:0] CmdEnable         = 5'd3;
	localparam [4:0] CmdAbort          = 5'd4;
	localparam [4:0] CmdNoncpuCommit   = 5'd5;
	localparam [4:0] CmdSoundCommit    = 5'd6;
	localparam [4:0] CmdCpuFinalCommit = 5'd7;

	typedef enum logic [2:0] {
		PhaseIdle             = 3'd0,
		PhaseSaveHeld         = 3'd1,
		PhaseRestoreBegin     = 3'd2,
		PhaseRestoreEnable    = 3'd3,
		PhaseRestoreNoncpu    = 3'd4,
		PhaseRestoreCpu       = 3'd5,
		PhaseRestoreCommitted = 3'd6
	} epoch_phase_e;

	typedef enum logic [4:0] {
		StReady             = 5'd0,
		StStopLaunch        = 5'd1,
		StStopWait          = 5'd2,
		StBeginReset        = 5'd3,
		StBeginPulse        = 5'd4,
		StBeginWait         = 5'd5,
		StNoncpuPrecheck    = 5'd6,
		StOwner3Issue       = 5'd7,
		StOwner3Wait        = 5'd8,
		StOwner20Issue      = 5'd9,
		StOwner20Wait       = 5'd10,
		StOwner22Issue      = 5'd11,
		StOwner22Wait       = 5'd12,
		StCpuPrecheck       = 5'd13,
		StCpuIssue          = 5'd14,
		StCpuWait           = 5'd15,
		StAbortWait         = 5'd16,
		StAbortReset        = 5'd17,
		StAbortFinish       = 5'd18,
		StWaitWithdraw      = 5'd19,
		StReleaseWait       = 5'd20,
		StReleaseRearm      = 5'd21,
		StFault             = 5'd22
	} endpoint_state_e;

	endpoint_state_e state_q;
	epoch_phase_e epoch_phase_q;

	logic [15:0] active_packet_q;
	logic  [3:0] epoch_game_q;
	logic        epoch_restore_q;
	logic        epoch_active_q;
	logic        state_hold_q;
	logic        restore_enable_q;
	logic        main_stopped_q;
	logic        mutation_started_q;

	logic owner3_load_seen_q;
	logic owner20_load_seen_q;
	logic owner20_applied_seen_q;
	logic owner22_load_seen_q;
	logic cpu_done_seen_q;
	logic cpu_abort_seen_q;
	logic [7:0] fault_reason_q;
	logic [23:0] fault_context_q;

	wire [4:0] command_opcode = command_i[4:0];
	wire [3:0] command_game = command_i[8:5];
	wire       command_restore = command_i[9];

	function automatic logic bit_known(input logic value);
		begin
			bit_known =
				(value === 1'b0) || (value === 1'b1);
		end
	endfunction

	function automatic logic game_supported(input logic [3:0] value);
		begin
			case (value)
				4'd0,
				4'd1,
				4'd2,
				4'd3,
				4'd4:
					game_supported = 1'b1;
				default:
					game_supported = 1'b0;
			endcase
		end
	endfunction

	wire command_known =
		((command_i == command_i) === 1'b1);
	wire command_header_valid =
		command_known &&
		(command_i[15:10] === 6'd0) &&
		game_supported(command_game) &&
		(command_game === game_index_i);
	wire command_matches_epoch =
		epoch_active_q &&
		(command_game === epoch_game_q) &&
		(command_restore === epoch_restore_q);
	wire active_packet_held =
		(command_valid_i === 1'b1) &&
		(command_i === active_packet_q);

	wire owner3_staging_good =
		(owner3_validation_complete_i === 1'b1) &&
		(owner3_validation_valid_i === 1'b1) &&
		(owner3_write_complete_i === 1'b1) &&
		(owner3_write_valid_i === 1'b1);
	wire owner20_staging_good =
		(owner20_validation_complete_i === 1'b1) &&
		(owner20_validation_valid_i === 1'b1) &&
		(owner20_write_complete_i === 1'b1) &&
		(owner20_write_valid_i === 1'b1);
	wire owner22_staging_good =
		(owner22_validation_complete_i === 1'b1) &&
		(owner22_validation_valid_i === 1'b1) &&
		(owner22_write_complete_i === 1'b1) &&
		(owner22_write_valid_i === 1'b1);
	wire cpu_staging_good =
		(cpu_validation_complete_i === 1'b1) &&
		(cpu_validation_valid_i === 1'b1) &&
		(cpu_write_complete_i === 1'b1) &&
		(cpu_write_valid_i === 1'b1);

	wire owner3_staging_bad =
		((owner3_validation_complete_i === 1'b1) &&
		 (owner3_validation_valid_i !== 1'b1)) ||
		((owner3_write_complete_i === 1'b1) &&
		 (owner3_write_valid_i !== 1'b1));
	wire owner20_staging_bad =
		((owner20_validation_complete_i === 1'b1) &&
		 (owner20_validation_valid_i !== 1'b1)) ||
		((owner20_write_complete_i === 1'b1) &&
		 (owner20_write_valid_i !== 1'b1));
	wire owner22_staging_bad =
		((owner22_validation_complete_i === 1'b1) &&
		 (owner22_validation_valid_i !== 1'b1)) ||
		((owner22_write_complete_i === 1'b1) &&
		 (owner22_write_valid_i !== 1'b1));
	wire cpu_staging_bad =
		((cpu_validation_complete_i === 1'b1) &&
		 (cpu_validation_valid_i !== 1'b1)) ||
		((cpu_write_complete_i === 1'b1) &&
		 (cpu_write_valid_i !== 1'b1));

	wire statuses_known =
		bit_known(command_valid_i) &&
		bit_known(release_request_i) &&
		bit_known(release_restore_i) &&
		bit_known(cpu_captured_i) &&
		bit_known(cpu_restore_done_i) &&
		bit_known(cpu_abort_ack_i) &&
		bit_known(cpu_validation_complete_i) &&
		bit_known(cpu_validation_valid_i) &&
		bit_known(cpu_write_complete_i) &&
		bit_known(cpu_write_valid_i) &&
		bit_known(cpu_restore_committed_i) &&
		bit_known(cpu_owner_idle_i) &&
		bit_known(cpu_terminal_fault_i) &&
		bit_known(owner3_validation_complete_i) &&
		bit_known(owner3_validation_valid_i) &&
		bit_known(owner3_write_complete_i) &&
		bit_known(owner3_write_valid_i) &&
		bit_known(owner3_restore_load_i) &&
		bit_known(owner3_restore_committed_i) &&
		bit_known(owner3_idle_i) &&
		bit_known(owner3_terminal_fault_i) &&
		bit_known(owner20_validation_complete_i) &&
		bit_known(owner20_validation_valid_i) &&
		bit_known(owner20_write_complete_i) &&
		bit_known(owner20_write_valid_i) &&
		bit_known(owner20_restore_load_i) &&
		bit_known(owner20_restore_committed_i) &&
		bit_known(owner20_external_applied_i) &&
		bit_known(owner20_idle_i) &&
		bit_known(owner20_terminal_fault_i) &&
		bit_known(owner20_bridge_terminal_fault_i) &&
		bit_known(owner22_validation_complete_i) &&
		bit_known(owner22_validation_valid_i) &&
		bit_known(owner22_write_complete_i) &&
		bit_known(owner22_write_valid_i) &&
		bit_known(owner22_restore_load_i) &&
		bit_known(owner22_restore_committed_i) &&
		bit_known(owner22_idle_i) &&
		bit_known(owner22_terminal_fault_i) &&
		((game_index_i == game_index_i) === 1'b1);

	wire imported_fault =
		(cpu_terminal_fault_i !== 1'b0) ||
		(owner3_terminal_fault_i !== 1'b0) ||
		(owner20_terminal_fault_i !== 1'b0) ||
		(owner20_bridge_terminal_fault_i !== 1'b0) ||
		(owner22_terminal_fault_i !== 1'b0);

	wire executing_command =
		(state_q != StReady) &&
		(state_q != StWaitWithdraw) &&
		(state_q != StReleaseWait) &&
		(state_q != StReleaseRearm) &&
		(state_q != StFault);

	wire unsolicited_apply =
		(owner3_restore_load_i &&
		 (state_q != StOwner3Wait)) ||
		(owner20_restore_load_i &&
		 (state_q != StOwner20Wait)) ||
		(owner20_external_applied_i &&
		 (state_q != StOwner20Wait)) ||
		(owner22_restore_load_i &&
		 (state_q != StOwner22Issue) &&
		 (state_q != StOwner22Wait)) ||
		(cpu_restore_done_i &&
		 (state_q != StCpuWait)) ||
		(cpu_abort_ack_i &&
		 (state_q != StAbortWait));

	wire release_protocol_fault =
		((state_q == StReleaseWait) ||
		 (state_q == StReleaseRearm)) &&
		((release_request_i !== 1'b0) ||
		 (release_restore_i !== epoch_restore_q));
	wire unexpected_cpu_release =
		epoch_active_q &&
		main_stopped_q &&
		state_hold_q &&
		(cpu_captured_i !== 1'b1) &&
		(state_q != StCpuWait) &&
		(state_q != StAbortWait) &&
		(state_q != StAbortReset) &&
		(state_q != StAbortFinish);

	wire begin_rearmed =
		(cpu_owner_idle_i === 1'b1) &&
		(owner3_idle_i === 1'b1) &&
		(owner20_idle_i === 1'b1) &&
		(owner22_idle_i === 1'b1) &&
		(cpu_validation_complete_i === 1'b0) &&
		(cpu_write_complete_i === 1'b0) &&
		(cpu_restore_committed_i === 1'b0) &&
		(owner3_validation_complete_i === 1'b0) &&
		(owner3_write_complete_i === 1'b0) &&
		(owner3_restore_committed_i === 1'b0) &&
		(owner20_validation_complete_i === 1'b0) &&
		(owner20_write_complete_i === 1'b0) &&
		(owner20_restore_committed_i === 1'b0) &&
		(owner22_validation_complete_i === 1'b0) &&
		(owner22_write_complete_i === 1'b0) &&
		(owner22_restore_committed_i === 1'b0);
	wire begin_owners_idle =
		(cpu_owner_idle_i === 1'b1) &&
		(owner3_idle_i === 1'b1) &&
		(owner20_idle_i === 1'b1) &&
		(owner22_idle_i === 1'b1);

	wire game_changed_fault =
		epoch_active_q &&
		(game_index_i !== epoch_game_q);
	wire active_packet_fault =
		executing_command && !active_packet_held;
	wire release_command_valid_fault =
		((state_q == StReleaseWait) ||
		 (state_q == StReleaseRearm)) &&
		(command_valid_i !== 1'b0);
	wire global_fault_event =
		!statuses_known ||
		imported_fault ||
		release_protocol_fault ||
		unexpected_cpu_release ||
		game_changed_fault ||
		unsolicited_apply ||
		active_packet_fault ||
		release_command_valid_fault;
	wire [7:0] global_fault_reason =
		!statuses_known               ? 8'h01 :
		imported_fault                ? 8'h02 :
		release_protocol_fault        ? 8'h03 :
		unexpected_cpu_release        ? 8'h04 :
		game_changed_fault            ? 8'h05 :
		unsolicited_apply             ? 8'h06 :
		active_packet_fault           ? 8'h07 :
		release_command_valid_fault   ? 8'h08 :
		                                8'h00;
	wire [23:0] fault_context_live = {
		command_matches_epoch,
		active_packet_held,
		cpu_abort_ack_i,
		cpu_restore_done_i,
		owner22_restore_load_i,
		owner20_external_applied_i,
		owner20_restore_load_i,
		owner3_restore_load_i,
		owner22_idle_i,
		owner20_idle_i,
		owner3_idle_i,
		cpu_owner_idle_i,
		cpu_captured_i,
		release_restore_i,
		release_request_i,
		command_valid_i,
		mutation_started_q,
		main_stopped_q,
		state_hold_q,
		epoch_restore_q,
		epoch_active_q,
		epoch_phase_q
	};

	assign state_hold_o = state_hold_q;
	assign restore_enable_o = restore_enable_q;
	assign main_stopped_o = main_stopped_q;
	assign state_debug_o = state_q;
	assign fault_debug_o = {fault_reason_q, fault_context_q};

	assign cpu_capture_request_o =
		!reset_i &&
		!terminal_fault_o &&
		(state_q == StStopWait);
	assign restore_begin_o =
		!reset_i &&
		!terminal_fault_o &&
		(state_q == StBeginPulse);
	assign owner3_restore_commit_o =
		!reset_i &&
		!terminal_fault_o &&
		(state_q == StOwner3Issue);
	assign owner20_restore_commit_o =
		!reset_i &&
		!terminal_fault_o &&
		(state_q == StOwner20Issue);
	assign owner22_restore_commit_o =
		!reset_i &&
		!terminal_fault_o &&
		(state_q == StOwner22Issue);
	assign cpu_final_restore_commit_o =
		!reset_i &&
		!terminal_fault_o &&
		(state_q == StCpuIssue);
	assign cpu_abort_o =
		!reset_i &&
		!terminal_fault_o &&
		((state_q == StAbortWait) ||
		 (state_q == StAbortReset));
	assign noncpu_owner_reset_o =
		!reset_i &&
		!terminal_fault_o &&
		(((state_q == StBeginReset) && begin_owners_idle) ||
		 (state_q == StAbortReset));

	always_ff @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= StReady;
			epoch_phase_q <= PhaseIdle;
			active_packet_q <= 16'd0;
			epoch_game_q <= 4'd0;
			epoch_restore_q <= 1'b0;
			epoch_active_q <= 1'b0;
			state_hold_q <= 1'b0;
			restore_enable_q <= 1'b0;
			main_stopped_q <= 1'b0;
			mutation_started_q <= 1'b0;
			owner3_load_seen_q <= 1'b0;
			owner20_load_seen_q <= 1'b0;
			owner20_applied_seen_q <= 1'b0;
			owner22_load_seen_q <= 1'b0;
			cpu_done_seen_q <= 1'b0;
			cpu_abort_seen_q <= 1'b0;
			fault_reason_q <= 8'd0;
			fault_context_q <= 24'd0;
			command_complete_o <= 1'b0;
			command_response_o <= 8'd0;
			release_complete_o <= 1'b0;
			main_abort_ack_o <= 1'b0;
			terminal_fault_o <= 1'b0;
		end else begin
			command_complete_o <= 1'b0;
			command_response_o <= 8'd0;
			release_complete_o <= 1'b0;
			main_abort_ack_o <= 1'b0;

			if (!terminal_fault_o && global_fault_event) begin
				terminal_fault_o <= 1'b1;
				state_q <= StFault;
				fault_reason_q <= global_fault_reason;
				fault_context_q <= fault_context_live;
			end else if (terminal_fault_o) begin
				state_q <= StFault;
			end else begin
				unique case (state_q)
					StReady: begin
						if (command_valid_i === 1'b1) begin
							active_packet_q <= command_i;

							if (!command_header_valid ||
							    (release_request_i !== 1'b0) ||
							    (command_opcode == CmdSoundCommit)) begin
								terminal_fault_o <= 1'b1;
								state_q <= StFault;
								fault_reason_q <= 8'h10;
								fault_context_q <= fault_context_live;
							end else begin
								unique case (command_opcode)
									CmdStop: begin
										if (epoch_active_q ||
										    (epoch_phase_q != PhaseIdle) ||
										    (cpu_captured_i !== 1'b0)) begin
											terminal_fault_o <= 1'b1;
											state_q <= StFault;
										end else begin
											epoch_game_q <= command_game;
											epoch_restore_q <= command_restore;
											epoch_active_q <= 1'b1;
											state_hold_q <= 1'b1;
											restore_enable_q <= 1'b0;
											main_stopped_q <= 1'b0;
											mutation_started_q <= 1'b0;
											owner3_load_seen_q <= 1'b0;
											owner20_load_seen_q <= 1'b0;
											owner20_applied_seen_q <= 1'b0;
											owner22_load_seen_q <= 1'b0;
											cpu_done_seen_q <= 1'b0;
											cpu_abort_seen_q <= 1'b0;
											// Hold the request in the existing wait state until
											// the CPU boundary gate admits and completes capture.
											state_q <= StStopWait;
										end
									end

									CmdBegin: begin
										if (!command_matches_epoch ||
										    !epoch_restore_q ||
										    (epoch_phase_q !=
										     PhaseRestoreBegin) ||
										    !main_stopped_q ||
										    !state_hold_q ||
										    mutation_started_q) begin
											terminal_fault_o <= 1'b1;
											state_q <= StFault;
										end else begin
											state_q <= StBeginReset;
										end
									end

									CmdEnable: begin
										if (!command_matches_epoch ||
										    !epoch_restore_q ||
										    (epoch_phase_q !=
										     PhaseRestoreEnable) ||
										    !main_stopped_q ||
										    !state_hold_q ||
										    mutation_started_q ||
										    (cpu_validation_complete_i !==
										     1'b1) ||
										    (cpu_validation_valid_i !==
										     1'b1) ||
										    (owner3_validation_complete_i !==
										     1'b1) ||
										    (owner3_validation_valid_i !==
										     1'b1) ||
										    (owner20_validation_complete_i !==
										     1'b1) ||
										    (owner20_validation_valid_i !==
										     1'b1) ||
										    (owner22_validation_complete_i !==
										     1'b1) ||
										    (owner22_validation_valid_i !==
										     1'b1) ||
										    !begin_owners_idle) begin
											terminal_fault_o <= 1'b1;
											state_q <= StFault;
										end else begin
											restore_enable_q <= 1'b1;
											epoch_phase_q <=
												PhaseRestoreNoncpu;
											command_complete_o <= 1'b1;
											command_response_o <=
												RESPONSE_OK;
											state_q <= StWaitWithdraw;
										end
									end

									CmdAbort: begin
										if (!epoch_active_q) begin
											if ((epoch_phase_q !=
											     PhaseIdle) ||
											    state_hold_q ||
											    restore_enable_q ||
											    main_stopped_q ||
											    (cpu_captured_i !==
											     1'b0)) begin
												terminal_fault_o <= 1'b1;
												state_q <= StFault;
											end else begin
												main_abort_ack_o <= 1'b1;
												command_complete_o <= 1'b1;
												command_response_o <=
													RESPONSE_OK;
												state_q <=
													StWaitWithdraw;
											end
										end else if (
											!command_matches_epoch ||
											(epoch_phase_q == PhaseIdle) ||
											restore_enable_q ||
											mutation_started_q ||
											!state_hold_q ||
											!main_stopped_q
										) begin
											terminal_fault_o <= 1'b1;
											state_q <= StFault;
										end else begin
											cpu_abort_seen_q <= 1'b0;
											state_q <= StAbortWait;
										end
									end

									CmdNoncpuCommit: begin
										if (!command_matches_epoch ||
										    !epoch_restore_q ||
										    (epoch_phase_q !=
										     PhaseRestoreNoncpu) ||
										    !restore_enable_q ||
										    !main_stopped_q ||
										    !state_hold_q ||
										    mutation_started_q) begin
											terminal_fault_o <= 1'b1;
											state_q <= StFault;
										end else begin
											owner3_load_seen_q <= 1'b0;
											owner20_load_seen_q <= 1'b0;
											owner20_applied_seen_q <= 1'b0;
											owner22_load_seen_q <= 1'b0;
											state_q <= StNoncpuPrecheck;
										end
									end

									CmdCpuFinalCommit: begin
										if (!command_matches_epoch ||
										    !epoch_restore_q ||
										    (epoch_phase_q !=
										     PhaseRestoreCpu) ||
										    !restore_enable_q ||
										    !main_stopped_q ||
										    !state_hold_q ||
										    !mutation_started_q) begin
											terminal_fault_o <= 1'b1;
											state_q <= StFault;
										end else begin
											cpu_done_seen_q <= 1'b0;
											state_q <= StCpuPrecheck;
										end
									end

									default: begin
										terminal_fault_o <= 1'b1;
										state_q <= StFault;
									end
								endcase
							end
						end else if (release_request_i === 1'b1) begin
							if (!epoch_active_q ||
							    !main_stopped_q ||
							    !state_hold_q ||
							    ((epoch_phase_q == PhaseSaveHeld) &&
							     (epoch_restore_q ||
							      (release_restore_i !== 1'b0))) ||
							    ((epoch_phase_q ==
							      PhaseRestoreCommitted) &&
							     (!epoch_restore_q ||
							      (release_restore_i !== 1'b1))) ||
							    ((epoch_phase_q != PhaseSaveHeld) &&
							     (epoch_phase_q !=
							      PhaseRestoreCommitted))) begin
								terminal_fault_o <= 1'b1;
								state_q <= StFault;
								fault_reason_q <= 8'h11;
								fault_context_q <= fault_context_live;
							end else begin
								restore_enable_q <= 1'b0;
								state_q <= StReleaseWait;
							end
						end
					end

					StStopLaunch: begin
						state_q <= StStopWait;
					end

					StStopWait: begin
						if (cpu_captured_i === 1'b1) begin
							main_stopped_q <= 1'b1;
							epoch_phase_q <= epoch_restore_q
								? PhaseRestoreBegin
								: PhaseSaveHeld;
							command_complete_o <= 1'b1;
							command_response_o <= RESPONSE_OK;
							state_q <= StWaitWithdraw;
						end
					end

					StBeginReset: begin
						if (begin_owners_idle)
							state_q <= StBeginPulse;
					end

					StBeginPulse: begin
						state_q <= StBeginWait;
					end

					StBeginWait: begin
						if (begin_rearmed) begin
							epoch_phase_q <= PhaseRestoreEnable;
							command_complete_o <= 1'b1;
							command_response_o <= RESPONSE_OK;
							state_q <= StWaitWithdraw;
						end
					end

					StNoncpuPrecheck: begin
						if (cpu_staging_bad ||
						    owner3_staging_bad ||
						    owner20_staging_bad ||
						    owner22_staging_bad ||
						    (cpu_restore_committed_i !== 1'b0) ||
						    (owner3_restore_committed_i !== 1'b0) ||
						    (owner20_restore_committed_i !== 1'b0) ||
						    (owner22_restore_committed_i !== 1'b0)) begin
							terminal_fault_o <= 1'b1;
							state_q <= StFault;
						end else if (cpu_staging_good &&
						            owner3_staging_good &&
						            owner20_staging_good &&
						            owner22_staging_good &&
						            (cpu_owner_idle_i === 1'b1) &&
						            (owner3_idle_i === 1'b1) &&
						            (owner20_idle_i === 1'b1) &&
						            (owner22_idle_i === 1'b1)) begin
							state_q <= StOwner3Issue;
						end
					end

					StOwner3Issue: begin
						state_q <= StOwner3Wait;
					end

					StOwner3Wait: begin
						if ((owner3_restore_load_i === 1'b1) &&
						    owner3_load_seen_q) begin
							terminal_fault_o <= 1'b1;
							state_q <= StFault;
						end else if (
							(owner3_restore_committed_i === 1'b1) &&
							!(owner3_load_seen_q ||
							  owner3_restore_load_i)
						) begin
							terminal_fault_o <= 1'b1;
							state_q <= StFault;
						end else begin
							if (owner3_restore_load_i === 1'b1) begin
								owner3_load_seen_q <= 1'b1;
								mutation_started_q <= 1'b1;
							end

							if (
								(owner3_restore_committed_i ===
								 1'b1) &&
								(owner3_load_seen_q ||
								 owner3_restore_load_i) &&
								(owner3_idle_i === 1'b1)
							) begin
								state_q <= StOwner20Issue;
							end
						end
					end

					StOwner20Issue: begin
						state_q <= StOwner20Wait;
					end

					StOwner20Wait: begin
						if (((owner20_restore_load_i === 1'b1) &&
						     owner20_load_seen_q) ||
						    ((owner20_external_applied_i === 1'b1) &&
						     owner20_applied_seen_q)) begin
							terminal_fault_o <= 1'b1;
							state_q <= StFault;
						end else if (
							(owner20_external_applied_i === 1'b1) &&
							!(owner20_load_seen_q ||
							  owner20_restore_load_i)
						) begin
							terminal_fault_o <= 1'b1;
							state_q <= StFault;
						end else if (
							(owner20_restore_committed_i === 1'b1) &&
							!(owner20_load_seen_q ||
							  owner20_restore_load_i)
						) begin
							terminal_fault_o <= 1'b1;
							state_q <= StFault;
						end else begin
							if (owner20_restore_load_i === 1'b1)
								owner20_load_seen_q <= 1'b1;
							if (owner20_external_applied_i === 1'b1)
								owner20_applied_seen_q <= 1'b1;

							if (
								(owner20_restore_committed_i ===
								 1'b1) &&
								(owner20_load_seen_q ||
								 owner20_restore_load_i) &&
								(owner20_applied_seen_q ||
								 owner20_external_applied_i) &&
								(owner20_idle_i === 1'b1)
							) begin
								state_q <= StOwner22Issue;
							end
						end
					end

					StOwner22Issue: begin
						if (owner22_restore_load_i === 1'b1) begin
							owner22_load_seen_q <= 1'b1;
							state_q <= StOwner22Wait;
						end else begin
							terminal_fault_o <= 1'b1;
							state_q <= StFault;
						end
					end

					StOwner22Wait: begin
						if ((owner22_restore_load_i === 1'b1) &&
						    owner22_load_seen_q) begin
							terminal_fault_o <= 1'b1;
							state_q <= StFault;
						end else if (
							(owner22_restore_committed_i === 1'b1) &&
							!(owner22_load_seen_q ||
							  owner22_restore_load_i)
						) begin
							terminal_fault_o <= 1'b1;
							state_q <= StFault;
						end else begin
							if (owner22_restore_load_i === 1'b1)
								owner22_load_seen_q <= 1'b1;

							if (
								(owner22_restore_committed_i ===
								 1'b1) &&
								(owner22_load_seen_q ||
								 owner22_restore_load_i) &&
								(owner22_idle_i === 1'b1)
							) begin
								epoch_phase_q <= PhaseRestoreCpu;
								command_complete_o <= 1'b1;
								command_response_o <= RESPONSE_OK;
								state_q <= StWaitWithdraw;
							end
						end
					end

					StCpuPrecheck: begin
						if (cpu_staging_bad ||
						    (cpu_restore_committed_i !== 1'b0)) begin
							terminal_fault_o <= 1'b1;
							state_q <= StFault;
						end else if (cpu_staging_good &&
						            (cpu_owner_idle_i === 1'b1) &&
						            (cpu_captured_i === 1'b1)) begin
							state_q <= StCpuIssue;
						end
					end

					StCpuIssue: begin
						state_q <= StCpuWait;
					end

					StCpuWait: begin
						if ((cpu_restore_done_i === 1'b1) &&
						    cpu_done_seen_q) begin
							terminal_fault_o <= 1'b1;
							state_q <= StFault;
						end else if (
							(cpu_restore_committed_i === 1'b1) &&
							!(cpu_done_seen_q ||
							  cpu_restore_done_i)
						) begin
							terminal_fault_o <= 1'b1;
							state_q <= StFault;
						end else begin
							if (cpu_restore_done_i === 1'b1)
								cpu_done_seen_q <= 1'b1;

							if (
								(cpu_restore_committed_i === 1'b1) &&
								(cpu_done_seen_q ||
								 cpu_restore_done_i) &&
								(cpu_owner_idle_i === 1'b1) &&
								(cpu_captured_i === 1'b1)
							) begin
								epoch_phase_q <=
									PhaseRestoreCommitted;
								command_complete_o <= 1'b1;
								command_response_o <= RESPONSE_OK;
								state_q <= StWaitWithdraw;
							end
						end
					end

					StAbortWait: begin
						if ((cpu_abort_ack_i === 1'b1) &&
						    cpu_abort_seen_q) begin
							terminal_fault_o <= 1'b1;
							state_q <= StFault;
						end else begin
							if (cpu_abort_ack_i === 1'b1)
								cpu_abort_seen_q <= 1'b1;

							if ((cpu_abort_seen_q ||
							     cpu_abort_ack_i) &&
							    (cpu_captured_i === 1'b0) &&
							    (cpu_owner_idle_i === 1'b1) &&
							    (owner3_idle_i === 1'b1) &&
							    (owner20_idle_i === 1'b1) &&
							    (owner22_idle_i === 1'b1)) begin
								state_q <= StAbortReset;
							end
						end
					end

					StAbortReset: begin
						state_q <= StAbortFinish;
					end

					StAbortFinish: begin
						if ((cpu_captured_i !== 1'b0) ||
						    (cpu_owner_idle_i !== 1'b1)) begin
							terminal_fault_o <= 1'b1;
							state_q <= StFault;
						end else begin
							state_hold_q <= 1'b0;
							restore_enable_q <= 1'b0;
							main_stopped_q <= 1'b0;
							mutation_started_q <= 1'b0;
							epoch_active_q <= 1'b0;
							epoch_restore_q <= 1'b0;
							epoch_phase_q <= PhaseIdle;
							main_abort_ack_o <= 1'b1;
							command_complete_o <= 1'b1;
							command_response_o <= RESPONSE_OK;
							state_q <= StWaitWithdraw;
						end
					end

					StWaitWithdraw: begin
						if (command_valid_i === 1'b0) begin
							active_packet_q <= 16'd0;
							state_q <= StReady;
						end else if (!active_packet_held) begin
							terminal_fault_o <= 1'b1;
							state_q <= StFault;
						end
					end

					StReleaseWait: begin
						// Owner 22's physical-idle proof is defined only
						// while EEPROM hold is asserted.  Drain every owner
						// first, then withdraw the hold and wait for CPU and
						// register-owner rearm; owner22_idle_i necessarily
						// falls once the EEPROM resumes.
						if (state_hold_q &&
						    (cpu_captured_i === 1'b1) &&
						    (cpu_owner_idle_i === 1'b1) &&
						    (owner3_idle_i === 1'b1) &&
						    (owner20_idle_i === 1'b1) &&
						    (owner22_idle_i === 1'b1)) begin
							state_hold_q <= 1'b0;
						end else if (
							!state_hold_q &&
							(cpu_captured_i === 1'b0) &&
							(cpu_owner_idle_i === 1'b1) &&
							(owner3_idle_i === 1'b1) &&
							(owner20_idle_i === 1'b1)
						) begin
							main_stopped_q <= 1'b0;
							mutation_started_q <= 1'b0;
							release_complete_o <= 1'b1;
							state_q <= StReleaseRearm;
						end
					end

					StReleaseRearm: begin
						if (release_request_i === 1'b0) begin
							epoch_active_q <= 1'b0;
							epoch_restore_q <= 1'b0;
							epoch_phase_q <= PhaseIdle;
							state_q <= StReady;
						end
					end

					StFault: begin
						state_q <= StFault;
					end

					default: begin
						terminal_fault_o <= 1'b1;
						state_q <= StFault;
					end
				endcase
			end
		end
	end

endmodule

`default_nettype wire
