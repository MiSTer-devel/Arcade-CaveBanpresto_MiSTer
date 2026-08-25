`default_nettype none

// Main-local three-cell layer register file with an atomic save-state hook.
//
// Normal byte-mask and readback behavior is intentionally identical to
// CaveLayerRegisterFile.  The only save-state behavior is:
//   * ss_hold_i blocks normal writes at the quiesced boundary;
//   * ss_restore_load_i atomically loads all three physical cells; and
//   * ss_state_o exposes the physical cells without adding mirror registers.
//
// State order is little-cell-first:
//   [15:0]   register 0
//   [31:16]  register 1
//   [47:32]  register 2
module CaveBanprestoMainLayerRegisterFile (
	input  wire        clock,
	input  wire        io_mem_wr,
	input  wire [1:0]  io_mem_addr,
	input  wire [1:0]  io_mem_mask,
	input  wire [15:0] io_mem_din,
	input  wire        ss_hold_i,
	input  wire        ss_restore_load_i,
	input  wire [47:0] ss_state_i,
	output wire [47:0] ss_state_o,
	output wire        ss_blocked_normal_write_o,
	output wire [15:0] io_mem_dout,
	output wire [15:0] io_regs_0,
	output wire [15:0] io_regs_1,
	output wire [15:0] io_regs_2
);

	// Justification (reg-a): these are the three software-visible physical
	// layer control cells whose values persist across CPU cycles.
	logic [15:0] regs_0;
	logic [15:0] regs_1;
	logic [15:0] regs_2;

	logic [15:0] selected_reg;

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

	always_comb begin
		case (io_mem_addr)
			2'h0: selected_reg = regs_0;
			2'h1: selected_reg = regs_1;
			2'h2: selected_reg = regs_2;
			default: selected_reg = regs_0;
		endcase
	end

	always_ff @(posedge clock) begin
		if (ss_restore_load_i === 1'b1) begin
			regs_0 <= ss_state_i[15:0];
			regs_1 <= ss_state_i[31:16];
			regs_2 <= ss_state_i[47:32];
		end
		else if ((ss_hold_i === 1'b0) &&
		         (io_mem_wr === 1'b1)) begin
			case (io_mem_addr)
				2'h0:
					regs_0 <= apply_mask(
						regs_0,
						io_mem_din,
						io_mem_mask
					);
				2'h1:
					regs_1 <= apply_mask(
						regs_1,
						io_mem_din,
						io_mem_mask
					);
				2'h2:
					regs_2 <= apply_mask(
						regs_2,
						io_mem_din,
						io_mem_mask
					);
				default: begin
				end
			endcase
		end
	end

	assign ss_state_o = {regs_2, regs_1, regs_0};
	assign ss_blocked_normal_write_o =
		(io_mem_wr !== 1'b0) &&
		((ss_hold_i !== 1'b0) ||
		 (ss_restore_load_i !== 1'b0));

	assign io_mem_dout = selected_reg;
	assign io_regs_0 = regs_0;
	assign io_regs_1 = regs_1;
	assign io_regs_2 = regs_2;

endmodule

`default_nettype wire
