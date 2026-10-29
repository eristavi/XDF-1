`timescale 1ns/1ps
module tb_xdf_top;
  import xdf_pkg::*;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;
  logic cfg_valid = 1'b0, cfg_ready;
  logic [7:0] cfg_node = 8'b0;
  logic [2:0] cfg_op = 3'b0;
  logic [7:0] cfg_dest_node = 8'b0;
  logic [3:0] cfg_dest_port = 4'b0;
  logic begin_valid = 1'b0, begin_ready;
  logic [3:0] begin_context = 4'b0;
  logic [7:0] begin_epoch = 8'b0;
  logic host_in_valid = 1'b0, host_in_ready;
  logic [63:0] host_in_token = 64'b0;
  logic host_result_valid, host_result_ready = 1'b0;
  logic [63:0] host_result_token;
  logic [3:0] debug_stall_tiles = 4'b0;
  logic clear_errors = 1'b0, error_valid;
  logic [7:0] error_code, error_node;
  logic [31:0] error_count;
  logic [1:0] active_slots;

  xdf_top dut(.*);

  task automatic reset_chip();
    @(negedge clk);
    rst_n = 0;
    cfg_valid = 0;
    begin_valid = 0;
    host_in_valid = 0;
    host_result_ready = 0;
    debug_stall_tiles = 0;
    clear_errors = 0;
    repeat (5) @(posedge clk);
    @(negedge clk);
    rst_n = 1;
  endtask

  task automatic write_node(input logic [7:0] nid, input logic [2:0] op,
                            input logic [7:0] destination,
                            input logic [3:0] port);
    @(negedge clk);
    cfg_node = nid;
    cfg_op = op;
    cfg_dest_node = destination;
    cfg_dest_port = port;
    cfg_valid = 1;
    for (int wait_cycles = 0; wait_cycles < 1000; wait_cycles++) begin
      @(posedge clk);
      if (cfg_ready) begin
        @(negedge clk);
        cfg_valid = 0;
        return;
      end
    end
    $fatal(1, "Timeout configuring node %0d", nid);
  endtask

  task automatic load_program();
    write_node(8'd0, OP_ADD, 8'd16, 4'd0);
    write_node(8'd8, OP_SUB, 8'd16, 4'd1);
    write_node(8'd16, OP_XOR, 8'd24, 4'd0);
    write_node(8'd24, OP_OUTPUT, 8'd0, 4'd0);
  endtask

  task automatic begin_tag(input logic [3:0] ctx_id,
                           input logic [7:0] epoch);
    @(negedge clk);
    begin_context = ctx_id;
    begin_epoch = epoch;
    begin_valid = 1;
    for (int wait_cycles = 0; wait_cycles < 1000; wait_cycles++) begin
      @(posedge clk);
      if (begin_ready) begin
        @(negedge clk);
        begin_valid = 0;
        return;
      end
    end
    $fatal(1, "Timeout beginning tag");
  endtask

  task automatic send_token(input logic [31:0] value,
                            input logic [7:0] epoch,
                            input logic [7:0] nid,
                            input logic [3:0] port,
                            input logic [3:0] ctx_id);
    @(negedge clk);
    host_in_token = pack_token(value, epoch, nid, port, ctx_id);
    host_in_valid = 1;
    for (int wait_cycles = 0; wait_cycles < 1000; wait_cycles++) begin
      @(posedge clk);
      if (host_in_ready) begin
        @(negedge clk);
        host_in_valid = 0;
        return;
      end
    end
    $fatal(1, "Timeout injecting node %0d", nid);
  endtask

  task automatic recv_token(output logic [63:0] value);
    @(negedge clk);
    host_result_ready = 0;
    for (int wait_cycles = 0; wait_cycles < 1000; wait_cycles++) begin
      @(posedge clk);
      if (host_result_valid) begin
        value = host_result_token;
        @(negedge clk);
        host_result_ready = 1;
        @(posedge clk);
        @(negedge clk);
        host_result_ready = 0;
        return;
      end
    end
    $fatal(1, "Timeout waiting for terminal result");
  endtask

  task automatic check_result(input logic [63:0] tok,
                              input logic [31:0] expected,
                              input logic [3:0] ctx_id,
                              input logic [7:0] epoch);
    if (tok[31:0] !== expected || tok[55:52] !== ctx_id ||
        tok[39:32] !== epoch || tok[47:40] !== 8'd24 ||
        tok[63:56] !== 8'd0 || tok[51:48] !== 4'd0)
      $fatal(1, "Unexpected result tok=%h, wanted value=%h ctx_id=%0d epoch=%0d",
             tok, expected, ctx_id, epoch);
  endtask

  task automatic inject_case(input logic [31:0] a, b, c, d,
                             input logic [3:0] ctx_id,
                             input logic [7:0] epoch,
                             input bit reorder);
    if (reorder) begin
      send_token(d, epoch, 8'd8, 4'd1, ctx_id);
      send_token(c, epoch, 8'd8, 4'd0, ctx_id);
      send_token(b, epoch, 8'd0, 4'd1, ctx_id);
      send_token(a, epoch, 8'd0, 4'd0, ctx_id);
    end else begin
      send_token(a, epoch, 8'd0, 4'd0, ctx_id);
      send_token(b, epoch, 8'd0, 4'd1, ctx_id);
      send_token(c, epoch, 8'd8, 4'd0, ctx_id);
      send_token(d, epoch, 8'd8, 4'd1, ctx_id);
    end
  endtask

  task automatic check_error(input logic [7:0] wanted);
    repeat (3) @(posedge clk);
    if (!error_valid || error_code !== wanted)
      $fatal(1, "Expected error %0d, got valid=%b code=%0d", wanted, error_valid, error_code);
  endtask

  task automatic clear_error_status();
    @(negedge clk);
    clear_errors = 1;
    @(posedge clk);
    @(negedge clk);
    clear_errors = 0;
  endtask

  initial begin : test_suite
    logic [63:0] result;
    logic [63:0] result2;
    logic [31:0] a, b, c, d, expected;
    int vf, parsed, num_cases;
    logic [3:0] ctx;
    logic [7:0] epoch;
    string vector_file;

    reset_chip();
    load_program();

    // Two live tag pairs executing the same graph; mixed arrival order.
    begin_tag(4'd1, 8'd7);
    begin_tag(4'd2, 8'd8);
    send_token(32'd7, 8'd7, 8'd0, 4'd0, 4'd1);
    send_token(32'd2, 8'd8, 8'd0, 4'd0, 4'd2);
    send_token(32'd8, 8'd8, 8'd0, 4'd1, 4'd2);
    send_token(32'd5, 8'd7, 8'd0, 4'd1, 4'd1);
    send_token(32'd11,8'd8, 8'd8, 4'd1, 4'd2);
    send_token(32'd9, 8'd7, 8'd8, 4'd0, 4'd1);
    send_token(32'd20,8'd8, 8'd8, 4'd0, 4'd2);
    send_token(32'd3, 8'd7, 8'd8, 4'd1, 4'd1);
    recv_token(result);
    recv_token(result2);
    if (result[55:52] == 4'd1) begin
      check_result(result, 32'd10, 4'd1, 8'd7);
      check_result(result2, 32'd3, 4'd2, 8'd8);
    end else begin
      check_result(result, 32'd3, 4'd2, 8'd8);
      check_result(result2, 32'd10, 4'd1, 8'd7);
    end
    if (active_slots !== 2'b00)
      $fatal(1, "Active slots not released after results");

    // Backpressure: a blocked tile prevents ingress handshake.
    begin_tag(4'd1, 8'd9);
    @(negedge clk);
    debug_stall_tiles = 4'b0001;
    host_in_token = pack_token(32'd7, 8'd9, 8'd0, 4'd0, 4'd1);
    host_in_valid = 1;
    repeat (8) begin
      @(posedge clk);
      if (host_in_ready)
        $fatal(1, "Host input accepted while destination tile was stalled");
    end
    @(negedge clk);
    debug_stall_tiles = 0;
    for (int n = 0; n < 100; n++) begin
      @(posedge clk);
      if (host_in_ready) break;
      if (n == 99) $fatal(1, "Did not recover after removing backpressure");
    end
    @(negedge clk);
    host_in_valid = 0;
    send_token(32'd5,8'd9,8'd0,4'd1,4'd1);
    send_token(32'd9,8'd9,8'd8,4'd0,4'd1);
    send_token(32'd3,8'd9,8'd8,4'd1,4'd1);
    repeat (8) @(posedge clk);
    if (!host_result_valid)
      $fatal(1, "Expected held terminal result under host backpressure");
    result = host_result_token;
    repeat (8) begin
      @(posedge clk);
      if (host_result_token !== result || !host_result_valid)
        $fatal(1, "Result changed while ready=0");
    end
    recv_token(result);
    check_result(result, 32'd10, 4'd1, 8'd9);

    // Bad operand port is an error, but subsequent legal tokens still execute.
    begin_tag(4'd1, 8'd10);
    send_token(32'd1,8'd10,8'd0,4'd2,4'd1);
    check_error(ERR_BAD_PORT);
    inject_case(32'd7,32'd5,32'd9,32'd3,4'd1,8'd10,1'b1);
    recv_token(result);
    check_result(result, 32'd10,4'd1,8'd10);
    clear_error_status();

    // Invalid program op rejected while idle.
    write_node(8'd17, 3'd7, 8'd0, 4'd0);
    check_error(ERR_BAD_CONFIG);
    clear_error_status();

    // Deterministic Python-generated randomized hardware regression.
    if (!$value$plusargs("VECTORS=%s", vector_file))
      vector_file = "tb/reference_vectors.txt";
    vf = $fopen(vector_file, "r");
    if (!vf)
      $fatal(1, "Cannot open test vectors: %s", vector_file);
    num_cases = 0;
    while (1) begin
      parsed = $fscanf(vf, "%h %h %h %h %h\n", a, b, c, d, expected);
      if (parsed != 5) break;
      ctx = 4'(num_cases % 16);
      epoch = 8'(num_cases % 256);
      begin_tag(ctx, epoch);
      inject_case(a,b,c,d,ctx,epoch,1'(num_cases % 2));
      recv_token(result);
      check_result(result,expected,ctx,epoch);
      num_cases++;
    end
    $fclose(vf);
    if (num_cases != 1000) $fatal(1,"Expected 1000 vectors, received %0d",num_cases);
    if (error_count != 0) $fatal(1,"Unexpected protocol errors during random tests: %0d",error_count);
    $display("RTL regression: %0d randomized cases PASS", num_cases);

    // Assert reset while an execution is incomplete, then reload a program.
    begin_tag(4'd1,8'd11);
    send_token(32'd7,8'd11,8'd0,4'd0,4'd1);
    reset_chip();
    if (active_slots !== 0 || host_result_valid || error_valid)
      $fatal(1, "Reset did not clear the machine");
    load_program();
    begin_tag(4'd1,8'd12);
    inject_case(32'd7,32'd5,32'd9,32'd3,4'd1,8'd12,1'b0);
    recv_token(result);
    check_result(result,32'd10,4'd1,8'd12);

    // All remaining v0.1 opcodes: a different AND -> PASS -> OUTPUT graph.
    reset_chip();
    write_node(8'd0, OP_AND, 8'd8, 4'd0);
    write_node(8'd8, OP_PASS, 8'd24, 4'd0);
    write_node(8'd24, OP_OUTPUT, 8'd0, 4'd0);
    begin_tag(4'd3, 8'd14);
    send_token(32'hffff0000, 8'd14, 8'd0, 4'd0, 4'd3);
    send_token(32'h0f0f0000, 8'd14, 8'd0, 4'd1, 4'd3);
    recv_token(result);
    check_result(result, 32'h0f0f0000, 4'd3, 8'd14);

    $display("XDF-1 M1 RTL ALL TESTS PASS");
    $finish;
  end
endmodule
