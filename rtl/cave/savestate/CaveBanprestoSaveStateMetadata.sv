`default_nettype none

// CaveBanpresto version-2 metadata owner (owner index 0).
//
// Restore pass 1 sends req_validate for all seven words.  This module stages
// each word, rejects duplicates and mismatches, and never mutates live state.
// Restore pass 2 sends req_write for the same seven words.  A commit pulse is
// possible only after a complete valid pass 1 and seven distinct matching
// pass-2 writes.
module CaveBanprestoSaveStateMetadata #(
	parameter [7:0] OWNER_INDEX = 8'd0,
	parameter [63:0] MAGIC = 64'h4342_5053_5330_3031, // ASCII "CBPSS001"
	parameter [31:0] SCHEMA_VERSION = 32'h0002_0000,
	parameter [31:0] CORE_ID = 32'h4342_5052 // ASCII "CBPR"
) (
	input  wire clk_i,
	input  wire reset_i,
	input  wire restore_begin_i,

	input  wire  [7:0] current_game_id_i,
	input  wire [63:0] current_set_id_i,
	input  wire [31:0] current_rom_length_i,
	input  wire [63:0] current_rom_crc64_i,
	input  wire [47:0] current_support_i,
	input  wire [63:0] current_config_fingerprint_i,

	output logic validation_complete_o,
	output logic validation_valid_o,
	output logic metadata_commit_o,
	output logic metadata_committed_o,

	cavebanpresto_ssbus_if.responder ssbus
);

	localparam [31:0] WORD_COUNT = 32'd7;
	localparam [1:0] WIDTH_CODE_64 = 2'd3;
	localparam [6:0] ALL_WORDS_SEEN = 7'b111_1111;

	// Justification (reg-a): pass-1 metadata staged for pass-2 comparison.
	logic [63:0] staged_word0_q;
	logic [63:0] staged_word1_q;
	logic [63:0] staged_word2_q;
	logic [63:0] staged_word3_q;
	logic [63:0] staged_word4_q;
	logic [63:0] staged_word5_q;
	logic [63:0] staged_word6_q;

	// Justification (reg-a): records exact-once coverage for both restore passes.
	logic [6:0] validate_seen_q;
	logic [6:0] write_seen_q;
	logic       validation_failed_q;
	logic       write_failed_q;
	// The requester holds a command through the response edge.  Admit it
	// exactly once and re-arm only after the command bus returns quiet.
	logic       request_seen_q;

	logic [63:0] expected_word;
	logic [63:0] staged_word;
	logic        address_valid;
	logic  [2:0] word_address;
	logic  [6:0] address_mask;
	logic  [6:0] validate_seen_next;
	logic  [6:0] write_seen_next;
	logic        validate_duplicate;
	logic        write_duplicate;
	logic        validate_match;
	logic        write_match;

	assign word_address = ssbus.req_addr[2:0];
	assign address_valid = ssbus.req_addr < WORD_COUNT;
	assign address_mask = address_valid ?
		(7'b000_0001 << word_address) : 7'b000_0000;
	assign validate_seen_next = validate_seen_q | address_mask;
	assign write_seen_next = write_seen_q | address_mask;
	assign validate_duplicate = |(validate_seen_q & address_mask);
	assign write_duplicate = |(write_seen_q & address_mask);
	assign validate_match = address_valid & (ssbus.req_data == expected_word);
	assign write_match = address_valid & (ssbus.req_data == staged_word);

	always_comb begin
		expected_word = 64'd0;
		staged_word = 64'd0;

		unique case (word_address)
			3'd0: begin
				expected_word = MAGIC;
				staged_word = staged_word0_q;
			end
			3'd1: begin
				expected_word = {SCHEMA_VERSION, CORE_ID};
				staged_word = staged_word1_q;
			end
			3'd2: begin
				expected_word = current_set_id_i;
				staged_word = staged_word2_q;
			end
			3'd3: begin
				expected_word = {
					24'd0,
					current_game_id_i,
					current_rom_length_i
				};
				staged_word = staged_word3_q;
			end
			3'd4: begin
				expected_word = current_rom_crc64_i;
				staged_word = staged_word4_q;
			end
			3'd5: begin
				expected_word = {16'd0, current_support_i};
				staged_word = staged_word5_q;
			end
			3'd6: begin
				expected_word = current_config_fingerprint_i;
				staged_word = staged_word6_q;
			end
			default: begin
				expected_word = 64'd0;
				staged_word = 64'd0;
			end
		endcase
	end

	always_ff @(posedge clk_i) begin
		if (reset_i) begin
			staged_word0_q <= 64'd0;
			staged_word1_q <= 64'd0;
			staged_word2_q <= 64'd0;
			staged_word3_q <= 64'd0;
			staged_word4_q <= 64'd0;
			staged_word5_q <= 64'd0;
			staged_word6_q <= 64'd0;
			validate_seen_q <= 7'b000_0000;
			write_seen_q <= 7'b000_0000;
			validation_failed_q <= 1'b0;
			write_failed_q <= 1'b0;
			request_seen_q <= 1'b0;
			validation_complete_o <= 1'b0;
			validation_valid_o <= 1'b0;
			metadata_commit_o <= 1'b0;
			metadata_committed_o <= 1'b0;
			ssbus.rsp_data <= 64'd0;
			ssbus.rsp_ack <= 1'b0;
			ssbus.rsp_error <= 1'b0;
		end else begin
			// Deterministic no-response defaults.  The mux converts the
			// transaction response into one upstream pulse and then drains it.
			ssbus.rsp_data <= 64'd0;
			ssbus.rsp_ack <= 1'b0;
			ssbus.rsp_error <= 1'b0;
			metadata_commit_o <= 1'b0;

			if (!ssbus.command_active())
				request_seen_q <= 1'b0;

			if (restore_begin_i) begin
				staged_word0_q <= 64'd0;
				staged_word1_q <= 64'd0;
				staged_word2_q <= 64'd0;
				staged_word3_q <= 64'd0;
				staged_word4_q <= 64'd0;
				staged_word5_q <= 64'd0;
				staged_word6_q <= 64'd0;
				validate_seen_q <= 7'b000_0000;
				write_seen_q <= 7'b000_0000;
				validation_failed_q <= 1'b0;
				write_failed_q <= 1'b0;
				request_seen_q <= 1'b0;
				validation_complete_o <= 1'b0;
				validation_valid_o <= 1'b0;
				metadata_committed_o <= 1'b0;
			end else if (ssbus.request_for(OWNER_INDEX) &&
			             !request_seen_q) begin
				request_seen_q <= 1'b1;
				if (ssbus.req_query) begin
					ssbus.rsp_data <= ssbus.query_descriptor(
						OWNER_INDEX,
						WORD_COUNT,
						WIDTH_CODE_64
					);
					ssbus.rsp_ack <= 1'b1;
				end else if (ssbus.req_read) begin
					ssbus.rsp_ack <= 1'b1;
					if (address_valid) begin
						ssbus.rsp_data <= expected_word;
					end else begin
						ssbus.rsp_error <= 1'b1;
					end
				end else if (ssbus.req_validate) begin
					ssbus.rsp_ack <= 1'b1;
					if (~address_valid | validate_duplicate |
					    ~validate_match) begin
						ssbus.rsp_error <= 1'b1;
						validation_failed_q <= 1'b1;
						validation_valid_o <= 1'b0;
					end

					if (address_valid & ~validate_duplicate) begin
						validate_seen_q <= validate_seen_next;
						unique case (word_address)
							3'd0: staged_word0_q <= ssbus.req_data;
							3'd1: staged_word1_q <= ssbus.req_data;
							3'd2: staged_word2_q <= ssbus.req_data;
							3'd3: staged_word3_q <= ssbus.req_data;
							3'd4: staged_word4_q <= ssbus.req_data;
							3'd5: staged_word5_q <= ssbus.req_data;
							3'd6: staged_word6_q <= ssbus.req_data;
							default: begin end
						endcase

						if (validate_seen_next == ALL_WORDS_SEEN) begin
							validation_complete_o <= 1'b1;
							validation_valid_o <=
								~validation_failed_q & validate_match;
						end
					end
				end else if (ssbus.req_write) begin
					ssbus.rsp_ack <= 1'b1;
					if (~validation_complete_o |
					    ~validation_valid_o |
					    ~address_valid |
					    write_duplicate |
					    ~write_match) begin
						ssbus.rsp_error <= 1'b1;
						write_failed_q <= 1'b1;
					end else begin
						write_seen_q <= write_seen_next;
						if ((write_seen_next == ALL_WORDS_SEEN) &
						    ~write_failed_q &
						    ~metadata_committed_o) begin
							metadata_commit_o <= 1'b1;
							metadata_committed_o <= 1'b1;
						end
					end
				end
			end
		end
	end

endmodule

`default_nettype wire
