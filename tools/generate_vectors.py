"""Reproducible RTL test vectors, with expected output from Python reference."""
from __future__ import annotations
from pathlib import Path
import random
from xdf1.architecture import Graph
from xdf1.reference import ReferenceFabric


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    graph = Graph.read(root / 'programs' / 'first_graph.yaml')
    randomizer = random.Random(0x5DF1001)
    vectors = []
    for i in range(1000):
        inputs = dict(zip('ABCD', (randomizer.getrandbits(32) for _ in range(4))))
        results = ReferenceFabric(graph).run([(i % 16, i % 256, inputs)])
        expected = results[0].value
        vectors.append(' '.join([*(f'{inputs[k]:08x}' for k in 'ABCD'), f'{expected:08x}']))
    dest = root / 'tb' / 'reference_vectors.txt'
    dest.write_text('\n'.join(vectors)+'\n', encoding='ascii')
    print(f'Generated {len(vectors)} deterministic RTL test vectors at {dest}')


if __name__ == '__main__':
    main()
