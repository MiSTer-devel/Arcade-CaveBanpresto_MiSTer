`default_nettype none

// CaveBanpresto-local save-state adapter for the existing MemSys
// EEPROM/NVRAM write-back-cache client.
//
// This module owns no EEPROM storage and adds no memory port.  Integration
// must route mem_* through CaveBanprestoMemSysNvramSaveState only while
// mem_takeover_o is asserted.  That MemSys-local adaptor owns the conversion
// between this exact byte image and the existing 16-bit cache client.
//
// Request/response contract:
// - owner 21 exposes exactly 128 logical 8-bit bytes;
// - query and bounds-only validate never touch the cache client;
// - read/write commands launch only with takeover permission;
// - mem_rd_o/mem_wr_o and their payload remain stable until mem_wait_n_i
//   accepts the request;
// - read data is consumed only when mem_valid_i is asserted, including a
//   response coincident with request acceptance;
// - a write is acknowledged only after mem_wait_n_i returns high with the
//   request strobe removed, which is the existing cache's idle indication;
// - an accepted operation is irrevocable.  Abort, permission loss, or request
//   abandonment poisons the transaction but retains takeover until the read
//   response or write-idle indication is drained;
// - a timed-out accepted operation remains in the drain state.  A late read
//   response or late write-idle indication is quarantined before rearm, so it
//   cannot be mistaken for a later save-state command.
//
// fatal_o and fatal_reason_o are sticky until reset.  The intended integrated
// controller treats any fatal condition as reset-only recovery.
module CaveBanprestoSaveStateNvramOwner #(
	parameter [7:0] OWNER_INDEX = 8'd21,
	parameter integer READ_TIMEOUT_CYCLES = 4096,
	parameter integer WRITE_IDLE_TIMEOUT_CYCLES = 4096
) (
	input  wire clk_i,
	input  wire reset_i,
	input  wire takeover_permitted_i,
	input  wire abort_i,

	output logic        mem_takeover_o,
	output logic        mem_rd_o,
	output logic        mem_wr_o,
	output logic  [6:0] mem_addr_o,
	output logic  [7:0] mem_din_o,
	input  wire   [7:0] mem_dout_i,
	input  wire         mem_wait_n_i,
	input  wire         mem_valid_i,

	output wire       busy_o,
	output wire       draining_o,
	output wire       poisoned_o,
	output logic      timeout_o,
	output logic      fatal_o,
	output logic [1:0] fatal_reason_o,

	cavebanpresto_ssbus_if.responder ssbus
);

	localparam [31:0] LOGICAL_BYTE_COUNT = 32'd128;
	localparam [1:0] WIDTH_CODE_8 = 2'd0;

	localparam [1:0] FATAL_NONE = 2'd0;
	localparam [1:0] FATAL_READ_TIMEOUT = 2'd1;
	localparam [1:0] FATAL_WRITE_IDLE_TIMEOUT = 2'd2;
	localparam [1:0] FATAL_INTERNAL_STATE = 2'd3;

	localparam integer MAX_RESPONSE_TIMEOUT_CYCLES =
		(READ_TIMEOUT_CYCLES > WRITE_IDLE_TIMEOUT_CYCLES) ?
			READ_TIMEOUT_CYCLES : WRITE_IDLE_TIMEOUT_CYCLES;
	localparam integer WATCHDOG_WIDTH =
		(MAX_RESPONSE_TIMEOUT_CYCLES <= 1) ?
			1 : $clog2(MAX_RESPONSE_TIMEOUT_CYCLES);
	localparam PARAMETERS_VALID =
		(READ_TIMEOUT_CYCLES > 0) &
		(WRITE_IDLE_TIMEOUT_CYCLES > 0);

	typedef enum logic [2:0] {
		StIdle         = 3'd0,
		StLaunch       = 3'd1,
		StReadDrain    = 3'd2,
		StWriteDrain   = 3'd3,
		StWaitRelease  = 3'd4
	} state_e;

	state_e state_q;

	// Justification (reg-a): the cache request must remain stable across
	// arbitrary mem_wait_n_i back-pressure and throughout accepted-operation
	// drain/quarantine.
	logic [63:0] held_req_data_q;
	logic [31:0] held_req_addr_q;
	logic  [7:0] held_req_select_q;
	logic  [3:0] held_req_command_q;

	// Justification (reg-a): bounds each accepted response/idle wait and
	// records whether an accepted transaction has become unsafe to commit.
	logic [WATCHDOG_WIDTH-1:0] watchdog_count_q;
	logic                      watchdog_expired_q;
	logic                      poisoned_q;

	logic [3:0] request_command;
	logic       request_active;
	logic       request_selected;
	logic       request_command_legal;
	logic       request_payload;
	logic       address_valid;
	logic       request_matches_held;
	logic       held_is_read;
	logic       held_is_write;
	logic       launch_allowed;
	logic       read_accepted;
	logic       write_accepted;
	logic       accepted_operation;
	logic       drain_cancelled_now;
	logic [63:0] read_response_data;
	logic       read_timeout_reached;
	logic       write_timeout_reached;

	assign request_command = {
		ssbus.req_query,
		ssbus.req_validate,
		ssbus.req_write,
		ssbus.req_read
	};
	assign request_active = |request_command;
	assign request_selected =
		(ssbus.req_select == OWNER_INDEX) & request_active;
	assign request_command_legal =
		(request_command == 4'b0001) |
		(request_command == 4'b0010) |
		(request_command == 4'b0100) |
		(request_command == 4'b1000);
	assign request_payload =
		(request_command == 4'b0001) |
		(request_command == 4'b0010);
	assign address_valid = ssbus.req_addr < LOGICAL_BYTE_COUNT;

	assign request_matches_held =
		request_active &
		(ssbus.req_data == held_req_data_q) &
		(ssbus.req_addr == held_req_addr_q) &
		(ssbus.req_select == held_req_select_q) &
		(request_command == held_req_command_q);
	assign held_is_read = held_req_command_q == 4'b0001;
	assign held_is_write = held_req_command_q == 4'b0010;

	assign launch_allowed =
		request_matches_held &
		takeover_permitted_i &
		~abort_i;
	assign read_accepted = mem_rd_o & mem_wait_n_i;
	assign write_accepted = mem_wr_o & mem_wait_n_i;
	assign accepted_operation = read_accepted | write_accepted;
	assign drain_cancelled_now =
		~request_matches_held |
		~takeover_permitted_i |
		abort_i;

	always_comb begin
		read_response_data = 64'd0;
		read_response_data[7:0] = mem_dout_i;
	end

	assign read_timeout_reached =
		(READ_TIMEOUT_CYCLES <= 1) |
		(watchdog_count_q == READ_TIMEOUT_CYCLES - 1);
	assign write_timeout_reached =
		(WRITE_IDLE_TIMEOUT_CYCLES <= 1) |
		(watchdog_count_q == WRITE_IDLE_TIMEOUT_CYCLES - 1);

	assign busy_o = state_q != StIdle;
	assign draining_o =
		(state_q == StReadDrain) |
		(state_q == StWriteDrain);
	assign poisoned_o = poisoned_q;

	// Combinational request controls are sampled by the existing cache client
	// on clk_i.  Once accepted, takeover remains asserted without depending on
	// permission or the original bus command so a late response can be drained.
	always_comb begin
		mem_takeover_o = 1'b0;
		mem_rd_o = 1'b0;
		mem_wr_o = 1'b0;
		mem_addr_o = 7'd0;
		mem_din_o = 8'd0;

		if (!reset_i) begin
			case (state_q)
				StIdle: begin
					if (PARAMETERS_VALID &&
					    request_selected &&
					    request_command_legal &&
					    request_payload &&
					    address_valid &&
					    takeover_permitted_i &&
					    ~abort_i &&
					    ~fatal_o) begin
						mem_takeover_o = 1'b1;
						mem_rd_o = ssbus.req_read;
						mem_wr_o = ssbus.req_write;
						mem_addr_o =
							ssbus.req_addr[6:0];
						mem_din_o =
							ssbus.req_data[7:0];
					end
				end

				StLaunch: begin
					if (launch_allowed) begin
						mem_takeover_o = 1'b1;
						mem_rd_o = held_is_read;
						mem_wr_o = held_is_write;
						mem_addr_o =
							held_req_addr_q[6:0];
						mem_din_o =
							held_req_data_q[7:0];
					end
				end

				StReadDrain,
				StWriteDrain: begin
					mem_takeover_o = 1'b1;
					mem_addr_o =
						held_req_addr_q[6:0];
					mem_din_o =
						held_req_data_q[7:0];
				end

				default: begin
					mem_takeover_o = 1'b0;
					mem_rd_o = 1'b0;
					mem_wr_o = 1'b0;
					mem_addr_o = 7'd0;
					mem_din_o = 8'd0;
				end
			endcase
		end
	end

	always_ff @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= StIdle;
			held_req_data_q <= 64'd0;
			held_req_addr_q <= 32'd0;
			held_req_select_q <= 8'd0;
			held_req_command_q <= 4'd0;
			watchdog_count_q <= {WATCHDOG_WIDTH{1'b0}};
			watchdog_expired_q <= 1'b0;
			poisoned_q <= 1'b0;
			timeout_o <= 1'b0;
			fatal_o <= 1'b0;
			fatal_reason_o <= FATAL_NONE;
			ssbus.rsp_data <= 64'd0;
			ssbus.rsp_ack <= 1'b0;
			ssbus.rsp_error <= 1'b0;
		end else begin
			// All bus responses and timeout indications are one-cycle pulses.
			ssbus.rsp_data <= 64'd0;
			ssbus.rsp_ack <= 1'b0;
			ssbus.rsp_error <= 1'b0;
			timeout_o <= 1'b0;

			case (state_q)
				StIdle: begin
					watchdog_count_q <=
						{WATCHDOG_WIDTH{1'b0}};
					watchdog_expired_q <= 1'b0;
					poisoned_q <= 1'b0;

					if (request_selected) begin
						if (!PARAMETERS_VALID ||
						    !request_command_legal) begin
							ssbus.rsp_ack <= 1'b1;
							ssbus.rsp_error <= 1'b1;
							state_q <= StWaitRelease;
						end else if (ssbus.req_query) begin
							ssbus.rsp_data <=
								ssbus.query_descriptor(
									OWNER_INDEX,
									LOGICAL_BYTE_COUNT,
									WIDTH_CODE_8
								);
							ssbus.rsp_ack <= 1'b1;
							state_q <= StWaitRelease;
						end else if (ssbus.req_validate) begin
							ssbus.rsp_ack <= 1'b1;
							ssbus.rsp_error <=
								~address_valid;
							state_q <= StWaitRelease;
						end else if (!address_valid ||
						             !takeover_permitted_i ||
						             abort_i ||
						             fatal_o) begin
							ssbus.rsp_ack <= 1'b1;
							ssbus.rsp_error <= 1'b1;
							poisoned_q <=
								abort_i | fatal_o;
							state_q <= StWaitRelease;
						end else begin
							held_req_data_q <=
								ssbus.req_data;
							held_req_addr_q <=
								ssbus.req_addr;
							held_req_select_q <=
								ssbus.req_select;
							held_req_command_q <=
								request_command;

							if (accepted_operation) begin
								if (ssbus.req_read) begin
									if (mem_valid_i) begin
										ssbus.rsp_data <=
											read_response_data;
										ssbus.rsp_ack <=
											1'b1;
										state_q <=
											StWaitRelease;
									end else begin
										state_q <=
											StReadDrain;
									end
								end else begin
									state_q <=
										StWriteDrain;
								end
							end else begin
								state_q <= StLaunch;
							end
						end
					end
				end

				StLaunch: begin
					if (!launch_allowed) begin
						poisoned_q <= 1'b1;
						if (request_matches_held) begin
							ssbus.rsp_ack <= 1'b1;
							ssbus.rsp_error <= 1'b1;
						end
						watchdog_count_q <=
							{WATCHDOG_WIDTH{1'b0}};
						state_q <= StWaitRelease;
					end else if (accepted_operation) begin
						watchdog_count_q <=
							{WATCHDOG_WIDTH{1'b0}};
						if (held_is_read) begin
							if (mem_valid_i) begin
								ssbus.rsp_data <=
									read_response_data;
								ssbus.rsp_ack <= 1'b1;
								state_q <=
									StWaitRelease;
							end else begin
								state_q <=
									StReadDrain;
							end
						end else begin
							state_q <= StWriteDrain;
						end
					end
				end

				StReadDrain: begin
					if (drain_cancelled_now)
						poisoned_q <= 1'b1;

					if (mem_valid_i) begin
						if (request_matches_held) begin
							ssbus.rsp_ack <= 1'b1;
							if (poisoned_q |
							    drain_cancelled_now |
							    watchdog_expired_q) begin
								ssbus.rsp_error <=
									1'b1;
							end else begin
								ssbus.rsp_data <=
									read_response_data;
							end
						end
						watchdog_count_q <=
							{WATCHDOG_WIDTH{1'b0}};
						state_q <= StWaitRelease;
					end else if (!watchdog_expired_q) begin
						if (read_timeout_reached) begin
							watchdog_expired_q <=
								1'b1;
							poisoned_q <= 1'b1;
							timeout_o <= 1'b1;
							fatal_o <= 1'b1;
							if (!fatal_o)
								fatal_reason_o <=
									FATAL_READ_TIMEOUT;
						end else begin
							watchdog_count_q <=
								watchdog_count_q +
								1'b1;
						end
					end
				end

				StWriteDrain: begin
					if (drain_cancelled_now)
						poisoned_q <= 1'b1;

					// With mem_rd_o/mem_wr_o low, wait_n high is the
					// existing write-back cache's idle indication.
					if (mem_wait_n_i) begin
						if (request_matches_held) begin
							ssbus.rsp_ack <= 1'b1;
							ssbus.rsp_error <=
								poisoned_q |
								drain_cancelled_now |
								watchdog_expired_q;
						end
						watchdog_count_q <=
							{WATCHDOG_WIDTH{1'b0}};
						state_q <= StWaitRelease;
					end else if (!watchdog_expired_q) begin
						if (write_timeout_reached) begin
							watchdog_expired_q <=
								1'b1;
							poisoned_q <= 1'b1;
							timeout_o <= 1'b1;
							fatal_o <= 1'b1;
							if (!fatal_o)
								fatal_reason_o <=
									FATAL_WRITE_IDLE_TIMEOUT;
						end else begin
							watchdog_count_q <=
								watchdog_count_q +
								1'b1;
						end
					end
				end

				StWaitRelease: begin
					watchdog_count_q <=
						{WATCHDOG_WIDTH{1'b0}};
					if (!ssbus.command_active()) begin
						watchdog_expired_q <= 1'b0;
						poisoned_q <= 1'b0;
						state_q <= StIdle;
					end
				end

				default: begin
					state_q <= StIdle;
					watchdog_count_q <=
						{WATCHDOG_WIDTH{1'b0}};
					watchdog_expired_q <= 1'b0;
					poisoned_q <= 1'b1;
					fatal_o <= 1'b1;
					if (!fatal_o)
						fatal_reason_o <=
							FATAL_INTERNAL_STATE;
				end
			endcase
		end
	end

endmodule

`default_nettype wire
