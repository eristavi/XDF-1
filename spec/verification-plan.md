# M1 verification and synthesis plan

## Test layers

1. **Pure Python contract (executed):** 1000 randomized cases, two simultaneously active tags, fixed examples, wraparound, different operand orders, invalid graph rejection, reset, invalid input port, invalid flags, and duplicate operand detection. `make python-test`.
2. **Generated cross-check vectors (generated):** `tools/generate_vectors.py` derives 1000 expected results using the reference model and writes `tb/reference_vectors.txt`. Each line: 5 unsigned 32-bit hexadecimal words (`A B C D EXPECTED`).
3. **SystemVerilog RTL integration testbench (provided, execution pending HDL tools):** two concurrent tags, arbitrary interleaving, input stall and output hold, invalid port, invalid config, 1000 generated vectors, midrun reset. `make rtl-sim` requires Verilator, a C++ toolchain, and GNU Make.
4. **SV lint (provided, pending tool):** `make rtl-lint` checks the same source against Verilator.
5. **Generic synthesis (provided, pending tools):** `make synth` translates SV with sv2v and runs Yosys technology-independent synthesis. It writes `build/synthesis.log`, `build/yosys.json`, `reports/synthesis-status.txt` **only on actual success**.
6. **FPGA synthesis, static timing, physical ASIC area/power:** out of scope for M1; dependent on choosing hardware platform/PDK, clocks, library and memory models.

## Metrics to record on toolchain-equipped machine

- Source hash and simulator / synthesis tool version.
- Directed and randomized vectors executed; count of pass/fail cases.
- Total simulation cycles; min/max/average cycles per graph.
- Generic combinational/sequential cells after synthesis (not equivalent to silicon area).
- Maximum synthesis memory usage and tool warnings.
- Later: mapped clock frequency, critical path, dynamic switching activity and power estimates.

## Important restrictions

- The 1000 randomized vectors are **not** evidence that the RTL has passed until the SV testbench is run and exits with PASS.
- Synthesis scripts must not invent cell counts when tools are missing.
- A successful Yosys synthesis does not prove correct silicon behavior or meet timing, PDK, DRC, LVS, antenna, or signoff requirements.