// =============================================================================
// FILE: power_logger.v
// PROJECT: Hardware Power Controller — pixel.ai
// MODULE: power_logger
//
// LEVEL-2 FEATURE: Performance vs power analysis
//
// PURPOSE:
//   Records per-window power and performance proxy metrics for both
//   subsystems and accumulates rolling totals.  Provides a lightweight
//   on-chip analysis layer without requiring external post-processing.
//
// POWER PROXY MODEL:
//   State weights (proportional to actual SoC dynamic power):
//     SLEEP     = 0   (clock gated, minimal leakage)
//     LOW_POWER = 1   (partial gating)
//     ACTIVE    = 3   (full frequency)
//     TURBO     = 5   (boosted voltage+frequency — super-linear power)
//
//   per_window_power = weight(state_a) + weight(state_b)
//   Max possible per window: 5+5 = 10
//
// PERFORMANCE PROXY MODEL:
//   Performance ∝ state × activity (work done at that state).
//   per_window_perf = state_a × (activity_count_a / 100)
//                   + state_b × (activity_count_b / 100)
//   Approximated in integer arithmetic (no division) as:
//   per_window_perf_raw = state_a * activity_count_a
//                       + state_b * activity_count_b
//   (scaled; compare relative values, not absolute)
//
// EFFICIENCY METRIC:
//   efficiency = perf_raw / power_proxy  (higher is better)
//   Stored as a 10-bit ratio; logged per feedback period.
//   Saturation at 10'h3FF if power_proxy == 0.
//
// OUTPUTS:
//   total_power_acc   [15:0] — accumulated power proxy since reset
//   total_perf_acc    [15:0] — accumulated performance proxy since reset
//   window_power      [3:0]  — power proxy this window
//   window_perf_raw   [9:0]  — performance proxy this window (raw, unscaled)
//   efficiency        [9:0]  — perf/power ratio this feedback period
//   log_valid                — pulses HIGH for one cycle when a new
//                              efficiency reading is ready (every
//                              FEEDBACK_WINDOW windows)
// =============================================================================

