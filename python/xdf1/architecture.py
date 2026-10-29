"""XDF-1 v0.1 architectural contract and graph loader (pure Python)."""
from __future__ import annotations
from collections import defaultdict, deque
from dataclasses import dataclass
from pathlib import Path
import yaml

WORD_MASK = (1 << 32) - 1
NUM_TILES = 4
NODES_PER_TILE = 8
NUM_NODES = 32
MAX_LIVE_TAGS = 2
OPERATIONS = {"ADD": 0, "SUB": 1, "XOR": 2, "AND": 3, "PASS": 4, "OUTPUT": 5}
OPERATIONS_REVERSE = {v: k for k, v in OPERATIONS.items()}
BINARY = frozenset({"ADD", "SUB", "XOR", "AND"})
UNARY = frozenset({"PASS", "OUTPUT"})


class GraphError(ValueError):
    """Graph has no defined v0.1 execution semantics."""


class ProtocolError(ValueError):
    """Token or runtime event violates the v0.1 protocol."""


@dataclass(frozen=True)
class Token:
    value: int
    epoch: int
    node: int
    port: int
    context: int
    flags: int = 0

    def __post_init__(self) -> None:
        for field, value, limit in (("value", self.value, 1 << 32),
                                    ("epoch", self.epoch, 1 << 8),
                                    ("node", self.node, 1 << 8),
                                    ("port", self.port, 1 << 4),
                                    ("context", self.context, 1 << 4),
                                    ("flags", self.flags, 1 << 8)):
            if not isinstance(value, int) or not 0 <= value < limit:
                raise ProtocolError(f"invalid {field}: {value}")

    def encode(self) -> int:
        return (self.value | self.epoch << 32 | self.node << 40 |
                self.port << 48 | self.context << 52 | self.flags << 56)

    @classmethod
    def decode(cls, packed: int) -> "Token":
        if packed < 0 or packed >= 1 << 64:
            raise ProtocolError("packed token must be 64 bits")
        return cls(value=packed & WORD_MASK, epoch=(packed >> 32) & 255,
                   node=(packed >> 40) & 255, port=(packed >> 48) & 15,
                   context=(packed >> 52) & 15, flags=(packed >> 56) & 255)


@dataclass(frozen=True)
class Node:
    id: int
    op: str
    dest_node: int = 0
    dest_port: int = 0

    @property
    def arity(self) -> int:
        return 2 if self.op in BINARY else 1


