// =============================================================================
// FILE: tb_power_arbiter.v
// PURPOSE: Integrated testbench — two subsystems (A,B) + arbiter budget check
// =============================================================================

`timescale 1ns / 1ps

module tb_power_arbiter;

    // Clock & reset
    reg clk;
    reg rst_n;

    // Subsystem A stimulus
    reg activity_a, stall_a;
    reg [6:0] temp_a;
    reg [6:0] thresh_a;

    // Subsystem B stimulus
    reg activity_b, stall_b;
    reg [6:0] temp_b;
    reg [6:0] thresh_b;

    // Counters outputs
    wire [6:0] activity_count_a, stall_count_a, cycle_count_a;
    wire        window_done_a;

    wire [6:0] activity_count_b, stall_count_b, cycle_count_b;
    wire        window_done_b;

    // FSM requests
    wire [1:0] req_a, req_b;
    wire [6:0] ewma_a, ewma_b;
    wire [1:0] wl_a, wl_b;

    // Arbiter grants
    wire [1:0] grant_a, grant_b;

    // Reg_interface outputs (applied state)
    wire [1:0] applied_state_a, applied_state_b;
    wire       clk_en_a, clk_en_b;
    wire [6:0] thermal_thresh_out_a, thermal_thresh_out_b;
    wire       thermal_alarm_a, thermal_alarm_b;

    // ------------------------------------------------------------------
    // Instantiate subsystem A
    // ------------------------------------------------------------------
    counters CNT_A (
        .clk            (clk),
        .rst_n          (rst_n),
        .activity_in    (activity_a),
        .stall_in       (stall_a),
        .activity_count (activity_count_a),
        .stall_count    (stall_count_a),
        .window_done    (window_done_a),
        .cycle_count    (cycle_count_a)
    );

    reg_interface REG_A (
        .clk               (clk),
        .rst_n             (rst_n),
        .activity_in       (activity_a),
        .stall_in          (stall_a),
        .temp_in           (temp_a),
        .power_state_in    (grant_a),        // arbiter grant applied here
        .thermal_thresh_in (thresh_a),
        .power_state_out   (applied_state_a),
        .activity_out      (),
        .stall_out         (),
        .temp_out          (),
        .clk_en            (clk_en_a),
        .thermal_thresh_out(thermal_thresh_out_a),
        .thermal_alarm     (thermal_alarm_a)
    );

    power_fsm FSM_A (
        .clk            (clk),
        .rst_n          (rst_n),
        .window_done    (window_done_a),
        .activity_count (activity_count_a),
        .stall_count    (stall_count_a),
        .thermal_alarm  (thermal_alarm_a),
        .power_state_out(req_a),
        .ewma_out       (ewma_a),
        .workload_class (wl_a)
    );

    // ------------------------------------------------------------------
    // Instantiate subsystem B
    // ------------------------------------------------------------------
    counters CNT_B (
        .clk            (clk),
        .rst_n          (rst_n),
        .activity_in    (activity_b),
        .stall_in       (stall_b),
        .activity_count (activity_count_b),
        .stall_count    (stall_count_b),
        .window_done    (window_done_b),
        .cycle_count    (cycle_count_b)
    );

    reg_interface REG_B (
        .clk               (clk),
        .rst_n             (rst_n),
        .activity_in       (activity_b),
        .stall_in          (stall_b),
        .temp_in           (temp_b),
        .power_state_in    (grant_b),        // arbiter grant applied here
        .thermal_thresh_in (thresh_b),
        .power_state_out   (applied_state_b),
        .activity_out      (),
        .stall_out         (),
        .temp_out          (),
        .clk_en            (clk_en_b),
        .thermal_thresh_out(thermal_thresh_out_b),
        .thermal_alarm     (thermal_alarm_b)
    );

    power_fsm FSM_B (
        .clk            (clk),
        .rst_n          (rst_n),
        .window_done    (window_done_b),
        .activity_count (activity_count_b),
        .stall_count    (stall_count_b),
        .thermal_alarm  (thermal_alarm_b),
        .power_state_out(req_b),
        .ewma_out       (ewma_b),
        .workload_class (wl_b)
    );

    // ------------------------------------------------------------------
    // Arbiter
    // ------------------------------------------------------------------
    power_arbiter ARB (
        .req_a  (req_a),
        .req_b  (req_b),
        .temp_a (temp_a),
        .temp_b (temp_b),
        .grant_a(grant_a),
        .grant_b(grant_b)
    );

    // ------------------------------------------------------------------
    // Clock generator
    // ------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // Helper: wait for N windows on subsystem A (assumes A/B aligned)
    task wait_windows;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(posedge window_done_a);
                // Allow registers to update
                @(posedge clk);
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Main test
    // ------------------------------------------------------------------
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_power_arbiter);

        $display("=========================================");
        $display("  power_arbiter integration test starting");
        $display("=========================================");

        // init
        rst_n = 0;
        activity_a = 0; stall_a = 0; temp_a = 7'd30; thresh_a = 7'd85;
        activity_b = 0; stall_b = 0; temp_b = 7'd30; thresh_b = 7'd85;

        @(posedge clk); @(posedge clk); @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // ------------------------------------------------------------------
        // TEST 1: Both subsystems run heavy activity for 3 windows -> both
        // request TURBO. Arbiter budget=BUDGET=4. With priority A, expected:
        //   req_a=req_b=3, grant_a=3, grant_b=1
        // ------------------------------------------------------------------
        $display("\n--- TEST 1: Both heavy => arbiter should throttle B ---");
        activity_a = 1; stall_a = 0;
        activity_b = 1; stall_b = 0;

        // Run 3 windows to reach TURBO
        wait_windows(3);

        $display("  req_a=%b req_b=%b  grant_a=%b grant_b=%b  applied_a=%b applied_b=%b",
                  req_a, req_b, grant_a, grant_b, applied_state_a, applied_state_b);

        if (req_a == 2'b11 && req_b == 2'b11 && grant_a == 2'b11 && grant_b == 2'b01)
            $display("  TEST 1 PASSED: Arbiter throttled B as expected");
        else
            $display("  TEST 1 FAILED: Unexpected arbiter/grant behavior <--");

        // ------------------------------------------------------------------
        // TEST 2: Now reduce activity on B so B should be allowed to rise.
        // Set activity_b=0 for 2 windows to drop B, then set activity_b=1
        // again and show arbiter grants both to ACTIVE (2) if budget allows.
        // ------------------------------------------------------------------
        $display("\n--- TEST 2: Reduce B then re-instate; expect sensible grants ---");

        activity_b = 0; // idle B
        wait_windows(2); // allow B to downscale

        // Now B idle, but A still heavy; after a window, A may still request high
        $display("  After B idle: req_a=%b req_b=%b  grant_a=%b grant_b=%b  applied_a=%b applied_b=%b",
                  req_a, req_b, grant_a, grant_b, applied_state_a, applied_state_b);

        // Bring B back to heavy for 1 window and see if both can reach ACTIVE within budget
        activity_b = 1; stall_b = 0;
        wait_windows(2);

        $display("  After B reinstated: req_a=%b req_b=%b  grant_a=%b grant_b=%b  applied_a=%b applied_b=%b",
                  req_a, req_b, grant_a, grant_b, applied_state_a, applied_state_b);

        $display("\n--- Arbiter integration test complete ---\n");

        #20;
        $finish;
    end

endmodule
