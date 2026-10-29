#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
for tool in sv2v yosys; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    echo "NOT RUN: $tool is unavailable. Install sv2v and Yosys for technology-independent synthesis." | tee reports/synthesis-status.txt
    exit 2
  fi
done
# sv2v translates SystemVerilog packages and multidimensional logic to Verilog.
sv2v rtl/xdf_pkg.sv rtl/xdf_tile.sv rtl/xdf_router.sv rtl/xdf_top.sv > build/xdf1_synth.v
yosys -l build/synthesis.log -p 'read_verilog build/xdf1_synth.v; hierarchy -check -top xdf_top; synth -top xdf_top; stat; write_json build/yosys.json'
{
  echo "TECHNOLOGY-INDEPENDENT YOSYS SYNTHESIS COMPLETED"
  echo "No ASIC PDK, timing corner, clock target or cell library was used."
  echo "See build/synthesis.log for generic cell counts, and build/yosys.json for netlist."
  tail -n 45 build/synthesis.log
} | tee reports/synthesis-status.txt
