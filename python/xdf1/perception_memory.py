"""Deterministic reference for XDF-1's future experience-memory selector.

This model handles *descriptors*, not a 500 MB/s payload transfer. RawSpan
references data that must remain in an external ring buffer. An archival
record selects references for future persistence; the JSONL writer stores
metadata only. Do not mistake selected bytes for physically written bytes.

The architecture keeps fast reflex decisions independent of memory I/O.
Hardware ingestion, neural inference, DMA, crash-safe raw payload storage,
and physical latency are not implemented here.
"""
from __future__ import annotations

from collections import deque
from dataclasses import dataclass, asdict
import json
import math
import os
from pathlib import Path
from typing import Protocol

NS = 1_000_000_000


@dataclass(frozen=True)
class RawSpan:
    """Reference to an externally owned, immutable raw-data fragment."""
    ref: str
    sensor_id: int
    start_ns: int
    end_ns: int
    size_bytes: int

    def __post_init__(self) -> None:
        if not self.ref or self.sensor_id < 0 or self.start_ns < 0:
            raise ValueError('raw span requires a reference, sensor ID and nonnegative time')
        if self.end_ns <= self.start_ns or self.size_bytes <= 0:
            raise ValueError('raw span must have positive duration and byte size')


@dataclass(frozen=True)
class ImportanceSignal:
    """Input from a rule, temporal feature detector, or future neural model."""
    event_id: str
    timestamp_ns: int
    sensor_ids: tuple[int, ...]
    severity: float
    novelty: float
    relevance: float
    uncertainty: float
    corroboration: float
    protected: bool = False
    explanation: str = ''
    model_version: str = 'rules-v0'

    def __post_init__(self) -> None:
        if not self.event_id or self.timestamp_ns < 0 or not self.sensor_ids:
            raise ValueError('event needs ID, timestamp and at least one sensor')
        if any(type(sid) is not int or sid < 0 for sid in self.sensor_ids):
            raise ValueError('invalid sensor ID')
        if len(set(self.sensor_ids)) != len(self.sensor_ids):
            raise ValueError('duplicate sensor IDs in event')
        for x in (self.severity, self.novelty, self.relevance,
                  self.uncertainty, self.corroboration):
            if not math.isfinite(x) or not 0.0 <= x <= 1.0:
                raise ValueError('importance features must be finite in [0,1]')
        if not self.model_version:
            raise ValueError('model or rule version is mandatory for traceability')


@dataclass(frozen=True)
class MemoryPolicy:
    """A budget is a preference; protected events bypass the elective budget."""
    target_fraction: float = 0.05
    ring_seconds: int = 15
    ring_bytes: int = 7_500_000_000
    pre_seconds: int = 2
    post_seconds: int = 2
    importance_threshold: float = 0.58
    credit_horizon_seconds: int = 120
    max_pending_events: int = 10000

    def __post_init__(self) -> None:
        if not 0.01 <= self.target_fraction <= 0.10:
            raise ValueError('retention fraction must be 1% to 10%')
        if self.ring_seconds <= 0 or self.ring_bytes <= 0:
            raise ValueError('ring memory must be positive')
        if self.pre_seconds < 0 or self.post_seconds < 0:
            raise ValueError('capture windows cannot be negative')
        if self.ring_seconds < self.pre_seconds + self.post_seconds:
            raise ValueError('ring must cover full pre/post event capture period')
        if not 0 <= self.importance_threshold <= 1:
            raise ValueError('invalid importance threshold')
        if self.credit_horizon_seconds <= 0 or self.max_pending_events <= 0:
            raise ValueError('invalid resource bound')


@dataclass(frozen=True)
class Experience:
    event_id: str
    timestamp_ns: int
    sensor_ids: tuple[int, ...]
    importance: float
    protected: bool
    capture_mode: str  # 'references' or 'summary' -- never claims raw bytes written
    raw_refs: tuple[str, ...]
    selected_raw_bytes: int
    context_may_be_incomplete: bool
    explanation: str
    model_version: str


