`timescale 1ns/1ps
// Directed system-level SEF validation -> reflex/context fan-out.
module tb_xdf_perception_frontend;
  logic clk=0;
  always #5 clk=~clk;
  logic rst_n=0;
  logic [3:0] sensor_valid='0, sensor_ready;
  logic [383:0] sensor_event='0;
  logic sensor_cfg_valid=0, sensor_cfg_ready, sensor_cfg_group=0;
  logic [7:0] sensor_cfg_index=0;
  logic signed [33:0] sensor_cfg_threshold=0;
  logic rule_cfg_valid=0, rule_cfg_ready, rule_cfg_enabled=0;
  logic [7:0] rule_cfg_index=0, rule_cfg_sensor=0;
  logic [1:0] rule_cfg_mode=0, rule_cfg_action=0;
  logic signed [31:0] rule_cfg_threshold=0;
  logic rule_cfg_fault;
  logic reflex_valid, reflex_ready=1;
  logic [175:0] reflex_data;
  logic context_valid, context_ready=0;
  logic [175:0] context_data;
  logic sensor_fault_valid;
  logic [7:0] sensor_fault_code, sensor_fault_id;
  logic [31:0] sensor_accepted, sensor_processed, sensor_faults;
  logic [31:0] event_accepted, event_filtered, event_reflex, event_context;
  logic [31:0] context_dropped, protected_context_dropped;
  int reflex_observed=0, context_observed=0;

  xdf_perception_frontend dut(.*);

  always @(posedge clk) begin
    if(rst_n && reflex_valid && reflex_ready) begin
      if(reflex_data[167] !== 1'b1 || reflex_data[71:64] !== 8'd0)
        $fatal(1,"Alarm did not preserve protected bit/sensor ID");
      reflex_observed++;
    end
    if(rst_n && context_valid && context_ready)
      context_observed++;
  end

  task automatic configure_sensor();
    @(negedge clk);
    sensor_cfg_index=0;
    sensor_cfg_group=0;
    sensor_cfg_threshold=34'sd50;
    sensor_cfg_valid=1;
    #1;
    if(!sensor_cfg_ready) $fatal(1,"Sensor config not ready");
    @(negedge clk);
    sensor_cfg_valid=0;
  endtask

  task automatic configure_rules();
    @(negedge clk);
    rule_cfg_index=8'hff;
    rule_cfg_action=2'd0;
    rule_cfg_valid=1;
    #1;
    if(!rule_cfg_ready) $fatal(1,"Rule config not ready");
    @(negedge clk);
    rule_cfg_valid=0;
  endtask

  task automatic send(input logic [7:0] sensor_id, input logic [15:0] seq,
                       input logic [31:0] raw, input logic [1:0] kind);
    @(negedge clk);
    sensor_valid=4'b0001;
    sensor_event[95:0]={4'd0,kind,2'd3,seq,sensor_id,32'(seq),raw};
    for(int j=0;j<400;j++) begin
      @(posedge clk);
      if(sensor_ready[0]) begin
        @(negedge clk);
        sensor_valid='0;
        return;
      end
    end
    $fatal(1,"Frontend input stalled indefinitely");
  endtask

  initial begin
    repeat(5) @(posedge clk);
    @(negedge clk);
    rst_n=1;
    configure_sensor();
    configure_rules();
    // The first event creates a protected contextual record held at the sink.
    for(int i=1;i<=7;i++)
      send(8'd0,16'(i),32'(60+i),2'd0);
    // An invalid kind never reaches either downstream path.
    send(8'd0,16'd8,32'd80,2'd1);
    for(int t=0;t<300;t++) begin
      @(negedge clk);
      if(event_accepted==32'd7 && sensor_faults==32'd1 && reflex_observed==7) break;
      if(t==299) $fatal(1,"Input did not drain: events=%0d faults=%0d",event_accepted,sensor_faults);
    end
    if(reflex_observed!=7 || event_reflex!=32'd7 || event_context!=32'd1 ||
       protected_context_dropped!=32'd6 || context_dropped!=32'd6 ||
       !context_valid || sensor_accepted!=32'd8 || sensor_processed!=32'd7)
      $fatal(1,"Integration count mismatch reflex=%0d context=%0d drops=%0d protected=%0d accepted=%0d processed=%0d faults=%0d",
          reflex_observed,event_context,context_dropped,protected_context_dropped,
          sensor_accepted,sensor_processed,sensor_faults);
    // First critical context remains available and stable until consumer ready.
    if(context_data[71:64]!==8'd0 || context_data[87:72]!==16'd1)
      $fatal(1,"Oldest held contextual evidence changed under stall");
    @(negedge clk);
    context_ready=1;
    @(negedge clk);
    if(context_observed!=1 || context_valid)
      $fatal(1,"Context stream did not drain properly");
    $display("FRONTEND RTL PASS: sensor=%0d valid=%0d reflex=%0d context_saved=1 context_dropped=%0d input_fault=%0d",
             sensor_accepted,event_accepted,event_reflex,context_dropped,sensor_faults);
    $display("XDF-1 M2.2B FRONTEND ALL TESTS PASS");
    $finish;
  end
endmodule
