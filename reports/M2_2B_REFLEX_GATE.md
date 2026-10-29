# M2.2B Programmable Reflex & Neural-Metadata Gate

**Status:** the first two-hardware-gate verification run passed (GitHub Actions run `40951350805`, SHA `e82f3da17af3c7c8e1265b9994338610b71337eb`); subsequent lossless directed test and final release-branch CI are independently required before merge.

## Implementation

New independent synthesis modules `rtl/xdf_reflex.sv` and `rtl/xdf_perception_frontend.sv`; Python reference `python/xdf1/reflex.py`; cycle oracle and Verilator testbench; directed full SEF-to-reflex integration test; synthesizable wrapper. The existing M2.1 `xdf_sensor_pipeline` and original XDF processor are untouched.

## Architectural behavior

- Eight ordered programmable rules, sensor wildcard, four condition modes, four routing actions, non-maskable SEF alarms.
- Split 176-bit output to urgent reflex and best-effort neural metadata stream; each buffered independently.
- Explicit counters for filtered events, accepted reflex/context records, lost contextual copies and lost **protected** contextual copies. Urgent reflex data remains stable under its own backpressure.
- Full source provenance and original sensor metadata retained in every forwarded record.

## Reference verification

Locally: `PYTHONPATH=python python3 -m pytest -q tests/test_reflex.py` and `PYTHONPATH=python python3 tools/generate_reflex_vectors.py`.

## Measurements from initial successful GitHub CI

- **79 Python tests passed**, including 11 new standalone rule/overflow/reset tests.
- **3,201 cycle-exact oracle comparisons passed:** 2,334 accepted observations, 277 filtered, 415 forwarded to reflex, 508 admitted to neural context, 1,549 context records discarded explicitly, and 172 of those associated with protected alarm events. This fixture deliberately keeps the context sink congested; these losses are **not acceptable evidence retention** for a future production system.
- System-level directed test: eight SEF ingress observations; seven valid alarms forwarded to reflex, one invalid-kind fault, one context record held, six protected context copies explicitly discarded.
- Standalone rule classifier Yosys: **4,806 generic cells, 897 sequential cells**.
- Combined 64-sensor + classifier Yosys: **41,158 generic cells, 12,333 sequential cells**, three reachable module types. Structural register retention and no conflicting drivers verified.
- No FPGA device mapping, real input-rate benchmark, trained network or persistent protected journal; no physical latency figures.

## CI acceptance requirements

- `make reflex-lint reflex-sim frontend-lint frontend-sim` with Verilator.
- `make reflex-synth frontend-synth` with sv2v v0.0.13 and Yosys.
- `make python-test`, plus the existing six RTL/synthesis gates, on the same commit.

## Scope disclaimer

The reflex path begins at a **validated SEF result**; it is not a dedicated asynchronous detector directly on physical pins. Contextual overflow can cause loss of metadata and protected context and is observable but not yet durably journaled. No trained neural network, physical 500 MB/s input, or power/latency measurement has been performed.
