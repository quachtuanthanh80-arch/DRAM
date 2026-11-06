// File: tb_rs_chipkill.sv
// Chức năng: Wrapper nối bộ mã hóa và giải mã RS(18,16)/GF(2^8) Chipkill kèm cổng tiêm lỗi tối đa hai symbol (hai chip x4).

`timescale 1ns / 1ps

module tb_rs_chipkill (
    input  logic         clk,
    input  logic         rst_n,

    input  logic         i_valid,
    output logic         o_ready,
    input  logic [127:0] i_data,

    // Tiêm lỗi: i_inject_count = 0/1/2 symbol, mỗi symbol XOR với giá trị 8 bit
    input  logic         i_inject_en,
    input  logic [1:0]   i_inject_count,
    input  logic [4:0]   i_inject_sym_idx0,
    input  logic [7:0]   i_inject_val0,
    input  logic [4:0]   i_inject_sym_idx1,
    input  logic [7:0]   i_inject_val1,

    output logic         o_valid,
    input  logic         i_ready,
    output logic [127:0] o_data,
    output logic         o_single_corrected,
    output logic         o_uncorrectable,
    output logic [4:0]   o_error_symbol_idx
);

    logic         enc_valid, enc_ready;
    logic [143:0] enc_codeword;

    rs_chipkill_encoder u_encoder (
        .clk(clk), .rst_n(rst_n), .i_valid(i_valid), .o_ready(o_ready), .i_data(i_data),
        .o_valid(enc_valid), .i_ready(enc_ready), .o_codeword(enc_codeword)
    );

    logic       inj_en_q;
    logic [1:0] inj_cnt_q;
    logic [4:0] inj_sym0_q, inj_sym1_q;
    logic [7:0] inj_val0_q, inj_val1_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inj_en_q <= 1'b0; inj_cnt_q <= '0;
            inj_sym0_q <= '0; inj_val0_q <= '0; inj_sym1_q <= '0; inj_val1_q <= '0;
        end else if (o_ready && i_valid) begin
            inj_en_q   <= i_inject_en;
            inj_cnt_q  <= i_inject_count;
            inj_sym0_q <= i_inject_sym_idx0;
            inj_val0_q <= i_inject_val0;
            inj_sym1_q <= i_inject_sym_idx1;
            inj_val1_q <= i_inject_val1;
        end else if (enc_valid && enc_ready) begin
            inj_en_q <= 1'b0;
        end
    end

    wire [143:0] err0 = (inj_en_q && inj_cnt_q >= 2'd1) ? ({136'd0, inj_val0_q} << (inj_sym0_q * 8)) : 144'd0;
    wire [143:0] err1 = (inj_en_q && inj_cnt_q >= 2'd2) ? ({136'd0, inj_val1_q} << (inj_sym1_q * 8)) : 144'd0;

    rs_chipkill_decoder u_decoder (
        .clk(clk), .rst_n(rst_n), .i_valid(enc_valid), .o_ready(enc_ready), .i_codeword(enc_codeword ^ err0 ^ err1),
        .o_valid(o_valid), .i_ready(i_ready), .o_data(o_data),
        .o_single_corrected(o_single_corrected), .o_uncorrectable(o_uncorrectable), .o_error_symbol_idx(o_error_symbol_idx)
    );

endmodule
