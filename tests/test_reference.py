"""Reference specification tests: software-only, NOT an RTL simulation."""
import random
import pytest
from xdf1.architecture import (Graph, GraphError, ProtocolError, Token, WORD_MASK)
from xdf1.reference import ReferenceFabric


def expected(a, b, c, d):
    return ((a + b) & WORD_MASK) ^ ((c - d) & WORD_MASK)


def test_known_result(graph):
    assert [r.value for r in ReferenceFabric(graph).run([(1, 7, {'A':7, 'B':5, 'C':9, 'D':3})])] == [10]


def test_two_epochs_isolated(graph):
    fabric = ReferenceFabric(graph)
    inputs = [(1, 7, {'A':7, 'B':5, 'C':9, 'D':3}),
              (2, 8, {'A':2, 'B':8, 'C':20, 'D':11})]
    assert {(r.context, r.epoch): r.value for r in fabric.run(inputs)} == {(1,7):10,(2,8):3}


def test_1000_randomized_reordered_inputs(graph):
    rng = random.Random(0xD3A6F10)
    fabric = ReferenceFabric(graph)
    for i in range(1000):
        numbers = [rng.getrandbits(32) for _ in range(4)]
        values = dict(zip('ABCD', numbers))
        fabric.begin(i % 16, i % 256)
        order = list('ABCD')
        rng.shuffle(order)
        for token in graph.input_tokens(values, context=i % 16, epoch=i % 256, order=order):
            assert Token.decode(token.encode()) == token
            fabric.inject(token)
        actual = fabric.drain()
        assert len(actual) == 1
        assert actual[0].value == expected(*numbers)


def test_wraparound(graph):
    values = {'A': 0xffffffff, 'B': 2, 'C': 0, 'D': 1}
    result = ReferenceFabric(graph).run([(1, 2, values)])[0]
    assert result.value == expected(*values.values())


def test_duplicate_operand_rejected(graph):
    f = ReferenceFabric(graph)
    f.begin(1, 1)
    tok = graph.input_tokens({'A':1,'B':2,'C':3,'D':4}, context=1, epoch=1)[0]
    f.inject(tok)
    f.inject(tok)
    with pytest.raises(ProtocolError, match='duplicate'):
        f.drain()


def test_reset_clears_all_state(graph):
    f = ReferenceFabric(graph)
    f.begin(1, 7)
    f.inject(Token(7, 7, 0, 0, 1))
    f.step()
    f.reset()
    assert f.run([(1, 7, {'A': 7, 'B': 5, 'C':9, 'D':3})])[0].value == 10


def test_active_tag_limit(graph):
    f = ReferenceFabric(graph)
    f.begin(1, 7)
    f.begin(1, 8)
    with pytest.raises(ProtocolError, match='at most 2'):
        f.begin(2, 9)
    with pytest.raises(ProtocolError, match='duplicate'):
        f.begin(1, 7)


def test_input_before_begin_rejected(graph):
    f = ReferenceFabric(graph)
    with pytest.raises(ProtocolError, match='not active'):
        f.inject(Token(7, 7, 0, 0, 1))


def test_nonzero_flags_rejected(graph):
    f = ReferenceFabric(graph)
    f.begin(1, 7)
    with pytest.raises(ProtocolError, match='flags'):
        f.inject(Token(7, 7, 0, 0, 1, flags=1))


def test_invalid_nodes_and_ports(graph):
    f = ReferenceFabric(graph)
    f.begin(1, 7)
    f.inject(Token(7, 7, 255, 0, 1))
    with pytest.raises(ProtocolError, match='unconfigured'):
        f.drain()
    f.reset()
    f.begin(1, 7)
    f.inject(Token(7, 7, 0, 3, 1))
    with pytest.raises(ProtocolError, match='operand port'):
        f.drain()


def test_graph_rejects_cycle():
    with pytest.raises(GraphError, match='cyclic'):
        Graph.from_dict({'nodes':[
            {'id':0,'op':'PASS','dest':{'node':1,'port':0}},
            {'id':1,'op':'PASS','dest':{'node':0,'port':0}},
            {'id':2,'op':'OUTPUT'}],
            'inputs':{'A':{'node':0,'port':0},'B':{'node':2,'port':0}}})


def test_graph_rejects_double_source():
    with pytest.raises(GraphError, match='one source'):
        Graph.from_dict({'nodes':[
            {'id':0,'op':'PASS','dest':{'node':1,'port':0}},
            {'id':1,'op':'OUTPUT'}],
            'inputs':{'A':{'node':0,'port':0},'B':{'node':1,'port':0}}})


def test_graph_rejects_missing_source():
    with pytest.raises(GraphError, match='one source'):
        Graph.from_dict({'nodes':[{'id':1,'op':'OUTPUT'}],
                         'inputs':{'A':{'node':1,'port':0},'B':{'node':1,'port':0}}})


def test_graph_config_metadata(graph):
    assert [r['node'] for r in graph.configuration()] == [0, 8, 16, 24]
    assert [r['opcode'] for r in graph.configuration()] == [0, 1, 2, 5]


def test_and_pass_output_alternative_graph():
    alternative = Graph.from_dict({
        'name': 'and_pass',
        'nodes': [
            {'id': 0, 'op': 'AND', 'dest': {'node': 8, 'port': 0}},
            {'id': 8, 'op': 'PASS', 'dest': {'node': 24, 'port': 0}},
            {'id': 24, 'op': 'OUTPUT'},
        ],
        'inputs': {'A': {'node': 0, 'port': 0}, 'B': {'node': 0, 'port': 1}},
    })
    f = ReferenceFabric(alternative)
    assert f.run([(3, 14, {'A': 0xffff0000, 'B': 0x0f0f0000})])[0].value == 0x0f0f0000


def test_all_opcodes_return_32_bit_words():
    from xdf1.architecture import alu
    assert alu('ADD', 0xffffffff, 1) == 0
    assert alu('SUB', 0, 1) == 0xffffffff
    assert alu('XOR', 0xaa, 0x0f) == 0xa5
    assert alu('AND', 0xaa, 0x0f) == 0x0a
    assert alu('PASS', 123) == 123
    assert alu('OUTPUT', 123) == 123
