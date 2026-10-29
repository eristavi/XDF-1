"""Sensor event semantics and bounded scheduling tests (behavioral reference)."""
import random
import pytest
from xdf1.sensory import (
    SensorEvent, SensorDecision, SensoryFabric, i32, MIN32, MAX32, MAX34, next_estimate,
)


def test_event_codec_boundaries():
    for v in (MIN32, -123, 0, 5, MAX32):
        e=SensorEvent(sensor=255,sequence=65535,timestamp=0xffffffff,value=v,priority=3,kind=3,reserved=15)
        assert SensorEvent.decode(e.encode()) == e
    with pytest.raises(ValueError):
        SensorEvent(sensor=256,sequence=0,timestamp=0,value=0)
    with pytest.raises(ValueError):
        SensorEvent.decode(1<<96)


def test_two_events_from_same_sensor_update_state():
    f=SensoryFabric()
    f.configure_sensor(0,10)
    f.configure_group(0,25)
    offers=[[SensorEvent(0,1,100,12),None,None,None],
            [SensorEvent(0,2,101,20),None,None,None]]
    delivered=[]
    for batch in offers:
        step=f.tick(batch)
        assert step.ready[0]
        if step.delivered: delivered.append(step.delivered)
    delivered.extend(f.drain())
    assert [d.event.value for d in delivered]==[12,20]
    assert [d.estimate for d in delivered]==[12,14]
    assert [d.group_sum for d in delivered]==[12,20]
    assert [d.alarm for d in delivered]==[True,True]
    assert [d.group_alarm for d in delivered]==[False,False]


def test_four_simultaneous_input_handshakes_and_fusion():
    f=SensoryFabric()
    f.configure_group(0,25)
    events=[SensorEvent(i,1,100,10,priority=0) for i in range(4)]
    first=f.tick(events)
    assert all(first.ready)
    assert f.accepted==4
    output=f.drain()
    assert len(output)==4
    assert output[-1].group_sum==40
    assert [x.group_sum for x in output]==[10,20,30,40]
    assert output[-1].group_alarm


def test_output_backpressure_holds_token_and_stops_ingress_when_full():
    f=SensoryFabric(depth=2)
    for seq in range(1,4):
        f.tick([SensorEvent(0,seq,seq,seq),None,None,None],result_ready=False)
    assert f.out is not None
    held=f.out
    for _ in range(5):
        step=f.tick([SensorEvent(0,4,4,4),None,None,None],result_ready=False)
        assert f.out==held
        assert not step.ready[0]
        assert step.delivered is None
    assert [d.event.sequence for d in f.drain()]==[1,2,3]


def test_sequence_duplicates_and_old_samples_rejected():
    f=SensoryFabric()
    for e in [SensorEvent(10,1,20,7),SensorEvent(10,1,30,3),SensorEvent(10,2,19,5),SensorEvent(10,2,21,9)]:
        f.tick([e,None,None,None]);f.tick()
    out=f.drain()
    assert [x.event.value for x in out]==[9]  # earlier three outputs already delivered in ticks
    assert f.count[10]==2
    assert f.faults==2
    assert f.group_sum[2]==9


def test_fixed_point_ema_avoids_signed_overflow():
    assert next_estimate(MAX32,MIN32,False)==1073741823
    assert next_estimate(MIN32,MAX32,False)==-1073741825
    assert next_estimate(0,MAX32,True)==MAX32


def test_priority_preemption_and_bounded_background_service():
    f=SensoryFabric(urgent_budget=3,depth=40)
    f.tick([SensorEvent(0,1,1,0,priority=0),SensorEvent(1,1,1,0,priority=3),None,None])
    assert f.tick().launched.event.sensor==1
    # Continuous priority-3 events should not prevent the low-priority item forever.
    for s in range(2,12):
        f.tick([None,SensorEvent(1,s,s,0,priority=3),None,None])
    result=f.drain()
    assert f.count[0]==1
    assert f.count[1]==11
    assert result


