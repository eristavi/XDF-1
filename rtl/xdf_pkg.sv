// XDF-1 v0.1 architectural constants. 64-bit little-field token.
package xdf_pkg;
  localparam logic [2:0] OP_ADD    = 3'd0;
  localparam logic [2:0] OP_SUB    = 3'd1;
  localparam logic [2:0] OP_XOR    = 3'd2;
  localparam logic [2:0] OP_AND    = 3'd3;
  localparam logic [2:0] OP_PASS   = 3'd4;
  localparam logic [2:0] OP_OUTPUT = 3'd5;

  localparam logic [7:0] ERR_BAD_CONFIG    = 8'd1;
  localparam logic [7:0] ERR_DUP_TAG       = 8'd2;
  localparam logic [7:0] ERR_BAD_DEST      = 8'd3;
  localparam logic [7:0] ERR_BAD_TAG       = 8'd4;
  localparam logic [7:0] ERR_UNCONFIGURED  = 8'd5;
  localparam logic [7:0] ERR_BAD_PORT      = 8'd6;
  localparam logic [7:0] ERR_DUP_OPERAND   = 8'd7;
  localparam logic [7:0] ERR_BAD_FLAGS     = 8'd8;
  localparam logic [7:0] ERR_DUP_RESULT    = 8'd9;

  function automatic logic [63:0] pack_token(
    input logic [31:0] value,
    input logic [7:0] epoch,
    input logic [7:0] node,
    input logic [3:0] port,
    input logic [3:0] ctx_id
  );
    return {8'h00, ctx_id, port, node, epoch, value};
  endfunction

  function automatic logic [31:0] do_alu(
    input logic [2:0] opcode,
    input logic [31:0] a,
    input logic [31:0] b
  );
    case (opcode)
      OP_ADD:    return a + b;
      OP_SUB:    return a - b;
      OP_XOR:    return a ^ b;
      OP_AND:    return a & b;
      OP_PASS:   return a;
      OP_OUTPUT: return a;
      default:   return 32'b0;
    endcase
  endfunction
endpackage