class Archive(Protocol):
    def append(self, record: Experience) -> None: ...


class ListArchive:
    """In-memory test sink, does not persist anything."""
    def __init__(self) -> None:
        self.records: list[Experience] = []

    def append(self, record: Experience) -> None:
        self.records.append(record)


class JsonlEventArchive:
    """Append-only metadata writer. RawSpan payloads are NOT written here.

    A future payload archival service must atomically materialize referenced
    buffers and acknowledge durability before their descriptors are released.
    """
    def __init__(self, path: str | Path) -> None:
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)

    def append(self, record: Experience) -> None:
        payload = (json.dumps(asdict(record), sort_keys=True, separators=(',', ':'))
                   + '\n').encode('utf-8')
        with self.path.open('ab') as f:
            f.write(payload)
            f.flush()
            os.fsync(f.fileno())


@dataclass(frozen=True)
class MemoryStats:
    ingested_raw_bytes: int
    selected_raw_bytes: int
    archived_experiences: int
    summary_only_experiences: int
    protected_experiences: int
    rejected_as_unimportant: int
    ring_resident_bytes: int
    ring_spans: int
    pending_experiences: int

    @property
    def reference_selection_fraction(self) -> float:
        return (self.selected_raw_bytes / self.ingested_raw_bytes
                if self.ingested_raw_bytes else 0.0)


