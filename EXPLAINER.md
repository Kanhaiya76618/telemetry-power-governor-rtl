EXPLAINER 
==========

Short story
-----------

This project is like a little helper for a computer chip. The helper watches how busy the chip is and how hot it gets. Then it tells the chip to go faster when work is needed and slower when it can rest. Faster finishes work but uses more power. Slower saves battery.

Think of it like a bike: when you pedal hard you go fast (high power). If you are tired or the bike is too hot, you pedal easy (low power).

Main parts (very short)
-----------------------

- `counters.v`: a watcher that counts how many times the chip is busy or stuck. Every little time block it rings a bell called `window_done`.
- `power_fsm.v`: the brain. When the bell rings, the brain looks at the counts and temperature and chooses one of a few states: SLEEP, LOW, ACTIVE, TURBO.
- `reg_interface.v`: a small memory and door that keeps settings (like the temperature limit) and makes clean outputs for the rest of the chip.
- `power_arbiter.v`: a referee that shares limited power between two parts (A and B) when both want more power.
- `pwr_gov_axi_lite.v`: a helper that lets a PC program registers over AXI (used for tests and demos). It can also run a fake workload simulator inside the FPGA so you can test without real inputs.
- `tb_*.v`: test files that pretend to be the world so we can check the helper works.
- `tools/generate_epv.py`: turns simulator logs into pretty pictures so you can see what happened.

How it works — step by step (simple)
-------------------------------------

1. The watcher (`counters.v`) counts busy cycles and stalled cycles inside a short time window (100 ticks).
2. When the window ends, it rings `window_done` and sends the counts to the brain (`power_fsm.v`).
3. The brain checks:
   - Is the chip too hot? If yes, tell it to slow down.
   - Is the activity high? If yes, maybe speed up.
   - Is the activity low? If yes, maybe slow down.
4. The brain uses a few helpers:
   - Dwell (hysteresis): it may wait a few windows before changing to make sure the change is real.
   - EWMA (a soft average): a gentle guess of future activity so we can act early.
   - Workload classifier: a tiny guess about what kind of job the chip is doing.
5. The `reg_interface.v` stores the chosen power state and gives an output `clk_en` (turn on/off the clock) and `thermal_alarm`.

Important ideas (very small words)
----------------------------------

- EWMA: it is like a running score that slowly follows what happened, not jumping at every blip. Think of it as a memory that remembers recent activity.
- Hysteresis (dwell): like waiting 3 rings of a bell before you jump. This stops flip‑flopping.
- Thermal override: if the chip is too hot, always slow down right away.

AXI register map (plain)
------------------------

This file `pwr_gov_axi_lite.v` has some registers you can read or write. Here are the important ones (addresses in hex):

- `0x00` CTRL: control bits

  - bit 0 = `host_mode` (0 = use the built‑in fake workload simulator; 1 = accept inputs from host registers)
  - bit 1 = `use_ext_budget` (when set, the external budget register is used)
- `0x04` BUDGET: 3‑bit number that tells the arbiter how much total budget the chip can give (0..7)
- `0x08` REQ / STATUS: when writing this register you set `req_a` and `req_b` (requests from subsystem A and B). When reading, you can see grants, clocks and alarms.
- `0x0C` IO: read shows `activity` and `stall` signals and also `temp` values for each side (for quick polling)
- `0x10` TEMP_A and `0x14` TEMP_B: 7‑bit temperature values for each side (write to pretend a temperature for tests)

Note: Use `host_mode` if you want to drive signals from a test script instead of the internal fake workload simulator.

Top-level signals (what the brain sees and sends)
-------------------------------------------------

The top module (`pwr_gov_top`) connects small things. Here are the important names and what they mean:

- Inputs (what the brain sees):

  - `act_a`, `stall_a`, `req_a`, `temp_a`  — activity, stalls, request and temperature for side A
  - `act_b`, `stall_b`, `req_b`, `temp_b`  — same for side B
  - `ext_budget_in`, `use_ext_budget`      — optional external budget control
- Outputs (what the brain tells others):

  - `grant_a[1:0]`, `grant_b[1:0]`         — how much power is given to A and B (two bits each)
  - `clk_en_a`, `clk_en_b`                — turn clocks on or off to save power
  - `current_budget[2:0]`, `budget_headroom` — budget numbers for monitoring
  - `system_efficiency[9:0]`              — a small number showing efficiency (for UI)
  - `alarm_a`, `alarm_b`                  — thermal alarms

How to run the tests (copy/paste)
---------------------------------

These commands run the simple simulators using Icarus Verilog. They make a file called `dump.vcd` that you can open with GTKWave or convert to PNG.

```bash
# Run the FSM test (also runs counters and reg_interface)
iverilog -g2012 -o tb_power_fsm.vvp power_fsm.v reg_interface.v counters.v tb_power_fsm.v
vvp tb_power_fsm.vvp

# View waveforms:
gtkwave dump.vcd

# Make PNG graphs (uses Python script already in repo):
python3 tools/generate_epv.py
```

How to put it on a real FPGA (very short)
-----------------------------------------

1. Make a small top file (`top_wrapper.v`) that maps the signals you want to real pins (LEDs, switches).
2. Edit a `.xdc` file with the pin numbers for your board (which LED is which pin).
3. Use Vivado to synthesize and write the bitstream and then program the board.

If you tell me your FPGA board model (for example: Nexys A7, Basys 3, or a Xilinx Zynq board), I can add a ready `top_wrapper.v` and a sample `.xdc` for that board.

Quick places to look in the code
--------------------------------

- `power_fsm.v` — the rules and decisions live here (this is the brain).
- `counters.v` — how we count activity and stalls.
- `reg_interface.v` — where settings are stored and the `thermal_alarm` is produced.
- `power_arbiter.v` — divides power between A and B when needed.

Want me to also commit this change and push it? Or add a board `top_wrapper` and `.xdc` now? Tell me which option you prefer.

---

File: EXPLAINER.md updated in repo root.
