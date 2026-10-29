SHELL := /bin/bash
PYTHON ?= python3
RTL = rtl/xdf_pkg.sv rtl/xdf_tile.sv rtl/xdf_router.sv rtl/xdf_top.sv

.PHONY: reflex-vectors reflex-lint reflex-sim reflex-synth frontend-lint frontend-sim frontend-synth help python-test vectors reference rtl-sim rtl-lint synth sensory-vectors sensory-lint sensory-sim sensory-synth clean pipeline-lint pipeline-sim pipeline-synth
help:
	@echo "XDF-1 targets: python-test vectors reference rtl-lint rtl-sim synth sensory-vectors sensory-lint sensory-sim sensory-synth reflex-lint reflex-sim frontend-lint frontend-sim reflex-synth frontend-synth clean"

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
	@mkdir -p build/obj_dir
	verilator --binary --timing -j 2 -Wno-fatal --top-module tb_xdf_top \
	  --Mdir build/obj_dir $(RTL) tb/tb_xdf_top.sv
	build/obj_dir/Vtb_xdf_top +VECTORS=tb/reference_vectors.txt

sensory-vectors:
	PYTHONPATH=python $(PYTHON) tools/generate_sensory_vectors.py

sensory-lint:
	@command -v verilator >/dev/null || { echo "ERROR: verilator is not installed"; exit 2; }
	verilator --lint-only --timing -Wno-fatal --top-module xdf_sensory rtl/xdf_sensory.sv

sensory-sim: sensory-vectors
	@command -v verilator >/dev/null || { echo "ERROR: verilator is not installed"; exit 2; }
	@mkdir -p build/sensory_obj_dir
	verilator --binary --timing -j 2 -Wno-fatal --top-module tb_xdf_sensory \
	  --Mdir build/sensory_obj_dir rtl/xdf_sensory.sv tb/tb_xdf_sensory.sv
	build/sensory_obj_dir/Vtb_xdf_sensory

synth:
	bash tools/synth.sh

sensory-synth:
	bash tools/synth_sensory.sh

# Whole-system M2.1 sensor -> tagged graph -> contextual decision.
PIPELINE_RTL = $(RTL) rtl/xdf_sensory.sv rtl/xdf_sensor_pipeline.sv

pipeline-lint:
	@command -v verilator >/dev/null || { echo "ERROR: Verilator is missing"; exit 2; }
	verilator --lint-only --timing -Wno-fatal --top-module xdf_sensor_pipeline $(PIPELINE_RTL)

pipeline-sim:
	@command -v verilator >/dev/null || { echo "ERROR: Verilator is missing"; exit 2; }
	@mkdir -p build/pipeline_obj_dir
	verilator --binary --timing -j 2 -Wno-fatal --top-module tb_xdf_sensor_pipeline \
	  --Mdir build/pipeline_obj_dir $(PIPELINE_RTL) tb/tb_xdf_sensor_pipeline.sv
	build/pipeline_obj_dir/Vtb_xdf_sensor_pipeline

pipeline-synth:
	bash tools/synth_pipeline.sh


# M2.2B programmable reflex classifier + validated SEF frontend.
FRONTEND_RTL = rtl/xdf_sensory.sv rtl/xdf_reflex.sv rtl/xdf_perception_frontend.sv

reflex-vectors:
	PYTHONPATH=python $(PYTHON) tools/generate_reflex_vectors.py

reflex-lint:
	@command -v verilator >/dev/null || { echo "ERROR: Verilator is missing"; exit 2; }
	verilator --lint-only --timing -Wno-fatal --top-module xdf_reflex rtl/xdf_reflex.sv

reflex-sim: reflex-vectors
	@command -v verilator >/dev/null || { echo "ERROR: Verilator is missing"; exit 2; }
	@mkdir -p build/reflex_obj_dir
	verilator --binary --timing -j 2 -Wno-fatal --top-module tb_xdf_reflex \
	  --Mdir build/reflex_obj_dir rtl/xdf_reflex.sv tb/tb_xdf_reflex.sv
	build/reflex_obj_dir/Vtb_xdf_reflex

reflex-synth:
	bash tools/synth_reflex.sh

frontend-lint:
	@command -v verilator >/dev/null || { echo "ERROR: Verilator is missing"; exit 2; }
	verilator --lint-only --timing -Wno-fatal --top-module xdf_perception_frontend $(FRONTEND_RTL)

frontend-sim:
	@command -v verilator >/dev/null || { echo "ERROR: Verilator is missing"; exit 2; }
	@mkdir -p build/frontend_obj_dir
	verilator --binary --timing -j 2 -Wno-fatal --top-module tb_xdf_perception_frontend \
	  --Mdir build/frontend_obj_dir $(FRONTEND_RTL) tb/tb_xdf_perception_frontend.sv
	build/frontend_obj_dir/Vtb_xdf_perception_frontend

frontend-synth:
	bash tools/synth_frontend.sh

clean:
	rm -rf build/reflex_obj_dir build/frontend_obj_dir build/reflex-synth.v build/reflex-synthesis.log build/reflex-yosys.json build/reflex-synthesis-summary.json build/reflex-synthesis-status.txt build/frontend-synth.v build/frontend-synthesis.log build/frontend-yosys.json build/frontend-synthesis-summary.json build/frontend-synthesis-status.txt build/pipeline_obj_dir build/pipeline-synth.v build/pipeline-synthesis.log build/pipeline-yosys.json build/pipeline-synthesis-summary.json build/pipeline-synthesis-status.txt build/obj_dir build/sensory_obj_dir build/xdf1_synth.v build/synthesis.log build/yosys.json build/xdf_sensory_synth.v build/sensory-synthesis.log build/sensory-yosys.json build/sensory-synthesis-summary.json build/sensory-synthesis-status.txt
