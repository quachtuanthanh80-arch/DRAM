// tb_rs_chipkill.sv
// Wrapper kiem tra bo ma hoa va giai ma RS(18,16) Chipkill kem cong tiem loi

`timescale 1ns / 1ps

module tb_rs_chipkill (
    input  logic        clk,
    input  logic        rst_n,

    // Giao dien phat du lieu 64-bit
    input  logic        i_valid,
    output logic        o_ready,
    input  logic [63:0] i_data,

    // Giao dien tiem loi (Fault Injection)
    input  logic        i_inject_en,
    input  logic [1:0]  i_inject_count, // 0 = khong loi, 1 = 1 symbol, 2 = 2 symbols
    input  logic [3:0]  i_inject_sym_idx0,
    input  logic [3:0]  i_inject_val0,
    input  logic [3:0]  i_inject_sym_idx1,
    input  logic [3:0]  i_inject_val1,

    // Giao dien nhan du lieu sau khi sua loi
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

    // Khoi tao bo ma hoa RS(18,16)
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

    // Pipeline dong bo tin hieu tiem loi theo do tre cua bo ma hoa
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

    // Cong tiem loi duong truyen DRAM PHY (Bus Channel Fault Injection)
    logic [71:0] corrupted_codeword;
    always_comb begin
        corrupted_codeword = enc_codeword;
        if (inject_en_q) begin
            if (inject_count_q >= 2'd1 && inject_sym0_q < 5'd18) begin
                corrupted_codeword[inject_sym0_q*4 +: 4] ^= inject_val0_q;
            end
            if (inject_count_q >= 2'd2 && inject_sym1_q < 5'd18) begin
                corrupted_codeword[inject_sym1_q*4 +: 4] ^= inject_val1_q;
            end
        end
    end

    // Khoi tao bo giai ma RS(18,16)
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