@dataclass
class Graph:
    name: str
    nodes: dict[int, Node]
    inputs: dict[str, tuple[int, int]]
    output_node: int

    @classmethod
    def read(cls, filename: str | Path) -> "Graph":
        with open(filename, "r", encoding="utf-8") as stream:
            raw = yaml.safe_load(stream)
        return cls.from_dict(raw)

    @classmethod
    def from_dict(cls, raw: dict) -> "Graph":
        if not isinstance(raw, dict):
            raise GraphError("graph must be a mapping")
        declarations = raw.get("nodes", [])
        if not isinstance(declarations, list) or not declarations:
            raise GraphError("nodes must be a nonempty list")
        nodes = {}
        for entry in declarations:
            try:
                nid, op = entry["id"], entry["op"]
            except (KeyError, TypeError) as exc:
                raise GraphError("each node needs an id and op") from exc
            if not isinstance(nid, int) or not 0 <= nid < NUM_NODES:
                raise GraphError(f"node id out of range: {nid}")
            if nid in nodes:
                raise GraphError(f"duplicate node: {nid}")
            if op not in OPERATIONS:
                raise GraphError(f"unsupported operation: {op}")
            route = entry.get("dest")
            if op == "OUTPUT":
                if route is not None:
                    raise GraphError("OUTPUT node cannot have an output edge")
                nodes[nid] = Node(nid, op)
            else:
                if not isinstance(route, dict) or set(route) != {"node", "port"}:
                    raise GraphError(f"node {nid} must define destination node/port")
                dest, port = route["node"], route["port"]
                if not isinstance(dest, int) or not 0 <= dest < NUM_NODES:
                    raise GraphError(f"bad destination node on {nid}")
                if not isinstance(port, int) or port not in (0, 1):
                    raise GraphError(f"bad destination port on {nid}")
                nodes[nid] = Node(nid, op, dest, port)
        sinks = [nid for nid, n in nodes.items() if n.op == "OUTPUT"]
        if len(sinks) != 1:
            raise GraphError("exactly one OUTPUT node required")
        output_node = sinks[0]
        raw_inputs = raw.get("inputs", {})
        if not isinstance(raw_inputs, dict) or not raw_inputs:
            raise GraphError("graph must declare its external inputs")
        inputs = {}
        for name, val in raw_inputs.items():
            if not isinstance(name, str) or not name or not isinstance(val, dict):
                raise GraphError("invalid input declaration")
            if set(val) != {"node", "port"}:
                raise GraphError(f"invalid input port declaration {name}")
            nid, port = val["node"], val["port"]
            if not isinstance(nid, int) or not isinstance(port, int):
                raise GraphError(f"invalid input mapping {name}")
            inputs[name] = (nid, port)
        graph = cls(str(raw.get("name", "unnamed")), nodes, inputs, output_node)
        graph.validate()
        return graph

    def validate(self) -> None:
        # Every node is executed exactly once per tag. Hence each operand port
        # has exactly one source (graph edge or external input).
        incoming: dict[tuple[int, int], list[str]] = defaultdict(list)
        adj: dict[int, list[int]] = defaultdict(list)
        indegree = {nid: 0 for nid in self.nodes}
        for nid, node in self.nodes.items():
            if node.op != "OUTPUT":
                if node.dest_node not in self.nodes:
                    raise GraphError(f"node {nid} routes to unconfigured {node.dest_node}")
                target = self.nodes[node.dest_node]
                if node.dest_port >= target.arity:
                    raise GraphError(f"node {nid} uses illegal destination port")
                incoming[(node.dest_node, node.dest_port)].append(f"node {nid}")
                adj[nid].append(node.dest_node)
                indegree[node.dest_node] += 1
        for name, (nid, port) in self.inputs.items():
            if nid not in self.nodes or port < 0 or port >= self.nodes[nid].arity:
                raise GraphError(f"input {name} has invalid destination")
            incoming[(nid, port)].append(f"input {name}")
        # Acyclic and all nodes used in the computation leading to the sink.
        queue = deque([nid for nid, count in indegree.items() if count == 0])
        seen = 0
        while queue:
            current = queue.popleft()
            seen += 1
            for child in adj[current]:
                indegree[child] -= 1
                if indegree[child] == 0:
                    queue.append(child)
        if seen != len(self.nodes):
            raise GraphError("cyclic graph is unsupported in v0.1")
        for nid, node in self.nodes.items():
            for port in range(node.arity):
                src = incoming[(nid, port)]
                if len(src) != 1:
                    raise GraphError(f"node {nid} input {port} must have one source; got {src}")
        # Follow successor chains. A legal graph has one terminal output.
        for nid, node in self.nodes.items():
            cursor = nid
            for _ in range(len(self.nodes) + 1):
                if cursor == self.output_node:
                    break
                cursor = self.nodes[cursor].dest_node
            else:
                raise GraphError(f"node {nid} does not lead to OUTPUT")

    def configuration(self) -> list[dict]:
        return [{"node": n.id, "tile": n.id // NODES_PER_TILE,
                 "opcode": OPERATIONS[n.op], "op": n.op,
                 "dest_node": n.dest_node, "dest_port": n.dest_port}
                for _, n in sorted(self.nodes.items())]

    def input_tokens(self, values: dict[str, int], *, context: int, epoch: int,
                     order: list[str] | None = None) -> list[Token]:
        if set(values) != set(self.inputs):
            raise ProtocolError("input names mismatch: expected " + str(sorted(self.inputs)))
        order = list(self.inputs) if order is None else order
        if len(order) != len(self.inputs) or set(order) != set(self.inputs):
            raise ProtocolError("order must name every input exactly once")
        result = []
        for name in order:
            value = values[name]
            if not isinstance(value, int):
                raise ProtocolError("input values must be integers")
            nid, port = self.inputs[name]
            result.append(Token(value=value & WORD_MASK, epoch=epoch, node=nid,
                                port=port, context=context))
        return result


def alu(op: str, a: int, b: int = 0) -> int:
    if op == "ADD": return (a + b) & WORD_MASK
    if op == "SUB": return (a - b) & WORD_MASK
    if op == "XOR": return a ^ b
    if op == "AND": return a & b
    if op in ("PASS", "OUTPUT"): return a
    raise ProtocolError(f"unsupported opcode: {op}")
