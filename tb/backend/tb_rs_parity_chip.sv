// File:      tb_rs_parity_chip.sv
// Chức năng: Kiểm tra Chipkill khi hỏng chip chứa symbol kiểm tra: lỗi ở P0/P1 phải được sửa, không được sửa nhầm sang dữ liệu.
`timescale 1ns / 1ps

module tb_rs_parity_chip;
    `include "tb_check.svh"

    logic         clk = 0, rst_n = 0;
    always #1.25 clk = ~clk;

    logic         enc_valid = 0, enc_ready, enc_ovalid;
    logic [127:0] enc_data = 0;
    logic [143:0] codeword;
    logic         dec_valid = 0, dec_ready, dec_ovalid;
    logic [143:0] dec_in = 0;
    logic [127:0] dec_data;
    logic         single_corr, uncorrectable;
    logic [4:0]   err_idx;

    rs_chipkill_encoder u_enc (.clk(clk), .rst_n(rst_n), .i_valid(enc_valid), .o_ready(enc_ready), .i_data(enc_data),
                               .o_valid(enc_ovalid), .i_ready(1'b1), .o_codeword(codeword));
    rs_chipkill_decoder u_dec (.clk(clk), .rst_n(rst_n), .i_valid(dec_valid), .o_ready(dec_ready), .i_codeword(dec_in),
                               .o_valid(dec_ovalid), .i_ready(1'b1), .o_data(dec_data),
                               .o_single_corrected(single_corr), .o_uncorrectable(uncorrectable), .o_error_symbol_idx(err_idx));

    task automatic encode(input logic [127:0] d, output logic [143:0] cw);
        @(negedge clk);
        enc_data = d; enc_valid = 1;
        @(negedge clk);
        enc_valid = 0;
        while (!enc_ovalid) @(negedge clk);
        cw = codeword;
    endtask

    task automatic decode(input logic [143:0] cw, output logic [127:0] d, output bit corr, output logic [4:0] idx);
        @(negedge clk);
        dec_in = cw; dec_valid = 1;
        @(negedge clk);
        dec_valid = 0;
        while (!dec_ovalid) @(negedge clk);
        d    = dec_data;
        corr = single_corr;
        idx  = err_idx;
    endtask

    initial begin
        int silent, wrong, total;
        logic [143:0] cw;
        logic [127:0] d, ref_d;
        logic [4:0]   idx;
        bit c;
        repeat (3) @(posedge clk);
        rst_n = 1;
        silent = 0;
        wrong = 0;
        total = 0;
        ref_d = 128'h0F1E_2D3C_4B5A_6978_8796_A5B4_C3D2_E1F0;
        encode(ref_d, cw);
        // Chip chứa P0 (bit 135:128) hoặc P1 (bit 143:136) hỏng với mọi độ lớn lỗi
        for (int p = 0; p < 2; p++) begin
            for (int v = 1; v < 256; v++) begin
                logic [143:0] bad;
                bad = cw;
                bad[128 + 8*p +: 8] = bad[128 + 8*p +: 8] ^ 8'(v);
                decode(bad, d, c, idx);
                total++;
                if (d !== ref_d) silent++;
                if (!c || idx != 5'(16 + p)) wrong++;
            end
        end
        $display("[INFO] parity-chip failures: %0d cases, %0d corrupted data, %0d not located at the parity symbol", total, silent, wrong);
        // RS trên GF(2^4) cũ: P0 trùng locator với symbol dữ liệu 0 nên 15/30 trường hợp bị sửa nhầm vào dữ liệu (R19)
        tb_check(silent == 0 && wrong == 0,
                 $sformatf("Single parity-chip failure is corrected at the parity symbol, data intact (%0d/%0d bad)", silent + wrong, total));
        tb_report();
        $finish;
    end
endmodule
