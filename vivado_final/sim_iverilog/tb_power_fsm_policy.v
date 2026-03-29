`timescale 1ns / 1ps

module tb_power_fsm_policy;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg window_done = 1'b0;
    reg [6:0] activity_count = 7'd0;
    reg [6:0] stall_count = 7'd0;
    reg thermal_alarm = 1'b0;

    wire [1:0] power_state_out;
    wire [6:0] ewma_out;
    wire [1:0] workload_class;

    integer fail_count;

    localparam STATE_SLEEP = 2'b00;
    localparam STATE_LOW_POWER = 2'b01;
    localparam STATE_ACTIVE = 2'b10;
    localparam STATE_TURBO = 2'b11;

    power_fsm dut (
        .clk(clk),
        .rst_n(rst_n),
        .window_done(window_done),
        .activity_count(activity_count),
        .stall_count(stall_count),
        .thermal_alarm(thermal_alarm),
        .power_state_out(power_state_out),
        .ewma_out(ewma_out),
        .workload_class(workload_class)
    );

    always #5 clk = ~clk;

    task send_window;
        input [6:0] act_cnt;
        input [6:0] stl_cnt;
        input therm;
        begin
            activity_count = act_cnt;
            stall_count = stl_cnt;
            thermal_alarm = therm;

            @(negedge clk);
            window_done = 1'b1;
            @(posedge clk);
            @(negedge clk);
            window_done = 1'b0;
            @(posedge clk);
        end
    endtask

    task expect_state;
        input [1:0] expected;
        input [127:0] label;
        begin
            if (power_state_out !== expected) begin
                fail_count = fail_count + 1;
                $display("TB_FAIL: %0s expected=%b got=%b", label, expected, power_state_out);
            end
        end
    endtask

    initial begin
        fail_count = 0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        expect_state(STATE_SLEEP, "reset state");

        send_window(7'd80, 7'd5, 1'b0);
        expect_state(STATE_LOW_POWER, "upscale step 1");
        send_window(7'd80, 7'd5, 1'b0);
        expect_state(STATE_ACTIVE, "upscale step 2");
        send_window(7'd80, 7'd5, 1'b0);
        expect_state(STATE_TURBO, "upscale step 3");

        send_window(7'd10, 7'd0, 1'b0);
        expect_state(STATE_ACTIVE, "downscale step 1");
        send_window(7'd10, 7'd0, 1'b0);
        expect_state(STATE_LOW_POWER, "downscale step 2");
        send_window(7'd10, 7'd0, 1'b0);
        expect_state(STATE_SLEEP, "downscale step 3");

        send_window(7'd80, 7'd5, 1'b0);
        send_window(7'd80, 7'd5, 1'b0);
        send_window(7'd80, 7'd5, 1'b0);
        expect_state(STATE_TURBO, "re-upscale before thermal override");

        send_window(7'd80, 7'd5, 1'b1);
        expect_state(STATE_LOW_POWER, "thermal override");

        if (fail_count == 0)
            $display("TB_PASS: power_fsm policy transitions verified");
        else
            $display("TB_FAIL: power_fsm policy found %0d issue(s)", fail_count);

        $finish;
    end
endmodule
