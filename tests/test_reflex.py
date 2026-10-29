"""Independent checks of programmable rules, decoupling, and safe overflow."""
import pytest
from xdf1.reflex import (
    ALWAYS, ABOVE, CHANGE, GROUP, DROP, CONTEXT, REFLEX, BOTH,
    ReflexClassifier, Rule, encode_observation,
)


def obs(sensor=1, raw=10, ema=10, *, sa=False, ga=False):
    return encode_observation(sensor, raw, ema, sensor_alarm=sa, group_alarm=ga)


def test_default_discard_and_counts():
    model = ReflexClassifier()
    step = model.tick(obs())
    assert step.ready and step.accepted and step.reflex is None and step.context is None
    assert (model.accepted_count, model.filtered_count) == (1, 1)


def test_priority_exact_sensor_rule_before_wildcard():
    model = ReflexClassifier()
    model.configure(0, Rule(True, 1, ABOVE, 100, REFLEX))
    model.configure(1, Rule(True, 255, ALWAYS, 0, CONTEXT))
    a = model.classify(obs(1, 101, 101))
    b = model.classify(obs(2, 101, 101))
    assert a.action == REFLEX and a.rule_id == 0 and a.reasons & 4
    assert b.action == CONTEXT and b.rule_id == 1
    assert a.packed >> 168 == 0
    assert (a.packed >> 164) & 0xF == a.reasons


def test_group_alarm_forces_reflex_and_context_when_rule_drops():
    model = ReflexClassifier()
    model.configure(0, Rule(True, 1, ALWAYS, 0, DROP))
    c = model.classify(obs(1, 5, 5, ga=True))
    assert c.action == BOTH and c.reasons == 0b1110
    assert (c.packed & ((1 << 164)-1)) == obs(1, 5, 5, ga=True)


def test_widened_delta_handles_extreme_signed_values():
    model = ReflexClassifier()
    model.configure(0, Rule(True, 255, CHANGE, 2000000000, REFLEX))
    assert model.classify(obs(7, (1 << 31)-1, -(1 << 31))).action == REFLEX
    assert model.classify(obs(7, -(1 << 31), (1 << 31)-1)).action == REFLEX
    assert model.classify(obs(7, 40, 0)).action == DROP


def test_negative_threshold_and_bad_rules_rejected():
    with pytest.raises(ValueError):
        Rule(True, 10, CHANGE, -1, BOTH)
    with pytest.raises(ValueError):
        Rule(True, 10, ABOVE, 1 << 31, BOTH)
    with pytest.raises(ValueError):
        ReflexClassifier(rules=33)
    m = ReflexClassifier(rules=2)
    assert not m.configure(3, Rule(True, 3, ALWAYS, 0, BOTH))
    assert m.cfg_faults == 1
    assert not m.configure(255, default_action=5)


def test_best_effort_context_drops_never_block_reflex():
    m = ReflexClassifier()
    m.configure(255, default_action=BOTH)
    first = obs(1, 3, 3)
    second = obs(2, 5, 4, sa=True)
    assert m.tick(first).ready
    # Old context is held. Reflex is drained, allowing another event.
    result = m.tick(second, reflex_ready=True, context_ready=False)
    assert result.ready and result.context is not None
    assert m.context_drop_count == 1 and m.protected_context_drop_count == 1
    assert m.reflex == m.classify(second).packed
    assert m.context == m.classify(first).packed


def test_reflex_output_never_drops_under_backpressure():
    m = ReflexClassifier()
    m.configure(255, default_action=REFLEX)
    a = obs(1, 1, 0)
    b = obs(2, 2, 0)
    m.tick(a)
    for _ in range(20):
        step = m.tick(b, reflex_ready=False)
        assert not step.ready and not step.accepted
        assert step.reflex == m.classify(a).packed
    assert m.tick(b, reflex_ready=True).accepted
    assert m.reflex == m.classify(b).packed


def test_lossless_context_backpressures_but_preserves_data():
    m = ReflexClassifier(context_lossless=True)
    m.configure(255, default_action=CONTEXT)
    a = obs(1, 1, 0)
    b = obs(2, 2, 0)
    m.tick(a)
    for _ in range(8):
        assert not m.tick(b, context_ready=False).ready
    assert m.context_drop_count == 0
    assert m.tick(b, context_ready=True).ready
    assert m.context_count == 2


def test_configuration_idle_only_and_reset():
    m = ReflexClassifier()
    m.configure(255, default_action=CONTEXT)
    m.tick(obs())
    with pytest.raises(RuntimeError):
        m.configure(0, Rule(True, 1, ALWAYS, 0, REFLEX))
    m.reset()
    assert m.context is None and m.default_action == DROP
    assert all(x is None for x in m.rules)
    assert m.accepted_count == 0


def test_group_rule_and_zero_threshold():
    m = ReflexClassifier()
    m.configure(0, Rule(True, 3, GROUP, 0, REFLEX))
    assert m.classify(obs(3, 10, 10)).action == DROP
    assert m.classify(obs(3, 10, 10, ga=True)).action == BOTH


def test_metadata_correct_under_context_stall():
    m = ReflexClassifier()
    m.configure(255, default_action=CONTEXT)
    a = encode_observation(12, -45, 15, timestamp=12345, sequence=59)
    b = encode_observation(11, 56, -8, timestamp=54321, sequence=61)
    m.tick(a)
    m.tick(b, context_ready=False)
    assert m.context == m.classify(a).packed
    assert m.context_drop_count == 1
    m.tick(b, context_ready=True)
    assert m.context == m.classify(b).packed
