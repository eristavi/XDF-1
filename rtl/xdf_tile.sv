`timescale 1ns/1ps
// XDF-1 M2 tile. Static per-node/per-tag writes avoid wide dynamic-register
// write multiplexers. Only the selected node can issue a result in a cycle.
module xdf_tile #(
  parameter int TILE_ID = 0,
  parameter int NODES_PER_TILE = 8
)(
  input  logic        clk,
  input  logic        rst_n,
  input  logic        cfg_write,
  input  logic [7:0]  cfg_node,
  input  logic [2:0]  cfg_op,
  input  logic [7:0]  cfg_dest_node,
  input  logic [3:0]  cfg_dest_port,
  input  logic [1:0]  active_valid,
  input  logic [7:0]  active_context,
  input  logic [15:0] active_epoch,
  input  logic        slot_alloc_valid,
  input  logic        slot_alloc_idx,
  input  logic        token_valid,
  output logic        token_ready,
  input  logic [63:0] token_data,
  input  logic        debug_stall,
  output logic        route_valid,
  input  logic        route_ready,
  output logic [63:0] route_token,
  output logic        result_valid,
  input  logic        result_ready,
  output logic [63:0] result_token,
  output logic        error_valid,
  output logic [7:0]  error_code,
  output logic [7:0]  error_node
);
  import xdf_pkg::*;
  // All v0.1 compatible physical tile instantiations use 8 local nodes.
  localparam int SLOT_COUNT=2;
  localparam int SCHEDULE_WIDTH=NODES_PER_TILE*SLOT_COUNT;
  localparam int NODE_BITS=$clog2(NODES_PER_TILE);
  logic cfg_enabled [0:NODES_PER_TILE-1];
  logic [2:0] cfg_opcode [0:NODES_PER_TILE-1];
  logic [7:0] cfg_dest [0:NODES_PER_TILE-1];
  logic [3:0] cfg_port [0:NODES_PER_TILE-1];
  logic [31:0] operand0 [0:NODES_PER_TILE-1][0:1];
  logic [31:0] operand1 [0:NODES_PER_TILE-1][0:1];
  logic valid0 [0:NODES_PER_TILE-1][0:1];
  logic valid1 [0:NODES_PER_TILE-1][0:1];
  logic fired [0:NODES_PER_TILE-1][0:1];

  logic obuf_valid, obuf_result;
  logic [63:0] obuf_token;
  logic can_emit;
  logic [3:0] rr_sched;
  logic [SCHEDULE_WIDTH-1:0] eligible;
  logic sched_valid, sched_slot;
  logic [NODE_BITS-1:0] sched_node;
  logic [3:0] sched_next;
  logic [31:0] sched_a, sched_b;
  logic [2:0] sched_op;
  logic [7:0] sched_dest;
  logic [3:0] sched_port;

  logic tag_found, tag_slot;
  logic [NODE_BITS-1:0] in_node;
  logic [3:0] in_port;
  logic input_accept, input_error;
  logic [7:0] input_error_code;

  assign in_node = token_data[40 +: NODE_BITS];
  assign in_port = token_data[51:48];
  assign token_ready = !debug_stall;
  assign route_valid = obuf_valid && !obuf_result;
  assign route_token = obuf_token;
  assign result_valid = obuf_valid && obuf_result;
  assign result_token = obuf_token;
  assign can_emit = !obuf_valid || (obuf_result ? result_ready : route_ready);

  always_comb begin
    tag_found = 1'b0;
    tag_slot = 1'b0;
    for (int s=0; s<2; s++) begin
      if (active_valid[s] &&
          active_context[4*s +: 4] == token_data[55:52] &&
          active_epoch[8*s +: 8] == token_data[39:32]) begin
        tag_found = 1'b1;
        tag_slot = 1'(s);
      end
    end
  end

  always_comb begin
    input_error = 1'b0;
    input_error_code = 8'b0;
    if (token_data[63:56] != 8'b0) begin
      input_error = 1'b1;
      input_error_code = ERR_BAD_FLAGS;
    end else if (!tag_found) begin
      input_error = 1'b1;
      input_error_code = ERR_BAD_TAG;
    end else if (token_data[47:43] != 5'(TILE_ID) || !cfg_enabled[in_node]) begin
      input_error = 1'b1;
      input_error_code = ERR_UNCONFIGURED;
    end else if (fired[in_node][tag_slot] ||
                 (in_port == 4'd0 && valid0[in_node][tag_slot]) ||
                 (in_port == 4'd1 && valid1[in_node][tag_slot])) begin
      input_error = 1'b1;
      input_error_code = ERR_DUP_OPERAND;
    end else if (in_port > 4'd1 ||
                 (cfg_opcode[in_node] >= OP_PASS && in_port != 4'd0)) begin
      input_error = 1'b1;
      input_error_code = ERR_BAD_PORT;
    end
  end
  assign input_accept = token_valid && token_ready && !input_error;

  // Elaboration creates single-owner, local FF enables for every operand.
  // This eliminates dynamic indexed FF writes from the datapath.
  for (genvar n=0; n<NODES_PER_TILE; n++) begin : nodes
    always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        cfg_enabled[n] <= 1'b0;
        cfg_opcode[n] <= 3'b0;
        cfg_dest[n] <= 8'b0;
        cfg_port[n] <= 4'b0;
      end else if (cfg_write && cfg_node == (8'(TILE_ID*NODES_PER_TILE+n))) begin
        cfg_enabled[n] <= 1'b1;
        cfg_opcode[n] <= cfg_op;
        cfg_dest[n] <= cfg_dest_node;
        cfg_port[n] <= cfg_dest_port;
      end
    end
    for (genvar s=0; s<2; s++) begin : slots
      wire scheduled = sched_valid && can_emit && sched_node == NODE_BITS'(n) && sched_slot == 1'(s);
      wire operand0_fire = input_accept && in_node == NODE_BITS'(n) && tag_slot == 1'(s) && in_port == 4'd0;
      wire operand1_fire = input_accept && in_node == NODE_BITS'(n) && tag_slot == 1'(s) && in_port == 4'd1;
      wire clear_slot = slot_alloc_valid && slot_alloc_idx == 1'(s);
      assign eligible[n + NODES_PER_TILE*s] = active_valid[s] && cfg_enabled[n] &&
        !fired[n][s] && valid0[n][s] &&
        ((cfg_opcode[n] >= OP_PASS) || valid1[n][s]);
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          operand0[n][s] <= 32'b0;
          operand1[n][s] <= 32'b0;
          valid0[n][s] <= 1'b0;
          valid1[n][s] <= 1'b0;
          fired[n][s] <= 1'b0;
        end else if (clear_slot) begin
          operand0[n][s] <= 32'b0;
          operand1[n][s] <= 32'b0;
          valid0[n][s] <= 1'b0;
          valid1[n][s] <= 1'b0;
          fired[n][s] <= 1'b0;
        end else begin
          if (scheduled) begin
            valid0[n][s] <= 1'b0;
            valid1[n][s] <= 1'b0;
            fired[n][s] <= 1'b1;
          end
          if (operand0_fire) begin
            operand0[n][s] <= token_data[31:0];
            valid0[n][s] <= 1'b1;
          end
          if (operand1_fire) begin
            operand1[n][s] <= token_data[31:0];
            valid1[n][s] <= 1'b1;
          end
        end
      end
    end
  end

  // Fair local round-robin scheduling over all local node/tag pairs.
  always_comb begin
    sched_valid = 1'b0;
    sched_node = '0;
    sched_slot = 1'b0;
    sched_next = rr_sched;
    for (int k=0; k<SCHEDULE_WIDTH; k++) begin
      int position;
      position = (int'(rr_sched) + k) % SCHEDULE_WIDTH;
      if (!sched_valid && eligible[position]) begin
        sched_valid = 1'b1;
        sched_node = NODE_BITS'(position % NODES_PER_TILE);
        sched_slot = 1'(position / NODES_PER_TILE);
        sched_next = 4'((position + 1) % SCHEDULE_WIDTH);
      end
    end
  end

  always_comb begin
    sched_a = '0;
    sched_b = '0;
    sched_op = '0;
    sched_dest = '0;
    sched_port = '0;
    for (int n=0; n<NODES_PER_TILE; n++) begin
      for (int s=0; s<2; s++) begin
        if (sched_valid && sched_node == NODE_BITS'(n) && sched_slot == 1'(s)) begin
          sched_a = operand0[n][s];
          sched_b = operand1[n][s];
          sched_op = cfg_opcode[n];
          sched_dest = cfg_dest[n];
          sched_port = cfg_port[n];
        end
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      obuf_valid <= 1'b0;
      obuf_result <= 1'b0;
      obuf_token <= 64'b0;
      rr_sched <= 4'b0;
      error_valid <= 1'b0;
      error_code <= 8'b0;
      error_node <= 8'b0;
    end else begin
      error_valid <= 1'b0;
      if (token_valid && token_ready && input_error) begin
        error_valid <= 1'b1;
        error_code <= input_error_code;
        error_node <= token_data[47:40];
      end
      if (obuf_valid && can_emit)
        obuf_valid <= 1'b0;
      if (can_emit && sched_valid) begin
        obuf_valid <= 1'b1;
        obuf_result <= (sched_op == OP_OUTPUT);
        obuf_token <= pack_token(
          do_alu(sched_op, sched_a, sched_b),
          active_epoch[8*int'(sched_slot) +: 8],
          sched_op == OP_OUTPUT ? 8'(TILE_ID*NODES_PER_TILE+int'(sched_node)) : sched_dest,
          sched_op == OP_OUTPUT ? 4'b0 : sched_port,
          active_context[4*int'(sched_slot) +: 4]
        );
        rr_sched <= sched_next;
      end
    end
  end
endmodule
