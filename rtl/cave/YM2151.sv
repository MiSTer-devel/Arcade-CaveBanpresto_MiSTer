// Core-side YM2151 wrapper for Z80 sound boards.
module YM2151 #(
  parameter WRITE_HOLD_CYCLES = 16
)(
  input         clock,
  input         reset,
  input         io_cpu_wr,
  input         io_cpu_addr,
  input  [7:0]  io_cpu_din,
  output [7:0]  io_cpu_dout,
  output        io_irq,
  output        io_audio_valid,
  output [15:0] io_audio_bits
);
  wire ym_cen;
  wire ym_irq_n;
  wire ym_sample;
  wire signed [15:0] ym_left;
  wire signed [15:0] ym_right;
  wire signed [16:0] ym_mono_sum = {ym_left[15], ym_left} + {ym_right[15], ym_right};
  localparam integer WRITE_HOLD_RELOAD =
    WRITE_HOLD_CYCLES <= 1 ? 0 :
    WRITE_HOLD_CYCLES > 16 ? 15 :
    WRITE_HOLD_CYCLES - 1;

  reg [3:0] write_hold;
  reg       write_addr;
  reg [7:0] write_data;
  wire      chip_cpu_wr = io_cpu_wr | (write_hold != 4'd0);
  wire      chip_cpu_addr = io_cpu_wr ? io_cpu_addr : write_addr;
  wire [7:0] chip_cpu_din = io_cpu_wr ? io_cpu_din : write_data;

  always @(posedge clock) begin
    if (reset) begin
      write_hold <= 4'd0;
      write_addr <= 1'b0;
      write_data <= 8'h00;
    end
    else if (io_cpu_wr) begin
      write_hold <= WRITE_HOLD_RELOAD;
      write_addr <= io_cpu_addr;
      write_data <= io_cpu_din;
    end
    else if (write_hold != 4'd0) begin
      write_hold <= write_hold - 4'd1;
    end
  end

  CaveClockEnable #(
    .STEP (17'h2000)
  ) clock_enable (
    .clock  (clock),
    .enable (ym_cen)
  );

  IKAOPM #(
    .FULLY_SYNCHRONOUS (1),
    .FAST_RESET        (1),
    .USE_BRAM          (1)
  ) ym2151 (
    .i_EMUCLK       (clock),
    .i_phiM_PCEN_n  (~ym_cen),
    .i_IC_n         (~reset),
    .o_phi1         (),
    .i_CS_n         (1'b0),
    .i_RD_n         (chip_cpu_wr),
    .i_WR_n         (~chip_cpu_wr),
    .i_A0           (chip_cpu_addr),
    .i_D            (chip_cpu_din),
    .o_D            (io_cpu_dout),
    .o_D_OE         (),
    .o_CT2          (),
    .o_CT1          (),
    .o_IRQ_n        (ym_irq_n),
    .o_SH1          (),
    .o_SH2          (),
    .o_SO           (),
    .o_EMU_R_SAMPLE (),
    .o_EMU_R_EX     (),
    .o_EMU_R        (ym_right),
    .o_EMU_L_SAMPLE (ym_sample),
    .o_EMU_L_EX     (),
    .o_EMU_L        (ym_left)
  );

  assign io_irq = ~ym_irq_n;
  assign io_audio_valid = ym_sample;
  assign io_audio_bits = ym_mono_sum[16:1];
endmodule
