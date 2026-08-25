// CaveBanpresto-local arbitration for the MiSTer 64-bit DDR port.
//
// All addresses in this module are BYTE addresses.  The eventual emu-level
// integration must convert ddr_byte_addr to the framework's 64-bit word
// address with DDRAM_ADDR = ddr_byte_addr[31:3].
//
// The save port is also the maintenance port used by the pre-boot ROM
// identity scanner.  Save ownership is deliberately unavailable until the
// game-side transport reports an explicit idle boundary.
module CaveBanprestoSaveStateDdrArbiter (
	input  logic        clock,
	input  logic        reset,

	// Normal game client.  A command transfers on cmd_valid && cmd_ready.
	// cmd_write=0 is a read command; cmd_write=1 is a write command.
	input  logic        game_idle,
	input  logic        game_cmd_valid,
	output logic        game_cmd_ready,
	input  logic        game_cmd_write,
	input  logic [31:0] game_cmd_byte_addr,
	input  logic [63:0] game_cmd_wdata,
	input  logic [7:0]  game_cmd_be,
	input  logic [7:0]  game_cmd_burstcnt,
	output logic        game_rsp_valid,
	output logic [63:0] game_rsp_rdata,
	output logic        game_write_commit,
	output logic [31:0] game_write_commit_byte_addr,

	// Save/identity maintenance client.
	input  logic        save_acquire,
	output logic        save_granted,
	input  logic        save_cmd_valid,
	output logic        save_cmd_ready,
	input  logic        save_cmd_write,
	input  logic [31:0] save_cmd_byte_addr,
	input  logic [63:0] save_cmd_wdata,
	input  logic [7:0]  save_cmd_be,
	input  logic [7:0]  save_cmd_burstcnt,
	output logic        save_rsp_valid,
	output logic [63:0] save_rsp_rdata,

	// Registered physical DDR command boundary.  ddr_wait_n=1 accepts the
	// command on this clock edge.  Read data is independently qualified by
	// ddr_rdata_valid and may arrive an arbitrary number of clocks later.
	output logic        ddr_rd,
	output logic        ddr_wr,
	output logic [31:0] ddr_byte_addr,
	output logic [63:0] ddr_wdata,
	output logic [7:0]  ddr_be,
	output logic [7:0]  ddr_burstcnt,
	input  logic        ddr_wait_n,
	input  logic [63:0] ddr_rdata,
	input  logic        ddr_rdata_valid
);

	logic        command_valid_q = 1'b0;
	logic        command_save_q = 1'b0;
	logic        command_write_q = 1'b0;
	logic [31:0] command_byte_addr_q = 32'd0;
	logic [63:0] command_wdata_q = 64'd0;
	logic [7:0]  command_be_q = 8'd0;
	logic [7:0]  command_burstcnt_q = 8'd0;

	logic        save_granted_q = 1'b0;

	// Exactly one physical read may be outstanding.  The owner and remaining
	// response-beat count live beyond command acceptance, when ddr_rd has
	// already been deasserted.
	logic        read_pending_q = 1'b0;
	logic        read_save_q = 1'b0;
	logic [7:0]  read_remaining_q = 8'd0;

	// MiSTer's safe f2sdram terminator lets an accepted read drain across a
	// reset.  These beats are quarantined so that a pre-reset reply can never
	// become the first post-reset game's reply.
	logic [7:0] discard_remaining_q = 8'd0;

	logic        game_rsp_valid_q = 1'b0;
	logic [63:0] game_rsp_rdata_q = 64'd0;
	logic        save_rsp_valid_q = 1'b0;
	logic [63:0] save_rsp_rdata_q = 64'd0;

	function automatic logic [7:0] response_beats(
		input logic [7:0] burstcnt
	);
		begin
			// Zero is not a legal MiSTer burst count, but treating it as one
			// response beat prevents malformed traffic from wedging ownership.
			response_beats = (burstcnt == 8'd0) ? 8'd1 : burstcnt;
		end
	endfunction

	function automatic logic [7:0] consume_one(
		input logic [7:0] remaining
	);
		begin
			consume_one = (remaining <= 8'd1) ? 8'd0
			                                 : remaining - 8'd1;
		end
	endfunction

	logic command_accepted;
	logic read_command_accepted;
	logic command_slot_available;
	logic client_command_allowed;
	logic capture_game_command;
	logic capture_save_command;
	logic capture_command;
	logic capture_command_save;
	logic capture_command_write;
	logic [31:0] capture_command_byte_addr;
	logic [63:0] capture_command_wdata;
	logic [7:0]  capture_command_be;
	logic [7:0]  capture_command_burstcnt;
	logic transport_idle;

	always_comb begin
		command_accepted = command_valid_q && ddr_wait_n;
		read_command_accepted = command_accepted && !command_write_q;

		// A write may be replaced on the same edge it is physically accepted,
		// retaining one accepted beat per clock.  A read may not be replaced:
		// it first creates the single outstanding-response obligation.
		command_slot_available = !command_valid_q
		                      || (command_accepted && command_write_q);
		client_command_allowed = !reset
		                      && (discard_remaining_q == 8'd0)
		                      && !read_pending_q
		                      && command_slot_available;

		game_cmd_ready = !save_granted_q && client_command_allowed;
		save_cmd_ready = save_granted_q
		              && save_acquire
		              && client_command_allowed;

		capture_game_command = game_cmd_valid && game_cmd_ready;
		capture_save_command = save_cmd_valid && save_cmd_ready;
		capture_command = capture_game_command || capture_save_command;
		capture_command_save = capture_save_command;

		capture_command_write = capture_save_command
		                      ? save_cmd_write : game_cmd_write;
		capture_command_byte_addr = capture_save_command
		                          ? save_cmd_byte_addr
		                          : game_cmd_byte_addr;
		capture_command_wdata = capture_save_command
		                      ? save_cmd_wdata : game_cmd_wdata;
		capture_command_be = capture_save_command
		                   ? save_cmd_be : game_cmd_be;
		capture_command_burstcnt = capture_save_command
		                         ? save_cmd_burstcnt
		                         : game_cmd_burstcnt;

		transport_idle = !command_valid_q
		              && !read_pending_q
		              && (discard_remaining_q == 8'd0)
		              && !game_rsp_valid_q
		              && !save_rsp_valid_q;
	end

	// Registered physical command stage.
	always_ff @(posedge clock) begin
		if (reset) begin
			command_valid_q <= 1'b0;
			command_save_q <= 1'b0;
			command_write_q <= 1'b0;
			command_byte_addr_q <= 32'd0;
			command_wdata_q <= 64'd0;
			command_be_q <= 8'd0;
			command_burstcnt_q <= 8'd0;
		end else if (read_command_accepted) begin
			// A read command is a single command beat.  It must fall as soon as
			// accepted even though its response remains outstanding.
			command_valid_q <= 1'b0;
		end else if (command_slot_available) begin
			command_valid_q <= capture_command;
			if (capture_command) begin
				command_save_q <= capture_command_save;
				command_write_q <= capture_command_write;
				command_byte_addr_q <= capture_command_byte_addr;
				command_wdata_q <= capture_command_wdata;
				command_be_q <= capture_command_be;
				command_burstcnt_q <= capture_command_burstcnt;
			end
		end
	end

	// Exclusive save ownership.  A simultaneous game command wins while the
	// game side is still selected, even if game_idle was asserted too early.
	always_ff @(posedge clock) begin
		if (reset) begin
			save_granted_q <= 1'b0;
		end else if (save_granted_q) begin
			if (!save_acquire && transport_idle)
				save_granted_q <= 1'b0;
		end else if (save_acquire
		          && game_idle
		          && !game_cmd_valid
		          && transport_idle) begin
			save_granted_q <= 1'b1;
		end
	end

	// Read ownership, response routing, and reset quarantine form one tightly
	// coupled concern.  Response outputs are registered for a full client
	// clock and are zero outside their valid window.
	always_ff @(posedge clock) begin
		if (reset) begin
			game_rsp_valid_q <= 1'b0;
			game_rsp_rdata_q <= 64'd0;
			save_rsp_valid_q <= 1'b0;
			save_rsp_rdata_q <= 64'd0;

			if (read_pending_q) begin
				discard_remaining_q <= ddr_rdata_valid
				                     ? consume_one(read_remaining_q)
				                     : read_remaining_q;
			end else if (read_command_accepted) begin
				discard_remaining_q <= ddr_rdata_valid
				                     ? consume_one(response_beats(
				                         command_burstcnt_q))
				                     : response_beats(
				                         command_burstcnt_q);
			end else if ((discard_remaining_q != 8'd0)
			          && ddr_rdata_valid) begin
				discard_remaining_q <= consume_one(
					discard_remaining_q);
			end

			read_pending_q <= 1'b0;
			read_save_q <= 1'b0;
			read_remaining_q <= 8'd0;
		end else begin
			game_rsp_valid_q <= 1'b0;
			game_rsp_rdata_q <= 64'd0;
			save_rsp_valid_q <= 1'b0;
			save_rsp_rdata_q <= 64'd0;

			if (discard_remaining_q != 8'd0) begin
				if (ddr_rdata_valid)
					discard_remaining_q <= consume_one(
						discard_remaining_q);
			end else if (read_pending_q) begin
				if (ddr_rdata_valid) begin
					if (read_save_q) begin
						save_rsp_valid_q <= 1'b1;
						save_rsp_rdata_q <= ddr_rdata;
					end else begin
						game_rsp_valid_q <= 1'b1;
						game_rsp_rdata_q <= ddr_rdata;
					end

					read_remaining_q <= consume_one(
						read_remaining_q);
					if (read_remaining_q <= 8'd1)
						read_pending_q <= 1'b0;
				end
			end else if (read_command_accepted) begin
				read_save_q <= command_save_q;
				if (ddr_rdata_valid) begin
					if (command_save_q) begin
						save_rsp_valid_q <= 1'b1;
						save_rsp_rdata_q <= ddr_rdata;
					end else begin
						game_rsp_valid_q <= 1'b1;
						game_rsp_rdata_q <= ddr_rdata;
					end

					read_remaining_q <= consume_one(
						response_beats(command_burstcnt_q));
					read_pending_q <= response_beats(
						command_burstcnt_q) > 8'd1;
				end else begin
					read_pending_q <= 1'b1;
					read_remaining_q <= response_beats(
						command_burstcnt_q);
				end
			end
		end
	end

	assign save_granted = save_granted_q;

	assign ddr_rd = command_valid_q && !command_write_q;
	assign ddr_wr = command_valid_q && command_write_q;
	assign ddr_byte_addr = command_byte_addr_q;
	assign ddr_wdata = command_wdata_q;
	assign ddr_be = command_be_q;
	assign ddr_burstcnt = command_burstcnt_q;

	assign game_rsp_valid = game_rsp_valid_q;
	assign game_rsp_rdata = game_rsp_valid_q ? game_rsp_rdata_q : 64'd0;
	assign game_write_commit = command_accepted
	                         && !command_save_q
	                         && command_write_q;
	assign game_write_commit_byte_addr = command_byte_addr_q;
	assign save_rsp_valid = save_rsp_valid_q;
	assign save_rsp_rdata = save_rsp_valid_q ? save_rsp_rdata_q : 64'd0;

endmodule
