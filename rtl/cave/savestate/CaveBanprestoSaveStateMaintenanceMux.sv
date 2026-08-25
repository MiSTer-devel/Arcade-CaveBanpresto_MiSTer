`default_nettype none

// Exclusive maintenance-client mux for the CaveBanpresto DDR save port.
//
// ROM identity scanning and save-state streaming share the maintenance side
// of CaveBanprestoSaveStateDdrArbiter.  A client owns the complete arbiter
// grant epoch.  Read-response ownership remains locked from command
// acceptance through the final burst beat, and a new client is not admitted
// until the physical arbiter has observed save_acquire_o low and withdrawn
// save_granted_i.
//
// Both clients must assert acquire before presenting a command and must retain
// acquire until all accepted reads have completed.  Simultaneous acquisition,
// inactive-client traffic, premature release, an unowned response, or a
// bounded grant/response/release timeout is reset-only terminal.
module CaveBanprestoSaveStateMaintenanceMux #(
	parameter integer TIMEOUT_CYCLES = 1_000_000
) (
	input  wire        clk_i,
	input  wire        reset_i,

	// Client 0: read-only ROM identity scanner.
	input  wire        identity_acquire_i,
	input  wire        identity_cmd_valid_i,
	output wire        identity_cmd_ready_o,
	input  wire [31:0] identity_cmd_byte_addr_i,
	output wire        identity_rsp_valid_o,
	output wire [63:0] identity_rsp_rdata_o,

	// Client 1: save-state stream engine.
	input  wire        stream_acquire_i,
	input  wire        stream_cmd_valid_i,
	output wire        stream_cmd_ready_o,
	input  wire        stream_cmd_write_i,
	input  wire [31:0] stream_cmd_byte_addr_i,
	input  wire [63:0] stream_cmd_wdata_i,
	input  wire  [7:0] stream_cmd_be_i,
	input  wire  [7:0] stream_cmd_burstcnt_i,
	output wire        stream_rsp_valid_o,
	output wire [63:0] stream_rsp_rdata_o,

	// Single maintenance connection to CaveBanprestoSaveStateDdrArbiter.
	output wire        save_acquire_o,
	input  wire        save_granted_i,
	output wire        save_cmd_valid_o,
	input  wire        save_cmd_ready_i,
	output wire        save_cmd_write_o,
	output wire [31:0] save_cmd_byte_addr_o,
	output wire [63:0] save_cmd_wdata_o,
	output wire  [7:0] save_cmd_be_o,
	output wire  [7:0] save_cmd_burstcnt_o,
	input  wire        save_rsp_valid_i,
	input  wire [63:0] save_rsp_rdata_i,

	output wire        idle_o,
	output wire        active_o,
	output wire        owner_identity_o,
	output wire        releasing_o,
	output logic       conflict_o,
	output logic       protocol_error_o,
	output logic       unexpected_response_o,
	output logic       timeout_o,
	output wire        terminal_fault_o
);

	typedef enum logic [1:0] {
		StIdle    = 2'd0,
		StActive  = 2'd1,
		StRelease = 2'd2,
		StFault   = 2'd3
	} state_e;

	localparam integer TIMEOUT_WIDTH =
		(TIMEOUT_CYCLES <= 1) ? 1 : $clog2(TIMEOUT_CYCLES);
	localparam integer TIMEOUT_LIMIT =
		(TIMEOUT_CYCLES <= 1) ? 0 : TIMEOUT_CYCLES - 1;

	// Justification (reg-d): identifies the client for the complete physical
	// grant epoch and every response beat belonging to an accepted read.
	state_e state_q;
	logic owner_stream_q;

	// Justification (reg-d): one physical read may be outstanding, but a
	// MiSTer burst can return multiple independently qualified response beats.
	logic [7:0] response_beats_remaining_q;

	// Justification (reg-d): bounds grant acquisition, read response, and
	// physical release waits at this arbitration boundary.
	logic [TIMEOUT_WIDTH-1:0] timeout_count_q;

	// Justification (reg-a): reset-only terminal evidence prevents a later
	// same-boot command from reusing ambiguous maintenance ownership.
	logic terminal_fault_q;

	wire identity_acquire = identity_acquire_i === 1'b1;
	wire stream_acquire = stream_acquire_i === 1'b1;
	wire identity_command = identity_cmd_valid_i === 1'b1;
	wire stream_command = stream_cmd_valid_i === 1'b1;

	wire selected_acquire =
		owner_stream_q ? stream_acquire : identity_acquire;
	wire inactive_acquire =
		owner_stream_q ? identity_acquire : stream_acquire;
	wire selected_command =
		owner_stream_q ? stream_command : identity_command;
	wire inactive_command =
		owner_stream_q ? identity_command : stream_command;

	wire selected_write =
		owner_stream_q ? stream_cmd_write_i : 1'b0;
	wire [31:0] selected_byte_addr =
		owner_stream_q
			? stream_cmd_byte_addr_i
			: identity_cmd_byte_addr_i;
	wire [63:0] selected_wdata =
		owner_stream_q ? stream_cmd_wdata_i : 64'd0;
	wire [7:0] selected_be =
		owner_stream_q ? stream_cmd_be_i : 8'hff;
	wire [7:0] selected_burstcnt =
		owner_stream_q
			? stream_cmd_burstcnt_i
			: 8'd1;

	wire command_route_active =
		(state_q == StActive) &&
		selected_acquire &&
		!terminal_fault_q &&
		(response_beats_remaining_q == 8'd0);

	assign save_acquire_o =
		(state_q == StActive) &&
		selected_acquire &&
		!terminal_fault_q;
	assign save_cmd_valid_o = command_route_active && selected_command;
	assign save_cmd_write_o = selected_write;
	assign save_cmd_byte_addr_o = selected_byte_addr;
	assign save_cmd_wdata_o = selected_wdata;
	assign save_cmd_be_o = selected_be;
	assign save_cmd_burstcnt_o =
		(selected_burstcnt == 8'd0) ? 8'd1 : selected_burstcnt;

	assign identity_cmd_ready_o =
		command_route_active &&
		!owner_stream_q &&
		save_cmd_ready_i;
	assign stream_cmd_ready_o =
		command_route_active &&
		owner_stream_q &&
		save_cmd_ready_i;

	wire response_owned =
		(response_beats_remaining_q != 8'd0) &&
		!terminal_fault_q;
	assign identity_rsp_valid_o =
		save_rsp_valid_i &&
		response_owned &&
		!owner_stream_q;
	assign stream_rsp_valid_o =
		save_rsp_valid_i &&
		response_owned &&
		owner_stream_q;
	assign identity_rsp_rdata_o =
		identity_rsp_valid_o ? save_rsp_rdata_i : 64'd0;
	assign stream_rsp_rdata_o =
		stream_rsp_valid_o ? save_rsp_rdata_i : 64'd0;

	wire command_accepted =
		save_cmd_valid_o && save_cmd_ready_i;
	wire read_accepted = command_accepted && !save_cmd_write_o;

	function automatic logic [7:0] response_count(
		input logic [7:0] burst_count
	);
		begin
			response_count =
				(burst_count == 8'd0) ? 8'd1 : burst_count;
		end
	endfunction

	wire idle_command_without_owner =
		(state_q == StIdle) &&
		(identity_command || stream_command) &&
		!(identity_acquire || stream_acquire);
	wire simultaneous_acquire =
		(state_q != StFault) &&
		identity_acquire &&
		stream_acquire;
	wire inactive_client_activity =
		(state_q == StActive) &&
		(inactive_acquire || inactive_command);
	wire premature_release =
		(state_q == StActive) &&
		!selected_acquire &&
		(selected_command ||
		 (response_beats_remaining_q != 8'd0));
	wire release_command =
		(state_q == StRelease) &&
		(identity_command || stream_command);
	wire unowned_response =
		(state_q != StFault) &&
		save_rsp_valid_i &&
		(response_beats_remaining_q == 8'd0);

	wire timeout_wait =
		((state_q == StActive) &&
		 selected_acquire &&
		 !save_granted_i) ||
		(response_beats_remaining_q != 8'd0) ||
		((state_q == StRelease) && save_granted_i);
	wire timeout_expired =
		(TIMEOUT_CYCLES != 0) &&
		timeout_wait &&
		(timeout_count_q == TIMEOUT_LIMIT);

	assign idle_o =
		(state_q == StIdle) &&
		!identity_acquire &&
		!stream_acquire &&
		!identity_command &&
		!stream_command &&
		!save_granted_i &&
		(response_beats_remaining_q == 8'd0) &&
		!terminal_fault_q;
	assign active_o = state_q == StActive;
	assign owner_identity_o =
		(state_q != StIdle) && !owner_stream_q;
	assign releasing_o = state_q == StRelease;
	assign terminal_fault_o = terminal_fault_q;

	always_ff @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= StIdle;
			owner_stream_q <= 1'b0;
			response_beats_remaining_q <= 8'd0;
			timeout_count_q <= {TIMEOUT_WIDTH{1'b0}};
			terminal_fault_q <= 1'b0;
			conflict_o <= 1'b0;
			protocol_error_o <= 1'b0;
			unexpected_response_o <= 1'b0;
			timeout_o <= 1'b0;
		end else begin
			conflict_o <= 1'b0;
			protocol_error_o <= 1'b0;
			unexpected_response_o <= 1'b0;
			timeout_o <= 1'b0;

			if (save_rsp_valid_i &&
			    (response_beats_remaining_q != 8'd0)) begin
				response_beats_remaining_q <=
					response_beats_remaining_q - 8'd1;
			end else if (read_accepted) begin
				response_beats_remaining_q <=
					response_count(save_cmd_burstcnt_o);
			end

			if (!timeout_wait ||
			    save_rsp_valid_i ||
			    command_accepted) begin
				timeout_count_q <= {TIMEOUT_WIDTH{1'b0}};
			end else if ((TIMEOUT_CYCLES != 0) &&
			             !timeout_expired) begin
				timeout_count_q <= timeout_count_q + 1'b1;
			end

			if (simultaneous_acquire ||
			    inactive_client_activity) begin
				state_q <= StFault;
				terminal_fault_q <= 1'b1;
				conflict_o <= 1'b1;
			end else if (idle_command_without_owner ||
			            premature_release ||
			            release_command) begin
				state_q <= StFault;
				terminal_fault_q <= 1'b1;
				protocol_error_o <= 1'b1;
			end else if (unowned_response) begin
				state_q <= StFault;
				terminal_fault_q <= 1'b1;
				unexpected_response_o <= 1'b1;
			end else if (timeout_expired) begin
				state_q <= StFault;
				terminal_fault_q <= 1'b1;
				timeout_o <= 1'b1;
			end else begin
				case (state_q)
					StIdle: begin
						if (identity_acquire ||
						    stream_acquire) begin
							owner_stream_q <=
								stream_acquire;
							state_q <= StActive;
						end
					end

					StActive: begin
						if (!selected_acquire)
							state_q <= StRelease;
					end

					StRelease: begin
						if (!save_granted_i &&
						    (response_beats_remaining_q ==
						     8'd0)) begin
							state_q <= StIdle;
						end
					end

					default: begin
						// Reset-only terminal.  The maintenance acquire and
						// command outputs remain deasserted while the
						// physical arbiter drains any accepted transaction.
						state_q <= StFault;
						terminal_fault_q <= 1'b1;
					end
				endcase
			end
		end
	end

endmodule

`default_nettype wire
