"""Host interface: validate program, emit config/stimulus, run reference."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
from .architecture import Graph
from .reference import ReferenceFabric


def inputs_from_args(values: list[str]) -> dict[str, int]:
    out = {}
    for piece in values:
        name, equal, val = piece.partition("=")
        if not equal:
            raise ValueError(f"expected NAME=INTEGER: {piece}")
        out[name] = int(val, 0)
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description="XDF-1 M1 reference host")
    parser.add_argument("graph", type=Path)
    parser.add_argument("--input", action="append", default=[], metavar="NAME=VALUE")
    parser.add_argument("--context", type=int, default=1)
    parser.add_argument("--epoch", type=int, default=7)
    parser.add_argument("--emit", type=Path, help="write program/config/tokens JSON")
    args = parser.parse_args()
    graph = Graph.read(args.graph)
    values = inputs_from_args(args.input)
    tokens = graph.input_tokens(values, context=args.context, epoch=args.epoch)
    run = ReferenceFabric(graph)
    run.begin(args.context, args.epoch)
    for token in tokens:
        run.inject(token)
    results = run.drain()
    doc = {"architecture": "XDF-1/v0.1", "graph": graph.name,
           "configuration": graph.configuration(),
           "injections": [f"0x{tok.encode():016x}" for tok in tokens],
           "results": [{"value": r.value, "context": r.context,
                        "epoch": r.epoch, "node": r.node} for r in results]}
    if args.emit:
        args.emit.parent.mkdir(parents=True, exist_ok=True)
        args.emit.write_text(json.dumps(doc, indent=2) + "\n")
    print(json.dumps(doc, indent=2))


if __name__ == "__main__":
    main()
