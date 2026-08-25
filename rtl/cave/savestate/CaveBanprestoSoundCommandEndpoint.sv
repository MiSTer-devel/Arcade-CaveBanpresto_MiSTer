`default_nettype none

// Sound-domain consumer for the coordinator's held 16-bit MCP command packet.
//
// This block is synchronous to the Sound/T80 clock.  The cross-domain MCP is
// wholly owned by CaveBanprestoSaveStateControlCdc; no command bit or payload
// bit is synchronized again here.
//
// Packet ABI:
//   [4:0]   opcode
//   [8:5]   immutable game index
//   [9]     immutable STOP-epoch restore intent
//   [15:10] reserved, must be zero
//
// Legal Sound opcodes are STOP, BEGIN, ENABLE, COMMIT, and ABORT.  Main-only
// NONCPU_COMMIT and CPU_FINAL_COMMIT are routing faults and never become
// no-ops.  A held command is captured once, must remain bit-for-bit stable
// through completion, and cannot be executed again while valid remains high.
//
// COMMIT ordering is local and explicit:
//   1. prove every required owner staged and idle;
//   2. pulse owner 25 and required OKI commits;
//   3. wait their sticky commit plus OKI prime and owner-idle evidence;
//   4. pulse owner 23/T80 commit last;
//   5. wait both T80 restore-load and sticky committed evidence;
//   6. acknowledge the held command.
//
// ABORT is legal only before ENABLE authorizes pass-2 mutation.  It drains the
// owner bus first, then asks the already-held Sound CPU to unwind.  It never
// emits BEGIN or either commit pulse and never resets a core.
module CaveBanprestoSoundCommandEndpoint #(
	parameter [7:0] RESPONSE_OK_VALUE = 8'h01
) (
	input  wire        clk_i,
	input  wire        reset_i,

	input  wire        command_valid_i,
	input  wire [15:0] command_i,
	input  wire  [3:0] current_game_index_i,

	// Bit zero is owner 23; bit six is owner 29.
	input  wire  [6:0] owner_required_i,
	input  wire  [6:0] owner_idle_i,
	input  wire        owner_bus_idle_i,
	input  wire  [6:0] owner_commit_ready_i,
	input  wire  [6:0] owner_committed_i,
	input  wire  [6:0] owner_prime_i,

	input  wire        sound_stopped_i,
	input  wire        external_idle_i,
	input  wire        sound_abort_ack_i,
	input  wire        release_complete_i,
	input  wire        lower_terminal_fault_i,

	output logic       command_complete_o,
	output wire  [7:0] command_response_o,
	output logic       terminal_fault_o,

	output logic       stop_request_o,
	output logic       restore_mode_o,
	output logic       state_enable_o,
	output logic       restore_enable_o,
	output logic       abort_o,
	output logic       restore_begin_o,
	output logic       device_restore_commit_o,
	output logic       t80_restore_commit_o,
	output wire  [3:0] state_debug_o
);

	localparam [4:0] CmdStop           = 5'd1;
	localparam [4:0] CmdBegin          = 5'd2;
	localparam [4:0] CmdEnable         = 5'd3;
	localparam [4:0] CmdAbort          = 5'd4;
	localparam [4:0] CmdNoncpuCommit   = 5'd5;
	localparam [4:0] CmdCommit         = 5'd6;
	localparam [4:0] CmdCpuFinalCommit = 5'd7;

	// Commit-capable owners are T80(23), wrapper(25), OKI0(28), OKI1(29).
	localparam [6:0] COMMIT_OWNER_MASK = 7'b110_0101;
	localparam [6:0] DEVICE_COMMIT_MASK = 7'b110_0100;
	localparam [6:0] T80_OWNER_MASK = 7'b000_0001;

	typedef enum logic [3:0] {
		StIdle              = 4'd0,
		StStopWait          = 4'd1,
		StBeginDrain        = 4'd2,
		StBeginClearWait    = 4'd3,
		StCommitPrecheck    = 4'd4,
		StDeviceCommitWait  = 4'd5,
		StT80CommitWait     = 4'd6,
		StAbortDrain        = 4'd7,
		StAbortWait         = 4'd8,
		StWaitCommandLow    = 4'd9,
		StTerminal          = 4'd10
	} state_e;

	typedef enum logic [2:0] {
		EpNone      = 3'd0,
		EpStopping  = 3'd1,
		EpStopped   = 3'd2,
		EpBegan     = 3'd3,
		EpEnabled   = 3'd4,
		EpCommitted = 3'd5
	} epoch_phase_e;

	state_e state_q;
	epoch_phase_e epoch_phase_q;

	// Justification (reg-a): immutable held-command comparison image.
	logic [15:0] command_hold_q;
	// Justification (reg-d): STOP freezes the complete Sound epoch identity.
	logic        epoch_active_q;
	logic  [3:0] epoch_game_index_q;
	logic        epoch_restore_q;
	logic  [6:0] epoch_owner_required_q;
	// Justification (reg-a): one-cycle OKI/T80 evidence must survive until all
	// other required proofs arrive.
	logic  [6:0] prime_seen_q;

	wire [4:0] packet_opcode = command_i[4:0];
	wire [3:0] packet_game_index = command_i[8:5];
	wire       packet_restore = command_i[9];
	wire [5:0] packet_reserved = command_i[15:10];

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

	wire command_valid_known =
		(command_valid_i === 1'b0) ||
		(command_valid_i === 1'b1);
	wire packet_known =
		((command_i == command_i) === 1'b1) &&
		((current_game_index_i == current_game_index_i) === 1'b1) &&
		((owner_required_i == owner_required_i) === 1'b1);
	wire [31:0] evidence_view = {
		owner_idle_i,
		owner_commit_ready_i,
		owner_committed_i,
		owner_prime_i,
		owner_bus_idle_i,
		sound_stopped_i,
		external_idle_i,
		sound_abort_ack_i
	};
	wire evidence_known =
		((evidence_view == evidence_view) === 1'b1);
	wire packet_base_valid =
		packet_known &&
		(packet_reserved == 6'd0) &&
		game_supported(packet_game_index) &&
		(packet_game_index == current_game_index_i);
	wire packet_epoch_matches =
		epoch_active_q &&
		(packet_game_index == epoch_game_index_q) &&
		(packet_restore == epoch_restore_q) &&
		(owner_required_i == epoch_owner_required_q) &&
		(current_game_index_i == epoch_game_index_q);

	wire [6:0] required_idle_view =
		owner_idle_i | ~epoch_owner_required_q;
	wire all_required_owners_idle =
		(required_idle_view === 7'h7f);
	wire stop_applied =
		(sound_stopped_i === 1'b1) &&
		(external_idle_i === 1'b1) &&
		(owner_bus_idle_i === 1'b1) &&
		all_required_owners_idle;

	wire [6:0] commit_owner_required =
		epoch_owner_required_q & COMMIT_OWNER_MASK;
	wire [6:0] device_commit_required =
		epoch_owner_required_q & DEVICE_COMMIT_MASK;
	wire [6:0] non_t80_required =
		epoch_owner_required_q & ~T80_OWNER_MASK;

	wire all_commit_owners_ready =
		((owner_commit_ready_i | ~commit_owner_required) === 7'h7f);
	wire all_non_t80_owners_idle =
		((owner_idle_i | ~non_t80_required) === 7'h7f);
	wire all_device_owners_committed =
		((owner_committed_i | ~device_commit_required) === 7'h7f);
	wire all_device_owners_primed =
		((prime_seen_q | owner_prime_i |
		  ~device_commit_required) === 7'h7f);
	wire commit_owners_clear =
		((owner_commit_ready_i & commit_owner_required) === 7'd0) &&
		((owner_committed_i & commit_owner_required) === 7'd0);
	wire no_commit_seen_early =
		((owner_committed_i & commit_owner_required) === 7'd0) &&
		((owner_prime_i & T80_OWNER_MASK) === 7'd0);

	wire begin_clear_complete =
		commit_owners_clear &&
		(owner_bus_idle_i === 1'b1) &&
		all_required_owners_idle;
	wire commit_precheck_complete =
		(sound_stopped_i === 1'b1) &&
		(external_idle_i === 1'b1) &&
		(owner_bus_idle_i === 1'b1) &&
		all_required_owners_idle &&
		all_commit_owners_ready &&
		no_commit_seen_early;
	wire device_commit_complete =
		(sound_stopped_i === 1'b1) &&
		(external_idle_i === 1'b1) &&
		(owner_bus_idle_i === 1'b1) &&
		all_non_t80_owners_idle &&
		all_device_owners_committed &&
		all_device_owners_primed &&
		((owner_committed_i & T80_OWNER_MASK) === 7'd0) &&
		((owner_prime_i & T80_OWNER_MASK) === 7'd0);
	wire t80_commit_complete =
		(sound_stopped_i === 1'b1) &&
		(external_idle_i === 1'b1) &&
		(owner_bus_idle_i === 1'b1) &&
		all_required_owners_idle &&
		all_device_owners_committed &&
		all_device_owners_primed &&
		(owner_committed_i[0] === 1'b1) &&
		((prime_seen_q[0] === 1'b1) ||
		 (owner_prime_i[0] === 1'b1));

	wire held_command_state =
		(state_q != StIdle) &&
		(state_q != StWaitCommandLow) &&
		(state_q != StTerminal);
	wire held_payload_changed =
		(state_q != StIdle) &&
		(state_q != StTerminal) &&
		(command_valid_i === 1'b1) &&
		(command_i !== command_hold_q);
	wire held_command_dropped =
		held_command_state &&
		(command_valid_i !== 1'b1);
	wire epoch_identity_changed =
		epoch_active_q &&
		((current_game_index_i !== epoch_game_index_q) ||
		 (owner_required_i !== epoch_owner_required_q));
	wire release_protocol_fault =
		(release_complete_i === 1'b1) &&
		((state_q != StIdle) ||
		 (command_valid_i !== 1'b0) ||
		 !epoch_active_q ||
		 (epoch_restore_q
		  ? (epoch_phase_q != EpCommitted)
		  : (epoch_phase_q != EpStopped)));
	wire release_known =
		(release_complete_i === 1'b0) ||
		(release_complete_i === 1'b1);
	wire protocol_fault_now =
		(lower_terminal_fault_i !== 1'b0) ||
		!command_valid_known ||
		!release_known ||
		!evidence_known ||
		held_payload_changed ||
		held_command_dropped ||
		epoch_identity_changed ||
		release_protocol_fault;

	assign command_response_o = RESPONSE_OK_VALUE;
	assign state_debug_o = state_q;

	always_ff @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= StIdle;
			epoch_phase_q <= EpNone;
			command_hold_q <= 16'd0;
			epoch_active_q <= 1'b0;
			epoch_game_index_q <= 4'd0;
			epoch_restore_q <= 1'b0;
			epoch_owner_required_q <= 7'd0;
			prime_seen_q <= 7'd0;
			command_complete_o <= 1'b0;
			terminal_fault_o <= 1'b0;
			stop_request_o <= 1'b0;
			restore_mode_o <= 1'b0;
			state_enable_o <= 1'b0;
			restore_enable_o <= 1'b0;
			abort_o <= 1'b0;
			restore_begin_o <= 1'b0;
			device_restore_commit_o <= 1'b0;
			t80_restore_commit_o <= 1'b0;
		end else begin
			command_complete_o <= 1'b0;
			restore_begin_o <= 1'b0;
			device_restore_commit_o <= 1'b0;
			t80_restore_commit_o <= 1'b0;

			if (protocol_fault_now) begin
				terminal_fault_o <= 1'b1;
				abort_o <= 1'b0;
				state_q <= StTerminal;
			end else if (!terminal_fault_o) begin
				if (release_complete_i === 1'b1) begin
					epoch_phase_q <= EpNone;
					epoch_active_q <= 1'b0;
					epoch_game_index_q <= 4'd0;
					epoch_restore_q <= 1'b0;
					epoch_owner_required_q <= 7'd0;
					prime_seen_q <= 7'd0;
					stop_request_o <= 1'b0;
					restore_mode_o <= 1'b0;
					state_enable_o <= 1'b0;
					restore_enable_o <= 1'b0;
					abort_o <= 1'b0;
				end

				unique case (state_q)
					StIdle: begin
						if (command_valid_i === 1'b1) begin
							command_hold_q <= command_i;

							if (!packet_base_valid) begin
								terminal_fault_o <= 1'b1;
								state_q <= StTerminal;
							end else begin
								unique case (packet_opcode)
									CmdStop: begin
										if (epoch_active_q ||
										    !owner_required_i[0] ||
										    !owner_required_i[2]) begin
											terminal_fault_o <= 1'b1;
											state_q <= StTerminal;
										end else begin
											epoch_phase_q <= EpStopping;
											epoch_active_q <= 1'b1;
											epoch_game_index_q <=
												packet_game_index;
											epoch_restore_q <=
												packet_restore;
											epoch_owner_required_q <=
												owner_required_i;
											prime_seen_q <= 7'd0;
											stop_request_o <= 1'b1;
											restore_mode_o <=
												packet_restore;
											state_enable_o <= 1'b1;
											restore_enable_o <= 1'b0;
											abort_o <= 1'b0;
											state_q <= StStopWait;
										end
									end

									CmdBegin: begin
										if (!packet_epoch_matches ||
										    !epoch_restore_q ||
										    (epoch_phase_q != EpStopped)) begin
											terminal_fault_o <= 1'b1;
											state_q <= StTerminal;
										end else begin
											prime_seen_q <= 7'd0;
											state_q <= StBeginDrain;
										end
									end

									CmdEnable: begin
										if (!packet_epoch_matches ||
										    !epoch_restore_q ||
										    (epoch_phase_q != EpBegan)) begin
											terminal_fault_o <= 1'b1;
											state_q <= StTerminal;
										end else begin
											restore_enable_o <= 1'b1;
											epoch_phase_q <= EpEnabled;
											command_complete_o <= 1'b1;
											state_q <= StWaitCommandLow;
										end
									end

									CmdCommit: begin
										if (!packet_epoch_matches ||
										    !epoch_restore_q ||
										    (epoch_phase_q != EpEnabled) ||
										    !restore_enable_o) begin
											terminal_fault_o <= 1'b1;
											state_q <= StTerminal;
										end else begin
											prime_seen_q <= 7'd0;
											state_q <= StCommitPrecheck;
										end
									end

									CmdAbort: begin
										if (epoch_active_q) begin
											if (!packet_epoch_matches ||
											    (epoch_phase_q == EpEnabled) ||
											    (epoch_phase_q == EpCommitted)) begin
												terminal_fault_o <= 1'b1;
												state_q <= StTerminal;
											end else begin
												state_q <= StAbortDrain;
											end
										end else begin
											// No epoch means there is no held/live
											// state to unwind.  Acknowledge exactly
											// once without pulsing any control.
											command_complete_o <= 1'b1;
											state_q <= StWaitCommandLow;
										end
									end

									CmdNoncpuCommit,
									CmdCpuFinalCommit: begin
										// Main-only commands at Sound are a
										// terminal routing error, never a no-op.
										terminal_fault_o <= 1'b1;
										state_q <= StTerminal;
									end

									default: begin
										terminal_fault_o <= 1'b1;
										state_q <= StTerminal;
									end
								endcase
							end
						end
					end

					StStopWait: begin
						if (stop_applied) begin
							epoch_phase_q <= EpStopped;
							command_complete_o <= 1'b1;
							state_q <= StWaitCommandLow;
						end
					end

					StBeginDrain: begin
						if (stop_applied) begin
							restore_begin_o <= 1'b1;
							prime_seen_q <= 7'd0;
							state_q <= StBeginClearWait;
						end
					end

					StBeginClearWait: begin
						if (begin_clear_complete) begin
							epoch_phase_q <= EpBegan;
							command_complete_o <= 1'b1;
							state_q <= StWaitCommandLow;
						end
					end

					StCommitPrecheck: begin
						if (!no_commit_seen_early) begin
							terminal_fault_o <= 1'b1;
							state_q <= StTerminal;
						end else if (commit_precheck_complete) begin
							device_restore_commit_o <= 1'b1;
							prime_seen_q <= 7'd0;
							state_q <= StDeviceCommitWait;
						end
					end

					StDeviceCommitWait: begin
						prime_seen_q <= prime_seen_q | owner_prime_i;

						if ((owner_committed_i[0] !== 1'b0) ||
						    (owner_prime_i[0] !== 1'b0)) begin
							terminal_fault_o <= 1'b1;
							state_q <= StTerminal;
						end else if (device_commit_complete) begin
							t80_restore_commit_o <= 1'b1;
							state_q <= StT80CommitWait;
						end
					end

					StT80CommitWait: begin
						prime_seen_q <= prime_seen_q | owner_prime_i;

						if (t80_commit_complete) begin
							epoch_phase_q <= EpCommitted;
							command_complete_o <= 1'b1;
							state_q <= StWaitCommandLow;
						end
					end

					StAbortDrain: begin
						if ((owner_bus_idle_i === 1'b1) &&
						    all_required_owners_idle) begin
							if (sound_stopped_i === 1'b1) begin
								abort_o <= 1'b1;
								state_q <= StAbortWait;
							end else begin
								epoch_phase_q <= EpNone;
								epoch_active_q <= 1'b0;
								epoch_game_index_q <= 4'd0;
								epoch_restore_q <= 1'b0;
								epoch_owner_required_q <= 7'd0;
								prime_seen_q <= 7'd0;
								stop_request_o <= 1'b0;
								restore_mode_o <= 1'b0;
								state_enable_o <= 1'b0;
								restore_enable_o <= 1'b0;
								abort_o <= 1'b0;
								command_complete_o <= 1'b1;
								state_q <= StWaitCommandLow;
							end
						end
					end

					StAbortWait: begin
						if (sound_abort_ack_i === 1'b1) begin
							epoch_phase_q <= EpNone;
							epoch_active_q <= 1'b0;
							epoch_game_index_q <= 4'd0;
							epoch_restore_q <= 1'b0;
							epoch_owner_required_q <= 7'd0;
							prime_seen_q <= 7'd0;
							stop_request_o <= 1'b0;
							restore_mode_o <= 1'b0;
							state_enable_o <= 1'b0;
							restore_enable_o <= 1'b0;
							abort_o <= 1'b0;
							command_complete_o <= 1'b1;
							state_q <= StWaitCommandLow;
						end
					end

					StWaitCommandLow: begin
						if (command_valid_i === 1'b0) begin
							command_hold_q <= 16'd0;
							state_q <= StIdle;
						end
					end

					StTerminal: begin
						terminal_fault_o <= 1'b1;
						abort_o <= 1'b0;
						state_q <= StTerminal;
					end

					default: begin
						terminal_fault_o <= 1'b1;
						abort_o <= 1'b0;
						state_q <= StTerminal;
					end
				endcase
			end else begin
				terminal_fault_o <= 1'b1;
				abort_o <= 1'b0;
				state_q <= StTerminal;
			end
		end
	end

endmodule

`default_nettype wire
