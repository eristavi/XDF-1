"""Architectural token execution model; intentionally independent of RTL timing."""
from collections import deque
from dataclasses import dataclass
from .architecture import Graph, MAX_LIVE_TAGS, ProtocolError, Token, alu


@dataclass(frozen=True)
class Result:
    value: int
    context: int
    epoch: int
    node: int


class ReferenceFabric:
    def __init__(self, graph: Graph):
        self.graph = graph
        self.reset()

    def reset(self) -> None:
        self.active: set[tuple[int, int]] = set()
        self.operands: dict[tuple[int, int, int, int], int] = {}
        self.fired: set[tuple[int, int, int]] = set()
        self.events: deque[Token] = deque()
        self.results: deque[Result] = deque()

    def begin(self, context: int, epoch: int) -> None:
        if not 0 <= context <= 15 or not 0 <= epoch <= 255:
            raise ProtocolError("tag out of range")
        tag = (context, epoch)
        if tag in self.active:
            raise ProtocolError(f"duplicate active tag {tag}")
        if len(self.active) >= MAX_LIVE_TAGS:
            raise ProtocolError("at most 2 active tags")
        self.active.add(tag)

    def inject(self, token: Token) -> None:
        if token.flags != 0:
            raise ProtocolError("nonzero flags unsupported")
        if (token.context, token.epoch) not in self.active:
            raise ProtocolError("tag is not active")
        self.events.append(token)

    def step(self) -> bool:
        if not self.events:
            return False
        tok = self.events.popleft()
        tag = (tok.context, tok.epoch)
        node = self.graph.nodes.get(tok.node)
        if node is None:
            raise ProtocolError(f"unconfigured node {tok.node}")
        if tok.flags or tok.port >= node.arity:
            raise ProtocolError("invalid flags/operand port")
        if tag not in self.active:
            raise ProtocolError("token's execution has already ended")
        operand_key = (*tag, tok.node, tok.port)
        fire_key = (*tag, tok.node)
        if operand_key in self.operands or fire_key in self.fired:
            raise ProtocolError("duplicate operand or already executed node")
        self.operands[operand_key] = tok.value
        ports = [(*tag, tok.node, p) for p in range(node.arity)]
        if all(key in self.operands for key in ports):
            self.fired.add(fire_key)
            value = alu(node.op, *(self.operands.pop(p) for p in ports))
            if node.op == "OUTPUT":
                self.results.append(Result(value, tok.context, tok.epoch, node.id))
                self.active.remove(tag)
                self.fired = {x for x in self.fired if x[:2] != tag}
                for key in tuple(self.operands):
                    if key[:2] == tag:
                        raise ProtocolError("unconsumed operands at completion")
            else:
                self.events.append(Token(value, tok.epoch, node.dest_node,
                                         node.dest_port, tok.context))
        return True

    def drain(self, max_steps: int = 1000) -> list[Result]:
        steps = 0
        while self.events:
            if steps >= max_steps:
                raise ProtocolError("execution step limit exceeded")
            self.step()
            steps += 1
        if self.active:
            raise ProtocolError("incomplete graph: some active tags have no result")
        result = list(self.results)
        self.results.clear()
        return result

    def run(self, input_sets: list[tuple[int, int, dict[str, int]]]) -> list[Result]:
        for context, epoch, values in input_sets:
            self.begin(context, epoch)
            for token in self.graph.input_tokens(values, context=context, epoch=epoch):
                self.inject(token)
        return self.drain()
