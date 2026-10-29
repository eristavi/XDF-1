`timescale 1ns/1ps
// Compare every combinational handshake and registered output cycle with the
// independent Python oracle. Backend neural metadata and reflex can stall
// independently. Producers hold valid/data unchanged until accepted.
module tb_xdf_reflex;
  logic clk = 0;
  always #5 clk = ~clk;
  logic rst_n = 0;
  logic in_valid = 0, in_ready;
  logic [163:0] in_data = '0;
  logic reflex_valid, reflex_ready = 0;
  logic [175:0] reflex_data;
  logic context_valid, context_ready = 0;
  logic [175:0] context_data;
  logic cfg_valid = 0, cfg_ready;
  logic [7:0] cfg_index = 0;
  logic cfg_enabled = 0;
  logic [7:0] cfg_sensor = 0;
  logic [1:0] cfg_mode = 0;
  logic signed [31:0] cfg_threshold = 0;
  logic [1:0] cfg_action = 0;
  logic cfg_fault;
  logic [31:0] accepted_count, filtered_count, reflex_count, context_count;
  logic [31:0] context_drop_count, protected_context_drop_count;

  xdf_reflex #(.RULES(8), .CONTEXT_LOSSLESS(1'b0)) dut (.*);

  task automatic config_rule(input logic [7:0] idx, input logic enabled,
       input logic [7:0] sensor, input logic [1:0] mode,
       input logic signed [31:0] threshold, input logic [1:0] action);
    @(negedge clk);
    cfg_index = idx;
    cfg_enabled = enabled;
    cfg_sensor = sensor;
    cfg_mode = mode;
    cfg_threshold = threshold;
    cfg_action = action;
    cfg_valid = 1;
    #1;
    if(!cfg_ready) $fatal(1,"Rule configuration not accepted");
    @(negedge clk);
    cfg_valid = 0;
    if(cfg_fault) $fatal(1,"Unexpected rule configuration fault");
  endtask

  initial begin : vectors
    int fd, fields, cycles;
    int final_accepted, final_filtered, final_reflex, final_context;
    int final_context_drops, final_protected_drops;
    logic offered, ref_ready, ctx_ready, expected_in_ready;
    logic exp_ref_valid, exp_ctx_valid;
    logic [163:0] event_word;
    logic [175:0] exp_ref, exp_ctx;
    int observed_reflex = 0, observed_context = 0, blocked_reflex = 0;
    int observed_drops = 0;
    logic [31:0] old_drops;

    repeat(5) @(posedge clk);
    @(negedge clk);
    rst_n=1;
    config_rule(8'hff, 0, 0, 0, 0, 0);
    config_rule(8'd0, 1, 8'd1, 2'd1, 32'sd100, 2'd3);
    config_rule(8'd1, 1, 8'hff, 2'd2, 32'sd40, 2'd1);
    config_rule(8'd2, 1, 8'd2, 2'd0, 32'sd0, 2'd0);
    config_rule(8'd3, 1, 8'd3, 2'd3, 32'sd0, 2'd3);
    config_rule(8'd4, 1, 8'd1, 2'd1, 32'sd0, 2'd1);

    // An invalid negative magnitude threshold must not mutate the rule bank.
    @(negedge clk);
    cfg_index=8'd5; cfg_enabled=1; cfg_sensor=8'd6;
    cfg_mode=2'd2; cfg_threshold=-32'sd1; cfg_action=2'd3; cfg_valid=1;
    #1;
    if(!cfg_ready) $fatal(1,"Invalid configuration not consumed");
    @(negedge clk);
    if(!cfg_fault) $fatal(1,"Invalid configuration fault did not pulse");
    cfg_valid=0;
    @(posedge clk);

    fd=$fopen("build/reflex_vectors.txt","r");
    if(fd==0) $fatal(1,"Missing reflex vectors");
    fields=$fscanf(fd,"%d %d %d %d %d %d %d",cycles,final_accepted,
                   final_filtered,final_reflex,final_context,
                   final_context_drops,final_protected_drops);
    if(fields!=7 || cycles<3000) $fatal(1,"Bad reference vector header");
    for(int k=0; k<cycles; k++) begin
      @(negedge clk);
      fields=$fscanf(fd,"%h %h %h %h %h %h %h %h %h",
          offered,event_word,ref_ready,ctx_ready,expected_in_ready,
          exp_ref_valid,exp_ref,exp_ctx_valid,exp_ctx);
      if(fields!=9) $fatal(1,"Invalid vector at cycle %0d: fields %0d",k,fields);
      in_valid=offered;
      in_data=event_word;
      reflex_ready=ref_ready;
      context_ready=ctx_ready;
      #1;
      if(in_ready !== expected_in_ready)
        $fatal(1,"Cycle %0d ready RTL=%b REF=%b",k,in_ready,expected_in_ready);
      if(reflex_valid !== exp_ref_valid)
        $fatal(1,"Cycle %0d reflex-valid RTL=%b REF=%b",k,reflex_valid,exp_ref_valid);
      if(exp_ref_valid && reflex_data !== exp_ref)
        $fatal(1,"Cycle %0d reflex record RTL=%h REF=%h",k,reflex_data,exp_ref);
      if(context_valid !== exp_ctx_valid)
        $fatal(1,"Cycle %0d context-valid RTL=%b REF=%b",k,context_valid,exp_ctx_valid);
      if(exp_ctx_valid && context_data !== exp_ctx)
        $fatal(1,"Cycle %0d context record RTL=%h REF=%h",k,context_data,exp_ctx);
      if(exp_ref_valid && ref_ready) observed_reflex++;
      if(exp_ctx_valid && ctx_ready) observed_context++;
      if(exp_ref_valid && !ref_ready) blocked_reflex++;
      old_drops=context_drop_count;
      @(posedge clk);
      #1;
      if(context_drop_count != old_drops && context_drop_count != old_drops+32'd1)
        $fatal(1,"Context drop count skipped a record");
    end
    @(negedge clk);
    in_valid=0;
    reflex_ready=1;
    context_ready=1;
    if(accepted_count !== 32'(final_accepted) ||
       filtered_count !== 32'(final_filtered) ||
       reflex_count !== 32'(final_reflex) ||
       context_count !== 32'(final_context) ||
       context_drop_count !== 32'(final_context_drops) ||
       protected_context_drop_count !== 32'(final_protected_drops))
      $fatal(1,"Counters mismatch: accepted=%0d/%0d filtered=%0d/%0d reflex=%0d/%0d context=%0d/%0d dropped=%0d/%0d protected=%0d/%0d",
        accepted_count,final_accepted,filtered_count,final_filtered,
        reflex_count,final_reflex,context_count,final_context,
        context_drop_count,final_context_drops,
        protected_context_drop_count,final_protected_drops);
    if(observed_reflex != final_reflex || observed_context != final_context ||
       blocked_reflex < 10 || final_protected_drops < 1)
      $fatal(1,"Coverage incomplete ref=%0d ctx=%0d blocked=%0d protected=%0d",
        observed_reflex,observed_context,blocked_reflex,final_protected_drops);
    $fclose(fd);
    $display("REFLEX RTL PASS: cycles=%0d accepted=%0d reflex=%0d context=%0d dropped=%0d protected_drops=%0d",
       cycles,final_accepted,final_reflex,final_context,
       final_context_drops,final_protected_drops);

    // Prove asynchronous reset clears rules, both output slots and all counters.
    @(negedge clk);
    rst_n=0;
    #1;
    if(reflex_valid || context_valid || accepted_count ||
       context_drop_count || protected_context_drop_count)
      $fatal(1,"Reset did not clear state");
    repeat(2) @(posedge clk);
    @(negedge clk);
    rst_n=1;
    in_valid=1;
    in_data='0;
    in_data[71:64]=8'd1;
    reflex_ready=0;
    context_ready=0;
    #1;
    if(!in_ready) $fatal(1,"Reset module not ready");
    @(negedge clk);
    in_valid=0;
    if(reflex_valid || context_valid || filtered_count!=32'd1)
      $fatal(1,"Rules were not reset to filtered default");
    // Non-maskable alarm after reset must still be dispatched.
    in_valid=1;
    in_data[162]=1;
    @(negedge clk);
    in_valid=0;
    #1;
    if(!reflex_valid || !context_valid || !reflex_data[167])
      $fatal(1,"Protected event not dispatched after reset");
    $display("REFLEX RESET + PROTECTED OVERRIDE PASS");
    $display("XDF-1 M2.2B REFLEX RTL ALL TESTS PASS");
    $finish;
  end
endmodule
