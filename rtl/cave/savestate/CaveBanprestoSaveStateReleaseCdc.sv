`default_nettype none

// Exact-once CaveBanpresto endpoint-release crossing.
//
// CDC pattern: one-bit MCP command/response over the existing four-phase
// CaveBanprestoSaveStateControlCdc.  The source latches release_restore_i from
// the one-cycle release request and holds it until the complete acknowledge
// round trip has re-armed.  The destination captures that stable payload only
// after the synchronized command level arrives.
//
// CaveBanprestoSaveStateControlCdc deliberately holds dst_command_valid_o
// until its consumer reports completion.  Main's release_request_i and
// Sound's release_authorize_i are instead one-shot authorizations.  This
// adapter therefore emits exactly one destination-clock release pulse, waits
// for the endpoint's applied-complete pulse without re-pulsing, and only then
// acknowledges the held CDC command.  The source sees exactly one completion
// pulse and cannot launch another release until the full return-to-idle phase
// has completed.
//
// Independent reset, timeout, malformed/duplicate request, unsolicited
// endpoint completion, changed MCP payload, imported endpoint poison, or an
// underlying CDC fault is ambiguous and therefore reset-only terminal.
// Sticky fault levels cross back to the opposite domain through dedicated
// two-flop synchronizers so neither side can silently re-arm after only one
// domain reset.
module CaveBanprestoSaveStateReleaseCdc #(
	parameter integer SOURCE_TIMEOUT_CYCLES = 4096,
	parameter integer DESTINATION_TIMEOUT_CYCLES = 4096,
	parameter integer RESET_GUARD_CYCLES = 4
) (
	input  wire src_clk_i,
	input  wire src_async_reset_i,
	input  wire src_release_request_i,
	input  wire src_release_restore_i,
	output wire src_release_complete_o,
	output wire src_ready_o,
	output wire src_busy_o,
	output wire src_timeout_o,
	output wire src_destination_reset_o,
	output wire src_protocol_fault_o,
	output wire src_terminal_fault_o,
	output wire [2:0] src_debug_state_o,
	output wire src_debug_restore_hold_o,
	output wire src_debug_command_valid_o,
	output wire src_debug_command_accepted_o,
	output wire src_debug_restore_known_o,

	input  wire dst_clk_i,
	input  wire dst_async_reset_i,
	output wire dst_release_request_o,
	output wire dst_release_restore_o,
	input  wire dst_release_complete_i,
	input  wire dst_terminal_fault_i,
	output wire dst_busy_o,
	output wire dst_timeout_o,
	output wire dst_source_reset_o,
	output wire dst_unsolicited_complete_o,
	output wire dst_protocol_fault_o,
	output wire dst_terminal_fault_o,
	output wire [2:0] dst_debug_state_o,
	output wire dst_debug_restore_hold_o,
	output wire dst_debug_command_valid_o,
	output wire dst_debug_command_o
);

	localparam integer SOURCE_OFFER_TIMEOUT_WIDTH =
		(SOURCE_TIMEOUT_CYCLES <= 1)
			? 1 : $clog2(SOURCE_TIMEOUT_CYCLES);

	typedef enum logic [2:0] {
		StSrcIdle         = 3'd0,
		StSrcOffer        = 3'd1,
		StSrcWaitResponse = 3'd2,
		StSrcWaitRearm    = 3'd3,
		StSrcTerminal     = 3'd4
	} src_state_e;

	typedef enum logic [2:0] {
		StDstIdle         = 3'd0,
		StDstWaitEndpoint = 3'd1,
		StDstWaitWithdraw = 3'd2,
		StDstTerminal     = 3'd3
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

	// Justification: MCP payload is immutable from source offer through the
	// complete request/acknowledge return-to-idle handshake.
	logic src_restore_hold_q;
	// Justification: destination payload remains stable for the endpoint's
	// complete release transaction and is sampled only with the pulse.
	logic dst_restore_hold_q;

	logic src_release_complete_q;
	logic dst_release_request_q;
	logic src_protocol_fault_q;
	logic dst_protocol_fault_q;
	// Justification: each terminal aggregate is registered and sticky before
	// feeding the opposite-domain 2FF synchronizer; no combinational fault
	// tree is placed directly at a synchronizer input.
	logic src_terminal_local_q;
	logic dst_terminal_local_q;
	logic dst_endpoint_unsolicited_q;
	logic src_offer_timeout_q;

	logic [SOURCE_OFFER_TIMEOUT_WIDTH-1:0]
		src_offer_timeout_count_q;

	wire cdc_src_command_ready;
	wire cdc_src_command_accepted;
	wire cdc_src_response_valid;
	wire cdc_src_response;
	wire cdc_src_busy;
	wire cdc_src_timeout;
	wire cdc_src_destination_reset;
	wire cdc_src_terminal_fault;

	wire cdc_dst_command_valid;
	wire cdc_dst_command;
	wire cdc_dst_complete;
	wire cdc_dst_busy;
	wire cdc_dst_timeout;
	wire cdc_dst_source_reset;
	wire cdc_dst_unsolicited_complete;
	wire cdc_dst_terminal_fault;

	wire src_fault_to_dst;
	wire dst_fault_to_src;

	wire dst_imported_fault =
		dst_terminal_fault_i !== 1'b0;

	CaveBanprestoSaveStateCdcBitSync source_fault_to_destination (
		.clk_i   (dst_clk_i),
		.reset_i (dst_reset),
		.async_i (src_terminal_local_q),
		.sync_o  (src_fault_to_dst)
	);

	CaveBanprestoSaveStateCdcBitSync destination_fault_to_source (
		.clk_i   (src_clk_i),
		.reset_i (src_reset),
		.async_i (dst_terminal_local_q),
		.sync_o  (dst_fault_to_src)
	);

	wire cdc_src_command_valid =
		!src_reset &&
		!src_terminal_fault_o &&
		(src_state_q == StSrcOffer);
	wire cdc_dst_terminal_fault_in =
		dst_imported_fault ||
		dst_protocol_fault_q ||
		dst_terminal_local_q ||
		src_fault_to_dst;

	CaveBanprestoSaveStateControlCdc #(
		.COMMAND_WIDTH(1),
		.RESPONSE_WIDTH(1),
		.SOURCE_TIMEOUT_CYCLES(SOURCE_TIMEOUT_CYCLES),
		.DESTINATION_TIMEOUT_CYCLES(
			DESTINATION_TIMEOUT_CYCLES
		),
		.RESET_GUARD_CYCLES(RESET_GUARD_CYCLES)
	) release_control_cdc (
		.src_clk_i                  (src_clk_i),
		.src_async_reset_i          (src_async_reset_i),
		.src_command_valid_i        (cdc_src_command_valid),
		.src_command_ready_o        (cdc_src_command_ready),
		.src_command_i              (src_restore_hold_q),
		.src_command_accepted_o     (cdc_src_command_accepted),
		.src_response_valid_o       (cdc_src_response_valid),
		.src_response_o             (cdc_src_response),
		.src_busy_o                 (cdc_src_busy),
		.src_timeout_o              (cdc_src_timeout),
		.src_destination_reset_o    (
			cdc_src_destination_reset
		),
		.src_terminal_fault_o       (cdc_src_terminal_fault),
		.dst_clk_i                  (dst_clk_i),
		.dst_async_reset_i          (dst_async_reset_i),
		.dst_command_valid_o        (cdc_dst_command_valid),
		.dst_command_o              (cdc_dst_command),
		.dst_complete_i             (cdc_dst_complete),
		.dst_response_i             (1'b1),
		.dst_terminal_fault_i       (
			cdc_dst_terminal_fault_in
		),
		.dst_busy_o                 (cdc_dst_busy),
		.dst_timeout_o              (cdc_dst_timeout),
		.dst_source_reset_o         (cdc_dst_source_reset),
		.dst_unsolicited_complete_o (
			cdc_dst_unsolicited_complete
		),
		.dst_terminal_fault_o       (cdc_dst_terminal_fault)
	);

	wire src_request_known =
		(src_release_request_i === 1'b0) ||
		(src_release_request_i === 1'b1);
	wire src_restore_known =
		(src_release_restore_i === 1'b0) ||
		(src_release_restore_i === 1'b1);
	wire cdc_src_response_known =
		(cdc_src_response === 1'b0) ||
		(cdc_src_response === 1'b1);
	wire cdc_dst_valid_known =
		(cdc_dst_command_valid === 1'b0) ||
		(cdc_dst_command_valid === 1'b1);
	wire cdc_dst_command_known =
		(cdc_dst_command === 1'b0) ||
		(cdc_dst_command === 1'b1);
	wire dst_complete_known =
		(dst_release_complete_i === 1'b0) ||
		(dst_release_complete_i === 1'b1);

	logic src_protocol_fault_event;
	logic dst_protocol_fault_event;

	always_comb begin
		src_protocol_fault_event = 1'b0;

		if (!src_reset && !src_terminal_fault_o) begin
			if (!src_request_known) begin
				src_protocol_fault_event = 1'b1;
			end else if (
				(src_release_request_i === 1'b1) &&
				((src_state_q != StSrcIdle) ||
				 !src_restore_known)
			) begin
				src_protocol_fault_event = 1'b1;
			end

			if (cdc_src_response_valid &&
			    ((src_state_q != StSrcWaitResponse) ||
			     !cdc_src_response_known ||
			     (cdc_src_response !== 1'b1)))
				src_protocol_fault_event = 1'b1;

			if (cdc_src_command_accepted &&
			    (src_state_q != StSrcWaitResponse))
				src_protocol_fault_event = 1'b1;
		end
	end

	always_comb begin
		dst_protocol_fault_event = 1'b0;

		if (!dst_reset && !dst_terminal_fault_o) begin
			if (!cdc_dst_valid_known ||
			    !dst_complete_known) begin
				dst_protocol_fault_event = 1'b1;
			end else begin
				unique case (dst_state_q)
					StDstIdle: begin
						if (dst_release_complete_i ===
						    1'b1)
							dst_protocol_fault_event =
								1'b1;
						if (cdc_dst_command_valid &&
						    !cdc_dst_command_known)
							dst_protocol_fault_event =
								1'b1;
					end

					StDstWaitEndpoint: begin
						if (!cdc_dst_command_valid ||
						    !cdc_dst_command_known ||
						    (cdc_dst_command !==
						     dst_restore_hold_q))
							dst_protocol_fault_event =
								1'b1;
					end

					StDstWaitWithdraw: begin
						if (cdc_dst_command_valid ||
						    (dst_release_complete_i ===
						     1'b1))
							dst_protocol_fault_event =
								1'b1;
					end

					StDstTerminal: begin
						dst_protocol_fault_event =
							1'b0;
					end

					default: begin
						dst_protocol_fault_event =
							1'b1;
					end
				endcase
			end
		end
	end

	wire src_offer_timeout_expired =
		(SOURCE_TIMEOUT_CYCLES != 0) &&
		(src_offer_timeout_count_q >=
		 SOURCE_TIMEOUT_CYCLES - 1);

	always_comb begin
		src_state_d = src_state_q;

		if (src_reset) begin
			src_state_d = StSrcIdle;
		end else if (src_terminal_fault_o ||
		    src_protocol_fault_event ||
		    ((src_state_q == StSrcOffer) &&
		     src_offer_timeout_expired)) begin
			src_state_d = StSrcTerminal;
		end else begin
			unique case (src_state_q)
				StSrcIdle: begin
					if (src_release_request_i === 1'b1)
						src_state_d = StSrcOffer;
				end

				StSrcOffer: begin
					if (cdc_src_command_ready)
						src_state_d =
							StSrcWaitResponse;
				end

				StSrcWaitResponse: begin
					if (cdc_src_response_valid)
						src_state_d = StSrcWaitRearm;
				end

				StSrcWaitRearm: begin
					if (cdc_src_command_ready)
						src_state_d = StSrcIdle;
				end

				StSrcTerminal: begin
					src_state_d = StSrcTerminal;
				end

				default: begin
					src_state_d = StSrcTerminal;
				end
			endcase
		end
	end

	always_comb begin
		dst_state_d = dst_state_q;

		if (dst_reset) begin
			dst_state_d = StDstIdle;
		end else if (dst_terminal_fault_o ||
		    dst_protocol_fault_event) begin
			dst_state_d = StDstTerminal;
		end else begin
			unique case (dst_state_q)
				StDstIdle: begin
					if (cdc_dst_command_valid)
						dst_state_d =
							StDstWaitEndpoint;
				end

				StDstWaitEndpoint: begin
					if (dst_release_complete_i ===
					    1'b1)
						dst_state_d =
							StDstWaitWithdraw;
				end

				StDstWaitWithdraw: begin
					if (!cdc_dst_command_valid &&
					    !cdc_dst_busy)
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

	assign cdc_dst_complete =
		!dst_reset &&
		!dst_terminal_fault_o &&
		!dst_protocol_fault_event &&
		(dst_state_q == StDstWaitEndpoint) &&
		(dst_release_complete_i === 1'b1);

	always_ff @(posedge src_clk_i) begin
		if (src_reset) begin
			src_state_q <= StSrcIdle;
			src_restore_hold_q <= 1'b0;
			src_release_complete_q <= 1'b0;
			src_protocol_fault_q <= 1'b0;
			src_terminal_local_q <= 1'b0;
			src_offer_timeout_count_q <=
				{SOURCE_OFFER_TIMEOUT_WIDTH{1'b0}};
			src_offer_timeout_q <= 1'b0;
		end else begin
			src_state_q <= src_state_d;
			src_release_complete_q <= 1'b0;
			src_offer_timeout_q <= 1'b0;

			if ((src_state_q == StSrcIdle) &&
			    (src_release_request_i === 1'b1) &&
			    src_restore_known &&
			    !src_terminal_fault_o)
				src_restore_hold_q <=
					src_release_restore_i;

			if ((src_state_q == StSrcWaitResponse) &&
			    cdc_src_response_valid &&
			    (cdc_src_response === 1'b1) &&
			    !src_protocol_fault_event &&
			    !src_terminal_fault_o)
				src_release_complete_q <= 1'b1;

			if ((src_state_q == StSrcWaitRearm) &&
			    (src_state_d == StSrcIdle))
				src_restore_hold_q <= 1'b0;

			if ((src_state_q != StSrcOffer) ||
			    (src_state_d != src_state_q) ||
			    (SOURCE_TIMEOUT_CYCLES == 0)) begin
				src_offer_timeout_count_q <=
					{SOURCE_OFFER_TIMEOUT_WIDTH{1'b0}};
			end else if (!src_offer_timeout_expired) begin
				src_offer_timeout_count_q <=
					src_offer_timeout_count_q + 1'b1;
			end

			if ((src_state_q == StSrcOffer) &&
			    src_offer_timeout_expired)
				src_offer_timeout_q <= 1'b1;

			if (src_protocol_fault_event)
				src_protocol_fault_q <= 1'b1;

			if (src_protocol_fault_event ||
			    cdc_src_terminal_fault ||
			    dst_fault_to_src ||
			    ((src_state_q == StSrcOffer) &&
			     src_offer_timeout_expired))
				src_terminal_local_q <= 1'b1;
		end
	end

	always_ff @(posedge dst_clk_i) begin
		if (dst_reset) begin
			dst_state_q <= StDstIdle;
			dst_restore_hold_q <= 1'b0;
			dst_release_request_q <= 1'b0;
			dst_protocol_fault_q <= 1'b0;
			dst_terminal_local_q <= 1'b0;
			dst_endpoint_unsolicited_q <= 1'b0;
		end else begin
			dst_state_q <= dst_state_d;
			dst_release_request_q <= 1'b0;
			dst_endpoint_unsolicited_q <= 1'b0;

			if ((dst_state_q == StDstIdle) &&
			    cdc_dst_command_valid &&
			    cdc_dst_command_known &&
			    !dst_protocol_fault_event &&
			    !dst_terminal_fault_o) begin
				dst_restore_hold_q <= cdc_dst_command;
				dst_release_request_q <= 1'b1;
			end

			if ((dst_state_q == StDstWaitWithdraw) &&
			    (dst_state_d == StDstIdle))
				dst_restore_hold_q <= 1'b0;

			if (dst_release_complete_i === 1'b1 &&
			    (dst_state_q != StDstWaitEndpoint))
				dst_endpoint_unsolicited_q <= 1'b1;

			if (dst_protocol_fault_event)
				dst_protocol_fault_q <= 1'b1;

			if (dst_protocol_fault_event ||
			    cdc_dst_terminal_fault ||
			    dst_imported_fault ||
			    src_fault_to_dst)
				dst_terminal_local_q <= 1'b1;
		end
	end

	assign src_release_complete_o =
		src_release_complete_q &&
		!src_reset &&
		!src_terminal_fault_o;
	assign src_ready_o =
		!src_reset &&
		!src_terminal_fault_o &&
		(src_state_q == StSrcIdle);
	assign src_busy_o =
		!src_reset &&
		!src_terminal_fault_o &&
		((src_state_q == StSrcOffer) ||
		 (src_state_q == StSrcWaitResponse) ||
		 (src_state_q == StSrcWaitRearm) ||
		 cdc_src_busy);
	assign src_timeout_o =
		!src_reset &&
		(cdc_src_timeout || src_offer_timeout_q);
	assign src_destination_reset_o =
		!src_reset &&
		cdc_src_destination_reset;
	assign src_protocol_fault_o =
		!src_reset &&
		src_protocol_fault_q;
	assign src_terminal_fault_o =
		!src_reset &&
		(src_terminal_local_q ||
		 cdc_src_terminal_fault ||
		 dst_fault_to_src);
	// Read-only diagnostics.  These expose registered MCP payload and FSM
	// stages without feeding any functional decision or crossing domains.
	assign src_debug_state_o = src_state_q;
	assign src_debug_restore_hold_o = src_restore_hold_q;
	assign src_debug_command_valid_o = cdc_src_command_valid;
	assign src_debug_command_accepted_o = cdc_src_command_accepted;
	assign src_debug_restore_known_o = src_restore_known;

	assign dst_release_request_o =
		dst_release_request_q &&
		!dst_reset &&
		!dst_terminal_fault_o &&
		!dst_protocol_fault_event;
	assign dst_release_restore_o =
		dst_reset ? 1'b0 : dst_restore_hold_q;
	assign dst_busy_o =
		!dst_reset &&
		!dst_terminal_fault_o &&
		((dst_state_q == StDstWaitEndpoint) ||
		 (dst_state_q == StDstWaitWithdraw) ||
		 dst_release_request_q ||
		 cdc_dst_busy);
	assign dst_timeout_o =
		!dst_reset &&
		cdc_dst_timeout;
	assign dst_source_reset_o =
		!dst_reset &&
		cdc_dst_source_reset;
	assign dst_unsolicited_complete_o =
		!dst_reset &&
		(cdc_dst_unsolicited_complete ||
		 dst_endpoint_unsolicited_q);
	assign dst_protocol_fault_o =
		!dst_reset &&
		dst_protocol_fault_q;
	assign dst_terminal_fault_o =
		!dst_reset &&
		(dst_terminal_local_q ||
		 cdc_dst_terminal_fault ||
		 dst_imported_fault ||
		 src_fault_to_dst);
	assign dst_debug_state_o = dst_state_q;
	assign dst_debug_restore_hold_o = dst_restore_hold_q;
	assign dst_debug_command_valid_o = cdc_dst_command_valid;
	assign dst_debug_command_o = cdc_dst_command;

endmodule

`default_nettype wire
