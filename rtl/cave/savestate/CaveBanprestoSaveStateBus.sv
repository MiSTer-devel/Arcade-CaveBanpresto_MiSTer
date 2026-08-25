`default_nettype none

// CaveBanpresto-local save-state owner bus.
//
// A requester holds exactly one req_* command until rsp_ack.  req_validate is
// the restore pass-1 dry-run operation: responders must bounds-check and
// acknowledge it without changing architectural state.
interface cavebanpresto_ssbus_if;
	logic [63:0] req_data;
	logic [31:0] req_addr;
	logic  [7:0] req_select;
	logic        req_read;
	logic        req_write;
	logic        req_validate;
	logic        req_query;

	logic [63:0] rsp_data;
	logic        rsp_ack;
	logic        rsp_error;

	function automatic logic command_active();
		command_active =
			req_read | req_write | req_validate | req_query;
	endfunction

	function automatic logic selected(input logic [7:0] owner_index);
		selected = req_select == owner_index;
	endfunction

	function automatic logic request_for(input logic [7:0] owner_index);
		request_for =
			(req_select == owner_index) &
			(req_read | req_write | req_validate | req_query);
	endfunction

	function automatic logic payload_request_for(input logic [7:0] owner_index);
		payload_request_for =
			(req_select == owner_index) &
			(req_read | req_write | req_validate);
	endfunction

	function automatic logic [63:0] query_descriptor(
		input logic  [7:0] owner_index,
		input logic [31:0] element_count,
		input logic  [1:0] width_code
	);
		query_descriptor =
			{owner_index, 22'd0, width_code, element_count};
	endfunction

	modport requester (
		output req_data,
		output req_addr,
		output req_select,
		output req_read,
		output req_write,
		output req_validate,
		output req_query,
		input  rsp_data,
		input  rsp_ack,
		input  rsp_error
	);

	modport responder (
		input  req_data,
		input  req_addr,
		input  req_select,
		input  req_read,
		input  req_write,
		input  req_validate,
		input  req_query,
		output rsp_data,
		output rsp_ack,
		output rsp_error,
		import command_active,
		import selected,
		import request_for,
		import payload_request_for,
		import query_descriptor
	);
endinterface

`default_nettype wire
