// =============================================================================
// FILE: tb_reg_interface.v
// PURPOSE: Testbench for reg_interface.v
//
// WHAT IS A TESTBENCH?
//   A testbench is a fake "wrapper" that pretends to be the outside world.
//   It feeds inputs into your module and checks if the outputs are correct.
//   Testbenches are NOT real hardware — they only run in simulation.
//
// CHANGES vs ORIGINAL:
//   • Added thermal_thresh_in stimulus register and thermal_alarm/
//     thermal_thresh_out observation wires to match the updated DUT ports.
//   • Tests 1–7 are IDENTICAL to the original — all original checks preserved.
//   • TEST  8 (new): Thermal alarm fires when temp reaches the threshold.
//   • TEST  9 (new): Thermal alarm clears when temp drops below threshold.
//   • TEST 10 (new): Reset unconditionally clears the thermal alarm.
//
// NOTE — NO `define HERE:
//   STATE_SLEEP / LOW_POWER / ACTIVE / TURBO are defined in reg_interface.v.
//   EDA Playground compiles both files in one iverilog run, so those macros
//   are visible here. Redefining them with -Wall makes iverilog abort with
//   "macro redefined" before elaboration, which shows up as "No top level
//   modules" in the log.
// =============================================================================

`timescale 1ns / 1ps

// ---------------------------------------------------------------------------
// TESTBENCH MODULE — no ports (it is the top of the simulation world)
// ---------------------------------------------------------------------------
module tb_reg_interface;

    // ── STIMULUS REGISTERS (we drive these) ──────────────────────────────────
    reg        clk;
    reg        rst_n;
    reg        activity_in;
    reg        stall_in;
    reg [6:0]  temp_in;
    reg [1:0]  power_state_in;
    reg [6:0]  thermal_thresh_in;    // NEW (P2): threshold we write to the DUT

    // ── OBSERVATION WIRES (DUT drives these, we read) ────────────────────────
    wire [1:0] power_state_out;
    wire       activity_out;
    wire       stall_out;
    wire [6:0] temp_out;
    wire       clk_en;
    wire [6:0] thermal_thresh_out;   // NEW (P2): registered copy of threshold
    wire       thermal_alarm;        // NEW (P2): alarm flag from DUT

    // ── INSTANTIATE THE DUT ───────────────────────────────────────────────────
    reg_interface DUT (
        .clk               (clk),
        .rst_n             (rst_n),
        .activity_in       (activity_in),
        .stall_in          (stall_in),
        .temp_in           (temp_in),
        .power_state_in    (power_state_in),
        .thermal_thresh_in (thermal_thresh_in),   // NEW
        .power_state_out   (power_state_out),
        .activity_out      (activity_out),
        .stall_out         (stall_out),
        .temp_out          (temp_out),
        .clk_en            (clk_en),
        .thermal_thresh_out(thermal_thresh_out),  // NEW
        .thermal_alarm     (thermal_alarm)        // NEW
    );

    // ── CLOCK GENERATOR: 10 ns period = 100 MHz ───────────────────────────────
    initial clk = 0;
    always #5 clk = ~clk;


    // =========================================================================
    // TASK: apply_inputs
    // Sets all main inputs at once and waits 2 clock cycles for outputs to
    // settle (registered outputs lag inputs by 1 cycle; we wait 2 to be safe).
    // =========================================================================
    task apply_inputs;
        input [1:0] state;
        input       activity;
        input       stall;
        input [6:0] temp;
        begin
            power_state_in = state;
            activity_in    = activity;
            stall_in       = stall;
            temp_in        = temp;
            @(posedge clk);
            @(posedge clk);
        end
    endtask


    // =========================================================================
    // TASK: check_clk_en
    // Compares clk_en against an expected value and prints PASS / FAIL.
    // Uses "===" (case-equality) which correctly handles X/Z states.
    // =========================================================================
    task check_clk_en;
        input       expected_clk_en;
        input [63:0] test_num;
        begin
            if (clk_en === expected_clk_en)
                $display("  TEST %0d PASSED: clk_en = %b (expected %b)",
                          test_num, clk_en, expected_clk_en);
            else
                $display("  TEST %0d FAILED: clk_en = %b (expected %b) <---",
                          test_num, clk_en, expected_clk_en);
        end
    endtask


    // =========================================================================
    // TASK: check_alarm
    // NEW — checks the thermal_alarm output against an expected value.
    // =========================================================================
    task check_alarm;
        input       expected_alarm;
        input [63:0] test_num;
        begin
            if (thermal_alarm === expected_alarm)
                $display("  TEST %0d PASSED: thermal_alarm = %b (expected %b)",
                          test_num, thermal_alarm, expected_alarm);
            else
                $display("  TEST %0d FAILED: thermal_alarm = %b (expected %b) <---",
                          test_num, thermal_alarm, expected_alarm);
        end
    endtask


    // =========================================================================
    // MAIN TEST SEQUENCE
    // =========================================================================
    initial begin

        // ── Waveform dump ──────────────────────────────────────────────────────
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_reg_interface);

        $display("=========================================");
        $display("  reg_interface Testbench Starting...");
        $display("  (includes P2 thermal alarm tests)");
        $display("=========================================");

        // ── Initialise all inputs BEFORE releasing reset ───────────────────────
        rst_n             = 0;
        activity_in       = 0;
        stall_in          = 0;
        temp_in           = 7'd25;
        power_state_in    = `STATE_SLEEP;
        thermal_thresh_in = 7'd85;    // Default ceiling: 85 °C

        // ── Hold reset for 3 cycles, then release ─────────────────────────────
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        $display("\n--- Reset Released ---");
        $display("  power_state_out=%b  clk_en=%b  temp_out=%0d  thermal_alarm=%b",
                  power_state_out, clk_en, temp_out, thermal_alarm);


        // =====================================================================
        // TEST 1: SLEEP state → clk_en = 0  [ORIGINAL]
        // =====================================================================
        $display("\n--- TEST 1: SLEEP state ---");
        apply_inputs(`STATE_SLEEP, 0, 0, 7'd20);
        $display("  power_state_out=%b  clk_en=%b  temp_out=%0d",
                  power_state_out, clk_en, temp_out);
        check_clk_en(1'b0, 1);

        // =====================================================================
        // TEST 2: LOW_POWER, activity=0 → clk_en = 0  [ORIGINAL]
        // =====================================================================
        $display("\n--- TEST 2: LOW_POWER, no activity ---");
        apply_inputs(`STATE_LOW_POWER, 0, 0, 7'd30);
        $display("  power_state_out=%b  clk_en=%b  activity_out=%b",
                  power_state_out, clk_en, activity_out);
        check_clk_en(1'b0, 2);

        // =====================================================================
        // TEST 3: LOW_POWER, activity=1 → clk_en = 1  [ORIGINAL]
        // =====================================================================
        $display("\n--- TEST 3: LOW_POWER, with activity ---");
        apply_inputs(`STATE_LOW_POWER, 1, 0, 7'd30);
        $display("  power_state_out=%b  clk_en=%b  activity_out=%b",
                  power_state_out, clk_en, activity_out);
        check_clk_en(1'b1, 3);

        // =====================================================================
        // TEST 4: ACTIVE state → clk_en = 1  [ORIGINAL]
        // =====================================================================
        $display("\n--- TEST 4: ACTIVE state ---");
        apply_inputs(`STATE_ACTIVE, 0, 1, 7'd45);
        $display("  power_state_out=%b  clk_en=%b  stall_out=%b",
                  power_state_out, clk_en, stall_out);
        check_clk_en(1'b1, 4);

        // =====================================================================
        // TEST 5: TURBO state → clk_en = 1  [ORIGINAL]
        // =====================================================================
        $display("\n--- TEST 5: TURBO state ---");
        apply_inputs(`STATE_TURBO, 1, 0, 7'd80);
        $display("  power_state_out=%b  clk_en=%b  temp_out=%0d",
                  power_state_out, clk_en, temp_out);
        check_clk_en(1'b1, 5);

        // =====================================================================
        // TEST 6: High temp register accuracy in TURBO  [ORIGINAL]
        // =====================================================================
        $display("\n--- TEST 6: TURBO at high temp (95 C) — register accuracy ---");
        apply_inputs(`STATE_TURBO, 1, 0, 7'd95);
        $display("  power_state_out=%b  clk_en=%b  temp_out=%0d",
                  power_state_out, clk_en, temp_out);
        if (temp_out === 7'd95)
            $display("  TEST 6 PASSED: temp_out correctly shows 95");
        else
            $display("  TEST 6 FAILED: temp_out = %0d (expected 95)", temp_out);

        // =====================================================================
        // TEST 7: Mid-simulation reset  [ORIGINAL]
        // =====================================================================
        $display("\n--- TEST 7: Mid-simulation reset ---");
        rst_n = 0;
        @(posedge clk);
        @(posedge clk);
        $display("  During reset: power_state_out=%b  clk_en=%b",
                  power_state_out, clk_en);
        check_clk_en(1'b0, 7);
        rst_n = 1;
        @(posedge clk);


        // =====================================================================
        // TEST 8 (NEW — P2): Thermal alarm fires when temp >= threshold
        //
        // Setup:
        //   thermal_thresh_in = 85 °C  (already set above)
        //   temp_in           = 90 °C  → temp_in >= threshold → alarm should = 1
        //
        // The DUT registers both temp_in and the comparison result on the
        // same clock edge, so thermal_alarm is valid one cycle after the input
        // is applied.  apply_inputs() waits 2 cycles, so the check sees the
        // stable registered output.
        // =====================================================================
        $display("\n--- TEST 8 (P2): Thermal alarm fires at temp=90, thresh=85 ---");
        thermal_thresh_in = 7'd85;
        apply_inputs(`STATE_TURBO, 1, 0, 7'd90);
        $display("  temp_out=%0d  thermal_thresh_out=%0d  thermal_alarm=%b",
                  temp_out, thermal_thresh_out, thermal_alarm);
        check_alarm(1'b1, 8);    // Expect alarm = 1 (90 >= 85)

        // Also confirm clk_en is still 1 (reg_interface doesn't throttle itself;
        // that is power_fsm's job — which reads thermal_alarm and changes state)
        $display("  clk_en=%b (should still be 1 — throttling is power_fsm's job)",
                  clk_en);

        // =====================================================================
        // TEST 9 (NEW — P2): Thermal alarm clears when temp drops below threshold
        //
        // Setup:
        //   thermal_thresh_in = 85 °C
        //   temp_in           = 70 °C  → temp_in < threshold → alarm should = 0
        // =====================================================================
        $display("\n--- TEST 9 (P2): Thermal alarm clears at temp=70, thresh=85 ---");
        thermal_thresh_in = 7'd85;
        apply_inputs(`STATE_ACTIVE, 1, 0, 7'd70);
        $display("  temp_out=%0d  thermal_thresh_out=%0d  thermal_alarm=%b",
                  temp_out, thermal_thresh_out, thermal_alarm);
        check_alarm(1'b0, 9);    // Expect alarm = 0 (70 < 85)

        // =====================================================================
        // TEST 10 (NEW — P2): Thermal alarm clears immediately on reset
        //
        // Drive a high temperature so alarm is 1, then assert reset and
        // confirm thermal_alarm returns to 0.
        // =====================================================================
        $display("\n--- TEST 10 (P2): Reset clears thermal alarm ---");
        // First, get alarm HIGH
        thermal_thresh_in = 7'd60;
        apply_inputs(`STATE_TURBO, 1, 0, 7'd75);
        $display("  Before reset: temp_out=%0d  thermal_alarm=%b (should be 1)",
                  temp_out, thermal_alarm);

        // Now assert reset
        rst_n = 0;
        @(posedge clk);
        @(posedge clk);
        $display("  After reset:  temp_out=%0d  thermal_alarm=%b (should be 0)",
                  temp_out, thermal_alarm);
        if (thermal_alarm === 1'b0)
            $display("  TEST 10 PASSED: reset correctly cleared thermal_alarm");
        else
            $display("  TEST 10 FAILED: thermal_alarm still %b after reset <---",
                      thermal_alarm);
        rst_n = 1;
        @(posedge clk);

        rst_n = 1;
    stall_in = 0;
    temp_in = 7'h19;
    thermal_thresh_in = 7'h55;

    #10;

    // Apply reset + stall together
    rst_n = 0;
    stall_in = 1;

    #20;

    // Release reset, keep stall
    rst_n = 1;
    stall_in = 1;

    #20;

    // Remove stall
    stall_in = 0;

    #50;

    $display("Test case: Reset=0 & Stall=1 completed");


        // ── DONE ──────────────────────────────────────────────────────────────
        $display("\n=========================================");
        $display("  All 11 tests complete!");
        $display("  (7 original + 3 P2 thermal alarm tests)");
        $display("  Open EPWave to see the waveforms.");
        $display("=========================================\n");

        #20;
        $finish;
    end

endmodule
