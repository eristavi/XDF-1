"""Acceptance and failure-mode checks for the AMEE reference design."""
import json
from pathlib import Path
import pytest

from xdf1.perception_memory import (
    NS, Experience, ImportanceSignal, JsonlEventArchive, ListArchive,
    MemoryPolicy, PerceptionMemory, RawSpan,
)


def span(i, *, sensor=0, bytes_=100):
    return RawSpan(f'dma:{i}:{sensor}', sensor, i*NS, (i+1)*NS, bytes_)


def signal(i, *, protected=False, score=1.0, sensors=(0,)):
    return ImportanceSignal(f'event:{i}', i*NS, sensors, score, score,
                            score, score, score, protected,
                            explanation='test event', model_version='fixture-v1')


def setup(**kwargs):
    archive = ListArchive()
    config = dict(ring_seconds=10, ring_bytes=10000, pre_seconds=1, post_seconds=1)
    config.update(kwargs)
    engine = PerceptionMemory(MemoryPolicy(**config), archive)
    return engine, archive


def test_raw_ring_bounded_by_time_and_bytes():
    engine, _ = setup()
    for i in range(20):
        engine.ingest(span(i, bytes_=100))
    assert engine.stats.ring_spans == 10
    assert engine.stats.ring_resident_bytes == 1000
    assert engine.stats.ingested_raw_bytes == 2000


def test_duplicate_reference_and_time_regression_rejected():
    engine, _ = setup()
    engine.ingest(span(1))
    with pytest.raises(ValueError, match='reused'):
        engine.ingest(span(1))
    with pytest.raises(ValueError, match='backwards'):
        engine.ingest(span(0))


def test_oversized_fragment_cannot_silently_overwrite_ring():
    engine, _ = setup()
    with pytest.raises(ValueError, match='exceeds'):
        engine.ingest(span(0, bytes_=20000))


def test_unimportant_event_skips_memory_not_perception():
    engine, archive = setup()
    engine.ingest(span(0))
    assert not engine.observe(signal(0, score=0.1))
    assert engine.advance(2*NS) == []
    assert not archive.records
    assert engine.stats.rejected_as_unimportant == 1


def test_budget_stores_summary_even_when_raw_capture_exceeds_credit():
    engine, archive = setup(target_fraction=0.01)
    for i in range(3): engine.ingest(span(i, bytes_=100))
    assert engine.observe(signal(1))
    r = engine.advance(3*NS)
    assert len(r) == 1
    assert r[0].capture_mode == 'summary'
    assert r[0].raw_refs == ()
    assert engine.stats.summary_only_experiences == 1
    assert len(archive.records) == 1


def test_protected_event_bypasses_retention_budget():
    engine, archive = setup(target_fraction=0.01)
    for i in range(4): engine.ingest(span(i, bytes_=100))
    assert engine.observe(signal(2, protected=True, score=0.01))
    selected = engine.advance(4*NS)
    assert selected[0].capture_mode == 'references'
    assert selected[0].raw_refs == ('dma:1:0','dma:2:0')
    assert selected[0].selected_raw_bytes == 200
    assert archive.records[0].protected
    assert engine.stats.protected_experiences == 1


def test_pre_and_post_context_of_correlated_sensors_only():
    engine, _ = setup(target_fraction=0.10)
    for i in range(4):
        engine.ingest(span(i, sensor=0, bytes_=1))
        engine.ingest(span(i, sensor=1, bytes_=1))
    assert engine.observe(signal(2, protected=True, sensors=(0,)))
    events = engine.advance(4*NS)
    assert len(events[0].raw_refs) == 2
    assert all(ref.endswith(':0') for ref in events[0].raw_refs)


def test_overlapping_events_deduplicate_raw_fragment_accounting():
    engine, _ = setup(target_fraction=0.01)
    for i in range(5): engine.ingest(span(i, bytes_=50))
    assert engine.observe(signal(2, protected=True))
    assert engine.observe(signal(3, protected=True))
    out = engine.advance(5*NS)
    assert len(out) == 2
    assert out[0].selected_raw_bytes == 100
    assert out[1].selected_raw_bytes == 50
    assert engine.stats.selected_raw_bytes == 150


