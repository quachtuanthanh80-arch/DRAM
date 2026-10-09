// File: tb_fault_hardened_csr.sv
// Chức năng: Testbench kiểm thử bộ bỏ phiếu TMR 2-out-of-3 và cảnh báo xung nhiễu (glitch) theo HOST 2020.
`timescale 1ns / 1ps

module tb_fault_hardened_csr;
    logic        clk;
    logic        rst_n;

    logic        i_cfg_we;
    logic [15:0] i_cfg_rh_threshold;
    logic [1:0]  i_cfg_rowpress_curve;
    logic        i_cfg_dual_hash_en;
    logic [1:0]  i_cfg_scramble_mode;

    wire  [15:0] o_cfg_rh_threshold;
    wire  [1:0]  o_cfg_rowpress_curve;
    wire         o_cfg_dual_hash_en;
    wire  [1:0]  o_cfg_scramble_mode;
    wire         o_glitch_alert;
    wire         o_security_locked;

    fault_hardened_csr dut (
        .clk                  (clk),
        .rst_n                (rst_n),
        .i_cfg_we             (i_cfg_we),
        .i_cfg_rh_threshold   (i_cfg_rh_threshold),
        .i_cfg_rowpress_curve (i_cfg_rowpress_curve),
        .i_cfg_dual_hash_en   (i_cfg_dual_hash_en),
        .i_cfg_scramble_mode  (i_cfg_scramble_mode),
        .o_cfg_rh_threshold   (o_cfg_rh_threshold),
        .o_cfg_rowpress_curve (o_cfg_rowpress_curve),
        .o_cfg_dual_hash_en   (o_cfg_dual_hash_en),
        .o_cfg_scramble_mode  (o_cfg_scramble_mode),
        .o_glitch_alert       (o_glitch_alert),
        .o_security_locked    (o_security_locked)
    );

    initial clk = 0;
    always #1.25 clk = ~clk;

    int test_errors = 0;

    initial begin
        rst_n = 0;
        i_cfg_we = 0;
        i_cfg_rh_threshold = 16'd1024;
        i_cfg_rowpress_curve = 2'b00;
        i_cfg_dual_hash_en = 1'b1;
        i_cfg_scramble_mode = 2'b10;

        #10;
        rst_n = 1;
        #10;

        $display("=== [TEST 1] Kiểm tra giá trị Reset mặc định an toàn ===");
        if (o_cfg_rh_threshold !== 16'd1024 || o_cfg_scramble_mode !== 2'b10 || o_glitch_alert !== 0) begin
            $display("[FAIL] Trạng thái Reset không đúng chuẩn!");
            test_errors++;
        end else begin
            $display("[PASS] Trạng thái Reset đạt chuẩn an toàn: Thresh=%0d Scramble=%b",
                     o_cfg_rh_threshold, o_cfg_scramble_mode);
        end

        $display("=== [TEST 2] Ghi cấu hình mới đồng thời vào 3 ray TMR ===");
        i_cfg_we = 1;
        i_cfg_rh_threshold = 16'd512;
        i_cfg_scramble_mode = 2'b10;
        #2.5;
        i_cfg_we = 0;
        #5;

        if (o_cfg_rh_threshold !== 16'd512) begin
            $display("[FAIL] Ghi cấu hình thất bại: Got %0d", o_cfg_rh_threshold);
            test_errors++;
        end else begin
            $display("[PASS] Cấu hình 3 đường ray đồng bộ thành công: Thresh=%0d", o_cfg_rh_threshold);
        end

        $display("=== [TEST 3] Bơm lỗi đơn tia (SEU) vào 1 ray và kiểm tra bỏ phiếu 2-out-of-3 ===");
        // Bơm xung nhiễu làm lệch rail0
        dut.rail0_rh_thresh = 16'hFFFF;
        #2.5;

        // Đầu ra phải giữ vững 16'd512 nhờ rail1 và rail2 chiếm đa số
        if (o_cfg_rh_threshold !== 16'd512) begin
            $display("[FAIL] Bỏ phiếu TMR thất bại khi 1 ray bị lỗi: Got %0d", o_cfg_rh_threshold);
            test_errors++;
        end else begin
            $display("[PASS] Bộ bỏ phiếu TMR chống chịu lỗi đơn cực tốt: Output vẫn giữ nguyên 512!");
        end

        if (!o_glitch_alert) begin
            $display("[FAIL] Không phát hiện cảnh báo xung nhiễu (o_glitch_alert)!");
            test_errors++;
        end else begin
            $display("[PASS] Phát hiện lệch ray và kích hoạt o_glitch_alert thành công!");
        end

        #5;
        if (!o_security_locked) begin
            $display("[FAIL] Không chốt khóa bảo mật sau cảnh báo glitch!");
            test_errors++;
        end else begin
            $display("[PASS] Chốt khóa bảo vệ phần cứng (o_security_locked) thành công!");
        end

        if (test_errors == 0) begin
            $display("\n>>> [ALL TESTS PASSED] Fault-Hardened CSR hoạt động hoàn hảo! <<<\n");
            $finish(0);
        end else begin
            $display("\n>>> [FAIL] Phát hiện %0d lỗi! <<<\n", test_errors);
            $finish(1);
        end
    end

endmodule
