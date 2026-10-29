# M2.1 — Integrated sensor-to-compute decision gate

## What was built

A synchronous top-level research wrapper joins the independently tested XDF-1
Sensory Event Fabric (`xdf_sensory`) with the optimized four-tile tagged-dataflow
processor (`xdf_top`). Events arrive on four input lanes and may represent
64 logical sensor IDs. The SEF handles admission, freshness, priority, fixed-point
EMA, group state and sensor/group threshold alarms. Each valid SEF result is
paired with an XDF tag and two input tokens for the fixed graph
`SUB(raw, EMA) -> OUTPUT`. The wrapper associates the computation with its
original sensor metadata and emits one 197-bit decision.

The wrapper has room for two in-flight graph contexts and a separate one-entry
output buffer. Backpressure reaches the SEF's queues and ultimately the
physical ingress ready signals. Sensor faults are counted and do not reach
XDF computation. The compute error signal is sticky and requires reset.

## Verified behavior — GitHub Actions

- Existing 1,000-vector tagged-graph RTL regression remains passing.
- Existing sensory RTL/Python crosscheck remains passing (2,514 cycles).
- Expanded Python suite: **45 tests passed**.
- Integrated RTL testbench **passed**: **840** sensor events accepted, **824**
  decisions delivered, **16** faulty observations rejected; observed **two**
  simultaneous XDF contexts.
- Deliberate output backpressure, temporary tile input stalls, error accounting,
  metadata integrity, nonduplicate results and reset/reinitialization passed.
- Mean sensor-handshake-to-output acceptance latency (with stalls): **70
  simulated clock cycles**; worst observed: **155 cycles**. The test workload is
  deterministic, deliberately stalls the downstream sink, and does not measure
  external sensor capture or real-world reaction times.

## Technology-independent synthesis

- [Successful CI run #40931936713](https://github.com/eristavi/XDF-1/actions/runs/40931936713) on commit `fbf48f6af08727878aef1b18eb3a03a752b7e156`.
- `sv2v` / Yosys generic synthesis: **73,019** leaf logic cells, including
  **17,184** sequential cells, across **8 reachable module types**.
- Yosys `check -assert` and independent structural sequential-cell sanity
  verification **passed**, with no driver-driver conflict warnings accepted.
- All six workflow jobs passed, including original core/SEF regressions and
  full integrated RTL/synthesis gates.

These are **technology-independent** cell counts. No FPGA target was selected;
there are no mapped LUT/BRAM counts, clock constraints, placement/routing,
static timing, hardware power measurements, or ASIC area estimates.

## Design boundaries and outstanding work

1. The program graph is fixed for this integration test. General-purpose
   validated programmable graph configuration is intentionally not exposed.
2. A sensor decision can occupy a core tag until the compute result is accepted;
   the sensory front-end processes at most one event per clock.
3. The prototype has no external sensor PHY, clock-domain crossing, actuator,
   safety monitor, hard real-time deadline guarantee, or power management.
4. Priority applies to SEF acquisition, not yet to XDF tile scheduling or
   critical response paths; there is no independent reflex bypass.
5. The 32-bit modular subtraction represents sensor deviation, not a
   high-integrity wide signed difference in extreme overflow cases.
6. Compare latency and resources against a fair baseline and then make the graph
   programmable before selecting a real FPGA board.

The correct outcome is a reproducible **hardware-simulated and generic-synthesized
integration demonstration**. It does not establish sensor-clock timing,
application accuracy, energy efficiency, or a deployable processor.
