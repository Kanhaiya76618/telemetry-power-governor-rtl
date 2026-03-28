Power Management Module — Audit & Implementation Report
======================================================

**Summary**

- Implemented a 4-state power governor and surrounding infrastructure covering the hackathon rubric P1–P6. A multi-module arbiter (`power_arbiter.v`) and integrated testbench were added to demonstrate Level‑2 budgeting.
- Key features added: `power_fsm` (P1), thermal throttling hooks and configurable threshold in `reg_interface` (P2), hysteresis/dwell counters to avoid oscillation (P3), EWMA workload predictor (P4), per-window workload classification (P5), and `power_arbiter` (P6).
- All testbenches (`tb_counters.v`, `tb_reg_interface.v`, `tb_power_fsm.v`, `tb_power_arbiter_direct.v`) were updated or added and pass with Icarus Verilog on macOS.

**Repository files**

- Overview and important modules:
  - [counters.v](counters.v) — 100-cycle observation window, produces `activity_count`, `stall_count`, `window_done`, `cycle_count`.
  - [reg_interface.v](reg_interface.v) — register interface, simulated inputs, thermal threshold register, `thermal_alarm`, and `clk_en` policy.
  - [power_fsm.v](power_fsm.v) — FSM governor (P1) with thermal override (P2), dwell/hysteresis (P3), EWMA (P4), workload classifier (P5).
  - [tb_counters.v](tb_counters.v), [tb_reg_interface.v](tb_reg_interface.v), [tb_power_fsm.v](tb_power_fsm.v) — testbenches that verify behavior and produce `dump.vcd`.

**Design overview & connections**

- High-level flow:
  - `counters.v` observes incoming activity/stall signals for a fixed window (100 cycles), counting active and stalled cycles.
  - At the end of each window `window_done` pulses one clock cycle; the `power_fsm` evaluates the measured counts (and the thermal alarm) and issues a `power_state_out`.
  - `reg_interface.v` latches `power_state_in`, provides `clk_en` to downstream logic, and implements the thermal threshold register and `thermal_alarm` output.

- Signals of interest:
  - `activity_count[6:0]`, `stall_count[6:0]` — raw per-window counts from `counters.v`.
  - `window_done` — single-cycle pulse, handshake for `power_fsm` evaluation.
  - `temp_in[6:0]`, `thermal_thresh_in[6:0]`, `thermal_alarm` — thermal inputs/outputs handled in `reg_interface`.
  - `power_state_in/out[1:0]` — SLEEP(00), LOW_POWER(01), ACTIVE(10), TURBO(11).
  - `ewma_out[6:0]`, `workload_class[1:0]` — new outputs from `power_fsm` (predictor & classifier).

**Module details and algorithms**

- `counters.v` (observation window)
  - Window length: 100 cycles (hardcoded). Internally `cycle_count` runs 0..99.
  - `activity_count` and `stall_count` increment on cycles where their inputs are 1 (they can both increment the same cycle).
  - On `cycle_count == 99` the module resets `cycle_count`, clears both counters, and pulses `window_done` for exactly one cycle (guaranteed single-cycle pulse for safe FSM sampling).

- `reg_interface.v` (register interface & thermal)
  - Inputs: `activity_in`, `stall_in`, `temp_in`, `power_state_in`, `thermal_thresh_in`.
  - Outputs: registered `power_state_out`, `activity_out`, `stall_out`, `temp_out`, `clk_en`, `thermal_thresh_out`, `thermal_alarm`.
  - Thermal alarm logic: `thermal_alarm <= (temp_in >= thermal_thresh_in) ? 1 : 0;` — alarm is a registered output (1 cycle later), preventing combinational glitches.
  - `clk_en` policy:
    - `SLEEP` → `clk_en = 0`.
    - `LOW_POWER` → `clk_en = activity_in` (clock gated on demand).
    - `ACTIVE`/`TURBO` → `clk_en = 1` (clock always enabled).
  - Reset values: default `thermal_thresh_out = 85`°C on reset.

- `power_fsm.v` (governor)
  - State encoding: `STATE_SLEEP=00`, `STATE_LOW_POWER=01`, `STATE_ACTIVE=10`, `STATE_TURBO=11`.
  - Thresholds (localparams):
    - `ACT_HIGH = 75` (≥75/100 cycles considered heavy).
    - `ACT_LOW  = 20` (<20/100 cycles considered light).
    - `STALL_HIGH = 50` (≥50 stalls blocks upscale).
  - Core rules evaluated when `window_done` pulses:
    1. Thermal override (highest priority): if `thermal_alarm == 1` then force `power_state_out <= STATE_LOW_POWER` (if higher).
    2. Upscale if workload is heavy AND not stalled: either raw `activity_count >= ACT_HIGH` OR predicted `ewma_out >= ACT_HIGH`, and `stall_count < STALL_HIGH`. FSM steps up by one state per window (no jumps) unless already at TURBO.
    3. Downscale if `activity_count < ACT_LOW`. FSM steps down by one state per window.
    4. Otherwise hold state.

  - Hysteresis / dwell guard (P3): `up_dwell` and `dn_dwell` counters ensure a condition must persist for `DWELL` windows before committing. This prevents oscillation when counts hover near thresholds. `DWELL` is a localparam — the repo currently sets `DWELL = 1` for test compatibility; consider `DWELL = 3` for production demonstration.

  - EWMA predictor (P4): implemented as fixed-point accumulator `ewma_accum[9:0]` with alpha = 1/8 (fast smoothing). Update rule per window:

    ewma_accum <= ewma_accum - (ewma_accum >> 3) + activity_count;
    ewma_out   <= ewma_accum[9:3];

    This implements ewma_next = (7/8)*ewma + (1/8)*sample; `ewma_out` uses the integer portion.

  - Workload classification (P5): a 2-bit combinational class per window with encodings:
    - `WL_IDLE` (00): `activity_count < 20`.
    - `WL_BURSTY` (01): default mid-range or high stalls.
    - `WL_COMPUTE` (10): `activity_count > 60` and `stall_count < 20` (CPU-bound).
    - `WL_SUSTAINED` (11): `activity_count > 75` and `stall_count < 40` (sustained high throughput).

  - Outputs added: `ewma_out[6:0]` and `workload_class[1:0]` (useful for tracing and future governors).

