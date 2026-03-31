# Telemetry Power Governor RTL

This repository contains a **telemetry-driven power governor implemented in Verilog RTL**, along with complete board and host integration for real-time telemetry monitoring and control.

---

## Project Overview

The project focuses on **hardware-level power management** using RTL design techniques. It processes telemetry data, applies control policies, and dynamically regulates system behavior for efficient power utilization.

---

## Contributors

* Arnav Angarkar
* Kanhaiya Mehta
* Aakash Pathrikar
* Rayyan Shaikh
* Ankit Dash

---

## Contributions by Kanhaiya Mehta

* Contributed to the development and integration of **RTL modules** for telemetry-based power control
* Assisted in **debugging and verification** of RTL design using **Xilinx Vivado**
* Identified and resolved:

  * Signal synchronization issues
  * Logical errors in power control FSM
* Supported **functional validation** through simulation and waveform analysis
* Collaborated with team members to improve **design stability and performance**

---

## What is Implemented

### A) Core RTL Design (Governor Datapath & Policy)

These Verilog modules implement telemetry processing, control policies, arbitration, and feedback mechanisms:

* `vivado_final/rtl/counters.v`
* `vivado_final/rtl/power_fsm.v`
* `vivado_final/rtl/reg_interface.v`
* `vivado_final/rtl/power_arbiter.v`
* `vivado_final/rtl/perf_feedback.v`
* `vivado_final/rtl/power_logger.v`
* `vivado_final/rtl/pwr_gov_top.v`
* `vivado_final/rtl/workload_sim.v`

---

### B) Integration & Interface Modules (RTL Wrappers)

Synthesizable Verilog modules used for system-level integration:

* `vivado_final/rtl/pwr_gov_uart_top.v` (PMOD UART demo wrapper)
* `vivado_final/rtl/uart_tx.v`
* `vivado_final/rtl/uart_rx.v`
* `vivado_final/rtl/pwr_gov_axi_lite.v` (AXI-Lite interface for PS bridge)
* `vivado_final/rtl/pwr_gov_btn_demo_top.v` (LED/button demo without jumpers)

---

### C) Software Bridge & Web Application

* `ps_bridge/baremetal/src/main.c` (Vitis standalone firmware)
* `ps_bridge/board_uart_bridge.py` (Linux userspace bridge)
* `host_app/server.py` and `host_app/static/*` (Backend + Web Dashboard)

---

## Recommended Run Flow (Single USB Setup)

For Cora Z7 using only micro-USB:

1. Build hardware in Vivado using `pwr_gov_axi_lite` in a Zynq block design
2. Export XSA and run standalone application in Vitis
3. Launch backend and frontend from `host_app` on host machine

Detailed guides:

* `vivado_final/README.md`
* `ps_bridge/baremetal/README.md`
* `host_app/README.md`

---

## Alternative Run Flow (External UART)

* Use top module: `pwr_gov_uart_top`
* Apply constraints: `vivado_final/constraints/cora_z7_07s_uart_demo.xdc`

Requires external TX/RX/GND connections via PMOD pins.

---

## Protocol

Binary frame protocol and control mapping:

* `host_app/docs/protocol_v1.md`

---

## Key Highlights

* Real **hardware-level power governance implementation**
* Modular RTL design with scalable architecture
* Integration of **hardware + software + web interface**
* Emphasis on **debugging, validation, and system stability**

---

## Notes

* Core governor logic is implemented in **Verilog RTL**
* UART and AXI modules serve as **integration wrappers**
* Micro-USB communication uses **PS-side firmware/software bridge**
