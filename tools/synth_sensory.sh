#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
for tool in sv2v yosys python3; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    echo "NOT RUN: $tool is unavailable; install sv2v, Yosys and Python 3." >&2
    exit 2
  fi
done
sv2v rtl/xdf_sensory.sv > build/xdf_sensory_synth.v
yosys -l build/sensory-synthesis.log -p \
  'read_verilog build/xdf_sensory_synth.v; hierarchy -check -top xdf_sensory; synth -top xdf_sensory; check -assert; write_json build/sensory-yosys.json; stat'
python3 tools/summarize_synthesis.py build/sensory-yosys.json build/sensory-synthesis-summary.json xdf_sensory
{
  echo "XDF-1 sensory technology-independent Yosys synthesis: SUCCESS"
  echo "Source SHA: ${GITHUB_SHA:-local-or-untracked}"
  echo "sv2v: $(sv2v --version)"
  echo "Yosys: $(yosys -V)"
  echo "Hardware top: xdf_sensory (64 logical sensors, four physical ingress lanes)"
  echo "Not a board-mapped design, FPGA timing closure, ASIC layout, or power measurement."
} | tee build/sensory-synthesis-status.txt
