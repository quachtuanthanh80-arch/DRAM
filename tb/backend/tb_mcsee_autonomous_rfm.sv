// File:        tb_mcsee_autonomous_rfm.sv
// Chức năng:   Kiểm chứng cơ chế tự phát lệnh RFM JEDEC DDR5 khi CPU không gửi lệnh (McSee USENIX'25 defense, T-REG-01).
`timescale 1ns / 1ps

module tb_mcsee_autonomous_rfm;

    localparam int BG_COUNT       = 8;
    localparam int BG_WIDTH       = $clog2(BG_COUNT);
    localparam int BANK_COUNT     = 4;
    localparam int BANK_WIDTH     = $clog2(BANK_COUNT);
    localparam int ROW_WIDTH      = 17;
    localparam int COL_WIDTH      = 10;
    localparam int AXI_ID_WIDTH   = 4;
    localparam int AXI_DATA_WIDTH = 64;
    localparam int AXI_LEN_WIDTH  = 8;
    localparam int ROB_PTR_WIDTH  = 5;
    localparam time ClkPeriod     = 2.5ns; // 400 MHz

    logic clk = 0;
    always #(ClkPeriod/2) clk = ~clk;

    logic                      rst_n;
    logic                      i_cmd_valid;
    logic                      i_cmd_is_write;
    logic [AXI_ID_WIDTH-1:0]   i_cmd_id;
    logic [BG_WIDTH-1:0]       i_cmd_bg;
    logic [BANK_WIDTH-1:0]     i_cmd_bank;
    logic [ROW_WIDTH-1:0]      i_cmd_row;
    logic [COL_WIDTH-1:0]      i_cmd_col;
    logic [AXI_LEN_WIDTH-1:0]  i_cmd_len;
    logic [ROB_PTR_WIDTH-1:0]  i_cmd_tag;
    logic                      i_cmd_is_mitigation;

    logic                      o_rowpress_alert;
    logic [BG_WIDTH-1:0]       o_rowpress_bg;
    logic [BANK_WIDTH-1:0]     o_rowpress_bank;
    logic [ROW_WIDTH-1:0]      o_rowpress_row;
    logic [15:0]               o_rowpress_alert_cnt;
    logic                      o_tras_clamped_alert;
    logic [15:0]               o_tras_clamped_cnt;

    logic                      i_dram_abo_alert;
    logic                      o_abo_active;
    logic [15:0]               o_abo_alert_cnt;
    logic [BG_WIDTH-1:0]       o_abo_bg;
    logic [BANK_WIDTH-1:0]     o_abo_bank;
    logic [ROW_WIDTH-1:0]      o_abo_row;

    logic [7:0]                cfg_raammt_thresh;
    logic [15:0]               o_rfm_auto_cnt;
    logic                      o_rfm_active;
    logic                      o_cnt_fault;
    logic [6:1]                o_fault;

    logic [BG_COUNT-1:0]       o_bg_ready;
    logic                      o_engine_ready;
    logic [BG_COUNT*BANK_COUNT-1:0] o_bank_free;
    logic                      o_engine_mit_only;
    logic                      o_slack_cycle;

    logic [2:0]                o_dfi_cmd;
    logic [BG_WIDTH-1:0]       o_dfi_bg;
    logic [BANK_WIDTH-1:0]     o_dfi_bank;
    logic [ROW_WIDTH-1:0]      o_dfi_row;
    logic [COL_WIDTH-1:0]      o_dfi_col;
    logic [AXI_LEN_WIDTH-1:0]  o_dfi_len;
    logic [ROB_PTR_WIDTH-1:0]  o_dfi_tag;
    logic                      dfi_rddata_valid;
    logic [AXI_DATA_WIDTH-1:0] dfi_rddata;

    logic                      o_wb_valid;
    logic [ROB_PTR_WIDTH-1:0]  o_wb_tag;
    logic [AXI_DATA_WIDTH-1:0] o_wb_data;
    logic [1:0]                o_wb_resp;
    logic                      o_wb_last;

    localparam logic [2:0] CMD_NOP = 3'b000;
    localparam logic [2:0] CMD_ACT = 3'b001;
    localparam logic [2:0] CMD_PRE = 3'b010;
    localparam logic [2:0] CMD_RD  = 3'b011;
    localparam logic [2:0] CMD_WR  = 3'b100;
    localparam logic [2:0] CMD_REF = 3'b101;
    localparam logic [2:0] CMD_RFM = 3'b110;

    ddr5_cmd_engine #(
        .BG_COUNT        (BG_COUNT),
        .BANK_COUNT      (BANK_COUNT),
        .ROW_WIDTH       (ROW_WIDTH),
        .COL_WIDTH       (COL_WIDTH),
        .AXI_ID_WIDTH    (AXI_ID_WIDTH),
        .AXI_DATA_WIDTH  (AXI_DATA_WIDTH),
        .AXI_LEN_WIDTH   (AXI_LEN_WIDTH),
        .ROB_PTR_WIDTH   (ROB_PTR_WIDTH)
    ) u_dut (
        .clk                 (clk),
        .rst_n               (rst_n),
        .i_cmd_valid         (i_cmd_valid),
        .i_cmd_is_write      (i_cmd_is_write),
        .i_cmd_id            (i_cmd_id),
        .i_cmd_bg            (i_cmd_bg),
        .i_cmd_bank          (i_cmd_bank),
        .i_cmd_row           (i_cmd_row),
        .i_cmd_col           (i_cmd_col),
        .i_cmd_len           (i_cmd_len),
        .i_cmd_tag           (i_cmd_tag),
        .i_cmd_is_mitigation (i_cmd_is_mitigation),

        .cfg_rowpress_thresh (16'd5000),
        .cfg_rowpress_curve  (2'b00),
        .cfg_decoy_en        (1'b0),
        .cfg_tras_max_thresh (16'd8775),
        .o_rowpress_alert    (o_rowpress_alert),
        .o_rowpress_bg       (o_rowpress_bg),
        .o_rowpress_bank     (o_rowpress_bank),
        .o_rowpress_row      (o_rowpress_row),
        .o_rowpress_alert_cnt(o_rowpress_alert_cnt),
        .o_tras_clamped_alert(o_tras_clamped_alert),
        .o_tras_clamped_cnt  (o_tras_clamped_cnt),

        .i_dram_abo_alert    (i_dram_abo_alert),
        .o_abo_active        (o_abo_active),
        .o_abo_alert_cnt     (o_abo_alert_cnt),
        .o_abo_bg            (o_abo_bg),
        .o_abo_bank          (o_abo_bank),
        .o_abo_row           (o_abo_row),

        .cfg_raammt_thresh   (cfg_raammt_thresh),
        .o_rfm_auto_cnt      (o_rfm_auto_cnt),
        .o_rfm_active        (o_rfm_active),
        .o_cnt_fault         (o_cnt_fault),
        .o_fault             (o_fault),

        .o_bg_ready          (o_bg_ready),
        .o_engine_ready      (o_engine_ready),
        .o_bank_free         (o_bank_free),
        .o_engine_mit_only   (o_engine_mit_only),
        .o_slack_cycle       (o_slack_cycle),
        .o_decoy_active      (),
        .o_decoy_cnt         (),

        .o_dfi_cmd           (o_dfi_cmd),
        .o_dfi_bg            (o_dfi_bg),
        .o_dfi_bank          (o_dfi_bank),
        .o_dfi_row           (o_dfi_row),
        .o_dfi_col           (o_dfi_col),
        .o_dfi_len           (o_dfi_len),
        .o_dfi_tag           (o_dfi_tag),
        .i_dfi_rddata_valid  (dfi_rddata_valid),
        .i_dfi_rddata        (dfi_rddata),

        .o_wb_valid          (o_wb_valid),
        .o_wb_tag            (o_wb_tag),
        .o_wb_data           (o_wb_data),
        .o_wb_resp           (o_wb_resp),
        .o_wb_last           (o_wb_last)
    );

    dram_model #(.COL_W(COL_WIDTH), .RL(9), .WL(9)) u_dram (
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

    int tests_run = 0;
    int tests_passed = 0;
    int tests_failed = 0;
    `include "tb_check.svh"

    int rfm_cmd_seen = 0;

    dfi_jedec_checker #(.TCK_PS(2500)) u_jchk (
        .clk  (clk),
        .rst_n(rst_n),
        .cmd  (o_dfi_cmd),
        .bg   (o_dfi_bg),
        .bank (o_dfi_bank),
        .row  (o_dfi_row),
        .len  (o_dfi_len)
    );

    always @(posedge clk) begin
        if (rst_n && o_dfi_cmd == CMD_RFM) begin
            rfm_cmd_seen <= 1;
            $display("[PASS] Autonomous RFMab command emitted at time %0t", $time);
        end
    end

    initial begin
        rst_n               = 0;
        i_cmd_valid         = 0;
        i_cmd_is_write      = 0;
        i_cmd_id            = 0;
        i_cmd_bg            = 0;
        i_cmd_bank          = 0;
        i_cmd_row           = 0;
        i_cmd_col           = 0;
        i_cmd_len           = 0;
        i_cmd_tag           = 0;
        i_cmd_is_mitigation = 0;
        i_dram_abo_alert    = 0;
        cfg_raammt_thresh   = 8'd4;

        #(ClkPeriod * 4);
        rst_n = 1;
        #(ClkPeriod * 2);

        $display("[TB_MCSEE] Testing Autonomous JEDEC DDR5 RFM Generation...");

        // Phát 4 lệnh đọc row-conflict tới BG 1, Bank 0, tôn trọng hợp đồng I-T1 (chờ o_bank_free[{1,0}])
        for (int i = 0; i < 4; i++) begin
            int w;
            w = 0;
            while ((!o_bank_free[{3'd1, 2'd0}] || o_engine_mit_only) && w < 500) begin
                @(posedge clk);
                w++;
            end
            @(negedge clk);
            i_cmd_valid    = 1;
            i_cmd_is_write = 0;
            i_cmd_bg       = 3'd1;
            i_cmd_bank     = 2'd0;
            i_cmd_row      = 17'(100 + i * 10);
            i_cmd_col      = 10'h10;
            i_cmd_tag      = 5'(i);

            @(posedge clk);
            @(negedge clk);
            i_cmd_valid = 0;
        end

        // Chờ có cận K_RFM cho RFMab tự động phát ra
        for (int c = 0; c < 400 && !rfm_cmd_seen; c++) begin
            @(posedge clk);
        end
        repeat (20) @(posedge clk);

        tests_run++;
        if (rfm_cmd_seen && o_rfm_auto_cnt >= 16'd1) begin
            $display("[PASS] McSee Autonomous RFM confirmed! o_rfm_auto_cnt = %0d", o_rfm_auto_cnt);
            tests_passed++;
        end else begin
            $display("[FAIL] Autonomous RFM failed to emit! seen=%0d, cnt=%0d", rfm_cmd_seen, o_rfm_auto_cnt);
            tests_failed++;
        end

        #(ClkPeriod * 4);
        $display("================================================================");
        $display("[TB_MCSEE] SUMMARY: %0d/%0d TESTS PASSED, %0d FAILED",
                 tests_passed, tests_run, tests_failed);
        $display("================================================================");

        u_jchk.report("mcsee");
        tb_check(u_jchk.n_rfm > 0 && u_jchk.viol_ref_open == 0,
                 $sformatf("RFM uses its own RFMab opcode and is issued only with all banks precharged (%0d RFM, %0d REF/RFM-open)",
                           u_jchk.n_rfm, u_jchk.viol_ref_open));
        tb_check(u_jchk.timing_violations() == 0,
                 $sformatf("No JEDEC timing violation around RFM (%0d)", u_jchk.timing_violations()));
        tb_check(o_fault == 6'd0, $sformatf("No engine fault flags during clean run (o_fault=%b)", o_fault));
        tb_merge_legacy(tests_passed + tests_failed, tests_failed);
        tb_report();
        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED SUCCESSFULLY]");
            $finish;
        end else begin
            $fatal(1, "[TESTBENCH COMPLETED WITH FAILURES]");
        end
    end

endmodule: tb_mcsee_autonomous_rfm