def test_64_streams_random_arrivals_and_integrity():
    rng=random.Random(0xADF123)
    f=SensoryFabric()
    last_seq=[0]*64
    last_value=[0]*64
    expected_seen=[]
    consumed=[]
    pending=[None]*4
    for cyc in range(4000):
        for lane in range(4):
            if pending[lane] is None and rng.random() < .72:
                sensor=rng.randrange(64)
                last_seq[sensor]+=1
                if last_seq[sensor]>=65536: raise AssertionError
                val=rng.randint(-1000,1000)
                pending[lane]=SensorEvent(sensor,last_seq[sensor],last_seq[sensor],val,priority=rng.randrange(4))
                expected_seen.append(pending[lane])
        tick=f.tick(pending, result_ready=(cyc%13!=0))
        if tick.delivered: consumed.append(tick.delivered)
        for lane in range(4):
            if pending[lane] and tick.ready[lane]:pending[lane]=None
    while any(pending):
        t=f.tick(pending)
        if t.delivered:consumed.append(t.delivered)
        for lane in range(4):
            if pending[lane] and t.ready[lane]: pending[lane]=None
    consumed.extend(f.drain())
    # Arrival order of a single sensor is not guaranteed across lanes; out-of-order
    # samples are explicitly rejected rather than silently corrupting state.
    assert f.accepted == len(expected_seen)
    assert len(consumed)+f.faults == f.accepted
    assert all(d.event.sensor < 64 for d in consumed)
    assert sum(f.count) == len(consumed)
    assert f.processed == len(consumed)
    assert f.alarms == sum(d.alarm or d.group_alarm for d in consumed)
    # Every emitted result is the sum of the latest 4 accepted sensor readings.
    state={}
    for d in consumed:
        state[d.event.sensor]=d.event.value
        expected=sum(state.get(i,0) for i in range((d.event.sensor//4)*4,(d.event.sensor//4)*4+4))
        assert d.group_sum==expected


def test_reserved_field_does_not_overflow_event_width():
    with pytest.raises(ValueError):
        SensorEvent(sensor=0,sequence=1,timestamp=0,value=0,reserved=16)
    with pytest.raises(ValueError):
        SensorEvent(sensor=0,sequence=1,timestamp=0,value=0,kind=4)


def test_reset_clears_config_and_pending_state():
    f=SensoryFabric(depth=1)
    f.configure_sensor(0,-100)
    f.configure_group(0,-100)
    f.tick([SensorEvent(0,1,1,-1),None,None,None],result_ready=False)
    with pytest.raises(RuntimeError):
        f.configure_sensor(0,10)
    f.reset()
    assert f.accepted==0 and f.processed==0 and f.faults==0
    assert not f.pending() and f.threshold[0]==MAX32 and f.group_threshold[0]==MAX34
    f.tick([SensorEvent(0,1,1,-1),None,None,None])
    f.tick()
    out=f.drain()
    assert len(out)==1 and not out[0].alarm and not out[0].group_alarm


def test_lower_nonzero_priority_cannot_starve_forever():
    f=SensoryFabric(urgent_budget=3,depth=64)
    # Both queues loaded while first result is held. 3-priority work must not
    # indefinitely starve priority-1 work even though no priority-0 is present.
    for k in range(20):
        f.tick([SensorEvent(0,k+1,k+1,0,priority=3),
                SensorEvent(1,k+1,k+1,0,priority=1),None,None],result_ready=False)
    out=f.drain()
    assert f.processed==40
    assert [d.event.sensor for d in out].count(1)==20
    assert any(d.event.sensor==1 for d in out[:8])


def test_256_logical_sensor_model_group_last():
    f=SensoryFabric(sensors=256)
    assert f.sensors==256 and len(f.group_sum)==64
    f.configure_sensor(255,5)
    f.configure_group(63,6)
    f.tick([SensorEvent(255,1,15,9),None,None,None])
    f.tick()
    out=f.drain()
    assert len(out)==1 and out[0].alarm and out[0].group_alarm
    assert f.group_sum[63]==9


def test_sensory_vector_packer_and_deterministic_stimulus():
    from tools.generate_sensory_vectors import pack_decision, generate
    ev=SensorEvent(0,1,1,-15)
    d=SensorDecision(event=ev,estimate=-10,group_sum=-123,alarm=True,group_alarm=False)
    packed=pack_decision(d)
    assert packed & ((1<<96)-1)==ev.encode()
    assert packed>>96 & 0xffffffff==(-10)&0xffffffff
    assert packed>>128 & ((1<<34)-1)==(-123)&((1<<34)-1)
    assert packed>>162 & 3==1
    data,metrics=generate()
    assert data.startswith(str(metrics['cycles'])) and metrics['accepted']==metrics['processed']+metrics['faults']
