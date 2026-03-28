/*
 * pwr_gov_top.v
 *
 * Top-level SoC Wrapper for pixel.ai Power Governor.
 * Integrates: 2x Cores (FSMs, Counters, Regs), Arbiter, Feedback, and Logger.
 */

module pwr_gov_top (
    input  wire        clk,
    input  wire        rst_n,

    // Telemetry & Control Inputs from Subsystem A
    input  wire        act_a,
    input  wire        stall_a,
    input  wire [1:0]  req_a,
    input  wire [6:0]  temp_a,
    // Telemetry & Control Inputs from Subsystem B
    input  wire        act_b,
    input  wire        stall_b,
    input  wire [1:0]  req_b,
    input  wire [6:0]  temp_b,

    // External Budget Control (for manual overrides)
    input  wire [2:0]  ext_budget_in,
    input  wire        use_ext_budget,

    // Control Outputs
    output wire [1:0]  grant_a,
    output wire [1:0]  grant_b,
    output wire        clk_en_a,
    output wire        clk_en_b,

    // Status / Telemetry Outputs
    output wire [2:0]  current_budget,
    output wire [2:0]  budget_headroom,
    output wire [9:0]  system_efficiency,
    output wire        alarm_a,
    output wire        alarm_b
);

    // -------------------------------------------------------------------------
    // Internal Wires (The "Glue")
    // -------------------------------------------------------------------------
    wire [1:0] fsm_req_a, fsm_req_b;
    wire [1:0] applied_state_a, applied_state_b;
    wire [6:0] activity_count_a, stall_count_a;
    wire [6:0] activity_count_b, stall_count_b;
    wire       window_done_a, window_done_b;
    wire [2:0] dynamic_budget;
    wire [1:0] perf_penalty;
    wire       budget_relax, budget_tighten;

    // Use either the internal dynamic budget or an external override
    wire [2:0] active_budget = use_ext_budget ? ext_budget_in : dynamic_budget;
    assign current_budget = active_budget;

    // -------------------------------------------------------------------------
    // Core A: Monitoring & Control
    // -------------------------------------------------------------------------
    counters CORE_A_CNT (
        .clk(clk), .rst_n(rst_n),
        .activity_in(act_a), .stall_in(stall_a),
        .activity_count(activity_count_a), .stall_count(stall_count_a),
        .window_done(window_done_a)
    );

    power_fsm CORE_A_FSM (
        .clk(clk), .rst_n(rst_n),
        .window_done(window_done_a),
        .activity_count(activity_count_a), .stall_count(stall_count_a),
        .thermal_alarm(alarm_a),
        .power_state_out(fsm_req_a)
    );

    reg_interface CORE_A_REG (
        .clk(clk), .rst_n(rst_n),
        .activity_in(act_a), .stall_in(stall_a), .temp_in(temp_a),
        .power_state_in(grant_a),
        .thermal_thresh_in(7'd85),
        .power_state_out(applied_state_a),
        .clk_en(clk_en_a),
        .thermal_alarm(alarm_a)
    );

    // -------------------------------------------------------------------------
    // Core B: Monitoring & Control
    // -------------------------------------------------------------------------
    counters CORE_B_CNT (
        .clk(clk), .rst_n(rst_n),
        .activity_in(act_b), .stall_in(stall_b),
        .activity_count(activity_count_b), .stall_count(stall_count_b),
        .window_done(window_done_b)
    );

    power_fsm CORE_B_FSM (
        .clk(clk), .rst_n(rst_n),
        .window_done(window_done_b),
        .activity_count(activity_count_b), .stall_count(stall_count_b),
        .thermal_alarm(alarm_b),
        .power_state_out(fsm_req_b)
    );

    reg_interface CORE_B_REG (
        .clk(clk), .rst_n(rst_n),
        .activity_in(act_b), .stall_in(stall_b), .temp_in(temp_b),
        .power_state_in(grant_b),
        .thermal_thresh_in(7'd85),
        .power_state_out(applied_state_b),
        .clk_en(clk_en_b),
        .thermal_alarm(alarm_b)
    );

    // -------------------------------------------------------------------------
    // Global Power Management
    // -------------------------------------------------------------------------
    
    // Choose between FSM-driven requests (runtime) or External overrides (tests)
    wire [1:0] arb_req_a = use_ext_budget ? req_a : fsm_req_a;
    wire [1:0] arb_req_b = use_ext_budget ? req_b : fsm_req_b;

    power_arbiter ARBITER (
        .clk               (clk),
        .rst_n             (rst_n),
        .req_a             (arb_req_a),
        .req_b             (arb_req_b),
        .temp_a            (temp_a),
        .temp_b            (temp_b),
        .global_budget_in  (active_budget),
        .grant_a           (grant_a),
        .grant_b           (grant_b),
        .budget_headroom   (budget_headroom)
    );

    perf_feedback FEEDBACK (
        .clk(clk), .rst_n(rst_n),
        .window_done(window_done_a),
        .req_a(fsm_req_a), .grant_a(grant_a),
        .req_b(fsm_req_b), .grant_b(grant_b),
        .budget_headroom(budget_headroom),
        .perf_penalty(perf_penalty),
        .budget_relax(budget_relax),
        .budget_tighten(budget_tighten)
    );

    // Simple Budget Logic (Normally in a separate Reg File, but here for Top-Level)
    reg [2:0] budget_reg;
    always @(posedge clk) begin
        if (!rst_n) budget_reg <= 3'd4;
        else if (budget_relax && budget_reg < 3'd7) budget_reg <= budget_reg + 1;
        else if (budget_tighten && budget_reg > 3'd1) budget_reg <= budget_reg - 1;
    end
    assign dynamic_budget = budget_reg;

    power_logger LOGGER (
        .clk(clk), .rst_n(rst_n),
        .window_done(window_done_a),
        .state_a(applied_state_a), .state_b(applied_state_b),
        .activity_count_a(activity_count_a), .activity_count_b(activity_count_b),
        .perf_penalty(perf_penalty),
        .efficiency(system_efficiency)
    );

endmodule
