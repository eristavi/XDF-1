`timescale 1ns/1ps
// XDF-1 SEF proof-of-concept: 4 simultaneous ready/valid input lanes,
// configurable logical sensor state, one bounded processing issue per cycle.
// This is an independently testable sensor front-end; it is NOT yet wired to
// the XDF-1 DAG tiles, clock synchronization, external sensors or actuators.
//
// Event[95:0]: reserved[3:0], kind[1:0], priority[1:0], sequence[15:0],
//              sensor_id[7:0], timestamp[31:0], signed_value[31:0].
// Result[163:0]: group_alarm, sensor_alarm, signed_group_sum[33:0],
//                 signed_smoothed_value[31:0], original_event[95:0].
module xdf_sensory #(
  parameter int N_SENSORS = 64,
  parameter int LANES = 4,
  parameter int DEPTH = 2,
  parameter int URGENT_BUDGET = 8
) (
  input  logic                    clk,
  input  logic                    rst_n,
  input  logic [LANES-1:0]        in_valid,
  output logic [LANES-1:0]        in_ready,
  input  logic [LANES*96-1:0]     in_event,
  output logic                    result_valid,
  input  logic                    result_ready,
  output logic [163:0]            result_data,
  // Configuration writes accepted only when the fabric is idle.
  input  logic                    cfg_valid,
  output logic                    cfg_ready,
  input  logic                    cfg_group,
  input  logic [7:0]              cfg_index,
  input  logic signed [33:0]      cfg_threshold,
  output logic                    fault_valid,
  output logic [7:0]              fault_code,
  output logic [7:0]              fault_sensor,
  output logic [31:0]             accepted_count,
  output logic [31:0]             processed_count,
  output logic [31:0]             fault_count
);
  localparam int SENSOR_BITS = $clog2(N_SENSORS);
  localparam int LANE_BITS = (LANES>1) ? $clog2(LANES) : 1;
  localparam int PTR_BITS = (DEPTH>1) ? $clog2(DEPTH) : 1;
  localparam int CNT_BITS = $clog2(DEPTH+1);
  localparam int GROUPS = N_SENSORS/4;
  localparam int GROUP_BITS = (GROUPS>1) ? $clog2(GROUPS) : 1;
  localparam int STREAK_BITS = $clog2(URGENT_BUDGET+1);

  localparam logic [7:0] FAULT_BAD_SENSOR=8'd1;
  localparam logic [7:0] FAULT_BAD_KIND=8'd2;
  localparam logic [7:0] FAULT_RESERVED=8'd3;
  localparam logic [7:0] FAULT_SEQUENCE=8'd4;
  localparam logic [7:0] FAULT_TIMESTAMP=8'd5;
  localparam logic [7:0] FAULT_CONFIG=8'd6;

  initial begin
    assert(N_SENSORS>=4 && N_SENSORS<=256 &&
           (N_SENSORS & (N_SENSORS-1))==0)
      else $fatal(1,"N_SENSORS must be power-of-two between 4 and 256");
    assert(LANES>=1 && LANES<=16 && DEPTH>=1 && DEPTH<=16 && URGENT_BUDGET>=1)
      else $fatal(1,"invalid lane, queue depth, or fairness budget");
  end

  // Fixed small FIFO per physical ingress lane. Each can handshake on the same edge.
  logic [95:0] fifo [0:LANES*DEPTH-1];
  logic [PTR_BITS-1:0] head [0:LANES-1];
  logic [PTR_BITS-1:0] tail [0:LANES-1];
  logic [CNT_BITS-1:0] count [0:LANES-1];
  logic [LANES-1:0] lane_valid;
  logic [1:0] lane_priority [0:LANES-1];
  logic [LANE_BITS-1:0] rr_lane, selected_lane;
  logic selected_valid, pop_valid;
  logic [1:0] min_priority, max_priority, chosen_priority;
  logic [STREAK_BITS-1:0] urgent_streak;
  logic [95:0] pop_data;
  logic emit_ready;
  logic idle;

  assign emit_ready = !result_valid || result_ready;
  always_comb begin
    idle = !result_valid;
    for (int i=0;i<LANES;i++) begin
      lane_valid[i] = count[i] != CNT_BITS'(0);
      lane_priority[i] = fifo[i*DEPTH + int'(head[i])][89:88];
      if(lane_valid[i]) idle = 1'b0;
    end
  end
  assign cfg_ready = idle && !(|in_valid);

  always_comb begin
    min_priority = 2'd3;
    max_priority = 2'd0;
    for(int i=0;i<LANES;i++) begin
      if(lane_valid[i]) begin
        if(lane_priority[i] < min_priority) min_priority = lane_priority[i];
        if(lane_priority[i] > max_priority) max_priority = lane_priority[i];
      end
    end
    chosen_priority = urgent_streak >= STREAK_BITS'(URGENT_BUDGET)
                    ? min_priority : max_priority;
    selected_lane = '0;
    selected_valid = 1'b0;
    for(int k=0;k<LANES;k++) begin
      int i;
      i=(int'(rr_lane)+k)%LANES;
      if(!selected_valid && lane_valid[i] && lane_priority[i]==chosen_priority) begin
        selected_valid = 1'b1;
        selected_lane = LANE_BITS'(i);
      end
    end
  end
  assign pop_valid = selected_valid && emit_ready && !cfg_valid;
  assign pop_data = fifo[int'(selected_lane)*DEPTH + int'(head[selected_lane])];

  always_comb begin
    for(int i=0;i<LANES;i++) begin
      in_ready[i] = !cfg_valid &&
        (count[i] < CNT_BITS'(DEPTH) ||
         (pop_valid && selected_lane==LANE_BITS'(i)));
    end
  end

  // Per-lane storage is not dynamically indexed on its write side.
  for(genvar l=0;l<LANES;l++) begin : ingress_lanes
    wire writing = in_valid[l] && in_ready[l];
    wire reading = pop_valid && selected_lane==LANE_BITS'(l);
    // Each physical queue cell has exactly one elaborated writer; a variable
    // index write to a multidimensional array caused sv2v/Yosys to drive
    // signal slices with X in its earlier technology-independent netlist.
    for (genvar d=0;d<DEPTH;d++) begin : storage
      always_ff @(posedge clk) begin
        if (writing && tail[l]==PTR_BITS'(d))
          fifo[l*DEPTH + d] <= in_event[l*96 +: 96];
      end
    end
    always_ff @(posedge clk or negedge rst_n) begin
      if(!rst_n) begin
        head[l] <= '0;
        tail[l] <= '0;
        count[l] <= '0;
      end else begin
        if(writing) begin
          tail[l] <= (tail[l]==PTR_BITS'(DEPTH-1)) ? '0 : tail[l]+PTR_BITS'(1);
        end
        if(reading) begin
          head[l] <= (head[l]==PTR_BITS'(DEPTH-1)) ? '0 : head[l]+PTR_BITS'(1);
        end
        case({writing,reading})
          2'b10: count[l] <= count[l]+CNT_BITS'(1);
          2'b01: count[l] <= count[l]-CNT_BITS'(1);
          default: ;
        endcase
      end
    end
  end

  logic seen [0:N_SENSORS-1];
  logic [15:0] last_seq [0:N_SENSORS-1];
  logic [31:0] last_time [0:N_SENSORS-1];
  logic signed [31:0] last_value [0:N_SENSORS-1];
  logic signed [31:0] estimate [0:N_SENSORS-1];
  logic signed [31:0] sensor_threshold [0:N_SENSORS-1];
  logic signed [33:0] group_sum [0:GROUPS-1];
  logic signed [33:0] group_threshold [0:GROUPS-1];

  wire [7:0] sensor_id = pop_data[71:64];
  wire [SENSOR_BITS-1:0] sensor_index = sensor_id[SENSOR_BITS-1:0];
  wire [GROUP_BITS-1:0] group_index = GROUP_BITS'(sensor_index >> 2);
  wire [15:0] incoming_seq = pop_data[87:72];
  wire [31:0] incoming_time = pop_data[63:32];
  wire signed [31:0] incoming_value = pop_data[31:0];
  // One-hot decoded read selection is an experimental area optimization.
  // It factors the sensor-ID comparison across all six state arrays instead
  // of independently synthesizing dynamic 64:1 indexed read multiplexers.
  logic selected_seen;
  logic [15:0] selected_seq;
  logic [31:0] selected_time;
  logic signed [31:0] selected_last_value;
  logic signed [31:0] selected_estimate;
  logic signed [31:0] selected_threshold;
  always_comb begin
    selected_seen=1'b0;
    selected_seq='0;
    selected_time='0;
    selected_last_value='0;
    selected_estimate='0;
    selected_threshold='0;
    for (int s=0;s<N_SENSORS;s++) begin
      selected_seen |= seen[s] & (sensor_index==SENSOR_BITS'(s));
      selected_seq |= last_seq[s] & {16{sensor_index==SENSOR_BITS'(s)}};
      selected_time |= last_time[s] & {32{sensor_index==SENSOR_BITS'(s)}};
      selected_last_value |= last_value[s] & {32{sensor_index==SENSOR_BITS'(s)}};
      selected_estimate |= estimate[s] & {32{sensor_index==SENSOR_BITS'(s)}};
      selected_threshold |= sensor_threshold[s] & {32{sensor_index==SENSOR_BITS'(s)}};
    end
  end
  wire [15:0] seq_delta = incoming_seq - selected_seq;
  wire [31:0] time_delta = incoming_time - selected_time;
  logic [7:0] detected_fault;
  logic accepted_event;

  always_comb begin
    detected_fault = 8'b0;
    if(int'(sensor_id) >= N_SENSORS) detected_fault = FAULT_BAD_SENSOR;
    else if(pop_data[91:90]!=2'b00) detected_fault = FAULT_BAD_KIND;
    else if(pop_data[95:92]!=4'b0000) detected_fault = FAULT_RESERVED;
    else if(selected_seen && (seq_delta==16'h0 || seq_delta[15]))
      detected_fault = FAULT_SEQUENCE;
    else if(selected_seen && time_delta!=32'h0 && time_delta[31])
      detected_fault = FAULT_TIMESTAMP;
  end
  assign accepted_event = pop_valid && detected_fault == 8'b0;

  wire signed [31:0] previous_value = selected_seen ? selected_last_value : 32'sd0;
  wire signed [32:0] previous_est_ext = {selected_estimate[31],selected_estimate};
  wire signed [32:0] sample_ext = {incoming_value[31],incoming_value};
  wire signed [32:0] difference = sample_ext - previous_est_ext;
  wire signed [32:0] estimate_ext = previous_est_ext + (difference >>> 2);
  wire signed [31:0] new_estimate = selected_seen ? estimate_ext[31:0] : incoming_value;
  wire signed [33:0] old_group = group_sum[group_index];
  wire signed [33:0] new_group = old_group +
     {{2{incoming_value[31]}},incoming_value} -
     {{2{previous_value[31]}},previous_value};
  wire sensor_alarm = incoming_value >= selected_threshold;
  wire group_alarm = new_group >= group_threshold[group_index];

  // Updating only one sensor and one group per cycle provides deterministic
  // state semantics. Input arrivals may be simultaneous, decisions are serialized.
  for(genvar s=0;s<N_SENSORS;s++) begin : sensors
    wire update = accepted_event && sensor_index==SENSOR_BITS'(s);
    wire cfg_write = cfg_valid && cfg_ready && !cfg_group && cfg_index==8'(s) &&
                     cfg_threshold[33:32]=={2{cfg_threshold[31]}};
    always_ff @(posedge clk or negedge rst_n) begin
      if(!rst_n) begin
        seen[s] <= 1'b0;
        last_seq[s] <= '0;
        last_time[s] <= '0;
        last_value[s] <= '0;
        estimate[s] <= '0;
        sensor_threshold[s] <= 32'sh7fff_ffff;
      end else begin
        if(cfg_write) sensor_threshold[s] <= cfg_threshold[31:0];
        if(update) begin
          seen[s] <= 1'b1;
          last_seq[s] <= incoming_seq;
          last_time[s] <= incoming_time;
          last_value[s] <= incoming_value;
          estimate[s] <= new_estimate;
        end
      end
    end
  end
  for(genvar g=0;g<GROUPS;g++) begin : groups
    wire update = accepted_event && group_index==GROUP_BITS'(g);
    wire cfg_write = cfg_valid && cfg_ready && cfg_group && cfg_index==8'(g);
    always_ff @(posedge clk or negedge rst_n) begin
      if(!rst_n) begin
        group_sum[g] <= '0;
        group_threshold[g] <= 34'sh1_ffff_ffff;
      end else begin
        if(cfg_write) group_threshold[g] <= cfg_threshold;
        if(update) group_sum[g] <= new_group;
      end
    end
  end

  logic [5:0] ingress_fire_count;
  always_comb begin
    ingress_fire_count='0;
    for (int lane=0;lane<LANES;lane++) begin
      if (in_valid[lane] && in_ready[lane])
        ingress_fire_count=ingress_fire_count+6'd1;
    end
  end

  logic bad_config;
  always_comb begin
    bad_config = cfg_group ? (int'(cfg_index) >= GROUPS) :
                 (int'(cfg_index) >= N_SENSORS ||
                  cfg_threshold[33:32]!={2{cfg_threshold[31]}});
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      result_valid <= 1'b0;
      result_data <= '0;
      rr_lane <= '0;
      urgent_streak <= '0;
      accepted_count <= '0;
      processed_count <= '0;
      fault_count <= '0;
      fault_valid <= 1'b0;
      fault_code <= 8'b0;
      fault_sensor <= 8'b0;
    end else begin
      fault_valid <= 1'b0;
      if(ingress_fire_count!=0)
        accepted_count <= accepted_count+32'(ingress_fire_count);
      if(cfg_valid && cfg_ready && bad_config) begin
        fault_valid <= 1'b1;
        fault_code <= FAULT_CONFIG;
        fault_sensor <= cfg_index;
        fault_count <= fault_count+32'd1;
      end
      if(pop_valid) begin
        rr_lane <= (selected_lane==LANE_BITS'(LANES-1)) ? '0 : selected_lane+LANE_BITS'(1);
        if(lane_priority[selected_lane] > min_priority)
          urgent_streak <= (urgent_streak>=STREAK_BITS'(URGENT_BUDGET)) ?
             urgent_streak : urgent_streak+STREAK_BITS'(1);
        else urgent_streak <= '0;
        if(detected_fault!=8'b0) begin
          fault_valid <= 1'b1;
          fault_code <= detected_fault;
          fault_sensor <= sensor_id;
          fault_count <= fault_count+32'd1;
        end else processed_count <= processed_count+32'd1;
      end
      if(emit_ready) begin
        result_valid <= accepted_event;
        if(accepted_event)
          result_data <= {group_alarm,sensor_alarm,new_group,new_estimate,pop_data};
      end
    end
  end
endmodule
