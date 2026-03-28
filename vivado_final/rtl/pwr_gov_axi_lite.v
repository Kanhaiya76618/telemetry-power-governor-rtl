`timescale 1ns / 1ps

module pwr_gov_axi_lite #(
    parameter integer AXI_ADDR_WIDTH = 8
) (
    input  wire                      s_axi_aclk,
    input  wire                      s_axi_aresetn,
    input  wire [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire                      s_axi_awvalid,
    output reg                       s_axi_awready,
    input  wire [31:0]               s_axi_wdata,
    input  wire [3:0]                s_axi_wstrb,
    input  wire                      s_axi_wvalid,
    output reg                       s_axi_wready,
    output reg [1:0]                 s_axi_bresp,
    output reg                       s_axi_bvalid,
    input  wire                      s_axi_bready,
    input  wire [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire                      s_axi_arvalid,
    output reg                       s_axi_arready,
    output reg [31:0]                s_axi_rdata,
    output reg [1:0]                 s_axi_rresp,
    output reg                       s_axi_rvalid,
    input  wire                      s_axi_rready
);

    wire rst_n = s_axi_aresetn;

    // ---------------------------------------------------------------------
    // AXI control registers (RW)
    // ---------------------------------------------------------------------
    // 0x00 CTRL: bit0 host_mode, bit1 use_ext_budget
    // 0x04 BUDGET: bits[2:0]
    // 0x08 REQ: bits[1:0]=req_a, bits[3:2]=req_b
    // 0x0C IO: bit0=act_a bit1=stall_a bit2=act_b bit3=stall_b
    // 0x10 TEMP_A: bits[6:0]
    // 0x14 TEMP_B: bits[6:0]
    reg host_mode;
    reg host_use_ext_budget;
    reg [2:0] host_budget;
    reg [1:0] host_req_a, host_req_b;
    reg host_act_a, host_stall_a, host_act_b, host_stall_b;
    reg [6:0] host_temp_a, host_temp_b;

    // ---------------------------------------------------------------------
    // Internal telemetry source: workload_sim
    // ---------------------------------------------------------------------
    reg [6:0] ws_cycle_count;
    reg       ws_window_done;

    always @(posedge s_axi_aclk or negedge rst_n) begin
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
        .clk(s_axi_aclk),
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

    wire act_a_in   = host_mode ? host_act_a   : ws_act_a;
    wire stall_a_in = host_mode ? host_stall_a : ws_stall_a;
    wire act_b_in   = host_mode ? host_act_b   : ws_act_b;
    wire stall_b_in = host_mode ? host_stall_b : ws_stall_b;

    wire [6:0] temp_a_in = host_mode ? host_temp_a : ws_temp_a;
    wire [6:0] temp_b_in = host_mode ? host_temp_b : ws_temp_b;

    wire [1:0] req_a_in = host_mode ? host_req_a : 2'b00;
    wire [1:0] req_b_in = host_mode ? host_req_b : 2'b00;

    wire [2:0] ext_budget_in = host_budget;
    wire       use_ext_budget = host_mode ? host_use_ext_budget : 1'b0;

    // ---------------------------------------------------------------------
    // Governor core
    // ---------------------------------------------------------------------
    wire [1:0] grant_a;
    wire [1:0] grant_b;
    wire       clk_en_a;
    wire       clk_en_b;
    wire [2:0] current_budget;
    wire [2:0] budget_headroom;
    wire [9:0] system_efficiency;
    wire       alarm_a;
    wire       alarm_b;

    pwr_gov_top GOV (
        .clk(s_axi_aclk),
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

    // Snapshot/update counter for host polling
    reg [31:0] sample_counter;
    always @(posedge s_axi_aclk or negedge rst_n) begin
        if (!rst_n)
            sample_counter <= 32'd0;
        else if (ws_window_done)
            sample_counter <= sample_counter + 32'd1;
    end

    // ---------------------------------------------------------------------
    // AXI write/read handling
    // ---------------------------------------------------------------------
    wire [5:0] wr_word = s_axi_awaddr[7:2];
    wire [5:0] rd_word = s_axi_araddr[7:2];

    always @(posedge s_axi_aclk or negedge rst_n) begin
        if (!rst_n) begin
            // AXI outputs
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            s_axi_bvalid  <= 1'b0;
            s_axi_arready <= 1'b0;
            s_axi_rdata   <= 32'd0;
            s_axi_rresp   <= 2'b00;
            s_axi_rvalid  <= 1'b0;

            // Control defaults
            host_mode <= 1'b0;
            host_use_ext_budget <= 1'b0;
            host_budget <= 3'd4;
            host_req_a <= 2'b00;
            host_req_b <= 2'b00;
            host_act_a <= 1'b0;
            host_stall_a <= 1'b0;
            host_act_b <= 1'b0;
            host_stall_b <= 1'b0;
            host_temp_a <= 7'd30;
            host_temp_b <= 7'd30;

        end else begin
            // Defaults: pulses
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_arready <= 1'b0;

            // Write transaction
            if (!s_axi_bvalid && s_axi_awvalid && s_axi_wvalid) begin
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b1;
                s_axi_bvalid  <= 1'b1;
                s_axi_bresp   <= 2'b00;

                case (wr_word)
                    6'h00: begin
                        if (s_axi_wstrb[0]) begin
                            host_mode <= s_axi_wdata[0];
                            host_use_ext_budget <= s_axi_wdata[1];
                        end
                    end
                    6'h01: begin
                        if (s_axi_wstrb[0])
                            host_budget <= s_axi_wdata[2:0];
                    end
                    6'h02: begin
                        if (s_axi_wstrb[0]) begin
                            host_req_a <= s_axi_wdata[1:0];
                            host_req_b <= s_axi_wdata[3:2];
                        end
                    end
                    6'h03: begin
                        if (s_axi_wstrb[0]) begin
                            host_act_a   <= s_axi_wdata[0];
                            host_stall_a <= s_axi_wdata[1];
                            host_act_b   <= s_axi_wdata[2];
                            host_stall_b <= s_axi_wdata[3];
                        end
                    end
                    6'h04: begin
                        if (s_axi_wstrb[0])
                            host_temp_a <= s_axi_wdata[6:0];
                    end
                    6'h05: begin
                        if (s_axi_wstrb[0])
                            host_temp_b <= s_axi_wdata[6:0];
                    end
                    default: begin
                        // no-op
                    end
                endcase
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            // Read transaction
            if (!s_axi_rvalid && s_axi_arvalid) begin
                s_axi_arready <= 1'b1;
                s_axi_rvalid  <= 1'b1;
                s_axi_rresp   <= 2'b00;

                case (rd_word)
                    // RW mirrors
                    6'h00: s_axi_rdata <= {30'd0, host_use_ext_budget, host_mode};
                    6'h01: s_axi_rdata <= {29'd0, host_budget};
                    6'h02: s_axi_rdata <= {28'd0, host_req_b, host_req_a};
                    6'h03: s_axi_rdata <= {28'd0, host_stall_b, host_act_b, host_stall_a, host_act_a};
                    6'h04: s_axi_rdata <= {25'd0, host_temp_a};
                    6'h05: s_axi_rdata <= {25'd0, host_temp_b};

                    // RO status
                    6'h08: s_axi_rdata <= {
                        19'd0,
                        ws_phase_done,
                        ws_phase,
                        grant_b,
                        grant_a,
                        clk_en_b,
                        clk_en_a,
                        alarm_b,
                        alarm_a,
                        host_mode
                    };
                    6'h09: s_axi_rdata <= {26'd0, budget_headroom, current_budget};
                    6'h0A: s_axi_rdata <= {22'd0, system_efficiency};
                    6'h0B: s_axi_rdata <= {
                        9'd0,
                        req_b_in,
                        req_a_in,
                        stall_b_in,
                        act_b_in,
                        stall_a_in,
                        act_a_in,
                        temp_b_in,
                        temp_a_in
                    };
                    6'h0C: s_axi_rdata <= sample_counter;
                    default: s_axi_rdata <= 32'd0;
                endcase
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule
