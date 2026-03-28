# Cora Z7 Micro-USB vs PL UART (Important)

## Why direct RTL->micro-USB does not work

On Cora Z7, the micro-USB UART/JTAG interface is connected to the Zynq Processing System (PS) side, not directly to PL FPGA IO pins.

That means:

- Pure PL RTL modules (`uart_tx.v`, `uart_rx.v`) cannot directly drive the board micro-USB serial path.
- PL UART must use PL pins (for example JA/JB/user_dio) and an external USB-UART adapter.

## What the current RTL supports

Current design top for laptop bridge:

- `vivado_final/rtl/pwr_gov_uart_top.v`

This uses PL UART pins in:

- `vivado_final/constraints/cora_z7_07s_uart_demo.xdc`

## If you require _micro-USB cable only_

You need a PS bridge path:

1. Keep governor processing in PL.
2. Expose status/control via PL<->PS interface (AXI-lite register bank).
3. Run a tiny PS app/firmware that reads PL registers and writes to PS UART.
4. Laptop reads that micro-USB COM port.

The PS app can be either:

- Linux userspace script (`ps_bridge/board_uart_bridge.py`), or
- Bare-metal Vitis standalone firmware (`ps_bridge/baremetal/src/main.c`).

This still keeps frontend/server on laptop and board-side processing in PL, but requires minimal PS software.

## Recommendation

For fastest working demo now:

- Use existing PL UART over JA pins + external USB-UART adapter.

For final polish with single micro-USB cable:

- Add AXI-lite register wrapper + PS UART forwarder.
