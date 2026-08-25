// SPDX-License-Identifier: GPL-2.0-or-later
//
// CaveBanpresto-local ROM identity scanner. This module is intentionally not
// connected to the core yet; save-state support remains disabled.
//
// Direct-DDR MRA loads assert ioctl_download at index 0 but do not produce
// ioctl_wr pulses. The start-time ioctl_addr value is the exact byte length.
// After the index-0 frame closes, this block reads the final image from DDR and
// computes CRC64-ECMA (poly 0x42F0E1EBA9EA3693, init/xorout zero).
//
// Index 4 carries this fixed 32-byte, little-endian WIDE=1 record:
//   0x00  u32 magic           bytes "CBID" (words 16'h4243, 16'h4449)
//   0x04  u16 schema
//   0x06  u8  board_id
//   0x07  u8  flags             must match METADATA_FLAGS
//   0x08  u64 canonical_set_id
//   0x10  u32 assembled_length
//   0x14  u32 version/reserved  must match METADATA_VERSION
//   0x18  u64 expected_crc64
//
// mem_rd and mem_addr remain asserted/stable until mem_wait_n accepts the
// single-beat request. The request then drops while the scanner independently
// waits for mem_valid. Abort, overlap, or timeout after acceptance marks the
// result invalid immediately but drains the outstanding response before idle.
module CaveBanprestoRomIdentity #(
    parameter [31:0] ROM_DDR_BASE = 32'h3000_0000,
    parameter [31:0] MAX_ROM_BYTES = 32'h0800_0000,
    parameter [31:0] METADATA_MAGIC = 32'h4449_4243,
    parameter [15:0] METADATA_SCHEMA = 16'h0001,
    parameter [7:0]  METADATA_FLAGS = 8'h00,
    parameter [31:0] METADATA_VERSION = 32'h0000_0001,
    parameter [31:0] DDR_TIMEOUT_CYCLES = 32'd1_000_000
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        abort,

    input  wire        ioctl_download,
    input  wire        ioctl_wr,
    input  wire [7:0]  ioctl_index,
    input  wire [26:0] ioctl_addr,
    input  wire [15:0] ioctl_dout,

    input  wire [7:0]  runtime_board_id,
    input  wire        runtime_board_valid,

    output wire        mem_rd,
    output wire [31:0] mem_addr,
    input  wire [63:0] mem_dout,
    input  wire        mem_wait_n,
    input  wire        mem_valid,

    output wire        busy,
    output reg         scan_done,
    output reg         metadata_done,
    output wire        identity_valid,
    output wire        identity_error,
    output wire [7:0]  error_flags,

    output reg  [31:0] rom_length,
    output reg  [63:0] rom_crc64,
    output reg  [63:0] canonical_set_id,
    output reg  [7:0]  metadata_board_id
);

    localparam [7:0] IOCTL_INDEX_ROM = 8'h00;
    localparam [7:0] IOCTL_INDEX_METADATA = 8'h04;
    localparam [4:0] METADATA_WORDS = 5'd16;

    typedef enum logic [2:0] {
        ScanIdle  = 3'd0,
        ScanIssue = 3'd1,
        ScanWait  = 3'd2,
        ScanHash  = 3'd3,
        ScanDrain = 3'd4
    } scan_state_e;

    reg        download_d;
    reg [7:0]  frame_index;

    reg [4:0]  metadata_word_count;
    reg        metadata_sequence_error;
    reg        metadata_frame_error;
    reg [31:0] metadata_magic;
    reg [15:0] metadata_schema;
    reg [7:0]  metadata_flags;
    reg [31:0] metadata_length;
    reg [31:0] metadata_version;
    reg [63:0] metadata_crc64;

    scan_state_e scan_state;
    reg          scan_error;
    reg [31:0]   scan_offset;
    reg [63:0]   crc_state;
    reg [63:0]   beat_data;
    reg [2:0]    beat_byte_index;
    reg [3:0]    beat_byte_count;
    reg [31:0]   ddr_watchdog;

    wire download_rise = ioctl_download && !download_d;
    wire download_fall = !ioctl_download && download_d;
    wire rom_epoch_start =
        download_rise && (ioctl_index == IOCTL_INDEX_ROM);
    wire rom_frame_end =
        download_fall && (frame_index == IOCTL_INDEX_ROM);
    wire metadata_frame_start =
        download_rise && (ioctl_index == IOCTL_INDEX_METADATA);
    wire metadata_frame_end =
        download_fall && (frame_index == IOCTL_INDEX_METADATA);
    wire metadata_word_write =
        ioctl_download && ioctl_wr &&
        (ioctl_index == IOCTL_INDEX_METADATA);

    wire [31:0] bytes_remaining = rom_length - scan_offset;
    wire [3:0] incoming_byte_count =
        (bytes_remaining >= 32'd8) ? 4'd8 : bytes_remaining[3:0];
    function automatic [7:0] select_beat_byte;
        input [63:0] word_value;
        input [2:0]  byte_index;
        begin
            case (byte_index)
                3'd0: select_beat_byte = word_value[7:0];
                3'd1: select_beat_byte = word_value[15:8];
                3'd2: select_beat_byte = word_value[23:16];
                3'd3: select_beat_byte = word_value[31:24];
                3'd4: select_beat_byte = word_value[39:32];
                3'd5: select_beat_byte = word_value[47:40];
                3'd6: select_beat_byte = word_value[55:48];
                default: select_beat_byte = word_value[63:56];
            endcase
        end
    endfunction

    wire [7:0] current_byte =
        select_beat_byte(beat_data, beat_byte_index);

    function automatic [63:0] crc64_ecma_byte;
        input [63:0] crc;
        input [7:0]  byte_value;
        integer bit_index;
        reg [63:0] next_crc;
        begin
            next_crc = crc ^ {byte_value, 56'd0};
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                if (next_crc[63])
                    next_crc =
                        (next_crc << 1) ^ 64'h42f0_e1eb_a9ea_3693;
                else
                    next_crc = next_crc << 1;
            end
            crc64_ecma_byte = next_crc;
        end
    endfunction

    wire [63:0] crc_after_current_byte =
        crc64_ecma_byte(crc_state, current_byte);
    wire current_byte_is_last =
        ({1'b0, beat_byte_index} + 4'd1) == beat_byte_count;
    wire current_beat_is_last =
        (scan_offset + {28'd0, beat_byte_count}) >= rom_length;

    // IOCTL transfer edge tracking is kept separate from both the metadata
    // parser and the DDR scanner.
    always_ff @(posedge clk) begin
        if (reset) begin
            download_d <= 1'b0;
            frame_index <= 8'd0;
        end else begin
            download_d <= ioctl_download;
            if (download_rise)
                frame_index <= ioctl_index;
        end
    end

    // Fixed-size index-4 metadata parser.
    always_ff @(posedge clk) begin
        if (reset || rom_epoch_start) begin
            metadata_done <= 1'b0;
            metadata_word_count <= 5'd0;
            metadata_sequence_error <= 1'b0;
            metadata_frame_error <= 1'b0;
            metadata_magic <= 32'd0;
            metadata_schema <= 16'd0;
            metadata_board_id <= 8'd0;
            metadata_flags <= 8'd0;
            canonical_set_id <= 64'd0;
            metadata_length <= 32'd0;
            metadata_version <= 32'd0;
            metadata_crc64 <= 64'd0;
        end else if (metadata_frame_start) begin
            metadata_done <= 1'b0;
            metadata_word_count <= 5'd0;
            metadata_sequence_error <= 1'b0;
            metadata_frame_error <= 1'b0;
            metadata_magic <= 32'd0;
            metadata_schema <= 16'd0;
            metadata_board_id <= 8'd0;
            metadata_flags <= 8'd0;
            canonical_set_id <= 64'd0;
            metadata_length <= 32'd0;
            metadata_version <= 32'd0;
            metadata_crc64 <= 64'd0;
        end else begin
            if (metadata_word_write) begin
                if ((metadata_word_count >= METADATA_WORDS) ||
                    ioctl_addr[0] ||
                    (ioctl_addr != {21'd0, metadata_word_count, 1'b0}))
                    metadata_sequence_error <= 1'b1;

                if (metadata_word_count < METADATA_WORDS) begin
                    case (metadata_word_count)
                        5'd0:  metadata_magic[15:0] <= ioctl_dout;
                        5'd1:  metadata_magic[31:16] <= ioctl_dout;
                        5'd2:  metadata_schema <= ioctl_dout;
                        5'd3: begin
                            metadata_board_id <= ioctl_dout[7:0];
                            metadata_flags <= ioctl_dout[15:8];
                        end
                        5'd4:  canonical_set_id[15:0] <= ioctl_dout;
                        5'd5:  canonical_set_id[31:16] <= ioctl_dout;
                        5'd6:  canonical_set_id[47:32] <= ioctl_dout;
                        5'd7:  canonical_set_id[63:48] <= ioctl_dout;
                        5'd8:  metadata_length[15:0] <= ioctl_dout;
                        5'd9:  metadata_length[31:16] <= ioctl_dout;
                        5'd10: metadata_version[15:0] <= ioctl_dout;
                        5'd11: metadata_version[31:16] <= ioctl_dout;
                        5'd12: metadata_crc64[15:0] <= ioctl_dout;
                        5'd13: metadata_crc64[31:16] <= ioctl_dout;
                        5'd14: metadata_crc64[47:32] <= ioctl_dout;
                        5'd15: metadata_crc64[63:48] <= ioctl_dout;
                        default: ;
                    endcase
                    metadata_word_count <= metadata_word_count + 5'd1;
                end
            end

            if (metadata_frame_end) begin
                metadata_done <= 1'b1;
                metadata_frame_error <=
                    metadata_sequence_error ||
                    (metadata_word_count != METADATA_WORDS);
            end
        end
    end

    // One-beat DDR reader followed by an eight-cycle-at-most byte hasher.
    // Request acceptance and response completion are deliberately independent.
    always_ff @(posedge clk) begin
        if (reset) begin
            scan_state <= ScanIdle;
            scan_done <= 1'b0;
            scan_error <= 1'b0;
            scan_offset <= 32'd0;
            crc_state <= 64'd0;
            beat_data <= 64'd0;
            beat_byte_index <= 3'd0;
            beat_byte_count <= 4'd0;
            ddr_watchdog <= 32'd0;
            rom_length <= 32'd0;
            rom_crc64 <= 64'd0;
        end else if (abort && (scan_state != ScanIdle)) begin
            scan_done <= 1'b1;
            scan_error <= 1'b1;
            ddr_watchdog <= 32'd0;
            case (scan_state)
                // If acceptance and abort coincide, the response is already
                // owed unless it also returned in this cycle.
                ScanIssue:
                    scan_state <=
                        (mem_wait_n && !mem_valid) ? ScanDrain : ScanIdle;
                ScanWait,
                ScanDrain:
                    scan_state <= mem_valid ? ScanIdle : ScanDrain;
                default:
                    scan_state <= ScanIdle;
            endcase
        end else if (rom_epoch_start) begin
            scan_done <= 1'b0;
            rom_crc64 <= 64'd0;
            if (scan_state == ScanIdle) begin
                scan_error <= 1'b0;
                rom_length <= {5'd0, ioctl_addr};
                scan_offset <= 32'd0;
                crc_state <= 64'd0;
                beat_byte_index <= 3'd0;
                beat_byte_count <= 4'd0;
                ddr_watchdog <= 32'd0;
            end else begin
                scan_done <= 1'b1;
                scan_error <= 1'b1;
                rom_length <= 32'd0;
                ddr_watchdog <= 32'd0;
                case (scan_state)
                    ScanIssue:
                        scan_state <=
                            (mem_wait_n && !mem_valid) ?
                            ScanDrain : ScanIdle;
                    ScanWait,
                    ScanDrain:
                        scan_state <= mem_valid ? ScanIdle : ScanDrain;
                    default:
                        scan_state <= ScanIdle;
                endcase
            end
        end else begin
            if (rom_frame_end && (scan_state == ScanIdle)) begin
                scan_offset <= 32'd0;
                crc_state <= 64'd0;
                beat_byte_index <= 3'd0;
                beat_byte_count <= 4'd0;
                if ((rom_length == 32'd0) ||
                    (rom_length > MAX_ROM_BYTES)) begin
                    scan_done <= 1'b1;
                    scan_error <= 1'b1;
                end else begin
                    ddr_watchdog <= 32'd0;
                    scan_state <= ScanIssue;
                end
            end

            case (scan_state)
                ScanIssue: begin
                    if (mem_wait_n) begin
                        ddr_watchdog <= 32'd0;
                        if (mem_valid) begin
                            beat_data <= mem_dout;
                            beat_byte_index <= 3'd0;
                            beat_byte_count <= incoming_byte_count;
                            scan_state <= ScanHash;
                        end else begin
                            scan_state <= ScanWait;
                        end
                    end else if ((DDR_TIMEOUT_CYCLES != 32'd0) &&
                                 (ddr_watchdog >=
                                  (DDR_TIMEOUT_CYCLES - 32'd1))) begin
                        scan_state <= ScanIdle;
                        scan_done <= 1'b1;
                        scan_error <= 1'b1;
                        ddr_watchdog <= 32'd0;
                    end else begin
                        ddr_watchdog <= ddr_watchdog + 32'd1;
                    end
                end

                ScanWait: begin
                    if (mem_valid) begin
                        ddr_watchdog <= 32'd0;
                        beat_data <= mem_dout;
                        beat_byte_index <= 3'd0;
                        beat_byte_count <= incoming_byte_count;
                        scan_state <= ScanHash;
                    end else if ((DDR_TIMEOUT_CYCLES != 32'd0) &&
                                 (ddr_watchdog >=
                                  (DDR_TIMEOUT_CYCLES - 32'd1))) begin
                        // The command was accepted. Quarantine the scanner
                        // until its response arrives so it cannot be mistaken
                        // for data from a later epoch.
                        scan_state <= ScanDrain;
                        scan_done <= 1'b1;
                        scan_error <= 1'b1;
                        ddr_watchdog <= 32'd0;
                    end else begin
                        ddr_watchdog <= ddr_watchdog + 32'd1;
                    end
                end

                ScanDrain: begin
                    ddr_watchdog <= 32'd0;
                    if (mem_valid)
                        scan_state <= ScanIdle;
                end

                ScanHash: begin
                    ddr_watchdog <= 32'd0;
                    crc_state <= crc_after_current_byte;
                    if (current_byte_is_last) begin
                        beat_byte_index <= 3'd0;
                        if (current_beat_is_last) begin
                            rom_crc64 <= crc_after_current_byte;
                            scan_done <= 1'b1;
                            scan_state <= ScanIdle;
                        end else begin
                            scan_offset <= scan_offset + 32'd8;
                            scan_state <= ScanIssue;
                        end
                    end else begin
                        beat_byte_index <= beat_byte_index + 3'd1;
                    end
                end

                default: ;
            endcase
        end
    end

    assign mem_rd = scan_state == ScanIssue;
    assign mem_addr = ROM_DDR_BASE + scan_offset;
    assign busy = scan_state != ScanIdle;

    wire metadata_semantic_ready =
        metadata_done && !metadata_frame_error;
    wire scan_semantic_ready = scan_done && !scan_error;

    assign error_flags[0] = scan_error;
    assign error_flags[1] = metadata_frame_error;
    assign error_flags[2] =
        metadata_semantic_ready && (metadata_magic != METADATA_MAGIC);
    assign error_flags[3] =
        metadata_semantic_ready &&
        ((metadata_schema != METADATA_SCHEMA) ||
         (metadata_flags != METADATA_FLAGS) ||
         (metadata_version != METADATA_VERSION));
    assign error_flags[4] =
        metadata_semantic_ready && runtime_board_valid &&
        (metadata_board_id != runtime_board_id);
    assign error_flags[5] =
        metadata_semantic_ready && scan_semantic_ready &&
        (metadata_length != rom_length);
    assign error_flags[6] =
        metadata_semantic_ready && scan_semantic_ready &&
        (metadata_crc64 != rom_crc64);
    assign error_flags[7] =
        metadata_semantic_ready && (canonical_set_id == 64'd0);

    assign identity_valid =
        scan_done && metadata_done && runtime_board_valid &&
        (error_flags == 8'd0);
    assign identity_error = error_flags != 8'd0;

endmodule