def test_pending_window_and_idempotency_check():
    engine, _ = setup(post_seconds=2)
    engine.ingest(span(1))
    assert engine.observe(signal(1, protected=True))
    with pytest.raises(ValueError, match='duplicate'):
        engine.observe(signal(1, protected=True))
    assert engine.advance(2*NS) == []
    assert engine.advance(3*NS)[0].event_id == 'event:1'


def test_policy_validation_and_invalid_signals():
    for target in [0, -0.1, 0.9]:
        with pytest.raises(ValueError): MemoryPolicy(target_fraction=target)
    with pytest.raises(ValueError): MemoryPolicy(ring_seconds=2,pre_seconds=2,post_seconds=2)
    with pytest.raises(ValueError): signal(0, score=float('nan'))
    with pytest.raises(ValueError): RawSpan('x',0,3,3,5)
    with pytest.raises(ValueError): ImportanceSignal('x',0,(0,0),1,1,1,1,1)


def test_pending_queue_resource_failure_is_visible():
    engine, _ = setup(max_pending_events=1)
    engine.ingest(span(2))
    assert engine.observe(signal(1, protected=True))
    with pytest.raises(OverflowError,match='escalation'):
        engine.observe(signal(2, protected=True))


def test_jsonl_archive_stores_metadata_only(tmp_path):
    path = tmp_path/'events.jsonl'
    archive = JsonlEventArchive(path)
    engine = PerceptionMemory(MemoryPolicy(ring_seconds=10,ring_bytes=1000,
                        pre_seconds=1,post_seconds=1), archive)
    for i in range(3): engine.ingest(span(i))
    assert engine.observe(signal(1,protected=True))
    engine.advance(3*NS)
    data = json.loads(path.read_text().strip())
    assert data['event_id'] == 'event:1'
    assert data['model_version'] == 'fixture-v1'
    assert data['capture_mode'] == 'references'
    assert data['raw_refs'] == ['dma:0:0','dma:1:0']
    assert list(tmp_path.iterdir()) == [path]  # No fake raw payload files.


def test_importance_weights_normalized_and_protected_override():
    low = signal(0, score=0)
    high = signal(0, score=1)
    assert PerceptionMemory.importance(low) == 0
    assert PerceptionMemory.importance(high) == 1


def test_window_has_no_future_data_when_producer_stops():
    engine, _ = setup()
    engine.ingest(span(0))
    assert engine.observe(signal(0, protected=True))
    record = engine.advance(2*NS)[0]
    assert record.raw_refs == ('dma:0:0',)


def test_archive_failure_keeps_pending_and_budget_unchanged():
    class FailingArchive:
        def __init__(self): self.fail = True; self.records = []
        def append(self, event):
            if self.fail: raise OSError('simulated disk unavailable')
            self.records.append(event)
    sink = FailingArchive()
    model = PerceptionMemory(MemoryPolicy(ring_seconds=10, ring_bytes=1000,
                            pre_seconds=1, post_seconds=1), sink)
    for i in range(3): model.ingest(span(i))
    model.observe(signal(1, protected=True))
    with pytest.raises(OSError, match='disk'):
        model.advance(3*NS)
    assert model.stats.pending_experiences == 1
    assert model.stats.selected_raw_bytes == 0
    sink.fail = False
    saved = model.advance(3*NS)
    assert len(saved) == 1
    assert model.stats.selected_raw_bytes == 200


def test_capture_flags_missing_context_if_retention_window_expired():
    model, _ = setup()
    for i in range(15): model.ingest(span(i))
    assert model.observe(signal(5, protected=True))  # late trigger, pre-data expired
    result = model.advance(15*NS)[0]
    assert result.context_may_be_incomplete


def test_full_capture_marks_context_complete():
    model, _ = setup()
    for i in range(5): model.ingest(span(i))
    assert model.observe(signal(2, protected=True))
    result = model.advance(5*NS)[0]
    assert result.context_may_be_incomplete is False
