// File: tb_mcsee_autonomous_rfm.sv
// Chức năng: Kiểm chứng cơ chế tự phát lệnh RFM JEDEC DDR5 khi CPU không gửi lệnh (McSee USENIX'25 defense).

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

    logic [15:0]               cfg_rowpress_thresh;
    logic [1:0]                cfg_rowpress_curve;
    logic [15:0]               cfg_tras_max_thresh;
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

    logic [BG_COUNT-1:0]       o_bg_ready;
    logic                      o_engine_ready;
    logic                      o_slack_cycle;

    logic [2:0]                o_dfi_cmd;
    logic [BG_WIDTH-1:0]       o_dfi_bg;
    logic [BANK_WIDTH-1:0]     o_dfi_bank;
    logic [ROW_WIDTH-1:0]      o_dfi_row;
    logic [COL_WIDTH-1:0]      o_dfi_col;

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

    ddr5_cmd_engine #(
        .BG_COUNT        (BG_COUNT),
        .BANK_COUNT      (BANK_COUNT),
        .ROW_WIDTH       (ROW_WIDTH),
        .COL_WIDTH       (COL_WIDTH),
        .AXI_ID_WIDTH    (AXI_ID_WIDTH),
        .AXI_DATA_WIDTH  (AXI_DATA_WIDTH),
        .AXI_LEN_WIDTH   (AXI_LEN_WIDTH),
        .ROB_PTR_WIDTH   (ROB_PTR_WIDTH),
        .T_RCD           (2),
        .T_RP            (2),
        .T_RAS           (4),
        .T_CCD_L         (2),
        .T_CCD_S         (1),
        .T_CL            (2)
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
        .cfg_tras_max_thresh (16'd28000),
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

        .o_bg_ready          (o_bg_ready),
        .o_engine_ready      (o_engine_ready),
        .o_slack_cycle       (o_slack_cycle),

        .o_dfi_cmd           (o_dfi_cmd),
        .o_dfi_bg            (o_dfi_bg),
        .o_dfi_bank          (o_dfi_bank),
        .o_dfi_row           (o_dfi_row),
        .o_dfi_col           (o_dfi_col),

        .o_wb_valid          (o_wb_valid),
        .o_wb_tag            (o_wb_tag),
        .o_wb_data           (o_wb_data),
        .o_wb_resp           (o_wb_resp),
        .o_wb_last           (o_wb_last)
    );

    int tests_run = 0;
    int tests_passed = 0;
    int tests_failed = 0;

    int rfm_cmd_seen = 0;
    always @(posedge clk) begin
        if (rst_n && o_dfi_cmd == CMD_REF && o_dfi_bg == 3'd1) begin
            rfm_cmd_seen <= 1;
            $display("[PASS] Autonomous RFM command CMD_REF emitted for BG 1 at time %0t", $time);
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
        cfg_raammt_thresh   = 8'd4; // Low threshold for fast simulation verification

        #(ClkPeriod * 4);
        rst_n = 1;
        #(ClkPeriod * 2);

        $display("[TB_MCSEE] Testing Autonomous JEDEC DDR5 RFM Generation...");

        // Issue 4 row-conflict accesses to Bank Group 1 to trigger 4 ACT commands
        for (int i = 0; i < 4; i++) begin
            @(negedge clk);
            i_cmd_valid    = 1;
            i_cmd_is_write = 0;
            i_cmd_bg       = 3'd1;
            i_cmd_bank     = 2'd0;
            i_cmd_row      = 17'(100 + i * 10);
            i_cmd_col      = 10'h10;
            i_cmd_tag      = 5'(i);

            @(posedge clk);
            #1;
            @(negedge clk);
            i_cmd_valid = 0;

            // Wait for command pipeline to finish (PRE -> ACT -> RD)
            repeat (8) @(posedge clk);
        end

        // Wait extra slack cycles to allow RFM if not already executed
        repeat (10) @(posedge clk);

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

        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED SUCCESSFULLY]");
            $finish;
        end else begin
            $fatal(1, "[TESTBENCH COMPLETED WITH FAILURES]");
        end
    end

endmodule: tb_mcsee_autonomous_rfm
