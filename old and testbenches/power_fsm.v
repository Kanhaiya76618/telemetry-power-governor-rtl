// =============================================================================
// FILE: power_fsm.v
// PROJECT: Hardware Power Controller — pixel.ai
// MODULE: power_fsm
//
// PURPOSE — P1: FSM Controller
//   This is the "brain" of the power controller.  It sits between the counters
//   module and the reg_interface and makes all state-transition decisions
//   automatically — no CPU driver needed.
//
//   Every time the counters module completes a 100-cycle observation window
//   (window_done pulses HIGH for one cycle), the FSM wakes up, reads the
//   activity and stall counts, and decides:
//
//       ┌──────────────────────────────────────────────────┐
//       │  activity_count ≥ ACT_HIGH  AND                  │
//       │  stall_count    < STALL_HIGH  →  scale UP one    │
//       │                                  state           │
//       ├──────────────────────────────────────────────────┤
//       │  activity_count < ACT_LOW         →  scale DOWN  │
//       │                                      one state   │
//       ├──────────────────────────────────────────────────┤
//       │  thermal_alarm == 1               →  THERMAL     │
//       │                                      OVERRIDE    │
//       │  (P2) Force state to LOW_POWER or               │
//       │       below regardless of activity              │
//       ├──────────────────────────────────────────────────┤
//       │  all other conditions             →  hold state  │
//       └──────────────────────────────────────────────────┘
//
// FOUR-STATE FSM ENCODING (matches reg_interface.v):
//   SLEEP (00) ↔ LOW_POWER (01) ↔ ACTIVE (10) ↔ TURBO (11)
//   The FSM can only step ±1 state per window — no sudden jumps.
//
// THERMAL OVERRIDE (P2):
//   If thermal_alarm (from reg_interface) is asserted, the FSM will not
//   upscale and will force a downgrade to LOW_POWER if currently in
//   ACTIVE or TURBO.  This mirrors real PMU thermal-throttling behaviour.
//
// CONNECTIONS (how this fits into the full design):
//
//   counters.v
//     ├─ activity_count[6:0] ──────────┐
//     ├─ stall_count[6:0]   ──────────┤
//     └─ window_done        ──────────┤
//                                      ▼
//   reg_interface.v          power_fsm.v  ──► power_state_in of reg_interface
//     └─ thermal_alarm ──────────────►
//
// THRESHOLDS (localparams — change here to tune behaviour):
//   ACT_HIGH   = 75   Out of 100 cycles, ≥75 active   → consider scaling up
//   ACT_LOW    = 20   Out of 100 cycles,  <20 active   → consider scaling down
//   STALL_HIGH = 50   Out of 100 cycles, ≥50 stalled  → too many stalls,
//                                                         don't scale up even
//                                                         if activity is high
// =============================================================================


`timescale 1ns / 1ps


module power_fsm (

    // ── CLOCK & RESET ────────────────────────────────────────────────────────
    input  wire        clk,
    input  wire        rst_n,             // Active-LOW asynchronous reset


    // ── INPUTS FROM counters.v ───────────────────────────────────────────────
    // window_done: pulses HIGH for exactly ONE clock cycle when the 100-cycle
    //              observation window completes.  The FSM only acts on this
    //              pulse — it ignores the counter values in all other cycles.
    input  wire        window_done,

    // activity_count: number of cycles in the window where activity_in was 1.
    // stall_count:    number of cycles in the window where stall_in was 1.
    // Both are valid (stable) when window_done is asserted.
    input  wire [6:0]  activity_count,
    input  wire [6:0]  stall_count,


    // ── INPUT FROM reg_interface.v (P2: thermal) ─────────────────────────────
    // thermal_alarm: HIGH when the chip temperature has reached or exceeded
    //                the programmed threshold.  Drives the override logic below.
    input  wire        thermal_alarm,


    // ── OUTPUT → power_state_in of reg_interface.v ───────────────────────────
    // The FSM drives this.  reg_interface latches it on the next clock edge
    // and distributes the stable state to the rest of the chip.
    output reg  [1:0]  power_state_out,
    // P4: EWMA predictor (7-bit) — smoothed recent activity prediction
    output reg  [6:0]  ewma_out,
    // P5: Workload classification (2-bit)
    output reg  [1:0]  workload_class

);


// ---------------------------------------------------------------------------
// LOCAL STATE ENCODING
// Using localparam (module-local) instead of `define (global) avoids
// re-definition warnings when both this file and reg_interface.v are compiled
// together on EDA Playground.
// ---------------------------------------------------------------------------
localparam STATE_SLEEP     = 2'b00;
localparam STATE_LOW_POWER = 2'b01;
localparam STATE_ACTIVE    = 2'b10;
localparam STATE_TURBO     = 2'b11;


