// SPDX-License-Identifier: GPL-2.0-or-later
//
// CaveBanpresto-local, support-disabled save-state transport helpers.
// These blocks deliberately separate request acceptance from read response
// completion and keep every level request and payload stable under stall.

module CaveBanprestoCrc64Word (
    input  wire        clk,
    input  wire        reset,
    input  wire        abort,
    input  wire        start,
    input  wire [63:0] crc_in,
    input  wire [63:0] word_in,
    output wire        busy,
    output reg         done,
    output reg  [63:0] crc_out
);

    // Justification: state across the eight byte-update cycles.
    reg        active;
    // Justification: selects the next byte in ascending DDR byte order.
    reg [2:0]  byte_index;
    // Justification: holds the stalled input word for the complete operation.
    reg [63:0] word_q;
    // Justification: carries the CRC between byte-update cycles.
    reg [63:0] crc_q;

    function automatic [63:0] crc64_ecma_byte;
        input [63:0] crc;
        input [7:0]  byte_value;
        integer bit_index;
        reg [63:0] next_crc;
        begin
            next_crc = crc ^ {byte_value, 56'd0};
            for (bit_index = 0; bit_index < 8;
                 bit_index = bit_index + 1) begin
                if (next_crc[63])
                    next_crc =
                        (next_crc << 1) ^ 64'h42f0_e1eb_a9ea_3693;
                else
                    next_crc = next_crc << 1;
            end
            crc64_ecma_byte = next_crc;
        end
    endfunction

    wire [5:0] current_byte_shift = {byte_index, 3'b000};
    wire [63:0] current_word_shifted = word_q >> current_byte_shift;
    wire [7:0] current_byte = current_word_shifted[7:0];
    wire [63:0] crc_next = crc64_ecma_byte(crc_q, current_byte);

    assign busy = active;

    always_ff @(posedge clk) begin
        if (reset) begin
            active <= 1'b0;
            byte_index <= 3'd0;
            word_q <= 64'd0;
            crc_q <= 64'd0;
            crc_out <= 64'd0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;

            if (abort) begin
                active <= 1'b0;
                byte_index <= 3'd0;
            end else if (!active) begin
                if (start) begin
                    active <= 1'b1;
                    byte_index <= 3'd0;
                    word_q <= word_in;
                    crc_q <= crc_in;
                end
            end else begin
                crc_q <= crc_next;
                if (byte_index == 3'd7) begin
                    active <= 1'b0;
                    byte_index <= 3'd0;
                    crc_out <= crc_next;
                    done <= 1'b1;
                end else begin
                    byte_index <= byte_index + 3'd1;
                end
            end
        end
    end

endmodule

module CaveBanprestoSaveStateDdrBeat #(
    parameter [31:0] TIMEOUT_CYCLES = 32'd1_000_000
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        abort,

    input  wire        launch,
    input  wire        launch_write,
    input  wire [31:0] launch_byte_addr,
    input  wire [63:0] launch_wdata,
    input  wire [7:0]  launch_be,
    input  wire [7:0]  launch_burstcnt,

    output wire        busy,
    output reg         done,
    output reg         error,
    output reg  [63:0] rdata,

    output wire        cmd_valid,
    input  wire        cmd_ready,
    output wire        cmd_write,
    output wire [31:0] cmd_byte_addr,
    output wire [63:0] cmd_wdata,
    output wire [7:0]  cmd_be,
    output wire [7:0]  cmd_burstcnt,
    input  wire        rsp_valid,
    input  wire [63:0] rsp_rdata
);

    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_ISSUE = 2'd1;
    localparam [1:0] ST_WAIT  = 2'd2;
    localparam [1:0] ST_DRAIN = 2'd3;
    localparam integer TIMEOUT_WIDTH =
        (TIMEOUT_CYCLES <= 1) ? 1 : $clog2(TIMEOUT_CYCLES);

    // Justification: protocol state across command and response phases.
    reg [1:0] state;
    // Justification: records an abort while an accepted read still owns a reply.
    reg abort_pending;
    // Justification: bounds command acceptance and read response waits.
    reg [TIMEOUT_WIDTH-1:0] watchdog;
    // Justification: registered protocol payload held stable while not ready.
    reg        write_q;
    reg [31:0] byte_addr_q;
    reg [63:0] wdata_q;
    reg [7:0]  be_q;
    reg [7:0]  burstcnt_q;

    wire timeout =
        (TIMEOUT_CYCLES != 32'd0) &&
        (watchdog >= (TIMEOUT_CYCLES - 1'b1));
    wire launch_burst_legal = launch_burstcnt == 8'd1;

    assign busy = state != ST_IDLE;
    // Abort withdraws an unaccepted command combinationally. The sequential
    // state transition below gives abort the same priority even when ready is
    // high, so the physical interface and helper accounting cannot disagree.
    assign cmd_valid = (state == ST_ISSUE) && !abort;
    assign cmd_write = write_q;
    assign cmd_byte_addr = byte_addr_q;
    assign cmd_wdata = wdata_q;
    assign cmd_be = be_q;
    assign cmd_burstcnt = burstcnt_q;

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= ST_IDLE;
            abort_pending <= 1'b0;
            watchdog <= {TIMEOUT_WIDTH{1'b0}};
            write_q <= 1'b0;
            byte_addr_q <= 32'd0;
            wdata_q <= 64'd0;
            be_q <= 8'd0;
            burstcnt_q <= 8'd1;
            done <= 1'b0;
            error <= 1'b0;
            rdata <= 64'd0;
        end else begin
            done <= 1'b0;

            case (state)
                ST_IDLE: begin
                    watchdog <= {TIMEOUT_WIDTH{1'b0}};
                    abort_pending <= 1'b0;
                    if (launch) begin
                        if (abort) begin
                            // Abort wins over admission. In particular, a
                            // one-cycle abort coincident with the final save
                            // commit launch must not leave a command behind.
                            done <= 1'b1;
                            error <= 1'b1;
                        end else if (!launch_burst_legal) begin
                            // This helper completes exactly one command beat
                            // and, for reads, exactly one response beat.
                            // Reject a malformed/multi-beat request locally
                            // so surplus replies cannot poison a later read.
                            done <= 1'b1;
                            error <= 1'b1;
                        end else begin
                            write_q <= launch_write;
                            byte_addr_q <= launch_byte_addr;
                            wdata_q <= launch_wdata;
                            be_q <= launch_be;
                            burstcnt_q <= launch_burstcnt;
                            error <= 1'b0;
                            state <= ST_ISSUE;
                        end
                    end
                end

                ST_ISSUE: begin
                    if (abort) begin
                        state <= ST_IDLE;
                        done <= 1'b1;
                        error <= 1'b1;
                        watchdog <= {TIMEOUT_WIDTH{1'b0}};
                    end else if (cmd_ready) begin
                        watchdog <= {TIMEOUT_WIDTH{1'b0}};
                        if (write_q) begin
                            state <= ST_IDLE;
                            done <= 1'b1;
                            error <= abort;
                        end else if (rsp_valid) begin
                            rdata <= rsp_rdata;
                            state <= ST_IDLE;
                            done <= 1'b1;
                            error <= abort;
                        end else begin
                            abort_pending <= abort;
                            state <= abort ? ST_DRAIN : ST_WAIT;
                        end
                    end else if (timeout) begin
                        state <= ST_IDLE;
                        done <= 1'b1;
                        error <= 1'b1;
                        watchdog <= {TIMEOUT_WIDTH{1'b0}};
                    end else begin
                        watchdog <= watchdog + 1'b1;
                    end
                end

                ST_WAIT: begin
                    if (abort) begin
                        abort_pending <= 1'b1;
                        state <= ST_DRAIN;
                    end

                    if (rsp_valid) begin
                        rdata <= rsp_rdata;
                        state <= ST_IDLE;
                        done <= 1'b1;
                        error <= abort || abort_pending;
                        abort_pending <= 1'b0;
                        watchdog <= {TIMEOUT_WIDTH{1'b0}};
                    end else if (timeout) begin
                        // A missing accepted read reply poisons the transport.
                        // Stay in drain so no later command can consume the
                        // stale reply. The caller keeps the machine frozen;
                        // an eventual reply drains it, otherwise reset clears
                        // the framework's safe DDR path.
                        state <= ST_DRAIN;
                        done <= 1'b1;
                        error <= 1'b1;
                        // Completion has been reported. The outstanding
                        // response remains quarantined, but its eventual
                        // drain must not complete the launch a second time.
                        abort_pending <= 1'b0;
                        watchdog <= {TIMEOUT_WIDTH{1'b0}};
                    end else begin
                        watchdog <= watchdog + 1'b1;
                    end
                end

                ST_DRAIN: begin
                    if (rsp_valid) begin
                        rdata <= rsp_rdata;
                        state <= ST_IDLE;
                        done <= abort_pending;
                        error <= 1'b1;
                        abort_pending <= 1'b0;
                        watchdog <= {TIMEOUT_WIDTH{1'b0}};
                    end else if (timeout) begin
                        state <= ST_DRAIN;
                        // An explicit abort has not yet completed until its
                        // response drains or this bounded wait expires. A
                        // read-response timeout was already reported before
                        // entering ST_DRAIN and therefore stays silent here.
                        done <= abort_pending;
                        error <= 1'b1;
                        abort_pending <= 1'b0;
                        watchdog <= {TIMEOUT_WIDTH{1'b0}};
                    end else begin
                        watchdog <= watchdog + 1'b1;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                    done <= 1'b1;
                    error <= 1'b1;
                end
            endcase
        end
    end

endmodule

module CaveBanprestoSaveStateOwnerCommand #(
    parameter [31:0] TIMEOUT_CYCLES = 32'd1_000_000
) (
    input  wire       clk,
    input  wire       reset,
    input  wire       abort,

    input  wire       launch,
    input  wire [2:0] launch_command,
    input  wire [7:0] launch_select,
    input  wire [31:0] launch_addr,
    input  wire [63:0] launch_data,

    output wire       busy,
    output reg        done,
    output reg        error,
    output reg [63:0] response_data,
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
    output reg [3:0]  debug_error_reason,
`endif

    cavebanpresto_ssbus_if.requester ssbus
);

    localparam [2:0] CMD_READ     = 3'd0;
    localparam [2:0] CMD_WRITE    = 3'd1;
    localparam [2:0] CMD_VALIDATE = 3'd2;
    localparam [2:0] CMD_QUERY    = 3'd3;

    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_ISSUE = 2'd1;
    localparam [1:0] ST_REARM = 2'd2;
    localparam integer TIMEOUT_WIDTH =
        (TIMEOUT_CYCLES <= 1) ? 1 : $clog2(TIMEOUT_CYCLES);

    // Justification: protocol state and stale-response rearm across cycles.
    reg [1:0] state;
    // Justification: bounds a missing owner response.
    reg [TIMEOUT_WIDTH-1:0] watchdog;
    // Justification: registered request payload held stable until response.
    reg [2:0]  command_q;
    reg [7:0]  select_q;
    reg [31:0] addr_q;
    reg [63:0] data_q;

    wire timeout =
        (TIMEOUT_CYCLES != 32'd0) &&
        (watchdog >= (TIMEOUT_CYCLES - 1'b1));

    assign busy = state != ST_IDLE;

    always_comb begin
        ssbus.req_data = data_q;
        ssbus.req_addr = addr_q;
        ssbus.req_select = select_q;
        ssbus.req_read = 1'b0;
        ssbus.req_write = 1'b0;
        ssbus.req_validate = 1'b0;
        ssbus.req_query = 1'b0;

        // Withdraw the destination request before the abort edge. Otherwise a
        // responder could still perform a write on the same edge on which the
        // helper reports that the operation was canceled.
        if ((state == ST_ISSUE) && !abort) begin
            case (command_q)
                CMD_READ: ssbus.req_read = 1'b1;
                CMD_WRITE: ssbus.req_write = 1'b1;
                CMD_VALIDATE: ssbus.req_validate = 1'b1;
                CMD_QUERY: ssbus.req_query = 1'b1;
                default: ;
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= ST_IDLE;
            watchdog <= {TIMEOUT_WIDTH{1'b0}};
            command_q <= CMD_READ;
            select_q <= 8'd0;
            addr_q <= 32'd0;
            data_q <= 64'd0;
            done <= 1'b0;
            error <= 1'b0;
            response_data <= 64'd0;
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
            debug_error_reason <= 4'd0;
`endif
        end else begin
            done <= 1'b0;

            case (state)
                ST_IDLE: begin
                    watchdog <= {TIMEOUT_WIDTH{1'b0}};
                    if (launch) begin
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
                        debug_error_reason <= 4'd0;
`endif
                        if (abort) begin
                            // Match the DDR helper: an abort on the launch
                            // edge completes locally and creates no request.
                            done <= 1'b1;
                            error <= 1'b1;
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
                            debug_error_reason <= 4'b0001;
`endif
                        end else begin
                            command_q <= launch_command;
                            select_q <= launch_select;
                            addr_q <= launch_addr;
                            data_q <= launch_data;
                            error <= 1'b0;
                            if (launch_command > CMD_QUERY) begin
                                done <= 1'b1;
                                error <= 1'b1;
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
                                debug_error_reason <= 4'b1000;
`endif
                            end else begin
                                state <= ST_ISSUE;
                            end
                        end
                    end
                end

                ST_ISSUE: begin
                    if (abort) begin
                        done <= 1'b1;
                        error <= 1'b1;
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
                        debug_error_reason <= 4'b0001;
`endif
                        state <= ssbus.rsp_ack ? ST_REARM : ST_IDLE;
                        watchdog <= {TIMEOUT_WIDTH{1'b0}};
                    end else if (ssbus.rsp_ack) begin
                        response_data <= ssbus.rsp_data;
                        done <= 1'b1;
                        error <= ssbus.rsp_error;
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
                        debug_error_reason <= ssbus.rsp_error
                            ? 4'b0010 : 4'b0000;
`endif
                        state <= ST_REARM;
                        watchdog <= {TIMEOUT_WIDTH{1'b0}};
                    end else if (timeout) begin
                        done <= 1'b1;
                        error <= 1'b1;
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
                        debug_error_reason <= 4'b0100;
`endif
                        state <= ST_REARM;
                        watchdog <= {TIMEOUT_WIDTH{1'b0}};
                    end else begin
                        watchdog <= watchdog + 1'b1;
                    end
                end

                ST_REARM: begin
                    watchdog <= {TIMEOUT_WIDTH{1'b0}};
                    if (!ssbus.rsp_ack)
                        state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                    done <= 1'b1;
                    error <= 1'b1;
`ifdef CAVEBANPRESTO_SS_RELEASE_HW_DIAGNOSTIC
                    debug_error_reason <= 4'b1000;
`endif
                end
            endcase
        end
    end

endmodule
