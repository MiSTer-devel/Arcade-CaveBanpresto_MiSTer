`default_nettype none

// Save-aware one-cell replacement for CaveSingleRegisterFile.
//
// Normal behavior is intentionally transparent: only address zero writes the
// full 16-bit physical DIP cell, and all other addresses are ignored.
module CaveBanprestoDipRegisterFile (
	input  wire        clock,
	input  wire        reset,
	input  wire        io_mem_wr,
	input  wire [1:0]  io_mem_addr,
	input  wire [15:0] io_mem_din,
	input  wire        ss_hold_i,
	input  wire        ss_restore_load_i,
	input  wire [15:0] ss_state_i,
	output wire [15:0] ss_state_o,
	output wire        ss_blocked_normal_write_o,
	output logic       ss_restore_applied_o,
	output wire [15:0] io_regs_0
);

	// Justification (reg-a): this is the software-visible physical DIP cell.
	logic [15:0] regs_0;

	always_ff @(posedge clock) begin
		if ((reset === 1'b0) &&
		    (ss_restore_load_i === 1'b1)) begin
			regs_0 <= ss_state_i;
		end else if ((ss_restore_load_i === 1'b0) &&
		             (ss_hold_i === 1'b0) &&
		             (io_mem_wr === 1'b1) &&
		             (io_mem_addr == 2'h0)) begin
			regs_0 <= io_mem_din;
		end
	end

	// Preserve the physical cell's legacy no-reset behavior.  Reset only
	// suppresses the save-state transaction proof pulse.
	always_ff @(posedge clock) begin
		if (reset !== 1'b0)
			ss_restore_applied_o <= 1'b0;
		else
			ss_restore_applied_o <= ss_restore_load_i === 1'b1;
	end

	assign ss_state_o = regs_0;
	assign ss_blocked_normal_write_o =
		(io_mem_wr !== 1'b0) &&
		((ss_hold_i !== 1'b0) ||
		 (ss_restore_load_i !== 1'b0));
	assign io_regs_0 = regs_0;

endmodule

`default_nettype wire
