`default_nettype none

// CaveBanpresto-local exact-state IKAOPM/YM2151 wrapper.
//
// Owner 27 contains the complete IKAOPM implementation state and only the
// state local to the production YM2151 wrapper: the write stretcher and the
// CaveClockEnable phase. Sound.ym2151AudioReg is a downstream sample-and-hold
// register and remains solely in owner 25.
//
// State ABI:
//   owner index:        27
//   element width:      32 bits (width code 2)
//   IKAOPM elements:    158
//   wrapper element:    158
//   reserved element:   159 (must be zero)
//   total elements:     160
//   serialized payload: 80 x 64-bit words
module CaveBanprestoYM2151SaveState #(
	parameter [7:0] OWNER_INDEX = 8'd27,
	parameter integer WRITE_HOLD_CYCLES = 16
) (
	input  wire        clock,
	input  wire        reset,
	input  wire        io_cpu_wr,
	input  wire        io_cpu_addr,
	input  wire  [7:0] io_cpu_din,
	output wire  [7:0] io_cpu_dout,
	output wire        io_irq,
	output wire        io_audio_valid,
	output wire [15:0] io_audio_bits,

	input  wire        io_ss_hold_i,
	input  wire        io_ss_restore_enable_i,
	output wire        io_ss_idle_o,
	cavebanpresto_ssbus_if.responder io_ssbus
);

	localparam [16:0] CLOCK_ENABLE_STEP = 17'h2000;
	localparam integer WRITE_HOLD_RELOAD =
		WRITE_HOLD_CYCLES <= 1 ? 0 :
		WRITE_HOLD_CYCLES > 16 ? 15 :
		WRITE_HOLD_CYCLES - 1;

	// Justification (reg-a): exact phase of the production CaveClockEnable.
	// Initial values model the Cyclone-V power-up state. Reset deliberately
	// does not alter these registers because CaveClockEnable has no reset.
	logic [15:0] scheduler_accumulator_q = 16'd0;
	logic        scheduler_enable_q = 1'b0;

	// Justification (reg-a): exact production host-write stretch state.
	logic [3:0] write_hold_q;
	logic       write_addr_q;
	logic [7:0] write_data_q;

	// Justification (reg-d): establishes that every generated core block has
	// observed hold before the owner accepts state reads or writes.
	logic [2:0] hold_stable_count_q;

	logic        wrapper_restore_wr;
	logic [31:0] wrapper_restore_data;

	logic        core_ss_req;
	logic        core_ss_write;
	wire  [7:0]  core_ss_word_addr;
	wire  [31:0] core_ss_wdata;
	wire  [31:0] core_ss_valid_mask;
	wire         core_ss_ack;
	wire         core_ss_error;
	wire  [31:0] core_ss_rdata;

	wire [16:0] scheduler_next =
		{1'b0, scheduler_accumulator_q} + CLOCK_ENABLE_STEP;
	wire scheduler_cen = scheduler_enable_q & ~io_ss_hold_i;
	wire stretched_write =
		io_cpu_wr | (write_hold_q != 4'd0);
	wire core_cpu_write = stretched_write & ~io_ss_hold_i;
	wire core_cpu_addr = io_cpu_wr ? io_cpu_addr : write_addr_q;
	wire [7:0] core_cpu_data = io_cpu_wr ? io_cpu_din : write_data_q;
	wire core_irq_n;
	wire core_sample;
	wire signed [15:0] core_left;
	wire signed [15:0] core_right;
	wire signed [16:0] core_mono_sum =
		{core_left[15], core_left} +
		{core_right[15], core_right};

	// Bits 31:30 are reserved and must remain zero.
	wire [31:0] wrapper_state_word = {
		2'd0,
		write_data_q,
		write_addr_q,
		write_hold_q,
		scheduler_enable_q,
		scheduler_accumulator_q
	};

	always_ff @(posedge clock) begin
		if (wrapper_restore_wr) begin
			scheduler_accumulator_q <= wrapper_restore_data[15:0];
			scheduler_enable_q <= wrapper_restore_data[16];
		end else if (!io_ss_hold_i) begin
			scheduler_accumulator_q <= scheduler_next[15:0];
			scheduler_enable_q <= scheduler_next[16];
		end
	end

	always_ff @(posedge clock) begin
		if (reset) begin
			write_hold_q <= 4'd0;
			write_addr_q <= 1'b0;
			write_data_q <= 8'd0;
		end else if (wrapper_restore_wr) begin
			write_hold_q <= wrapper_restore_data[20:17];
			write_addr_q <= wrapper_restore_data[21];
			write_data_q <= wrapper_restore_data[29:22];
		end else if (!io_ss_hold_i) begin
			if (io_cpu_wr) begin
				write_hold_q <= WRITE_HOLD_RELOAD[3:0];
				write_addr_q <= io_cpu_addr;
				write_data_q <= io_cpu_din;
			end else if (write_hold_q != 4'd0) begin
				write_hold_q <= write_hold_q - 4'd1;
			end
		end
	end

	always_ff @(posedge clock) begin
		if (reset || !io_ss_hold_i) begin
			hold_stable_count_q <= 3'd0;
		end else if (!(&hold_stable_count_q)) begin
			hold_stable_count_q <= hold_stable_count_q + 3'd1;
		end
	end

	CaveBanprestoIKAOPMExact #(
		.FULLY_SYNCHRONOUS(1),
		.FAST_RESET(1),
		.USE_BRAM(1)
	) exact_core (
		.i_EMUCLK(clock),
		.i_phiM_PCEN_n(~scheduler_cen),
		.i_IC_n(~reset),
		.o_phi1(),
		.i_CS_n(1'b0),
		.i_RD_n(core_cpu_write),
		.i_WR_n(~core_cpu_write),
		.i_A0(core_cpu_addr),
		.i_D(core_cpu_data),
		.o_D(io_cpu_dout),
		.o_D_OE(),
		.o_CT2(),
		.o_CT1(),
		.o_IRQ_n(core_irq_n),
		.o_SH1(),
		.o_SH2(),
		.o_SO(),
		.o_EMU_R_SAMPLE(),
		.o_EMU_R_EX(),
		.o_EMU_R(core_right),
		.o_EMU_L_SAMPLE(core_sample),
		.o_EMU_L_EX(),
		.o_EMU_L(core_left),
		.i_SS_HOLD(io_ss_hold_i),
		.i_SS_REQ(core_ss_req),
		.i_SS_WRITE(core_ss_write),
		.i_SS_WORD_ADDR(core_ss_word_addr),
		.i_SS_WDATA(core_ss_wdata),
		.o_SS_VALID_MASK(core_ss_valid_mask),
		.o_SS_ACK(core_ss_ack),
		.o_SS_ERROR(core_ss_error),
		.o_SS_RDATA(core_ss_rdata)
	);

	CaveBanprestoYM2151StatePort #(
		.OWNER_INDEX(OWNER_INDEX)
	) state_port (
		.clock(clock),
		.reset(reset),
		.state_enable(io_ss_idle_o),
		.restore_enable(io_ss_restore_enable_i),
		.wrapper_state_word(wrapper_state_word),
		.wrapper_restore_wr(wrapper_restore_wr),
		.wrapper_restore_data(wrapper_restore_data),
		.core_ss_req(core_ss_req),
		.core_ss_write(core_ss_write),
		.core_ss_word_addr(core_ss_word_addr),
		.core_ss_wdata(core_ss_wdata),
		.core_ss_valid_mask(core_ss_valid_mask),
		.core_ss_ack(core_ss_ack),
		.core_ss_error(core_ss_error),
		.core_ss_rdata(core_ss_rdata),
		.ssbus(io_ssbus)
	);

	assign io_irq = ~core_irq_n;
	assign io_audio_valid = core_sample;
	assign io_audio_bits = core_mono_sum[16:1];
	assign io_ss_idle_o = io_ss_hold_i & (&hold_stable_count_q);

endmodule

module CaveBanprestoYM2151StatePort #(
	parameter [7:0] OWNER_INDEX = 8'd27
) (
	input  wire        clock,
	input  wire        reset,
	input  wire        state_enable,
	input  wire        restore_enable,
	input  wire [31:0] wrapper_state_word,
	output logic       wrapper_restore_wr,
	output logic [31:0] wrapper_restore_data,

	output logic        core_ss_req,
	output logic        core_ss_write,
	output wire  [7:0]  core_ss_word_addr,
	output wire  [31:0] core_ss_wdata,
	input  wire  [31:0] core_ss_valid_mask,
	input  wire         core_ss_ack,
	input  wire         core_ss_error,
	input  wire  [31:0] core_ss_rdata,

	cavebanpresto_ssbus_if.responder ssbus
);

	localparam [31:0] CORE_WORD_COUNT = 32'd158;
	localparam [31:0] WRAPPER_WORD = 32'd158;
	localparam [31:0] RESERVED_WORD = 32'd159;
	localparam [31:0] WORD_COUNT = 32'd160;
	localparam [1:0] WIDTH_CODE_32 = 2'd2;

	typedef enum logic [2:0] {
		StIdle          = 3'd0,
		StCoreWait      = 3'd2,
		StWrapperWrite  = 3'd4,
		StWaitRelease   = 3'd5
	} state_e;

	// Justification (reg-a): protocol state and one admitted 32-bit core word
	// remain stable until its endpoint acknowledges the complete transaction.
	state_e state_q;
	logic [31:0] request_addr_q;
	logic [63:0] request_data_q;
	logic        request_read_q;
	logic        request_fault_q;

	// Justification (reg-d): a complete RAM-plane word takes fewer than
	// 40 clocks; seven bits retain a conservative endpoint-fault bound.
	logic [6:0] scan_watchdog_q;

	logic [3:0] request_command;
	logic       request_selected;
	logic       request_command_legal;
	logic       address_valid;
	logic       restore_structure_valid;
	logic       request_matches;
	logic       core_authorized;
	logic       core_mask_known;
	logic       core_padding_valid;
	logic       core_has_live_bits;

	function automatic logic restore_word_valid(
		input logic [31:0] address,
		input logic [63:0] data
	);
		logic data_known;
		begin
			data_known = (^data !== 1'bx);
			if (!data_known || (data[63:32] != 32'd0)) begin
				restore_word_valid = 1'b0;
			end else if (address == WRAPPER_WORD) begin
				restore_word_valid =
					data[31:30] == 2'd0;
			end else if (address == RESERVED_WORD) begin
				restore_word_valid =
					data[31:0] == 32'd0;
			end else begin
				restore_word_valid = 1'b1;
			end
		end
	endfunction

	assign request_command = {
		ssbus.req_query,
		ssbus.req_validate,
		ssbus.req_write,
		ssbus.req_read
	};
	assign request_selected =
		(ssbus.req_select === OWNER_INDEX) &&
		(request_command !== 4'b0000);
	assign request_command_legal =
		(request_command === 4'b0001) ||
		(request_command === 4'b0010) ||
		(request_command === 4'b0100) ||
		(request_command === 4'b1000);
	assign address_valid = ssbus.req_addr < WORD_COUNT;
	assign restore_structure_valid =
		restore_word_valid(ssbus.req_addr, ssbus.req_data);
	assign request_matches =
		(ssbus.req_select === OWNER_INDEX) &&
		(request_command ===
		 (request_read_q ? 4'b0001 : 4'b0010)) &&
		(ssbus.req_addr === request_addr_q) &&
		(ssbus.req_data === request_data_q);
	assign core_authorized =
		(state_enable === 1'b1) &&
		(request_read_q || (restore_enable === 1'b1));
	assign core_mask_known =
		^core_ss_valid_mask !== 1'bx;
	assign core_padding_valid =
		core_mask_known &&
		((ssbus.req_data[31:0] & ~core_ss_valid_mask) === 32'd0);
	assign core_has_live_bits = |core_ss_valid_mask;

	// In idle, the mask is a pure static decode of the presented bus address.
	// Once admitted, the word address and payload come only from request_q.
	assign core_ss_word_addr =
		(state_q == StIdle) ?
		ssbus.req_addr[7:0] :
		request_addr_q[7:0];
	assign core_ss_wdata =
		(state_q == StIdle) ?
		ssbus.req_data[31:0] :
		request_data_q[31:0];

	always_ff @(posedge clock) begin
		if (reset) begin
			state_q <= StIdle;
			request_addr_q <= 32'd0;
			request_data_q <= 64'd0;
			request_read_q <= 1'b0;
			request_fault_q <= 1'b0;
			scan_watchdog_q <= 7'd0;
			wrapper_restore_wr <= 1'b0;
			wrapper_restore_data <= 32'd0;
			core_ss_req <= 1'b0;
			core_ss_write <= 1'b0;
			ssbus.rsp_data <= 64'd0;
			ssbus.rsp_ack <= 1'b0;
			ssbus.rsp_error <= 1'b0;
		end else begin
			ssbus.rsp_data <= 64'd0;
			ssbus.rsp_ack <= 1'b0;
			ssbus.rsp_error <= 1'b0;
			wrapper_restore_wr <= 1'b0;

			unique case (state_q)
				StIdle: begin
					core_ss_req <= 1'b0;
					core_ss_write <= 1'b0;
					request_fault_q <= 1'b0;
					scan_watchdog_q <= 7'd0;

					if (request_selected) begin
						if (!request_command_legal) begin
							ssbus.rsp_ack <= 1'b1;
							ssbus.rsp_error <= 1'b1;
							state_q <= StWaitRelease;
						end else if (ssbus.req_query) begin
							ssbus.rsp_data <=
								ssbus.query_descriptor(
									OWNER_INDEX,
									WORD_COUNT,
									WIDTH_CODE_32
								);
							ssbus.rsp_ack <= 1'b1;
							state_q <= StWaitRelease;
						end else if (ssbus.req_validate) begin
							if (
								(address_valid !== 1'b1) ||
								(restore_structure_valid !== 1'b1) ||
								(
									(ssbus.req_addr <
									 CORE_WORD_COUNT) &&
									(
										(core_mask_known !== 1'b1) ||
										(core_padding_valid !== 1'b1)
									)
								)
							) begin
								ssbus.rsp_error <= 1'b1;
							end
							ssbus.rsp_ack <= 1'b1;
							state_q <= StWaitRelease;
						end else if (address_valid !== 1'b1) begin
							ssbus.rsp_ack <= 1'b1;
							ssbus.rsp_error <= 1'b1;
							state_q <= StWaitRelease;
						end else if (state_enable !== 1'b1) begin
							ssbus.rsp_ack <= 1'b1;
							ssbus.rsp_error <= 1'b1;
							state_q <= StWaitRelease;
						end else if (
							ssbus.req_write &&
							(
								(restore_enable !== 1'b1) ||
								(restore_structure_valid !== 1'b1)
							)
						) begin
							ssbus.rsp_ack <= 1'b1;
							ssbus.rsp_error <= 1'b1;
							state_q <= StWaitRelease;
						end else if (
							ssbus.req_addr < CORE_WORD_COUNT
						) begin
							if (
								(core_mask_known !== 1'b1) ||
								(
									ssbus.req_write &&
									(core_padding_valid !== 1'b1)
								)
							) begin
								ssbus.rsp_ack <= 1'b1;
								ssbus.rsp_error <= 1'b1;
								state_q <= StWaitRelease;
							end else if (
								core_has_live_bits !== 1'b1
							) begin
								// A fully empty ABI word is canonical
								// zero and has no endpoint to launch.
								ssbus.rsp_data <= 64'd0;
								ssbus.rsp_ack <= 1'b1;
								state_q <= StWaitRelease;
							end else begin
								request_addr_q <= ssbus.req_addr;
								request_data_q <= ssbus.req_data;
								request_read_q <= ssbus.req_read;
								core_ss_write <= ssbus.req_write;
								core_ss_req <= 1'b1;
								state_q <= StCoreWait;
							end
						end else if (ssbus.req_read) begin
							ssbus.rsp_data <=
								(ssbus.req_addr ==
								 WRAPPER_WORD) ?
								{32'd0, wrapper_state_word} :
								64'd0;
							ssbus.rsp_ack <= 1'b1;
							state_q <= StWaitRelease;
						end else if (
							ssbus.req_addr == WRAPPER_WORD
						) begin
							request_addr_q <= ssbus.req_addr;
							request_data_q <= ssbus.req_data;
							request_read_q <= 1'b0;
							wrapper_restore_data <=
								ssbus.req_data[31:0];
							wrapper_restore_wr <= 1'b1;
							state_q <= StWrapperWrite;
						end else begin
							// Word 159 was preflighted as canonical
							// zero and has no live destination.
							ssbus.rsp_ack <= 1'b1;
							state_q <= StWaitRelease;
						end
					end
				end

				StCoreWait: begin
					if (!request_matches || !core_authorized)
						request_fault_q <= 1'b1;

					if (core_ss_ack === 1'b1) begin
						core_ss_req <= 1'b0;
						core_ss_write <= 1'b0;
						if (request_selected) begin
							ssbus.rsp_ack <= 1'b1;
							if (
								request_fault_q ||
								!request_matches ||
								!core_authorized ||
								(core_ss_error !== 1'b0) ||
								(
									request_read_q &&
									(^core_ss_rdata === 1'bx)
								)
							) begin
								ssbus.rsp_error <= 1'b1;
							end else if (request_read_q) begin
								ssbus.rsp_data <= {
									32'd0,
									core_ss_rdata &
									core_ss_valid_mask
								};
							end
						end
						state_q <= StWaitRelease;
					end else if (core_ss_ack !== 1'b0) begin
						core_ss_req <= 1'b0;
						core_ss_write <= 1'b0;
						if (request_selected) begin
							ssbus.rsp_ack <= 1'b1;
							ssbus.rsp_error <= 1'b1;
						end
						state_q <= StWaitRelease;
					end else if (&scan_watchdog_q) begin
						core_ss_req <= 1'b0;
						core_ss_write <= 1'b0;
						if (request_selected) begin
							ssbus.rsp_ack <= 1'b1;
							ssbus.rsp_error <= 1'b1;
						end
						state_q <= StWaitRelease;
					end else begin
						scan_watchdog_q <=
							scan_watchdog_q + 7'd1;
					end
				end

				StWrapperWrite: begin
					if (
						!request_matches ||
						(state_enable !== 1'b1) ||
						(restore_enable !== 1'b1)
					) begin
						ssbus.rsp_error <= 1'b1;
					end
					ssbus.rsp_ack <= 1'b1;
					state_q <= StWaitRelease;
				end

				StWaitRelease: begin
					core_ss_req <= 1'b0;
					core_ss_write <= 1'b0;
					if (request_command === 4'b0000)
						state_q <= StIdle;
				end

				default: begin
					state_q <= StIdle;
					core_ss_req <= 1'b0;
					core_ss_write <= 1'b0;
				end
			endcase
		end
	end

endmodule

`default_nettype wire
