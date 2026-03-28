// =============================================================================
// FILE: perf_feedback.v
// PROJECT: Hardware Power Controller — pixel.ai
// MODULE: perf_feedback
//
// LEVEL-2 FEATURE: Feedback performance loop
//
// PURPOSE:
//   Measures the performance cost of power throttling and feeds a penalty
//   signal back to the power arbiter so the system can relax the budget when
//   throttling is genuinely hurting throughput.
//
// HOW IT WORKS:
//   Every observation window the module compares what the FSM REQUESTED
//   (req) vs. what the arbiter GRANTED (grant).  If the grant is below the
//   request, the system is being throttled.  The module accumulates a
//   throttle-cycle count over a configurable FEEDBACK_WINDOW (default 4
//   arbiter windows) and classifies the result:
//
//     perf_penalty = 0   No throttling this feedback window
//     perf_penalty = 1   Light throttle  (<25% of windows throttled)
//     perf_penalty = 2   Moderate        (25–50%)
//     perf_penalty = 3   Heavy           (>50% of windows throttled)
//
//   budget_relax is asserted for one cycle when heavy throttling is detected,
//   signalling the arbiter to relax (raise) its budget by 1.
//   budget_tighten is asserted when zero throttling has persisted for
//   SLACK_WINDOWS consecutive feedback windows (system has headroom to spare).
//
// CONNECTIONS:
//   req_a, req_b     — from power_fsm outputs
//   grant_a, grant_b — from power_arbiter outputs
//   window_done      — pulse from counters (one per 100-cycle observation)
//   budget_headroom  — from power_arbiter (unused here but available)
//   perf_penalty[1:0]— classification of current throttle severity
//   budget_relax     — 1-cycle pulse: tell arbiter to raise budget by 1
//   budget_tighten   — 1-cycle pulse: tell arbiter to lower budget by 1
// =============================================================================

`timescale 1ns / 1ps

module perf_feedback (
    input  wire        clk,
    input  wire        rst_n,

    // Window boundary (from counters module)
    input  wire        window_done,

    // FSM requests vs arbiter grants (both subsystems)
    input  wire [1:0]  req_a,
    input  wire [1:0]  grant_a,
    input  wire [1:0]  req_b,
    input  wire [1:0]  grant_b,

    // Remaining arbiter budget (from power_arbiter)
    input  wire [2:0]  budget_headroom,

    // Outputs
    output reg  [1:0]  perf_penalty,     // 0=none 1=light 2=moderate 3=heavy
    output reg         budget_relax,     // pulse: request budget +1
    output reg         budget_tighten    // pulse: request budget -1
);

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------
// Number of windows in one feedback evaluation period
localparam [2:0] FEEDBACK_WINDOW = 3'd4;

// Consecutive feedback periods with zero throttle before tightening budget
localparam [2:0] SLACK_WINDOWS   = 3'd3;

// Throttle thresholds (out of FEEDBACK_WINDOW windows)
// Light    < THRESH_MOD,  Moderate  < THRESH_HEAVY,  Heavy >= THRESH_HEAVY
localparam [2:0] THRESH_MOD   = 3'd1;   // >=1 throttled window  = at least light
localparam [2:0] THRESH_HEAVY = 3'd2;   // >=2 throttled windows = heavy

// ---------------------------------------------------------------------------
// Internal counters
// ---------------------------------------------------------------------------
reg [2:0] window_cnt;       // counts windows within current feedback period
reg [2:0] throttle_cnt;     // windows where any throttling occurred
reg [2:0] slack_cnt;        // consecutive zero-throttle feedback periods

// ---------------------------------------------------------------------------
// Per-window throttle detection (combinational)
// Throttled = any subsystem's grant < its request
// ---------------------------------------------------------------------------
wire throttled_this_window = (grant_a < req_a) || (grant_b < req_b);

// ---------------------------------------------------------------------------
// Main registered logic
// ---------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        window_cnt     <= 3'd0;
        throttle_cnt   <= 3'd0;
        slack_cnt      <= 3'd0;
        perf_penalty   <= 2'd0;
        budget_relax   <= 1'b0;
        budget_tighten <= 1'b0;

    end else begin

        // Default: clear pulses every cycle
        budget_relax   <= 1'b0;
        budget_tighten <= 1'b0;

        if (window_done) begin

            // Accumulate throttle count for this feedback window
            if (throttled_this_window && throttle_cnt < 3'd7)
                throttle_cnt <= throttle_cnt + 3'd1;

            window_cnt <= window_cnt + 3'd1;

            // ── End of feedback period ───────────────────────────────────
            if (window_cnt == (FEEDBACK_WINDOW - 3'd1)) begin
                window_cnt <= 3'd0;

                // Classify throttle severity
                if (throttle_cnt == 3'd0) begin
                    perf_penalty <= 2'd0;  // none
                    // Accumulate slack
                    if (slack_cnt < 3'd7)
                        slack_cnt <= slack_cnt + 3'd1;
                    // Enough slack: suggest tightening budget
                    if (slack_cnt >= (SLACK_WINDOWS - 3'd1))
                        budget_tighten <= 1'b1;
                end else if (throttle_cnt < THRESH_HEAVY) begin
                    perf_penalty <= 2'd1;  // light
                    slack_cnt    <= 3'd0;
                end else if (throttle_cnt < (FEEDBACK_WINDOW >> 1)) begin
                    perf_penalty <= 2'd2;  // moderate
                    slack_cnt    <= 3'd0;
                end else begin
                    perf_penalty <= 2'd3;  // heavy
                    slack_cnt    <= 3'd0;
                    budget_relax <= 1'b1;  // pulse: raise budget
                end

                // Reset throttle counter for next period
                throttle_cnt <= 3'd0;
            end
        end
    end
end

endmodule
