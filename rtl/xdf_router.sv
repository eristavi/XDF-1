// 5-to-4 single-transfer router: src 0=host, src 1..4=tiles 0..3.
// Fair round-robin among currently transferable sources; ready/valid handshake.
module xdf_router (
  input  logic         clk,
  input  logic         rst_n,
  input  logic [4:0]   src_valid,
  output logic [4:0]   src_ready,
  input  logic [319:0] src_token,
  output logic [3:0]   dst_valid,
  input  logic [3:0]   dst_ready,
  output logic [255:0] dst_token,
  output logic         bad_dest_valid,
  output logic [7:0]   bad_dest_node
);
  logic [2:0] round_robin;
  logic granted;
  logic [2:0] grant_id;
  always_comb begin
    src_ready = 5'b0;
    dst_valid = 4'b0;
    dst_token = 256'b0;
    bad_dest_valid = 1'b0;
    bad_dest_node = 8'b0;
    granted = 1'b0;
    grant_id = 3'b0;
    for (int k = 0; k < 5; k++) begin : search
      int i;
      logic [63:0] tok;
      logic [7:0] node_id;
      logic [1:0] tile;
      i = (int'(round_robin) + k) % 5;
      tok = src_token[i*64 +: 64];
      node_id = tok[47:40];
      tile = node_id[4:3];
      if (!granted && src_valid[i]) begin
        if (node_id[7:5] != 3'b0) begin
          granted = 1'b1;
          grant_id = 3'(i);
          src_ready[i] = 1'b1;
          bad_dest_valid = 1'b1;
          bad_dest_node = node_id;
        end else if (dst_ready[tile]) begin
          granted = 1'b1;
          grant_id = 3'(i);
          src_ready[i] = 1'b1;
          dst_valid[tile] = 1'b1;
          dst_token[64*int'(tile) +: 64] = tok;
        end
      end
    end
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      round_robin <= 3'd0;
    else if (granted)
      round_robin <= (grant_id == 3'd4) ? 3'd0 : grant_id + 3'd1;
  end
endmodule
