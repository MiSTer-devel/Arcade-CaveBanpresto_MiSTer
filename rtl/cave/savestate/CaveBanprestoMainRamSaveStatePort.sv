`default_nettype none

// CaveBanpresto-local normal/save-state mux for one existing Main RAM port.
//
// This module owns no storage.  It preserves the original RAM primitive and
// its normal address/data/mask path, then lends that same physical port to the
// generic save-state owner only after the Main CPU and both render clients
// have reported idle.  Normal requests are blocked for the complete permitted
// takeover window, including gaps between serialized owner commands.
module CaveBanprestoMainRamSaveStatePort #(
	parameter [7:0] OWNER_INDEX = 8'd4,
	parameter integer ADDR_WIDTH = 15,
	parameter integer ELEMENT_COUNT = 32768
) (
	input  wire clk_i,
	input  wire reset_i,
	input  wire takeover_permitted_i,

	input  wire normal_rd_i,
	input  wire normal_wr_i,
	input  wire [1:0] normal_mask_i,
	input  wire [ADDR_WIDTH-1:0] normal_addr_i,
	input  wire [15:0] normal_din_i,

	output wire ram_rd_o,
	output wire ram_wr_o,
	output wire [1:0] ram_mask_o,
	output wire [ADDR_WIDTH-1:0] ram_addr_o,
	output wire [15:0] ram_din_o,
	input  wire [15:0] ram_dout_i,

	output wire takeover_active_o,
	output wire blocked_normal_access_o,

	cavebanpresto_ssbus_if.responder ssbus
);

	localparam integer OWNER_ADDRESS_WIDTH =
		(ELEMENT_COUNT <= 1) ? 1 : $clog2(ELEMENT_COUNT);

	wire owner_takeover;
	wire owner_rd;
	wire owner_wr;
	wire [OWNER_ADDRESS_WIDTH-1:0] owner_addr;
	wire [15:0] owner_din;

	// Every production instantiation has ADDR_WIDTH == clog2(ELEMENT_COUNT).
	// Keeping the memory's physical address width explicit also preserves the
	// non-power-of-two 5120-word scratch-RAM primitive while the owner enforces
	// its exact logical bound.
	wire [ADDR_WIDTH-1:0] owner_addr_extended = owner_addr;

	assign ram_rd_o =
		owner_takeover ? owner_rd :
		takeover_permitted_i ? 1'b0 :
		normal_rd_i;
	assign ram_wr_o =
		owner_takeover ? owner_wr :
		takeover_permitted_i ? 1'b0 :
		normal_wr_i;
	assign ram_mask_o =
		owner_takeover ? {2{owner_wr}} :
		normal_mask_i;
	assign ram_addr_o =
		owner_takeover ? owner_addr_extended :
		normal_addr_i;
	assign ram_din_o =
		owner_takeover ? owner_din :
		normal_din_i;

	assign takeover_active_o = owner_takeover;
	assign blocked_normal_access_o =
		takeover_permitted_i & (normal_rd_i | normal_wr_i);

	CaveBanprestoSaveStateRamOwner #(
		.OWNER_INDEX(OWNER_INDEX),
		.ELEMENT_WIDTH(16),
		.ELEMENT_COUNT(ELEMENT_COUNT),
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
		.port_dout_i(ram_dout_i),
		.ssbus(ssbus)
	);

endmodule

`default_nettype wire
