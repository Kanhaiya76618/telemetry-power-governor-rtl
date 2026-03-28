// =============================================================================
// FILE: power_arbiter.v
// PURPOSE: Simple combinational arbiter enforcing a global power budget
// =============================================================================

`timescale 1ns / 1ps

module power_arbiter (
    input  wire [1:0] req_a,
    input  wire [1:0] req_b,
    input  wire [6:0] temp_a, // reserved for future thermal-aware arbitration
    input  wire [6:0] temp_b,
    output reg  [1:0] grant_a,
    output reg  [1:0] grant_b
);

    // Example budget: maximum combined "state value" allowed.
    // STATE_SLEEP=0, LOW_POWER=1, ACTIVE=2, TURBO=3
    localparam [2:0] BUDGET = 3'd4;

    wire [2:0] total_requested = {1'b0, req_a} + {1'b0, req_b};
    reg  [2:0] remaining;

    always @(*) begin
        if (total_requested <= BUDGET) begin
            // Everyone gets what they asked for
            grant_a = req_a;
            grant_b = req_b;
        end else begin
            // Priority: module A preferred. Give A what it wants, throttle B.
            grant_a = req_a;
            remaining = (BUDGET > {1'b0, req_a}) ? (BUDGET - {1'b0, req_a}) : 3'd0;
            grant_b = remaining[1:0];
        end
    end

endmodule