**Testbenches & verification**

- `tb_counters.v`:
  - Tests basic counting, rollover, activity+stall simultaneous counting, mid-sim reset, and ensures `window_done` is exactly one cycle high (critical for `power_fsm`).

- `tb_reg_interface.v`:
  - Exercises `clk_en` policy across states, verifies `temp_out` registration and `thermal_alarm` behaviour, tests that `thermal_alarm` clears on reset, and confirms `thermal_thresh_in` is latched to `thermal_thresh_out`.

- `tb_power_fsm.v`:
  - Stimulates `power_fsm` directly (driving `window_done`, `activity_count`, `stall_count`, `thermal_alarm`) to test upscale, downscale, stall-block, thermal override, and asynchronous reset. Also connected new `ewma_out` and `workload_class` signals to trace.

- All three testbenches produce a VCD file `dump.vcd`. Running with Icarus Verilog on macOS (Homebrew) produced passing results for all tests.

**How to run locally**

- Install simulator (macOS):

```bash
brew install icarus-verilog
```

- Run each testbench (examples):

```bash
# counters
iverilog -g2012 -o tb_counters.vvp tb_counters.v counters.v
vvp tb_counters.vvp

# reg_interface (compile DUT first so macros are visible)
iverilog -g2012 -o tb_reg_interface.vvp reg_interface.v counters.v tb_reg_interface.v
vvp tb_reg_interface.vvp

# power_fsm
iverilog -g2012 -o tb_power_fsm.vvp power_fsm.v reg_interface.v counters.v tb_power_fsm.v
vvp tb_power_fsm.vvp
```

- View waveforms using GTKWave:

```bash
gtkwave dump.vcd
```

- Recommended signals to inspect in waveforms: `window_done`, `cycle_count`, `activity_count`, `stall_count`, `power_state_out`, `ewma_out`, `workload_class`, `temp_out`, `thermal_thresh_out`, `thermal_alarm`, `clk_en`.

**How to run on EDA Playground**

- Create each file in the editor (paste contents of `counters.v`, `reg_interface.v`, `power_fsm.v`, `tb_*` files).
- Tool: choose Icarus Verilog (or Verilator if you adapt tests).
- Top module: set the testbench you want to run (e.g., `tb_power_fsm`).
- Compiler options: `-g2012`.
- Run and open the waveform viewer (GTKWave) via the Waveform tab.

**Design decisions & trade-offs**

- Single-cycle `window_done` handshake: deliberately enforced to ensure `power_fsm` only runs once per window — simpler reasoning and avoids repeated transitions.
- Step ±1 state per window: avoids large jumps which could be disruptive; matches many real PMU governors.
- Predictive EWMA use on upscale only: using prediction for upscale reduces ramp latency while still using raw counts for conservative downscale decisions.
- Dwell/hysteresis: increases stability at the cost of slower reactivity. `DWELL` is parameterizable.
- Thermal override forces a conservative state immediately — safe default for thermal tests.

**Future work & suggestions**

- P6: Implement a `power_arbiter` top-level to manage multiple subsystem requests and enforce a global power budget.
- Add a register for configurable window length (`window_len`) (trade-off: reactivity vs smoothing).
- Increase `DWELL` to 3 for production demos to show hysteresis preventing oscillation; add a test demonstrating pre/post behaviour.
- Add state transition logging (4-entry FIFO with timestamps) to provide offline analysis of governor behavior.
- Integrate two `reg_interface` + `counters` pairs and show arbiter decisions (Level 2 coverage).

**Changelog (work done)**

- Added/updated `power_fsm.v`: thermal override, EWMA predictor, dwell counters, workload classifier, new outputs `ewma_out` and `workload_class`.
- Updated `reg_interface.v`: added `thermal_thresh_in` port, `thermal_thresh_out`, and `thermal_alarm` behavior was already included; ensured reset defaults.
- Verified `counters.v` pulse width behavior and left original logic intact.
- Updated testbenches to exercise new functionality and produce `dump.vcd`.

**Contact & notes**

- Files of interest: [power_fsm.v](power_fsm.v), [reg_interface.v](reg_interface.v), [counters.v](counters.v), [tb_power_fsm.v](tb_power_fsm.v), [tb_reg_interface.v](tb_reg_interface.v), [tb_counters.v](tb_counters.v).
- All tests passed locally with Icarus Verilog; VCD available at `dump.vcd`.

---
Report generated: 28 March 2026

**Generated Graphs (EPV)**

The following graphs were generated from `dump.vcd` produced by the integrated arbiter test (`tb_power_arbiter_direct.v`). They visualize governor decisions, predictions, and arbiter grants.

- Power state transitions: ![Power states](docs/graphs/power_states.png)
- Activity counts & EWMA (A/B): ![Activity & EWMA](docs/graphs/activity_ewma.png)
- Arbiter grants: ![Arbiter grants](docs/graphs/arbiter_grants.png)
