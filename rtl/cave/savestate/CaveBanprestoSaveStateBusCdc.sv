`default_nettype none

// Async-assert, synchronous-release reset for one clock domain.
module CaveBanprestoSaveStateResetSync (
	input  wire clk_i,
	input  wire async_reset_i,
	output wire reset_o
);

	(* preserve, useioff = 0,
	   altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic [1:0] release_q = 2'b00;

	always_ff @(posedge clk_i or posedge async_reset_i) begin
		if (async_reset_i)
			release_q <= 2'b00;
		else
			release_q <= {release_q[0], 1'b1};
	end

	assign reset_o = ~release_q[1];

endmodule

// CaveBanpresto-local, destination-clocked two-flop level synchronizer.
module CaveBanprestoSaveStateCdcBitSync #(
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

// One-transaction CaveBanpresto owner-bus CDC bridge.
//
// The request and response payloads use a multi-cycle-path (MCP) crossing:
// each payload is captured in its source domain, held for the entire
// four-phase offer/confirm/response handshake, and sampled only after a
// synchronized level announces that it is stable.  Only registered protocol
// levels pass through two-flop synchronizers.
//
// Admission is deliberately two-stage.  The source first raises an offer
// level.  The destination captures the stable MCP payload and returns an offer
// echo, but does not assert an owner command.  After the source sees that echo
// it rechecks the held request, abort input, and current runtime support, then
// raises a confirm level.  Only a synchronized confirm can launch the owner
// command.  Thus a request abandoned before confirmation is discarded without
// a read or write reaching the owner.  Once confirmation is raised it is held
// until the destination returns a launch echo; cancellation after that point
// is irrevocable and takes the explicit drain path.
//
// Requests are filtered in the source domain before the request level rises.
// Both the compile-time union and the current runtime support bitmap must
// contain the selected owner.  A union-present/runtime-absent owner therefore
// completes locally with an error and cannot occupy the destination bridge.
//
// If the source abandons, explicitly aborts, or times out after confirmation,
// the destination keeps the already-launched command stable while draining its
// response.  A responder that never acknowledges cannot be proven safe to
// reuse: the bounded forced-drop path removes the command, enters a sticky
// reset-only terminal-fault state, and never advertises availability again.
// Accepted-operation owners must poison and drain their internal work after
// request withdrawal.  dst_terminal_fault_i imports the same reset-only
// contract from a downstream mux or owner.
module CaveBanprestoSaveStateBusCdc #(
	parameter integer OWNER_COUNT = 48,
	parameter integer SUPPORT_WIDTH = 48,
	parameter [SUPPORT_WIDTH-1:0] COMPILED_SUPPORT_BITMAP =
		{SUPPORT_WIDTH{1'b1}},
	parameter integer SOURCE_TIMEOUT_CYCLES = 4096,
	parameter integer DESTINATION_ABORT_TIMEOUT_CYCLES = 2048,
	parameter integer DRAIN_QUIET_CYCLES = 8,
	parameter integer RESET_GUARD_CYCLES = 4
) (
	input  wire src_clk_i,
	input  wire src_async_reset_i,
	input  wire [SUPPORT_WIDTH-1:0] runtime_support_i,
	input  wire src_abort_i,
	cavebanpresto_ssbus_if.responder src_bus,

	output logic src_ready_o,
	output logic src_busy_o,
	output logic src_draining_o,
	output logic src_timeout_o,
	output logic src_abandoned_o,
	output logic src_aborted_o,
	output logic src_local_reject_o,
	output logic src_destination_reset_o,
	output logic src_terminal_fault_o,

	input  wire dst_clk_i,
	input  wire dst_async_reset_i,
	input  wire dst_terminal_fault_i,
	cavebanpresto_ssbus_if.requester dst_bus,

	output logic dst_busy_o,
	output logic dst_draining_o,
	output logic dst_forced_drop_o,
	output logic dst_late_response_o,
	output logic dst_terminal_fault_o
);

	localparam integer SOURCE_TIMEOUT_WIDTH =
		(SOURCE_TIMEOUT_CYCLES <= 1) ? 1 :
		$clog2(SOURCE_TIMEOUT_CYCLES);
	localparam integer DESTINATION_ABORT_TIMEOUT_WIDTH =
		(DESTINATION_ABORT_TIMEOUT_CYCLES <= 1) ? 1 :
		$clog2(DESTINATION_ABORT_TIMEOUT_CYCLES);
	localparam integer DRAIN_QUIET_LIMIT =
		(DRAIN_QUIET_CYCLES < 2) ? 2 : DRAIN_QUIET_CYCLES;
	localparam integer DRAIN_QUIET_WIDTH =
		(DRAIN_QUIET_LIMIT <= 1) ? 1 : $clog2(DRAIN_QUIET_LIMIT);
	localparam integer RESET_GUARD_LIMIT =
		(RESET_GUARD_CYCLES < 3) ? 3 : RESET_GUARD_CYCLES;
	localparam integer RESET_GUARD_WIDTH =
		(RESET_GUARD_LIMIT <= 1) ? 1 : $clog2(RESET_GUARD_LIMIT);

	typedef enum logic [3:0] {
		StSrcBootLow          = 4'd0,
		StSrcBootHigh         = 4'd1,
		StSrcIdle             = 4'd2,
		StSrcWaitOfferEcho    = 4'd3,
		StSrcWaitLaunchEcho   = 4'd4,
		StSrcWaitResponse     = 4'd5,
		StSrcCancelOffer      = 4'd6,
		StSrcCancelConfirmed  = 4'd7,
		StSrcWaitDrain        = 4'd8,
		StSrcWaitRelease      = 4'd9,
		StSrcTerminalFault    = 4'd10,
		StSrcDrainReleased    = 4'd11
	} src_state_e;

	typedef enum logic [3:0] {
		StDstBoot          = 4'd0,
		StDstWaitSource    = 4'd1,
		StDstIdle          = 4'd2,
		StDstWaitConfirm   = 4'd3,
		StDstWaitResponse  = 4'd4,
		StDstWaitReqLow    = 4'd5,
		StDstAbortDrain    = 4'd6,
		StDstQuietDrain    = 4'd7,
		StDstTerminalFault = 4'd8
	} dst_state_e;

	wire src_reset;
	wire dst_reset;

	CaveBanprestoSaveStateResetSync src_reset_sync (
		.clk_i(src_clk_i),
		.async_reset_i(src_async_reset_i),
		.reset_o(src_reset)
	);

	CaveBanprestoSaveStateResetSync dst_reset_sync (
		.clk_i(dst_clk_i),
		.async_reset_i(dst_async_reset_i),
		.reset_o(dst_reset)
	);

	src_state_e src_state_q;
	dst_state_e dst_state_q;

	// Source-domain request MCP payload.  These registers are not modified
	// again until the destination has drained and advertised availability.
	logic [63:0] src_req_data_hold_q = 64'd0;
	logic [31:0] src_req_addr_hold_q = 32'd0;
	logic  [7:0] src_req_select_hold_q = 8'd0;
	logic        src_req_read_hold_q = 1'b0;
	logic        src_req_write_hold_q = 1'b0;
	logic        src_req_validate_hold_q = 1'b0;
	logic        src_req_query_hold_q = 1'b0;
	logic        src_request_level_q;
	logic        src_confirm_level_q;
	logic        src_online_q;

	// Destination-domain response MCP payload.  These registers remain stable
	// while dst_response_level_q is asserted.
	logic [63:0] dst_rsp_data_hold_q;
	logic        dst_rsp_error_hold_q;
	logic        dst_response_level_q;

	// Destination latches its own registered copy before driving the local bus.
	logic [63:0] dst_req_data_hold_q;
	logic [31:0] dst_req_addr_hold_q;
	logic  [7:0] dst_req_select_hold_q;
	logic        dst_req_read_hold_q;
	logic        dst_req_write_hold_q;
	logic        dst_req_validate_hold_q;
	logic        dst_req_query_hold_q;

	logic dst_online_q;
	logic dst_available_q;
	logic dst_source_online_ack_q;
	logic dst_request_echo_q;
	logic dst_launch_echo_q;

	wire dst_request_level_sync;
	wire dst_confirm_level_sync;
	wire dst_source_online_sync;
	wire src_response_level_sync;
	wire src_destination_online_sync;
	wire src_destination_available_sync;
	wire src_online_ack_sync;
	wire src_request_echo_sync;
	wire src_launch_echo_sync;
	wire src_terminal_fault_sync;

	CaveBanprestoSaveStateCdcBitSync req_to_dst_sync (
		.clk_i(dst_clk_i),
		.reset_i(dst_reset),
		.async_i(src_request_level_q),
		.sync_o(dst_request_level_sync)
	);

	CaveBanprestoSaveStateCdcBitSync source_online_to_dst_sync (
		.clk_i(dst_clk_i),
		.reset_i(dst_reset),
		.async_i(src_online_q),
		.sync_o(dst_source_online_sync)
	);

	CaveBanprestoSaveStateCdcBitSync confirm_to_dst_sync (
		.clk_i(dst_clk_i),
		.reset_i(dst_reset),
		.async_i(src_confirm_level_q),
		.sync_o(dst_confirm_level_sync)
	);

	CaveBanprestoSaveStateCdcBitSync rsp_to_src_sync (
		.clk_i(src_clk_i),
		.reset_i(src_reset),
		.async_i(dst_response_level_q),
		.sync_o(src_response_level_sync)
	);

	CaveBanprestoSaveStateCdcBitSync online_to_src_sync (
		.clk_i(src_clk_i),
		.reset_i(src_reset),
		.async_i(dst_online_q),
		.sync_o(src_destination_online_sync)
	);

	CaveBanprestoSaveStateCdcBitSync available_to_src_sync (
		.clk_i(src_clk_i),
		.reset_i(src_reset),
		.async_i(dst_available_q),
		.sync_o(src_destination_available_sync)
	);

	CaveBanprestoSaveStateCdcBitSync source_online_ack_to_src_sync (
		.clk_i(src_clk_i),
		.reset_i(src_reset),
		.async_i(dst_source_online_ack_q),
		.sync_o(src_online_ack_sync)
	);

	CaveBanprestoSaveStateCdcBitSync request_echo_to_src_sync (
		.clk_i(src_clk_i),
		.reset_i(src_reset),
		.async_i(dst_request_echo_q),
		.sync_o(src_request_echo_sync)
	);

	CaveBanprestoSaveStateCdcBitSync launch_echo_to_src_sync (
		.clk_i(src_clk_i),
		.reset_i(src_reset),
		.async_i(dst_launch_echo_q),
		.sync_o(src_launch_echo_sync)
	);

	CaveBanprestoSaveStateCdcBitSync terminal_fault_to_src_sync (
		.clk_i(src_clk_i),
		.reset_i(src_reset),
		.async_i(dst_terminal_fault_o),
		.sync_o(src_terminal_fault_sync)
	);

	logic [SOURCE_TIMEOUT_WIDTH-1:0] src_timeout_count_q;
	logic [DESTINATION_ABORT_TIMEOUT_WIDTH-1:0]
		dst_abort_timeout_count_q;
	logic [DRAIN_QUIET_WIDTH-1:0] dst_quiet_count_q;
	logic [RESET_GUARD_WIDTH-1:0] dst_reset_guard_count_q;

	logic [3:0] src_command;
	logic       src_command_active;
	logic       src_command_legal;
	logic       src_selected_in_range;
	logic       src_selected_compiled;
	logic       src_selected_runtime;
	logic       src_selected_supported;
	logic       src_request_matches;
	logic [3:0] dst_held_command;
	logic       dst_held_command_legal;
	logic       dst_command_active;
	logic       dst_response_active;

	assign src_command = {
		src_bus.req_query,
		src_bus.req_validate,
		src_bus.req_write,
		src_bus.req_read
	};
	assign src_command_active = |src_command;
	assign src_command_legal =
		(src_command == 4'b0001) |
		(src_command == 4'b0010) |
		(src_command == 4'b0100) |
		(src_command == 4'b1000);

	assign src_selected_in_range =
		(src_bus.req_select < SUPPORT_WIDTH) &&
		(src_bus.req_select < OWNER_COUNT);
	always_comb begin
		src_selected_compiled = 1'b0;
		src_selected_runtime = 1'b0;
		if (src_selected_in_range) begin
			src_selected_compiled =
				COMPILED_SUPPORT_BITMAP[src_bus.req_select];
			src_selected_runtime =
				runtime_support_i[src_bus.req_select];
		end
	end
	assign src_selected_supported =
		src_selected_in_range &
		src_selected_compiled &
		src_selected_runtime;

	assign src_request_matches =
		src_command_active &
		(src_bus.req_data == src_req_data_hold_q) &
		(src_bus.req_addr == src_req_addr_hold_q) &
		(src_bus.req_select == src_req_select_hold_q) &
		(src_bus.req_read == src_req_read_hold_q) &
		(src_bus.req_write == src_req_write_hold_q) &
		(src_bus.req_validate == src_req_validate_hold_q) &
		(src_bus.req_query == src_req_query_hold_q);

	assign dst_held_command = {
		dst_req_query_hold_q,
		dst_req_validate_hold_q,
		dst_req_write_hold_q,
		dst_req_read_hold_q
	};
	assign dst_held_command_legal =
		(dst_held_command == 4'b0001) |
		(dst_held_command == 4'b0010) |
		(dst_held_command == 4'b0100) |
		(dst_held_command == 4'b1000);

	assign dst_command_active =
		(dst_state_q == StDstWaitResponse) |
		(dst_state_q == StDstAbortDrain);
	assign dst_response_active = dst_bus.rsp_ack | dst_bus.rsp_error;

	assign dst_bus.req_data = dst_req_data_hold_q;
	assign dst_bus.req_addr = dst_req_addr_hold_q;
	assign dst_bus.req_select = dst_req_select_hold_q;
	assign dst_bus.req_read =
		dst_command_active & dst_req_read_hold_q;
	assign dst_bus.req_write =
		dst_command_active & dst_req_write_hold_q;
	assign dst_bus.req_validate =
		dst_command_active & dst_req_validate_hold_q;
	assign dst_bus.req_query =
		dst_command_active & dst_req_query_hold_q;

	always_comb begin
		src_ready_o =
			(src_state_q == StSrcIdle) &
			src_online_q &
			src_online_ack_sync &
			src_destination_online_sync &
			src_destination_available_sync &
			~src_request_echo_sync &
			~src_launch_echo_sync &
			~src_response_level_sync &
			~src_terminal_fault_sync &
			~src_terminal_fault_o &
			~src_abort_i;
		src_busy_o = src_state_q != StSrcIdle;
		src_draining_o =
			(src_state_q == StSrcCancelOffer) |
			(src_state_q == StSrcCancelConfirmed) |
			(src_state_q == StSrcWaitDrain) |
			(src_state_q == StSrcDrainReleased) |
			(src_state_q == StSrcTerminalFault);
		dst_busy_o =
			(dst_state_q != StDstIdle) &
			(dst_state_q != StDstBoot);
		dst_draining_o =
			(dst_state_q == StDstAbortDrain) |
			(dst_state_q == StDstQuietDrain) |
			(dst_state_q == StDstTerminalFault);
	end

	always_ff @(posedge src_clk_i) begin
		if (src_reset) begin
			src_state_q <= StSrcBootLow;
			src_request_level_q <= 1'b0;
			src_confirm_level_q <= 1'b0;
			src_online_q <= 1'b0;
			src_timeout_count_q <= {SOURCE_TIMEOUT_WIDTH{1'b0}};
			src_bus.rsp_data <= 64'd0;
			src_bus.rsp_ack <= 1'b0;
			src_bus.rsp_error <= 1'b0;
			src_timeout_o <= 1'b0;
			src_abandoned_o <= 1'b0;
			src_aborted_o <= 1'b0;
			src_local_reject_o <= 1'b0;
			src_destination_reset_o <= 1'b0;
			src_terminal_fault_o <= 1'b0;
		end else begin
			src_bus.rsp_data <= 64'd0;
			src_bus.rsp_ack <= 1'b0;
			src_bus.rsp_error <= 1'b0;
			src_timeout_o <= 1'b0;
			src_abandoned_o <= 1'b0;
			src_aborted_o <= 1'b0;
			src_local_reject_o <= 1'b0;
			src_destination_reset_o <= 1'b0;

			if (src_terminal_fault_sync) begin
				src_request_level_q <= 1'b0;
				src_confirm_level_q <= 1'b0;
				src_online_q <= 1'b0;
				src_terminal_fault_o <= 1'b1;
				src_state_q <= StSrcTerminalFault;

				// Only states that can still owe the current requester a
				// response may emit the one terminal-fault completion.
				// Cancel/drain/release states have already completed or
				// were abandoned and must not produce a duplicate ack.
				if (!src_terminal_fault_o &&
				    (((src_state_q == StSrcIdle) &&
				      src_command_active) ||
				     (((src_state_q == StSrcWaitOfferEcho) ||
				       (src_state_q == StSrcWaitLaunchEcho) ||
				       (src_state_q == StSrcWaitResponse)) &&
				      src_request_matches))) begin
					src_bus.rsp_ack <= 1'b1;
					src_bus.rsp_error <= 1'b1;
				end
			end else begin
			unique case (src_state_q)
				StSrcBootLow: begin
					src_request_level_q <= 1'b0;
					src_confirm_level_q <= 1'b0;
					src_online_q <= 1'b0;
					src_timeout_count_q <=
						{SOURCE_TIMEOUT_WIDTH{1'b0}};
					if (~src_command_active &
					    src_destination_online_sync &
					    ~src_online_ack_sync &
					    ~src_request_echo_sync &
					    ~src_launch_echo_sync &
					    ~src_response_level_sync) begin
						src_online_q <= 1'b1;
						src_state_q <= StSrcBootHigh;
					end
				end

				StSrcBootHigh: begin
					src_request_level_q <= 1'b0;
					src_confirm_level_q <= 1'b0;
					src_online_q <= 1'b1;
					if (~src_destination_online_sync) begin
						src_online_q <= 1'b0;
						src_state_q <= StSrcBootLow;
					end else if (~src_command_active &
					             src_online_ack_sync &
					             src_destination_available_sync &
					             ~src_request_echo_sync &
					             ~src_launch_echo_sync &
					             ~src_response_level_sync) begin
						src_state_q <= StSrcIdle;
					end
				end

				StSrcIdle: begin
					src_request_level_q <= 1'b0;
					src_confirm_level_q <= 1'b0;
					src_online_q <= 1'b1;
					src_timeout_count_q <=
						{SOURCE_TIMEOUT_WIDTH{1'b0}};
					if (~src_destination_online_sync |
					    ~src_online_ack_sync) begin
						src_online_q <= 1'b0;
						src_destination_reset_o <= 1'b1;
						if (src_command_active) begin
							src_bus.rsp_ack <= 1'b1;
							src_bus.rsp_error <= 1'b1;
							src_state_q <= StSrcWaitRelease;
						end else begin
							src_state_q <= StSrcBootLow;
						end
					end else if (src_command_active) begin
						if (src_abort_i |
						    ~src_command_legal |
						    ~src_selected_supported |
						    ~src_destination_available_sync |
						    src_request_echo_sync |
						    src_launch_echo_sync |
						    src_response_level_sync) begin
							src_bus.rsp_ack <= 1'b1;
							src_bus.rsp_error <= 1'b1;
							src_local_reject_o <= 1'b1;
							if (src_abort_i)
								src_aborted_o <= 1'b1;
							src_state_q <= StSrcWaitRelease;
						end else begin
							src_req_data_hold_q <=
								src_bus.req_data;
							src_req_addr_hold_q <=
								src_bus.req_addr;
							src_req_select_hold_q <=
								src_bus.req_select;
							src_req_read_hold_q <=
								src_bus.req_read;
							src_req_write_hold_q <=
								src_bus.req_write;
							src_req_validate_hold_q <=
								src_bus.req_validate;
							src_req_query_hold_q <=
								src_bus.req_query;
							src_request_level_q <= 1'b1;
							src_confirm_level_q <= 1'b0;
							src_state_q <=
								StSrcWaitOfferEcho;
						end
					end
				end

				StSrcWaitOfferEcho: begin
					src_online_q <= 1'b1;
					src_confirm_level_q <= 1'b0;
					if (~src_destination_online_sync |
					    ~src_online_ack_sync) begin
						src_request_level_q <= 1'b0;
						src_confirm_level_q <= 1'b0;
						src_online_q <= 1'b0;
						src_destination_reset_o <= 1'b1;
						if (src_request_matches) begin
							src_bus.rsp_ack <= 1'b1;
							src_bus.rsp_error <= 1'b1;
						end
						src_state_q <= StSrcWaitRelease;
					end else if (src_abort_i) begin
						src_aborted_o <= 1'b1;
						if (src_request_matches) begin
							src_bus.rsp_ack <= 1'b1;
							src_bus.rsp_error <= 1'b1;
						end
						if (src_request_echo_sync) begin
							src_request_level_q <= 1'b0;
							src_state_q <= StSrcWaitDrain;
						end else begin
							src_state_q <= StSrcCancelOffer;
						end
					end else if (~src_request_matches) begin
						src_abandoned_o <= 1'b1;
						if (src_request_echo_sync) begin
							src_request_level_q <= 1'b0;
							src_state_q <= StSrcWaitDrain;
						end else begin
							src_state_q <= StSrcCancelOffer;
						end
					end else if (~src_command_legal |
					             ~src_selected_supported) begin
						src_bus.rsp_ack <= 1'b1;
						src_bus.rsp_error <= 1'b1;
						src_local_reject_o <= 1'b1;
						if (src_request_echo_sync) begin
							src_request_level_q <= 1'b0;
							src_state_q <= StSrcWaitDrain;
						end else begin
							src_state_q <= StSrcCancelOffer;
						end
					end else if (SOURCE_TIMEOUT_CYCLES <= 1) begin
						src_timeout_o <= 1'b1;
						src_bus.rsp_ack <= 1'b1;
						src_bus.rsp_error <= 1'b1;
						if (src_request_echo_sync) begin
							src_request_level_q <= 1'b0;
							src_state_q <= StSrcWaitDrain;
						end else begin
							src_state_q <= StSrcCancelOffer;
						end
					end else if (src_timeout_count_q ==
					             SOURCE_TIMEOUT_CYCLES - 1) begin
						src_timeout_o <= 1'b1;
						src_bus.rsp_ack <= 1'b1;
						src_bus.rsp_error <= 1'b1;
						if (src_request_echo_sync) begin
							src_request_level_q <= 1'b0;
							src_state_q <= StSrcWaitDrain;
						end else begin
							src_state_q <= StSrcCancelOffer;
						end
					end else if (src_request_echo_sync) begin
						src_confirm_level_q <= 1'b1;
						src_state_q <= StSrcWaitLaunchEcho;
					end else begin
						src_timeout_count_q <=
							src_timeout_count_q + 1'b1;
					end
				end

				StSrcWaitLaunchEcho: begin
					src_online_q <= 1'b1;
					src_confirm_level_q <= 1'b1;
					if (~src_destination_online_sync |
					    ~src_online_ack_sync) begin
						src_request_level_q <= 1'b0;
						src_confirm_level_q <= 1'b0;
						src_online_q <= 1'b0;
						src_destination_reset_o <= 1'b1;
						if (src_request_matches) begin
							src_bus.rsp_ack <= 1'b1;
							src_bus.rsp_error <= 1'b1;
						end
						src_state_q <= StSrcWaitRelease;
					end else if (src_abort_i) begin
						src_aborted_o <= 1'b1;
						if (src_request_matches) begin
							src_bus.rsp_ack <= 1'b1;
							src_bus.rsp_error <= 1'b1;
						end
						if (src_launch_echo_sync) begin
							src_request_level_q <= 1'b0;
							src_confirm_level_q <= 1'b0;
							src_state_q <= StSrcWaitDrain;
						end else begin
							src_state_q <=
								StSrcCancelConfirmed;
						end
					end else if (~src_request_matches) begin
						src_abandoned_o <= 1'b1;
						if (src_launch_echo_sync) begin
							src_request_level_q <= 1'b0;
							src_confirm_level_q <= 1'b0;
							src_state_q <= StSrcWaitDrain;
						end else begin
							src_state_q <=
								StSrcCancelConfirmed;
						end
					end else if (src_launch_echo_sync) begin
						src_state_q <= StSrcWaitResponse;
					end else if (SOURCE_TIMEOUT_CYCLES <= 1) begin
						src_timeout_o <= 1'b1;
						src_bus.rsp_ack <= 1'b1;
						src_bus.rsp_error <= 1'b1;
						src_state_q <= StSrcCancelConfirmed;
					end else if (src_timeout_count_q ==
					             SOURCE_TIMEOUT_CYCLES - 1) begin
						src_timeout_o <= 1'b1;
						src_bus.rsp_ack <= 1'b1;
						src_bus.rsp_error <= 1'b1;
						src_state_q <= StSrcCancelConfirmed;
					end else begin
						src_timeout_count_q <=
							src_timeout_count_q + 1'b1;
					end
				end

				StSrcWaitResponse: begin
					src_online_q <= 1'b1;
					src_confirm_level_q <= 1'b1;
					if (~src_destination_online_sync |
					    ~src_online_ack_sync) begin
						src_request_level_q <= 1'b0;
						src_confirm_level_q <= 1'b0;
						src_online_q <= 1'b0;
						src_destination_reset_o <= 1'b1;
						if (src_request_matches) begin
							src_bus.rsp_ack <= 1'b1;
							src_bus.rsp_error <= 1'b1;
						end
						src_state_q <= StSrcWaitRelease;
					end else if (src_abort_i) begin
						src_aborted_o <= 1'b1;
						if (src_request_matches) begin
							src_bus.rsp_ack <= 1'b1;
							src_bus.rsp_error <= 1'b1;
						end
						src_request_level_q <= 1'b0;
						src_confirm_level_q <= 1'b0;
						src_state_q <= StSrcWaitDrain;
					end else if (~src_request_matches) begin
						src_abandoned_o <= 1'b1;
						src_request_level_q <= 1'b0;
						src_confirm_level_q <= 1'b0;
						src_state_q <= StSrcWaitDrain;
					end else if (src_response_level_sync) begin
						src_bus.rsp_data <= dst_rsp_data_hold_q;
						src_bus.rsp_ack <= 1'b1;
						src_bus.rsp_error <=
							dst_rsp_error_hold_q;
						src_request_level_q <= 1'b0;
						src_confirm_level_q <= 1'b0;
						src_state_q <= StSrcWaitDrain;
					end else if (SOURCE_TIMEOUT_CYCLES <= 1) begin
						src_timeout_o <= 1'b1;
						src_bus.rsp_ack <= 1'b1;
						src_bus.rsp_error <= 1'b1;
						src_request_level_q <= 1'b0;
						src_confirm_level_q <= 1'b0;
						src_state_q <= StSrcWaitDrain;
					end else if (src_timeout_count_q ==
					             SOURCE_TIMEOUT_CYCLES - 1) begin
						src_timeout_o <= 1'b1;
						src_bus.rsp_ack <= 1'b1;
						src_bus.rsp_error <= 1'b1;
						src_request_level_q <= 1'b0;
						src_confirm_level_q <= 1'b0;
						src_state_q <= StSrcWaitDrain;
					end else begin
						src_timeout_count_q <=
							src_timeout_count_q + 1'b1;
					end
				end

				StSrcCancelOffer: begin
					src_online_q <= 1'b1;
					src_confirm_level_q <= 1'b0;
					if (~src_destination_online_sync |
					    ~src_online_ack_sync) begin
						src_request_level_q <= 1'b0;
						src_confirm_level_q <= 1'b0;
						src_online_q <= 1'b0;
						src_destination_reset_o <= 1'b1;
						if (src_command_active)
							src_state_q <= StSrcWaitRelease;
						else
							src_state_q <= StSrcBootLow;
					end else if (src_request_echo_sync) begin
						src_request_level_q <= 1'b0;
						src_state_q <= StSrcWaitDrain;
					end
				end

				StSrcCancelConfirmed: begin
					src_online_q <= 1'b1;
					src_confirm_level_q <= 1'b1;
					if (~src_destination_online_sync |
					    ~src_online_ack_sync) begin
						src_request_level_q <= 1'b0;
						src_confirm_level_q <= 1'b0;
						src_online_q <= 1'b0;
						src_destination_reset_o <= 1'b1;
						if (src_command_active)
							src_state_q <= StSrcWaitRelease;
						else
							src_state_q <= StSrcBootLow;
					end else if (src_launch_echo_sync) begin
						src_request_level_q <= 1'b0;
						src_confirm_level_q <= 1'b0;
						src_state_q <= StSrcWaitDrain;
					end
				end

				StSrcWaitDrain: begin
					src_request_level_q <= 1'b0;
					src_confirm_level_q <= 1'b0;
					src_online_q <= 1'b1;
					if (~src_destination_online_sync |
					    ~src_online_ack_sync) begin
						src_online_q <= 1'b0;
						src_destination_reset_o <= 1'b1;
						if (src_command_active)
							src_state_q <= StSrcWaitRelease;
						else
							src_state_q <= StSrcBootLow;
					end else if (~src_command_active) begin
						if (src_destination_available_sync &
						    ~src_request_echo_sync &
						    ~src_launch_echo_sync &
						    ~src_response_level_sync)
							src_state_q <= StSrcIdle;
						else
							src_state_q <= StSrcDrainReleased;
					end
				end

				// This state is the remembered requester-low phase.  It prevents
				// a completed request from being recaptured, while allowing the
				// next request to remain asserted until the destination drain ends.
				StSrcDrainReleased: begin
					src_request_level_q <= 1'b0;
					src_confirm_level_q <= 1'b0;
					src_online_q <= 1'b1;
					if (~src_destination_online_sync |
					    ~src_online_ack_sync) begin
						src_online_q <= 1'b0;
						src_destination_reset_o <= 1'b1;
						if (src_command_active)
							src_state_q <= StSrcWaitRelease;
						else
							src_state_q <= StSrcBootLow;
					end else if (src_destination_available_sync &
					             ~src_request_echo_sync &
					             ~src_launch_echo_sync &
					             ~src_response_level_sync) begin
						src_state_q <= StSrcIdle;
					end
				end

				StSrcWaitRelease: begin
					src_request_level_q <= 1'b0;
					src_confirm_level_q <= 1'b0;
					if (~src_destination_online_sync |
					    ~src_online_ack_sync)
						src_online_q <= 1'b0;
					if (~src_command_active) begin
						if (src_online_q &
						    src_destination_online_sync &
						    src_online_ack_sync &
						    src_destination_available_sync &
						    ~src_request_echo_sync &
						    ~src_launch_echo_sync &
						    ~src_response_level_sync)
							src_state_q <= StSrcIdle;
						else begin
							src_online_q <= 1'b0;
							src_state_q <= StSrcBootLow;
						end
					end
				end

				StSrcTerminalFault: begin
					src_request_level_q <= 1'b0;
					src_confirm_level_q <= 1'b0;
					src_online_q <= 1'b0;
					src_terminal_fault_o <= 1'b1;
					src_state_q <= StSrcTerminalFault;
				end

				default: begin
					src_request_level_q <= 1'b0;
					src_confirm_level_q <= 1'b0;
					src_online_q <= 1'b0;
					src_terminal_fault_o <= 1'b1;
					src_state_q <= StSrcTerminalFault;
				end
			endcase
			end
		end
	end

	always_ff @(posedge dst_clk_i) begin
		if (dst_reset) begin
			dst_state_q <= StDstBoot;
			dst_req_data_hold_q <= 64'd0;
			dst_req_addr_hold_q <= 32'd0;
			dst_req_select_hold_q <= 8'd0;
			dst_req_read_hold_q <= 1'b0;
			dst_req_write_hold_q <= 1'b0;
			dst_req_validate_hold_q <= 1'b0;
			dst_req_query_hold_q <= 1'b0;
			dst_rsp_data_hold_q <= 64'd0;
			dst_rsp_error_hold_q <= 1'b0;
			dst_response_level_q <= 1'b0;
			dst_online_q <= 1'b0;
			dst_available_q <= 1'b0;
			dst_source_online_ack_q <= 1'b0;
			dst_request_echo_q <= 1'b0;
			dst_launch_echo_q <= 1'b0;
			dst_abort_timeout_count_q <=
				{DESTINATION_ABORT_TIMEOUT_WIDTH{1'b0}};
			dst_quiet_count_q <= {DRAIN_QUIET_WIDTH{1'b0}};
			dst_reset_guard_count_q <=
				{RESET_GUARD_WIDTH{1'b0}};
			dst_forced_drop_o <= 1'b0;
			dst_late_response_o <= 1'b0;
			dst_terminal_fault_o <= 1'b0;
		end else begin
			dst_forced_drop_o <= 1'b0;
			dst_late_response_o <= 1'b0;

			// A downstream sticky fault has priority over an ordinary
			// acknowledgement in the same destination cycle.
			if (dst_terminal_fault_i) begin
				dst_online_q <= 1'b1;
				dst_available_q <= 1'b0;
				dst_source_online_ack_q <= 1'b1;
				dst_response_level_q <= 1'b0;
				dst_request_echo_q <= 1'b0;
				dst_launch_echo_q <= 1'b0;
				dst_terminal_fault_o <= 1'b1;
				if (dst_response_active)
					dst_late_response_o <= 1'b1;
				dst_state_q <= StDstTerminalFault;
			end else begin
			unique case (dst_state_q)
				StDstBoot: begin
					dst_online_q <= 1'b0;
					dst_available_q <= 1'b0;
					dst_source_online_ack_q <= 1'b0;
					dst_response_level_q <= 1'b0;
					dst_request_echo_q <= 1'b0;
					dst_launch_echo_q <= 1'b0;
					dst_abort_timeout_count_q <=
						{DESTINATION_ABORT_TIMEOUT_WIDTH{1'b0}};
					dst_quiet_count_q <=
						{DRAIN_QUIET_WIDTH{1'b0}};
					if (dst_request_level_sync |
					    dst_confirm_level_sync |
					    dst_response_active) begin
						dst_reset_guard_count_q <=
							{RESET_GUARD_WIDTH{1'b0}};
					end else if (dst_reset_guard_count_q ==
					             RESET_GUARD_LIMIT - 1) begin
						dst_online_q <= 1'b1;
						dst_quiet_count_q <=
							{DRAIN_QUIET_WIDTH{1'b0}};
						dst_state_q <= StDstWaitSource;
					end else begin
						dst_reset_guard_count_q <=
							dst_reset_guard_count_q + 1'b1;
					end
				end

				StDstWaitSource: begin
					dst_online_q <= 1'b1;
					dst_available_q <= 1'b0;
					dst_source_online_ack_q <= 1'b0;
					dst_response_level_q <= 1'b0;
					dst_request_echo_q <= 1'b0;
					dst_launch_echo_q <= 1'b0;
					if (~dst_source_online_sync |
					    dst_request_level_sync |
					    dst_confirm_level_sync |
					    dst_response_active) begin
						if (dst_response_active)
							dst_late_response_o <= 1'b1;
						dst_quiet_count_q <=
							{DRAIN_QUIET_WIDTH{1'b0}};
					end else if (dst_quiet_count_q ==
					             DRAIN_QUIET_LIMIT - 1) begin
						dst_source_online_ack_q <= 1'b1;
						dst_available_q <= 1'b1;
						dst_state_q <= StDstIdle;
					end else begin
						dst_quiet_count_q <=
							dst_quiet_count_q + 1'b1;
					end
				end

				StDstIdle: begin
					dst_online_q <= 1'b1;
					dst_available_q <= 1'b1;
					dst_source_online_ack_q <= 1'b1;
					dst_response_level_q <= 1'b0;
					dst_request_echo_q <= 1'b0;
					dst_launch_echo_q <= 1'b0;
					dst_abort_timeout_count_q <=
						{DESTINATION_ABORT_TIMEOUT_WIDTH{1'b0}};
					dst_quiet_count_q <=
						{DRAIN_QUIET_WIDTH{1'b0}};

					if (~dst_source_online_sync) begin
						dst_available_q <= 1'b0;
						dst_source_online_ack_q <= 1'b0;
						dst_state_q <= StDstQuietDrain;
					end else if (dst_request_level_sync) begin
						dst_available_q <= 1'b0;
						dst_req_data_hold_q <=
							src_req_data_hold_q;
						dst_req_addr_hold_q <=
							src_req_addr_hold_q;
						dst_req_select_hold_q <=
							src_req_select_hold_q;
						dst_req_read_hold_q <=
							src_req_read_hold_q;
						dst_req_write_hold_q <=
							src_req_write_hold_q;
						dst_req_validate_hold_q <=
							src_req_validate_hold_q;
						dst_req_query_hold_q <=
							src_req_query_hold_q;
						dst_request_echo_q <= 1'b1;
						if (dst_response_active |
						    dst_confirm_level_sync) begin
							if (dst_response_active)
								dst_late_response_o <=
									1'b1;
							dst_rsp_data_hold_q <= 64'd0;
							dst_rsp_error_hold_q <= 1'b1;
							dst_response_level_q <= 1'b1;
							dst_launch_echo_q <= 1'b1;
							dst_state_q <=
								StDstWaitReqLow;
						end else begin
							dst_launch_echo_q <= 1'b0;
							dst_state_q <=
								StDstWaitConfirm;
						end
					end else if (dst_response_active |
					             dst_confirm_level_sync) begin
						dst_available_q <= 1'b0;
						if (dst_response_active)
							dst_late_response_o <= 1'b1;
						dst_state_q <= StDstQuietDrain;
					end
				end

				StDstWaitConfirm: begin
					dst_online_q <= 1'b1;
					dst_available_q <= 1'b0;
					dst_source_online_ack_q <= 1'b1;
					dst_response_level_q <= 1'b0;
					dst_request_echo_q <= 1'b1;
					dst_launch_echo_q <= 1'b0;
					if (~dst_source_online_sync) begin
						dst_source_online_ack_q <= 1'b0;
						dst_request_echo_q <= 1'b0;
						dst_quiet_count_q <=
							{DRAIN_QUIET_WIDTH{1'b0}};
						dst_state_q <= StDstQuietDrain;
					end else if (~dst_request_level_sync) begin
						dst_request_echo_q <= 1'b0;
						dst_quiet_count_q <=
							{DRAIN_QUIET_WIDTH{1'b0}};
						dst_state_q <= StDstQuietDrain;
					end else if (dst_response_active) begin
						dst_late_response_o <= 1'b1;
						dst_rsp_data_hold_q <= 64'd0;
						dst_rsp_error_hold_q <= 1'b1;
						dst_response_level_q <= 1'b1;
						dst_launch_echo_q <= 1'b1;
						dst_state_q <= StDstWaitReqLow;
					end else if (dst_confirm_level_sync) begin
						dst_launch_echo_q <= 1'b1;
						if (dst_held_command_legal) begin
							dst_state_q <=
								StDstWaitResponse;
						end else begin
							dst_rsp_data_hold_q <= 64'd0;
							dst_rsp_error_hold_q <= 1'b1;
							dst_response_level_q <= 1'b1;
							dst_state_q <=
								StDstWaitReqLow;
						end
					end
				end

				StDstWaitResponse: begin
					dst_online_q <= 1'b1;
					dst_available_q <= 1'b0;
					dst_request_echo_q <= 1'b1;
					dst_launch_echo_q <= 1'b1;
					if (~dst_source_online_sync) begin
						dst_source_online_ack_q <= 1'b0;
						dst_response_level_q <= 1'b0;
						if (dst_response_active) begin
							dst_late_response_o <= 1'b1;
							dst_state_q <=
								StDstQuietDrain;
						end else begin
							dst_state_q <=
								StDstAbortDrain;
						end
						dst_abort_timeout_count_q <=
							{DESTINATION_ABORT_TIMEOUT_WIDTH{1'b0}};
						dst_quiet_count_q <=
							{DRAIN_QUIET_WIDTH{1'b0}};
					end else if (~dst_request_level_sync |
					             ~dst_confirm_level_sync) begin
						if (dst_response_active) begin
							dst_late_response_o <= 1'b1;
							dst_state_q <=
								StDstQuietDrain;
						end else begin
							dst_state_q <=
								StDstAbortDrain;
						end
						dst_abort_timeout_count_q <=
							{DESTINATION_ABORT_TIMEOUT_WIDTH{1'b0}};
						dst_quiet_count_q <=
							{DRAIN_QUIET_WIDTH{1'b0}};
					end else if (dst_response_active) begin
						dst_rsp_data_hold_q <=
							dst_bus.rsp_ack ?
							dst_bus.rsp_data : 64'd0;
						dst_rsp_error_hold_q <=
							dst_bus.rsp_error;
						dst_response_level_q <= 1'b1;
						dst_state_q <= StDstWaitReqLow;
					end
				end

				StDstWaitReqLow: begin
					dst_online_q <= 1'b1;
					dst_available_q <= 1'b0;
					dst_request_echo_q <= 1'b1;
					dst_launch_echo_q <= 1'b1;
					if (~dst_source_online_sync) begin
						dst_source_online_ack_q <= 1'b0;
						dst_response_level_q <= 1'b0;
						dst_request_echo_q <= 1'b0;
						dst_launch_echo_q <= 1'b0;
						dst_quiet_count_q <=
							{DRAIN_QUIET_WIDTH{1'b0}};
						dst_state_q <= StDstQuietDrain;
					end else if (~dst_request_level_sync &
					             ~dst_confirm_level_sync) begin
						dst_response_level_q <= 1'b0;
						dst_request_echo_q <= 1'b0;
						dst_launch_echo_q <= 1'b0;
						dst_quiet_count_q <=
							{DRAIN_QUIET_WIDTH{1'b0}};
						dst_state_q <= StDstQuietDrain;
					end
				end

				StDstAbortDrain: begin
					dst_online_q <= 1'b1;
					dst_available_q <= 1'b0;
					dst_response_level_q <= 1'b0;
					dst_request_echo_q <= 1'b1;
					dst_launch_echo_q <= 1'b1;
					if (~dst_source_online_sync)
						dst_source_online_ack_q <= 1'b0;
					if (dst_response_active) begin
						dst_late_response_o <= 1'b1;
						dst_request_echo_q <= 1'b0;
						dst_launch_echo_q <= 1'b0;
						dst_quiet_count_q <=
							{DRAIN_QUIET_WIDTH{1'b0}};
						dst_state_q <= StDstQuietDrain;
					end else if (DESTINATION_ABORT_TIMEOUT_CYCLES <= 1) begin
						dst_forced_drop_o <= 1'b1;
						dst_request_echo_q <= 1'b0;
						dst_launch_echo_q <= 1'b0;
						dst_available_q <= 1'b0;
						dst_terminal_fault_o <= 1'b1;
						dst_state_q <=
							StDstTerminalFault;
					end else if (dst_abort_timeout_count_q ==
					             DESTINATION_ABORT_TIMEOUT_CYCLES - 1) begin
						dst_forced_drop_o <= 1'b1;
						dst_request_echo_q <= 1'b0;
						dst_launch_echo_q <= 1'b0;
						dst_available_q <= 1'b0;
						dst_terminal_fault_o <= 1'b1;
						dst_state_q <=
							StDstTerminalFault;
					end else begin
						dst_abort_timeout_count_q <=
							dst_abort_timeout_count_q + 1'b1;
					end
				end

				StDstQuietDrain: begin
					dst_online_q <= 1'b1;
					dst_available_q <= 1'b0;
					dst_response_level_q <= 1'b0;
					dst_request_echo_q <= 1'b0;
					dst_launch_echo_q <= 1'b0;
					if (~dst_source_online_sync)
						dst_source_online_ack_q <= 1'b0;
					if (dst_source_online_sync &
					    dst_request_level_sync) begin
						if (dst_response_active)
							dst_late_response_o <= 1'b1;
						dst_rsp_data_hold_q <= 64'd0;
						dst_rsp_error_hold_q <= 1'b1;
						dst_response_level_q <= 1'b1;
						dst_request_echo_q <= 1'b1;
						dst_launch_echo_q <= 1'b1;
						dst_state_q <= StDstWaitReqLow;
					end else if (dst_request_level_sync |
					             dst_confirm_level_sync) begin
						dst_quiet_count_q <=
							{DRAIN_QUIET_WIDTH{1'b0}};
					end else if (dst_response_active) begin
						dst_late_response_o <= 1'b1;
						dst_quiet_count_q <=
							{DRAIN_QUIET_WIDTH{1'b0}};
					end else if (dst_quiet_count_q ==
					             DRAIN_QUIET_LIMIT - 1) begin
						if (dst_source_online_sync) begin
							dst_source_online_ack_q <= 1'b1;
							dst_available_q <= 1'b1;
							dst_state_q <= StDstIdle;
						end else begin
							dst_state_q <= StDstWaitSource;
						end
					end else begin
						dst_quiet_count_q <=
							dst_quiet_count_q + 1'b1;
					end
				end

				StDstTerminalFault: begin
					dst_online_q <= 1'b1;
					dst_available_q <= 1'b0;
					dst_source_online_ack_q <= 1'b1;
					dst_response_level_q <= 1'b0;
					dst_request_echo_q <= 1'b0;
					dst_launch_echo_q <= 1'b0;
					dst_terminal_fault_o <= 1'b1;
					if (dst_response_active)
						dst_late_response_o <= 1'b1;
					dst_state_q <= StDstTerminalFault;
				end

				default: begin
					dst_online_q <= 1'b1;
					dst_available_q <= 1'b0;
					dst_source_online_ack_q <= 1'b1;
					dst_response_level_q <= 1'b0;
					dst_request_echo_q <= 1'b0;
					dst_launch_echo_q <= 1'b0;
					dst_terminal_fault_o <= 1'b1;
					if (dst_response_active)
						dst_late_response_o <= 1'b1;
					dst_state_q <= StDstTerminalFault;
				end
			endcase
			end
		end
	end

endmodule

`default_nettype wire
