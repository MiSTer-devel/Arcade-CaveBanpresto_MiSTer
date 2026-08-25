`default_nettype none

// One-shot CPU-to-system restore bridge for the VideoSys and DIP cells.
//
// This is a four-phase MCP word synchronizer from src_clk_i to dst_clk_i.
// The 144-bit payload is carried as one stable command and remains held for
// the complete request/acknowledge round trip:
//   [143:16] VideoSys physical cells 0..7
//   [15:0]   DIP physical cell
//
// Exactly one destination restore pulse is emitted for each accepted source
// request.  Completion is returned only after the destination explicitly
// reports that both register files applied that pulse.  Duplicate requests,
// unsolicited/duplicate apply indications, timeouts, and an opposite-domain
// reset in flight all poison the bridge until both domains are reset.
module CaveBanprestoVideoDipRestoreCdc #(
	parameter integer SOURCE_TIMEOUT_CYCLES = 4096,
	parameter integer DESTINATION_TIMEOUT_CYCLES = 4096,
	parameter integer RESET_GUARD_CYCLES = 4
) (
	input  wire         src_clk_i,
	input  wire         src_async_reset_i,
	input  wire         src_restore_load_i,
	input  wire [127:0] src_video_state_i,
	input  wire [15:0]  src_dip_state_i,
	output wire         src_ready_o,
	output wire         src_accepted_o,
	output wire         src_complete_o,
	output wire         src_busy_o,
	output logic        src_duplicate_request_o,
	output wire         src_timeout_o,
	output wire         src_destination_reset_o,
	output wire         src_terminal_fault_o,

	input  wire         dst_clk_i,
	input  wire         dst_async_reset_i,
	output logic        dst_restore_load_o,
	output wire [127:0] dst_video_state_o,
	output wire [15:0]  dst_dip_state_o,
	input  wire         dst_restore_applied_i,
	output wire         dst_busy_o,
	output logic        dst_unsolicited_applied_o,
	output wire         dst_timeout_o,
	output wire         dst_source_reset_o,
	output wire         dst_terminal_fault_o
);

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

	logic src_local_fault_q;
	logic dst_local_fault_q;
	logic dst_load_sent_q;
	logic dst_completion_sent_q;

	wire src_fault_to_dst;
	wire dst_fault_to_src;
	wire core_src_ready;
	wire core_src_accepted;
	wire core_src_response_valid;
	wire core_src_busy;
	wire core_src_timeout;
	wire core_src_destination_reset;
	wire core_src_terminal_fault;
	wire core_dst_command_valid;
	wire [143:0] core_dst_command;
	wire core_dst_busy;
	wire core_dst_timeout;
	wire core_dst_source_reset;
	wire core_dst_unsolicited_complete;
	wire core_dst_terminal_fault;

	wire src_fault_level =
		src_local_fault_q || core_src_terminal_fault;
	wire dst_fault_level =
		dst_local_fault_q || core_dst_terminal_fault;

	CaveBanprestoSaveStateCdcBitSync src_fault_sync (
		.clk_i   (dst_clk_i),
		.reset_i (dst_reset),
		.async_i (src_fault_level),
		.sync_o  (src_fault_to_dst)
	);

	CaveBanprestoSaveStateCdcBitSync dst_fault_sync (
		.clk_i   (src_clk_i),
		.reset_i (src_reset),
		.async_i (dst_fault_level),
		.sync_o  (dst_fault_to_src)
	);

	wire core_src_command_valid =
		(src_restore_load_i === 1'b1) &&
		!src_local_fault_q &&
		!dst_fault_to_src;

	// The endpoint's apply pulse is accepted only once, after this wrapper has
	// emitted its load pulse and while the underlying command remains active.
	wire dst_apply_accept =
		(dst_restore_applied_i === 1'b1) &&
		core_dst_command_valid &&
		dst_load_sent_q &&
		!dst_completion_sent_q &&
		!dst_local_fault_q &&
		!src_fault_to_dst;

	CaveBanprestoSaveStateControlCdc #(
		.COMMAND_WIDTH              (144),
		.RESPONSE_WIDTH             (1),
		.SOURCE_TIMEOUT_CYCLES      (SOURCE_TIMEOUT_CYCLES),
		.DESTINATION_TIMEOUT_CYCLES (DESTINATION_TIMEOUT_CYCLES),
		.RESET_GUARD_CYCLES         (RESET_GUARD_CYCLES)
	) restore_control_cdc (
		.src_clk_i                      (src_clk_i),
		.src_async_reset_i              (src_async_reset_i),
		.src_command_valid_i            (core_src_command_valid),
		.src_command_ready_o            (core_src_ready),
		.src_command_i                  ({
			src_video_state_i,
			src_dip_state_i
		}),
		.src_command_accepted_o         (core_src_accepted),
		.src_response_valid_o           (core_src_response_valid),
		.src_response_o                 (),
		.src_busy_o                     (core_src_busy),
		.src_timeout_o                  (core_src_timeout),
		.src_destination_reset_o        (
			core_src_destination_reset
		),
		.src_terminal_fault_o           (core_src_terminal_fault),

		.dst_clk_i                      (dst_clk_i),
		.dst_async_reset_i              (dst_async_reset_i),
		.dst_command_valid_o            (core_dst_command_valid),
		.dst_command_o                  (core_dst_command),
		.dst_complete_i                 (dst_apply_accept),
		.dst_response_i                 (1'b1),
		.dst_terminal_fault_i           (
			dst_local_fault_q || src_fault_to_dst
		),
		.dst_busy_o                     (core_dst_busy),
		.dst_timeout_o                  (core_dst_timeout),
		.dst_source_reset_o             (core_dst_source_reset),
		.dst_unsolicited_complete_o     (
			core_dst_unsolicited_complete
		),
		.dst_terminal_fault_o           (core_dst_terminal_fault)
	);

	always_ff @(posedge src_clk_i) begin
		if (src_reset) begin
			src_local_fault_q <= 1'b0;
			src_duplicate_request_o <= 1'b0;
		end else begin
			src_duplicate_request_o <= 1'b0;

			if (!src_local_fault_q &&
			    (src_restore_load_i === 1'b1) &&
			    !src_ready_o) begin
				src_local_fault_q <= 1'b1;
				src_duplicate_request_o <= 1'b1;
			end
		end
	end

	always_ff @(posedge dst_clk_i) begin
		if (dst_reset) begin
			dst_local_fault_q <= 1'b0;
			dst_load_sent_q <= 1'b0;
			dst_completion_sent_q <= 1'b0;
			dst_restore_load_o <= 1'b0;
			dst_unsolicited_applied_o <= 1'b0;
		end else begin
			dst_restore_load_o <= 1'b0;
			dst_unsolicited_applied_o <= 1'b0;

			if (!core_dst_command_valid) begin
				dst_load_sent_q <= 1'b0;
				dst_completion_sent_q <= 1'b0;
			end else if (!dst_load_sent_q &&
			             !dst_local_fault_q &&
			             !src_fault_to_dst &&
			             !core_dst_terminal_fault) begin
				dst_load_sent_q <= 1'b1;
				dst_restore_load_o <= 1'b1;
			end

			if (dst_apply_accept)
				dst_completion_sent_q <= 1'b1;

			if (!dst_local_fault_q &&
			    (dst_restore_applied_i === 1'b1) &&
			    !dst_apply_accept) begin
				dst_local_fault_q <= 1'b1;
				dst_unsolicited_applied_o <= 1'b1;
			end

			// This should be unreachable because dst_complete_i is locally
			// qualified, but importing it keeps the wrapper fail-closed if
			// the underlying protocol checker ever observes otherwise.
			if (core_dst_unsolicited_complete)
				dst_local_fault_q <= 1'b1;
		end
	end

	assign src_ready_o =
		core_src_ready &&
		!src_local_fault_q &&
		!dst_fault_to_src &&
		!core_src_terminal_fault;
	assign src_accepted_o =
		core_src_accepted &&
		!src_local_fault_q &&
		!dst_fault_to_src;
	assign src_complete_o =
		core_src_response_valid &&
		!src_local_fault_q &&
		!dst_fault_to_src &&
		!core_src_terminal_fault;
	assign src_busy_o = core_src_busy;
	assign src_timeout_o = core_src_timeout;
	assign src_destination_reset_o = core_src_destination_reset;
	assign src_terminal_fault_o =
		src_local_fault_q ||
		dst_fault_to_src ||
		core_src_terminal_fault;

	assign dst_video_state_o = core_dst_command[143:16];
	assign dst_dip_state_o = core_dst_command[15:0];
	assign dst_busy_o = core_dst_busy || dst_load_sent_q;
	assign dst_timeout_o = core_dst_timeout;
	assign dst_source_reset_o = core_dst_source_reset;
	assign dst_terminal_fault_o =
		dst_local_fault_q ||
		src_fault_to_dst ||
		core_dst_terminal_fault;

endmodule

`default_nettype wire
