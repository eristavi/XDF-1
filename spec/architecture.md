# XDF-1 v0.1 architecture specification (M1 freeze)

**Status:** Experimental research design; not a completed ASIC or a validated new invention.
**Architecture revision:** M1-0.1. **Scope:** bounded DAG execution; no loops or memory loads/stores.

## 1. Machine organization

- Four identical, synchronous 32-bit integer processing tiles in a logical 2x2 topology.
- Eight independently configurable graph nodes per tile (32 addressed node IDs total).
- Two simultaneous execution instances, distinguished by `(context[3:0], epoch[7:0])`.
- One output token buffer and one ALU scheduler per tile; maximum one node firing per tile per cycle.
- One fair round-robin, five-source-to-four-destination token router, committing at most one transfer per cycle.
- One host configuration port, one tag allocation port, one 64-bit input port, one 64-bit result port.
- No instruction fetch, program counter, register ISA, virtual memory, operating system, or external SRAM in M1.

This design is *synchronous, data-driven*: an operation becomes eligible to fire once all its operands have arrived. Execution latency is affected by arbitration and backpressure; numerical outputs are independent of input arrival order for valid graphs.

## 2. Token bit encoding

`token = {flags[7:0], context[3:0], port[3:0], node[7:0], epoch[7:0], value[31:0]}`

| Bits | Field | M1 semantics |
|---|---|---|
| 31:0 | value | Unsigned 32-bit bit pattern; signed interpretation only for extensions |
| 39:32 | epoch | 0..255, execution instance component |
| 47:40 | node | destination node ID 0..31; upper 3 bits must be 0 |
| 51:48 | port | 0 or 1 on binary operations; only 0 on unary operations |
| 55:52 | context | 0..15, execution instance component |
| 63:56 | flags | Must be 0 for all M1 tokens; nonzero is a protocol error |

Fields are *bit positions*, not an endianness specification for an external byte protocol. The Python host encodes and decodes packed 64-bit integers. Byte order for a future physical interface must be specified separately.

Node numbering is fixed: `tile = node_id >> 3`; `local_node = node_id & 7`.

## 3. Graph program and operations

The program is a finite directed acyclic graph (DAG). Each configured node has:

- a unique node ID from 0 through 31;
- a supported opcode;
- for nonterminal nodes, one output route `(dest_node, dest_port)`.

| Opcode | Mnemonic | Input ports | 32-bit result |
|---|---|---|---|
| 0 | ADD | 0, 1 | `(a + b) mod 2^32` |
| 1 | SUB | 0, 1 | `(a - b) mod 2^32` |
| 2 | XOR | 0, 1 | bitwise XOR |
| 3 | AND | 0, 1 | bitwise AND |
| 4 | PASS | 0 | `a` |
| 5 | OUTPUT | 0 | emits terminal result to host; no onward route |
| 6..7 | — | — | invalid configuration |

A valid program contains exactly one terminal OUTPUT node. Each operand port of each node has **exactly one producer**, either an external named input or the output of an upstream node. Every configured node must lead to OUTPUT; all graph edges must be acyclic. This means every node fires exactly once for each valid execution instance. There is no graph self-modification during active execution.

The included graph calculates `(A+B) XOR (C-D)` using nodes 0 (ADD), 8 (SUB), 16 (XOR), and 24 (OUTPUT).

## 4. Execution tags and token matching

- A host `BEGIN` allocates one of two currently unused slots for an exact `(context, epoch)` pair.
- Each tile maintains `valid0`, `valid1`, operand data, and `fired` per node and tag slot.
- Token destination node and `(context, epoch)` select a unique operand location.
- Token insertion is atomic on the `valid && ready` handshake.
- If a node has all required input ports valid and has not yet fired for that slot, it is *eligible* to execute.
- A round-robin scheduler chooses an eligible node if the tile's one-entry output buffer is free or being consumed that cycle.
- Firing consumes both operands (or one for unary), marks the node fired, and emits one token to the configured destination or the terminal output channel.
- A terminal result remains stable under host backpressure. On its accepted `valid && ready` handshake, the global execution tag is released.
- Before a released slot is reused, operand and fired state are cleared synchronously by the next `BEGIN` allocation. The host must not inject tokens belonging to a completed instance.

Tokens for different active tag pairs may be interleaved. Matching NEVER mixes tokens from distinct pairs even when their destination node is identical.

**Ordering:** No defined ordering between independent operations or completed results across different execution pairs. There is exactly one numerical result per valid graph instance. Scheduling affects latency, not numerical results.

## 5. Routing and backpressure

The router has five ingress sources (host plus four tile outputs) and four destinations (tiles). Selection is fair round-robin among sources with valid, transferable tokens; a source whose destination is stalled may be bypassed. Each router cycle transfers **at most one token**.

