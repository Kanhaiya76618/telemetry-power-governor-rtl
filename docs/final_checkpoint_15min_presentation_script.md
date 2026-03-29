# Final Checkpoint Presentation Script (15 Minutes)

## Presenter Setup (Before Recording)

- Open Vivado project with Runs panel visible.
- Keep these windows ready in tabs:
  - Block Design canvas
  - Synthesis and Implementation runs
  - Timing report
  - Power report
  - Utilization report
  - Device placement view after implementation
  - Hardware Manager (programmed board)
- Keep Vitis project and source file open.
- Keep your GUI application open and connected to board/UART path.
- Keep simulation terminal ready with self-checking testbench outputs.

## Slide/Section Timing Plan

- 00:00 to 01:30: Problem statement and motivation
- 01:30 to 03:30: Approach to solving the problem
- 03:30 to 06:00: Design architecture and module explanation
- 06:00 to 07:30: Self-checking testbench outputs
- 07:30 to 08:30: Synthesis, implementation, bitstream evidence
- 08:30 to 09:30: FPGA placement results after implementation
- 09:30 to 11:30: Reports (timing, power, hardware, utilization)
- 11:30 to 13:00: Vitis software + runtime bridge demonstration
- 13:00 to 14:00: GUI demonstration
- 14:00 to 15:00: Challenges, unique contributions, conclusion

---

## Full Speaker Script

### 1) Problem Statement Introduction (00:00 to 01:30)

"Good [morning/afternoon], we are Team [Team Name]. Our project addresses intelligent power governance on FPGA-based systems where workload and thermal behavior change over time.

The core problem is to make power-state decisions dynamically while maintaining performance and safety. We need a design that can monitor telemetry, arbitrate power requests, expose control through a software-accessible interface, and run reliably on real hardware."

"Our final checkpoint deliverables require successful synthesis, implementation, and bitstream generation, along with hardware demonstration and report-based validation. This presentation shows all of that end-to-end."

[On screen]

- Title slide with project name, team, and objective.

---

### 2) Approach to Solving the Problem (01:30 to 03:30)

"We followed a modular hardware-software co-design approach:

1. Build and verify core RTL modules independently.
2. Integrate modules into a top-level power governor.
3. Wrap the governor with AXI-Lite for processor/software interaction.
4. Integrate into Zynq block design and validate complete system.
5. Add software control and telemetry through Vitis.
6. Add a GUI for user-friendly interaction and live monitoring."

"This approach gave us faster debugging, clear ownership per module, and predictable integration at each stage."

[On screen]

- Flow diagram: RTL modules -> Top -> AXI-Lite -> Block Design -> Bitstream -> Vitis -> GUI.

---

### 3) Design Architecture (03:30 to 06:00)

"This is our design architecture. At the center is the power governor top module.

Main hardware blocks:

1. Counters: track activity/stall metrics over windows.
2. Power FSM per core: determines requested power state from workload and thermal status.
3. Register Interface: captures inputs and status outputs.
4. Power Arbiter: resolves requests under budget constraints.
5. Performance Feedback: measures throttling and adjusts policy pressure.
6. Power Logger: computes efficiency and cumulative stats.
7. AXI-Lite Wrapper: maps control/status registers to software."

"In the block design, the Processing System connects through AXI SmartConnect to our AXI-Lite governor IP. Reset and clock are aligned through Processor System Reset."

[On screen]

- Vivado block design with clear zoom on governor path.
- Optional architecture diagram labeling data/control flow.

---

### 4) Self-Checking Testbench Console Outputs (06:00 to 07:30)

"For verification, we used self-checking testbenches with pass/fail markers.

Each testbench prints TB_PASS on success and TB_FAIL on mismatch. We validated:

1. Counter window behavior.
2. FSM transition policy.
3. Register interface thermal and clock-enable behavior.
4. Arbiter budget and priority behavior."

"This gave us automated confidence before hardware deployment."

[On screen]

- Terminal logs showing TB_PASS lines.
- Briefly point to one policy test and one arbitration test output.

---

### 5) Synthesis, Implementation, Bitstream Evidence (07:30 to 08:30)

