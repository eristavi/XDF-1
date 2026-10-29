from tools.demo_memory import simulate


def test_descriptor_only_500mbps_scenario(capsys):
    stats=simulate(seconds=350, target=.05)
    assert stats.ingested_raw_bytes == 500_000_000*350
    assert 0 < stats.selected_raw_bytes <= stats.ingested_raw_bytes
    assert stats.archived_experiences == 4
    assert stats.protected_experiences == 1
    text=capsys.readouterr().out
    assert 'descriptor-only' in text.lower()
    assert 'Physical raw payload bytes copied to disk: 0' in text
