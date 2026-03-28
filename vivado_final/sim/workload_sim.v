// =============================================================================
// FILE: workload_sim.v
// PROJECT: Hardware Power Controller — pixel.ai
// MODULE: workload_sim
//
// LEVEL-2 FEATURE: Workload simulation
//
// PURPOSE:
//   Generates realistic, parameterised workload patterns for two subsystems
//   (A and B) to drive the power controller in simulation.  Replaces the
//   trivial "always-on" or "always-off" stimulus used in early testbenches
//   with a state-machine that cycles through four characteristic workload
//   phases seen in real SoCs:
//
//   PHASE 0 — IDLE        Both subsystems quiet.  activity ≈ 5%, stall ≈ 0.
//   PHASE 1 — RAMP_UP     A ramps from idle to compute (activity 20→80).
//                          B stays idle.
//   PHASE 2 — SUSTAINED   Both subsystems at full compute load (80% activity).
//   PHASE 3 — BURSTY      A has high activity with intermittent stalls (memory-
//                          bound); B alternates between burst and idle every
//                          2 windows, modelling a co-running background job.
//   PHASE 4 — THERMAL     Temperature rises to trigger thermal throttling.
//                          Tests that the power controller correctly downscales.
//   PHASE 5 — COOLDOWN    Load drops; temperature falls; system should recover.
//
//   The module automatically advances through phases based on PHASE_WINDOWS
//   (configurable number of 100-cycle windows per phase).
//
// OUTPUTS (connect to power_fsm / reg_interface inputs in testbench):
//   activity_a, stall_a  — per-cycle signals for subsystem A
//   activity_b, stall_b  — per-cycle signals for subsystem B
//   temp_a, temp_b       — simulated chip temperatures
//   phase_out [2:0]      — current phase (for testbench checking)
//   phase_done           — 1-cycle pulse when a phase completes
// =============================================================================

