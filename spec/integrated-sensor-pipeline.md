# XDF-1 M2.1 sensor-to-dataflow integration contract

**Status:** experimental synchronous reference pipeline; no physical sensor clock
crossing, FPGA board, hard realtime guarantee, power measurements or safety
certification. This integration wires two previously simulated hardware designs,
without modifying their existing program or sensory-event contracts.

## Architecture

`4 SEF acquisition lanes -> SEF priorities / 64 sensor states -> fixed tagged XDF
SUB(raw, estimate) -> OUTPUT -> combined threshold decision`.

- `xdf_sensory` queues up to 2 events per lane, accepts four different lane
  handshakes on a single rising edge, serializes event processing to one per
  clock, validates sequence and timestamps, and maintains EMA/group state.
- `xdf_sensor_pipeline` atomically accepts a *validated* 164-bit SEF result
  and allocates one of **two** live `(context, epoch)` tags in `xdf_top`.
  It waits for both input tokens to be accepted, rather than dropping input on
  host-router backpressure.
- The boot controller programs exactly two nodes into existing XDF tile hardware:
  `node 0: SUB(port0 raw_value, port1 smoothed_value) -> node 24`;
  `node 24: OUTPUT`. No general graph loader is exposed through this wrapper.
  Core can have two graph instances in flight while the SEF independently
  receives a multi-lane burst.
- A two-entry metadata array associates SEF's full sensory result with its
  corresponding XDF context and epoch. The terminal result is checked against
  the expected node, port, flags and live tag before it can retire a context.
  The identity of the original event is preserved even if results reorder.
- One buffered output uses ready/valid and propagates backpressure to XDF,
  then SEF, then sensor ingress. Source producers must hold input stable until
  their lane reports `ready=1`.
- Unexpected graph results raise sticky `pipeline_error`, requiring reset;
  SEF input faults are separately observable and do not enter the compute core.

## Result format: 197 bits

| Bits | Meaning |
|---|---|
| 163:0 | Unchanged 164-bit SEF result (sensor + group alarms, group sum, EMA, original 96-bit event) |
| 195:164 | XDF modular `raw_value - smoothed_value` (32-bit two's complement bit pattern) |
| 196 | Critical: `sensor_alarm OR group_alarm OR signed_abs(delta) >= DELTA_LIMIT` |

The example `DELTA_LIMIT` is a synthesis parameter (20 units by default), not a
runtime-calibrated sensor threshold. `signed_abs(delta)` means interpreting the
**wrapped 32-bit SUB result** as a signed number and taking its magnitude; the
choice is intentionally consistent with XDF's documented modular arithmetic,
but overflow makes the value unsuitable for high-integrity real-world control
without further numerical qualification.

The SEF output is NOT itself a safety-critical actuation signal. No feedback
signals are wired to real devices. There is no extra reflex pathway independent
of XDF computation in this milestone.

## Interfaces and execution

- Same synchronous `clk` and active-low asynchronous `rst_n` for both blocks.
- Sensor ingress: `sensor_valid[3:0]`, `sensor_ready[3:0]`,
  `sensor_event[383:0]`; four 96-bit lanes, lane 0 at bits 95:0.
- Sensor configuration forwards the existing `cfg_valid/ready`, group, sensor
  index and signed 34-bit threshold controls to SEF. Configure when SEF is idle.
- `initialized` indicates completion of the fixed graph's internal boot writes.
- `inflight[1:0]` indicates metadata slots awaiting terminal core results.
- Decision interface: `decision_valid`, `decision_ready`, `decision_data[196:0]`.
- Exposed sticky pipeline errors and independent sensor faults/counters.
- `debug_stall_tiles` is only a verification hook for XDF ingress backpressure.

A full reset is the unconditional recovery path for incomplete tag instances.
The epoch counter wraps after 256 begins, but reuse is safe only because each
metadata slot is released after matching completion and no delayed tokens are
allowed to arrive from completed epochs.

## Verification gates

1. Original Python model, existing 1,000-vector core RTL regression, original
   2,514-cycle SEF Python/RTL crosscheck, both independent synthesis targets.
2. Python arithmetic test cases covering signed thresholds, overflow,
   full metadata retention and modular arithmetic.
3. Integrated RTL testbench with 4 lanes and 64 sensor IDs: input backpressure,
   core tile stalls, output stalls, 2 live graph contexts, invalid events,
   reset/reinitialization and no duplicated, lost or mismatched result.
4. Technology-independent sv2v/Yosys synthesis of the complete integrated top
   with `check -assert`, a structural sequential-cell sanity check, and failure
   on driver-driver conflict warnings. Report generic cells accurately.
5. Clock-frequency, FPGA LUT/BRAM mapping, electrical throughput, sensor clock
   crossing, and energy per decision are **not** established by these gates.

This is the first *integrated* pipeline, not yet completion of all Phase 1/2
optimization objectives. Future milestones need configurable graph programs,
conditional routing, deadline and priority propagation through computation,
physical sensor interfaces, and measured throughput/energy comparisons.
