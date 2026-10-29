"""Independent architectural router model used for fairness/backpressure tests."""
from collections import deque
from dataclasses import dataclass
from .architecture import Token


@dataclass(frozen=True)
class Transfer:
    source: int
    destination: int | None
    token: Token
    error: str | None = None


class RouterModel:
    """Five producer FIFOs, four sinks; one successful transfer per cycle.

    The queues represent external stable ready/valid sources, not actual RTL
    router queues. This model verifies routing and fairness policy only.
    """
    def __init__(self):
        self.sources = [deque() for _ in range(5)]
        self.rr = 0

    def push(self, source: int, token: Token):
        if not 0 <= source < 5:
            raise ValueError('source must be 0..4')
        self.sources[source].append(token)

    def cycle(self, ready: tuple[bool, bool, bool, bool]) -> Transfer | None:
        if len(ready) != 4:
            raise ValueError('four destination ready bits required')
        for offset in range(5):
            source = (self.rr + offset) % 5
            if not self.sources[source]:
                continue
            token = self.sources[source][0]
            destination = token.node >> 3 if token.node < 32 else None
            if destination is not None and not ready[destination]:
                continue
            self.sources[source].popleft()
            self.rr = (source + 1) % 5
            return Transfer(source, destination, token,
                            'BAD_DEST' if destination is None else None)
        return None
