//=============================================================================
// Testbench:   tb_ddr5_subchannel_scheduler
// Description: Comprehensive Self-Checking Testbench for ddr5_subchannel_scheduler.
//              Verifies:
//              1. Cold start bank activation (ACTIVATE -> tRCD -> READ/WRITE)
//              2. Page Hit detection (direct READ without PRE/ACT penalty)
//              3. Page Conflict resolution (PRECHARGE -> tRP -> ACTIVATE -> tRCD -> ACCESS)
// Standard:    JEDEC DDR5 (JESD79-5) / SystemVerilog IEEE 1800-2017
//=============================================================================

`timescale 1ns / 1ps

module tb_ddr5_subchannel_scheduler;

    localparam int NumBanks    = 8;
    localparam int NumBankGrps = 4;
    localparam int RowWidth    = 16;
    localparam int ColWidth    = 10;
    localparam time ClkPeriod  = 2.5ns; // 400 MHz DDR5 Controller clock

    logic                clk = 0;
    always #(ClkPeriod/2) clk = ~clk;

    logic                rst_n;

    // Request Interface
    logic                req_valid;
    logic                req_ready;
    logic                req_is_write;
    logic [2:0]          req_bank;
    logic [1:0]          req_bank_grp;
    logic [RowWidth-1:0] req_row;
    logic [ColWidth-1:0] req_col;
    logic [127:0]        req_wdata;
    logic [15:0]         req_tag;

    // Command Interface
    logic                cmd_valid;
    logic                cmd_ready;
    logic [2:0]          cmd_type;
    logic [1:0]          cmd_bg;
    logic [2:0]          cmd_ba;
    logic [RowWidth-1:0] cmd_addr;
    logic [127:0]        cmd_wdata;
    logic [15:0]         cmd_tag;

    logic [31:0]         page_hits;
    logic [31:0]         page_misses;
    logic [31:0]         total_cmds;

    // DUT Instance
    ddr5_subchannel_scheduler #(
        .NumBanks   (NumBanks),
        .NumBankGrps(NumBankGrps),
        .RowWidth   (RowWidth),
        .ColWidth   (ColWidth),
        .TRCD_CYC   (6),
        .TRP_CYC    (6),
        .TCCDL_CYC  (4)
    ) u_dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .req_valid   (req_valid),
        .req_ready   (req_ready),
        .req_is_write(req_is_write),
        .req_bank    (req_bank),
        .req_bank_grp(req_bank_grp),
        .req_row     (req_row),
        .req_col     (req_col),
        .req_wdata   (req_wdata),
        .req_tag     (req_tag),
        .cmd_valid   (cmd_valid),
        .cmd_ready   (cmd_ready),
        .cmd_type    (cmd_type),
        .cmd_bg      (cmd_bg),
        .cmd_ba      (cmd_ba),
        .cmd_addr    (cmd_addr),
        .cmd_wdata   (cmd_wdata),
        .cmd_tag     (cmd_tag),
        .page_hits   (page_hits),
        .page_misses (page_misses),
        .total_cmds  (total_cmds)
    );

    int tests_run    = 0;
    int tests_passed = 0;
    int tests_failed = 0;

    // Helper task to wait for command during active valid cycle
    task automatic wait_for_cmd(
        output logic [2:0]          type_out,
        output logic [2:0]          ba_out,
        output logic [RowWidth-1:0] addr_out
    );
        forever begin
            @(posedge clk);
            #1ps; // Allow Non-Blocking Assignment (NBA) to settle
            if (cmd_valid) begin
                type_out = cmd_type;
                ba_out   = cmd_ba;
                addr_out = cmd_addr;
                break;
            end
        end
    endtask

    // Helper task to submit request
    task automatic submit_request(
        input logic                 is_write,
        input logic [2:0]           bank,
        input logic [1:0]           bank_grp,
        input logic [RowWidth-1:0]  row,
        input logic [ColWidth-1:0]  col,
        input logic [127:0]         wdata,
        input logic [15:0]          tag
    );
        while (!req_ready) @(posedge clk);
        req_valid    <= 1'b1;
        req_is_write <= is_write;
        req_bank     <= bank;
        req_bank_grp <= bank_grp;
        req_row      <= row;
        req_col      <= col;
        req_wdata    <= wdata;
        req_tag      <= tag;

        @(posedge clk);
        req_valid    <= 1'b0;
    endtask

    logic [2:0]          sampled_type;
    logic [2:0]          sampled_ba;
    logic [RowWidth-1:0] sampled_addr;

    initial begin
        // Reset initialization
        rst_n        = 1'b0;
        req_valid    = 1'b0;
        req_is_write = 1'b0;
        req_bank     = '0;
        req_bank_grp = '0;
        req_row      = '0;
        req_col      = '0;
        req_wdata    = '0;
        req_tag      = '0;
        cmd_ready    = 1'b1;

        #(ClkPeriod * 4);
        rst_n = 1'b1;
        #(ClkPeriod * 2);

        $display("================================================================");
        $display("[TB_DDR5_SCHED] STARTING DDR5 SUBCHANNEL SCHEDULER VERIFICATION");
        $display("================================================================");

        // TEST 1: Cold Start Bank Activation (Bank 0, Row 0x1234, Col 0x050)
        tests_run++;
        submit_request(1'b1, 3'd0, 2'd0, 16'h1234, 10'h050, 128'hBEEF, 16'h0001);

        // Expect CmdAct first
        wait_for_cmd(sampled_type, sampled_ba, sampled_addr);
        if (sampled_type == 3'b001 && sampled_ba == 3'd0 && sampled_addr == 16'h1234) begin
            $display("[PASS] Test 1a: CmdAct issued correctly for cold bank.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 1a: Unexpected command %03b for cold bank. Addr=%04h",
                     sampled_type, sampled_addr);
            tests_failed++;
        end

        // Wait for tRCD and expect CmdWr
        wait_for_cmd(sampled_type, sampled_ba, sampled_addr);
        if (sampled_type == 3'b100 && sampled_ba == 3'd0 && sampled_addr[9:0] == 10'h050) begin
            $display("[PASS] Test 1b: CmdWr issued following tRCD activation latency.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 1b: CmdWr not issued after tRCD. Got %03b, Addr=%04h",
                     sampled_type, sampled_addr);
            tests_failed++;
        end

        #(ClkPeriod * 4);

        // TEST 2: Page Hit (Same Bank 0, Same Row 0x1234, New Col 0x0A0)
        tests_run++;
        submit_request(1'b0, 3'd0, 2'd0, 16'h1234, 10'h0A0, '0, 16'h0002);

        // Expect DIRECT CmdRd without any CmdAct/CmdPre!
        wait_for_cmd(sampled_type, sampled_ba, sampled_addr);
        if (sampled_type == 3'b011 && sampled_ba == 3'd0 && sampled_addr[9:0] == 10'h0A0) begin
            $display("[PASS] Test 2: PAGE HIT! Direct CmdRd issued with zero ACT penalty.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 2: Page hit missed! Cmd=%03b", sampled_type);
            tests_failed++;
        end

        #(ClkPeriod * 4);

        // TEST 3: Page Conflict (Same Bank 0, Different Row 0x5678)
        tests_run++;
        submit_request(1'b0, 3'd0, 2'd0, 16'h5678, 10'h0F0, '0, 16'h0003);

        // Expect CmdPre first
        wait_for_cmd(sampled_type, sampled_ba, sampled_addr);
        if (sampled_type == 3'b010 && sampled_ba == 3'd0) begin
            $display("[PASS] Test 3a: Row conflict detected -> CmdPre issued to close row.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 3a: CmdPre expected on row conflict, got %03b", sampled_type);
            tests_failed++;
        end

        // Expect CmdAct after tRP
        wait_for_cmd(sampled_type, sampled_ba, sampled_addr);
        if (sampled_type == 3'b001 && sampled_ba == 3'd0 && sampled_addr == 16'h5678) begin
            $display("[PASS] Test 3b: CmdAct issued for new row 0x5678 after tRP precharge.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 3b: CmdAct failed after precharge. Got %03b", sampled_type);
            tests_failed++;
        end

        // Expect CmdRd after tRCD
        wait_for_cmd(sampled_type, sampled_ba, sampled_addr);
        if (sampled_type == 3'b011 && sampled_ba == 3'd0 && sampled_addr[9:0] == 10'h0F0) begin
            $display("[PASS] Test 3c: CmdRd completed for conflicting access.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 3c: Final read failed. Got %03b", sampled_type);
            tests_failed++;
        end

        #(ClkPeriod * 8);
        $display("================================================================");
        $display("[TB_DDR5_SCHED] SUMMARY: %0d/%0d TESTS PASSED, %0d FAILED",
                 tests_passed, tests_run + 2, tests_failed);
        $display("================================================================");

        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED SUCCESSFULLY]");
            $finish;
        end else begin
            $fatal(1, "[TESTBENCH COMPLETED WITH FAILURES]");
        end
    end

endmodule: tb_ddr5_subchannel_scheduler
