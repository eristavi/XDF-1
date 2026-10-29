# XDF-1 M2 — Sensory Event Fabric verification gates

**Research milestone:** first standalone, stateful, synthesizable sensor stream
processing peripheral. The sensory RTL is deliberately separate from the
existing four-tile computational graph processor. This is **not** a physical
sensor implementation or an ASIC, and the FPGA board clock has not been measured.

## Verified releases on research branch

**Core operand storage optimization:** GitHub Actions run
[40915006303](https://github.com/eristavi/XDF-1/actions/runs/40915006303)
for commit `9add2d68904e48fd763bd3d3ef1e0285470c7f42`:

- Yosys generic leaf cells **90,085 → 35,555**, a **60.5% reduction**;
  5,183 generic sequential cells unchanged.
- Existing XDF-1 Python and 1,000-random-case RTL regressions pass.

**Sensory RTL integration and corrected synthesis:** GitHub Actions run
[40917840911](https://github.com/eristavi/XDF-1/actions/runs/40917840911)
for commit `dc9c031f8f2aa791c462d5099060a463834af377`:

- Python reference: **36 tests passed**.
- Original four-tile RTL regression: **1,000 cases passed**.
- Sensory cycle-by-cycle RTL/reference comparison: **2,514 cycles**;
  **1,887 accepted events**, **1,695 matching decisions**, **192 invalid/stale
  events rejected**, **625 output-held cycles**, and reset recovery passed.
- The Python reference reports **96 threshold alarms** for the workload.
- Simulated accepted-event-to-delivered-result latency: **10.9 cycles mean**,
  **44 cycles p99**, **57 cycles maximum** *for this workload and queue policy*.
  This is not a board Fmax or worst-case timing guarantee.
- Independent `xdf_sensory` generic Yosys synthesis: **36,345 leaf cells**,
  **11,436 sequential** and structural sanity checks passed.
- Initial synthesis attempt generated a false-positive **338-cell netlist**
  because multi-writer FIFO inference resolved signals to X. That result was
  **rejected**, the FIFO implementation was rewritten with a single static
  writer per storage cell, and the build now fails on conflicting-driver
  warnings or implausibly small state utilization.

## Current architectural capabilities

- Four physical ready/valid lanes can accept independent events on the same clock.
- 64 logical sensor IDs; 16 groups, each containing four sensor IDs.
- Original source timestamps, sequence numbers, sensor identity and priorities
  are carried through; *no external sensor timebase synchronization is done*.
- Bounded FIFO ingress and one buffered output, with explicit backpressure.
- Head-of-line priority arbitration with round-robin fairness inside a class,
  and bounded selection of lower-priority waiting heads.
- Stateful signed fixed-point EMA, latest-value group sum, per-sensor and group
  threshold decisions. Boolean conditions are evaluated directly in RTL.
- Protocol faults for invalid sensor IDs, kinds, reserved bits, stale
  sequence numbers and backward source timestamps.

## Phase 1 / 2 milestones not yet completed

- No proof of power reductions, real-time wall-clock latency, FPGA Fmax or
  exact logic delay. The current counts are technology-independent generic gates.
- No SRAM/BRAM inference in the small per-node operand arrays; further storage
  experiments must be measured and verified against the same workload.
- No networked sensor hubs, physical SPI/I2C/camera interfaces, clock-domain
  crossing, sensor synchronization or safety-certified actuation.
- No source-event deadlines, timed cancelation, full hardware temporal windows,
  neural network, general MAC operator or programmable conditional graph routes.
- The `xdf_sensory` block has **not** been connected to XDF-1's four-tile DAG core.
  This integration and end-to-end decision benchmarking are the next gate.

## Acceptance checklist

- [x] Full Python suite verified.
- [x] Original four-tile 1,000-random-case regression verified.
- [x] 4-lane/64-stream sensory RTL matches independent cycle oracle.
- [x] Sensory RTL structural synthesis and state-inference sanity checks pass.
- [x] No fabricated power, timing or silicon area numbers.
- [ ] Sensor front end connected to core/actuator interfaces and retested.
- [ ] Demonstrate real sensor streams with device-specific FPGA timing closure.

## Reproduce

```bash
python3 -m pip install -e . pytest
make python-test
make sensory-lint sensory-sim
make sensory-synth
```

See `spec/sensory-event-protocol.md` for the frozen v0.2 semantics and error
handling. Logs and netlist summaries are attached to the corresponding GitHub
Actions run as downloadable artifacts.
