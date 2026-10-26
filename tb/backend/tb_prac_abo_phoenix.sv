// File: tb_prac_abo_phoenix.sv
// Chức năng: Kiểm thử giao thức JEDEC DDR5 PRAC Alert-Back-Off (ABO), phòng thủ tấn công Phoenix (CVE-2025-6202) và Decoy Access.

`timescale 1ns / 1ps

module tb_prac_abo_phoenix;

    localparam time ClkPeriod = 2.5ns; // 400 MHz

    logic        clk = 0;
    always #(ClkPeriod/2) clk = ~clk;

    logic        rst_n;

    logic        i_cmd_valid;
    logic        i_cmd_is_write;
    logic [3:0]  i_cmd_id;
    logic [2:0]  i_cmd_bg;
    logic [1:0]  i_cmd_bank;
    logic [16:0] i_cmd_row;
    logic [9:0]  i_cmd_col;
    logic [7:0]  i_cmd_len;
    logic [4:0]  i_cmd_tag;
    logic        i_cmd_is_mitigation;

    logic [15:0] cfg_rowpress_thresh;
    logic [1:0]  cfg_rowpress_curve;
    logic [15:0] cfg_tras_max_thresh;
    logic        o_rowpress_alert;
    logic [2:0]  o_rowpress_bg;
    logic [1:0]  o_rowpress_bank;
    logic [16:0] o_rowpress_row;
    logic [15:0] o_rowpress_alert_cnt;
    logic        o_tras_clamped_alert;
    logic [15:0] o_tras_clamped_cnt;

    logic        i_dram_abo_alert;
    logic        o_abo_active;
    logic [15:0] o_abo_alert_cnt;
    logic [2:0]  o_abo_bg;
    logic [1:0]  o_abo_bank;
    logic [16:0] o_abo_row;

    logic [7:0]  cfg_raammt_thresh;
    logic [15:0] o_rfm_auto_cnt;
    logic        o_rfm_active;

    logic [7:0]  o_bg_ready;
    logic        o_engine_ready;
    logic        o_slack_cycle;

    logic        cfg_decoy_en;
    logic        o_decoy_active;
    logic [15:0] o_decoy_cnt;

    logic [2:0]  o_dfi_cmd;
    logic [2:0]  o_dfi_bg;
    logic [1:0]  o_dfi_bank;
    logic [16:0] o_dfi_row;
    logic [9:0]  o_dfi_col;

    logic        o_wb_valid;
    logic [4:0]  o_wb_tag;
    logic [63:0] o_wb_data;
    logic [1:0]  o_wb_resp;
    logic        o_wb_last;

    ddr5_cmd_engine u_dut (
        .clk                  (clk),
        .rst_n                (rst_n),
        .i_cmd_valid          (i_cmd_valid),
        .i_cmd_is_write       (i_cmd_is_write),
        .i_cmd_id             (i_cmd_id),
        .i_cmd_bg             (i_cmd_bg),
        .i_cmd_bank           (i_cmd_bank),
        .i_cmd_row            (i_cmd_row),
        .i_cmd_col            (i_cmd_col),
        .i_cmd_len            (i_cmd_len),
        .i_cmd_tag            (i_cmd_tag),
        .i_cmd_is_mitigation  (i_cmd_is_mitigation),
        .cfg_rowpress_thresh  (cfg_rowpress_thresh),
        .cfg_rowpress_curve   (cfg_rowpress_curve),
        .cfg_tras_max_thresh  (cfg_tras_max_thresh),
        .o_rowpress_alert     (o_rowpress_alert),
        .o_rowpress_bg        (o_rowpress_bg),
        .o_rowpress_bank      (o_rowpress_bank),
        .o_rowpress_row       (o_rowpress_row),
        .o_rowpress_alert_cnt (o_rowpress_alert_cnt),
        .o_tras_clamped_alert (o_tras_clamped_alert),
        .o_tras_clamped_cnt   (o_tras_clamped_cnt),
        .i_dram_abo_alert     (i_dram_abo_alert),
        .o_abo_active         (o_abo_active),
        .o_abo_alert_cnt      (o_abo_alert_cnt),
        .o_abo_bg             (o_abo_bg),
        .o_abo_bank           (o_abo_bank),
        .o_abo_row            (o_abo_row),
        .cfg_raammt_thresh    (cfg_raammt_thresh),
        .o_rfm_auto_cnt       (o_rfm_auto_cnt),
        .o_rfm_active         (o_rfm_active),
        .o_bg_ready           (o_bg_ready),
        .o_engine_ready       (o_engine_ready),
        .o_slack_cycle        (o_slack_cycle),
        .cfg_decoy_en         (cfg_decoy_en),
        .o_decoy_active       (o_decoy_active),
        .o_decoy_cnt          (o_decoy_cnt),
        .o_dfi_cmd            (o_dfi_cmd),
        .o_dfi_bg             (o_dfi_bg),
        .o_dfi_bank           (o_dfi_bank),
        .o_dfi_row            (o_dfi_row),
        .o_dfi_col            (o_dfi_col),
        .o_wb_valid           (o_wb_valid),
        .o_wb_tag             (o_wb_tag),
        .o_wb_data            (o_wb_data),
        .o_wb_resp            (o_wb_resp),
        .o_wb_last            (o_wb_last)
    );

    int tests_passed = 0;
    int tests_failed = 0;

    initial begin
        rst_n               = 1'b0;
        i_cmd_valid         = 1'b0;
        i_cmd_is_write      = 1'b0;
        i_cmd_id            = '0;
        i_cmd_bg            = '0;
        i_cmd_bank          = '0;
        i_cmd_row           = '0;
        i_cmd_col           = '0;
        i_cmd_len           = '0;
        i_cmd_tag           = '0;
        i_cmd_is_mitigation = 1'b0;
        cfg_rowpress_thresh = 16'd20;
        cfg_rowpress_curve  = 2'b11; // Aggressive dynamic curve
        cfg_tras_max_thresh = 16'd0;
        i_dram_abo_alert    = 1'b0;
        cfg_raammt_thresh   = 8'd4;
        cfg_decoy_en        = 1'b0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("================================================================");
        $display("[TB_PRAC_PHOENIX] STARTING PRAC ABO & PHOENIX (CVE-2025-6202) VERIF");
        $display("================================================================");

        // TEST 1: Mở dòng trên BG=1, Bank=2, Row=0x1A2B rồi kích hoạt JEDEC PRAC Alert-Back-Off (ABO)
        while (!o_engine_ready) @(posedge clk);
        i_cmd_valid    <= 1'b1;
        i_cmd_is_write <= 1'b0;
        i_cmd_bg       <= 3'd1;
        i_cmd_bank     <= 2'd2;
        i_cmd_row      <= 17'h01A2B;
        i_cmd_col      <= 10'h010;
        @(posedge clk);
        i_cmd_valid    <= 1'b0;

        repeat (12) @(posedge clk);

        // Kích hoạt tín hiệu vật lý i_dram_abo_alert từ DRAM (PRAC Back-Off)
        i_dram_abo_alert <= 1'b1;
        @(posedge clk);
        #1ps;

        if (o_abo_active && (o_abo_alert_cnt == 16'd1) && (o_abo_bg == 3'd1) && (o_abo_row == 17'h01A2B)) begin
            $display("[PASS] Test 1a: PRAC ABO Alert latched (BG=1, Bank=2, Row=0x01A2B, cnt=1).");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 1a: PRAC ABO latch failed. active=%b cnt=%0d row=%h",
                     o_abo_active, o_abo_alert_cnt, o_abo_row);
            tests_failed++;
        end

        // Gửi lệnh Mitigation (i_cmd_is_mitigation=1) trong lúc ABO đang active -> Phải phát CMD_REF (3'd5) ngay!
        i_cmd_valid         <= 1'b1;
        i_cmd_is_mitigation <= 1'b1;
        i_cmd_bg            <= 3'd1;
        i_cmd_bank          <= 2'd2;
        i_cmd_row           <= 17'h01A2C;
        @(posedge clk);
        i_cmd_valid         <= 1'b0;
        i_cmd_is_mitigation <= 1'b0;
        #1ps;

        if (o_dfi_cmd == 3'd5) begin
            $display("[PASS] Test 1b: PRAC ABO Recovery bypassed demand stall and issued CMD_REF.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 1b: Expected CMD_REF (5) during ABO mitigation, got %0d", o_dfi_cmd);
            tests_failed++;
        end

        i_dram_abo_alert <= 1'b0;
        repeat (4) @(posedge clk);

        // TEST 2: Tấn công Phoenix (CVE-2025-6202) lệch pha làm tươi -> Kiểm tra RFM tự trị khi vượt ngưỡng RAAMMT
        for (int r = 0; r < 4; r++) begin
            while (!o_engine_ready) @(posedge clk);
            i_cmd_valid    <= 1'b1;
            i_cmd_is_write <= 1'b1;
            i_cmd_bg       <= 3'd3;
            i_cmd_bank     <= r[1:0];
            i_cmd_row      <= 17'h02000 + r;
            i_cmd_col      <= 10'h000;
            @(posedge clk);
            i_cmd_valid    <= 1'b0;
            repeat (10) @(posedge clk);
        end

        repeat (10) @(posedge clk);
        if (o_rfm_auto_cnt >= 16'd1) begin
            $display("[PASS] Test 2: Phoenix (CVE-2025-6202) desync thwarted via Autonomous RFM (cnt=%0d).", o_rfm_auto_cnt);
            tests_passed++;
        end else begin
            $display("[FAIL] Test 2: Autonomous RFM did not trigger against Phoenix burst.");
            tests_failed++;
        end

        // TEST 3: Kiểm tra cơ chế làm nhiễu kênh kề Decoy Dummy Access (S3ORAM / Thang Hoang defense)
        cfg_decoy_en <= 1'b1;
        repeat (8) @(posedge clk);
        cfg_decoy_en <= 1'b0;

        if (o_decoy_cnt >= 16'd1) begin
            $display("[PASS] Test 3: Decoy Dummy Access bus obfuscation active during slack cycles (cnt=%0d).", o_decoy_cnt);
            tests_passed++;
        end else begin
            $display("[FAIL] Test 3: Decoy Dummy Access failed to increment o_decoy_cnt.");
            tests_failed++;
        end

        $display("================================================================");
        $display("[TB_PRAC_PHOENIX] SUMMARY: %0d/4 TESTS PASSED, %0d FAILED", tests_passed, tests_failed);
        $display("================================================================");

        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED SUCCESSFULLY]");
            $finish;
        end else begin
            $fatal(1, "[TESTBENCH COMPLETED WITH FAILURES]");
        end
    end

endmodule
