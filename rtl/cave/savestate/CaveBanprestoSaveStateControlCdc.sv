`default_nettype none

// Ordered, one-command-at-a-time CaveBanpresto save-state control crossing.
//
// The command and response buses are multi-cycle-path payloads.  The source
// latches a command before raising request_q and does not overwrite it until
// the complete request/acknowledge return-to-zero handshake finishes.  The
// destination captures that stable command only after request_q has crossed a
// two-flop synchronizer, holds dst_command_valid_o until the consumer reports
// that the command was applied, and latches the response before raising
// acknowledge_q.  The response remains stable until the source has observed
// it and returned request_q low.
//
// This bridge intentionally transports an ordered control packet rather than
// independently synchronizing restore_begin, restore_enable, restore_commit,
// release, or abort pulses.  The integration sequencer is responsible for
// assigning those meanings to command_i and for asserting dst_complete_i only
// after the requested destination-domain state transition has taken effect.
//
// A timeout, unsolicited completion, imported destination fault, or reset of
// the opposite domain while a command is in flight is ambiguous: the command
// may already have taken effect.  Such cases therefore enter a reset-only
// terminal state and never advertise readiness again.
module CaveBanprestoSaveStateControlCdc #(
	parameter integer COMMAND_WIDTH = 32,
	parameter integer RESPONSE_WIDTH = 32,
	parameter integer SOURCE_TIMEOUT_CYCLES = 4096,
	parameter integer DESTINATION_TIMEOUT_CYCLES = 4096,
	parameter integer RESET_GUARD_CYCLES = 4
) (
	input  wire                         src_clk_i,
	input  wire                         src_async_reset_i,
	input  wire                         src_command_valid_i,
	output wire                         src_command_ready_o,
	input  wire [COMMAND_WIDTH-1:0]     src_command_i,
	output logic                        src_command_accepted_o,
	output logic                        src_response_valid_o,
	output logic [RESPONSE_WIDTH-1:0]   src_response_o,
	output wire                         src_busy_o,
	output logic                        src_timeout_o,
	output logic                        src_destination_reset_o,
	output wire                         src_terminal_fault_o,

	input  wire                         dst_clk_i,
	input  wire                         dst_async_reset_i,
	output wire                         dst_command_valid_o,
	output logic [COMMAND_WIDTH-1:0]    dst_command_o,
	input  wire                         dst_complete_i,
	input  wire [RESPONSE_WIDTH-1:0]    dst_response_i,
	input  wire                         dst_terminal_fault_i,
	output wire                         dst_busy_o,
	output logic                        dst_timeout_o,
	output logic                        dst_source_reset_o,
	output logic                        dst_unsolicited_complete_o,
	output wire                         dst_terminal_fault_o
);

	localparam integer SOURCE_TIMEOUT_WIDTH =
		(SOURCE_TIMEOUT_CYCLES <= 1)
			? 1 : $clog2(SOURCE_TIMEOUT_CYCLES);
	localparam integer DESTINATION_TIMEOUT_WIDTH =
		(DESTINATION_TIMEOUT_CYCLES <= 1)
			? 1 : $clog2(DESTINATION_TIMEOUT_CYCLES);
	localparam integer RESET_GUARD_LIMIT =
		(RESET_GUARD_CYCLES < 3) ? 3 : RESET_GUARD_CYCLES;
	localparam integer RESET_GUARD_WIDTH =
		(RESET_GUARD_LIMIT <= 1)
			? 1 : $clog2(RESET_GUARD_LIMIT);

	typedef enum logic [2:0] {
		StSrcBoot        = 3'd0,
		StSrcIdle        = 3'd1,
		StSrcWaitAckHigh = 3'd2,
		StSrcWaitAckLow  = 3'd3,
		StSrcTerminal    = 3'd4
	} src_state_e;

	typedef enum logic [2:0] {
		StDstBoot         = 3'd0,
		StDstIdle         = 3'd1,
		StDstWaitComplete = 3'd2,
		StDstWaitReqLow   = 3'd3,
		StDstTerminal     = 3'd4
	} dst_state_e;

	wire src_reset;
	wire dst_reset;

	CaveBanprestoSaveStateResetSync src_reset_sync (
		.clk_i         (src_clk_i),
		.async_reset_i (src_async_reset_i),
		.reset_o       (src_reset)
	);

	CaveBanprestoSaveStateResetSync dst_reset_sync (
		.clk_i         (dst_clk_i),
		.async_reset_i (dst_async_reset_i),
		.reset_o       (dst_reset)
	);

	src_state_e src_state_q;
	src_state_e src_state_d;
	dst_state_e dst_state_q;
	dst_state_e dst_state_d;

	// Justification: MCP command payload is immutable for the full handshake.
	logic [COMMAND_WIDTH-1:0] src_command_hold_q;
	// Justification: MCP response payload is immutable until request returns low.
	logic [RESPONSE_WIDTH-1:0] dst_response_hold_q;
	// Justification: four-phase protocol levels cross only through 2FF chains.
	logic src_request_q;
	logic dst_acknowledge_q;

	logic [RESET_GUARD_WIDTH-1:0] src_boot_count_q;
	logic [RESET_GUARD_WIDTH-1:0] dst_boot_count_q;
	logic src_alive_q;
	logic dst_alive_q;
	logic src_alive_sync;
	logic dst_alive_sync;
	logic src_request_sync;
	logic dst_acknowledge_sync;

	logic [SOURCE_TIMEOUT_WIDTH-1:0] src_timeout_count_q;
	logic [DESTINATION_TIMEOUT_WIDTH-1:0] dst_timeout_count_q;

	wire src_waiting =
		(src_state_q == StSrcWaitAckHigh) ||
		(src_state_q == StSrcWaitAckLow);
	wire dst_waiting = dst_state_q == StDstWaitComplete;
	wire src_timeout_expired =
		(SOURCE_TIMEOUT_CYCLES != 0) &&
		(src_timeout_count_q >= SOURCE_TIMEOUT_CYCLES - 1);
	wire dst_timeout_expired =
		(DESTINATION_TIMEOUT_CYCLES != 0) &&
		(dst_timeout_count_q >= DESTINATION_TIMEOUT_CYCLES - 1);
	wire src_accept =
		src_command_valid_i && src_command_ready_o;
	wire dst_complete =
		(dst_state_q == StDstWaitComplete) && dst_complete_i;

	CaveBanprestoSaveStateCdcBitSync src_alive_to_dst (
		.clk_i   (dst_clk_i),
		.reset_i (dst_reset),
		.async_i (src_alive_q),
		.sync_o  (src_alive_sync)
	);

	CaveBanprestoSaveStateCdcBitSync dst_alive_to_src (
		.clk_i   (src_clk_i),
		.reset_i (src_reset),
		.async_i (dst_alive_q),
		.sync_o  (dst_alive_sync)
	);

	CaveBanprestoSaveStateCdcBitSync request_to_dst (
		.clk_i   (dst_clk_i),
		.reset_i (dst_reset),
		.async_i (src_request_q),
		.sync_o  (src_request_sync)
	);

	CaveBanprestoSaveStateCdcBitSync acknowledge_to_src (
		.clk_i   (src_clk_i),
		.reset_i (src_reset),
		.async_i (dst_acknowledge_q),
		.sync_o  (dst_acknowledge_sync)
	);

	always_comb begin
		src_state_d = src_state_q;

		unique case (src_state_q)
			StSrcBoot: begin
				if (src_alive_q && dst_alive_sync &&
				    !dst_acknowledge_sync)
					src_state_d = StSrcIdle;
			end

			StSrcIdle: begin
				if (dst_alive_sync && dst_acknowledge_sync)
					src_state_d = StSrcTerminal;
				else if (src_accept)
					src_state_d = StSrcWaitAckHigh;
			end

			StSrcWaitAckHigh: begin
				if (!dst_alive_sync)
					src_state_d = StSrcTerminal;
				else if (dst_acknowledge_sync)
					src_state_d = StSrcWaitAckLow;
				else if (src_timeout_expired)
					src_state_d = StSrcTerminal;
			end

			StSrcWaitAckLow: begin
				if (!dst_alive_sync)
					src_state_d = StSrcTerminal;
				else if (!dst_acknowledge_sync)
					src_state_d = StSrcIdle;
				else if (src_timeout_expired)
					src_state_d = StSrcTerminal;
			end

			StSrcTerminal: begin
				src_state_d = StSrcTerminal;
			end

			default: begin
				src_state_d = StSrcTerminal;
			end
		endcase
	end

	always_comb begin
		dst_state_d = dst_state_q;

		if (dst_terminal_fault_i) begin
			dst_state_d = StDstTerminal;
		end else begin
			unique case (dst_state_q)
				StDstBoot: begin
					if (dst_alive_q && src_alive_sync &&
					    !src_request_sync)
						dst_state_d = StDstIdle;
				end

				StDstIdle: begin
					if (dst_complete_i)
						dst_state_d = StDstTerminal;
					else if (src_alive_sync && src_request_sync)
						dst_state_d = StDstWaitComplete;
				end

				StDstWaitComplete: begin
					if (!src_alive_sync)
						dst_state_d = StDstTerminal;
					else if (dst_complete_i)
						dst_state_d = StDstWaitReqLow;
					else if (dst_timeout_expired)
						dst_state_d = StDstTerminal;
				end

				StDstWaitReqLow: begin
					if (!src_alive_sync)
						dst_state_d = StDstTerminal;
					else if (dst_complete_i)
						dst_state_d = StDstTerminal;
					else if (!src_request_sync)
						dst_state_d = StDstIdle;
				end

				StDstTerminal: begin
					dst_state_d = StDstTerminal;
				end

				default: begin
					dst_state_d = StDstTerminal;
				end
			endcase
		end
	end

	always_ff @(posedge src_clk_i) begin
		if (src_reset) begin
			src_state_q <= StSrcBoot;
			src_command_hold_q <= {COMMAND_WIDTH{1'b0}};
			src_request_q <= 1'b0;
			src_boot_count_q <= {RESET_GUARD_WIDTH{1'b0}};
			src_alive_q <= 1'b0;
			src_timeout_count_q <= {SOURCE_TIMEOUT_WIDTH{1'b0}};
			src_command_accepted_o <= 1'b0;
			src_response_valid_o <= 1'b0;
			src_response_o <= {RESPONSE_WIDTH{1'b0}};
			src_timeout_o <= 1'b0;
			src_destination_reset_o <= 1'b0;
		end else begin
			src_state_q <= src_state_d;
			src_command_accepted_o <= 1'b0;
			src_response_valid_o <= 1'b0;
			src_timeout_o <= 1'b0;
			src_destination_reset_o <= 1'b0;

			if (!src_alive_q) begin
				if (src_boot_count_q == RESET_GUARD_LIMIT - 1)
					src_alive_q <= 1'b1;
				else
					src_boot_count_q <= src_boot_count_q + 1'b1;
			end

			if (!src_waiting || (src_state_d != src_state_q))
				src_timeout_count_q <= {SOURCE_TIMEOUT_WIDTH{1'b0}};
			else if (!src_timeout_expired)
				src_timeout_count_q <= src_timeout_count_q + 1'b1;

			if (src_accept) begin
				src_command_hold_q <= src_command_i;
				src_request_q <= 1'b1;
				src_command_accepted_o <= 1'b1;
			end

			if ((src_state_q == StSrcWaitAckHigh) &&
			    dst_acknowledge_sync) begin
				src_response_o <= dst_response_hold_q;
				src_response_valid_o <= 1'b1;
				src_request_q <= 1'b0;
			end

			if (src_waiting && !dst_alive_sync)
				src_destination_reset_o <= 1'b1;

			if (src_waiting && src_timeout_expired)
				src_timeout_o <= 1'b1;
		end
	end

	always_ff @(posedge dst_clk_i) begin
		if (dst_reset) begin
			dst_state_q <= StDstBoot;
			dst_command_o <= {COMMAND_WIDTH{1'b0}};
			dst_response_hold_q <= {RESPONSE_WIDTH{1'b0}};
			dst_acknowledge_q <= 1'b0;
			dst_boot_count_q <= {RESET_GUARD_WIDTH{1'b0}};
			dst_alive_q <= 1'b0;
			dst_timeout_count_q <=
				{DESTINATION_TIMEOUT_WIDTH{1'b0}};
			dst_timeout_o <= 1'b0;
			dst_source_reset_o <= 1'b0;
			dst_unsolicited_complete_o <= 1'b0;
		end else begin
			dst_state_q <= dst_state_d;
			dst_timeout_o <= 1'b0;
			dst_source_reset_o <= 1'b0;
			dst_unsolicited_complete_o <= 1'b0;

			if (!dst_alive_q) begin
				if (dst_boot_count_q == RESET_GUARD_LIMIT - 1)
					dst_alive_q <= 1'b1;
				else
					dst_boot_count_q <= dst_boot_count_q + 1'b1;
			end

			if (!dst_waiting || (dst_state_d != dst_state_q))
				dst_timeout_count_q <=
					{DESTINATION_TIMEOUT_WIDTH{1'b0}};
			else if (!dst_timeout_expired)
				dst_timeout_count_q <= dst_timeout_count_q + 1'b1;

			if ((dst_state_q == StDstIdle) &&
			    src_alive_sync && src_request_sync)
				dst_command_o <= src_command_hold_q;

			if (dst_complete) begin
				dst_response_hold_q <= dst_response_i;
				dst_acknowledge_q <= 1'b1;
			end

			if ((dst_state_q == StDstWaitReqLow) &&
			    !src_request_sync)
				dst_acknowledge_q <= 1'b0;

			if (((dst_state_q == StDstWaitComplete) ||
			     (dst_state_q == StDstWaitReqLow)) &&
			    !src_alive_sync)
				dst_source_reset_o <= 1'b1;

			if (dst_waiting && dst_timeout_expired)
				dst_timeout_o <= 1'b1;

			if (dst_complete_i &&
			    (dst_state_q != StDstWaitComplete))
				dst_unsolicited_complete_o <= 1'b1;
		end
	end

	assign src_command_ready_o =
		(src_state_q == StSrcIdle) &&
		dst_alive_sync &&
		!dst_acknowledge_sync;
	assign src_busy_o = src_waiting;
	assign src_terminal_fault_o = src_state_q == StSrcTerminal;

	assign dst_command_valid_o =
		dst_state_q == StDstWaitComplete;
	assign dst_busy_o =
		(dst_state_q == StDstWaitComplete) ||
		(dst_state_q == StDstWaitReqLow);
	assign dst_terminal_fault_o = dst_state_q == StDstTerminal;

endmodule

`default_nettype wire
