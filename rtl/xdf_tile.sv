// One tile, eight configurable DAG nodes and two execution-tag slots.
// A valid node fires once per slot; the tile schedules one operation per cycle.
module xdf_tile #(
  parameter int TILE_ID = 0
)(
  input  logic        clk,
  input  logic        rst_n,
  // Configured while all execution slots are inactive.
  input  logic        cfg_write,
  input  logic [7:0]  cfg_node,
  input  logic [2:0]  cfg_op,
  input  logic [7:0]  cfg_dest_node,
  input  logic [3:0]  cfg_dest_port,
  // Two globally allocated execution slots.
  input  logic [1:0]  active_valid,
  input  logic [7:0]  active_context,
  input  logic [15:0] active_epoch,
  input  logic        slot_alloc_valid,
  input  logic        slot_alloc_idx,
  // Incoming token (router handles backpressure).
  input  logic        token_valid,
  output logic        token_ready,
  input  logic [63:0] token_data,
  input  logic        debug_stall,
  // Routed result for another tile.
  output logic        route_valid,
  input  logic        route_ready,
  output logic [63:0] route_token,
  // Terminal token delivered to host.
  output logic        result_valid,
  input  logic        result_ready,
  output logic [63:0] result_token,
  // One-cycle protocol error pulse.
  output logic        error_valid,
  output logic [7:0]  error_code,
  output logic [7:0]  error_node
);
  import xdf_pkg::*;
  logic cfg_enabled [0:7];
  logic [2:0] cfg_opcode [0:7];
  logic [7:0] cfg_dest [0:7];
  logic [3:0] cfg_port [0:7];

  logic [31:0] operand0 [0:7][0:1];
  logic [31:0] operand1 [0:7][0:1];
  logic valid0 [0:7][0:1];
  logic valid1 [0:7][0:1];
  logic fired  [0:7][0:1];

  logic obuf_valid, obuf_result;
  logic [63:0] obuf_token;
  logic [3:0] rr_sched;
  logic can_emit;
  logic sched_valid;
  logic [2:0] sched_node;
  logic       sched_slot;
  logic [3:0] sched_next;
  integer matching_slot;

  assign token_ready  = !debug_stall;
  assign route_valid  = obuf_valid && !obuf_result;
  assign route_token  = obuf_token;
  assign result_valid = obuf_valid && obuf_result;
  assign result_token = obuf_token;
  assign can_emit = !obuf_valid || (obuf_result ? result_ready : route_ready);

  // If an execution tag is active, its tag/epoch determines operand slot.
  always_comb begin
    matching_slot = -1;
    for (int s = 0; s < 2; s++) begin
      if (active_valid[s] &&
          active_context[s*4 +: 4] == token_data[55:52] &&
          active_epoch[s*8 +: 8] == token_data[39:32])
        matching_slot = s;
    end
  end

  // Small fair round-robin scheduler scanning 8 nodes x 2 slots.
  always_comb begin
    sched_valid = 1'b0;
    sched_node  = 3'b0;
    sched_slot  = 1'b0;
    sched_next  = rr_sched;
    for (int k = 0; k < 16; k++) begin : scan
      int pos;
      int n;
      int s;
      pos = (int'(rr_sched) + k) % 16;
      n = pos % 8;
      s = pos / 8;
      if (!sched_valid && active_valid[s] && cfg_enabled[n] && !fired[n][s] &&
          valid0[n][s] && ((cfg_opcode[n] >= OP_PASS) || valid1[n][s])) begin
        sched_valid = 1'b1;
        sched_node  = 3'(n);
        sched_slot  = 1'(s);
        sched_next  = 4'((pos + 1) % 16);
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
      for (int n = 0; n < 8; n++) begin
        cfg_enabled[n] <= 1'b0;
        cfg_opcode[n] <= 3'b0;
        cfg_dest[n] <= 8'b0;
        cfg_port[n] <= 4'b0;
        for (int s = 0; s < 2; s++) begin
          operand0[n][s] <= 32'b0;
          operand1[n][s] <= 32'b0;
          valid0[n][s] <= 1'b0;
          valid1[n][s] <= 1'b0;
          fired[n][s] <= 1'b0;
        end
      end
    end else begin
      error_valid <= 1'b0;
      if (cfg_write && cfg_node[4:3] == 2'(TILE_ID)) begin
        cfg_enabled[cfg_node[2:0]] <= 1'b1;
        cfg_opcode[cfg_node[2:0]] <= cfg_op;
        cfg_dest[cfg_node[2:0]] <= cfg_dest_node;
        cfg_port[cfg_node[2:0]] <= cfg_dest_port;
        // Reconfiguration is only accepted when both tags are idle.
      end
      if (slot_alloc_valid) begin
        for (int n = 0; n < 8; n++) begin
          valid0[n][slot_alloc_idx] <= 1'b0;
          valid1[n][slot_alloc_idx] <= 1'b0;
          fired[n][slot_alloc_idx] <= 1'b0;
          operand0[n][slot_alloc_idx] <= 32'b0;
          operand1[n][slot_alloc_idx] <= 32'b0;
        end
      end
      if (obuf_valid && can_emit)
        obuf_valid <= 1'b0;

      if (can_emit && sched_valid) begin
        logic [31:0] answer;
        answer = do_alu(cfg_opcode[sched_node],
                        operand0[sched_node][sched_slot],
                        operand1[sched_node][sched_slot]);
        obuf_valid <= 1'b1;
        obuf_result <= (cfg_opcode[sched_node] == OP_OUTPUT);
        obuf_token <= pack_token(
          answer,
          active_epoch[8*int'(sched_slot) +: 8],
          cfg_opcode[sched_node] == OP_OUTPUT ?
            {3'b000, 2'(TILE_ID), sched_node} : cfg_dest[sched_node],
          cfg_opcode[sched_node] == OP_OUTPUT ? 4'b0 : cfg_port[sched_node],
          active_context[4*int'(sched_slot) +: 4]
        );
        valid0[sched_node][sched_slot] <= 1'b0;
        valid1[sched_node][sched_slot] <= 1'b0;
        fired[sched_node][sched_slot] <= 1'b1;
        rr_sched <= sched_next;
      end
      if (token_valid && token_ready) begin
        if (token_data[63:56] != 8'b0) begin
          error_valid <= 1'b1;
          error_code <= ERR_BAD_FLAGS;
          error_node <= token_data[47:40];
        end else if (matching_slot < 0) begin
          error_valid <= 1'b1;
          error_code <= ERR_BAD_TAG;
          error_node <= token_data[47:40];
        end else if (token_data[47:45] != 3'b0 ||
                     token_data[44:43] != 2'(TILE_ID) ||
                     !cfg_enabled[token_data[42:40] & 3'b111]) begin
          // Router guarantees node[7:5]==0, node[4:3]==TILE_ID.
          error_valid <= 1'b1;
          error_code <= ERR_UNCONFIGURED;
          error_node <= token_data[47:40];
        end else if (fired[token_data[42:40]][matching_slot] ||
                     (token_data[51:48] == 4'd0 && valid0[token_data[42:40]][matching_slot]) ||
                     (token_data[51:48] == 4'd1 && valid1[token_data[42:40]][matching_slot])) begin
          error_valid <= 1'b1;
          error_code <= ERR_DUP_OPERAND;
          error_node <= token_data[47:40];
        end else if (token_data[51:48] > 4'd1 ||
                     (cfg_opcode[token_data[42:40]] >= OP_PASS && token_data[51:48] != 4'd0)) begin
          error_valid <= 1'b1;
          error_code <= ERR_BAD_PORT;
          error_node <= token_data[47:40];
        end else if (token_data[51:48] == 4'd0) begin
          operand0[token_data[42:40]][matching_slot] <= token_data[31:0];
          valid0[token_data[42:40]][matching_slot] <= 1'b1;
        end else begin
          operand1[token_data[42:40]][matching_slot] <= token_data[31:0];
          valid1[token_data[42:40]][matching_slot] <= 1'b1;
        end
      end
    end
  end
endmodule
