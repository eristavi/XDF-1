#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
for exe in sv2v yosys python3; do
  command -v "$exe" >/dev/null || { echo "Missing tool: $exe" >&2; exit 2; }
done
sv2v rtl/xdf_pkg.sv rtl/xdf_tile.sv rtl/xdf_router.sv rtl/xdf_top.sv \
     rtl/xdf_sensory.sv rtl/xdf_sensor_pipeline.sv > build/pipeline-synth.v
yosys -l build/pipeline-synthesis.log -p \
  'read_verilog build/pipeline-synth.v; hierarchy -check -top xdf_sensor_pipeline; synth -top xdf_sensor_pipeline; check -assert; write_json build/pipeline-yosys.json; stat'
# Yosys has previously optimized a broken dynamically indexed array into X
# through a conflicting-driver resolution. Reject this even on exit code zero.
if grep -Ei 'driver-driver conflict|multiple conflicting drivers' build/pipeline-synthesis.log; then
  echo 'FATAL: conflicting drivers in complete sensory+compute pipeline' >&2
  exit 1
fi
python3 tools/summarize_synthesis.py build/pipeline-yosys.json \
        build/pipeline-synthesis-summary.json xdf_sensor_pipeline
python3 - <<'PY_CHECK'
import json
from pathlib import Path
report=json.loads(Path('build/pipeline-synthesis-summary.json').read_text())
if report['generic_sequential_cell_instances'] < 14000:
    raise SystemExit('FATAL: implausibly few sequential cells; incomplete or X-resolved design?')
if report['modules_reachable'] < 6:
    raise SystemExit('FATAL: missing reachable processor/sensory components')
print('Integrated structural coverage check: PASS')
PY_CHECK
{
  echo "Integrated sensor-to-dataflow generic synthesis: SUCCESS"
  echo "Source SHA: ${GITHUB_SHA:-local-or-untracked}"
  echo "sv2v: $(sv2v --version)"
  echo "Yosys: $(yosys -V)"
  echo "No FPGA target, timing closure, power/energy measurement or silicon claim."
} | tee build/pipeline-synthesis-status.txt
