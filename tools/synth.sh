#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
for tool in sv2v yosys python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "NOT RUN: $tool is unavailable. Install sv2v, Yosys and Python 3." >&2
    exit 2
  fi
done

# Convert the synthesizable SystemVerilog files into Verilog-2005.
# The testbench is deliberately excluded from synthesis.
sv2v rtl/xdf_pkg.sv rtl/xdf_tile.sv rtl/xdf_router.sv rtl/xdf_top.sv > build/xdf1_synth.v

# Technology-independent structural check. No target FPGA, cell library,
# clock period, PDK, or placement constraints are supplied at this stage.
yosys -l build/synthesis.log -p \
  'read_verilog build/xdf1_synth.v; hierarchy -check -top xdf_top; synth -top xdf_top; check -assert; write_json build/yosys.json; stat'

python3 tools/summarize_synthesis.py build/yosys.json build/synthesis-summary.json
{
  echo "Technology-independent Yosys synthesis: SUCCESS"
  echo "Source SHA: ${GITHUB_SHA:-local-or-untracked}"
  echo "sv2v version: $(sv2v --version)"
  echo "yosys version: $(yosys -V)"
  echo "Design top: xdf_top"
  echo "No FPGA device, timing constraints, ASIC standard-cell library or PDK was used."
  echo "Files: build/synthesis.log, build/yosys.json, build/synthesis-summary.json"
} | tee build/synthesis-status.txt