"Now showing required implementation milestones:

1. Synthesis completed.
2. Implementation completed.
3. Bitstream generation completed."

"These three deliverables are ready and reproducible."

[On screen]

- Vivado Runs panel with green check status for synth_1, impl_1, write_bitstream.

---

### 6) FPGA Placement Results After Implementation (08:30 to 09:30)

"After implementation, we inspected placement to ensure the design is physically realized and routed without critical issues.

This view confirms placement completion and gives us confidence in physical feasibility and timing closure context."

[On screen]

- Device/placement view in Vivado.
- Highlight major logic region or route density briefly.

---

### 7) Reports: Timing, Power, Hardware, Utilization (09:30 to 11:30)

"We now present the key reports.

Timing report:

- [Insert WNS, TNS, failing endpoints if any].
- Interpretation: [met/not met] target clock requirements.

Power report:

- [Insert total on-chip power, static, dynamic].
- Interpretation: aligns with expected activity profile.

Hardware report:

- [Insert board/device summary, clocking summary, implementation status].
- Interpretation: design is deployable on target FPGA.

Utilization report:

- LUTs: [value / percent]
- FFs: [value / percent]
- DSPs: [value / percent]
- BRAM: [value / percent]
- Interpretation: resource usage is within device budget."

[On screen]

- report_timing_summary
- report_power
- report_utilization
- implementation summary/hardware manager metadata

---

### 8) Vitis Code and Runtime Bridge Demo (11:30 to 13:00)

"On software side, we implemented a Vitis bare-metal bridge.

Capabilities:

1. AXI register read/write for host mode, requests, budget, and IO controls.
2. Periodic telemetry frame generation over UART.
3. Command handling to change runtime behavior without reprogramming FPGA."

"This creates a clean control plane between software and hardware logic."

[On screen]

- Vitis source code in editor.
- UART/serial output showing telemetry frames.
- One command example changing budget or request and reflected status.

---

### 9) GUI Demonstration Section (13:00 to 14:00)

"To improve observability and usability, we built a GUI on top of the bridge.

GUI functions:

1. Send control commands.
2. Display live telemetry and decoded status.
3. Trigger simulation checks and show pass/fail labels.

This makes demonstration and debugging faster for both developers and evaluators."

[On screen]

- GUI panel with controls and live values.
- Perform one interaction and show immediate telemetry/state change.

---

### 10) Challenges Faced + Unique Contributions + Conclusion (14:00 to 15:00)

"Key challenges we faced:

1. Integration consistency between RTL hierarchy and block design.
2. Build/run issues from stale generated artifacts in Vivado.
3. Keeping feedback policy behavior consistent under host override modes.
4. Ensuring verification covered both module-level and integrated behavior."

"Unique things we implemented:

1. Closed-loop feedback-driven budget policy in hardware.
2. Curated self-checking verification benches for major policy blocks.
3. End-to-end software bridge from Vitis to AXI registers.
4. GUI-assisted telemetry/control workflow for live validation.
5. Full pipeline proof: simulation -> synthesis -> implementation -> bitstream -> hardware demo."

"Conclusion:
We achieved a complete FPGA power-governor system with verified RTL, successful synthesis/implementation/bitstream, software control via Vitis, and live GUI-based monitoring. The design is ready for final evaluation and future extension. Thank you."

---

## Quick Checklist During Recording

- Problem statement explained
- Approach explained
- Architecture explained neatly
- Self-checking TB outputs shown
- Synthesis/Implementation/Bitstream shown
- Placement shown
- Timing report shown
- Power report shown
- Hardware summary shown
- Utilization numbers shown
- Challenges and unique contributions covered
- Vitis code and runtime interaction shown
- GUI section shown
- Clear conclusion delivered

## Optional Backup One-Liners (if asked)

- "Our validation strategy combines module-level self-checking benches with system-level hardware verification."
- "Our AXI-Lite map provides deterministic control of budget, requests, and IO stimuli for repeatable experiments."
- "The GUI reduces debug turnaround by making telemetry and controls observable in real time."
