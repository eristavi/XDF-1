"""Reference arithmetic for the sensor -> tagged-dataflow -> decision bridge.

The bridge's fixed graph computes two's-complement 32-bit RAW - EMA using XDF
SUB/OUTPUT. Sensor thresholds are evaluated by the existing SEF reference.
This module describes *decision semantics*, not unmeasured hardware latency.
"""
from __future__ import annotations
from dataclasses import dataclass

MASK32 = (1 << 32) - 1


def signed32(raw: int) -> int:
    value = raw & MASK32
    return value - (1 << 32) if value & (1 << 31) else value


@dataclass(frozen=True)
class PipelineDecision:
    """Deterministic result for an already validated SEF observation."""

    delta_bits: int
    delta_signed: int
    critical: bool
    sensor_alarm: bool
    group_alarm: bool


def decide(raw: int, estimate: int, sensor_alarm: bool,
           group_alarm: bool, delta_limit: int = 20) -> PipelineDecision:
    if not 0 <= delta_limit <= MASK32:
        raise ValueError("delta_limit must be a 32-bit unsigned magnitude")
    if type(raw) is not int or type(estimate) is not int:
        raise TypeError("raw and estimate must be integers")
    if not -(1 << 31) <= raw < 1 << 31 or not -(1 << 31) <= estimate < 1 << 31:
        raise ValueError("raw and estimate must be signed 32-bit")
    delta_bits = (raw - estimate) & MASK32
    delta_signed = signed32(delta_bits)
    return PipelineDecision(
        delta_bits=delta_bits,
        delta_signed=delta_signed,
        critical=bool(sensor_alarm or group_alarm or abs(delta_signed) >= delta_limit),
        sensor_alarm=bool(sensor_alarm),
        group_alarm=bool(group_alarm),
    )


def pack_result(meta_164: int, delta_limit: int = 20) -> int:
    """Convert SEF 164-bit result to the bridge's documented 197-bit output."""
    if type(meta_164) is not int or not 0 <= meta_164 < (1 << 164):
        raise ValueError("meta_164 must be a 164-bit integer")
    raw = signed32(meta_164)
    estimate = signed32(meta_164 >> 96)
    decision = decide(raw, estimate, bool((meta_164 >> 162) & 1),
                      bool((meta_164 >> 163) & 1), delta_limit)
    return (int(decision.critical) << 196) | (decision.delta_bits << 164) | meta_164