- A source owns its token while `valid=1 && ready=0` and must keep that token stable.
- Transfers occur only on a rising clock with `valid=1 && ready=1`.
- The router forwards only to a destination indicated by the token's `node` field.
- Invalid destination node 32..255 is consumed and reported via `ERR_BAD_DEST`.
- Each tile's one-entry output buffer applies backpressure to its scheduler when the router/host will not accept it.
- Legitimate graph inputs fit the statically allocated operand storage. Invalid duplicate operands are consumed and reported instead of silently overwriting pending operands.
- The `debug_stall_tiles` mask deliberately disables ingress readiness for verification. It is not a necessary architectural feature for a future ASIC interface.

**Fairness caveat:** Successful transfer requires the destination to eventually be ready; an indefinitely stalled tile or host can block progress. For valid finite DAGs with fair output consumption and finite stalls, all tags should eventually complete.

## 6. Hardware host pins (synchronous)

All inputs are sampled on `posedge clk`, active-low asynchronous reset `rst_n`.

### Program configuration

`cfg_valid,cfg_ready,cfg_node[7:0],cfg_op[2:0],cfg_dest_node[7:0],cfg_dest_port[3:0]`

- Accepted on `cfg_valid && cfg_ready`.
- `cfg_ready` is high only when **both execution slots are inactive** and no BEGIN is being asserted.
- Valid configuration writes set/replace the selected node's configuration; other configured nodes are retained.
- A full graph load after a different graph is NOT supported without `rst_n` reset in M1; the host must reset before programming a different graph, since otherwise unused old nodes remain enabled.
- Elementary invalid fields trigger `ERR_BAD_CONFIG` and do not change the node. Full graph validity is checked by the Python loader, not synthesized hardware.

### Tag allocation

`begin_valid,begin_ready,begin_context[3:0],begin_epoch[7:0]`

- Accepted on `begin_valid && begin_ready`. Valid unique tags occupy the first free slot.
- A duplicate existing tag is consumed as an error `ERR_DUP_TAG` (it does not allocate a new slot).
- When two tags are active, `begin_ready=0`.

### Host input and result

- Ingress: `host_in_valid,host_in_ready,host_in_token[63:0]`.
- Completion: `host_result_valid,host_result_ready,host_result_token[63:0]`.
- `host_result_token` retains the OUTPUT node ID, context, epoch and computed result; port=0, flags=0.

### Errors

- `error_valid` is sticky until `clear_errors` or reset.
- `error_code, error_node` capture the **first** error since the most recent clear.
- `error_count` counts observed errors (wraps after 2^32); arbitration collapses simultaneous errors into one per cycle, so it is not a precise count of all dropped-token faults under concurrent invalid traffic.
- The host must check `error_valid` after configuration and execution. An error can prevent an instance from completing; reset is the unconditional recovery mechanism.

| Code | Meaning |
|---|---|
| 1 | BAD_CONFIG: invalid configuration write |
| 2 | DUP_TAG: begin requested for an already active pair |
| 3 | BAD_DEST: token routed to node outside 0..31 |
| 4 | BAD_TAG: token has no active `(context, epoch)` pair |
| 5 | UNCONFIGURED: destination node not programmed |
| 6 | BAD_PORT: operand port unsupported by operation |
| 7 | DUP_OPERAND: port filled twice or node has fired |
| 8 | BAD_FLAGS: nonzero reserved flags |
| 9 | DUP_RESULT: result has no corresponding active tag |

## 7. Reset and error recovery

Driving `rst_n=0` asynchronously clears active tags, configured nodes, operand-valid/fired state, outstanding output tokens, router state, result status, and sticky errors. Payload data may be zeroed, but the only architecturally significant values after reset are their invalid flags.

Because there is no cancel-one-tag mechanism in M1, host software uses full reset to recover from an error that leaves a graph incomplete.

## 8. M1 exclusions and security assumptions

This is an experimentation platform with **no** isolation between untrusted programs, no authenticated program loading, no MMU, no memory protection, no coherent caches, no power management, and no general-purpose programming capabilities. Host graph validation is a *trusted* preparation step. Fault injection and malicious concurrent inputs are outside the proof-of-correctness scope.

## 9. M1 acceptance tests

1. Two tagged executions return `(7+5) XOR (9-3)=10` and `(2+8) XOR (20-11)=3` without mixing operands.
2. At least 1000 reproducible input cases match independent reference-model expected results.
3. Stall input delivery and output acceptance; token/result stability must hold until handshake.
4. Illegal input ports and invalid program configuration report correct errors.
5. Reset mid-run clears state, and a reprogrammed new run succeeds.
6. Hardware source parses, simulates, and synthesizes with named tool versions and a documented cell report before claiming completion.

A passing Python model by itself does **not** satisfy RTL or silicon acceptance criteria.