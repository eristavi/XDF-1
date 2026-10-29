# M2.2B — Programmable reflex and neural-metadata dispatch

**Status:** synchronous simulation and technology-independent synthesis gate pending. This is not a safety-certified reflex controller, neural accelerator, real physical sensor interface, raw-data DMA engine, or persistent-memory implementation.

## Why a second path?

The existing M2.1 graph evaluates `SUB(raw, EMA)` and produces contextual decisions, but output waits for the tagged graph. This milestone adds a direct programmable classifier **after successful SEF validation but before any XDF graph or neural inference**. The fast path and contextual output have **separate ready/valid buffers**, so slower inference cannot delay a ready reflex sink in best-effort mode. An urgent output can still stall safely if *its own* consumer stops.

### Blocks

- `xdf_sensory` (existing): four independent physical ingress lanes, 64 logical sensor IDs, time/sequence validity checks, EMA/group state, valid 164-bit observation.
- `xdf_reflex` (new): ordered rule bank (eight default), signed comparison and widened delta comparator, autonomous alarm override, independent reflex and context channels.
- `xdf_perception_frontend` (new): minimal wrapper wiring the two, with whole-front-end-idle configuration gating. Does not replace or modify the existing M2.1 `xdf_sensor_pipeline`.

## Program model

At idle, write individual rule entries `cfg_index=0..RULES-1`; the lowest-index matching enabled rule wins. `cfg_index=255` sets the default action. All rule writes are accepted only when there is no live input and both output slots are empty; in the wrapper both SEF and classifier must be idle.

| `cfg_mode` | Match condition |
|---|---|
| `0` | Always true |
| `1` | Signed 32-bit `raw >= threshold` |
| `2` | Unsigned **33-bit magnitude** of signed `(raw-EMA) >= threshold`, requiring a nonnegative signed threshold |
| `3` | SEF group alarm flag |

`cfg_sensor=255` is a wildcard, otherwise it matches one logical sensor ID. `cfg_action`: `0` DROP (no output), `1` CONTEXT only, `2` REFLEX only, `3` BOTH. Default action is DROP. Invalid index and negative change threshold emit a `cfg_fault` pulse without writing the rule bank.

### Non-maskable alarm behavior

Valid `SEF.sensor_alarm` or `SEF.group_alarm` **forces action=BOTH**, even if the rule asks to DROP. This policy is independent of the rule table. It is an important sensor-notification mechanism, but **not a safety-critical, fail-safe actuation guarantee**.

## Output record (176 bits)

Both channels carry the original validated 164-bit observation and self-describing classifier provenance:

| Bits | Contents |
|---|---|
| `163:0` | Unchanged SEF validated event, EMA, group sum and alarm flags |
| `167:164` | Reason bits: `bit3` protected alarm, `bit2` matching rule, `bit1` group alarm, `bit0` sensor alarm |
| `175:168` | First matching rule ID; `255` if none |

The **context stream** is a compact neural-ready *metadata/feature interface*. It does not carry a camera frame, raw waveform, neural tensor, or DMA payload. A future host/accelerator bridge must attach payload descriptors and use a separate high-throughput data plane. Inference model choice can remain independent of RTL using established runtime APIs (e.g., ONNX Runtime execution providers).

## Backpressure and explicit overload policy

- Reflex output: single registered record. If it is held (`valid && !ready`), all further reflex-requiring input **backpressures**; the reflex record remains unchanged, never silently dropped by this module.
- Context output: separate single record. With `CONTEXT_LOSSLESS=0` (default), an incoming context record with a stalled/full buffer is **discarded and counted**; `context_drop_count` tracks every dropped contextual record and `protected_context_drop_count` separately tracks missing alarm context. This avoids allowing a stalled neural consumer to block *an available reflex output*. It does **not** guarantee critical evidence retention. An independent protected evidence logger/alert and storage-acknowledgment protocol are necessary before high-integrity use.
- With `CONTEXT_LOSSLESS=1`, context output stalls propagate back to input. No context records are intentionally discarded, but an urgent event may then be delayed by slow context handling. This tradeoff must be selected explicitly for the application.
- Outputs are stable while `valid && !ready` and can each handshake at most once per clock. Accepted event counters count dispatch decisions, not necessarily downstream deliveries; counters wrap at 2^32.
- The source must hold valid/data stable while input ready is low; both streams use synchronous one-clock-domain ready/valid. Actual asynchronously clocked peripherals need clock-domain crossings outside this module.

## Verification acceptance

1. Python reference model defines exact rule priority, signed/widened arithmetic, non-maskable alarm, output buffering, stall semantics, counters, reset, config refusal and both best-effort/lossless modes.
2. Deterministic 3,000+ cycle oracle vectors compare **every** ready/valid beat, 176-bit output payload, and final accounting with Verilator, including context congestion, urgent alarm override, signed extremes, output stability, and concurrent consumer stalls.
3. Directed end-to-end wrapper test injects SEF 96-bit sensor packets, configures a sensor alarm and checks seven valid reflex outputs, one rejected bad-kind input, contextual stall/drop accounting and the oldest retained contextual event.
4. Independent Yosys generic synthesis of standalone classifier and combined frontend, with structural register-count sanity checks and no conflicting drivers.
5. Keep the original M2.1 processor RTL and its previous six CI regression gates unchanged.

## Still missing

Real neural inference, raw payload/descriptor DMA, latency/energy measurements on physical FPGA, multi-level context queues, guaranteed protected-event journaling, runtime security boundaries, deterministic deadlines, online learning and 500 MB/s system throughput. This work does **not** implement these features.

## Sources informing interface choices

- ARM AMBA AXI4-Stream transfer signaling (valid/ready and stable payload): https://documentation-service.arm.com/static/642583d7314e245d086bc8c9
- NVIDIA Holoscan Sensor Bridge (control plane vs. high-bandwidth sensor data plane): https://docs.nvidia.com/holoscan/sensor-bridge/applications/architecture
- ONNX Runtime Execution Providers (portable acceleration runtime): https://onnxruntime.ai/docs/execution-providers/
