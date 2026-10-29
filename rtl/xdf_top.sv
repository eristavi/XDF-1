`timescale 1ns/1ps
// XDF-1 top-level. Program while idle, BEGIN up to 2 tag pairs, stream tokens.
// Result acceptance releases tag and allows reuse. Error status is sticky.
module xdf_top (
  input  logic clk,
  input  logic rst_n,
  // One-node-per-cycle program configuration. Only accepted when idle.
  input  logic cfg_valid,
  output logic cfg_ready,
  input  logic [7:0] cfg_node,
  input  logic [2:0] cfg_op,
  input  logic [7:0] cfg_dest_node,
  input  logic [3:0] cfg_dest_port,
  // Claim one of two global execution tags.
  input  logic begin_valid,
  output logic begin_ready,
  input  logic [3:0] begin_context,
  input  logic [7:0] begin_epoch,
  // Ingress from host. Must refer to an active execution pair.
  input  logic host_in_valid,
  output logic host_in_ready,
  input  logic [63:0] host_in_token,
  // Completed result, ready/valid (host MUST eventually assert ready).
  output logic host_result_valid,
  input  logic host_result_ready,
  output logic [63:0] host_result_token,
  // Debug test hook: apply backpressure to ingress of any tile.
  input  logic [3:0] debug_stall_tiles,
  // Sticky error interface, clear by pulsing clear_errors.
  input  logic clear_errors,
  output logic error_valid,
  output logic [7:0] error_code,
  output logic [7:0] error_node,
  output logic [31:0] error_count,
  output logic [1:0] active_slots
);
  import xdf_pkg::*;

  logic [1:0] active_valid;
  logic [7:0] active_context;
  logic [15:0] active_epoch;
  logic dup_begin;
  logic alloc_slot;
  logic alloc_fire;
  logic cfg_fire;
  logic cfg_good;

  assign active_slots = active_valid;
  assign cfg_ready = !(|active_valid) && !begin_valid;
  assign cfg_fire = cfg_valid && cfg_ready;
  assign cfg_good = cfg_node[7:5] == 3'b0 && cfg_op <= OP_OUTPUT &&
                   (cfg_op == OP_OUTPUT ||
                    (cfg_dest_node[7:5] == 3'b0 && cfg_dest_port <= 4'd1));
  assign begin_ready = !( &active_valid) && !cfg_valid;
  assign alloc_slot = active_valid[0];
  assign dup_begin = (active_valid[0] && active_context[3:0] == begin_context &&
                      active_epoch[7:0] == begin_epoch) ||
                     (active_valid[1] && active_context[7:4] == begin_context &&
                      active_epoch[15:8] == begin_epoch);
  assign alloc_fire = begin_valid && begin_ready && !dup_begin;

  logic [4:0] src_valid, src_ready;
  logic [319:0] src_token;
  logic [3:0] dst_valid, dst_ready;
  logic [255:0] dst_token;
  logic bad_dest_valid;
  logic [7:0] bad_dest_node;
  logic [3:0] tile_route_valid, tile_route_ready;
  logic [255:0] tile_route_token;
  logic [3:0] tile_result_valid, tile_result_ready;
  logic [255:0] tile_result_token;
  logic [3:0] tile_error_valid;
  logic [31:0] tile_error_code;
  logic [31:0] tile_error_node;
  logic cfg_write;

  assign cfg_write = cfg_fire && cfg_good;
  assign src_valid = {tile_route_valid, host_in_valid};
  assign src_token[63:0] = host_in_token;
  assign host_in_ready = src_ready[0];
  assign dst_ready = {4{1'b1}} & ~debug_stall_tiles;

  xdf_router router (
    .clk(clk), .rst_n(rst_n),
    .src_valid(src_valid), .src_ready(src_ready), .src_token(src_token),
    .dst_valid(dst_valid), .dst_ready(dst_ready), .dst_token(dst_token),
    .bad_dest_valid(bad_dest_valid), .bad_dest_node(bad_dest_node)
  );

  for (genvar t = 0; t < 4; t++) begin : tiles
    assign src_token[64*(t+1) +: 64] = tile_route_token[64*t +: 64];
    assign tile_route_ready[t] = src_ready[t+1];
    xdf_tile #(.TILE_ID(t)) u_tile (
      .clk(clk), .rst_n(rst_n),
      .cfg_write(cfg_write), .cfg_node(cfg_node), .cfg_op(cfg_op),
      .cfg_dest_node(cfg_dest_node), .cfg_dest_port(cfg_dest_port),
      .active_valid(active_valid), .active_context(active_context),
      .active_epoch(active_epoch),
      .slot_alloc_valid(alloc_fire), .slot_alloc_idx(alloc_slot),
      .token_valid(dst_valid[t]), .token_ready(),
      .token_data(dst_token[64*t +: 64]),
      .debug_stall(debug_stall_tiles[t]),
      .route_valid(tile_route_valid[t]), .route_ready(tile_route_ready[t]),
      .route_token(tile_route_token[64*t +: 64]),
      .result_valid(tile_result_valid[t]), .result_ready(tile_result_ready[t]),
      .result_token(tile_result_token[64*t +: 64]),
      .error_valid(tile_error_valid[t]),
      .error_code(tile_error_code[8*t +: 8]),
      .error_node(tile_error_node[8*t +: 8])
    );
  end

  // Fair result arbitration, separately from routed internal tokens.
  logic [1:0] result_rr;
  logic result_sel_valid;
  logic [1:0] result_sel;
  logic result_lock_valid;
  logic [1:0] result_lock_sel;
  // Explicit combinational default prevents a latch on the arbitration index.
  integer result_index;
  always_comb begin
    result_index = 0;
    result_sel_valid = 1'b0;
    result_sel = 2'b0;
    tile_result_ready = 4'b0;
    host_result_valid = 1'b0;
    host_result_token = 64'b0;
    // Lock the output owner while ready=0, keeping host token stable.
    if (result_lock_valid) begin
      result_sel_valid = tile_result_valid[result_lock_sel];
      result_sel = result_lock_sel;
      host_result_valid = tile_result_valid[result_lock_sel];
      host_result_token = tile_result_token[64*int'(result_lock_sel) +: 64];
      tile_result_ready[result_lock_sel] = host_result_ready;
    end else begin
      for (int k = 0; k < 4; k++) begin : result_select
        result_index = (int'(result_rr) + k) % 4;
        if (!result_sel_valid && tile_result_valid[result_index]) begin
          result_sel_valid = 1'b1;
          result_sel = 2'(result_index);
          host_result_valid = 1'b1;
          host_result_token = tile_result_token[64*result_index +: 64];
          tile_result_ready[result_index] = host_result_ready;
        end
      end
    end
  end

  logic completed_slot_found;
  logic completed_slot;
  always_comb begin
    completed_slot_found = 1'b0;
    completed_slot = 1'b0;
    for (int s=0; s<2; s++) begin
      if (active_valid[s] && active_context[4*s +: 4] == host_result_token[55:52] &&
          active_epoch[8*s +: 8] == host_result_token[39:32]) begin
        completed_slot_found = 1'b1;
        completed_slot = 1'(s);
      end
    end
  end

  // Expose the FIRST error since last clear. Also count subsequent events.
  logic new_error;
  logic [7:0] new_error_code;
  logic [7:0] new_error_node;
  always_comb begin
    new_error = 1'b0;
    new_error_code = 8'b0;
    new_error_node = 8'b0;
    if (cfg_fire && !cfg_good) begin
      new_error = 1'b1;
      new_error_code = ERR_BAD_CONFIG;
      new_error_node = cfg_node;
    end else if (begin_valid && begin_ready && dup_begin) begin
      new_error = 1'b1;
      new_error_code = ERR_DUP_TAG;
    end else if (bad_dest_valid) begin
      new_error = 1'b1;
      new_error_code = ERR_BAD_DEST;
      new_error_node = bad_dest_node;
    end else if (host_result_valid && host_result_ready && !completed_slot_found) begin
      new_error = 1'b1;
      new_error_code = ERR_DUP_RESULT;
      new_error_node = host_result_token[47:40];
    end else begin
      for (int t=0; t<4; t++) begin
        if (!new_error && tile_error_valid[t]) begin
          new_error = 1'b1;
          new_error_code = tile_error_code[8*t +: 8];
          new_error_node = tile_error_node[8*t +: 8];
        end
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active_valid <= 2'b0;
      active_context <= 8'b0;
      active_epoch <= 16'b0;
      result_rr <= 2'b0;
      result_lock_valid <= 1'b0;
      result_lock_sel <= 2'b0;
      error_valid <= 1'b0;
      error_code <= 8'b0;
      error_node <= 8'b0;
      error_count <= 32'b0;
    end else begin
      if (clear_errors) begin
        error_valid <= 1'b0;
        error_code <= 8'b0;
        error_node <= 8'b0;
        error_count <= 32'b0;
      end else if (new_error) begin
        error_count <= error_count + 32'd1;
        if (!error_valid) begin
          error_valid <= 1'b1;
          error_code <= new_error_code;
          error_node <= new_error_node;
        end
      end
      if (alloc_fire) begin
        active_valid[alloc_slot] <= 1'b1;
        active_context[4*int'(alloc_slot) +: 4] <= begin_context;
        active_epoch[8*int'(alloc_slot) +: 8] <= begin_epoch;
      end
      if (host_result_valid && !host_result_ready && !result_lock_valid) begin
        result_lock_valid <= 1'b1;
        result_lock_sel <= result_sel;
      end
      if (host_result_valid && host_result_ready) begin
        result_lock_valid <= 1'b0;
        result_rr <= result_sel + 2'd1;
        if (completed_slot_found)
          active_valid[completed_slot] <= 1'b0;
      end
    end
  end
endmodule
