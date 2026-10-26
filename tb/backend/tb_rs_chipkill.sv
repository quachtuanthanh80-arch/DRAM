// File: tb_rs_chipkill.sv
// Chức năng: Wrapper kết nối bộ mã hóa và giải mã RS(18,16) Chipkill kèm cổng tiêm lỗi đường truyền DRAM.

`timescale 1ns / 1ps

module tb_rs_chipkill (
    input  logic        clk,
    input  logic        rst_n,

    // Giao diện phát dữ liệu 64-bit
    input  logic        i_valid,
    output logic        o_ready,
    input  logic [63:0] i_data,

    // Giao diện tiêm lỗi (Fault Injection)
    input  logic        i_inject_en,
    input  logic [1:0]  i_inject_count, // 0 = không lỗi, 1 = 1 symbol, 2 = 2 symbols
    input  logic [3:0]  i_inject_sym_idx0,
    input  logic [3:0]  i_inject_val0,
    input  logic [3:0]  i_inject_sym_idx1,
    input  logic [3:0]  i_inject_val1,

    // Giao diện nhận dữ liệu sau khi sửa lỗi
    output logic        o_valid,
    input  logic        i_ready,
    output logic [63:0] o_data,
    output logic        o_single_corrected,
    output logic        o_double_detected,
    output logic [3:0]  o_error_symbol_idx
);

    logic        enc_valid;
    logic        enc_ready;
    logic [71:0] enc_codeword;

    rs_chipkill_encoder u_encoder (
        .clk        (clk),
        .rst_n      (rst_n),
        .i_valid    (i_valid),
        .o_ready    (o_ready),
        .i_data     (i_data),
        .o_valid    (enc_valid),
        .i_ready    (enc_ready),
        .o_codeword (enc_codeword)
    );

    logic        inject_en_q;
    logic [1:0]  inject_count_q;
    logic [3:0]  inject_sym0_q, inject_val0_q;
    logic [3:0]  inject_sym1_q, inject_val1_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inject_en_q    <= 1'b0;
            inject_count_q <= '0;
            inject_sym0_q  <= '0;
            inject_val0_q  <= '0;
            inject_sym1_q  <= '0;
            inject_val1_q  <= '0;
        end else if (o_ready && i_valid) begin
            inject_en_q    <= i_inject_en;
            inject_count_q <= i_inject_count;
            inject_sym0_q  <= i_inject_sym_idx0;
            inject_val0_q  <= i_inject_val0;
            inject_sym1_q  <= i_inject_sym_idx1;
            inject_val1_q  <= i_inject_val1;
        end else if (enc_valid && enc_ready) begin
            inject_en_q    <= 1'b0;
        end
    end

    wire [71:0] err_mask0 = (inject_en_q && (inject_count_q >= 2'd1)) ? ({68'd0, inject_val0_q} << (inject_sym0_q * 4)) : 72'd0;
    wire [71:0] err_mask1 = (inject_en_q && (inject_count_q >= 2'd2)) ? ({68'd0, inject_val1_q} << (inject_sym1_q * 4)) : 72'd0;
    wire [71:0] corrupted_codeword = enc_codeword ^ err_mask0 ^ err_mask1;

    rs_chipkill_decoder u_decoder (
        .clk                (clk),
        .rst_n              (rst_n),
        .i_valid            (enc_valid),
        .o_ready            (enc_ready),
        .i_codeword         (corrupted_codeword),
        .o_valid            (o_valid),
        .i_ready            (i_ready),
        .o_data             (o_data),
        .o_single_corrected (o_single_corrected),
        .o_double_detected  (o_double_detected),
        .o_error_symbol_idx (o_error_symbol_idx)
    );

endmodule
