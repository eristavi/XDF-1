`timescale 1ns/1ps

// Directed hardware verification of optional lossless contextual backpressure.
module tb_xdf_reflex_lossless;
  logic clk=0;
  always #5 clk=~clk;
  logic rst_n=0, in_valid=0, in_ready;
  logic [163:0] in_data='0;
  logic reflex_valid, reflex_ready=1;
  logic [175:0] reflex_data;
  logic context_valid, context_ready=0;
  logic [175:0] context_data;
  logic cfg_valid=0, cfg_ready, cfg_enabled=0, cfg_fault;
  logic [7:0] cfg_index=0, cfg_sensor=0;
  logic [1:0] cfg_mode=0, cfg_action=0;
  logic signed [31:0] cfg_threshold=0;
  logic [31:0] accepted_count, filtered_count, reflex_count, context_count;
  logic [31:0] context_drop_count, protected_context_drop_count;

  xdf_reflex #(.RULES(8), .CONTEXT_LOSSLESS(1'b1)) dut(.*);

  initial begin
    logic [175:0] first_context;
    repeat(4) @(posedge clk);
    @(negedge clk);
    rst_n=1;
    cfg_valid=1;
    cfg_index=8'hff;
    cfg_action=2'd1;
    #1;
    if(!cfg_ready) $fatal(1,"Lossless default configuration refused");
    @(negedge clk);
    cfg_valid=0;
    in_valid=1;
    in_data='0;
    in_data[71:64]=8'd5;
    in_data[31:0]=32'd11;
    #1;
    if(!in_ready) $fatal(1,"First context not accepted");
    @(negedge clk);
    first_context=context_data;
    if(!context_valid || first_context[31:0]!=32'd11)
      $fatal(1,"First output not buffered");
    in_data[31:0]=32'd22;
    repeat(12) begin
      #1;
      if(in_ready || !context_valid || context_data!==first_context)
        $fatal(1,"Lossless output changed or input accepted during context stall");
      @(negedge clk);
    end
    context_ready=1;
    #1;
    if(!in_ready) $fatal(1,"Lossless context did not recover after ready");
    @(negedge clk);
    in_valid=0;
    #1;
    if(!context_valid || context_data[31:0]!==32'd22)
      $fatal(1,"Second context not buffered after backpressure");
    @(negedge clk);
    if(context_valid || accepted_count!=32'd2 || context_count!=32'd2 ||
       context_drop_count!=32'd0 || protected_context_drop_count!=32'd0)
      $fatal(1,"Lossless counters invalid");
    $display("REFLEX LOSSLESS RTL PASS: two records, backpressure, zero drops");
    $finish;
  end
endmodule
