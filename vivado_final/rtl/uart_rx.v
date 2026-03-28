`timescale 1ns / 1ps

module uart_rx #(
    parameter integer CLK_HZ = 125_000_000,
    parameter integer BAUD   = 115200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] data_out,
    output reg        data_valid
);

    localparam integer CLKS_PER_BIT  = CLK_HZ / BAUD;
    localparam integer HALF_BIT_CLKS = CLKS_PER_BIT / 2;

    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_START = 2'd1;
    localparam [1:0] ST_DATA  = 2'd2;
    localparam [1:0] ST_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] bit_clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shreg;

    reg rx_sync_0, rx_sync_1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync_0 <= 1'b1;
            rx_sync_1 <= 1'b1;
        end else begin
            rx_sync_0 <= rx;
            rx_sync_1 <= rx_sync_0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            bit_clk_cnt <= 16'd0;
            bit_idx     <= 3'd0;
            shreg       <= 8'd0;
            data_out    <= 8'd0;
            data_valid  <= 1'b0;
        end else begin
            data_valid <= 1'b0;

            case (state)
                ST_IDLE: begin
                    bit_clk_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    if (!rx_sync_1)
                        state <= ST_START;
                end

                ST_START: begin
                    if (bit_clk_cnt == HALF_BIT_CLKS - 1) begin
                        bit_clk_cnt <= 16'd0;
                        if (!rx_sync_1)
                            state <= ST_DATA;
                        else
                            state <= ST_IDLE;
                    end else begin
                        bit_clk_cnt <= bit_clk_cnt + 16'd1;
                    end
                end

                ST_DATA: begin
                    if (bit_clk_cnt == CLKS_PER_BIT - 1) begin
                        bit_clk_cnt <= 16'd0;
                        shreg <= {rx_sync_1, shreg[7:1]};
                        if (bit_idx == 3'd7) begin
                            bit_idx <= 3'd0;
                            state <= ST_STOP;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                        end
                    end else begin
                        bit_clk_cnt <= bit_clk_cnt + 16'd1;
                    end
                end

                ST_STOP: begin
                    if (bit_clk_cnt == CLKS_PER_BIT - 1) begin
                        bit_clk_cnt <= 16'd0;
                        state <= ST_IDLE;
                        if (rx_sync_1) begin
                            data_out <= shreg;
                            data_valid <= 1'b1;
                        end
                    end else begin
                        bit_clk_cnt <= bit_clk_cnt + 16'd1;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