// ---------------------------------------------------------------------------
// DECISION THRESHOLDS
// All values are counts out of a 100-cycle window.
// Change these localparams to tune how aggressively the governor scales.
// ---------------------------------------------------------------------------
localparam ACT_HIGH   = 7'd75;   // ≥ this → workload is heavy  → scale up
localparam ACT_LOW    = 7'd20;   // <  this → workload is light  → scale down
localparam STALL_HIGH = 7'd50;   // ≥ this → pipeline choked     → block upscale
                                 //           (memory-bound: more MHz won't help)

// ---------------------------------------------------------------------------
// P3: Oscillation guard (dwell/hysteresis)
// The FSM must see an upscale/downscale condition for DWELL consecutive
// windows before committing the transition.  Prevents flip-flopping.
// ---------------------------------------------------------------------------
localparam DWELL = 3'd1;   // windows required to confirm a decision (1 = immediate)

// P4: EWMA predictor accumulator (10-bit internal, 7-bit visible)
reg [2:0] up_dwell, dn_dwell;
reg [9:0] ewma_accum;   // 3-bit fractional headroom, top bits contain integer value

// P5: Workload classification encodings
localparam WL_IDLE      = 2'b00;
localparam WL_BURSTY    = 2'b01;
localparam WL_COMPUTE   = 2'b10;
localparam WL_SUSTAINED = 2'b11;


// =============================================================================
// FSM ALWAYS BLOCK (enhanced)
// =============================================================================
// Implements:
//  - P2: Thermal override (highest priority)
//  - P3: Hysteresis / dwell counters to avoid oscillation
//  - P4: EWMA predictor (used to pre-scale on ramps)
//  - P5: Workload classification per-window
// =============================================================================
always @(posedge clk or negedge rst_n) begin

    // -------------------------------------------------------------------------
    // RESET: initialise all registers to safe defaults
    // -------------------------------------------------------------------------
    if (!rst_n) begin
        power_state_out <= STATE_SLEEP;
        up_dwell        <= 3'd0;
        dn_dwell        <= 3'd0;
        ewma_accum      <= 10'd0;
        ewma_out        <= 7'd0;
        workload_class  <= WL_IDLE;

    end else if (window_done) begin
    // -------------------------------------------------------------------------
    // WINDOW DONE — evaluate transitions using per-window measurements
    // -------------------------------------------------------------------------

        // P2: Thermal override wins always — force conservative state
        if (thermal_alarm) begin
            if (power_state_out > STATE_LOW_POWER)
                power_state_out <= STATE_LOW_POWER;
            // clear dwell counters so we don't immediately flip back
            up_dwell <= 3'd0;
            dn_dwell <= 3'd0;

        end else begin
            // P4+P3: Upscale decision uses EWMA predictor to pre-empt ramps.
            // Use the registered `ewma_out` (prediction) here; it reflects
            // the smoothed history available at the start of this window.
            if ((activity_count >= ACT_HIGH || ewma_out >= ACT_HIGH) && stall_count < STALL_HIGH) begin
                up_dwell <= up_dwell + 3'd1;
                dn_dwell <= 3'd0;
                if (up_dwell >= (DWELL - 1)) begin
                    if (power_state_out != STATE_TURBO)
                        power_state_out <= power_state_out + 2'b01;
                    up_dwell <= 3'd0;
                end

            // P3: Downscale uses the ACTUAL activity count (don't downscale on
            // transient stalls).  Also protected by dwell.
            end else if (activity_count < ACT_LOW) begin
                dn_dwell <= dn_dwell + 3'd1;
                up_dwell <= 3'd0;
                if (dn_dwell >= (DWELL - 1)) begin
                    if (power_state_out != STATE_SLEEP)
                        power_state_out <= power_state_out - 2'b01;
                    dn_dwell <= 3'd0;
                end

            end else begin
                // Ambiguous/mid-range: reset dwell counters
                up_dwell <= 3'd0;
                dn_dwell <= 3'd0;
            end
        end

        // P4: Update EWMA accumulator (first-order, alpha = 1/8):
        // ewma = (7/8)*ewma + (1/8)*activity_count
        // Implemented as: ewma_accum <= ewma_accum - (ewma_accum >> 3) + activity_count
        ewma_accum <= ewma_accum - (ewma_accum >> 3) + activity_count;
        ewma_out   <= ewma_accum[9:3];

        // P5: Workload classification based on raw counts this window
        if (activity_count < 7'd20)
            workload_class <= WL_IDLE;
        else if (activity_count > 7'd60 && stall_count < 7'd20)
            workload_class <= WL_COMPUTE;
        else if (activity_count > 7'd75 && stall_count < 7'd40)
            workload_class <= WL_SUSTAINED;
        else
            workload_class <= WL_BURSTY;

    end

    // If window_done is not asserted, hold all registers steady.
end


endmodule
