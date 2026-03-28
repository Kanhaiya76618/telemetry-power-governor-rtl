// =============================================================================
// FILE: tb_power_fsm.v
// PURPOSE: Dedicated testbench for power_fsm.v  (P1 + P2)
//
// HOW IT WORKS:
//   The FSM only acts when window_done pulses.  Rather than instantiating the
//   full counters module and waiting 100 real cycles per test, this testbench
//   drives window_done, activity_count, stall_count, and thermal_alarm
//   DIRECTLY — giving us full control in much fewer simulation cycles.
//
//   This is standard practice for FSM verification: isolate the FSM from
//   its data sources and inject the corner-case inputs you care about.
//
// TEST SCENARIOS:
//   1. UPSCALE — high activity, low stalls → state climbs SLEEP→LOW_POWER→
//                                             ACTIVE→TURBO over 3 windows
//   2. DOWNSCALE — low activity → state drops TURBO→ACTIVE→LOW_POWER→SLEEP
//                                 over 3 windows
//   3. STALL BLOCK — high activity AND high stalls → FSM should NOT upscale
//                    (pipeline bottlenecked; more MHz won't help)
//   4. THERMAL OVERRIDE — thermal_alarm=1 → force TURBO straight to LOW_POWER
//                          regardless of activity
//   5. RESET — mid-simulation reset returns FSM to SLEEP immediately
// =============================================================================

