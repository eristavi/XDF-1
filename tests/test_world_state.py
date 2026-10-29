import pytest
from xdf1.world_state import CurrentObservation, WorldState


def obs(sensor, ns, value, confidence=1):
    return CurrentObservation(sensor, ns, value, 'm/s', confidence, 'test-imu')


def test_world_state_is_latest_not_a_raw_history():
    w=WorldState(max_sensors=2, expiry_ns=10)
    w.update(obs(0,1,2))
    w.update(obs(1,2,3))
    w.update(obs(0,3,4))
    assert len(w.snapshot(4)) == 2
    assert w.snapshot(4)[0].value == 4


def test_stale_and_duplicate_values_rejected():
    w=WorldState()
    w.update(obs(0,5,1))
    for ts in (4,5):
        with pytest.raises(ValueError,match='stale'):
            w.update(obs(0,ts,2))


def test_capacity_exceeded_explicitly_not_silently_dropped():
    w=WorldState(max_sensors=1)
    w.update(obs(0,1,1))
    with pytest.raises(OverflowError): w.update(obs(1,2,2))


def test_expiration_and_stale_state_visibility():
    w=WorldState(expiry_ns=10)
    w.update(obs(5,1,2))
    w.update(obs(6,9,2))
    assert [x.sensor_id for x in w.snapshot(12)] == [6]
    assert w.expire(12)==1
    assert len(w.snapshot(12))==1


def test_invalid_observations_cannot_contaminate_world_state():
    with pytest.raises(ValueError): obs(0,0,float('nan'))
    with pytest.raises(ValueError): obs(0,0,3,confidence=1.2)