class PerceptionMemory:
    """Bounded raw descriptors + asynchronous event capture policy reference.

    No live filesystem I/O happens in the fast reflex path: caller must run
    `advance` in a lower-priority worker. Future hardware uses independent
    DMA, descriptor rings, and a persistence acknowledgement protocol.
    """
    def __init__(self, policy: MemoryPolicy | None = None,
                 archive: Archive | None = None):
        self.policy = policy or MemoryPolicy()
        self.archive: Archive = archive if archive is not None else ListArchive()
        self._ring: deque[RawSpan] = deque()
        self._ring_bytes = 0
        self._now_ns: int | None = None
        self._known_refs: set[str] = set()
        self._event_ids: set[str] = set()
        self._pending: list[ImportanceSignal] = []
        self._saved_refs: set[str] = set()
        self._credit_bytes = 0.0
        self._ingested_bytes = 0
        self._selected_bytes = 0
        self._archived = 0
        self._summary_only = 0
        self._protected = 0
        self._rejected = 0

    @staticmethod
    def importance(signal: ImportanceSignal) -> float:
        # Configurable *reference* scoring, not a trained neural network.
        return (0.35 * signal.severity + 0.25 * signal.novelty +
                0.20 * signal.relevance + 0.10 * signal.uncertainty +
                0.10 * signal.corroboration)

    def ingest(self, span: RawSpan) -> None:
        if span.ref in self._known_refs:
            raise ValueError('reused raw reference could corrupt memory provenance')
        if self._now_ns is not None and span.end_ns < self._now_ns:
            raise ValueError('raw span arrival time moved backwards')
        if span.size_bytes > self.policy.ring_bytes:
            raise ValueError('one raw span exceeds ring capacity')
        self._now_ns = span.end_ns
        self._ring.append(span)
        self._ring_bytes += span.size_bytes
        self._known_refs.add(span.ref)
        self._ingested_bytes += span.size_bytes
        self._credit_bytes += span.size_bytes * self.policy.target_fraction
        # Keep a bounded maximum retention credit, even after long idle periods.
        # Per-second rate is estimated from configured ring capacity and time.
        max_credit = (self.policy.ring_bytes / self.policy.ring_seconds *
                      self.policy.credit_horizon_seconds *
                      self.policy.target_fraction)
        self._credit_bytes = min(self._credit_bytes, max_credit)
        self._evict()

    def _evict(self) -> None:
        assert self._now_ns is not None
        cutoff = self._now_ns - self.policy.ring_seconds * NS
        while self._ring and (self._ring[0].end_ns <= cutoff or
                              self._ring_bytes > self.policy.ring_bytes):
            old = self._ring.popleft()
            self._ring_bytes -= old.size_bytes
            # History of identifiers is deliberately retained for exact
            # duplicate rejection. Bound it in a production metadata store.

    def observe(self, event: ImportanceSignal) -> bool:
        if event.event_id in self._event_ids:
            raise ValueError('duplicate memory event ID')
        if self._now_ns is None or event.timestamp_ns > self._now_ns:
            raise ValueError('event must refer to already observed sensory time')
        if not event.protected and self.importance(event) < self.policy.importance_threshold:
            self._event_ids.add(event.event_id)
            self._rejected += 1
            return False
        if len(self._pending) >= self.policy.max_pending_events:
            # Critical signals must not be silently discarded. Fail explicitly;
            # a real implementation must have a separate protected journal.
            raise OverflowError('memory capture queue full; escalation required')
        self._event_ids.add(event.event_id)
        self._pending.append(event)
        return True

    def advance(self, now_ns: int) -> list[Experience]:
        """Finalize completed windows. Must run in a separate memory worker."""
        if now_ns < 0 or (self._now_ns is not None and now_ns < self._now_ns):
            raise ValueError('advance time cannot go backwards')
        # The caller may advance time without receiving new chunks. This also
        # models idle drains and leaves no fictional raw data in the ring.
        self._now_ns = now_ns
        self._evict()
        remaining: list[ImportanceSignal] = []
        saved: list[Experience] = []
        for idx, event in enumerate(self._pending):
            if now_ns < event.timestamp_ns + self.policy.post_seconds * NS:
                remaining.append(event)
                continue
            start = max(0, event.timestamp_ns - self.policy.pre_seconds * NS)
            end = event.timestamp_ns + self.policy.post_seconds * NS
            related = [s for s in self._ring if s.start_ns < end and s.end_ns > start
                       and s.sensor_id in event.sensor_ids]
            # The reference cannot know if unreported sensor data once existed.
            # Flag incomplete edge coverage; production pinning/acknowledgement
            # must prevent losing pre-event evidence under memory pressure.
            incomplete = any(
                not any(s.sensor_id == sid and s.start_ns <= start for s in related)
                or not any(s.sensor_id == sid and s.end_ns >= end for s in related)
                for sid in event.sensor_ids
            )
            new_refs = [s for s in related if s.ref not in self._saved_refs]
            new_raw = sum(s.size_bytes for s in new_refs)
            keep_refs = event.protected or new_raw <= self._credit_bytes
            refs = tuple(s.ref for s in related) if keep_refs else ()
            result = Experience(
                event_id=event.event_id, timestamp_ns=event.timestamp_ns,
                sensor_ids=event.sensor_ids, importance=self.importance(event),
                protected=event.protected,
                capture_mode='references' if keep_refs else 'summary',
                raw_refs=refs, selected_raw_bytes=new_raw if keep_refs else 0,
                context_may_be_incomplete=incomplete,
                explanation=event.explanation, model_version=event.model_version,
            )
            # Never mutate credit or deduplication before the archive
            # acknowledges the metadata append. On error, the event remains
            # pending for retry; a production writer must also deduplicate
            # partial writes transactionally and confirm actual raw payloads.
            try:
                self.archive.append(result)
            except Exception:
                self._pending = remaining + self._pending[idx:]
                raise
            if keep_refs:
                self._saved_refs.update(refs)
                self._selected_bytes += new_raw
                self._credit_bytes -= new_raw
            else:
                self._summary_only += 1
            self._protected += int(event.protected)
            self._archived += 1
            saved.append(result)
        self._pending = remaining
        return saved

    @property
    def stats(self) -> MemoryStats:
        return MemoryStats(
            ingested_raw_bytes=self._ingested_bytes,
            selected_raw_bytes=self._selected_bytes,
            archived_experiences=self._archived,
            summary_only_experiences=self._summary_only,
            protected_experiences=self._protected,
            rejected_as_unimportant=self._rejected,
            ring_resident_bytes=self._ring_bytes,
            ring_spans=len(self._ring), pending_experiences=len(self._pending),
        )
