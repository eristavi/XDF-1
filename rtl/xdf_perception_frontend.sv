`timescale 1ns/1ps
// M2.2B parallel reflex and neural-ready metadata front end.
// Existing M2.1 XDF graph pipeline is intentionally left unchanged.
// Sensor observations pass through the existing SEF validation/state logic,
// then independently fan out to a bounded reflex and context output.
module xdf_perception_frontend #(
  parameter int N_SENSORS = 64,
  parameter int LANES = 4,
  parameter int RULES = 8,
  parameter bit CONTEXT_LOSSLESS = 1'b0
) (
  input  logic                   clk,
  input  logic                   rst_n,
  input  logic [LANES-1:0]       sensor_valid,
  output logic [LANES-1:0]       sensor_ready,
  input  logic [LANES*96-1:0]    sensor_event,
  input  logic                   sensor_cfg_valid,
  output logic                   sensor_cfg_ready,
  input  logic                   sensor_cfg_group,
  input  logic [7:0]             sensor_cfg_index,
  input  logic signed [33:0]     sensor_cfg_threshold,
  input  logic                   rule_cfg_valid,
  output logic                   rule_cfg_ready,
  input  logic [7:0]             rule_cfg_index,
  input  logic                   rule_cfg_enabled,
  input  logic [7:0]             rule_cfg_sensor,
  input  logic [1:0]             rule_cfg_mode,
  input  logic signed [31:0]     rule_cfg_threshold,
  input  logic [1:0]             rule_cfg_action,
  output logic                   rule_cfg_fault,
  output logic                   reflex_valid,
  input  logic                   reflex_ready,
  output logic [175:0]           reflex_data,
  output logic                   context_valid,
  input  logic                   context_ready,
  output logic [175:0]           context_data,
  output logic                   sensor_fault_valid,
  output logic [7:0]             sensor_fault_code,
  output logic [7:0]             sensor_fault_id,
  output logic [31:0]            sensor_accepted,
  output logic [31:0]            sensor_processed,
  output logic [31:0]            sensor_faults,
  output logic [31:0]            event_accepted,
  output logic [31:0]            event_filtered,
  output logic [31:0]            event_reflex,
  output logic [31:0]            event_context,
  output logic [31:0]            context_dropped,
  output logic [31:0]            protected_context_dropped
);
  logic sef_valid, sef_ready;
  logic [163:0] sef_data;
  logic sef_cfg_ready, classifier_cfg_ready;
  logic sef_cfg_fire, classifier_cfg_fire;

  // Both configuration interfaces require the WHOLE FRONTEND to be idle;
  // neither is allowed to reprogram rules mid-flight.
  assign sensor_cfg_ready = sef_cfg_ready && classifier_cfg_ready && !rule_cfg_valid;
  assign rule_cfg_ready = sef_cfg_ready && classifier_cfg_ready && !sensor_cfg_valid;
  assign sef_cfg_fire = sensor_cfg_valid && sensor_cfg_ready;
  assign classifier_cfg_fire = rule_cfg_valid && sef_cfg_ready && !sensor_cfg_valid;

  xdf_sensory #(.N_SENSORS(N_SENSORS), .LANES(LANES)) acquisition (
    .clk(clk), .rst_n(rst_n),
    .in_valid(sensor_valid), .in_ready(sensor_ready), .in_event(sensor_event),
    .result_valid(sef_valid), .result_ready(sef_ready), .result_data(sef_data),
    .cfg_valid(sef_cfg_fire), .cfg_ready(sef_cfg_ready),
    .cfg_group(sensor_cfg_group), .cfg_index(sensor_cfg_index),
    .cfg_threshold(sensor_cfg_threshold),
    .fault_valid(sensor_fault_valid), .fault_code(sensor_fault_code),
    .fault_sensor(sensor_fault_id),
    .accepted_count(sensor_accepted), .processed_count(sensor_processed),
    .fault_count(sensor_faults)
  );

  xdf_reflex #(.RULES(RULES), .CONTEXT_LOSSLESS(CONTEXT_LOSSLESS)) decisions (
    .clk(clk), .rst_n(rst_n),
    .in_valid(sef_valid), .in_ready(sef_ready), .in_data(sef_data),
    .reflex_valid(reflex_valid), .reflex_ready(reflex_ready),
    .reflex_data(reflex_data),
    .context_valid(context_valid), .context_ready(context_ready),
    .context_data(context_data),
    .cfg_valid(classifier_cfg_fire), .cfg_ready(classifier_cfg_ready),
    .cfg_index(rule_cfg_index), .cfg_enabled(rule_cfg_enabled),
    .cfg_sensor(rule_cfg_sensor), .cfg_mode(rule_cfg_mode),
    .cfg_threshold(rule_cfg_threshold), .cfg_action(rule_cfg_action),
    .cfg_fault(rule_cfg_fault),
    .accepted_count(event_accepted), .filtered_count(event_filtered),
    .reflex_count(event_reflex), .context_count(event_context),
    .context_drop_count(context_dropped),
    .protected_context_drop_count(protected_context_dropped)
  );
endmodule
