# M2.2B Programmable Reflex & Neural-Metadata Gate

**Status: in verification.** Do not treat this file as proof of passing hardware tests until GitHub Actions completes on the exact committed SHA.

## Implementation

New independent synthesis modules `rtl/xdf_reflex.sv` and `rtl/xdf_perception_frontend.sv`; Python reference `python/xdf1/reflex.py`; cycle oracle and Verilator testbench; directed full SEF-to-reflex integration test; synthesizable wrapper. The existing M2.1 `xdf_sensor_pipeline` and original XDF processor are untouched.

## Architectural behavior

- Eight ordered programmable rules, sensor wildcard, four condition modes, four routing actions, non-maskable SEF alarms.
- Split 176-bit output to urgent reflex and best-effort neural metadata stream; each buffered independently.
- Explicit counters for filtered events, accepted reflex/context records, lost contextual copies and lost **protected** contextual copies. Urgent reflex data remains stable under its own backpressure.
- Full source provenance and original sensor metadata retained in every forwarded record.

## Reference verification

Locally: `PYTHONPATH=python python3 -m pytest -q tests/test_reflex.py` and `PYTHONPATH=python python3 tools/generate_reflex_vectors.py`.

## CI acceptance requirements

- `make reflex-lint reflex-sim frontend-lint frontend-sim` with Verilator.
- `make reflex-synth frontend-synth` with sv2v v0.0.13 and Yosys.
- `make python-test`, plus the existing six RTL/synthesis gates, on the same commit.

## Scope disclaimer

The reflex path begins at a **validated SEF result**; it is not a dedicated asynchronous detector directly on physical pins. Contextual overflow can cause loss of metadata and protected context and is observable but not yet durably journaled. No trained neural network, physical 500 MB/s input, or power/latency measurement has been performed.
