// File: rs_chipkill_decoder.sv
// Chức năng: Bộ giải mã RS(18,16) trên GF(2^8): sửa lỗi một symbol (một chip x4 hỏng) và báo lỗi không sửa được.

`timescale 1ns / 1ps

module rs_chipkill_decoder
    import gf256_arith_pkg::*;
#(
    parameter int DATA_SYMBOLS   = 16,
    parameter int PARITY_SYMBOLS = 2
)(
    input  logic                                clk,
    input  logic                                rst_n,

    input  logic                                i_valid,
    output logic                                o_ready,
    input  logic [(DATA_SYMBOLS+PARITY_SYMBOLS)*8-1:0] i_codeword,

    output logic                                o_valid,
    input  logic                                i_ready,
    output logic [DATA_SYMBOLS*8-1:0]           o_data,

    output logic                                o_single_corrected,
    // Khoảng cách d = 3 chỉ bảo đảm SSC: lỗi 2 chip được phát hiện với xác suất ~93.7% (syndrome rơi ngoài
    // 18 locator hợp lệ), phần còn lại bị sửa nhầm. Muốn DSD bảo đảm cần 3 symbol kiểm tra (d = 4).
    output logic                                o_uncorrectable,
    output logic [4:0]                          o_error_symbol_idx
);

    localparam int N = DATA_SYMBOLS + PARITY_SYMBOLS;

    assign o_ready = i_ready || !o_valid;

    // Lỗi đơn ở vị trí j với độ lớn e: S0 = e, S1 = e·α^j. Định vị bằng N phép so sánh song song S1 == S0·α^j
    // (nhân hằng = ma trận XOR), không cần bảng log/nghịch đảo và luôn ra one-hot vì các α^j phân biệt.
    gf256_t       prod [N];
    gf256_t       acc0 [N+1];
    gf256_t       acc1 [N+1];
    logic [N-1:0] loc_oh;
    logic [4:0]   loc_part [N+1];
    assign acc0[0]     = '0;
    assign acc1[0]     = '0;
    assign loc_part[0] = '0;
    for (genvar i = 0; i < N; i++) begin : g_syn
        assign prod[i]     = gf256_mul(i_codeword[i*8 +: 8], RS_ALPHA[i*8 +: 8]);
        assign acc0[i + 1] = acc0[i] ^ i_codeword[i*8 +: 8];
        assign acc1[i + 1] = acc1[i] ^ prod[i];
    end
    wire gf256_t s0 = acc0[N];
    wire gf256_t s1 = acc1[N];
    for (genvar j = 0; j < N; j++) begin : g_loc
        assign loc_oh[j]       = (s0 != 8'h00) && (s1 == gf256_mul(s0, RS_ALPHA[j*8 +: 8]));
        assign loc_part[j + 1] = loc_part[j] | (loc_oh[j] ? 5'(j) : 5'd0);
    end
    wire [4:0] loc_idx = loc_part[N];

    wire clean     = (s0 == 8'h00) && (s1 == 8'h00);
    wire located   = |loc_oh;

    logic [DATA_SYMBOLS*8-1:0] corr_mask;
    for (genvar j = 0; j < DATA_SYMBOLS; j++) begin : g_corr
        assign corr_mask[j*8 +: 8] = loc_oh[j] ? s0 : 8'h00;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_valid            <= 1'b0;
            o_data             <= '0;
            o_single_corrected <= 1'b0;
            o_uncorrectable    <= 1'b0;
            o_error_symbol_idx <= '0;
        end else if (o_ready) begin
            o_valid <= i_valid;
            if (i_valid) begin
                o_data             <= i_codeword[DATA_SYMBOLS*8-1:0] ^ corr_mask;
                o_single_corrected <= !clean && located;
                o_uncorrectable    <= !clean && !located;
                o_error_symbol_idx <= loc_idx;
            end
        end
    end

endmodule