`timescale 1ns / 1ps

module power_logger (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        window_done,

    // Applied power states from reg_interface (not requests — actual grants)
    input  wire [1:0]  state_a,
    input  wire [1:0]  state_b,

    // Activity counts from counters (valid when window_done)
    input  wire [6:0]  activity_count_a,
    input  wire [6:0]  activity_count_b,

    // Throttle flag from perf_feedback
    input  wire [1:0]  perf_penalty,

    // Outputs
    output reg  [15:0] total_power_acc,
    output reg  [15:0] total_perf_acc,
    output reg  [3:0]  window_power,
    output reg  [9:0]  window_perf_raw,
    output reg  [9:0]  efficiency,
    output reg         log_valid
);

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------
localparam [2:0] FEEDBACK_WINDOW = 3'd4;   // match perf_feedback.v

// ---------------------------------------------------------------------------
// Power weight lookup (combinational)
// State: SLEEP=0, LOW_POWER=1, ACTIVE=2, TURBO=3
// Weight:        0          1         3          5
// ---------------------------------------------------------------------------
function [2:0] power_weight;
    input [1:0] state;
    begin
        case (state)
            2'b00: power_weight = 3'd0;   // SLEEP
            2'b01: power_weight = 3'd1;   // LOW_POWER
            2'b10: power_weight = 3'd3;   // ACTIVE
            2'b11: power_weight = 3'd5;   // TURBO
            default: power_weight = 3'd0;
        endcase
    end
endfunction

// ---------------------------------------------------------------------------
// Internal signals
// ---------------------------------------------------------------------------
wire [2:0] w_a = power_weight(state_a);
wire [2:0] w_b = power_weight(state_b);
wire [3:0] this_power = {1'b0, w_a} + {1'b0, w_b};

// Performance raw = state_value * activity_count
// Implemented with shifts/adds (no inferred multipliers)
wire [8:0] act_a_ext = {2'b00, activity_count_a};
wire [8:0] act_b_ext = {2'b00, activity_count_b};

wire [8:0] perf_a = (state_a == 2'b00) ? 9'd0 :
                    (state_a == 2'b01) ? act_a_ext :
                    (state_a == 2'b10) ? {act_a_ext[7:0], 1'b0} :
                                         ({act_a_ext[7:0], 1'b0} + act_a_ext); // x3

wire [8:0] perf_b = (state_b == 2'b00) ? 9'd0 :
                    (state_b == 2'b01) ? act_b_ext :
                    (state_b == 2'b10) ? {act_b_ext[7:0], 1'b0} :
                                         ({act_b_ext[7:0], 1'b0} + act_b_ext); // x3

wire [9:0] this_perf = {1'b0, perf_a} + {1'b0, perf_b};           // max 600

wire [5:0]  period_power_next = period_power_acc + {2'b00, this_power};
wire [11:0] period_perf_next  = period_perf_acc  + {2'b00, this_perf};

// ---------------------------------------------------------------------------
// Feedback period accumulator
// ---------------------------------------------------------------------------
reg [2:0]  win_cnt;
reg [5:0]  period_power_acc;   // up to 4 windows × 10 = 40
reg [11:0] period_perf_acc;    // up to 4 windows × 600 = 2400

// Sequential divider state (timing-friendly replacement for combinational '/')
reg        div_busy;
reg [3:0]  div_cnt;            // 14 cycles for 14-bit numerator
reg [13:0] div_num;
reg [13:0] div_quo;
reg [6:0]  div_rem;
reg [5:0]  div_den;

wire [6:0]  div_rem_shift = {div_rem[5:0], div_num[13]};
wire        div_ge        = (div_rem_shift >= {1'b0, div_den});
wire [6:0]  div_rem_next  = div_ge ? (div_rem_shift - {1'b0, div_den}) : div_rem_shift;
wire [13:0] div_quo_next  = {div_quo[12:0], div_ge};

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        total_power_acc  <= 16'd0;
        total_perf_acc   <= 16'd0;
        window_power     <= 4'd0;
        window_perf_raw  <= 10'd0;
        efficiency       <= 10'd0;
        log_valid        <= 1'b0;
        win_cnt          <= 3'd0;
        period_power_acc <= 6'd0;
        period_perf_acc  <= 12'd0;
        div_busy         <= 1'b0;
        div_cnt          <= 4'd0;
        div_num          <= 14'd0;
        div_quo          <= 14'd0;
        div_rem          <= 7'd0;
        div_den          <= 6'd0;

    end else begin
        log_valid <= 1'b0;

        // Run restoring divider one bit per cycle when active.
        if (div_busy) begin
            div_num <= {div_num[12:0], 1'b0};
            div_rem <= div_rem_next;
            div_quo <= div_quo_next;
            div_cnt <= div_cnt - 4'd1;

            if (div_cnt == 4'd1) begin
                div_busy <= 1'b0;
                log_valid <= 1'b1;

                // Saturate to 10 bits.
                if (|div_quo_next[13:10])
                    efficiency <= 10'h3FF;
                else
                    efficiency <= div_quo_next[9:0];
            end
        end

        if (window_done) begin
            // Latch per-window values
            window_power    <= this_power;
            window_perf_raw <= this_perf;

            // Accumulate running totals
            total_power_acc <= total_power_acc + {12'd0, this_power};
            total_perf_acc  <= total_perf_acc  + {6'd0,  this_perf};

            // Accumulate period totals
            period_power_acc <= period_power_next;
            period_perf_acc  <= period_perf_next;

            win_cnt <= win_cnt + 3'd1;

            // End of feedback period — compute efficiency and report
            if (win_cnt == (FEEDBACK_WINDOW - 3'd1)) begin
                win_cnt          <= 3'd0;
                period_power_acc <= 6'd0;
                period_perf_acc  <= 12'd0;

                // Start efficiency calculation at period boundary.
                // Uses a sequential divider to avoid a long critical path.
                if (period_power_next == 6'd0)
                    begin
                        efficiency <= 10'h3FF;   // avoid divide-by-zero
                        log_valid  <= 1'b1;
                    end
                else if (!div_busy)
                    begin
                        div_busy <= 1'b1;
                        div_cnt  <= 4'd14;
                        div_num  <= {period_perf_next, 2'b00}; // x4 scale for extra resolution
                        div_quo  <= 14'd0;
                        div_rem  <= 7'd0;
                        div_den  <= period_power_next;
                    end
            end
        end
    end
end

endmodule
