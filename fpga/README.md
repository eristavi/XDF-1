# FPGA readiness gate - XDF-1 v0.1

This folder is a platform-neutral FPGA *planning* area, not a validated FPGA bitstream.
Technology-independent Yosys synthesis is a prerequisite, **not** an FPGA timing or board validation result.

## Current interface

The `xdf_top` core currently exposes parallel configuration, 64-bit token ingress,
64-bit result egress, error signals, and debug controls. It is an *internal module*,
not a practical set of physical board connectors for most development boards.

## Minimum platform integration before an FPGA claim

1. Pick an exact FPGA board and part number, available block RAM and I/O resources.
2. Implement a clocked host transport bridge (e.g., UART or SPI), framing the token,
   configuration, BEGIN, error and result transactions. Define byte ordering.
3. Provide a reset synchronizer appropriate for the target clock and reset source.
4. Add a board-specific top module and constraints (clock definition, pin assignments,
   I/O voltage standards and any required false paths).
5. Run device-mapped synthesis, place and route, and static timing analysis; report
   LUTs, registers, RAMs, critical paths and achieved clock frequency.
6. Test host backpressure, tags, reset, real I/O and long-duration randomized runs
   on actual hardware before claiming FPGA functional validation.

## Engineering boundaries

- No vendor board or pinout is selected by this milestone.
- No serial bridge is included yet; connecting the wide test harness directly to
  physical pins is not recommended.
- The current RTL uses arrays for operand and configuration state; their conversion
  to FPGA registers or RAM depends on synthesis and inferred memory characteristics.
- No ASIC PDK, power estimation, tapeout-ready timing or standard-cell area is provided.

Review `build/synthesis-summary.json` from a successful GitHub Actions synthesis
artifact for technology-independent counts. Those counts are not FPGA LUTs.
