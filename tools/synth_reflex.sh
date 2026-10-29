#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
for exe in sv2v yosys python3; do
  command -v "$exe" >/dev/null || { echo "Missing tool: $exe" >&2; exit 2; }
done
sv2v rtl/xdf_reflex.sv > build/reflex-synth.v
yosys -l build/reflex-synthesis.log -p \
  'read_verilog build/reflex-synth.v; hierarchy -check -top xdf_reflex; synth -top xdf_reflex; check -assert; write_json build/reflex-yosys.json; stat'
if grep -Ei 'driver-driver conflict|multiple conflicting drivers' build/reflex-synthesis.log; then
  echo 'FATAL: conflicting drivers in reflex RTL' >&2
  exit 1
fi
python3 tools/summarize_synthesis.py build/reflex-yosys.json \
  build/reflex-synthesis-summary.json xdf_reflex
python3 - <<'PY_CHECK'
import json
from pathlib import Path
report=json.loads(Path('build/reflex-synthesis-summary.json').read_text())
if report['generic_sequential_cell_instances'] < 450:
    raise SystemExit('FATAL: rule bank or both output buffers lost in synthesis')
if report['generic_cell_instances'] < 600:
    raise SystemExit('FATAL: reflex control logic unexpectedly missing')
print('Rule-bank and dual-output state sanity check: PASS')
PY_CHECK
{
  echo "XDF-1 programmable reflex generic synthesis: SUCCESS"
  echo "Source SHA: ${GITHUB_SHA:-local-or-untracked}"
  echo "sv2v: $(sv2v --version)"
  echo "Yosys: $(yosys -V)"
  echo "Device mapping, FPGA timing, neural inference, and physical data throughput NOT measured."
} | tee build/reflex-synthesis-status.txt
