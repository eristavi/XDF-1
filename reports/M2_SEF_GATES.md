# XDF-1 M2 — Sensory Event Fabric verification gates

This report tracks the first **independently synthesizable sensory front-end**.
The existing XDF-1 arithmetic graph processor is a separate module and must
continue passing its prior hardware regression after any edits.

## Candidate capabilities

- Four physical ingress queues accept independently in the same clock.
- 64 configurable sensor IDs; 16 groups of four sensors.
- Event capture metadata preserved (source timestamp, ID, sequence, priority).
- Priority-preference arbitration with bounded service of waiting lower-priority lanes.
- Signed fixed-point EMA, stateful latest-value fusion, threshold/predicate decisions.
- Input/output ready-valid backpressure, explicit stale-event faults and async reset.
- Independent Python model and generated deterministic cycle-by-cycle vectors.

## Acceptance checklist

- [ ] Full Python suite passed on milestone commit.
- [ ] Original four-tile 1,000-random-case RTL regression passed.
- [ ] Sensory Verilator RTL simulation matched Python cycle oracle.
- [ ] Sensory RTL synthesizes and passes Yosys `check -assert`.
- [ ] Resource counts recorded separately from core logic baseline.
- [ ] Module explicitly documented as not yet integrated with external sensors.

### Latest verified optimization result

Optimization commit `9add2d68904e48fd763bd3d3ef1e0285470c7f42` passed
Python/RTL regression and Yosys synthesis on GitHub Actions. Synthesis counted
**35,555** generic leaf cells versus **90,085** for the original M1.1 design
(same Yosys generic flow, 60.5% lower); both counted 5,183 sequential cells.

These figures are not FPGA LUT/BRAM utilization, ASIC area, measured clock
frequency or power. New sensory subsystem resources will be reported separately.
