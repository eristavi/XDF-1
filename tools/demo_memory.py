"""Simulate an XDF-1 500 MB/s metadata-only retention workload.

NO actual 500 MB/s raw ingestion occurs. External raw buffers, DMA, neural
inference and raw payload persistence are not exercised by this script.
"""
from __future__ import annotations
import argparse
from pathlib import Path
from xdf1.perception_memory import (NS, ImportanceSignal, JsonlEventArchive,
                                     ListArchive, MemoryPolicy, PerceptionMemory, RawSpan)

SENSOR_BYTES_PER_SECOND = [(0,250_000_000),(1,100_000_000),(2,100_000_000),(3,50_000_000)]


def simulate(seconds: int = 350, target: float = 0.05, archive_path: Path | None = None):
    if seconds < 10:
        raise ValueError('simulation needs at least 10 seconds')
    archive = JsonlEventArchive(archive_path) if archive_path else ListArchive()
    m = PerceptionMemory(MemoryPolicy(target_fraction=target), archive)
    for second in range(seconds):
        for sensor, size in SENSOR_BYTES_PER_SECOND:
            m.ingest(RawSpan(f'dma:{sensor}:{second}', sensor,
                             second*NS, (second+1)*NS, size))
        if second in (100, 200, 250, 300):
            # A protected event at 250 bypasses any optional retention cap.
            m.observe(ImportanceSignal(
                event_id=f'synthetic-{second}', timestamp_ns=second*NS,
                sensor_ids=(0,1,2,3), severity=.99, novelty=.90,
                relevance=.95, uncertainty=.12, corroboration=.85,
                protected=second == 250,
                explanation='Synthetic correlated anomaly. No neural inference.',
                model_version='synthetic-rules-v0'))
        m.advance((second+1)*NS)
    m.advance((seconds+2)*NS)
    st=m.stats
    print('MODE: DESCRIPTOR-ONLY SIMULATION (NOT A HARDWARE THROUGHPUT TEST)')
    print(f'Input rate assumed: 500 MB/s; modeled seconds: {seconds}')
    print(f'Logical raw bytes received: {st.ingested_raw_bytes:,}')
    print(f'Raw bytes selected as external references: {st.selected_raw_bytes:,}')
    print(f'Selected reference ratio: {st.reference_selection_fraction*100:.2f}%')
    print(f'Experience metadata records: {st.archived_experiences}')
    print(f'Summary-only records: {st.summary_only_experiences}')
    print('Physical raw payload bytes copied to disk: 0 (not implemented)')
    return st


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seconds', type=int, default=350)
    parser.add_argument('--target', type=float, default=.05)
    parser.add_argument('--archive', type=Path, help='Optional JSONL metadata destination')
    args=parser.parse_args()
    simulate(args.seconds,args.target,args.archive)
