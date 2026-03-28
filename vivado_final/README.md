# Vivado Final Merged RTL

This folder contains a clean, merged final design based on your original repo + new Level-2 files.

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

## Simulation Files

Simulation helpers are kept in `vivado_final/sim`:

- `tb_level2.v`
- `workload_sim.v`

## Important

Do not add both the old root RTL files and these final files into the same Vivado project, because module names overlap and will cause duplicate-definition errors.
