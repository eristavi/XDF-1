"""Cycle-accurate oracle for the M2.2B programmable sensory reflex classifier.

A 164-bit item is the validated scalar observation emitted by xdf_sensory.
This module makes no physical timing, neural inference or disk I/O claims.
"""
from __future__ import annotations

from dataclasses import dataclass

DROP, CONTEXT, REFLEX, BOTH = range(4)
ALWAYS, ABOVE, CHANGE, GROUP = range(4)
MASK32 = (1 << 32) - 1
MASK164 = (1 << 164) - 1
MASK176 = (1 << 176) - 1


def signed32(value: int) -> int:
    value &= MASK32
    return value - (1 << 32) if value & (1 << 31) else value


@dataclass(frozen=True)
class Rule:
    enabled: bool
    sensor: int
    mode: int
    threshold: int
    action: int

    def __post_init__(self) -> None:
        if not 0 <= self.sensor <= 255:
            raise ValueError("sensor outside 8-bit range")
        if not 0 <= self.mode <= 3 or not 0 <= self.action <= 3:
            raise ValueError("invalid mode/action")
        if not -(1 << 31) <= self.threshold < 1 << 31:
            raise ValueError("threshold outside signed 32-bit range")
        if self.mode == CHANGE and self.threshold < 0:
            raise ValueError("ABS delta threshold must be nonnegative")


@dataclass(frozen=True)
class Classification:
    action: int
    rule_id: int
    reasons: int
    packed: int


@dataclass(frozen=True)
class Cycle:
    ready: bool
    reflex: int | None
    context: int | None
    accepted: bool
    context_lost: bool


class ReflexClassifier:
    def __init__(self, rules: int = 8, *, context_lossless: bool = False):
        if not 1 <= rules <= 32:
            raise ValueError("rules must be 1..32")
        self.rule_capacity = rules
        self.context_lossless = context_lossless
        self.reset()

    def reset(self) -> None:
        self.rules: list[Rule | None] = [None] * self.rule_capacity
        self.default_action = DROP
        self.reflex: int | None = None
        self.context: int | None = None
        self.accepted_count = 0
        self.filtered_count = 0
        self.reflex_count = 0
        self.context_count = 0
        self.context_drop_count = 0
        self.protected_context_drop_count = 0
        self.cfg_faults = 0

    def configure(self, index: int, rule: Rule | None = None, *, default_action: int | None = None) -> bool:
        if self.reflex is not None or self.context is not None:
            raise RuntimeError("configuration requires idle outputs")
        if index == 255:
            if default_action is None or not 0 <= default_action <= 3:
                self.cfg_faults += 1
                return False
            self.default_action = default_action
            return True
        if not 0 <= index < self.rule_capacity or rule is None:
            self.cfg_faults += 1
            return False
        self.rules[index] = rule
        return True

    @staticmethod
    def alarm_bits(observation: int) -> tuple[bool, bool]:
        return bool((observation >> 162) & 1), bool((observation >> 163) & 1)

    def classify(self, observation: int) -> Classification:
        if type(observation) is not int or not 0 <= observation <= MASK164:
            raise ValueError("observation must be 164-bit unsigned")
        sensor = (observation >> 64) & 0xFF
        raw = signed32(observation)
        ema = signed32(observation >> 96)
        sensor_alarm, group_alarm = self.alarm_bits(observation)
        protected = sensor_alarm or group_alarm
        action, chosen = self.default_action, 255
        matched = False
        for i, rule in enumerate(self.rules):
            if rule is None or not rule.enabled or (rule.sensor not in (255, sensor)):
                continue
            if ((rule.mode == ALWAYS) or
                (rule.mode == ABOVE and raw >= rule.threshold) or
                (rule.mode == CHANGE and abs(raw - ema) >= rule.threshold) or
                (rule.mode == GROUP and group_alarm)):
                chosen = i
                action = rule.action
                matched = True
                break
        if protected:
            action |= BOTH
        reasons = (int(protected) << 3) | (int(matched) << 2) | (int(group_alarm) << 1) | int(sensor_alarm)
        return Classification(action, chosen, reasons, (chosen << 168) | (reasons << 164) | observation)

    def tick(self, observation: int | None = None, *, reflex_ready: bool = True,
             context_ready: bool = True) -> Cycle:
        old_reflex, old_context = self.reflex, self.context
        classification = self.classify(observation) if observation is not None else None
        reflex_space = old_reflex is None or reflex_ready
        context_space = old_context is None or context_ready
        ready = (classification is None or
                 (not classification.action & REFLEX or reflex_space) and
                 (not self.context_lossless or not classification.action & CONTEXT or context_space))
        accepted = observation is not None and ready
        lost = bool(accepted and classification.action & CONTEXT and not context_space)
        if reflex_space:
            self.reflex = classification.packed if accepted and classification.action & REFLEX else None
        if context_space:
            self.context = classification.packed if accepted and classification.action & CONTEXT else None
        if accepted:
            self.accepted_count = (self.accepted_count + 1) & MASK32
            if classification.action == DROP:
                self.filtered_count = (self.filtered_count + 1) & MASK32
            if classification.action & REFLEX:
                self.reflex_count = (self.reflex_count + 1) & MASK32
            if classification.action & CONTEXT and context_space:
                self.context_count = (self.context_count + 1) & MASK32
        if lost:
            self.context_drop_count = (self.context_drop_count + 1) & MASK32
            if any(self.alarm_bits(observation)):
                self.protected_context_drop_count = (self.protected_context_drop_count + 1) & MASK32
        return Cycle(ready=ready, reflex=old_reflex, context=old_context,
                     accepted=accepted, context_lost=lost)


def encode_observation(sensor: int, raw: int, ema: int, *, sensor_alarm: bool = False,
                       group_alarm: bool = False, timestamp: int = 0,
                       sequence: int = 0, group_sum: int = 0) -> int:
    if not 0 <= sensor <= 255 or not 0 <= timestamp <= MASK32 or not 0 <= sequence <= 65535:
        raise ValueError("invalid sensor ID or time/sequence")
    if not -(1 << 31) <= raw < 1 << 31 or not -(1 << 31) <= ema < 1 << 31:
        raise ValueError("raw/ema outside signed32")
    if not -(1 << 33) <= group_sum < 1 << 33:
        raise ValueError("group sum outside signed34")
    return ((int(group_alarm) << 163) | (int(sensor_alarm) << 162) |
            ((group_sum & ((1 << 34)-1)) << 128) | ((ema & MASK32) << 96) |
            (sequence << 72) | (sensor << 64) | (timestamp << 32) | (raw & MASK32))
