// perf_monitor_unit.sv
// Bo giam sat hieu nang phan cung PMU voi 8 thanh ghi dem bao hoa tuong thich kien truc Intel PCM

`timescale 1ns / 1ps

module perf_monitor_unit #(
    parameter int NUM_COUNTERS  = 8,
    parameter int COUNTER_WIDTH = 32
)(
    input  logic                                          clk,
    input  logic                                          rst_n,

    // Tin hieu dieu khien chung tu APB CSR
    input  logic                                          cfg_perf_en,
    input  logic                                          cfg_counter_reset,

    // 8 kenh xung su kien giam sat thoi gian thuc
    input  logic                                          ev_act_cmd,
    input  logic                                          ev_rd_cmd,
    input  logic                                          ev_wr_cmd,
    input  logic                                          ev_bg_bypass,
    input  logic                                          ev_sdc_throttle,
    input  logic                                          ev_rowpress_alert,
    input  logic                                          ev_ecc_corrected,
    input  logic                                          ev_rob_stall,

    // Giao dien doc thanh ghi APB
    input  logic [2:0]                                    i_pmu_reg_sel,
    output logic [COUNTER_WIDTH-1:0]                      o_pmu_reg_data,

    // Xuat mang toan bo thanh ghi ra ngoai
    output logic [NUM_COUNTERS-1:0][COUNTER_WIDTH-1:0]    o_all_counters
);

    // Mảng 8 thanh ghi đếm bão hòa (Saturating Counters)
    // Co che bao hoa: Khi bo dem dat gia tri cuc dai 32'hFFFF_FFFF thi giu nguyen, khong bi tran ve 0
    logic [COUNTER_WIDTH-1:0] counters_q [NUM_COUNTERS];

    // Ghep cac xung su kien thanh vector de xu ly lap
    wire [NUM_COUNTERS-1:0] ev_vec = {
        ev_rob_stall,        // Index 7
        ev_ecc_corrected,     // Index 6
        ev_rowpress_alert,    // Index 5
        ev_sdc_throttle,      // Index 4
        ev_bg_bypass,         // Index 3
        ev_wr_cmd,            // Index 2
        ev_rd_cmd,            // Index 1
        ev_act_cmd            // Index 0
    };

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_COUNTERS; i++) begin
                counters_q[i] <= '0;
            end
        end else if (cfg_counter_reset) begin
            for (int i = 0; i < NUM_COUNTERS; i++) begin
                counters_q[i] <= '0;
            end
        end else if (cfg_perf_en) begin
            for (int i = 0; i < NUM_COUNTERS; i++) begin
                if (ev_vec[i]) begin
                    // Kiem tra chong tran (Saturating Counter)
                    if (counters_q[i] != {COUNTER_WIDTH{1'b1}}) begin
                        counters_q[i] <= counters_q[i] + 1'b1;
                    end
                end
            end
        end
    end

    // Giao dien doc MUX tra ve du lieu cho APB CSR Bus
    always_comb begin
        o_pmu_reg_data = counters_q[i_pmu_reg_sel];
        for (int i = 0; i < NUM_COUNTERS; i++) begin
            o_all_counters[i] = counters_q[i];
        end
    end

endmodule