`timescale 1ns / 1ps

module tb_power_fsm;

    // ── STIMULUS REGISTERS ────────────────────────────────────────────────────
    reg        clk;
    reg        rst_n;
    reg        window_done;        // We pulse this manually to trigger FSM
    reg [6:0]  activity_count;    // Injected counter value (from counters.v)
    reg [6:0]  stall_count;       // Injected counter value (from counters.v)
    reg        thermal_alarm;     // From reg_interface.v thermal logic (P2)

    // ── OBSERVATION WIRE ──────────────────────────────────────────────────────
    wire [1:0] power_state_out;   // FSM's decision output
    wire [6:0] ewma_out;          // EWMA predictor output (for tracing)
    wire [1:0] workload_class;    // Workload class output (for tracing)

    // ── INSTANTIATE power_fsm.v ───────────────────────────────────────────────
    power_fsm DUT (
        .clk            (clk),
        .rst_n          (rst_n),
        .window_done    (window_done),
        .activity_count (activity_count),
        .stall_count    (stall_count),
        .thermal_alarm  (thermal_alarm),
        .power_state_out(power_state_out),
        .ewma_out       (ewma_out),
        .workload_class (workload_class)
    );

    // ── CLOCK: 10 ns period = 100 MHz ─────────────────────────────────────────
    initial clk = 0;
    always #5 clk = ~clk;

    // ── STATE NAME CONSTANTS ──────────────────────────────────────────────────
    // Using localparam instead of `define to avoid conflicts with other files.
    localparam STATE_SLEEP     = 2'b00;
    localparam STATE_LOW_POWER = 2'b01;
    localparam STATE_ACTIVE    = 2'b10;
    localparam STATE_TURBO     = 2'b11;


    // =========================================================================
    // TASK: send_window
    //
    // Simulates one completed 100-cycle observation window.
    //   act_cnt  — activity_count value to present to the FSM
    //   stl_cnt  — stall_count value to present to the FSM
    //   therm    — thermal_alarm value
    //
    // The task sets the data inputs BEFORE the pulse (as counters.v would),
    // then asserts window_done for exactly ONE clock cycle (matching the real
    // counters module behaviour verified in tb_counters TEST 5).
    //
    // IMPORTANT — simulator scheduling vs Icarus Verilog:
    //   If we clear window_done with a blocking assign in the SAME time step as
    //   @(posedge clk), some simulators run the testbench continuation BEFORE
    //   the DUT's always @(posedge clk). Then window_done is already 0 when the
    //   FSM samples it — the FSM never leaves SLEEP.  De-assert on the NEXT
    //   negedge so window_done stays 1 for the entire posedge sampling window.
    // =========================================================================
    task send_window;
        input [6:0] act_cnt;
        input [6:0] stl_cnt;
        input       therm;
        begin
            // Present the data
            activity_count = act_cnt;
            stall_count    = stl_cnt;
            thermal_alarm  = therm;

            // Pulse window_done HIGH through one full posedge (then low rest of cycle)
            @(negedge clk);
            window_done = 1'b1;
            @(posedge clk);           // FSM samples window_done == 1 here
            @(negedge clk);           // do NOT clear in same step as posedge (race)
            window_done = 1'b0;

            // Wait one more posedge so power_state_out (nonblocking) is stable
            @(posedge clk);
        end
    endtask


    // =========================================================================
    // TASK: check_state
    // Compares power_state_out against expected value.
    // Prints a state name string for readability (not just raw bits).
    // =========================================================================
    task check_state;
        input [1:0]  expected;
        input [63:0] test_num;
        reg   [15:0] got_name;   // simple 2-char label trick not needed; use display
        begin
            if (power_state_out === expected) begin
                $display("  TEST %0d PASSED: power_state_out = %b (%s)",
                          test_num, power_state_out, state_name(power_state_out));
            end else begin
                $display("  TEST %0d FAILED: power_state_out = %b (%s), expected %b (%s) <---",
                          test_num, power_state_out, state_name(power_state_out),
                          expected, state_name(expected));
            end
        end
    endtask


    // =========================================================================
    // FUNCTION: state_name
    // Returns a short ASCII label for a 2-bit power state.
    // Used by check_state() for human-readable console output.
    // =========================================================================
    function [79:0] state_name;
        input [1:0] s;
        begin
            case (s)
                2'b00:   state_name = "SLEEP    ";
                2'b01:   state_name = "LOW_POWER";
                2'b10:   state_name = "ACTIVE   ";
                2'b11:   state_name = "TURBO    ";
                default: state_name = "UNKNOWN  ";
            endcase
        end
    endfunction


    // =========================================================================
    // MAIN TEST SEQUENCE
    // =========================================================================
    initial begin

        $dumpfile("dump.vcd");
        $dumpvars(0, tb_power_fsm);

        $display("=========================================");
        $display("  power_fsm Testbench Starting...");
        $display("  (P1 FSM + P2 thermal override)");
        $display("=========================================");

        // ── Initialise all inputs before releasing reset ───────────────────────
        rst_n          = 0;
        window_done    = 0;
        activity_count = 7'd0;
        stall_count    = 7'd0;
        thermal_alarm  = 1'b0;

        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        $display("\n--- Reset Released: FSM should be in SLEEP ---");
        $display("  power_state_out = %b (%s)", power_state_out, state_name(power_state_out));


        // =====================================================================
        // TEST 1: UPSCALE — high activity, low stalls
        //
        // Each send_window() presents activity_count=80 (>ACT_HIGH=75) and
        // stall_count=10 (<STALL_HIGH=50).  The FSM should step up by 1
        // state per window:
        //   Window 1: SLEEP     → LOW_POWER
        //   Window 2: LOW_POWER → ACTIVE
        //   Window 3: ACTIVE    → TURBO
        // =====================================================================
        $display("\n--- TEST 1: Upscale — heavy workload, 3 windows ---");

        send_window(7'd80, 7'd10, 1'b0);
        $display("  After window 1: %b (%s)", power_state_out, state_name(power_state_out));
        check_state(STATE_LOW_POWER, 1);

        send_window(7'd80, 7'd10, 1'b0);
        $display("  After window 2: %b (%s)", power_state_out, state_name(power_state_out));
        check_state(STATE_ACTIVE, 1);

        send_window(7'd80, 7'd10, 1'b0);
        $display("  After window 3: %b (%s)", power_state_out, state_name(power_state_out));
        check_state(STATE_TURBO, 1);

        // Extra window at TURBO — should HOLD, not overflow
        send_window(7'd80, 7'd10, 1'b0);
        $display("  After window 4 (saturate at TURBO): %b (%s)",
                  power_state_out, state_name(power_state_out));
        if (power_state_out === STATE_TURBO)
            $display("  TEST 1 BONUS PASSED: TURBO held correctly (no overflow)");
        else
            $display("  TEST 1 BONUS FAILED: TURBO overflowed to %b <---", power_state_out);


        // =====================================================================
        // TEST 2: DOWNSCALE — low activity
        //
        // Starting from TURBO, send activity_count=10 (<ACT_LOW=20).
        // FSM should step DOWN one state per window:
        //   Window 1: TURBO     → ACTIVE
        //   Window 2: ACTIVE    → LOW_POWER
        //   Window 3: LOW_POWER → SLEEP
        // =====================================================================
        $display("\n--- TEST 2: Downscale — idle workload, 3 windows ---");

        send_window(7'd10, 7'd0, 1'b0);
        $display("  After window 1: %b (%s)", power_state_out, state_name(power_state_out));
        check_state(STATE_ACTIVE, 2);

        send_window(7'd10, 7'd0, 1'b0);
        $display("  After window 2: %b (%s)", power_state_out, state_name(power_state_out));
        check_state(STATE_LOW_POWER, 2);

        send_window(7'd10, 7'd0, 1'b0);
        $display("  After window 3: %b (%s)", power_state_out, state_name(power_state_out));
        check_state(STATE_SLEEP, 2);

        // Extra window at SLEEP — should HOLD, not underflow
        send_window(7'd10, 7'd0, 1'b0);
        $display("  After window 4 (saturate at SLEEP): %b (%s)",
                  power_state_out, state_name(power_state_out));
        if (power_state_out === STATE_SLEEP)
            $display("  TEST 2 BONUS PASSED: SLEEP held correctly (no underflow)");
        else
            $display("  TEST 2 BONUS FAILED: SLEEP underflowed to %b <---", power_state_out);


        // =====================================================================
        // TEST 3: STALL BLOCK — high activity AND high stalls
        //
        // activity_count=80 would normally trigger an upscale.
        // But stall_count=60 (>=STALL_HIGH=50) blocks it.
        // Reason: the pipeline is stalled (memory-bound); boosting the clock
        // won't help and wastes power.
        //
        // Starting from SLEEP, no upscale should occur after 2 windows.
        // =====================================================================
        $display("\n--- TEST 3: Stall block — high activity blocked by high stalls ---");

        $display("  State before Test 3: %s", state_name(power_state_out));

        send_window(7'd80, 7'd60, 1'b0);   // High activity, high stall
        $display("  After window 1: %b (%s)", power_state_out, state_name(power_state_out));
        if (power_state_out === STATE_SLEEP)
            $display("  TEST 3 PASSED: stall correctly blocked upscale (still SLEEP)");
        else
            $display("  TEST 3 FAILED: FSM upscaled despite high stalls → %s <---",
                      state_name(power_state_out));

        send_window(7'd80, 7'd60, 1'b0);   // Same again
        $display("  After window 2: %b (%s)", power_state_out, state_name(power_state_out));
        if (power_state_out === STATE_SLEEP)
            $display("  TEST 3 PASSED: stall block sustained across 2 windows");
        else
            $display("  TEST 3 FAILED: stall block failed on 2nd window → %s <---",
                      state_name(power_state_out));


        // =====================================================================
        // TEST 4 (P2): THERMAL OVERRIDE — force TURBO down to LOW_POWER
        //
        // First, upscale to TURBO (3 windows of high activity, no stalls).
        // Then assert thermal_alarm=1.  The FSM should override activity and
        // force power_state_out to LOW_POWER regardless.
        //
        // This tests the highest-priority branch of the FSM — thermal safety
        // must always beat performance demands.
        // =====================================================================
        $display("\n--- TEST 4 (P2): Thermal override — TURBO forced to LOW_POWER ---");

        // Get to TURBO first
        send_window(7'd80, 7'd10, 1'b0);
        send_window(7'd80, 7'd10, 1'b0);
        send_window(7'd80, 7'd10, 1'b0);
        $display("  Pre-override state: %b (%s)", power_state_out, state_name(power_state_out));
        if (power_state_out !== STATE_TURBO)
            $display("  (Setup issue: expected TURBO but got %s)", state_name(power_state_out));

        // Now fire the thermal alarm — activity is STILL high (80) but alarm wins
        send_window(7'd80, 7'd10, 1'b1);    // thermal_alarm = 1
        $display("  After thermal alarm window: %b (%s)",
                  power_state_out, state_name(power_state_out));
        if (power_state_out === STATE_LOW_POWER)
            $display("  TEST 4 PASSED: thermal alarm forced TURBO → LOW_POWER");
        else
            $display("  TEST 4 FAILED: state is %s (expected LOW_POWER) <---",
                      state_name(power_state_out));

        // Confirm alarm holds state at LOW_POWER (does not upscale while hot)
        send_window(7'd80, 7'd10, 1'b1);    // Still alarming, high activity
        $display("  Second alarm window: %b (%s) (should stay LOW_POWER)",
                  power_state_out, state_name(power_state_out));
        if (power_state_out === STATE_LOW_POWER)
            $display("  TEST 4 BONUS PASSED: thermal hold sustained");
        else
            $display("  TEST 4 BONUS FAILED: state slipped to %s <---",
                      state_name(power_state_out));

        // Cool down — alarm clears — should be free to upscale again next window
        thermal_alarm = 1'b0;
        send_window(7'd80, 7'd10, 1'b0);    // Alarm gone, high activity
        $display("  After cooldown window: %b (%s) (should upscale to ACTIVE)",
                  power_state_out, state_name(power_state_out));
        if (power_state_out === STATE_ACTIVE)
            $display("  TEST 4 BONUS PASSED: upscale resumed after cooldown");
        else
            $display("  TEST 4 BONUS FAILED: got %s (expected ACTIVE) <---",
                      state_name(power_state_out));


        // =====================================================================
        // TEST 5: MID-SIMULATION RESET
        //
        // Assert rst_n=0 at an arbitrary point.  power_state_out must return
        // to STATE_SLEEP immediately (next clock edge) without waiting for a
        // window_done pulse.  This is the asynchronous reset path.
        // =====================================================================
        $display("\n--- TEST 5: Mid-simulation reset ---");
        $display("  State before reset: %b (%s)", power_state_out, state_name(power_state_out));

        rst_n = 0;
        @(posedge clk);
        @(posedge clk);

        $display("  State during reset: %b (%s)", power_state_out, state_name(power_state_out));
        if (power_state_out === STATE_SLEEP)
            $display("  TEST 5 PASSED: reset correctly returned FSM to SLEEP");
        else
            $display("  TEST 5 FAILED: power_state_out = %s (expected SLEEP) <---",
                      state_name(power_state_out));

        rst_n = 1;
        @(posedge clk);


        // ── DONE ──────────────────────────────────────────────────────────────
        $display("\n=========================================");
        $display("  All power_fsm tests complete!");
        $display("  Tests: upscale, downscale, stall-block,");
        $display("         thermal-override (P2), reset");
        $display("=========================================\n");

        #20;
        $finish;
    end

endmodule