`timescale 1ns / 1ps

module workload_sim (
    input  wire        clk,
    input  wire        rst_n,

    // Synchronisation: advance phase counter at every window boundary
    input  wire        window_done,

    // Outputs — connect to DUT inputs
    output reg         activity_a,
    output reg         stall_a,
    output reg         activity_b,
    output reg         stall_b,
    output reg  [6:0]  temp_a,
    output reg  [6:0]  temp_b,

    // Phase visibility for testbench assertions
    output reg  [2:0]  phase_out,
    output reg         phase_done      // 1-cycle pulse at end of each phase
);

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------
localparam [2:0] PHASE_IDLE     = 3'd0;
localparam [2:0] PHASE_RAMP_UP  = 3'd1;
localparam [2:0] PHASE_SUSTAINED= 3'd2;
localparam [2:0] PHASE_BURSTY   = 3'd3;
localparam [2:0] PHASE_THERMAL  = 3'd4;
localparam [2:0] PHASE_COOLDOWN = 3'd5;
localparam [2:0] NUM_PHASES     = 3'd6;

// Windows per phase (change to control simulation length)
localparam [3:0] PHASE_WINDOWS  = 4'd4;

// ---------------------------------------------------------------------------
// Internal
// ---------------------------------------------------------------------------
reg [2:0]  phase;
reg [3:0]  win_in_phase;   // window count within current phase
reg        bursty_toggle;  // for alternating B in BURSTY phase
reg [6:0]  ramp_activity;  // ramps 20 → 80 during RAMP_UP

// Pseudo-random toggle for cycle-level activity generation
// Uses a simple 8-bit LFSR to produce realistic duty cycles
reg [7:0]  lfsr;
wire       lfsr_bit = lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        lfsr <= 8'hA5;
    else
        lfsr <= {lfsr[6:0], lfsr_bit};
end

// ---------------------------------------------------------------------------
// Phase state machine (advances on window_done)
// ---------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        phase         <= PHASE_IDLE;
        win_in_phase  <= 4'd0;
        bursty_toggle <= 1'b0;
        ramp_activity <= 7'd20;
        phase_done    <= 1'b0;

    end else begin
        phase_done <= 1'b0;

        if (window_done) begin
            win_in_phase <= win_in_phase + 4'd1;

            // RAMP_UP: step activity up each window
            if (phase == PHASE_RAMP_UP && ramp_activity < 7'd76)
                ramp_activity <= ramp_activity + 7'd15;

            // BURSTY: toggle B every 2 windows
            if (phase == PHASE_BURSTY)
                bursty_toggle <= ~bursty_toggle;

            // Phase transition
            if (win_in_phase == (PHASE_WINDOWS - 4'd1)) begin
                win_in_phase  <= 4'd0;
                phase_done    <= 1'b1;
                ramp_activity <= 7'd20;   // reset ramp for next time
                bursty_toggle <= 1'b0;

                if (phase == (NUM_PHASES - 3'd1))
                    phase <= PHASE_IDLE;  // wrap around
                else
                    phase <= phase + 3'd1;
            end
        end
    end
end

// ---------------------------------------------------------------------------
// Output generation (combinational based on phase + LFSR)
// ---------------------------------------------------------------------------
// Activity signals are generated by comparing the LFSR value against a
// duty-cycle threshold, giving statistically correct average counts while
// remaining cycle-level realistic.
//
// Threshold table (lfsr[7:0] < threshold  →  signal = 1):
//   5%  activity : threshold =  13
//  20%  activity : threshold =  51
//  50%  activity : threshold = 128
//  75%  activity : threshold = 192
//  80%  activity : threshold = 204
//  90%  activity : threshold = 230
// ---------------------------------------------------------------------------

always @(*) begin
    // Safe defaults
    activity_a = 1'b0;
    stall_a    = 1'b0;
    activity_b = 1'b0;
    stall_b    = 1'b0;
    temp_a     = 7'd35;
    temp_b     = 7'd35;
    phase_out  = phase;

    case (phase)

        PHASE_IDLE: begin
            // ~5% activity, no stalls, cool temperatures
            activity_a = (lfsr < 8'd13);
            activity_b = (lfsr < 8'd13);
            temp_a     = 7'd30;
            temp_b     = 7'd30;
        end

        PHASE_RAMP_UP: begin
            // A ramps from 20% → 80% over PHASE_WINDOWS windows
            // B stays idle (~5%)
            activity_a = (lfsr < {1'b0, ramp_activity});
            activity_b = (lfsr < 8'd13);
            // Temperature rises with activity
            temp_a     = 7'd35 + ramp_activity[6:1];  // 35→75 over ramp
            temp_b     = 7'd30;
        end

        PHASE_SUSTAINED: begin
            // Both ~80% active, no stalls, elevated temperature
            activity_a = (lfsr < 8'd204);
            activity_b = (lfsr < 8'd204);
            temp_a     = 7'd70;
            temp_b     = 7'd70;
        end

        PHASE_BURSTY: begin
            // A: high activity (75%) with heavy stalls (50%) — memory-bound
            // B: alternates between burst (80%) and idle (5%) every 2 windows
            activity_a = (lfsr < 8'd192);
            stall_a    = (lfsr[3:0] < 4'd8);   // ~50% stall
            if (bursty_toggle) begin
                activity_b = (lfsr < 8'd204);
                temp_b     = 7'd65;
            end else begin
                activity_b = (lfsr < 8'd13);
                temp_b     = 7'd40;
            end
            temp_a     = 7'd72;
        end

        PHASE_THERMAL: begin
            // Both at full load; temperature deliberately high to trigger alarm
            // Default thermal threshold in reg_interface = 85 °C
            activity_a = (lfsr < 8'd230);
            activity_b = (lfsr < 8'd230);
            temp_a     = 7'd90;   // above 85 → thermal_alarm asserts
            temp_b     = 7'd88;
        end

        PHASE_COOLDOWN: begin
            // Activity drops suddenly (burst ended); temperature falls
            activity_a = (lfsr < 8'd51);
            activity_b = (lfsr < 8'd51);
            temp_a     = 7'd60;   // below 80 → alarm clears (85-5=80)
            temp_b     = 7'd55;
        end

        default: begin
            activity_a = 1'b0;
            activity_b = 1'b0;
        end

    endcase
end

endmodule
