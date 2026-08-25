`default_nettype none

// Main-local eight-cell sprite register file with an atomic save-state hook.
//
// All eight physical cells are state, including cells 2, 3, 6, and 7 whose
// current downstream outputs are unused.  Omitting those cells would make a
// restored software-visible register bank depend on pre-restore history.
//
// State order is little-cell-first:
//   [ 15:  0] register 0 through [127:112] register 7.
module CaveBanprestoMainSpriteRegisterFile (
	input  wire         clock,
	input  wire         io_mem_wr,
	input  wire [2:0]   io_mem_addr,
	input  wire [1:0]   io_mem_mask,
	input  wire [15:0]  io_mem_din,
	input  wire         ss_hold_i,
	input  wire         ss_restore_load_i,
	input  wire [127:0] ss_state_i,
	output wire [127:0] ss_state_o,
	output wire         ss_blocked_normal_write_o,
	output wire [15:0]  io_regs_0,
	output wire [15:0]  io_regs_1,
	output wire [15:0]  io_regs_2,
	output wire [15:0]  io_regs_3,
	output wire [15:0]  io_regs_4,
	output wire [15:0]  io_regs_5
);

	// Justification (reg-a): these are the eight software-visible physical
	// sprite control cells whose values persist across CPU cycles.
	logic [15:0] regs_0;
	logic [15:0] regs_1;
	logic [15:0] regs_2;
	logic [15:0] regs_3;
	logic [15:0] regs_4;
	logic [15:0] regs_5;
	logic [15:0] regs_6;
	logic [15:0] regs_7;

	function automatic logic [15:0] apply_mask(
		input logic [15:0] old_value,
		input logic [15:0] new_value,
		input logic  [1:0] mask
	);
		begin
			apply_mask = {
				mask[1] ? new_value[15:8] : old_value[15:8],
				mask[0] ? new_value[7:0]  : old_value[7:0]
			};
		end
	endfunction

	always_ff @(posedge clock) begin
		if (ss_restore_load_i === 1'b1) begin
			regs_0 <= ss_state_i[15:0];
			regs_1 <= ss_state_i[31:16];
			regs_2 <= ss_state_i[47:32];
			regs_3 <= ss_state_i[63:48];
			regs_4 <= ss_state_i[79:64];
			regs_5 <= ss_state_i[95:80];
			regs_6 <= ss_state_i[111:96];
			regs_7 <= ss_state_i[127:112];
		end
		else if ((ss_hold_i === 1'b0) &&
		         (io_mem_wr === 1'b1)) begin
			case (io_mem_addr)
				3'h0:
					regs_0 <= apply_mask(
						regs_0,
						io_mem_din,
						io_mem_mask
					);
				3'h1:
					regs_1 <= apply_mask(
						regs_1,
						io_mem_din,
						io_mem_mask
					);
				3'h2:
					regs_2 <= apply_mask(
						regs_2,
						io_mem_din,
						io_mem_mask
					);
				3'h3:
					regs_3 <= apply_mask(
						regs_3,
						io_mem_din,
						io_mem_mask
					);
				3'h4:
					regs_4 <= apply_mask(
						regs_4,
						io_mem_din,
						io_mem_mask
					);
				3'h5:
					regs_5 <= apply_mask(
						regs_5,
						io_mem_din,
						io_mem_mask
					);
				3'h6:
					regs_6 <= apply_mask(
						regs_6,
						io_mem_din,
						io_mem_mask
					);
				3'h7:
					regs_7 <= apply_mask(
						regs_7,
						io_mem_din,
						io_mem_mask
					);
			endcase
		end
	end

	assign ss_state_o = {
		regs_7,
		regs_6,
		regs_5,
		regs_4,
		regs_3,
		regs_2,
		regs_1,
		regs_0
	};
	assign ss_blocked_normal_write_o =
		(io_mem_wr !== 1'b0) &&
		((ss_hold_i !== 1'b0) ||
		 (ss_restore_load_i !== 1'b0));

	assign io_regs_0 = regs_0;
	assign io_regs_1 = regs_1;
	assign io_regs_2 = regs_2;
	assign io_regs_3 = regs_3;
	assign io_regs_4 = regs_4;
	assign io_regs_5 = regs_5;

endmodule

`default_nettype wire
