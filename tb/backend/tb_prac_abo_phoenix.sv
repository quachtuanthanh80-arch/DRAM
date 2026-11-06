// File:        tb_prac_abo_phoenix.sv
// Chức năng:   Kiểm thử giao thức JEDEC DDR5 PRAC Alert-Back-Off (ABO), phòng thủ tấn công Phoenix (CVE-2025-6202) và Decoy Access (M-09).
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
    logic [6:1]  o_fault;

    logic [7:0]  o_bg_ready;
    logic        o_engine_ready;
    logic [31:0] o_bank_free;
    logic        o_engine_mit_only;
    logic        o_slack_cycle;

    logic        cfg_decoy_en;
    logic        i_decoy_avail;
    logic [21:0] i_decoy_addr;
    logic        o_decoy_take;
    logic        o_decoy_active;
    logic [15:0] o_decoy_cnt;
    bit          o_decoy_cnt_seen_fail = 0;

    logic [2:0]  o_dfi_cmd;
    logic [2:0]  o_dfi_bg;
    logic [1:0]  o_dfi_bank;
    logic [16:0] o_dfi_row;
    logic [9:0]  o_dfi_col;
    logic [7:0]  o_dfi_len;
    logic [4:0]  o_dfi_tag;
    logic        dfi_rddata_valid;
    logic [63:0] dfi_rddata;

    logic        o_wb_valid;
    logic [4:0]  o_wb_tag;
    logic [63:0] o_wb_data;
    logic [1:0]  o_wb_resp;
    logic        o_wb_last;

    // Nguồn địa chỉ mồi giả lập PRF bằng xorshift32
    logic [31:0] prf_state;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prf_state     <= 32'hDEC0_1234;
            i_decoy_avail <= 1'b1;
            i_decoy_addr  <= {3'd4, 2'd1, 17'h05A5A};
        end else if (o_decoy_take) begin
            logic [31:0] x;
            x = prf_state;
            x = x ^ (x << 13);
            x = x ^ (x >> 17);
            x = x ^ (x << 5);
            prf_state     <= x;
            i_decoy_avail <= 1'b1;
            i_decoy_addr  <= x[21:0];
        end
    end

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
        .o_fault              (o_fault),
        .o_bg_ready           (o_bg_ready),
        .o_engine_ready       (o_engine_ready),
        .o_bank_free          (o_bank_free),
        .o_engine_mit_only    (o_engine_mit_only),
        .o_slack_cycle        (o_slack_cycle),
        .cfg_decoy_en         (cfg_decoy_en),
        .i_decoy_avail        (i_decoy_avail),
        .i_decoy_addr         (i_decoy_addr),
        .o_decoy_take         (o_decoy_take),
        .o_decoy_active       (o_decoy_active),
        .o_decoy_cnt          (o_decoy_cnt),
        .o_dfi_cmd            (o_dfi_cmd),
        .o_dfi_bg             (o_dfi_bg),
        .o_dfi_bank           (o_dfi_bank),
        .o_dfi_row            (o_dfi_row),
        .o_dfi_col            (o_dfi_col),
        .o_dfi_len            (o_dfi_len),
        .o_dfi_tag            (o_dfi_tag),
        .i_dfi_rddata_valid   (dfi_rddata_valid),
        .i_dfi_rddata         (dfi_rddata),
        .o_wb_valid           (o_wb_valid),
        .o_wb_tag             (o_wb_tag),
        .o_wb_data            (o_wb_data),
        .o_wb_resp            (o_wb_resp),
        .o_wb_last            (o_wb_last)
    );

    dram_model #(.COL_W(10), .RL(9), .WL(9)) u_dram (
        .clk          (clk),
        .rst_n        (rst_n),
        .cmd          (o_dfi_cmd),
        .bg           (o_dfi_bg),
        .bank         (o_dfi_bank),
        .row          (o_dfi_row),
        .col          (o_dfi_col),
        .len          (o_dfi_len),
        .wrdata_en    (1'b0),
        .wrdata       ('0),
        .wrdata_mask  ('0),
        .wrdata_ecc   ('0),
        .rddata_valid (dfi_rddata_valid),
        .rddata       (dfi_rddata),
        .rddata_ecc   ()
    );

    dfi_jedec_checker #(.TCK_PS(2500)) u_jchk (
        .clk  (clk),
        .rst_n(rst_n),
        .cmd  (o_dfi_cmd),
        .bg   (o_dfi_bg),
        .bank (o_dfi_bank),
        .row  (o_dfi_row),
        .len  (o_dfi_len)
    );

    int tests_passed = 0;
    int tests_failed = 0;
    `include "tb_check.svh"

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
        cfg_rowpress_curve  = 2'b11;
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
        @(negedge clk);
        i_cmd_valid    = 1'b1;
        i_cmd_is_write = 1'b0;
        i_cmd_bg       = 3'd1;
        i_cmd_bank     = 2'd2;
        i_cmd_row      = 17'h01A2B;
        i_cmd_col      = 10'h010;
        @(posedge clk);
        @(negedge clk);
        i_cmd_valid    = 1'b0;

        repeat (16) @(posedge clk);

        // Kích hoạt tín hiệu vật lý i_dram_abo_alert từ DRAM (PRAC Back-Off)
        @(negedge clk);
        i_dram_abo_alert = 1'b1;
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

        // Lệnh giảm thiểu trong lúc ABO active vẫn phải được thực hiện: làm tươi hàng nạn nhân bằng ACT (sau PRE + RFMab).
        @(negedge clk);
        i_cmd_valid         = 1'b1;
        i_cmd_is_mitigation = 1'b1;
        i_cmd_bg            = 3'd1;
        i_cmd_bank          = 2'd2;
        i_cmd_row           = 17'h01A2C;
        @(posedge clk);
        @(negedge clk);
        i_cmd_valid         = 1'b0;
        i_cmd_is_mitigation = 1'b0;
        begin
            bit victim_act, abo_rfm;
            victim_act = 0;
            abo_rfm    = 0;
            for (int c = 0; c < 250 && !victim_act; c++) begin
                @(posedge clk);
                #1ps;
                if (o_dfi_cmd == 3'd6) abo_rfm = 1;
                if (o_dfi_cmd == 3'd1 && o_dfi_bg == 3'd1 && o_dfi_bank == 2'd2 && o_dfi_row == 17'h01A2C) victim_act = 1;
            end
            if (abo_rfm) begin
                $display("[PASS] Test 1c: ABO answered with RFMab.");
                tests_passed++;
            end else begin
                $display("[FAIL] Test 1c: no RFMab after ABO");
                tests_failed++;
            end
            if (victim_act) begin
                $display("[PASS] Test 1b: mitigation during ABO activated victim row 0x01A2C (victim refresh by ACT).");
                tests_passed++;
            end else begin
                $display("[FAIL] Test 1b: no victim-row ACT within window during ABO mitigation");
                tests_failed++;
            end
        end

        @(negedge clk);
        i_dram_abo_alert = 1'b0;
        repeat (20) @(posedge clk);

        // TEST 2: Tấn công Phoenix (CVE-2025-6202) -> Kiểm tra RFM tự trị khi vượt ngưỡng RAAMMT
        begin
            logic [15:0] rfm_before;
            rfm_before = o_rfm_auto_cnt;
            for (int r = 0; r < 4; r++) begin
                while (!o_bank_free[{3'd3, r[1:0]}] || o_engine_mit_only) @(posedge clk);
                @(negedge clk);
                i_cmd_valid    = 1'b1;
                i_cmd_is_write = 1'b1;
                i_cmd_bg       = 3'd3;
                i_cmd_bank     = r[1:0];
                i_cmd_row      = 17'h02000 + r;
                i_cmd_col      = 10'h000;
                @(posedge clk);
                @(negedge clk);
                i_cmd_valid    = 1'b0;
                repeat (10) @(posedge clk);
            end

            for (int c = 0; c < 200 && (o_rfm_auto_cnt == rfm_before); c++) @(posedge clk);
            if (o_rfm_auto_cnt > rfm_before) begin
                $display("[PASS] Test 2: Phoenix (CVE-2025-6202) desync thwarted via Autonomous RFM (cnt=%0d).", o_rfm_auto_cnt);
                tests_passed++;
            end else begin
                $display("[FAIL] Test 2: Autonomous RFM did not trigger against Phoenix burst.");
                tests_failed++;
            end
        end

        // TEST 3: Kiểm tra cơ chế làm nhiễu kênh kề Decoy Dummy Access (M-09)
        begin
            int decoy_acts;
            decoy_acts = 0;
            @(negedge clk);
            cfg_decoy_en = 1'b1;
            repeat (260) begin
                @(posedge clk);
                if (o_dfi_cmd == 3'd1) decoy_acts++;
            end
            @(negedge clk);
            cfg_decoy_en = 1'b0;
            if (o_decoy_cnt >= 16'd1 && decoy_acts > 0)
                $display("[INFO] Test 3: %0d decoy ACTs reached DFI", decoy_acts);
            else
                o_decoy_cnt_seen_fail = 1;
        end

        if (o_decoy_cnt >= 16'd1 && !o_decoy_cnt_seen_fail) begin
            $display("[PASS] Test 3: Decoy accesses issued real ACT commands during idle cycles (cnt=%0d).", o_decoy_cnt);
            tests_passed++;
        end else begin
            $display("[FAIL] Test 3: Decoy Dummy Access failed to increment o_decoy_cnt.");
            tests_failed++;
        end

        u_jchk.report("prac_phoenix");
        tb_check(u_jchk.timing_violations() == 0,
                 $sformatf("No JEDEC timing violation during PRAC/Phoenix/Decoy (%0d)", u_jchk.timing_violations()));
        tb_check(o_fault == 6'd0, $sformatf("No engine fault flags during clean run (o_fault=%b)", o_fault));

        $display("================================================================");
        $display("[TB_PRAC_PHOENIX] SUMMARY: %0d/%0d TESTS PASSED, %0d FAILED", tests_passed, tests_passed + tests_failed, tests_failed);
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

endmodule
