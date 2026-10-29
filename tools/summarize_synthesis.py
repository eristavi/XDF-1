#!/usr/bin/env python3
"""Count generic Yosys cells hierarchy-aware, without claiming silicon area."""
from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path


def summarize(netlist: dict, top: str = "xdf_top") -> dict:
    modules = netlist["modules"]
    if top not in modules:
        raise ValueError(f"Synthesis top {top!r} not found")
    cells: Counter[str] = Counter()
    seen = set()

    def visit(module_name: str, ancestors: tuple[str, ...]) -> None:
        if module_name in ancestors:
            raise ValueError(f"Recursive module instantiation: {module_name}")
        seen.add(module_name)
        for cell in modules[module_name].get("cells", {}).values():
            kind = cell["type"]
            if kind in modules:
                visit(kind, ancestors + (module_name,))
            else:
                cells[kind] += 1

    visit(top, ())
    sequential = sum(v for k, v in cells.items() if k.startswith(("$_DFF", "$_SDFF", "$_DFFE", "$_SDFFE", "$_DLATCH", "$_DFFE", "$_FF")))
    return {
        "top": top,
        "purpose": "technology-independent generic cell enumeration",
        "mapped_fpga_resources": False,
        "mapped_asic_area": False,
        "timing_analyzed": False,
        "modules_reachable": len(seen),
        "generic_cell_instances": sum(cells.values()),
        "generic_sequential_cell_instances": sequential,
        "generic_other_cell_instances": sum(cells.values()) - sequential,
        "cell_types": dict(sorted(cells.items())),
    }


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("Usage: summarize_synthesis.py NETLIST.json SUMMARY.json")
    netlist = json.loads(Path(sys.argv[1]).read_text())
    report = summarize(netlist)
    Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(f"Yosys generic synthesis: {report['generic_cell_instances']} leaf cells; "
          f"{report['generic_sequential_cell_instances']} sequential; "
          f"{report['modules_reachable']} reachable module types")


if __name__ == "__main__":
    main()
