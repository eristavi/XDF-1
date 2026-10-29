"""Independent behavioral model of XDF-1's streaming sensory event front end.

A 96-bit event carries one timestamped measurement. Physical lanes are bounded
input queues, not one independently-clocked processor per sensor. Four sensors
may handshake on one edge, but the decision datapath processes one per cycle.
No real-time latency, clock accuracy or silicon power claims are implied.
"""
from __future__ import annotations
from collections import deque
from dataclasses import dataclass

EVENT_BITS = 96
N_SENSORS = 64
N_LANES = 4
FIFO_DEPTH = 2
PRIORITY_BUDGET = 8
MIN32, MAX32 = -(1 << 31), (1 << 31) - 1
MIN34, MAX34 = -(1 << 33), (1 << 33) - 1


def i32(value: int) -> int:
    value &= 0xffffffff
    return value - 0x100000000 if value & 0x80000000 else value


def i34(value: int) -> int:
    value &= (1 << 34)-1
    return value - (1 << 34) if value & (1 << 33) else value


def next_estimate(previous: int, sample: int, first: bool) -> int:
    # Arithmetic right shift; 33 bits avoid subtraction overflow.
    return sample if first else i32(previous + ((sample - previous) >> 2))


@dataclass(frozen=True)
class SensorEvent:
    sensor: int
    sequence: int
    timestamp: int
    value: int
    priority: int = 0
    kind: int = 0
    reserved: int = 0

    def __post_init__(self) -> None:
        checks = (('sensor', self.sensor, 256), ('sequence', self.sequence, 65536),
                  ('timestamp', self.timestamp, 1 << 32), ('priority', self.priority, 4),
                  ('kind', self.kind, 4), ('reserved', self.reserved, 16))
        for name, val, ceiling in checks:
            if type(val) is not int or not 0 <= val < ceiling:
                raise ValueError(f'invalid {name}: {val}')
        if type(self.value) is not int or not MIN32 <= self.value <= MAX32:
            raise ValueError('value must be signed 32-bit')

    def encode(self) -> int:
        return ((self.reserved << 92) | (self.kind << 90) |
                (self.priority << 88) | (self.sequence << 72) |
                (self.sensor << 64) | (self.timestamp << 32) |
                (self.value & 0xffffffff))

    @classmethod
    def decode(cls, packed: int) -> 'SensorEvent':
        if type(packed) is not int or not 0 <= packed < 1 << 96:
            raise ValueError('event must be 96-bit unsigned integer')
        return cls(sensor=(packed >> 64) & 255,
                   sequence=(packed >> 72) & 65535,
                   timestamp=(packed >> 32) & 0xffffffff,
                   value=i32(packed), priority=(packed >> 88) & 3,
                   kind=(packed >> 90) & 3, reserved=(packed >> 92) & 15)


@dataclass(frozen=True)
class SensorDecision:
    event: SensorEvent
    estimate: int
    group_sum: int
    alarm: bool
    group_alarm: bool


@dataclass(frozen=True)
class Tick:
    ready: tuple[bool, ...]
    delivered: SensorDecision | None
    launched: SensorDecision | None


