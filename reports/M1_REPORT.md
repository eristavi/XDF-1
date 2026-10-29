# XDF-1 M1 engineering verification report

**Date:** 2026-10-29  
**Release classification:** `M1-0.1-pre-rtl-validation`  
**Important:** This is a source-code prototype, not a validated or fabricated semiconductor chip.

## Completed and actually verified

| Item | Result | Evidence |
|---|---|---|
| Architecture / token and graph semantics | Documented | `spec/architecture.md` |
| Independent Python reference model | Built and executed | `python/xdf1/`, `reports/reference-example.json` |
| Python model and graph verification | **20 passed, 0 failed** | `reports/python-test.log` |
| Randomized reference execution | **1,000 cases passed** | `tests/test_reference.py` |
| Python router model under randomized stalls | **1,000 tokens delivered without loss or duplication** | `tests/test_router.py` |
| Repeatable RTL test vector generation | **1,000 vectors produced** | `tb/reference_vectors.txt` |
| SystemVerilog processing tiles | Source written | `rtl/xdf_tile.sv`; **unvalidated RTL** |
| SystemVerilog routing and backpressure | Source written | `rtl/xdf_router.sv`; **unvalidated RTL** |
| SystemVerilog top-level control and host interface | Source written | `rtl/xdf_top.sv`; **unvalidated RTL** |
| SystemVerilog directed and random testbench | Source written | `tb/tb_xdf_top.sv`; **not executed** |
| Synthesis recipe | Source written | `tools/synth.sh`; **not executed** |

## Toolchain blockers

The current execution container does not include Verilator, sv2v or Yosys. Lint, hardware simulation and synthesis commands were attempted and returned a missing-tool error (see `reports/*-attempt.log`). No HDL compilation was performed and **no gate count, timing, resource use, or ASIC area number has been measured**.

A GitHub Actions workflow in `.github/workflows/verify.yml` is supplied to run Python and Verilator tests automatically on a standard Ubuntu runner after this project is added to a repository. A CI workflow file does not by itself establish that the tools have succeeded.

## Required before declaring M1 complete

1. Run `make rtl-lint` using Verilator; resolve all syntax and important lint warnings.
2. Run `make rtl-sim` with the supplied testbench; observe the complete RTL regression pass.
3. Run `make synth` using sv2v and Yosys; preserve the actual cell statistics and netlist.
4. Review the generated hardware structure and simulation coverage, including reset and backpressure.
5. Commit the exact validated source revision and results, then plan FPGA target selection.

## Reproducibility

- `make python-test`: executes Python verification.
- `make reference`: compiles the reference graph and emits expected `10`.
- `make vectors`: regenerates 1,000 deterministic hardware vectors.
- `make rtl-lint`, `make rtl-sim`: require Verilator.
- `make synth`: requires sv2v and Yosys.

Exact RTL file SHA-256 hashes, Python tool versions and machine-readable statuses are in `reports/verification-summary.json`.