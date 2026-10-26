// File: tb_rs_chipkill_selfcheck.sv
// Chức năng: Kiểm thử tự động bộ mã hóa/giải mã Reed-Solomon RS(18,16) trên GF(2^4) chống lỗi chết chip DRAM x4 (Chipkill).

`timescale 1ns / 1ps

module tb_rs_chipkill_selfcheck;

    localparam time ClkPeriod = 2.5ns;

    logic        clk = 0;
    always #(ClkPeriod/2) clk = ~clk;

    logic        rst_n;
    logic        i_valid;
    logic        o_ready;
    logic [63:0] i_data;

    logic        i_inject_en;
    logic [1:0]  i_inject_count;
    logic [3:0]  i_inject_sym_idx0;
    logic [3:0]  i_inject_val0;
    logic [3:0]  i_inject_sym_idx1;
    logic [3:0]  i_inject_val1;

    logic        o_valid;
    logic        i_ready;
    logic [63:0] o_data;
    logic        o_single_corrected;
    logic        o_double_detected;
    logic [3:0]  o_error_symbol_idx;

    tb_rs_chipkill u_dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .i_valid           (i_valid),
        .o_ready           (o_ready),
        .i_data            (i_data),
        .i_inject_en       (i_inject_en),
        .i_inject_count    (i_inject_count),
        .i_inject_sym_idx0 (i_inject_sym_idx0),
        .i_inject_val0     (i_inject_val0),
        .i_inject_sym_idx1 (i_inject_sym_idx1),
        .i_inject_val1     (i_inject_val1),
        .o_valid           (o_valid),
        .i_ready           (i_ready),
        .o_data            (o_data),
        .o_single_corrected(o_single_corrected),
        .o_double_detected (o_double_detected),
        .o_error_symbol_idx(o_error_symbol_idx)
    );

    int tests_passed = 0;
    int tests_failed = 0;
    logic [63:0] test_vec;

    initial begin
        rst_n             = 1'b0;
        i_valid           = 1'b0;
        i_data            = '0;
        i_inject_en       = 1'b0;
        i_inject_count    = '0;
        i_inject_sym_idx0 = '0;
        i_inject_val0     = '0;
        i_inject_sym_idx1 = '0;
        i_inject_val1     = '0;
        i_ready           = 1'b1;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("================================================================");
        $display("[TB_RS_CHIPKILL] STARTING RS(18,16) GF(2^4) CHIPKILL ECC VERIF");
        $display("================================================================");

        test_vec = 64'h0123_4567_89AB_CDEF;

        // TEST 1: Dữ liệu 64-bit không lỗi đi qua RS(18,16) Encoder (1 cyc) -> Decoder (1 cyc)
        @(posedge clk);
        i_valid     <= 1'b1;
        i_data      <= test_vec;
        i_inject_en <= 1'b0;
        @(posedge clk);
        i_valid     <= 1'b0;
        @(posedge clk);
        #1ps;
        if (o_valid && (o_data == test_vec) && !o_single_corrected && !o_double_detected) begin
            $display("[PASS] Test 1: Clean 64-bit codeword encoded & decoded losslessly.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 1: Clean codeword mismatch. valid=%b data=%h", o_valid, o_data);
            tests_failed++;
        end

        // TEST 2a: Hỏng toàn bộ 1 chip DRAM x4 tại Symbol 5 (sai số 4'hA) -> Tự phục hồi 100%
        @(posedge clk);
        i_valid           <= 1'b1;
        i_data            <= test_vec;
        i_inject_en       <= 1'b1;
        i_inject_count    <= 2'd1;
        i_inject_sym_idx0 <= 4'd5;
        i_inject_val0     <= 4'hA;
        @(posedge clk);
        i_valid           <= 1'b0;
        i_inject_en       <= 1'b0;
        @(posedge clk);
        #1ps;
        if (o_valid && (o_data == test_vec) && o_single_corrected && !o_double_detected && (o_error_symbol_idx == 4'd5)) begin
            $display("[PASS] Test 2a: Single x4 DRAM die failure at Symbol 5 (err=0xA) corrected bit-exact!");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 2a: Symbol 5 recovery failed. valid=%b data=%h single=%b idx=%0d",
                     o_valid, o_data, o_single_corrected, o_error_symbol_idx);
            tests_failed++;
        end

        // TEST 2b: Hỏng toàn bộ 1 chip DRAM x4 tại Symbol 12 (sai số 4'hF - đảo sạch 4 bit) -> Tự phục hồi 100%
        @(posedge clk);
        i_valid           <= 1'b1;
        i_data            <= 64'hFEDC_BA98_7654_3210;
        i_inject_en       <= 1'b1;
        i_inject_count    <= 2'd1;
        i_inject_sym_idx0 <= 4'd12;
        i_inject_val0     <= 4'hF;
        @(posedge clk);
        i_valid           <= 1'b0;
        i_inject_en       <= 1'b0;
        @(posedge clk);
        #1ps;
        if (o_valid && (o_data == 64'hFEDC_BA98_7654_3210) && o_single_corrected && !o_double_detected && (o_error_symbol_idx == 4'd12)) begin
            $display("[PASS] Test 2b: Complete 4-bit burst failure at Symbol 12 (err=0xF) corrected bit-exact!");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 2b: Symbol 12 recovery failed.");
            tests_failed++;
        end

        // TEST 3: Hỏng đồng thời 2 chip DRAM x4 (Double Symbol Error tại Symbol 3 và Symbol 11 cùng độ lớn 4'h7 -> S0=0, S1!=0)
        @(posedge clk);
        i_valid           <= 1'b1;
        i_data            <= test_vec;
        i_inject_en       <= 1'b1;
        i_inject_count    <= 2'd2;
        i_inject_sym_idx0 <= 4'd3;
        i_inject_val0     <= 4'h7;
        i_inject_sym_idx1 <= 4'd11;
        i_inject_val1     <= 4'h7;
        @(posedge clk);
        i_valid           <= 1'b0;
        i_inject_en       <= 1'b0;
        @(posedge clk);
        #1ps;
        if (o_valid && o_double_detected && !o_single_corrected) begin
            $display("[PASS] Test 3: Double x4 DRAM die failure (Symbols 3 & 11) accurately detected (o_double_detected=1)!");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 3: Double symbol error detection failed. valid=%b double=%b single=%b",
                     o_valid, o_double_detected, o_single_corrected);
            tests_failed++;
        end

        repeat (2) @(posedge clk);
        $display("================================================================");
        $display("[TB_RS_CHIPKILL] SUMMARY: %0d/4 TESTS PASSED, %0d FAILED", tests_passed, tests_failed);
        $display("================================================================");

        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED SUCCESSFULLY]");
            $finish;
        end else begin
            $fatal(1, "[TESTBENCH COMPLETED WITH FAILURES]");
        end
    end

endmodule
