`timescale 1ns / 1ps

module pwr_gov_uart_top (
    input  wire clk,
    input  wire btn0,
    input  wire btn1,
    input  wire uart_rx,

    output wire uart_tx,
    output wire led0_b,
    output wire led0_g,
    output wire led0_r,
    output wire led1_b,
    output wire led1_g,
    output wire led1_r
);

    wire rst_n = ~btn0;

    // ---------------------------------------------------------------------
    // Button sync (display page select)
    // ---------------------------------------------------------------------
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

    wire       ws_act_a;
    wire       ws_stall_a;
    wire       ws_act_b;
    wire       ws_stall_b;
    wire [6:0] ws_temp_a;
    wire [6:0] ws_temp_b;
    wire [2:0] ws_phase;
    wire       ws_phase_done;

    workload_sim WS (
        .clk(clk),
        .rst_n(rst_n),
        .window_done(ws_window_done),
        .activity_a(ws_act_a),
        .stall_a(ws_stall_a),
        .activity_b(ws_act_b),
        .stall_b(ws_stall_b),
        .temp_a(ws_temp_a),
        .temp_b(ws_temp_b),
        .phase_out(ws_phase),
        .phase_done(ws_phase_done)
    );

    // ---------------------------------------------------------------------
    // UART RX command handling
    // ---------------------------------------------------------------------
    wire [7:0] rx_byte;
    wire       rx_valid;

    uart_rx #(
        .CLK_HZ(125_000_000),
        .BAUD(115200)
    ) U_RX (
        .clk(clk),
        .rst_n(rst_n),
        .rx(uart_rx),
        .data_out(rx_byte),
        .data_valid(rx_valid)
    );

    reg host_mode;             // 0=internal workload, 1=host-injected signals
    reg host_use_ext_budget;   // forwarded to pwr_gov_top when host_mode=1
    reg [2:0] host_budget;

    reg host_act_a, host_stall_a, host_act_b, host_stall_b;
    reg [1:0] host_req_a, host_req_b;
    reg [6:0] host_temp_a, host_temp_b;

    reg expect_value;
    reg expect_temp_sel;       // 0=temp_a, 1=temp_b

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            host_mode <= 1'b0;
            host_use_ext_budget <= 1'b0;
            host_budget <= 3'd4;
            host_act_a <= 1'b0;
            host_stall_a <= 1'b0;
            host_act_b <= 1'b0;
            host_stall_b <= 1'b0;
            host_req_a <= 2'b00;
            host_req_b <= 2'b00;
            host_temp_a <= 7'd30;
            host_temp_b <= 7'd30;
            expect_value <= 1'b0;
            expect_temp_sel <= 1'b0;
        end else if (rx_valid) begin
            if (expect_value) begin
                expect_value <= 1'b0;
                if (!expect_temp_sel)
                    host_temp_a <= rx_byte[6:0];
                else
                    host_temp_b <= rx_byte[6:0];
            end else begin
                case (rx_byte)
                    8'hA0: host_mode <= 1'b0;
                    8'hA1: host_mode <= 1'b1;

                    8'hF0: host_use_ext_budget <= 1'b0;
                    8'hF1: host_use_ext_budget <= 1'b1;

                    8'hB0,8'hB1,8'hB2,8'hB3,8'hB4,8'hB5,8'hB6,8'hB7:
                        host_budget <= rx_byte[2:0];

                    8'hC0,8'hC1,8'hC2,8'hC3:
                        host_req_a <= rx_byte[1:0];

                    8'hC4,8'hC5,8'hC6,8'hC7:
                        host_req_b <= rx_byte[1:0];

                    8'hD0: host_act_a   <= 1'b0;
                    8'hD1: host_act_a   <= 1'b1;
                    8'hD2: host_stall_a <= 1'b0;
                    8'hD3: host_stall_a <= 1'b1;
                    8'hD4: host_act_b   <= 1'b0;
                    8'hD5: host_act_b   <= 1'b1;
                    8'hD6: host_stall_b <= 1'b0;
                    8'hD7: host_stall_b <= 1'b1;

                    8'hE0: begin
                        expect_value <= 1'b1;
                        expect_temp_sel <= 1'b0;
                    end
                    8'hE1: begin
                        expect_value <= 1'b1;
                        expect_temp_sel <= 1'b1;
                    end

                    default: begin
                        // Ignore unknown commands
                    end
                endcase
            end
        end
    end

    // ---------------------------------------------------------------------
    // Telemetry source mux into real governor
    // ---------------------------------------------------------------------
    wire use_host_inputs = host_mode;

    wire act_a_in   = use_host_inputs ? host_act_a   : ws_act_a;
    wire stall_a_in = use_host_inputs ? host_stall_a : ws_stall_a;
    wire act_b_in   = use_host_inputs ? host_act_b   : ws_act_b;
    wire stall_b_in = use_host_inputs ? host_stall_b : ws_stall_b;

    wire [6:0] temp_a_in = use_host_inputs ? host_temp_a : ws_temp_a;
    wire [6:0] temp_b_in = use_host_inputs ? host_temp_b : ws_temp_b;

    wire [1:0] req_a_in = use_host_inputs ? host_req_a : 2'b00;
    wire [1:0] req_b_in = use_host_inputs ? host_req_b : 2'b00;

    wire [2:0] ext_budget_in = host_budget;
    wire       use_ext_budget = use_host_inputs ? host_use_ext_budget : 1'b0;

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
        .act_a(act_a_in),
        .stall_a(stall_a_in),
        .req_a(req_a_in),
        .temp_a(temp_a_in),
        .act_b(act_b_in),
        .stall_b(stall_b_in),
        .req_b(req_b_in),
        .temp_b(temp_b_in),
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

    // ---------------------------------------------------------------------
    // UART TX telemetry framing (binary frame, 16 bytes, 5 Hz)
    // ---------------------------------------------------------------------
    // [0]=0xAA, [1]=0x55
    // [2]=frame_ctr LSB, [3]=frame_ctr MSB
    // [4]=flags: b0=host_mode b1=alarm_a b2=alarm_b b3=clk_en_a b4=clk_en_b
    // [5]=grant pack: [1:0]=grant_a [3:2]=grant_b
    // [6]=budget pack: [2:0]=current_budget [5:3]=budget_headroom
    // [7]=efficiency LSB, [8]=efficiency MSB
    // [9]=temp_a, [10]=temp_b
    // [11]=io flags: b0=act_a b1=stall_a b2=act_b b3=stall_b
    // [12]=req pack: [1:0]=req_a [3:2]=req_b
    // [13]=ws_phase
    // [14]=checksum XOR of bytes [2..13]
    // [15]=0x0D

    reg [24:0] tx_period_cnt;
    wire tx_tick = (tx_period_cnt == 25'd24_999_999); // 125MHz / 25,000,000 = 5 Hz

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            tx_period_cnt <= 25'd0;
        else if (tx_tick)
            tx_period_cnt <= 25'd0;
        else
            tx_period_cnt <= tx_period_cnt + 25'd1;
    end

    reg [15:0] frame_ctr;
    reg [7:0] frame_mem [0:15];
    reg [4:0] tx_idx;
    reg       frame_tx_active;

    wire [7:0] tx_b2  = frame_ctr[7:0];
    wire [7:0] tx_b3  = frame_ctr[15:8];
    wire [7:0] tx_b4  = {3'b000, clk_en_b, clk_en_a, alarm_b, alarm_a, use_host_inputs};
    wire [7:0] tx_b5  = {4'b0000, grant_b, grant_a};
    wire [7:0] tx_b6  = {2'b00, budget_headroom, current_budget};
    wire [7:0] tx_b7  = system_efficiency[7:0];
    wire [7:0] tx_b8  = {6'b000000, system_efficiency[9:8]};
    wire [7:0] tx_b9  = temp_a_in;
    wire [7:0] tx_b10 = temp_b_in;
    wire [7:0] tx_b11 = {4'b0000, act_b_in, stall_b_in, act_a_in, stall_a_in};
    wire [7:0] tx_b12 = {4'b0000, req_b_in, req_a_in};
    wire [7:0] tx_b13 = {5'b00000, ws_phase};
    wire [7:0] tx_b14 = tx_b2 ^ tx_b3 ^ tx_b4 ^ tx_b5 ^ tx_b6 ^ tx_b7 ^ tx_b8 ^ tx_b9 ^ tx_b10 ^ tx_b11 ^ tx_b12 ^ tx_b13;

    reg [7:0] tx_data;
    reg       tx_start;
    wire      tx_busy;

    uart_tx #(
        .CLK_HZ(125_000_000),
        .BAUD(115200)
    ) U_TX (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(tx_data),
        .data_valid(tx_start),
        .tx(uart_tx),
        .busy(tx_busy)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_ctr <= 16'd0;
            tx_idx <= 5'd0;
            frame_tx_active <= 1'b0;
            tx_data <= 8'd0;
            tx_start <= 1'b0;
        end else begin
            tx_start <= 1'b0;

            if (tx_tick && !frame_tx_active) begin
                frame_mem[0]  <= 8'hAA;
                frame_mem[1]  <= 8'h55;
                frame_mem[2]  <= tx_b2;
                frame_mem[3]  <= tx_b3;
                frame_mem[4]  <= tx_b4;
                frame_mem[5]  <= tx_b5;
                frame_mem[6]  <= tx_b6;
                frame_mem[7]  <= tx_b7;
                frame_mem[8]  <= tx_b8;
                frame_mem[9]  <= tx_b9;
                frame_mem[10] <= tx_b10;
                frame_mem[11] <= tx_b11;
                frame_mem[12] <= tx_b12;
                frame_mem[13] <= tx_b13;
                frame_mem[14] <= tx_b14;
                frame_mem[15] <= 8'h0D;

                frame_tx_active <= 1'b1;
                tx_idx <= 5'd0;
                frame_ctr <= frame_ctr + 16'd1;
            end

            if (frame_tx_active && !tx_busy) begin
                if (tx_idx < 5'd16) begin
                    tx_data <= frame_mem[tx_idx];
                    tx_start <= 1'b1;
                    tx_idx <= tx_idx + 5'd1;
                end else begin
                    frame_tx_active <= 1'b0;
                end
            end
        end
    end

    // ---------------------------------------------------------------------
    // LEDs
    // ---------------------------------------------------------------------
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
