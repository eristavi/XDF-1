# XDF-1 Sensory Event Fabric — experimental v0.2 contract

**Status:** experimental, independent peripheral RTL and Python reference. The
sensory block is NOT connected to the four-tile XDF-1 graph processor, external
sensor hardware, or safety-critical actuator outputs.

## Architectural intent

- Four independent physical ready/valid ingress lanes in the first hardware
  prototype; **each may accept one event during the same clock edge**.
- Logical sensor IDs `0..63` (parameterizable; 256 in the Python model).
- A bounded FIFO per lane, depth 2 by default, plus a single buffered output.
- Up to **one decision or fault processed per clock**. Four simultaneous
  *acceptances* are not four simultaneous *decisions*. This bound is explicit.
- Sensors of different rates may share physical acquisition lanes; there is no
  implicit guarantee of zero loss if the upstream producer ignores `ready`.

## Event (96-bit packed value)

| Bits | Field | Description |
|---|---|---|
| `31:0` | `value` | signed two's-complement 32-bit measurement |
| `63:32` | `timestamp` | 32-bit sensor-source timestamp (unit externally defined) |
| `71:64` | `sensor` | logical sensor ID, 0..63 with default configuration |
| `87:72` | `sequence` | 16-bit modulo sequence number |
| `89:88` | `priority` | 2-bit admission priority, 0 background to 3 high |
| `91:90` | `kind` | presently only 0 accepted |
| `95:92` | `reserved` | must equal zero |

**Clock domain:** one synchronous clock. Real asynchronous sensors must use
proper synchronizers/asynchronous FIFOs before feeding this interface.
A timestamp supplied by a sensor describes its capture instant only when the
sensor/host correctly supplies and synchronizes that time base. This module
**does not measure physical time or synchronize clocks**.

## Decision (164-bit output)

| Bits | Field |
|---|---|
| `95:0` | original event (unchanged) |
| `127:96` | signed 32-bit smoothed sensor reading |
| `161:128` | signed 34-bit rolling **group sum** |
| `162` | per-sensor threshold alarm |
| `163` | four-sensor group threshold alarm |

Adjacent sensors are grouped in fours: `group=floor(sensor_id/4)`.
A group sum stores the latest valid measurement from each of four sensors,
not a time-window sum. An absent sensor contributes zero.

The sensor exponential moving average uses the deterministic fixed-point rule:
`estimate = first_sample ? value : estimate + arithmetic_shift_right(value - estimate,2)`;
subtraction uses at least 33 signed bits and the output is signed 32 bits.
No floating-point instructions, calibration or unit conversion are assumed.

`alarm = (value >= sensor_threshold[sensor_id])`.
`group_alarm = (updated_group_sum >= group_threshold[group])`.
Both comparisons are **signed**. Defaults are maximum signed 32/34-bit values
for predictable behavior until explicitly configured.

## Ordering, fairness and overload

- FIFO ordering is preserved **within each physical lane**.
- Among lane heads, choose highest priority, round-robin within that class.
- After `URGENT_BUDGET` consecutive choices that bypass lower-priority waiting
  lane heads, the next selection serves the *lowest available* priority; then
  the urgent budget resets. The bound applies to **head-of-line** queued events.
- New input cannot bypass its lane FIFO or be selected during the same edge.
- `in_ready[lane]=0` when its FIFO is full unless that same lane dequeues on
  the current edge. The producer **must hold event and valid stable** while
  `ready=0`.
- Output is stable with `result_valid=1 && result_ready=0`. Backpressure
  propagates through the output buffer and FIFOs, rather than dropping data.
- When a producer ignores ready, drops become the producer's responsibility.
- Requests to change thresholds are accepted only while all queues and output
  buffers are idle and no ingress offers are present.

## Validity, sequence and timestamp checks

- Invalid sensor ID, nonzero kind/reserved, repeated/stale sequence, and
  backward source timestamp cause a **fault** and no decision output.
- Sequence freshness: `delta=(new-last)&0xffff`, accepted only if
  `0<delta<0x8000`.
- Timestamp: equal timestamps are allowed; otherwise the same half-range
  modulo-newer rule applies with 32 bits.
- Valid but out-of-order inter-lane arrivals from the *same* sensor may be
  rejected as stale; producers must make their sequence ordering assumptions
  explicit and respect this contract.
- Fault counter is 32-bit wrapping; one popped event can cause at most one
  fault per clock. Fault pulse and sensor ID are observable.

## Reset and acceptance evidence

An active-low asynchronous reset clears queues, counters, state, output valid,
threshold configuration and scheduler state. The 96-bit FIFO payload bits need
not be cleared because queue validity is cleared.

Required CI before graduation:
1. 64-stream Python model deterministic tests and concurrent ingress.
2. RTL lint and exact event-by-event comparison against independent Python
   cycle vectors (readiness, output validity, values, alarms and counters).
3. Directed reset recovery and output backpressure verification.
4. Independent generic Yosys synthesis with reported logic/sequential counts.
5. No assumptions about FPGA Fmax, physical power, energy per decision or
   zeptosecond/femtosecond end-to-end response until **measured**.
