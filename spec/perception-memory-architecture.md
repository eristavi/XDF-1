# XDF-1 Sensory Intelligence, Perception and Episodic Memory Architecture

**Design baseline:** 2026-10-29. **Status:** vision + executable Python *reference*, not physical 500 MB/s hardware. No trained neural network, external memory controller, raw-payload writer, neural accelerator or runtime deadline guarantee is implemented in this milestone.

## The main principle

> Raw sensory data describes the **present**. The working world state represents an evolving **interpretation** of the present. Episodic memory preserves **selected past events** for future use. The processor can act on data without retaining its full raw representation.

This borrows the *functional* distinction between perception, working memory and long-term experience from human cognition. XDF-1 is **not** claimed to be conscious or biologically equivalent to a brain.

## Distinct paths (do not serialize everything through a neural model)

1. **Raw acquisition / data plane (proposed)** — many sensor adapters, 500 MB/s aggregate payload target, timestamp/quality metadata, DMA or equivalent high-speed transfers into external DRAM. A payload might be a camera frame, radar sweep, point cloud, waveform, or batch of small samples. A compact descriptor references payload storage; large payloads are **not** inserted into every 96-bit XDF sensory token.
2. **Reflex / event plane (partially prototyped)** — use the existing 4-lane, 64-logical-sensor SEF and tagged-dataflow processor for compact observations; future conditional comparator and deadline contract required. Reflex rules may react without awaiting GPU inference or disk.
3. **Contextual / neural path (planned)** — modality-specific encoders feed a time-aligned fused state, novelty/uncertainty estimation and context-dependent decisions. Train models on real labeled datasets, validate out-of-distribution behavior, version weights, and keep deterministic rules for essential alarms. Start with an existing GPU/NPU and an ONNX inference interface instead of hard-coding one hardware accelerator.
4. **Working world-state model (Python reference added)** — bounded latest-valid compact feature per logical sensor, with timestamp, units, confidence and provenance; independent of raw-data history and long-term event storage.
5. **AMEE / episodic memory (Python policy reference added)** — score the significance of events; preserve context *before and after* selected events; keep protected evidence even when elective budget is exceeded; store summaries and event provenance; retrieve by time, sensor and future semantic similarity. Persistent raw payload storage and retrieval indexes are future work.
6. **Feedback path (planned)** — sensor acquisition policy, alerts, or external approved actuators receive outputs; separate validation is necessary for critical operation.

## Numerical budgets, decimal units

| Quantity | If 500 MB/s is sustained |
| --- | ---: |
| Data throughput excluding protocol overhead | 4 Gb/s |
| Data generated in one hour | 1.8 TB |
| Data generated in one day | 43.2 TB |
| External-memory ring for 5 s | 2.5 GB |
| External-memory ring for 15 s | 7.5 GB |
| External-memory ring for 30 s | 15 GB |
| 1% selection (reference average) | 5 MB/s = 432 GB/day |
| 10% selection (reference average) | 50 MB/s = 4.32 TB/day |

**Do not assume 500 MB/s as a proven RTL rate.** The current SEF has four 96-bit physical lanes, small FIFOs and *one event processed per cycle*, with no measured clock rate. Event rate, data-plane payload rate and inference operations/second are separate quantities.

### Why a layered memory hierarchy?

A 500 MB/s input stream requires practical external RAM and wide or DMA-based data movement. Do not create hundreds of megabytes of individual small Python objects or rely on a scalar-token router as the raw frame transport. Support descriptor-based zero-copy transfers when available and measure unavoidable copies. Raw memory should be a bounded circular buffer, not permanent storage.

`RawSpan` in the reference identifies external data (`ref`, sensor ID, start/end timestamp and byte length), without allocating the referenced payload. This is intentional: reference metadata tests are **not** 500 MB/s throughput tests. A production ring must pin protected buffers, use atomic ownership/acknowledgment, report incomplete context, and recover from power or device failures.

## 1%-10% retention means *budget*, not indiscriminate compression

The operating target is **average bytes selected for persistence / input bytes** in [0.01, 0.10]. This does **not** mean we can assume 90%-99% of scientific information is redundant. The selected output includes distinct categories: (a) tiny structured state and perception summaries, (b) event-linked feature recordings, and (c) optional raw pre/post windows. The percentages must be measured over a declared workload and time horizon, with audit of missed important events.

Importance signals carry identifiable sources and model/rule versions. The reference scores normalized severity, novelty, relevance, uncertainty and corroboration using transparent fixed weights; it is **not a neural network**. Real policy must incorporate operator requirements, sensor uncertainty, protected-event policy, privacy constraints, and repeated quiet-period samples. Critical events bypass elective byte budgets and may cause temporary retention to exceed 10%. Any loss must be explicit and should trigger alerts/escalation, not a silently successful write.

