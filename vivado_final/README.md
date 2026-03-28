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
- Use constraints file `vivado_final/constraints/cora_z7_07s_btn_demo.xdc`

Button behavior:

- `btn0`: reset (hold to reset, release to run)
- `btn1=0`: autonomous mode patterns
- `btn1=1`: external-control mode patterns

LED behavior:

- `LD0` shows grant bits (A/B)
- `LD1` shows grant/clock-enable bits

The design cycles through four internal workload phases automatically so color changes are visible.

## Simulation Files

Simulation helpers are kept in `vivado_final/sim`:

- `tb_level2.v`
- `workload_sim.v`

## Important

Do not add both the old root RTL files and these final files into the same Vivado project, because module names overlap and will cause duplicate-definition errors.
