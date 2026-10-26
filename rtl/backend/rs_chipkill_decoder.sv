// File: rs_chipkill_decoder.sv
// Chức năng: Bộ giải mã Reed-Solomon RS(18,16) sửa lỗi 1 symbol 4-bit (1 chip DRAM x4) và phát hiện lỗi 2 symbol.

`timescale 1ns / 1ps

module rs_chipkill_decoder
    import gf16_arith_pkg::*;
#(
    parameter int DATA_SYMBOLS   = 16,
    parameter int PARITY_SYMBOLS = 2
)(
    input  logic                                clk,
    input  logic                                rst_n,

    // Giao diện codeword 72-bit vào (từ DRAM Bus / PHY)
    input  logic                                i_valid,
    output logic                                o_ready,
    input  logic [(DATA_SYMBOLS+PARITY_SYMBOLS)*4-1:0] i_codeword,

    // Giao diện dữ liệu 64-bit sau khi sửa lỗi
    output logic                                o_valid,
    input  logic                                i_ready,
    output logic [DATA_SYMBOLS*4-1:0]           o_data,

    // Tín hiệu telemetry thông báo trạng thái lỗi
    output logic                                o_single_corrected,
    output logic                                o_double_detected,
    output logic [3:0]                          o_error_symbol_idx
);

    assign o_ready = i_ready || !o_valid;

    // Tính toán hội chứng lỗi (Syndrome S0, S1), định vị lỗi O(1) trên GF(2^4) và sửa lỗi tổ hợp
    gf16_t s0_comb, s1_comb;
    gf16_t syn_term [DATA_SYMBOLS];

    genvar gi;
    generate
        for (gi = 0; gi < DATA_SYMBOLS; gi = gi + 1) begin : gen_syn_mul
            assign syn_term[gi] = gf16_mul(i_codeword[gi*4 +: 4], gf16_t'(gi));
        end
    endgenerate

    assign s0_comb = i_codeword[64 +: 4] ^
                     i_codeword[0*4 +: 4]  ^ i_codeword[1*4 +: 4]  ^ i_codeword[2*4 +: 4]  ^ i_codeword[3*4 +: 4]  ^
                     i_codeword[4*4 +: 4]  ^ i_codeword[5*4 +: 4]  ^ i_codeword[6*4 +: 4]  ^ i_codeword[7*4 +: 4]  ^
                     i_codeword[8*4 +: 4]  ^ i_codeword[9*4 +: 4]  ^ i_codeword[10*4 +: 4] ^ i_codeword[11*4 +: 4] ^
                     i_codeword[12*4 +: 4] ^ i_codeword[13*4 +: 4] ^ i_codeword[14*4 +: 4] ^ i_codeword[15*4 +: 4];

    assign s1_comb = i_codeword[68 +: 4] ^
                     syn_term[0]  ^ syn_term[1]  ^ syn_term[2]  ^ syn_term[3]  ^
                     syn_term[4]  ^ syn_term[5]  ^ syn_term[6]  ^ syn_term[7]  ^
                     syn_term[8]  ^ syn_term[9]  ^ syn_term[10] ^ syn_term[11] ^
                     syn_term[12] ^ syn_term[13] ^ syn_term[14] ^ syn_term[15];

    wire       match_found   = (s0_comb != 4'h0);
    wire [3:0] match_idx     = match_found ? gf16_mul(s1_comb, gf16_inv(s0_comb)) : 4'h0;
    wire [3:0] err_magnitude = match_found ? s0_comb : 4'h0;

    wire [DATA_SYMBOLS*4-1:0] corr_mask      = match_found ? ({60'd0, err_magnitude} << (match_idx * 4)) : 64'd0;
    wire [DATA_SYMBOLS*4-1:0] corrected_data = i_codeword[63:0] ^ corr_mask;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_valid            <= 1'b0;
            o_data             <= '0;
            o_single_corrected <= 1'b0;
            o_double_detected  <= 1'b0;
            o_error_symbol_idx <= '0;
        end else if (o_ready) begin
            o_valid <= i_valid;
            if (i_valid) begin
                o_data             <= corrected_data;
                o_error_symbol_idx <= match_idx;

                if ((s0_comb == 4'h0) && (s1_comb == 4'h0)) begin
                    o_single_corrected <= 1'b0;
                    o_double_detected  <= 1'b0;
                end else if (match_found) begin
                    o_single_corrected <= 1'b1;
                    o_double_detected  <= 1'b0;
                end else begin
                    o_single_corrected <= 1'b0;
                    o_double_detected  <= 1'b1;
                end
            end
        end
    end

endmodule
