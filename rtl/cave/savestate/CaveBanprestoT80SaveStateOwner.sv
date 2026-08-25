`default_nettype none

// CaveBanpresto owner 23: exact T80 architectural state and wrapper divider.
//
// The stream contains five 64-bit elements:
//   0: {32'h5438_3031 ("T801"), 2'b00, divider[2:0], auxiliary[26:0]}
//   1: REG[63:0]
//   2: REG[127:64]
//   3: REG[191:128]
//   4: {44'd0, REG[211:192]}
//
// Pass 1 validates the version tag, reserved bits, bounds, and strict address
// order while staging an immutable comparison image.  Pass 2 must reproduce
// that image exactly and only populates restore staging registers.  The live
// T80 load strobe is emitted once, and only in response to the stream engine's
// final restore_commit_i pulse.
module CaveBanprestoT80SaveStateOwner #(
	parameter [7:0] OWNER_INDEX = 8'd23,
	parameter [31:0] FORMAT_TAG = 32'h5438_3031 // ASCII "T801"
) (
	input  wire clk_i,
	input  wire reset_i,
	input  wire restore_begin_i,
	input  wire restore_commit_i,

	input  wire [211:0] live_reg_i,
	input  wire  [26:0] live_aux_i,
	input  wire   [2:0] live_divider_i,

	output wire [211:0] restore_reg_o,
	output wire  [26:0] restore_aux_o,
	output wire   [2:0] restore_divider_o,
	output logic        restore_load_o,

	output logic validation_complete_o,
	output logic validation_valid_o,
	output logic write_complete_o,
	output logic write_valid_o,
	output logic restore_committed_o,
	output logic terminal_fault_o,

	cavebanpresto_ssbus_if.responder ssbus
);

	localparam [31:0] WORD_COUNT = 32'd5;
	localparam [1:0] WIDTH_CODE_64 = 2'd3;

	// Justification (reg-a): immutable pass-1 image used to prove pass-2
	// identity without changing any live T80 state.
	logic [63:0] validate_word0_q;
	logic [63:0] validate_word1_q;
	logic [63:0] validate_word2_q;
	logic [63:0] validate_word3_q;
	logic [63:0] validate_word4_q;

	// Justification (reg-a): pass-2 image remains staging-only until the
	// external, globally ordered final commit pulse.
	logic [63:0] write_word0_q;
	logic [63:0] write_word1_q;
	logic [63:0] write_word2_q;
	logic [63:0] write_word3_q;
	logic [63:0] write_word4_q;

	// Justification (reg-b): strict monotonic cursors and sticky failure state
	// make duplicate, missing, and out-of-order transfers unambiguous.
	logic [2:0] validate_next_q;
	logic [2:0] write_next_q;
	logic       validation_failed_q;
	logic       write_failed_q;
	// The save-state bus holds a registered request until the registered ACK
	// propagates back through its mux/router.  Accept each held request once;
	// otherwise a cursor-bearing command is executed again on the ACK edge and
	// silently poisons the following address.
	logic       request_seen_q;

	logic [63:0] live_word;
	logic [63:0] validated_word;
	logic        address_valid;
	logic        validate_sequence_valid;
	logic        write_sequence_valid;
	logic        validate_structure_valid;

	assign address_valid = ssbus.req_addr < WORD_COUNT;
	assign validate_sequence_valid =
		address_valid &&
		(ssbus.req_addr == {29'd0, validate_next_q});
	assign write_sequence_valid =
		address_valid &&
		(ssbus.req_addr == {29'd0, write_next_q});

	assign restore_aux_o = write_word0_q[26:0];
	assign restore_divider_o = write_word0_q[29:27];
	assign restore_reg_o = {
		write_word4_q[19:0],
		write_word3_q,
		write_word2_q,
		write_word1_q
	};

	always_comb begin
		live_word = 64'd0;
		validated_word = 64'd0;
		validate_structure_valid = 1'b0;

		unique case (ssbus.req_addr)
			32'd0: begin
				live_word = {
					FORMAT_TAG,
					2'b00,
					live_divider_i,
					live_aux_i
				};
				validated_word = validate_word0_q;
				validate_structure_valid =
					(ssbus.req_data[63:32] == FORMAT_TAG) &&
					(ssbus.req_data[31:30] == 2'b00);
			end
			32'd1: begin
				live_word = live_reg_i[63:0];
				validated_word = validate_word1_q;
				validate_structure_valid = 1'b1;
			end
			32'd2: begin
				live_word = live_reg_i[127:64];
				validated_word = validate_word2_q;
				validate_structure_valid = 1'b1;
			end
			32'd3: begin
				live_word = live_reg_i[191:128];
				validated_word = validate_word3_q;
				validate_structure_valid = 1'b1;
			end
			32'd4: begin
				live_word = {44'd0, live_reg_i[211:192]};
				validated_word = validate_word4_q;
				validate_structure_valid =
					ssbus.req_data[63:20] == 44'd0;
			end
			default: begin
				live_word = 64'd0;
				validated_word = 64'd0;
				validate_structure_valid = 1'b0;
			end
		endcase
	end

	always_ff @(posedge clk_i) begin
		if (reset_i) begin
			validate_word0_q <= 64'd0;
			validate_word1_q <= 64'd0;
			validate_word2_q <= 64'd0;
			validate_word3_q <= 64'd0;
			validate_word4_q <= 64'd0;
			write_word0_q <= 64'd0;
			write_word1_q <= 64'd0;
			write_word2_q <= 64'd0;
			write_word3_q <= 64'd0;
			write_word4_q <= 64'd0;
			validate_next_q <= 3'd0;
			write_next_q <= 3'd0;
			validation_failed_q <= 1'b0;
			write_failed_q <= 1'b0;
			request_seen_q <= 1'b0;
			validation_complete_o <= 1'b0;
			validation_valid_o <= 1'b0;
			write_complete_o <= 1'b0;
			write_valid_o <= 1'b0;
			restore_load_o <= 1'b0;
			restore_committed_o <= 1'b0;
			terminal_fault_o <= 1'b0;
			ssbus.rsp_data <= 64'd0;
			ssbus.rsp_ack <= 1'b0;
			ssbus.rsp_error <= 1'b0;
		end else begin
			ssbus.rsp_data <= 64'd0;
			ssbus.rsp_ack <= 1'b0;
			ssbus.rsp_error <= 1'b0;
			restore_load_o <= 1'b0;

			if (restore_begin_i) begin
				validate_word0_q <= 64'd0;
				validate_word1_q <= 64'd0;
				validate_word2_q <= 64'd0;
				validate_word3_q <= 64'd0;
				validate_word4_q <= 64'd0;
				write_word0_q <= 64'd0;
				write_word1_q <= 64'd0;
				write_word2_q <= 64'd0;
				write_word3_q <= 64'd0;
				write_word4_q <= 64'd0;
				validate_next_q <= 3'd0;
				write_next_q <= 3'd0;
				validation_failed_q <= 1'b0;
				write_failed_q <= 1'b0;
				request_seen_q <= 1'b0;
				validation_complete_o <= 1'b0;
				validation_valid_o <= 1'b0;
				write_complete_o <= 1'b0;
				write_valid_o <= 1'b0;
				restore_committed_o <= 1'b0;
				terminal_fault_o <= 1'b0;
			end else if (restore_commit_i) begin
				if (validation_complete_o &&
				    validation_valid_o &&
				    write_complete_o &&
				    write_valid_o &&
				    ~validation_failed_q &&
				    ~write_failed_q &&
				    ~restore_committed_o &&
				    ~terminal_fault_o &&
				    ~ssbus.command_active()) begin
					restore_load_o <= 1'b1;
					restore_committed_o <= 1'b1;
				end else begin
					// A premature, repeated, concurrent, or otherwise
					// malformed global commit is terminal for this attempt.
					terminal_fault_o <= 1'b1;
				end
			end else begin
				if (!ssbus.command_active())
					request_seen_q <= 1'b0;

				if (ssbus.request_for(OWNER_INDEX) && !request_seen_q) begin
					request_seen_q <= 1'b1;
				if (terminal_fault_o) begin
					ssbus.rsp_ack <= 1'b1;
					ssbus.rsp_error <= 1'b1;
				end else if (ssbus.req_query) begin
					ssbus.rsp_data <= ssbus.query_descriptor(
						OWNER_INDEX,
						WORD_COUNT,
						WIDTH_CODE_64
					);
					ssbus.rsp_ack <= 1'b1;
				end else if (ssbus.req_read) begin
					ssbus.rsp_ack <= 1'b1;
					if (address_valid) begin
						ssbus.rsp_data <= live_word;
					end else begin
						ssbus.rsp_error <= 1'b1;
					end
				end else if (ssbus.req_validate) begin
					ssbus.rsp_ack <= 1'b1;
					if (validation_failed_q ||
					    validation_complete_o ||
					    ~validate_sequence_valid ||
					    ~validate_structure_valid) begin
						ssbus.rsp_error <= 1'b1;
						validation_failed_q <= 1'b1;
						validation_valid_o <= 1'b0;
					end else begin
						unique case (ssbus.req_addr)
							32'd0: validate_word0_q <= ssbus.req_data;
							32'd1: validate_word1_q <= ssbus.req_data;
							32'd2: validate_word2_q <= ssbus.req_data;
							32'd3: validate_word3_q <= ssbus.req_data;
							32'd4: validate_word4_q <= ssbus.req_data;
							default: begin end
						endcase

						validate_next_q <= validate_next_q + 3'd1;
						if (ssbus.req_addr == 32'd4) begin
							validation_complete_o <= 1'b1;
							validation_valid_o <= 1'b1;
						end
					end
				end else if (ssbus.req_write) begin
					ssbus.rsp_ack <= 1'b1;
					if (~validation_complete_o ||
					    ~validation_valid_o ||
					    validation_failed_q ||
					    write_failed_q ||
					    write_complete_o ||
					    ~write_sequence_valid ||
					    (ssbus.req_data != validated_word)) begin
						ssbus.rsp_error <= 1'b1;
						write_failed_q <= 1'b1;
						write_valid_o <= 1'b0;
					end else begin
						unique case (ssbus.req_addr)
							32'd0: write_word0_q <= ssbus.req_data;
							32'd1: write_word1_q <= ssbus.req_data;
							32'd2: write_word2_q <= ssbus.req_data;
							32'd3: write_word3_q <= ssbus.req_data;
							32'd4: write_word4_q <= ssbus.req_data;
							default: begin end
						endcase

						write_next_q <= write_next_q + 3'd1;
						if (ssbus.req_addr == 32'd4) begin
							write_complete_o <= 1'b1;
							write_valid_o <= 1'b1;
						end
					end
				end
				end
			end
		end
	end

endmodule

`default_nettype wire
