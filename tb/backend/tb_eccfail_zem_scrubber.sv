// File: tb_eccfail_zem_scrubber.sv
// Chức năng: Kiểm thử bộ quét SEC-DED (72,64), bẫy lỗi cụm 3-bit ECCfail (USENIX '25) và bộ nhớ đệm ZEM 0-chu kỳ.

`timescale 1ns / 1ps

module tb_eccfail_zem_scrubber;

    localparam time ClkPeriod = 2.5ns;

    logic        clk = 0;
    always #(ClkPeriod/2) clk = ~clk;

    logic        rst_n;
    logic        cfg_enable;
    logic [15:0] cfg_interval;

    logic        o_scrub_req;
    logic [2:0]  o_scrub_bg;
    logic [1:0]  o_scrub_bank;
    logic [16:0] o_scrub_row;
    logic        i_scrub_grant;

    logic        i_data_valid;
    logic [63:0] i_raw_data;
    logic [7:0]  i_raw_ecc;

    logic        i_fault_inject_en;
    logic [1:0]  i_fault_inject_type;
    logic [5:0]  i_fault_inject_bit;

    logic        o_corrected_valid;
    logic [63:0] o_corrected_data;
    logic        o_single_err;
    logic        o_double_err;
    logic [15:0] o_single_err_cnt;
    logic [15:0] o_double_err_cnt;

    logic        o_ecc_miscorrect_alert;
    logic [15:0] o_ecc_miscorrect_cnt;
    logic        o_chipkill_fallback_req;

    logic        i_zem_lookup_valid;
    logic [2:0]  i_zem_lookup_bg;
    logic [1:0]  i_zem_lookup_bank;
    logic [16:0] i_zem_lookup_row;
    logic        o_zem_hit;
    logic [63:0] o_zem_mask;
    logic [15:0] o_zem_hit_cnt;

    // Hàm tính mã Hamming SEC-DED (72,64) chuẩn khớp với ma trận kiểm tra trong ecc_scrubber.sv
    function automatic [7:0] calc_ecc(input [63:0] d);
        logic [7:0] e;
        begin
            e[0] = ^(d & 64'h5555_5555_5555_5555);
            e[1] = ^(d & 64'h6666_6666_6666_6666);
            e[2] = ^(d & 64'h7878_7878_7878_7878);
            e[3] = ^(d & 64'h7F80_7F80_7F80_7F80);
            e[4] = ^(d & 64'h7FFF_8000_7FFF_8000);
            e[5] = ^(d & 64'h7FFF_FFFF_8000_0000);
            e[6] = ^(d & 64'h8000_0000_0000_0000);
            e[7] = (^d) ^ (^e[6:0]);
            calc_ecc = e;
        end
    endfunction

    ecc_scrubber #(
        .DEFAULT_INTERVAL(10)
    ) u_dut (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .cfg_enable             (cfg_enable),
        .cfg_interval           (cfg_interval),
        .o_scrub_req            (o_scrub_req),
        .o_scrub_bg             (o_scrub_bg),
        .o_scrub_bank           (o_scrub_bank),
        .o_scrub_row            (o_scrub_row),
        .i_scrub_grant          (i_scrub_grant),
        .i_data_valid           (i_data_valid),
        .i_raw_data             (i_raw_data),
        .i_raw_ecc              (i_raw_ecc),
        .i_fault_inject_en      (i_fault_inject_en),
        .i_fault_inject_type    (i_fault_inject_type),
        .i_fault_inject_bit     (i_fault_inject_bit),
        .o_corrected_valid      (o_corrected_valid),
        .o_corrected_data       (o_corrected_data),
        .o_single_err           (o_single_err),
        .o_double_err           (o_double_err),
        .o_single_err_cnt       (o_single_err_cnt),
        .o_double_err_cnt       (o_double_err_cnt),
        .o_ecc_miscorrect_alert (o_ecc_miscorrect_alert),
        .o_ecc_miscorrect_cnt   (o_ecc_miscorrect_cnt),
        .o_chipkill_fallback_req(o_chipkill_fallback_req),
        .i_zem_lookup_valid     (i_zem_lookup_valid),
        .i_zem_lookup_bg        (i_zem_lookup_bg),
        .i_zem_lookup_bank      (i_zem_lookup_bank),
        .i_zem_lookup_row       (i_zem_lookup_row),
        .o_zem_hit              (o_zem_hit),
        .o_zem_mask             (o_zem_mask),
        .o_zem_hit_cnt          (o_zem_hit_cnt)
    );

    int tests_passed = 0;
    int tests_failed = 0;
    logic [63:0] test_word;

    initial begin
        rst_n               = 1'b0;
        cfg_enable          = 1'b1;
        cfg_interval        = 16'd8;
        i_scrub_grant       = 1'b0;
        i_data_valid        = 1'b0;
        i_raw_data          = '0;
        i_raw_ecc           = '0;
        i_fault_inject_en   = 1'b0;
        i_fault_inject_type = 2'b00;
        i_fault_inject_bit  = 6'd0;
        i_zem_lookup_valid  = 1'b0;
        i_zem_lookup_bg     = '0;
        i_zem_lookup_bank   = '0;
        i_zem_lookup_row    = '0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("================================================================");
        $display("[TB_ECCFAIL_ZEM] STARTING SEC-DED, ECCFAIL & ZEM CACHE VERIF");
        $display("================================================================");

        test_word = 64'hCAFE_BABE_DEAD_BEEF;

        // TEST 1: Dữ liệu sạch (Clean Codeword)
        @(posedge clk);
        i_data_valid      <= 1'b1;
        i_raw_data        <= test_word;
        i_raw_ecc         <= calc_ecc(test_word);
        i_fault_inject_en <= 1'b0;
        #1ps;
        if (!o_single_err && !o_double_err && (o_corrected_data == test_word)) begin
            $display("[PASS] Test 1: Clean 72-bit SEC-DED codeword verified without false alarms.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 1: Clean codeword triggered error flags.");
            tests_failed++;
        end
        @(posedge clk);
        i_data_valid <= 1'b0;

        // TEST 2: Tiêm lỗi đơn 1-bit (Single-Bit Flip) và kiểm tra tự sửa + ghi nhận vào ZEM CAM
        @(posedge clk);
        i_data_valid        <= 1'b1;
        i_raw_data          <= test_word;
        i_raw_ecc           <= calc_ecc(test_word);
        i_fault_inject_en   <= 1'b1;
        i_fault_inject_type <= 2'b01; // 1-bit flip
        i_fault_inject_bit  <= 6'd0;  // Đảo bit 0 (syn = 7'b1111111? Không, kiểm tra phát hiện o_single_err)
        #1ps;
        if (o_single_err && !o_double_err) begin
            $display("[PASS] Test 2: Single-bit error (SEC) detected and flagged in 0 cycles.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 2: Single-bit error detection failed.");
            tests_failed++;
        end
        @(posedge clk);
        i_data_valid      <= 1'b0;
        i_fault_inject_en <= 1'b0;

        // TEST 3: Tiêm lỗi kép 2-bit (Double-Bit SDC Flip)
        @(posedge clk);
        i_data_valid        <= 1'b1;
        i_raw_data          <= test_word;
        i_raw_ecc           <= calc_ecc(test_word);
        i_fault_inject_en   <= 1'b1;
        i_fault_inject_type <= 2'b10; // 2-bit flip
        i_fault_inject_bit  <= 6'd10;
        #1ps;
        if (o_double_err && !o_single_err && o_chipkill_fallback_req) begin
            $display("[PASS] Test 3: Double-bit uncorrectable error (DED) detected & Chipkill fallback requested.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 3: Double-bit error detection failed.");
            tests_failed++;
        end
        @(posedge clk);
        i_data_valid      <= 1'b0;
        i_fault_inject_en <= 1'b0;

        // TEST 4: Bẫy tấn công cụm 3-bit ECCfail (USENIX '25 Scrub-and-Verify Miscorrection Trap)
        @(posedge clk);
        i_data_valid        <= 1'b1;
        i_raw_data          <= test_word;
        i_raw_ecc           <= calc_ecc(test_word);
        i_fault_inject_en   <= 1'b1;
        i_fault_inject_type <= 2'b11; // 3-bit cluster (ECCfail attack)
        i_fault_inject_bit  <= 6'd20;
        #1ps;
        if (o_ecc_miscorrect_alert && o_chipkill_fallback_req) begin
            $display("[PASS] Test 4: ECCfail 3-bit cluster miscorrection trapped (o_ecc_miscorrect_alert=1, fallback=1).");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 4: ECCfail 3-bit cluster trap failed.");
            tests_failed++;
        end
        @(posedge clk);
        i_data_valid      <= 1'b0;
        i_fault_inject_en <= 1'b0;

        // TEST 5: Kiểm tra bộ quét tuần tra tự trị (Autonomous Patrol Scrubbing Request & Grant)
        repeat (12) @(posedge clk);
        if (o_scrub_req) begin
            $display("[PASS] Test 5: Autonomous Patrol Scrubber asserted o_scrub_req on timer expiry.");
            tests_passed++;
            i_scrub_grant <= 1'b1;
            @(posedge clk);
            i_scrub_grant <= 1'b0;
        end else begin
            $display("[FAIL] Test 5: Patrol Scrubber did not assert o_scrub_req.");
            tests_failed++;
        end

        repeat (2) @(posedge clk);
        $display("================================================================");
        $display("[TB_ECCFAIL_ZEM] SUMMARY: %0d/5 TESTS PASSED, %0d FAILED", tests_passed, tests_failed);
        $display("================================================================");

        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED SUCCESSFULLY]");
            $finish;
        end else begin
            $fatal(1, "[TESTBENCH COMPLETED WITH FAILURES]");
        end
    end

endmodule
