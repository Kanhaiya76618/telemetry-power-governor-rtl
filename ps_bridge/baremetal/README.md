# Bare-Metal PS Bridge (No Linux Required)

Use this path when you cannot boot Linux on Cora Z7 but still want single-cable micro-USB telemetry.

## What stays the same

- Governor processing remains in PL (`pwr_gov_top` inside AXI-lite wrapper).
- Laptop app remains unchanged (`host_app/server.py`).
- UART protocol stays `protocol_v1.md` compatible.

## Files

- Firmware source: `ps_bridge/baremetal/src/main.c`
- PL AXI-lite bridge wrapper: `vivado_final/rtl/pwr_gov_axi_lite.v`

## Vivado hardware setup

1. Build a Zynq block design.
2. Add `pwr_gov_axi_lite.v` as RTL module.
3. Connect PS `M_AXI_GP0` -> AXI interconnect -> `pwr_gov_axi_lite` slave.
4. Assign AXI base address (default expected: `0x43C00000`).
5. Generate bitstream and export hardware (`.xsa`) to Vitis.

## Vitis firmware setup (standalone)

1. Create platform from exported `.xsa`.
2. Create a standalone domain/application (C).
3. Replace generated `main.c` with `ps_bridge/baremetal/src/main.c`.
4. Build and run on hardware.

First-time click-path (Vitis):

1. `File -> New -> Platform Project`.
2. Select the exported `.xsa`.
3. `File -> New -> Application Project`.
4. Platform: choose the one you just created.
5. Processor: `ps7_cortexa9_0`.
6. Domain OS: `standalone`.
7. Template: `Empty Application` (or `Hello World`, then replace `main.c`).
8. Paste `ps_bridge/baremetal/src/main.c` into application `src/main.c`.
9. Right-click app -> `Build Project`.
10. Right-click app -> `Run As -> Launch on Hardware (System Debugger)`.

## Important macros

`main.c` auto-detects these if they exist in `xparameters.h`:

- `XPAR_PWR_GOV_AXI_LITE_0_S_AXI_BASEADDR`
- `XPAR_XUARTPS_0_DEVICE_ID`

If your design uses different names, set manually at build time, for example:

- `PWR_GOV_BASEADDR=0x43C00000`
- `PWR_GOV_UART_DEVICE_ID=<id>`

## Laptop run

On laptop, run the existing host app and select the Cora micro-USB COM port:

```powershell
cd host_app
$env:PWRGOV_PORT="COM5"
$env:PWRGOV_BAUD="115200"
python server.py
```

Open `http://localhost:8000`.

## Notes

- If no telemetry appears, verify the COM port and baud first.
- Ensure the PS UART chosen by firmware maps to the USB-UART channel you are using.
- If Linux is not used, ignore `board_uart_bridge.py` and use only this bare-metal firmware.
- Firmware runs forever and continuously streams binary frames; this is expected behavior.
- Startup messages from firmware:
  - `PwrGov bare-metal bridge start`
  - `AXI base: 0x43C00000`
