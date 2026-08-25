`default_nettype none

// CaveBanpresto save-state owner 24 for the Sound Z80's exact 8 KiB RAM.
//
// This wrapper owns the existing single physical 8-bit x 8192-word RAM.  It
// does not create a shadow copy or a second RAM port.  Normal Z80 traffic is
// passed through unchanged while takeover_permitted_i is low.  The quiesce
// controller raises takeover_permitted_i only after the Sound Z80 has stopped;
// while it is high, all runtime reads and writes are blocked even between
// owner-bus commands.  That defensive gate prevents a stale CPU write from
// racing pass-1 reads or pass-2 restore writes.
//
// Owner 24 uses one 8-bit element per byte:
//   descriptor = {8'd24, 22'd0, 2'd0, 32'd8192}
//   req_addr    = byte address 0..8191
//   req_data    = byte in bits [7:0], upper bits ignored on pass-2 write
//
// Restore is deliberately not shadowed: req_validate is the write-free pass-1
// bounds check, and req_write is the pass-2 architectural mutation.  The
// global stream engine is responsible for issuing every validation before any
// write and for the single final slot commit after all owners have completed.
module CaveBanprestoSoundRamSaveStateOwner (
	input  wire        clk_i,
	input  wire        reset_i,
	input  wire        takeover_permitted_i,

	input  wire        runtime_rd_i,
	input  wire        runtime_wr_i,
	input  wire [12:0] runtime_addr_i,
	input  wire  [7:0] runtime_din_i,
	output wire  [7:0] runtime_dout_o,

	output wire        state_takeover_o,

	cavebanpresto_ssbus_if.responder ssbus
);

	wire        owner_takeover;
	wire        owner_rd;
	wire        owner_wr;
	wire [12:0] owner_addr;
	wire  [7:0] owner_din;

	logic        ram_rd;
	logic        ram_wr;
	logic [12:0] ram_addr;
	logic  [7:0] ram_din;
	wire   [7:0] ram_dout;

	assign runtime_dout_o = ram_dout;
	assign state_takeover_o = owner_takeover;

	// A default-zero mux is fail-closed for unknown quiesce/ownership inputs in
	// simulation.  In normal operation, takeover_permitted_i=0 reproduces the
	// original Sound.sv RAM port bit-for-bit.
	always_comb begin
		ram_rd = 1'b0;
		ram_wr = 1'b0;
		ram_addr = 13'd0;
		ram_din = 8'd0;

		if (owner_takeover) begin
			ram_rd = owner_rd;
			ram_wr = owner_wr;
			ram_addr = owner_addr;
			ram_din = owner_din;
		end else if (!takeover_permitted_i) begin
			ram_rd = runtime_rd_i;
			ram_wr = runtime_wr_i;
			ram_addr = runtime_addr_i;
			ram_din = runtime_din_i;
		end
	end

	CaveBanprestoSaveStateRamOwner #(
		.OWNER_INDEX(8'd24),
		.ELEMENT_WIDTH(8),
		.ELEMENT_COUNT(8192),
		.READ_LATENCY(1)
	) owner (
		.clk_i(clk_i),
		.reset_i(reset_i),
		.takeover_permitted_i(takeover_permitted_i),
		.port_takeover_o(owner_takeover),
		.port_rd_o(owner_rd),
		.port_wr_o(owner_wr),
		.port_addr_o(owner_addr),
		.port_din_o(owner_din),
		.port_dout_i(ram_dout),
		.ssbus(ssbus)
	);

	// The local VHDL bridge binds the same production single_port_ram entity
	// and exact parameters as Sound.sv. It exists only to make the VHDL
	// Boolean MASK_ENABLE binding explicit across mixed-language tools.
	CaveBanprestoSoundRamPrimitive ram (
		.clock(clk_i),
		.rd(ram_rd),
		.wr(ram_wr),
		.addr(ram_addr),
		.din(ram_din),
		.dout(ram_dout)
	);

endmodule

`default_nettype wire
