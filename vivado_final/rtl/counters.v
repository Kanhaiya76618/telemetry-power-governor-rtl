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

    reg clear_window;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count     <= 7'd0;
            activity_count  <= 7'd0;
            stall_count     <= 7'd0;
            window_done     <= 1'b0;
            clear_window    <= 1'b0;
        end else begin
            if (clear_window) begin
                // Keep previous window counts valid for one cycle while
                // window_done is observed by downstream modules, then clear.
                clear_window   <= 1'b0;
                window_done    <= 1'b0;
                cycle_count    <= 7'd1;
                activity_count <= activity_in ? 7'd1 : 7'd0;
                stall_count    <= stall_in ? 7'd1 : 7'd0;
            end else if (cycle_count == 7'd99) begin
                // End-of-window pulse with counts still valid in this cycle.
                window_done    <= 1'b1;
                clear_window   <= 1'b1;
                cycle_count    <= 7'd0;
                if (activity_in)
                    activity_count <= activity_count + 7'd1;
                if (stall_in)
                    stall_count <= stall_count + 7'd1;
            end else begin
                window_done <= 1'b0;
                cycle_count <= cycle_count + 7'd1;
                if (activity_in)
                    activity_count <= activity_count + 7'd1;
                if (stall_in)
                    stall_count <= stall_count + 7'd1;
            end
        end
    end

endmodule
