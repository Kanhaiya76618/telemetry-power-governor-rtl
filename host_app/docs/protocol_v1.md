# PwrGov UART Protocol v1

> Transport note for Cora Z7:
> This protocol is carried by PL UART pins (JA in current constraints) with an external USB-UART adapter.
> Board micro-USB UART is PS-side and cannot be directly driven by pure PL RTL.

## Link settings

- UART: `115200 8N1`
- Direction:
  - FPGA -> Laptop: periodic telemetry frames (binary)
  - Laptop -> FPGA: command bytes (binary)

## Telemetry frame (16 bytes)

- Byte 0: `0xAA`
- Byte 1: `0x55`
- Byte 2: `frame_counter_lsb`
- Byte 3: `frame_counter_msb`
- Byte 4: flags
  - bit0: `host_mode` (0=internal workload_sim, 1=host-injected)
  - bit1: `alarm_a`
  - bit2: `alarm_b`
  - bit3: `clk_en_a`
  - bit4: `clk_en_b`
- Byte 5: grants
  - bits[1:0]: `grant_a`
  - bits[3:2]: `grant_b`
- Byte 6: budget pack
  - bits[2:0]: `current_budget`
  - bits[5:3]: `budget_headroom`
- Byte 7: `efficiency_lsb`
- Byte 8: `efficiency_msb` (bits[1:0] valid)
- Byte 9: `temp_a`
- Byte10: `temp_b`
- Byte11: IO flags
  - bit0: `stall_a`
  - bit1: `act_a`
  - bit2: `stall_b`
  - bit3: `act_b`
- Byte12: req pack
  - bits[1:0]: `req_a`
  - bits[3:2]: `req_b`
- Byte13: `workload_phase` (`ws_phase`)
- Byte14: checksum = XOR(Byte2..Byte13)
- Byte15: `0x0D`

## Commands (Laptop -> FPGA)

Single-byte commands unless noted.

### Mode and budget

- `0xA0`: set internal telemetry mode (`host_mode=0`)
- `0xA1`: set host-injected telemetry mode (`host_mode=1`)
- `0xF0`: `host_use_ext_budget=0`
- `0xF1`: `host_use_ext_budget=1`
- `0xB0`..`0xB7`: set `host_budget = cmd & 0x07`

### Requests

- `0xC0`..`0xC3`: set `req_a = cmd & 0x03`
- `0xC4`..`0xC7`: set `req_b = cmd & 0x03`

### Activity/stall bits

- `0xD0`: `act_a=0`
- `0xD1`: `act_a=1`
- `0xD2`: `stall_a=0`
- `0xD3`: `stall_a=1`
- `0xD4`: `act_b=0`
- `0xD5`: `act_b=1`
- `0xD6`: `stall_b=0`
- `0xD7`: `stall_b=1`

### Temperatures (2-byte commands)

- `0xE0` then `<value 0..127>`: set `temp_a`
- `0xE1` then `<value 0..127>`: set `temp_b`

## Telemetry rate

- Default in RTL: `5 Hz`
