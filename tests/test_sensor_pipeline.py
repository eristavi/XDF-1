"""Independent numerical semantics for the integrated dataflow decision."""
import pytest
from xdf1.sensor_pipeline import signed32, decide, pack_result


def test_zero_delta_first_sample():
    d=decide(123,123,False,False)
    assert (d.delta_bits,d.delta_signed,d.critical)==(0,0,False)


def test_signed_rise_and_fall():
    assert decide(100,70,False,False).critical
    d=decide(-100,-55,False,False)
    assert d.delta_signed==-45 and d.delta_bits==(2**32-45) and d.critical
    assert not decide(1,-15,False,False).critical


def test_alarms_work_even_with_zero_delta():
    assert decide(10,10,True,False).critical
    assert decide(10,10,False,True).critical


def test_m1_sub_is_modular_for_overflow():
    d=decide((1<<31)-1,-(1<<31),False,False)
    assert d.delta_bits==0xffffffff and d.delta_signed==-1 and not d.critical
    d=decide(-(1<<31),(1<<31)-1,False,False)
    assert d.delta_bits==1 and d.delta_signed==1


def test_min_negative_delta_magnitude():
    d=decide(-(1<<31),0,False,False)
    assert d.delta_bits==1<<31 and d.critical


def test_pack_full_metadata_preserved():
    raw=(-75)&0xffffffff
    estimate=(-60)&0xffffffff
    meta=(1<<162)|(estimate<<96)|(0x123456789abcdef<<32)|raw
    got=pack_result(meta)
    assert got&((1<<164)-1)==meta
    assert (got>>164)&0xffffffff==(raw-estimate)&0xffffffff
    assert got>>196==1


@pytest.mark.parametrize('limit',[-1,1<<32])
def test_invalid_threshold(limit):
    with pytest.raises(ValueError): decide(1,1,False,False,limit)


def test_metadata_input_range():
    with pytest.raises(ValueError): pack_result(-1)
    with pytest.raises(ValueError): pack_result(1<<164)
