`timescale 1ns/1ps
// XDF-1 M2.2B: autonomous, programmable reflex + neural-metadata dispatch.
// Source is a VALIDATED 164-bit xdf_sensory result, not raw camera/audio bytes.
// Background context is deliberately best-effort unless CONTEXT_LOSSLESS=1;
// every overflow is reported, including protected-alarm context loss.
// Registered reflex decisions never wait on context_ready in best-effort mode.
module xdf_reflex #(
  parameter int RULES = 8,
  parameter bit CONTEXT_LOSSLESS = 1'b0
) (
  input  logic            clk,
  input  logic            rst_n,
  input  logic            in_valid,
  output logic            in_ready,
  input  logic [163:0]    in_data,
  output logic            reflex_valid,
  input  logic            reflex_ready,
  output logic [175:0]    reflex_data,
  output logic            context_valid,
  input  logic            context_ready,
  output logic [175:0]    context_data,
  // Rule writes are accepted only when both output buffers and ingress idle.
  // cfg_index==8'hff sets the default action, otherwise configures a rule.
  input  logic            cfg_valid,
  output logic            cfg_ready,
  input  logic [7:0]      cfg_index,
  input  logic            cfg_enabled,
  input  logic [7:0]      cfg_sensor,
  input  logic [1:0]      cfg_mode,
  input  logic signed [31:0] cfg_threshold,
  input  logic [1:0]      cfg_action,
  output logic            cfg_fault,
  // Counts wrap naturally at 2^32. An admitted observation may be delivered
  // to zero, one or both paths. `context_drop` counts admitted lossy events.
  output logic [31:0]     accepted_count,
  output logic [31:0]     filtered_count,
  output logic [31:0]     reflex_count,
  output logic [31:0]     context_count,
  output logic [31:0]     context_drop_count,
  output logic [31:0]     protected_context_drop_count
);
  // Actions: 0=DROP, 1=CONTEXT, 2=REFLEX, 3=BOTH.
  // Modes: 0=ALWAYS, 1=RAW >= THRESHOLD (signed),
  //        2=ABS(RAW-EMA) >= THRESHOLD (nonnegative), 3=GROUP_ALARM.
  initial begin
    assert (RULES >= 1 && RULES <= 32)
      else $fatal(1, "RULES must be within 1..32");
  end
  logic              rule_enabled [0:RULES-1];
  logic [7:0]        rule_sensor [0:RULES-1];
  logic [1:0]        rule_mode [0:RULES-1];
  logic signed [31:0] rule_threshold [0:RULES-1];
  logic [1:0]        rule_action [0:RULES-1];
  logic [1:0]        default_action;
  logic [RULES-1:0] rule_match;

  wire [7:0] sensor_id = in_data[71:64];
  wire signed [31:0] sample = in_data[31:0];
  wire signed [31:0] ema = in_data[127:96];
  wire sensor_alarm = in_data[162];
  wire group_alarm = in_data[163];
  wire protected_event = sensor_alarm || group_alarm;
  // Widen BEFORE subtraction, avoiding 32-bit wrap of the absolute delta.
  wire signed [32:0] delta =
      $signed({sample[31],sample}) - $signed({ema[31],ema});
  wire [32:0] delta_magnitude = delta[32] ? $unsigned(-delta) : $unsigned(delta);

  for(genvar r=0; r<RULES; r++) begin : config_rule
    always_ff @(posedge clk or negedge rst_n) begin
      if(!rst_n) begin
        rule_enabled[r] <= 1'b0;
        rule_sensor[r] <= 8'hff;
        rule_mode[r] <= 2'b00;
        rule_threshold[r] <= 32'sd0;
        rule_action[r] <= 2'b00;
      end else if(cfg_valid && cfg_ready && cfg_index == 8'(r) &&
                  !(cfg_mode == 2'd2 && cfg_threshold[31])) begin
        rule_enabled[r] <= cfg_enabled;
        rule_sensor[r] <= cfg_sensor;
        rule_mode[r] <= cfg_mode;
        rule_threshold[r] <= cfg_threshold;
        rule_action[r] <= cfg_action;
      end
    end
    always_comb begin
      rule_match[r] = 1'b0;
      if(rule_enabled[r] &&
         (rule_sensor[r] == 8'hff || rule_sensor[r] == sensor_id)) begin
        case(rule_mode[r])
          2'd0: rule_match[r] = 1'b1;
          2'd1: rule_match[r] = sample >= rule_threshold[r];
          2'd2: rule_match[r] = delta_magnitude >= {1'b0,rule_threshold[r]};
          2'd3: rule_match[r] = group_alarm;
          default: rule_match[r] = 1'b0;
        endcase
      end
    end
  end

  logic [1:0] chosen_action;
  logic [7:0] chosen_rule;
  logic matched;
  logic [3:0] reason;
  logic to_reflex, to_context;
  logic [175:0] dispatch_data;
  always_comb begin
    chosen_action = default_action;
    chosen_rule = 8'hff;
    matched = 1'b0;
    for(int r=0; r<RULES; r++) begin
      if(!matched && rule_match[r]) begin
        chosen_action = rule_action[r];
        chosen_rule = 8'(r);
        matched = 1'b1;
      end
    end
    // Non-maskable by configuration: all validated SEF alarm events take
    // the reflex path AND request contextual evidence. An exhausted context
    // sink may lose evidence only in explicit best-effort mode, with counters.
    if(protected_event) chosen_action = chosen_action | 2'b11;
    to_reflex = chosen_action[1];
    to_context = chosen_action[0];
    reason = {protected_event,matched,group_alarm,sensor_alarm};
    dispatch_data = {chosen_rule,reason,in_data};
  end

  wire reflex_space = !reflex_valid || reflex_ready;
  wire context_space = !context_valid || context_ready;
  assign cfg_ready = !in_valid && !reflex_valid && !context_valid;
  assign in_ready = !cfg_valid &&
      (!in_valid || ((!to_reflex || reflex_space) &&
       (!CONTEXT_LOSSLESS || !to_context || context_space)));
  wire accept = in_valid && in_ready;
  wire loss = accept && to_context && !context_space;

  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      default_action <= 2'b00;
      cfg_fault <= 1'b0;
      reflex_valid <= 1'b0;
      reflex_data <= '0;
      context_valid <= 1'b0;
      context_data <= '0;
      accepted_count <= '0;
      filtered_count <= '0;
      reflex_count <= '0;
      context_count <= '0;
      context_drop_count <= '0;
      protected_context_drop_count <= '0;
    end else begin
      cfg_fault <= 1'b0;
      if(cfg_valid && cfg_ready) begin
        if(cfg_index == 8'hff)
          default_action <= cfg_action;
        else if(int'(cfg_index) >= RULES || (cfg_mode == 2'd2 && cfg_threshold[31]))
          cfg_fault <= 1'b1;
      end
      if(reflex_space) begin
        reflex_valid <= accept && to_reflex;
        if(accept && to_reflex) reflex_data <= dispatch_data;
      end
      if(context_space) begin
        context_valid <= accept && to_context;
        if(accept && to_context) context_data <= dispatch_data;
      end
      if(accept) begin
        accepted_count <= accepted_count + 32'd1;
        if(!to_reflex && !to_context)
          filtered_count <= filtered_count + 32'd1;
        if(to_reflex)
          reflex_count <= reflex_count + 32'd1;
        if(to_context && context_space)
          context_count <= context_count + 32'd1;
      end
      if(loss) begin
        context_drop_count <= context_drop_count + 32'd1;
        if(protected_event)
          protected_context_drop_count <= protected_context_drop_count + 32'd1;
      end
    end
  end
endmodule
