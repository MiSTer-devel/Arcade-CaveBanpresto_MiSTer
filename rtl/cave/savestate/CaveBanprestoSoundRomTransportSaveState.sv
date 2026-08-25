`default_nettype none

// CaveBanpresto-local owner-34 sound-ROM transport boundary.
//
// This module is intended to replace the three CaveSoundRomReadFreezer
// instances at integration time.  With every ss_* control low, each lane is
// the same one-request, address-tagged MCP/toggle crossing used by the repaired
// Cave sound-ROM freezer: the target-domain request address and system-domain
// response payload remain stable until the corresponding synchronized toggle
// is observed.
//
// Save-state ordering is deliberately stricter than a generic launch gate:
//   1. stop the sound CPU;
//   2. assert ss_launch_block_i;
//   3. retire every request already accepted in either clock domain;
//   4. observe every MemSys input wait_n high and valid low for a fence;
//   5. query owner 34 (zero serialized words);
//   6. after a restored/private Z80 launch exposes its release address, pulse
//      ss_prepare_release_i.  Slow-Z80 profiles set
//      ss_prefetch_required_i, which admits exactly one lane-0 prefetch while
//      the global launch gate remains closed;
//   7. the boundary reopens lane-0 normal acceptance, round-trips that fact
//      through the target domain, and only then raises
//      ss_restore_dependencies_ready_o.  Thus a released slow Z80 can advance
//      from the held byte to its next address without a gate-crossing bubble.
//   8. release only after ss_restore_dependencies_ready_o.
//
// A draining response is returned to the target for a complete target-clock
// interval.  This is required even while the CPU is stopped: the upstream
// CaveSoundRomReadArbiter clears its locked request only when it observes
// io_in_valid.  The response is discarded only after that retirement edge.
//
// CaveReadCache line data and replacement state are not serialized.  ROM is
// immutable, so those entries are derived acceleration state once all accepted
// traffic is retired.  Integrated verification must nevertheless compare
// cold- and warm-cache save/restore runs at exact release-cycle granularity.
//
// ss_abort_i never cancels accepted traffic.  Quiesce keeps
// ss_launch_block_i asserted through abort recovery, and the same
// prepare/dependency contract applies before release.  Any timeout or protocol
// violation is sticky and reset-only.

// Dedicated destination-clocked two-flop synchronizer.  Only single-bit
// protocol levels/toggles pass through this primitive; MCP payloads are held
// stable by their source until the synchronized event is consumed.
module CaveBanprestoSoundRomCdcBitSync #(
	parameter RESET_VALUE = 1'b0
) (
	input  wire clk_i,
	input  wire reset_i,
	input  wire async_i,
	output wire sync_o
);

	(* preserve, useioff = 0,
	   altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic sync0_q;
	(* preserve, useioff = 0,
	   altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic sync1_q;

	always_ff @(posedge clk_i) begin
		if (reset_i) begin
			sync0_q <= RESET_VALUE;
			sync1_q <= RESET_VALUE;
		end else begin
			sync0_q <= async_i;
			sync1_q <= sync0_q;
		end
	end

	assign sync_o = sync1_q;

endmodule

module CaveBanprestoSoundRomTransportLane #(
	parameter integer ALLOW_PREFETCH = 0,
	parameter integer FENCE_STABLE_CYCLES = 4,
	parameter integer TRANSACTION_TIMEOUT_CYCLES = 1_000_000
) (
	input  wire        system_clock_i,
	input  wire        system_reset_i,
	input  wire        target_clock_i,
	input  wire        target_reset_i,

	input  wire        launch_block_system_i,
	input  wire        prefetch_enable_system_i,
	input  wire        release_admit_system_i,
	input  wire        hold_response_i,

	input  wire        target_rd_i,
	input  wire [24:0] target_addr_i,
	output wire  [7:0] target_dout_o,
	output wire        target_wait_n_o,
	output wire        target_valid_o,

	output wire        memory_rd_o,
	output wire [24:0] memory_addr_o,
	input  wire  [7:0] memory_dout_i,
	input  wire        memory_wait_n_i,
	input  wire        memory_valid_i,

	output wire        system_idle_o,
	output wire        target_transport_idle_system_o,
	output wire        target_canonical_empty_system_o,
	output wire        prefetch_ready_system_o,
	output wire        response_held_system_o,
	output wire        release_open_system_o,
	output wire        launch_block_target_system_o,
	output logic       terminal_fault_o
);

	localparam integer FENCE_COUNT_WIDTH =
		(FENCE_STABLE_CYCLES <= 1) ? 1 :
		$clog2(FENCE_STABLE_CYCLES);
	localparam integer TIMEOUT_COUNT_WIDTH =
		(TRANSACTION_TIMEOUT_CYCLES <= 1) ? 1 :
		$clog2(TRANSACTION_TIMEOUT_CYCLES);
	localparam integer FENCE_COUNT_LIMIT =
		(FENCE_STABLE_CYCLES <= 1) ? 0 :
		FENCE_STABLE_CYCLES - 1;
	localparam integer TIMEOUT_COUNT_LIMIT =
		(TRANSACTION_TIMEOUT_CYCLES <= 1) ? 0 :
		TRANSACTION_TIMEOUT_CYCLES - 1;

	typedef enum logic [1:0] {
		StSystemIdle  = 2'd0,
		StSystemIssue = 2'd1,
		StSystemWait  = 2'd2,
		StSystemFence = 2'd3
	} system_state_e;

	// Target-domain request MCP source.
	logic        request_toggle_target_q;
	logic [24:0] request_addr_target_q;
	logic        pending_read_target_q;
	logic        request_armed_target_q;

	// Target-domain response MCP destination and response presentation state.
	logic        response_toggle_target_seen_q;
	logic  [7:0] response_data_target_q;
	logic [24:0] response_addr_target_q;
	logic        response_valid_target_q;
	logic        drain_retire_target_q;
	logic        prefetch_launched_target_q;
	logic        launch_block_target_d_q;
	logic        target_protocol_fault_q;

	// System-domain request MCP destination and memory transaction state.
	logic        request_toggle_system_seen_q;
	logic [24:0] request_addr_system_q;
	system_state_e system_state_q;
	logic [FENCE_COUNT_WIDTH-1:0] fence_count_q;
	logic [TIMEOUT_COUNT_WIDTH-1:0] timeout_count_q;

	// System-domain response MCP source.
	logic  [7:0] response_data_system_q;
	logic [24:0] response_addr_system_q;
	logic        response_toggle_system_q;

	wire launch_block_target;
	wire prefetch_enable_target;
	wire release_admit_target;
	wire request_toggle_system_sync;
	wire response_toggle_target_sync;
	wire target_fault_system_sync;

	wire new_request_system =
		request_toggle_system_sync != request_toggle_system_seen_q;
	wire new_response_target =
		response_toggle_target_sync != response_toggle_target_seen_q;
	wire normal_launch_block_target =
		launch_block_target && !release_admit_target;
	wire response_matches_target =
		response_valid_target_q &&
		target_rd_i &&
		(response_addr_target_q == target_addr_i);
	wire target_transport_idle =
		!pending_read_target_q &&
		!drain_retire_target_q &&
		(response_toggle_target_sync == response_toggle_target_seen_q);
	wire target_canonical_empty =
		normal_launch_block_target &&
		target_transport_idle &&
		!response_valid_target_q &&
		!prefetch_launched_target_q;
	wire prefetch_ready_target =
		normal_launch_block_target &&
		prefetch_enable_target &&
		prefetch_launched_target_q &&
		target_transport_idle &&
		response_matches_target;
	wire release_open_target =
		release_admit_target &&
		target_transport_idle;
	wire fence_quiet = memory_wait_n_i && !memory_valid_i;
	wire transaction_timeout =
		(TRANSACTION_TIMEOUT_CYCLES != 0) &&
		(system_state_q != StSystemIdle) &&
		(timeout_count_q == TIMEOUT_COUNT_LIMIT);

	CaveBanprestoSoundRomCdcBitSync launch_block_to_target (
		.clk_i   (target_clock_i),
		.reset_i (target_reset_i),
		.async_i (launch_block_system_i),
		.sync_o  (launch_block_target)
	);

	CaveBanprestoSoundRomCdcBitSync prefetch_enable_to_target (
		.clk_i   (target_clock_i),
		.reset_i (target_reset_i),
		.async_i (prefetch_enable_system_i),
		.sync_o  (prefetch_enable_target)
	);

	CaveBanprestoSoundRomCdcBitSync release_admit_to_target (
		.clk_i   (target_clock_i),
		.reset_i (target_reset_i),
		.async_i (release_admit_system_i),
		.sync_o  (release_admit_target)
	);

	CaveBanprestoSoundRomCdcBitSync request_toggle_to_system (
		.clk_i   (system_clock_i),
		.reset_i (system_reset_i),
		.async_i (request_toggle_target_q),
		.sync_o  (request_toggle_system_sync)
	);

	CaveBanprestoSoundRomCdcBitSync response_toggle_to_target (
		.clk_i   (target_clock_i),
		.reset_i (target_reset_i),
		.async_i (response_toggle_system_q),
		.sync_o  (response_toggle_target_sync)
	);

	CaveBanprestoSoundRomCdcBitSync target_idle_to_system (
		.clk_i   (system_clock_i),
		.reset_i (system_reset_i),
		.async_i (target_transport_idle),
		.sync_o  (target_transport_idle_system_o)
	);

	CaveBanprestoSoundRomCdcBitSync target_empty_to_system (
		.clk_i   (system_clock_i),
		.reset_i (system_reset_i),
		.async_i (target_canonical_empty),
		.sync_o  (target_canonical_empty_system_o)
	);

	CaveBanprestoSoundRomCdcBitSync prefetch_ready_to_system (
		.clk_i   (system_clock_i),
		.reset_i (system_reset_i),
		.async_i (prefetch_ready_target),
		.sync_o  (prefetch_ready_system_o)
	);

	CaveBanprestoSoundRomCdcBitSync response_held_to_system (
		.clk_i   (system_clock_i),
		.reset_i (system_reset_i),
		.async_i (response_matches_target),
		.sync_o  (response_held_system_o)
	);

	CaveBanprestoSoundRomCdcBitSync release_open_to_system (
		.clk_i   (system_clock_i),
		.reset_i (system_reset_i),
		.async_i (release_open_target),
		.sync_o  (release_open_system_o)
	);

	CaveBanprestoSoundRomCdcBitSync launch_block_target_to_system (
		.clk_i   (system_clock_i),
		.reset_i (system_reset_i),
		.async_i (launch_block_target),
		.sync_o  (launch_block_target_system_o)
	);

	CaveBanprestoSoundRomCdcBitSync target_fault_to_system (
		.clk_i   (system_clock_i),
		.reset_i (system_reset_i),
		.async_i (target_protocol_fault_q),
		.sync_o  (target_fault_system_sync)
	);

	// Target-side launch, response retirement, and dependency prefetch.
	always_ff @(posedge target_clock_i) begin
		if (target_reset_i) begin
			request_toggle_target_q <= 1'b0;
			request_addr_target_q <= 25'd0;
			pending_read_target_q <= 1'b0;
			request_armed_target_q <= 1'b1;
			response_toggle_target_seen_q <= 1'b0;
			response_data_target_q <= 8'd0;
			response_addr_target_q <= 25'd0;
			response_valid_target_q <= 1'b0;
			drain_retire_target_q <= 1'b0;
			prefetch_launched_target_q <= 1'b0;
			launch_block_target_d_q <= 1'b0;
			target_protocol_fault_q <= 1'b0;
		end else begin
			launch_block_target_d_q <= normal_launch_block_target;

			// A response event without a target-side outstanding request
			// indicates a reset mismatch or broken toggle protocol.
			if (new_response_target && !pending_read_target_q)
				target_protocol_fault_q <= 1'b1;

			if (!normal_launch_block_target) begin
				drain_retire_target_q <= 1'b0;
				prefetch_launched_target_q <= 1'b0;

				if (hold_response_i) begin
					if (response_valid_target_q &&
					    (!target_rd_i ||
					     (response_addr_target_q != target_addr_i)))
						response_valid_target_q <= 1'b0;

					if (target_rd_i &&
					    !pending_read_target_q &&
					    !response_matches_target) begin
						request_addr_target_q <= target_addr_i;
						request_toggle_target_q <=
							~request_toggle_target_q;
						pending_read_target_q <= 1'b1;
					end
				end else begin
					// Pulse-mode clients receive exactly one target
					// interval and cannot retrigger until rd falls or
					// the address changes.
					response_valid_target_q <= 1'b0;
					if (!target_rd_i ||
					    (target_addr_i != request_addr_target_q))
						request_armed_target_q <= 1'b1;

					if (target_rd_i &&
					    request_armed_target_q &&
					    !pending_read_target_q) begin
						request_addr_target_q <= target_addr_i;
						request_toggle_target_q <=
							~request_toggle_target_q;
						pending_read_target_q <= 1'b1;
						request_armed_target_q <= 1'b0;
					end
				end

				if (new_response_target) begin
					response_toggle_target_seen_q <=
						response_toggle_target_sync;
					response_data_target_q <=
						response_data_system_q;
					response_addr_target_q <=
						response_addr_system_q;
					// Keep a one-interval retirement marker even
					// when the reader changed address.  Normal-mode
					// valid remains address-filtered below, while a
					// gate arriving on this CDC edge can still return
					// the accepted response and unlock its arbiter.
					response_valid_target_q <= 1'b1;
					pending_read_target_q <= 1'b0;
				end
			end else begin
				// Normal wait/accept is closed throughout drain and
				// dependency preparation.  A response already held at
				// gate entry is presented for one final interval before
				// canonicalization.
				if (!launch_block_target_d_q &&
				    response_valid_target_q)
					drain_retire_target_q <= 1'b1;

				if (drain_retire_target_q) begin
					response_valid_target_q <= 1'b0;
					drain_retire_target_q <= 1'b0;
				end

				if (!prefetch_enable_target)
					prefetch_launched_target_q <= 1'b0;

				if (prefetch_enable_target &&
				    (ALLOW_PREFETCH == 0))
					target_protocol_fault_q <= 1'b1;

				// The prefetch is an internal dependency fetch: do not
				// raise wait_n and accidentally let the upstream arbiter
				// accept a new normal transaction while gated.
				if (prefetch_enable_target &&
				    (ALLOW_PREFETCH != 0) &&
				    !prefetch_launched_target_q &&
				    !pending_read_target_q &&
				    !response_valid_target_q &&
				    target_rd_i) begin
					request_addr_target_q <= target_addr_i;
					request_toggle_target_q <=
						~request_toggle_target_q;
					pending_read_target_q <= 1'b1;
					prefetch_launched_target_q <= 1'b1;
				end

				if (new_response_target) begin
					response_toggle_target_seen_q <=
						response_toggle_target_sync;
					response_data_target_q <=
						response_data_system_q;
					response_addr_target_q <=
						response_addr_system_q;
					pending_read_target_q <= 1'b0;

					if (prefetch_enable_target &&
					    prefetch_launched_target_q) begin
						// Hold reconstructed lane-0 data through
						// release.  Address mismatch cannot be
						// declared ready and is terminal.
						response_valid_target_q <= 1'b1;
						drain_retire_target_q <= 1'b0;
						if (!target_rd_i ||
						    (response_addr_system_q !=
						     target_addr_i))
							target_protocol_fault_q <=
								1'b1;
					end else begin
						// Accepted-before-gate traffic must still
						// return valid for a complete target edge
						// so CaveSoundRomReadArbiter unlocks.
						response_valid_target_q <= 1'b1;
						drain_retire_target_q <= 1'b1;
					end
				end
			end
		end
	end

	// System-side request issue, accepted-response drain, and downstream-idle
	// fence.  A timeout poisons the lane but does not cancel the transaction.
	always_ff @(posedge system_clock_i) begin
		if (system_reset_i) begin
			request_toggle_system_seen_q <= 1'b0;
			request_addr_system_q <= 25'd0;
			system_state_q <= StSystemIdle;
			fence_count_q <= {FENCE_COUNT_WIDTH{1'b0}};
			timeout_count_q <= {TIMEOUT_COUNT_WIDTH{1'b0}};
			response_data_system_q <= 8'd0;
			response_addr_system_q <= 25'd0;
			response_toggle_system_q <= 1'b0;
			terminal_fault_o <= 1'b0;
		end else begin
			if (target_fault_system_sync || transaction_timeout)
				terminal_fault_o <= 1'b1;

			if (system_state_q == StSystemIdle) begin
				timeout_count_q <=
					{TIMEOUT_COUNT_WIDTH{1'b0}};
			end else if (!transaction_timeout) begin
				timeout_count_q <= timeout_count_q + 1'b1;
			end

			unique case (system_state_q)
				StSystemIdle: begin
					fence_count_q <=
						{FENCE_COUNT_WIDTH{1'b0}};

					if (memory_valid_i)
						terminal_fault_o <= 1'b1;

					if (new_request_system) begin
						request_toggle_system_seen_q <=
							request_toggle_system_sync;
						request_addr_system_q <=
							request_addr_target_q;
						system_state_q <= StSystemIssue;
					end
				end

				StSystemIssue: begin
					if (memory_valid_i && !memory_wait_n_i)
						terminal_fault_o <= 1'b1;

					if (memory_wait_n_i) begin
						if (memory_valid_i) begin
							response_data_system_q <=
								memory_dout_i;
							response_addr_system_q <=
								request_addr_system_q;
							response_toggle_system_q <=
								~response_toggle_system_q;
							fence_count_q <=
								{FENCE_COUNT_WIDTH{1'b0}};
							system_state_q <=
								StSystemFence;
						end else begin
							system_state_q <=
								StSystemWait;
						end
					end
				end

				StSystemWait: begin
					if (memory_valid_i) begin
						response_data_system_q <= memory_dout_i;
						response_addr_system_q <=
							request_addr_system_q;
						response_toggle_system_q <=
							~response_toggle_system_q;
						fence_count_q <=
							{FENCE_COUNT_WIDTH{1'b0}};
						system_state_q <= StSystemFence;
					end
				end

				StSystemFence: begin
					if (memory_valid_i)
						terminal_fault_o <= 1'b1;

					if (!fence_quiet) begin
						fence_count_q <=
							{FENCE_COUNT_WIDTH{1'b0}};
					end else if ((FENCE_STABLE_CYCLES <= 1) ||
					             (fence_count_q ==
					              FENCE_COUNT_LIMIT)) begin
						fence_count_q <=
							{FENCE_COUNT_WIDTH{1'b0}};
						system_state_q <= StSystemIdle;
					end else begin
						fence_count_q <= fence_count_q + 1'b1;
					end
				end

				default: begin
					system_state_q <= StSystemIdle;
					terminal_fault_o <= 1'b1;
				end
			endcase
		end
	end

	assign target_dout_o = response_data_target_q;
	assign target_wait_n_o =
		normal_launch_block_target
			? 1'b0
			: !pending_read_target_q;
	assign target_valid_o =
		response_valid_target_q &&
		(normal_launch_block_target
			? (drain_retire_target_q ||
			   (prefetch_enable_target && response_matches_target))
			: (hold_response_i
				? response_matches_target
				: response_addr_target_q == target_addr_i));

	assign memory_rd_o = system_state_q == StSystemIssue;
	assign memory_addr_o = request_addr_system_q;
	assign system_idle_o =
		(system_state_q == StSystemIdle) &&
		!new_request_system &&
		memory_wait_n_i &&
		!memory_valid_i;

endmodule

module CaveBanprestoSoundRomTransportSaveState #(
	parameter [7:0] OWNER_INDEX = 8'd34,
	parameter integer IDLE_STABLE_CYCLES = 4,
	parameter integer GATE_SETTLE_CYCLES = 4,
	parameter integer FENCE_STABLE_CYCLES = 4,
	parameter integer TRANSACTION_TIMEOUT_CYCLES = 1_000_000,
	parameter integer DRAIN_TIMEOUT_CYCLES = 1_000_000,
	parameter integer PREFETCH_TIMEOUT_CYCLES = 1_000_000
) (
	input  wire         system_clock_i,
	input  wire         system_reset_i,
	input  wire         target_clock_i,
	input  wire         target_reset_i,

	input  wire         ss_launch_block_i,
	input  wire         ss_sound_cpu_stopped_i,
	input  wire         ss_prepare_release_i,
	input  wire         ss_prefetch_required_i,
	input  wire         ss_abort_i,

	input  wire   [2:0] hold_response_i,
	input  wire   [2:0] target_rd_i,
	input  wire  [74:0] target_addr_i,
	output wire  [23:0] target_dout_o,
	output wire   [2:0] target_wait_n_o,
	output wire   [2:0] target_valid_o,

	output wire   [2:0] memory_rd_o,
	output wire  [74:0] memory_addr_o,
	input  wire  [23:0] memory_dout_i,
	input  wire   [2:0] memory_wait_n_i,
	input  wire   [2:0] memory_valid_i,

	cavebanpresto_ssbus_if.responder ssbus,

	output wire         ss_canonical_idle_o,
	output wire         ss_external_idle_o,
	output wire         ss_restore_dependencies_ready_o,
	output wire         ss_release_path_ready_o,
	output wire         ss_rearmed_o,
	output logic        ss_terminal_fault_o,
	output wire   [2:0] ss_lane_system_idle_o,
	output wire   [2:0] ss_lane_target_empty_o
);

	localparam integer IDLE_COUNT_WIDTH =
		(IDLE_STABLE_CYCLES <= 1) ? 1 :
		$clog2(IDLE_STABLE_CYCLES);
	localparam integer GATE_COUNT_WIDTH =
		(GATE_SETTLE_CYCLES <= 1) ? 1 :
		$clog2(GATE_SETTLE_CYCLES);
	localparam integer DRAIN_COUNT_WIDTH =
		(DRAIN_TIMEOUT_CYCLES <= 1) ? 1 :
		$clog2(DRAIN_TIMEOUT_CYCLES);
	localparam integer PREFETCH_COUNT_WIDTH =
		(PREFETCH_TIMEOUT_CYCLES <= 1) ? 1 :
		$clog2(PREFETCH_TIMEOUT_CYCLES);

	localparam integer IDLE_COUNT_LIMIT =
		(IDLE_STABLE_CYCLES <= 1) ? 0 :
		IDLE_STABLE_CYCLES - 1;
	localparam integer GATE_COUNT_LIMIT =
		(GATE_SETTLE_CYCLES <= 1) ? 0 :
		GATE_SETTLE_CYCLES - 1;
	localparam integer DRAIN_COUNT_LIMIT =
		(DRAIN_TIMEOUT_CYCLES <= 1) ? 0 :
		DRAIN_TIMEOUT_CYCLES - 1;
	localparam integer PREFETCH_COUNT_LIMIT =
		(PREFETCH_TIMEOUT_CYCLES <= 1) ? 0 :
		PREFETCH_TIMEOUT_CYCLES - 1;

	logic [IDLE_COUNT_WIDTH-1:0] idle_count_q;
	logic [GATE_COUNT_WIDTH-1:0] gate_count_q;
	logic [DRAIN_COUNT_WIDTH-1:0] drain_timeout_count_q;
	logic [PREFETCH_COUNT_WIDTH-1:0] prefetch_timeout_count_q;
	logic prepare_q;
	logic prepare_prefetch_q;
	logic gate_seen_q;
	logic dependencies_ready_seen_q;
	logic prefetch_complete_q;
	logic release_arm_q;
	logic release_cleanup_q;
	// The shared owner bus holds a request through rsp_ack.  Re-arm only after
	// command_active falls so even this zero-word owner responds exactly once.
	logic owner_request_seen_q;

	wire [2:0] lane_system_idle;
	wire [2:0] lane_target_transport_idle;
	wire [2:0] lane_target_empty;
	wire lane0_prefetch_ready;
	wire lane0_response_held;
	wire lane0_release_open;
	wire [2:0] lane_launch_block_target;
	wire [2:0] lane_terminal_fault;

	wire memory_quiet =
		(&memory_wait_n_i) && !(|memory_valid_i);
	wire raw_canonical_idle =
		ss_launch_block_i &&
		!prepare_q &&
		(&lane_system_idle) &&
		(&lane_target_empty) &&
		memory_quiet;
	wire gate_settled =
		(GATE_SETTLE_CYCLES <= 1) ||
		(gate_count_q == GATE_COUNT_LIMIT);
	wire idle_settled =
		(IDLE_STABLE_CYCLES <= 1) ||
		(idle_count_q == IDLE_COUNT_LIMIT);
	wire raw_transport_idle =
		ss_launch_block_i &&
		(&lane_system_idle) &&
		(&lane_target_transport_idle) &&
		memory_quiet;
	wire prefetch_completion_now =
		prepare_q &&
		raw_transport_idle &&
		(!prepare_prefetch_q || lane0_prefetch_ready);
	wire release_path_ready =
		prepare_q &&
		prefetch_complete_q &&
		release_arm_q &&
		lane0_release_open &&
		(!prepare_prefetch_q || lane0_response_held) &&
		raw_transport_idle;
	wire all_target_launch_blocks_open =
		lane_launch_block_target == 3'b000;
	wire drain_timeout =
		(DRAIN_TIMEOUT_CYCLES != 0) &&
		ss_launch_block_i &&
		!prepare_q &&
		!ss_canonical_idle_o &&
		(drain_timeout_count_q == DRAIN_COUNT_LIMIT);
	wire prefetch_timeout =
		(PREFETCH_TIMEOUT_CYCLES != 0) &&
		prepare_q &&
		prepare_prefetch_q &&
		!ss_restore_dependencies_ready_o &&
		(prefetch_timeout_count_q == PREFETCH_COUNT_LIMIT);
	wire prepare_enable_lane0 =
		prepare_q &&
		prepare_prefetch_q &&
		!release_arm_q;

	CaveBanprestoSoundRomTransportLane #(
		.ALLOW_PREFETCH(1),
		.FENCE_STABLE_CYCLES(FENCE_STABLE_CYCLES),
		.TRANSACTION_TIMEOUT_CYCLES(TRANSACTION_TIMEOUT_CYCLES)
	) lane0 (
		.system_clock_i(system_clock_i),
		.system_reset_i(system_reset_i),
		.target_clock_i(target_clock_i),
		.target_reset_i(target_reset_i),
		.launch_block_system_i(ss_launch_block_i),
		.prefetch_enable_system_i(prepare_enable_lane0),
		.release_admit_system_i(release_arm_q),
		.hold_response_i(hold_response_i[0]),
		.target_rd_i(target_rd_i[0]),
		.target_addr_i(target_addr_i[24:0]),
		.target_dout_o(target_dout_o[7:0]),
		.target_wait_n_o(target_wait_n_o[0]),
		.target_valid_o(target_valid_o[0]),
		.memory_rd_o(memory_rd_o[0]),
		.memory_addr_o(memory_addr_o[24:0]),
		.memory_dout_i(memory_dout_i[7:0]),
		.memory_wait_n_i(memory_wait_n_i[0]),
		.memory_valid_i(memory_valid_i[0]),
		.system_idle_o(lane_system_idle[0]),
		.target_transport_idle_system_o(
			lane_target_transport_idle[0]
		),
		.target_canonical_empty_system_o(lane_target_empty[0]),
		.prefetch_ready_system_o(lane0_prefetch_ready),
		.response_held_system_o(lane0_response_held),
		.release_open_system_o(lane0_release_open),
		.launch_block_target_system_o(
			lane_launch_block_target[0]
		),
		.terminal_fault_o(lane_terminal_fault[0])
	);

	CaveBanprestoSoundRomTransportLane #(
		.ALLOW_PREFETCH(0),
		.FENCE_STABLE_CYCLES(FENCE_STABLE_CYCLES),
		.TRANSACTION_TIMEOUT_CYCLES(TRANSACTION_TIMEOUT_CYCLES)
	) lane1 (
		.system_clock_i(system_clock_i),
		.system_reset_i(system_reset_i),
		.target_clock_i(target_clock_i),
		.target_reset_i(target_reset_i),
		.launch_block_system_i(ss_launch_block_i),
		.prefetch_enable_system_i(1'b0),
		.release_admit_system_i(1'b0),
		.hold_response_i(hold_response_i[1]),
		.target_rd_i(target_rd_i[1]),
		.target_addr_i(target_addr_i[49:25]),
		.target_dout_o(target_dout_o[15:8]),
		.target_wait_n_o(target_wait_n_o[1]),
		.target_valid_o(target_valid_o[1]),
		.memory_rd_o(memory_rd_o[1]),
		.memory_addr_o(memory_addr_o[49:25]),
		.memory_dout_i(memory_dout_i[15:8]),
		.memory_wait_n_i(memory_wait_n_i[1]),
		.memory_valid_i(memory_valid_i[1]),
		.system_idle_o(lane_system_idle[1]),
		.target_transport_idle_system_o(
			lane_target_transport_idle[1]
		),
		.target_canonical_empty_system_o(lane_target_empty[1]),
		.prefetch_ready_system_o(),
		.response_held_system_o(),
		.release_open_system_o(),
		.launch_block_target_system_o(
			lane_launch_block_target[1]
		),
		.terminal_fault_o(lane_terminal_fault[1])
	);

	CaveBanprestoSoundRomTransportLane #(
		.ALLOW_PREFETCH(0),
		.FENCE_STABLE_CYCLES(FENCE_STABLE_CYCLES),
		.TRANSACTION_TIMEOUT_CYCLES(TRANSACTION_TIMEOUT_CYCLES)
	) lane2 (
		.system_clock_i(system_clock_i),
		.system_reset_i(system_reset_i),
		.target_clock_i(target_clock_i),
		.target_reset_i(target_reset_i),
		.launch_block_system_i(ss_launch_block_i),
		.prefetch_enable_system_i(1'b0),
		.release_admit_system_i(1'b0),
		.hold_response_i(hold_response_i[2]),
		.target_rd_i(target_rd_i[2]),
		.target_addr_i(target_addr_i[74:50]),
		.target_dout_o(target_dout_o[23:16]),
		.target_wait_n_o(target_wait_n_o[2]),
		.target_valid_o(target_valid_o[2]),
		.memory_rd_o(memory_rd_o[2]),
		.memory_addr_o(memory_addr_o[74:50]),
		.memory_dout_i(memory_dout_i[23:16]),
		.memory_wait_n_i(memory_wait_n_i[2]),
		.memory_valid_i(memory_valid_i[2]),
		.system_idle_o(lane_system_idle[2]),
		.target_transport_idle_system_o(
			lane_target_transport_idle[2]
		),
		.target_canonical_empty_system_o(lane_target_empty[2]),
		.prefetch_ready_system_o(),
		.response_held_system_o(),
		.release_open_system_o(),
		.launch_block_target_system_o(
			lane_launch_block_target[2]
		),
		.terminal_fault_o(lane_terminal_fault[2])
	);

	assign ss_canonical_idle_o =
		raw_canonical_idle &&
		gate_settled &&
		idle_settled &&
		!ss_terminal_fault_o;
	assign ss_external_idle_o =
		!ss_terminal_fault_o &&
		(!prepare_q
			? ss_canonical_idle_o
			: release_path_ready);
	assign ss_restore_dependencies_ready_o =
		release_path_ready &&
		!ss_terminal_fault_o;
	assign ss_release_path_ready_o =
		ss_restore_dependencies_ready_o;
	// New operation admission must wait beyond release-path readiness.  The
	// source gate has to cross low through every target lane and the retained
	// release bookkeeping must be completely cleared before a new gate rise
	// is legal.
	assign ss_rearmed_o =
		!ss_terminal_fault_o &&
		!ss_launch_block_i &&
		!gate_seen_q &&
		!prepare_q &&
		!release_arm_q &&
		!release_cleanup_q &&
		!dependencies_ready_seen_q &&
		all_target_launch_blocks_open;
	assign ss_lane_system_idle_o = lane_system_idle;
	assign ss_lane_target_empty_o = lane_target_empty;

	// Canonical qualification, dependency preparation, release legality, and
	// sticky terminal-fault aggregation.
	always_ff @(posedge system_clock_i) begin
		if (system_reset_i) begin
			idle_count_q <= {IDLE_COUNT_WIDTH{1'b0}};
			gate_count_q <= {GATE_COUNT_WIDTH{1'b0}};
			drain_timeout_count_q <=
				{DRAIN_COUNT_WIDTH{1'b0}};
			prefetch_timeout_count_q <=
				{PREFETCH_COUNT_WIDTH{1'b0}};
			prepare_q <= 1'b0;
			prepare_prefetch_q <= 1'b0;
			gate_seen_q <= 1'b0;
			dependencies_ready_seen_q <= 1'b0;
			prefetch_complete_q <= 1'b0;
			release_arm_q <= 1'b0;
			release_cleanup_q <= 1'b0;
			ss_terminal_fault_o <= 1'b0;
		end else begin
			if (|lane_terminal_fault)
				ss_terminal_fault_o <= 1'b1;

			// The dedicated gate is legal only after the CPU stop
			// acknowledgement.  Controls becoming true on the same
			// system edge are accepted.
			if (ss_launch_block_i &&
			    !ss_sound_cpu_stopped_i &&
			    !dependencies_ready_seen_q)
				ss_terminal_fault_o <= 1'b1;

			if (ss_launch_block_i) begin
				if (!gate_seen_q &&
				    (release_cleanup_q || release_arm_q))
					ss_terminal_fault_o <= 1'b1;
				gate_seen_q <= 1'b1;
				if (ss_restore_dependencies_ready_o)
					dependencies_ready_seen_q <= 1'b1;
			end else begin
				if (gate_seen_q) begin
					if (!dependencies_ready_seen_q)
						ss_terminal_fault_o <= 1'b1;
					release_cleanup_q <=
						dependencies_ready_seen_q;
					prepare_q <= 1'b0;
					prepare_prefetch_q <= 1'b0;
					prefetch_complete_q <= 1'b0;
				end
				gate_seen_q <= 1'b0;

				// Keep lane 0's release bypass asserted until the raw
				// launch gate has actually crossed low in every target
				// lane.  Clearing it earlier could re-block a released
				// slow Z80 for one target-clock interval.
				if (release_cleanup_q &&
				    all_target_launch_blocks_open) begin
					release_cleanup_q <= 1'b0;
					release_arm_q <= 1'b0;
					dependencies_ready_seen_q <= 1'b0;
				end
			end

			if (!ss_launch_block_i || prepare_q) begin
				idle_count_q <= {IDLE_COUNT_WIDTH{1'b0}};
				gate_count_q <= {GATE_COUNT_WIDTH{1'b0}};
			end else begin
				if ((GATE_SETTLE_CYCLES > 1) &&
				    (gate_count_q != GATE_COUNT_LIMIT))
					gate_count_q <= gate_count_q + 1'b1;

				if (!raw_canonical_idle) begin
					idle_count_q <=
						{IDLE_COUNT_WIDTH{1'b0}};
				end else if ((IDLE_STABLE_CYCLES > 1) &&
				             (idle_count_q != IDLE_COUNT_LIMIT)) begin
					idle_count_q <= idle_count_q + 1'b1;
				end
			end

			if (!ss_launch_block_i ||
			    prepare_q ||
			    ss_canonical_idle_o) begin
				drain_timeout_count_q <=
					{DRAIN_COUNT_WIDTH{1'b0}};
			end else if (!drain_timeout) begin
				drain_timeout_count_q <=
					drain_timeout_count_q + 1'b1;
			end

			if (!prepare_q ||
			    !prepare_prefetch_q ||
			    ss_restore_dependencies_ready_o) begin
				prefetch_timeout_count_q <=
					{PREFETCH_COUNT_WIDTH{1'b0}};
			end else if (!prefetch_timeout) begin
				prefetch_timeout_count_q <=
					prefetch_timeout_count_q + 1'b1;
			end

			if (drain_timeout || prefetch_timeout)
				ss_terminal_fault_o <= 1'b1;

			if (prefetch_completion_now) begin
				prefetch_complete_q <= 1'b1;
				release_arm_q <= 1'b1;
			end

			if (ss_prepare_release_i && !prepare_q) begin
				if (ss_canonical_idle_o &&
				    ss_launch_block_i &&
				    ss_sound_cpu_stopped_i &&
				    (!ss_prefetch_required_i ||
				     hold_response_i[0]) &&
				    !release_cleanup_q &&
				    !release_arm_q &&
				    !ss_terminal_fault_o) begin
					prepare_q <= 1'b1;
					prepare_prefetch_q <=
						ss_prefetch_required_i;
					prefetch_complete_q <=
						!ss_prefetch_required_i;
				end else begin
					ss_terminal_fault_o <= 1'b1;
				end
			end

			// Abort is intentionally not a cancellation input.  The Z80 may
			// clear ss_stopped_o after dependencies were proven while quiesce
			// still holds the launch gate until it samples the abort
			// acknowledgement; dependencies_ready_seen_q makes that bounded
			// acknowledgement window legal even when ss_abort_i was a pulse.
		end
	end

	// Owner 34 has a canonical zero-word representation.  Discovery is legal
	// only while the transport is proven empty and before dependency prefetch
	// reconstructs a held lane-0 response.  Any payload/restore operation is a
	// bounds error and cannot mutate transport state.
	always_ff @(posedge system_clock_i) begin
		if (system_reset_i) begin
			owner_request_seen_q <= 1'b0;
			ssbus.rsp_data <= 64'd0;
			ssbus.rsp_ack <= 1'b0;
			ssbus.rsp_error <= 1'b0;
		end else begin
			ssbus.rsp_data <= 64'd0;
			ssbus.rsp_ack <= 1'b0;
			ssbus.rsp_error <= 1'b0;

			if (!ssbus.command_active())
				owner_request_seen_q <= 1'b0;

			if (ssbus.request_for(OWNER_INDEX) &&
			    !owner_request_seen_q) begin
				owner_request_seen_q <= 1'b1;
				ssbus.rsp_ack <= 1'b1;

				if (ssbus.req_query &&
				    !ssbus.req_read &&
				    !ssbus.req_write &&
				    !ssbus.req_validate &&
				    (ssbus.req_addr == 32'd0) &&
				    (ssbus.req_data == 64'd0) &&
				    !ss_abort_i &&
				    ss_canonical_idle_o &&
				    !prepare_q &&
				    !ss_terminal_fault_o) begin
					ssbus.rsp_data <= ssbus.query_descriptor(
						OWNER_INDEX,
						32'd0,
						2'd3
					);
				end else begin
					ssbus.rsp_error <= 1'b1;
				end
			end
		end
	end

endmodule

`default_nettype wire
