// File: fault_hardened_csr.sv
// Chức năng: Khối thanh ghi điều khiển cấu hình an toàn chống tấn công xung nhiễu (glitch) với bộ bỏ phiếu TMR.
`timescale 1ns / 1ps

module fault_hardened_csr (
    input  logic        clk,
    input  logic        rst_n,

    // Tín hiệu ghi cấu hình từ giao diện CSR
    input  logic        i_cfg_we,
    input  logic [15:0] i_cfg_rh_threshold,
    input  logic [1:0]  i_cfg_rowpress_curve,
    input  logic        i_cfg_dual_hash_en,
    input  logic [1:0]  i_cfg_scramble_mode,

    // Đầu ra đã qua bộ bỏ phiếu đa số 2-out-of-3 (TMR Majority Voting)
    output logic [15:0] o_cfg_rh_threshold,
    output logic [1:0]  o_cfg_rowpress_curve,
    output logic        o_cfg_dual_hash_en,
    output logic [1:0]  o_cfg_scramble_mode,

    // Cảnh báo tấn công xung điện áp/xung clock (Glitch & Fault Alert)
    output logic        o_glitch_alert,
    output logic        o_security_locked
);

    // Ba đường ray thanh ghi độc lập vật lý (Triple Modular Redundancy Rails)
    logic [15:0] rail0_rh_thresh, rail1_rh_thresh, rail2_rh_thresh;
    logic [1:0]  rail0_rowpress,  rail1_rowpress,  rail2_rowpress;
    logic        rail0_dual_hash, rail1_dual_hash, rail2_dual_hash;
    logic [1:0]  rail0_scramble,  rail1_scramble,  rail2_scramble;

    logic        glitch_latch;

    // Ghi đồng bộ vào cả 3 đường ray
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rail0_rh_thresh <= 16'd1024;
            rail1_rh_thresh <= 16'd1024;
            rail2_rh_thresh <= 16'd1024;

            rail0_rowpress  <= 2'b00;
            rail1_rowpress  <= 2'b00;
            rail2_rowpress  <= 2'b00;

            rail0_dual_hash <= 1'b1;
            rail1_dual_hash <= 1'b1;
            rail2_dual_hash <= 1'b1;

            rail0_scramble  <= 2'b10; // Mặc định SCARF mode
            rail1_scramble  <= 2'b10;
            rail2_scramble  <= 2'b10;

            glitch_latch    <= 1'b0;
        end else begin
            if (i_cfg_we && !glitch_latch) begin
                rail0_rh_thresh <= i_cfg_rh_threshold;
                rail1_rh_thresh <= i_cfg_rh_threshold;
                rail2_rh_thresh <= i_cfg_rh_threshold;

                rail0_rowpress  <= i_cfg_rowpress_curve;
                rail1_rowpress  <= i_cfg_rowpress_curve;
                rail2_rowpress  <= i_cfg_rowpress_curve;

                rail0_dual_hash <= i_cfg_dual_hash_en;
                rail1_dual_hash <= i_cfg_dual_hash_en;
                rail2_dual_hash <= i_cfg_dual_hash_en;

                rail0_scramble  <= i_cfg_scramble_mode;
                rail1_scramble  <= i_cfg_scramble_mode;
                rail2_scramble  <= i_cfg_scramble_mode;
            end

            // Chốt khóa an toàn khi phát hiện xung nhiễu gây lệch bit giữa các ray
            if (o_glitch_alert) begin
                glitch_latch <= 1'b1;
            end
        end
    end

    // Hàm bỏ phiếu đa số 2-out-of-3
    function automatic logic tmr_vote(input logic a, input logic b, input logic c);
        return (a & b) | (b & c) | (a & c);
    endfunction

    // Bỏ phiếu từng bit cho toàn bộ các thanh ghi
    always_comb begin
        for (int i = 0; i < 16; i++) begin
            o_cfg_rh_threshold[i] = tmr_vote(rail0_rh_thresh[i], rail1_rh_thresh[i], rail2_rh_thresh[i]);
        end
        for (int i = 0; i < 2; i++) begin
            o_cfg_rowpress_curve[i] = tmr_vote(rail0_rowpress[i], rail1_rowpress[i], rail2_rowpress[i]);
            o_cfg_scramble_mode[i]  = tmr_vote(rail0_scramble[i], rail1_scramble[i], rail2_scramble[i]);
        end
        o_cfg_dual_hash_en = tmr_vote(rail0_dual_hash, rail1_dual_hash, rail2_dual_hash);
    end

    // Phát hiện sai lệch (mismatch) giữa 3 đường ray
    wire mismatch_thresh   = (rail0_rh_thresh != rail1_rh_thresh) || (rail1_rh_thresh != rail2_rh_thresh);
    wire mismatch_rowpress = (rail0_rowpress  != rail1_rowpress)  || (rail1_rowpress  != rail2_rowpress);
    wire mismatch_hash     = (rail0_dual_hash != rail1_dual_hash) || (rail1_dual_hash != rail2_dual_hash);
    wire mismatch_scramble = (rail0_scramble  != rail1_scramble)  || (rail1_scramble  != rail2_scramble);

    assign o_glitch_alert    = mismatch_thresh || mismatch_rowpress || mismatch_hash || mismatch_scramble;
    assign o_security_locked = glitch_latch;

endmodule
