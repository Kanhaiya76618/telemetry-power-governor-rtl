# Micro-USB PS Bridge (PL processing preserved)

This path keeps power-governor processing in PL but uses Cora Z7 micro-USB serial by forwarding telemetry/commands through Zynq PS.

## Components

- PL RTL AXI-lite slave wrapper:
  - `vivado_final/rtl/pwr_gov_axi_lite.v`
- PS userspace UART forwarder:
  - `ps_bridge/board_uart_bridge.py`
- PS bare-metal UART forwarder (no Linux):
  - `ps_bridge/baremetal/src/main.c`

The laptop `host_app/server.py` can remain unchanged because the bridge emits the same frame format as `protocol_v1.md`.

## Vivado integration (summary)

1. Create/modify block design with Zynq PS.
2. Add `pwr_gov_axi_lite.v` as custom RTL module.
3. Connect PS `M_AXI_GP0` to module AXI-lite slave via AXI interconnect.
4. Assign module base address (default example: `0x43C00000`).
5. Generate bitstream and boot Linux on PS.

## Board-side bridge run (Linux option)

On board Linux (as root):

```bash
python3 board_uart_bridge.py --base 0x43C00000 --port /dev/ttyPS0 --baud 115200 --hz 5
```

## Board-side bridge run (No Linux option)

If you cannot boot Linux, use the standalone PS firmware path in:

- `ps_bridge/baremetal/README.md`

This keeps the same laptop app and same frame protocol.

## Laptop-side app run

On laptop:

- Use same host app in `host_app/`
- Point serial port to Cora micro-USB COM port

## Notes

- Disable conflicting serial console/getty on `/dev/ttyPS0` if needed.
- This path requires PS Linux userspace support (`python3`, `pyserial`).
- Linux is optional: bare-metal firmware is supported in `ps_bridge/baremetal/README.md`.
