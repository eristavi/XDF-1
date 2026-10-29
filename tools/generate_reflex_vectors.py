"""Generated cycle oracle for the standalone RTL reflex filter.

Builds a stable valid/data producer (including long backpressure), unrelated
reflex and context consumer stalls, alarms and signed overflow corner cases.
"""
from __future__ import annotations

from pathlib import Path
from random import Random
from xdf1.reflex import (
    ABOVE, ALWAYS, BOTH, CHANGE, CONTEXT, DROP, GROUP, REFLEX,
    ReflexClassifier, Rule, encode_observation,
)

OUTPUT = Path('build/reflex_vectors.txt')
SEED = 0x58444622
ACTIVE_CYCLES = 3200


def configured_model() -> ReflexClassifier:
    m = ReflexClassifier(rules=8)
    m.configure(255, default_action=DROP)
    m.configure(0, Rule(True, 1, ABOVE, 100, BOTH))
    m.configure(1, Rule(True, 255, CHANGE, 40, CONTEXT))
    m.configure(2, Rule(True, 2, ALWAYS, 0, DROP))
    m.configure(3, Rule(True, 3, GROUP, 0, BOTH))
    m.configure(4, Rule(True, 1, ABOVE, 0, CONTEXT))
    return m


def generate() -> tuple[str, dict[str, int]]:
    m = configured_model()
    rng = Random(SEED)
    rows: list[str] = []
    pending: int | None = None
    sequence = 0
    held_reflex_cycles = 0
    held_context_cycles = 0

    def cycle(k: int, offer_new: bool) -> None:
        nonlocal pending, sequence, held_reflex_cycles, held_context_cycles
        if offer_new and pending is None and rng.random() < 0.91:
            sensor = rng.choice([1, 1, 2, 3, 5, 7, 12, 63])
            raw = rng.choice([-(1 << 31), (1 << 31)-1, -150, -40, 0, 39, 90, 105, 200])
            ema = rng.choice([-(1 << 31), (1 << 31)-1, -50, 0, 25, 100])
            sequence += 1
            pending = encode_observation(sensor, raw, ema,
                sensor_alarm=(rng.random() < 0.06),
                group_alarm=(rng.random() < 0.045),
                timestamp=sequence*100, sequence=sequence % 65536,
                group_sum=rng.randint(-200, 200))
        reflex_ready = (k % 101 not in range(27, 56)) and rng.random() > 0.23
        context_ready = (k % 151 not in range(30, 96)) and rng.random() > 0.62
        result = m.tick(pending, reflex_ready=reflex_ready, context_ready=context_ready)
        if result.reflex is not None and not reflex_ready:
            held_reflex_cycles += 1
        if result.context is not None and not context_ready:
            held_context_cycles += 1
        rows.append(f'{int(pending is not None):x} {pending or 0:041x} '
                    f'{int(reflex_ready):x} {int(context_ready):x} {int(result.ready):x} '
                    f'{int(result.reflex is not None):x} {result.reflex or 0:044x} '
                    f'{int(result.context is not None):x} {result.context or 0:044x}')
        if result.accepted:
            pending = None

    for k in range(ACTIVE_CYCLES):
        cycle(k, True)
    k = ACTIVE_CYCLES
    while pending is not None or m.reflex is not None or m.context is not None:
        if k >= ACTIVE_CYCLES + 2000:
            raise RuntimeError('pipeline failed to drain')
        cycle(k, False)
        k += 1
    counters = {
        'cycles': len(rows), 'accepted': m.accepted_count,
        'filtered': m.filtered_count, 'reflex': m.reflex_count,
        'context': m.context_count, 'context_drops': m.context_drop_count,
        'protected_drops': m.protected_context_drop_count,
        'held_reflex_cycles': held_reflex_cycles,
        'held_context_cycles': held_context_cycles,
    }
    assert counters['accepted'] > 300 and counters['reflex'] > 60
    assert counters['filtered'] > 100 and counters['context_drops'] > 40
    assert counters['protected_drops'] > 0 and held_reflex_cycles > 30
    assert counters['context_drops'] >= counters['protected_drops']
    header = ' '.join(str(counters[k]) for k in (
        'cycles', 'accepted', 'filtered', 'reflex', 'context', 'context_drops', 'protected_drops'))
    return header + '\n' + '\n'.join(rows) + '\n', counters


if __name__ == '__main__':
    content, stats = generate()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(content, encoding='ascii')
    print(f'Reflex reference: {stats}; vectors: {OUTPUT}')
