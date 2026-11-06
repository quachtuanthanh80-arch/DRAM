// File: tb_rs_chipkill_selfcheck.sv
// Chức năng: Kiểm thử RS(18,16)/GF(2^8) Chipkill: vét cạn lỗi một chip (18 vị trí x 255 độ lớn), đo tỉ lệ phát hiện lỗi hai chip.

`timescale 1ns / 1ps

module tb_rs_chipkill_selfcheck;
    `include "tb_check.svh"

    logic clk = 0;
    always #1.25 clk = ~clk;

    logic         rst_n = 0;
    logic         i_valid = 0, o_ready, o_valid;
    logic [127:0] i_data = 0, o_data;
    logic         i_inject_en = 0;
    logic [1:0]   i_inject_count = 0;
    logic [4:0]   i_inject_sym_idx0 = 0, i_inject_sym_idx1 = 0;
    logic [7:0]   i_inject_val0 = 0, i_inject_val1 = 0;
    logic         o_single_corrected, o_uncorrectable;
    logic [4:0]   o_error_symbol_idx;

    tb_rs_chipkill u_dut (
        .clk(clk), .rst_n(rst_n), .i_valid(i_valid), .o_ready(o_ready), .i_data(i_data),
        .i_inject_en(i_inject_en), .i_inject_count(i_inject_count),
        .i_inject_sym_idx0(i_inject_sym_idx0), .i_inject_val0(i_inject_val0),
        .i_inject_sym_idx1(i_inject_sym_idx1), .i_inject_val1(i_inject_val1),
        .o_valid(o_valid), .i_ready(1'b1), .o_data(o_data),
        .o_single_corrected(o_single_corrected), .o_uncorrectable(o_uncorrectable), .o_error_symbol_idx(o_error_symbol_idx)
    );

    // Một giao dịch qua encoder -> tiêm lỗi -> decoder (mỗi tầng 1 chu kỳ)
    task automatic xfer(input logic [127:0] d, input int cnt, input int s0, input int v0, input int s1, input int v1);
        @(negedge clk);
        i_valid = 1; i_data = d; i_inject_en = (cnt > 0); i_inject_count = 2'(cnt);
        i_inject_sym_idx0 = 5'(s0); i_inject_val0 = 8'(v0); i_inject_sym_idx1 = 5'(s1); i_inject_val1 = 8'(v1);
        @(negedge clk);
        i_valid = 0; i_inject_en = 0;
        while (!o_valid) @(negedge clk);
    endtask

    initial begin
        logic [127:0] d;
        repeat (3) @(posedge clk);
        rst_n = 1;

        // 1. Dữ liệu sạch
        begin
            int bad;
            bad = 0;
            for (int n = 0; n < 50; n++) begin
                d = {$urandom, $urandom, $urandom, $urandom};
                xfer(d, 0, 0, 0, 0, 0);
                if (o_data !== d || o_single_corrected || o_uncorrectable) bad++;
            end
            tb_check(bad == 0, $sformatf("Clean codewords decode losslessly with no flag (%0d/50 wrong)", bad));
        end

        // 2. Hỏng một chip x4 bất kỳ (kể cả hai chip kiểm tra) với mọi độ lớn: sửa đúng 100% (SSC)
        begin
            int bad, wrong_idx;
            bad = 0;
            wrong_idx = 0;
            for (int s = 0; s < 18; s++)
                for (int v = 1; v < 256; v++) begin
                    d = {$urandom, $urandom, $urandom, $urandom};
                    xfer(d, 1, s, v, 0, 0);
                    if (o_data !== d || !o_single_corrected || o_uncorrectable) bad++;
                    if (o_error_symbol_idx != 5'(s)) wrong_idx++;
                end
            tb_check(bad == 0 && wrong_idx == 0,
                     $sformatf("Exhaustive single-chip failure (18 symbols x 255 values = 4590): %0d wrong data, %0d wrong locator", bad, wrong_idx));
        end

        // 3. Hỏng hai chip: d = 3 nên không bảo đảm DSD. Đo tỉ lệ phát hiện trên mẫu ngẫu nhiên (tham chiếu Python ~93.7%).
        begin
            int det, mis, total, s0, s1;
            det = 0; mis = 0; total = 20000;
            for (int n = 0; n < total; n++) begin
                s0 = $urandom_range(0, 17);
                do s1 = $urandom_range(0, 17); while (s1 == s0);
                d = {$urandom, $urandom, $urandom, $urandom};
                xfer(d, 2, s0, $urandom_range(1, 255), s1, $urandom_range(1, 255));
                if (o_uncorrectable) det++;
                else if (o_single_corrected) mis++;
            end
            $display("[INFO] double-chip failures: %0d/%0d detected (%.2f%%), %0d miscorrected, %0d silent",
                     det, total, 100.0 * det / total, mis, total - det - mis);
            tb_check(det + mis == total, "Double-chip failures never decode as clean (no zero-syndrome escape)");
            tb_check(det * 100 > total * 90, $sformatf("Double-chip detection rate above 90%% (%0d/%0d)", det, total));
        end

        tb_report();
        $finish;
    end
endmodule
