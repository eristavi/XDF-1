SHELL := /bin/bash
PYTHON ?= python3
RTL = rtl/xdf_pkg.sv rtl/xdf_tile.sv rtl/xdf_router.sv rtl/xdf_top.sv

.PHONY: help python-test vectors reference rtl-sim rtl-lint synth clean
help:
	@echo "XDF-1 M1 targets: python-test vectors reference rtl-lint rtl-sim synth clean"

python-test:
	PYTHONPATH=python $(PYTHON) -m pytest -q tests

vectors:
	PYTHONPATH=python $(PYTHON) tools/generate_vectors.py

reference:
	PYTHONPATH=python $(PYTHON) -m xdf1.cli programs/first_graph.yaml \
	  --input A=7 --input B=5 --input C=9 --input D=3 --emit build/first_graph.compiled.json

rtl-lint:
	@command -v verilator >/dev/null || { echo "ERROR: verilator is not installed"; exit 2; }
	verilator --lint-only --timing -Wno-fatal --top-module xdf_top $(RTL)

rtl-sim: vectors
	@command -v verilator >/dev/null || { echo "ERROR: verilator is not installed"; exit 2; }
	verilator --binary --timing -j 2 -Wno-fatal --top-module tb_xdf_top \
	  --Mdir build/obj_dir $(RTL) tb/tb_xdf_top.sv
	build/obj_dir/Vtb_xdf_top +VECTORS=tb/reference_vectors.txt

synth:
	bash tools/synth.sh

clean:
	rm -rf build/obj_dir build/xdf1_synth.v build/synthesis.log build/yosys.json
