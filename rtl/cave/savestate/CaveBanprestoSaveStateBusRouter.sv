`default_nettype none

// Transaction-safe exclusive router for CaveBanpresto save-state bus groups.
//
// A CaveBanprestoSaveStateBusMux broadcasts its admitted request to every
// attached responder.  That is correct for individual owners, but not for
// hierarchical branches such as independent Main-CPU and Sound-CPU CDC
// bridges: a non-owning bridge deliberately rejects an out-of-mask owner and
// would collide with the owning branch's response.
//
// This router instead maps every supported owner to exactly one branch.  It
// latches both the request and selected branch at admission, drives command
// strobes only on that branch, and keeps them stable until the branch answers.
// Runtime-support changes after admission cannot reroute an in-flight command.
//
// BRANCH_OWNER_MASKS is packed in ascending branch slices.  Branch N owns
// BRANCH_OWNER_MASKS[N*SUPPORT_WIDTH +: SUPPORT_WIDTH].
//
// Unsupported requests and malformed commands complete locally with an error
// and remain reusable after the requester releases them.  A supported owner
// with no route or multiple routes is a structural configuration failure.
// Timeout, unsolicited/late branch activity, error without acknowledge, or a
// response from the wrong branch likewise enters a reset-only fail-stop state.
module CaveBanprestoSaveStateBusRouter #(
	parameter integer BRANCH_COUNT = 1,
	parameter integer SUPPORT_WIDTH = 48,
	parameter [SUPPORT_WIDTH-1:0] COMPILED_SUPPORT_BITMAP =
		{SUPPORT_WIDTH{1'b1}},
	parameter [BRANCH_COUNT*SUPPORT_WIDTH-1:0] BRANCH_OWNER_MASKS =
		{BRANCH_COUNT*SUPPORT_WIDTH{1'b1}},
	parameter integer RESPONSE_TIMEOUT_CYCLES = 1024
) (
	input  wire clk_i,
	input  wire reset_i,
	input  wire [SUPPORT_WIDTH-1:0] runtime_support_i,

	cavebanpresto_ssbus_if.requester branches [BRANCH_COUNT],
	cavebanpresto_ssbus_if.responder upstream,

	output logic no_route_o,
	output logic multiple_route_o,
	output logic wrong_branch_response_o,
	output logic timeout_o,
	output logic faulted_o,
	output wire  idle_o
);

	localparam integer TIMEOUT_WIDTH =
		(RESPONSE_TIMEOUT_CYCLES <= 1)
			? 1 : $clog2(RESPONSE_TIMEOUT_CYCLES);
	localparam integer RESPONSE_COUNT_WIDTH =
		(BRANCH_COUNT <= 1) ? 1 : $clog2(BRANCH_COUNT + 1);
	localparam logic PARAMETERS_VALID =
		(BRANCH_COUNT > 0) &&
		(SUPPORT_WIDTH > 0) &&
		(SUPPORT_WIDTH <= 256);

	typedef enum logic [1:0] {
		StIdle         = 2'd0,
		StWaitResponse = 2'd1,
		StWaitRelease  = 2'd2,
		StFault        = 2'd3
	} state_e;

	state_e state_q;

	// Justification (reg-a): hold the transaction and route for the complete
	// branch request/response handshake.
	logic [63:0] req_data_q;
	logic [31:0] req_addr_q;
	logic  [7:0] req_select_q;
	logic        req_read_q;
	logic        req_write_q;
	logic        req_validate_q;
	logic        req_query_q;
	logic [BRANCH_COUNT-1:0] selected_branch_q;

	// Justification (reg-a): bound an unresponsive branch before fail-stop.
	logic [TIMEOUT_WIDTH-1:0] timeout_count_q;

	logic [3:0] upstream_command;
	logic       upstream_command_active;
	logic       upstream_command_legal;
	logic       upstream_request_matches;
	logic       selected_in_range;
	logic       selected_compiled;
	logic       selected_runtime;
	logic       selected_supported;
	logic [BRANCH_COUNT-1:0] route_match_view;
	logic [RESPONSE_COUNT_WIDTH-1:0] route_match_count;
	logic [BRANCH_COUNT-1:0] branch_ack_view;
	logic [BRANCH_COUNT-1:0] branch_error_view;
	logic [63:0] branch_data_view [0:BRANCH_COUNT-1];
	logic [RESPONSE_COUNT_WIDTH-1:0] branch_ack_count;
	logic [63:0] selected_response_data;
	logic        selected_response_error;
	logic        branch_error_without_ack;
	logic        response_from_selected_branch;
	logic        branches_idle;
	logic        forward_request;

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
	assign selected_in_range =
		PARAMETERS_VALID && (upstream.req_select < SUPPORT_WIDTH);

	always_comb begin
		selected_compiled = 1'b0;
		selected_runtime = 1'b0;
		if (selected_in_range) begin
			selected_compiled =
				COMPILED_SUPPORT_BITMAP[upstream.req_select];
			selected_runtime =
				runtime_support_i[upstream.req_select];
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

	integer branch_index;
	always_comb begin
		route_match_view = {BRANCH_COUNT{1'b0}};
		route_match_count = {RESPONSE_COUNT_WIDTH{1'b0}};
		branch_ack_count = {RESPONSE_COUNT_WIDTH{1'b0}};
		selected_response_data = 64'd0;
		selected_response_error = 1'b0;
		branch_error_without_ack = 1'b0;
		response_from_selected_branch = 1'b0;

		for (branch_index = 0; branch_index < BRANCH_COUNT;
		     branch_index = branch_index + 1) begin
			if (selected_in_range) begin
				route_match_view[branch_index] =
					BRANCH_OWNER_MASKS[
						branch_index*SUPPORT_WIDTH +
						upstream.req_select
					];
				if (BRANCH_OWNER_MASKS[
					branch_index*SUPPORT_WIDTH +
					upstream.req_select
				])
					route_match_count =
						route_match_count + 1'b1;
			end

			if (branch_ack_view[branch_index]) begin
				branch_ack_count = branch_ack_count + 1'b1;
				if (selected_branch_q[branch_index]) begin
					response_from_selected_branch = 1'b1;
					selected_response_data =
						branch_data_view[branch_index];
					selected_response_error =
						branch_error_view[branch_index];
				end
			end else if (branch_error_view[branch_index]) begin
				branch_error_without_ack = 1'b1;
			end
		end
	end

	assign branches_idle =
		(branch_ack_count == {RESPONSE_COUNT_WIDTH{1'b0}}) &
		~branch_error_without_ack;
	assign forward_request = state_q == StWaitResponse;
	assign idle_o =
		(state_q === StIdle) &&
		(branches_idle === 1'b1) &&
		(upstream_command_active === 1'b0) &&
		(faulted_o === 1'b0);

	genvar gi;
	generate
		for (gi = 0; gi < BRANCH_COUNT; gi = gi + 1) begin : gen_branch
			assign branch_ack_view[gi] = branches[gi].rsp_ack;
			assign branch_error_view[gi] = branches[gi].rsp_error;
			assign branch_data_view[gi] = branches[gi].rsp_data;

			assign branches[gi].req_data = req_data_q;
			assign branches[gi].req_addr = req_addr_q;
			assign branches[gi].req_select = req_select_q;
			assign branches[gi].req_read =
				forward_request & selected_branch_q[gi] &
				req_read_q;
			assign branches[gi].req_write =
				forward_request & selected_branch_q[gi] &
				req_write_q;
			assign branches[gi].req_validate =
				forward_request & selected_branch_q[gi] &
				req_validate_q;
			assign branches[gi].req_query =
				forward_request & selected_branch_q[gi] &
				req_query_q;
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
			selected_branch_q <= {BRANCH_COUNT{1'b0}};
			timeout_count_q <= {TIMEOUT_WIDTH{1'b0}};
			upstream.rsp_data <= 64'd0;
			upstream.rsp_ack <= 1'b0;
			upstream.rsp_error <= 1'b0;
			no_route_o <= 1'b0;
			multiple_route_o <= 1'b0;
			wrong_branch_response_o <= 1'b0;
			timeout_o <= 1'b0;
			faulted_o <= 1'b0;
		end else begin
			upstream.rsp_data <= 64'd0;
			upstream.rsp_ack <= 1'b0;
			upstream.rsp_error <= 1'b0;
			no_route_o <= 1'b0;
			multiple_route_o <= 1'b0;
			wrong_branch_response_o <= 1'b0;
			timeout_o <= 1'b0;

			unique case (state_q)
				StIdle: begin
					timeout_count_q <= {TIMEOUT_WIDTH{1'b0}};
					selected_branch_q <=
						{BRANCH_COUNT{1'b0}};

					if (~branches_idle) begin
						if (upstream_command_active) begin
							upstream.rsp_ack <= 1'b1;
							upstream.rsp_error <= 1'b1;
						end
						wrong_branch_response_o <= 1'b1;
						faulted_o <= 1'b1;
						state_q <= StFault;
					end else if (upstream_command_active) begin
						if (~upstream_command_legal |
						    ~selected_supported) begin
							upstream.rsp_ack <= 1'b1;
							upstream.rsp_error <= 1'b1;
							state_q <= StWaitRelease;
						end else if (route_match_count == 0) begin
							upstream.rsp_ack <= 1'b1;
							upstream.rsp_error <= 1'b1;
							no_route_o <= 1'b1;
							faulted_o <= 1'b1;
							state_q <= StFault;
						end else if (route_match_count != 1) begin
							upstream.rsp_ack <= 1'b1;
							upstream.rsp_error <= 1'b1;
							multiple_route_o <= 1'b1;
							faulted_o <= 1'b1;
							state_q <= StFault;
						end else begin
							req_data_q <= upstream.req_data;
							req_addr_q <= upstream.req_addr;
							req_select_q <= upstream.req_select;
							req_read_q <= upstream.req_read;
							req_write_q <= upstream.req_write;
							req_validate_q <=
								upstream.req_validate;
							req_query_q <= upstream.req_query;
							selected_branch_q <=
								route_match_view;
							state_q <= StWaitResponse;
						end
					end
				end

				StWaitResponse: begin
					if (branch_error_without_ack ||
					    (branch_ack_count > 1) ||
					    ((branch_ack_count == 1) &&
					     ~response_from_selected_branch)) begin
						if (upstream_request_matches) begin
							upstream.rsp_ack <= 1'b1;
							upstream.rsp_error <= 1'b1;
						end
						wrong_branch_response_o <= 1'b1;
						faulted_o <= 1'b1;
						state_q <= StFault;
					end else if (branch_ack_count == 1) begin
						if (upstream_request_matches) begin
							upstream.rsp_data <=
								selected_response_data;
							upstream.rsp_ack <= 1'b1;
							upstream.rsp_error <=
								selected_response_error;
						end
						state_q <= StWaitRelease;
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
						timeout_count_q <=
							timeout_count_q + 1'b1;
					end
				end

				StWaitRelease: begin
					if (branch_error_without_ack ||
					    (branch_ack_count > 1) ||
					    ((branch_ack_count == 1) &&
					     ~response_from_selected_branch)) begin
						wrong_branch_response_o <= 1'b1;
						faulted_o <= 1'b1;
						state_q <= StFault;
					end else if (branches_idle &&
					             ~upstream_command_active) begin
						state_q <= StIdle;
					end
				end

				StFault: begin
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
