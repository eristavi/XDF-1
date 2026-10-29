`timescale 1ns/1ps
// Cycle-exact independent reference verification of XDF-1 sensory front end.
module tb_xdf_sensory;
  logic clk=0;
  always #5 clk=~clk;
  logic rst_n=0;
  logic [3:0] in_valid=0;
  logic [3:0] in_ready;
  logic [383:0] in_event='0;
  logic result_valid;
  logic result_ready=0;
  logic [163:0] result_data;
  logic cfg_valid=0, cfg_ready, cfg_group=0;
  logic [7:0] cfg_index=0;
  logic signed [33:0] cfg_threshold=0;
  logic fault_valid;
  logic [7:0] fault_code, fault_sensor;
  logic [31:0] accepted_count, processed_count, fault_count;
  xdf_sensory dut(.*);

  task automatic configure(input logic group_mode, input logic [7:0] index,
                           input logic signed [33:0] threshold);
    @(negedge clk);
    cfg_group=group_mode;
    cfg_index=index;
    cfg_threshold=threshold;
    cfg_valid=1'b1;
    #1;
    if(!cfg_ready) $fatal(1,"Configuration rejected: group %0d index %0d",group_mode,index);
    @(negedge clk);
    cfg_valid=1'b0;
  endtask

  initial begin : regression
    int fd, fields, cycles, final_accepted, final_processed, final_faults;
    logic [3:0] vin, expected_ready;
    logic [95:0] e0,e1,e2,e3;
    logic desired_out_ready, expected_out_valid;
    logic [163:0] expected_out;
    int transferred=0, seen_outputs=0, backpressure_cycles=0;
    repeat(5) @(posedge clk);
    @(negedge clk);
    rst_n=1'b1;
    configure(1'b0, 8'd0, 34'sd50);
    configure(1'b0, 8'd1, 34'sd35);
    configure(1'b0, 8'd5, -34'sd20);
    configure(1'b1, 8'd0, 34'sd100);
    configure(1'b1, 8'd1, 34'sd60);

    fd=$fopen("build/sensory_vectors.txt","r");
    if(fd==0) $fatal(1,"Missing sensory_vectors.txt; generate with Python");
    fields=$fscanf(fd,"%d %d %d %d",cycles,final_accepted,final_processed,final_faults);
    if(fields!=4 || cycles<2000) $fatal(1,"Invalid sensory vector header");
    for(int k=0;k<cycles;k++) begin
      @(negedge clk);
      fields=$fscanf(fd,"%h %h %h %h %h %h %h %h %h",vin,e0,e1,e2,e3,
                     desired_out_ready,expected_ready,expected_out_valid,expected_out);
      if(fields!=9) $fatal(1,"Unexpected EOF/bad vector at cycle %0d got %0d",k,fields);
      in_valid=vin;
      in_event={e3,e2,e1,e0};
      result_ready=desired_out_ready;
      #1;
      if(in_ready !== expected_ready)
        $fatal(1,"Cycle %0d ready mismatch: RTL=%h REF=%h",k,in_ready,expected_ready);
      if(result_valid !== expected_out_valid)
        $fatal(1,"Cycle %0d output valid mismatch: RTL=%b REF=%b",k,result_valid,expected_out_valid);
      if(expected_out_valid && result_data !== expected_out)
        $fatal(1,"Cycle %0d decision mismatch: RTL=%h REF=%h",k,result_data,expected_out);
      if(expected_out_valid && !desired_out_ready) backpressure_cycles++;
      if(expected_out_valid && desired_out_ready) seen_outputs++;
      for(int lane=0;lane<4;lane++) if(vin[lane] && in_ready[lane]) transferred++;
      @(posedge clk);
    end
    @(negedge clk);
    in_valid='0;
    result_ready=1;
    if(accepted_count !== 32'(final_accepted))
      $fatal(1,"Accepted events mismatch: RTL=%0d REF=%0d",accepted_count,final_accepted);
    if(processed_count !== 32'(final_processed))
      $fatal(1,"Processed events mismatch: RTL=%0d REF=%0d",processed_count,final_processed);
    if(fault_count !== 32'(final_faults))
      $fatal(1,"Fault events mismatch: RTL=%0d REF=%0d",fault_count,final_faults);
    if(transferred != final_accepted || seen_outputs != final_processed ||
       backpressure_cycles == 0 || final_faults == 0)
      $fatal(1,"Coverage/count mismatch accepted=%0d processed=%0d stalled=%0d faults=%0d",
             transferred,seen_outputs,backpressure_cycles,final_faults);
    $fclose(fd);
    $display("SENSORY RTL PASS: cycles=%0d events=%0d decisions=%0d faults=%0d held_cycles=%0d",
             cycles, final_accepted,final_processed,final_faults,backpressure_cycles);

    // Midstream asynchronous reset must clear all state, counters, queues,
    // output and threshold configuration. Then check simple post-reset event.
    @(negedge clk); rst_n=0;
    #1;
    if(result_valid || accepted_count!=32'd0 || processed_count!=32'd0 || fault_count!=32'd0)
      $fatal(1,"Asynchronous sensory reset did not clear state");
    repeat(3) @(posedge clk);
    @(negedge clk); rst_n=1;
    in_valid=4'b0001;
    in_event='0;
    in_event[95:0]={4'b0,2'b0,2'b0,16'd1,8'd0,32'd1,32'd25};
    result_ready=1;
    #1;
    if(!in_ready[0]) $fatal(1,"Sensor input not ready after reset");
    @(negedge clk); in_valid=0;
    // Event accepted on the intervening posedge; next edge processes it.
    for(int wait_cyc=0;wait_cyc<20;wait_cyc++) begin
      #1;
      if(result_valid) begin
        if(result_data[31:0] !== 32'd25 || result_data[162] !== 1'b0)
          $fatal(1,"Post-reset sensor output incorrect");
        $display("SENSORY RESET PASS");
        $display("XDF-1 SEF RTL ALL TESTS PASS");
        $finish;
      end
      @(negedge clk);
    end
    $fatal(1,"Sensor output timeout after reset");
  end
endmodule
