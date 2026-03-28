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

    // Synchronize btn1 before using it as a mode select.
    reg [1:0] btn1_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            btn1_sync <= 2'b00;
        else
            btn1_sync <= {btn1_sync[0], btn1};
    end
    wire mode_ext = btn1_sync[1];

    // Slow phase counter so LED behavior is human-visible.
    reg [26:0] phase_div;
    reg [1:0]  phase;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_div <= 27'd0;
            phase     <= 2'd0;
        end else begin
            if (phase_div == 27'd99_999_999) begin
                phase_div <= 27'd0;
                phase     <= phase + 2'd1;
            end else begin
                phase_div <= phase_div + 27'd1;
            end
        end
    end

    // Stimulus wires into the real top-level governor.
    reg        act_a;
    reg        stall_a;
    reg [1:0]  req_a;
    reg [6:0]  temp_a;

    reg        act_b;
    reg        stall_b;
    reg [1:0]  req_b;
    reg [6:0]  temp_b;

    reg [2:0]  ext_budget_in;
    reg        use_ext_budget;

    always @(*) begin
        // Safe defaults
        act_a         = 1'b0;
        stall_a       = 1'b0;
        req_a         = 2'b00;
        temp_a        = 7'd30;

        act_b         = 1'b0;
        stall_b       = 1'b0;
        req_b         = 2'b00;
        temp_b        = 7'd30;

        ext_budget_in = 3'd4;
        use_ext_budget = mode_ext;

        if (mode_ext) begin
            // BTN1 = 1: direct external mode patterns
            case (phase)
                2'd0: begin
                    ext_budget_in = 3'd6;
                    req_a         = 2'b01;
                    req_b         = 2'b00;
                    act_a         = 1'b1;
                end
                2'd1: begin
                    ext_budget_in = 3'd6;
                    req_a         = 2'b11;
                    req_b         = 2'b01;
                    act_a         = 1'b1;
                    act_b         = 1'b1;
                end
                2'd2: begin
                    ext_budget_in = 3'd3;
                    req_a         = 2'b11;
                    req_b         = 2'b11;
                    temp_a        = 7'd35;
                    temp_b        = 7'd70;
                    act_a         = 1'b1;
                    act_b         = 1'b1;
                end
                default: begin
                    ext_budget_in = 3'd2;
                    req_a         = 2'b10;
                    req_b         = 2'b11;
                    temp_a        = 7'd75;
                    temp_b        = 7'd35;
                    act_a         = 1'b1;
                    act_b         = 1'b1;
                end
            endcase
        end else begin
            // BTN1 = 0: autonomous mode patterns (FSM + feedback active)
            case (phase)
                2'd0: begin
                    act_a   = 1'b0;
                    act_b   = 1'b0;
                    stall_a = 1'b0;
                    stall_b = 1'b0;
                    temp_a  = 7'd30;
                    temp_b  = 7'd30;
                end
                2'd1: begin
                    act_a   = 1'b1;
                    act_b   = 1'b0;
                    stall_a = 1'b0;
                    stall_b = 1'b0;
                    temp_a  = 7'd35;
                    temp_b  = 7'd35;
                end
                2'd2: begin
                    act_a   = 1'b1;
                    act_b   = 1'b1;
                    stall_a = 1'b0;
                    stall_b = 1'b1;
                    temp_a  = 7'd45;
                    temp_b  = 7'd55;
                end
                default: begin
                    act_a   = 1'b1;
                    act_b   = 1'b1;
                    stall_a = 1'b1;
                    stall_b = 1'b1;
                    temp_a  = 7'd40;
                    temp_b  = 7'd92;
                end
            endcase
        end
    end

    wire [1:0] grant_a;
    wire [1:0] grant_b;
    wire       clk_en_a;
    wire       clk_en_b;
    wire [2:0] current_budget;
    wire [2:0] budget_headroom;
    wire [9:0] system_efficiency;
    wire       alarm_a;
    wire       alarm_b;

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
    assign led0_b = grant_a[0];
    assign led0_g = grant_a[1];
    assign led0_r = grant_b[0];

    assign led1_b = grant_b[1];
    assign led1_g = clk_en_a;
    assign led1_r = clk_en_b;

endmodule
