// File: rs_chipkill_encoder.sv
// Chức năng: Bộ mã hóa Reed-Solomon RS(18,16) trên trường GF(2^4) bảo vệ Chipkill cho chip nhớ DRAM x4.

`timescale 1ns / 1ps

module rs_chipkill_encoder
    import gf16_arith_pkg::*;
#(
    parameter int DATA_SYMBOLS   = 16, // 16 symbols x 4-bit = 64-bit data
    parameter int PARITY_SYMBOLS = 2   // 2 symbols x 4-bit = 8-bit parity (RS(18,16))
)(
    input  logic                                clk,
    input  logic                                rst_n,

    // Giao diện dữ liệu vào
    input  logic                                i_valid,
    output logic                                o_ready,
    input  logic [DATA_SYMBOLS*4-1:0]           i_data,

    // Giao diện dữ liệu ra đã ghép mã parity
    output logic                                o_valid,
    input  logic                                i_ready,
    output logic [(DATA_SYMBOLS+PARITY_SYMBOLS)*4-1:0] o_codeword
);

    assign o_ready = i_ready || !o_valid;

    // Tính toán trực tiếp 2 parity symbols bằng phép nhân-cộng Galois GF(2^4) trong 1 chu kỳ:
    // P0 = sum(msg_i), P1 = sum(msg_i * x_i) với x_i = i
    gf16_t p0_comb, p1_comb;
    gf16_t prod_term [DATA_SYMBOLS];

    genvar gi;
    generate
        for (gi = 0; gi < DATA_SYMBOLS; gi = gi + 1) begin : gen_gf_mul
            assign prod_term[gi] = gf16_mul(i_data[gi*4 +: 4], gf16_t'(gi));
        end
    endgenerate

    assign p0_comb = i_data[0*4 +: 4]  ^ i_data[1*4 +: 4]  ^ i_data[2*4 +: 4]  ^ i_data[3*4 +: 4]  ^
                     i_data[4*4 +: 4]  ^ i_data[5*4 +: 4]  ^ i_data[6*4 +: 4]  ^ i_data[7*4 +: 4]  ^
                     i_data[8*4 +: 4]  ^ i_data[9*4 +: 4]  ^ i_data[10*4 +: 4] ^ i_data[11*4 +: 4] ^
                     i_data[12*4 +: 4] ^ i_data[13*4 +: 4] ^ i_data[14*4 +: 4] ^ i_data[15*4 +: 4];

    assign p1_comb = prod_term[0]  ^ prod_term[1]  ^ prod_term[2]  ^ prod_term[3]  ^
                     prod_term[4]  ^ prod_term[5]  ^ prod_term[6]  ^ prod_term[7]  ^
                     prod_term[8]  ^ prod_term[9]  ^ prod_term[10] ^ prod_term[11] ^
                     prod_term[12] ^ prod_term[13] ^ prod_term[14] ^ prod_term[15];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_valid    <= 1'b0;
            o_codeword <= '0;
        end else if (o_ready) begin
            o_valid <= i_valid;
            if (i_valid) begin
                o_codeword <= {p1_comb, p0_comb, i_data};
            end
        end
    end

endmodule
