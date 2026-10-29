#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
for exe in sv2v yosys python3; do
  command -v "$exe" >/dev/null || { echo "Missing tool: $exe" >&2; exit 2; }
done
sv2v rtl/xdf_sensory.sv rtl/xdf_reflex.sv rtl/xdf_perception_frontend.sv > build/frontend-synth.v
yosys -l build/frontend-synthesis.log -p \
  'read_verilog build/frontend-synth.v; hierarchy -check -top xdf_perception_frontend; synth -top xdf_perception_frontend; check -assert; write_json build/frontend-yosys.json; stat'
if grep -Ei 'driver-driver conflict|multiple conflicting drivers' build/frontend-synthesis.log; then
  echo 'FATAL: conflicting drivers in perception frontend' >&2
  exit 1
fi
python3 tools/summarize_synthesis.py build/frontend-yosys.json \
  build/frontend-synthesis-summary.json xdf_perception_frontend
python3 - <<'PY_CHECK'
import json
from pathlib import Path
report=json.loads(Path('build/frontend-synthesis-summary.json').read_text())
if report['generic_sequential_cell_instances'] < 12000:
    raise SystemExit('FATAL: missing state registers in sensory+reflex frontend')
if report['modules_reachable'] < 3:
    raise SystemExit('FATAL: missing reachable sensory/reflex modules')
print('Perception frontend structural check: PASS')
PY_CHECK
{
  echo "XDF-1 perception frontend generic synthesis: SUCCESS"
  echo "Source SHA: ${GITHUB_SHA:-local-or-untracked}"
  echo "sv2v: $(sv2v --version)"
  echo "Yosys: $(yosys -V)"
  echo "No physical FPGA timing, neural inference or 500 MB/s raw-data validation."
} | tee build/frontend-synthesis-status.txt