class SensoryFabric:
    """Clocked, cycle-sensitive reference model of bounded event arbitration."""

    def __init__(self, sensors: int = N_SENSORS, lanes: int = N_LANES,
                 depth: int = FIFO_DEPTH, urgent_budget: int = PRIORITY_BUDGET):
        if sensors < 4 or sensors > 256 or sensors & (sensors - 1) or sensors % 4:
            raise ValueError('sensors must be a power of two between 4 and 256')
        if lanes <= 0 or depth <= 0 or urgent_budget <= 0:
            raise ValueError('lanes, depth and budget must be positive')
        self.sensors, self.lanes, self.depth, self.urgent_budget = sensors, lanes, depth, urgent_budget
        self.reset()

    def reset(self) -> None:
        self.threshold = [MAX32] * self.sensors
        self.group_threshold = [MAX34] * (self.sensors // 4)
        self.queue: list[deque[SensorEvent]] = [deque() for _ in range(self.lanes)]
        self.rr = 0
        self.urgent_streak = 0
        self.out: SensorDecision | None = None
        self.last_sequence: list[int | None] = [None] * self.sensors
        self.last_timestamp: list[int] = [0] * self.sensors
        self.last_value = [0] * self.sensors
        self.estimates = [0] * self.sensors
        self.group_sum = [0] * (self.sensors // 4)
        self.count = [0] * self.sensors
        self.accepted = 0
        self.processed = 0
        self.alarms = 0
        self.faults = 0
        self.last_fault_sensor: int | None = None
        self.cycle = 0

    def configure_sensor(self, sensor: int, threshold: int) -> None:
        if not 0 <= sensor < self.sensors or not MIN32 <= threshold <= MAX32:
            raise ValueError('invalid sensor threshold')
        if self.pending():
            raise RuntimeError('configure only while idle')
        self.threshold[sensor] = threshold

    def configure_group(self, group: int, threshold: int) -> None:
        if not 0 <= group < self.sensors // 4 or not MIN34 <= threshold <= MAX34:
            raise ValueError('invalid group threshold')
        if self.pending():
            raise RuntimeError('configure only while idle')
        self.group_threshold[group] = threshold

    def pending(self) -> bool:
        return any(self.queue) or self.out is not None

    @staticmethod
    def is_newer(curr: int, prev: int, width: int) -> bool:
        diff = (curr - prev) & ((1 << width) - 1)
        return 0 < diff < (1 << (width - 1))

    def _pick(self) -> int | None:
        available = [(i, self.queue[i][0].priority)
                     for i in range(self.lanes) if self.queue[i]]
        if not available:
            return None
        lowest = min(p for _, p in available)
        highest = max(p for _, p in available)
        # Priority is a bounded preference rather than unconditional starvation:
        # after `urgent_budget` consecutive higher-priority choices, serve the
        # lowest currently waiting priority before resuming preferential service.
        if self.urgent_streak >= self.urgent_budget:
            highest = lowest
        for k in range(self.lanes):
            i = (self.rr + k) % self.lanes
            if self.queue[i] and self.queue[i][0].priority == highest:
                return i
        raise AssertionError('nonempty arbitration set must have winner')

    def _process(self, event: SensorEvent) -> SensorDecision | None:
        if event.sensor >= self.sensors or event.kind != 0 or event.reserved:
            self.faults += 1
            self.last_fault_sensor = event.sensor
            return None
        sensor = event.sensor
        last_seq = self.last_sequence[sensor]
        if last_seq is not None:
            if (not self.is_newer(event.sequence, last_seq, 16) or
                    not self.is_newer(event.timestamp, self.last_timestamp[sensor], 32) and
                    event.timestamp != self.last_timestamp[sensor]):
                self.faults += 1
                self.last_fault_sensor = sensor
                return None
        old = self.last_value[sensor] if last_seq is not None else 0
        estimate = next_estimate(self.estimates[sensor], event.value, last_seq is None)
        group = sensor // 4
        fused = i34(self.group_sum[group] + event.value - old)
        self.estimates[sensor] = estimate
        self.group_sum[group] = fused
        self.last_value[sensor] = event.value
        self.last_sequence[sensor] = event.sequence
        self.last_timestamp[sensor] = event.timestamp
        self.count[sensor] += 1
        alert = event.value >= self.threshold[sensor]
        group_alert = fused >= self.group_threshold[group]
        self.processed += 1
        self.alarms += int(alert or group_alert)
        return SensorDecision(event, estimate, fused, alert, group_alert)

    def tick(self, offers: list[SensorEvent | None] | None = None,
             *, result_ready: bool = True) -> Tick:
        if offers is None:
            offers = [None] * self.lanes
        if len(offers) != self.lanes:
            raise ValueError('offers must have exactly lanes entries')
        delivered = self.out if self.out is not None and result_ready else None
        can_emit = self.out is None or result_ready
        choice = self._pick() if can_emit else None
        popping = [choice == i for i in range(self.lanes)]
        ready = tuple(len(self.queue[i]) < self.depth or popping[i]
                      for i in range(self.lanes))
        # Pop before new inputs: the newly offered event cannot bypass the FIFO.
        min_priority = min((self.queue[i][0].priority for i in range(self.lanes)
                            if self.queue[i]), default=3)
        popped = self.queue[choice].popleft() if choice is not None else None
        if choice is not None:
            # Count only occasions when lower-priority lane heads were waiting
            # at arbitration time (same semantics as combinational RTL).
            if popped.priority > min_priority:
                self.urgent_streak = min(self.urgent_streak + 1, self.urgent_budget)
            else:
                self.urgent_streak = 0
            self.rr = (choice + 1) % self.lanes
        for i, event in enumerate(offers):
            if event is not None and ready[i]:
                self.queue[i].append(event)
                self.accepted += 1
        launched = self._process(popped) if popped is not None else None
        if can_emit:
            self.out = launched
        self.cycle += 1
        return Tick(ready, delivered, launched)

    def drain(self, max_cycles: int = 100000) -> list[SensorDecision]:
        results = []
        for _ in range(max_cycles):
            if not self.pending():
                return results
            result = self.tick()
            if result.delivered is not None:
                results.append(result.delivered)
        raise TimeoutError('sensory pipeline did not drain')
