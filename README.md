# Telemetry Power Governor RTL

This repository contains a telemetry-driven power governor implemented in Verilog RTL, plus complete board and host integration for live telemetry/control demos.

## What is implemented

### A) Real designed RTL (core governor datapath and policy)

These are the actual Verilog modules implementing telemetry processing, policy, arbitration, and feedback:

- `vivado_final/rtl/counters.v`
- `vivado_final/rtl/power_fsm.v`
- `vivado_final/rtl/reg_interface.v`
- `vivado_final/rtl/power_arbiter.v`
- `vivado_final/rtl/perf_feedback.v`
- `vivado_final/rtl/power_logger.v`
- `vivado_final/rtl/pwr_gov_top.v`
- `vivado_final/rtl/workload_sim.v`

### B) Verilog integration/transport wrappers (still real RTL)

These are also synthesizable Verilog modules, but they serve as wrappers/interfaces around the core governor:

- `vivado_final/rtl/pwr_gov_uart_top.v` (PMOD UART demo wrapper)
- `vivado_final/rtl/uart_tx.v`
- `vivado_final/rtl/uart_rx.v`
- `vivado_final/rtl/pwr_gov_axi_lite.v` (PS bridge AXI-lite wrapper)
- `vivado_final/rtl/pwr_gov_btn_demo_top.v` (no-jumper LED/button demo)

### C) Software bridge + web app

- `ps_bridge/baremetal/src/main.c` (Vitis standalone PS firmware, no Linux)
- `ps_bridge/board_uart_bridge.py` (Linux userspace PS bridge)
- `host_app/server.py` and `host_app/static/*` (backend + frontend dashboard)

## Recommended run flow (single USB cable, no external wiring)

This is the recommended end-to-end flow for Cora Z7 when you want data/control through micro-USB only.

1. Build hardware in Vivado using `pwr_gov_axi_lite` in a Zynq block design.
2. Export XSA and build/run standalone app in Vitis using `ps_bridge/baremetal/src/main.c`.
3. Run Python backend/frontend from `host_app` on your laptop.

Detailed instructions are in:

- `vivado_final/README.md`
- `ps_bridge/baremetal/README.md`
- `host_app/README.md`

## Alternative run flow (external USB-UART adapter)

If you prefer PL UART over PMOD pins:

- Use top `pwr_gov_uart_top`
- Use constraint `vivado_final/constraints/cora_z7_07s_uart_demo.xdc`

This mode requires external TX/RX/GND wiring to JA pins.

## Protocol

Binary frame protocol and control command mapping:

- `host_app/docs/protocol_v1.md`

## Notes

- The governor logic is real Verilog RTL from this project.
- The UART/AXI modules are also real RTL, used as integration wrappers.
- The micro-USB path on Cora Z7 is PS-side, so single-cable mode uses PS firmware/software bridge.
