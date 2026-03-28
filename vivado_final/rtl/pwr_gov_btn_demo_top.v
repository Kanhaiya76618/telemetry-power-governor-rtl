`timescale 1ns / 1ps

module pwr_gov_btn_demo_top (
    input  wire clk,
    input  wire btn0,
    input  wire btn1,

    output wire led0_b,
    output wire led0_g,
    output wire led0_r,
    output wire led1_b,
    output wire led1_g,
    output wire led1_r
);

    // btn0 is reset (active high when pressed)
    wire rst_n = ~btn0;

    // Synchronize btn1 before using it as a display-page select.
    reg [1:0] btn1_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            btn1_sync <= 2'b00;
        else
            btn1_sync <= {btn1_sync[0], btn1};
    end
    wire show_diag = btn1_sync[1];

    // ---------------------------------------------------------------------
    // Real telemetry source: workload_sim
    // ---------------------------------------------------------------------
    // workload_sim advances phases on a 100-cycle window_done pulse.
    // Generate that pulse here so the workload engine runs on-board.
    reg [6:0] ws_cycle_count;
    reg       ws_window_done;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ws_cycle_count <= 7'd0;
            ws_window_done <= 1'b0;
        end else begin
            ws_window_done <= 1'b0;
            if (ws_cycle_count == 7'd99) begin
                ws_cycle_count <= 7'd0;
                ws_window_done <= 1'b1;
            end else begin
                ws_cycle_count <= ws_cycle_count + 7'd1;
            end
        end
    end

    wire       act_a;
    wire       stall_a;
    wire       act_b;
    wire       stall_b;
    wire [6:0] temp_a;
    wire [6:0] temp_b;
    wire [2:0] ws_phase;
    wire       ws_phase_done;

    workload_sim WS (
        .clk(clk),
        .rst_n(rst_n),
        .window_done(ws_window_done),
        .activity_a(act_a),
        .stall_a(stall_a),
        .activity_b(act_b),
        .stall_b(stall_b),
        .temp_a(temp_a),
        .temp_b(temp_b),
        .phase_out(ws_phase),
        .phase_done(ws_phase_done)
    );

    wire [1:0] grant_a;
    wire [1:0] grant_b;
    wire       clk_en_a;
    wire       clk_en_b;
    wire [2:0] current_budget;
    wire [2:0] budget_headroom;
    wire [9:0] system_efficiency;
    wire       alarm_a;
    wire       alarm_b;

    // Always telemetry-driven (no external request override)
    wire [1:0] req_a = 2'b00;
    wire [1:0] req_b = 2'b00;
    wire [2:0] ext_budget_in = 3'd4;
    wire       use_ext_budget = 1'b0;

    pwr_gov_top DUT (
        .clk(clk),
        .rst_n(rst_n),
        .act_a(act_a),
        .stall_a(stall_a),
        .req_a(req_a),
        .temp_a(temp_a),
        .act_b(act_b),
        .stall_b(stall_b),
        .req_b(req_b),
        .temp_b(temp_b),
        .ext_budget_in(ext_budget_in),
        .use_ext_budget(use_ext_budget),
        .grant_a(grant_a),
        .grant_b(grant_b),
        .clk_en_a(clk_en_a),
        .clk_en_b(clk_en_b),
        .current_budget(current_budget),
        .budget_headroom(budget_headroom),
        .system_efficiency(system_efficiency),
        .alarm_a(alarm_a),
        .alarm_b(alarm_b)
    );

    // RGB LED mapping
    // BTN1=0: show governor outputs
    // BTN1=1: show telemetry diagnostics (phase + alarms + window pulse)
    wire led0_b_ctrl = grant_a[0];
    wire led0_g_ctrl = grant_a[1];
    wire led0_r_ctrl = grant_b[0];
    wire led1_b_ctrl = grant_b[1];
    wire led1_g_ctrl = clk_en_a;
    wire led1_r_ctrl = clk_en_b;

    wire led0_b_diag = ws_phase[0];
    wire led0_g_diag = ws_phase[1];
    wire led0_r_diag = ws_phase[2];
    wire led1_b_diag = alarm_a;
    wire led1_g_diag = alarm_b;
    wire led1_r_diag = ws_phase_done;

    assign led0_b = show_diag ? led0_b_diag : led0_b_ctrl;
    assign led0_g = show_diag ? led0_g_diag : led0_g_ctrl;
    assign led0_r = show_diag ? led0_r_diag : led0_r_ctrl;
    assign led1_b = show_diag ? led1_b_diag : led1_b_ctrl;
    assign led1_g = show_diag ? led1_g_diag : led1_g_ctrl;
    assign led1_r = show_diag ? led1_r_diag : led1_r_ctrl;

endmodule
