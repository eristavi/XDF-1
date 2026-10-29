"""Bounded *current* sensory state, separate from episodic archival memory.

This is a pure reference model: it stores compact features, not raw frames.
Time correlation, uncertainty estimation, and neural encoders are future work.
"""
from __future__ import annotations

from dataclasses import dataclass
import math


@dataclass(frozen=True)
class CurrentObservation:
    sensor_id: int
    timestamp_ns: int
    value: float
    unit: str
    confidence: float
    source: str

    def __post_init__(self) -> None:
        if self.sensor_id < 0 or self.timestamp_ns < 0 or not self.unit or not self.source:
            raise ValueError('invalid sensor identity, time, unit or provenance')
        if not math.isfinite(self.value) or not math.isfinite(self.confidence):
            raise ValueError('non-finite state value or confidence')
        if not 0 <= self.confidence <= 1:
            raise ValueError('confidence must be in [0,1]')


class WorldState:
    """Latest valid per-sensor observation with bounded capacity and expiry."""
    def __init__(self, max_sensors: int = 4096, expiry_ns: int = 5_000_000_000):
        if max_sensors < 1 or expiry_ns <= 0:
            raise ValueError('capacity and expiry must be positive')
        self.max_sensors = max_sensors
        self.expiry_ns = expiry_ns
        self._current: dict[int, CurrentObservation] = {}

    def update(self, item: CurrentObservation) -> None:
        old = self._current.get(item.sensor_id)
        if old and item.timestamp_ns <= old.timestamp_ns:
            raise ValueError('stale or duplicate per-sensor observation')
        if not old and len(self._current) >= self.max_sensors:
            raise OverflowError('working-state capacity exceeded')
        self._current[item.sensor_id] = item

    def snapshot(self, now_ns: int) -> tuple[CurrentObservation, ...]:
        if now_ns < 0:
            raise ValueError('now_ns cannot be negative')
        return tuple(item for _, item in sorted(self._current.items())
                     if item.timestamp_ns <= now_ns
                     and now_ns-item.timestamp_ns <= self.expiry_ns)

    def expire(self, now_ns: int) -> int:
        old_size = len(self._current)
        self._current = {s: item for s, item in self._current.items()
                         if item.timestamp_ns <= now_ns
                         and now_ns-item.timestamp_ns <= self.expiry_ns}
        return old_size-len(self._current)
