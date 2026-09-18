//=============================================================================
// Testbench:   tb_slack_aware_arbiter
// Description: Self-checking SystemVerilog testbench for slack_aware_arbiter:
//              1. Starved emergency boost over normal QoS
//              2. Bank Group readiness gating
//              3. Opportunistic slack cycle mitigation grant
//              4. Write-Drain / Read-Burst mode switching and write burst priority
// Standard:    SystemVerilog IEEE 1800-2017
//=============================================================================

`timescale 1ns / 1ps

module tb_slack_aware_arbiter;

    localparam int BG_COUNT        = 8;
    localparam int BG_WIDTH        = $clog2(BG_COUNT);
    localparam int BANK_WIDTH      = 2;
    localparam int ROW_WIDTH       = 17;
    localparam int COL_WIDTH       = 10;
    localparam int AXI_ID_WIDTH    = 4;
    localparam int AXI_LEN_WIDTH   = 8;
    localparam int QUEUE_PTR_WIDTH = 3;
    localparam time ClkPeriod      = 2.5ns; // 400 MHz

    logic clk = 0;
    always #(ClkPeriod/2) clk = ~clk;

    logic rst_n;

    logic [BG_COUNT-1:0]                 i_cand_valid;
    logic [BG_COUNT*AXI_ID_WIDTH-1:0]    i_cand_id;
    logic [BG_COUNT-1:0]                 i_cand_is_write;
    logic [BG_COUNT*BANK_WIDTH-1:0]      i_cand_bank;
    logic [BG_COUNT*ROW_WIDTH-1:0]       i_cand_row;
    logic [BG_COUNT*COL_WIDTH-1:0]       i_cand_col;
    logic [BG_COUNT*AXI_LEN_WIDTH-1:0]   i_cand_len;
    logic [BG_COUNT*4-1:0]               i_cand_qos;
    logic [BG_COUNT-1:0]                 i_cand_throttled;
    logic [BG_COUNT-1:0]                 i_cand_starved;
    logic [BG_COUNT*QUEUE_PTR_WIDTH-1:0] i_cand_queue_idx;

    logic [BG_COUNT-1:0]                 i_bg_ready;
    logic                                i_engine_ready;
    logic                                i_slack_cycle;

    logic                                i_mitigation_req;
    logic [BG_WIDTH-1:0]                 i_mitigation_bg;
    logic [BANK_WIDTH-1:0]               i_mitigation_bank;
    logic [ROW_WIDTH-1:0]                i_mitigation_row;
    logic                                o_mitigation_grant;

    logic                                o_issue_grant_valid;
    logic [BG_WIDTH-1:0]                 o_issue_grant_bg;
    logic [QUEUE_PTR_WIDTH-1:0]          o_issue_grant_idx;

    logic                                o_cmd_valid;
    logic                                o_cmd_is_write;
    logic [AXI_ID_WIDTH-1:0]             o_cmd_id;
    logic [BG_WIDTH-1:0]                 o_cmd_bg;
    logic [BANK_WIDTH-1:0]               o_cmd_bank;
    logic [ROW_WIDTH-1:0]                o_cmd_row;
    logic [COL_WIDTH-1:0]                o_cmd_col;
    logic [AXI_LEN_WIDTH-1:0]            o_cmd_len;
    logic                                o_cmd_is_mitigation;
    logic                                o_drain_mode;

    // Instantiate DUT
    slack_aware_arbiter #(
        .BG_COUNT        (BG_COUNT),
        .BANK_WIDTH      (BANK_WIDTH),
        .ROW_WIDTH       (ROW_WIDTH),
        .COL_WIDTH       (COL_WIDTH),
        .AXI_ID_WIDTH    (AXI_ID_WIDTH),
        .AXI_LEN_WIDTH   (AXI_LEN_WIDTH),
        .QUEUE_PTR_WIDTH (QUEUE_PTR_WIDTH),
        .DRAIN_HIGH_THRESH(4),
        .DRAIN_LOW_THRESH (0)
    ) u_dut (
        .clk                 (clk),
        .rst_n               (rst_n),
        .i_cand_valid        (i_cand_valid),
        .i_cand_id           (i_cand_id),
        .i_cand_is_write     (i_cand_is_write),
        .i_cand_bank         (i_cand_bank),
        .i_cand_row          (i_cand_row),
        .i_cand_col          (i_cand_col),
        .i_cand_len          (i_cand_len),
        .i_cand_qos          (i_cand_qos),
        .i_cand_throttled    (i_cand_throttled),
        .i_cand_starved      (i_cand_starved),
        .i_cand_queue_idx    (i_cand_queue_idx),
        .i_bg_ready          (i_bg_ready),
        .i_engine_ready      (i_engine_ready),
        .i_slack_cycle       (i_slack_cycle),
        .i_mitigation_req    (i_mitigation_req),
        .i_mitigation_bg     (i_mitigation_bg),
        .i_mitigation_bank   (i_mitigation_bank),
        .i_mitigation_row    (i_mitigation_row),
        .o_mitigation_grant  (o_mitigation_grant),
        .o_issue_grant_valid (o_issue_grant_valid),
        .o_issue_grant_bg    (o_issue_grant_bg),
        .o_issue_grant_idx   (o_issue_grant_idx),
        .o_cmd_valid         (o_cmd_valid),
        .o_cmd_is_write      (o_cmd_is_write),
        .o_cmd_id            (o_cmd_id),
        .o_cmd_bg            (o_cmd_bg),
        .o_cmd_bank          (o_cmd_bank),
        .o_cmd_row           (o_cmd_row),
        .o_cmd_col           (o_cmd_col),
        .o_cmd_len           (o_cmd_len),
        .o_cmd_is_mitigation (o_cmd_is_mitigation),
        .o_drain_mode        (o_drain_mode)
    );

    int tests_run = 0;
    int tests_passed = 0;
    int tests_failed = 0;

    initial begin
        $display("================================================================");
        $display("[TB_SLACK_ARBITER] STARTING SLACK-AWARE ARBITER & WRITE-DRAIN VERIFICATION");
        $display("================================================================");

        // Reset
        rst_n = 0;
        i_cand_valid = '0;
        i_cand_id = '0;
        i_cand_is_write = '0;
        i_cand_bank = '0;
        i_cand_row = '0;
        i_cand_col = '0;
        i_cand_len = '0;
        i_cand_qos = '0;
        i_cand_throttled = '0;
        i_cand_starved = '0;
        i_cand_queue_idx = '0;
        i_bg_ready = 8'hFF;
        i_engine_ready = 1'b1;
        i_slack_cycle = 1'b0;
        i_mitigation_req = 1'b0;
        i_mitigation_bg = '0;
        i_mitigation_bank = '0;
        i_mitigation_row = '0;

        #(ClkPeriod * 2);
        rst_n = 1;
        #(ClkPeriod);

        // TEST 1: Starved emergency priority boost
        tests_run++;
        i_cand_valid = (8'b1 << 0) | (8'b1 << 1);
        i_cand_starved = (8'b1 << 0);
        i_cand_qos = (4'd1 << 0) | (4'd15 << 4);
        i_cand_id = (4'd5 << 0) | (4'd10 << 4);
        #1;
        if (o_cmd_valid && o_cmd_bg == 0 && o_cmd_id == 4'd5) begin
            $display("[PASS] Test 1: Starved BG 0 boosted ahead of higher QoS BG 1.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 1: Starved boost failed.");
            tests_failed++;
        end

        // TEST 2: Bank Group readiness gating
        tests_run++;
        i_cand_starved = '0;
        i_cand_valid = (8'b1 << 2) | (8'b1 << 3);
        i_cand_qos = (4'd15 << (2*4)) | (4'd8 << (3*4));
        i_cand_id = (4'd2 << (2*4)) | (4'd3 << (3*4));
        i_bg_ready = 8'hFF ^ (8'b1 << 2); // BG2 not ready
        #1;
        if (o_cmd_valid && o_cmd_bg == 3 && o_cmd_id == 4'd3) begin
            $display("[PASS] Test 2: Unready BG 2 gated out, ready BG 3 selected.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 2: Readiness gating failed.");
            tests_failed++;
        end

        // TEST 3: Opportunistic slack cycle mitigation grant
        tests_run++;
        i_cand_valid = '0;
        i_bg_ready = 8'hFF;
        i_slack_cycle = 1'b1;
        i_mitigation_req = 1'b1;
        i_mitigation_bg = 3'd4;
        i_mitigation_bank = 2'd1;
        i_mitigation_row = 17'h0123;
        #1;
        if (o_mitigation_grant && o_cmd_valid && o_cmd_is_mitigation && o_cmd_bg == 4 && o_cmd_row == 17'h0123) begin
            $display("[PASS] Test 3: Opportunistic slack mitigation grant verified.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 3: Mitigation grant failed.");
            tests_failed++;
        end

        // TEST 4: Write-Drain Mode Activation & Directional Prioritization
        tests_run++;
        i_slack_cycle = 1'b0;
        i_mitigation_req = 1'b0;

        // BG0 = Read (QoS = 15)
        // BG1..BG4 = Writes (QoS = 2 each) => 4 writes >= DRAIN_HIGH_THRESH (4)
        i_cand_valid = 8'b0001_1111;
        i_cand_is_write = 8'b0001_1110;
        i_cand_qos = (4'd15 << 0) | (4'd2 << 4) | (4'd2 << 8) | (4'd2 << 12) | (4'd2 << 16);

        @(posedge clk);
        #1;
        if (o_drain_mode == 1'b1 && o_cmd_valid && o_cmd_is_write == 1'b1) begin
            $display("[PASS] Test 4: Write-Drain mode activated (drain_mode=1) and write burst prioritized.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 4: Write-Drain mode failed. drain_mode=%0d, is_write=%0d", o_drain_mode, o_cmd_is_write);
            tests_failed++;
        end

        // TEST 5: Write-Drain Mode Exit on Drain Completion
        tests_run++;
        // Remove all writes, only read on BG0 remains
        i_cand_valid = 8'b0000_0001;
        i_cand_is_write = 8'b0000_0000;

        @(posedge clk);
        #1;
        if (o_drain_mode == 1'b0 && o_cmd_valid && o_cmd_is_write == 1'b0) begin
            $display("[PASS] Test 5: Write-Drain mode successfully returned to Read-Burst mode.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 5: Write-Drain exit failed. drain_mode=%0d, is_write=%0d", o_drain_mode, o_cmd_is_write);
            tests_failed++;
        end

        #(ClkPeriod * 4);
        $display("================================================================");
        $display("[TB_SLACK_ARBITER] SUMMARY: %0d/%0d TESTS PASSED, %0d FAILED",
                 tests_passed, tests_run, tests_failed);
        $display("================================================================");

        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED SUCCESSFULLY]");
            $finish;
        end else begin
            $fatal(1, "[TESTBENCH COMPLETED WITH FAILURES]");
        end
    end

endmodule: tb_slack_aware_arbiter
