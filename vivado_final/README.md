# Vivado Final Merged RTL

This folder contains a clean, merged final design based on your original repo + new Level-2 files.

## Implementation inventory

Core governor RTL designed in this project:

- `counters.v`
- `power_fsm.v`
- `reg_interface.v`
- `power_arbiter.v`
- `perf_feedback.v`
- `power_logger.v`
- `pwr_gov_top.v`

Integration RTL (also real synthesizable Verilog):

- `pwr_gov_uart_top.v`
- `uart_tx.v`
- `uart_rx.v`
- `pwr_gov_axi_lite.v`
- `pwr_gov_btn_demo_top.v`
- `workload_sim.v`

## Recommended Vivado Source Set

Add only files from `vivado_final/rtl` as Design Sources:

- `counters.v`
- `power_fsm.v`
- `reg_interface.v`
- `power_arbiter.v`
- `perf_feedback.v`
- `power_logger.v`
- `pwr_gov_top.v`

Set top module to:

- `pwr_gov_top`

Add this Constraints file:

- `vivado_final/constraints/cora_z7_07s_pwr_gov_top.xdc`

## No-Jumper Demo (btn0 + btn1)

If you want board-only demo operation without any jumper wires:

- Set top module to `pwr_gov_btn_demo_top`
- Add `vivado_final/rtl/pwr_gov_btn_demo_top.v` to Design Sources
- Add `vivado_final/rtl/workload_sim.v` to Design Sources
- Use constraints file `vivado_final/constraints/cora_z7_07s_btn_demo.xdc`

Button behavior:

- `btn0`: reset (hold to reset, release to run)
- `btn1=0`: show governor outputs (`grant_*`, `clk_en_*`)
- `btn1=1`: show telemetry diagnostics (`phase`, `alarm_*`, `phase_done`)

LED behavior:

- Telemetry source is the real `workload_sim` module (not hardcoded grant patterns)
- `LD0` / `LD1` pages are selected by `btn1`

The design cycles automatically through workload phases inside `workload_sim`.

## UART Telemetry Demo (Laptop Frontend + Backend)

Use this flow when you want the board to process telemetry and stream status to a laptop web app.

- Set top module to `pwr_gov_uart_top`
- Add these RTL files:
  - `vivado_final/rtl/pwr_gov_uart_top.v`
  - `vivado_final/rtl/workload_sim.v`
  - `vivado_final/rtl/uart_tx.v`
  - `vivado_final/rtl/uart_rx.v`
- Use constraints file `vivado_final/constraints/cora_z7_07s_uart_demo.xdc`

UART notes:

- UART settings: `115200 8N1`
- Pin map in this flow:
  - `uart_tx` -> JA[0] (Y18)
  - `uart_rx` -> JA[1] (Y19)
- Connect USB-UART adapter:
  - Adapter TX -> FPGA `uart_rx`
  - Adapter RX -> FPGA `uart_tx`
  - Adapter GND -> FPGA GND

Important hardware note:

- On Cora Z7, the micro-USB UART path is PS-side and is not directly drivable by pure PL RTL.
- The RTL in this repo uses PL pins (JA) for UART telemetry.
- If you need single micro-USB cable operation, add a PS UART bridge (PL<->PS AXI-lite + PS forwarder app).

## Micro-USB PS-Bridge Flow (Single Cable)

Use this flow when you want telemetry/control over Cora micro-USB UART without external PMOD USB-UART.

Design side:

- Add `vivado_final/rtl/pwr_gov_axi_lite.v` to Design Sources.
- Build around Zynq PS block design and connect PS `M_AXI_GP0` to the AXI-lite slave.
- Assign an AXI base address (example used by scripts: `0x43C00000`).

Software side (on board Linux):

- Run `ps_bridge/board_uart_bridge.py` to bridge AXI registers <-> `/dev/ttyPS0`.
- Script details and bring-up notes are in `ps_bridge/README.md`.

Laptop side:

- Reuse `host_app/` unchanged.
- Point serial port to the board micro-USB COM port.

Laptop app:

- Run backend + frontend from `host_app/`
- Protocol reference: `host_app/docs/protocol_v1.md`

## Step-by-step: Vivado for single USB cable (recommended)

Use this when you do not want external wiring.

1. Create a new RTL project for Cora Z7-07S.
2. Add these RTL files from `vivado_final/rtl`:

- `pwr_gov_axi_lite.v`
- `pwr_gov_top.v`
- `counters.v`
- `power_fsm.v`
- `reg_interface.v`
- `power_arbiter.v`
- `perf_feedback.v`
- `power_logger.v`
- `workload_sim.v`

3. Do not add PMOD UART files in this flow (`pwr_gov_uart_top.v`, `uart_tx.v`, `uart_rx.v`).
4. Do not use UART demo XDC in this flow.
5. Open IP Integrator and create block design `design_1`.
6. Add IP `ZYNQ7 Processing System` and run Block Automation.
7. Add module `pwr_gov_axi_lite` from project sources.
8. Run Connection Automation for `S_AXI`.
9. In Address Editor, set base address of the module to `0x43C00000`.
10. Validate design.
11. Create HDL Wrapper (`let Vivado manage wrapper`) and set wrapper as top.
12. Run Synthesis, Implementation, and Generate Bitstream.
13. Export hardware including bitstream (`.xsa`) for Vitis.

After this, continue with:

- `ps_bridge/baremetal/README.md` for Vitis app build/run
- `host_app/README.md` for Python backend/frontend run

## Simulation Files

Simulation helpers are kept in `vivado_final/sim`:

- `tb_level2.v`
- `workload_sim.v`

## Important

Do not add both the old root RTL files and these final files into the same Vivado project, because module names overlap and will cause duplicate-definition errors.
