"""Deterministic cycle-by-cycle oracle for the independent sensory RTL block.

All expected handshakes and output tokens derive from the Python reference model.
The resulting file is generated during CI and never used as a source artifact.
"""
from __future__ import annotations
import random
from collections import defaultdict, deque
from pathlib import Path
from xdf1.sensory import SensorDecision, SensorEvent, SensoryFabric

OUTPUT = Path('build/sensory_vectors.txt')
RNG_SEED = 0x58444632
OFFER_CYCLES = 2500


def pack_decision(dec: SensorDecision) -> int:
    return ((int(dec.group_alarm) << 163) | (int(dec.alarm) << 162) |
            ((dec.group_sum & ((1 << 34) - 1)) << 128) |
            ((dec.estimate & 0xffffffff) << 96) | dec.event.encode())


def generate() -> tuple[str, dict[str, int]]:
    rng = random.Random(RNG_SEED)
    model = SensoryFabric(sensors=64, lanes=4, depth=2, urgent_budget=8)
    model.configure_sensor(0, 50)
    model.configure_sensor(1, 35)
    model.configure_sensor(5, -20)
    model.configure_group(0, 100)
    model.configure_group(1, 60)
    next_sequence = [0] * 64
    pending: list[SensorEvent | None] = [None] * 4
    rows: list[str] = []
    accepted_cycles = defaultdict(deque)
    latencies = []

    def one_cycle(allow_new: bool, cycle: int) -> None:
        if allow_new:
            for lane in range(4):
                if pending[lane] is None and rng.random() < .81:
                    sensor = rng.randrange(64)
                    next_sequence[sensor] = (next_sequence[sensor] + 1) & 0xffff
                    seq = next_sequence[sensor]
                    # Out-of-order/same-sensor events across distinct lanes are
                    # expected: the oracle rejects stale duplicates explicitly.
                    kind = 1 if rng.random() < .024 else 0
                    reserved = 1 if rng.random() < .013 else 0
                    if rng.random() < .012: sensor = rng.randint(64,255)
                    event = SensorEvent(
                        sensor=sensor, sequence=seq, timestamp=seq,
                        value=rng.randint(-160, 160),
                        priority=rng.randrange(4), kind=kind, reserved=reserved
                    )
                    pending[lane] = event
        ready_result = not ((cycle % 113) in range(44, 55) or rng.random() < .18)
        observed_output = model.out
        response = model.tick(pending, result_ready=ready_result)
        if response.delivered is not None:
            code = response.delivered.event.encode()
            if not accepted_cycles[code]:
                raise AssertionError('decision without accepted event')
            latencies.append(cycle - accepted_cycles[code].popleft())
        vin = sum((1 << i) for i in range(4) if pending[i] is not None)
        packed = [(x.encode() if x else 0) for x in pending]
        ready_mask = sum(1 << i for i, b in enumerate(response.ready) if b)
        result_valid = observed_output is not None
        output = pack_decision(observed_output) if result_valid else 0
        rows.append(f'{vin:x} ' + ' '.join(f'{x:024x}' for x in packed) +
                    f' {int(ready_result):x} {ready_mask:x} {int(result_valid):x} {output:041x}')
        for i in range(4):
            if pending[i] is not None and response.ready[i]:
                accepted_cycles[pending[i].encode()].append(cycle)
                pending[i] = None

    for cycle in range(OFFER_CYCLES):
        one_cycle(True, cycle)
    cycle = OFFER_CYCLES
    while any(x is not None for x in pending) or model.pending():
        if cycle > OFFER_CYCLES + 50000:
            raise RuntimeError('sensory pipeline failed to drain within budget')
        one_cycle(False, cycle)
        cycle += 1

    counts = dict(cycles=len(rows), accepted=model.accepted, processed=model.processed,
                  faults=model.faults, alarms=model.alarms)
    assert model.accepted == model.processed + model.faults, counts
    # Fixture has to exercise all important behaviors, not merely produce valid data.
    assert model.accepted > 1000 and model.processed > 700, counts
    assert model.faults > 0 and model.alarms > 0, counts
    assert len(latencies) == model.processed
    ordered = sorted(latencies)
    counts.update(latency_avg_cycles=round(sum(latencies)/len(latencies),2),
                  latency_p99_cycles=ordered[(99*len(ordered)-1)//100],
                  latency_max_cycles=max(latencies))
    return '\n'.join([f'{counts["cycles"]} {counts["accepted"]} {counts["processed"]} {counts["faults"]}',
                      *rows, '']), counts


if __name__ == '__main__':
    contents, counts = generate()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(contents, encoding='ascii')
    print(f'Sensory reference: {counts}; vectors: {OUTPUT}')
