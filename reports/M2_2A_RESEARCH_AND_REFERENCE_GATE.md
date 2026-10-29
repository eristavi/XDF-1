# M2.2A — Perception, neural-interface and selective-memory architecture gate

## Scope and methodology

Document the user's complete XDF-1 objective and provide a small, independently testable Python **semantic reference** for working-state expiry and memory importance selection. Protect existing RTL (M2.1) and avoid claiming high-throughput acquisition or neural inference merely from model-derived bytes.

## Findings and design choices

1. **Separate payload and event planes:** 500 MB/s (= 4 Gb/s) raw ingress is not the same thing as four 96-bit event lanes; high-bandwidth buffers and DMA should be investigated on a selected FPGA/SoC platform.
2. **Separate cognition-inspired lifetimes:** transient external raw ring, compact current world-state, and event-centric memory records. Retention target is 1%-10% *by byte volume averaged over a specified window*, not a guarantee of semantic preservation, fixed compression ratio, or cap on protected incidents.
3. **Neural models belong behind a validated interface:** test specialized sensory encoders and time-aware multimodal fusion on GPU/NPU/ONNX before proposing custom neural accelerators. Reflex path must remain independent.
4. **Memory is an asynchronous consumer:** preservation decisions refer to raw buffers; actual durable raw writes require pinning, replay safety and acknowledgement, not merely saving descriptors.
5. **Provenance, clock quality, privacy and audit:** events need time base, source, units, model version, quality and policy reason. A disk budget must not erase critical evidence.

## Files added / changed in this milestone

- `README.md`: fully revised public explanation with verified vs. planned scope.
- `docs/diagrams/xdf-vision.svg`, `perception-memory.svg`, `milestones.svg`: portable architecture illustrations.
- `tools/make_vision_diagrams.py`: deterministic diagram generator.
- `spec/perception-memory-architecture.md`: interface and lifecycle contract.
- `spec/sensor-taxonomy.md`: all 50 sensor types grouped by acquisition requirements.
- `python/xdf1/world_state.py`: bounded current-state reference.
- `python/xdf1/perception_memory.py`: selective event-memory reference and metadata archive.
- `tools/demo_memory.py`: *descriptor-only* synthetic 500 MB/s workload.
- `tests/test_perception_memory.py`, `test_world_state.py`, `test_demo_memory.py`: reference tests and failure handling.

## Verification and limitations

All existing M2.1 Python/RTL/generic synthesis gates should remain green; this milestone does **not** edit existing RTL. Python tests exercise new memory logic, including protected-event override, window capture, time-and-byte bounded buffer, incomplete context flag, stale state, storage failure, no duplicate byte accounting and no silent queue overflow.

The synthetic 500 MB/s demo produces only metadata descriptors: it **never processes 500 MB/s of actual bytes**, executes no trained neural network, has no FPGA mapping and writes **zero raw payload bytes**. The JSONL archive stores event *metadata*; it is not an SSD payload engine. Reference Python data structures use unbounded identifier history; a production service must use bounded durable indexes and replay-safe transactions. Its capture-completeness flag only checks temporal edge coverage, not per-sample continuity. Its retention accounting represents **selected reference bytes**, not durable disk bytes. Report these separately.

## Reproducible commands

```bash
python3 -m pip install -e . pytest
make python-test
PYTHONPATH=python python3 tools/demo_memory.py --seconds 350 --target 0.05
python3 tools/make_vision_diagrams.py
```

The demo prints an explicit warning that its byte rate is **assumed**, not benchmarked. For full CI details see GitHub Actions for this change.

## Next hardware engineering gate

M2.2B: programmable reflex compares/predicates (independently compared with a Python oracle), conditionally routed events, priority/deadline propagation with valid/ready and fault coverage; then integrate a real GPU inference process and benchmark alternative raw acquisition paths. Do not merge work with incomplete verification.
