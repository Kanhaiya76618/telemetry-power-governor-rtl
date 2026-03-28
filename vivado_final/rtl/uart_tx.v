`timescale 1ns / 1ps

module uart_tx #(
    parameter integer CLK_HZ = 125_000_000,
    parameter integer BAUD   = 115200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data_in,
    input  wire       data_valid,
    output reg        tx,
    output reg        busy
);

    localparam integer CLKS_PER_BIT = CLK_HZ / BAUD;
    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_START = 2'd1;
    localparam [1:0] ST_DATA  = 2'd2;
    localparam [1:0] ST_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] bit_clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shreg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx          <= 1'b1;
            busy        <= 1'b0;
            state       <= ST_IDLE;
            bit_clk_cnt <= 16'd0;
            bit_idx     <= 3'd0;
            shreg       <= 8'd0;
        end else begin
            case (state)
                ST_IDLE: begin
                    tx   <= 1'b1;
                    busy <= 1'b0;
                    bit_clk_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    if (data_valid) begin
                        shreg <= data_in;
                        busy  <= 1'b1;
                        state <= ST_START;
                    end
                end

                ST_START: begin
                    tx <= 1'b0;
                    if (bit_clk_cnt == CLKS_PER_BIT - 1) begin
                        bit_clk_cnt <= 16'd0;
                        state <= ST_DATA;
                    end else begin
                        bit_clk_cnt <= bit_clk_cnt + 16'd1;
                    end
                end

                ST_DATA: begin
                    tx <= shreg[0];
                    if (bit_clk_cnt == CLKS_PER_BIT - 1) begin
                        bit_clk_cnt <= 16'd0;
                        shreg <= {1'b0, shreg[7:1]};
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
                    tx <= 1'b1;
                    if (bit_clk_cnt == CLKS_PER_BIT - 1) begin
                        bit_clk_cnt <= 16'd0;
                        busy <= 1'b0;
                        state <= ST_IDLE;
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
