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

## Verified results (GitHub Actions, 29 October 2026)

- Validated branch commit: `ddef1a08465b0af41e2df8241507794c12081195`.
- [Passing CI run](https://github.com/eristavi/XDF-1/actions/runs/40909494109): `python-and-rtl` and `generic-synthesis` both successful.
- 23 Python tests passed; 1,000 deterministic randomized RTL simulation cases passed.
- Verilator lint/build no longer reports the previous inferred latch, timescale, or file-handle width warnings.
- sv2v version: `0.0.13`; Yosys version: `0.33`.
- Yosys generic leaf-cell instances (hierarchy expanded): **90,085** total, including **5,183 sequential** and **84,902 other generic cells**, across **6 reachable module types**.
- Yosys emitted `Replacing memory ... with list of registers` warnings for operand/configuration arrays. This is a significant FPGA optimization target, not evidence of usable inferred block RAM.

These figures are a **baseline**; they do not establish device fit, LUT utilization,
clock frequency, SRAM use, physical gate area, or power. Full evidence is available
in the workflow's `generic-synthesis-evidence` artifact.

## Remaining engineering work

FPGA board selection, host transport bridge, synchronized reset, pin constraints,
device-mapped synthesis and static timing, hardware bring-up, and silicon PDK mapping.
The current run is not an ASIC implementation or foundry signoff.
