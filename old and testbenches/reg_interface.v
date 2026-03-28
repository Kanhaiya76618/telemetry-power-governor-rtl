// =============================================================================
// FILE: reg_interface.v
// PROJECT: Hardware Power Controller — pixel.ai
// MODULE: reg_interface
//
// PURPOSE:
//   This is the "front door" of the power controller.
//   It holds all the values that the rest of the design reads and writes:
//     - The current power state (SLEEP / LOW_POWER / ACTIVE / TURBO)
//     - Simulated input signals (activity, stall)
//     - A simulated temperature reading (0–100 °C)
//     - A clock-enable output (tells downstream logic when to run)
//
// ── P2 ADDITION ─────────────────────────────────────────────────────────────
//   Thermal-aware control has been added.  Two new ports:
//     thermal_thresh_in  — software-writable threshold register (simulated).
//                          When temp_in reaches or exceeds this value the
//                          thermal_alarm output is asserted.
//     thermal_thresh_out — registered (glitch-free) copy of the threshold.
//     thermal_alarm      — asserted (1) the cycle AFTER temp_in >= threshold.
//                          The power_fsm reads this signal and forces a
//                          downgrade to LOW_POWER or SLEEP.
//
//   WHY SIMULATED?
//     Physical on-chip thermal sensors require analog IP.  In this project
//     every temperature value is driven by the testbench — exactly as the
//     hackathon rules permit ("simulated via software-writable registers").
// =============================================================================


`timescale 1ns / 1ps


// ---------------------------------------------------------------------------
// GLOBAL POWER-STATE DEFINES
// Used by reg_interface, power_fsm, and all testbenches.
// Defining them here (once) avoids re-definition conflicts on EDA Playground.
// ---------------------------------------------------------------------------
`define STATE_SLEEP     2'b00   // 00 → lowest power,   clk_en = 0
`define STATE_LOW_POWER 2'b01   // 01 → reduced power,  clk_en = activity_in
`define STATE_ACTIVE    2'b10   // 10 → normal operation, clk_en = 1
`define STATE_TURBO     2'b11   // 11 → max performance, clk_en = 1


// ---------------------------------------------------------------------------
// MODULE DECLARATION
// ---------------------------------------------------------------------------
module reg_interface (

    // ── CLOCK & RESET ────────────────────────────────────────────────────────
    input  wire        clk,
    input  wire        rst_n,          // Active-LOW asynchronous reset


    // ── SIMULATED INPUT SIGNALS ──────────────────────────────────────────────
    input  wire        activity_in,    // 1 = CPU/bus active,  0 = idle
    input  wire        stall_in,       // 1 = pipeline stalled, 0 = flowing


    // ── SIMULATED TEMPERATURE INPUT ──────────────────────────────────────────
    // 7-bit value representing °C.  Range 0–100 (7 bits can hold 0–127).
    // In this project the testbench drives this port; in real silicon it
    // would be wired to an on-chip thermal-sensor ADC output.
    input  wire [6:0]  temp_in,


    // ── POWER STATE INPUT ────────────────────────────────────────────────────
    // Driven by power_fsm.v (P1).  In older builds this was driven directly
    // by the testbench; now the FSM owns it.
    input  wire [1:0]  power_state_in,


    // ── P2: THERMAL THRESHOLD INPUT ─────────────────────────────────────────
    // Software-writable threshold.  When temp_in >= this value, thermal_alarm
    // goes HIGH one cycle later (registered output, no glitches).
    // Testbench drives this to 7'd85 (85 °C) by default.
    input  wire [6:0]  thermal_thresh_in,


    // ── OUTPUTS ──────────────────────────────────────────────────────────────
    output reg  [1:0]  power_state_out,   // Stable, registered power state
    output reg         activity_out,       // Registered activity flag
    output reg         stall_out,          // Registered stall flag
    output reg  [6:0]  temp_out,           // Registered temperature reading

    // Clock Enable — downstream logic checks this before running.
    // Drives the gating decision in all states.
    output reg         clk_en,

    // ── P2: THERMAL OUTPUTS ──────────────────────────────────────────────────
    // Registered copy of the threshold (other modules can read it).
    output reg  [6:0]  thermal_thresh_out,

    // Asserted the cycle AFTER temp_in >= thermal_thresh_in.
    // power_fsm reads this and throttles the state if it is 1.
    output reg         thermal_alarm

);


// =============================================================================
// ALWAYS BLOCK — synchronous logic, asynchronous reset
// =============================================================================
//
// Sensitivity list:
//   posedge clk   → normal operation: latch inputs, compute outputs
//   negedge rst_n → async reset: drive everything to safe defaults immediately
//                   (does NOT wait for the next clock edge)
// =============================================================================
always @(posedge clk or negedge rst_n) begin

    // -------------------------------------------------------------------------
    // RESET PATH
    // Every output goes to its safest value.  This runs the instant rst_n
    // falls, regardless of where the clock is.
    // -------------------------------------------------------------------------
    if (!rst_n) begin

        power_state_out   <= `STATE_SLEEP;   // Always start in lowest-power state
        activity_out      <= 1'b0;
        stall_out         <= 1'b0;
        temp_out          <= 7'd0;
        clk_en            <= 1'b0;           // No clocks until we know the state

        // P2: reset thermal registers to safe defaults
        thermal_thresh_out <= 7'd85;         // Default ceiling: 85 °C
        thermal_alarm      <= 1'b0;          // No alarm at cold start

    end else begin
    // -------------------------------------------------------------------------
    // NORMAL OPERATION (reset not asserted)
    // All non-blocking assignments below evaluate simultaneously at the clock
    // edge.  This prevents race conditions between power_state_out and the
    // case statement that drives clk_en.
    // -------------------------------------------------------------------------

        // ── Latch the main control inputs ────────────────────────────────────
        power_state_out    <= power_state_in;
        activity_out       <= activity_in;
        stall_out          <= stall_in;
        temp_out           <= temp_in;

        // ── P2: Latch thermal threshold ───────────────────────────────────────
        thermal_thresh_out <= thermal_thresh_in;

        // ── P2: Compute thermal alarm ─────────────────────────────────────────
        // We compare the RAW inputs (not the registered outputs) so the alarm
        // reflects THIS cycle's temperature against THIS cycle's threshold.
        // The result is stored as a registered output (no combinational glitch).
        thermal_alarm      <= (temp_in >= thermal_thresh_in) ? 1'b1 : 1'b0;

        // ── Generate clk_en based on the REQUESTED power state ───────────────
        //
        // We use power_state_in (not power_state_out) because power_state_out
        // is the registered copy — it lags by one cycle.  Using the input here
        // keeps clk_en in step with the state register update.
        case (power_state_in)

            `STATE_SLEEP: begin
                // Nothing runs in SLEEP.  Gating the clock saves all dynamic power.
                clk_en <= 1'b0;
            end

            `STATE_LOW_POWER: begin
                // Fine-grained, cycle-accurate gating: clock enabled only when
                // there is real work.  Saves power during idle bursts.
                clk_en <= activity_in;
            end

            `STATE_ACTIVE: begin
                // Full normal operation.
                clk_en <= 1'b1;
            end

            `STATE_TURBO: begin
                // Maximum performance — clock always enabled.
                // (In real silicon the PLL would also boost frequency here.)
                clk_en <= 1'b1;
            end

            default: begin
                // Catch any illegal 2-bit encoding.  Safe fallback: gate off.
                // Also suppresses synthesis latch warnings.
                clk_en <= 1'b0;
            end

        endcase

    end
end


endmodule
