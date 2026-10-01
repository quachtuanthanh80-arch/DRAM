// rs_chipkill_decoder.sv
// Bo giai ma Reed-Solomon RS(18,16) sua loi 1 symbol 4-bit (1 chip DRAM x4) va phat hien loi 2 symbol

`timescale 1ns / 1ps

module rs_chipkill_decoder
    import gf16_arith_pkg::*;
#(
    parameter int DATA_SYMBOLS   = 16,
    parameter int PARITY_SYMBOLS = 2
)(
    input  logic                                clk,
    input  logic                                rst_n,

    // Giao dien codeword 72-bit vao (tu DRAM Bus / PHY)
    input  logic                                i_valid,
    output logic                                o_ready,
    input  logic [(DATA_SYMBOLS+PARITY_SYMBOLS)*4-1:0] i_codeword,

    // Giao dien du lieu 64-bit sau khi sua loi
    output logic                                o_valid,
    input  logic                                i_ready,
    output logic [DATA_SYMBOLS*4-1:0]           o_data,

    // Tin hieu telemetry thong bao trang thai loi
    output logic                                o_single_corrected,
    output logic                                o_double_detected,
    output logic [3:0]                          o_error_symbol_idx
);

    assign o_ready = i_ready || !o_valid;

    // Phan ra du lieu codeword thanh 16 data symbols va 2 parity symbols
    gf16_t rx_msg    [DATA_SYMBOLS];
    gf16_t rx_parity [PARITY_SYMBOLS];

    always_comb begin
        for (int i = 0; i < DATA_SYMBOLS; i++) begin
            rx_msg[i] = i_codeword[i*4 +: 4];
        end
        rx_parity[0] = i_codeword[64 +: 4];
        rx_parity[1] = i_codeword[68 +: 4];
    end

    // 1. Tinh toan hoi chung loi (Syndrome Calculation)
    gf16_t s0_comb, s1_comb;
    always_comb begin
        s0_comb = rx_parity[0];
        s1_comb = rx_parity[1];
        for (int i = 0; i < DATA_SYMBOLS; i++) begin
            s0_comb = gf16_add(s0_comb, rx_msg[i]);
            s1_comb = gf16_add(s1_comb, gf16_mul(rx_msg[i], gf16_t'(i)));
        end
    end

    // 2. Dinh vi vi tri loi va do lon sai so O(1) truc tiep (Direct Error Locator & Evaluator)
    logic [3:0] match_idx;
    logic       match_found;
    gf16_t      err_magnitude;

    always_comb begin
        if ((s0_comb == 4'h0) && (s1_comb == 4'h0)) begin
            match_found   = 1'b0;
            match_idx     = 4'h0;
            err_magnitude = 4'h0;
        end else if (s0_comb != 4'h0) begin
            // 1 data symbol error: Ti so S1 / S0 = e * x_j / e = x_j truc tiep cho chi so match_idx
            match_found   = 1'b1;
            match_idx     = gf16_mul(s1_comb, gf16_inv(s0_comb));
            err_magnitude = s0_comb;
        end else begin
            // S0 == 0 nhung S1 != 0: Loi kep 2-symbol khong the sua
            match_found   = 1'b0;
            match_idx     = 4'h0;
            err_magnitude = 4'h0;
        end
    end

    // 3. Tuyen du lieu sua loi (Correction MUX)
    logic [DATA_SYMBOLS*4-1:0] corrected_data;
    always_comb begin
        corrected_data = i_codeword[63:0];
        if (match_found && (s0_comb != 4'h0)) begin
            corrected_data[match_idx*4 +: 4] = rx_msg[match_idx] ^ err_magnitude;
        end
    end

    // 4. Thanh ghi xuat ket qua (Pipeline Stage)
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
                    // Khong co loi
                    o_single_corrected <= 1'b0;
                    o_double_detected  <= 1'b0;
                end else if (match_found) begin
                    // Sua duoc 1 symbol 4-bit (1 chip DRAM x4)
                    o_single_corrected <= 1'b1;
                    o_double_detected  <= 1'b0;
                end else begin
                    // Loi kep khong the sua (Double Symbol Error)
                    o_single_corrected <= 1'b0;
                    o_double_detected  <= 1'b1;
                end
            end
        end
    end

endmodule
