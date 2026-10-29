from pathlib import Path
import pytest
from xdf1.architecture import Graph


@pytest.fixture
def graph():
    return Graph.read(Path(__file__).parents[1] / 'programs' / 'first_graph.yaml')
