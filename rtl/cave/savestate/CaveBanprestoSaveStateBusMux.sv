`default_nettype none

// Transaction-safe CaveBanpresto owner-bus fanout and response mux.
//
// Requests are admitted only when both the compile-time and runtime owner bits
// are set.  An illegal or unsupported request is completed locally with
// rsp_error and is never launched to an owner.  Once admitted, the request is
// latched and held until an owner responds, even if the upstream requester
// abandons it.
//
// A timeout is different from an ordinary response: there is no owner-busy
// sideband proving that a timed-out operation can no longer respond.  Timeout,
// unsolicited owner activity, malformed error-without-ack, multiple
// acknowledgements, and an invalid FSM state therefore enter a reset-only
// fail-stop state.  Forwarded commands are dropped on entry so an unaccepted
// write cannot launch after failure was reported, and late responses are
// ignored so they cannot satisfy a later transaction.
//
// OWNER_BASE permits a clock-domain-local group to retain the stream's
// absolute owner IDs.  For example, a seven-entry Sound mux uses base 23 and
// accepts only IDs 23 through 29 while still indexing the global support mask
// with those absolute IDs.
module CaveBanprestoSaveStateBusMux #(
	parameter integer OWNER_COUNT = 1,
	parameter integer OWNER_BASE = 0,
	parameter integer SUPPORT_WIDTH = 48,
	parameter [SUPPORT_WIDTH-1:0] COMPILED_SUPPORT_BITMAP =
		{SUPPORT_WIDTH{1'b1}},
	parameter integer RESPONSE_TIMEOUT_CYCLES = 1024
) (
	input  wire clk_i,
	input  wire reset_i,
	input  wire [SUPPORT_WIDTH-1:0] runtime_support_i,

	cavebanpresto_ssbus_if.requester owners [OWNER_COUNT],
	cavebanpresto_ssbus_if.responder upstream,

	output logic multiple_ack_o,
	output logic timeout_o,
	output logic faulted_o,
	output wire  idle_o
);

	localparam integer TIMEOUT_WIDTH =
		(RESPONSE_TIMEOUT_CYCLES <= 1) ? 1 : $clog2(RESPONSE_TIMEOUT_CYCLES);
	localparam integer ACK_COUNT_WIDTH =
		(OWNER_COUNT <= 1) ? 1 : $clog2(OWNER_COUNT + 1);
	localparam [31:0] OWNER_BASE_WIDE = OWNER_BASE;
	localparam [31:0] OWNER_LIMIT_WIDE = OWNER_BASE + OWNER_COUNT;
	localparam [31:0] SUPPORT_LIMIT_WIDE = SUPPORT_WIDTH;
	localparam [8:0] OWNER_BASE_9 = OWNER_BASE_WIDE[8:0];
	localparam [8:0] OWNER_LIMIT_9 = OWNER_LIMIT_WIDE[8:0];
	localparam [8:0] SUPPORT_LIMIT_9 = SUPPORT_LIMIT_WIDE[8:0];
	localparam logic PARAMETERS_VALID =
		(OWNER_COUNT > 0) &&
		(OWNER_BASE >= 0) &&
		(OWNER_BASE < SUPPORT_WIDTH) &&
		((OWNER_BASE + OWNER_COUNT) <= SUPPORT_WIDTH) &&
		((OWNER_BASE + OWNER_COUNT) <= 256);

	typedef enum logic [1:0] {
		StIdle        = 2'd0,
		StWaitOwner   = 2'd1,
		StWaitRelease = 2'd2,
		StFault       = 2'd3
	} state_e;

	state_e state_q;

	// Justification (reg-a): holds the admitted transaction until completion.
	logic [63:0] req_data_q;
	logic [31:0] req_addr_q;
	logic  [7:0] req_select_q;
	logic        req_read_q;
	logic        req_write_q;
	logic        req_validate_q;
	logic        req_query_q;

	// Justification (reg-a): bounds an unresponsive owner transaction before
	// the reset-only fail-stop state drops the forwarded command.
	logic [TIMEOUT_WIDTH-1:0] timeout_count_q;

	logic [3:0] upstream_command;
	logic       upstream_command_active;
	logic       upstream_command_legal;
	logic       upstream_request_matches;
	logic       selected_in_range;
	logic       selected_compiled;
	logic       selected_runtime;
	logic       selected_supported;
	logic       forward_request;
	logic [8:0] selected_owner_9;

	logic [ACK_COUNT_WIDTH-1:0] owner_ack_count;
	logic [63:0] owner_rsp_data;
	logic        owner_rsp_error;
	logic        owner_error_without_ack;
	logic        owners_idle;
	logic [OWNER_COUNT-1:0] owner_rsp_ack_view;
	logic [OWNER_COUNT-1:0] owner_rsp_error_view;
	logic [63:0] owner_rsp_data_view [0:OWNER_COUNT-1];

	integer owner_index;
	always_comb begin
		owner_ack_count = {ACK_COUNT_WIDTH{1'b0}};
		owner_rsp_data = 64'd0;
		owner_rsp_error = 1'b0;
		owner_error_without_ack = 1'b0;

		for (owner_index = 0; owner_index < OWNER_COUNT;
		     owner_index = owner_index + 1) begin
			if (owner_rsp_ack_view[owner_index]) begin
				if (owner_ack_count == {ACK_COUNT_WIDTH{1'b0}}) begin
					owner_rsp_data = owner_rsp_data_view[owner_index];
					owner_rsp_error = owner_rsp_error_view[owner_index];
				end
				owner_ack_count = owner_ack_count + 1'b1;
			end else if (owner_rsp_error_view[owner_index]) begin
				owner_error_without_ack = 1'b1;
			end
		end
	end

	assign owners_idle =
		(owner_ack_count == {ACK_COUNT_WIDTH{1'b0}}) &
		~owner_error_without_ack;

	assign upstream_command = {
		upstream.req_query,
		upstream.req_validate,
		upstream.req_write,
		upstream.req_read
	};
	assign upstream_command_active = |upstream_command;
	assign upstream_command_legal =
		(upstream_command == 4'b0001) |
		(upstream_command == 4'b0010) |
		(upstream_command == 4'b0100) |
		(upstream_command == 4'b1000);

	assign selected_owner_9 = {1'b0, upstream.req_select};
	assign selected_in_range =
		PARAMETERS_VALID &&
		(selected_owner_9 >= OWNER_BASE_9) &&
		(selected_owner_9 < OWNER_LIMIT_9) &&
		(selected_owner_9 < SUPPORT_LIMIT_9);
	always_comb begin
		selected_compiled = 1'b0;
		selected_runtime = 1'b0;
		if (selected_in_range) begin
			selected_compiled =
				COMPILED_SUPPORT_BITMAP[upstream.req_select];
			selected_runtime = runtime_support_i[upstream.req_select];
		end
	end
	assign selected_supported =
		selected_in_range & selected_compiled & selected_runtime;

	assign upstream_request_matches =
		upstream_command_active &
		(upstream.req_data == req_data_q) &
		(upstream.req_addr == req_addr_q) &
		(upstream.req_select == req_select_q) &
		(upstream.req_read == req_read_q) &
		(upstream.req_write == req_write_q) &
		(upstream.req_validate == req_validate_q) &
		(upstream.req_query == req_query_q);

	assign forward_request = state_q == StWaitOwner;
	assign idle_o =
		(state_q === StIdle) &&
		(owners_idle === 1'b1) &&
		(upstream_command_active === 1'b0) &&
		(faulted_o === 1'b0);

	genvar gi;
	generate
		for (gi = 0; gi < OWNER_COUNT; gi = gi + 1) begin : gen_owner_fanout
			assign owner_rsp_ack_view[gi] = owners[gi].rsp_ack;
			assign owner_rsp_error_view[gi] = owners[gi].rsp_error;
			assign owner_rsp_data_view[gi] = owners[gi].rsp_data;

			assign owners[gi].req_data = req_data_q;
			assign owners[gi].req_addr = req_addr_q;
			assign owners[gi].req_select = req_select_q;
			assign owners[gi].req_read = forward_request & req_read_q;
			assign owners[gi].req_write = forward_request & req_write_q;
			assign owners[gi].req_validate =
				forward_request & req_validate_q;
			assign owners[gi].req_query = forward_request & req_query_q;
		end
	endgenerate

	always_ff @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= StIdle;
			req_data_q <= 64'd0;
			req_addr_q <= 32'd0;
			req_select_q <= 8'd0;
			req_read_q <= 1'b0;
			req_write_q <= 1'b0;
			req_validate_q <= 1'b0;
			req_query_q <= 1'b0;
			timeout_count_q <= {TIMEOUT_WIDTH{1'b0}};
			upstream.rsp_data <= 64'd0;
			upstream.rsp_ack <= 1'b0;
			upstream.rsp_error <= 1'b0;
			multiple_ack_o <= 1'b0;
			timeout_o <= 1'b0;
			faulted_o <= 1'b0;
		end else begin
			// Responses and diagnostics are one-cycle pulses with deterministic
			// no-response defaults.
			upstream.rsp_data <= 64'd0;
			upstream.rsp_ack <= 1'b0;
			upstream.rsp_error <= 1'b0;
			multiple_ack_o <= 1'b0;
			timeout_o <= 1'b0;

			unique case (state_q)
				StIdle: begin
					timeout_count_q <= {TIMEOUT_WIDTH{1'b0}};
					if (~owners_idle) begin
						// Any response while no transaction is
						// outstanding is unassignable.  If a new
						// request is present, reject it exactly once
						// before entering the terminal state.
						if (upstream_command_active) begin
							upstream.rsp_ack <= 1'b1;
							upstream.rsp_error <= 1'b1;
						end
						if ((owner_ack_count !=
						     {ACK_COUNT_WIDTH{1'b0}}) &&
						    (owner_ack_count !=
						     {{(ACK_COUNT_WIDTH-1){1'b0}},
						      1'b1}))
							multiple_ack_o <= 1'b1;
						faulted_o <= 1'b1;
						state_q <= StFault;
					end else if (upstream_command_active) begin
						if (~upstream_command_legal |
						    ~selected_supported) begin
							upstream.rsp_ack <= 1'b1;
							upstream.rsp_error <= 1'b1;
							state_q <= StWaitRelease;
						end else begin
							req_data_q <= upstream.req_data;
							req_addr_q <= upstream.req_addr;
							req_select_q <= upstream.req_select;
							req_read_q <= upstream.req_read;
							req_write_q <= upstream.req_write;
							req_validate_q <= upstream.req_validate;
							req_query_q <= upstream.req_query;
							state_q <= StWaitOwner;
						end
					end
				end

				StWaitOwner: begin
					if (owner_error_without_ack) begin
						if (upstream_request_matches) begin
							upstream.rsp_ack <= 1'b1;
							upstream.rsp_error <= 1'b1;
						end
						faulted_o <= 1'b1;
						state_q <= StFault;
					end else if (owner_ack_count !=
					             {ACK_COUNT_WIDTH{1'b0}}) begin
						if (owner_ack_count !=
						    {{(ACK_COUNT_WIDTH-1){1'b0}}, 1'b1}) begin
							multiple_ack_o <= 1'b1;
							if (upstream_request_matches) begin
								upstream.rsp_ack <= 1'b1;
								upstream.rsp_data <= 64'd0;
								upstream.rsp_error <= 1'b1;
							end
							faulted_o <= 1'b1;
							state_q <= StFault;
						end else begin
							if (upstream_request_matches) begin
								upstream.rsp_ack <= 1'b1;
								upstream.rsp_data <= owner_rsp_data;
								upstream.rsp_error <= owner_rsp_error;
							end
							state_q <= StWaitRelease;
						end
					end else if (RESPONSE_TIMEOUT_CYCLES <= 1) begin
						if (upstream_request_matches) begin
							upstream.rsp_ack <= 1'b1;
							upstream.rsp_error <= 1'b1;
						end
						timeout_o <= 1'b1;
						faulted_o <= 1'b1;
						state_q <= StFault;
					end else if (timeout_count_q ==
					             RESPONSE_TIMEOUT_CYCLES - 1) begin
						if (upstream_request_matches) begin
							upstream.rsp_ack <= 1'b1;
							upstream.rsp_error <= 1'b1;
						end
						timeout_o <= 1'b1;
						faulted_o <= 1'b1;
						state_q <= StFault;
					end else begin
						timeout_count_q <= timeout_count_q + 1'b1;
					end
				end

				StWaitRelease: begin
					if (~upstream_command_active & owners_idle) begin
						state_q <= StIdle;
					end
				end

				StFault: begin
					// Reset-only fail-stop.  Response defaults above
					// quarantine all late owner activity.
					faulted_o <= 1'b1;
				end

				default: begin
					faulted_o <= 1'b1;
					state_q <= StFault;
				end
			endcase
		end
	end

endmodule

`default_nettype wire
