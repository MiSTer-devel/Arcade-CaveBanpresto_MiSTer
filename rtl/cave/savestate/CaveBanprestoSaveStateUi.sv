// SPDX-License-Identifier: GPL-2.0-or-later
//
// CaveBanpresto-local MiSTer save-state UI decoder.
//
// Keyboard, joystick, and OSD inputs are edge-qualified into one-cycle save
// and load requests. Input histories continue to track while save states are
// disabled so an input asserted during reset/download cannot become a deferred
// request when the core later enables save-state service. The operation slot
// is registered independently from the displayed slot so auto-increment can
// update the menu without changing the slot attached to the current request.
//
// hps_io consumes status_set and info_req on rising edges. Notification pulses
// therefore have an enforced low gap; one pending event retains the latest
// status snapshot or information value during that gap.

`default_nettype none

module CaveBanprestoSaveStateUi #(
	parameter integer INFO_TIMEOUT_BITS = 25
) (
	input  wire                         clk,
	input  wire                         reset,
	input  wire [10:0]                  ps2_key,
	input  wire                         allow_ss,
	input  wire                         joy_ss,
	input  wire                         joy_right,
	input  wire                         joy_left,
	input  wire                         joy_down,
	input  wire                         joy_up,
	input  wire [1:0]                   status_slot,
	input  wire                         autoinc_slot,
	input  wire [1:0]                   osd_saveload,
	output logic                        save_request,
	output logic                        load_request,
	output logic                        info_request,
	output logic [7:0]                  info,
	output logic                        status_update,
	output wire [1:0]                   selected_slot,
	output wire [1:0]                   request_slot
);

	// A zero override is coerced to one bit so elaboration remains defined.
	// With N effective bits, help fires after 2**(N-1)+1 continuously held
	// enabled cycles and repeats at that same interval.
	localparam integer INFO_TIMER_BITS =
		(INFO_TIMEOUT_BITS < 1) ? 1 : INFO_TIMEOUT_BITS;

	// Justification (reg-a): selected slot persists between UI events.
	logic [1:0] slot_q;
	logic [1:0] slot_d;
	// Justification (reg-a): binds a request to its source slot even when the
	// displayed slot auto-increments on the same edge.
	logic [1:0] request_slot_q;
	logic [1:0] request_slot_d;
	// Justification (reg-a): edge histories prevent held inputs from repeating.
	logic last_right_q;
	logic last_left_q;
	logic last_down_q;
	logic last_up_q;
	logic old_key_state_q;
	logic [1:0] old_osd_saveload_q;
	logic [1:0] last_status_slot_q;
	logic alt_q;
	logic alt_d;
	// Justification (reg-a): bounds the held-save-button help-text interval.
	logic [INFO_TIMER_BITS-1:0] info_wait_q;
	logic [INFO_TIMER_BITS-1:0] info_wait_d;
	// Justification (reg-d): hps_io accepts notifications only on rising edges;
	// these bits retain one latest-value event across the mandatory low gap.
	logic status_pending_q;
	logic status_pending_d;
	logic info_pending_q;
	logic info_pending_d;
	logic [7:0] info_pending_data_q;
	logic [7:0] info_pending_data_d;

	logic [1:0] event_slot;
	logic [1:0] navigation_slot;
	logic [1:0] key_slot;
	logic key_save_candidate;
	logic key_load_candidate;
	logic joy_save_candidate;
	logic joy_load_candidate;
	logic osd_save_candidate;
	logic osd_load_candidate;
	logic nav_right_candidate;
	logic nav_left_candidate;
	logic [2:0] operation_event_count;
	logic [1:0] navigation_event_count;
	logic status_event;
	logic info_event;
	logic [7:0] info_event_data;
	logic save_request_d;
	logic load_request_d;
	logic status_update_d;
	logic info_request_d;
	logic [7:0] info_d;

	wire allow_known_high = allow_ss === 1'b1;
	wire status_slot_known =
		(status_slot === 2'd0) ||
		(status_slot === 2'd1) ||
		(status_slot === 2'd2) ||
		(status_slot === 2'd3);
	wire last_status_slot_known =
		(last_status_slot_q === 2'd0) ||
		(last_status_slot_q === 2'd1) ||
		(last_status_slot_q === 2'd2) ||
		(last_status_slot_q === 2'd3);
	wire status_slot_sync =
		status_slot_known &&
		(!last_status_slot_known ||
		 (last_status_slot_q != status_slot));
	wire autoinc_known =
		(autoinc_slot === 1'b0) ||
		(autoinc_slot === 1'b1);
	wire key_toggle_known =
		(ps2_key[10] === 1'b0) ||
		(ps2_key[10] === 1'b1);
	wire old_key_toggle_known =
		(old_key_state_q === 1'b0) ||
		(old_key_state_q === 1'b1);
	wire key_pressed_known =
		(ps2_key[9] === 1'b0) ||
		(ps2_key[9] === 1'b1);
	wire key_pressed_high = ps2_key[9] === 1'b1;
	wire key_event =
		key_toggle_known &&
		old_key_toggle_known &&
		(old_key_state_q != ps2_key[10]);
	wire joy_modifier_high = joy_ss === 1'b1;
	wire joy_right_rise =
		(joy_right === 1'b1) && (last_right_q === 1'b0);
	wire joy_left_rise =
		(joy_left === 1'b1) && (last_left_q === 1'b0);
	wire joy_down_rise =
		(joy_down === 1'b1) && (last_down_q === 1'b0);
	wire joy_up_rise =
		(joy_up === 1'b1) && (last_up_q === 1'b0);
	wire osd_save_rise =
		(osd_saveload[0] === 1'b1) &&
		(old_osd_saveload_q[0] === 1'b0);
	wire osd_load_rise =
		(osd_saveload[1] === 1'b1) &&
		(old_osd_saveload_q[1] === 1'b0);

	assign selected_slot = slot_q;
	assign request_slot = request_slot_q;

	always_comb begin
		slot_d = slot_q;
		request_slot_d = request_slot_q;
		alt_d = alt_q;
		info_wait_d = info_wait_q;
		status_pending_d = status_pending_q;
		info_pending_d = info_pending_q;
		info_pending_data_d = info_pending_data_q;
		key_slot = slot_q;
		key_save_candidate = 1'b0;
		key_load_candidate = 1'b0;
		joy_save_candidate = 1'b0;
		joy_load_candidate = 1'b0;
		osd_save_candidate = 1'b0;
		osd_load_candidate = 1'b0;
		nav_right_candidate = 1'b0;
		nav_left_candidate = 1'b0;
		operation_event_count = 3'd0;
		navigation_event_count = 2'd0;
		event_slot = slot_q;
		navigation_slot = slot_q;
		status_event = 1'b0;
		info_event = 1'b0;
		info_event_data = info;
		save_request_d = 1'b0;
		load_request_d = 1'b0;
		status_update_d = 1'b0;
		info_request_d = 1'b0;
		info_d = info;

		// Track a known physical Alt event even while service is disabled.
		if (key_event &&
		    key_pressed_known &&
		    (ps2_key[7:0] === 8'h11))
			alt_d = key_pressed_high;

		// An HPS/OSD slot change remains authoritative even during reset,
		// download, or an unsupported runtime profile. It has priority over
		// every local event in the same cycle; those edges are consumed.
		if (status_slot_sync) begin
			slot_d = status_slot;
			info_wait_d = {INFO_TIMER_BITS{1'b0}};
		end else if (allow_known_high &&
		             status_slot_known &&
		             autoinc_known) begin
			if (key_event) begin
				unique case (ps2_key[7:0])
					8'h05: begin
						key_save_candidate =
							key_pressed_high && alt_q;
						key_load_candidate =
							key_pressed_high && !alt_q;
						key_slot = 2'd0;
					end
					8'h06: begin
						key_save_candidate =
							key_pressed_high && alt_q;
						key_load_candidate =
							key_pressed_high && !alt_q;
						key_slot = 2'd1;
					end
					8'h04: begin
						key_save_candidate =
							key_pressed_high && alt_q;
						key_load_candidate =
							key_pressed_high && !alt_q;
						key_slot = 2'd2;
					end
					8'h0c: begin
						key_save_candidate =
							key_pressed_high && alt_q;
						key_load_candidate =
							key_pressed_high && !alt_q;
						key_slot = 2'd3;
					end
					default: begin
					end
				endcase
			end

			if (joy_modifier_high) begin
				info_wait_d =
					info_wait_q +
					{{(INFO_TIMER_BITS-1){1'b0}}, 1'b1};
				if (info_wait_q[INFO_TIMER_BITS-1]) begin
					info_event = 1'b1;
					info_event_data = 8'd1;
					info_wait_d = {INFO_TIMER_BITS{1'b0}};
				end

				nav_right_candidate = joy_right_rise;
				nav_left_candidate = joy_left_rise;
				joy_save_candidate = joy_down_rise;
				joy_load_candidate = joy_up_rise;
			end else begin
				info_wait_d = {INFO_TIMER_BITS{1'b0}};
			end

			osd_save_candidate = osd_save_rise;
			osd_load_candidate = osd_load_rise;

			operation_event_count =
				{2'd0, key_save_candidate} +
				{2'd0, key_load_candidate} +
				{2'd0, joy_save_candidate} +
				{2'd0, joy_load_candidate} +
				{2'd0, osd_save_candidate} +
				{2'd0, osd_load_candidate};
			navigation_event_count =
				{1'b0, nav_right_candidate} +
				{1'b0, nav_left_candidate};

			// Any simultaneous operation sources, simultaneous navigation
			// directions, or operation-plus-navigation combination is
			// ambiguous. Suppress requests and every slot/status side effect.
			if ((operation_event_count > 3'd1) ||
			    (navigation_event_count > 2'd1) ||
			    ((operation_event_count != 3'd0) &&
			     (navigation_event_count != 2'd0))) begin
				info_event = 1'b0;
				info_wait_d = {INFO_TIMER_BITS{1'b0}};
			end else if (operation_event_count == 3'd1) begin
				if (key_save_candidate ||
				    key_load_candidate) begin
					event_slot = key_slot;
					slot_d = key_slot;
					status_event = 1'b1;
					save_request_d = key_save_candidate;
					load_request_d = key_load_candidate;
				end else if (joy_save_candidate ||
				             joy_load_candidate) begin
					event_slot = slot_q;
					save_request_d = joy_save_candidate;
					load_request_d = joy_load_candidate;
					if (joy_save_candidate &&
					    (autoinc_slot === 1'b1)) begin
						slot_d = slot_q + 2'd1;
						status_event = 1'b1;
					end
				end else begin
					event_slot = slot_q;
					save_request_d = osd_save_candidate;
					load_request_d = osd_load_candidate;
					if (osd_save_candidate &&
					    (autoinc_slot === 1'b1)) begin
						slot_d = slot_q + 2'd1;
						status_event = 1'b1;
					end
				end

				request_slot_d = event_slot;
				info_event = 1'b1;
				info_event_data =
					8'd6 +
					{5'd0, event_slot, load_request_d};
				info_wait_d = {INFO_TIMER_BITS{1'b0}};
			end else if (navigation_event_count == 2'd1) begin
				if (nav_right_candidate &&
				    (slot_q < 2'd3)) begin
					navigation_slot = slot_q + 2'd1;
					slot_d = navigation_slot;
					status_event = 1'b1;
					info_event = 1'b1;
					info_event_data =
						8'd2 +
						{6'd0, navigation_slot};
				end else if (nav_left_candidate &&
				             (slot_q > 2'd0)) begin
					navigation_slot = slot_q - 2'd1;
					slot_d = navigation_slot;
					status_event = 1'b1;
					info_event = 1'b1;
					info_event_data =
						8'd2 +
						{6'd0, navigation_slot};
				end
				info_wait_d = {INFO_TIMER_BITS{1'b0}};
			end
		end else begin
			info_wait_d = {INFO_TIMER_BITS{1'b0}};
		end

		// Enforce a low cycle between hps_io status_set rising edges. Status
		// updates are latest-slot semantics, so a single pending bit safely
		// coalesces any faster local changes.
		if (!allow_known_high) begin
			status_update_d = 1'b0;
			status_pending_d = 1'b0;
		end else if (status_update) begin
			status_update_d = 1'b0;
			if (status_event)
				status_pending_d = 1'b1;
		end else if (status_pending_q) begin
			status_update_d = 1'b1;
			status_pending_d = status_event;
		end else if (status_event) begin
			status_update_d = 1'b1;
		end

		// Info notifications use the same rising-edge contract, retaining the
		// newest value when another event arrives during the low-gap cycle.
		if (!allow_known_high) begin
			info_request_d = 1'b0;
			info_pending_d = 1'b0;
		end else if (info_request) begin
			info_request_d = 1'b0;
			if (info_event) begin
				info_pending_d = 1'b1;
				info_pending_data_d = info_event_data;
			end
		end else if (info_pending_q) begin
			info_request_d = 1'b1;
			info_d = info_pending_data_q;
			if (info_event) begin
				info_pending_d = 1'b1;
				info_pending_data_d = info_event_data;
			end else begin
				info_pending_d = 1'b0;
			end
		end else if (info_event) begin
			info_request_d = 1'b1;
			info_d = info_event_data;
		end
	end

	always_ff @(posedge clk) begin
		if (reset) begin
			if (status_slot_known)
				slot_q <= status_slot;
			else
				slot_q <= 2'd0;
			request_slot_q <= 2'd0;
			alt_q <= 1'b0;
			info_wait_q <= {INFO_TIMER_BITS{1'b0}};
			last_right_q <= joy_right;
			last_left_q <= joy_left;
			last_down_q <= joy_down;
			last_up_q <= joy_up;
			old_key_state_q <= ps2_key[10];
			old_osd_saveload_q <= osd_saveload;
			last_status_slot_q <= status_slot;
			status_pending_q <= 1'b0;
			info_pending_q <= 1'b0;
			info_pending_data_q <= 8'd0;
			save_request <= 1'b0;
			load_request <= 1'b0;
			info_request <= 1'b0;
			info <= 8'd0;
			status_update <= 1'b0;
		end else begin
			slot_q <= slot_d;
			request_slot_q <= request_slot_d;
			alt_q <= alt_d;
			info_wait_q <= info_wait_d;
			last_right_q <= joy_right;
			last_left_q <= joy_left;
			last_down_q <= joy_down;
			last_up_q <= joy_up;
			old_key_state_q <= ps2_key[10];
			old_osd_saveload_q <= osd_saveload;
			last_status_slot_q <= status_slot;
			status_pending_q <= status_pending_d;
			info_pending_q <= info_pending_d;
			info_pending_data_q <= info_pending_data_d;
			save_request <= save_request_d;
			load_request <= load_request_d;
			info_request <= info_request_d;
			info <= info_d;
			status_update <= status_update_d;
		end
	end

endmodule

`default_nettype wire
