// rs_chipkill_encoder.sv
// Bo ma hoa Reed-Solomon RS(18,16) tren truong GF(2^4) bao ve Chipkill cho chip nho DRAM x4

`timescale 1ns / 1ps

module rs_chipkill_encoder
    import gf16_arith_pkg::*;
#(
    parameter int DATA_SYMBOLS   = 16, // 16 symbols x 4-bit = 64-bit data
    parameter int PARITY_SYMBOLS = 2   // 2 symbols x 4-bit = 8-bit parity (RS(18,16))
)(
    input  logic                                clk,
    input  logic                                rst_n,

    // Giao dien du lieu vao
    input  logic                                i_valid,
    output logic                                o_ready,
    input  logic [DATA_SYMBOLS*4-1:0]           i_data,

    // Giao dien du lieu ra da ghep ma parity
    output logic                                o_valid,
    input  logic                                i_ready,
    output logic [(DATA_SYMBOLS+PARITY_SYMBOLS)*4-1:0] o_codeword
);

    assign o_ready = i_ready || !o_valid;

    // Phan ra du lieu thanh mang 16 symbols
    gf16_t msg_symbols [DATA_SYMBOLS];
    always_comb begin
        for (int i = 0; i < DATA_SYMBOLS; i++) begin
            msg_symbols[i] = i_data[i*4 +: 4];
        end
    end

    // Tinh toan 2 parity symbols bang LFSR da thuc sinh g(x) = x^2 + 3x + 2
    // Co che song song ket hop to hop: P0 = sum(msg_i * alpha_i), P1 = sum(msg_i * beta_i)
    gf16_t p0_comb, p1_comb;

    // He so ma tran tao ma parity cho RS(18,16)
    // Tinh toan truc tiep bang phep nhan-cong Galois trong 1 chu ky
    always_comb begin
        p0_comb = 4'h0;
        p1_comb = 4'h0;
        for (int i = 0; i < DATA_SYMBOLS; i++) begin
            // Ma hoa Cauchy/Vandermonde RS: P0 = sum(msg_i), P1 = sum(msg_i * x_i) voi x_i = i
            p0_comb = gf16_add(p0_comb, msg_symbols[i]);
            p1_comb = gf16_add(p1_comb, gf16_mul(msg_symbols[i], gf16_t'(i)));
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_valid    <= 1'b0;
            o_codeword <= '0;
        end else if (o_ready) begin
            o_valid <= i_valid;
            if (i_valid) begin
                // Ghep 64-bit data voi 8-bit parity thanh 72-bit codeword
                o_codeword <= {p1_comb, p0_comb, i_data};
            end
        end
    end

endmodule
