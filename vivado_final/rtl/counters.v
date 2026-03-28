// =============================================================================
// FILE: counters.v
// PURPOSE: 100-cycle observation window for activity / stall statistics.
//
//   - cycle_count: 0..99 within the current window (100 cycles per window)
//   - activity_count: counts cycles where activity_in was 1 this window
//   - stall_count:    counts cycles where stall_in was 1 this window
//   - window_done:    pulses HIGH for exactly ONE cycle when a window ends
//                     (handshake for power_fsm.v — must not stay high)
//
// Same-cycle activity=1 and stall=1 increment both counters (TEST 3).
// =============================================================================

`timescale 1ns / 1ps

module counters (

    input  wire        clk,
    input  wire        rst_n,

    input  wire        activity_in,
    input  wire        stall_in,

    output reg  [6:0]  activity_count,
    output reg  [6:0]  stall_count,
    output reg         window_done,
    output reg  [6:0]  cycle_count
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count     <= 7'd0;
            activity_count  <= 7'd0;
            stall_count     <= 7'd0;
            window_done     <= 1'b0;
        end else begin
            window_done <= 1'b0;

            if (cycle_count == 7'd99) begin
                // End of window: single-cycle pulse; start next window with clean
                // zeros (do not seed from activity_in/stall_in here). The cycle
                // that closed the window was already counted when cycle_count went
                // 98→99. Seeding caused stall_count to lead activity_count when
                // TEST 2 ended with stall=1 and TEST 3 ran 30 cycles (tb_counters).
                cycle_count    <= 7'd0;
                activity_count <= 7'd0;
                stall_count    <= 7'd0;
                window_done    <= 1'b1;
            end else begin
                cycle_count <= cycle_count + 7'd1;
                if (activity_in)
                    activity_count <= activity_count + 7'd1;
                if (stall_in)
                    stall_count <= stall_count + 7'd1;
            end
        end
    end

endmodule
