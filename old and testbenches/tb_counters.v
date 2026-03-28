// =============================================================================
// FILE: tb_counters.v
// PURPOSE: Testbench for counters.v
//
// CHANGES vs ORIGINAL:
//   Tests 1–4 are IDENTICAL to the original — all checks preserved.
//   TEST 5 (new): Verifies that window_done produces exactly one pulse of
//                 exactly one cycle width — this is the handshake signal that
//                 power_fsm.v (P1) depends on.  If window_done stays high for
//                 more than one cycle, the FSM would act multiple times per
//                 window, causing incorrect state transitions.
// =============================================================================

`timescale 1ns / 1ps

module tb_counters;

    // ── SIGNALS TO DRIVE INTO counters.v ─────────────────────────────────────
    reg        clk;
    reg        rst_n;
    reg        activity_in;
    reg        stall_in;

    // ── SIGNALS TO READ FROM counters.v ──────────────────────────────────────
    wire [6:0] activity_count;
    wire [6:0] stall_count;
    wire       window_done;
    wire [6:0] cycle_count;

    // ── INSTANTIATE counters.v ────────────────────────────────────────────────
    counters DUT (
        .clk            (clk),
        .rst_n          (rst_n),
        .activity_in    (activity_in),
        .stall_in       (stall_in),
        .activity_count (activity_count),
        .stall_count    (stall_count),
        .window_done    (window_done),
        .cycle_count    (cycle_count)
    );

    // ── CLOCK: 10 ns period = 100 MHz ─────────────────────────────────────────
    initial clk = 0;
    always #5 clk = ~clk;

    // ── VARIABLES ─────────────────────────────────────────────────────────────
    integer i;
    integer done_pulse_count;   // NEW (Test 5): count how many cycles window_done stays HIGH


    // =========================================================================
    // MAIN TEST SEQUENCE
    // =========================================================================
    initial begin

        $dumpfile("dump.vcd");
        $dumpvars(0, tb_counters);

        $display("=========================================");
        $display("  counters.v Testbench Starting...");
        $display("  (includes P1 window_done pulse test)");
        $display("=========================================");

        // ── Initialise & apply reset ───────────────────────────────────────────
        rst_n       = 0;
        activity_in = 0;
        stall_in    = 0;

        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        $display("\n--- Reset released. All counters should be 0 ---");
        $display("  cycle_count=%0d  activity_count=%0d  stall_count=%0d",
                  cycle_count, activity_count, stall_count);


        // =====================================================================
        // TEST 1: 50 cycles, activity=1, stall=0  [ORIGINAL]
        // activity_count should reach 50; stall_count should stay 0.
        // =====================================================================
        $display("\n--- TEST 1: 50 cycles, activity=1, stall=0 ---");
        activity_in = 1;
        stall_in    = 0;

        repeat(50) @(posedge clk);

        $display("  cycle_count=%0d  activity_count=%0d  stall_count=%0d",
                  cycle_count, activity_count, stall_count);

        if (activity_count == 7'd50)
            $display("  TEST 1 PASSED: activity_count = 50");
        else
            $display("  TEST 1 FAILED: activity_count = %0d (expected 50)", activity_count);

        if (stall_count == 7'd0)
            $display("  TEST 1 PASSED: stall_count = 0");
        else
            $display("  TEST 1 FAILED: stall_count = %0d (expected 0)", stall_count);


        // =====================================================================
        // TEST 2: Next 50 cycles → window rollover  [ORIGINAL]
        // At the 100th cycle window_done pulses; counters reset automatically.
        // =====================================================================
        $display("\n--- TEST 2: next 50 cycles, activity=0, stall=1 ---");
        activity_in = 0;
        stall_in    = 1;

        repeat(49) @(posedge clk);   // 49 more (now at cycle 99)
        @(posedge clk);              // 100th cycle — window resets

        $display("  After full 100-cycle window:");
        $display("  cycle_count=%0d  activity_count=%0d  stall_count=%0d  window_done=%b",
                  cycle_count, activity_count, stall_count, window_done);

        if (cycle_count <= 7'd1)
            $display("  TEST 2 PASSED: window correctly reset (cycle_count=%0d)", cycle_count);
        else
            $display("  TEST 2 FAILED: cycle_count = %0d (expected ~0)", cycle_count);


        // =====================================================================
        // TEST 3: 30 cycles, both activity=1 and stall=1  [ORIGINAL]
        // Both counters must increment together every cycle.
        //
        // NOTE: Brief reset clears the window.  Stimulus for this test MUST be
        // driven *before* the first posedge after reset release — otherwise that
        // edge still sees TEST 2's activity_in=0, stall_in=1 and stall_count
        // gets one extra tick (31 vs 30).
        // =====================================================================
        $display("\n--- TEST 3: 30 cycles, activity=1, stall=1 ---");

        activity_in = 1'b1;
        stall_in    = 1'b1;
        rst_n       = 1'b0;
        @(posedge clk);
        rst_n = 1'b1;
        repeat(30) @(posedge clk);

        $display("  activity_count=%0d  stall_count=%0d",
                  activity_count, stall_count);

        if (activity_count == 7'd30 && stall_count == 7'd30)
            $display("  TEST 3 PASSED: both counts = 30");
        else
            $display("  TEST 3 FAILED: activity=%0d stall=%0d (expected both 30)",
                      activity_count, stall_count);


        // =====================================================================
        // TEST 4: Mid-simulation reset  [ORIGINAL]
        // Asserting rst_n=0 must clear all counters immediately.
        // =====================================================================
        $display("\n--- TEST 4: Mid-simulation reset ---");
        rst_n = 0;
        @(posedge clk);
        @(posedge clk);

        $display("  cycle_count=%0d  activity_count=%0d  stall_count=%0d",
                  cycle_count, activity_count, stall_count);

        if (cycle_count == 0 && activity_count == 0 && stall_count == 0)
            $display("  TEST 4 PASSED: all counters cleared by reset");
        else
            $display("  TEST 4 FAILED: counters not cleared!");

        rst_n = 1;
        @(posedge clk);


        // =====================================================================
        // TEST 5 (NEW — P1): window_done is a single-cycle pulse
        //
        // WHY THIS MATTERS FOR power_fsm:
        //   power_fsm acts on "if (window_done)" inside a clocked always block.
        //   If window_done stays HIGH for N cycles, the FSM will try to
        //   transition N times per window — completely wrong behaviour.
        //   This test proves window_done is exactly 1 cycle wide.
        //
        // METHOD:
        //   Run a full 100-cycle window and count how many consecutive clock
        //   cycles window_done is HIGH.  Expected answer: exactly 1.
        // =====================================================================
        $display("\n--- TEST 5 (P1): window_done is a 1-cycle pulse ---");

        // Ensure we're at the start of a fresh window
        rst_n = 0;
        @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Set stable inputs for the full window
        activity_in      = 1;
        stall_in         = 0;
        done_pulse_count = 0;

        // Run 101 cycles while watching window_done on every edge
        // (101 to catch the pulse that arrives exactly at cycle 100)
        repeat(101) begin
            @(posedge clk);
            if (window_done) done_pulse_count = done_pulse_count + 1;
        end

        $display("  window_done was HIGH for %0d cycle(s) across 101 cycles",
                  done_pulse_count);

        if (done_pulse_count == 1)
            $display("  TEST 5 PASSED: window_done is exactly 1 cycle (safe for power_fsm)");
        else if (done_pulse_count == 0)
            $display("  TEST 5 FAILED: window_done never pulsed — check counters.v rollover logic <---");
        else
            $display("  TEST 5 FAILED: window_done pulsed %0d times (power_fsm would over-transition) <---",
                      done_pulse_count);


        // ── DONE ──────────────────────────────────────────────────────────────
        $display("\n=========================================");
        $display("  All 5 tests complete!");
        $display("  (4 original + 1 P1 pulse-width test)");
        $display("  Open EPWave to watch the counters climb!");
        $display("=========================================\n");

        #20;
        $finish;
    end

endmodule
