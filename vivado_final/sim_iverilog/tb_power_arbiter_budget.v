`timescale 1ns / 1ps

module tb_power_arbiter_budget;
    reg clk = 1'b0;
    reg rst_n = 1'b1;
    reg [1:0] req_a = 2'b00;
    reg [1:0] req_b = 2'b00;
    reg [6:0] temp_a = 7'd30;
    reg [6:0] temp_b = 7'd30;
    reg [2:0] global_budget_in = 3'd4;

    wire [1:0] grant_a;
    wire [1:0] grant_b;
    wire [2:0] budget_headroom;

    integer fail_count;

    power_arbiter dut (
        .clk(clk),
        .rst_n(rst_n),
        .req_a(req_a),
        .req_b(req_b),
        .temp_a(temp_a),
        .temp_b(temp_b),
        .global_budget_in(global_budget_in),
        .grant_a(grant_a),
        .grant_b(grant_b),
        .budget_headroom(budget_headroom)
    );

    always #5 clk = ~clk;

    task expect_vals;
        input [1:0] exp_a;
        input [1:0] exp_b;
        input [2:0] exp_h;
        input [127:0] label;
        begin
            #1;
            if (grant_a !== exp_a || grant_b !== exp_b || budget_headroom !== exp_h) begin
                fail_count = fail_count + 1;
                $display("TB_FAIL: %0s expected ga=%0d gb=%0d h=%0d got ga=%0d gb=%0d h=%0d",
                         label, exp_a, exp_b, exp_h, grant_a, grant_b, budget_headroom);
            end
        end
    endtask

    initial begin
        fail_count = 0;

        req_a = 2'd2;
        req_b = 2'd1;
        temp_a = 7'd40;
        temp_b = 7'd40;
        global_budget_in = 3'd4;
        expect_vals(2'd2, 2'd1, 3'd1, "no conflict with headroom");

        req_a = 2'd3;
        req_b = 2'd2;
        temp_a = 7'd35;
        temp_b = 7'd60;
        global_budget_in = 3'd3;
        expect_vals(2'd3, 2'd0, 3'd0, "conflict, A cooler gets priority");

        req_a = 2'd2;
        req_b = 2'd3;
        temp_a = 7'd70;
        temp_b = 7'd33;
        global_budget_in = 3'd3;
        expect_vals(2'd0, 2'd3, 3'd0, "conflict, B cooler gets priority");

        req_a = 2'd3;
        req_b = 2'd3;
        temp_a = 7'd50;
        temp_b = 7'd50;
        global_budget_in = 3'd3;
        expect_vals(2'd3, 2'd0, 3'd0, "temperature tie gives A priority");

        if (fail_count == 0)
            $display("TB_PASS: power_arbiter budget and thermal priority verified");
        else
            $display("TB_FAIL: power_arbiter found %0d issue(s)", fail_count);

        $finish;
    end
endmodule