Selection is not durable storage. Selecting a `dma:...` raw reference does not transfer bytes to SSD. The reference `JsonlEventArchive` writes only event *metadata* and references. A future payload writer requires transactional batch IDs, checksums, idempotency, power-loss handling, pinning and acknowledgement before releasing raw buffers. The reference data structure currently holds historical IDs in process memory (unbounded across very long runtimes), so it is **not** a production continuous-ingestion implementation.

## Time, event semantics and failure discipline

- Timestamp raw samples as near the acquisition source as possible. Keep sensor time base, clock quality/uncertainty and capture-vs-arrival distinction. IEEE 1588/PTP is a candidate for networked synchronous sources; not all sensors or buses can use it.
- Preserve event sequence, source, units, data quality, source graph and model/rule version. Don't compare raw values in unlike units; normalize by calibrated sensor and model schema.
- Keep reflex processing isolated from slow inference, long-term lookup and filesystem writes. Data overload must be observable and controlled; never silently fail open on protected events.
- Define per-stream policies: lossless-with-backpressure when the upstream source supports it, or explicit best-effort with overflow accounting. Data that is too stale must not become fresh merely because it arrived late.
- Maintain per-stage latency histograms: sample captured -> DMA visible -> feature available -> decision -> response. Measure worst-case/p99, event loss, missed critical event rate, throughput, resource usage and power under *real workloads*.
- For personal, health, biometric and camera data, define consent, access control, encryption and data retention/deletion separately from event importance. The chip must not decide to retain private data merely because a model scores it as unusual.

## What is implemented in this milestone

**Reference-only modules** (`python/xdf1/`):

- `world_state.py`: latest-feature working state with finite values, provenance, strict per-sensor monotonic timestamps, bounded active sensor count and expiry.
- `perception_memory.py`: time/byte bounded **metadata ring**, deterministic importance scoring, protected-event override, elective credit-based raw-reference selection, pre/post-event window selection, deduplication of selected refs, JSONL *metadata* writer and explicit failure indicators.
- `tools/demo_memory.py`: a synthetic metadata-only scenario assuming 500 MB/s from four *aggregated logical sources*; reports theoretical selected reference bytes. It does not transfer raw payloads or run a trained model.
- Tests cover capture windows, missing context, stale data, bounded queues, protective override, archive failure, deduplication and arithmetic.

## Architecture next gates

| Gate | Required engineering evidence | Status |
| --- | --- | --- |
| M2.1: SEF -> tagged arithmetic -> decision | Verilator exact checks; Yosys synthesis; bounded output handshake | **Passed**, separate verified hardware |
| M2.2A: Human-readable vision + memory/reference boundaries | Portable SVG diagrams; policy tests; synthetic byte accounting | **Reference gate** (this change) |
| M2.2B: Programmable reflexes | Runtime-configurable comparison/predicate operations, fault modes, RTL tests and independent oracle | **Not started** |
| M2.3: Neural perception interfaces | Real modality encoders, ONNX/GPU/NPU benchmarks, dataset-based recall/precision and drift tests | **Not started** |
| M3: Real sensor data-plane | FPGA/SoC board, DMA, physical 500 MB/s load, clock synchronization and memory protection | **Not started** |
| M4: Durable experience memory | Payload writer, retrieval index, lossless critical journal, measured 1%-10% retention plus recall quality | **Not started** |
| M5: Physical comparative validation | Fmax, BRAM, power and latency vs. conventional CPU/GPU/FPGA baseline | **Not started** |

## Research references (upstream design patterns, not XDF-1 performance evidence)

- NVIDIA Holoscan Sensor Bridge, high-speed acquisition, control/data plane separation and optional RDMA: https://docs.nvidia.com/holoscan/sensor-bridge/applications/architecture
- NVIDIA Holoscan FPGA IP overview and sensor-agnostic data plane: https://docs.nvidia.com/holoscan/sensor-bridge/fpga-ip/overview
- ROS 2 quality-of-service design: https://design.ros2.org/articles/qos
- IEEE 1588-2019 precision clock synchronization: https://standards.ieee.org/ieee/1588/6825/
- ONNX Runtime Execution Providers and heterogeneous deployment: https://onnxruntime.ai/docs/execution-providers/
- SNIA: write endurance, device writes per day and SSD lifetime: https://www.snia.org/education/what-is-ssd

These references inform *candidate design choices*; we have not reproduced any supplier's performance results or validated a device for XDF-1.
