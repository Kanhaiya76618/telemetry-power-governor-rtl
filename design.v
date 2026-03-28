// =============================================================================
// FILE: design.sv
// Contains: power_fsm, power_arbiter, counters, reg_interface
// =============================================================================

`timescale 1ns / 1ps

// ---------------------------------------------------------------------------
// GLOBAL POWER-STATE DEFINES
// Defined once here at the top to avoid re-definition errors.
// ---------------------------------------------------------------------------
`define STATE_SLEEP     2'b00
`define STATE_LOW_POWER 2'b01
`define STATE_ACTIVE    2'b10
`define STATE_TURBO     2'b11


// =============================================================================
// MODULE 1: power_fsm
// =============================================================================
module power_fsm (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        window_done,
    input  wire [6:0]  activity_count,
    input  wire [6:0]  stall_count,
    input  wire        thermal_alarm,
    output reg  [1:0]  power_state_out,
    output reg  [6:0]  ewma_out,
    output reg  [1:0]  workload_class
);

    localparam STATE_SLEEP     = 2'b00;
    localparam STATE_LOW_POWER = 2'b01;
    localparam STATE_ACTIVE    = 2'b10;
    localparam STATE_TURBO     = 2'b11;

    localparam ACT_HIGH   = 7'd75;
    localparam ACT_LOW    = 7'd20;
    localparam STALL_HIGH = 7'd50;

    // P3: DWELL = 3 means FSM must see condition for 3 consecutive windows
    localparam DWELL = 3'd3;

    reg [2:0] up_dwell, dn_dwell;
    reg [9:0] ewma_accum;

    localparam WL_IDLE      = 2'b00;
    localparam WL_BURSTY    = 2'b01;
    localparam WL_COMPUTE   = 2'b10;
    localparam WL_SUSTAINED = 2'b11;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            power_state_out <= STATE_SLEEP;
            up_dwell        <= 3'd0;
            dn_dwell        <= 3'd0;
            ewma_accum      <= 10'd0;
            ewma_out        <= 7'd0;
            workload_class  <= WL_IDLE;

        end else if (window_done) begin

            // P2: Thermal override — highest priority
            if (thermal_alarm) begin
                if (power_state_out > STATE_LOW_POWER)
                    power_state_out <= STATE_LOW_POWER;
                up_dwell <= 3'd0;
                dn_dwell <= 3'd0;

            end else begin
                // P4+P3: Upscale with EWMA predictor + dwell guard
                if ((activity_count >= ACT_HIGH || ewma_out >= ACT_HIGH) && stall_count < STALL_HIGH) begin
                    up_dwell <= up_dwell + 3'd1;
                    dn_dwell <= 3'd0;
                    if (up_dwell >= (DWELL - 1)) begin
                        if (power_state_out != STATE_TURBO)
                            power_state_out <= power_state_out + 2'b01;
                        up_dwell <= 3'd0;
                    end

                // P3: Downscale with dwell guard
                end else if (activity_count < ACT_LOW) begin
                    dn_dwell <= dn_dwell + 3'd1;
                    up_dwell <= 3'd0;
                    if (dn_dwell >= (DWELL - 1)) begin
                        if (power_state_out != STATE_SLEEP)
                            power_state_out <= power_state_out - 2'b01;
                        dn_dwell <= 3'd0;
                    end

                end else begin
                    // Mid-range: reset both dwell counters
                    up_dwell <= 3'd0;
                    dn_dwell <= 3'd0;
                end
            end

            // P4: Update EWMA accumulator (alpha = 1/8)
            ewma_accum <= ewma_accum - (ewma_accum >> 3) + activity_count;
            ewma_out   <= ewma_accum[9:3];

            // P5: Workload classification
            if (activity_count < 7'd20)
                workload_class <= WL_IDLE;
            else if (activity_count > 7'd60 && stall_count < 7'd20)
                workload_class <= WL_COMPUTE;
            else if (activity_count > 7'd75 && stall_count < 7'd40)
                workload_class <= WL_SUSTAINED;
            else
                workload_class <= WL_BURSTY;

        end
    end

endmodule


// =============================================================================
// MODULE 2: power_arbiter
// =============================================================================
module power_arbiter (
    input  wire [1:0] req_a,
    input  wire [1:0] req_b,
    input  wire [6:0] temp_a,
    input  wire [6:0] temp_b,
    output reg  [1:0] grant_a,
    output reg  [1:0] grant_b
);

    localparam [2:0] BUDGET = 3'd4;

    wire [2:0] total_requested = {1'b0, req_a} + {1'b0, req_b};
    reg  [2:0] remaining;

    always @(*) begin
        if (total_requested <= BUDGET) begin
            grant_a = req_a;
            grant_b = req_b;
        end else begin
            grant_a   = req_a;
            remaining = (BUDGET > {1'b0, req_a}) ? (BUDGET - {1'b0, req_a}) : 3'd0;
            grant_b   = remaining[1:0];
        end
    end

endmodule


// =============================================================================
// MODULE 3: counters
// =============================================================================
module counters (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        activity_in,
    input  wire        stall_in,
    output reg  [6:0]  activity_count,
    output reg  [6:0]  stall_count,
    output reg         window_done,
    output reg  [6:0]  cycle_count
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count    <= 7'd0;
            activity_count <= 7'd0;
            stall_count    <= 7'd0;
            window_done    <= 1'b0;
        end else begin
            window_done <= 1'b0;

            if (cycle_count == 7'd99) begin
                cycle_count    <= 7'd0;
                activity_count <= 7'd0;
                stall_count    <= 7'd0;
                window_done    <= 1'b1;
            end else begin
                cycle_count <= cycle_count + 7'd1;
                if (activity_in)
                    activity_count <= activity_count + 7'd1;
                if (stall_in)
                    stall_count <= stall_count + 7'd1;
            end
        end
    end

endmodule


// =============================================================================
// MODULE 4: reg_interface
// =============================================================================
module reg_interface (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        activity_in,
    input  wire        stall_in,
    input  wire [6:0]  temp_in,
    input  wire [1:0]  power_state_in,
    input  wire [6:0]  thermal_thresh_in,
    output reg  [1:0]  power_state_out,
    output reg         activity_out,
    output reg         stall_out,
    output reg  [6:0]  temp_out,
    output reg         clk_en,
    output reg  [6:0]  thermal_thresh_out,
    output reg         thermal_alarm
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            power_state_out    <= `STATE_SLEEP;
            activity_out       <= 1'b0;
            stall_out          <= 1'b0;
            temp_out           <= 7'd0;
            clk_en             <= 1'b0;
            thermal_thresh_out <= 7'd85;
            thermal_alarm      <= 1'b0;

        end else begin
            power_state_out    <= power_state_in;
            activity_out       <= activity_in;
            stall_out          <= stall_in;
            temp_out           <= temp_in;
            thermal_thresh_out <= thermal_thresh_in;
            thermal_alarm      <= (temp_in >= thermal_thresh_in) ? 1'b1 : 1'b0;

            case (power_state_in)
                `STATE_SLEEP:     clk_en <= 1'b0;
                `STATE_LOW_POWER: clk_en <= activity_in;
                `STATE_ACTIVE:    clk_en <= 1'b1;
                `STATE_TURBO:     clk_en <= 1'b1;
                default:          clk_en <= 1'b0;
            endcase
        end
    end

endmodule