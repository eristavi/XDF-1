# XDF-1 M1 host interface and execution protocol

## Host transaction sequence

1. Assert `rst_n=0`, then deassert; clear any pending host valid pins.
2. For every compiled graph node, drive `cfg_node, cfg_op, cfg_dest_node, cfg_dest_port`, assert `cfg_valid`, and wait for `cfg_ready=1` on the same active clock edge. Check that `error_valid=0` after configuration.
3. For each execution instance, assert `begin_valid` with a unique `(begin_context, begin_epoch)` until `begin_ready=1`. Two pairs may be active simultaneously.
4. Inject each named external operand as a packed token. Hold `host_in_valid=1` and `host_in_token` stable until `host_in_ready=1` at a rising clock edge. Inputs may arrive in any order or be interleaved with those of a second active pair.
5. Wait for `host_result_valid=1`; retain its token stable under backpressure. Accept on a rising edge with `host_result_ready=1`, then decode the resulting context, epoch, and 32-bit value. The tag pair is released after this handshake.
6. Check error status. For a stuck execution instance, reset the device, reload the graph, and start again.

### Python host compiler

`python -m xdf1.cli programs/first_graph.yaml --input A=7 --input B=5 --input C=9 --input D=3 --emit build/run.json`

This command validates the graph; produces the ordered `configuration` commands, 64-bit encoded `injections`, and reference `results`; and prints an equivalent JSON object. Values are normalized to 32-bit arithmetic. The JSON is a portable testing artifact, not a transport protocol for a fabricated device.

### Execution example

- `CFG node=0 op=ADD dest=16 port=0`
- `CFG node=8 op=SUB dest=16 port=1`
- `CFG node=16 op=XOR dest=24 port=0`
- `CFG node=24 op=OUTPUT`
- `BEGIN context=1 epoch=7`
- `INJECT A=7 to (0,0)`, `B=5 to (0,1)`, `C=9 to (8,0)`, `D=3 to (8,1)`
- `READ RESULT node=24 context=1 epoch=7 value=10`

When there are two active tags, result ordering is not defined; the host must match results using `(context, epoch)`.

## Interface state restrictions

- `cfg_ready` is false whenever any execution slot is allocated, and while `begin_valid` is asserted.
- `begin_ready` is false when both slots are allocated, or `cfg_valid` is asserted.
- The host cannot reset one execution instance independently or replace only a fraction of a running graph.
- `cfg_valid` and `begin_valid` should not be asserted concurrently; the implementation resolves them by making both ready signals false. This is a host sequencing rule, not hardware deadlock recovery.
- Configuring a new graph requires complete reset and reload. The release of the last execution tag does not erase prior graph nodes.