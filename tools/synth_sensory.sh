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
# Never consider an X-resolved driver conflict a successful synthesis.
if grep -Ei 'driver-driver conflict|multiple conflicting drivers' build/sensory-synthesis.log; then
  echo 'FATAL: synthesis resolved conflicting drivers; result is not hardware-valid.' >&2
  exit 1
fi
python3 tools/summarize_synthesis.py build/sensory-yosys.json build/sensory-synthesis-summary.json xdf_sensory
python3 - <<'PY_CHECK'
import json
from pathlib import Path
report=json.loads(Path('build/sensory-synthesis-summary.json').read_text())
if report['generic_sequential_cell_instances'] < 4000:
    raise SystemExit('FATAL: implausibly few state bits; the synthesis may have optimized the sensor array away')
print('Structural sensor-state sanity check: PASS')
PY_CHECK
{
  echo "XDF-1 sensory technology-independent Yosys synthesis: SUCCESS"
  echo "Source SHA: ${GITHUB_SHA:-local-or-untracked}"
  echo "sv2v: $(sv2v --version)"
  echo "Yosys: $(yosys -V)"
  echo "Hardware top: xdf_sensory (64 logical sensors, four physical ingress lanes)"
  echo "Not a board-mapped design, FPGA timing closure, ASIC layout, or power measurement."
} | tee build/sensory-synthesis-status.txt
