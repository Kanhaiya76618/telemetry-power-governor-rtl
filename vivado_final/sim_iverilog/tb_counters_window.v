`timescale 1ns / 1ps

module tb_counters_window;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg activity_in = 1'b0;
    reg stall_in = 1'b0;

    wire [6:0] activity_count;
    wire [6:0] stall_count;
    wire window_done;
    wire [6:0] cycle_count;

    integer i;
    integer fail_count;
    integer pulse_count;

    counters dut (
        .clk(clk),
        .rst_n(rst_n),
        .activity_in(activity_in),
        .stall_in(stall_in),
        .activity_count(activity_count),
        .stall_count(stall_count),
        .window_done(window_done),
        .cycle_count(cycle_count)
    );

    always #5 clk = ~clk;

    initial begin
        fail_count = 0;
        pulse_count = 0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        activity_in = 1'b1;
        stall_in = 1'b0;

        for (i = 0; i < 110; i = i + 1) begin
            @(posedge clk);
            if (window_done) begin
                pulse_count = pulse_count + 1;
                if (activity_count < 7'd99) begin
                    fail_count = fail_count + 1;
                    $display("TB_FAIL: activity_count too low at window boundary: %0d", activity_count);
                end
            end
        end

        if (pulse_count != 1) begin
            fail_count = fail_count + 1;
            $display("TB_FAIL: window_done pulse count expected 1, got %0d", pulse_count);
        end

        activity_in = 1'b0;
        stall_in = 1'b1;
        repeat (20) @(posedge clk);

        if (stall_count == 7'd0) begin
            fail_count = fail_count + 1;
            $display("TB_FAIL: stall_count did not increment under stall stimulus");
        end

        if (fail_count == 0)
            $display("TB_PASS: counters windowing and pulse behavior verified");
        else
            $display("TB_FAIL: counters windowing found %0d issue(s)", fail_count);

        $finish;
    end
endmodule
