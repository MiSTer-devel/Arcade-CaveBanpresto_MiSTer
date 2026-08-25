`default_nettype none

// MemSys-local maintenance adaptor for owner 21.
//
// The EEPROM image lives behind CaveNvramWriteBackCache; this block does not
// add a shadow copy.  A save-state session first sweeps one address from every
// cache line.  For either set, the sweep visits tags 0 through 7 in order.
// Across eight distinct tags, a two-way set cannot retain either entry that
// existed before the sweep: later misses evict every preexisting dirty entry,
// while any line installed by the sweep is clean.  A local cache reset then
// invalidates both ways and prevents a stale line from surviving into the
// owner transaction.
//
// Owner 21 is byte-addressed while the existing cache client is 16-bit.  Reads
// select the requested byte lane.  Writes use an accepted read/modify/write
// sequence through the same cache port.  The final byte (address 127) does not
// return the cache to idle until a second full sweep and local invalidation
// have committed every restored word to backing SDRAM.
//
// Integration contract:
// - session_active_i is asserted only after the normal NVRAM clients have
//   stopped launching requests, and remains asserted until owner_busy is low;
// - the owner receives takeover permission only while prepared_o is high;
// - normal client responses are never rerouted after an accepted request;
// - abort_i blocks new owner operations but accepted cache operations drain;
// - fatal_o is sticky until reset and must feed the global reset-only hold.
module CaveBanprestoMemSysNvramSaveState #(
	parameter integer TIMEOUT_CYCLES = 1_000_000
) (
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        enable_i,

	input  wire        normal_rd_i,
	input  wire        normal_wr_i,
	input  wire  [6:0] normal_addr_i,
	input  wire [15:0] normal_din_i,
	output wire [15:0] normal_dout_o,
	output wire        normal_wait_n_o,
	output wire        normal_valid_o,

	input  wire        session_active_i,
	input  wire        abort_i,
	input  wire        owner_rd_i,
	input  wire        owner_wr_i,
	input  wire  [6:0] owner_addr_i,
	input  wire  [7:0] owner_din_i,
	output wire  [7:0] owner_dout_o,
	output wire        owner_wait_n_o,
	output wire        owner_valid_o,

	output wire        prepared_o,
	output wire        busy_o,
	output logic       flush_done_o,
	output logic       timeout_o,
	output logic       fatal_o,
	output logic [2:0] fatal_reason_o,

	output logic       cache_reset_o,
	output logic       cache_rd_o,
	output logic       cache_wr_o,
	output logic [6:0] cache_addr_o,
	output logic [15:0] cache_din_o,
	input  wire [15:0] cache_dout_i,
	input  wire        cache_wait_n_i,
	input  wire        cache_valid_i
);

	localparam [2:0] FATAL_NONE = 3'd0;
	localparam [2:0] FATAL_FLUSH_REQUEST = 3'd1;
	localparam [2:0] FATAL_FLUSH_RESPONSE = 3'd2;
	localparam [2:0] FATAL_INVALIDATE = 3'd3;
	localparam [2:0] FATAL_OWNER_READ = 3'd4;
	localparam [2:0] FATAL_OWNER_RMW_READ = 3'd5;
	localparam [2:0] FATAL_OWNER_WRITE = 3'd6;
	localparam [2:0] FATAL_PROTOCOL = 3'd7;

	localparam integer WATCHDOG_WIDTH =
		(TIMEOUT_CYCLES <= 1) ? 1 : $clog2(TIMEOUT_CYCLES);
	localparam PARAMETERS_VALID = TIMEOUT_CYCLES > 0;

	typedef enum logic [3:0] {
		StNormal          = 4'd0,
		StFlushLaunch     = 4'd1,
		StFlushWait       = 4'd2,
		StFlushDrain      = 4'd3,
		StInvalidatePulse = 4'd4,
		StInvalidateWait  = 4'd5,
		StReady           = 4'd6,
		StReadLaunch      = 4'd7,
		StReadWait        = 4'd8,
		StReadDrain       = 4'd9,
		StWriteReadLaunch = 4'd10,
		StWriteReadWait   = 4'd11,
		StWriteReadDrain  = 4'd12,
		StWriteLaunch     = 4'd13,
		StWriteDrain      = 4'd14
	} state_e;

	state_e state_q;

	// Justification (reg-a): the line sweep, byte operation, and final-flush
	// identity must remain stable across arbitrary cache back-pressure.
	logic  [3:0] flush_line_q;
	logic  [6:0] owner_addr_q;
	logic  [7:0] owner_din_q;
	logic  [7:0] owner_dout_q;
	logic [15:0] merged_word_q;
	logic        prepared_q;

	// Justification (reg-a): bounds every externally acknowledged cache wait.
	logic [WATCHDOG_WIDTH-1:0] watchdog_q;

	logic owner_valid_q;
	logic progress_now;
	logic watchdog_reached;
	logic [2:0] wait_reason;

	wire normal_passthrough = state_q == StNormal;
	wire owner_accept_window =
		(state_q == StReady) &
		session_active_i &
		prepared_q &
		~abort_i &
		~fatal_o &
		enable_i;
	wire owner_request = owner_rd_i | owner_wr_i;
	wire owner_request_legal = owner_rd_i ^ owner_wr_i;
	wire flush_last_line = flush_line_q == 4'd15;
	wire cache_operation_idle = cache_wait_n_i;

	assign normal_dout_o = cache_dout_i;
	assign normal_wait_n_o =
		normal_passthrough ? cache_wait_n_i : 1'b0;
	assign normal_valid_o =
		normal_passthrough ? cache_valid_i : 1'b0;

	assign owner_dout_o = owner_dout_q;
	// Ready is also the accepted-write drain indication.  Keep it observable
	// after abort/permission loss so an irrevocable operation can retire; the
	// owner itself suppresses new request strobes when permission is absent.
	assign owner_wait_n_o =
		enable_i & (state_q == StReady);
	assign owner_valid_o = owner_valid_q;

	assign prepared_o =
		session_active_i &
		prepared_q &
		~abort_i &
		~fatal_o;
	assign busy_o =
		(state_q != StNormal) &
		(state_q != StReady);

	assign watchdog_reached =
		(TIMEOUT_CYCLES <= 1) |
		(watchdog_q == TIMEOUT_CYCLES - 1);

	always_comb begin
		cache_reset_o = 1'b0;
		cache_rd_o = 1'b0;
		cache_wr_o = 1'b0;
		cache_addr_o = 7'd0;
		cache_din_o = 16'd0;

		case (state_q)
			StNormal: begin
				cache_rd_o = normal_rd_i;
				cache_wr_o = normal_wr_i;
				cache_addr_o = normal_addr_i;
				cache_din_o = normal_din_i;
			end

			StFlushLaunch: begin
				cache_rd_o = 1'b1;
				cache_addr_o = {flush_line_q, 3'b000};
			end

			StReadLaunch,
			StWriteReadLaunch: begin
				cache_rd_o = 1'b1;
				cache_addr_o = {
					owner_addr_q[6:1],
					1'b0
				};
			end

			StWriteLaunch: begin
				cache_wr_o = 1'b1;
				cache_addr_o = {
					owner_addr_q[6:1],
					1'b0
				};
				cache_din_o = merged_word_q;
			end

			StInvalidatePulse: begin
				cache_reset_o = 1'b1;
			end

			default: begin
				cache_reset_o = 1'b0;
				cache_rd_o = 1'b0;
				cache_wr_o = 1'b0;
				cache_addr_o = 7'd0;
				cache_din_o = 16'd0;
			end
		endcase
	end

	always_comb begin
		progress_now = 1'b0;
		wait_reason = FATAL_PROTOCOL;

		case (state_q)
			StFlushLaunch: begin
				progress_now = cache_wait_n_i;
				wait_reason = FATAL_FLUSH_REQUEST;
			end
			StFlushWait: begin
				progress_now = cache_valid_i;
				wait_reason = FATAL_FLUSH_RESPONSE;
			end
			StFlushDrain: begin
				progress_now = cache_operation_idle;
				wait_reason = FATAL_FLUSH_RESPONSE;
			end
			StInvalidateWait: begin
				progress_now = cache_operation_idle;
				wait_reason = FATAL_INVALIDATE;
			end
			StReadLaunch: begin
				progress_now = cache_wait_n_i;
				wait_reason = FATAL_OWNER_READ;
			end
			StReadWait: begin
				progress_now = cache_valid_i;
				wait_reason = FATAL_OWNER_READ;
			end
			StReadDrain: begin
				progress_now = cache_operation_idle;
				wait_reason = FATAL_OWNER_READ;
			end
			StWriteReadLaunch: begin
				progress_now = cache_wait_n_i;
				wait_reason = FATAL_OWNER_RMW_READ;
			end
			StWriteReadWait: begin
				progress_now = cache_valid_i;
				wait_reason = FATAL_OWNER_RMW_READ;
			end
			StWriteReadDrain: begin
				progress_now = cache_operation_idle;
				wait_reason = FATAL_OWNER_RMW_READ;
			end
			StWriteLaunch: begin
				progress_now = cache_wait_n_i;
				wait_reason = FATAL_OWNER_WRITE;
			end
			StWriteDrain: begin
				progress_now = cache_operation_idle;
				wait_reason = FATAL_OWNER_WRITE;
			end
			default: begin
				progress_now = 1'b1;
				wait_reason = FATAL_NONE;
			end
		endcase
	end

	always_ff @(posedge clk_i) begin
		if (reset_i) begin
			state_q <= StNormal;
			flush_line_q <= 4'd0;
			owner_addr_q <= 7'd0;
			owner_din_q <= 8'd0;
			owner_dout_q <= 8'd0;
			merged_word_q <= 16'd0;
			prepared_q <= 1'b0;
			owner_valid_q <= 1'b0;
			watchdog_q <= {WATCHDOG_WIDTH{1'b0}};
			flush_done_o <= 1'b0;
			timeout_o <= 1'b0;
			fatal_o <= 1'b0;
			fatal_reason_o <= FATAL_NONE;
		end else begin
			owner_valid_q <= 1'b0;
			flush_done_o <= 1'b0;
			timeout_o <= 1'b0;

			if ((state_q == StNormal) ||
			    (state_q == StReady) ||
			    (state_q == StInvalidatePulse) ||
			    progress_now) begin
				watchdog_q <= {WATCHDOG_WIDTH{1'b0}};
			end else if (!fatal_o) begin
				if (!PARAMETERS_VALID || watchdog_reached) begin
					timeout_o <= 1'b1;
					fatal_o <= 1'b1;
					fatal_reason_o <= wait_reason;
				end else begin
					watchdog_q <= watchdog_q + 1'b1;
				end
			end

			case (state_q)
				StNormal: begin
					flush_line_q <= 4'd0;
					prepared_q <= 1'b0;

					// Do not strand a normal response.  The integration
					// contract stops new normal launches first; this
					// additionally observes a fully idle cache/client edge.
					if (session_active_i &&
					    !normal_rd_i &&
					    !normal_wr_i &&
					    cache_operation_idle) begin
						state_q <= StFlushLaunch;
					end
				end

				StFlushLaunch: begin
					if (cache_wait_n_i)
						state_q <= StFlushWait;
				end

				StFlushWait: begin
					if (cache_valid_i) begin
						if (cache_operation_idle) begin
							if (flush_last_line)
								state_q <=
									StInvalidatePulse;
							else begin
								flush_line_q <=
									flush_line_q +
									1'b1;
								state_q <=
									StFlushLaunch;
							end
						end else begin
							state_q <= StFlushDrain;
						end
					end
				end

				StFlushDrain: begin
					if (cache_operation_idle) begin
						if (flush_last_line)
							state_q <=
								StInvalidatePulse;
						else begin
							flush_line_q <=
								flush_line_q +
								1'b1;
							state_q <=
								StFlushLaunch;
						end
					end
				end

				StInvalidatePulse: begin
					state_q <= StInvalidateWait;
				end

				StInvalidateWait: begin
					if (cache_operation_idle) begin
						flush_done_o <= 1'b1;
						flush_line_q <= 4'd0;
						prepared_q <= 1'b1;
						state_q <= StReady;
					end
				end

				StReady: begin
					if (!session_active_i) begin
						state_q <= StNormal;
					end else if (owner_request &&
					             !owner_request_legal) begin
						if (!fatal_o) begin
							fatal_o <= 1'b1;
							fatal_reason_o <=
								FATAL_PROTOCOL;
						end
					end else if (owner_accept_window &&
					             owner_request_legal) begin
						owner_addr_q <= owner_addr_i;
						owner_din_q <= owner_din_i;
						if (owner_rd_i)
							state_q <= StReadLaunch;
						else
							state_q <=
								StWriteReadLaunch;
					end
				end

				StReadLaunch: begin
					if (cache_wait_n_i)
						state_q <= StReadWait;
				end

				StReadWait: begin
					if (cache_valid_i) begin
						owner_dout_q <= owner_addr_q[0]
							? cache_dout_i[15:8]
							: cache_dout_i[7:0];
						owner_valid_q <= 1'b1;
						state_q <= cache_operation_idle
							? StReady
							: StReadDrain;
					end
				end

				StReadDrain: begin
					if (cache_operation_idle)
						state_q <= StReady;
				end

				StWriteReadLaunch: begin
					if (cache_wait_n_i)
						state_q <= StWriteReadWait;
				end

				StWriteReadWait: begin
					if (cache_valid_i) begin
						merged_word_q <= owner_addr_q[0]
							? {
								owner_din_q,
								cache_dout_i[7:0]
							}
							: {
								cache_dout_i[15:8],
								owner_din_q
							};
						state_q <= cache_operation_idle
							? StWriteLaunch
							: StWriteReadDrain;
					end
				end

				StWriteReadDrain: begin
					if (cache_operation_idle)
						state_q <= StWriteLaunch;
				end

				StWriteLaunch: begin
					if (cache_wait_n_i)
						state_q <= StWriteDrain;
				end

				StWriteDrain: begin
					if (cache_operation_idle) begin
						if (owner_addr_q == 7'd127) begin
							flush_line_q <= 4'd0;
							state_q <= StFlushLaunch;
						end else begin
							state_q <= StReady;
						end
					end
				end

				default: begin
					state_q <= StNormal;
					if (!fatal_o) begin
						fatal_o <= 1'b1;
						fatal_reason_o <= FATAL_PROTOCOL;
					end
				end
			endcase
		end
	end

endmodule

`default_nettype wire
