`default_nettype none

// GENERATED FILE - DO NOT EDIT.
// Generator: scripts/generate_cavebanpresto_ikaopm_exact.py
// Pinned source hashes:
//   IKAOPM.v: C241ED442BA181C36F8D3BC4CF9C857322370828C3D0134B756EC18ECFC4C2CE
//   IKAOPM_modules/IKAOPM_acc.v: 228D65884F3264347F049C03B594571C538C29061BEEDAB3CB96BEA25CC7C259
//   IKAOPM_modules/IKAOPM_eg.v: 407E666BC4D2F27D5715A718ADEC9B7FE8577BEF6F302CF9316BFC8D9EEA102E
//   IKAOPM_modules/IKAOPM_lfo.v: 76826401406B5E1A0C8C2E49D48232959F414C2CD3982523FB53C242CC6AB0E5
//   IKAOPM_modules/IKAOPM_noise.v: CFAFDF4B03DA88046E2F6F54E3D853F15D8B9D5F0050FDACE95C403F4C8BAE18
//   IKAOPM_modules/IKAOPM_op.v: 7E12834823CA6292673FB1842AFBC562A48D81FDCE41E92F010975F65A7DC07C
//   IKAOPM_modules/IKAOPM_pg.v: 48463500311C83F0933CB065B29E6FFB8248EA2F00D69173796E30CBA3F56797
//   IKAOPM_modules/IKAOPM_primitives.v: E4E02E7E159B26ECF0E6CD8A8C2EBC66BA651F7C9628BD92269537EE0F567AC0
//   IKAOPM_modules/IKAOPM_reg.v: EF5AACF1092193977AF00517AB3A10F28A96F75D4E1C54B48662D4AA7025D25F
//   IKAOPM_modules/IKAOPM_timer.v: 26CE3AE0061AD2621D0E04E0BB4BC755DEE7728B6B9ED4F1830D673A8A9C195F
//   IKAOPM_modules/IKAOPM_timinggen.v: BD4554FEDC2B8D285DA6F25019E7EEDD8353D0CF6E1E9AF7395CE706D5A6E4F8
//
// Exact-state layout (32-bit words, owner 27):
//   0..1     timing generator
//   2..61    register/bus/ring state
//   62..63   noise
//   64..68   LFO
//   69..107  phase generator
//   108..125 envelope generator
//   126..146 operator
//   147..155 accumulator/output
//   156..157 timers/IRQ
//   158       wrapper write stretcher and clock scheduler
//   159       reserved, reads zero
//
// All emulation state is held by i_SS_HOLD. The eleven explicit
// primitive_sr_bram rings retain one synchronous registered-read
// RAM process. Plane-word scans re-prime o_Q_TAP from
// (restored rdcntr - 1) mod 32 before acknowledging.
// Generator-checked layout: 4859 live core bits, 197 zero holes.
module cavebanpresto_ikaopm_ss_srlatch (
    input   wire            i_S,
    input   wire            i_R,
    output  reg             o_Q
);

always @(*) begin
    case({i_S, i_R})
        2'b00: o_Q = o_Q;
        2'b01: o_Q = 1'b0;
        2'b10: o_Q = 1'b1;
        2'b11: o_Q = 1'b0; //invalid
    endcase
end

endmodule

module cavebanpresto_ikaopm_ss_dlatch #(parameter WIDTH = 8 ) (
    input   wire                    i_EN,
    input   wire    [WIDTH-1:0]     i_D,
    output  reg     [WIDTH-1:0]     o_Q
);

always @(*) begin
    if(i_EN) o_Q = i_D;
    else o_Q = o_Q;
end

endmodule


module cavebanpresto_ikaopm_ss_syncsrlatch #(parameter integer SS_BASE_BIT = 0) (
    input wire i_EMUCLK, input wire i_RST_n,
    input wire i_S, input wire i_R, output reg o_Q,
    input wire i_SS_HOLD, input wire i_SS_REQ, input wire i_SS_WRITE,
    input wire [7:0] i_SS_WORD_ADDR, input wire [31:0] i_SS_WDATA,
    output wire [31:0] o_SS_VALID_MASK, output wire o_SS_ACK,
    output wire o_SS_ERROR, output wire [31:0] o_SS_RDATA
);
localparam integer SS_WORD = SS_BASE_BIT / 32;
localparam integer SS_BIT = SS_BASE_BIT % 32;
reg ss_seen_q, ss_ack_q, ss_rdata_q;
wire ss_accept =
    i_SS_HOLD && i_SS_REQ && (i_SS_WORD_ADDR == SS_WORD) && !ss_seen_q;
assign o_SS_VALID_MASK =
    (i_SS_WORD_ADDR == SS_WORD) ? (32'h0000_0001 << SS_BIT) : 32'd0;
assign o_SS_ACK = ss_ack_q;
assign o_SS_ERROR = 1'b0;
assign o_SS_RDATA =
    ss_rdata_q ? (32'h0000_0001 << SS_BIT) : 32'd0;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_accept && i_SS_WRITE) o_Q <= i_SS_WDATA[SS_BIT];
    end else if (!i_RST_n) o_Q <= 1'b0;
    else case ({i_S, i_R})
        2'b00: o_Q <= o_Q;
        2'b01: o_Q <= 1'b0;
        2'b10: o_Q <= 1'b1;
        2'b11: o_Q <= 1'b0;
    endcase
end
always @(posedge i_EMUCLK) begin
    if (!i_SS_HOLD) begin
        ss_seen_q <= 1'b0; ss_ack_q <= 1'b0; ss_rdata_q <= 1'b0;
    end else begin
        ss_ack_q <= 1'b0;
        if (!i_SS_REQ) ss_seen_q <= 1'b0;
        if (ss_accept) begin
            ss_seen_q <= 1'b1; ss_ack_q <= 1'b1;
            ss_rdata_q <= o_Q;
        end
    end
end
endmodule



module cavebanpresto_ikaopm_ss_syncdlatch #(
    parameter WIDTH = 8, parameter integer SS_BASE_BIT = 0
) (
    input wire i_EMUCLK, input wire i_RST_n,
    input wire i_EN, input wire [WIDTH-1:0] i_D,
    output reg [WIDTH-1:0] o_Q,
    input wire i_SS_HOLD, input wire i_SS_REQ, input wire i_SS_WRITE,
    input wire [7:0] i_SS_WORD_ADDR, input wire [31:0] i_SS_WDATA,
    output reg [31:0] o_SS_VALID_MASK, output wire o_SS_ACK,
    output wire o_SS_ERROR, output wire [31:0] o_SS_RDATA
);
integer ss_read_lane;
integer ss_write_lane;
reg ss_seen_q, ss_ack_q;
reg [31:0] ss_read_data, ss_rdata_q;
wire ss_accept =
    i_SS_HOLD && i_SS_REQ && (|o_SS_VALID_MASK) && !ss_seen_q;
assign o_SS_ACK = ss_ack_q;
assign o_SS_ERROR = 1'b0;
assign o_SS_RDATA = ss_rdata_q & o_SS_VALID_MASK;
always @(*) begin
    o_SS_VALID_MASK = 32'd0;
    ss_read_data = 32'd0;
    for (
        ss_read_lane = 0;
        ss_read_lane < WIDTH;
        ss_read_lane = ss_read_lane + 1
    ) begin
        if (i_SS_WORD_ADDR == (SS_BASE_BIT + ss_read_lane) / 32) begin
            o_SS_VALID_MASK[(SS_BASE_BIT + ss_read_lane) % 32] = 1'b1;
            ss_read_data[(SS_BASE_BIT + ss_read_lane) % 32] =
                o_Q[ss_read_lane];
        end
    end
end
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_accept && i_SS_WRITE) begin
            for (
                ss_write_lane = 0;
                ss_write_lane < WIDTH;
                ss_write_lane = ss_write_lane + 1
            )
                if (i_SS_WORD_ADDR == (SS_BASE_BIT + ss_write_lane) / 32)
                    o_Q[ss_write_lane] <=
                        i_SS_WDATA[(SS_BASE_BIT + ss_write_lane) % 32];
        end
    end else if (!i_RST_n) o_Q <= {WIDTH{1'b0}};
    else if (i_EN) o_Q <= i_D;
end
always @(posedge i_EMUCLK) begin
    if (!i_SS_HOLD) begin
        ss_seen_q <= 1'b0; ss_ack_q <= 1'b0; ss_rdata_q <= 32'd0;
    end else begin
        ss_ack_q <= 1'b0;
        if (!i_SS_REQ) ss_seen_q <= 1'b0;
        if (ss_accept) begin
            ss_seen_q <= 1'b1; ss_ack_q <= 1'b1;
            ss_rdata_q <= ss_read_data;
        end
    end
end
endmodule



module cavebanpresto_ikaopm_ss_counter #(
    parameter WIDTH = 4, parameter integer SS_BASE_BIT = 0
) (
    input wire i_EMUCLK, input wire i_PCEN_n, input wire i_NCEN_n,
    input wire i_CNT, input wire i_LD, input wire i_RST,
    input wire [WIDTH-1:0] i_D, output wire [WIDTH-1:0] o_Q,
    output wire o_CO,
    input wire i_SS_HOLD, input wire i_SS_REQ, input wire i_SS_WRITE,
    input wire [7:0] i_SS_WORD_ADDR, input wire [31:0] i_SS_WDATA,
    output reg [31:0] o_SS_VALID_MASK, output wire o_SS_ACK,
    output wire o_SS_ERROR, output wire [31:0] o_SS_RDATA
);
localparam COUNTER_MAX = (2**WIDTH) - 1;
reg [WIDTH-1:0] counter;
reg counter_full;
integer ss_read_lane;
integer ss_write_lane;
reg ss_seen_q, ss_ack_q;
reg [31:0] ss_read_data, ss_rdata_q;
wire ss_accept =
    i_SS_HOLD && i_SS_REQ && (|o_SS_VALID_MASK) && !ss_seen_q;
assign o_SS_ACK = ss_ack_q;
assign o_SS_ERROR = 1'b0;
assign o_SS_RDATA = ss_rdata_q & o_SS_VALID_MASK;
always @(*) begin
    o_SS_VALID_MASK = 32'd0;
    ss_read_data = 32'd0;
    for (
        ss_read_lane = 0;
        ss_read_lane < WIDTH + 1;
        ss_read_lane = ss_read_lane + 1
    ) begin
        if (i_SS_WORD_ADDR == (SS_BASE_BIT + ss_read_lane) / 32) begin
            o_SS_VALID_MASK[
                (SS_BASE_BIT + ss_read_lane) % 32
            ] = 1'b1;
            if (ss_read_lane < WIDTH)
                ss_read_data[
                    (SS_BASE_BIT + ss_read_lane) % 32
                ] = counter[ss_read_lane];
            else
                ss_read_data[
                    (SS_BASE_BIT + ss_read_lane) % 32
                ] = counter_full;
        end
    end
end
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_accept && i_SS_WRITE) begin
            for (
                ss_write_lane = 0;
                ss_write_lane < WIDTH + 1;
                ss_write_lane = ss_write_lane + 1
            ) begin
                if (
                    i_SS_WORD_ADDR ==
                    (SS_BASE_BIT + ss_write_lane) / 32
                ) begin
                    if (ss_write_lane < WIDTH)
                        counter[ss_write_lane] <=
                            i_SS_WDATA[
                                (SS_BASE_BIT + ss_write_lane) % 32
                            ];
                    else
                        counter_full <=
                            i_SS_WDATA[
                                (SS_BASE_BIT + ss_write_lane) % 32
                            ];
                end
            end
        end
    end else begin
        if (!i_PCEN_n) begin
            if (i_RST) counter <= {WIDTH{1'b0}};
            else if (i_LD) counter <= i_D;
            else if (i_CNT)
                counter <= (counter == COUNTER_MAX) ?
                    {WIDTH{1'b0}} :
                    counter + {{(WIDTH - 1){1'b0}}, 1'b1};
        end
        if (!i_NCEN_n) counter_full <= counter == COUNTER_MAX;
    end
end
always @(posedge i_EMUCLK) begin
    if (!i_SS_HOLD) begin
        ss_seen_q <= 1'b0; ss_ack_q <= 1'b0; ss_rdata_q <= 32'd0;
    end else begin
        ss_ack_q <= 1'b0;
        if (!i_SS_REQ) ss_seen_q <= 1'b0;
        if (ss_accept) begin
            ss_seen_q <= 1'b1; ss_ack_q <= 1'b1;
            ss_rdata_q <= ss_read_data;
        end
    end
end
assign o_CO = counter_full & i_CNT;
assign o_Q = counter;
endmodule



module cavebanpresto_ikaopm_ss_sr #(
    parameter WIDTH = 1, parameter LENGTH = 32, parameter TAP = 32,
    parameter integer SS_BASE_BIT = 0
) (
    input wire i_EMUCLK, input wire i_CEN_n,
    input wire [WIDTH-1:0] i_D,
    output wire [WIDTH-1:0] o_Q_TAP,
    output wire [WIDTH-1:0] o_Q_LAST,
    input wire i_SS_HOLD, input wire i_SS_REQ, input wire i_SS_WRITE,
    input wire [7:0] i_SS_WORD_ADDR, input wire [31:0] i_SS_WDATA,
    output reg [31:0] o_SS_VALID_MASK, output wire o_SS_ACK,
    output wire o_SS_ERROR, output wire [31:0] o_SS_RDATA
);
reg [WIDTH-1:0] sr[0:LENGTH-1];
integer stage;
integer ss_write_stage;
integer ss_write_bit;
integer ss_read_stage;
integer ss_read_bit;
reg ss_seen_q, ss_ack_q;
reg [31:0] ss_read_data, ss_rdata_q;
wire ss_accept =
    i_SS_HOLD && i_SS_REQ && (|o_SS_VALID_MASK) && !ss_seen_q;
assign o_SS_ACK = ss_ack_q;
assign o_SS_ERROR = 1'b0;
assign o_SS_RDATA = ss_rdata_q & o_SS_VALID_MASK;
always @(*) begin
    o_SS_VALID_MASK = 32'd0;
    ss_read_data = 32'd0;
    for (
        ss_read_stage = 0;
        ss_read_stage < LENGTH;
        ss_read_stage = ss_read_stage + 1
    ) begin
        for (
            ss_read_bit = 0;
            ss_read_bit < WIDTH;
            ss_read_bit = ss_read_bit + 1
        ) begin
            if (
                i_SS_WORD_ADDR ==
                (
                    SS_BASE_BIT +
                    ss_read_stage * WIDTH +
                    ss_read_bit
                ) / 32
            ) begin
                o_SS_VALID_MASK[
                    (
                        SS_BASE_BIT +
                        ss_read_stage * WIDTH +
                        ss_read_bit
                    ) % 32
                ] = 1'b1;
                ss_read_data[
                    (
                        SS_BASE_BIT +
                        ss_read_stage * WIDTH +
                        ss_read_bit
                    ) % 32
                ] = sr[ss_read_stage][ss_read_bit];
            end
        end
    end
end
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_accept && i_SS_WRITE) begin
            for (
                ss_write_stage = 0;
                ss_write_stage < LENGTH;
                ss_write_stage = ss_write_stage + 1
            ) begin
                for (
                    ss_write_bit = 0;
                    ss_write_bit < WIDTH;
                    ss_write_bit = ss_write_bit + 1
                ) begin
                    if (
                        i_SS_WORD_ADDR ==
                        (
                            SS_BASE_BIT +
                            ss_write_stage * WIDTH +
                            ss_write_bit
                        ) / 32
                    )
                        sr[ss_write_stage][ss_write_bit] <=
                            i_SS_WDATA[
                                (
                                    SS_BASE_BIT +
                                    ss_write_stage * WIDTH +
                                    ss_write_bit
                                ) % 32
                            ];
                end
            end
        end
    end else if (!i_CEN_n) begin
        sr[0] <= i_D;
        for (stage = 1; stage < LENGTH; stage = stage + 1)
            sr[stage] <= sr[stage - 1];
    end
end
always @(posedge i_EMUCLK) begin
    if (!i_SS_HOLD) begin
        ss_seen_q <= 1'b0; ss_ack_q <= 1'b0; ss_rdata_q <= 32'd0;
    end else begin
        ss_ack_q <= 1'b0;
        if (!i_SS_REQ) ss_seen_q <= 1'b0;
        if (ss_accept) begin
            ss_seen_q <= 1'b1; ss_ack_q <= 1'b1;
            ss_rdata_q <= ss_read_data;
        end
    end
end
assign o_Q_LAST = sr[LENGTH-1];
assign o_Q_TAP = (TAP == 0) ? i_D : sr[TAP-1];
endmodule



module cavebanpresto_ikaopm_ss_sr_bram #(
    parameter WIDTH = 1, parameter LENGTH = 32, parameter TAP = 32,
    parameter integer SS_MEM_BASE_BIT = 0,
    parameter integer SS_META_BASE_BIT = WIDTH * LENGTH
) (
    input wire i_EMUCLK, input wire i_CEN_n,
    input wire i_CNTRRST, input wire i_WR,
    input wire [WIDTH-1:0] i_D,
    output wire [WIDTH-1:0] o_Q_TAP,
    input wire i_SS_HOLD, input wire i_SS_REQ, input wire i_SS_WRITE,
    input wire [7:0] i_SS_WORD_ADDR, input wire [31:0] i_SS_WDATA,
    output reg [31:0] o_SS_VALID_MASK, output wire o_SS_ACK,
    output wire o_SS_ERROR, output wire [31:0] o_SS_RDATA
);
function integer length_bin(input integer length);
    integer iter;
begin
    iter = 0;
    while (2**iter < length) iter = iter + 1;
    length_bin = iter;
end
endfunction
localparam LENGTH_BIN = length_bin(LENGTH);
localparam WRCNTR_INIT = 0;
localparam RDCNTR_INIT = {LENGTH - (TAP - 1)};
localparam [31:0] SS_MEM_BASE_WORD_WIDE = SS_MEM_BASE_BIT / 32;
localparam [31:0] SS_MEM_WIDTH_WORDS = WIDTH;
localparam [31:0] SS_MEM_LIMIT_WORD_WIDE =
    SS_MEM_BASE_WORD_WIDE + SS_MEM_WIDTH_WORDS;
localparam [31:0] SS_MEM_VALID_MASK =
    32'hffff_ffff >> (32 - LENGTH);
localparam [2:0] SS_IDLE = 3'd0;
localparam [2:0] SS_READ = 3'd1;
localparam [2:0] SS_WRITE = 3'd2;
localparam [2:0] SS_REPRIME = 3'd3;
localparam [2:0] SS_ACK = 3'd4;
localparam [2:0] SS_WAIT_RELEASE = 3'd5;

reg [LENGTH_BIN-1:0] wrcntr;
reg [LENGTH_BIN-1:0] rdcntr;
reg [WIDTH-1:0] sr_bram[0:LENGTH-1];
reg [2:0] ss_state_q;
reg [LENGTH_BIN-1:0] ss_cell_q;
reg [5:0] ss_plane_q;
reg [31:0] ss_write_data_q;
reg ss_ack_q;
reg [31:0] ss_rdata_q;
reg [31:0] ss_meta_read_data;
reg [WIDTH-1:0] ram_read_q;
reg ram_read_enable;
reg [LENGTH_BIN-1:0] ram_read_address;
reg ram_write_enable;
reg [LENGTH_BIN-1:0] ram_write_address;
reg [WIDTH-1:0] ram_write_data;
integer init_index;
integer ss_meta_read_bit;
integer ss_meta_write_bit;

wire [31:0] ss_word_addr_wide = {24'd0, i_SS_WORD_ADDR};
wire ss_mem_selected =
    (ss_word_addr_wide >= SS_MEM_BASE_WORD_WIDE) &&
    (ss_word_addr_wide < SS_MEM_LIMIT_WORD_WIDE);
wire [31:0] ss_plane_index_wide =
    ss_word_addr_wide - SS_MEM_BASE_WORD_WIDE;
wire ss_meta_selected = (|o_SS_VALID_MASK) && !ss_mem_selected;
wire ss_accept =
    i_SS_HOLD && (ss_state_q == SS_IDLE) &&
    i_SS_REQ && (|o_SS_VALID_MASK);
wire [LENGTH_BIN-1:0] ss_last_cell =
    LENGTH[LENGTH_BIN-1:0] -
    {{(LENGTH_BIN - 1){1'b0}}, 1'b1};
wire [LENGTH_BIN-1:0] ss_reprime_addr =
    (rdcntr == {LENGTH_BIN{1'b0}}) ?
    ss_last_cell : rdcntr - {{(LENGTH_BIN - 1){1'b0}}, 1'b1};
assign o_Q_TAP = ram_read_q;
assign o_SS_ACK = ss_ack_q;
assign o_SS_ERROR = 1'b0;
assign o_SS_RDATA = ss_rdata_q & o_SS_VALID_MASK;

always @(*) begin
    o_SS_VALID_MASK = 32'd0;
    ss_meta_read_data = 32'd0;
    if (ss_mem_selected)
        o_SS_VALID_MASK = SS_MEM_VALID_MASK;
    for (
        ss_meta_read_bit = 0;
        ss_meta_read_bit < 2 * LENGTH_BIN;
        ss_meta_read_bit = ss_meta_read_bit + 1
    ) begin
        if (
            i_SS_WORD_ADDR ==
            (SS_META_BASE_BIT + ss_meta_read_bit) / 32
        ) begin
            o_SS_VALID_MASK[
                (SS_META_BASE_BIT + ss_meta_read_bit) % 32
            ] = 1'b1;
            if (ss_meta_read_bit < LENGTH_BIN)
                ss_meta_read_data[
                    (SS_META_BASE_BIT + ss_meta_read_bit) % 32
                ] = wrcntr[ss_meta_read_bit];
            else
                ss_meta_read_data[
                    (SS_META_BASE_BIT + ss_meta_read_bit) % 32
                ] = rdcntr[ss_meta_read_bit - LENGTH_BIN];
        end
    end
end

function [WIDTH-1:0] replace_bit;
    input [WIDTH-1:0] value;
    input [5:0] bit_index;
    input bit_value;
    reg [WIDTH-1:0] result;
begin
    result = value;
    result[bit_index] = bit_value;
    replace_bit = result;
end
endfunction

initial begin
    for (init_index = 0; init_index < LENGTH; init_index = init_index + 1)
        sr_bram[init_index] = {WIDTH{1'b0}};
end

always @(*) begin
    ram_read_enable = 1'b0;
    ram_read_address = rdcntr;
    ram_write_enable = 1'b0;
    ram_write_address = wrcntr;
    ram_write_data = i_D;

    if (!i_SS_HOLD) begin
        if (!i_CEN_n) begin
            ram_read_enable = 1'b1;
            if (i_WR) ram_write_enable = 1'b1;
        end
    end else begin
        case (ss_state_q)
            SS_IDLE: begin
                if (ss_accept && ss_mem_selected) begin
                    ram_read_enable = 1'b1;
                    ram_read_address = {LENGTH_BIN{1'b0}};
                end
            end
            SS_READ: begin
                ram_read_enable = 1'b1;
                ram_read_address =
                    (ss_cell_q == ss_last_cell) ?
                    ss_reprime_addr :
                    ss_cell_q + {{(LENGTH_BIN - 1){1'b0}}, 1'b1};
            end
            SS_WRITE: begin
                ram_write_enable = 1'b1;
                ram_write_address = ss_cell_q;
                ram_write_data = replace_bit(
                    ram_read_q,
                    ss_plane_q,
                    ss_write_data_q[ss_cell_q]
                );
                if (ss_cell_q != ss_last_cell) begin
                    ram_read_enable = 1'b1;
                    ram_read_address =
                        ss_cell_q +
                        {{(LENGTH_BIN - 1){1'b0}}, 1'b1};
                end
            end
            SS_REPRIME: begin
                ram_read_enable = 1'b1;
                ram_read_address = ss_reprime_addr;
            end
            default: ;
        endcase
    end
end

// Canonical single-clock, registered-read RAM process.  Save-state access
// only changes the address/control mux in front of this existing port.
always @(posedge i_EMUCLK) begin
    if (ram_write_enable)
        sr_bram[ram_write_address] <= ram_write_data;
    if (ram_read_enable)
        ram_read_q <= sr_bram[ram_read_address];
end

always @(posedge i_EMUCLK) begin
    if (!i_SS_HOLD) begin
        if (!i_CEN_n) begin
            if (i_CNTRRST) begin
                wrcntr <= WRCNTR_INIT[LENGTH_BIN-1:0];
                rdcntr <= RDCNTR_INIT[LENGTH_BIN-1:0];
            end else begin
                wrcntr <= (wrcntr < LENGTH - 1) ?
                    wrcntr + {{(LENGTH_BIN - 1){1'b0}}, 1'b1} :
                    {LENGTH_BIN{1'b0}};
                rdcntr <= (rdcntr < LENGTH - 1) ?
                    rdcntr + {{(LENGTH_BIN - 1){1'b0}}, 1'b1} :
                    {LENGTH_BIN{1'b0}};
            end
        end
    end else if (
        ss_accept && i_SS_WRITE && ss_meta_selected
    ) begin
        for (
            ss_meta_write_bit = 0;
            ss_meta_write_bit < 2 * LENGTH_BIN;
            ss_meta_write_bit = ss_meta_write_bit + 1
        ) begin
            if (
                i_SS_WORD_ADDR ==
                (SS_META_BASE_BIT + ss_meta_write_bit) / 32
            ) begin
                if (ss_meta_write_bit < LENGTH_BIN)
                    wrcntr[ss_meta_write_bit] <=
                        i_SS_WDATA[
                            (
                                SS_META_BASE_BIT +
                                ss_meta_write_bit
                            ) % 32
                        ];
                else
                    rdcntr[ss_meta_write_bit - LENGTH_BIN] <=
                        i_SS_WDATA[
                            (
                                SS_META_BASE_BIT +
                                ss_meta_write_bit
                            ) % 32
                        ];
            end
        end
    end
end

always @(posedge i_EMUCLK) begin
    if (!i_SS_HOLD) begin
        ss_state_q <= SS_IDLE;
        ss_cell_q <= {LENGTH_BIN{1'b0}};
        ss_plane_q <= 6'd0;
        ss_write_data_q <= 32'd0;
        ss_ack_q <= 1'b0;
        ss_rdata_q <= 32'd0;
    end else begin
        ss_ack_q <= 1'b0;
        case (ss_state_q)
            SS_IDLE: begin
                if (ss_accept) begin
                    if (ss_mem_selected) begin
                        ss_cell_q <= {LENGTH_BIN{1'b0}};
                        ss_plane_q <= ss_plane_index_wide[5:0];
                        ss_write_data_q <= i_SS_WDATA;
                        ss_rdata_q <= 32'd0;
                        ss_state_q <=
                            i_SS_WRITE ? SS_WRITE : SS_READ;
                    end else if (i_SS_WRITE) begin
                        ss_state_q <= SS_REPRIME;
                    end else begin
                        ss_rdata_q <= ss_meta_read_data;
                        ss_ack_q <= 1'b1;
                        ss_state_q <= SS_WAIT_RELEASE;
                    end
                end
            end
            SS_READ: begin
                ss_rdata_q[ss_cell_q] <= ram_read_q[ss_plane_q];
                if (ss_cell_q == ss_last_cell)
                    ss_state_q <= SS_ACK;
                else
                    ss_cell_q <=
                        ss_cell_q +
                        {{(LENGTH_BIN - 1){1'b0}}, 1'b1};
            end
            SS_WRITE: begin
                if (ss_cell_q == ss_last_cell)
                    ss_state_q <= SS_REPRIME;
                else
                    ss_cell_q <=
                        ss_cell_q +
                        {{(LENGTH_BIN - 1){1'b0}}, 1'b1};
            end
            SS_REPRIME: begin
                ss_state_q <= SS_ACK;
            end
            SS_ACK: begin
                ss_ack_q <= 1'b1;
                ss_state_q <= SS_WAIT_RELEASE;
            end
            SS_WAIT_RELEASE: begin
                if (!i_SS_REQ) ss_state_q <= SS_IDLE;
            end
            default: ss_state_q <= SS_IDLE;
        endcase
    end
end
endmodule



module cavebanpresto_ikaopm_ss_loreg_decoder #(parameter integer SS_BASE_BIT = 0, parameter TARGET_ADDR = 8'h00 ) (
    //master clock
    input   wire            i_EMUCLK, //emulator master clock

    //internal clock
    input   wire            i_phi1_NCEN_n, //negative edge clock enable for emulation

    //address to be decoded
    input   wire    [7:0]   i_ADDR,

    input   wire            i_ADDR_LD,
    input   wire            i_DATA_LD,

    output  wire            o_REG_LD

,
    input   wire            i_SS_HOLD,
    input   wire            i_SS_REQ,
    input   wire            i_SS_WRITE,
    input   wire    [7:0]   i_SS_WORD_ADDR,
    input   wire    [31:0]  i_SS_WDATA,
    output  wire    [31:0]  o_SS_VALID_MASK,
    output  wire            o_SS_ACK,
    output  wire            o_SS_ERROR,
    output  wire    [31:0]  o_SS_RDATA
);

// Forward declarations for exact-state instrumentation.
wire ss_local_write_accept;
wire ss_local_accept;
reg ss_local_seen_q;
reg ss_local_ack_q;
reg [31:0] ss_local_rdata_q;
reg [31:0] ss_local_valid_mask;
reg [31:0] ss_local_read_data;


reg             loreg_addr_valid;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 0) / 32)
                loreg_addr_valid <= i_SS_WDATA[(SS_BASE_BIT + 0) % 32];
        end
    end else begin
        begin
            if(!i_phi1_NCEN_n) begin
                loreg_addr_valid <= ((TARGET_ADDR == i_ADDR) & i_ADDR_LD) | (loreg_addr_valid & ~i_ADDR_LD);
            end
        end
    end
end

assign  o_REG_LD = loreg_addr_valid & i_DATA_LD;


// CaveBanpresto exact-state word instrumentation.

always @(*) begin
    ss_local_valid_mask = 32'd0;
    ss_local_read_data = 32'd0;
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 0) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 0) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 0) % 32] = loreg_addr_valid;
    end
end

assign ss_local_accept =
    i_SS_HOLD && i_SS_REQ && (|ss_local_valid_mask) && !ss_local_seen_q;
assign ss_local_write_accept = ss_local_accept && i_SS_WRITE;

always @(posedge i_EMUCLK) begin
    if (!i_SS_HOLD) begin
        ss_local_seen_q <= 1'b0;
        ss_local_ack_q <= 1'b0;
        ss_local_rdata_q <= 32'd0;
    end else begin
        ss_local_ack_q <= 1'b0;
        if (!i_SS_REQ)
            ss_local_seen_q <= 1'b0;
        if (ss_local_accept) begin
            ss_local_seen_q <= 1'b1;
            ss_local_ack_q <= 1'b1;
            ss_local_rdata_q <= ss_local_read_data;
        end
    end
end

assign o_SS_VALID_MASK = ss_local_valid_mask;
assign o_SS_ACK = ss_local_ack_q;
assign o_SS_ERROR = 1'b0;
assign o_SS_RDATA = (ss_local_rdata_q & ss_local_valid_mask);


endmodule



module cavebanpresto_ikaopm_ss_fnumrom #(parameter integer SS_BASE_BIT = 0) (
    //master clock
    input   wire            i_EMUCLK, //emulator master clock

    //clock enable
    input   wire            i_CEN_n, //positive edge clock enable for emulation

    input   wire    [5:0]   i_ADDR,
    output  reg     [16:0]  o_DATA

,
    input   wire            i_SS_HOLD,
    input   wire            i_SS_REQ,
    input   wire            i_SS_WRITE,
    input   wire    [7:0]   i_SS_WORD_ADDR,
    input   wire    [31:0]  i_SS_WDATA,
    output  wire    [31:0]  o_SS_VALID_MASK,
    output  wire            o_SS_ACK,
    output  wire            o_SS_ERROR,
    output  wire    [31:0]  o_SS_RDATA
);

// Forward declarations for exact-state instrumentation.
wire ss_local_write_accept;
wire ss_local_accept;
reg ss_local_seen_q;
reg ss_local_ack_q;
reg [31:0] ss_local_rdata_q;
reg [31:0] ss_local_valid_mask;
reg [31:0] ss_local_read_data;


always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 0) / 32)
                o_DATA[0] <= i_SS_WDATA[(SS_BASE_BIT + 0) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 1) / 32)
                o_DATA[1] <= i_SS_WDATA[(SS_BASE_BIT + 1) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 2) / 32)
                o_DATA[2] <= i_SS_WDATA[(SS_BASE_BIT + 2) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 3) / 32)
                o_DATA[3] <= i_SS_WDATA[(SS_BASE_BIT + 3) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 4) / 32)
                o_DATA[4] <= i_SS_WDATA[(SS_BASE_BIT + 4) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 5) / 32)
                o_DATA[5] <= i_SS_WDATA[(SS_BASE_BIT + 5) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 6) / 32)
                o_DATA[6] <= i_SS_WDATA[(SS_BASE_BIT + 6) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 7) / 32)
                o_DATA[7] <= i_SS_WDATA[(SS_BASE_BIT + 7) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 8) / 32)
                o_DATA[8] <= i_SS_WDATA[(SS_BASE_BIT + 8) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 9) / 32)
                o_DATA[9] <= i_SS_WDATA[(SS_BASE_BIT + 9) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 10) / 32)
                o_DATA[10] <= i_SS_WDATA[(SS_BASE_BIT + 10) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 11) / 32)
                o_DATA[11] <= i_SS_WDATA[(SS_BASE_BIT + 11) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 12) / 32)
                o_DATA[12] <= i_SS_WDATA[(SS_BASE_BIT + 12) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 13) / 32)
                o_DATA[13] <= i_SS_WDATA[(SS_BASE_BIT + 13) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 14) / 32)
                o_DATA[14] <= i_SS_WDATA[(SS_BASE_BIT + 14) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 15) / 32)
                o_DATA[15] <= i_SS_WDATA[(SS_BASE_BIT + 15) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 16) / 32)
                o_DATA[16] <= i_SS_WDATA[(SS_BASE_BIT + 16) % 32];
        end
    end else begin
        if(!i_CEN_n) begin
            case(i_ADDR)
                6'h00: o_DATA <= 17'b010100_010011_1001_1;
                6'h01: o_DATA <= 17'b010100_100110_1001_1;
                6'h02: o_DATA <= 17'b010100_111001_1001_1;
                6'h03: o_DATA <= 17'b010101_001100_0010_1;
                6'h04: o_DATA <= 17'b010101_100000_0010_1;
                6'h05: o_DATA <= 17'b010101_110100_0010_1;
                6'h06: o_DATA <= 17'b010110_001000_1010_1;
                6'h07: o_DATA <= 17'b010110_011101_0010_1;
                6'h08: o_DATA <= 17'b010110_110010_1010_1;
                6'h09: o_DATA <= 17'b010111_000111_1010_1;
                6'h0A: o_DATA <= 17'b010111_011101_0011_1;
                6'h0B: o_DATA <= 17'b010111_110011_0011_1;
                6'h0C: o_DATA <= 17'b000000_000000_0000_0;
                6'h0D: o_DATA <= 17'b000000_000000_0000_0;
                6'h0E: o_DATA <= 17'b000000_000000_0000_0;
                6'h0F: o_DATA <= 17'b000000_000000_0000_0;

                6'h10: o_DATA <= 17'b011000_001001_0011_1;
                6'h11: o_DATA <= 17'b011000_011111_0011_1;
                6'h12: o_DATA <= 17'b011000_110110_1011_1;
                6'h13: o_DATA <= 17'b011001_001101_1011_1;
                6'h14: o_DATA <= 17'b011001_100101_1011_1;
                6'h15: o_DATA <= 17'b011001_111100_0100_1;
                6'h16: o_DATA <= 17'b011010_010101_0100_1;
                6'h17: o_DATA <= 17'b011010_101101_0100_1;
                6'h18: o_DATA <= 17'b011011_000110_1100_1;
                6'h19: o_DATA <= 17'b011011_011111_1100_1;
                6'h1A: o_DATA <= 17'b011011_111001_0101_1;
                6'h1B: o_DATA <= 17'b011100_010011_0101_1;
                6'h1C: o_DATA <= 17'b000000_000000_0000_0;
                6'h1D: o_DATA <= 17'b000000_000000_0000_0;
                6'h1E: o_DATA <= 17'b000000_000000_0000_0;
                6'h1F: o_DATA <= 17'b000000_000000_0000_0;

                6'h20: o_DATA <= 17'b011100_101101_0101_1;
                6'h21: o_DATA <= 17'b011101_001000_1101_1;
                6'h22: o_DATA <= 17'b011101_100011_1101_1;
                6'h23: o_DATA <= 17'b011101_111110_0110_1;
                6'h24: o_DATA <= 17'b011110_011010_0110_1;
                6'h25: o_DATA <= 17'b011110_110111_0110_1;
                6'h26: o_DATA <= 17'b011111_010011_1110_1;
                6'h27: o_DATA <= 17'b011111_110000_0111_1;
                6'h28: o_DATA <= 17'b100000_001110_0111_1;
                6'h29: o_DATA <= 17'b100000_101100_0111_1;
                6'h2A: o_DATA <= 17'b100001_001010_1111_1;
                6'h2B: o_DATA <= 17'b100001_101001_1111_1;
                6'h2C: o_DATA <= 17'b000000_000000_0000_0;
                6'h2D: o_DATA <= 17'b000000_000000_0000_0;
                6'h2E: o_DATA <= 17'b000000_000000_0000_0;
                6'h2F: o_DATA <= 17'b000000_000000_0000_0;

                6'h30: o_DATA <= 17'b100010_001001_1111_1;
                6'h31: o_DATA <= 17'b100010_101000_1111_0;
                6'h32: o_DATA <= 17'b100011_001001_1111_0;
                6'h33: o_DATA <= 17'b100011_101001_1111_0;
                6'h34: o_DATA <= 17'b100100_001011_1111_0;
                6'h35: o_DATA <= 17'b100100_101100_1111_0;
                6'h36: o_DATA <= 17'b100101_001110_0111_0;
                6'h37: o_DATA <= 17'b100101_110001_0111_0;
                6'h38: o_DATA <= 17'b100110_010100_0111_0;
                6'h39: o_DATA <= 17'b100110_111000_0111_0;
                6'h3A: o_DATA <= 17'b100111_011100_0111_0;
                6'h3B: o_DATA <= 17'b101000_000001_0111_0;
                6'h3C: o_DATA <= 17'b000000_000000_0000_0;
                6'h3D: o_DATA <= 17'b000000_000000_0000_0;
                6'h3E: o_DATA <= 17'b000000_000000_0000_0;
                6'h3F: o_DATA <= 17'b000000_000000_0000_0;
            endcase
        end
    end
end


// CaveBanpresto exact-state word instrumentation.

always @(*) begin
    ss_local_valid_mask = 32'd0;
    ss_local_read_data = 32'd0;
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 0) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 0) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 0) % 32] = o_DATA[0];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 1) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 1) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 1) % 32] = o_DATA[1];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 2) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 2) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 2) % 32] = o_DATA[2];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 3) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 3) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 3) % 32] = o_DATA[3];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 4) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 4) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 4) % 32] = o_DATA[4];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 5) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 5) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 5) % 32] = o_DATA[5];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 6) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 6) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 6) % 32] = o_DATA[6];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 7) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 7) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 7) % 32] = o_DATA[7];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 8) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 8) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 8) % 32] = o_DATA[8];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 9) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 9) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 9) % 32] = o_DATA[9];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 10) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 10) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 10) % 32] = o_DATA[10];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 11) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 11) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 11) % 32] = o_DATA[11];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 12) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 12) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 12) % 32] = o_DATA[12];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 13) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 13) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 13) % 32] = o_DATA[13];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 14) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 14) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 14) % 32] = o_DATA[14];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 15) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 15) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 15) % 32] = o_DATA[15];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 16) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 16) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 16) % 32] = o_DATA[16];
    end
end

assign ss_local_accept =
    i_SS_HOLD && i_SS_REQ && (|ss_local_valid_mask) && !ss_local_seen_q;
assign ss_local_write_accept = ss_local_accept && i_SS_WRITE;

always @(posedge i_EMUCLK) begin
    if (!i_SS_HOLD) begin
        ss_local_seen_q <= 1'b0;
        ss_local_ack_q <= 1'b0;
        ss_local_rdata_q <= 32'd0;
    end else begin
        ss_local_ack_q <= 1'b0;
        if (!i_SS_REQ)
            ss_local_seen_q <= 1'b0;
        if (ss_local_accept) begin
            ss_local_seen_q <= 1'b1;
            ss_local_ack_q <= 1'b1;
            ss_local_rdata_q <= ss_local_read_data;
        end
    end
end

assign o_SS_VALID_MASK = ss_local_valid_mask;
assign o_SS_ACK = ss_local_ack_q;
assign o_SS_ERROR = 1'b0;
assign o_SS_RDATA = (ss_local_rdata_q & ss_local_valid_mask);


endmodule



module cavebanpresto_ikaopm_ss_logsinrom #(parameter integer SS_BASE_BIT = 0) (
    //master clock
    input   wire            i_EMUCLK, //emulator master clock

    //clock enable
    input   wire            i_CEN_n, //positive edge clock enable for emulation

    input   wire    [4:0]   i_ADDR,
    output  reg     [45:0]  o_DATA

,
    input   wire            i_SS_HOLD,
    input   wire            i_SS_REQ,
    input   wire            i_SS_WRITE,
    input   wire    [7:0]   i_SS_WORD_ADDR,
    input   wire    [31:0]  i_SS_WDATA,
    output  wire    [31:0]  o_SS_VALID_MASK,
    output  wire            o_SS_ACK,
    output  wire            o_SS_ERROR,
    output  wire    [31:0]  o_SS_RDATA
);

// Forward declarations for exact-state instrumentation.
wire ss_local_write_accept;
wire ss_local_accept;
reg ss_local_seen_q;
reg ss_local_ack_q;
reg [31:0] ss_local_rdata_q;
reg [31:0] ss_local_valid_mask;
reg [31:0] ss_local_read_data;


always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 0) / 32)
                o_DATA[0] <= i_SS_WDATA[(SS_BASE_BIT + 0) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 1) / 32)
                o_DATA[1] <= i_SS_WDATA[(SS_BASE_BIT + 1) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 2) / 32)
                o_DATA[2] <= i_SS_WDATA[(SS_BASE_BIT + 2) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 3) / 32)
                o_DATA[3] <= i_SS_WDATA[(SS_BASE_BIT + 3) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 4) / 32)
                o_DATA[4] <= i_SS_WDATA[(SS_BASE_BIT + 4) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 5) / 32)
                o_DATA[5] <= i_SS_WDATA[(SS_BASE_BIT + 5) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 6) / 32)
                o_DATA[6] <= i_SS_WDATA[(SS_BASE_BIT + 6) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 7) / 32)
                o_DATA[7] <= i_SS_WDATA[(SS_BASE_BIT + 7) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 8) / 32)
                o_DATA[8] <= i_SS_WDATA[(SS_BASE_BIT + 8) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 9) / 32)
                o_DATA[9] <= i_SS_WDATA[(SS_BASE_BIT + 9) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 10) / 32)
                o_DATA[10] <= i_SS_WDATA[(SS_BASE_BIT + 10) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 11) / 32)
                o_DATA[11] <= i_SS_WDATA[(SS_BASE_BIT + 11) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 12) / 32)
                o_DATA[12] <= i_SS_WDATA[(SS_BASE_BIT + 12) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 13) / 32)
                o_DATA[13] <= i_SS_WDATA[(SS_BASE_BIT + 13) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 14) / 32)
                o_DATA[14] <= i_SS_WDATA[(SS_BASE_BIT + 14) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 15) / 32)
                o_DATA[15] <= i_SS_WDATA[(SS_BASE_BIT + 15) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 16) / 32)
                o_DATA[16] <= i_SS_WDATA[(SS_BASE_BIT + 16) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 17) / 32)
                o_DATA[17] <= i_SS_WDATA[(SS_BASE_BIT + 17) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 18) / 32)
                o_DATA[18] <= i_SS_WDATA[(SS_BASE_BIT + 18) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 19) / 32)
                o_DATA[19] <= i_SS_WDATA[(SS_BASE_BIT + 19) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 20) / 32)
                o_DATA[20] <= i_SS_WDATA[(SS_BASE_BIT + 20) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 21) / 32)
                o_DATA[21] <= i_SS_WDATA[(SS_BASE_BIT + 21) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 22) / 32)
                o_DATA[22] <= i_SS_WDATA[(SS_BASE_BIT + 22) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 23) / 32)
                o_DATA[23] <= i_SS_WDATA[(SS_BASE_BIT + 23) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 24) / 32)
                o_DATA[24] <= i_SS_WDATA[(SS_BASE_BIT + 24) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 25) / 32)
                o_DATA[25] <= i_SS_WDATA[(SS_BASE_BIT + 25) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 26) / 32)
                o_DATA[26] <= i_SS_WDATA[(SS_BASE_BIT + 26) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 27) / 32)
                o_DATA[27] <= i_SS_WDATA[(SS_BASE_BIT + 27) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 28) / 32)
                o_DATA[28] <= i_SS_WDATA[(SS_BASE_BIT + 28) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 29) / 32)
                o_DATA[29] <= i_SS_WDATA[(SS_BASE_BIT + 29) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 30) / 32)
                o_DATA[30] <= i_SS_WDATA[(SS_BASE_BIT + 30) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 31) / 32)
                o_DATA[31] <= i_SS_WDATA[(SS_BASE_BIT + 31) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 32) / 32)
                o_DATA[32] <= i_SS_WDATA[(SS_BASE_BIT + 32) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 33) / 32)
                o_DATA[33] <= i_SS_WDATA[(SS_BASE_BIT + 33) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 34) / 32)
                o_DATA[34] <= i_SS_WDATA[(SS_BASE_BIT + 34) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 35) / 32)
                o_DATA[35] <= i_SS_WDATA[(SS_BASE_BIT + 35) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 36) / 32)
                o_DATA[36] <= i_SS_WDATA[(SS_BASE_BIT + 36) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 37) / 32)
                o_DATA[37] <= i_SS_WDATA[(SS_BASE_BIT + 37) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 38) / 32)
                o_DATA[38] <= i_SS_WDATA[(SS_BASE_BIT + 38) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 39) / 32)
                o_DATA[39] <= i_SS_WDATA[(SS_BASE_BIT + 39) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 40) / 32)
                o_DATA[40] <= i_SS_WDATA[(SS_BASE_BIT + 40) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 41) / 32)
                o_DATA[41] <= i_SS_WDATA[(SS_BASE_BIT + 41) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 42) / 32)
                o_DATA[42] <= i_SS_WDATA[(SS_BASE_BIT + 42) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 43) / 32)
                o_DATA[43] <= i_SS_WDATA[(SS_BASE_BIT + 43) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 44) / 32)
                o_DATA[44] <= i_SS_WDATA[(SS_BASE_BIT + 44) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 45) / 32)
                o_DATA[45] <= i_SS_WDATA[(SS_BASE_BIT + 45) % 32];
        end
    end else begin
        if(!i_CEN_n) begin
            case(i_ADDR)
                5'd0 : o_DATA <= 46'b000110000010010001000100_0010101010101001010010;
                5'd1 : o_DATA <= 46'b000110000011010000010000_0010010001001101000001;
                5'd2 : o_DATA <= 46'b000110000011010000010011_0010001011001101100000;
                5'd3 : o_DATA <= 46'b000111000001000000000011_0010110001001101110010;
                5'd4 : o_DATA <= 46'b000111000001000000110000_0010111010001101101001;
                5'd5 : o_DATA <= 46'b000111000001010000100110_0010000000101101111010;
                5'd6 : o_DATA <= 46'b000111000001010000110110_0010010011001101011010;
                5'd7 : o_DATA <= 46'b000111000001110000010101_0010111000101111111100;

                5'd8 : o_DATA <= 46'b000111000011100000000111_0010101110001101110111;
                5'd9 : o_DATA <= 46'b000111000011100001010011_1000011101011010100110;
                5'd10: o_DATA <= 46'b000111000011110001100001_1000111100001001111010;
                5'd11: o_DATA <= 46'b000111000011110001110011_1001101011001001110111;
                5'd12: o_DATA <= 46'b010010000101000001000101_1001001000111010110111;
                5'd13: o_DATA <= 46'b010010000101010001000100_1001110001111100101010;
                5'd14: o_DATA <= 46'b010010000101010001010110_1101111110100101000110;
                5'd15: o_DATA <= 46'b010010001110000000100001_1001010110101101111001;

                5'd16: o_DATA <= 46'b010010001110010000100010_1011100101001011101111;
                5'd17: o_DATA <= 46'b010010001110110000011101_1010000001011010110001;
                5'd18: o_DATA <= 46'b010011001100100000011110_1010000010111010111111;
                5'd19: o_DATA <= 46'b010011001100110000101101_1110101110110110000001;
                5'd20: o_DATA <= 46'b010011001110100001101011_1011001010001101110001;
                5'd21: o_DATA <= 46'b010011001110110101101011_0101111001010100001111;
                5'd22: o_DATA <= 46'b011100001000000101011100_0101010101010110010111;
                5'd23: o_DATA <= 46'b011100001000010101011111_0111110101010010111011;

                5'd24: o_DATA <= 46'b011100001011010110100010_1100001000010000011001;
                5'd25: o_DATA <= 46'b011101001001100110010001_1110100100010010010010;
                5'd26: o_DATA <= 46'b011101001011101010010110_0101000000110100100011;
                5'd27: o_DATA <= 46'b101000001001101010110101_1101100001110010011010;
                5'd28: o_DATA <= 46'b101000001011111111110010_0111010100010000111001;
                5'd29: o_DATA <= 46'b101001011111010011001000_1100111001010110100000;
                5'd30: o_DATA <= 46'b101101011101001111101101_1110000100110010100001;
                5'd31: o_DATA <= 46'b111001101111000111101110_0111100001110110100111;
            endcase
        end
    end
end


// CaveBanpresto exact-state word instrumentation.

always @(*) begin
    ss_local_valid_mask = 32'd0;
    ss_local_read_data = 32'd0;
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 0) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 0) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 0) % 32] = o_DATA[0];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 1) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 1) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 1) % 32] = o_DATA[1];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 2) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 2) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 2) % 32] = o_DATA[2];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 3) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 3) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 3) % 32] = o_DATA[3];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 4) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 4) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 4) % 32] = o_DATA[4];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 5) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 5) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 5) % 32] = o_DATA[5];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 6) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 6) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 6) % 32] = o_DATA[6];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 7) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 7) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 7) % 32] = o_DATA[7];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 8) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 8) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 8) % 32] = o_DATA[8];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 9) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 9) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 9) % 32] = o_DATA[9];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 10) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 10) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 10) % 32] = o_DATA[10];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 11) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 11) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 11) % 32] = o_DATA[11];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 12) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 12) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 12) % 32] = o_DATA[12];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 13) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 13) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 13) % 32] = o_DATA[13];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 14) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 14) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 14) % 32] = o_DATA[14];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 15) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 15) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 15) % 32] = o_DATA[15];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 16) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 16) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 16) % 32] = o_DATA[16];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 17) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 17) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 17) % 32] = o_DATA[17];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 18) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 18) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 18) % 32] = o_DATA[18];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 19) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 19) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 19) % 32] = o_DATA[19];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 20) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 20) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 20) % 32] = o_DATA[20];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 21) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 21) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 21) % 32] = o_DATA[21];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 22) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 22) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 22) % 32] = o_DATA[22];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 23) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 23) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 23) % 32] = o_DATA[23];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 24) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 24) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 24) % 32] = o_DATA[24];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 25) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 25) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 25) % 32] = o_DATA[25];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 26) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 26) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 26) % 32] = o_DATA[26];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 27) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 27) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 27) % 32] = o_DATA[27];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 28) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 28) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 28) % 32] = o_DATA[28];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 29) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 29) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 29) % 32] = o_DATA[29];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 30) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 30) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 30) % 32] = o_DATA[30];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 31) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 31) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 31) % 32] = o_DATA[31];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 32) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 32) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 32) % 32] = o_DATA[32];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 33) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 33) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 33) % 32] = o_DATA[33];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 34) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 34) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 34) % 32] = o_DATA[34];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 35) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 35) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 35) % 32] = o_DATA[35];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 36) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 36) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 36) % 32] = o_DATA[36];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 37) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 37) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 37) % 32] = o_DATA[37];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 38) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 38) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 38) % 32] = o_DATA[38];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 39) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 39) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 39) % 32] = o_DATA[39];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 40) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 40) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 40) % 32] = o_DATA[40];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 41) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 41) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 41) % 32] = o_DATA[41];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 42) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 42) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 42) % 32] = o_DATA[42];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 43) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 43) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 43) % 32] = o_DATA[43];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 44) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 44) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 44) % 32] = o_DATA[44];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 45) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 45) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 45) % 32] = o_DATA[45];
    end
end

assign ss_local_accept =
    i_SS_HOLD && i_SS_REQ && (|ss_local_valid_mask) && !ss_local_seen_q;
assign ss_local_write_accept = ss_local_accept && i_SS_WRITE;

always @(posedge i_EMUCLK) begin
    if (!i_SS_HOLD) begin
        ss_local_seen_q <= 1'b0;
        ss_local_ack_q <= 1'b0;
        ss_local_rdata_q <= 32'd0;
    end else begin
        ss_local_ack_q <= 1'b0;
        if (!i_SS_REQ)
            ss_local_seen_q <= 1'b0;
        if (ss_local_accept) begin
            ss_local_seen_q <= 1'b1;
            ss_local_ack_q <= 1'b1;
            ss_local_rdata_q <= ss_local_read_data;
        end
    end
end

assign o_SS_VALID_MASK = ss_local_valid_mask;
assign o_SS_ACK = ss_local_ack_q;
assign o_SS_ERROR = 1'b0;
assign o_SS_RDATA = (ss_local_rdata_q & ss_local_valid_mask);


endmodule



module cavebanpresto_ikaopm_ss_exprom #(parameter integer SS_BASE_BIT = 0) (
    //master clock
    input   wire            i_EMUCLK, //emulator master clock

    //clock enable
    input   wire            i_CEN_n, //positive edge clock enable for emulation

    input   wire    [4:0]   i_ADDR,
    output  reg     [44:0]  o_DATA

,
    input   wire            i_SS_HOLD,
    input   wire            i_SS_REQ,
    input   wire            i_SS_WRITE,
    input   wire    [7:0]   i_SS_WORD_ADDR,
    input   wire    [31:0]  i_SS_WDATA,
    output  wire    [31:0]  o_SS_VALID_MASK,
    output  wire            o_SS_ACK,
    output  wire            o_SS_ERROR,
    output  wire    [31:0]  o_SS_RDATA
);

// Forward declarations for exact-state instrumentation.
wire ss_local_write_accept;
wire ss_local_accept;
reg ss_local_seen_q;
reg ss_local_ack_q;
reg [31:0] ss_local_rdata_q;
reg [31:0] ss_local_valid_mask;
reg [31:0] ss_local_read_data;


always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 0) / 32)
                o_DATA[0] <= i_SS_WDATA[(SS_BASE_BIT + 0) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 1) / 32)
                o_DATA[1] <= i_SS_WDATA[(SS_BASE_BIT + 1) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 2) / 32)
                o_DATA[2] <= i_SS_WDATA[(SS_BASE_BIT + 2) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 3) / 32)
                o_DATA[3] <= i_SS_WDATA[(SS_BASE_BIT + 3) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 4) / 32)
                o_DATA[4] <= i_SS_WDATA[(SS_BASE_BIT + 4) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 5) / 32)
                o_DATA[5] <= i_SS_WDATA[(SS_BASE_BIT + 5) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 6) / 32)
                o_DATA[6] <= i_SS_WDATA[(SS_BASE_BIT + 6) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 7) / 32)
                o_DATA[7] <= i_SS_WDATA[(SS_BASE_BIT + 7) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 8) / 32)
                o_DATA[8] <= i_SS_WDATA[(SS_BASE_BIT + 8) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 9) / 32)
                o_DATA[9] <= i_SS_WDATA[(SS_BASE_BIT + 9) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 10) / 32)
                o_DATA[10] <= i_SS_WDATA[(SS_BASE_BIT + 10) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 11) / 32)
                o_DATA[11] <= i_SS_WDATA[(SS_BASE_BIT + 11) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 12) / 32)
                o_DATA[12] <= i_SS_WDATA[(SS_BASE_BIT + 12) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 13) / 32)
                o_DATA[13] <= i_SS_WDATA[(SS_BASE_BIT + 13) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 14) / 32)
                o_DATA[14] <= i_SS_WDATA[(SS_BASE_BIT + 14) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 15) / 32)
                o_DATA[15] <= i_SS_WDATA[(SS_BASE_BIT + 15) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 16) / 32)
                o_DATA[16] <= i_SS_WDATA[(SS_BASE_BIT + 16) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 17) / 32)
                o_DATA[17] <= i_SS_WDATA[(SS_BASE_BIT + 17) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 18) / 32)
                o_DATA[18] <= i_SS_WDATA[(SS_BASE_BIT + 18) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 19) / 32)
                o_DATA[19] <= i_SS_WDATA[(SS_BASE_BIT + 19) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 20) / 32)
                o_DATA[20] <= i_SS_WDATA[(SS_BASE_BIT + 20) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 21) / 32)
                o_DATA[21] <= i_SS_WDATA[(SS_BASE_BIT + 21) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 22) / 32)
                o_DATA[22] <= i_SS_WDATA[(SS_BASE_BIT + 22) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 23) / 32)
                o_DATA[23] <= i_SS_WDATA[(SS_BASE_BIT + 23) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 24) / 32)
                o_DATA[24] <= i_SS_WDATA[(SS_BASE_BIT + 24) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 25) / 32)
                o_DATA[25] <= i_SS_WDATA[(SS_BASE_BIT + 25) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 26) / 32)
                o_DATA[26] <= i_SS_WDATA[(SS_BASE_BIT + 26) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 27) / 32)
                o_DATA[27] <= i_SS_WDATA[(SS_BASE_BIT + 27) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 28) / 32)
                o_DATA[28] <= i_SS_WDATA[(SS_BASE_BIT + 28) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 29) / 32)
                o_DATA[29] <= i_SS_WDATA[(SS_BASE_BIT + 29) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 30) / 32)
                o_DATA[30] <= i_SS_WDATA[(SS_BASE_BIT + 30) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 31) / 32)
                o_DATA[31] <= i_SS_WDATA[(SS_BASE_BIT + 31) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 32) / 32)
                o_DATA[32] <= i_SS_WDATA[(SS_BASE_BIT + 32) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 33) / 32)
                o_DATA[33] <= i_SS_WDATA[(SS_BASE_BIT + 33) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 34) / 32)
                o_DATA[34] <= i_SS_WDATA[(SS_BASE_BIT + 34) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 35) / 32)
                o_DATA[35] <= i_SS_WDATA[(SS_BASE_BIT + 35) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 36) / 32)
                o_DATA[36] <= i_SS_WDATA[(SS_BASE_BIT + 36) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 37) / 32)
                o_DATA[37] <= i_SS_WDATA[(SS_BASE_BIT + 37) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 38) / 32)
                o_DATA[38] <= i_SS_WDATA[(SS_BASE_BIT + 38) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 39) / 32)
                o_DATA[39] <= i_SS_WDATA[(SS_BASE_BIT + 39) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 40) / 32)
                o_DATA[40] <= i_SS_WDATA[(SS_BASE_BIT + 40) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 41) / 32)
                o_DATA[41] <= i_SS_WDATA[(SS_BASE_BIT + 41) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 42) / 32)
                o_DATA[42] <= i_SS_WDATA[(SS_BASE_BIT + 42) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 43) / 32)
                o_DATA[43] <= i_SS_WDATA[(SS_BASE_BIT + 43) % 32];
            if (i_SS_WORD_ADDR == (SS_BASE_BIT + 44) / 32)
                o_DATA[44] <= i_SS_WDATA[(SS_BASE_BIT + 44) % 32];
        end
    end else begin
        if(!i_CEN_n) begin
            case(i_ADDR)
                5'd0 : o_DATA <= 45'b110111111000111111010001_011000000100110011101;
                5'd1 : o_DATA <= 45'b110111111000110100111110_000001100001110110011;
                5'd2 : o_DATA <= 45'b110111111000000111101101_011101110100111011010;
                5'd3 : o_DATA <= 45'b110111111000000111000011_011100000010101010110;
                5'd4 : o_DATA <= 45'b110111111000000100001100_010100000010101011011;
                5'd5 : o_DATA <= 45'b110111010010101010111011_011000111100111011101;
                5'd6 : o_DATA <= 45'b110110010110111011110100_111001011000011000000;
                5'd7 : o_DATA <= 45'b110110010110111001001011_010001001100111011110;

                5'd8 : o_DATA <= 45'b110110010110011010001101_011000101000111011010;
                5'd9 : o_DATA <= 45'b110110010110000011100110_011110010100111010100;
                5'd10: o_DATA <= 45'b110110000111000101111001_010110110100110010101;
                5'd11: o_DATA <= 45'b110100001111100110011110_011111110000110011011;
                5'd12: o_DATA <= 45'b110100001111100110000001_001111001101110111101;
                5'd13: o_DATA <= 45'b110100001001111101101111_010110101010101010001;
                5'd14: o_DATA <= 45'b110100001001111101100000_010110001100110010011;
                5'd15: o_DATA <= 45'b110100001001011010110101_011001110000111010101;

                5'd16: o_DATA <= 45'b110100001001011000011010_001001010101110110111;
                5'd17: o_DATA <= 45'b110100001001001001010100_000000111001110110001;
                5'd18: o_DATA <= 45'b110100000001100011101011_000000011101110110011;
                5'd19: o_DATA <= 45'b110100000001100000101100_001011100001111110101;
                5'd20: o_DATA <= 45'b110100000000100100010011_011011000100110010101;
                5'd21: o_DATA <= 45'b011101000100010111011101_000010101001110110101;
                5'd22: o_DATA <= 45'b011001100110011111110010_000010001101111110011;
                5'd23: o_DATA <= 45'b011001100110011100100111_001001100001110110001;

                5'd24: o_DATA <= 45'b001011101110111110101001_001000000001110101010;
                5'd25: o_DATA <= 45'b001011101110101111000110_000000101101110111000;
                5'd26: o_DATA <= 45'b001011101110101001011001_010001001000110011010;
                5'd27: o_DATA <= 45'b001011101110100000110110_010011000100110010000;
                5'd28: o_DATA <= 45'b001011101110000010110000_001010101001110110001;
                5'd29: o_DATA <= 45'b001011101010010001001111_001010001101110111011;
                5'd30: o_DATA <= 45'b001011101010010001000010_011001000100100000000;
                5'd31: o_DATA <= 45'b001011100010110010001100_000000101001110110000;
            endcase
        end
    end
end


// CaveBanpresto exact-state word instrumentation.

always @(*) begin
    ss_local_valid_mask = 32'd0;
    ss_local_read_data = 32'd0;
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 0) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 0) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 0) % 32] = o_DATA[0];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 1) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 1) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 1) % 32] = o_DATA[1];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 2) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 2) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 2) % 32] = o_DATA[2];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 3) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 3) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 3) % 32] = o_DATA[3];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 4) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 4) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 4) % 32] = o_DATA[4];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 5) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 5) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 5) % 32] = o_DATA[5];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 6) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 6) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 6) % 32] = o_DATA[6];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 7) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 7) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 7) % 32] = o_DATA[7];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 8) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 8) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 8) % 32] = o_DATA[8];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 9) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 9) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 9) % 32] = o_DATA[9];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 10) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 10) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 10) % 32] = o_DATA[10];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 11) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 11) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 11) % 32] = o_DATA[11];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 12) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 12) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 12) % 32] = o_DATA[12];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 13) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 13) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 13) % 32] = o_DATA[13];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 14) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 14) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 14) % 32] = o_DATA[14];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 15) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 15) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 15) % 32] = o_DATA[15];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 16) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 16) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 16) % 32] = o_DATA[16];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 17) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 17) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 17) % 32] = o_DATA[17];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 18) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 18) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 18) % 32] = o_DATA[18];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 19) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 19) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 19) % 32] = o_DATA[19];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 20) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 20) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 20) % 32] = o_DATA[20];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 21) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 21) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 21) % 32] = o_DATA[21];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 22) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 22) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 22) % 32] = o_DATA[22];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 23) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 23) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 23) % 32] = o_DATA[23];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 24) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 24) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 24) % 32] = o_DATA[24];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 25) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 25) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 25) % 32] = o_DATA[25];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 26) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 26) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 26) % 32] = o_DATA[26];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 27) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 27) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 27) % 32] = o_DATA[27];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 28) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 28) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 28) % 32] = o_DATA[28];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 29) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 29) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 29) % 32] = o_DATA[29];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 30) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 30) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 30) % 32] = o_DATA[30];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 31) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 31) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 31) % 32] = o_DATA[31];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 32) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 32) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 32) % 32] = o_DATA[32];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 33) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 33) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 33) % 32] = o_DATA[33];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 34) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 34) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 34) % 32] = o_DATA[34];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 35) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 35) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 35) % 32] = o_DATA[35];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 36) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 36) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 36) % 32] = o_DATA[36];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 37) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 37) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 37) % 32] = o_DATA[37];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 38) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 38) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 38) % 32] = o_DATA[38];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 39) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 39) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 39) % 32] = o_DATA[39];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 40) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 40) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 40) % 32] = o_DATA[40];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 41) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 41) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 41) % 32] = o_DATA[41];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 42) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 42) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 42) % 32] = o_DATA[42];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 43) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 43) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 43) % 32] = o_DATA[43];
    end
    if (i_SS_WORD_ADDR == (SS_BASE_BIT + 44) / 32) begin
        ss_local_valid_mask[(SS_BASE_BIT + 44) % 32] = 1'b1;
        ss_local_read_data[(SS_BASE_BIT + 44) % 32] = o_DATA[44];
    end
end

assign ss_local_accept =
    i_SS_HOLD && i_SS_REQ && (|ss_local_valid_mask) && !ss_local_seen_q;
assign ss_local_write_accept = ss_local_accept && i_SS_WRITE;

always @(posedge i_EMUCLK) begin
    if (!i_SS_HOLD) begin
        ss_local_seen_q <= 1'b0;
        ss_local_ack_q <= 1'b0;
        ss_local_rdata_q <= 32'd0;
    end else begin
        ss_local_ack_q <= 1'b0;
        if (!i_SS_REQ)
            ss_local_seen_q <= 1'b0;
        if (ss_local_accept) begin
            ss_local_seen_q <= 1'b1;
            ss_local_ack_q <= 1'b1;
            ss_local_rdata_q <= ss_local_read_data;
        end
    end
end

assign o_SS_VALID_MASK = ss_local_valid_mask;
assign o_SS_ACK = ss_local_ack_q;
assign o_SS_ERROR = 1'b0;
assign o_SS_RDATA = (ss_local_rdata_q & ss_local_valid_mask);


endmodule

module cavebanpresto_ikaopm_ss_timinggen #(parameter integer SS_BASE_BIT = 0, parameter FULLY_SYNCHRONOUS = 1, parameter FAST_RESET = 0) (
    //chip clock
    input   wire            i_EMUCLK, //emulator master clock

    //chip reset
    input   wire            i_IC_n,
    output  wire            o_MRST_n, //core internal reset

    //clock endables
    input   wire            i_phiM_PCEN_n, //phiM positive edge clock enable(negative logic)
    `ifdef IKAOPM_USER_DEFINED_CLOCK_ENABLES
    input   wire            i_phi1_PCEN_n, //phi1 positive edge clock enable
    input   wire            i_phi1_NCEN_n, //phi1 negative edge clock enable
    `endif

    //phiM/2
    output  wire            o_phi1, //phi1 output
    output  wire            o_phi1_PCEN_n, //positive edge clock enable for emulation
    output  wire            o_phi1_NCEN_n, //negative edge clock enable for emulation

    //SH1 and 2
    output  reg             o_SH1,
    output  reg             o_SH2,

    //timings
    output  reg             o_CYCLE_01,
    output  reg             o_CYCLE_31,

    output  reg             o_CYCLE_12_28,
    output  reg             o_CYCLE_05_21,
    output  reg             o_CYCLE_BYTE,

    output  reg             o_CYCLE_05,
    output  reg             o_CYCLE_10,

    output  reg             o_CYCLE_03,
    output  reg             o_CYCLE_00_16,
    output  reg             o_CYCLE_01_TO_16,

    output  reg             o_CYCLE_04_12_20_28,

    output  reg             o_CYCLE_12,
    output  reg             o_CYCLE_15_31,

    output  reg             o_CYCLE_29,
    output  reg             o_CYCLE_06_22

,
    input   wire            i_SS_HOLD,
    input   wire            i_SS_REQ,
    input   wire            i_SS_WRITE,
    input   wire    [7:0]   i_SS_WORD_ADDR,
    input   wire    [31:0]  i_SS_WDATA,
    output  wire    [31:0]  o_SS_VALID_MASK,
    output  wire            o_SS_ACK,
    output  wire            o_SS_ERROR,
    output  wire    [31:0]  o_SS_RDATA
);

// Forward declarations for exact-state instrumentation.
wire ss_local_write_accept;
wire ss_local_accept;
reg ss_local_seen_q;
reg ss_local_ack_q;
reg [31:0] ss_local_rdata_q;
reg [31:0] ss_local_valid_mask;
reg [31:0] ss_local_read_data;


///////////////////////////////////////////////////////////
//////  Clock and reset
////

wire            phi1ncen_n = o_phi1_NCEN_n;
wire            mrst_n = o_MRST_n;




///////////////////////////////////////////////////////////
//////  Reset generator
////

reg             ic_n_negedge = 1'b1; //IC_n negedge detector
reg             synced_mrst_n = 1'b0; //synchronized master reset
wire            phi1_init;

generate
if(FAST_RESET == 0) begin : FAST_RESET_0_clock_and_global_rst
    assign  o_MRST_n = synced_mrst_n;
    assign  phi1_init = ic_n_negedge;
end
else begin : FAST_RESET_1_clock_and_global_rst
    assign  o_MRST_n = synced_mrst_n & i_IC_n;
    assign  phi1_init = ic_n_negedge | ~i_IC_n;
end
endgenerate

generate
if(FULLY_SYNCHRONOUS == 0) begin : FULLY_SYNCHRONOUS_0_reset_syncchain
    //2 stage SR for synchronization
    reg     [1:0]   ic_n_internal = 2'b00;
    always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd0: begin
                    ic_n_internal <= i_SS_WDATA[22:19];
                end
                default: ;
            endcase
        end
    end else begin
        if(!i_phiM_PCEN_n) begin 
                ic_n_internal[0] <= i_IC_n; 
                ic_n_internal[1] <= ic_n_internal[0]; //shift
            end
    end
end

    //ICn falling edge detector for phi1 phase initialization
    always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd0: begin
                    ic_n_negedge <= i_SS_WDATA[17];
                end
                default: ;
            endcase
        end
    end else begin
        if(!i_phiM_PCEN_n) begin
                ic_n_negedge <= ~ic_n_internal[0] & ic_n_internal[1];
            end
    end
end

    //internal master reset
    always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd0: begin
                    synced_mrst_n <= i_SS_WDATA[18];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
                synced_mrst_n <= ic_n_internal[0];
            end
    end
end
end
else begin : FULLY_SYNCHRONOUS_1_reset_syncchain
    //add two stage SR

    //4 stage SR for synchronization
    reg     [3:0]   ic_n_internal = 4'b0000;
    always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd0: begin
                    ic_n_internal <= i_SS_WDATA[22:19];
                end
                default: ;
            endcase
        end
    end else begin
        if(!i_phiM_PCEN_n) begin 
                ic_n_internal[0] <= i_IC_n; 
                ic_n_internal[3:1] <= ic_n_internal[2:0]; //shift
            end
    end
end

    //ICn falling edge detector for phi1 phase initialization
    always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd0: begin
                    ic_n_negedge <= i_SS_WDATA[17];
                end
                default: ;
            endcase
        end
    end else begin
        if(!i_phiM_PCEN_n) begin
                ic_n_negedge <= ~ic_n_internal[2] & ic_n_internal[3];
            end
    end
end

    //internal master reset
    always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd0: begin
                    synced_mrst_n <= i_SS_WDATA[18];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
                synced_mrst_n <= ic_n_internal[2];
            end
    end
end
end
endgenerate



///////////////////////////////////////////////////////////
//////  phi1 and clock enables generator
////

/*
    CLOCKING INFORMATION(ORIGINAL CHIP)
    
    phiM        _______|¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|
    ICn         ¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|___________________________|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯

    ICn neg     ¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|_______________|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯
    ICn pos     ¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|_______________|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯
    IC          _________________________________|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|__________________________________________________
    IC neg det  _________________________________|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|________________________________________________________

    phi1        ¯¯¯¯¯¯¯|_______________|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|_______________|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|________


    (FPGA)    
    EMUCLK      ¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|
    phiM cen    ¯¯¯|___|¯¯¯¯¯¯¯¯¯¯¯|___|¯¯¯¯¯¯¯¯¯¯¯|___|¯¯¯¯¯¯¯¯¯¯¯|___|¯¯¯¯¯¯¯¯¯¯¯|___|¯¯¯¯¯¯¯¯¯¯¯|___|¯¯¯¯¯¯¯¯¯¯¯|___|¯¯¯¯¯¯¯¯
    phiM        _______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|

    phi1p       ¯¯¯¯¯¯¯|_______________|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|_______________|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|________
    phi1n       _______|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|_______________________________________________|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|_______________|¯¯¯¯¯¯¯¯
*/


`ifdef IKAOPM_USER_DEFINED_CLOCK_ENABLES

reg             phi1;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        // Held: no emulation state advances.
    end else begin
        begin
            case({i_phi1_PCEN_n, i_phi1_NCEN_n})
                2'b00: phi1 <= phi1;
                2'b01: phi1 <= 1'b1;
                2'b10: phi1 <= 1'b0;
                2'b11: phi1 <= phi1;
            endcase
        end
    end
end

//phi1 output(for reference)
assign  o_phi1 = phi1;

generate
if(FAST_RESET == 0) begin : FAST_RESET_0_cenout
    //phi1 cen(internal)
    assign  o_phi1_PCEN_n = i_phi1_PCEN_n;
    assign  o_phi1_NCEN_n = i_phi1_NCEN_n;
end
else begin : FAST_RESET_1_cenout
    //phi1 cen(internal)
    assign  o_phi1_PCEN_n = i_phi1_PCEN_n & i_IC_n;
    assign  o_phi1_NCEN_n = i_phi1_NCEN_n & i_IC_n;
end
endgenerate

`else

//actual phi1 output is phi1p(positive), and the inverted phi1 is phi1n(negative)
reg             phi1p, phi1n;
generate
if(FAST_RESET == 0) begin : FAST_RESET_0_phi1gen
    always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd0: begin
                    phi1p <= i_SS_WDATA[23];
                    phi1n <= i_SS_WDATA[24];
                end
                default: ;
            endcase
        end
    end else begin
        if(!i_phiM_PCEN_n) begin
                if(phi1_init)   begin phi1p <= 1'b1;   phi1n <= 1'b1;  end //reset
                else            begin phi1p <= ~phi1p; phi1n <= phi1p; end //toggle
            end
    end
end
end
else begin : FAST_RESET_1_phi1gen
    always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd0: begin
                    phi1p <= i_SS_WDATA[23];
                    phi1n <= i_SS_WDATA[24];
                end
                default: ;
            endcase
        end
    end else begin
        if(!(i_phiM_PCEN_n & i_IC_n)) begin
                if(phi1_init)   begin phi1p <= 1'b1;   phi1n <= 1'b1;  end //reset
                else            begin phi1p <= ~phi1p; phi1n <= phi1p; end //toggle
            end
    end
end
end
endgenerate

//phi1 output(for reference)
assign  o_phi1 = phi1p;

generate
if(FAST_RESET == 0) begin : FAST_RESET_0_cenout
    //phi1 cen(internal)
    assign  o_phi1_PCEN_n = phi1p | i_phiM_PCEN_n; //ORed signal
    assign  o_phi1_NCEN_n = phi1n | i_phiM_PCEN_n;
end
else begin : FAST_RESET_1_cenout
    //phi1 cen(internal)
    assign  o_phi1_PCEN_n = (phi1p | i_phiM_PCEN_n) & i_IC_n; //ORed signal
    assign  o_phi1_NCEN_n = (phi1n | i_phiM_PCEN_n) & i_IC_n;
end
endgenerate

`endif


///////////////////////////////////////////////////////////
//////  Timing Generator
////

//
//  counter
//

reg     [4:0]   timinggen_cntr = 5'h0;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd0: begin
                    timinggen_cntr <= i_SS_WDATA[29:25];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            if(!mrst_n) begin
                timinggen_cntr <= 5'h0;
            end
            else begin
                if(timinggen_cntr == 5'h1F) timinggen_cntr <= 5'h0;
                else                        timinggen_cntr <= timinggen_cntr + 5'h1;
            end
        end
    end
end



//
//  decoder
//

always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd0: begin
                    o_CYCLE_01 <= i_SS_WDATA[2];
                    o_CYCLE_31 <= i_SS_WDATA[3];
                    o_CYCLE_12_28 <= i_SS_WDATA[4];
                    o_CYCLE_05_21 <= i_SS_WDATA[5];
                    o_CYCLE_BYTE <= i_SS_WDATA[6];
                    o_CYCLE_05 <= i_SS_WDATA[7];
                    o_CYCLE_10 <= i_SS_WDATA[8];
                    o_CYCLE_03 <= i_SS_WDATA[9];
                    o_CYCLE_00_16 <= i_SS_WDATA[10];
                    o_CYCLE_01_TO_16 <= i_SS_WDATA[11];
                    o_CYCLE_04_12_20_28 <= i_SS_WDATA[12];
                    o_CYCLE_12 <= i_SS_WDATA[13];
                    o_CYCLE_15_31 <= i_SS_WDATA[14];
                    o_CYCLE_29 <= i_SS_WDATA[15];
                    o_CYCLE_06_22 <= i_SS_WDATA[16];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            //REG
            o_CYCLE_01          <= timinggen_cntr == 5'd0;
            o_CYCLE_31          <= timinggen_cntr == 5'd30;

            //LFO
            o_CYCLE_12_28 <= (timinggen_cntr == 5'd11) | (timinggen_cntr == 5'd27);
            o_CYCLE_05_21 <= (timinggen_cntr == 5'd4) | (timinggen_cntr == 5'd20);
            o_CYCLE_BYTE  <= (timinggen_cntr[3:1] == 3'b111) |
                             (timinggen_cntr[3:1] == 3'b010) |
                             (timinggen_cntr[3:2] == 2'b00);

            //PG
            o_CYCLE_05          <= timinggen_cntr == 5'd4;
            o_CYCLE_10          <= timinggen_cntr == 5'd9;

            //EG
            o_CYCLE_03          <= timinggen_cntr == 5'd2;
            o_CYCLE_00_16       <= (timinggen_cntr == 5'd31) | (timinggen_cntr == 5'd15);
            o_CYCLE_01_TO_16    <= ~timinggen_cntr[4];

            //OP
            o_CYCLE_04_12_20_28 <= (timinggen_cntr == 5'd3) | (timinggen_cntr == 5'd11) | (timinggen_cntr == 5'd19) | (timinggen_cntr == 5'd27);

            //ACC
            o_CYCLE_29          <= timinggen_cntr == 5'd28;
            o_CYCLE_06_22       <= (timinggen_cntr == 5'd05) | (timinggen_cntr == 5'd21);

            //NOISE
            o_CYCLE_12          <= timinggen_cntr == 5'd11;
            o_CYCLE_15_31       <= (timinggen_cntr == 5'd14) | (timinggen_cntr == 5'd30);
        end
    end
end



///////////////////////////////////////////////////////////
//////  SH1 / SH2
////

//sh1/sh2
wire            sh1 = timinggen_cntr[4:3] == 2'b01; //01XXX
wire            sh2 = timinggen_cntr[4:3] == 2'b11; //11XXX

reg     [4:0]   sh1_sr, sh2_sr;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd0: begin
                    o_SH1 <= i_SS_WDATA[0];
                    o_SH2 <= i_SS_WDATA[1];
                    sh1_sr[1:0] <= i_SS_WDATA[31:30];
                end
                8'd1: begin
                    sh1_sr[4:2] <= i_SS_WDATA[2:0];
                    sh2_sr <= i_SS_WDATA[7:3];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            //sh1/2 shift register
            sh1_sr[0] <= sh1;
            sh2_sr[0] <= sh2;

            sh1_sr[4:1] <= sh1_sr[3:0];
            sh2_sr[4:1] <= sh2_sr[3:0];

            //sh1/2 output
            o_SH1 <= sh1_sr[4] & mrst_n;
            o_SH2 <= sh2_sr[4] & mrst_n;
        end
    end
end


// CaveBanpresto exact-state word instrumentation.

always @(*) begin
    ss_local_valid_mask = 32'd0;
    ss_local_read_data = 32'd0;
    case (i_SS_WORD_ADDR)
        8'd0: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[0] = o_SH1;
            ss_local_read_data[1] = o_SH2;
            ss_local_read_data[2] = o_CYCLE_01;
            ss_local_read_data[3] = o_CYCLE_31;
            ss_local_read_data[4] = o_CYCLE_12_28;
            ss_local_read_data[5] = o_CYCLE_05_21;
            ss_local_read_data[6] = o_CYCLE_BYTE;
            ss_local_read_data[7] = o_CYCLE_05;
            ss_local_read_data[8] = o_CYCLE_10;
            ss_local_read_data[9] = o_CYCLE_03;
            ss_local_read_data[10] = o_CYCLE_00_16;
            ss_local_read_data[11] = o_CYCLE_01_TO_16;
            ss_local_read_data[12] = o_CYCLE_04_12_20_28;
            ss_local_read_data[13] = o_CYCLE_12;
            ss_local_read_data[14] = o_CYCLE_15_31;
            ss_local_read_data[15] = o_CYCLE_29;
            ss_local_read_data[16] = o_CYCLE_06_22;
            ss_local_read_data[17] = ic_n_negedge;
            ss_local_read_data[18] = synced_mrst_n;
            ss_local_read_data[22:19] = FULLY_SYNCHRONOUS_1_reset_syncchain.ic_n_internal;
            ss_local_read_data[23] = phi1p;
            ss_local_read_data[24] = phi1n;
            ss_local_read_data[29:25] = timinggen_cntr;
            ss_local_read_data[31:30] = sh1_sr[1:0];
        end
        8'd1: begin
            ss_local_valid_mask = 32'h000000ff;
            ss_local_read_data[2:0] = sh1_sr[4:2];
            ss_local_read_data[7:3] = sh2_sr;
        end
        default: ;
    endcase
end

assign ss_local_accept =
    i_SS_HOLD && i_SS_REQ && (|ss_local_valid_mask) && !ss_local_seen_q;
assign ss_local_write_accept = ss_local_accept && i_SS_WRITE;

always @(posedge i_EMUCLK) begin
    if (!i_SS_HOLD) begin
        ss_local_seen_q <= 1'b0;
        ss_local_ack_q <= 1'b0;
        ss_local_rdata_q <= 32'd0;
    end else begin
        ss_local_ack_q <= 1'b0;
        if (!i_SS_REQ)
            ss_local_seen_q <= 1'b0;
        if (ss_local_accept) begin
            ss_local_seen_q <= 1'b1;
            ss_local_ack_q <= 1'b1;
            ss_local_rdata_q <= ss_local_read_data;
        end
    end
end

assign o_SS_VALID_MASK = ss_local_valid_mask;
assign o_SS_ACK = ss_local_ack_q;
assign o_SS_ERROR = 1'b0;
assign o_SS_RDATA = (ss_local_rdata_q & ss_local_valid_mask);


endmodule

module cavebanpresto_ikaopm_ss_reg #(parameter integer SS_BASE_BIT = 64, parameter USE_BRAM_FOR_D32REG = 0, parameter FULLY_SYNCHRONOUS = 1) (
    //master clock
    input   wire            i_EMUCLK, //emulator master clock

    //core internal reset
    input   wire            i_MRST_n,

    //internal clock
    input   wire            i_phi1_PCEN_n, //positive edge clock enable for emulation
    input   wire            i_phi1_NCEN_n, //negative edge clock enable for emulation

    //timings
    input   wire            i_CYCLE_01,
    input   wire            i_CYCLE_31,
    
    //control/address
    input   wire            i_CS_n,
    input   wire            i_RD_n,
    input   wire            i_WR_n,
    input   wire            i_A0,

    //bus data io
    input   wire    [7:0]   i_D,
    output  wire    [7:0]   o_D,   
    output  wire            o_D_OE,  //output driver enable

    //timer input
    input   wire            i_TIMERA_OVFL,
    input   wire            i_TIMERA_FLAG,
    input   wire            i_TIMERB_FLAG,

    //register output
    output  reg     [7:0]   o_TEST,     //0x01      TEST register

    output  reg             o_CT1,
    output  reg             o_CT2,

    output  reg             o_NE,       //0x0F[7]   Noise Enable
    output  reg     [4:0]   o_NFRQ,     //0x0F[4:0] Noise Frequency

    output  reg     [7:0]   o_CLKA1,        //0x10      Timer A D[9:2]
    output  reg     [1:0]   o_CLKA2,        //0x11      Timer A D[1:0]
    output  reg     [7:0]   o_CLKB,         //0x12      Timer B
    output  wire            o_TIMERA_FRST,  //0x14      Timer Control
    output  wire            o_TIMERB_FRST,  //          |
    output  reg             o_TIMERA_RUN,   //          |
    output  reg             o_TIMERB_RUN,   //          |
    output  reg             o_TIMERA_IRQ_EN,//          |
    output  reg             o_TIMERB_IRQ_EN,//          |

    output  reg     [7:0]   o_LFRQ,     //0x18      LFO frequency
    output  reg     [6:0]   o_PMD,      //0x19[6:0] D[7] == 1
    output  reg     [6:0]   o_AMD,      //0x19[6:0] D[7] == 0
    output  reg     [1:0]   o_W,        //0x1B[1:0] Waveform type
    output  wire            o_LFRQ_UPDATE,

    //PG
    output  wire    [6:0]   o_KC, 
    output  wire    [5:0]   o_KF, 
    output  wire    [2:0]   o_PMS,
    output  wire    [1:0]   o_DT2,
    output  wire    [2:0]   o_DT1,
    output  wire    [3:0]   o_MUL,

    //EG
    output  wire            o_KON,
    output  wire    [1:0]   o_KS,
    output  wire    [4:0]   o_AR,
    output  wire    [4:0]   o_D1R,
    output  wire    [4:0]   o_D2R,
    output  wire    [3:0]   o_RR,
    output  wire    [3:0]   o_D1L,
    output  wire    [6:0]   o_TL,
    output  wire    [1:0]   o_AMS,

    //OP
    output  wire    [2:0]   o_ALG,
    output  wire    [2:0]   o_FL,

    //ACC
    output  wire    [1:0]   o_RL,

    //input data for LSI test via CT pin
    input   wire            i_REG_LFO_CLK,

    //input data for LSI test via bus registers
    input   wire            i_REG_PHASE_CH6_C2,
    input   wire            i_REG_ATTENLEVEL_CH8_C2,
    input   wire    [13:0]  i_REG_OPDATA

,
    input   wire            i_SS_HOLD,
    input   wire            i_SS_REQ,
    input   wire            i_SS_WRITE,
    input   wire    [7:0]   i_SS_WORD_ADDR,
    input   wire    [31:0]  i_SS_WDATA,
    output  wire    [31:0]  o_SS_VALID_MASK,
    output  wire            o_SS_ACK,
    output  wire            o_SS_ERROR,
    output  wire    [31:0]  o_SS_RDATA
);

// Forward declarations for exact-state instrumentation.
wire ss_local_write_accept;
wire ss_local_accept;
reg ss_local_seen_q;
reg ss_local_ack_q;
reg [31:0] ss_local_rdata_q;
reg [31:0] ss_local_valid_mask;
reg [31:0] ss_local_read_data;
wire [31:0] ss_u_reg10_valid_mask;
wire ss_u_reg10_ack;
wire ss_u_reg10_error;
wire [31:0] ss_u_reg10_rdata;
wire [31:0] ss_u_reg11_valid_mask;
wire ss_u_reg11_ack;
wire ss_u_reg11_error;
wire [31:0] ss_u_reg11_rdata;
wire [31:0] ss_u_reg12_valid_mask;
wire ss_u_reg12_ack;
wire ss_u_reg12_error;
wire [31:0] ss_u_reg12_rdata;
wire [31:0] ss_u_reg14_valid_mask;
wire ss_u_reg14_ack;
wire ss_u_reg14_error;
wire [31:0] ss_u_reg14_rdata;
wire [31:0] ss_u_reg01_valid_mask;
wire ss_u_reg01_ack;
wire ss_u_reg01_error;
wire [31:0] ss_u_reg01_rdata;
wire [31:0] ss_u_reg0f_valid_mask;
wire ss_u_reg0f_ack;
wire ss_u_reg0f_error;
wire [31:0] ss_u_reg0f_rdata;
wire [31:0] ss_u_reg19_valid_mask;
wire ss_u_reg19_ack;
wire ss_u_reg19_error;
wire [31:0] ss_u_reg19_rdata;
wire [31:0] ss_u_reg18_valid_mask;
wire ss_u_reg18_ack;
wire ss_u_reg18_error;
wire [31:0] ss_u_reg18_rdata;
wire [31:0] ss_u_reg1b_valid_mask;
wire ss_u_reg1b_ack;
wire ss_u_reg1b_error;
wire [31:0] ss_u_reg1b_rdata;
wire [31:0] ss_u_reg08_valid_mask;
wire ss_u_reg08_ack;
wire ss_u_reg08_error;
wire [31:0] ss_u_reg08_rdata;
wire [31:0] ss_u_hireg_addrcntr_valid_mask;
wire ss_u_hireg_addrcntr_ack;
wire ss_u_hireg_addrcntr_error;
wire [31:0] ss_u_hireg_addrcntr_rdata;
wire [31:0] ss_u_busycntr_valid_mask;
wire ss_u_busycntr_ack;
wire ss_u_busycntr_error;
wire [31:0] ss_u_busycntr_rdata;
wire [31:0] ss_u_dbus_inlatch_temp_valid_mask;
wire ss_u_dbus_inlatch_temp_ack;
wire ss_u_dbus_inlatch_temp_error;
wire [31:0] ss_u_dbus_inlatch_temp_rdata;
wire [31:0] ss_u_dreg_req_inlatch_valid_mask;
wire ss_u_dreg_req_inlatch_ack;
wire ss_u_dreg_req_inlatch_error;
wire [31:0] ss_u_dreg_req_inlatch_rdata;
wire [31:0] ss_u_areg_req_inlatch_valid_mask;
wire ss_u_areg_req_inlatch_ack;
wire ss_u_areg_req_inlatch_error;
wire [31:0] ss_u_areg_req_inlatch_rdata;
wire [31:0] ss_u_pms_reg_valid_mask;
wire ss_u_pms_reg_ack;
wire ss_u_pms_reg_error;
wire [31:0] ss_u_pms_reg_rdata;
wire [31:0] ss_u_ams_reg_valid_mask;
wire ss_u_ams_reg_ack;
wire ss_u_ams_reg_error;
wire [31:0] ss_u_ams_reg_rdata;
wire [31:0] ss_u_kf_reg_valid_mask;
wire ss_u_kf_reg_ack;
wire ss_u_kf_reg_error;
wire [31:0] ss_u_kf_reg_rdata;
wire [31:0] ss_u_kc_reg_valid_mask;
wire ss_u_kc_reg_ack;
wire ss_u_kc_reg_error;
wire [31:0] ss_u_kc_reg_rdata;
wire [31:0] ss_u_fl_reg_valid_mask;
wire ss_u_fl_reg_ack;
wire ss_u_fl_reg_error;
wire [31:0] ss_u_fl_reg_rdata;
wire [31:0] ss_u_alg_reg_valid_mask;
wire ss_u_alg_reg_ack;
wire ss_u_alg_reg_error;
wire [31:0] ss_u_alg_reg_rdata;
wire [31:0] ss_u_rl_reg_valid_mask;
wire ss_u_rl_reg_ack;
wire ss_u_rl_reg_error;
wire [31:0] ss_u_rl_reg_rdata;
wire [31:0] ss_u_dt2_reg_valid_mask;
wire ss_u_dt2_reg_ack;
wire ss_u_dt2_reg_error;
wire [31:0] ss_u_dt2_reg_rdata;
wire [31:0] ss_u_dt1_reg_valid_mask;
wire ss_u_dt1_reg_ack;
wire ss_u_dt1_reg_error;
wire [31:0] ss_u_dt1_reg_rdata;
wire [31:0] ss_u_mul_reg_valid_mask;
wire ss_u_mul_reg_ack;
wire ss_u_mul_reg_error;
wire [31:0] ss_u_mul_reg_rdata;
wire [31:0] ss_u_ar_reg_valid_mask;
wire ss_u_ar_reg_ack;
wire ss_u_ar_reg_error;
wire [31:0] ss_u_ar_reg_rdata;
wire [31:0] ss_u_d1r_reg_valid_mask;
wire ss_u_d1r_reg_ack;
wire ss_u_d1r_reg_error;
wire [31:0] ss_u_d1r_reg_rdata;
wire [31:0] ss_u_d2r_reg_valid_mask;
wire ss_u_d2r_reg_ack;
wire ss_u_d2r_reg_error;
wire [31:0] ss_u_d2r_reg_rdata;
wire [31:0] ss_u_rr_reg_valid_mask;
wire ss_u_rr_reg_ack;
wire ss_u_rr_reg_error;
wire [31:0] ss_u_rr_reg_rdata;
wire [31:0] ss_u_d1l_reg_valid_mask;
wire ss_u_d1l_reg_ack;
wire ss_u_d1l_reg_error;
wire [31:0] ss_u_d1l_reg_rdata;
wire [31:0] ss_u_amen_reg_valid_mask;
wire ss_u_amen_reg_ack;
wire ss_u_amen_reg_error;
wire [31:0] ss_u_amen_reg_rdata;
wire [31:0] ss_u_ks_reg_valid_mask;
wire ss_u_ks_reg_ack;
wire ss_u_ks_reg_error;
wire [31:0] ss_u_ks_reg_rdata;
wire [31:0] ss_u_tl_reg_valid_mask;
wire ss_u_tl_reg_ack;
wire ss_u_tl_reg_error;
wire [31:0] ss_u_tl_reg_rdata;




///////////////////////////////////////////////////////////
//////  Clock and reset
////

wire            phi1pcen_n = i_phi1_PCEN_n;
wire            phi1ncen_n = i_phi1_NCEN_n;
wire            mrst_n = i_MRST_n;



///////////////////////////////////////////////////////////
//////  Cycle number
////

//additional cycle bits
reg             cycle_02;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd3: begin
                    cycle_02 <= i_SS_WDATA[30];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cycle_02 <= i_CYCLE_01;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Bus/control data inlatch and synchronizer
////

//3.58MHz phiM and 1.79MHz phi1 would be too slow to catch up
//bus transaction speed. So the chip "latch" the input first.
//3-stage DFF chain will synchronize the data then.

//latch outputs
wire    [7:0]   dbus_inlatch_temp;
wire            dreg_rq_inlatch, areg_rq_inlatch;

//Synchronizer DFF
reg             dreg_rq_synced0, dreg_rq_synced1, dreg_rq_synced2;
reg             areg_rq_synced0, areg_rq_synced1, areg_rq_synced2;
wire            data_ld = dreg_rq_synced2;
wire            addr_ld = areg_rq_synced2;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd3: begin
                    dreg_rq_synced0 <= i_SS_WDATA[31];
                end
                8'd4: begin
                    dreg_rq_synced1 <= i_SS_WDATA[0];
                    dreg_rq_synced2 <= i_SS_WDATA[1];
                    areg_rq_synced0 <= i_SS_WDATA[2];
                    areg_rq_synced1 <= i_SS_WDATA[3];
                    areg_rq_synced2 <= i_SS_WDATA[4];
                end
                default: ;
            endcase
        end
    end else begin
        begin
            if(!phi1ncen_n) begin
                if(!mrst_n) begin
                    dreg_rq_synced0 <= 1'b0;
                    dreg_rq_synced2 <= 1'b0;

                    areg_rq_synced0 <= 1'b0;
                    areg_rq_synced2 <= 1'b0;
                end
                else begin
                    //data load
                    dreg_rq_synced0 <= dreg_rq_inlatch;
                    dreg_rq_synced2 <= dreg_rq_synced1;

                    //address load
                    areg_rq_synced0 <= areg_rq_inlatch;
                    areg_rq_synced2 <= areg_rq_synced1;
                end
            end

            if(!phi1pcen_n) begin
                if(!mrst_n) begin
                    dreg_rq_synced1 <= 1'b0;

                    areg_rq_synced1 <= 1'b0;
                end
                else begin
                    //data load
                    dreg_rq_synced1 <= dreg_rq_synced0;

                    //address load
                    areg_rq_synced1 <= areg_rq_synced0;
                end
            end
        end
    end
end

//Stable data bus value; without this, a data value will overwrite a address value on a fast write cycle(6502@8MHz).
//The actual YM2151 is slow, so when the CPU writes a new value, it takes a significant amount of time for the old value
//to change(<20 ns). But an FPGA is fast. So the value has already changed before the address register samples the value.
reg     [7:0]   dbus_inlatch; 
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd4: begin
                    dbus_inlatch <= i_SS_WDATA[12:5];
                end
                default: ;
            endcase
        end
    end else begin
        begin
            if(!phi1ncen_n) begin
                if(!i_MRST_n) begin
                    dbus_inlatch <= 8'h00;
                end
                else begin
                    if(areg_rq_synced1 | dreg_rq_synced1) dbus_inlatch <= dbus_inlatch_temp;
                end
            end
        end
    end
end



generate
if(FULLY_SYNCHRONOUS == 0) begin : FULLY_SYNCHRONOUS_0_busctrl
    wire            dbus_inlatch_temp_en = ~|{i_CS_n, i_WR_n};
    wire            dreg_req_inlatch_set = ~(|{i_CS_n, i_WR_n, ~i_A0, ~mrst_n} | dreg_rq_synced1);
    wire            dreg_req_inlatch_rst = dreg_rq_synced1 | ~mrst_n;
    wire            areg_req_inlatch_set = ~(|{i_CS_n, i_WR_n,  i_A0, ~mrst_n} | areg_rq_synced1);
    wire            areg_req_inlatch_rst = areg_rq_synced1 | ~mrst_n;

    //D latch
    cavebanpresto_ikaopm_ss_dlatch #(.WIDTH(8)) u_dbus_inlatch_temp (
        .i_EN(dbus_inlatch_temp_en), .i_D(i_D), .o_Q(dbus_inlatch_temp)
    );

    //SR latch
    cavebanpresto_ikaopm_ss_srlatch u_dreg_req_inlatch (
        .i_S(dreg_req_inlatch_set), .i_R(dreg_req_inlatch_rst), .o_Q(dreg_rq_inlatch)
    );
    cavebanpresto_ikaopm_ss_srlatch u_areg_req_inlatch (
        .i_S(areg_req_inlatch_set), .i_R(areg_req_inlatch_rst), .o_Q(areg_rq_inlatch)
    );
end
else begin : FULLY_SYNCHRONOUS_1_busctrl
    reg     [7:0]   din_syncchain[0:1];
    reg     [1:0]   cs_n_syncchain, rd_n_syncchain, wr_n_syncchain, a0_syncchain;
    always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd4: begin
                    din_syncchain[0] <= i_SS_WDATA[20:13];
                    din_syncchain[1] <= i_SS_WDATA[28:21];
                    cs_n_syncchain <= i_SS_WDATA[30:29];
                    wr_n_syncchain[0] <= i_SS_WDATA[31];
                end
                8'd5: begin
                    wr_n_syncchain[1] <= i_SS_WDATA[0];
                    a0_syncchain <= i_SS_WDATA[2:1];
                end
                default: ;
            endcase
        end
    end else begin
        begin
                din_syncchain[0] <= i_D;
                din_syncchain[1] <= din_syncchain[0];

                cs_n_syncchain[0] <= i_CS_n;
                cs_n_syncchain[1] <= cs_n_syncchain[0];

                wr_n_syncchain[0] <= i_WR_n;
                wr_n_syncchain[1] <= wr_n_syncchain[0];

                a0_syncchain[0] <= i_A0;
                a0_syncchain[1] <= a0_syncchain[0];
            end
    end
end

    //make alias signals
    wire            cs_n = cs_n_syncchain[1];
    wire            wr_n = wr_n_syncchain[1];
    wire            a0 = a0_syncchain[1];
    wire    [7:0]   din = din_syncchain[1];

    wire            dbus_inlatch_temp_en = ~|{cs_n, wr_n};
    wire            dreg_req_inlatch_set = ~(|{cs_n, wr_n, ~a0, ~mrst_n} | dreg_rq_synced1);
    wire            dreg_req_inlatch_rst = dreg_rq_synced1 | ~mrst_n;
    wire            areg_req_inlatch_set = ~(|{cs_n, wr_n, a0, ~mrst_n} | areg_rq_synced1);
    wire            areg_req_inlatch_rst = areg_rq_synced1 | ~mrst_n;

    //D latch
    cavebanpresto_ikaopm_ss_syncdlatch #(.SS_BASE_BIT(13'd263), .WIDTH(8)) u_dbus_inlatch_temp (
        .i_EMUCLK(i_EMUCLK), .i_RST_n(i_MRST_n),
        .i_EN(dbus_inlatch_temp_en), .i_D(din), .o_Q(dbus_inlatch_temp)
    
,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_dbus_inlatch_temp_valid_mask),
    .o_SS_ACK        (ss_u_dbus_inlatch_temp_ack),
    .o_SS_ERROR      (ss_u_dbus_inlatch_temp_error),
    .o_SS_RDATA      (ss_u_dbus_inlatch_temp_rdata)
);

    //SR latch
    cavebanpresto_ikaopm_ss_syncsrlatch #(.SS_BASE_BIT(13'd271)) u_dreg_req_inlatch (
        .i_EMUCLK(i_EMUCLK), .i_RST_n(i_MRST_n),
        .i_S(dreg_req_inlatch_set), .i_R(dreg_req_inlatch_rst), .o_Q(dreg_rq_inlatch)
    
,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_dreg_req_inlatch_valid_mask),
    .o_SS_ACK        (ss_u_dreg_req_inlatch_ack),
    .o_SS_ERROR      (ss_u_dreg_req_inlatch_error),
    .o_SS_RDATA      (ss_u_dreg_req_inlatch_rdata)
);
    cavebanpresto_ikaopm_ss_syncsrlatch #(.SS_BASE_BIT(13'd272)) u_areg_req_inlatch (
        .i_EMUCLK(i_EMUCLK), .i_RST_n(i_MRST_n),
        .i_S(areg_req_inlatch_set), .i_R(areg_req_inlatch_rst), .o_Q(areg_rq_inlatch)
    
,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_areg_req_inlatch_valid_mask),
    .o_SS_ACK        (ss_u_areg_req_inlatch_ack),
    .o_SS_ERROR      (ss_u_areg_req_inlatch_error),
    .o_SS_RDATA      (ss_u_areg_req_inlatch_rdata)
);
end
endgenerate


///////////////////////////////////////////////////////////
//////  Loreg decoder
////

wire            reg10_en, reg11_en, reg12_en, reg14_en; //timer related
wire            reg01_en; //test register
wire            reg0f_en; //noise generator
wire            reg19_en; //vibrato
wire            reg18_en; //LFO
wire            reg1b_en; //GPO
wire            reg08_en; //KON register

assign  o_LFRQ_UPDATE = reg18_en; //LFO frequency update flag;

cavebanpresto_ikaopm_ss_loreg_decoder #(.SS_BASE_BIT(13'd241), .TARGET_ADDR(8'h10)) u_reg10 (
    .i_EMUCLK(i_EMUCLK), .i_phi1_NCEN_n(phi1ncen_n),
    .i_ADDR(dbus_inlatch), .i_ADDR_LD(addr_ld), .i_DATA_LD(data_ld), .o_REG_LD(reg10_en)

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_reg10_valid_mask),
    .o_SS_ACK        (ss_u_reg10_ack),
    .o_SS_ERROR      (ss_u_reg10_error),
    .o_SS_RDATA      (ss_u_reg10_rdata)
);

cavebanpresto_ikaopm_ss_loreg_decoder #(.SS_BASE_BIT(13'd242), .TARGET_ADDR(8'h11)) u_reg11 (
    .i_EMUCLK(i_EMUCLK), .i_phi1_NCEN_n(phi1ncen_n),
    .i_ADDR(dbus_inlatch), .i_ADDR_LD(addr_ld), .i_DATA_LD(data_ld), .o_REG_LD(reg11_en)

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_reg11_valid_mask),
    .o_SS_ACK        (ss_u_reg11_ack),
    .o_SS_ERROR      (ss_u_reg11_error),
    .o_SS_RDATA      (ss_u_reg11_rdata)
);

cavebanpresto_ikaopm_ss_loreg_decoder #(.SS_BASE_BIT(13'd243), .TARGET_ADDR(8'h12)) u_reg12 (
    .i_EMUCLK(i_EMUCLK), .i_phi1_NCEN_n(phi1ncen_n),
    .i_ADDR(dbus_inlatch), .i_ADDR_LD(addr_ld), .i_DATA_LD(data_ld), .o_REG_LD(reg12_en)

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_reg12_valid_mask),
    .o_SS_ACK        (ss_u_reg12_ack),
    .o_SS_ERROR      (ss_u_reg12_error),
    .o_SS_RDATA      (ss_u_reg12_rdata)
);

cavebanpresto_ikaopm_ss_loreg_decoder #(.SS_BASE_BIT(13'd244), .TARGET_ADDR(8'h14)) u_reg14 (
    .i_EMUCLK(i_EMUCLK), .i_phi1_NCEN_n(phi1ncen_n),
    .i_ADDR(dbus_inlatch), .i_ADDR_LD(addr_ld), .i_DATA_LD(data_ld), .o_REG_LD(reg14_en)

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_reg14_valid_mask),
    .o_SS_ACK        (ss_u_reg14_ack),
    .o_SS_ERROR      (ss_u_reg14_error),
    .o_SS_RDATA      (ss_u_reg14_rdata)
);

cavebanpresto_ikaopm_ss_loreg_decoder #(.SS_BASE_BIT(13'd245), .TARGET_ADDR(8'h01)) u_reg01 (
    .i_EMUCLK(i_EMUCLK), .i_phi1_NCEN_n(phi1ncen_n),
    .i_ADDR(dbus_inlatch), .i_ADDR_LD(addr_ld), .i_DATA_LD(data_ld), .o_REG_LD(reg01_en)

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_reg01_valid_mask),
    .o_SS_ACK        (ss_u_reg01_ack),
    .o_SS_ERROR      (ss_u_reg01_error),
    .o_SS_RDATA      (ss_u_reg01_rdata)
);

cavebanpresto_ikaopm_ss_loreg_decoder #(.SS_BASE_BIT(13'd246), .TARGET_ADDR(8'h0f)) u_reg0f (
    .i_EMUCLK(i_EMUCLK), .i_phi1_NCEN_n(phi1ncen_n),
    .i_ADDR(dbus_inlatch), .i_ADDR_LD(addr_ld), .i_DATA_LD(data_ld), .o_REG_LD(reg0f_en)

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_reg0f_valid_mask),
    .o_SS_ACK        (ss_u_reg0f_ack),
    .o_SS_ERROR      (ss_u_reg0f_error),
    .o_SS_RDATA      (ss_u_reg0f_rdata)
);

cavebanpresto_ikaopm_ss_loreg_decoder #(.SS_BASE_BIT(13'd247), .TARGET_ADDR(8'h19)) u_reg19 (
    .i_EMUCLK(i_EMUCLK), .i_phi1_NCEN_n(phi1ncen_n),
    .i_ADDR(dbus_inlatch), .i_ADDR_LD(addr_ld), .i_DATA_LD(data_ld), .o_REG_LD(reg19_en)

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_reg19_valid_mask),
    .o_SS_ACK        (ss_u_reg19_ack),
    .o_SS_ERROR      (ss_u_reg19_error),
    .o_SS_RDATA      (ss_u_reg19_rdata)
);

cavebanpresto_ikaopm_ss_loreg_decoder #(.SS_BASE_BIT(13'd248), .TARGET_ADDR(8'h18)) u_reg18 (
    .i_EMUCLK(i_EMUCLK), .i_phi1_NCEN_n(phi1ncen_n),
    .i_ADDR(dbus_inlatch), .i_ADDR_LD(addr_ld), .i_DATA_LD(data_ld), .o_REG_LD(reg18_en)

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_reg18_valid_mask),
    .o_SS_ACK        (ss_u_reg18_ack),
    .o_SS_ERROR      (ss_u_reg18_error),
    .o_SS_RDATA      (ss_u_reg18_rdata)
);

cavebanpresto_ikaopm_ss_loreg_decoder #(.SS_BASE_BIT(13'd249), .TARGET_ADDR(8'h1B)) u_reg1b (
    .i_EMUCLK(i_EMUCLK), .i_phi1_NCEN_n(phi1ncen_n),
    .i_ADDR(dbus_inlatch), .i_ADDR_LD(addr_ld), .i_DATA_LD(data_ld), .o_REG_LD(reg1b_en)

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_reg1b_valid_mask),
    .o_SS_ACK        (ss_u_reg1b_ack),
    .o_SS_ERROR      (ss_u_reg1b_error),
    .o_SS_RDATA      (ss_u_reg1b_rdata)
);

cavebanpresto_ikaopm_ss_loreg_decoder #(.SS_BASE_BIT(13'd250), .TARGET_ADDR(8'h08)) u_reg08 (
    .i_EMUCLK(i_EMUCLK), .i_phi1_NCEN_n(phi1ncen_n),
    .i_ADDR(dbus_inlatch), .i_ADDR_LD(addr_ld), .i_DATA_LD(data_ld), .o_REG_LD(reg08_en)

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_reg08_valid_mask),
    .o_SS_ACK        (ss_u_reg08_ack),
    .o_SS_ERROR      (ss_u_reg08_error),
    .o_SS_RDATA      (ss_u_reg08_rdata)
);



///////////////////////////////////////////////////////////
//////  Hireg temp register, flags, decoder
////

//
//  TEMPORARY ADDRESS REGISTER FOR HIREG
//

//hireg temporary address register load enable
wire            hireg_addrreg_en = (addr_ld & (dbus_inlatch[7:5] != 3'b000)); //not 000X_XXXX

//hireg "address" temporary register with async reset
reg     [7:0]   hireg_addr;
always @(posedge i_EMUCLK or negedge mrst_n) begin
    if (!mrst_n) begin
        hireg_addr <= 8'hFF;
    end else if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd5: begin
                    hireg_addr <= i_SS_WDATA[10:3];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1pcen_n) begin
            if(hireg_addrreg_en) hireg_addr <= dbus_inlatch;
        end
    end
end

//hireg address valid flag, reset when the address input is loreg
reg             hireg_addr_valid;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd5: begin
                    hireg_addr_valid <= i_SS_WDATA[11];
                end
                default: ;
            endcase
        end
    end else begin
        begin
            if(!phi1ncen_n) begin
                hireg_addr_valid <= hireg_addrreg_en | (hireg_addr_valid & ~addr_ld);
            end
        end
    end
end


//
//  TEMPORARY DATA REGISTER FOR HIREG
//

//hireg temporary data register load enable
wire            hireg_datareg_en = data_ld & hireg_addr_valid;

//hireg "data" temporary register with async reset
reg     [7:0]   hireg_data;
always @(posedge i_EMUCLK or negedge mrst_n) begin
    if (!mrst_n) begin
        hireg_data <= 8'hFF;
    end else if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd5: begin
                    hireg_data <= i_SS_WDATA[19:12];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            if(hireg_datareg_en) hireg_data <= dbus_inlatch;
        end
    end
end

//hireg data valid flag, reset when the data input is loreg
reg             hireg_data_valid;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd5: begin
                    hireg_data_valid <= i_SS_WDATA[20];
                end
                default: ;
            endcase
        end
    end else begin
        begin
            if(!phi1pcen_n) begin
                hireg_data_valid <= hireg_datareg_en | (hireg_data_valid & ~addr_ld);
            end
        end
    end
end


//
//  HIREG ADDRESS COUNTER
//

wire    [4:0]   hireg_addrcntr;
cavebanpresto_ikaopm_ss_counter #(.SS_BASE_BIT(13'd251), .WIDTH(5)) u_hireg_addrcntr (
    .i_EMUCLK(i_EMUCLK), .i_PCEN_n(phi1pcen_n), .i_NCEN_n(phi1ncen_n),
    .i_CNT(1'b1), .i_LD(1'b0), .i_RST(i_CYCLE_31 | ~mrst_n),
    .i_D(5'd0), .o_Q(hireg_addrcntr), .o_CO()

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_hireg_addrcntr_valid_mask),
    .o_SS_ACK        (ss_u_hireg_addrcntr_ack),
    .o_SS_ERROR      (ss_u_hireg_addrcntr_error),
    .o_SS_RDATA      (ss_u_hireg_addrcntr_rdata)
);



//
//  DECODER
//

reg             reg38_3f_en; //PMS[6:4]/AMS[1:0]
reg             reg30_37_en; //KF[7:2]
reg             reg28_2f_en; //KC[6:0]
reg             reg20_27_en; //RL[7:6]/FL[5:3]/CONNECT(algorithm)[2:0]

reg             rege0_ff_en; //D1L[7:4]/RR[3:0]
reg             regc0_df_en; //DT2[7:6]/D2R[4:0]
reg             rega0_bf_en; //AMS-EN[7]/D1R[4:0]
reg             reg80_9f_en; //KS[7:6]/AR[4:0]
reg             reg60_7f_en; //TL[6:0]
reg             reg40_5f_en; //DT1[6:4]/MUL[3:0]

always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd5: begin
                    reg38_3f_en <= i_SS_WDATA[21];
                    reg30_37_en <= i_SS_WDATA[22];
                    reg28_2f_en <= i_SS_WDATA[23];
                    reg20_27_en <= i_SS_WDATA[24];
                    rege0_ff_en <= i_SS_WDATA[25];
                    regc0_df_en <= i_SS_WDATA[26];
                    rega0_bf_en <= i_SS_WDATA[27];
                    reg80_9f_en <= i_SS_WDATA[28];
                    reg60_7f_en <= i_SS_WDATA[29];
                    reg40_5f_en <= i_SS_WDATA[30];
                end
                default: ;
            endcase
        end
    end else begin
        begin
            if(!phi1ncen_n) begin
                reg38_3f_en <= (hireg_addr[7:3] == 5'b00111) & (hireg_addr[2:0] == hireg_addrcntr[2:0]) & hireg_data_valid;
                reg30_37_en <= (hireg_addr[7:3] == 5'b00110) & (hireg_addr[2:0] == hireg_addrcntr[2:0]) & hireg_data_valid;
                reg28_2f_en <= (hireg_addr[7:3] == 5'b00101) & (hireg_addr[2:0] == hireg_addrcntr[2:0]) & hireg_data_valid;
                reg20_27_en <= (hireg_addr[7:3] == 5'b00100) & (hireg_addr[2:0] == hireg_addrcntr[2:0]) & hireg_data_valid;

                rege0_ff_en <= (hireg_addr[7:5] == 3'b111)   & (hireg_addr[4:0] == hireg_addrcntr)      & hireg_data_valid;
                regc0_df_en <= (hireg_addr[7:5] == 3'b110)   & (hireg_addr[4:0] == hireg_addrcntr)      & hireg_data_valid;
                rega0_bf_en <= (hireg_addr[7:5] == 3'b101)   & (hireg_addr[4:0] == hireg_addrcntr)      & hireg_data_valid;
                reg80_9f_en <= (hireg_addr[7:5] == 3'b100)   & (hireg_addr[4:0] == hireg_addrcntr)      & hireg_data_valid;
                reg60_7f_en <= (hireg_addr[7:5] == 3'b011)   & (hireg_addr[4:0] == hireg_addrcntr)      & hireg_data_valid;
                reg40_5f_en <= (hireg_addr[7:5] == 3'b010)   & (hireg_addr[4:0] == hireg_addrcntr)      & hireg_data_valid;
            end
        end
    end
end



///////////////////////////////////////////////////////////
//////  Low registers
////

//
//  GENERAL STATIC REGISTERS
//

//CT reg output
reg     [1:0]   ct_reg; //define CT reg

always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd2: begin
                    o_CT1 <= i_SS_WDATA[8];
                    o_CT2 <= i_SS_WDATA[9];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            o_CT1 <= o_TEST[3] ? i_REG_LFO_CLK : ct_reg[0];  //LSI test purpose
            o_CT2 <= ct_reg[1];
        end
    end
end

//reg for KON
reg             csm_reg;
reg     [6:0]   kon_temp_reg;

//timer flag reset
assign  o_TIMERA_FRST = (reg14_en & dbus_inlatch[4]) | ~mrst_n;
assign  o_TIMERB_FRST = (reg14_en & dbus_inlatch[5]) | ~mrst_n;

always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd2: begin
                    o_TEST <= i_SS_WDATA[7:0];
                    o_NE <= i_SS_WDATA[10];
                    o_NFRQ <= i_SS_WDATA[15:11];
                    o_CLKA1 <= i_SS_WDATA[23:16];
                    o_CLKA2 <= i_SS_WDATA[25:24];
                    o_CLKB[5:0] <= i_SS_WDATA[31:26];
                end
                8'd3: begin
                    o_CLKB[7:6] <= i_SS_WDATA[1:0];
                    o_TIMERA_RUN <= i_SS_WDATA[2];
                    o_TIMERB_RUN <= i_SS_WDATA[3];
                    o_TIMERA_IRQ_EN <= i_SS_WDATA[4];
                    o_TIMERB_IRQ_EN <= i_SS_WDATA[5];
                    o_LFRQ <= i_SS_WDATA[13:6];
                    o_PMD <= i_SS_WDATA[20:14];
                    o_AMD <= i_SS_WDATA[27:21];
                    o_W <= i_SS_WDATA[29:28];
                end
                8'd5: begin
                    ct_reg[0] <= i_SS_WDATA[31];
                end
                8'd6: begin
                    ct_reg[1] <= i_SS_WDATA[0];
                    csm_reg <= i_SS_WDATA[1];
                    kon_temp_reg <= i_SS_WDATA[8:2];
                end
                default: ;
            endcase
        end
    end else begin
        begin
            if(!phi1pcen_n) begin //positive edge!!
                if(!mrst_n) begin
                    o_TEST          <= 8'h0;

                    ct_reg          <= 2'b00;

                    o_NE            <= 1'b0;
                    o_NFRQ          <= 5'h00;

                    o_CLKA1         <= 8'h0;
                    o_CLKA2         <= 2'h0;
                    o_CLKB          <= 8'h0;
                    o_TIMERA_RUN    <= 1'b0;
                    o_TIMERB_RUN    <= 1'b0;
                    o_TIMERA_IRQ_EN <= 1'b0;
                    o_TIMERB_IRQ_EN <= 1'b0;

                    o_LFRQ          <= 8'h00;
                    o_PMD           <= 7'h00;
                    o_AMD           <= 7'h00;
                    o_W             <= 2'd0;

                    csm_reg         <= 1'b0;
                    kon_temp_reg    <= 7'b0000_000;
                end
                else begin
                    o_TEST          <= reg01_en ? dbus_inlatch      : o_TEST;

                    ct_reg          <= reg1b_en ? dbus_inlatch[7:6] : ct_reg;
                    
                    o_NE            <= reg0f_en ? dbus_inlatch[7]   : o_NE;
                    o_NFRQ          <= reg0f_en ? dbus_inlatch[4:0] : o_NFRQ;

                    o_CLKA1         <= reg10_en ? dbus_inlatch      : o_CLKA1;
                    o_CLKA2         <= reg11_en ? dbus_inlatch[1:0] : o_CLKA2;
                    o_CLKB          <= reg12_en ? dbus_inlatch      : o_CLKB;
                    o_TIMERA_RUN    <= reg14_en ? dbus_inlatch[0]   : o_TIMERA_RUN;
                    o_TIMERB_RUN    <= reg14_en ? dbus_inlatch[1]   : o_TIMERB_RUN;
                    o_TIMERA_IRQ_EN <= reg14_en ? dbus_inlatch[2]   : o_TIMERA_IRQ_EN;
                    o_TIMERB_IRQ_EN <= reg14_en ? dbus_inlatch[3]   : o_TIMERB_IRQ_EN;

                    o_LFRQ          <= reg18_en ? dbus_inlatch      : o_LFRQ;
                    o_PMD           <= reg19_en ? (dbus_inlatch[7] == 1'b1) ? dbus_inlatch[6:0] : o_PMD :
                                                  o_PMD;
                    o_AMD           <= reg19_en ? (dbus_inlatch[7] == 1'b0) ? dbus_inlatch[6:0] : o_AMD :
                                                  o_AMD;
                    o_W             <= reg1b_en ? dbus_inlatch[1:0] : o_W;

                    csm_reg         <= reg14_en ? dbus_inlatch[7]   : csm_reg;
                    kon_temp_reg    <= reg08_en ? dbus_inlatch[6:0] : kon_temp_reg;
                end
            end
        end
    end
end


//
//  DYNAMIC REGISTERS FOR KON
//

reg             ch_equal, force_kon;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd6: begin
                    ch_equal <= i_SS_WDATA[9];
                    force_kon <= i_SS_WDATA[10];
                end
                default: ;
            endcase
        end
    end else begin
        begin
            if(!phi1ncen_n) begin
                ch_equal <= hireg_addrcntr == {2'b00, kon_temp_reg[2:0]}; //channel number
            
                if(!mrst_n) force_kon <= 1'b0;
                else begin if(cycle_02) force_kon <= i_TIMERA_OVFL & csm_reg; end
            end
        end
    end
end

/*
    define 8-bit, 4-line, total 32-stage shift register(8*4)
    Data flows from LSB to MSB. The LSB of each line has a multiplexer
    to choose data to be written in the LSB register.
    When ch_equal is activated, new data from temporary kon reg is loaded.
    If not, it gets data from the MSB of the previous "line"
*/
reg             kon_m1, kon_m2, kon_c1, kon_c2;
reg     [7:0]   kon_sr_0_7, kon_sr_8_15, kon_sr_16_23, kon_sr_24_31;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd6: begin
                    kon_m1 <= i_SS_WDATA[11];
                    kon_m2 <= i_SS_WDATA[12];
                    kon_c1 <= i_SS_WDATA[13];
                    kon_c2 <= i_SS_WDATA[14];
                    kon_sr_0_7 <= i_SS_WDATA[22:15];
                    kon_sr_8_15 <= i_SS_WDATA[30:23];
                    kon_sr_16_23[0] <= i_SS_WDATA[31];
                end
                8'd7: begin
                    kon_sr_16_23[7:1] <= i_SS_WDATA[6:0];
                    kon_sr_24_31 <= i_SS_WDATA[14:7];
                end
                default: ;
            endcase
        end
    end else begin
        begin
            if(!phi1ncen_n) begin
                kon_m1 <= kon_temp_reg[3]; kon_m2 <= kon_temp_reg[5];
                kon_c1 <= kon_temp_reg[4]; kon_c2 <= kon_temp_reg[6];

                //line 1
                kon_sr_0_7[0] <= ch_equal ? kon_m1 : (kon_sr_24_31[7] & mrst_n);
                kon_sr_0_7[7:1] <= kon_sr_0_7[6:0];

                //line 2
                kon_sr_8_15[0] <= ch_equal ? kon_c2 : kon_sr_0_7[7];
                kon_sr_8_15[7:1] <= kon_sr_8_15[6:0];

                //line 3
                kon_sr_16_23[0] <= ch_equal ? kon_c1 : kon_sr_8_15[7];
                kon_sr_16_23[7:1] <= kon_sr_16_23[6:0];

                //line 4
                kon_sr_24_31[0] <= ch_equal ? kon_m2 : kon_sr_16_23[7];
                kon_sr_24_31[7:1] <= kon_sr_24_31[6:0];
            end
        end
    end
end

assign  o_KON = kon_sr_24_31[5] | force_kon;



///////////////////////////////////////////////////////////
//////  High registers
////

//
//  SR8 REGISTERS
//

/*
    8-stage sr for the data below:

    Address 38_3f : PMS[6:4]    AMS[1:0]
    Address 30_37 : KF[7:2]
    Address 28_2f : KC[6:0]
    Address 20_27 : RL[7:6]     FL[5:3]     CONNECT(algorithm)[2:0]
*/

//define in/out port
wire    [2:0]   pms_out;    //phase modulation sensitivity
wire    [1:0]   ams_out;    //amplitude modulation sensitivity
wire    [5:0]   kf_out;     //key fraction
wire    [6:0]   kc_out;     //key code
wire    [2:0]   fl_out;     //feedback level
wire    [2:0]   alg_out;    //algorithm type
wire    [1:0]   rl_out;     //right/left channel enable

wire    [2:0]   pms_in  = !mrst_n ? 3'd0  : reg38_3f_en ? hireg_data[6:4] : pms_out;
wire    [1:0]   ams_in  = !mrst_n ? 2'd0  : reg38_3f_en ? hireg_data[1:0] : ams_out;
wire    [5:0]   kf_in   = !mrst_n ? 6'd0  : reg30_37_en ? hireg_data[7:2] : kf_out;
wire    [6:0]   kc_in   = !mrst_n ? 7'd0  : reg28_2f_en ? hireg_data[6:0] : kc_out;
wire    [2:0]   fl_in   = !mrst_n ? 3'd0  : reg20_27_en ? hireg_data[5:3] : fl_out;
wire    [2:0]   alg_in  = !mrst_n ? 3'd0  : reg20_27_en ? hireg_data[2:0] : alg_out;
wire    [1:0]   rl_in   = !mrst_n ? 2'b00 : reg20_27_en ? hireg_data[7:6] : rl_out;

cavebanpresto_ikaopm_ss_sr #(.SS_BASE_BIT(13'd273), .WIDTH(3), .LENGTH(8), .TAP(0)) u_pms_reg 
(.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_D(pms_in), .o_Q_TAP(o_PMS), .o_Q_LAST(pms_out)
,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_pms_reg_valid_mask),
    .o_SS_ACK        (ss_u_pms_reg_ack),
    .o_SS_ERROR      (ss_u_pms_reg_error),
    .o_SS_RDATA      (ss_u_pms_reg_rdata)
);

cavebanpresto_ikaopm_ss_sr #(.SS_BASE_BIT(13'd297), .WIDTH(2), .LENGTH(8), .TAP(8)) u_ams_reg 
(.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_D(ams_in), .o_Q_TAP(), .o_Q_LAST(ams_out)
,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_ams_reg_valid_mask),
    .o_SS_ACK        (ss_u_ams_reg_ack),
    .o_SS_ERROR      (ss_u_ams_reg_error),
    .o_SS_RDATA      (ss_u_ams_reg_rdata)
);

cavebanpresto_ikaopm_ss_sr #(.SS_BASE_BIT(13'd313), .WIDTH(6), .LENGTH(8), .TAP(1)) u_kf_reg 
(.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_D(kf_in), .o_Q_TAP(o_KF), .o_Q_LAST(kf_out)
,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_kf_reg_valid_mask),
    .o_SS_ACK        (ss_u_kf_reg_ack),
    .o_SS_ERROR      (ss_u_kf_reg_error),
    .o_SS_RDATA      (ss_u_kf_reg_rdata)
);

cavebanpresto_ikaopm_ss_sr #(.SS_BASE_BIT(13'd361), .WIDTH(7), .LENGTH(8), .TAP(1)) u_kc_reg 
(.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_D(kc_in), .o_Q_TAP(o_KC), .o_Q_LAST(kc_out)
,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_kc_reg_valid_mask),
    .o_SS_ACK        (ss_u_kc_reg_ack),
    .o_SS_ERROR      (ss_u_kc_reg_error),
    .o_SS_RDATA      (ss_u_kc_reg_rdata)
);

cavebanpresto_ikaopm_ss_sr #(.SS_BASE_BIT(13'd417), .WIDTH(3), .LENGTH(8), .TAP(7)) u_fl_reg 
(.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_D(fl_in), .o_Q_TAP(o_FL), .o_Q_LAST(fl_out)
,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_fl_reg_valid_mask),
    .o_SS_ACK        (ss_u_fl_reg_ack),
    .o_SS_ERROR      (ss_u_fl_reg_error),
    .o_SS_RDATA      (ss_u_fl_reg_rdata)
);

cavebanpresto_ikaopm_ss_sr #(.SS_BASE_BIT(13'd441), .WIDTH(3), .LENGTH(8), .TAP(4)) u_alg_reg 
(.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_D(alg_in), .o_Q_TAP(o_ALG), .o_Q_LAST(alg_out)
,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_alg_reg_valid_mask),
    .o_SS_ACK        (ss_u_alg_reg_ack),
    .o_SS_ERROR      (ss_u_alg_reg_error),
    .o_SS_RDATA      (ss_u_alg_reg_rdata)
);

cavebanpresto_ikaopm_ss_sr #(.SS_BASE_BIT(13'd465), .WIDTH(2), .LENGTH(8), .TAP(5)) u_rl_reg 
(.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_D(rl_in), .o_Q_TAP(o_RL), .o_Q_LAST(rl_out)
,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_rl_reg_valid_mask),
    .o_SS_ACK        (ss_u_rl_reg_ack),
    .o_SS_ERROR      (ss_u_rl_reg_error),
    .o_SS_RDATA      (ss_u_rl_reg_rdata)
);




//
//  SR32 REGISTERS
//

/*
    32-stage sr for the data below:

    Address e0_ff : D1L[7:4]    RR[3:0]
    Address c0_df : DT2[7:6]    D2R[4:0]
    Address a0_bf : AMS-EN[7]   D1R[4:0]
    Address 80_9f : KS[7:6]     AR[4:0]
    Address 60_7f : TL[6:0]
    Address 40_5f : DT1[6:4]    MUL[3:0]
*/

//define in/out port
wire    [1:0]   dt2_out;    //detune2
wire    [2:0]   dt1_out;    //detune1
wire    [3:0]   mul_out;    //phase multuply
wire    [4:0]   ar_out;     //attack rate
wire    [4:0]   d2r_out;    //second decay rate
wire    [4:0]   d1r_out;    //first decay rate
wire    [3:0]   rr_out;     //release rate
wire    [3:0]   d1l_out;    //first decay level
wire            amen_out;   //amplitude modulation enable
wire    [1:0]   ks_out;     //key scale
wire    [6:0]   tl_out;     //total level

generate
if(USE_BRAM_FOR_D32REG == 0) begin: d32reg_mode_sr
    wire    [1:0]   dt2_in  = !mrst_n ? 2'd0 : regc0_df_en ? hireg_data[7:6] : dt2_out;
    wire    [2:0]   dt1_in  = !mrst_n ? 3'd0 : reg40_5f_en ? hireg_data[6:4] : dt1_out;
    wire    [3:0]   mul_in  = !mrst_n ? 4'd0 : reg40_5f_en ? hireg_data[3:0] : mul_out;
    wire    [4:0]   ar_in   = !mrst_n ? 5'd0 : reg80_9f_en ? hireg_data[4:0] : ar_out;
    wire    [4:0]   d1r_in  = !mrst_n ? 5'd0 : rega0_bf_en ? hireg_data[4:0] : d1r_out;
    wire    [4:0]   d2r_in  = !mrst_n ? 5'd0 : regc0_df_en ? hireg_data[4:0] : d2r_out;
    wire    [3:0]   rr_in   = !mrst_n ? 4'd0 : rege0_ff_en ? hireg_data[3:0] : rr_out;
    wire    [3:0]   d1l_in  = !mrst_n ? 4'd0 : rege0_ff_en ? hireg_data[7:4] : d1l_out;
    wire            amen_in = !mrst_n ? 1'b0 : rega0_bf_en ? hireg_data[7]   : amen_out;
    wire    [1:0]   ks_in   = !mrst_n ? 2'd0 : reg80_9f_en ? hireg_data[7:6] : ks_out; 
    wire    [6:0]   tl_in   = !mrst_n ? 7'd0 : reg60_7f_en ? hireg_data[6:0] : tl_out; 

    cavebanpresto_ikaopm_ss_sr #(.WIDTH(2), .LENGTH(32), .TAP(27)) u_dt2_reg 
    (.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_D(dt2_in), .o_Q_TAP(o_DT2), .o_Q_LAST(dt2_out));

    cavebanpresto_ikaopm_ss_sr #(.WIDTH(3), .LENGTH(32), .TAP(32)) u_dt1_reg 
    (.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_D(dt1_in), .o_Q_TAP(o_DT1), .o_Q_LAST(dt1_out));

    cavebanpresto_ikaopm_ss_sr #(.WIDTH(4), .LENGTH(32), .TAP(32)) u_mul_reg 
    (.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_D(mul_in), .o_Q_TAP(o_MUL), .o_Q_LAST(mul_out));

    cavebanpresto_ikaopm_ss_sr #(.WIDTH(5), .LENGTH(32), .TAP(32)) u_ar_reg 
    (.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_D(ar_in), .o_Q_TAP(o_AR), .o_Q_LAST(ar_out));

    cavebanpresto_ikaopm_ss_sr #(.WIDTH(5), .LENGTH(32), .TAP(32)) u_d1r_reg 
    (.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_D(d1r_in), .o_Q_TAP(o_D1R), .o_Q_LAST(d1r_out));

    cavebanpresto_ikaopm_ss_sr #(.WIDTH(5), .LENGTH(32), .TAP(32)) u_d2r_reg 
    (.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_D(d2r_in), .o_Q_TAP(o_D2R), .o_Q_LAST(d2r_out));

    cavebanpresto_ikaopm_ss_sr #(.WIDTH(4), .LENGTH(32), .TAP(32)) u_rr_reg 
    (.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_D(rr_in), .o_Q_TAP(o_RR), .o_Q_LAST(rr_out));

    cavebanpresto_ikaopm_ss_sr #(.WIDTH(4), .LENGTH(32), .TAP(32)) u_d1l_reg 
    (.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_D(d1l_in), .o_Q_TAP(o_D1L), .o_Q_LAST(d1l_out));

    cavebanpresto_ikaopm_ss_sr #(.WIDTH(1), .LENGTH(32), .TAP(32)) u_amen_reg 
    (.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_D(amen_in), .o_Q_TAP(), .o_Q_LAST(amen_out));

    cavebanpresto_ikaopm_ss_sr #(.WIDTH(2), .LENGTH(32), .TAP(32)) u_ks_reg 
    (.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_D(ks_in), .o_Q_TAP(o_KS), .o_Q_LAST(ks_out));

    cavebanpresto_ikaopm_ss_sr #(.WIDTH(7), .LENGTH(32), .TAP(32)) u_tl_reg 
    (.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_D(tl_in), .o_Q_TAP(o_TL), .o_Q_LAST(tl_out));

    assign  o_AMS = ams_out & {2{amen_out}};
end
else begin: d32reg_mode_bram
    wire    [1:0]   dt2_in  = !mrst_n ? 2'd0 : regc0_df_en ? hireg_data[7:6] : dt2_out;
    wire    [2:0]   dt1_in  = !mrst_n ? 3'd0 : hireg_data[6:4];
    wire    [3:0]   mul_in  = !mrst_n ? 4'd0 : hireg_data[3:0];
    wire    [4:0]   ar_in   = !mrst_n ? 5'd0 : hireg_data[4:0];
    wire    [4:0]   d1r_in  = !mrst_n ? 5'd0 : hireg_data[4:0];
    wire    [4:0]   d2r_in  = !mrst_n ? 5'd0 : hireg_data[4:0];
    wire    [3:0]   rr_in   = !mrst_n ? 4'd0 : hireg_data[3:0];
    wire    [3:0]   d1l_in  = !mrst_n ? 4'd0 : hireg_data[7:4];
    wire            amen_in = !mrst_n ? 1'b0 : hireg_data[7]  ;
    wire    [1:0]   ks_in   = !mrst_n ? 2'd0 : hireg_data[7:6];
    wire    [6:0]   tl_in   = !mrst_n ? 7'd0 : hireg_data[6:0];

    wire            d32reg_cntr_rst = i_CYCLE_31 | ~mrst_n;

    cavebanpresto_ikaopm_ss_sr #(.SS_BASE_BIT(13'd481), .WIDTH(2), .LENGTH(32), .TAP(27)) u_dt2_reg 
    (.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_D(dt2_in), .o_Q_TAP(o_DT2), .o_Q_LAST(dt2_out)
,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_dt2_reg_valid_mask),
    .o_SS_ACK        (ss_u_dt2_reg_ack),
    .o_SS_ERROR      (ss_u_dt2_reg_error),
    .o_SS_RDATA      (ss_u_dt2_reg_rdata)
);

    cavebanpresto_ikaopm_ss_sr_bram #(.SS_MEM_BASE_BIT(13'd576), .SS_META_BASE_BIT(13'd1856), .WIDTH(3), .LENGTH(32), .TAP(32)) u_dt1_reg 
    (.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_CNTRRST(d32reg_cntr_rst), .i_WR(reg40_5f_en), .i_D(dt1_in), .o_Q_TAP(o_DT1)
,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_dt1_reg_valid_mask),
    .o_SS_ACK        (ss_u_dt1_reg_ack),
    .o_SS_ERROR      (ss_u_dt1_reg_error),
    .o_SS_RDATA      (ss_u_dt1_reg_rdata)
);

    cavebanpresto_ikaopm_ss_sr_bram #(.SS_MEM_BASE_BIT(13'd672), .SS_META_BASE_BIT(13'd1866), .WIDTH(4), .LENGTH(32), .TAP(32)) u_mul_reg 
    (.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_CNTRRST(d32reg_cntr_rst), .i_WR(reg40_5f_en), .i_D(mul_in), .o_Q_TAP(o_MUL)
,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_mul_reg_valid_mask),
    .o_SS_ACK        (ss_u_mul_reg_ack),
    .o_SS_ERROR      (ss_u_mul_reg_error),
    .o_SS_RDATA      (ss_u_mul_reg_rdata)
);

    cavebanpresto_ikaopm_ss_sr_bram #(.SS_MEM_BASE_BIT(13'd800), .SS_META_BASE_BIT(13'd1876), .WIDTH(5), .LENGTH(32), .TAP(32)) u_ar_reg 
    (.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_CNTRRST(d32reg_cntr_rst), .i_WR(reg80_9f_en), .i_D(ar_in), .o_Q_TAP(o_AR)
,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_ar_reg_valid_mask),
    .o_SS_ACK        (ss_u_ar_reg_ack),
    .o_SS_ERROR      (ss_u_ar_reg_error),
    .o_SS_RDATA      (ss_u_ar_reg_rdata)
);

    cavebanpresto_ikaopm_ss_sr_bram #(.SS_MEM_BASE_BIT(13'd960), .SS_META_BASE_BIT(13'd1886), .WIDTH(5), .LENGTH(32), .TAP(32)) u_d1r_reg 
    (.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_CNTRRST(d32reg_cntr_rst), .i_WR(rega0_bf_en), .i_D(d1r_in), .o_Q_TAP(o_D1R)
,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_d1r_reg_valid_mask),
    .o_SS_ACK        (ss_u_d1r_reg_ack),
    .o_SS_ERROR      (ss_u_d1r_reg_error),
    .o_SS_RDATA      (ss_u_d1r_reg_rdata)
);

    cavebanpresto_ikaopm_ss_sr_bram #(.SS_MEM_BASE_BIT(13'd1120), .SS_META_BASE_BIT(13'd1896), .WIDTH(5), .LENGTH(32), .TAP(32)) u_d2r_reg 
    (.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_CNTRRST(d32reg_cntr_rst), .i_WR(regc0_df_en), .i_D(d2r_in), .o_Q_TAP(o_D2R)
,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_d2r_reg_valid_mask),
    .o_SS_ACK        (ss_u_d2r_reg_ack),
    .o_SS_ERROR      (ss_u_d2r_reg_error),
    .o_SS_RDATA      (ss_u_d2r_reg_rdata)
);

    cavebanpresto_ikaopm_ss_sr_bram #(.SS_MEM_BASE_BIT(13'd1280), .SS_META_BASE_BIT(13'd1906), .WIDTH(4), .LENGTH(32), .TAP(32)) u_rr_reg 
    (.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_CNTRRST(d32reg_cntr_rst), .i_WR(rege0_ff_en), .i_D(rr_in), .o_Q_TAP(o_RR)
,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_rr_reg_valid_mask),
    .o_SS_ACK        (ss_u_rr_reg_ack),
    .o_SS_ERROR      (ss_u_rr_reg_error),
    .o_SS_RDATA      (ss_u_rr_reg_rdata)
);

    cavebanpresto_ikaopm_ss_sr_bram #(.SS_MEM_BASE_BIT(13'd1408), .SS_META_BASE_BIT(13'd1916), .WIDTH(4), .LENGTH(32), .TAP(32)) u_d1l_reg 
    (.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_CNTRRST(d32reg_cntr_rst), .i_WR(rege0_ff_en), .i_D(d1l_in), .o_Q_TAP(o_D1L)
,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_d1l_reg_valid_mask),
    .o_SS_ACK        (ss_u_d1l_reg_ack),
    .o_SS_ERROR      (ss_u_d1l_reg_error),
    .o_SS_RDATA      (ss_u_d1l_reg_rdata)
);

    cavebanpresto_ikaopm_ss_sr_bram #(.SS_MEM_BASE_BIT(13'd1536), .SS_META_BASE_BIT(13'd1926), .WIDTH(1), .LENGTH(32), .TAP(32)) u_amen_reg 
    (.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_CNTRRST(d32reg_cntr_rst), .i_WR(rega0_bf_en), .i_D(amen_in), .o_Q_TAP(amen_out)
,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_amen_reg_valid_mask),
    .o_SS_ACK        (ss_u_amen_reg_ack),
    .o_SS_ERROR      (ss_u_amen_reg_error),
    .o_SS_RDATA      (ss_u_amen_reg_rdata)
);

    cavebanpresto_ikaopm_ss_sr_bram #(.SS_MEM_BASE_BIT(13'd1568), .SS_META_BASE_BIT(13'd1936), .WIDTH(2), .LENGTH(32), .TAP(32)) u_ks_reg 
    (.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_CNTRRST(d32reg_cntr_rst), .i_WR(reg80_9f_en), .i_D(ks_in), .o_Q_TAP(o_KS)
,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_ks_reg_valid_mask),
    .o_SS_ACK        (ss_u_ks_reg_ack),
    .o_SS_ERROR      (ss_u_ks_reg_error),
    .o_SS_RDATA      (ss_u_ks_reg_rdata)
);

    cavebanpresto_ikaopm_ss_sr_bram #(.SS_MEM_BASE_BIT(13'd1632), .SS_META_BASE_BIT(13'd1946), .WIDTH(7), .LENGTH(32), .TAP(32)) u_tl_reg 
    (.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_CNTRRST(d32reg_cntr_rst), .i_WR(reg60_7f_en), .i_D(tl_in), .o_Q_TAP(o_TL)
,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_tl_reg_valid_mask),
    .o_SS_ACK        (ss_u_tl_reg_ack),
    .o_SS_ERROR      (ss_u_tl_reg_error),
    .o_SS_RDATA      (ss_u_tl_reg_rdata)
);

    assign  o_AMS = ams_out & {2{amen_out}};
end
endgenerate



///////////////////////////////////////////////////////////
//////  Write busy flag timer
////

//write busy timer
reg             busycntr_cnt;
wire            busycntr_ovfl;
cavebanpresto_ikaopm_ss_counter #(.SS_BASE_BIT(13'd257), .WIDTH(5)) u_busycntr (
    .i_EMUCLK(i_EMUCLK), .i_PCEN_n(phi1pcen_n), .i_NCEN_n(phi1ncen_n),
    .i_CNT(busycntr_cnt), .i_LD(1'b0), .i_RST(~mrst_n),
    .i_D(5'd0), .o_Q(), .o_CO(busycntr_ovfl)

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_busycntr_valid_mask),
    .o_SS_ACK        (ss_u_busycntr_ack),
    .o_SS_ERROR      (ss_u_busycntr_error),
    .o_SS_RDATA      (ss_u_busycntr_rdata)
);

//write busy flag
reg             write_busy;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd7: begin
                    busycntr_cnt <= i_SS_WDATA[15];
                    write_busy <= i_SS_WDATA[16];
                end
                default: ;
            endcase
        end
    end else begin
        begin
            if(!phi1pcen_n) write_busy <= (write_busy & ~(~mrst_n | busycntr_ovfl)) | data_ld;
            if(!phi1ncen_n) busycntr_cnt <= write_busy;
        end
    end
end





///////////////////////////////////////////////////////////
//////  Read-only register multiplexer
////

wire        [7:0]   internal_data = o_TEST[7] ? {i_REG_PHASE_CH6_C2, i_REG_ATTENLEVEL_CH8_C2, i_REG_OPDATA[13:8]} : i_REG_OPDATA[7:0];
assign  o_D = o_TEST[6] ? internal_data : {write_busy, 5'b00000, i_TIMERB_FLAG, i_TIMERA_FLAG};

assign  o_D_OE = ~|{~mrst_n, ~i_A0, i_RD_n, i_CS_n};


// CaveBanpresto exact-state word instrumentation.

always @(*) begin
    ss_local_valid_mask = 32'd0;
    ss_local_read_data = 32'd0;
    case (i_SS_WORD_ADDR)
        8'd2: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[7:0] = o_TEST;
            ss_local_read_data[8] = o_CT1;
            ss_local_read_data[9] = o_CT2;
            ss_local_read_data[10] = o_NE;
            ss_local_read_data[15:11] = o_NFRQ;
            ss_local_read_data[23:16] = o_CLKA1;
            ss_local_read_data[25:24] = o_CLKA2;
            ss_local_read_data[31:26] = o_CLKB[5:0];
        end
        8'd3: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[1:0] = o_CLKB[7:6];
            ss_local_read_data[2] = o_TIMERA_RUN;
            ss_local_read_data[3] = o_TIMERB_RUN;
            ss_local_read_data[4] = o_TIMERA_IRQ_EN;
            ss_local_read_data[5] = o_TIMERB_IRQ_EN;
            ss_local_read_data[13:6] = o_LFRQ;
            ss_local_read_data[20:14] = o_PMD;
            ss_local_read_data[27:21] = o_AMD;
            ss_local_read_data[29:28] = o_W;
            ss_local_read_data[30] = cycle_02;
            ss_local_read_data[31] = dreg_rq_synced0;
        end
        8'd4: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[0] = dreg_rq_synced1;
            ss_local_read_data[1] = dreg_rq_synced2;
            ss_local_read_data[2] = areg_rq_synced0;
            ss_local_read_data[3] = areg_rq_synced1;
            ss_local_read_data[4] = areg_rq_synced2;
            ss_local_read_data[12:5] = dbus_inlatch;
            ss_local_read_data[20:13] = FULLY_SYNCHRONOUS_1_busctrl.din_syncchain[0];
            ss_local_read_data[28:21] = FULLY_SYNCHRONOUS_1_busctrl.din_syncchain[1];
            ss_local_read_data[30:29] = FULLY_SYNCHRONOUS_1_busctrl.cs_n_syncchain;
            ss_local_read_data[31] = FULLY_SYNCHRONOUS_1_busctrl.wr_n_syncchain[0];
        end
        8'd5: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[0] = FULLY_SYNCHRONOUS_1_busctrl.wr_n_syncchain[1];
            ss_local_read_data[2:1] = FULLY_SYNCHRONOUS_1_busctrl.a0_syncchain;
            ss_local_read_data[10:3] = hireg_addr;
            ss_local_read_data[11] = hireg_addr_valid;
            ss_local_read_data[19:12] = hireg_data;
            ss_local_read_data[20] = hireg_data_valid;
            ss_local_read_data[21] = reg38_3f_en;
            ss_local_read_data[22] = reg30_37_en;
            ss_local_read_data[23] = reg28_2f_en;
            ss_local_read_data[24] = reg20_27_en;
            ss_local_read_data[25] = rege0_ff_en;
            ss_local_read_data[26] = regc0_df_en;
            ss_local_read_data[27] = rega0_bf_en;
            ss_local_read_data[28] = reg80_9f_en;
            ss_local_read_data[29] = reg60_7f_en;
            ss_local_read_data[30] = reg40_5f_en;
            ss_local_read_data[31] = ct_reg[0];
        end
        8'd6: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[0] = ct_reg[1];
            ss_local_read_data[1] = csm_reg;
            ss_local_read_data[8:2] = kon_temp_reg;
            ss_local_read_data[9] = ch_equal;
            ss_local_read_data[10] = force_kon;
            ss_local_read_data[11] = kon_m1;
            ss_local_read_data[12] = kon_m2;
            ss_local_read_data[13] = kon_c1;
            ss_local_read_data[14] = kon_c2;
            ss_local_read_data[22:15] = kon_sr_0_7;
            ss_local_read_data[30:23] = kon_sr_8_15;
            ss_local_read_data[31] = kon_sr_16_23[0];
        end
        8'd7: begin
            ss_local_valid_mask = 32'h0001ffff;
            ss_local_read_data[6:0] = kon_sr_16_23[7:1];
            ss_local_read_data[14:7] = kon_sr_24_31;
            ss_local_read_data[15] = busycntr_cnt;
            ss_local_read_data[16] = write_busy;
        end
        default: ;
    endcase
end

assign ss_local_accept =
    i_SS_HOLD && i_SS_REQ && (|ss_local_valid_mask) && !ss_local_seen_q;
assign ss_local_write_accept = ss_local_accept && i_SS_WRITE;

always @(posedge i_EMUCLK) begin
    if (!i_SS_HOLD) begin
        ss_local_seen_q <= 1'b0;
        ss_local_ack_q <= 1'b0;
        ss_local_rdata_q <= 32'd0;
    end else begin
        ss_local_ack_q <= 1'b0;
        if (!i_SS_REQ)
            ss_local_seen_q <= 1'b0;
        if (ss_local_accept) begin
            ss_local_seen_q <= 1'b1;
            ss_local_ack_q <= 1'b1;
            ss_local_rdata_q <= ss_local_read_data;
        end
    end
end

assign o_SS_VALID_MASK = ss_local_valid_mask | ss_u_reg10_valid_mask | ss_u_reg11_valid_mask | ss_u_reg12_valid_mask | ss_u_reg14_valid_mask | ss_u_reg01_valid_mask | ss_u_reg0f_valid_mask | ss_u_reg19_valid_mask | ss_u_reg18_valid_mask | ss_u_reg1b_valid_mask | ss_u_reg08_valid_mask | ss_u_hireg_addrcntr_valid_mask | ss_u_busycntr_valid_mask | ss_u_dbus_inlatch_temp_valid_mask | ss_u_dreg_req_inlatch_valid_mask | ss_u_areg_req_inlatch_valid_mask | ss_u_pms_reg_valid_mask | ss_u_ams_reg_valid_mask | ss_u_kf_reg_valid_mask | ss_u_kc_reg_valid_mask | ss_u_fl_reg_valid_mask | ss_u_alg_reg_valid_mask | ss_u_rl_reg_valid_mask | ss_u_dt2_reg_valid_mask | ss_u_dt1_reg_valid_mask | ss_u_mul_reg_valid_mask | ss_u_ar_reg_valid_mask | ss_u_d1r_reg_valid_mask | ss_u_d2r_reg_valid_mask | ss_u_rr_reg_valid_mask | ss_u_d1l_reg_valid_mask | ss_u_amen_reg_valid_mask | ss_u_ks_reg_valid_mask | ss_u_tl_reg_valid_mask;
assign o_SS_ACK = ss_local_ack_q | ss_u_reg10_ack | ss_u_reg11_ack | ss_u_reg12_ack | ss_u_reg14_ack | ss_u_reg01_ack | ss_u_reg0f_ack | ss_u_reg19_ack | ss_u_reg18_ack | ss_u_reg1b_ack | ss_u_reg08_ack | ss_u_hireg_addrcntr_ack | ss_u_busycntr_ack | ss_u_dbus_inlatch_temp_ack | ss_u_dreg_req_inlatch_ack | ss_u_areg_req_inlatch_ack | ss_u_pms_reg_ack | ss_u_ams_reg_ack | ss_u_kf_reg_ack | ss_u_kc_reg_ack | ss_u_fl_reg_ack | ss_u_alg_reg_ack | ss_u_rl_reg_ack | ss_u_dt2_reg_ack | ss_u_dt1_reg_ack | ss_u_mul_reg_ack | ss_u_ar_reg_ack | ss_u_d1r_reg_ack | ss_u_d2r_reg_ack | ss_u_rr_reg_ack | ss_u_d1l_reg_ack | ss_u_amen_reg_ack | ss_u_ks_reg_ack | ss_u_tl_reg_ack;
assign o_SS_ERROR = 1'b0 | ss_u_reg10_error | ss_u_reg11_error | ss_u_reg12_error | ss_u_reg14_error | ss_u_reg01_error | ss_u_reg0f_error | ss_u_reg19_error | ss_u_reg18_error | ss_u_reg1b_error | ss_u_reg08_error | ss_u_hireg_addrcntr_error | ss_u_busycntr_error | ss_u_dbus_inlatch_temp_error | ss_u_dreg_req_inlatch_error | ss_u_areg_req_inlatch_error | ss_u_pms_reg_error | ss_u_ams_reg_error | ss_u_kf_reg_error | ss_u_kc_reg_error | ss_u_fl_reg_error | ss_u_alg_reg_error | ss_u_rl_reg_error | ss_u_dt2_reg_error | ss_u_dt1_reg_error | ss_u_mul_reg_error | ss_u_ar_reg_error | ss_u_d1r_reg_error | ss_u_d2r_reg_error | ss_u_rr_reg_error | ss_u_d1l_reg_error | ss_u_amen_reg_error | ss_u_ks_reg_error | ss_u_tl_reg_error;
assign o_SS_RDATA = (ss_local_rdata_q & ss_local_valid_mask) | (ss_u_reg10_rdata & ss_u_reg10_valid_mask) | (ss_u_reg11_rdata & ss_u_reg11_valid_mask) | (ss_u_reg12_rdata & ss_u_reg12_valid_mask) | (ss_u_reg14_rdata & ss_u_reg14_valid_mask) | (ss_u_reg01_rdata & ss_u_reg01_valid_mask) | (ss_u_reg0f_rdata & ss_u_reg0f_valid_mask) | (ss_u_reg19_rdata & ss_u_reg19_valid_mask) | (ss_u_reg18_rdata & ss_u_reg18_valid_mask) | (ss_u_reg1b_rdata & ss_u_reg1b_valid_mask) | (ss_u_reg08_rdata & ss_u_reg08_valid_mask) | (ss_u_hireg_addrcntr_rdata & ss_u_hireg_addrcntr_valid_mask) | (ss_u_busycntr_rdata & ss_u_busycntr_valid_mask) | (ss_u_dbus_inlatch_temp_rdata & ss_u_dbus_inlatch_temp_valid_mask) | (ss_u_dreg_req_inlatch_rdata & ss_u_dreg_req_inlatch_valid_mask) | (ss_u_areg_req_inlatch_rdata & ss_u_areg_req_inlatch_valid_mask) | (ss_u_pms_reg_rdata & ss_u_pms_reg_valid_mask) | (ss_u_ams_reg_rdata & ss_u_ams_reg_valid_mask) | (ss_u_kf_reg_rdata & ss_u_kf_reg_valid_mask) | (ss_u_kc_reg_rdata & ss_u_kc_reg_valid_mask) | (ss_u_fl_reg_rdata & ss_u_fl_reg_valid_mask) | (ss_u_alg_reg_rdata & ss_u_alg_reg_valid_mask) | (ss_u_rl_reg_rdata & ss_u_rl_reg_valid_mask) | (ss_u_dt2_reg_rdata & ss_u_dt2_reg_valid_mask) | (ss_u_dt1_reg_rdata & ss_u_dt1_reg_valid_mask) | (ss_u_mul_reg_rdata & ss_u_mul_reg_valid_mask) | (ss_u_ar_reg_rdata & ss_u_ar_reg_valid_mask) | (ss_u_d1r_reg_rdata & ss_u_d1r_reg_valid_mask) | (ss_u_d2r_reg_rdata & ss_u_d2r_reg_valid_mask) | (ss_u_rr_reg_rdata & ss_u_rr_reg_valid_mask) | (ss_u_d1l_reg_rdata & ss_u_d1l_reg_valid_mask) | (ss_u_amen_reg_rdata & ss_u_amen_reg_valid_mask) | (ss_u_ks_reg_rdata & ss_u_ks_reg_valid_mask) | (ss_u_tl_reg_rdata & ss_u_tl_reg_valid_mask);


endmodule

module cavebanpresto_ikaopm_ss_noise #(parameter integer SS_BASE_BIT = 1984) (
    //master clock
    input   wire            i_EMUCLK, //emulator master clock

    //core internal reset
    input   wire            i_MRST_n,

    //internal clock
    input   wire            i_phi1_PCEN_n, //positive edge clock enable for emulation
    input   wire            i_phi1_NCEN_n, //negative edge clock enable for emulation

    //timings
    input   wire            i_CYCLE_12,
    input   wire            i_CYCLE_15_31,

    //register data
    input   wire    [4:0]   i_NFRQ,

    //noise attenuation level input for muting(atten max detection)
    input   wire            i_NOISE_ATTENLEVEL,

    //output data
    output  wire    [13:0]  o_ACC_NOISE,
    output  wire            o_LFO_NOISE

,
    input   wire            i_SS_HOLD,
    input   wire            i_SS_REQ,
    input   wire            i_SS_WRITE,
    input   wire    [7:0]   i_SS_WORD_ADDR,
    input   wire    [31:0]  i_SS_WDATA,
    output  wire    [31:0]  o_SS_VALID_MASK,
    output  wire            o_SS_ACK,
    output  wire            o_SS_ERROR,
    output  wire    [31:0]  o_SS_RDATA
);

// Forward declarations for exact-state instrumentation.
wire ss_local_write_accept;
wire ss_local_accept;
reg ss_local_seen_q;
reg ss_local_ack_q;
reg [31:0] ss_local_rdata_q;
reg [31:0] ss_local_valid_mask;
reg [31:0] ss_local_read_data;
wire [31:0] ss_u_noise_freqgen_valid_mask;
wire ss_u_noise_freqgen_ack;
wire ss_u_noise_freqgen_error;
wire [31:0] ss_u_noise_freqgen_rdata;




///////////////////////////////////////////////////////////
//////  Clock and reset
////

wire            phi1pcen_n = i_phi1_PCEN_n;
wire            phi1ncen_n = i_phi1_NCEN_n;
wire            mrst_n = i_MRST_n;



///////////////////////////////////////////////////////////
//////  Noise frequency tick generator
////

wire    [4:0]   noise_freqgen_value;
reg             noise_update, noise_update_z;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd62: begin
                    noise_update <= i_SS_WDATA[0];
                    noise_update_z <= i_SS_WDATA[1];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            noise_update <= (noise_freqgen_value == ~i_NFRQ);
            noise_update_z <= noise_update;
        end
    end
end

cavebanpresto_ikaopm_ss_counter #(.SS_BASE_BIT(13'd2027), .WIDTH(5)) u_noise_freqgen (
    .i_EMUCLK(i_EMUCLK), .i_PCEN_n(phi1pcen_n), .i_NCEN_n(phi1ncen_n),
    .i_CNT(i_CYCLE_15_31), .i_LD(1'b0), .i_RST(~mrst_n | (noise_update & i_CYCLE_15_31)),
    .i_D(5'd0), .o_Q(noise_freqgen_value), .o_CO()

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_noise_freqgen_valid_mask),
    .o_SS_ACK        (ss_u_noise_freqgen_ack),
    .o_SS_ERROR      (ss_u_noise_freqgen_error),
    .o_SS_RDATA      (ss_u_noise_freqgen_rdata)
);



///////////////////////////////////////////////////////////
//////  LFSR
////

reg     [15:0]  noise_lfsr;
reg             xor_flag;
wire            xor_fdbk = (xor_flag ^ noise_lfsr[2]) | (noise_lfsr == 16'h0000 && xor_flag == 1'b0);
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd62: begin
                    noise_lfsr <= i_SS_WDATA[17:2];
                    xor_flag <= i_SS_WDATA[18];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            noise_lfsr[15] <= !mrst_n ? 1'b0 : 
                                        noise_update_z ? xor_fdbk : noise_lfsr[0];
            noise_lfsr[14:0] <= noise_lfsr[15:1];

            xor_flag  <= !mrst_n ? noise_lfsr[0] :
                                   noise_update_z ? noise_lfsr[0] : xor_flag;
        end
    end
end

wire            noise_serial = noise_lfsr[1];
assign  o_LFO_NOISE = noise_serial;



///////////////////////////////////////////////////////////
//////  Noise muting detection
////

reg             is_attenlevel_max; //zero detected = attenlevel is not max
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd62: begin
                    is_attenlevel_max <= i_SS_WDATA[19];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            is_attenlevel_max <= i_CYCLE_12 ? 1'b1 : (i_NOISE_ATTENLEVEL & is_attenlevel_max);
        end
    end
end



///////////////////////////////////////////////////////////
//////  Noise SIPO
////

reg             noise_sign_z, noise_sign_zz;
reg     [8:0]   noise_sipo_sr;

//flags
reg             noise_mute;
reg             noise_sign;
reg             noise_redundant_bit;
reg     [8:0]   noise_parallel;

always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd62: begin
                    noise_sign_z <= i_SS_WDATA[20];
                    noise_sign_zz <= i_SS_WDATA[21];
                    noise_sipo_sr <= i_SS_WDATA[30:22];
                    noise_mute <= i_SS_WDATA[31];
                end
                8'd63: begin
                    noise_sign <= i_SS_WDATA[0];
                    noise_redundant_bit <= i_SS_WDATA[1];
                    noise_parallel <= i_SS_WDATA[10:2];
                end
                default: ;
            endcase
        end
    end else begin
        begin
            if(!phi1ncen_n) begin
                noise_sign_z <= noise_sign;
                noise_sign_zz <= noise_sign_z;

                noise_sipo_sr[0] <= noise_sign_zz ^ ~i_NOISE_ATTENLEVEL;
                noise_sipo_sr[8:1] <= noise_sipo_sr[7:0];
            end

            if(!phi1pcen_n) begin
                if(i_CYCLE_12) begin
                    noise_mute <= is_attenlevel_max; //latch mute flag
                    noise_sign <= noise_serial; //latch new sign bit
                    noise_redundant_bit <= noise_sign_z; //latch redundant bits: previous sign bit
                    noise_parallel <= noise_sipo_sr; //latch parallel output, discard MSB(really)
                end
            end    
        end
    end
end



///////////////////////////////////////////////////////////
//////  Make output
////

assign  o_ACC_NOISE = noise_mute ? 14'd0 : {{2{noise_redundant_bit}},
                                             noise_parallel,
                                            {3{noise_redundant_bit}}};


// CaveBanpresto exact-state word instrumentation.

always @(*) begin
    ss_local_valid_mask = 32'd0;
    ss_local_read_data = 32'd0;
    case (i_SS_WORD_ADDR)
        8'd62: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[0] = noise_update;
            ss_local_read_data[1] = noise_update_z;
            ss_local_read_data[17:2] = noise_lfsr;
            ss_local_read_data[18] = xor_flag;
            ss_local_read_data[19] = is_attenlevel_max;
            ss_local_read_data[20] = noise_sign_z;
            ss_local_read_data[21] = noise_sign_zz;
            ss_local_read_data[30:22] = noise_sipo_sr;
            ss_local_read_data[31] = noise_mute;
        end
        8'd63: begin
            ss_local_valid_mask = 32'h000007ff;
            ss_local_read_data[0] = noise_sign;
            ss_local_read_data[1] = noise_redundant_bit;
            ss_local_read_data[10:2] = noise_parallel;
        end
        default: ;
    endcase
end

assign ss_local_accept =
    i_SS_HOLD && i_SS_REQ && (|ss_local_valid_mask) && !ss_local_seen_q;
assign ss_local_write_accept = ss_local_accept && i_SS_WRITE;

always @(posedge i_EMUCLK) begin
    if (!i_SS_HOLD) begin
        ss_local_seen_q <= 1'b0;
        ss_local_ack_q <= 1'b0;
        ss_local_rdata_q <= 32'd0;
    end else begin
        ss_local_ack_q <= 1'b0;
        if (!i_SS_REQ)
            ss_local_seen_q <= 1'b0;
        if (ss_local_accept) begin
            ss_local_seen_q <= 1'b1;
            ss_local_ack_q <= 1'b1;
            ss_local_rdata_q <= ss_local_read_data;
        end
    end
end

assign o_SS_VALID_MASK = ss_local_valid_mask | ss_u_noise_freqgen_valid_mask;
assign o_SS_ACK = ss_local_ack_q | ss_u_noise_freqgen_ack;
assign o_SS_ERROR = 1'b0 | ss_u_noise_freqgen_error;
assign o_SS_RDATA = (ss_local_rdata_q & ss_local_valid_mask) | (ss_u_noise_freqgen_rdata & ss_u_noise_freqgen_valid_mask);



endmodule

module cavebanpresto_ikaopm_ss_lfo #(parameter integer SS_BASE_BIT = 2048) (
    //master clock
    input   wire            i_EMUCLK, //emulator master clock

    //core internal reset
    input   wire            i_MRST_n,

    //internal clock
    input   wire            i_phi1_PCEN_n, //positive edge clock enable for emulation
    input   wire            i_phi1_NCEN_n, //negative edge clock enable for emulation

    //timings
    input   wire            i_CYCLE_12_28,
    input   wire            i_CYCLE_05_21,
    input   wire            i_CYCLE_BYTE,

    //register data
    input   wire    [7:0]   i_LFRQ, //LFO frequency
    input   wire    [6:0]   i_AMD,  //amplitude modulation depth
    input   wire    [6:0]   i_PMD,  //phase modulation depth
    input   wire    [1:0]   i_W,    //waveform select
    input   wire            i_TEST_D1, //test register
    input   wire            i_TEST_D2,
    input   wire            i_TEST_D3,

    //control signal
    input   wire            i_LFRQ_UPDATE,

    //noise
    input   wire            i_LFO_NOISE,

    output  wire    [7:0]   o_LFP,
    output  wire    [7:0]   o_LFA,

    output  wire            o_REG_LFO_CLK

,
    input   wire            i_SS_HOLD,
    input   wire            i_SS_REQ,
    input   wire            i_SS_WRITE,
    input   wire    [7:0]   i_SS_WORD_ADDR,
    input   wire    [31:0]  i_SS_WDATA,
    output  wire    [31:0]  o_SS_VALID_MASK,
    output  wire            o_SS_ACK,
    output  wire            o_SS_ERROR,
    output  wire    [31:0]  o_SS_RDATA
);

// Forward declarations for exact-state instrumentation.
wire ss_local_write_accept;
wire ss_local_accept;
reg ss_local_seen_q;
reg ss_local_ack_q;
reg [31:0] ss_local_rdata_q;
reg [31:0] ss_local_valid_mask;
reg [31:0] ss_local_read_data;
wire [31:0] ss_u_lfo_prescaler_valid_mask;
wire ss_u_lfo_prescaler_ack;
wire ss_u_lfo_prescaler_error;
wire [31:0] ss_u_lfo_prescaler_rdata;
wire [31:0] ss_u_lfo_locntr_valid_mask;
wire ss_u_lfo_locntr_ack;
wire ss_u_lfo_locntr_error;
wire [31:0] ss_u_lfo_locntr_rdata;
wire [31:0] ss_u_lfo_hicntr_valid_mask;
wire ss_u_lfo_hicntr_ack;
wire ss_u_lfo_hicntr_error;
wire [31:0] ss_u_lfo_hicntr_rdata;
wire [31:0] ss_u_lfo_multiplier_bitselcntr_valid_mask;
wire ss_u_lfo_multiplier_bitselcntr_ack;
wire ss_u_lfo_multiplier_bitselcntr_error;
wire [31:0] ss_u_lfo_multiplier_bitselcntr_rdata;



///////////////////////////////////////////////////////////
//////  Clock and reset
////

wire            phi1pcen_n = i_phi1_PCEN_n;
wire            phi1ncen_n = i_phi1_NCEN_n;
wire            mrst_n = i_MRST_n;



///////////////////////////////////////////////////////////
//////  Cycle number
////

//additional cycle bits
reg             cycle_06_22, cycle_13_29, cycle_14_30, cycle_15_31;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd64: begin
                    cycle_06_22 <= i_SS_WDATA[0];
                    cycle_13_29 <= i_SS_WDATA[1];
                    cycle_14_30 <= i_SS_WDATA[2];
                    cycle_15_31 <= i_SS_WDATA[3];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cycle_06_22 <= i_CYCLE_05_21;

            cycle_13_29 <= i_CYCLE_12_28;
            cycle_14_30 <= cycle_13_29;
            cycle_15_31 <= cycle_14_30;
        end
    end
end

`ifdef IKAOPM_DEBUG
reg             debug_cycle_07_23;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        // Held: no emulation state advances.
    end else begin
        if(!phi1ncen_n) begin
            debug_cycle_07_23 <= cycle_06_22;
        end
    end
end
`endif



///////////////////////////////////////////////////////////
//////  Prescaler
////

//counter
wire    [3:0]   prescaler_value;
wire            prescaler_cout;
cavebanpresto_ikaopm_ss_counter #(.SS_BASE_BIT(13'd2154), .WIDTH(4)) u_lfo_prescaler (
    .i_EMUCLK(i_EMUCLK), .i_PCEN_n(phi1pcen_n), .i_NCEN_n(phi1ncen_n),
    .i_CNT(i_CYCLE_12_28), .i_LD(1'b0), .i_RST(~mrst_n),
    .i_D(4'd0), .o_Q(prescaler_value), .o_CO(prescaler_cout)

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_lfo_prescaler_valid_mask),
    .o_SS_ACK        (ss_u_lfo_prescaler_ack),
    .o_SS_ERROR      (ss_u_lfo_prescaler_error),
    .o_SS_RDATA      (ss_u_lfo_prescaler_rdata)
);

//cycle 2 / cout_z
reg             prescaler_cycle_2, prescaler_cout_z;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd64: begin
                    prescaler_cycle_2 <= i_SS_WDATA[4];
                    prescaler_cout_z <= i_SS_WDATA[5];
                end
                default: ;
            endcase
        end
    end else begin
        begin
            if(!phi1ncen_n) prescaler_cycle_2 <= prescaler_value == 4'd2;

            if(!phi1ncen_n) prescaler_cout_z <= prescaler_cout;
        end
    end
end



///////////////////////////////////////////////////////////
//////  LFO LUT and output latch
////

/*
    pre-initialized LFO LUT. The bit order of the original chip is:
      (LEFT) D1 - D7 / D14 - D8 (RIGHT)
    D0 is controlled by row F enable signal, so the table below contains the precalculated values

    lfo dout latch:
    the original one uses different edges due to carry delay of the counter cells
    so the counter for MSBs is delayed by a half phi1.
*/

reg     [14:0]  lfolut_dout;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd64: begin
                    lfolut_dout <= i_SS_WDATA[20:6];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            case(i_LFRQ[7:4])
                4'hF: lfolut_dout <= 15'h7FFF;
                4'hE: lfolut_dout <= 15'h7FFE;
                4'hD: lfolut_dout <= 15'h7FFC;
                4'hC: lfolut_dout <= 15'h7FF8;
                4'hB: lfolut_dout <= 15'h7FF0;
                4'hA: lfolut_dout <= 15'h7FE0;
                4'h9: lfolut_dout <= 15'h7FC0;
                4'h8: lfolut_dout <= 15'h7F80;
                4'h7: lfolut_dout <= 15'h7F00;
                4'h6: lfolut_dout <= 15'h7E00;
                4'h5: lfolut_dout <= 15'h7C00;
                4'h4: lfolut_dout <= 15'h7800;
                4'h3: lfolut_dout <= 15'h7000;
                4'h2: lfolut_dout <= 15'h6000;
                4'h1: lfolut_dout <= 15'h4000;
                4'h0: lfolut_dout <= 15'h1000;
            endcase
        end
    end
end



///////////////////////////////////////////////////////////
//////  LFRQ counter low bits
////

//locntr cnt up signal
reg             locntr_cnt;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd64: begin
                    locntr_cnt <= i_SS_WDATA[21];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            locntr_cnt <= prescaler_cout_z | i_TEST_D3; //de morgan
        end
    end
end

//locntr preload signal
wire            locntr_cout;
reg             locntr_cout_z, freq_update;
reg             locntr_ld;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd64: begin
                    locntr_cout_z <= i_SS_WDATA[22];
                    freq_update <= i_SS_WDATA[23];
                    locntr_ld <= i_SS_WDATA[24];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            locntr_cout_z <= locntr_cout;
            freq_update <= i_LFRQ_UPDATE;

            locntr_ld <= (locntr_cout_z | freq_update);
        end
    end
end

//define locntr
cavebanpresto_ikaopm_ss_counter #(.SS_BASE_BIT(13'd2159), .WIDTH(15)) u_lfo_locntr (
    .i_EMUCLK(i_EMUCLK), .i_PCEN_n(phi1pcen_n), .i_NCEN_n(phi1ncen_n),
    .i_CNT(locntr_cnt), .i_LD(locntr_ld), .i_RST(~mrst_n),
    .i_D(lfolut_dout), .o_Q(), .o_CO(locntr_cout)

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_lfo_locntr_valid_mask),
    .o_SS_ACK        (ss_u_lfo_locntr_ack),
    .o_SS_ERROR      (ss_u_lfo_locntr_error),
    .o_SS_RDATA      (ss_u_lfo_locntr_rdata)
);



///////////////////////////////////////////////////////////
//////  LFRQ counter high bits
////

//hicntr cout delay
reg             locntr_cout_step1, locntr_cout_step2;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd64: begin
                    locntr_cout_step1 <= i_SS_WDATA[25];
                    locntr_cout_step2 <= i_SS_WDATA[26];
                end
                default: ;
            endcase
        end
    end else begin
        begin
            if(!phi1pcen_n) if(cycle_15_31) locntr_cout_step1 <= locntr_cout_z;

            if(!phi1pcen_n) if(i_CYCLE_05_21) locntr_cout_step2 <= locntr_cout_step1; //use positive edge
        end
    end
end

//hicntr cnt up and output decoder enable
reg             hicntr_cnt;
wire            hicntr_decode_en = (cycle_13_29 & locntr_cout_step2); //de morgan
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd64: begin
                    hicntr_cnt <= i_SS_WDATA[27];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            hicntr_cnt <= hicntr_decode_en;
        end
    end
end

//counter
wire    [3:0]  hicntr_value;
cavebanpresto_ikaopm_ss_counter #(.SS_BASE_BIT(13'd2175), .WIDTH(4)) u_lfo_hicntr (
    .i_EMUCLK(i_EMUCLK), .i_PCEN_n(phi1pcen_n), .i_NCEN_n(phi1ncen_n),
    .i_CNT(hicntr_cnt), .i_LD(1'b0), .i_RST(~mrst_n),
    .i_D(4'd0), .o_Q(hicntr_value), .o_CO()

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_lfo_hicntr_valid_mask),
    .o_SS_ACK        (ss_u_lfo_hicntr_ack),
    .o_SS_ERROR      (ss_u_lfo_hicntr_error),
    .o_SS_RDATA      (ss_u_lfo_hicntr_rdata)
);

//hicntr complete flag
reg             hicntr_complete; //use positive edge
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd64: begin
                    hicntr_complete <= i_SS_WDATA[28];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            if(hicntr_decode_en) begin //decode locntr value only when decode_en == 1
                casez(hicntr_value)
                    4'b???0: hicntr_complete <= i_LFRQ[3];
                    4'b??01: hicntr_complete <= i_LFRQ[2];
                    4'b?011: hicntr_complete <= i_LFRQ[1];
                    4'b0111: hicntr_complete <= i_LFRQ[0];
                    
                    default: hicntr_complete <= 1'b0;
                endcase
            end
            else hicntr_complete <= 1'b0; //disable
        end
    end
end



///////////////////////////////////////////////////////////
//////  LFO clock generation
////

reg             lfo_clk;
assign  o_REG_LFO_CLK = lfo_clk;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd64: begin
                    lfo_clk <= i_SS_WDATA[29];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            lfo_clk <= |{locntr_cout, hicntr_complete, i_TEST_D2};
        end
    end
end



///////////////////////////////////////////////////////////
//////  latched LFO clock
////

//The original one used dynamic D-latch to latch lfo_clk
//I reused the signal above to eliminate a latch.
reg             lfo_clk_latched = 1'b0; //dynamic d latch
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd64: begin
                    lfo_clk_latched <= i_SS_WDATA[30];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            if(cycle_14_30) lfo_clk_latched <= |{locntr_cout, hicntr_complete, i_TEST_D2};
        end
    end
end



///////////////////////////////////////////////////////////
//////  waveform decoder
////

reg     [1:0]   wfsel;
wire            wfsel_noise = (wfsel == 2'd3);
wire            wfsel_tri   = (wfsel == 2'd2);
//wire            wfsel_sq    = (wfsel == 2'd1);
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd64: begin
                    wfsel[0] <= i_SS_WDATA[31];
                end
                8'd65: begin
                    wfsel[1] <= i_SS_WDATA[0];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            wfsel <= i_W;
        end
    end
end



///////////////////////////////////////////////////////////
//////  LFO phase accumulator
////

//test bit 1 latch
reg             tst_bit1_latched;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd65: begin
                    tst_bit1_latched <= i_SS_WDATA[1];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            tst_bit1_latched <= i_TEST_D1;
        end
    end
end

//phase accumulator
reg     [15:0]  phase_acc; //phase accumulator shift register
wire            phase_acc_lsb = phase_acc[0];

//full adder
wire    [1:0]   phase_acc_fa;
reg             phase_acc_fa_prev_carry = 1'b0;
always @(posedge i_EMUCLK or negedge mrst_n) begin
    if (!mrst_n) begin
        phase_acc_fa_prev_carry <= 1'b0;
    end else if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd65: begin
                    phase_acc_fa_prev_carry <= i_SS_WDATA[18];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) phase_acc_fa_prev_carry <= phase_acc_fa[1]; //store previous carry(serial full adder)
    end
end

//tri = enable / square, saw, noise = disable
wire            phase_acc_fa_a   =  &{cycle_15_31, lfo_clk, ~wfsel_noise} &
                                    wfsel_tri;

//tri, square, saw = enable / noise = temporarily disable 
wire            phase_acc_fa_b   =  mrst_n &
                                   ~tst_bit1_latched &
                                    phase_acc_lsb &
                                   ~(lfo_clk_latched & wfsel_noise);

//tri, square, saw = enable / noise = disable
wire            phase_acc_fa_cin = ~(|{cycle_15_31, ~phase_acc_fa_prev_carry, wfsel_noise} &
                                     ~&{cycle_15_31, lfo_clk, ~wfsel_noise});

assign  phase_acc_fa = phase_acc_fa_a + phase_acc_fa_b + phase_acc_fa_cin;


//noise input
reg             noise_input_z, noise_stream;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd65: begin
                    noise_input_z <= i_SS_WDATA[19];
                    noise_stream <= i_SS_WDATA[20];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            noise_input_z <= i_LFO_NOISE;
            noise_stream <= lfo_clk_latched & noise_input_z; //de morgan
        end
    end
end

//phase accumulator input
wire            phase_acc_input = phase_acc_fa[0] | (wfsel_noise & noise_stream);

//shift accumulator
always @(posedge i_EMUCLK or negedge mrst_n) begin
    if (!mrst_n) begin
        phase_acc <= 16'h0;
    end else if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd65: begin
                    phase_acc <= i_SS_WDATA[17:2];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            phase_acc[15] <= phase_acc_input;
            phase_acc[14:0] <= phase_acc[15:1];
        end
    end
end

//for debug
`ifdef IKAOPM_DEBUG
reg     [15:0]      debug_phase_acc;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        // Held: no emulation state advances.
    end else begin
        if(!phi1ncen_n) begin
            if(cycle_15_31) debug_phase_acc <= phase_acc;
        end
    end
end
`endif


///////////////////////////////////////////////////////////
//////  Bit select counter for base value multiply
////

//define counter
wire    [3:0]   multiplier_bitselcntr_value;
cavebanpresto_ikaopm_ss_counter #(.SS_BASE_BIT(13'd2180), .WIDTH(4)) u_lfo_multiplier_bitselcntr (
    .i_EMUCLK(i_EMUCLK), .i_PCEN_n(phi1pcen_n), .i_NCEN_n(phi1ncen_n),
    .i_CNT(cycle_14_30), .i_LD(1'b0), .i_RST(prescaler_cycle_2 & i_CYCLE_12_28),
    .i_D(4'd0), .o_Q(multiplier_bitselcntr_value), .o_CO()

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_lfo_multiplier_bitselcntr_valid_mask),
    .o_SS_ACK        (ss_u_lfo_multiplier_bitselcntr_ack),
    .o_SS_ERROR      (ss_u_lfo_multiplier_bitselcntr_error),
    .o_SS_RDATA      (ss_u_lfo_multiplier_bitselcntr_rdata)
);

//this counter output value selects AMD/PMD bit
reg     [2:0]   multiplier_bitsel;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd65: begin
                    multiplier_bitsel <= i_SS_WDATA[23:21];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            multiplier_bitsel <= multiplier_bitselcntr_value[2:0]; //store value at negative edge
        end
    end
end

//timings/control
wire            a_np_sel = ~multiplier_bitselcntr_value[3]; //AMD/PMD mux select
wire            multiplier_bitselcntr_cycle_0_8 = multiplier_bitselcntr_value == 4'd0 | multiplier_bitselcntr_value == 4'd8;
wire            multiplier_bitsel_0 = multiplier_bitsel == 3'd0;
wire            multiplier_bitsel_7 = multiplier_bitsel == 3'd7;



///////////////////////////////////////////////////////////
//////  Sigh bit latch
////

//triangle/sawtooth sign bit latch
/*
    phi1    |_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯
            |----(14_30)----|----(15_31)----|----(0_16)----|

    d valid <--------------> <-------------> <------------->
    0_8     ________|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯
    latchen ________________|¯¯¯¯¯¯¯|_______________________

    dff                             ^ <-- sample here     
*/

reg             wf_tri_sign, wf_saw_sign;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd65: begin
                    wf_tri_sign <= i_SS_WDATA[24];
                    wf_saw_sign <= i_SS_WDATA[25];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1pcen_n) begin
            if(cycle_15_31 & multiplier_bitselcntr_cycle_0_8) begin
                wf_tri_sign <= phase_acc[8];
                wf_saw_sign <= phase_acc[7];
            end
        end
    end
end



///////////////////////////////////////////////////////////
//////  Oscillator base value generator
////

//amd/pmd select latch
reg             a_np_sel_latched;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd65: begin
                    a_np_sel_latched <= i_SS_WDATA[26];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            a_np_sel_latched <= a_np_sel;
        end
    end
end

//base value stream, behavioral implementation
//              waveform type                           (             AM            ) : (             PM             )
wire            noise_value_stream = a_np_sel_latched ? phase_acc_fa_b ^ 1'b1         : (phase_acc_fa_b ^ wf_saw_sign);
wire            tri_value_stream   = a_np_sel_latched ? phase_acc_fa_b ^ ~wf_tri_sign : (phase_acc_fa_b ^ wf_saw_sign);
wire            sq_value_stream    = a_np_sel_latched ?         ~wf_saw_sign          :          cycle_06_22          ;
wire            saw_value_stream   = a_np_sel_latched ? phase_acc_fa_b ^ 1'b1         : (phase_acc_fa_b ^ wf_saw_sign);

//input selector
reg             base_value_input;
always @(*) begin
    if(i_CYCLE_BYTE) begin
        case(wfsel)
            2'd3: base_value_input = noise_value_stream;
            2'd2: base_value_input = tri_value_stream; //gawr gura
            2'd1: base_value_input = sq_value_stream;
            2'd0: base_value_input = saw_value_stream;
        endcase
    end
    else base_value_input = 1'b0;
end

//base value shift register
reg     [6:0]   base_value_sr;
always @(posedge i_EMUCLK or negedge mrst_n) begin
    if (!mrst_n) begin
        base_value_sr <= 7'h00;
    end else if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd65: begin
                    base_value_sr[4:0] <= i_SS_WDATA[31:27];
                end
                8'd66: begin
                    base_value_sr[6:5] <= i_SS_WDATA[1:0];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            base_value_sr[6] <= base_value_input;
            base_value_sr[5:0] <= base_value_sr[6:1];
        end
    end
end

//debug
`ifdef IKAOPM_DEBUG
reg     [6:0]   debug_base_value_am, debug_base_value_pm;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        // Held: no emulation state advances.
    end else begin
        if(!phi1ncen_n) begin
            if(debug_cycle_07_23) begin
                if(a_np_sel_latched) debug_base_value_am <= base_value_sr;
                else debug_base_value_pm <= base_value_sr;
            end
        end
    end
end
`endif



///////////////////////////////////////////////////////////
//////  Volume multiplier
////

/*
                         TAP
                                MSB 6   5   4   3   2   1   0 LSB

    Base value shift register       0   1   1   0   1   0   1

    Volume register(AMD/PMD)        1   0   0   1   1   0   0

    1. pick volume_reg[6] and do AND with the base value[6:0], add serially, from the LSB
    -> 0110101

    2. pick volume reg[5] and do AND with the base value {1'b0, value[6:1]}, add serially, from the LSB
    -> 0000000

    3. pick volume reg[4] and do AND with the base value {2'b00, value[6:2]}, add serially, from the LSB
    -> 0000000

    ...repeat for all bits of AMD/PMD

    now the process above can be expressed like below
        0110101
        0000000
        0000000
        0000110
        0000011
        0000000
        0000000 +
    =   0111110       ====> this is the final value calculated

    Volume format X.XXXXXX fixed point.
    AMD/PMD bit 6 is decimal part, and bit 5 to 0 is fractional part. Step width 0.015625.
*/

//AMD/PMD mux
reg     [6:0]   ap_muxed;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd66: begin
                    ap_muxed <= i_SS_WDATA[8:2];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            ap_muxed <= a_np_sel ? i_AMD : i_PMD;
        end
    end
end

//bit selector
reg             multiplier_fa_b;
always @(*) begin
    case(multiplier_bitsel)
        3'b000: multiplier_fa_b = base_value_sr[0] & ap_muxed[6];
        3'b001: multiplier_fa_b = base_value_sr[1] & ap_muxed[5];
        3'b010: multiplier_fa_b = base_value_sr[2] & ap_muxed[4];
        3'b011: multiplier_fa_b = base_value_sr[3] & ap_muxed[3];
        3'b100: multiplier_fa_b = base_value_sr[4] & ap_muxed[2];
        3'b101: multiplier_fa_b = base_value_sr[5] & ap_muxed[1];
        3'b110: multiplier_fa_b = base_value_sr[6] & ap_muxed[0];
        3'b111: multiplier_fa_b = 1'b0;
    endcase 
end

//multiplier
wire    [1:0]   multiplier_fa;
reg     [15:0]  multiplier_sr = 16'h0;

always @(posedge i_EMUCLK or negedge mrst_n) begin
    if (!mrst_n) begin
        multiplier_sr <= 16'h0;
    end else if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd66: begin
                    multiplier_sr <= i_SS_WDATA[24:9];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            multiplier_sr[15] <= multiplier_fa[0];
            multiplier_sr[14:0] <= multiplier_sr[15:1];
        end
    end
end

reg             multiplier_prev_carry = 1'b0;
always @(posedge i_EMUCLK or negedge mrst_n) begin
    if (!mrst_n) begin
        multiplier_prev_carry <= 1'b0;
    end else if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd66: begin
                    multiplier_prev_carry <= i_SS_WDATA[25];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) multiplier_prev_carry <= multiplier_fa[1];
    end
end

wire            multiplier_fa_a = ~(~multiplier_sr[0] | multiplier_bitsel_0);
wire            multiplier_fa_cin = multiplier_prev_carry & ~cycle_15_31;

assign  multiplier_fa = multiplier_fa_a + multiplier_fa_b + multiplier_fa_cin;



///////////////////////////////////////////////////////////
//////  LFA/LFP latch
////

//LFA LFP register load
wire            lfa_reg_ld = &{cycle_15_31, multiplier_bitsel_7, a_np_sel};
wire            lfp_reg_ld = &{cycle_15_31, multiplier_bitsel_7, ~a_np_sel};

//LFA LFP register
reg     [7:0]   lfa_reg, lfp_reg;
assign  o_LFA = lfa_reg;
assign  o_LFP = lfp_reg;

//LFP sign/value control
wire            pmd_zero = i_PMD == 7'h00;
wire            lfp_sign_ctrl = wfsel_tri ? wf_tri_sign : wf_saw_sign; //AOI

//note that LFA is 8-bit unsigned, LFP is 8-bit sign(1 = negative) and magnitude output
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd66: begin
                    lfa_reg[5:0] <= i_SS_WDATA[31:26];
                end
                8'd67: begin
                    lfa_reg[7:6] <= i_SS_WDATA[1:0];
                    lfp_reg <= i_SS_WDATA[9:2];
                end
                default: ;
            endcase
        end
    end else begin
        begin
            //negative edge
            if(!phi1ncen_n) begin
                if(!mrst_n) lfa_reg <= 8'd0; 
                else begin
                    if(lfa_reg_ld) lfa_reg <= multiplier_sr[15:8];
                end
            end

            //positive edge
            if(!phi1pcen_n) begin
                if(!mrst_n) lfp_reg <= 8'd0;
                else begin
                    if(lfp_reg_ld) lfp_reg <= (pmd_zero == 1'b1) ? 8'h00 : {~(multiplier_sr[15] ^ ~lfp_sign_ctrl), multiplier_sr[14:8]};
                end
            end
        end
    end
end

//lfp debug(2's complement)
`ifdef IKAOPM_DEBUG
reg     [7:0]   debug_lfp_reg_pitchmod, debug_lfa_reg_attenlevel;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        // Held: no emulation state advances.
    end else begin
        begin
            if(!phi1ncen_n) 
                if(lfa_reg_ld) begin 
                    debug_lfa_reg_attenlevel <= multiplier_sr[15:8]; 
                end
            if(!phi1pcen_n) begin
                if(lfp_reg_ld) 
                    debug_lfp_reg_pitchmod <= (pmd_zero == 1'b1) ? 8'h80 : 
                                              (~(multiplier_sr[15] ^ ~lfp_sign_ctrl) == 1'b1) ? (~multiplier_sr[14:8] + 7'h1) : multiplier_sr[14:8];
            end
        end
    end
end
`endif


// CaveBanpresto exact-state word instrumentation.

always @(*) begin
    ss_local_valid_mask = 32'd0;
    ss_local_read_data = 32'd0;
    case (i_SS_WORD_ADDR)
        8'd64: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[0] = cycle_06_22;
            ss_local_read_data[1] = cycle_13_29;
            ss_local_read_data[2] = cycle_14_30;
            ss_local_read_data[3] = cycle_15_31;
            ss_local_read_data[4] = prescaler_cycle_2;
            ss_local_read_data[5] = prescaler_cout_z;
            ss_local_read_data[20:6] = lfolut_dout;
            ss_local_read_data[21] = locntr_cnt;
            ss_local_read_data[22] = locntr_cout_z;
            ss_local_read_data[23] = freq_update;
            ss_local_read_data[24] = locntr_ld;
            ss_local_read_data[25] = locntr_cout_step1;
            ss_local_read_data[26] = locntr_cout_step2;
            ss_local_read_data[27] = hicntr_cnt;
            ss_local_read_data[28] = hicntr_complete;
            ss_local_read_data[29] = lfo_clk;
            ss_local_read_data[30] = lfo_clk_latched;
            ss_local_read_data[31] = wfsel[0];
        end
        8'd65: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[0] = wfsel[1];
            ss_local_read_data[1] = tst_bit1_latched;
            ss_local_read_data[17:2] = phase_acc;
            ss_local_read_data[18] = phase_acc_fa_prev_carry;
            ss_local_read_data[19] = noise_input_z;
            ss_local_read_data[20] = noise_stream;
            ss_local_read_data[23:21] = multiplier_bitsel;
            ss_local_read_data[24] = wf_tri_sign;
            ss_local_read_data[25] = wf_saw_sign;
            ss_local_read_data[26] = a_np_sel_latched;
            ss_local_read_data[31:27] = base_value_sr[4:0];
        end
        8'd66: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[1:0] = base_value_sr[6:5];
            ss_local_read_data[8:2] = ap_muxed;
            ss_local_read_data[24:9] = multiplier_sr;
            ss_local_read_data[25] = multiplier_prev_carry;
            ss_local_read_data[31:26] = lfa_reg[5:0];
        end
        8'd67: begin
            ss_local_valid_mask = 32'h000003ff;
            ss_local_read_data[1:0] = lfa_reg[7:6];
            ss_local_read_data[9:2] = lfp_reg;
        end
        default: ;
    endcase
end

assign ss_local_accept =
    i_SS_HOLD && i_SS_REQ && (|ss_local_valid_mask) && !ss_local_seen_q;
assign ss_local_write_accept = ss_local_accept && i_SS_WRITE;

always @(posedge i_EMUCLK) begin
    if (!i_SS_HOLD) begin
        ss_local_seen_q <= 1'b0;
        ss_local_ack_q <= 1'b0;
        ss_local_rdata_q <= 32'd0;
    end else begin
        ss_local_ack_q <= 1'b0;
        if (!i_SS_REQ)
            ss_local_seen_q <= 1'b0;
        if (ss_local_accept) begin
            ss_local_seen_q <= 1'b1;
            ss_local_ack_q <= 1'b1;
            ss_local_rdata_q <= ss_local_read_data;
        end
    end
end

assign o_SS_VALID_MASK = ss_local_valid_mask | ss_u_lfo_prescaler_valid_mask | ss_u_lfo_locntr_valid_mask | ss_u_lfo_hicntr_valid_mask | ss_u_lfo_multiplier_bitselcntr_valid_mask;
assign o_SS_ACK = ss_local_ack_q | ss_u_lfo_prescaler_ack | ss_u_lfo_locntr_ack | ss_u_lfo_hicntr_ack | ss_u_lfo_multiplier_bitselcntr_ack;
assign o_SS_ERROR = 1'b0 | ss_u_lfo_prescaler_error | ss_u_lfo_locntr_error | ss_u_lfo_hicntr_error | ss_u_lfo_multiplier_bitselcntr_error;
assign o_SS_RDATA = (ss_local_rdata_q & ss_local_valid_mask) | (ss_u_lfo_prescaler_rdata & ss_u_lfo_prescaler_valid_mask) | (ss_u_lfo_locntr_rdata & ss_u_lfo_locntr_valid_mask) | (ss_u_lfo_hicntr_rdata & ss_u_lfo_hicntr_valid_mask) | (ss_u_lfo_multiplier_bitselcntr_rdata & ss_u_lfo_multiplier_bitselcntr_valid_mask);



endmodule

module cavebanpresto_ikaopm_ss_pg #(parameter integer SS_BASE_BIT = 2208, parameter USE_BRAM_FOR_PHASEREG = 0) (
    //master clock
    input   wire            i_EMUCLK, //emulator master clock

    //core internal reset
    input   wire            i_MRST_n,

    //internal clock
    input   wire            i_phi1_PCEN_n, //positive edge clock enable for emulation
    input   wire            i_phi1_NCEN_n, //negative edge clock enable for emulation

    //timings
    input   wire            i_CYCLE_05, //ch6 c2 phase piso sr parallel load
    input   wire            i_CYCLE_10,

    //register data
    input   wire    [6:0]   i_KC, //Key Code
    input   wire    [5:0]   i_KF, //Key Fraction
    input   wire    [2:0]   i_PMS, //Pulse Modulation Sensitivity
    input   wire    [1:0]   i_DT2, //Detune 2
    input   wire    [2:0]   i_DT1, //Detune 1
    input   wire    [3:0]   i_MUL,
    input   wire            i_TEST_D3, //test register

    //Vibrato
    input   wire    [7:0]   i_LFP,

    //send signals to other modules
    input   wire            i_PG_PHASE_RST, //phase reset request signal from PG
    output  wire    [4:0]   o_EG_PDELTA_SHIFT_AMOUNT, //send shift amount to EG
    output  wire    [9:0]   o_OP_PHASEDATA, //send phase data to OP
    output  wire            o_REG_PHASE_CH6_C2 //send Ch6, Carrier2 phase data to REG serially

,
    input   wire            i_SS_HOLD,
    input   wire            i_SS_REQ,
    input   wire            i_SS_WRITE,
    input   wire    [7:0]   i_SS_WORD_ADDR,
    input   wire    [31:0]  i_SS_WDATA,
    output  wire    [31:0]  o_SS_VALID_MASK,
    output  wire            o_SS_ACK,
    output  wire            o_SS_ERROR,
    output  wire    [31:0]  o_SS_RDATA
);

// Forward declarations for exact-state instrumentation.
wire ss_local_write_accept;
wire ss_local_accept;
reg ss_local_seen_q;
reg ss_local_ack_q;
reg [31:0] ss_local_rdata_q;
reg [31:0] ss_local_valid_mask;
reg [31:0] ss_local_read_data;
wire [31:0] ss_u_cyc6r_fnumrom_valid_mask;
wire ss_u_cyc6r_fnumrom_ack;
wire ss_u_cyc6r_fnumrom_error;
wire [31:0] ss_u_cyc6r_fnumrom_rdata;
wire [31:0] ss_u_cyc19r_cyc40r_phase_sr_valid_mask;
wire ss_u_cyc19r_cyc40r_phase_sr_ack;
wire ss_u_cyc19r_cyc40r_phase_sr_error;
wire [31:0] ss_u_cyc19r_cyc40r_phase_sr_rdata;




///////////////////////////////////////////////////////////
//////  Clock and reset
////

wire            phi1ncen_n = i_phi1_NCEN_n;
wire            mrst_n = i_MRST_n;



///////////////////////////////////////////////////////////
//////  Cycle 0: PMS decoding, ex-LFP conversion
////

//  DESCRIPTION
//The original chip decodes PMS value in this step(we don't need to do it)
//and does extended LFP conversion with few adders.


//
//  combinational part
//

//ex-lfp conversion
wire    [2:0]   cyc0c_ex_lfp_weight0 = (i_PMS == 3'd7) ? i_LFP[6:4]        : {1'b0, i_LFP[6:5]};
wire    [2:0]   cyc0c_ex_lfp_weight1 = (i_PMS == 3'd7) ? {2'b00, i_LFP[6]} : 3'b000;
wire            cyc0c_ex_lfp_weight2 = (i_PMS == 3'd7) ? ((i_LFP[6] & i_LFP[5]) | (i_LFP[5] & i_LFP[4])) : 
                                       (i_PMS == 3'd6) ? (i_LFP[6] & i_LFP[5]) : 1'b0;
wire    [3:0]   cyc0c_ex_lfp_weightsum = cyc0c_ex_lfp_weight0 + cyc0c_ex_lfp_weight1 + cyc0c_ex_lfp_weight2;


//
//  register part
//

reg     [2:0]   cyc0r_pms_level;
reg     [7:0]   cyc0r_ex_lfp;
reg             cyc0r_ex_lfp_sign;

always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd69: begin
                    cyc0r_pms_level <= i_SS_WDATA[2:0];
                    cyc0r_ex_lfp <= i_SS_WDATA[10:3];
                    cyc0r_ex_lfp_sign <= i_SS_WDATA[11];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc0r_pms_level <= i_PMS;

            if(i_PMS == 3'd7) cyc0r_ex_lfp <= {cyc0c_ex_lfp_weightsum,      i_LFP[3:0]};
            else              cyc0r_ex_lfp <= {cyc0c_ex_lfp_weightsum[2:0], i_LFP[4:0]};

            //lfp_sign becomes 1 when PMS > 0 and LFP sign is negative to convert lfp_ex to 2's complement
            cyc0r_ex_lfp_sign <= (i_PMS > 3'd0) & i_LFP[7];
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 1: Pitch value calculation
////

//  DESCRIPTION
//The original chip decodes PMS value in this step(we don't need to do it)
//and does extended LFP conversion with few adders.


//
//  combinational part
//

reg     [12:0]  cyc1c_lfp_deviance;
always @(*) begin
    case(cyc0r_pms_level)
        3'd0: cyc1c_lfp_deviance = 13'b0;
        3'd1: cyc1c_lfp_deviance = {11'b0, cyc0r_ex_lfp[6:5]      };
        3'd2: cyc1c_lfp_deviance = {10'b0, cyc0r_ex_lfp[6:4]      };
        3'd3: cyc1c_lfp_deviance = {9'b0,  cyc0r_ex_lfp[6:3]      };
        3'd4: cyc1c_lfp_deviance = {8'b0,  cyc0r_ex_lfp[6:2]      };
        3'd5: cyc1c_lfp_deviance = {7'b0,  cyc0r_ex_lfp[6:1]      };
        3'd6: cyc1c_lfp_deviance = {4'b0,  cyc0r_ex_lfp[7:0], 1'b0};
        3'd7: cyc1c_lfp_deviance = {3'b0,  cyc0r_ex_lfp[7:0], 2'b0};
    endcase
end

wire    [6:0]   cyc1c_frac_adder      = i_KF      + (cyc1c_lfp_deviance[5:0]  ^ {6{cyc0r_ex_lfp_sign}}) + cyc0r_ex_lfp_sign; 
wire    [7:0]   cyc1c_int_adder       = i_KC      + (cyc1c_lfp_deviance[12:6] ^ {7{cyc0r_ex_lfp_sign}}) + cyc1c_frac_adder[6];
wire    [2:0]   cyc1c_notegroup_adder = i_KC[1:0] + (cyc1c_lfp_deviance[7:6]  ^ {2{cyc0r_ex_lfp_sign}}) + cyc1c_frac_adder[6];
//wire    [12:0]  cyc1c_modded_raw_pitchval = (cyc0r_ex_lfp_sign == 1'b0) ? {i_KC, i_KF} + cyc1c_lfp_deviance : {i_KC, i_KF} + ~cyc1c_lfp_deviance + 13'd1;


//
//  register part
//

reg     [12:0]  cyc1r_modded_pitchval; //add or subtract LFP value from KC, KF
reg             cyc1r_modded_pitchval_ovfl;
reg             cyc1r_notegroup_nopitchmod; //this flag set when no "LFP" addend is given to a "note group" range(note group: 012/456/89A/CDE)
reg             cyc1r_notegroup_ovfl; //note group overflow, e.g. 6(3'b1_10) + 2(3'b0_10)
reg             cyc1r_lfp_sign;

always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd69: begin
                    cyc1r_modded_pitchval <= i_SS_WDATA[24:12];
                    cyc1r_modded_pitchval_ovfl <= i_SS_WDATA[25];
                    cyc1r_notegroup_nopitchmod <= i_SS_WDATA[26];
                    cyc1r_notegroup_ovfl <= i_SS_WDATA[27];
                    cyc1r_lfp_sign <= i_SS_WDATA[28];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc1r_modded_pitchval      <= {cyc1c_int_adder[6:0], cyc1c_frac_adder[5:0]};

            cyc1r_modded_pitchval_ovfl <= cyc1c_int_adder[7];
            cyc1r_notegroup_nopitchmod <= (cyc1c_lfp_deviance[7:6] ^ {2{cyc0r_ex_lfp_sign}}) == 2'b00;
            cyc1r_notegroup_ovfl <= cyc1c_notegroup_adder[2];

            //bypass
            cyc1r_lfp_sign <= cyc0r_ex_lfp_sign; 
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 2: Notegroup rearrange
////

//  DESCRIPTION
//The pitch value modulated by the LFP value can cause notegroup violation.
//Modify the integer part of this pitch value if it is out of the note group range.
//Notegroup (note group: 012/456/89A/CDE)

//
//  combinational part
//

//wire            cyc2c_int_adder_add1 = ((cyc1r_modded_pitchval[7:6] == 2'd3) | cyc1r_notegroup_ovfl) & ~cyc1r_lfp_sign;
//wire            cyc2c_int_adder_sub1 = ~(cyc1r_notegroup_nopitchmod | cyc1r_notegroup_ovfl | ~cyc1r_lfp_sign);
//wire    [7:0]   cyc2c_int_adder = cyc1r_modded_pitchval[12:6] + {7{cyc2c_int_adder_sub1}} + cyc2c_int_adder_add1;

reg     [7:0]   cyc2c_int_adder;
always @(*) begin
    case({(cyc1r_modded_pitchval[7:6] == 2'd3), cyc1r_notegroup_nopitchmod, cyc1r_notegroup_ovfl, cyc1r_lfp_sign})
        //valid notegroup value
        4'b0_0_0_0: cyc2c_int_adder = cyc1r_modded_pitchval[12:6]        ; //
        4'b0_0_0_1: cyc2c_int_adder = cyc1r_modded_pitchval[12:6] + 7'h7F; //
        4'b0_0_1_0: cyc2c_int_adder = cyc1r_modded_pitchval[12:6] + 7'h01; //
        4'b0_0_1_1: cyc2c_int_adder = cyc1r_modded_pitchval[12:6]        ; //

        4'b0_1_0_0: cyc2c_int_adder = cyc1r_modded_pitchval[12:6]        ; //
        4'b0_1_0_1: cyc2c_int_adder = cyc1r_modded_pitchval[12:6]        ; //
        4'b0_1_1_0: cyc2c_int_adder = cyc1r_modded_pitchval[12:6] + 7'h01; //
        4'b0_1_1_1: cyc2c_int_adder = cyc1r_modded_pitchval[12:6]        ; //

        //invalid notegroup value
        4'b1_0_0_0: cyc2c_int_adder = cyc1r_modded_pitchval[12:6] + 7'h01; //
        4'b1_0_0_1: cyc2c_int_adder = cyc1r_modded_pitchval[12:6] + 7'h7F; //
        4'b1_0_1_0: cyc2c_int_adder = cyc1r_modded_pitchval[12:6] + 7'h01; //
        4'b1_0_1_1: cyc2c_int_adder = cyc1r_modded_pitchval[12:6]        ; //

        4'b1_1_0_0: cyc2c_int_adder = cyc1r_modded_pitchval[12:6] + 7'h01; //
        4'b1_1_0_1: cyc2c_int_adder = cyc1r_modded_pitchval[12:6]        ; //
        4'b1_1_1_0: cyc2c_int_adder = cyc1r_modded_pitchval[12:6] + 7'h01; //
        4'b1_1_1_1: cyc2c_int_adder = cyc1r_modded_pitchval[12:6]        ; //
    endcase
end


//
//  register part
//

reg     [12:0]  cyc2r_rearranged_pitchval;
reg             cyc2r_rearranged_pitchval_ovfl;
reg             cyc2r_modded_pitchval_ovfl;
reg             cyc2r_int_sub1;
reg             cyc2r_lfp_sign;

always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd69: begin
                    cyc2r_rearranged_pitchval[2:0] <= i_SS_WDATA[31:29];
                end
                8'd70: begin
                    cyc2r_rearranged_pitchval[12:3] <= i_SS_WDATA[9:0];
                    cyc2r_rearranged_pitchval_ovfl <= i_SS_WDATA[10];
                    cyc2r_modded_pitchval_ovfl <= i_SS_WDATA[11];
                    cyc2r_int_sub1 <= i_SS_WDATA[12];
                    cyc2r_lfp_sign <= i_SS_WDATA[13];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc2r_rearranged_pitchval <= {cyc2c_int_adder[6:0], cyc1r_modded_pitchval[5:0]};
            cyc2r_rearranged_pitchval_ovfl <= cyc2c_int_adder[7];

            cyc2r_int_sub1 <= ~(cyc1r_notegroup_nopitchmod | cyc1r_notegroup_ovfl | ~cyc1r_lfp_sign);

            cyc2r_modded_pitchval_ovfl <= cyc1r_modded_pitchval_ovfl;
            cyc2r_lfp_sign <= cyc1r_lfp_sign;
        end
    end
end

`ifdef IKAOPM_DEBUG
wire    [13:0]  debug_cyc1c_lfp_deviance = (cyc0r_ex_lfp_sign == 1'b1) ? (~cyc1c_lfp_deviance + 7'h1) : cyc1c_lfp_deviance;
wire            debug_cyc1r_notrgroup_violation = cyc1r_modded_pitchval[7:6] == 2'd3;
wire            debug_cyc2r_notrgroup_violation = cyc2r_rearranged_pitchval[7:6] == 2'd3;
`endif


///////////////////////////////////////////////////////////
//////  Cycle 3: Overflow control
////

//  DESCRIPTION
//Controls the rearranged pitch values to be saturated.

//
//  register part
//

reg     [12:0]  cyc3r_saturated_pitchval;
reg     [1:0]   cyc3r_dt2; //just delays, the original chip decodes DT2 input here, we don't have to do.

always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd70: begin
                    cyc3r_saturated_pitchval <= i_SS_WDATA[26:14];
                    cyc3r_dt2 <= i_SS_WDATA[28:27];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            casez({cyc2r_lfp_sign, cyc2r_modded_pitchval_ovfl, cyc2r_int_sub1, cyc2r_rearranged_pitchval_ovfl})
                //lfp = positive
                4'b0000: cyc3r_saturated_pitchval <= cyc2r_rearranged_pitchval;
                4'b00?1: cyc3r_saturated_pitchval <= 13'b111_1110_111111; //max
                4'b01?0: cyc3r_saturated_pitchval <= 13'b111_1110_111111;
                4'b01?1: cyc3r_saturated_pitchval <= 13'b111_1110_111111;
                4'b0010: cyc3r_saturated_pitchval <= 13'b000_0000_000000; //will never happen

                //lfp = negative
                4'b1000: cyc3r_saturated_pitchval <= 13'b000_0000_000000; //min
                4'b1001: cyc3r_saturated_pitchval <= 13'b000_0000_000000;
                4'b1010: cyc3r_saturated_pitchval <= 13'b000_0000_000000;
                4'b1011: cyc3r_saturated_pitchval <= 13'b000_0000_000000;
                4'b1100: cyc3r_saturated_pitchval <= cyc2r_rearranged_pitchval;
                4'b1101: cyc3r_saturated_pitchval <= cyc2r_rearranged_pitchval;
                4'b1110: cyc3r_saturated_pitchval <= 13'b000_0000_000000;
                4'b1111: cyc3r_saturated_pitchval <= cyc2r_rearranged_pitchval;
            endcase

            cyc3r_dt2 <= i_DT2;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 4: apply DT2 to fractional part
////

//  DESCRIPTION
//Apply DT2 to fractional part of the pitch value
//fixed point, fractional part is 6 bits. 0.015625 step value

//
//  register part
//

reg     [6:0]   cyc4r_frac_detuned_pitchval; //carry + 6bit value
reg     [6:0]   cyc4r_int_pitchval;
reg     [1:0]   cyc4r_dt2;

always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd70: begin
                    cyc4r_frac_detuned_pitchval[2:0] <= i_SS_WDATA[31:29];
                end
                8'd71: begin
                    cyc4r_frac_detuned_pitchval[6:3] <= i_SS_WDATA[3:0];
                    cyc4r_int_pitchval <= i_SS_WDATA[10:4];
                    cyc4r_dt2 <= i_SS_WDATA[12:11];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            case(cyc3r_dt2)
                2'd0: cyc4r_frac_detuned_pitchval <= cyc3r_saturated_pitchval[5:0] + 6'd0  + 1'd0;
                2'd1: cyc4r_frac_detuned_pitchval <= cyc3r_saturated_pitchval[5:0] + 6'd0  + 1'd0;
                2'd2: cyc4r_frac_detuned_pitchval <= cyc3r_saturated_pitchval[5:0] + 6'd52 + 1'd0; //fractional part +0.8125
                2'd3: cyc4r_frac_detuned_pitchval <= cyc3r_saturated_pitchval[5:0] + 6'd32 + 1'd0; //fractional part +0.5
            endcase

            cyc4r_int_pitchval <= cyc3r_saturated_pitchval[12:6];

            cyc4r_dt2 <= cyc3r_dt2;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 5: apply DT2 to integer part
////

//  DESCRIPTION
//Apply DT2 to integer part of the pitch value

//
//  register part
//

reg     [5:0]   cyc5r_frac_detuned_pitchval; //no carry here
reg     [7:0]   cyc5r_int_detuned_pitchval; //carry + 7bit value

always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd71: begin
                    cyc5r_frac_detuned_pitchval <= i_SS_WDATA[18:13];
                    cyc5r_int_detuned_pitchval <= i_SS_WDATA[26:19];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            casez({cyc4r_dt2, cyc4r_frac_detuned_pitchval[6], cyc4r_int_pitchval[1:0]})
                //dt2 = 0
                5'b00_0_00: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd0;
                5'b00_0_01: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd0;
                5'b00_0_10: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd0;
                5'b00_0_11: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd0;
                5'b00_1_00: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd0 + 7'd1;
                5'b00_1_01: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd0 + 7'd1;
                5'b00_1_10: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd0 + 7'd2;
                5'b00_1_11: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd0 + 7'd2;
                //                                        |---base value---| +  dt2 + carry(avoids notegroup violation)

                //dt2 = 1
                5'b01_0_00: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd8;
                5'b01_0_01: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd8;
                5'b01_0_10: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd8;
                5'b01_0_11: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd8;
                5'b01_1_00: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd8 + 7'd1;
                5'b01_1_01: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd8 + 7'd1;
                5'b01_1_10: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd8 + 7'd2;
                5'b01_1_11: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd8 + 7'd2;

                //dt2 = 2
                5'b10_0_00: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd9;
                5'b10_0_01: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd9;
                5'b10_0_10: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd9 + 7'd1;
                5'b10_0_11: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd9 + 7'd1;
                5'b10_1_00: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd9 + 7'd1;
                5'b10_1_01: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd9 + 7'd2;
                5'b10_1_10: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd9 + 7'd2;
                5'b10_1_11: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd9 + 7'd2;

                //dt2 = 3
                5'b11_0_00: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd12;
                5'b11_0_01: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd12;
                5'b11_0_10: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd12;
                5'b11_0_11: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd12;
                5'b11_1_00: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd12 + 7'd1;
                5'b11_1_01: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd12 + 7'd1;
                5'b11_1_10: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd12 + 7'd2;
                5'b11_1_11: cyc5r_int_detuned_pitchval <= cyc4r_int_pitchval + 7'd12 + 7'd2;
            endcase

            cyc5r_frac_detuned_pitchval <= cyc4r_frac_detuned_pitchval[5:0]; //discard carry
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 6: Overflow control, Keycode to F-num 1
////


//  DESCRIPTION
//Controls the final pitch values to be saturated.

//
//  combinational part
//

wire   [12:0]  cyc6c_final_pitchval = (cyc5r_int_detuned_pitchval[7] == 1'b1) ? 13'b111_1110_111111 : {cyc5r_int_detuned_pitchval[6:0], cyc5r_frac_detuned_pitchval};

//  DESCRIPTION
//This ROM has absolute phase increment value(pdelta) and 
//fine tuning value for small phase changes. Now we get the values
//from the conversion table.

//
//  register part
//

reg     [4:0]   cyc6r_pdelta_shift_amount;
wire    [11:0]  cyc6r_pdelta_base;
wire    [3:0]   cyc6r_pdelta_increment_multiplicand;
reg     [3:0]   cyc6r_pdelta_increment_multiplier;
wire            cyc6r_pdelta_calcmode;

cavebanpresto_ikaopm_ss_fnumrom #(.SS_BASE_BIT(13'd2751)) u_cyc6r_fnumrom (
    .i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_ADDR(cyc6c_final_pitchval[9:4]),
    .o_DATA({cyc6r_pdelta_base, cyc6r_pdelta_increment_multiplicand[0], cyc6r_pdelta_increment_multiplicand[3:1], cyc6r_pdelta_calcmode})
    //The original chip's output bit order is scrambled!

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_cyc6r_fnumrom_valid_mask),
    .o_SS_ACK        (ss_u_cyc6r_fnumrom_ack),
    .o_SS_ERROR      (ss_u_cyc6r_fnumrom_error),
    .o_SS_RDATA      (ss_u_cyc6r_fnumrom_rdata)
);

always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd71: begin
                    cyc6r_pdelta_shift_amount <= i_SS_WDATA[31:27];
                end
                8'd72: begin
                    cyc6r_pdelta_increment_multiplier <= i_SS_WDATA[3:0];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc6r_pdelta_shift_amount <= cyc6c_final_pitchval[12:8];
            cyc6r_pdelta_increment_multiplier <= cyc6c_final_pitchval[3:0];
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 7: Keycode to F-num 2
////

//  DESCRIPTION
//Now we have to generate the value to adjust the pdelta base value.
//YM2151 decompresses the ROM output we got in the previous step.
//
//in calcmode == 0, we can write the weird expression like this:
//if(multiply[3:2] == 2'b11) and (increment[0] == 1'b0), then +4
//if(multiply[3] == 1'b1), then +1
//if(multiply[1] == 1'b1), then +8
//if(multuply[0] == 1'b1), then +2

//
//  register part
//

reg     [4:0]   cyc7r_pdelta_shift_amount;
reg     [11:0]  cyc7r_pdelta_base;
reg     [6:0]   cyc7r_multiplied_increment;
assign  o_EG_PDELTA_SHIFT_AMOUNT = cyc7r_pdelta_shift_amount;

always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd72: begin
                    cyc7r_pdelta_shift_amount <= i_SS_WDATA[8:4];
                    cyc7r_pdelta_base <= i_SS_WDATA[20:9];
                    cyc7r_multiplied_increment <= i_SS_WDATA[27:21];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc7r_pdelta_shift_amount <= cyc6r_pdelta_shift_amount;
            cyc7r_pdelta_base <= cyc6r_pdelta_base;

            if(cyc6r_pdelta_calcmode) begin
                cyc7r_multiplied_increment <= ({{1'b1, cyc6r_pdelta_increment_multiplicand} >> 0} & {5{cyc6r_pdelta_increment_multiplier[3]}}) +
                                                ({{1'b1, cyc6r_pdelta_increment_multiplicand} >> 1} & {5{cyc6r_pdelta_increment_multiplier[2]}}) +
                                                ({{1'b1, cyc6r_pdelta_increment_multiplicand} >> 2} & {5{cyc6r_pdelta_increment_multiplier[1]}}) +
                                                ({{1'b1, cyc6r_pdelta_increment_multiplicand} >> 3} & {5{cyc6r_pdelta_increment_multiplier[0]}});
            end
            else begin
                cyc7r_multiplied_increment <= ({{1'b1, cyc6r_pdelta_increment_multiplicand[3:1], 1'b1} >> 0} & {5{cyc6r_pdelta_increment_multiplier[3]}}) +
                                                ({{1'b1, cyc6r_pdelta_increment_multiplicand[3:1], 1'b1} >> 1} & {5{cyc6r_pdelta_increment_multiplier[2]}}) +
                                                ({{1'b1, cyc6r_pdelta_increment_multiplicand[3:1], 1'b1} >> 3} & {5{cyc6r_pdelta_increment_multiplier[0]}}) +

                                                (5'd4 & {5{&{cyc6r_pdelta_increment_multiplier[3:2], ~cyc6r_pdelta_increment_multiplicand[0]}}}) + 
                                                (5'd1 & {5{cyc6r_pdelta_increment_multiplier[3]}}) + 
                                                (5'd8 & {5{cyc6r_pdelta_increment_multiplier[1]}}) + 
                                                (5'd2 & {5{cyc6r_pdelta_increment_multiplier[0]}});
            end
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 8: Keycode to F-num 3, DT1/MUL latch
////

//  DESCRIPTION
//This is the third step of F-num conversion.
//Discard the LSB of "cyc7r_multiplied_increment" first.
//Add them to the base next.

//
//  register part
//

reg     [4:0]   cyc8r_pdelta_shift_amount;
reg     [11:0]  cyc8r_pdelta_base;
reg     [2:0]   cyc8r_dt1;
reg     [3:0]   cyc8r_mul;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd72: begin
                    cyc8r_pdelta_shift_amount[3:0] <= i_SS_WDATA[31:28];
                end
                8'd73: begin
                    cyc8r_pdelta_shift_amount[4] <= i_SS_WDATA[0];
                    cyc8r_pdelta_base <= i_SS_WDATA[12:1];
                    cyc8r_dt1 <= i_SS_WDATA[15:13];
                    cyc8r_mul <= i_SS_WDATA[19:16];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc8r_pdelta_shift_amount <= cyc7r_pdelta_shift_amount;
            cyc8r_pdelta_base <= cyc7r_pdelta_base + {6'b0, cyc7r_multiplied_increment[6:1]};
            cyc8r_dt1 <= i_DT1;
            cyc8r_mul <= i_MUL;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 9: Keycode to F-num 4, DT1 decode
////

//  DESCRIPTION
//This is the last step of F-num conversion. Shift the pdelta
//value using the shift amount[4:3].
//Calculate the intensity of detuning amount. Decode the base
//detuning value from DT1 parameter.

//
//  combinational part
//

//intensity shifts the base value
reg     [4:0]   cyc9c_dt1_intensity; //possible intensity value: from 1 to 19
always @(*) begin
    case(cyc8r_dt1[1:0])
        2'd0: cyc9c_dt1_intensity = {1'b0, cyc8r_pdelta_shift_amount[4:2]} + 4'd0  + 1'd1; //always +1, confirmed 2023-07-06
        2'd1: cyc9c_dt1_intensity = {1'b0, cyc8r_pdelta_shift_amount[4:2]} + 4'd8  + 1'd1;
        2'd2: cyc9c_dt1_intensity = {1'b0, cyc8r_pdelta_shift_amount[4:2]} + 4'd10 + 1'd1;
        2'd3: cyc9c_dt1_intensity = {1'b0, cyc8r_pdelta_shift_amount[4:2]} + 4'd11 + 1'd1;
    endcase
end

//generate the base value(PLA), confirmed 2023-07-06
wire    [1:0]   cyc9c_dt1_base_sel = (cyc8r_pdelta_shift_amount >= 5'd28) ? 2'd0 : cyc8r_pdelta_shift_amount[1:0]; //confirmed 2023-07-06
reg     [4:0]   cyc9c_dt1_base;
always @(*) begin
    case({cyc9c_dt1_intensity[0], cyc9c_dt1_base_sel})
        //dt1 intensity is even
        3'b0_00: cyc9c_dt1_base = 5'b10000; //1, 0
        3'b0_01: cyc9c_dt1_base = 5'b10001; //1, 1
        3'b0_10: cyc9c_dt1_base = 5'b10011; //1, 3
        3'b0_11: cyc9c_dt1_base = 5'b10100; //1, 4

        //dt1 intensity is odd
        3'b1_00: cyc9c_dt1_base = 5'b10110; //1, 6
        3'b1_01: cyc9c_dt1_base = 5'b11000; //1, 8
        3'b1_10: cyc9c_dt1_base = 5'b11011; //1, 11
        3'b1_11: cyc9c_dt1_base = 5'b11101; //1, 13
    endcase
end

//
//  register part
//

wire    [19:0]  cyc40r_phase_sr_out; //get previous phase from the cycle 40, SR last step(21)
reg     [19:0]  cyc9r_previous_phase;
reg     [16:0]  cyc9r_shifted_pdelta;
reg     [16:0]  cyc9r_pdelta_detuning_value;
reg     [3:0]   cyc9r_mul;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd73: begin
                    cyc9r_previous_phase[11:0] <= i_SS_WDATA[31:20];
                end
                8'd74: begin
                    cyc9r_previous_phase[19:12] <= i_SS_WDATA[7:0];
                    cyc9r_shifted_pdelta <= i_SS_WDATA[24:8];
                    cyc9r_pdelta_detuning_value[6:0] <= i_SS_WDATA[31:25];
                end
                8'd75: begin
                    cyc9r_pdelta_detuning_value[16:7] <= i_SS_WDATA[9:0];
                    cyc9r_mul <= i_SS_WDATA[13:10];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            case(cyc8r_pdelta_shift_amount[4:2])
                3'd0: cyc9r_shifted_pdelta <= {7'b0000000, cyc8r_pdelta_base[11:2]}; //>>4
                3'd1: cyc9r_shifted_pdelta <= {6'b000000, cyc8r_pdelta_base[11:1] }; //>>3
                3'd2: cyc9r_shifted_pdelta <= {5'b00000, cyc8r_pdelta_base        }; //>>2
                3'd3: cyc9r_shifted_pdelta <= {4'b0000, cyc8r_pdelta_base, 1'b0   }; //>>1
                3'd4: cyc9r_shifted_pdelta <= {3'b000, cyc8r_pdelta_base, 2'b00   }; //zero
                3'd5: cyc9r_shifted_pdelta <= {2'b00, cyc8r_pdelta_base, 3'b000   }; //<<1
                3'd6: cyc9r_shifted_pdelta <= {1'b0, cyc8r_pdelta_base, 4'b0000   }; //<<2
                3'd7: cyc9r_shifted_pdelta <= {     cyc8r_pdelta_base, 5'b00000   }; //<<3
            endcase

            case(cyc9c_dt1_intensity[4:1])
                //                                                      DT1 is ? |-------- positive --------|   |------------- negative -----------|  intensity
                4'b0101: cyc9r_pdelta_detuning_value <= (cyc8r_dt1[2] == 1'b0) ? {16'd0, cyc9c_dt1_base[4]}   : ~{16'd0, cyc9c_dt1_base[4]}   + 1'd1; //10, 11
                4'b0110: cyc9r_pdelta_detuning_value <= (cyc8r_dt1[2] == 1'b0) ? {15'd0, cyc9c_dt1_base[4:3]} : ~{15'd0, cyc9c_dt1_base[4:3]} + 1'd1; //12, 13
                4'b0111: cyc9r_pdelta_detuning_value <= (cyc8r_dt1[2] == 1'b0) ? {14'd0, cyc9c_dt1_base[4:2]} : ~{14'd0, cyc9c_dt1_base[4:2]} + 1'd1; //14, 15
                4'b1000: cyc9r_pdelta_detuning_value <= (cyc8r_dt1[2] == 1'b0) ? {13'd0, cyc9c_dt1_base[4:1]} : ~{13'd0, cyc9c_dt1_base[4:1]} + 1'd1; //16, 17
                4'b1001: cyc9r_pdelta_detuning_value <= (cyc8r_dt1[2] == 1'b0) ? {12'd0, cyc9c_dt1_base}      : ~{12'd0, cyc9c_dt1_base}      + 1'd1; //18, 19

                default: cyc9r_pdelta_detuning_value <= 17'd0;                                                                                    //1 to 9
            endcase

            cyc9r_mul <= cyc8r_mul;
            cyc9r_previous_phase <= mrst_n ? cyc40r_phase_sr_out : 20'd0; //force reset added
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 10: apply DT1
////

//  DESCRIPTION
//Sum shifted pdelta and detuning value.
//YM2151 adds low bits in this step, but we don't have to do it. 
//Add everything within one cycle.

//
//  register part
//

reg     [19:0]  cyc10r_previous_phase;
reg     [16:0]  cyc10r_detuned_pdelta; //ignore carry
reg     [3:0]   cyc10r_mul;
reg             cyc10r_phase_rst;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd75: begin
                    cyc10r_previous_phase[17:0] <= i_SS_WDATA[31:14];
                end
                8'd76: begin
                    cyc10r_previous_phase[19:18] <= i_SS_WDATA[1:0];
                    cyc10r_detuned_pdelta <= i_SS_WDATA[18:2];
                    cyc10r_mul <= i_SS_WDATA[22:19];
                    cyc10r_phase_rst <= i_SS_WDATA[23];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc10r_detuned_pdelta <= cyc9r_shifted_pdelta + cyc9r_pdelta_detuning_value;
            cyc10r_mul <= cyc9r_mul;
            cyc10r_previous_phase <= cyc9r_previous_phase;
            cyc10r_phase_rst <= i_PG_PHASE_RST;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 11: delay
////

//  DESCRIPTION
//YM2151 adds high bits in this step.
//Just latch multiplier. The original chip decodes mul value
//here to feed some control signal for booth multiplier.

//
//  register part
//

reg     [19:0]  cyc11r_previous_phase;
reg     [16:0]  cyc11r_detuned_pdelta;
reg     [3:0]   cyc11r_mul;
reg             cyc11r_phase_rst;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd76: begin
                    cyc11r_previous_phase[7:0] <= i_SS_WDATA[31:24];
                end
                8'd77: begin
                    cyc11r_previous_phase[19:8] <= i_SS_WDATA[11:0];
                    cyc11r_detuned_pdelta <= i_SS_WDATA[28:12];
                    cyc11r_mul[2:0] <= i_SS_WDATA[31:29];
                end
                8'd78: begin
                    cyc11r_mul[3] <= i_SS_WDATA[0];
                    cyc11r_phase_rst <= i_SS_WDATA[1];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc11r_detuned_pdelta <= cyc10r_detuned_pdelta;
            cyc11r_mul <= cyc10r_mul;
            cyc11r_previous_phase <= cyc10r_previous_phase;
            cyc11r_phase_rst <= cyc10r_phase_rst;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 12: apply mul
////

//
//  register part
//

reg     [19:0]  cyc12r_previous_phase;
reg     [19:0]  cyc12r_multiplied_pdelta; //131071*15 = 1_1101_1111_1111_1111_0001, max 21 bits, but discard MSB anyway
reg             cyc12r_phase_rst;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd78: begin
                    cyc12r_previous_phase <= i_SS_WDATA[21:2];
                    cyc12r_multiplied_pdelta[9:0] <= i_SS_WDATA[31:22];
                end
                8'd79: begin
                    cyc12r_multiplied_pdelta[19:10] <= i_SS_WDATA[9:0];
                    cyc12r_phase_rst <= i_SS_WDATA[10];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            if(cyc11r_mul == 4'b0) cyc12r_multiplied_pdelta <= {4'b0000, cyc11r_detuned_pdelta[16:1]}; // divide by 2
            else begin
                cyc12r_multiplied_pdelta <= cyc11r_detuned_pdelta * cyc11r_mul;
            end

            cyc12r_previous_phase <= cyc11r_previous_phase;
            cyc12r_phase_rst <= cyc11r_phase_rst;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 13: delay
////

//
//  register part
//

reg     [19:0]  cyc13r_previous_phase;
reg     [19:0]  cyc13r_multiplied_pdelta; //ignore carry
reg             cyc13r_phase_rst;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd79: begin
                    cyc13r_previous_phase <= i_SS_WDATA[30:11];
                    cyc13r_multiplied_pdelta[0] <= i_SS_WDATA[31];
                end
                8'd80: begin
                    cyc13r_multiplied_pdelta[19:1] <= i_SS_WDATA[18:0];
                    cyc13r_phase_rst <= i_SS_WDATA[19];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc13r_multiplied_pdelta <= cyc12r_multiplied_pdelta[19:0];
            cyc13r_previous_phase <= cyc12r_previous_phase;
            cyc13r_phase_rst <= cyc12r_phase_rst;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 14: reset phase
////

//
//  register part
//

reg     [19:0]  cyc14r_previous_phase;
reg     [19:0]  cyc14r_final_pdelta; 
reg             cyc14r_phase_rst;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd80: begin
                    cyc14r_previous_phase[11:0] <= i_SS_WDATA[31:20];
                end
                8'd81: begin
                    cyc14r_previous_phase[19:12] <= i_SS_WDATA[7:0];
                    cyc14r_final_pdelta <= i_SS_WDATA[27:8];
                    cyc14r_phase_rst <= i_SS_WDATA[28];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc14r_final_pdelta <= (cyc13r_phase_rst) ? 20'd0 : cyc13r_multiplied_pdelta;
            cyc14r_previous_phase <= cyc13r_previous_phase;
            cyc14r_phase_rst <= cyc13r_phase_rst;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 15: delay
////

//
//  register part
//

reg     [19:0]  cyc15r_previous_phase;
reg     [19:0]  cyc15r_final_pdelta; 
reg             cyc15r_phase_rst;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd81: begin
                    cyc15r_previous_phase[2:0] <= i_SS_WDATA[31:29];
                end
                8'd82: begin
                    cyc15r_previous_phase[19:3] <= i_SS_WDATA[16:0];
                    cyc15r_final_pdelta[14:0] <= i_SS_WDATA[31:17];
                end
                8'd83: begin
                    cyc15r_final_pdelta[19:15] <= i_SS_WDATA[4:0];
                    cyc15r_phase_rst <= i_SS_WDATA[5];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc15r_final_pdelta <= cyc14r_final_pdelta;
            cyc15r_previous_phase <= cyc14r_previous_phase;
            cyc15r_phase_rst <= cyc14r_phase_rst;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 16: delay, reset previous phase
////

//
//  register part
//

reg     [19:0]  cyc16r_final_pdelta; 
reg     [19:0]  cyc16r_previous_phase;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd83: begin
                    cyc16r_final_pdelta <= i_SS_WDATA[25:6];
                    cyc16r_previous_phase[5:0] <= i_SS_WDATA[31:26];
                end
                8'd84: begin
                    cyc16r_previous_phase[19:6] <= i_SS_WDATA[13:0];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc16r_final_pdelta <= cyc15r_final_pdelta;
            cyc16r_previous_phase <= (cyc15r_phase_rst | i_TEST_D3) ? 20'd0 : cyc15r_previous_phase;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 17: sum previous phase and pdelta
////

//  DESCRIPTION
//YM2151 adds low bits in this step. We will sum entire bits.

//
//  register part
//

reg     [19:0]  cyc17r_current_phase; //ignore carry
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd84: begin
                    cyc17r_current_phase[17:0] <= i_SS_WDATA[31:14];
                end
                8'd85: begin
                    cyc17r_current_phase[19:18] <= i_SS_WDATA[1:0];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc17r_current_phase <= cyc16r_previous_phase + cyc16r_final_pdelta;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 18: delay 
////

//  DESCRIPTION
//YM2151 adds high bits in this step.

//
//  register part
//

reg     [19:0]  cyc18r_current_phase;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd85: begin
                    cyc18r_current_phase <= i_SS_WDATA[21:2];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc18r_current_phase <= mrst_n ? cyc17r_current_phase : 20'd0; //force reset added
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 19-40: delay shift register 
////

//  DESCRIPTION
//10-bit processing chain above and 22-bit length shift register 
//will store all 32 phases.

//
//  register part
//

generate
if(USE_BRAM_FOR_PHASEREG == 0) begin: phasesr_mode_sr
    cavebanpresto_ikaopm_ss_sr #(.WIDTH(20), .LENGTH(22), .TAP(22)) u_cyc19r_cyc40r_phase_sr
    (.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_D(cyc18r_current_phase), .o_Q_TAP(), .o_Q_LAST(cyc40r_phase_sr_out));
end
else begin: phasesr_mode_bram
    cavebanpresto_ikaopm_ss_sr_bram #(.SS_MEM_BASE_BIT(13'd2784), .SS_META_BASE_BIT(13'd3424), .WIDTH(20), .LENGTH(32), .TAP(22)) u_cyc19r_cyc40r_phase_sr
    (.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_CNTRRST(i_CYCLE_10 | ~mrst_n), .i_WR(1'b1), .i_D(cyc18r_current_phase), .o_Q_TAP(cyc40r_phase_sr_out)
,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_cyc19r_cyc40r_phase_sr_valid_mask),
    .o_SS_ACK        (ss_u_cyc19r_cyc40r_phase_sr_ack),
    .o_SS_ERROR      (ss_u_cyc19r_cyc40r_phase_sr_error),
    .o_SS_RDATA      (ss_u_cyc19r_cyc40r_phase_sr_rdata)
);
end
endgenerate

//last stage
assign  o_OP_PHASEDATA = cyc40r_phase_sr_out[19:10];



///////////////////////////////////////////////////////////
//////  Phase serialization(send to test reg)
////

reg     [8:0]   phase_ch6_c2;
assign  o_REG_PHASE_CH6_C2 = phase_ch6_c2[0];
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd85: begin
                    phase_ch6_c2 <= i_SS_WDATA[30:22];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            if(i_CYCLE_05) phase_ch6_c2 <= cyc15r_previous_phase[8:0];
            else begin 
                phase_ch6_c2[7:0] <= phase_ch6_c2[8:1];
                phase_ch6_c2[8] <= 1'b0;
            end
        end
    end
end



///////////////////////////////////////////////////////////
//////  STATIC STORAGE FOR DEBUG
////

`ifdef IKAOPM_DEBUG

reg     [4:0]   sim_pg_static_storage_addr_cntr = 5'd0;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        // Held: no emulation state advances.
    end else begin
        if(!phi1ncen_n) begin
            if(i_CYCLE_10) sim_pg_static_storage_addr_cntr <= 5'd0;
            else sim_pg_static_storage_addr_cntr <= sim_pg_static_storage_addr_cntr == 5'd31 ? 5'd0 : sim_pg_static_storage_addr_cntr + 5'd1;
        end
    end
end

reg     [19:0]  sim_pg_static_storage[0:31];
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        // Held: no emulation state advances.
    end else begin
        if(!phi1ncen_n) begin
            sim_pg_static_storage[sim_pg_static_storage_addr_cntr] <= mrst_n ? cyc18r_current_phase : 20'd0;
        end
    end
end

`endif


// CaveBanpresto exact-state word instrumentation.

always @(*) begin
    ss_local_valid_mask = 32'd0;
    ss_local_read_data = 32'd0;
    case (i_SS_WORD_ADDR)
        8'd69: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[2:0] = cyc0r_pms_level;
            ss_local_read_data[10:3] = cyc0r_ex_lfp;
            ss_local_read_data[11] = cyc0r_ex_lfp_sign;
            ss_local_read_data[24:12] = cyc1r_modded_pitchval;
            ss_local_read_data[25] = cyc1r_modded_pitchval_ovfl;
            ss_local_read_data[26] = cyc1r_notegroup_nopitchmod;
            ss_local_read_data[27] = cyc1r_notegroup_ovfl;
            ss_local_read_data[28] = cyc1r_lfp_sign;
            ss_local_read_data[31:29] = cyc2r_rearranged_pitchval[2:0];
        end
        8'd70: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[9:0] = cyc2r_rearranged_pitchval[12:3];
            ss_local_read_data[10] = cyc2r_rearranged_pitchval_ovfl;
            ss_local_read_data[11] = cyc2r_modded_pitchval_ovfl;
            ss_local_read_data[12] = cyc2r_int_sub1;
            ss_local_read_data[13] = cyc2r_lfp_sign;
            ss_local_read_data[26:14] = cyc3r_saturated_pitchval;
            ss_local_read_data[28:27] = cyc3r_dt2;
            ss_local_read_data[31:29] = cyc4r_frac_detuned_pitchval[2:0];
        end
        8'd71: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[3:0] = cyc4r_frac_detuned_pitchval[6:3];
            ss_local_read_data[10:4] = cyc4r_int_pitchval;
            ss_local_read_data[12:11] = cyc4r_dt2;
            ss_local_read_data[18:13] = cyc5r_frac_detuned_pitchval;
            ss_local_read_data[26:19] = cyc5r_int_detuned_pitchval;
            ss_local_read_data[31:27] = cyc6r_pdelta_shift_amount;
        end
        8'd72: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[3:0] = cyc6r_pdelta_increment_multiplier;
            ss_local_read_data[8:4] = cyc7r_pdelta_shift_amount;
            ss_local_read_data[20:9] = cyc7r_pdelta_base;
            ss_local_read_data[27:21] = cyc7r_multiplied_increment;
            ss_local_read_data[31:28] = cyc8r_pdelta_shift_amount[3:0];
        end
        8'd73: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[0] = cyc8r_pdelta_shift_amount[4];
            ss_local_read_data[12:1] = cyc8r_pdelta_base;
            ss_local_read_data[15:13] = cyc8r_dt1;
            ss_local_read_data[19:16] = cyc8r_mul;
            ss_local_read_data[31:20] = cyc9r_previous_phase[11:0];
        end
        8'd74: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[7:0] = cyc9r_previous_phase[19:12];
            ss_local_read_data[24:8] = cyc9r_shifted_pdelta;
            ss_local_read_data[31:25] = cyc9r_pdelta_detuning_value[6:0];
        end
        8'd75: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[9:0] = cyc9r_pdelta_detuning_value[16:7];
            ss_local_read_data[13:10] = cyc9r_mul;
            ss_local_read_data[31:14] = cyc10r_previous_phase[17:0];
        end
        8'd76: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[1:0] = cyc10r_previous_phase[19:18];
            ss_local_read_data[18:2] = cyc10r_detuned_pdelta;
            ss_local_read_data[22:19] = cyc10r_mul;
            ss_local_read_data[23] = cyc10r_phase_rst;
            ss_local_read_data[31:24] = cyc11r_previous_phase[7:0];
        end
        8'd77: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[11:0] = cyc11r_previous_phase[19:8];
            ss_local_read_data[28:12] = cyc11r_detuned_pdelta;
            ss_local_read_data[31:29] = cyc11r_mul[2:0];
        end
        8'd78: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[0] = cyc11r_mul[3];
            ss_local_read_data[1] = cyc11r_phase_rst;
            ss_local_read_data[21:2] = cyc12r_previous_phase;
            ss_local_read_data[31:22] = cyc12r_multiplied_pdelta[9:0];
        end
        8'd79: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[9:0] = cyc12r_multiplied_pdelta[19:10];
            ss_local_read_data[10] = cyc12r_phase_rst;
            ss_local_read_data[30:11] = cyc13r_previous_phase;
            ss_local_read_data[31] = cyc13r_multiplied_pdelta[0];
        end
        8'd80: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[18:0] = cyc13r_multiplied_pdelta[19:1];
            ss_local_read_data[19] = cyc13r_phase_rst;
            ss_local_read_data[31:20] = cyc14r_previous_phase[11:0];
        end
        8'd81: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[7:0] = cyc14r_previous_phase[19:12];
            ss_local_read_data[27:8] = cyc14r_final_pdelta;
            ss_local_read_data[28] = cyc14r_phase_rst;
            ss_local_read_data[31:29] = cyc15r_previous_phase[2:0];
        end
        8'd82: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[16:0] = cyc15r_previous_phase[19:3];
            ss_local_read_data[31:17] = cyc15r_final_pdelta[14:0];
        end
        8'd83: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[4:0] = cyc15r_final_pdelta[19:15];
            ss_local_read_data[5] = cyc15r_phase_rst;
            ss_local_read_data[25:6] = cyc16r_final_pdelta;
            ss_local_read_data[31:26] = cyc16r_previous_phase[5:0];
        end
        8'd84: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[13:0] = cyc16r_previous_phase[19:6];
            ss_local_read_data[31:14] = cyc17r_current_phase[17:0];
        end
        8'd85: begin
            ss_local_valid_mask = 32'h7fffffff;
            ss_local_read_data[1:0] = cyc17r_current_phase[19:18];
            ss_local_read_data[21:2] = cyc18r_current_phase;
            ss_local_read_data[30:22] = phase_ch6_c2;
        end
        default: ;
    endcase
end

assign ss_local_accept =
    i_SS_HOLD && i_SS_REQ && (|ss_local_valid_mask) && !ss_local_seen_q;
assign ss_local_write_accept = ss_local_accept && i_SS_WRITE;

always @(posedge i_EMUCLK) begin
    if (!i_SS_HOLD) begin
        ss_local_seen_q <= 1'b0;
        ss_local_ack_q <= 1'b0;
        ss_local_rdata_q <= 32'd0;
    end else begin
        ss_local_ack_q <= 1'b0;
        if (!i_SS_REQ)
            ss_local_seen_q <= 1'b0;
        if (ss_local_accept) begin
            ss_local_seen_q <= 1'b1;
            ss_local_ack_q <= 1'b1;
            ss_local_rdata_q <= ss_local_read_data;
        end
    end
end

assign o_SS_VALID_MASK = ss_local_valid_mask | ss_u_cyc6r_fnumrom_valid_mask | ss_u_cyc19r_cyc40r_phase_sr_valid_mask;
assign o_SS_ACK = ss_local_ack_q | ss_u_cyc6r_fnumrom_ack | ss_u_cyc19r_cyc40r_phase_sr_ack;
assign o_SS_ERROR = 1'b0 | ss_u_cyc6r_fnumrom_error | ss_u_cyc19r_cyc40r_phase_sr_error;
assign o_SS_RDATA = (ss_local_rdata_q & ss_local_valid_mask) | (ss_u_cyc6r_fnumrom_rdata & ss_u_cyc6r_fnumrom_valid_mask) | (ss_u_cyc19r_cyc40r_phase_sr_rdata & ss_u_cyc19r_cyc40r_phase_sr_valid_mask);



endmodule

module cavebanpresto_ikaopm_ss_eg #(parameter integer SS_BASE_BIT = 3456) (
    //master clock
    input   wire            i_EMUCLK, //emulator master clock

    //core internal reset
    input   wire            i_MRST_n,

    //internal clock
    input   wire            i_phi1_PCEN_n, //positive edge clock enable for emulation
    input   wire            i_phi1_NCEN_n, //negative edge clock enable for emulation

    //timings
    input   wire            i_CYCLE_03,
    input   wire            i_CYCLE_31,
    input   wire            i_CYCLE_00_16,
    input   wire            i_CYCLE_01_TO_16,

    //register data
    input   wire            i_KON, //key on
    input   wire    [1:0]   i_KS,  //key scale
    input   wire    [4:0]   i_AR,  //attack rate
    input   wire    [4:0]   i_D1R, //first decay rate
    input   wire    [4:0]   i_D2R, //second decay rate
    input   wire    [3:0]   i_RR,  //release rate
    input   wire    [3:0]   i_D1L, //first decay level
    input   wire    [6:0]   i_TL,  //total level
    input   wire    [1:0]   i_AMS, //amplitude modulation sensitivity
    input   wire    [7:0]   i_LFA, //amplitude modulation from LFO
    input   wire            i_TEST_D0, //test register
    input   wire            i_TEST_D5,

    //input data
    input   wire    [4:0]   i_EG_PDELTA_SHIFT_AMOUNT,

    //output data
    output  wire            o_PG_PHASE_RST,
    output  wire    [9:0]   o_OP_ATTENLEVEL, //envelope level
    output  wire            o_NOISE_ATTENLEVEL, //envelope level(for noise module)
    output  wire            o_REG_ATTENLEVEL_CH8_C2 //noise envelope level

,
    input   wire            i_SS_HOLD,
    input   wire            i_SS_REQ,
    input   wire            i_SS_WRITE,
    input   wire    [7:0]   i_SS_WORD_ADDR,
    input   wire    [31:0]  i_SS_WDATA,
    output  wire    [31:0]  o_SS_VALID_MASK,
    output  wire            o_SS_ACK,
    output  wire            o_SS_ERROR,
    output  wire    [31:0]  o_SS_RDATA
);

// Forward declarations for exact-state instrumentation.
wire ss_local_write_accept;
wire ss_local_accept;
reg ss_local_seen_q;
reg ss_local_ack_q;
reg [31:0] ss_local_rdata_q;
reg [31:0] ss_local_valid_mask;
reg [31:0] ss_local_read_data;
wire [31:0] ss_u_samplecntr_valid_mask;
wire ss_u_samplecntr_ack;
wire ss_u_samplecntr_error;
wire [31:0] ss_u_samplecntr_rdata;
wire [31:0] ss_u_cyc11r_cyc37r_envstate_sr_valid_mask;
wire ss_u_cyc11r_cyc37r_envstate_sr_ack;
wire ss_u_cyc11r_cyc37r_envstate_sr_error;
wire [31:0] ss_u_cyc11r_cyc37r_envstate_sr_rdata;
wire [31:0] ss_u_cyc13r_cyc40r_attenlevel_sr_valid_mask;
wire ss_u_cyc13r_cyc40r_attenlevel_sr_ack;
wire ss_u_cyc13r_cyc40r_attenlevel_sr_error;
wire [31:0] ss_u_cyc13r_cyc40r_attenlevel_sr_rdata;




///////////////////////////////////////////////////////////
//////  Clock and reset
////

wire            phi1pcen_n = i_phi1_PCEN_n;
wire            phi1ncen_n = i_phi1_NCEN_n;
wire            mrst_n = i_MRST_n;



///////////////////////////////////////////////////////////
//////  Cycle number
////

//additional cycle bits
reg             cycle_01_17;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd108: begin
                    cycle_01_17 <= i_SS_WDATA[0];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cycle_01_17 <= i_CYCLE_00_16;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Third sample flag
////

reg             samplecntr_rst;
wire    [1:0]   samplecntr_q;
reg             third_sample;

always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd108: begin
                    samplecntr_rst <= i_SS_WDATA[1];
                    third_sample <= i_SS_WDATA[2];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            samplecntr_rst <= samplecntr_q[1];

            third_sample <= samplecntr_q[1] | i_TEST_D0;
        end
    end
end

cavebanpresto_ikaopm_ss_counter #(.SS_BASE_BIT(13'd3693), .WIDTH(2)) u_samplecntr (
    .i_EMUCLK(i_EMUCLK), .i_PCEN_n(phi1pcen_n), .i_NCEN_n(phi1ncen_n),
    .i_CNT(i_CYCLE_31), .i_LD(1'b0), .i_RST((samplecntr_rst & i_CYCLE_31) | ~mrst_n),
    .i_D(2'd0), .o_Q(samplecntr_q), .o_CO()

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_samplecntr_valid_mask),
    .o_SS_ACK        (ss_u_samplecntr_ack),
    .o_SS_ERROR      (ss_u_samplecntr_error),
    .o_SS_RDATA      (ss_u_samplecntr_rdata)
);



///////////////////////////////////////////////////////////
//////  Attenuation rate generator
////

/*
    YM2151 uses serial counter and shift register to get the rate below

    timecntr = X_0000_00000_00000 = 0
    timecntr = X_1000_00000_00000 = 14
    timecntr = X_X100_00000_00000 = 13
    timecntr = X_XX10_00000_00000 = 12
    ...
    timecntr = X_XXXX_XXXXX_XXX10 = 2
    timecntr = X_XXXX_XXXXX_XXXX1 = 1

    I used parallel 4-bit counter instead of the shift register to save
    FPGA resources.
*/

reg             mrst_z;
reg     [1:0]   timecntr_adder;
reg     [14:0]  timecntr_sr; //this sr can hold 15-bit integer

reg             onebit_det, mrst_dlyd;
reg     [3:0]   conseczerobitcntr;

always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd108: begin
                    mrst_z <= i_SS_WDATA[3];
                    timecntr_adder <= i_SS_WDATA[5:4];
                    timecntr_sr <= i_SS_WDATA[20:6];
                    onebit_det <= i_SS_WDATA[21];
                    conseczerobitcntr <= i_SS_WDATA[25:22];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            //adder
            timecntr_adder <= mrst_n ? (((third_sample & i_CYCLE_01_TO_16) & (cycle_01_17 | timecntr_adder[1])) + timecntr_sr[0]) :
                                        2'd0;

            //sr
            timecntr_sr[14] <= timecntr_adder[0];
            timecntr_sr[13:0] <= timecntr_sr[14:1];

            //consecutive zero bits counter
            mrst_z <= ~mrst_n; //delay master reset, to synchronize the reset timing with timecntr_adder register

            if(mrst_z | cycle_01_17) begin
                onebit_det <= 1'b0;
                conseczerobitcntr <= 4'd1; //start from 1
            end
            else begin
                if(!onebit_det) begin
                    if(timecntr_adder[0]) begin
                        onebit_det <= 1'b1;
                        conseczerobitcntr <= conseczerobitcntr;
                    end
                    else begin
                        onebit_det <= 1'b0;
                        conseczerobitcntr <= (conseczerobitcntr == 4'd14) ? 4'd0 : conseczerobitcntr + 4'd1; //max 14
                    end
                end
            end
        end
    end
end

`ifdef IKAOPM_DEBUG
reg     [15:0]  debug_timecntr;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        // Held: no emulation state advances.
    end else begin
        if(!phi1ncen_n) begin
            if(cycle_01_17) debug_timecntr <= {timecntr_adder[0], timecntr_sr}; //timecounter parallel output
        end
    end
end
`endif


reg     [1:0]   envcntr;
reg     [3:0]   attenrate;

always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd108: begin
                    envcntr <= i_SS_WDATA[27:26];
                    attenrate <= i_SS_WDATA[31:28];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1pcen_n) begin //positive edge!!!!
            if(third_sample & ~i_CYCLE_01_TO_16 & cycle_01_17) begin
                envcntr <= timecntr_sr[2:1];

                attenrate <= conseczerobitcntr;
            end
        end
    end
end



///////////////////////////////////////////////////////////
//////  Previous KON shift register
////

/*
    Note that the cycle numbers below are "elapsed" cycle, 
    NOT the master cycle counter value

                                             previous KON data
                                     |----------(32 stages)---------|
    i_KON(cyc5) -> (cyc6 - cyc9) -+> (cyc10 - cyc37) -> (cyc6 - cyc9) -> -o|¯¯¯¯\
                                  |                                        | AND )---
                                  +------------------------------------> --|____/
                                                                    positive edge detector
*/

//These shift registers holds KON values from previous 32 cycles
reg     [3:0]   cyc6r_cyc9r_kon_current_dlyline; //outer process delay compensation(4 cycles)
reg     [27:0]  cyc10r_cyc37r_kon_previous; //previous KON values
reg     [3:0]   cyc6r_cyc9r_kon_previous; //delayed concurrently with the current kon delay line

wire            cyc9r_kon_current = cyc6r_cyc9r_kon_current_dlyline[3]; //current kon value
wire            cyc9r_kon_detected = ~cyc6r_cyc9r_kon_previous[3] & cyc9r_kon_current; //prev=0, curr=1, new kon detected
assign  o_PG_PHASE_RST = cyc9r_kon_detected;

always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd109: begin
                    cyc6r_cyc9r_kon_current_dlyline <= i_SS_WDATA[3:0];
                    cyc10r_cyc37r_kon_previous <= i_SS_WDATA[31:4];
                end
                8'd110: begin
                    cyc6r_cyc9r_kon_previous <= i_SS_WDATA[3:0];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc6r_cyc9r_kon_current_dlyline[0] <= i_KON;
            cyc6r_cyc9r_kon_current_dlyline[3:1] <= cyc6r_cyc9r_kon_current_dlyline[2:0];

            cyc10r_cyc37r_kon_previous[0] <= cyc6r_cyc9r_kon_current_dlyline[3];
            cyc10r_cyc37r_kon_previous[27:1] <= cyc10r_cyc37r_kon_previous[26:0];

            cyc6r_cyc9r_kon_previous[0] <= cyc10r_cyc37r_kon_previous[27];
            cyc6r_cyc9r_kon_previous[3:1] <= cyc6r_cyc9r_kon_previous[2:0];
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 6 to 37: Envelope state machine
////

/*
    Note that the cycle numbers below are "elapsed" cycle, 
    NOT the master cycle counter value

    Envelope state machine holds the states of 32 operators

                  (state update)
                        |
                        V
    (cyc6 - cyc9) -> (cyc10 - cyc37) (loop to cyc 6, total 32 stages) 
*/

localparam ATTACK = 2'd0;
localparam FIRST_DECAY = 2'd1;
localparam SECOND_DECAY = 2'd2;
localparam RELEASE = 2'd3;

//
//  combinational part
//

//flags and prev state for FSM, get the values from the last step of the attenuation level SR
wire            cyc10c_first_decay_end;
wire            cyc10c_prevatten_min;
wire            cyc10c_prevatten_max;


//
//  register part
//

//total 32 stages to store states of all operators
reg     [1:0]   cyc6r_cyc9r_envstate_previous[0:3]; //4 stages
reg     [1:0]   cyc10r_envstate_current; //1 stage
wire    [1:0]   cyc37r_envstate_previous; //27 stages

wire    [1:0]   cyc9r_envstate_previous = cyc6r_cyc9r_envstate_previous[3];


//sr4
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd110: begin
                    cyc6r_cyc9r_envstate_previous[0] <= i_SS_WDATA[5:4];
                    cyc6r_cyc9r_envstate_previous[1] <= i_SS_WDATA[7:6];
                    cyc6r_cyc9r_envstate_previous[2] <= i_SS_WDATA[9:8];
                    cyc6r_cyc9r_envstate_previous[3] <= i_SS_WDATA[11:10];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            //if kon detected, make previous envstate ATTACK
            cyc6r_cyc9r_envstate_previous[0] <= (~cyc10r_cyc37r_kon_previous[27] & i_KON) ? ATTACK : cyc37r_envstate_previous;
            cyc6r_cyc9r_envstate_previous[1] <= cyc6r_cyc9r_envstate_previous[0];
            cyc6r_cyc9r_envstate_previous[2] <= cyc6r_cyc9r_envstate_previous[1];
            cyc6r_cyc9r_envstate_previous[3] <= cyc6r_cyc9r_envstate_previous[2];
        end
    end
end

//sr27 first stage
cavebanpresto_ikaopm_ss_sr #(.SS_BASE_BIT(13'd3696), .WIDTH(2), .LENGTH(27), .TAP(27)) u_cyc11r_cyc37r_envstate_sr
(.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_D(cyc10r_envstate_current), .o_Q_TAP(), .o_Q_LAST(cyc37r_envstate_previous)
,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_cyc11r_cyc37r_envstate_sr_valid_mask),
    .o_SS_ACK        (ss_u_cyc11r_cyc37r_envstate_sr_ack),
    .o_SS_ERROR      (ss_u_cyc11r_cyc37r_envstate_sr_error),
    .o_SS_RDATA      (ss_u_cyc11r_cyc37r_envstate_sr_rdata)
);



//state machine
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd110: begin
                    cyc10r_envstate_current <= i_SS_WDATA[13:12];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            if(!mrst_n) begin
                cyc10r_envstate_current <= RELEASE;
            end
            else begin
                if(cyc9r_kon_detected) begin
                    cyc10r_envstate_current <= ATTACK; //start attack
                end
                else begin
                    if(cyc9r_kon_current) begin
                        case(cyc9r_envstate_previous)
                            //current state 0: attack
                            2'd0: begin
                                if(cyc10c_prevatten_min) begin
                                    cyc10r_envstate_current <= FIRST_DECAY; //start first decay
                                end
                                else begin
                                    cyc10r_envstate_current <= ATTACK; //hold state
                                end
                            end

                            //current state 1: first decay
                            2'd1: begin
                                if(cyc10c_prevatten_max) begin
                                    cyc10r_envstate_current <= RELEASE; //start release
                                end
                                else begin
                                    if(cyc10c_first_decay_end) begin
                                        cyc10r_envstate_current <= SECOND_DECAY; //start second decay
                                    end
                                    else begin
                                        cyc10r_envstate_current <= FIRST_DECAY; //hold state
                                    end
                                end
                            end 

                            //current state 2: second decay
                            2'd2: begin
                                if(cyc10c_prevatten_max) begin
                                    cyc10r_envstate_current <= RELEASE; //start release
                                end
                                else begin
                                    cyc10r_envstate_current <= SECOND_DECAY; //hold state
                                end
                            end

                            //current state 3: release
                            2'd3: begin
                                cyc10r_envstate_current <= RELEASE; //hold state
                            end
                        endcase                    
                    end
                    else begin
                        cyc10r_envstate_current <= RELEASE; //key off -> start release
                    end
                end
            end
        end
    end
end



///////////////////////////////////////////////////////////
//////  Attenuation level preprocessing
//////  Cycle 8: EG param/KS latch 
////


//
//  combinational part
//

reg     [4:0]   cyc8c_egparam;
always @(*) begin
    if(!mrst_n) begin
        cyc8c_egparam = 5'd31;
    end
    else begin
        case(cyc6r_cyc9r_envstate_previous[1])
            ATTACK:         cyc8c_egparam = i_AR;
            FIRST_DECAY:    cyc8c_egparam = i_D1R;
            SECOND_DECAY:   cyc8c_egparam = i_D2R;
            RELEASE:        cyc8c_egparam = {i_RR, 1'b1};
        endcase
    end
end


//
//  register part
//

reg     [4:0]   cyc8r_egparam;
reg             cyc8r_egparam_zero;
reg     [3:0]   cyc8r_d1l;
reg     [4:0]   cyc8r_keyscale;

always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd110: begin
                    cyc8r_egparam <= i_SS_WDATA[18:14];
                    cyc8r_egparam_zero <= i_SS_WDATA[19];
                    cyc8r_d1l <= i_SS_WDATA[23:20];
                    cyc8r_keyscale <= i_SS_WDATA[28:24];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc8r_egparam <= cyc8c_egparam;
            cyc8r_egparam_zero <= cyc8c_egparam == 5'd0;
            cyc8r_d1l <= i_D1L;

            case(i_KS)
                2'd0: cyc8r_keyscale <= (cyc8c_egparam == 5'd0) ? 5'd0 : {3'b000, i_EG_PDELTA_SHIFT_AMOUNT[4:3]};
                2'd1: cyc8r_keyscale <= {2'b00, i_EG_PDELTA_SHIFT_AMOUNT[4:2]};
                2'd2: cyc8r_keyscale <= {1'b0, i_EG_PDELTA_SHIFT_AMOUNT[4:1]};
                2'd3: cyc8r_keyscale <= i_EG_PDELTA_SHIFT_AMOUNT;
            endcase
        end
    end
end



///////////////////////////////////////////////////////////
//////  Attenuation level preprocessing
//////  Cycle 9: apply KS 
////


//
//  combinational part
//

wire    [6:0]   cyc9c_egparam_scaled_adder = {cyc8r_egparam, 1'b0} + {1'b0, cyc8r_keyscale};
wire    [9:0]   cyc40r_attenlevel_previous; //feedback from the last stage of the SR


//
//  register part
//

reg             cyc9r_egparam_zero;
reg     [5:0]   cyc9r_egparam_scaled;
reg             cyc9r_egparam_scaled_fullrate;
reg     [3:0]   cyc9r_d1l;

reg             cyc9r_third_sample;
reg     [1:0]   cyc9r_envcntr;
reg     [3:0]   cyc9r_attenrate;

reg     [9:0]   cyc9r_attenlevel_previous;

always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd110: begin
                    cyc9r_egparam_zero <= i_SS_WDATA[29];
                    cyc9r_egparam_scaled[1:0] <= i_SS_WDATA[31:30];
                end
                8'd111: begin
                    cyc9r_egparam_scaled[5:2] <= i_SS_WDATA[3:0];
                    cyc9r_egparam_scaled_fullrate <= i_SS_WDATA[4];
                    cyc9r_d1l <= i_SS_WDATA[8:5];
                    cyc9r_third_sample <= i_SS_WDATA[9];
                    cyc9r_envcntr <= i_SS_WDATA[11:10];
                    cyc9r_attenrate <= i_SS_WDATA[15:12];
                    cyc9r_attenlevel_previous <= i_SS_WDATA[25:16];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc9r_egparam_zero <= cyc8r_egparam_zero;
            cyc9r_egparam_scaled <= cyc9c_egparam_scaled_adder[6] ? 6'd63 : cyc9c_egparam_scaled_adder[5:0]; //saturation
            cyc9r_egparam_scaled_fullrate <= cyc9c_egparam_scaled_adder[5:1] == 5'b11111; //eg parameter max
            cyc9r_d1l <= cyc8r_d1l;

            cyc9r_third_sample <= third_sample;
            cyc9r_envcntr <= envcntr;
            cyc9r_attenrate <= attenrate;

            cyc9r_attenlevel_previous <= cyc40r_attenlevel_previous;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Attenuation level preprocessing
//////  Cycle 10: make attenuation level delta weight
////


/*

    HOW ATTENUATION RATE GENERATOR WORKS:

    See "Attenuation rate generator" section. Attenrate value is determined
    from the counter value like below:

    timecntr = X_0000_00000_00000 = 0
    timecntr = X_1000_00000_00000 = 14
    timecntr = X_X100_00000_00000 = 13
    timecntr = X_XX10_00000_00000 = 12
    ...
    timecntr = X_XXXX_XXXXX_XXX10 = 2
    timecntr = X_XXXX_XXXXX_XXXX1 = 1

    An attenuation rate of 1 will occur most often, 14 or 0 will occur 
    least often. Attenuation rate * 4 (2-bit left shift) is added to 
    the "egparam_scaled" to get the final value.

    Therefore, the quadrupled values that should be added to 
    "egparam_scaled" are:

    least often <----                      ----> most often
    0, 56, 52, 48, 44, 40, 36, 32, 28, 24, 20, 16, 12, 8, 4


    If the "egparam_scaled" is NOT 11XXXX, there are three conditions 
    that can change the envelope value:

    1. egparam_scaled      != from 6'd48 to 6'd63
       egparam_scaled      != 6'd0
       egparam_rateapplied == from 6'd48 to 6'd51

    2. egparam_scaled      != from 6'd48 to 6'd63
       egparam_rateapplied == 6'd54 or 6'd55

    3. egparam_scaled      != from 6'd48 to 6'd63
       egparam_rateapplied == 6'd57 or 6'd59

    These three conditions can be compressed like this:
        egparam_scaled      != from 6'd48 to 6'd63
        egparam_scaled      != 6'd0
        egparam_rateapplied == 48, 49, 50, 51, 54, 55, 57, 59


    Therefore, if "egparam scaled" is 1, this value can change the envelope
    level when the rate is "48"
    if "egparam_scaled" is 2, this value can change the envelope level when
    the rate is "48" or "52"
    if 3, the value-changable rate is "48" or "52" or "59"
    if 4, the value-changable rate is "44"

    The rate "44" appears more often than the sum of the frequency of
    occurrence of "48", "52", "59". So, egparam_scaled = 4 can change the
    envelope level often, than 1, 2, 3. If the envelope level changes frequently,
    the difference between the envelope level of the current sample and the next 
    sample becomes larger.


    INTENSITY AND ENVELOPE DELTA WEIGHT:






*/


//
//  combinational part
//

reg             cyc10c_envdeltaweight_intensity; //0 = weak, 1 = strong
always @(*) begin
    case({cyc9r_egparam_scaled[1:0], cyc9r_envcntr})
        4'b00_00: cyc10c_envdeltaweight_intensity = 1'b0;
        4'b00_01: cyc10c_envdeltaweight_intensity = 1'b0;
        4'b00_10: cyc10c_envdeltaweight_intensity = 1'b0;
        4'b00_11: cyc10c_envdeltaweight_intensity = 1'b0;

        4'b01_00: cyc10c_envdeltaweight_intensity = 1'b1;
        4'b01_01: cyc10c_envdeltaweight_intensity = 1'b0;
        4'b01_10: cyc10c_envdeltaweight_intensity = 1'b0;
        4'b01_11: cyc10c_envdeltaweight_intensity = 1'b0;

        4'b10_00: cyc10c_envdeltaweight_intensity = 1'b1;
        4'b10_01: cyc10c_envdeltaweight_intensity = 1'b0;
        4'b10_10: cyc10c_envdeltaweight_intensity = 1'b1;
        4'b10_11: cyc10c_envdeltaweight_intensity = 1'b0;

        4'b11_00: cyc10c_envdeltaweight_intensity = 1'b1;
        4'b11_01: cyc10c_envdeltaweight_intensity = 1'b1;
        4'b11_10: cyc10c_envdeltaweight_intensity = 1'b1;
        4'b11_11: cyc10c_envdeltaweight_intensity = 1'b0;
    endcase
end

wire    [5:0]   cyc10c_egparam_rateapplied = cyc9r_egparam_scaled + {cyc9r_attenrate, 2'b00}; //discard carry

//first decay end, compare cyc9r_attenlevel_previous[9:4] with {(cyc9r_d1l == 4'd15), cyc9r_d1l, 1'b0} <- idk why
assign  cyc10c_first_decay_end =  cyc9r_attenlevel_previous[9:4] == {(cyc9r_d1l == 4'd15), cyc9r_d1l, 1'b0}; //==? {(cyc9r_d1l == 4'd15), cyc9r_d1l, 1'b0, 4'bXXXX};

//attenuation level is min(loud)
assign  cyc10c_prevatten_min = cyc9r_attenlevel_previous == 10'd0;

//attenuation level is around max(quiet), get cyc9r_attenlevel_previous[9:4] only. [3:0] don't care
assign  cyc10c_prevatten_max = cyc9r_attenlevel_previous >= 10'd1008; //==? 10'b11_1111_xxxx;


//
//  register part
//

//envelope delta weight
reg     [3:0]   cyc10r_envdeltaweight; //lv4, lv3, lv2, lv1
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd111: begin
                    cyc10r_envdeltaweight <= i_SS_WDATA[29:26];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            //only works every third sample
            if(cyc9r_third_sample) begin
                //if egparam_scaled == 1111XX
                if     (cyc9r_egparam_scaled[5:2] == 4'b1111) cyc10r_envdeltaweight <= cyc10c_envdeltaweight_intensity ? 4'b1000 : 4'b1000;
                
                //if egparam_scaled == 1110XX
                else if(cyc9r_egparam_scaled[5:2] == 4'b1110) cyc10r_envdeltaweight <= cyc10c_envdeltaweight_intensity ? 4'b1000 : 4'b0100;
                
                //if egparam_scaled == 1101XX
                else if(cyc9r_egparam_scaled[5:2] == 4'b1101) cyc10r_envdeltaweight <= cyc10c_envdeltaweight_intensity ? 4'b0100 : 4'b0010;
                
                //if egparam_scaled == 1100XX
                else if(cyc9r_egparam_scaled[5:2] == 4'b1100) cyc10r_envdeltaweight <= cyc10c_envdeltaweight_intensity ? 4'b0010 : 4'b0001;
                
                //else, not 11XXXX
                else begin
                    if(cyc9r_egparam_zero) begin
                        cyc10r_envdeltaweight <= 4'b0000;
                    end
                    else begin
                        if(cyc9r_egparam_scaled != 6'd0 & 
                            |{cyc10c_egparam_rateapplied == 6'd59, cyc10c_egparam_rateapplied == 6'd57,
                                cyc10c_egparam_rateapplied == 6'd55, cyc10c_egparam_rateapplied == 6'd54,
                                cyc10c_egparam_rateapplied == 6'd51, cyc10c_egparam_rateapplied == 6'd50,
                                cyc10c_egparam_rateapplied == 6'd49, cyc10c_egparam_rateapplied == 6'd48}) begin
                            
                            cyc10r_envdeltaweight <= 4'b0001;
                        end
                        else begin
                            cyc10r_envdeltaweight <= 4'b0000;
                        end
                    end
                end
            end
            else begin
                cyc10r_envdeltaweight <= 4'b0000;
            end
        end
    end
end

//misc flags for envelope generator feedback
reg             cyc10r_atten_inc; //attenuation level decrement mode(for decay and release)
reg             cyc10r_atten_dec; //attenuation level increment mode(for attack)
reg             cyc10r_fix_prevatten_max; //force previous attenuation level max(quiet)
reg             cyc10r_enable_prevatten; //previous attenuation level enable(disable = 0)
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd111: begin
                    cyc10r_atten_inc <= i_SS_WDATA[30];
                    cyc10r_atten_dec <= i_SS_WDATA[31];
                end
                8'd112: begin
                    cyc10r_fix_prevatten_max <= i_SS_WDATA[0];
                    cyc10r_enable_prevatten <= i_SS_WDATA[1];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            if(!mrst_n) begin
                cyc10r_atten_inc <= 1'b0;
                cyc10r_atten_dec <= 1'b0;
            end
            else begin
                cyc10r_atten_inc     <= ( cyc9r_envstate_previous == FIRST_DECAY &
                                        ~cyc9r_kon_detected &
                                        ~cyc10c_first_decay_end &
                                        ~cyc10c_prevatten_max ) |
                                        ((cyc9r_envstate_previous == SECOND_DECAY | cyc9r_envstate_previous == RELEASE) &
                                        ~cyc9r_kon_detected &
                                        ~cyc10c_prevatten_max );

                cyc10r_atten_dec      <= ( cyc9r_envstate_previous == ATTACK &
                                        cyc9r_kon_current &
                                        ~cyc10c_prevatten_min &
                                        ~cyc9r_egparam_scaled_fullrate );
            end

            cyc10r_fix_prevatten_max <= ( cyc9r_envstate_previous != ATTACK ) & ~cyc9r_kon_detected & cyc10c_prevatten_max;

            cyc10r_enable_prevatten  <= (~cyc9r_kon_detected &
                                            cyc9r_egparam_scaled_fullrate) |
                                            ~cyc9r_egparam_scaled_fullrate;
        end
    end
end

reg     [9:0]   cyc10r_attenlevel_previous;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd112: begin
                    cyc10r_attenlevel_previous <= i_SS_WDATA[11:2];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc10r_attenlevel_previous <= cyc9r_attenlevel_previous;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 11 to 40: Attenuation level SR storage
////

/*
    Note that the cycle numbers below are "elapsed" cycle, 
    NOT the master cycle counter value

    start from cycle 11, this shift register stores all envelopes of 32 operators

                                                  <---------(30 stages)----------->
    cyc6  -> cyc7  -> cyc8  -> cyc9  -> cyc10 -+> cyc11 -> cyc12 -> (cyc13 - cyc40) --> attenuation value output from cycle 40
                                               |                               |
                                 +---------------------------------------------+
                                 V             |
                               cyc9  -> cyc10 -+
                               <--(2 stages)-->

*/ 

//
//  cycle 11: latch weighted delta
//

reg     [9:0]   cyc11r_attenlevel_previous_gated; //loud: 10'd0, quiet: 10'd1023
reg     [9:0]   cyc11r_attenlevel_weighted_delta;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd112: begin
                    cyc11r_attenlevel_previous_gated <= i_SS_WDATA[21:12];
                    cyc11r_attenlevel_weighted_delta <= i_SS_WDATA[31:22];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            if(cyc10r_fix_prevatten_max | ~mrst_n) cyc11r_attenlevel_previous_gated <= 10'd1023;
            else begin
                if(cyc10r_enable_prevatten) cyc11r_attenlevel_previous_gated <= cyc10r_attenlevel_previous;
                else                        cyc11r_attenlevel_previous_gated <= 10'd0;
            end

            case({cyc10r_atten_dec, cyc10r_atten_inc})
                //off, no change
                2'b00: cyc11r_attenlevel_weighted_delta <= 10'd0;

                //attenuation level increment: quieter
                2'b01: cyc11r_attenlevel_weighted_delta <= {6'b000000, cyc10r_envdeltaweight};

                //attenuation level decrement: louder
                2'b10: begin
                    case(cyc10r_envdeltaweight)
                        4'b0001: cyc11r_attenlevel_weighted_delta <= {4'b1111, ~cyc10r_attenlevel_previous[9:5], ~cyc10r_attenlevel_previous[3]};
                        4'b0010: cyc11r_attenlevel_weighted_delta <= {3'b111, ~cyc10r_attenlevel_previous[9:5], ~cyc10r_attenlevel_previous[3], ~cyc10r_attenlevel_previous[1]};
                        4'b0100: cyc11r_attenlevel_weighted_delta <= {2'b11, ~cyc10r_attenlevel_previous[9:5], ~cyc10r_attenlevel_previous[3], {2{~cyc10r_attenlevel_previous[2]}}};
                        4'b1000: cyc11r_attenlevel_weighted_delta <= {1'b1, ~cyc10r_attenlevel_previous[9:5], {4{~cyc10r_attenlevel_previous[4]}}};
                        default: cyc11r_attenlevel_weighted_delta <= 10'd0;
                    endcase
                end

                //invalid, will not happen
                2'b11: cyc11r_attenlevel_weighted_delta <= 10'd1023;
            endcase
        end
    end
end



//
//  cycle 12: add delta
//

reg     [9:0]   cyc12r_attenlevel_current;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd113: begin
                    cyc12r_attenlevel_current <= i_SS_WDATA[9:0];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc12r_attenlevel_current <= cyc11r_attenlevel_previous_gated + cyc11r_attenlevel_weighted_delta; //discard carry
        end
    end
end



//
//  cycle from 13 to 40: shift register storage
//

//total 32 stages to store all levels, SR 28 stages and the remaining 4 stages from cyc9r to cyc12r

cavebanpresto_ikaopm_ss_sr #(.SS_BASE_BIT(13'd3750), .WIDTH(10), .LENGTH(28), .TAP(28)) u_cyc13r_cyc40r_attenlevel_sr
(.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_D(cyc12r_attenlevel_current), .o_Q_TAP(), .o_Q_LAST(cyc40r_attenlevel_previous)
,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_cyc13r_cyc40r_attenlevel_sr_valid_mask),
    .o_SS_ACK        (ss_u_cyc13r_cyc40r_attenlevel_sr_ack),
    .o_SS_ERROR      (ss_u_cyc13r_cyc40r_attenlevel_sr_error),
    .o_SS_RDATA      (ss_u_cyc13r_cyc40r_attenlevel_sr_rdata)
);





///////////////////////////////////////////////////////////
//////  Attenuation level postprocessing
//////  Cycle 40: shift LFA
////

//
//  register part
//

reg     [9:0]   cyc40r_lfa_shifted;
reg             cyc40r_force_no_atten;
reg     [6:0]   cyc40r_tl;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd113: begin
                    cyc40r_lfa_shifted <= i_SS_WDATA[19:10];
                    cyc40r_force_no_atten <= i_SS_WDATA[20];
                    cyc40r_tl <= i_SS_WDATA[27:21];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            case(i_AMS)
                2'd0: cyc40r_lfa_shifted <= {10'd0};
                2'd1: cyc40r_lfa_shifted <= {2'b00, i_LFA};
                2'd2: cyc40r_lfa_shifted <= {1'b0, i_LFA, 1'b0};
                2'd3: cyc40r_lfa_shifted <= {i_LFA, 2'b00};
            endcase

            cyc40r_force_no_atten <= i_TEST_D5;
            cyc40r_tl <= i_TL;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Attenuation level postprocessing
//////  Cycle 41: apply LFA/underflow handling
////

//
//  combinational part
//

wire    [10:0]  cyc41c_attenlevel_mod_adder = cyc40r_attenlevel_previous + cyc40r_lfa_shifted;


//
//  register part
//

reg     [9:0]   cyc41r_attenlevel_mod;
reg             cyc41r_force_no_atten;
reg     [6:0]   cyc41r_tl;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd113: begin
                    cyc41r_attenlevel_mod[3:0] <= i_SS_WDATA[31:28];
                end
                8'd114: begin
                    cyc41r_attenlevel_mod[9:4] <= i_SS_WDATA[5:0];
                    cyc41r_force_no_atten <= i_SS_WDATA[6];
                    cyc41r_tl <= i_SS_WDATA[13:7];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc41r_attenlevel_mod <= cyc41c_attenlevel_mod_adder[10] ? 10'd1023 : cyc41c_attenlevel_mod_adder[9:0]; //attenlevel saturation

            cyc41r_force_no_atten <= cyc40r_force_no_atten;
            cyc41r_tl <= cyc40r_tl;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Attenuation level postprocessing
//////  Cycle 42: apply TL/underflow handling
////

//
//  combinational part
//

wire    [10:0]  cyc42c_attenlevel_tl_adder = cyc41r_attenlevel_mod + {cyc41r_tl, 3'b000}; //multiply by 8


//
//  register part
//

reg     [9:0]   cyc42r_attenlevel_tl;
reg             cyc42r_force_no_atten;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd114: begin
                    cyc42r_attenlevel_tl <= i_SS_WDATA[23:14];
                    cyc42r_force_no_atten <= i_SS_WDATA[24];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc42r_attenlevel_tl <= cyc42c_attenlevel_tl_adder[10] ? 10'd1023 : cyc42c_attenlevel_tl_adder[9:0]; //attenlevel saturation

            cyc42r_force_no_atten <= cyc41r_force_no_atten;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Attenuation level postprocessing
//////  Cycle 43: apply test bit
////

reg     [9:0]   cyc43r_attenlevel_final;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd114: begin
                    cyc43r_attenlevel_final[6:0] <= i_SS_WDATA[31:25];
                end
                8'd115: begin
                    cyc43r_attenlevel_final[9:7] <= i_SS_WDATA[2:0];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc43r_attenlevel_final <= cyc42r_force_no_atten ? 10'd0 : cyc42r_attenlevel_tl; //force attenlevel min(loud)
        end
    end
end

//final value
assign  o_OP_ATTENLEVEL = cyc43r_attenlevel_final;



///////////////////////////////////////////////////////////
//////  Attenuation level serialization
////

reg     [9:0]   noise_attenlevel;
assign  o_NOISE_ATTENLEVEL = noise_attenlevel[9];
assign  o_REG_ATTENLEVEL_CH8_C2 = noise_attenlevel[9];

always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd115: begin
                    noise_attenlevel <= i_SS_WDATA[12:3];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            if(i_CYCLE_03) noise_attenlevel <= cyc43r_attenlevel_final;
            else begin 
                noise_attenlevel[9:1] <= noise_attenlevel[8:0];
                noise_attenlevel[0] <= 1'b1;
            end
        end
    end
end



///////////////////////////////////////////////////////////
//////  STATIC STORAGE FOR DEBUG
////

`ifdef IKAOPM_DEBUG

reg     [4:0]   sim_attenlevel_static_storage_addr_cntr = 5'd0;
reg     [4:0]   sim_envstate_static_storage_addr_cntr = 5'd0;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        // Held: no emulation state advances.
    end else begin
        if(!phi1ncen_n) begin
            if(i_CYCLE_03) sim_attenlevel_static_storage_addr_cntr <= 5'd0;
            else sim_attenlevel_static_storage_addr_cntr <= sim_attenlevel_static_storage_addr_cntr == 5'd31 ? 5'd0 : sim_attenlevel_static_storage_addr_cntr + 5'd1;

            if(i_CYCLE_03) sim_envstate_static_storage_addr_cntr <= 5'd1;
            else sim_envstate_static_storage_addr_cntr <= sim_envstate_static_storage_addr_cntr == 5'd31 ? 5'd0 : sim_envstate_static_storage_addr_cntr + 5'd1;
        end
    end
end

reg     [9:0]  sim_attenlevel_static_storage[0:31];
reg     [1:0]  sim_envstate_static_storage[0:31];
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        // Held: no emulation state advances.
    end else begin
        if(!phi1ncen_n) begin
            sim_attenlevel_static_storage[sim_attenlevel_static_storage_addr_cntr] <= mrst_n ? ~cyc43r_attenlevel_final : 10'd0;
            sim_envstate_static_storage[sim_envstate_static_storage_addr_cntr] <= mrst_n ? cyc10r_envstate_current : 2'd3;
        end
    end
end

`endif


// CaveBanpresto exact-state word instrumentation.

always @(*) begin
    ss_local_valid_mask = 32'd0;
    ss_local_read_data = 32'd0;
    case (i_SS_WORD_ADDR)
        8'd108: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[0] = cycle_01_17;
            ss_local_read_data[1] = samplecntr_rst;
            ss_local_read_data[2] = third_sample;
            ss_local_read_data[3] = mrst_z;
            ss_local_read_data[5:4] = timecntr_adder;
            ss_local_read_data[20:6] = timecntr_sr;
            ss_local_read_data[21] = onebit_det;
            ss_local_read_data[25:22] = conseczerobitcntr;
            ss_local_read_data[27:26] = envcntr;
            ss_local_read_data[31:28] = attenrate;
        end
        8'd109: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[3:0] = cyc6r_cyc9r_kon_current_dlyline;
            ss_local_read_data[31:4] = cyc10r_cyc37r_kon_previous;
        end
        8'd110: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[3:0] = cyc6r_cyc9r_kon_previous;
            ss_local_read_data[5:4] = cyc6r_cyc9r_envstate_previous[0];
            ss_local_read_data[7:6] = cyc6r_cyc9r_envstate_previous[1];
            ss_local_read_data[9:8] = cyc6r_cyc9r_envstate_previous[2];
            ss_local_read_data[11:10] = cyc6r_cyc9r_envstate_previous[3];
            ss_local_read_data[13:12] = cyc10r_envstate_current;
            ss_local_read_data[18:14] = cyc8r_egparam;
            ss_local_read_data[19] = cyc8r_egparam_zero;
            ss_local_read_data[23:20] = cyc8r_d1l;
            ss_local_read_data[28:24] = cyc8r_keyscale;
            ss_local_read_data[29] = cyc9r_egparam_zero;
            ss_local_read_data[31:30] = cyc9r_egparam_scaled[1:0];
        end
        8'd111: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[3:0] = cyc9r_egparam_scaled[5:2];
            ss_local_read_data[4] = cyc9r_egparam_scaled_fullrate;
            ss_local_read_data[8:5] = cyc9r_d1l;
            ss_local_read_data[9] = cyc9r_third_sample;
            ss_local_read_data[11:10] = cyc9r_envcntr;
            ss_local_read_data[15:12] = cyc9r_attenrate;
            ss_local_read_data[25:16] = cyc9r_attenlevel_previous;
            ss_local_read_data[29:26] = cyc10r_envdeltaweight;
            ss_local_read_data[30] = cyc10r_atten_inc;
            ss_local_read_data[31] = cyc10r_atten_dec;
        end
        8'd112: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[0] = cyc10r_fix_prevatten_max;
            ss_local_read_data[1] = cyc10r_enable_prevatten;
            ss_local_read_data[11:2] = cyc10r_attenlevel_previous;
            ss_local_read_data[21:12] = cyc11r_attenlevel_previous_gated;
            ss_local_read_data[31:22] = cyc11r_attenlevel_weighted_delta;
        end
        8'd113: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[9:0] = cyc12r_attenlevel_current;
            ss_local_read_data[19:10] = cyc40r_lfa_shifted;
            ss_local_read_data[20] = cyc40r_force_no_atten;
            ss_local_read_data[27:21] = cyc40r_tl;
            ss_local_read_data[31:28] = cyc41r_attenlevel_mod[3:0];
        end
        8'd114: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[5:0] = cyc41r_attenlevel_mod[9:4];
            ss_local_read_data[6] = cyc41r_force_no_atten;
            ss_local_read_data[13:7] = cyc41r_tl;
            ss_local_read_data[23:14] = cyc42r_attenlevel_tl;
            ss_local_read_data[24] = cyc42r_force_no_atten;
            ss_local_read_data[31:25] = cyc43r_attenlevel_final[6:0];
        end
        8'd115: begin
            ss_local_valid_mask = 32'h00001fff;
            ss_local_read_data[2:0] = cyc43r_attenlevel_final[9:7];
            ss_local_read_data[12:3] = noise_attenlevel;
        end
        default: ;
    endcase
end

assign ss_local_accept =
    i_SS_HOLD && i_SS_REQ && (|ss_local_valid_mask) && !ss_local_seen_q;
assign ss_local_write_accept = ss_local_accept && i_SS_WRITE;

always @(posedge i_EMUCLK) begin
    if (!i_SS_HOLD) begin
        ss_local_seen_q <= 1'b0;
        ss_local_ack_q <= 1'b0;
        ss_local_rdata_q <= 32'd0;
    end else begin
        ss_local_ack_q <= 1'b0;
        if (!i_SS_REQ)
            ss_local_seen_q <= 1'b0;
        if (ss_local_accept) begin
            ss_local_seen_q <= 1'b1;
            ss_local_ack_q <= 1'b1;
            ss_local_rdata_q <= ss_local_read_data;
        end
    end
end

assign o_SS_VALID_MASK = ss_local_valid_mask | ss_u_samplecntr_valid_mask | ss_u_cyc11r_cyc37r_envstate_sr_valid_mask | ss_u_cyc13r_cyc40r_attenlevel_sr_valid_mask;
assign o_SS_ACK = ss_local_ack_q | ss_u_samplecntr_ack | ss_u_cyc11r_cyc37r_envstate_sr_ack | ss_u_cyc13r_cyc40r_attenlevel_sr_ack;
assign o_SS_ERROR = 1'b0 | ss_u_samplecntr_error | ss_u_cyc11r_cyc37r_envstate_sr_error | ss_u_cyc13r_cyc40r_attenlevel_sr_error;
assign o_SS_RDATA = (ss_local_rdata_q & ss_local_valid_mask) | (ss_u_samplecntr_rdata & ss_u_samplecntr_valid_mask) | (ss_u_cyc11r_cyc37r_envstate_sr_rdata & ss_u_cyc11r_cyc37r_envstate_sr_valid_mask) | (ss_u_cyc13r_cyc40r_attenlevel_sr_rdata & ss_u_cyc13r_cyc40r_attenlevel_sr_valid_mask);


endmodule

module cavebanpresto_ikaopm_ss_op #(parameter integer SS_BASE_BIT = 4032) (
    //master clock
    input   wire            i_EMUCLK, //emulator master clock

    //core internal reset
    input   wire            i_MRST_n,

    //internal clock
    input   wire            i_phi1_PCEN_n, //positive edge clock enable for emulation
    input   wire            i_phi1_NCEN_n, //negative edge clock enable for emulation

    //timings
    input   wire            i_CYCLE_03,
    input   wire            i_CYCLE_12,
    input   wire            i_CYCLE_04_12_20_28,

    input   wire    [2:0]   i_ALG,
    input   wire    [2:0]   i_FL,
    input   wire            i_TEST_D4, //test register

    input   wire    [9:0]   i_OP_PHASEDATA,
    input   wire    [9:0]   i_OP_ATTENLEVEL,
    output  wire            o_ACC_SNDADD,
    output  wire    [13:0]  o_ACC_OPDATA

,
    input   wire            i_SS_HOLD,
    input   wire            i_SS_REQ,
    input   wire            i_SS_WRITE,
    input   wire    [7:0]   i_SS_WORD_ADDR,
    input   wire    [31:0]  i_SS_WDATA,
    output  wire    [31:0]  o_SS_VALID_MASK,
    output  wire            o_SS_ACK,
    output  wire            o_SS_ERROR,
    output  wire    [31:0]  o_SS_RDATA
);

// Forward declarations for exact-state instrumentation.
wire ss_local_write_accept;
wire ss_local_accept;
reg ss_local_seen_q;
reg ss_local_ack_q;
reg [31:0] ss_local_rdata_q;
reg [31:0] ss_local_valid_mask;
reg [31:0] ss_local_read_data;
wire [31:0] ss_u_op_algst_cntr_valid_mask;
wire ss_u_op_algst_cntr_ack;
wire ss_u_op_algst_cntr_error;
wire [31:0] ss_u_op_algst_cntr_rdata;
wire [31:0] ss_u_cyc42r_logsinrom_valid_mask;
wire ss_u_cyc42r_logsinrom_ack;
wire ss_u_cyc42r_logsinrom_error;
wire [31:0] ss_u_cyc42r_logsinrom_rdata;
wire [31:0] ss_u_cyc46r_exprom_valid_mask;
wire ss_u_cyc46r_exprom_ack;
wire ss_u_cyc46r_exprom_error;
wire [31:0] ss_u_cyc46r_exprom_rdata;
wire [31:0] ss_u_cyc46r_cyc53r_M1_z_valid_mask;
wire ss_u_cyc46r_cyc53r_M1_z_ack;
wire ss_u_cyc46r_cyc53r_M1_z_error;
wire [31:0] ss_u_cyc46r_cyc53r_M1_z_rdata;
wire [31:0] ss_u_cyc46r_cyc53r_M1_zz_valid_mask;
wire ss_u_cyc46r_cyc53r_M1_zz_ack;
wire ss_u_cyc46r_cyc53r_M1_zz_error;
wire [31:0] ss_u_cyc46r_cyc53r_M1_zz_rdata;
wire [31:0] ss_u_cyc46r_cyc53r_C1_z_valid_mask;
wire ss_u_cyc46r_cyc53r_C1_z_ack;
wire ss_u_cyc46r_cyc53r_C1_z_error;
wire [31:0] ss_u_cyc46r_cyc53r_C1_z_rdata;




///////////////////////////////////////////////////////////
//////  Clock and reset
////

wire            phi1pcen_n = i_phi1_PCEN_n;
wire            phi1ncen_n = i_phi1_NCEN_n;
wire            mrst_n = i_MRST_n;



///////////////////////////////////////////////////////////
//////  Algorithm state counter
////

wire    [1:0]   algst_cntr;
cavebanpresto_ikaopm_ss_counter #(.SS_BASE_BIT(13'd4266), .WIDTH(2)) u_op_algst_cntr (
    .i_EMUCLK(i_EMUCLK), .i_PCEN_n(phi1pcen_n), .i_NCEN_n(phi1ncen_n),
    .i_CNT(i_CYCLE_04_12_20_28), .i_LD(1'b0), .i_RST(i_CYCLE_12 | ~mrst_n),
    .i_D(2'd0), .o_Q(algst_cntr), .o_CO()

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_op_algst_cntr_valid_mask),
    .o_SS_ACK        (ss_u_op_algst_cntr_ack),
    .o_SS_ERROR      (ss_u_op_algst_cntr_error),
    .o_SS_RDATA      (ss_u_op_algst_cntr_rdata)
);



///////////////////////////////////////////////////////////
//////  Cycle 41: Phase modulation
////

//
//  combinational part
//

reg     [9:0]   cyc56r_phasemod_value; //get value from the end of the pipeline
wire    [10:0]  cyc41c_modded_phase_adder = !mrst_n ? 10'd0 : i_OP_PHASEDATA + cyc56r_phasemod_value;




//
//  register part
//

reg     [7:0]   cyc41r_logsinrom_phase;
reg             cyc41r_level_fp_sign;

always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd126: begin
                    cyc41r_logsinrom_phase <= i_SS_WDATA[17:10];
                    cyc41r_level_fp_sign <= i_SS_WDATA[18];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc41r_logsinrom_phase <= cyc41c_modded_phase_adder[8] ?  cyc41c_modded_phase_adder[7:0] : 
                                                                     ~cyc41c_modded_phase_adder[7:0];

            cyc41r_level_fp_sign <= cyc41c_modded_phase_adder[9]; //discard carry
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 42: Get data from Sin ROM
////

//
//  register part
//

wire    [45:0]  cyc42r_logsinrom_out;
cavebanpresto_ikaopm_ss_logsinrom #(.SS_BASE_BIT(13'd4269)) u_cyc42r_logsinrom (
    .i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_ADDR(cyc41r_logsinrom_phase[5:1]), .o_DATA(cyc42r_logsinrom_out)

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_cyc42r_logsinrom_valid_mask),
    .o_SS_ACK        (ss_u_cyc42r_logsinrom_ack),
    .o_SS_ERROR      (ss_u_cyc42r_logsinrom_error),
    .o_SS_RDATA      (ss_u_cyc42r_logsinrom_rdata)
);

reg             cyc42r_logsinrom_phase_odd;
reg     [1:0]   cyc42r_logsinrom_bitsel;
reg             cyc42r_level_fp_sign;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd126: begin
                    cyc42r_logsinrom_phase_odd <= i_SS_WDATA[19];
                    cyc42r_logsinrom_bitsel <= i_SS_WDATA[21:20];
                    cyc42r_level_fp_sign <= i_SS_WDATA[22];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc42r_logsinrom_phase_odd <= cyc41r_logsinrom_phase[0];
            cyc42r_logsinrom_bitsel <= cyc41r_logsinrom_phase[7:6];
            cyc42r_level_fp_sign <= cyc41r_level_fp_sign;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 43: Choose bits from Sin ROM and add them
////

//
//  combinational part
//

wire    [45:0]  ls = cyc42r_logsinrom_out; //alias signal
wire            odd = cyc42r_logsinrom_phase_odd; //alias signal

reg     [10:0]  cyc43c_logsinrom_addend0, cyc43c_logsinrom_addend1;
always @(*) begin
    case(cyc42r_logsinrom_bitsel)
        /*                                   D10      D9      D8      D7      D6      D5      D4      D3      D2      D1      D0  */
        2'd0: cyc43c_logsinrom_addend0 = {  1'b0,   1'b0,   1'b0,   1'b0,   1'b0,   1'b0, ls[29], ls[25], ls[18], ls[14],  ls[3]};
        2'd1: cyc43c_logsinrom_addend0 = {  1'b0,   1'b0,   1'b0,   1'b0, ls[37], ls[34], ls[28], ls[24], ls[17], ls[13],  ls[2]};
        2'd2: cyc43c_logsinrom_addend0 = {  1'b0,   1'b0, ls[43], ls[41], ls[36], ls[33], ls[27], ls[23], ls[16], ls[12],  ls[1]};
        2'd3: cyc43c_logsinrom_addend0 = {ls[45], ls[44], ls[42], ls[40], ls[35], ls[32], ls[26], ls[22], ls[15], ls[11],  ls[0]};
    endcase

    case(cyc42r_logsinrom_bitsel)
        /*                                   D10      D9      D8      D7      D6      D5      D4      D3      D2      D1      D0  */
        2'd0: cyc43c_logsinrom_addend1 = {  1'b0,   1'b0,   1'b0,   1'b0,   1'b0,   1'b0,   1'b0,   1'b0,   1'b0,   1'b0,  ls[7]} & {2'b00, {9{odd}}};
        2'd1: cyc43c_logsinrom_addend1 = {  1'b0,   1'b0,   1'b0,   1'b0,   1'b0,   1'b0,   1'b0,   1'b0,   1'b0, ls[10],  ls[6]} & {2'b00, {9{odd}}};
        2'd2: cyc43c_logsinrom_addend1 = {  1'b0,   1'b0,   1'b0,   1'b0,   1'b0,   1'b0,   1'b0,   1'b0, ls[20],  ls[9],  ls[5]} & {2'b00, {9{odd}}};
        2'd3: cyc43c_logsinrom_addend1 = {  1'b0,   1'b0, ls[39], ls[39], ls[38], ls[31], ls[30], ls[21], ls[19],  ls[8],  ls[4]} & {2'b00, {9{odd}}};
    endcase 
end


//
//  register part
//

reg     [11:0]  cyc43r_logsin_raw;
reg             cyc43r_level_fp_sign;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd126: begin
                    cyc43r_logsin_raw[8:0] <= i_SS_WDATA[31:23];
                end
                8'd127: begin
                    cyc43r_logsin_raw[11:9] <= i_SS_WDATA[2:0];
                    cyc43r_level_fp_sign <= i_SS_WDATA[3];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc43r_logsin_raw <= cyc43c_logsinrom_addend0 + cyc43c_logsinrom_addend1;
            cyc43r_level_fp_sign <= cyc42r_level_fp_sign;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 44: Apply attenuation level
////

//
//  register part
//

reg     [12:0]  cyc44r_logsin_attenuated;
reg             cyc44r_level_fp_sign;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd127: begin
                    cyc44r_logsin_attenuated <= i_SS_WDATA[16:4];
                    cyc44r_level_fp_sign <= i_SS_WDATA[17];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc44r_logsin_attenuated <= cyc43r_logsin_raw + {i_OP_ATTENLEVEL, 2'b00};
            cyc44r_level_fp_sign <= cyc43r_level_fp_sign;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 45: Saturation
////

//
//  register part
//

reg     [11:0]  cyc45r_logsin_saturated;
reg             cyc45r_level_fp_sign;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd127: begin
                    cyc45r_logsin_saturated <= i_SS_WDATA[29:18];
                    cyc45r_level_fp_sign <= i_SS_WDATA[30];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc45r_logsin_saturated <= cyc44r_logsin_attenuated[12] ? 12'd4095 : cyc44r_logsin_attenuated[11:0]; //discard carry
            cyc45r_level_fp_sign <= cyc44r_level_fp_sign;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 46: Get data from exp ROM
////

//
//  register part
//

wire    [44:0]  cyc46r_exprom_out;
cavebanpresto_ikaopm_ss_exprom #(.SS_BASE_BIT(13'd4315)) u_cyc46r_exprom (
    .i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_ADDR(cyc45r_logsin_saturated[5:1]), .o_DATA(cyc46r_exprom_out)

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_cyc46r_exprom_valid_mask),
    .o_SS_ACK        (ss_u_cyc46r_exprom_ack),
    .o_SS_ERROR      (ss_u_cyc46r_exprom_error),
    .o_SS_RDATA      (ss_u_cyc46r_exprom_rdata)
);

reg             cyc46r_logsin_even;
reg     [1:0]   cyc46r_exprom_bitsel;
reg     [3:0]   cyc46r_level_fp_exp;
reg             cyc46r_level_fp_sign;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd127: begin
                    cyc46r_logsin_even <= i_SS_WDATA[31];
                end
                8'd128: begin
                    cyc46r_exprom_bitsel <= i_SS_WDATA[1:0];
                    cyc46r_level_fp_exp <= i_SS_WDATA[5:2];
                    cyc46r_level_fp_sign <= i_SS_WDATA[6];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc46r_logsin_even <= ~cyc45r_logsin_saturated[0]; //inverted!! EVEN flag!!
            cyc46r_exprom_bitsel <= cyc45r_logsin_saturated[7:6];
            cyc46r_level_fp_exp <= ~cyc45r_logsin_saturated[11:8]; //invert
            cyc46r_level_fp_sign <= cyc45r_level_fp_sign;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 47: Choose bits from exp ROM and add them
////

//
//  combinational part
//

wire    [44:0]  e = cyc46r_exprom_out; //alias signal
wire            even = cyc46r_logsin_even; //alias signal

reg     [9:0]  cyc47c_exprom_addend0, cyc47c_exprom_addend1;
always @(*) begin
    case(cyc46r_exprom_bitsel)
        /*                                 D9      D8      D7      D6      D5      D4      D3      D2      D1     D0  */
        2'd0: cyc47c_exprom_addend0 = {  1'b1,  e[43],  e[40],  e[36],  e[32],  e[28],  e[24],  e[18],  e[14],   e[3]};
        2'd1: cyc47c_exprom_addend0 = { e[44],  e[42],  e[39],  e[35],  e[31],  e[27],  e[23],  e[17],  e[13],   e[2]};
        2'd2: cyc47c_exprom_addend0 = {  1'b0,  e[41],  e[38],  e[34],  e[30],  e[26],  e[22],  e[16],  e[12],   e[1]};
        2'd3: cyc47c_exprom_addend0 = {  1'b0,   1'b0,  e[37],  e[33],  e[29],  e[25],  e[21],  e[15],  e[11],   e[0]};
    endcase

    case(cyc46r_exprom_bitsel)
        /*                                 D9      D8      D7      D6      D5      D4      D3      D2      D1      D0  */
        2'd0: cyc47c_exprom_addend1 = {  1'b0,   1'b0,   1'b0,   1'b0,   1'b0,   1'b0,   1'b0,   1'b1,  e[10],   e[7]} & {7'b0000000, {3{even}}};
        2'd1: cyc47c_exprom_addend1 = {  1'b0,   1'b0,   1'b0,   1'b0,   1'b0,   1'b0,   1'b0,   1'b1,   1'b0,   e[6]} & {7'b0000000, {3{even}}};
        2'd2: cyc47c_exprom_addend1 = {  1'b0,   1'b0,   1'b0,   1'b0,   1'b0,   1'b0,   1'b0,  e[19],   e[9],   e[5]} & {7'b0000000, {3{even}}};
        2'd3: cyc47c_exprom_addend1 = {  1'b0,   1'b0,   1'b0,   1'b0,   1'b0,   1'b0,   1'b0,  e[20],   e[8],   e[4]} & {7'b0000000, {3{even}}};
    endcase 
end


//
//  register part
//

reg     [9:0]   cyc47r_level_fp_mant;
reg     [3:0]   cyc47r_level_fp_exp;
reg             cyc47r_level_fp_sign;
reg             cyc47r_level_negate;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd128: begin
                    cyc47r_level_fp_mant <= i_SS_WDATA[16:7];
                    cyc47r_level_fp_exp <= i_SS_WDATA[20:17];
                    cyc47r_level_fp_sign <= i_SS_WDATA[21];
                    cyc47r_level_negate <= i_SS_WDATA[22];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc47r_level_fp_mant <= cyc47c_exprom_addend0 + cyc47c_exprom_addend1; //discard carry
            cyc47r_level_fp_exp <= cyc46r_level_fp_exp;
            cyc47r_level_fp_sign <= cyc46r_level_fp_sign;
            cyc47r_level_negate <= i_TEST_D4;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 48: Floating point to integer
////

//
//  combinational part
//

reg     [12:0]  cyc48c_shifter0, cyc48c_shifter1;
always @(*) begin
    case(cyc47r_level_fp_exp[1:0])
        2'b00: cyc48c_shifter0 = {3'b000, 1'b1, cyc47r_level_fp_mant[9:1]};
        2'b01: cyc48c_shifter0 = {2'b00, 1'b1, cyc47r_level_fp_mant      };
        2'b10: cyc48c_shifter0 = {1'b0, 1'b1, cyc47r_level_fp_mant, 1'b0 };
        2'b11: cyc48c_shifter0 = {     1'b1, cyc47r_level_fp_mant, 2'b00 };
    endcase

    case(cyc47r_level_fp_exp[3:2])
        2'b00: cyc48c_shifter1 = {12'b0, cyc48c_shifter0[12]  };
        2'b01: cyc48c_shifter1 = { 8'b0, cyc48c_shifter0[12:8]};
        2'b10: cyc48c_shifter1 = { 4'b0, cyc48c_shifter0[12:4]};
        2'b11: cyc48c_shifter1 = cyc48c_shifter0;
    endcase
end

//
//  register part
//

reg             cyc48r_level_negate;
reg             cyc48r_level_sign;
reg     [12:0]  cyc48r_level_magnitude;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd128: begin
                    cyc48r_level_negate <= i_SS_WDATA[23];
                    cyc48r_level_sign <= i_SS_WDATA[24];
                    cyc48r_level_magnitude[6:0] <= i_SS_WDATA[31:25];
                end
                8'd129: begin
                    cyc48r_level_magnitude[12:7] <= i_SS_WDATA[5:0];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc48r_level_negate <= cyc47r_level_negate;
            cyc48r_level_sign <= cyc47r_level_fp_sign;
            cyc48r_level_magnitude <= cyc48c_shifter1;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 49: sign-magnitude to signed integer
////

//
//  register part
//

reg     [13:0]  cyc49r_level_signed;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd129: begin
                    cyc49r_level_signed <= i_SS_WDATA[19:6];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc49r_level_signed <= cyc48r_level_sign ? (~{cyc48r_level_negate, cyc48r_level_magnitude} + 14'd1) : 
                                                         {cyc48r_level_negate, cyc48r_level_magnitude};
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 50: delay
////

//
//  register part
//

reg     [13:0]  cyc50r_level_signed;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd129: begin
                    cyc50r_level_signed[11:0] <= i_SS_WDATA[31:20];
                end
                8'd130: begin
                    cyc50r_level_signed[13:12] <= i_SS_WDATA[1:0];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc50r_level_signed <= cyc49r_level_signed;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 51: delay
////

//
//  register part
//

reg     [13:0]  cyc51r_level_signed;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd130: begin
                    cyc51r_level_signed <= i_SS_WDATA[15:2];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc51r_level_signed <= cyc50r_level_signed;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 52: delay / latch algorithm type and state
////

//
//  register part
//

reg     [1:0]   cyc52r_algst;
reg     [2:0]   cyc52r_algtype;
reg     [13:0]  cyc52r_level_signed;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd130: begin
                    cyc52r_algst <= i_SS_WDATA[17:16];
                    cyc52r_algtype <= i_SS_WDATA[20:18];
                    cyc52r_level_signed[10:0] <= i_SS_WDATA[31:21];
                end
                8'd131: begin
                    cyc52r_level_signed[13:11] <= i_SS_WDATA[2:0];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc52r_algst <= algst_cntr; //algorithm state counter
            cyc52r_algtype <= i_ALG; //algorithm type

            cyc52r_level_signed <= cyc51r_level_signed;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 53: delay / Z reg / algorithm decoder
////

//
//  combinational part
//

assign  o_ACC_OPDATA = cyc52r_level_signed; //OP data output
reg             cyc53c_accumulation_en;
assign  o_ACC_SNDADD = cyc53c_accumulation_en;
always @(*) begin
    case(cyc52r_algst)
        2'd0: cyc53c_accumulation_en = cyc52r_algtype == 3'd7; //Add M1?
        2'd1: cyc53c_accumulation_en = cyc52r_algtype == 3'd7 || cyc52r_algtype == 3'd6 || cyc52r_algtype == 3'd5; //Add M2?
        2'd2: cyc53c_accumulation_en = cyc52r_algtype == 3'd7 || cyc52r_algtype == 3'd6 || cyc52r_algtype == 3'd5 || cyc52r_algtype == 3'd4; //Add C1?
        2'd3: cyc53c_accumulation_en = 1'b1; //Add C2?
    endcase
end


//
//  register part
//

//signed sound level
reg     [1:0]   cyc53r_algst;
reg     [2:0]   cyc53r_algtype;
reg     [13:0]  cyc53r_OP_current;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd131: begin
                    cyc53r_algst <= i_SS_WDATA[4:3];
                    cyc53r_algtype <= i_SS_WDATA[7:5];
                    cyc53r_OP_current <= i_SS_WDATA[21:8];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc53r_algst <= cyc52r_algst;
            cyc53r_algtype <= cyc52r_algtype;

            cyc53r_OP_current <= cyc52r_level_signed;
        end
    end
end


//Z registers that hold previous values
reg             cyc53r_M1_z_ld, cyc53r_M1_zz_ld; //store THIS M1 value, store PREVIOUS M1 value again
reg             cyc53r_C1_z_ld; //store THIS C1 value
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd131: begin
                    cyc53r_M1_z_ld <= i_SS_WDATA[22];
                    cyc53r_M1_zz_ld <= i_SS_WDATA[23];
                    cyc53r_C1_z_ld <= i_SS_WDATA[24];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc53r_M1_z_ld <= cyc52r_algst == 2'd0;
            cyc53r_M1_zz_ld <= cyc52r_algst == 2'd0;
            cyc53r_C1_z_ld <= cyc52r_algst == 2'd2;
        end
    end
end

wire    [13:0]  cyc53r_M1_z_reg_out, cyc53r_M1_zz_reg_out, cyc53r_C1_z_reg_out;
wire    [13:0]  cyc46c_M1_z_reg_in  = !mrst_n ? 14'd0 : 
                                                cyc53r_M1_z_ld ? cyc53r_OP_current: cyc53r_M1_z_reg_out;
wire    [13:0]  cyc46c_M1_zz_reg_in = !mrst_n ? 14'd0 : 
                                                cyc53r_M1_zz_ld ? cyc53r_M1_z_reg_out : cyc53r_M1_zz_reg_out;
wire    [13:0]  cyc46c_C1_z_reg_in  = !mrst_n ? 14'd0 : 
                                                cyc53r_C1_z_ld ? cyc53r_OP_current : cyc53r_C1_z_reg_out;

//stores THIS M1
cavebanpresto_ikaopm_ss_sr #(.SS_BASE_BIT(13'd4360), .WIDTH(14), .LENGTH(8), .TAP(8)) u_cyc46r_cyc53r_M1_z
(.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_D(cyc46c_M1_z_reg_in), .o_Q_TAP(), .o_Q_LAST(cyc53r_M1_z_reg_out)
,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_cyc46r_cyc53r_M1_z_valid_mask),
    .o_SS_ACK        (ss_u_cyc46r_cyc53r_M1_z_ack),
    .o_SS_ERROR      (ss_u_cyc46r_cyc53r_M1_z_error),
    .o_SS_RDATA      (ss_u_cyc46r_cyc53r_M1_z_rdata)
);

//stores PREVIOUS M1 again, this will be used for M1 self feedback calculation
cavebanpresto_ikaopm_ss_sr #(.SS_BASE_BIT(13'd4472), .WIDTH(14), .LENGTH(8), .TAP(8)) u_cyc46r_cyc53r_M1_zz
(.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_D(cyc46c_M1_zz_reg_in), .o_Q_TAP(), .o_Q_LAST(cyc53r_M1_zz_reg_out)
,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_cyc46r_cyc53r_M1_zz_valid_mask),
    .o_SS_ACK        (ss_u_cyc46r_cyc53r_M1_zz_ack),
    .o_SS_ERROR      (ss_u_cyc46r_cyc53r_M1_zz_error),
    .o_SS_RDATA      (ss_u_cyc46r_cyc53r_M1_zz_rdata)
);

//stores THIS C1
cavebanpresto_ikaopm_ss_sr #(.SS_BASE_BIT(13'd4584), .WIDTH(14), .LENGTH(8), .TAP(8)) u_cyc46r_cyc53r_C1_z
(.i_EMUCLK(i_EMUCLK), .i_CEN_n(phi1ncen_n), .i_D(cyc46c_C1_z_reg_in), .o_Q_TAP(), .o_Q_LAST(cyc53r_C1_z_reg_out)
,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_cyc46r_cyc53r_C1_z_valid_mask),
    .o_SS_ACK        (ss_u_cyc46r_cyc53r_C1_z_ack),
    .o_SS_ERROR      (ss_u_cyc46r_cyc53r_C1_z_error),
    .o_SS_RDATA      (ss_u_cyc46r_cyc53r_C1_z_rdata)
);

//misc control bits
reg             cyc53r_self_fdbk_en;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd131: begin
                    cyc53r_self_fdbk_en <= i_SS_WDATA[25];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc53r_self_fdbk_en <= cyc52r_algst == 2'd2;
        end
    end
end




///////////////////////////////////////////////////////////
//////  Cycle 54: select addend 0 and 1
////

//
//  register part
//

//make alias signals
wire    [13:0]  M1    = cyc53r_OP_current;
wire    [13:0]  M2    = cyc53r_OP_current;
wire    [13:0]  M1_z  = cyc53r_M1_z_reg_out;
wire    [13:0]  M1_zz = cyc53r_M1_zz_reg_out;
wire    [13:0]  C1_z  = cyc53r_C1_z_reg_out;

//selector
reg     [13:0]  cyc54r_op_addend0, cyc54r_op_addend1;
reg             cyc54r_self_fdbk_en;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd131: begin
                    cyc54r_op_addend0[5:0] <= i_SS_WDATA[31:26];
                end
                8'd132: begin
                    cyc54r_op_addend0[13:6] <= i_SS_WDATA[7:0];
                    cyc54r_op_addend1 <= i_SS_WDATA[21:8];
                    cyc54r_self_fdbk_en <= i_SS_WDATA[22];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            case({cyc53r_algtype, cyc53r_algst})
                //Algorithm 0
                5'b000_10: begin cyc54r_op_addend0 <= M1_z ; cyc54r_op_addend1 <= M1_zz; end //state 2
                5'b000_11: begin cyc54r_op_addend0 <= 14'd0; cyc54r_op_addend1 <= C1_z ; end //state 3
                5'b000_00: begin cyc54r_op_addend0 <= M1   ; cyc54r_op_addend1 <= 14'd0; end //state 0
                5'b000_01: begin cyc54r_op_addend0 <= M2   ; cyc54r_op_addend1 <= 14'd0; end //state 1
                
                //Algorithm 1
                5'b001_10: begin cyc54r_op_addend0 <= M1_z ; cyc54r_op_addend1 <= M1_zz; end //state 2
                5'b001_11: begin cyc54r_op_addend0 <= M1_z ; cyc54r_op_addend1 <= C1_z ; end //state 3
                5'b001_00: begin cyc54r_op_addend0 <= 14'd0; cyc54r_op_addend1 <= 14'd0; end //state 0
                5'b001_01: begin cyc54r_op_addend0 <= M2   ; cyc54r_op_addend1 <= 14'd0; end //state 1
                
                //Algorithm 2
                5'b010_10: begin cyc54r_op_addend0 <= M1_z ; cyc54r_op_addend1 <= M1_zz; end //state 2
                5'b010_11: begin cyc54r_op_addend0 <= 14'd0; cyc54r_op_addend1 <= C1_z ; end //state 3
                5'b010_00: begin cyc54r_op_addend0 <= 14'd0; cyc54r_op_addend1 <= 14'd0; end //state 0
                5'b010_01: begin cyc54r_op_addend0 <= M1_z ; cyc54r_op_addend1 <= M2   ; end //state 1
                
                //Algorithm 3
                5'b011_10: begin cyc54r_op_addend0 <= M1_z ; cyc54r_op_addend1 <= M1_zz; end //state 2
                5'b011_11: begin cyc54r_op_addend0 <= 14'd0; cyc54r_op_addend1 <= 14'd0; end //state 3
                5'b011_00: begin cyc54r_op_addend0 <= M1   ; cyc54r_op_addend1 <= 14'd0; end //state 0
                5'b011_01: begin cyc54r_op_addend0 <= M2   ; cyc54r_op_addend1 <= C1_z ; end //state 1
                
                //Algorithm 4
                5'b100_10: begin cyc54r_op_addend0 <= M1_z ; cyc54r_op_addend1 <= M1_zz; end //state 2
                5'b100_11: begin cyc54r_op_addend0 <= 14'd0; cyc54r_op_addend1 <= 14'd0; end //state 3
                5'b100_00: begin cyc54r_op_addend0 <= M1   ; cyc54r_op_addend1 <= 14'd0; end //state 0
                5'b100_01: begin cyc54r_op_addend0 <= M2   ; cyc54r_op_addend1 <= 14'd0; end //state 1
                
                //Algorithm 5
                5'b101_10: begin cyc54r_op_addend0 <= M1_z ; cyc54r_op_addend1 <= M1_zz; end //state 2
                5'b101_11: begin cyc54r_op_addend0 <= M1_z ; cyc54r_op_addend1 <= 14'd0; end //state 3
                5'b101_00: begin cyc54r_op_addend0 <= M1   ; cyc54r_op_addend1 <= 14'd0; end //state 0
                5'b101_01: begin cyc54r_op_addend0 <= M1_z ; cyc54r_op_addend1 <= 14'd0; end //state 1
                
                //Algorithm 6
                5'b110_10: begin cyc54r_op_addend0 <= M1_z ; cyc54r_op_addend1 <= M1_zz; end //state 2
                5'b110_11: begin cyc54r_op_addend0 <= 14'd0; cyc54r_op_addend1 <= 14'd0; end //state 3
                5'b110_00: begin cyc54r_op_addend0 <= M1   ; cyc54r_op_addend1 <= 14'd0; end //state 0
                5'b110_01: begin cyc54r_op_addend0 <= 14'd0; cyc54r_op_addend1 <= 14'd0; end //state 1
                
                //Algorithm 7
                5'b111_10: begin cyc54r_op_addend0 <= M1_z ; cyc54r_op_addend1 <= M1_zz; end //state 2
                5'b111_11: begin cyc54r_op_addend0 <= 14'd0; cyc54r_op_addend1 <= 14'd0; end //state 3
                5'b111_00: begin cyc54r_op_addend0 <= 14'd0; cyc54r_op_addend1 <= 14'd0; end //state 0
                5'b111_01: begin cyc54r_op_addend0 <= 14'd0; cyc54r_op_addend1 <= 14'd0; end //state 1
            endcase

            cyc54r_self_fdbk_en <= cyc53r_self_fdbk_en;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 55: sum two operator outputs
////

//
//  register part
//

reg             cyc55r_self_fdbk_en;
reg     [2:0]   cyc55r_fl;
reg     [14:0]  cyc55r_op_sum;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd132: begin
                    cyc55r_self_fdbk_en <= i_SS_WDATA[23];
                    cyc55r_fl <= i_SS_WDATA[26:24];
                    cyc55r_op_sum[4:0] <= i_SS_WDATA[31:27];
                end
                8'd133: begin
                    cyc55r_op_sum[14:5] <= i_SS_WDATA[9:0];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cyc55r_self_fdbk_en <= cyc54r_self_fdbk_en;
            cyc55r_fl <= cyc54r_self_fdbk_en ? i_FL : 3'd0;
            cyc55r_op_sum <= {cyc54r_op_addend0[13], cyc54r_op_addend0} + {cyc54r_op_addend1[13], cyc54r_op_addend1}; //add with sign extension, carry discarded
        end
    end
end



///////////////////////////////////////////////////////////
//////  Cycle 56: phase modulation value
////

//
//  register part
//

always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd126: begin
                    cyc56r_phasemod_value <= i_SS_WDATA[9:0];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            if(cyc55r_self_fdbk_en) begin
                case(cyc55r_fl)
                    3'd0: cyc56r_phasemod_value <= 10'd0;
                    3'd1: cyc56r_phasemod_value <= {{4{cyc55r_op_sum[14]}}, cyc55r_op_sum[14:9]};
                    3'd2: cyc56r_phasemod_value <= {{3{cyc55r_op_sum[14]}}, cyc55r_op_sum[14:8]};
                    3'd3: cyc56r_phasemod_value <= {{2{cyc55r_op_sum[14]}}, cyc55r_op_sum[14:7]};
                    3'd4: cyc56r_phasemod_value <= {{1{cyc55r_op_sum[14]}}, cyc55r_op_sum[14:6]};
                    3'd5: cyc56r_phasemod_value <= cyc55r_op_sum[14:5];
                    3'd6: cyc56r_phasemod_value <= cyc55r_op_sum[13:4];
                    3'd7: cyc56r_phasemod_value <= cyc55r_op_sum[12:3];
                endcase
            end
            else cyc56r_phasemod_value <= cyc55r_op_sum[10:1];
        end
    end
end


// CaveBanpresto exact-state word instrumentation.

always @(*) begin
    ss_local_valid_mask = 32'd0;
    ss_local_read_data = 32'd0;
    case (i_SS_WORD_ADDR)
        8'd126: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[9:0] = cyc56r_phasemod_value;
            ss_local_read_data[17:10] = cyc41r_logsinrom_phase;
            ss_local_read_data[18] = cyc41r_level_fp_sign;
            ss_local_read_data[19] = cyc42r_logsinrom_phase_odd;
            ss_local_read_data[21:20] = cyc42r_logsinrom_bitsel;
            ss_local_read_data[22] = cyc42r_level_fp_sign;
            ss_local_read_data[31:23] = cyc43r_logsin_raw[8:0];
        end
        8'd127: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[2:0] = cyc43r_logsin_raw[11:9];
            ss_local_read_data[3] = cyc43r_level_fp_sign;
            ss_local_read_data[16:4] = cyc44r_logsin_attenuated;
            ss_local_read_data[17] = cyc44r_level_fp_sign;
            ss_local_read_data[29:18] = cyc45r_logsin_saturated;
            ss_local_read_data[30] = cyc45r_level_fp_sign;
            ss_local_read_data[31] = cyc46r_logsin_even;
        end
        8'd128: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[1:0] = cyc46r_exprom_bitsel;
            ss_local_read_data[5:2] = cyc46r_level_fp_exp;
            ss_local_read_data[6] = cyc46r_level_fp_sign;
            ss_local_read_data[16:7] = cyc47r_level_fp_mant;
            ss_local_read_data[20:17] = cyc47r_level_fp_exp;
            ss_local_read_data[21] = cyc47r_level_fp_sign;
            ss_local_read_data[22] = cyc47r_level_negate;
            ss_local_read_data[23] = cyc48r_level_negate;
            ss_local_read_data[24] = cyc48r_level_sign;
            ss_local_read_data[31:25] = cyc48r_level_magnitude[6:0];
        end
        8'd129: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[5:0] = cyc48r_level_magnitude[12:7];
            ss_local_read_data[19:6] = cyc49r_level_signed;
            ss_local_read_data[31:20] = cyc50r_level_signed[11:0];
        end
        8'd130: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[1:0] = cyc50r_level_signed[13:12];
            ss_local_read_data[15:2] = cyc51r_level_signed;
            ss_local_read_data[17:16] = cyc52r_algst;
            ss_local_read_data[20:18] = cyc52r_algtype;
            ss_local_read_data[31:21] = cyc52r_level_signed[10:0];
        end
        8'd131: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[2:0] = cyc52r_level_signed[13:11];
            ss_local_read_data[4:3] = cyc53r_algst;
            ss_local_read_data[7:5] = cyc53r_algtype;
            ss_local_read_data[21:8] = cyc53r_OP_current;
            ss_local_read_data[22] = cyc53r_M1_z_ld;
            ss_local_read_data[23] = cyc53r_M1_zz_ld;
            ss_local_read_data[24] = cyc53r_C1_z_ld;
            ss_local_read_data[25] = cyc53r_self_fdbk_en;
            ss_local_read_data[31:26] = cyc54r_op_addend0[5:0];
        end
        8'd132: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[7:0] = cyc54r_op_addend0[13:6];
            ss_local_read_data[21:8] = cyc54r_op_addend1;
            ss_local_read_data[22] = cyc54r_self_fdbk_en;
            ss_local_read_data[23] = cyc55r_self_fdbk_en;
            ss_local_read_data[26:24] = cyc55r_fl;
            ss_local_read_data[31:27] = cyc55r_op_sum[4:0];
        end
        8'd133: begin
            ss_local_valid_mask = 32'h000003ff;
            ss_local_read_data[9:0] = cyc55r_op_sum[14:5];
        end
        default: ;
    endcase
end

assign ss_local_accept =
    i_SS_HOLD && i_SS_REQ && (|ss_local_valid_mask) && !ss_local_seen_q;
assign ss_local_write_accept = ss_local_accept && i_SS_WRITE;

always @(posedge i_EMUCLK) begin
    if (!i_SS_HOLD) begin
        ss_local_seen_q <= 1'b0;
        ss_local_ack_q <= 1'b0;
        ss_local_rdata_q <= 32'd0;
    end else begin
        ss_local_ack_q <= 1'b0;
        if (!i_SS_REQ)
            ss_local_seen_q <= 1'b0;
        if (ss_local_accept) begin
            ss_local_seen_q <= 1'b1;
            ss_local_ack_q <= 1'b1;
            ss_local_rdata_q <= ss_local_read_data;
        end
    end
end

assign o_SS_VALID_MASK = ss_local_valid_mask | ss_u_op_algst_cntr_valid_mask | ss_u_cyc42r_logsinrom_valid_mask | ss_u_cyc46r_exprom_valid_mask | ss_u_cyc46r_cyc53r_M1_z_valid_mask | ss_u_cyc46r_cyc53r_M1_zz_valid_mask | ss_u_cyc46r_cyc53r_C1_z_valid_mask;
assign o_SS_ACK = ss_local_ack_q | ss_u_op_algst_cntr_ack | ss_u_cyc42r_logsinrom_ack | ss_u_cyc46r_exprom_ack | ss_u_cyc46r_cyc53r_M1_z_ack | ss_u_cyc46r_cyc53r_M1_zz_ack | ss_u_cyc46r_cyc53r_C1_z_ack;
assign o_SS_ERROR = 1'b0 | ss_u_op_algst_cntr_error | ss_u_cyc42r_logsinrom_error | ss_u_cyc46r_exprom_error | ss_u_cyc46r_cyc53r_M1_z_error | ss_u_cyc46r_cyc53r_M1_zz_error | ss_u_cyc46r_cyc53r_C1_z_error;
assign o_SS_RDATA = (ss_local_rdata_q & ss_local_valid_mask) | (ss_u_op_algst_cntr_rdata & ss_u_op_algst_cntr_valid_mask) | (ss_u_cyc42r_logsinrom_rdata & ss_u_cyc42r_logsinrom_valid_mask) | (ss_u_cyc46r_exprom_rdata & ss_u_cyc46r_exprom_valid_mask) | (ss_u_cyc46r_cyc53r_M1_z_rdata & ss_u_cyc46r_cyc53r_M1_z_valid_mask) | (ss_u_cyc46r_cyc53r_M1_zz_rdata & ss_u_cyc46r_cyc53r_M1_zz_valid_mask) | (ss_u_cyc46r_cyc53r_C1_z_rdata & ss_u_cyc46r_cyc53r_C1_z_valid_mask);


endmodule

module cavebanpresto_ikaopm_ss_acc #(parameter integer SS_BASE_BIT = 4704) (
    //master clock
    input   wire            i_EMUCLK, //emulator master clock

    //core internal reset
    input   wire            i_MRST_n,

    //internal clock
    input   wire            i_phi1_PCEN_n, //positive edge clock enable for emulation
    input   wire            i_phi1_NCEN_n, //engative edge clock enable for emulation

    //timings
    input   wire            i_CYCLE_12,
    input   wire            i_CYCLE_29,
    input   wire            i_CYCLE_00_16,
    input   wire            i_CYCLE_06_22,
    input   wire            i_CYCLE_01_TO_16,

    //data
    input   wire            i_NE,
    input   wire    [1:0]   i_RL,

    input   wire            i_ACC_SNDADD,
    input   wire    [13:0]  i_ACC_OPDATA,
    input   wire    [13:0]  i_ACC_NOISE,

    output  reg             o_SO,
    
    output  reg             o_EMU_R_SAMPLE, o_EMU_L_SAMPLE,
    output  reg signed      [15:0]  o_EMU_R_EX, o_EMU_L_EX,
    output  reg signed      [15:0]  o_EMU_R, o_EMU_L

,
    input   wire            i_SS_HOLD,
    input   wire            i_SS_REQ,
    input   wire            i_SS_WRITE,
    input   wire    [7:0]   i_SS_WORD_ADDR,
    input   wire    [31:0]  i_SS_WDATA,
    output  wire    [31:0]  o_SS_VALID_MASK,
    output  wire            o_SS_ACK,
    output  wire            o_SS_ERROR,
    output  wire    [31:0]  o_SS_RDATA
);

// Forward declarations for exact-state instrumentation.
wire ss_local_write_accept;
wire ss_local_accept;
reg ss_local_seen_q;
reg ss_local_ack_q;
reg [31:0] ss_local_rdata_q;
reg [31:0] ss_local_valid_mask;
reg [31:0] ss_local_read_data;




///////////////////////////////////////////////////////////
//////  Clock and reset
////

wire            phi1ncen_n = i_phi1_NCEN_n;
wire            mrst_n = i_MRST_n;



///////////////////////////////////////////////////////////
//////  Cycle number
////

//additional cycle bits
reg             cycle_13, cycle_01_17, cycle_02_to_17;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd149: begin
                    cycle_13 <= i_SS_WDATA[3];
                    cycle_01_17 <= i_SS_WDATA[4];
                    cycle_02_to_17 <= i_SS_WDATA[5];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            cycle_13 <= i_CYCLE_12;
            cycle_01_17 <= i_CYCLE_00_16;
            cycle_02_to_17 <= i_CYCLE_01_TO_16;
        end
    end
end



///////////////////////////////////////////////////////////
//////  Sound input MUX / RL acc enable
////

//noise data will be launched at master cycle 12
reg     [13:0]  sound_inlatch;
reg             r_add, l_add;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd149: begin
                    sound_inlatch <= i_SS_WDATA[19:6];
                    r_add <= i_SS_WDATA[20];
                    l_add <= i_SS_WDATA[21];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            sound_inlatch <= (i_NE & i_CYCLE_12) ? i_ACC_NOISE : i_ACC_OPDATA;

            r_add <= i_ACC_SNDADD & i_RL[1];
            l_add <= i_ACC_SNDADD & i_RL[0];
        end
    end
end



///////////////////////////////////////////////////////////
//////  R/L channel accmulators
////

reg     [17:0]  r_accumulator, l_accumulator;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd149: begin
                    r_accumulator[9:0] <= i_SS_WDATA[31:22];
                end
                8'd150: begin
                    r_accumulator[17:10] <= i_SS_WDATA[7:0];
                    l_accumulator <= i_SS_WDATA[25:8];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            if(!mrst_n) begin
                r_accumulator <= 18'd0; //original chip doesn't have this reset
                l_accumulator <= 18'd0;
            end
            else begin
                if(cycle_13)   r_accumulator <= r_add ? {{4{sound_inlatch[13]}}, sound_inlatch}                 : 17'd0;         //reset
                else           r_accumulator <= r_add ? {{4{sound_inlatch[13]}}, sound_inlatch} + r_accumulator : r_accumulator; //accumulation

                if(i_CYCLE_29) l_accumulator <= l_add ? {{4{sound_inlatch[13]}}, sound_inlatch}                 : 17'd0;         //reset
                else           l_accumulator <= l_add ? {{4{sound_inlatch[13]}}, sound_inlatch} + l_accumulator : l_accumulator; //accumulation
            end
        end
    end
end



///////////////////////////////////////////////////////////
//////  R/L PISO register
////

/*
    Sign bit is inverted in this stage.
    11111...(positive max)
    10000...(positive min)
    01111...(negative min)
    00000...(negative max)
*/

reg     [15:0]  mcyc14_r_piso, mcyc30_l_piso;
reg     [2:0]   mcyc14_r_saturation_ctrl, mcyc30_l_saturation_ctrl;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd150: begin
                    mcyc14_r_piso[5:0] <= i_SS_WDATA[31:26];
                end
                8'd151: begin
                    mcyc14_r_piso[15:6] <= i_SS_WDATA[9:0];
                    mcyc30_l_piso <= i_SS_WDATA[25:10];
                    mcyc14_r_saturation_ctrl <= i_SS_WDATA[28:26];
                    mcyc30_l_saturation_ctrl <= i_SS_WDATA[31:29];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            if(cycle_13) begin
                mcyc14_r_piso <= {~r_accumulator[17], r_accumulator[14:0]}; //FLIP THE SIGN BIT!!
                mcyc14_r_saturation_ctrl <= r_accumulator[17:15];
            end
            else begin
                mcyc14_r_piso[14:0] <= mcyc14_r_piso[15:1]; //shift
            end

            if(i_CYCLE_29) begin
                mcyc30_l_piso <= {~l_accumulator[17], l_accumulator[14:0]}; //FLIP THE SIGN BIT!!
                mcyc30_l_saturation_ctrl <= l_accumulator[17:15];
            end
            else begin
                mcyc30_l_piso[14:0] <= mcyc30_l_piso[15:1]; //shift
            end
        end
    end
end



///////////////////////////////////////////////////////////
//////  Parallel output control
////

localparam  SAMPLE_STROBE_LENGTH = 1; //adjust this value to stretch the strobe width
reg     [SAMPLE_STROBE_LENGTH+1:0]   r_sample_det, l_sample_det;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd147: begin
                    o_EMU_R_SAMPLE <= i_SS_WDATA[1];
                    o_EMU_L_SAMPLE <= i_SS_WDATA[2];
                end
                8'd152: begin
                    r_sample_det <= i_SS_WDATA[2:0];
                    l_sample_det <= i_SS_WDATA[5:3];
                end
                default: ;
            endcase
        end
    end else begin
        begin
            if(!i_MRST_n) begin
                r_sample_det[0] <= 1'b0;
                l_sample_det[0] <= 1'b0;
            end
            else begin
                r_sample_det[0] <= cycle_13;
                l_sample_det[0] <= i_CYCLE_29;
            end

            r_sample_det[SAMPLE_STROBE_LENGTH+1:1] <= r_sample_det[SAMPLE_STROBE_LENGTH:0];
            l_sample_det[SAMPLE_STROBE_LENGTH+1:1] <= l_sample_det[SAMPLE_STROBE_LENGTH:0];

            //negative edge detector + pulse stretcher
            o_EMU_R_SAMPLE <= {|{r_sample_det[SAMPLE_STROBE_LENGTH+1:2]}, r_sample_det[1]} == 2'b10;
            o_EMU_L_SAMPLE <= {|{l_sample_det[SAMPLE_STROBE_LENGTH+1:2]}, l_sample_det[1]} == 2'b10;
        end
    end
end


reg signed  [15:0]  r_parallel, l_parallel, r_parallel_extended, l_parallel_extended; //parallel output intermediate storage
reg         [2:0]   r_parallel_saturation_ctrl, l_parallel_saturation_ctrl; //parallel output saturation control
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd152: begin
                    r_parallel <= i_SS_WDATA[21:6];
                    l_parallel[9:0] <= i_SS_WDATA[31:22];
                end
                8'd153: begin
                    l_parallel[15:10] <= i_SS_WDATA[5:0];
                    r_parallel_extended <= i_SS_WDATA[21:6];
                    l_parallel_extended[9:0] <= i_SS_WDATA[31:22];
                end
                8'd154: begin
                    l_parallel_extended[15:10] <= i_SS_WDATA[5:0];
                    r_parallel_saturation_ctrl <= i_SS_WDATA[8:6];
                    l_parallel_saturation_ctrl <= i_SS_WDATA[11:9];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            if(!i_MRST_n) begin
                r_parallel_saturation_ctrl <= 3'b000;
                r_parallel_extended <= 16'sd0;
                r_parallel <= 16'sd0;

                l_parallel_saturation_ctrl <= 3'b000;
                l_parallel_extended <= 16'sd0;
                l_parallel <= 16'sd0;
            end
            else begin
                if(cycle_13) begin
                    r_parallel_saturation_ctrl <= r_accumulator[17:15];
                    r_parallel_extended <= {r_accumulator[17], r_accumulator[14:0]}; //extended output, sign bit + least important 15 bits

                    casez(r_accumulator[14:9] ^ {6{r_accumulator[17]}})
                        6'b000000: r_parallel <= {r_accumulator[17], r_accumulator[14:6], r_accumulator[5:0]}; //small number
                        6'b000001: r_parallel <= {r_accumulator[17], r_accumulator[14:6], r_accumulator[17] ? r_accumulator[5:0] | 6'b000001 : r_accumulator[5:0] & 6'b111110};
                        6'b00001?: r_parallel <= {r_accumulator[17], r_accumulator[14:6], r_accumulator[17] ? r_accumulator[5:0] | 6'b000011 : r_accumulator[5:0] & 6'b111100};
                        6'b0001??: r_parallel <= {r_accumulator[17], r_accumulator[14:6], r_accumulator[17] ? r_accumulator[5:0] | 6'b000111 : r_accumulator[5:0] & 6'b111000};
                        6'b001???: r_parallel <= {r_accumulator[17], r_accumulator[14:6], r_accumulator[17] ? r_accumulator[5:0] | 6'b001111 : r_accumulator[5:0] & 6'b110000};
                        6'b01????: r_parallel <= {r_accumulator[17], r_accumulator[14:6], r_accumulator[17] ? r_accumulator[5:0] | 6'b011111 : r_accumulator[5:0] & 6'b100000};
                        6'b1?????: r_parallel <= {r_accumulator[17], r_accumulator[14:6], r_accumulator[17] ? r_accumulator[5:0] | 6'b111111 : r_accumulator[5:0] & 6'b000000}; //large number
                        
                        default:   r_parallel <= {r_accumulator[17], r_accumulator[14:6], r_accumulator[5:0]};
                    endcase
                end
                if(i_CYCLE_29) begin
                    l_parallel_saturation_ctrl <= l_accumulator[17:15];
                    l_parallel_extended <= {l_accumulator[17], l_accumulator[14:0]}; //extended output, sign bit + least important 15 bits

                    casez(l_accumulator[14:9] ^ {6{l_accumulator[17]}})
                        6'b000000: l_parallel <= {l_accumulator[17], l_accumulator[14:6], l_accumulator[5:0]}; //small number
                        6'b000001: l_parallel <= {l_accumulator[17], l_accumulator[14:6], l_accumulator[17] ? l_accumulator[5:0] | 6'b000001 : l_accumulator[5:0] & 6'b111110};
                        6'b00001?: l_parallel <= {l_accumulator[17], l_accumulator[14:6], l_accumulator[17] ? l_accumulator[5:0] | 6'b000011 : l_accumulator[5:0] & 6'b111100};
                        6'b0001??: l_parallel <= {l_accumulator[17], l_accumulator[14:6], l_accumulator[17] ? l_accumulator[5:0] | 6'b000111 : l_accumulator[5:0] & 6'b111000};
                        6'b001???: l_parallel <= {l_accumulator[17], l_accumulator[14:6], l_accumulator[17] ? l_accumulator[5:0] | 6'b001111 : l_accumulator[5:0] & 6'b110000};
                        6'b01????: l_parallel <= {l_accumulator[17], l_accumulator[14:6], l_accumulator[17] ? l_accumulator[5:0] | 6'b011111 : l_accumulator[5:0] & 6'b100000};
                        6'b1?????: l_parallel <= {l_accumulator[17], l_accumulator[14:6], l_accumulator[17] ? l_accumulator[5:0] | 6'b111111 : l_accumulator[5:0] & 6'b000000}; //large number
                        
                        default:   l_parallel <= {l_accumulator[17], l_accumulator[14:6], l_accumulator[5:0]};
                    endcase
                end
            end
        end
    end
end

always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd147: begin
                    o_EMU_R_EX <= i_SS_WDATA[18:3];
                    o_EMU_L_EX[12:0] <= i_SS_WDATA[31:19];
                end
                8'd148: begin
                    o_EMU_L_EX[15:13] <= i_SS_WDATA[2:0];
                    o_EMU_R <= i_SS_WDATA[18:3];
                    o_EMU_L[12:0] <= i_SS_WDATA[31:19];
                end
                8'd149: begin
                    o_EMU_L[15:13] <= i_SS_WDATA[2:0];
                end
                default: ;
            endcase
        end
    end else begin
        begin
            if(!i_MRST_n) begin
                o_EMU_R <= 16'sd0;
                o_EMU_R_EX <= 16'sd0;
                o_EMU_L <= 16'sd0;
                o_EMU_L_EX <= 16'sd0;
            end
            else begin
                case(r_parallel_saturation_ctrl)
                    3'b000: begin o_EMU_R <= r_parallel; o_EMU_R_EX <= r_parallel_extended; end
                    3'b001: begin o_EMU_R <= 16'h7FFF;   o_EMU_R_EX <= 16'h7FFF; end //saturated to positive maximum
                    3'b010: begin o_EMU_R <= 16'h7FFF;   o_EMU_R_EX <= 16'h7FFF; end
                    3'b011: begin o_EMU_R <= 16'h7FFF;   o_EMU_R_EX <= 16'h7FFF; end
                    3'b100: begin o_EMU_R <= 16'h8000;   o_EMU_R_EX <= 16'h8000; end //saturated to negative maximum
                    3'b101: begin o_EMU_R <= 16'h8000;   o_EMU_R_EX <= 16'h8000; end
                    3'b110: begin o_EMU_R <= 16'h8000;   o_EMU_R_EX <= 16'h8000; end
                    3'b111: begin o_EMU_R <= r_parallel; o_EMU_R_EX <= r_parallel_extended; end
                endcase

                case(l_parallel_saturation_ctrl)
                    3'b000: begin o_EMU_L <= l_parallel; o_EMU_L_EX <= l_parallel_extended; end
                    3'b001: begin o_EMU_L <= 16'h7FFF;   o_EMU_L_EX <= 16'h7FFF; end //saturated to positive maximum
                    3'b010: begin o_EMU_L <= 16'h7FFF;   o_EMU_L_EX <= 16'h7FFF; end
                    3'b011: begin o_EMU_L <= 16'h7FFF;   o_EMU_L_EX <= 16'h7FFF; end
                    3'b100: begin o_EMU_L <= 16'h8000;   o_EMU_L_EX <= 16'h8000; end //saturated to negative maximum
                    3'b101: begin o_EMU_L <= 16'h8000;   o_EMU_L_EX <= 16'h8000; end
                    3'b110: begin o_EMU_L <= 16'h8000;   o_EMU_L_EX <= 16'h8000; end
                    3'b111: begin o_EMU_L <= l_parallel; o_EMU_L_EX <= l_parallel_extended; end
                endcase
            end
        end
    end
end



///////////////////////////////////////////////////////////
//////  R/L Saturation control
////

reg             mcyc15_r_stream, mcyc31_l_stream;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd154: begin
                    mcyc15_r_stream <= i_SS_WDATA[12];
                    mcyc31_l_stream <= i_SS_WDATA[13];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            case(mcyc14_r_saturation_ctrl)
                3'b000: mcyc15_r_stream <= mcyc14_r_piso[0];
                3'b001: mcyc15_r_stream <= 1'b1; //saturated to positive maximum
                3'b010: mcyc15_r_stream <= 1'b1;
                3'b011: mcyc15_r_stream <= 1'b1;
                3'b100: mcyc15_r_stream <= 1'b0; //saturated to negative maximum
                3'b101: mcyc15_r_stream <= 1'b0;
                3'b110: mcyc15_r_stream <= 1'b0;
                3'b111: mcyc15_r_stream <= mcyc14_r_piso[0];
            endcase

            case(mcyc30_l_saturation_ctrl)
                3'b000: mcyc31_l_stream <= mcyc30_l_piso[0];
                3'b001: mcyc31_l_stream <= 1'b1; //saturated to positive maximum
                3'b010: mcyc31_l_stream <= 1'b1;
                3'b011: mcyc31_l_stream <= 1'b1;
                3'b100: mcyc31_l_stream <= 1'b0; //saturated to negative maximum
                3'b101: mcyc31_l_stream <= 1'b0;
                3'b110: mcyc31_l_stream <= 1'b0;
                3'b111: mcyc31_l_stream <= mcyc30_l_piso[0];
            endcase
        end
    end
end



///////////////////////////////////////////////////////////
//////  Delays
////

reg             mcyc16_r_stream_z, mcyc17_r_stream_zz, mcyc18_r_stream_zzz;
reg             mcyc00_l_stream_z, mcyc01_l_stream_zz, mcyc02_l_stream_zzz;

always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd154: begin
                    mcyc16_r_stream_z <= i_SS_WDATA[14];
                    mcyc17_r_stream_zz <= i_SS_WDATA[15];
                    mcyc18_r_stream_zzz <= i_SS_WDATA[16];
                    mcyc00_l_stream_z <= i_SS_WDATA[17];
                    mcyc01_l_stream_zz <= i_SS_WDATA[18];
                    mcyc02_l_stream_zzz <= i_SS_WDATA[19];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            mcyc16_r_stream_z <= mcyc15_r_stream;
            mcyc00_l_stream_z <= mcyc31_l_stream;
            mcyc17_r_stream_zz <= mcyc16_r_stream_z;
            mcyc01_l_stream_zz <= mcyc00_l_stream_z;
            mcyc18_r_stream_zzz <= mcyc17_r_stream_zz;
            mcyc02_l_stream_zzz <= mcyc01_l_stream_zz;
        end
    end
end



///////////////////////////////////////////////////////////
//////  SIPO/SO register
////

wire            sound_data_lookaround_register_input_stream = cycle_02_to_17 ? mcyc02_l_stream_zzz : mcyc18_r_stream_zzz;
reg     [20:0]  sound_data_lookaround_register;
reg     [6:0]   sound_data_bit_15_9;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd154: begin
                    sound_data_lookaround_register[11:0] <= i_SS_WDATA[31:20];
                end
                8'd155: begin
                    sound_data_lookaround_register[20:12] <= i_SS_WDATA[8:0];
                    sound_data_bit_15_9 <= i_SS_WDATA[15:9];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            //The LSB of serial sound data is placed on the MSB of lookaround register if(master cycle == 17 || 1). It flows in from the LSB.
            sound_data_lookaround_register[20] <= sound_data_lookaround_register_input_stream; //sound data LSB is latched at (master cycle == 18)
            sound_data_lookaround_register[19:0] <= sound_data_lookaround_register[20:1];

            if(cycle_01_17) sound_data_bit_15_9 <= {sound_data_lookaround_register_input_stream, sound_data_lookaround_register[20:15]};
        end
    end
end



///////////////////////////////////////////////////////////
//////  Output MUX
////

//original chip used shift register to select bits
reg     [3:0]   outmux_sel_cntr;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd155: begin
                    outmux_sel_cntr <= i_SS_WDATA[19:16];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            if(i_CYCLE_06_22) outmux_sel_cntr <= 4'd1;
            else outmux_sel_cntr <= (outmux_sel_cntr == 4'd15) ? 4'd0 : outmux_sel_cntr + 4'd1;
        end
    end
end

//sound data magnitude
/*
    Invert the upper bits when the number is negative.
    11111...(positive max)
    10000...(positive min)
    00000...(negative min)
    01111...(negative max)
*/
wire    [5:0]   sound_data_magnitude = sound_data_bit_15_9[6] ? sound_data_bit_15_9[5:0] : ~sound_data_bit_15_9[5:0];
reg             sound_data_sign;
reg     [2:0]   sound_data_shift_amount;
reg     [4:0]   sound_data_output_tap;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd155: begin
                    sound_data_sign <= i_SS_WDATA[20];
                    sound_data_shift_amount <= i_SS_WDATA[23:21];
                    sound_data_output_tap <= i_SS_WDATA[28:24];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            if(i_CYCLE_06_22) begin
                sound_data_sign <= sound_data_bit_15_9[6];

                casez(sound_data_magnitude)
                    6'b000000: begin sound_data_output_tap <= 5'd0; sound_data_shift_amount <= 3'd1; end //small number
                    6'b000001: begin sound_data_output_tap <= 5'd1; sound_data_shift_amount <= 3'd2; end
                    6'b00001?: begin sound_data_output_tap <= 5'd2; sound_data_shift_amount <= 3'd3; end
                    6'b0001??: begin sound_data_output_tap <= 5'd3; sound_data_shift_amount <= 3'd4; end
                    6'b001???: begin sound_data_output_tap <= 5'd4; sound_data_shift_amount <= 3'd5; end
                    6'b01????: begin sound_data_output_tap <= 5'd5; sound_data_shift_amount <= 3'd6; end
                    6'b1?????: begin sound_data_output_tap <= 5'd6; sound_data_shift_amount <= 3'd7; end //large number
                    
                    default:   begin sound_data_output_tap <= 5'd0; sound_data_shift_amount <= 3'd1; end
                endcase
            end
        end
    end
end

reg             floating_sound_data;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd147: begin
                    o_SO <= i_SS_WDATA[0];
                end
                8'd155: begin
                    floating_sound_data <= i_SS_WDATA[29];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            if(outmux_sel_cntr >= 4'd1 && outmux_sel_cntr < 4'd10)  floating_sound_data <= sound_data_lookaround_register[sound_data_output_tap];
            else if(outmux_sel_cntr == 4'd10)                       floating_sound_data <= sound_data_sign;
            else if(outmux_sel_cntr == 4'd11)                       floating_sound_data <= sound_data_shift_amount[0];
            else if(outmux_sel_cntr == 4'd12)                       floating_sound_data <= sound_data_shift_amount[1];
            else if(outmux_sel_cntr == 4'd13)                       floating_sound_data <= sound_data_shift_amount[2];
            else                                                    floating_sound_data <= sound_data_lookaround_register[sound_data_output_tap];

            o_SO <= floating_sound_data;
        end
    end
end


// CaveBanpresto exact-state word instrumentation.

always @(*) begin
    ss_local_valid_mask = 32'd0;
    ss_local_read_data = 32'd0;
    case (i_SS_WORD_ADDR)
        8'd147: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[0] = o_SO;
            ss_local_read_data[1] = o_EMU_R_SAMPLE;
            ss_local_read_data[2] = o_EMU_L_SAMPLE;
            ss_local_read_data[18:3] = o_EMU_R_EX;
            ss_local_read_data[31:19] = o_EMU_L_EX[12:0];
        end
        8'd148: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[2:0] = o_EMU_L_EX[15:13];
            ss_local_read_data[18:3] = o_EMU_R;
            ss_local_read_data[31:19] = o_EMU_L[12:0];
        end
        8'd149: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[2:0] = o_EMU_L[15:13];
            ss_local_read_data[3] = cycle_13;
            ss_local_read_data[4] = cycle_01_17;
            ss_local_read_data[5] = cycle_02_to_17;
            ss_local_read_data[19:6] = sound_inlatch;
            ss_local_read_data[20] = r_add;
            ss_local_read_data[21] = l_add;
            ss_local_read_data[31:22] = r_accumulator[9:0];
        end
        8'd150: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[7:0] = r_accumulator[17:10];
            ss_local_read_data[25:8] = l_accumulator;
            ss_local_read_data[31:26] = mcyc14_r_piso[5:0];
        end
        8'd151: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[9:0] = mcyc14_r_piso[15:6];
            ss_local_read_data[25:10] = mcyc30_l_piso;
            ss_local_read_data[28:26] = mcyc14_r_saturation_ctrl;
            ss_local_read_data[31:29] = mcyc30_l_saturation_ctrl;
        end
        8'd152: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[2:0] = r_sample_det;
            ss_local_read_data[5:3] = l_sample_det;
            ss_local_read_data[21:6] = r_parallel;
            ss_local_read_data[31:22] = l_parallel[9:0];
        end
        8'd153: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[5:0] = l_parallel[15:10];
            ss_local_read_data[21:6] = r_parallel_extended;
            ss_local_read_data[31:22] = l_parallel_extended[9:0];
        end
        8'd154: begin
            ss_local_valid_mask = 32'hffffffff;
            ss_local_read_data[5:0] = l_parallel_extended[15:10];
            ss_local_read_data[8:6] = r_parallel_saturation_ctrl;
            ss_local_read_data[11:9] = l_parallel_saturation_ctrl;
            ss_local_read_data[12] = mcyc15_r_stream;
            ss_local_read_data[13] = mcyc31_l_stream;
            ss_local_read_data[14] = mcyc16_r_stream_z;
            ss_local_read_data[15] = mcyc17_r_stream_zz;
            ss_local_read_data[16] = mcyc18_r_stream_zzz;
            ss_local_read_data[17] = mcyc00_l_stream_z;
            ss_local_read_data[18] = mcyc01_l_stream_zz;
            ss_local_read_data[19] = mcyc02_l_stream_zzz;
            ss_local_read_data[31:20] = sound_data_lookaround_register[11:0];
        end
        8'd155: begin
            ss_local_valid_mask = 32'h3fffffff;
            ss_local_read_data[8:0] = sound_data_lookaround_register[20:12];
            ss_local_read_data[15:9] = sound_data_bit_15_9;
            ss_local_read_data[19:16] = outmux_sel_cntr;
            ss_local_read_data[20] = sound_data_sign;
            ss_local_read_data[23:21] = sound_data_shift_amount;
            ss_local_read_data[28:24] = sound_data_output_tap;
            ss_local_read_data[29] = floating_sound_data;
        end
        default: ;
    endcase
end

assign ss_local_accept =
    i_SS_HOLD && i_SS_REQ && (|ss_local_valid_mask) && !ss_local_seen_q;
assign ss_local_write_accept = ss_local_accept && i_SS_WRITE;

always @(posedge i_EMUCLK) begin
    if (!i_SS_HOLD) begin
        ss_local_seen_q <= 1'b0;
        ss_local_ack_q <= 1'b0;
        ss_local_rdata_q <= 32'd0;
    end else begin
        ss_local_ack_q <= 1'b0;
        if (!i_SS_REQ)
            ss_local_seen_q <= 1'b0;
        if (ss_local_accept) begin
            ss_local_seen_q <= 1'b1;
            ss_local_ack_q <= 1'b1;
            ss_local_rdata_q <= ss_local_read_data;
        end
    end
end

assign o_SS_VALID_MASK = ss_local_valid_mask;
assign o_SS_ACK = ss_local_ack_q;
assign o_SS_ERROR = 1'b0;
assign o_SS_RDATA = (ss_local_rdata_q & ss_local_valid_mask);


endmodule

module cavebanpresto_ikaopm_ss_timer #(parameter integer SS_BASE_BIT = 4992) (
    //master clock
    input   wire            i_EMUCLK, //emulator master clock

    //core internal reset
    input   wire            i_MRST_n,

    //internal clock
    input   wire            i_phi1_PCEN_n, //positive edge clock enable for emulation
    input   wire            i_phi1_NCEN_n, //negative edge clock enable for emulation

    //timings
    input   wire            i_CYCLE_31,

    //control input
    input   wire    [7:0]   i_CLKA1,
    input   wire    [1:0]   i_CLKA2,
    input   wire    [7:0]   i_CLKB,
    input   wire            i_TIMERA_RUN,
    input   wire            i_TIMERB_RUN,
    input   wire            i_TIMERA_IRQ_EN,
    input   wire            i_TIMERB_IRQ_EN,
    input   wire            i_TIMERA_FRST,
    input   wire            i_TIMERB_FRST,
    input   wire            i_TEST_D2, //test register

    //timer output
    output  wire            o_TIMERA_OVFL,
    output  reg             o_TIMERA_FLAG,
    output  reg             o_TIMERB_FLAG,
    output  reg             o_IRQ_n

,
    input   wire            i_SS_HOLD,
    input   wire            i_SS_REQ,
    input   wire            i_SS_WRITE,
    input   wire    [7:0]   i_SS_WORD_ADDR,
    input   wire    [31:0]  i_SS_WDATA,
    output  wire    [31:0]  o_SS_VALID_MASK,
    output  wire            o_SS_ACK,
    output  wire            o_SS_ERROR,
    output  wire    [31:0]  o_SS_RDATA
);

// Forward declarations for exact-state instrumentation.
wire ss_local_write_accept;
wire ss_local_accept;
reg ss_local_seen_q;
reg ss_local_ack_q;
reg [31:0] ss_local_rdata_q;
reg [31:0] ss_local_valid_mask;
reg [31:0] ss_local_read_data;
wire [31:0] ss_u_timera_valid_mask;
wire ss_u_timera_ack;
wire ss_u_timera_error;
wire [31:0] ss_u_timera_rdata;
wire [31:0] ss_u_timerb_prescaler_valid_mask;
wire ss_u_timerb_prescaler_ack;
wire ss_u_timerb_prescaler_error;
wire [31:0] ss_u_timerb_prescaler_rdata;
wire [31:0] ss_u_timerb_valid_mask;
wire ss_u_timerb_ack;
wire ss_u_timerb_error;
wire [31:0] ss_u_timerb_rdata;




///////////////////////////////////////////////////////////
//////  Clock and reset
////

wire            phi1pcen_n = i_phi1_PCEN_n;
wire            phi1ncen_n = i_phi1_NCEN_n;
wire            mrst_n = i_MRST_n;



///////////////////////////////////////////////////////////
//////  Timer A
////

reg             timera_cnt, timera_ld, timera_rst, timera_ovfl_z;
wire            timera_ovfl;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd156: begin
                    timera_cnt <= i_SS_WDATA[3];
                    timera_ld <= i_SS_WDATA[4];
                    timera_rst <= i_SS_WDATA[5];
                    timera_ovfl_z <= i_SS_WDATA[6];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            timera_cnt <= (i_CYCLE_31 & i_TIMERA_RUN) | i_TEST_D2;
            timera_ld  <= (i_TIMERA_RUN & timera_rst) | timera_ovfl_z; //run reg postive edge detector
            timera_rst <= ~i_TIMERA_RUN;

            timera_ovfl_z <= timera_ovfl;
        end
    end
end

cavebanpresto_ikaopm_ss_counter #(.SS_BASE_BIT(13'd5005), .WIDTH(10)) u_timera (
    .i_EMUCLK(i_EMUCLK), .i_PCEN_n(phi1pcen_n), .i_NCEN_n(phi1ncen_n),
    .i_CNT(timera_cnt), .i_LD(timera_ld), .i_RST(~mrst_n | timera_rst),
    .i_D({i_CLKA1, i_CLKA2}), .o_Q(), .o_CO(timera_ovfl)

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_timera_valid_mask),
    .o_SS_ACK        (ss_u_timera_ack),
    .o_SS_ERROR      (ss_u_timera_error),
    .o_SS_RDATA      (ss_u_timera_rdata)
);

assign  o_TIMERA_OVFL = timera_ld; //for CSM



///////////////////////////////////////////////////////////
//////  Timer B
////

//Prescaler
reg             timerb_prescaler_cnt, timerb_prescaler_ovfl_z;
wire            timerb_prescaler_ovfl;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd156: begin
                    timerb_prescaler_cnt <= i_SS_WDATA[7];
                    timerb_prescaler_ovfl_z <= i_SS_WDATA[8];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            timerb_prescaler_ovfl_z <= timerb_prescaler_ovfl; //save carry

            timerb_prescaler_cnt <= i_CYCLE_31;
        end
    end
end

cavebanpresto_ikaopm_ss_counter #(.SS_BASE_BIT(13'd5016), .WIDTH(4)) u_timerb_prescaler (
    .i_EMUCLK(i_EMUCLK), .i_PCEN_n(phi1pcen_n), .i_NCEN_n(phi1ncen_n),
    .i_CNT(timerb_prescaler_cnt), .i_LD(1'b0), .i_RST(~mrst_n),
    .i_D(4'd0), .o_Q(), .o_CO(timerb_prescaler_ovfl)

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_timerb_prescaler_valid_mask),
    .o_SS_ACK        (ss_u_timerb_prescaler_ack),
    .o_SS_ERROR      (ss_u_timerb_prescaler_error),
    .o_SS_RDATA      (ss_u_timerb_prescaler_rdata)
);

//Timer B
reg             timerb_cnt, timerb_ld, timerb_rst, timerb_ovfl_z;
wire            timerb_ovfl;
always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd156: begin
                    timerb_cnt <= i_SS_WDATA[9];
                    timerb_ld <= i_SS_WDATA[10];
                    timerb_rst <= i_SS_WDATA[11];
                    timerb_ovfl_z <= i_SS_WDATA[12];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            timerb_cnt <= (timerb_prescaler_ovfl_z & i_TIMERB_RUN) | i_TEST_D2;
            timerb_ld  <= (i_TIMERB_RUN & timerb_rst) | timerb_ovfl_z; //run reg postive edge detector
            timerb_rst <= ~i_TIMERB_RUN;

            timerb_ovfl_z <= timerb_ovfl;
        end
    end
end

cavebanpresto_ikaopm_ss_counter #(.SS_BASE_BIT(13'd5021), .WIDTH(8)) u_timerb (
    .i_EMUCLK(i_EMUCLK), .i_PCEN_n(phi1pcen_n), .i_NCEN_n(phi1ncen_n),
    .i_CNT(timerb_cnt), .i_LD(timerb_ld), .i_RST(~mrst_n | timerb_rst),
    .i_D(i_CLKB), .o_Q(), .o_CO(timerb_ovfl)

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        (i_SS_REQ),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_u_timerb_valid_mask),
    .o_SS_ACK        (ss_u_timerb_ack),
    .o_SS_ERROR      (ss_u_timerb_error),
    .o_SS_RDATA      (ss_u_timerb_rdata)
);



///////////////////////////////////////////////////////////
//////  Flag and IRQ generator
////

always @(posedge i_EMUCLK) begin
    if (i_SS_HOLD) begin
        if (ss_local_write_accept) begin
            case (i_SS_WORD_ADDR)
                8'd156: begin
                    o_TIMERA_FLAG <= i_SS_WDATA[0];
                    o_TIMERB_FLAG <= i_SS_WDATA[1];
                    o_IRQ_n <= i_SS_WDATA[2];
                end
                default: ;
            endcase
        end
    end else begin
        if(!phi1ncen_n) begin
            if(~mrst_n || i_TIMERA_FRST) begin
                o_TIMERA_FLAG <= 1'b0;
            end
            else begin
                if(i_TIMERA_IRQ_EN) o_TIMERA_FLAG <= timera_ovfl_z | o_TIMERA_FLAG;
                else o_TIMERA_FLAG <= 1'b0;
            end

            if(~mrst_n || i_TIMERB_FRST) begin
                o_TIMERB_FLAG <= 1'b0;
            end
            else begin
                if(i_TIMERB_IRQ_EN) o_TIMERB_FLAG <= timerb_ovfl_z | o_TIMERB_FLAG;
                else o_TIMERB_FLAG <= 1'b0;
            end

            o_IRQ_n <= ~(o_TIMERA_FLAG | o_TIMERB_FLAG);
        end
    end
end


// CaveBanpresto exact-state word instrumentation.

always @(*) begin
    ss_local_valid_mask = 32'd0;
    ss_local_read_data = 32'd0;
    case (i_SS_WORD_ADDR)
        8'd156: begin
            ss_local_valid_mask = 32'h00001fff;
            ss_local_read_data[0] = o_TIMERA_FLAG;
            ss_local_read_data[1] = o_TIMERB_FLAG;
            ss_local_read_data[2] = o_IRQ_n;
            ss_local_read_data[3] = timera_cnt;
            ss_local_read_data[4] = timera_ld;
            ss_local_read_data[5] = timera_rst;
            ss_local_read_data[6] = timera_ovfl_z;
            ss_local_read_data[7] = timerb_prescaler_cnt;
            ss_local_read_data[8] = timerb_prescaler_ovfl_z;
            ss_local_read_data[9] = timerb_cnt;
            ss_local_read_data[10] = timerb_ld;
            ss_local_read_data[11] = timerb_rst;
            ss_local_read_data[12] = timerb_ovfl_z;
        end
        default: ;
    endcase
end

assign ss_local_accept =
    i_SS_HOLD && i_SS_REQ && (|ss_local_valid_mask) && !ss_local_seen_q;
assign ss_local_write_accept = ss_local_accept && i_SS_WRITE;

always @(posedge i_EMUCLK) begin
    if (!i_SS_HOLD) begin
        ss_local_seen_q <= 1'b0;
        ss_local_ack_q <= 1'b0;
        ss_local_rdata_q <= 32'd0;
    end else begin
        ss_local_ack_q <= 1'b0;
        if (!i_SS_REQ)
            ss_local_seen_q <= 1'b0;
        if (ss_local_accept) begin
            ss_local_seen_q <= 1'b1;
            ss_local_ack_q <= 1'b1;
            ss_local_rdata_q <= ss_local_read_data;
        end
    end
end

assign o_SS_VALID_MASK = ss_local_valid_mask | ss_u_timera_valid_mask | ss_u_timerb_prescaler_valid_mask | ss_u_timerb_valid_mask;
assign o_SS_ACK = ss_local_ack_q | ss_u_timera_ack | ss_u_timerb_prescaler_ack | ss_u_timerb_ack;
assign o_SS_ERROR = 1'b0 | ss_u_timera_error | ss_u_timerb_prescaler_error | ss_u_timerb_error;
assign o_SS_RDATA = (ss_local_rdata_q & ss_local_valid_mask) | (ss_u_timera_rdata & ss_u_timera_valid_mask) | (ss_u_timerb_prescaler_rdata & ss_u_timerb_prescaler_valid_mask) | (ss_u_timerb_rdata & ss_u_timerb_valid_mask);


endmodule

module CaveBanprestoIKAOPMExact #(parameter FULLY_SYNCHRONOUS = 1, parameter FAST_RESET = 0,
                parameter USE_BRAM = 0) (
    //chip clock
    input   wire            i_EMUCLK, //emulator master clock

    //clock endables
    input   wire            i_phiM_PCEN_n, //phiM positive edge clock enable(negative logic)
    `ifdef IKAOPM_USER_DEFINED_CLOCK_ENABLES
    input   wire            i_phi1_PCEN_n, //phi1 positive edge clock enable(negative logic)
    input   wire            i_phi1_NCEN_n, //phi1 negative edge clock enable(negative logic)
    `endif

    //chip reset
    input   wire            i_IC_n,    

    //phi1
    output  wire            o_phi1,

    //bus control and address
    input   wire            i_CS_n,
    input   wire            i_RD_n,
    input   wire            i_WR_n,
    input   wire            i_A0,

    //bus data
    input   wire    [7:0]   i_D,
    output  wire    [7:0]   o_D,

    //output driver enable
    output  wire            o_D_OE,

    //ct
    output  wire            o_CT2, //BIT7 of register 0x1B, pin 8
    output  wire            o_CT1, //BIT6 of register 0x1B, pin 9

    //interrupt
    output  wire            o_IRQ_n,

    //sh
    output  wire            o_SH1,
    output  wire            o_SH2,

    //output
    output  wire            o_SO,

    output  wire            o_EMU_R_SAMPLE, o_EMU_L_SAMPLE,
    output  wire signed     [15:0]  o_EMU_R_EX, o_EMU_L_EX,
    output  wire signed     [15:0]  o_EMU_R, o_EMU_L

    `ifdef IKAOPM_BUSY_FLAG_ENABLE
    , output  wire            o_EMU_BUSY_FLAG
    `endif 

,
    input   wire            i_SS_HOLD,
    input   wire            i_SS_REQ,
    input   wire            i_SS_WRITE,
    input   wire    [7:0]   i_SS_WORD_ADDR,
    input   wire    [31:0]  i_SS_WDATA,
    output  wire    [31:0]  o_SS_VALID_MASK,
    output  wire            o_SS_ACK,
    output  wire            o_SS_ERROR,
    output  wire    [31:0]  o_SS_RDATA
);

// Forward declarations for exact-state instrumentation.
wire [31:0] ss_timinggen_valid_mask;
wire ss_timinggen_ack;
wire ss_timinggen_error;
wire [31:0] ss_timinggen_rdata;
wire [31:0] ss_reg_valid_mask;
wire ss_reg_ack;
wire ss_reg_error;
wire [31:0] ss_reg_rdata;
wire [31:0] ss_noise_valid_mask;
wire ss_noise_ack;
wire ss_noise_error;
wire [31:0] ss_noise_rdata;
wire [31:0] ss_lfo_valid_mask;
wire ss_lfo_ack;
wire ss_lfo_error;
wire [31:0] ss_lfo_rdata;
wire [31:0] ss_pg_valid_mask;
wire ss_pg_ack;
wire ss_pg_error;
wire [31:0] ss_pg_rdata;
wire [31:0] ss_eg_valid_mask;
wire ss_eg_ack;
wire ss_eg_error;
wire [31:0] ss_eg_rdata;
wire [31:0] ss_op_valid_mask;
wire ss_op_ack;
wire ss_op_error;
wire [31:0] ss_op_rdata;
wire [31:0] ss_acc_valid_mask;
wire ss_acc_ack;
wire ss_acc_error;
wire [31:0] ss_acc_rdata;
wire [31:0] ss_timer_valid_mask;
wire ss_timer_ack;
wire ss_timer_error;
wire [31:0] ss_timer_rdata;




///////////////////////////////////////////////////////////
//////  Clock enable information
////

/*
    EMUCLK      ¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|
    phiM        _______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|_______|¯¯¯¯¯¯¯|
    phi1        ¯¯¯¯¯¯¯|_______________|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|_______________|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|_______________|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|________

    You should provide 3 enables when `IKAOPM_USER_DEFINED_CLOCK_ENABLES is defined
    phiM_PCEN   ¯¯¯|___|¯¯¯¯¯¯¯¯¯¯¯|___|¯¯¯¯¯¯¯¯¯¯¯|___|¯¯¯¯¯¯¯¯¯¯¯|___|¯¯¯¯¯¯¯¯¯¯¯|___|¯¯¯¯¯¯¯¯¯¯¯|___|¯¯¯¯¯¯¯¯¯¯¯|___|¯¯¯¯¯¯¯¯
    phi1_NCEN   ¯¯¯|___|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|___|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|___|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|___|¯¯¯¯¯¯¯¯
    phi1_PCEN   ¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|___|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|___|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|___|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯
*/



///////////////////////////////////////////////////////////
//////  Clock and reset
////

wire            phi1pcen_n, phi1ncen_n;
wire            mrst_n;



///////////////////////////////////////////////////////////
//////  Interconnects
////

//timings
wire            cycle_31, cycle_01;                     //to REG
wire            cycle_12_28, cycle_05_21, cycle_byte;   //to LFO
wire            cycle_05, cycle_10;                     //to PG
wire            cycle_03, cycle_00_16, cycle_01_to_16;  //to EG
wire            cycle_04_12_20_28;                      //to OP(algorithm state counter)
wire            cycle_29, cycle_06_22;                  //to ACC
wire            cycle_12, cycle_15_31;                  //to NOISE

//NOISE
wire    [4:0]   nfrq;
wire            lfo_noise;
wire            noise_attenlevel;

//LFO
wire    [7:0]   lfrq;
wire    [6:0]   pmd, amd;
wire    [1:0]   w;
wire            lfrq_update;
wire    [7:0]   lfa, lfp;

//PG
wire    [6:0]   kc;
wire    [5:0]   kf;
wire    [2:0]   pms;
wire    [1:0]   dt2;
wire    [2:0]   dt1;
wire    [3:0]   mul;
wire    [4:0]   pdelta_shamt;
wire            phase_rst;

//EG
wire            kon;
wire    [1:0]   ks;
wire    [4:0]   ar;
wire    [4:0]   d1r;
wire    [4:0]   d2r;
wire    [3:0]   rr;
wire    [3:0]   d1l;
wire    [6:0]   tl;
wire    [1:0]   ams;

//OP
wire    [9:0]   op_attenlevel, op_phasedata;
wire    [2:0]   alg, fl;

//ACC
wire            ne;
wire    [1:0]   rl;
wire            acc_snd_add;
wire    [13:0]  acc_noise;
wire    [13:0]  acc_opdata;

//TIMER
wire    [7:0]   clka1, clkb;
wire    [1:0]   clka2;
wire    [5:0]   timerctrl;
wire            timera_flag, timerb_flag, timera_ovfl;

//TEST
wire    [7:0]   test;
wire            reg_phase_ch6_c2, reg_attenlevel_ch8_c2, reg_lfo_clk;

//write busy flag(especially for an external asynchronous fifo)
`ifdef IKAOPM_BUSY_FLAG_ENABLE
assign  o_EMU_BUSY_FLAG = o_D[7];
`endif



///////////////////////////////////////////////////////////
//////  Modules
////

cavebanpresto_ikaopm_ss_timinggen #(.SS_BASE_BIT(13'd0), 
    .FULLY_SYNCHRONOUS          (FULLY_SYNCHRONOUS          ),
    .FAST_RESET                 (FAST_RESET                 )
) TIMINGGEN (
    .i_EMUCLK                   (i_EMUCLK                   ),

    .i_IC_n                     (i_IC_n                     ),
    .o_MRST_n                   (mrst_n                     ),

    .i_phiM_PCEN_n              (i_phiM_PCEN_n              ),
    `ifdef IKAOPM_USER_DEFINED_CLOCK_ENABLES
    .i_phi1_PCEN_n              (i_phi1_PCEN_n              ),
    .i_phi1_NCEN_n              (i_phi1_NCEN_n              ),
    `endif

    .o_phi1                     (o_phi1                     ),
    .o_phi1_PCEN_n              (phi1pcen_n                 ),
    .o_phi1_NCEN_n              (phi1ncen_n                 ),

    .o_SH1                      (o_SH1                      ),
    .o_SH2                      (o_SH2                      ),

    .o_CYCLE_01                 (cycle_01                   ),
    .o_CYCLE_31                 (cycle_31                   ),

    .o_CYCLE_12_28              (cycle_12_28                ),
    .o_CYCLE_05_21              (cycle_05_21                ),
    .o_CYCLE_BYTE               (cycle_byte                 ),

    .o_CYCLE_05                 (cycle_05                   ),
    .o_CYCLE_10                 (cycle_10                   ),

    .o_CYCLE_03                 (cycle_03                   ),
    .o_CYCLE_00_16              (cycle_00_16                ),
    .o_CYCLE_01_TO_16           (cycle_01_to_16             ),

    .o_CYCLE_04_12_20_28        (cycle_04_12_20_28          ),

    .o_CYCLE_12                 (cycle_12                   ),
    .o_CYCLE_15_31              (cycle_15_31                ),

    .o_CYCLE_29                 (cycle_29                   ),
    .o_CYCLE_06_22              (cycle_06_22                )

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        ((i_SS_REQ && (i_SS_WORD_ADDR >= 8'd0) && (i_SS_WORD_ADDR < 8'd2))),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_timinggen_valid_mask),
    .o_SS_ACK        (ss_timinggen_ack),
    .o_SS_ERROR      (ss_timinggen_error),
    .o_SS_RDATA      (ss_timinggen_rdata)
);



cavebanpresto_ikaopm_ss_reg #(.SS_BASE_BIT(13'd64), 
    .USE_BRAM_FOR_D32REG        (USE_BRAM                   ),
    .FULLY_SYNCHRONOUS          (FULLY_SYNCHRONOUS          )
) REG (
    .i_EMUCLK                   (i_EMUCLK                   ),
    .i_MRST_n                   (mrst_n                     ),

    .i_phi1_PCEN_n              (phi1pcen_n                 ),
    .i_phi1_NCEN_n              (phi1ncen_n                 ),

    .i_CYCLE_01                 (cycle_01                   ),
    .i_CYCLE_31                 (cycle_31                   ),

    .i_CS_n                     (i_CS_n                     ),
    .i_RD_n                     (i_RD_n                     ),
    .i_WR_n                     (i_WR_n                     ),
    .i_A0                       (i_A0                       ),

    .i_D                        (i_D                        ),
    .o_D                        (o_D                        ),
    .o_D_OE                     (o_D_OE                     ),

    .i_TIMERA_OVFL              (timera_ovfl                ),
    .i_TIMERA_FLAG              (timera_flag                ),
    .i_TIMERB_FLAG              (timerb_flag                ),

    .o_TEST                     (test                       ),

    .o_CT1                      (o_CT1                      ),
    .o_CT2                      (o_CT2                      ),

    .o_NE                       (ne                         ),
    .o_NFRQ                     (nfrq                       ),

    .o_CLKA1                    (clka1                      ),
    .o_CLKA2                    (clka2                      ),
    .o_CLKB                     (clkb                       ),       
    .o_TIMERA_RUN               (timerctrl[0]               ),
    .o_TIMERB_RUN               (timerctrl[1]               ),
    .o_TIMERA_IRQ_EN            (timerctrl[2]               ),
    .o_TIMERB_IRQ_EN            (timerctrl[3]               ),
    .o_TIMERA_FRST              (timerctrl[4]               ),
    .o_TIMERB_FRST              (timerctrl[5]               ),

    .o_LFRQ                     (lfrq                       ),
    .o_PMD                      (pmd                        ),
    .o_AMD                      (amd                        ),
    .o_W                        (w                          ),
    .o_LFRQ_UPDATE              (lfrq_update                ),

    .o_KC                       (kc                         ),
    .o_KF                       (kf                         ),
    .o_PMS                      (pms                        ),
    .o_DT2                      (dt2                        ),
    .o_DT1                      (dt1                        ),
    .o_MUL                      (mul                        ),

    .o_KON                      (kon                        ),
    .o_KS                       (ks                         ),
    .o_AR                       (ar                         ),
    .o_D1R                      (d1r                        ),
    .o_D2R                      (d2r                        ),
    .o_RR                       (rr                         ),
    .o_D1L                      (d1l                        ),
    .o_TL                       (tl                         ),
    .o_AMS                      (ams                        ),

    .o_ALG                      (alg                        ),
    .o_FL                       (fl                         ),

    .o_RL                       (rl                         ),

    .i_REG_LFO_CLK              (reg_lfo_clk                ),

    .i_REG_PHASE_CH6_C2         (reg_phase_ch6_c2           ),
    .i_REG_ATTENLEVEL_CH8_C2    (reg_attenlevel_ch8_c2      ),
    .i_REG_OPDATA               (acc_opdata                 )

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        ((i_SS_REQ && (i_SS_WORD_ADDR >= 8'd2) && (i_SS_WORD_ADDR < 8'd62))),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_reg_valid_mask),
    .o_SS_ACK        (ss_reg_ack),
    .o_SS_ERROR      (ss_reg_error),
    .o_SS_RDATA      (ss_reg_rdata)
);



cavebanpresto_ikaopm_ss_noise #(.SS_BASE_BIT(13'd1984)) NOISE (
    .i_EMUCLK                   (i_EMUCLK                   ),

    .i_MRST_n                   (mrst_n                     ),
    
    .i_phi1_PCEN_n              (phi1pcen_n                 ),
    .i_phi1_NCEN_n              (phi1ncen_n                 ),

    .i_CYCLE_12                 (cycle_12                   ),
    .i_CYCLE_15_31              (cycle_15_31                ),

    .i_NFRQ                     (nfrq                       ),

    .i_NOISE_ATTENLEVEL         (noise_attenlevel           ),

    .o_ACC_NOISE                (acc_noise                  ),
    .o_LFO_NOISE                (lfo_noise                  )

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        ((i_SS_REQ && (i_SS_WORD_ADDR >= 8'd62) && (i_SS_WORD_ADDR < 8'd64))),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_noise_valid_mask),
    .o_SS_ACK        (ss_noise_ack),
    .o_SS_ERROR      (ss_noise_error),
    .o_SS_RDATA      (ss_noise_rdata)
);



cavebanpresto_ikaopm_ss_lfo #(.SS_BASE_BIT(13'd2048)) LFO (
    .i_EMUCLK                   (i_EMUCLK                   ),

    .i_MRST_n                   (mrst_n                     ),
    
    .i_phi1_PCEN_n              (phi1pcen_n                 ),
    .i_phi1_NCEN_n              (phi1ncen_n                 ),
    
    .i_CYCLE_12_28              (cycle_12_28                ),
    .i_CYCLE_05_21              (cycle_05_21                ),
    .i_CYCLE_BYTE               (cycle_byte                 ),
    
    .i_LFRQ                     (lfrq                       ),
    .i_PMD                      (pmd                        ),
    .i_AMD                      (amd                        ),
    .i_W                        (w                          ),
    .i_TEST_D1                  (test[1]                    ),
    .i_TEST_D2                  (test[2]                    ),
    .i_TEST_D3                  (test[3]                    ),

    .i_LFRQ_UPDATE              (lfrq_update                ),

    .i_LFO_NOISE                (lfo_noise                  ),

    .o_LFA                      (lfa                        ),
    .o_LFP                      (lfp                        ),
    .o_REG_LFO_CLK              (reg_lfo_clk                )

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        ((i_SS_REQ && (i_SS_WORD_ADDR >= 8'd64) && (i_SS_WORD_ADDR < 8'd69))),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_lfo_valid_mask),
    .o_SS_ACK        (ss_lfo_ack),
    .o_SS_ERROR      (ss_lfo_error),
    .o_SS_RDATA      (ss_lfo_rdata)
);



cavebanpresto_ikaopm_ss_pg #(.SS_BASE_BIT(13'd2208), 
    .USE_BRAM_FOR_PHASEREG      (USE_BRAM                   )
) PG (
    .i_EMUCLK                   (i_EMUCLK                   ),

    .i_MRST_n                   (mrst_n                     ),
    
    .i_phi1_PCEN_n              (phi1pcen_n                 ),
    .i_phi1_NCEN_n              (phi1ncen_n                 ),

    .i_CYCLE_05                 (cycle_05                   ),
    .i_CYCLE_10                 (cycle_10                   ),

    .i_KC                       (kc                         ),
    .i_KF                       (kf                         ),
    .i_PMS                      (pms                        ),
    .i_DT2                      (dt2                        ),
    .i_DT1                      (dt1                        ),
    .i_MUL                      (mul                        ),
    .i_TEST_D3                  (test[3]                    ),

    .i_LFP                      (lfp                        ),

    .i_PG_PHASE_RST             (phase_rst                  ),
    .o_EG_PDELTA_SHIFT_AMOUNT   (pdelta_shamt               ),
    .o_OP_PHASEDATA             (op_phasedata               ),
    .o_REG_PHASE_CH6_C2         (reg_phase_ch6_c2           )

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        ((i_SS_REQ && (i_SS_WORD_ADDR >= 8'd69) && (i_SS_WORD_ADDR < 8'd108))),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_pg_valid_mask),
    .o_SS_ACK        (ss_pg_ack),
    .o_SS_ERROR      (ss_pg_error),
    .o_SS_RDATA      (ss_pg_rdata)
);



cavebanpresto_ikaopm_ss_eg #(.SS_BASE_BIT(13'd3456)) EG (
    .i_EMUCLK                   (i_EMUCLK                   ),

    .i_MRST_n                   (mrst_n                     ),
    
    .i_phi1_PCEN_n              (phi1pcen_n                 ),
    .i_phi1_NCEN_n              (phi1ncen_n                 ),

    .i_CYCLE_03                 (cycle_03                   ),
    .i_CYCLE_31                 (cycle_31                   ),
    .i_CYCLE_00_16              (cycle_00_16                ),
    .i_CYCLE_01_TO_16           (cycle_01_to_16             ),

    .i_KON                      (kon                        ),
    .i_KS                       (ks                         ),
    .i_AR                       (ar                         ),
    .i_D1R                      (d1r                        ),
    .i_D2R                      (d2r                        ),
    .i_RR                       (rr                         ),
    .i_D1L                      (d1l                        ),
    .i_TL                       (tl                         ),
    .i_AMS                      (ams                        ),
    .i_LFA                      (lfa                        ),
    .i_TEST_D0                  (test[0]                    ),
    .i_TEST_D5                  (test[5]                    ),

    .i_EG_PDELTA_SHIFT_AMOUNT   (pdelta_shamt               ),

    .o_PG_PHASE_RST             (phase_rst                  ),
    .o_OP_ATTENLEVEL            (op_attenlevel              ),
    .o_NOISE_ATTENLEVEL         (noise_attenlevel           ),
    .o_REG_ATTENLEVEL_CH8_C2    (reg_attenlevel_ch8_c2      )

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        ((i_SS_REQ && (i_SS_WORD_ADDR >= 8'd108) && (i_SS_WORD_ADDR < 8'd126))),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_eg_valid_mask),
    .o_SS_ACK        (ss_eg_ack),
    .o_SS_ERROR      (ss_eg_error),
    .o_SS_RDATA      (ss_eg_rdata)
);



cavebanpresto_ikaopm_ss_op #(.SS_BASE_BIT(13'd4032)) OP (
    .i_EMUCLK                   (i_EMUCLK                   ),

    .i_MRST_n                   (mrst_n                     ),
    
    .i_phi1_PCEN_n              (phi1pcen_n                 ),
    .i_phi1_NCEN_n              (phi1ncen_n                 ),

    .i_CYCLE_03                 (cycle_03                   ),
    .i_CYCLE_12                 (cycle_12                   ),
    .i_CYCLE_04_12_20_28        (cycle_04_12_20_28          ),

    .i_ALG                      (alg                        ),
    .i_FL                       (fl                         ),
    .i_TEST_D4                  (test[4]                    ),

    .i_OP_PHASEDATA             (op_phasedata               ),
    .i_OP_ATTENLEVEL            (op_attenlevel              ),
    .o_ACC_SNDADD               (acc_snd_add                ),
    .o_ACC_OPDATA               (acc_opdata                 )

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        ((i_SS_REQ && (i_SS_WORD_ADDR >= 8'd126) && (i_SS_WORD_ADDR < 8'd147))),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_op_valid_mask),
    .o_SS_ACK        (ss_op_ack),
    .o_SS_ERROR      (ss_op_error),
    .o_SS_RDATA      (ss_op_rdata)
);



cavebanpresto_ikaopm_ss_acc #(.SS_BASE_BIT(13'd4704)) ACC (
    .i_EMUCLK                   (i_EMUCLK                   ),

    .i_MRST_n                   (mrst_n                     ),
    
    .i_phi1_PCEN_n              (phi1pcen_n                 ),
    .i_phi1_NCEN_n              (phi1ncen_n                 ),

    .i_CYCLE_12                 (cycle_12                   ),
    .i_CYCLE_29                 (cycle_29                   ),
    .i_CYCLE_00_16              (cycle_00_16                ),
    .i_CYCLE_06_22              (cycle_06_22                ),
    .i_CYCLE_01_TO_16           (cycle_01_to_16             ),

    .i_NE                       (ne                         ),
    .i_RL                       (rl                         ),

    .i_ACC_SNDADD               (acc_snd_add                ),
    .i_ACC_OPDATA               (acc_opdata                 ),
    .i_ACC_NOISE                (acc_noise                  ),

    .o_SO                       (o_SO                       ),

    .o_EMU_R_SAMPLE             (o_EMU_R_SAMPLE             ),
    .o_EMU_R_EX                 (o_EMU_R_EX                 ),
    .o_EMU_R                    (o_EMU_R                    ),

    .o_EMU_L_SAMPLE             (o_EMU_L_SAMPLE             ),
    .o_EMU_L_EX                 (o_EMU_L_EX                 ),
    .o_EMU_L                    (o_EMU_L                    )

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        ((i_SS_REQ && (i_SS_WORD_ADDR >= 8'd147) && (i_SS_WORD_ADDR < 8'd156))),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_acc_valid_mask),
    .o_SS_ACK        (ss_acc_ack),
    .o_SS_ERROR      (ss_acc_error),
    .o_SS_RDATA      (ss_acc_rdata)
);



cavebanpresto_ikaopm_ss_timer #(.SS_BASE_BIT(13'd4992)) TIMER (
    .i_EMUCLK                   (i_EMUCLK                   ),

    .i_MRST_n                   (mrst_n                     ),
    
    .i_phi1_PCEN_n              (phi1pcen_n                 ),
    .i_phi1_NCEN_n              (phi1ncen_n                 ),

    .i_CYCLE_31                 (cycle_31                   ),

    .i_CLKA1                    (clka1                      ),
    .i_CLKA2                    (clka2                      ),
    .i_CLKB                     (clkb                       ),
    .i_TIMERA_RUN               (timerctrl[0]               ),
    .i_TIMERB_RUN               (timerctrl[1]               ),
    .i_TIMERA_IRQ_EN            (timerctrl[2]               ),
    .i_TIMERB_IRQ_EN            (timerctrl[3]               ),
    .i_TIMERA_FRST              (timerctrl[4]               ),
    .i_TIMERB_FRST              (timerctrl[5]               ),
    .i_TEST_D2                  (test[2]                    ),

    .o_TIMERA_OVFL              (timera_ovfl                ),
    .o_TIMERA_FLAG              (timera_flag                ),
    .o_TIMERB_FLAG              (timerb_flag                ),
    .o_IRQ_n                    (o_IRQ_n                    )

,
    .i_SS_HOLD       (i_SS_HOLD),
    .i_SS_REQ        ((i_SS_REQ && (i_SS_WORD_ADDR >= 8'd156) && (i_SS_WORD_ADDR < 8'd158))),
    .i_SS_WRITE      (i_SS_WRITE),
    .i_SS_WORD_ADDR  (i_SS_WORD_ADDR),
    .i_SS_WDATA      (i_SS_WDATA),
    .o_SS_VALID_MASK (ss_timer_valid_mask),
    .o_SS_ACK        (ss_timer_ack),
    .o_SS_ERROR      (ss_timer_error),
    .o_SS_RDATA      (ss_timer_rdata)
);


// CaveBanpresto exact-state word instrumentation.

assign o_SS_VALID_MASK = 32'd0 | ss_timinggen_valid_mask | ss_reg_valid_mask | ss_noise_valid_mask | ss_lfo_valid_mask | ss_pg_valid_mask | ss_eg_valid_mask | ss_op_valid_mask | ss_acc_valid_mask | ss_timer_valid_mask;
assign o_SS_ACK = 1'b0 | ss_timinggen_ack | ss_reg_ack | ss_noise_ack | ss_lfo_ack | ss_pg_ack | ss_eg_ack | ss_op_ack | ss_acc_ack | ss_timer_ack;
assign o_SS_ERROR = 1'b0 | ss_timinggen_error | ss_reg_error | ss_noise_error | ss_lfo_error | ss_pg_error | ss_eg_error | ss_op_error | ss_acc_error | ss_timer_error;
assign o_SS_RDATA = 32'd0 | (ss_timinggen_rdata & ss_timinggen_valid_mask) | (ss_reg_rdata & ss_reg_valid_mask) | (ss_noise_rdata & ss_noise_valid_mask) | (ss_lfo_rdata & ss_lfo_valid_mask) | (ss_pg_rdata & ss_pg_valid_mask) | (ss_eg_rdata & ss_eg_valid_mask) | (ss_op_rdata & ss_op_valid_mask) | (ss_acc_rdata & ss_acc_valid_mask) | (ss_timer_rdata & ss_timer_valid_mask);


endmodule

`default_nettype wire
