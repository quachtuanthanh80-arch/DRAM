// File: rs_chipkill_encoder.sv
// Chức năng: Bộ mã hóa Reed-Solomon RS(18,16) trên GF(2^8) cho Chipkill x4: mỗi symbol 8 bit là phần của một chip x4 qua 2 beat.

`timescale 1ns / 1ps

module rs_chipkill_encoder
    import gf256_arith_pkg::*;
#(
    parameter int DATA_SYMBOLS   = 16, // 16 symbol x 8 bit = 128 bit dữ liệu (2 beat x 64 bit)
    parameter int PARITY_SYMBOLS = 2   // 2 chip x4 kiểm tra
)(
    input  logic                                clk,
    input  logic                                rst_n,

    input  logic                                i_valid,
    output logic                                o_ready,
    input  logic [DATA_SYMBOLS*8-1:0]           i_data,

    output logic                                o_valid,
    input  logic                                i_ready,
    output logic [(DATA_SYMBOLS+PARITY_SYMBOLS)*8-1:0] o_codeword
);

    assign o_ready = i_ready || !o_valid;

    // Parity chọn sao cho hai hội chứng của cả codeword bằng 0: S0 = Σ c_i, S1 = Σ c_i·α^i.
    // Với A = Σ d_i, B = Σ d_i·α^i: c17 = (B + α^16·A)·K, c16 = A + c17 (K = (α^16 + α^17)^-1).
    // Nhân hằng tách thành assign theo từng symbol (ma trận XOR cố định), cộng dồn bằng XOR
    gf256_t prod [DATA_SYMBOLS];
    gf256_t acc_a [DATA_SYMBOLS+1];
    gf256_t acc_b [DATA_SYMBOLS+1];
    assign acc_a[0] = '0;
    assign acc_b[0] = '0;
    for (genvar i = 0; i < DATA_SYMBOLS; i++) begin : g_sum
        assign prod[i]      = gf256_mul(i_data[i*8 +: 8], RS_ALPHA[i*8 +: 8]);
        assign acc_a[i + 1] = acc_a[i] ^ i_data[i*8 +: 8];
        assign acc_b[i + 1] = acc_b[i] ^ prod[i];
    end

    wire gf256_t a_sum = acc_a[DATA_SYMBOLS];
    wire gf256_t b_sum = acc_b[DATA_SYMBOLS];
    wire gf256_t p17   = gf256_mul(b_sum ^ gf256_mul(a_sum, RS_ALPHA[16*8 +: 8]), RS_K);
    wire gf256_t p16   = a_sum ^ p17;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_valid    <= 1'b0;
            o_codeword <= '0;
        end else if (o_ready) begin
            o_valid <= i_valid;
            if (i_valid) o_codeword <= {p17, p16, i_data};
        end
    end

endmodule
