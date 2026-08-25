`default_nettype none

// CaveBanpresto-local exact-state YM2203 wrapper.
//
// The CPU write path deliberately remains the production Sound.sv contract:
// io_cpu_wr is a one-master-clock pulse presented directly to JT03.  There is
// no write queue and no wait-state insertion in this wrapper.
//
// State ABI:
//   owner index:        26
//   element width:      32 bits (width code 2)
//   core elements:      241
//   wrapper elements:   2
//   total elements:     243
//   serialized payload: 122 x 64-bit words (within the reserved 160 words)
module CaveBanprestoYM2203SaveState #(
	parameter [7:0] OWNER_INDEX = 8'd26
) (
	input  wire        clock,
	input  wire        reset,
	input  wire        io_cpu_wr,
	input  wire        io_cpu_addr,
	input  wire  [7:0] io_cpu_din,
	output wire  [7:0] io_cpu_dout,
	output wire        io_irq,
	output wire        io_audio_valid,
	output wire [15:0] io_audio_bits_psg,
	output wire [15:0] io_audio_bits_fm,

	input  wire        io_ss_hold_i,
	input  wire        io_ss_restore_enable_i,
	output wire        io_ss_idle_o,
	cavebanpresto_ssbus_if.responder io_ssbus
);

	localparam [16:0] CLOCK_ENABLE_STEP = 17'h2000;

	// Justification (reg-a): these are the two registers in the production
	// CaveClockEnable scheduler.  Explicit initial values model their FPGA
	// power-up state; reset intentionally does not alter them because the
	// production scheduler has no reset input.
	logic [15:0] scheduler_accumulator_q = 16'd0;
	logic        scheduler_enable_q = 1'b0;

	// Justification (reg-a): proves that hold has remained asserted long enough
	// for every core sequential block to observe a masked clock enable/write.
	logic [2:0] hold_stable_count_q;

	logic        wrapper_restore_wr;
	logic        wrapper_restore_index;
	logic [31:0] wrapper_restore_data;

	logic        auto_rd;
	logic        auto_wr;
	logic [31:0] auto_data_in;
	logic  [7:0] auto_device_idx;
	logic [15:0] auto_state_idx;
	wire  [31:0] auto_data_out;
	wire         auto_ack;

	wire [16:0] scheduler_next =
		{1'b0, scheduler_accumulator_q} + CLOCK_ENABLE_STEP;
	wire core_cen = scheduler_enable_q & ~io_ss_hold_i;
	wire core_write = io_cpu_wr & ~io_ss_hold_i;
	wire core_irq_n;
	wire [9:0] core_psg_snd;
	wire [31:0] wrapper_state_word0 =
		{16'd0, scheduler_accumulator_q};
	wire [31:0] wrapper_state_word1 =
		{31'd0, scheduler_enable_q};

	always_ff @(posedge clock) begin
		if (wrapper_restore_wr) begin
			if (!wrapper_restore_index) begin
				scheduler_accumulator_q <=
					wrapper_restore_data[15:0];
			end else begin
				scheduler_enable_q <= wrapper_restore_data[0];
			end
		end else if (!io_ss_hold_i) begin
			scheduler_accumulator_q <= scheduler_next[15:0];
			scheduler_enable_q <= scheduler_next[16];
		end
	end

	always_ff @(posedge clock) begin
		if (reset || !io_ss_hold_i) begin
			hold_stable_count_q <= 3'd0;
		end else if (!(&hold_stable_count_q)) begin
			hold_stable_count_q <= hold_stable_count_q + 3'd1;
		end
	end

	cavebanpresto_jt03_ss_jt03 exact_core (
		.rst(reset),
		.clk(clock),
		.cen(core_cen),
		.din(io_cpu_din),
		.addr(io_cpu_addr),
		.cs_n(1'b0),
		.wr_n(~core_write),
		.dout(io_cpu_dout),
		.irq_n(core_irq_n),
		.IOA_in(8'h00),
		.IOB_in(8'h00),
		.psg_A(),
		.psg_B(),
		.psg_C(),
		.fm_snd(io_audio_bits_fm),
		.psg_snd(core_psg_snd),
		.snd(),
		.snd_sample(io_audio_valid),
		.debug_view(),
		.auto_ss_rd(auto_rd),
		.auto_ss_wr(auto_wr),
		.auto_ss_data_in(auto_data_in),
		.auto_ss_device_idx(auto_device_idx),
		.auto_ss_state_idx(auto_state_idx),
		.auto_ss_base_device_idx(8'd0),
		.auto_ss_data_out(auto_data_out),
		.auto_ss_ack(auto_ack)
	);

	CaveBanprestoYM2203StatePort #(
		.OWNER_INDEX(OWNER_INDEX)
	) state_port (
		.clock(clock),
		.reset(reset),
		.state_enable(io_ss_idle_o),
		.restore_enable(io_ss_restore_enable_i),
		.wrapper_state_word0(wrapper_state_word0),
		.wrapper_state_word1(wrapper_state_word1),
		.wrapper_restore_wr(wrapper_restore_wr),
		.wrapper_restore_index(wrapper_restore_index),
		.wrapper_restore_data(wrapper_restore_data),
		.auto_rd(auto_rd),
		.auto_wr(auto_wr),
		.auto_data_in(auto_data_in),
		.auto_device_idx(auto_device_idx),
		.auto_state_idx(auto_state_idx),
		.auto_data_out(auto_data_out),
		.auto_ack(auto_ack),
		.ssbus(io_ssbus)
	);

	assign io_irq = ~core_irq_n;
	assign io_audio_bits_psg = {1'b0, core_psg_snd, 5'b0};
	assign io_ss_idle_o = io_ss_hold_i & (&hold_stable_count_q);

endmodule

module CaveBanprestoYM2203StatePort #(
	parameter [7:0] OWNER_INDEX = 8'd26
) (
	input  wire        clock,
	input  wire        reset,
	input  wire        state_enable,
	input  wire        restore_enable,
	input  wire [31:0] wrapper_state_word0,
	input  wire [31:0] wrapper_state_word1,
	output logic       wrapper_restore_wr,
	output logic       wrapper_restore_index,
	output logic [31:0] wrapper_restore_data,
	output logic       auto_rd,
	output logic       auto_wr,
	output logic [31:0] auto_data_in,
	output logic  [7:0] auto_device_idx,
	output logic [15:0] auto_state_idx,
	input  wire [31:0] auto_data_out,
	input  wire        auto_ack,
	cavebanpresto_ssbus_if.responder ssbus
);

	localparam [31:0] AUTO_WORD_COUNT = 32'd241;
	localparam [31:0] WRAPPER_WORD_BASE = 32'd241;
	localparam [31:0] WORD_COUNT = 32'd243;
	localparam [1:0] WIDTH_CODE_32 = 2'd2;

	typedef enum logic [2:0] {
		StIdle          = 3'd0,
		StAutoRead      = 3'd1,
		StAutoWrite     = 3'd2,
		StWrapperWrite  = 3'd3,
		StWaitRelease   = 3'd4
	} state_e;

	// Justification (reg-a): retains an accepted transaction while the
	// generated core's state port completes its read/write cycle.
	state_e state_q;
	logic [31:0] request_addr_q;
	logic [63:0] request_data_q;

	logic [3:0] request_command;
	logic       request_selected;
	logic       request_command_legal;
	logic       address_valid;
	logic       request_structure_valid;
	logic       request_matches;
	logic [23:0] request_auto_location;

	// The generated core owns words 0..240 and consumes all 32 bits of each
	// element.  The two local wrapper words have narrower architectural
	// payloads; pass 1 must reject nonzero or unknown padding before pass 2
	// can load either scheduler register.
	function automatic logic restore_word_structure_valid(
		input [31:0] address,
		input [63:0] data
	);
	begin
		case (address)
			WRAPPER_WORD_BASE:
				restore_word_structure_valid =
					data[31:16] === 16'd0;
			WRAPPER_WORD_BASE + 32'd1:
				restore_word_structure_valid =
					data[31:1] === 31'd0;
			default:
				restore_word_structure_valid = 1'b1;
		endcase
	end
	endfunction

	assign request_command = {
		ssbus.req_query,
		ssbus.req_validate,
		ssbus.req_write,
		ssbus.req_read
	};
	assign request_selected =
		(ssbus.req_select == OWNER_INDEX) & (|request_command);
	assign request_command_legal =
		(request_command == 4'b0001) |
		(request_command == 4'b0010) |
		(request_command == 4'b0100) |
		(request_command == 4'b1000);
	assign address_valid = ssbus.req_addr < WORD_COUNT;
	assign request_structure_valid =
		restore_word_structure_valid(
			ssbus.req_addr,
			ssbus.req_data
		);
	assign request_matches =
		(ssbus.req_select == OWNER_INDEX) &
		(request_command == (state_q == StAutoRead ?
		                     4'b0001 : 4'b0010)) &
		(ssbus.req_addr == request_addr_q) &
		(ssbus.req_data == request_data_q);
	assign request_auto_location =
		auto_location(flat_index_for_address(ssbus.req_addr));

	// Timer A/B state occupies generated flattened indices 83 through 88.
	// Applying it before the shared MMR control bits can immediately change a
	// just-restored load/flag value.  Preserve the sibling's reverse order for
	// every other element, but place both timers at the end of the core range
	// so their count/load/flag state is the final core state written.
	function automatic [7:0] flat_index_for_address(
		input [31:0] address
	);
	begin
		if (address <= 32'd151)
			flat_index_for_address =
				8'd240 - address[7:0];
		else if (address <= 32'd234)
			flat_index_for_address =
				8'd234 - address[7:0];
		else if (address <= 32'd240)
			flat_index_for_address =
				8'd88 - (address[7:0] - 8'd235);
		else
			flat_index_for_address = 8'd0;
	end
	endfunction

	// The generated JT03 state image contains 241 flattened 32-bit elements.
	// Its instrumentation allocates sparse device IDs, so this stable mapping
	// translates the ABI's dense element index to {device,state}.
	function automatic [23:0] auto_location(
		input [7:0] flat_index
	);
	begin
		if (flat_index == 8'd0)
			auto_location = {8'd2, 16'd0};
		else if (flat_index <= 8'd8)
			auto_location =
				{8'd3, 8'd0, flat_index - 8'd1};
		else if (flat_index <= 8'd10)
			auto_location =
				{8'd4, 8'd0, flat_index - 8'd9};
		else if (flat_index == 8'd11)
			auto_location = {8'd5, 16'd0};
		else if (flat_index == 8'd12)
			auto_location = {8'd6, 16'd0};
		else if (flat_index == 8'd13)
			auto_location = {8'd11, 16'd0};
		else if (flat_index <= 8'd38)
			auto_location =
				{8'd12, 8'd0, flat_index - 8'd14};
		else if (flat_index <= 8'd82)
			auto_location =
				{8'd18, 8'd0, flat_index - 8'd39};
		else if (flat_index <= 8'd85)
			auto_location =
				{8'd21, 8'd0, flat_index - 8'd83};
		else if (flat_index <= 8'd88)
			auto_location =
				{8'd22, 8'd0, flat_index - 8'd86};
		else if (flat_index == 8'd89)
			auto_location = {8'd23, 16'd0};
		else if (flat_index <= 8'd109)
			auto_location =
				{8'd24, 8'd0, flat_index - 8'd90};
		else if (flat_index <= 8'd119)
			auto_location =
				{8'd25, 8'd0, flat_index - 8'd110};
		else if (flat_index <= 8'd121)
			auto_location =
				{8'd26, 8'd0, flat_index - 8'd120};
		else if (flat_index == 8'd122)
			auto_location = {8'd27, 16'd0};
		else if (flat_index == 8'd123)
			auto_location = {8'd28, 16'd0};
		else if (flat_index <= 8'd133)
			auto_location =
				{8'd29, 8'd0, flat_index - 8'd124};
		else if (flat_index <= 8'd136)
			auto_location =
				{8'd30, 8'd0, flat_index - 8'd134};
		else if (flat_index == 8'd137)
			auto_location = {8'd31, 16'd0};
		else if (flat_index == 8'd138)
			auto_location = {8'd32, 16'd0};
		else if (flat_index <= 8'd148)
			auto_location =
				{8'd33, 8'd0, flat_index - 8'd139};
		else if (flat_index <= 8'd151)
			auto_location =
				{8'd34, 8'd0, flat_index - 8'd149};
		else if (flat_index <= 8'd165)
			auto_location =
				{8'd35, 8'd0, flat_index - 8'd152};
		else if (flat_index <= 8'd179)
			auto_location =
				{8'd36, 8'd0, flat_index - 8'd166};
		else if (flat_index <= 8'd193)
			auto_location =
				{8'd37, 8'd0, flat_index - 8'd180};
		else if (flat_index <= 8'd203)
			auto_location =
				{8'd38, 8'd0, flat_index - 8'd194};
		else if (flat_index == 8'd204)
			auto_location = {8'd39, 16'd0};
		else if (flat_index == 8'd205)
			auto_location = {8'd40, 16'd0};
		else if (flat_index <= 8'd224)
			auto_location =
				{8'd59, 8'd0, flat_index - 8'd206};
		else if (flat_index == 8'd225)
			auto_location = {8'd60, 16'd0};
		else if (flat_index <= 8'd227)
			auto_location =
				{8'd61, 8'd0, flat_index - 8'd226};
		else if (flat_index <= 8'd229)
			auto_location =
				{8'd62, 8'd0, flat_index - 8'd228};
		else if (flat_index <= 8'd231)
			auto_location =
				{8'd63, 8'd0, flat_index - 8'd230};
		else if (flat_index == 8'd232)
			auto_location = {8'd64, 16'd0};
		else if (flat_index <= 8'd234)
			auto_location =
				{8'd65, 8'd0, flat_index - 8'd233};
		else if (flat_index <= 8'd236)
			auto_location =
				{8'd66, 8'd0, flat_index - 8'd235};
		else if (flat_index == 8'd237)
			auto_location = {8'd67, 16'd0};
		else if (flat_index == 8'd238)
			auto_location = {8'd68, 16'd0};
		else
			auto_location =
				{8'd76, 8'd0, flat_index - 8'd239};
	end
	endfunction

	always_ff @(posedge clock) begin
		if (reset) begin
			state_q <= StIdle;
			request_addr_q <= 32'd0;
			request_data_q <= 64'd0;
			wrapper_restore_wr <= 1'b0;
			wrapper_restore_index <= 1'b0;
			wrapper_restore_data <= 32'd0;
			auto_rd <= 1'b0;
			auto_wr <= 1'b0;
			auto_data_in <= 32'd0;
			auto_device_idx <= 8'd0;
			auto_state_idx <= 16'd0;
			ssbus.rsp_data <= 64'd0;
			ssbus.rsp_ack <= 1'b0;
			ssbus.rsp_error <= 1'b0;
		end else begin
			ssbus.rsp_data <= 64'd0;
			ssbus.rsp_ack <= 1'b0;
			ssbus.rsp_error <= 1'b0;
			wrapper_restore_wr <= 1'b0;

			case (state_q)
				StIdle: begin
					auto_rd <= 1'b0;
					auto_wr <= 1'b0;

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
							// Restore pass 1 is deliberately
							// non-mutating.
							ssbus.rsp_ack <= 1'b1;
							ssbus.rsp_error <=
								(address_valid !==
								 1'b1) ||
								(request_structure_valid !==
								 1'b1);
							state_q <= StWaitRelease;
						end else if (!address_valid ||
						             !state_enable) begin
							ssbus.rsp_ack <= 1'b1;
							ssbus.rsp_error <= 1'b1;
							state_q <= StWaitRelease;
						end else if (ssbus.req_write &&
						             !restore_enable) begin
							ssbus.rsp_ack <= 1'b1;
							ssbus.rsp_error <= 1'b1;
							state_q <= StWaitRelease;
						end else if (ssbus.req_addr <
						             AUTO_WORD_COUNT) begin
							request_addr_q <=
								ssbus.req_addr;
							request_data_q <=
								ssbus.req_data;
							auto_device_idx <=
								request_auto_location[
									23:16
								];
							auto_state_idx <=
								request_auto_location[
									15:0
								];
							auto_data_in <=
								ssbus.req_data[31:0];
							if (ssbus.req_read) begin
								auto_rd <= 1'b1;
								state_q <=
									StAutoRead;
							end else begin
								auto_wr <= 1'b1;
								state_q <=
									StAutoWrite;
							end
						end else if (ssbus.req_read) begin
							if (ssbus.req_addr ==
							    WRAPPER_WORD_BASE) begin
								ssbus.rsp_data <=
									{32'd0,
									 wrapper_state_word0};
							end else begin
								ssbus.rsp_data <=
									{32'd0,
									 wrapper_state_word1};
							end
							ssbus.rsp_ack <= 1'b1;
							state_q <= StWaitRelease;
						end else begin
							request_addr_q <=
								ssbus.req_addr;
							request_data_q <=
								ssbus.req_data;
							wrapper_restore_index <=
								ssbus.req_addr !=
								WRAPPER_WORD_BASE;
							wrapper_restore_data <=
								ssbus.req_data[31:0];
							wrapper_restore_wr <= 1'b1;
							state_q <= StWrapperWrite;
						end
					end
				end

				StAutoRead: begin
					if (!request_matches) begin
						auto_rd <= 1'b0;
						state_q <= StWaitRelease;
					end else if (auto_ack) begin
						auto_rd <= 1'b0;
						ssbus.rsp_data <=
							{32'd0, auto_data_out};
						ssbus.rsp_ack <= 1'b1;
						state_q <= StWaitRelease;
					end
				end

				StAutoWrite: begin
					auto_wr <= 1'b0;
					ssbus.rsp_ack <= 1'b1;
					state_q <= StWaitRelease;
				end

				StWrapperWrite: begin
					ssbus.rsp_ack <= 1'b1;
					state_q <= StWaitRelease;
				end

				StWaitRelease: begin
					auto_rd <= 1'b0;
					auto_wr <= 1'b0;
					if (!ssbus.command_active()) begin
						state_q <= StIdle;
					end
				end

				default: begin
					state_q <= StIdle;
					auto_rd <= 1'b0;
					auto_wr <= 1'b0;
				end
			endcase
		end
	end

endmodule

`default_nettype wire
