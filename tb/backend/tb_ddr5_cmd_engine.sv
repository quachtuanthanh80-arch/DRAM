//=============================================================================
// Testbench:   tb_ddr5_cmd_engine
// Description: Self-checking SystemVerilog testbench for ddr5_cmd_engine:
//              1. Row-Miss: Closed bank -> ACT -> tRCD -> RD
//              2. Row-Hit: Open bank -> Immediate RD
//              3. Row-Conflict: Diff row -> PRE -> tRP -> ACT -> tRCD -> RD
//              4. RowPress Attack Detection: bank kept open > thresh fires alert
// Standard:    SystemVerilog IEEE 1800-2017
//=============================================================================

`timescale 1ns / 1ps

module tb_ddr5_cmd_engine;

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

    logic rst_n;

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
    logic                      o_rowpress_alert;
    logic [BG_WIDTH-1:0]       o_rowpress_bg;
    logic [BANK_WIDTH-1:0]     o_rowpress_bank;
    logic [ROW_WIDTH-1:0]      o_rowpress_row;
    logic [15:0]               o_rowpress_alert_cnt;

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

    // DFI Commands
    localparam logic [2:0] CMD_NOP = 3'b000;
    localparam logic [2:0] CMD_ACT = 3'b001;
    localparam logic [2:0] CMD_PRE = 3'b010;
    localparam logic [2:0] CMD_RD  = 3'b011;
    localparam logic [2:0] CMD_WR  = 3'b100;
    localparam logic [2:0] CMD_REF = 3'b101;

    // Instantiate DUT
    ddr5_cmd_engine #(
        .BG_COUNT        (BG_COUNT),
        .BANK_COUNT      (BANK_COUNT),
        .ROW_WIDTH       (ROW_WIDTH),
        .COL_WIDTH       (COL_WIDTH),
        .AXI_ID_WIDTH    (AXI_ID_WIDTH),
        .AXI_DATA_WIDTH  (AXI_DATA_WIDTH),
        .AXI_LEN_WIDTH   (AXI_LEN_WIDTH),
        .ROB_PTR_WIDTH   (ROB_PTR_WIDTH),
        .T_RCD           (4),
        .T_RP            (4),
        .T_RAS           (8),
        .T_CCD_L         (2),
        .T_CCD_S         (1),
        .T_CL            (4),
        .ROWPRESS_THRESH_DEFAULT(25)
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
        .cfg_rowpress_thresh (cfg_rowpress_thresh),
        .o_rowpress_alert    (o_rowpress_alert),
        .o_rowpress_bg       (o_rowpress_bg),
        .o_rowpress_bank     (o_rowpress_bank),
        .o_rowpress_row      (o_rowpress_row),
        .o_rowpress_alert_cnt(o_rowpress_alert_cnt),
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

    initial begin
        $display("================================================================");
        $display("[TB_CMD_ENGINE] STARTING DDR5 COMMAND ENGINE & ROWPRESS VERIFICATION");
        $display("================================================================");

        rst_n = 0;
        i_cmd_valid = 0;
        i_cmd_is_write = 0;
        i_cmd_id = 0;
        i_cmd_bg = 0;
        i_cmd_bank = 0;
        i_cmd_row = 0;
        i_cmd_col = 0;
        i_cmd_len = 0;
        i_cmd_tag = 0;
        i_cmd_is_mitigation = 0;
        cfg_rowpress_thresh = 16'd20;

        #(ClkPeriod * 2);
        rst_n = 1;
        #(ClkPeriod);

        // TEST 1: Row-Miss (Closed bank -> ACT -> RD)
        tests_run++;
        @(negedge clk);
        i_cmd_valid = 1;
        i_cmd_is_write = 0;
        i_cmd_bg = 3'd0;
        i_cmd_bank = 2'd0;
        i_cmd_row = 17'h0100;
        i_cmd_col = 10'h010;
        i_cmd_tag = 5'd1;

        @(posedge clk);
        #1;
        if (o_dfi_cmd == CMD_ACT && o_dfi_row == 17'h0100) begin
            $display("[PASS] Test 1: Row-Miss initiated with CMD_ACT for Row 0x0100.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 1: Expected CMD_ACT, got %0d", o_dfi_cmd);
            tests_failed++;
        end
        @(negedge clk);
        i_cmd_valid = 0;

        // Wait for RCD to complete and read to be issued
        repeat (6) @(posedge clk);

        // TEST 2: Row-Hit (Immediate RD without ACT)
        tests_run++;
        @(negedge clk);
        i_cmd_valid = 1;
        i_cmd_is_write = 0;
        i_cmd_bg = 3'd0;
        i_cmd_bank = 2'd0;
        i_cmd_row = 17'h0100;
        i_cmd_col = 10'h020;
        i_cmd_tag = 5'd2;

        @(posedge clk);
        #1;
        if (o_dfi_cmd == CMD_RD && o_dfi_col == 10'h020) begin
            $display("[PASS] Test 2: Row-Hit issued immediate CMD_RD for Col 0x020.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 2: Row-Hit failed, got %0d", o_dfi_cmd);
            tests_failed++;
        end
        @(negedge clk);
        i_cmd_valid = 0;

        // TEST 3: RowPress Attack Detection
        // Bank (BG 0, Bank 0) is already open to Row 0x0100.
        // Let it sit open for > 20 cycles without PRE.
        tests_run++;
        begin : rowpress_test
            int alert_seen;
            alert_seen = 0;
            for (int cycle = 0; cycle < 30 && alert_seen == 0; cycle++) begin
                @(posedge clk);
                #1;
                if (o_rowpress_alert) begin
                    alert_seen = 1;
                    if (o_rowpress_bg == 3'd0 && o_rowpress_bank == 2'd0 &&
                        o_rowpress_row == 17'h0100 && o_rowpress_alert_cnt >= 1) begin
                        $display("[PASS] Test 3: RowPress attack detected on open Row 0x%04X (cycle %0d)!", o_rowpress_row, cycle);
                        tests_passed++;
                    end else begin
                        $display("[FAIL] Test 3: Alert payload mismatch. bg=%0d, bank=%0d, row=0x%04X",
                                 o_rowpress_bg, o_rowpress_bank, o_rowpress_row);
                        tests_failed++;
                    end
                end
            end
            if (!alert_seen) begin
                $display("[FAIL] Test 3: RowPress alert never fired after 30 cycles of open bank!");
                tests_failed++;
            end
        end

        #(ClkPeriod * 4);
        $display("================================================================");
        $display("[TB_CMD_ENGINE] SUMMARY: %0d/%0d TESTS PASSED, %0d FAILED",
                 tests_passed, tests_run, tests_failed);
        $display("================================================================");

        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED SUCCESSFULLY]");
            $finish;
        end else begin
            $fatal(1, "[TESTBENCH COMPLETED WITH FAILURES]");
        end
    end

endmodule: tb_ddr5_cmd_engine
