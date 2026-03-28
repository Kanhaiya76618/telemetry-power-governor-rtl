# Laptop Host App (Frontend + Backend)

This app runs completely on the laptop and bridges browser UI to Cora Z7 over USB-UART.

It works with both:

- PMOD USB-UART adapter flow (`pwr_gov_uart_top`), and
- Single-cable micro-USB flow (PS bridge).

## 1) Install dependencies

```bash
cd host_app
python -m venv .venv
# Windows
.venv\\Scripts\\activate
pip install -r requirements.txt
```

## 2) Set serial port and run

```bash
# PowerShell example
$env:PWRGOV_PORT="COM5"
$env:PWRGOV_BAUD="115200"
python server.py
```

Git Bash example:

```bash
export PWRGOV_PORT=COM14
export PWRGOV_BAUD=115200
python server.py
```

Then open:

- http://localhost:8000

## 3) API

- `GET /api/state` -> latest decoded FPGA telemetry
- `POST /api/control` -> sends command bytes to FPGA
- `WS /ws` -> streamed telemetry updates

## 4) Command notes

Protocol details are in:

- `docs/protocol_v1.md`

## 5) UART wiring

Use `pwr_gov_uart_top` + `cora_z7_07s_uart_demo.xdc`.

Adapter wiring:

- Adapter TX -> FPGA `uart_rx`
- Adapter RX -> FPGA `uart_tx`
- Adapter GND -> FPGA GND

Do not connect 5V.

## 6) Micro-USB mode (no external UART adapter)

Use this when you want single-cable Cora micro-USB serial.

- Keep this laptop app exactly as-is.
- On board, choose one PS bridge:
  - Linux userspace: `ps_bridge/board_uart_bridge.py`
  - Bare-metal standalone (no Linux): `ps_bridge/baremetal/src/main.c`
- In Vivado, use AXI-lite PL wrapper `vivado_final/rtl/pwr_gov_axi_lite.v` connected to Zynq PS (`M_AXI_GP0`).

Reference:

- `ps_bridge/README.md`

## 7) End-to-end run checklist (Vivado + Vitis + Python)

1. Build Vivado hardware with AXI-lite wrapper (`pwr_gov_axi_lite`) and export XSA.
2. Build and run standalone firmware in Vitis using `ps_bridge/baremetal/src/main.c`.
3. Identify board COM port in Device Manager.
4. Set `PWRGOV_PORT` to that COM port and run `python server.py`.
5. Open `http://localhost:8000`.
6. Verify `GET /api/state` returns `connected=true` and increasing `frame_counter`.

## 8) Troubleshooting

- `Serial not connected` on `POST /api/control`:
  - Usually wrong COM port or COM port already in use.
  - Close any serial terminal before running this server.

- `connected=false` in `/api/state`:
  - Confirm Vitis app is running on hardware.
  - Confirm board is actually streaming data on selected COM port.

- Python package issue (`serial.tools` missing):
  - You installed `serial` package instead of `pyserial`.
  - Fix with:

```bash
python -m pip uninstall -y serial
python -m pip install -r requirements.txt
```
