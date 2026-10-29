"""Backpressure and fair-routing tests on policy model; not RTL results."""
import random
from xdf1.architecture import Token
from xdf1.router_model import RouterModel


def tok(node, value):
    return Token(value=value, epoch=0, node=node, port=0, context=0)


def test_backpressure_does_not_consume_blocked_source():
    router = RouterModel()
    original = tok(0, 11)
    router.push(0, original)
    for _ in range(20):
        assert router.cycle((False, True, True, True)) is None
        assert router.sources[0][0] == original
    sent = router.cycle((True, True, True, True))
    assert sent.token == original and sent.source == 0 and sent.destination == 0


def test_fair_round_robin_and_destination_skipping():
    router = RouterModel()
    for source in range(5):
        router.push(source, tok(8, source))
    assert [router.cycle((True,True,True,True)).source for _ in range(5)] == list(range(5))
    router.push(0, tok(0,100))
    router.push(1, tok(8,101))
    event = router.cycle((False, True, True, True))
    assert event.source == 1 and event.token.value == 101
    assert len(router.sources[0]) == 1


def test_invalid_destination_consumed_with_error():
    router = RouterModel()
    router.push(0, tok(255, 0))
    event = router.cycle((False,False,False,False))
    assert event.destination is None and event.error == 'BAD_DEST'


def test_randomized_stall_no_duplicate_or_lost_tokens():
    rng = random.Random(90210)
    router = RouterModel()
    expected = set()
    for i in range(1000):
        source = rng.randrange(5)
        node = rng.randrange(32)
        packet = tok(node, i)
        router.push(source, packet)
        expected.add(i)
    seen = set()
    for tick in range(20000):
        # Every eleventh cycle accepts all tiles; random stalls on others.
        ready = (True,True,True,True) if tick % 11 == 0 else tuple(bool(rng.getrandbits(1)) for _ in range(4))
        event = router.cycle(ready)
        if event is not None:
            assert event.token.value not in seen
            assert event.destination == event.token.node // 8
            assert ready[event.destination]
            seen.add(event.token.value)
        if len(seen) == 1000:
            break
    assert seen == expected
    assert all(not src for src in router.sources)
