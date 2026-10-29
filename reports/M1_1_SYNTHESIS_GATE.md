# M1.1 - synthesis and FPGA-readiness gate

**Purpose:** preserve M1 behavioral correctness while running a repeatable generic
synthesis build and removing the first known HDL lint warnings.

## Gates

- Python architectural tests remain green, including summary reporter tests.
- Verilator RTL lint has no inferred-latch/timescale/testbench width warnings.
- Verilator integration simulation reproduces the M1 directed and 1000-case run.
- sv2v -> Yosys runs successfully with `check -assert` enabled.
- A machine-readable `build/synthesis-summary.json` accompanies synthesis log evidence.
- Platform-specific FPGA I/O and timing constraints are explicitly deferred until a
  board and clock target have been selected.

## Synthesis output

GitHub Actions job `generic-synthesis` uploads `generic-synthesis-evidence` containing
`synthesis.log`, `synthesis-status.txt`, and `synthesis-summary.json`.
The JSON enumerates **generic leaf-cell instances across the module hierarchy**;
its totals are not transistor count, die area, energy consumption, or FPGA LUT count.

## Remaining engineering work

FPGA board selection, host transport bridge, synchronized reset, pin constraints,
device-mapped synthesis and static timing, hardware bring-up, and silicon PDK mapping.
The current run is not an ASIC implementation or foundry signoff.
