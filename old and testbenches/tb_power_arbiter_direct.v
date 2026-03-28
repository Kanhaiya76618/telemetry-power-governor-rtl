// =============================================================================
// FILE: tb_power_arbiter_direct.v
// PURPOSE: Direct arbiter integration test; drives window_done + counts into
//          two `power_fsm` instances and checks `power_arbiter` grants.
// =============================================================================

`timescale 1ns / 1ps

module tb_power_arbiter_direct;

    // Clock & reset
    reg clk;
    reg rst_n;

    // Stimulus for reg_interface (for clk_en visibility)
    reg activity_a, stall_a;
    reg activity_b, stall_b;

    // Thermal inputs
    reg [6:0] temp_a, temp_b;
    reg [6:0] thresh_a, thresh_b;

    // Inputs directly fed to FSMs
    reg [6:0] activity_count_a, stall_count_a;
    reg [6:0] activity_count_b, stall_count_b;
    reg window_done_a, window_done_b;
    reg thermal_alarm_a, thermal_alarm_b; // also can be driven by reg_interface in full design

    // FSM requests
    wire [1:0] req_a, req_b;
    wire [6:0] ewma_a, ewma_b;
    wire [1:0] wl_a, wl_b;

    // Arbiter grants
    wire [1:0] grant_a, grant_b;

    // Reg_interface applied states (for visibility)
    wire [1:0] applied_state_a, applied_state_b;
    wire clk_en_a, clk_en_b;

    // ------------------------------------------------------------------
    // Instantiate reg_interfaces (they will show applied grants)
    // ------------------------------------------------------------------
    reg_interface REG_A (
        .clk               (clk),
        .rst_n             (rst_n),
        .activity_in       (activity_a),
        .stall_in          (stall_a),
        .temp_in           (temp_a),
        .power_state_in    (grant_a),
        .thermal_thresh_in (thresh_a),
        .power_state_out   (applied_state_a),
        .activity_out      (),
        .stall_out         (),
        .temp_out          (),
        .clk_en            (clk_en_a),
        .thermal_thresh_out(),
        .thermal_alarm     ()
    );

    reg_interface REG_B (
        .clk               (clk),
        .rst_n             (rst_n),
        .activity_in       (activity_b),
        .stall_in          (stall_b),
        .temp_in           (temp_b),
        .power_state_in    (grant_b),
        .thermal_thresh_in (thresh_b),
        .power_state_out   (applied_state_b),
        .activity_out      (),
        .stall_out         (),
        .temp_out          (),
        .clk_en            (clk_en_b),
        .thermal_thresh_out(),
        .thermal_alarm     ()
    );

    // ------------------------------------------------------------------
    // Instantiate two FSMs
    // ------------------------------------------------------------------
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
    // Clock
    // ------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // Helper: send a window to both FSMs (present counts then pulse)
    task send_window;
        input [6:0] act_a, stl_a;
        input [6:0] act_b, stl_b;
        input       therm_a, therm_b;
        begin
            activity_count_a = act_a;
            stall_count_a    = stl_a;
            activity_count_b = act_b;
            stall_count_b    = stl_b;
            thermal_alarm_a  = therm_a;
            thermal_alarm_b  = therm_b;

            // Pulse window_done HIGH for one clock
            @(negedge clk);
            window_done_a = 1'b1;
            window_done_b = 1'b1;
            @(posedge clk); // FSM samples here
            @(negedge clk);
            window_done_a = 1'b0;
            window_done_b = 1'b0;

            // Wait a cycle for everything to settle
            @(posedge clk);
        end
    endtask

    // ------------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------------
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_power_arbiter_direct);

        $display("=========================================");
        $display("  Direct arbiter integration test starting");
        $display("=========================================");

        // init
        rst_n = 0;
        activity_a = 0; stall_a = 0; temp_a = 7'd30; thresh_a = 7'd85;
        activity_b = 0; stall_b = 0; temp_b = 7'd30; thresh_b = 7'd85;

        window_done_a = 0; window_done_b = 0;
        activity_count_a = 0; stall_count_a = 0;
        activity_count_b = 0; stall_count_b = 0;
        thermal_alarm_a = 0; thermal_alarm_b = 0;

        @(posedge clk); @(posedge clk); @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // ------------------------------------------------------------------
        // TEST 1: both request TURBO (act=80)
        // ------------------------------------------------------------------
        $display("\n--- TEST 1: Both request TURBO; arbiter should throttle B ---");
        // three windows of heavy activity to step from SLEEP->LOW->ACT->TURBO
        send_window(7'd80, 7'd0, 7'd80, 7'd0, 1'b0, 1'b0);
        send_window(7'd80, 7'd0, 7'd80, 7'd0, 1'b0, 1'b0);
        send_window(7'd80, 7'd0, 7'd80, 7'd0, 1'b0, 1'b0);

        $display("  req_a=%b req_b=%b  grant_a=%b grant_b=%b  applied_a=%b applied_b=%b",
                  req_a, req_b, grant_a, grant_b, applied_state_a, applied_state_b);

        if (req_a == 2'b11 && req_b == 2'b11 && grant_a == 2'b11 && grant_b == 2'b01)
            $display("  TEST 1 PASSED: Arbiter throttled B as expected");
        else
            $display("  TEST 1 FAILED: Unexpected arbiter/grant behavior <--");

        // ------------------------------------------------------------------
        // TEST 2: both request ACTIVE (act=80 for two windows), sum==4 -> allowed
        // Reset to SLEEP and test both up two windows
        // ------------------------------------------------------------------
        $display("\n--- TEST 2: Both request ACTIVE -> budget allows both ACTIVE ---");

        rst_n = 0; @(posedge clk); rst_n = 1; @(posedge clk);

        send_window(7'd80,7'd0, 7'd80,7'd0, 1'b0, 1'b0);
        send_window(7'd80,7'd0, 7'd80,7'd0, 1'b0, 1'b0);

        $display("  req_a=%b req_b=%b  grant_a=%b grant_b=%b  applied_a=%b applied_b=%b",
                  req_a, req_b, grant_a, grant_b, applied_state_a, applied_state_b);

        if (req_a == 2'b10 && req_b == 2'b10 && grant_a == 2'b10 && grant_b == 2'b10)
            $display("  TEST 2 PASSED: Both granted ACTIVE");
        else
            $display("  TEST 2 FAILED: Unexpected arbiter/grant behavior <--");

        $display("\nDirect arbiter tests complete.\n");

        #20; $finish;
    end

endmodule
