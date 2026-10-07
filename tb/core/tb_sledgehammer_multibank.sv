// File: tb_sledgehammer_multibank.sv
// Chức năng: Kiểm chứng cơ chế phát hiện và điều tiết tấn công SledgeHammer đa bank đồng thời.

`timescale 1ns / 1ps

module tb_sledgehammer_multibank;

    localparam int AXI_ID_WIDTH   = 4;
    localparam int AXI_QOS_WIDTH  = 4;
    localparam int ROW_WIDTH      = 17;
    localparam int COL_WIDTH      = 10;
    localparam int BG_WIDTH       = 3;
    localparam int BANK_WIDTH     = 2;
    localparam int BANK_COUNT     = 1 << BANK_WIDTH;
    localparam int TABLE_ENTRIES  = 256;
    localparam int COUNT_WIDTH    = 16;
    localparam time ClkPeriod     = 2.5ns;

    logic clk = 0;
    always #(ClkPeriod/2) clk = ~clk;

    logic                      rst_n;
    logic                      cfg_hash_mode;
    logic [COUNT_WIDTH-1:0]    cfg_sdc_thresh;
    logic [15:0]               cfg_window_size;
    logic [2:0]                cfg_multibank_thresh;

    logic                      i_cmd_valid;
    logic                      o_cmd_ready;
    logic [AXI_ID_WIDTH-1:0]   i_cmd_id;
    logic                      i_cmd_is_write;
    logic [BG_WIDTH-1:0]       i_cmd_bg;
    logic [BANK_WIDTH-1:0]     i_cmd_bank;
    logic [ROW_WIDTH-1:0]      i_cmd_row;
    logic [COL_WIDTH-1:0]      i_cmd_col;
    logic [7:0]                i_cmd_len;
    logic [AXI_QOS_WIDTH-1:0]  i_cmd_qos;

    logic                      o_cmd_valid;
    logic                      i_cmd_ready;
    logic [AXI_ID_WIDTH-1:0]   o_cmd_id;
    logic                      o_cmd_is_write;
    logic [BG_WIDTH-1:0]       o_cmd_bg;
    logic [BANK_WIDTH-1:0]     o_cmd_bank;
    logic [ROW_WIDTH-1:0]      o_cmd_row;
    logic [COL_WIDTH-1:0]      o_cmd_col;
    logic [7:0]                o_cmd_len;
    logic [AXI_QOS_WIDTH-1:0]  o_cmd_qos;
    logic                      o_cmd_throttled;

    logic                      o_mitigation_req;
    logic [BG_WIDTH-1:0]       o_mitigation_bg;
    logic [BANK_WIDTH-1:0]     o_mitigation_bank;
    logic [ROW_WIDTH-1:0]      o_mitigation_row;
    logic                      o_sdc_alert;
    logic                      o_coordinated_throttle_active;
    logic [BANK_COUNT-1:0]     o_bank_throttled_flags;
    logic [15:0]               o_coordinated_throttle_cnt;
    logic [31:0]               o_telemetry_accesses;
    logic [31:0]               o_telemetry_throttles;

    sdc_resilient_filter #(
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_QOS_WIDTH (AXI_QOS_WIDTH),
        .ROW_WIDTH     (ROW_WIDTH),
        .COL_WIDTH     (COL_WIDTH),
        .BG_WIDTH      (BG_WIDTH),
        .BANK_WIDTH    (BANK_WIDTH),
        .TABLE_ENTRIES (TABLE_ENTRIES),
        .COUNT_WIDTH   (COUNT_WIDTH)
    ) u_filter (
        .clk                          (clk),
        .rst_n                        (rst_n),
        .cfg_hash_mode                (cfg_hash_mode),
        .cfg_sdc_thresh               (cfg_sdc_thresh),
        .cfg_window_size              (cfg_window_size),
        .cfg_multibank_thresh         (cfg_multibank_thresh),

        .i_cmd_valid                  (i_cmd_valid),
        .o_cmd_ready                  (o_cmd_ready),
        .i_cmd_id                     (i_cmd_id),
        .i_cmd_is_write               (i_cmd_is_write),
        .i_cmd_bg                     (i_cmd_bg),
        .i_cmd_bank                   (i_cmd_bank),
        .i_cmd_row                    (i_cmd_row),
        .i_cmd_col                    (i_cmd_col),
        .i_cmd_len                    (i_cmd_len),
        .i_cmd_qos                    (i_cmd_qos),

        .o_cmd_valid                  (o_cmd_valid),
        .i_cmd_ready                  (i_cmd_ready),
        .o_cmd_id                     (o_cmd_id),
        .o_cmd_is_write               (o_cmd_is_write),
        .o_cmd_bg                     (o_cmd_bg),
        .o_cmd_bank                   (o_cmd_bank),
        .o_cmd_row                    (o_cmd_row),
        .o_cmd_col                    (o_cmd_col),
        .o_cmd_len                    (o_cmd_len),
        .o_cmd_qos                    (o_cmd_qos),
        .o_cmd_throttled              (o_cmd_throttled),

        .o_mitigation_req             (o_mitigation_req),
        .o_mitigation_bg              (o_mitigation_bg),
        .o_mitigation_bank            (o_mitigation_bank),
        .o_mitigation_row             (o_mitigation_row),
        .o_sdc_alert                  (o_sdc_alert),
        .o_coordinated_throttle_active(o_coordinated_throttle_active),
        .o_bank_throttled_flags       (o_bank_throttled_flags),
        .o_coordinated_throttle_cnt   (o_coordinated_throttle_cnt),
        .o_telemetry_accesses         (o_telemetry_accesses),
        .o_telemetry_throttles        (o_telemetry_throttles)
    );

    int tests_run = 0;
    int tests_passed = 0;
    int tests_failed = 0;

    task automatic send_cmd(
        input logic [BG_WIDTH-1:0]   bg,
        input logic [BANK_WIDTH-1:0] bk,
        input logic [ROW_WIDTH-1:0]  row
    );
        @(negedge clk);
        i_cmd_valid    = 1;
        i_cmd_is_write = 0;
        i_cmd_id       = 4'd1;
        i_cmd_bg       = bg;
        i_cmd_bank     = bk;
        i_cmd_row      = row;
        i_cmd_col      = 10'h00;
        i_cmd_len      = 8'd0;
        i_cmd_qos      = 4'd2;

        @(posedge clk);
        while (!o_cmd_ready) @(posedge clk);
        #1;
        @(negedge clk);
        i_cmd_valid = 0;
        @(posedge clk);
    endtask

    initial begin
        rst_n                = 0;
        cfg_hash_mode        = 1'b1;   // Dual-hash mode
        cfg_sdc_thresh       = 16'd3;  // Throttle bank when row hit >= 3
        cfg_window_size      = 16'd1000;
        cfg_multibank_thresh = 3'd2;   // Coordinated throttle triggers when > 2 banks are throttled
        i_cmd_valid          = 0;
        i_cmd_ready          = 1;

        #(ClkPeriod * 4);
        rst_n = 1;
        #(ClkPeriod * 2);

        $display("[TB_SLEDGEHAMMER] Hammering Bank 0 (Row 0x100) 4 times...");
        for (int i = 0; i < 4; i++) send_cmd(3'd0, 2'd0, 17'h100);

        $display("[TB_SLEDGEHAMMER] Hammering Bank 1 (Row 0x200) 4 times...");
        for (int i = 0; i < 4; i++) send_cmd(3'd0, 2'd1, 17'h200);

        tests_run++;
        if (o_bank_throttled_flags[0] && o_bank_throttled_flags[1] && !o_coordinated_throttle_active) begin
            $display("[PASS] 2 banks throttled, coordinated throttle not yet triggered ($countones=%0d)",
                     $countones(o_bank_throttled_flags));
            tests_passed++;
        end else begin
            $display("[FAIL] Unexpected state after 2 banks: flags=%b, active=%b",
                     o_bank_throttled_flags, o_coordinated_throttle_active);
            tests_failed++;
        end

        $display("[TB_SLEDGEHAMMER] Hammering Bank 2 (Row 0x300) 4 times (Crosses threshold > 2)...");
        for (int i = 0; i < 4; i++) send_cmd(3'd0, 2'd2, 17'h300);

        repeat (2) @(posedge clk);

        tests_run++;
        if (o_coordinated_throttle_active && (o_coordinated_throttle_cnt >= 16'd1) &&
            o_bank_throttled_flags[0] && o_bank_throttled_flags[1] && o_bank_throttled_flags[2]) begin
            $display("[PASS] SledgeHammer Coordinated Multi-Bank Throttle confirmed! flags=%b, cnt=%0d",
                     o_bank_throttled_flags, o_coordinated_throttle_cnt);
            tests_passed++;
        end else begin
            $display("[FAIL] Coordinated throttle failed! flags=%b, active=%b, cnt=%0d",
                     o_bank_throttled_flags, o_coordinated_throttle_active, o_coordinated_throttle_cnt);
            tests_failed++;
        end

        #(ClkPeriod * 4);
        $display("================================================================");
        $display("[TB_SLEDGEHAMMER] SUMMARY: %0d/%0d TESTS PASSED, %0d FAILED",
                 tests_passed, tests_run, tests_failed);
        $display("================================================================");

        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED SUCCESSFULLY]");
            $finish;
        end else begin
            $fatal(1, "[TESTBENCH COMPLETED WITH FAILURES]");
        end
    end

endmodule: tb_sledgehammer_multibank
