`timescale 1ns/1ps
// M2.1 experimental sensor-to-dataflow bridge.
// Four-lane SEF events -> dual tagged XDF graph instances -> decision output.
// The fixed demonstration graph is SUB(raw, smoothed) -> OUTPUT.
// The processor remains independently programmable elsewhere; this wrapper
// intentionally fixes its graph so the first end-to-end contract is auditable.
// No asynchronous sensor clock crossing, external peripherals or fail-safe I/O.
module xdf_sensor_pipeline #(
  parameter int N_SENSORS = 64,
  parameter int LANES = 4,
  parameter logic [31:0] DELTA_LIMIT = 32'd20
) (
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic [LANES-1:0]     sensor_valid,
  output logic [LANES-1:0]     sensor_ready,
  input  logic [LANES*96-1:0]  sensor_event,
  input  logic                 cfg_valid,
  output logic                 cfg_ready,
  input  logic                 cfg_group,
  input  logic [7:0]           cfg_index,
  input  logic signed [33:0]   cfg_threshold,
  output logic                 decision_valid,
  input  logic                 decision_ready,
  output logic [196:0]         decision_data,
  input  logic [3:0]           debug_stall_tiles,
  output logic                 initialized,
  output logic [1:0]           inflight,
  output logic                 pipeline_error,
  output logic [7:0]           core_error_code,
  output logic                 sensor_fault_valid,
  output logic [7:0]           sensor_fault_code,
  output logic [7:0]           sensor_fault_id,
  output logic [31:0]          sensor_accepted,
  output logic [31:0]          sensor_processed,
  output logic [31:0]          sensor_faults
);
  import xdf_pkg::*;

  logic sef_result_valid, sef_result_ready;
  logic [163:0] sef_result;
  xdf_sensory #(.N_SENSORS(N_SENSORS), .LANES(LANES)) sensory (
    .clk(clk), .rst_n(rst_n),
    .in_valid(sensor_valid), .in_ready(sensor_ready), .in_event(sensor_event),
    .result_valid(sef_result_valid), .result_ready(sef_result_ready),
    .result_data(sef_result),
    .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
    .cfg_group(cfg_group), .cfg_index(cfg_index), .cfg_threshold(cfg_threshold),
    .fault_valid(sensor_fault_valid), .fault_code(sensor_fault_code),
    .fault_sensor(sensor_fault_id),
    .accepted_count(sensor_accepted), .processed_count(sensor_processed),
    .fault_count(sensor_faults)
  );

  typedef enum logic [2:0] {
    LOAD_SUB=3'd0, LOAD_OUTPUT=3'd1, WAIT_EVENT=3'd2,
    SEND_RAW=3'd3, SEND_ESTIMATE=3'd4
  } bridge_state_t;
  bridge_state_t state;
  logic [1:0] live;
  logic [163:0] event_meta [0:1];
  logic [7:0] epoch_meta [0:1];
  logic [7:0] next_epoch, launch_epoch;
  logic launch_slot;
  logic bridge_bad_result;
  logic [1:0] core_slots;
  logic core_cfg_valid, core_cfg_ready;
  logic core_begin_valid, core_begin_ready;
  logic core_input_valid, core_input_ready;
  logic [63:0] core_input_token;
  logic core_output_valid, core_output_ready;
  logic [63:0] core_output_token;
  logic core_error_valid;
  logic [7:0] core_error_node;
  logic [31:0] core_error_count;

  assign initialized = (state != LOAD_SUB && state != LOAD_OUTPUT);
  assign inflight = live;
  assign pipeline_error = bridge_bad_result || core_error_valid;
  assign core_cfg_valid = state == LOAD_SUB || state == LOAD_OUTPUT;

  logic [7:0] core_cfg_node, core_cfg_dest;
  logic [2:0] core_cfg_opcode;
  always_comb begin
    core_cfg_node = 8'd0;
    core_cfg_dest = 8'd24;
    core_cfg_opcode = OP_SUB;
    if (state == LOAD_OUTPUT) begin
      core_cfg_node = 8'd24;
      core_cfg_dest = 8'd0;
      core_cfg_opcode = OP_OUTPUT;
    end
  end

  logic free_slot_valid, free_slot;
  assign free_slot_valid = live != 2'b11;
  assign free_slot = live[0]; // slot 0 first, otherwise slot 1
  // A SEF result and the corresponding core BEGIN are accepted atomically.
  // The intermediate SEF output is held until an XDF context is available.
  assign core_begin_valid = state == WAIT_EVENT && sef_result_valid &&
                            free_slot_valid && !pipeline_error;
  assign sef_result_ready = state == WAIT_EVENT && free_slot_valid &&
                            core_begin_ready && !pipeline_error;

  assign core_input_valid = (state == SEND_RAW || state == SEND_ESTIMATE) &&
                            !pipeline_error;
  assign core_input_token = pack_token(
    state == SEND_RAW ? event_meta[launch_slot][31:0] :
                        event_meta[launch_slot][127:96],
    launch_epoch, 8'd0,
    state == SEND_RAW ? 4'd0 : 4'd1,
    {3'b000,launch_slot}
  );

  wire result_slot = core_output_token[52];
  wire result_tag_matches = core_output_token[55:53] == 3'b000 &&
      core_output_token[63:56] == 8'b0 &&
      core_output_token[47:40] == 8'd24 &&
      core_output_token[51:48] == 4'd0 &&
      live[result_slot] && epoch_meta[result_slot] == core_output_token[39:32];
  wire output_space = !decision_valid || decision_ready;
  // Keep output readiness independent of token fields. This avoids a
  // combinational ready/data loop through top-level result arbitration.
  // Unexpected results are consumed only to raise a sticky fatal error.
  assign core_output_ready = output_space && !pipeline_error;

  wire signed [32:0] signed_delta = {core_output_token[31],core_output_token[31:0]};
  wire [32:0] abs_delta = signed_delta[32] ?
                         $unsigned(-signed_delta) : $unsigned(signed_delta);
  wire critical = event_meta[result_slot][163] || event_meta[result_slot][162] ||
                  (abs_delta >= {1'b0,DELTA_LIMIT});

  xdf_top core (
    .clk(clk), .rst_n(rst_n),
    .cfg_valid(core_cfg_valid), .cfg_ready(core_cfg_ready),
    .cfg_node(core_cfg_node), .cfg_op(core_cfg_opcode),
    .cfg_dest_node(core_cfg_dest), .cfg_dest_port(4'd0),
    .begin_valid(core_begin_valid), .begin_ready(core_begin_ready),
    .begin_context({3'b000,free_slot}), .begin_epoch(next_epoch),
    .host_in_valid(core_input_valid), .host_in_ready(core_input_ready),
    .host_in_token(core_input_token),
    .host_result_valid(core_output_valid), .host_result_ready(core_output_ready),
    .host_result_token(core_output_token),
    .debug_stall_tiles(debug_stall_tiles),
    .clear_errors(1'b0), .error_valid(core_error_valid),
    .error_code(core_error_code), .error_node(core_error_node),
    .error_count(core_error_count), .active_slots(core_slots)
  );

  // Each metadata slot has one elaborated writer, avoiding dynamic-index
  // register writes that can produce bad sv2v/Yosys driver resolution.
  wire begin_fire = core_begin_valid && core_begin_ready;
  wire complete_fire = core_output_valid && core_output_ready && result_tag_matches;
  for (genvar slot=0;slot<2;slot++) begin : metadata_slots
    always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        live[slot] <= 1'b0;
        event_meta[slot] <= '0;
        epoch_meta[slot] <= '0;
      end else begin
        if (begin_fire && free_slot == 1'(slot)) begin
          event_meta[slot] <= sef_result;
          epoch_meta[slot] <= next_epoch;
          live[slot] <= 1'b1;
        end
        if (complete_fire && result_slot == 1'(slot))
          live[slot] <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= LOAD_SUB;
      launch_slot <= 1'b0;
      launch_epoch <= 8'b0;
      next_epoch <= 8'b0;
      bridge_bad_result <= 1'b0;
      decision_valid <= 1'b0;
      decision_data <= '0;
    end else begin
      if (core_output_valid && !result_tag_matches)
        bridge_bad_result <= 1'b1;
      case (state)
        LOAD_SUB: if (core_cfg_ready) state <= LOAD_OUTPUT;
        LOAD_OUTPUT: if (core_cfg_ready) state <= WAIT_EVENT;
        WAIT_EVENT: if (sef_result_valid && sef_result_ready) begin
          launch_slot <= free_slot;
          launch_epoch <= next_epoch;
          next_epoch <= next_epoch + 8'd1;
          state <= SEND_RAW;
        end
        SEND_RAW: if (core_input_valid && core_input_ready) state <= SEND_ESTIMATE;
        SEND_ESTIMATE: if (core_input_valid && core_input_ready) state <= WAIT_EVENT;
        default: state <= LOAD_SUB;
      endcase

      if (decision_valid && decision_ready) decision_valid <= 1'b0;
      if (core_output_valid && core_output_ready && result_tag_matches) begin
        decision_valid <= 1'b1;
        decision_data <= {critical,core_output_token[31:0],event_meta[result_slot]};
      end
    end
  end
endmodule
