`timescale 1ns / 1ps

module tb_reg_interface_thermal;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg activity_in = 1'b0;
    reg stall_in = 1'b0;
    reg [6:0] temp_in = 7'd25;
    reg [1:0] power_state_in = 2'b00;
    reg [6:0] thermal_thresh_in = 7'd85;

    wire [1:0] power_state_out;
    wire activity_out;
    wire stall_out;
    wire [6:0] temp_out;
    wire clk_en;
    wire [6:0] thermal_thresh_out;
    wire thermal_alarm;

    integer fail_count;

    reg_interface dut (
        .clk(clk),
        .rst_n(rst_n),
        .activity_in(activity_in),
        .stall_in(stall_in),
        .temp_in(temp_in),
        .power_state_in(power_state_in),
        .thermal_thresh_in(thermal_thresh_in),
        .power_state_out(power_state_out),
        .activity_out(activity_out),
        .stall_out(stall_out),
        .temp_out(temp_out),
        .clk_en(clk_en),
        .thermal_thresh_out(thermal_thresh_out),
        .thermal_alarm(thermal_alarm)
    );

    always #5 clk = ~clk;

    task step;
        begin
            @(posedge clk);
            @(posedge clk);
        end
    endtask

    task expect_bit;
        input actual;
        input expected;
        input [127:0] label;
        begin
            if (actual !== expected) begin
                fail_count = fail_count + 1;
                $display("TB_FAIL: %0s expected=%b got=%b", label, expected, actual);
            end
        end
    endtask

    initial begin
        fail_count = 0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        step();

        power_state_in = 2'b00;
        activity_in = 1'b0;
        step();
        expect_bit(clk_en, 1'b0, "sleep clk_en");

        power_state_in = 2'b01;
        activity_in = 1'b0;
        step();
        expect_bit(clk_en, 1'b0, "low power no activity");

        power_state_in = 2'b01;
        activity_in = 1'b1;
        step();
        expect_bit(clk_en, 1'b1, "low power with activity");

        thermal_thresh_in = 7'd85;
        temp_in = 7'd90;
        power_state_in = 2'b10;
        step();
        expect_bit(thermal_alarm, 1'b1, "thermal alarm assert");

        temp_in = 7'd60;
        step();
        expect_bit(thermal_alarm, 1'b0, "thermal alarm clear");

        if (fail_count == 0)
            $display("TB_PASS: reg_interface thermal and clk_en behavior verified");
        else
            $display("TB_FAIL: reg_interface found %0d issue(s)", fail_count);

        $finish;
    end
endmodule
