"""Unit tests for synthesis-count reporting (not for RTL correctness)."""
import importlib.util
from pathlib import Path

import pytest


loader_spec = importlib.util.spec_from_file_location(
    "synthesis_summary", Path(__file__).parents[1] / "tools/summarize_synthesis.py"
)
module = importlib.util.module_from_spec(loader_spec)
loader_spec.loader.exec_module(module)


def test_hierarchy_counts_instances_not_just_cell_types():
    data = {"modules": {
        "xdf_top": {"cells": {
            "tile0": {"type": "tile"}, "tile1": {"type": "tile"},
            "and0": {"type": "$_AND_"}
        }},
        "tile": {"cells": {
            "reg": {"type": "$_DFF_P_"}, "mux": {"type": "$_MUX_"}
        }}
    }}
    report = module.summarize(data)
    assert report["modules_reachable"] == 2
    assert report["generic_cell_instances"] == 5
    assert report["generic_sequential_cell_instances"] == 2
    assert report["cell_types"] == {"$_AND_": 1, "$_DFF_P_": 2, "$_MUX_": 2}


def test_missing_top_is_rejected():
    with pytest.raises(ValueError, match="not found"):
        module.summarize({"modules": {}})


def test_recursive_module_is_rejected():
    with pytest.raises(ValueError, match="Recursive"):
        module.summarize({"modules": {"xdf_top": {"cells": {"a": {"type": "xdf_top"}}}}})
