//=============================================================================
// Testbench:   tb_sec_ddr5_controller_top
// Description: Comprehensive End-to-End System Testbench for the Complete
//              Secure DDR5 Memory Controller Architecture.
//
// Verifies Full Closed-Loop Integration:
// 1. System Reset & Multi-Clock Domain Initialization (250 MHz AXI / 400 MHz DDR5)
// 2. APB4 Key Provisioning & Security Lockdown
// 3. 64-Byte AXI4 Write Burst Handshake (AW, W, B channels)
// 4. Subchannel A & B Decomposition with 14-Stage In-Line AES-256-XTS Pipelining
// 5. Dual CDC FIFO Asynchronous Crossing (250 MHz -> 400 MHz)
// 6. Dual FR-FCFS Bank Schedulers & DFI 5.0 PHY Bus Command/Data Generation
// Standard:    AMBA AXI4 / AMBA APB4 / DFI 5.0 / SystemVerilog IEEE 1800-2017
//=============================================================================

`timescale 1ns / 1ps

module tb_sec_ddr5_controller_top;

    localparam int IdWidth    = 8;
    localparam int AddrWidth  = 34;
    localparam int DataWidth  = 128;
    localparam int ApbAddrW   = 12;

    localparam time AxiClkPeriod = 4.0ns; // 250 MHz
    localparam time DdrClkPeriod = 2.5ns; // 400 MHz

    // Clocks & Resets
    logic clk_axi = 0;
    always #(AxiClkPeriod/2) clk_axi = ~clk_axi;

    logic clk_ddr = 0;
    always #(DdrClkPeriod/2) clk_ddr = ~clk_ddr;

    logic rst_axi_n;
    logic rst_ddr_n;

    // AXI4 Master Signals
    logic [IdWidth-1:0]    s_axi_awid;
    logic [AddrWidth-1:0]  s_axi_awaddr;
    logic [7:0]            s_axi_awlen;
    logic [2:0]            s_axi_awsize;
    logic [1:0]            s_axi_awburst;
    logic                  s_axi_awvalid;
    logic                  s_axi_awready;

    logic [DataWidth-1:0]  s_axi_wdata;
    logic [DataWidth/8-1:0] s_axi_wstrb;
    logic                  s_axi_wlast;
    logic                  s_axi_wvalid;
    logic                  s_axi_wready;

    logic [IdWidth-1:0]    s_axi_bid;
    logic [1:0]            s_axi_bresp;
    logic                  s_axi_bvalid;
    logic                  s_axi_bready;

    logic [IdWidth-1:0]    s_axi_arid;
    logic [AddrWidth-1:0]  s_axi_araddr;
    logic [7:0]            s_axi_arlen;
    logic [2:0]            s_axi_arsize;
    logic [1:0]            s_axi_arburst;
    logic                  s_axi_arvalid;
    logic                  s_axi_arready;

    logic [IdWidth-1:0]    s_axi_rid;
    logic [DataWidth-1:0]  s_axi_rdata;
    logic [1:0]            s_axi_rresp;
    logic                  s_axi_rlast;
    logic                  s_axi_rvalid;
    logic                  s_axi_rready;

    // APB4 Master Signals
    logic [ApbAddrW-1:0]   paddr;
    logic                  psel;
    logic                  penable;
    logic                  pwrite;
    logic [31:0]           pwdata;
    logic [3:0]            pstrb;
    logic [2:0]            pprot;
    logic                  pready;
    logic [31:0]           prdata;
    logic                  pslverr;

    // DFI 5.0 Subchannel A
    logic [15:0]           dfi_a_address;
    logic [2:0]            dfi_a_bank;
    logic [1:0]            dfi_a_bank_group;
    logic                  dfi_a_cs_n;
    logic                  dfi_a_act_n;
    logic                  dfi_a_ras_n;
    logic                  dfi_a_cas_n;
    logic                  dfi_a_we_n;
    logic                  dfi_a_wrdata_en;
    logic [127:0]          dfi_a_wrdata;
    logic [15:0]           dfi_a_wrdata_mask;
    logic                  dfi_a_rddata_en;
    logic [127:0]          dfi_a_rddata;
    logic                  dfi_a_rddata_valid;

    // DFI 5.0 Subchannel B
    logic [15:0]           dfi_b_address;
    logic [2:0]            dfi_b_bank;
    logic [1:0]            dfi_b_bank_group;
    logic                  dfi_b_cs_n;
    logic                  dfi_b_act_n;
    logic                  dfi_b_ras_n;
    logic                  dfi_b_cas_n;
    logic                  dfi_b_we_n;
    logic                  dfi_b_wrdata_en;
    logic [127:0]          dfi_b_wrdata;
    logic [15:0]           dfi_b_wrdata_mask;
    logic                  dfi_b_rddata_en;
    logic [127:0]          dfi_b_rddata;
    logic                  dfi_b_rddata_valid;

    logic                  controller_idle;
    logic                  security_locked;

    // DUT Top Instance
    sec_ddr5_controller_top #(
        .IdWidth  (IdWidth),
        .AddrWidth(AddrWidth),
        .DataWidth(DataWidth),
        .ApbAddrW (ApbAddrW)
    ) u_top_dut (
        .clk_axi           (clk_axi),
        .rst_axi_n         (rst_axi_n),
        .clk_ddr           (clk_ddr),
        .rst_ddr_n         (rst_ddr_n),
        .s_axi_awid        (s_axi_awid),
        .s_axi_awaddr      (s_axi_awaddr),
        .s_axi_awlen       (s_axi_awlen),
        .s_axi_awsize      (s_axi_awsize),
        .s_axi_awburst     (s_axi_awburst),
        .s_axi_awvalid     (s_axi_awvalid),
        .s_axi_awready     (s_axi_awready),
        .s_axi_wdata       (s_axi_wdata),
        .s_axi_wstrb       (s_axi_wstrb),
        .s_axi_wlast       (s_axi_wlast),
        .s_axi_wvalid      (s_axi_wvalid),
        .s_axi_wready      (s_axi_wready),
        .s_axi_bid         (s_axi_bid),
        .s_axi_bresp       (s_axi_bresp),
        .s_axi_bvalid      (s_axi_bvalid),
        .s_axi_bready      (s_axi_bready),
        .s_axi_arid        (s_axi_arid),
        .s_axi_araddr      (s_axi_araddr),
        .s_axi_arlen       (s_axi_arlen),
        .s_axi_arsize      (s_axi_arsize),
        .s_axi_arburst     (s_axi_arburst),
        .s_axi_arvalid     (s_axi_arvalid),
        .s_axi_arready     (s_axi_arready),
        .s_axi_rid         (s_axi_rid),
        .s_axi_rdata       (s_axi_rdata),
        .s_axi_rresp       (s_axi_rresp),
        .s_axi_rlast       (s_axi_rlast),
        .s_axi_rvalid      (s_axi_rvalid),
        .s_axi_rready      (s_axi_rready),
        .paddr             (paddr),
        .psel              (psel),
        .penable           (penable),
        .pwrite            (pwrite),
        .pwdata            (pwdata),
        .pstrb             (pstrb),
        .pprot             (pprot),
        .pready            (pready),
        .prdata            (prdata),
        .pslverr           (pslverr),
        .dfi_a_address     (dfi_a_address),
        .dfi_a_bank        (dfi_a_bank),
        .dfi_a_bank_group  (dfi_a_bank_group),
        .dfi_a_cs_n        (dfi_a_cs_n),
        .dfi_a_act_n       (dfi_a_act_n),
        .dfi_a_ras_n       (dfi_a_ras_n),
        .dfi_a_cas_n       (dfi_a_cas_n),
        .dfi_a_we_n        (dfi_a_we_n),
        .dfi_a_wrdata_en   (dfi_a_wrdata_en),
        .dfi_a_wrdata      (dfi_a_wrdata),
        .dfi_a_wrdata_mask (dfi_a_wrdata_mask),
        .dfi_a_rddata_en   (dfi_a_rddata_en),
        .dfi_a_rddata      (dfi_a_rddata),
        .dfi_a_rddata_valid(dfi_a_rddata_valid),
        .dfi_b_address     (dfi_b_address),
        .dfi_b_bank        (dfi_b_bank),
        .dfi_b_bank_group  (dfi_b_bank_group),
        .dfi_b_cs_n        (dfi_b_cs_n),
        .dfi_b_act_n       (dfi_b_act_n),
        .dfi_b_ras_n       (dfi_b_ras_n),
        .dfi_b_cas_n       (dfi_b_cas_n),
        .dfi_b_we_n        (dfi_b_we_n),
        .dfi_b_wrdata_en   (dfi_b_wrdata_en),
        .dfi_b_wrdata      (dfi_b_wrdata),
        .dfi_b_wrdata_mask (dfi_b_wrdata_mask),
        .dfi_b_rddata_en   (dfi_b_rddata_en),
        .dfi_b_rddata      (dfi_b_rddata),
        .dfi_b_rddata_valid(dfi_b_rddata_valid),
        .controller_idle   (controller_idle),
        .security_locked   (security_locked)
    );

    int tests_run    = 0;
    int tests_passed = 0;
    int tests_failed = 0;
    `include "tb_check.svh"

    // Monitor DFI: hàng của mỗi lệnh ACT (cs_n=0, act_n=0) và payload ghi trên subchannel A/B.
    logic [15:0]  a_act_rows [$];
    logic [127:0] a_wr_data  [$];
    int           b_wr_data_cnt = 0;
    int           a_wr_data_total = 0;

    always @(posedge clk_ddr) begin
        if (rst_ddr_n) begin
            if (!dfi_a_cs_n && !dfi_a_act_n) a_act_rows.push_back(dfi_a_address);
            if (dfi_a_wrdata_en) begin
                a_wr_data.push_back(dfi_a_wrdata);
                a_wr_data_total++;
            end
            if (dfi_b_wrdata_en) b_wr_data_cnt++;
        end
    end

    task automatic axi_write_burst_resp(input logic [7:0] id, input logic [33:0] addr, input logic [127:0] base,
                                        output logic [7:0] bid, output logic [1:0] bresp);
        @(posedge clk_axi);
        s_axi_awid    <= id;
        s_axi_awaddr  <= addr;
        s_axi_awlen   <= 8'd3;
        s_axi_awvalid <= 1'b1;
        @(posedge clk_axi);
        while (!s_axi_awready) @(posedge clk_axi);
        s_axi_awvalid <= 1'b0;
        for (int b = 0; b < 4; b++) begin
            s_axi_wdata  <= base + 128'(b);
            s_axi_wlast  <= (b == 3);
            s_axi_wvalid <= 1'b1;
            do @(posedge clk_axi); while (!s_axi_wready);
        end
        s_axi_wvalid <= 1'b0;
        s_axi_wlast  <= 1'b0;
        while (!s_axi_bvalid) @(posedge clk_axi);
        bid   = s_axi_bid;
        bresp = s_axi_bresp;
        @(posedge clk_axi);
    endtask

    task automatic axi_write_burst(input logic [7:0] id, input logic [33:0] addr, input logic [127:0] base);
        logic [7:0] bid;
        logic [1:0] bresp;
        axi_write_burst_resp(id, addr, base, bid, bresp);
    endtask

    // APB Write Task
    task automatic apb_write(
        input logic [ApbAddrW-1:0] addr,
        input logic [31:0]         data
    );
        @(posedge clk_axi);
        paddr   <= addr;
        pwrite  <= 1'b1;
        psel    <= 1'b1;
        penable <= 1'b0;
        pwdata  <= data;
        pstrb   <= 4'hF;

        @(posedge clk_axi);
        penable <= 1'b1;

        @(posedge clk_axi);
        psel    <= 1'b0;
        penable <= 1'b0;
        pwrite  <= 1'b0;
    endtask

    initial begin
        #200us;
        $fatal(1, "[TIMEOUT] Simulation hung in tb_sec_ddr5_controller_top");
    end

    initial begin
        // Reset initialization
        rst_axi_n          = 1'b0;
        rst_ddr_n          = 1'b0;
        s_axi_awid         = '0;
        s_axi_awaddr       = '0;
        s_axi_awlen        = 8'h0;
        s_axi_awsize       = 3'b100; // 16 bytes
        s_axi_awburst      = 2'b01;  // INCR
        s_axi_awvalid      = 1'b0;
        s_axi_wdata        = '0;
        s_axi_wstrb        = '1;
        s_axi_wlast        = 1'b0;
        s_axi_wvalid       = 1'b0;
        s_axi_bready       = 1'b1;
        s_axi_arid         = '0;
        s_axi_araddr       = '0;
        s_axi_arlen        = 8'h0;
        s_axi_arsize       = 3'b100; // 16 bytes
        s_axi_arburst      = 2'b01;  // INCR
        s_axi_arvalid      = 1'b0;
        s_axi_rready       = 1'b1;

        paddr              = '0;
        psel               = 1'b0;
        penable            = 1'b0;
        pwrite             = 1'b0;
        pwdata             = '0;
        pstrb              = 4'hF;
        pprot              = 3'b000;

        dfi_a_rddata       = '0;
        dfi_a_rddata_valid = 1'b0;
        dfi_b_rddata       = '0;
        dfi_b_rddata_valid = 1'b0;

        #(AxiClkPeriod * 5);
        rst_axi_n = 1'b1;
        rst_ddr_n = 1'b1;
        #(AxiClkPeriod * 2);

        $display("================================================================");
        $display("[TB_TOP] STARTING FULL-SYSTEM SECURE DDR5 CONTROLLER VERIF");
        $display("================================================================");

        // TEST 1: Initial System State
        tests_run++;
        if (s_axi_awready && !security_locked) begin
            $display("[PASS] Test 1: Full System initialized cleanly. AXI ready, security unlocked.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 1: Initial system state invalid.");
            tests_failed++;
        end

        // TEST 2: APB4 Key Configuration & Security Lockdown
        tests_run++;
        $display("[INFO] Configuring AES-256 Keys via APB4 CSR...");
        for (int i = 0; i < 8; i++) begin
            apb_write(12'h010 + (i * 4), 32'hA000_0000 | i); // Key 1
            apb_write(12'h030 + (i * 4), 32'hB000_0000 | i); // Key 2
        end

        // Assert Security Lockdown
        apb_write(12'h008, 32'hA55A_0001);
        repeat (2) @(posedge clk_axi);

        if (security_locked) begin
            $display("[PASS] Test 2: Keys loaded and Security Lockdown successfully enforced.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 2: Security Lockdown failed to assert.");
            tests_failed++;
        end

        // TEST 3: End-to-End 64-Byte Write Burst Execution
        // AXI4 Master writes 64 Bytes -> In-line AES-XTS -> CDC -> DFI PHY
        tests_run++;
        $display("[INFO] Streaming 64-Byte AXI4 Write Burst through controller...");

        @(posedge clk_axi);
        s_axi_awid    <= 8'h42;
        s_axi_awaddr  <= 34'h1_8000_0000;
        s_axi_awlen   <= 8'd3; // 4 beats of 16 Bytes = 64 Bytes
        s_axi_awvalid <= 1'b1;

        @(posedge clk_axi);
        s_axi_awvalid <= 1'b0;

        // Drive 4 W beats
        for (int b = 0; b < 4; b++) begin
            s_axi_wdata  <= {4{32'h1234_0000 | b}};
            s_axi_wlast  <= (b == 3);
            s_axi_wvalid <= 1'b1;
            do begin
                @(posedge clk_axi);
            end while (!s_axi_wready);
        end
        s_axi_wvalid <= 1'b0;
        s_axi_wlast  <= 1'b0;

        // Monitor AXI Write Response
        while (!s_axi_bvalid) @(posedge clk_axi);
        #1ps;
        if (s_axi_bid == 8'h42 && s_axi_bresp == 2'b00) begin
            $display("[PASS] Test 3a: AXI4 Write response completed with BID=0x42 and BRESP=OKAY.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 3a: AXI4 Write response mismatch. BID=%02h, BRESP=%02b",
                     s_axi_bid, s_axi_bresp);
            tests_failed++;
        end

        // TEST 4: Payload trên DFI phải là bản mã (khác mọi beat plaintext của Test 3).
        begin
            bit leaked;
            for (int c = 0; c < 400 && (a_wr_data.size() == 0 || b_wr_data_cnt == 0); c++) @(posedge clk_ddr);
            tb_check(a_wr_data.size() > 0 && b_wr_data_cnt > 0,
                     $sformatf("Test 4a: both subchannels transferred write data (A=%0d, B=%0d beats)",
                               a_wr_data.size(), b_wr_data_cnt));
            leaked = 1'b0;
            foreach (a_wr_data[i]) begin
                for (int b = 0; b < 4; b++) if (a_wr_data[i] == {4{32'h1234_0000 | b}}) leaked = 1'b1;
            end
            tb_check(!leaked, "Test 4b: no plaintext beat appears on DFI subchannel A");
            tb_xfail("R6", "Test 4c: ciphertext not compared to a golden AES-256-XTS model (key schedule is not FIPS-197)");
        end

        // TEST 5: Hàng DRAM chỉ được phụ thuộc địa chỉ: ghi lại CÙNG địa chỉ với dữ liệu khác không được kích hoạt hàng khác.
        begin
            logic [15:0] first_row;
            bit          other_row;
            first_row = (a_act_rows.size() > 0) ? a_act_rows[0] : 16'hFFFF;
            a_act_rows.delete();
            axi_write_burst(8'h43, 34'h1_8000_0000, 128'hFFFF_FFFF_0000_0000_FFFF_FFFF_0000_0000);
            repeat (200) @(posedge clk_ddr);
            other_row = 1'b0;
            foreach (a_act_rows[i]) if (a_act_rows[i] != first_row) other_row = 1'b1;
            tb_check_xfail(!other_row, "R4",
                           $sformatf("Test 5: same AXI address, different data -> same DRAM row (first 0x%04h, %0d new ACT)",
                                     first_row, a_act_rows.size()));
        end

        // TEST 6: Luồng ghi liên tục: mỗi burst phải nhận đúng BID và BRESP=OKAY.
        for (int burst = 0; burst < 4; burst++) begin
            logic [7:0] got_bid;
            logic [1:0] got_bresp;
            axi_write_burst_resp(8'h50 + burst[7:0], 34'h1_8000_0000 + (burst * 64), 128'(burst * 4), got_bid, got_bresp);
            tb_check(got_bid == 8'h50 + burst[7:0] && got_bresp == 2'b00,
                     $sformatf("Test 6: burst %0d write response BID=0x%02h BRESP=%0d", burst, got_bid, got_bresp));
        end

        // TEST 7: Đọc lại địa chỉ đã ghi phải nhận được phản hồi R (kênh đọc của adapter hiện là stub).
        begin
            int waited;
            @(posedge clk_axi);
            s_axi_arid    <= 8'h77;
            s_axi_araddr  <= 34'h1_8000_0000;
            s_axi_arlen   <= 8'd3;
            s_axi_arvalid <= 1'b1;
            @(posedge clk_axi);
            while (!s_axi_arready) @(posedge clk_axi);
            s_axi_arvalid <= 1'b0;
            waited = 0;
            while (!s_axi_rvalid && waited < 500) begin
                @(posedge clk_axi);
                waited++;
            end
            tb_check_xfail(s_axi_rvalid === 1'b1, "R1",
                           $sformatf("Test 7: read-back of written address returns R data (waited %0d cycles)", waited));
        end

        #(DdrClkPeriod * 20);
        $display("================================================================");
        $display("[TB_TOP] SUMMARY: %0d/%0d TESTS PASSED, %0d FAILED",
                 tests_passed, tests_run, tests_failed);
        $display("================================================================");

        // TEST 8: Bảo toàn dữ liệu ghi: 6 burst × 4 beat AXI (24 beat) phải xuất hiện đủ trên hai subchannel DFI.
        repeat (400) @(posedge clk_ddr);
        tb_check(a_wr_data_total + b_wr_data_cnt == 24,
                 $sformatf("Test 8: all AXI write beats reached DFI (A=%0d + B=%0d of 24)", a_wr_data_total, b_wr_data_cnt));

        // TEST 9 (TEE.Fail'25 / DDRop'26): kẻ nghe lén bus DDR5 thấy bản mã lặp lại khi giá trị cũ được ghi lại,
        // và có thể phát lại bản mã cũ mà không bị phát hiện. Mã hóa có độ tươi (counter/MAC) phải cho bản mã khác nhau.
        begin
            int n0, n1;
            logic [127:0] c_first, c_again;
            n0 = a_wr_data.size();
            axi_write_burst(8'h61, 34'h1_8000_1000, 128'h5555_AAAA_5555_AAAA_5555_AAAA_5555_AAAA);
            for (int c = 0; c < 400 && a_wr_data.size() == n0; c++) @(posedge clk_ddr);
            c_first = a_wr_data[n0];
            axi_write_burst(8'h62, 34'h1_8000_1000, 128'h0123_4567_89AB_CDEF_0123_4567_89AB_CDEF);
            repeat (200) @(posedge clk_ddr);
            n1 = a_wr_data.size();
            axi_write_burst(8'h63, 34'h1_8000_1000, 128'h5555_AAAA_5555_AAAA_5555_AAAA_5555_AAAA);
            for (int c = 0; c < 400 && a_wr_data.size() == n1; c++) @(posedge clk_ddr);
            c_again = a_wr_data[n1];
            tb_check_xfail(c_first != c_again, "S23",
                           $sformatf("Test 9: rewriting an old value must not reproduce its ciphertext on the bus (%032h vs %032h)",
                                     c_first, c_again));
        end

        tb_merge_legacy(tests_passed + tests_failed, tests_failed);
        tb_report();
        $finish;
    end

endmodule: tb_sec_ddr5_controller_top
