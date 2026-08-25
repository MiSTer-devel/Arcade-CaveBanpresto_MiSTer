`default_nettype none

// CaveBanpresto-local exact T80s-compatible sound-CPU wrapper.
//
// With every save-state control input low, the divider, CEN cadence, and
// registered T80s bus shell are intentionally identical to
// CaveSoundZ80Cpu/T80s. A stop request waits for a scheduled normal M1/T1
// boundary, commits its pending writeback with one externally silent CEN,
// self-loads the resulting exact image to reset microstate, and privately
// launches from M1/T0 back to M1/T1. This first-stage CPU/divider
// acknowledgement deliberately does not wait for the external ROM path:
// integration gates new ROM launches only after ss_stopped_o,
// drains/canonicalizes owner 34, and then raises ss_external_idle_i. Restore
// performs the same private launch and waits for both transport idle and
// dependency/prefetch qualification before any release or recoverable abort.
module CaveBanprestoSoundZ80SaveState #(
	parameter integer T2_WRITE = 1
) (
	input  wire         clock,
	input  wire         reset,

	output wire [15:0]  io_addr,
	input  wire  [7:0]  io_din,
	output wire  [7:0]  io_dout,
	output wire         io_m1,
	output wire         io_rd,
	output wire         io_wr,
	output wire         io_rfsh,
	output wire         io_mreq,
	output wire         io_iorq,
	input  wire         io_fast_clock,
	input  wire         io_wait_n,
	input  wire         io_int,
	input  wire         io_nmi,

	input  wire         ss_stop_request_i,
	input  wire         ss_restore_mode_i,
	input  wire         ss_external_idle_i,
	input  wire         ss_abort_i,
	input  wire         ss_release_i,
	input  wire         ss_release_restore_i,
	input  wire         ss_restore_dependencies_ready_i,

	input  wire         ss_restore_load_i,
	input  wire [211:0] ss_restore_reg_i,
	input  wire  [26:0] ss_restore_aux_i,
	input  wire   [2:0] ss_restore_divider_i,

	output wire [211:0] ss_live_reg_o,
	output wire  [26:0] ss_live_aux_o,
	output wire   [2:0] ss_live_divider_o,
	output wire         ss_boundary_safe_o,
	output logic        ss_stopped_o,
	output logic        ss_abort_ack_o,
	output logic        ss_restore_launch_done_o,
	output logic        ss_terminal_fault_o,
	output wire         ss_cpu_cen_o
);

	logic [2:0] clock_divider_q;
	logic       restore_mode_q;
	logic       restore_mutated_q;
	logic       launch_pending_q;
	logic       abort_pending_q;
	logic       stop_rearm_block_q;

	typedef enum logic [1:0] {
		StNormal          = 2'd0,
		StSelfLoad        = 2'd1,
		StCanonicalLaunch = 2'd2
	} stop_phase_e;

	stop_phase_e stop_phase_q;
	stop_phase_e stop_phase_d;

	wire m1_n_core;
	wire iorq_core;
	wire no_read_core;
	wire write_core;
	wire rfsh_n_core;
	wire halt_n_core;
	wire busak_n_core;
	wire [2:0] machine_cycle_core;
	wire [2:0] t_state_core;
	wire int_cycle_n_core;
	wire int_enable_core;
	wire stop_core;
	wire canonical_safe_core;
	wire nmi_to_core;
	wire [211:0] reg_core;
	wire [26:0] aux_core;
	wire [7:0] data_out_core;
	wire [15:0] io_addr_core;

	logic rd_n_q;
	logic wr_n_q;
	logic iorq_n_q;
	logic mreq_n_q;
	logic [7:0] data_in_q;

	wire divider_cen =
		io_fast_clock ? &clock_divider_q[1:0] : &clock_divider_q;
	wire wrapper_bus_idle =
		rd_n_q && wr_n_q && iorq_n_q && mreq_n_q && rfsh_n_core;
	wire cpu_stop_boundary_now =
		ss_stop_request_i &&
		~ss_abort_i &&
		~stop_rearm_block_q &&
		~ss_stopped_o &&
		~ss_terminal_fault_o &&
		(stop_phase_q == StNormal) &&
		divider_cen &&
		canonical_safe_core &&
		wrapper_bus_idle &&
		io_wait_n;
	wire stop_settle_cen = cpu_stop_boundary_now;
	wire stop_self_load = stop_phase_q == StSelfLoad;
	wire stop_private_launch_cen =
		stop_phase_q == StCanonicalLaunch;
	wire normal_cen =
		divider_cen &&
		~ss_stopped_o &&
		(stop_phase_q == StNormal) &&
		~cpu_stop_boundary_now &&
		~ss_terminal_fault_o;
	wire launch_cen =
		ss_stopped_o &&
		launch_pending_q &&
		~ss_terminal_fault_o &&
		~ss_abort_i &&
		~abort_pending_q &&
		~ss_release_i &&
		~ss_restore_load_i;
	wire core_cen =
		normal_cen |
		stop_settle_cen |
		stop_private_launch_cen |
		launch_cen;
	wire restore_load_legal =
		ss_stopped_o &&
		restore_mode_q &&
		ss_external_idle_i &&
		~restore_mutated_q &&
		~launch_pending_q &&
		~ss_restore_launch_done_o &&
		~ss_abort_i &&
		~abort_pending_q &&
		~ss_terminal_fault_o;
	wire restore_dir_set = ss_restore_load_i && restore_load_legal;
	wire dir_set_to_core = restore_dir_set | stop_self_load;
	wire [211:0] dir_reg_to_core =
		stop_self_load ? reg_core : ss_restore_reg_i;
	wire [26:0] dir_aux_to_core =
		stop_self_load ? aux_core : ss_restore_aux_i;
	wire private_bus_cen =
		stop_settle_cen | stop_private_launch_cen | launch_cen;
	assign nmi_to_core =
		io_nmi &&
		!ss_stopped_o &&
		(stop_phase_q == StNormal);

	assign io_addr = io_addr_core;
	assign io_dout = data_out_core;
	assign io_m1 = ~m1_n_core;
	assign io_rd = ~rd_n_q;
	assign io_wr = ~wr_n_q;
	assign io_rfsh = ~rfsh_n_core;
	assign io_mreq = ~mreq_n_q;
	assign io_iorq = ~iorq_n_q;

	assign ss_live_reg_o = reg_core;
	assign ss_live_aux_o = aux_core;
	assign ss_live_divider_o = clock_divider_q;
	assign ss_boundary_safe_o =
		canonical_safe_core && wrapper_bus_idle && io_wait_n;
	assign ss_cpu_cen_o = core_cen;

	CaveBanprestoT80SaveState #(
		.Mode(0),
		.IOWait(1)
	) cpu (
		.RESET_n(~reset),
		.CLK_n(clock),
		.CEN(core_cen),
		.WAIT_n(io_wait_n),
		.INT_n(~io_int),
		.NMI_n(~nmi_to_core),
		.BUSRQ_n(1'b1),
		.M1_n(m1_n_core),
		.IORQ(iorq_core),
		.NoRead(no_read_core),
		.Write(write_core),
		.RFSH_n(rfsh_n_core),
		.HALT_n(halt_n_core),
		.BUSAK_n(busak_n_core),
		.A(io_addr_core),
		.DInst(io_din),
		.DI(data_in_q),
		.DO(data_out_core),
		.MC(machine_cycle_core),
		.TS(t_state_core),
		.IntCycle_n(int_cycle_n_core),
		.IntE(int_enable_core),
		.Stop(stop_core),
		.out0(1'b0),
		.REG(reg_core),
		.DIRSet(dir_set_to_core),
		.DIR(dir_reg_to_core),
		.SS_AUX(aux_core),
		.DIR_AUX(dir_aux_to_core),
		.SS_NMI_HOLD(
			ss_stopped_o || (stop_phase_q != StNormal)
		),
		.SS_CANONICAL_SAFE(canonical_safe_core)
	);

	// A normal M1/T1 boundary still carries the previous instruction's pending
	// writeback. Commit that writeback with one externally silent CEN, self-load
	// the resulting exact image to reset non-architectural microstate, then
	// launch privately from M1/T0 back to the serialized M1/T1 boundary.
	always_comb begin
		stop_phase_d = stop_phase_q;

		unique case (stop_phase_q)
			StNormal: begin
				if (cpu_stop_boundary_now)
					stop_phase_d = StSelfLoad;
			end

			StSelfLoad: begin
				stop_phase_d = StCanonicalLaunch;
			end

			StCanonicalLaunch: begin
				stop_phase_d = StNormal;
			end

			default: begin
				stop_phase_d = StNormal;
			end
		endcase
	end

	always_ff @(posedge clock) begin
		if (reset)
			stop_phase_q <= StNormal;
		else if (ss_stopped_o || ss_terminal_fault_o)
			stop_phase_q <= StNormal;
		else
			stop_phase_q <= stop_phase_d;
	end

	// Exact copy of the T80s registered external-bus shell (T2Write=1 in the
	// live Cave wrapper). It is held inactive by the restore launch from T0.
	always @(posedge clock or posedge reset) begin
		if (reset) begin
			rd_n_q <= 1'b1;
			wr_n_q <= 1'b1;
			iorq_n_q <= 1'b1;
			mreq_n_q <= 1'b1;
			data_in_q <= 8'h00;
		end else if (core_cen) begin
			rd_n_q <= 1'b1;
			wr_n_q <= 1'b1;
			iorq_n_q <= 1'b1;
			mreq_n_q <= 1'b1;

			if (!private_bus_cen) begin
				if (machine_cycle_core == 3'd1) begin
					if ((t_state_core == 3'd1) ||
					    ((t_state_core == 3'd2) && !io_wait_n)) begin
						rd_n_q <= ~int_cycle_n_core;
						mreq_n_q <= ~int_cycle_n_core;
						iorq_n_q <= int_cycle_n_core;
					end
					if (t_state_core == 3'd3)
						mreq_n_q <= 1'b0;
				end else begin
					if (((t_state_core == 3'd1) ||
					     ((t_state_core == 3'd2) && !io_wait_n)) &&
					    !no_read_core && !write_core) begin
						rd_n_q <= 1'b0;
						iorq_n_q <= ~iorq_core;
						mreq_n_q <= iorq_core;
					end

					if (T2_WRITE == 0) begin
						if ((t_state_core == 3'd2) &&
						    write_core) begin
							wr_n_q <= 1'b0;
							iorq_n_q <= ~iorq_core;
							mreq_n_q <= iorq_core;
						end
					end else begin
						if (((t_state_core == 3'd1) ||
						     ((t_state_core == 3'd2) &&
						      !io_wait_n)) &&
						    write_core) begin
							wr_n_q <= 1'b0;
							iorq_n_q <= ~iorq_core;
							mreq_n_q <= iorq_core;
						end
					end
				end

				if ((t_state_core == 3'd2) && io_wait_n)
					data_in_q <= io_din;
			end
		end
	end

	// Preserve the original free-running divider when save-state controls are
	// inactive. It freezes on the accepted boundary and is restored on DIRSet.
	always_ff @(posedge clock) begin
		if (reset) begin
			clock_divider_q <= 3'd0;
		end else if (restore_dir_set) begin
			clock_divider_q <= ss_restore_divider_i;
		end else if (!ss_stopped_o &&
		             (stop_phase_q == StNormal) &&
		             !cpu_stop_boundary_now &&
		             !ss_terminal_fault_o) begin
			clock_divider_q <= clock_divider_q + 3'd1;
		end
	end

	always_ff @(posedge clock) begin
		if (reset) begin
			restore_mode_q <= 1'b0;
			restore_mutated_q <= 1'b0;
			launch_pending_q <= 1'b0;
			abort_pending_q <= 1'b0;
			stop_rearm_block_q <= 1'b0;
			ss_stopped_o <= 1'b0;
			ss_abort_ack_o <= 1'b0;
			ss_restore_launch_done_o <= 1'b0;
			ss_terminal_fault_o <= 1'b0;
		end else if (!ss_terminal_fault_o) begin
			ss_abort_ack_o <= 1'b0;

			// Release/abort acknowledgement may cross back to the
			// coordinator more slowly than the held stop level drops.
			// Require a complete low re-arm interval before another stop can
			// be accepted, preventing an immediately repeated private stop.
			if (!ss_stop_request_i)
				stop_rearm_block_q <= 1'b0;

			if (!ss_stopped_o) begin
				if (ss_restore_load_i || ss_release_i) begin
					// Restore control while running must never reach DIRSet.
					ss_stopped_o <= 1'b1;
					ss_terminal_fault_o <= 1'b1;
				end else begin
					// Once the externally silent canonicalization has
					// started it must finish. Remember a racing abort and
					// acknowledge it only after that exact image is safely
					// stopped and its external dependencies can recover.
					if (ss_abort_i && (stop_phase_q != StNormal))
						abort_pending_q <= 1'b1;

					if (cpu_stop_boundary_now) begin
						restore_mode_q <= ss_restore_mode_i;
						restore_mutated_q <= 1'b0;
						launch_pending_q <= 1'b0;
						abort_pending_q <= 1'b0;
						ss_restore_launch_done_o <= 1'b0;
					end else if (stop_private_launch_cen) begin
						ss_stopped_o <= 1'b1;
					end
				end
			end else if (ss_abort_i || abort_pending_q) begin
				abort_pending_q <= 1'b1;

				if (restore_mutated_q) begin
					// Once DIRSet has occurred, unwinding would expose a
					// partially restored machine. The fault is reset-only.
					ss_terminal_fault_o <= 1'b1;
				end else if (ss_external_idle_i &&
				            ss_restore_dependencies_ready_i) begin
					restore_mode_q <= 1'b0;
					restore_mutated_q <= 1'b0;
					launch_pending_q <= 1'b0;
					abort_pending_q <= 1'b0;
					stop_rearm_block_q <= 1'b1;
					ss_stopped_o <= 1'b0;
					ss_abort_ack_o <= 1'b1;
					ss_restore_launch_done_o <= 1'b0;
				end
			end else if (ss_restore_load_i) begin
				if (restore_load_legal) begin
					restore_mutated_q <= 1'b1;
					launch_pending_q <= 1'b1;
					ss_restore_launch_done_o <= 1'b0;
				end else begin
					ss_terminal_fault_o <= 1'b1;
				end
			end else if (launch_pending_q) begin
				launch_pending_q <= 1'b0;
				ss_restore_launch_done_o <= 1'b1;
			end else if (ss_release_i) begin
				if (ss_external_idle_i &&
				    ss_restore_dependencies_ready_i &&
				    ((!ss_release_restore_i &&
				      !restore_mutated_q) ||
				     (restore_mode_q &&
				      ss_release_restore_i &&
				      restore_mutated_q &&
				      ss_restore_launch_done_o))) begin
					restore_mode_q <= 1'b0;
					restore_mutated_q <= 1'b0;
					launch_pending_q <= 1'b0;
					abort_pending_q <= 1'b0;
					stop_rearm_block_q <= 1'b1;
					ss_stopped_o <= 1'b0;
					ss_restore_launch_done_o <= 1'b0;
				end else begin
					ss_terminal_fault_o <= 1'b1;
				end
			end
		end
	end

endmodule

`default_nettype wire
