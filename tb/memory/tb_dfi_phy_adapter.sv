//=============================================================================
// Testbench:   tb_dfi_phy_adapter
// Description: Comprehensive Self-Checking Testbench for Industrial DFI 5.0 Adapter.
//              Verifies:
//              1. DFI 5.0 Reset and Initialization FSM Handshake (dfi_init_start/complete)
//              2. Inactive default state on DFI bus (all CS#/ACT#/RAS#/CAS#/WE# high)
//              3. ACTIVATE pin-level encoding (dfi_act_n = 0)
//              4. PRECHARGE pin-level encoding (RAS# = 0, WE# = 0)
//              5. WRITE data alignment and dfi_wrdata_en strobe
//              6. READ command and CasLatency pipelined tag matching
//              7. DFI 5.0 PHY Update & Calibration Interlock (dfi_phyupd_req/ack)
// Standard:    DFI 5.0 Specification / SystemVerilog IEEE 1800-2017
//=============================================================================

`timescale 1ns / 1ps

module tb_dfi_phy_adapter;

    localparam int AddrWidth  = 16;
    localparam int DataWidth  = 128;
    localparam int CasLatency = 14;
    localparam time ClkPeriod = 2.5ns; // 400 MHz

    logic                 clk = 0;
    always #(ClkPeriod/2) clk = ~clk;

    logic                 rst_n;

    // Command Interface
    logic                 cmd_valid;
    logic                 cmd_ready;
    logic [2:0]           cmd_type;
    logic [1:0]           cmd_bg;
    logic [2:0]           cmd_ba;
    logic [AddrWidth-1:0] cmd_addr;
    logic [DataWidth-1:0] cmd_wdata;
    logic [15:0]          cmd_tag;

    // Read Response
    logic                 rd_resp_valid;
    logic [DataWidth-1:0] rd_resp_data;
    logic [15:0]          rd_resp_tag;

    // DFI 5.0 Bus
    logic [AddrWidth-1:0] dfi_address;
    logic [2:0]           dfi_bank;
    logic [1:0]           dfi_bank_group;
    logic                 dfi_cs_n;
    logic                 dfi_act_n;
    logic                 dfi_ras_n;
    logic                 dfi_cas_n;
    logic                 dfi_we_n;
    logic                 dfi_wrdata_en;
    logic [DataWidth-1:0] dfi_wrdata;
    logic [15:0]          dfi_wrdata_mask;
    logic                 dfi_rddata_en;
    logic [DataWidth-1:0] dfi_rddata;
    logic                 dfi_rddata_valid;

    // DFI 5.0 Status, Calibration & Low-Power Handshakes
    logic                 dfi_reset_n;
    logic                 dfi_init_start;
    logic                 dfi_init_complete;
    logic                 phy_initialized;
    logic                 dfi_ctrlupd_req;
    logic                 dfi_ctrlupd_ack;
    logic                 dfi_phyupd_req;
    logic                 dfi_phyupd_ack;
    logic                 dfi_lp_req;
    logic                 dfi_lp_ack;
    logic [3:0]           dfi_lp_wakeup;

    // DUT Instance
    dfi_phy_adapter #(
        .AddrWidth (AddrWidth),
        .DataWidth (DataWidth),
        .CasLatency(CasLatency)
    ) u_dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .cmd_valid        (cmd_valid),
        .cmd_ready        (cmd_ready),
        .cmd_type         (cmd_type),
        .cmd_bg           (cmd_bg),
        .cmd_ba           (cmd_ba),
        .cmd_addr         (cmd_addr),
        .cmd_wdata        (cmd_wdata),
        .cmd_tag          (cmd_tag),
        .rd_resp_valid    (rd_resp_valid),
        .rd_resp_data     (rd_resp_data),
        .rd_resp_tag      (rd_resp_tag),
        .dfi_address      (dfi_address),
        .dfi_bank         (dfi_bank),
        .dfi_bank_group   (dfi_bank_group),
        .dfi_cs_n         (dfi_cs_n),
        .dfi_act_n        (dfi_act_n),
        .dfi_ras_n        (dfi_ras_n),
        .dfi_cas_n        (dfi_cas_n),
        .dfi_we_n         (dfi_we_n),
        .dfi_wrdata_en    (dfi_wrdata_en),
        .dfi_wrdata       (dfi_wrdata),
        .dfi_wrdata_mask  (dfi_wrdata_mask),
        .dfi_rddata_en    (dfi_rddata_en),
        .dfi_rddata       (dfi_rddata),
        .dfi_rddata_valid (dfi_rddata_valid),
        .dfi_reset_n      (dfi_reset_n),
        .dfi_init_start   (dfi_init_start),
        .dfi_init_complete(dfi_init_complete),
        .phy_initialized  (phy_initialized),
        .dfi_ctrlupd_req  (dfi_ctrlupd_req),
        .dfi_ctrlupd_ack  (dfi_ctrlupd_ack),
        .dfi_phyupd_req   (dfi_phyupd_req),
        .dfi_phyupd_ack   (dfi_phyupd_ack),
        .dfi_lp_req       (dfi_lp_req),
        .dfi_lp_ack       (dfi_lp_ack),
        .dfi_lp_wakeup    (dfi_lp_wakeup)
    );

    int tests_run    = 0;
    int tests_passed = 0;
    int tests_failed = 0;

    initial begin
        // Reset initialization
        rst_n             = 1'b0;
        cmd_valid         = 1'b0;
        cmd_type          = 3'b000;
        cmd_bg            = 2'd0;
        cmd_ba            = 3'd0;
        cmd_addr          = '0;
        cmd_wdata         = '0;
        cmd_tag           = 16'h0;
        dfi_rddata        = '0;
        dfi_rddata_valid  = 1'b0;
        dfi_init_complete = 1'b0;
        dfi_ctrlupd_ack   = 1'b0;
        dfi_phyupd_req    = 1'b0;
        dfi_lp_ack        = 1'b0;

        #(ClkPeriod * 4);
        rst_n = 1'b1;

        $display("================================================================");
        $display("[TB_DFI_ADAPTER] STARTING DFI 5.0 PHY ADAPTER VERIFICATION");
        $display("================================================================");

        // TEST 0: DFI 5.0 Initialization Handshake
        tests_run++;
        // Wait for dfi_init_start from DUT
        while (!dfi_init_start) @(posedge clk);
        $display("[INFO] dfi_init_start asserted. Simulating PHY leveling and calibration...");
        repeat (5) @(posedge clk);
        dfi_init_complete <= 1'b1; // Signal PHY training complete
        @(posedge clk);
        #1ps;
        if (phy_initialized && cmd_ready && dfi_reset_n) begin
            $display("[PASS] Test 0: DFI 5.0 Initialization handshake successful.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 0: DFI 5.0 Initialization failed.");
            tests_failed++;
        end

        // TEST 1: Reset Bus State
        tests_run++;
        if (dfi_cs_n == 1'b1 && dfi_act_n == 1'b1 && dfi_ras_n == 1'b1 &&
            dfi_cas_n == 1'b1 && dfi_we_n == 1'b1 && dfi_wrdata_en == 1'b0 &&
            dfi_rddata_en == 1'b0) begin
            $display("[PASS] Test 1: Reset bus pins verified idle and unselected.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 1: DFI bus active during reset.");
            tests_failed++;
        end

        // TEST 2: ACTIVATE Command
        tests_run++;
        @(posedge clk);
        cmd_valid <= 1'b1;
        cmd_type  <= 3'b001; // CmdAct
        cmd_bg    <= 2'd2;
        cmd_ba    <= 3'd5;
        cmd_addr  <= 16'hABCD;
        cmd_tag   <= 16'h1111;

        @(posedge clk);
        #1ps;
        if (dfi_cs_n == 1'b0 && dfi_act_n == 1'b0 && dfi_bank_group == 2'd2 &&
            dfi_bank == 3'd5 && dfi_address == 16'hABCD) begin
            $display("[PASS] Test 2: CmdAct issued correctly (ACT# = 0, BG=2, Bank=5, Addr=0xABCD).");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 2: ACTIVATE command pin encoding mismatch.");
            tests_failed++;
        end
        cmd_valid <= 1'b0;

        // TEST 3: PRECHARGE Command
        tests_run++;
        @(posedge clk);
        cmd_valid <= 1'b1;
        cmd_type  <= 3'b010; // CmdPre
        cmd_bg    <= 2'd1;
        cmd_ba    <= 3'd3;
        cmd_addr  <= 16'h0400; // A10 = 1 for Precharge All
        cmd_tag   <= 16'h2222;

        @(posedge clk);
        #1ps;
        if (dfi_cs_n == 1'b0 && dfi_ras_n == 1'b0 && dfi_we_n == 1'b0 && dfi_cas_n == 1'b1) begin
            $display("[PASS] Test 3: CmdPre issued correctly (RAS# = 0, WE# = 0, CAS# = 1).");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 3: PRECHARGE pin encoding mismatch.");
            tests_failed++;
        end
        cmd_valid <= 1'b0;

        // TEST 4: WRITE Command with Data
        tests_run++;
        @(posedge clk);
        cmd_valid <= 1'b1;
        cmd_type  <= 3'b100; // CmdWr
        cmd_bg    <= 2'd3;
        cmd_ba    <= 3'd0;
        cmd_addr  <= 16'h0020;
        cmd_wdata <= 128'hCAFE_BABE_DEAD_BEEF_0123_4567_89AB_CDEF;
        cmd_tag   <= 16'h3333;

        @(posedge clk);
        #1ps;
        if (dfi_cs_n == 1'b0 && dfi_cas_n == 1'b0 && dfi_we_n == 1'b0 &&
            dfi_wrdata_en == 1'b1 && dfi_wrdata == 128'hCAFE_BABE_DEAD_BEEF_0123_4567_89AB_CDEF) begin
            $display("[PASS] Test 4: CmdWr issued with 128-bit aligned write payload and dfi_wrdata_en=1.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 4: WRITE pin or data encoding mismatch.");
            tests_failed++;
        end
        cmd_valid <= 1'b0;

        // TEST 5: READ Command and Tag Pipeline Match
        tests_run++;
        @(posedge clk);
        cmd_valid <= 1'b1;
        cmd_type  <= 3'b011; // CmdRd
        cmd_bg    <= 2'd0;
        cmd_ba    <= 3'd1;
        cmd_addr  <= 16'h0080;
        cmd_tag   <= 16'h7788;

        @(posedge clk);
        #1ps;
        if (dfi_cs_n == 1'b0 && dfi_cas_n == 1'b0 && dfi_we_n == 1'b1 && dfi_rddata_en == 1'b1) begin
            $display("[PASS] Test 5a: CmdRd issued with dfi_rddata_en=1.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 5a: READ pin encoding mismatch.");
            tests_failed++;
        end
        cmd_valid <= 1'b0;

        // Wait CAS Latency (14 cycles) and return read data from simulated PHY
        repeat (CasLatency - 1) @(posedge clk);
        @(posedge clk);
        dfi_rddata       <= 128'h9999_8888_7777_6666_5555_4444_3333_2222;
        dfi_rddata_valid <= 1'b1;

        @(posedge clk);
        #1ps;
        if (rd_resp_valid && rd_resp_data == 128'h9999_8888_7777_6666_5555_4444_3333_2222 &&
            rd_resp_tag == 16'h7788) begin
            $display("[PASS] Test 5b: Read response completed after CL=14 with matching tag 0x7788.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 5b: Read response mismatch after CL=14. Tag=%04h", rd_resp_tag);
            tests_failed++;
        end
        dfi_rddata_valid <= 1'b0;

        // TEST 6: DFI 5.0 Calibration & Update Protocol (dfi_phyupd)
        tests_run++;
        @(posedge clk);
        dfi_phyupd_req <= 1'b1; // PHY requests update window for DLL recalibration
        @(posedge clk);
        #1ps;
        if (dfi_phyupd_ack && !cmd_ready) begin
            $display("[PASS] Test 6: PHY Update requested, dfi_phyupd_ack=1, cmd_ready=0 (traffic stalled).");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 6: PHY Update interlock failed.");
            tests_failed++;
        end
        dfi_phyupd_req <= 1'b0;
        @(posedge clk);
        #1ps;
        if (cmd_ready) begin
            $display("[PASS] Test 6b: Traffic resumed cleanly after calibration.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 6b: Traffic failed to resume.");
            tests_failed++;
        end

        #(ClkPeriod * 4);
        $display("================================================================");
        $display("[TB_DFI_ADAPTER] SUMMARY: %0d/%0d TESTS PASSED, %0d FAILED",
                 tests_passed, tests_run + 2, tests_failed);
        $display("================================================================");

        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED SUCCESSFULLY]");
            $finish;
        end else begin
            $fatal(1, "[TESTBENCH COMPLETED WITH FAILURES]");
        end
    end

endmodule: tb_dfi_phy_adapter
