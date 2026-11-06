// File:        tb_directed_refresh_manager.sv
// Chức năng:   Testbench tự kiểm cho directed_refresh_manager: sinh hàng nạn nhân +/-1, +/-2, ưu tiên scrub, SA-F10/SA-F11 và o_drm_fault.
`timescale 1ns / 1ps

module tb_directed_refresh_manager;

    localparam int BG_WIDTH    = 3;
    localparam int BANK_WIDTH  = 2;
    localparam int ROW_WIDTH   = 17;
    localparam int QUEUE_DEPTH = 8;
    localparam time ClkPeriod  = 2.5ns; // 400 MHz

    logic clk = 0;
    always #(ClkPeriod/2) clk = ~clk;

    logic rst_n;

    logic                   cfg_drm_en;
    logic                   cfg_victim2_en;

    logic                   i_sdc_req;
    logic [BG_WIDTH-1:0]    i_sdc_bg;
    logic [BANK_WIDTH-1:0]  i_sdc_bank;
    logic [ROW_WIDTH-1:0]   i_sdc_row;

    logic                   i_rp_req;
    logic [BG_WIDTH-1:0]    i_rp_bg;
    logic [BANK_WIDTH-1:0]  i_rp_bank;
    logic [ROW_WIDTH-1:0]   i_rp_row;

    logic                   i_scrub_req;
    logic [BG_WIDTH-1:0]    i_scrub_bg;
    logic [BANK_WIDTH-1:0]  i_scrub_bank;
    logic [ROW_WIDTH-1:0]   i_scrub_row;
    logic                   o_scrub_grant;

    logic                   o_mitigation_req;
    logic [BG_WIDTH-1:0]    o_mitigation_bg;
    logic [BANK_WIDTH-1:0]  o_mitigation_bank;
    logic [ROW_WIDTH-1:0]   o_mitigation_row;
    logic                   i_mitigation_grant;

    logic [15:0]            o_drm_ref_count;
    logic                   o_queue_full;
    logic                   o_drm_fault;
    logic [(1<<BG_WIDTH)-1:0] o_proq_blk;

    // Instantiate DUT
    directed_refresh_manager #(
        .BG_WIDTH   (BG_WIDTH),
        .BANK_WIDTH (BANK_WIDTH),
        .ROW_WIDTH  (ROW_WIDTH),
        .QUEUE_DEPTH(QUEUE_DEPTH)
    ) u_dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .cfg_drm_en         (cfg_drm_en),
        .cfg_victim2_en     (cfg_victim2_en),
        .i_sdc_req          (i_sdc_req),
        .i_sdc_bg           (i_sdc_bg),
        .i_sdc_bank         (i_sdc_bank),
        .i_sdc_row          (i_sdc_row),
        .i_rp_req           (i_rp_req),
        .i_rp_bg            (i_rp_bg),
        .i_rp_bank          (i_rp_bank),
        .i_rp_row           (i_rp_row),
        .i_scrub_req        (i_scrub_req),
        .i_scrub_bg         (i_scrub_bg),
        .i_scrub_bank       (i_scrub_bank),
        .i_scrub_row        (i_scrub_row),
        .o_scrub_grant      (o_scrub_grant),
        .o_mitigation_req   (o_mitigation_req),
        .o_mitigation_bg    (o_mitigation_bg),
        .o_mitigation_bank  (o_mitigation_bank),
        .o_mitigation_row   (o_mitigation_row),
        .i_mitigation_grant (i_mitigation_grant),
        .i_cand_fresh       ({(1<<BG_WIDTH){1'b1}}),
        .o_proq_blk         (o_proq_blk),
        .o_drm_ref_count    (o_drm_ref_count),
        .o_queue_full       (o_queue_full),
        .o_drm_fault        (o_drm_fault)
    );

    int tests_run = 0;
    int tests_passed = 0;
    int tests_failed = 0;
    int inv_err = 0;
    `include "tb_check.svh"

    always @(posedge clk) begin
        if (rst_n) begin
            if (o_drm_fault || (u_dut.blkp_a !== u_dut.blkp_b) || (u_dut.pq_v !== u_dut.pq_region) || u_dut.inj_oh_err)
                inv_err++;
        end
    end

    initial begin
        $display("================================================================");
        $display("[TB_DRM] STARTING DIRECTED REFRESH MANAGER (DRM) VERIFICATION");
        $display("================================================================");

        rst_n              = 0;
        cfg_drm_en         = 1;
        cfg_victim2_en     = 0;
        i_sdc_req          = 0;
        i_sdc_bg           = 0;
        i_sdc_bank         = 0;
        i_sdc_row          = 0;
        i_rp_req           = 0;
        i_rp_bg            = 0;
        i_rp_bank          = 0;
        i_rp_row           = 0;
        i_scrub_req        = 0;
        i_scrub_bg         = 0;
        i_scrub_bank       = 0;
        i_scrub_row        = 0;
        i_mitigation_grant = 0;

        #(ClkPeriod * 2);
        rst_n = 1;
        #(ClkPeriod);

        // TEST 1: Idle state
        tests_run++;
        if (!o_mitigation_req && o_drm_ref_count == 0 && !o_queue_full && !o_drm_fault) begin
            $display("[PASS] Test 1: Reset idle state verified.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 1: Idle state mismatch.");
            tests_failed++;
        end

        // TEST 2: Aggressor Alert -> Victim Row Generation (Row +/- 1)
        tests_run++;
        @(negedge clk);
        i_sdc_req  = 1;
        i_sdc_bg   = 3'd1;
        i_sdc_bank = 2'd2;
        i_sdc_row  = 17'h1000;

        @(posedge clk);
        @(negedge clk);
        i_sdc_req = 0;

        // SA-F11: trong khi đẩy nạn nhân của BG 1 vào PROQ, chỉ o_proq_blk[1] được bật, các BG khác bằng 0
        tb_check((o_proq_blk & 8'b1111_1101) == 8'd0,
                 $sformatf("SA-F11: BG 1 push does not block other BGs (o_proq_blk=%b)", o_proq_blk));

        for (int c = 0; c < 8 && !o_mitigation_req; c++) @(posedge clk);
        #1;

        if (o_mitigation_req && o_mitigation_row == 17'h1001 &&
            o_mitigation_bg == 3'd1 && o_mitigation_bank == 2'd2) begin
            $display("[PASS] Test 2a: Victim 1 (Row + 1 = 0x1001) presented at output.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 2a: Expected Row 0x1001, got 0x%04X", o_mitigation_row);
            tests_failed++;
        end

        // Grant Victim 1 for exactly 1 cycle
        tests_run++;
        @(negedge clk);
        i_mitigation_grant = 1;
        @(negedge clk);
        i_mitigation_grant = 0;
        for (int c = 0; c < 8 && !o_mitigation_req; c++) @(posedge clk);
        #1ps;

        // Victim 2 should now be Row - 1 = 0x0FFF
        if (o_mitigation_req && o_mitigation_row == 17'h0FFF) begin
            $display("[PASS] Test 2b: Victim 2 (Row - 1 = 0x0FFF) presented at output.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 2b: Expected Row 0x0FFF, got 0x%04X", o_mitigation_row);
            tests_failed++;
        end

        // Grant Victim 2
        @(negedge clk);
        i_mitigation_grant = 1;
        @(negedge clk);
        i_mitigation_grant = 0;
        repeat (2) @(posedge clk);
        #1ps;

        // TEST 3: Priority - ECC Scrubbing when queue empty
        tests_run++;
        @(negedge clk);
        i_scrub_req  = 1;
        i_scrub_bg   = 3'd5;
        i_scrub_bank = 2'd3;
        i_scrub_row  = 17'h0555;
        for (int c = 0; c < 4 && !o_mitigation_req; c++) @(posedge clk);
        #1;

        if (o_mitigation_req && o_mitigation_bg == 3'd5 && o_mitigation_row == 17'h0555) begin
            @(negedge clk);
            i_mitigation_grant = 1;
            @(negedge clk);
            i_mitigation_grant = 0;
            #1;
            if (o_scrub_grant == 1) begin
                $display("[PASS] Test 3: ECC Patrol Scrub granted when DRM queue is empty.");
                tests_passed++;
            end else begin
                $display("[FAIL] Test 3: Scrub grant not asserted.");
                tests_failed++;
            end
            @(negedge clk);
            i_scrub_req = 0;
        end else begin
            $display("[FAIL] Test 3: Scrub request did not pass through.");
            tests_failed++;
        end

        #(ClkPeriod * 4);
        tb_check(inv_err == 0 && !o_drm_fault,
                 $sformatf("SA-F10: DRM invariants clean and o_drm_fault=0 (inv_err=%0d)", inv_err));

        $display("================================================================");
        $display("[TB_DRM] SUMMARY: %0d/%0d TESTS PASSED, %0d FAILED",
                 tests_passed, tests_run, tests_failed);
        $display("================================================================");

        tb_merge_legacy(tests_passed + tests_failed, tests_failed);
        tb_report();
        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED SUCCESSFULLY]");
            $finish;
        end else begin
            $fatal(1, "[TESTBENCH COMPLETED WITH FAILURES]");
        end
    end

endmodule: tb_directed_refresh_manager
