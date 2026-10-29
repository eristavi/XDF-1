# XDF-1 — measured optimization decisions

All figures are technology-independent generic Yosys cell instances,
**not** FPGA LUTs, power, clock speed, physical area or ASIC cell count.
Only candidates passing the original and new RTL testbenches are eligible.

## Experiment A — static per-node operand storage (ACCEPTED)

| Version | Generic leaf cells | Sequential cells | RTL regression |
|---|---:|---:|---|
| M1.1 baseline | 90,085 | 5,183 | 1,000 cases pass |
| Statically enabled per-node operand registers | 35,555 | 5,183 | 1,000 cases pass |

**Outcome:** −54,530 leaf cells (−60.53%) without changing storage capacity.
The earlier design's dynamically indexed register writes created excessive
read-modify-write selection circuitry. Static node/slot ownership produces
cheaper FF enables. GitHub CI:
[passing optimization test](https://github.com/eristavi/XDF-1/actions/runs/40915006303).

## Experiment B — sensory FIFO storage write inference (MANDATORY CORRECTION)

The first sensory synthesis reported **338 generic cells / 82 sequential** for
a 64-sensor design, after many Yosys **driver-driver conflict** warnings.
It was **invalid**: do not use that count as a successful optimization.

Replacing dynamic writes to nested FIFO memory with one static writer per
physical FIFO cell eliminated the conflicts. The corrected design gives
**36,345 generic cells / 11,436 sequential**, and matches Python expectations
on 2,514 cycles, including 1,887 accepted events, 1,695 valid decisions and
192 rejected observations. CI now **fails** if synthesis reports conflicting
drivers or an implausibly low sensor-state count.

## Experiment C — one-hot sensor state read selection (REJECTED)

The same sensory module was rewritten to decode the sensor ID once and select
all six state arrays through parallel one-hot AND/OR networks rather than
ordinary indexed reads.

| Design | Generic leaf cells | Sequential cells | RTL test |
|---|---:|---:|---|
| Corrected indexed-read baseline | 36,345 | 11,436 | pass |
| One-hot read selection | 36,322 | 11,436 | pass |

Only **23 cells** (approximately **0.063%**) were saved. This is smaller than
meaningful cost or uncertainty in physical mapping and provides no verified
clock or energy improvement. **Not adopted**, to keep RTL simpler and easier
to maintain. Experimental branch:
[`experiment/sensory-onehot-state-read`](https://github.com/eristavi/XDF-1/tree/experiment/sensory-onehot-state-read).

## Pending experiments

- Graph processor token routing contention under heavy, balanced traffic.
- FPGA-mapped LUT/BRAM inference compared with explicit registers.
- Event-queue depth and scheduling policies across 4, 8 and 16 input lanes.
- SRAM banked group state and a latency-aware arbitration option with measured
  Fmax, area and energy outcomes.

Do not infer speedup or power savings from a generic gate-count improvement.
