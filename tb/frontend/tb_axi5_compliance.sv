// File: tb_axi5_compliance.sv
// Chức năng: Kiểm chứng tuân thủ chuẩn AMBA AXI5 Poison và bảo vệ chẵn lẻ ASIL-D.

`timescale 1ns / 1ps

module tb_axi5_compliance;

    localparam int AXI_ID_WIDTH   = 4;
    localparam int AXI_ADDR_WIDTH = 32;
    localparam int AXI_DATA_WIDTH = 64;
    localparam int AXI_QOS_WIDTH  = 4;
    localparam time ClkPeriod     = 2.5ns;

    logic clk = 0;
    always #(ClkPeriod/2) clk = ~clk;

    logic aresetn;

    // AXI Slave external signals
    logic [AXI_ID_WIDTH-1:0]   s_axi_awid;
    logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr;
    logic [7:0]                s_axi_awlen;
    logic [2:0]                s_axi_awsize;
    logic [1:0]                s_axi_awburst;
    logic [AXI_QOS_WIDTH-1:0]  s_axi_awqos;
    logic                      s_axi_awvalid;
    logic                      s_axi_awready;

    logic [AXI_DATA_WIDTH-1:0]   s_axi_wdata;
    logic [AXI_DATA_WIDTH/8-1:0] s_axi_wstrb;
    logic                        s_axi_wlast;
    logic                        s_axi_wvalid;
    logic                        s_axi_wready;

    logic [AXI_ID_WIDTH-1:0]   s_axi_bid;
    logic [1:0]                s_axi_bresp;
    logic                      s_axi_bvalid;
    logic                      s_axi_bready;

    logic [AXI_ID_WIDTH-1:0]   s_axi_arid;
    logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr;
    logic [7:0]                s_axi_arlen;
    logic [2:0]                s_axi_arsize;
    logic [1:0]                s_axi_arburst;
    logic [AXI_QOS_WIDTH-1:0]  s_axi_arqos;
    logic                      s_axi_arvalid;
    logic                      s_axi_arready;

    logic [AXI_ID_WIDTH-1:0]   s_axi_rid;
    logic [AXI_DATA_WIDTH-1:0] s_axi_rdata;
    logic [1:0]                s_axi_rresp;
    logic                      s_axi_rlast;
    logic                      s_axi_rvalid;
    logic                      s_axi_rready;

    // AXI5 Poison & Parity
    logic                      s_axi_awpoison;
    logic                      s_axi_wpoison;
    logic                      s_axi_arpoison;
    logic                      s_axi_rpoison;

    logic [3:0]                s_axi_awchk;
    logic [3:0]                s_axi_archk;
    logic [7:0]                s_axi_wchk;
    logic [7:0]                s_axi_rchk;
    logic                      cfg_parity_check_en;
    logic                      o_parity_err;

    // Internal backend signals
    logic                      o_wr_addr_valid;
    logic                      i_wr_addr_ready;
    logic [AXI_ID_WIDTH-1:0]   o_wr_addr_id;
    logic [AXI_ADDR_WIDTH-1:0] o_wr_addr;
    logic [7:0]                o_wr_len;
    logic [2:0]                o_wr_size;
    logic [1:0]                o_wr_burst;
    logic [AXI_QOS_WIDTH-1:0]  o_wr_qos;
    logic                      o_wr_addr_cross_4kb;

    logic                      o_wr_data_valid;
    logic                      i_wr_data_ready;
    logic [AXI_DATA_WIDTH-1:0] o_wr_data;
    logic [7:0]                o_wr_strb;
    logic                      o_wr_last;

    logic                      i_bresp_valid;
    logic                      o_bresp_ready;
    logic [AXI_ID_WIDTH-1:0]   i_bresp_id;
    logic [1:0]                i_bresp_code;

    logic                      o_rd_req_valid;
    logic                      i_rd_req_ready;
    logic [AXI_ID_WIDTH-1:0]   o_rd_req_id;
    logic [AXI_ADDR_WIDTH-1:0] o_rd_req_addr;
    logic [7:0]                o_rd_req_len;
    logic [2:0]                o_rd_req_size;
    logic [1:0]                o_rd_req_burst;
    logic [AXI_QOS_WIDTH-1:0]  o_rd_req_qos;
    logic                      o_rd_req_cross_4kb;

    logic                      i_rdata_valid;
    logic                      o_rdata_ready;
    logic [AXI_ID_WIDTH-1:0]   i_rdata_id;
    logic [AXI_DATA_WIDTH-1:0] i_rdata;
    logic [1:0]                i_rdata_resp;
    logic                      i_rdata_last;
    logic                      i_rdata_poison;

    axi_slave_frontend #(
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_QOS_WIDTH  (AXI_QOS_WIDTH)
    ) u_frontend (
        .clk_axi             (clk),
        .aresetn_axi         (aresetn),

        .s_axi_awid          (s_axi_awid),
        .s_axi_awaddr        (s_axi_awaddr),
        .s_axi_awlen         (s_axi_awlen),
        .s_axi_awsize        (s_axi_awsize),
        .s_axi_awburst       (s_axi_awburst),
        .s_axi_awqos         (s_axi_awqos),
        .s_axi_awvalid       (s_axi_awvalid),
        .s_axi_awready       (s_axi_awready),

        .s_axi_wdata         (s_axi_wdata),
        .s_axi_wstrb         (s_axi_wstrb),
        .s_axi_wlast         (s_axi_wlast),
        .s_axi_wvalid        (s_axi_wvalid),
        .s_axi_wready        (s_axi_wready),

        .s_axi_bid           (s_axi_bid),
        .s_axi_bresp         (s_axi_bresp),
        .s_axi_bvalid        (s_axi_bvalid),
        .s_axi_bready        (s_axi_bready),

        .s_axi_arid          (s_axi_arid),
        .s_axi_araddr        (s_axi_araddr),
        .s_axi_arlen         (s_axi_arlen),
        .s_axi_arsize        (s_axi_arsize),
        .s_axi_arburst       (s_axi_arburst),
        .s_axi_arqos         (s_axi_arqos),
        .s_axi_arvalid       (s_axi_arvalid),
        .s_axi_arready       (s_axi_arready),

        .s_axi_rid           (s_axi_rid),
        .s_axi_rdata         (s_axi_rdata),
        .s_axi_rresp         (s_axi_rresp),
        .s_axi_rlast         (s_axi_rlast),
        .s_axi_rvalid        (s_axi_rvalid),
        .s_axi_rready        (s_axi_rready),

        .s_axi_awpoison      (s_axi_awpoison),
        .s_axi_wpoison       (s_axi_wpoison),
        .s_axi_arpoison      (s_axi_arpoison),
        .s_axi_rpoison       (s_axi_rpoison),

        .s_axi_awchk         (s_axi_awchk),
        .s_axi_archk         (s_axi_archk),
        .s_axi_wchk          (s_axi_wchk),
        .s_axi_rchk          (s_axi_rchk),
        .cfg_parity_check_en (cfg_parity_check_en),
        .o_parity_err        (o_parity_err),

        .o_wr_addr_valid     (o_wr_addr_valid),
        .i_wr_addr_ready     (i_wr_addr_ready),
        .o_wr_addr_id        (o_wr_addr_id),
        .o_wr_addr           (o_wr_addr),
        .o_wr_len            (o_wr_len),
        .o_wr_size           (o_wr_size),
        .o_wr_burst          (o_wr_burst),
        .o_wr_qos            (o_wr_qos),
        .o_wr_addr_cross_4kb (o_wr_addr_cross_4kb),

        .o_wr_data_valid     (o_wr_data_valid),
        .i_wr_data_ready     (i_wr_data_ready),
        .o_wr_data           (o_wr_data),
        .o_wr_strb           (o_wr_strb),
        .o_wr_last           (o_wr_last),

        .i_bresp_valid       (i_bresp_valid),
        .o_bresp_ready       (o_bresp_ready),
        .i_bresp_id          (i_bresp_id),
        .i_bresp_code        (i_bresp_code),

        .o_rd_req_valid      (o_rd_req_valid),
        .i_rd_req_ready      (i_rd_req_ready),
        .o_rd_req_id         (o_rd_req_id),
        .o_rd_req_addr       (o_rd_req_addr),
        .o_rd_req_len        (o_rd_req_len),
        .o_rd_req_size       (o_rd_req_size),
        .o_rd_req_burst      (o_rd_req_burst),
        .o_rd_req_qos        (o_rd_req_qos),
        .o_rd_req_cross_4kb  (o_rd_req_cross_4kb),

        .i_rdata_valid       (i_rdata_valid),
        .o_rdata_ready       (o_rdata_ready),
        .i_rdata_id          (i_rdata_id),
        .i_rdata             (i_rdata),
        .i_rdata_resp        (i_rdata_resp),
        .i_rdata_last        (i_rdata_last),
        .i_rdata_poison      (i_rdata_poison)
    );

    int tests_run = 0;
    int tests_passed = 0;
    int tests_failed = 0;

    initial begin
        aresetn             = 0;
        s_axi_awid          = '0;
        s_axi_awaddr        = '0;
        s_axi_awlen         = '0;
        s_axi_awsize        = 3'd3;
        s_axi_awburst       = 2'd1;
        s_axi_awqos         = '0;
        s_axi_awvalid       = 0;
        s_axi_wdata         = '0;
        s_axi_wstrb         = '0;
        s_axi_wlast         = 0;
        s_axi_wvalid        = 0;
        s_axi_bready        = 1;
        s_axi_arid          = '0;
        s_axi_araddr        = '0;
        s_axi_arlen         = '0;
        s_axi_arsize        = 3'd3;
        s_axi_arburst       = 2'd1;
        s_axi_arqos         = '0;
        s_axi_arvalid       = 0;
        s_axi_rready        = 1;

        s_axi_awpoison      = 0;
        s_axi_wpoison       = 0;
        s_axi_arpoison      = 0;
        s_axi_awchk         = '0;
        s_axi_archk         = '0;
        s_axi_wchk          = '0;
        cfg_parity_check_en = 0;

        i_wr_addr_ready     = 1;
        i_wr_data_ready     = 1;
        i_bresp_valid       = 0;
        i_bresp_id          = '0;
        i_bresp_code        = '0;
        i_rd_req_ready      = 1;
        i_rdata_valid       = 0;
        i_rdata_id          = '0;
        i_rdata             = '0;
        i_rdata_resp        = '0;
        i_rdata_last        = 0;
        i_rdata_poison      = 0;

        #(ClkPeriod * 4);
        aresetn = 1;
        #(ClkPeriod * 2);

        $display("[TB_AXI5] Test 1: Clean Read Data without Poison...");
        @(negedge clk);
        i_rdata_valid  = 1;
        i_rdata_id     = 4'hA;
        i_rdata        = 64'h0123_4567_89AB_CDEF;
        i_rdata_resp   = 2'b00; // OKAY
        i_rdata_last   = 1;
        i_rdata_poison = 0;

        @(posedge clk);
        #1;
        i_rdata_valid = 0;

        while (!s_axi_rvalid) @(posedge clk);
        #1;
        tests_run++;
        if (s_axi_rvalid && s_axi_rpoison == 1'b0 && s_axi_rresp == 2'b00) begin
            $display("[PASS] Test 1: Normal response has rpoison = 0");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 1: rvalid=%b, rpoison=%b", s_axi_rvalid, s_axi_rpoison);
            tests_failed++;
        end
        @(posedge clk);

        $display("[TB_AXI5] Test 2: Uncorrectable Error Read with Poison Assertion...");
        @(negedge clk);
        i_rdata_valid  = 1;
        i_rdata_id     = 4'hB;
        i_rdata        = 64'hDEAD_BEEF_CAFE_BABE;
        i_rdata_resp   = 2'b00;
        i_rdata_last   = 1;
        i_rdata_poison = 1; // Chipkill / SEC-DED Uncorrectable Error

        @(posedge clk);
        #1;
        i_rdata_valid = 0;

        while (!s_axi_rvalid) @(posedge clk);
        #1;
        tests_run++;
        if (s_axi_rvalid && s_axi_rpoison == 1'b1) begin
            $display("[PASS] Test 2: AXI5 rpoison = 1 propagated on uncorrectable error");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 2: rvalid=%b, rpoison=%b", s_axi_rvalid, s_axi_rpoison);
            tests_failed++;
        end
        @(posedge clk);

        $display("[TB_AXI5] Test 3: ASIL-D Parity Check on W Channel...");
        cfg_parity_check_en = 1;
        @(negedge clk);
        s_axi_wvalid = 1;
        s_axi_wdata  = 64'h0000_0000_0000_0001;
        s_axi_wstrb  = 8'hFF;
        s_axi_wlast  = 1;
        // Correct odd parity for 0x01 is ~1 = 0; for 0x00 is ~0 = 1.
        // Byte 0: 0x01 -> ~1 = 0
        // Bytes 1..7: 0x00 -> ~0 = 1
        s_axi_wchk   = 8'b1111_1110;

        @(posedge clk);
        #1;
        tests_run++;
        if (!o_parity_err) begin
            $display("[PASS] Test 3: Correct odd parity produces o_parity_err = 0");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 3: False positive parity error detected");
            tests_failed++;
        end
        s_axi_wvalid = 0;
        @(posedge clk);

        $display("[TB_AXI5] Test 4: Parity Error Detection on Injected Bit Flip...");
        @(negedge clk);
        s_axi_wvalid = 1;
        s_axi_wdata  = 64'h0000_0000_0000_0001;
        s_axi_wstrb  = 8'hFF;
        s_axi_wlast  = 1;
        s_axi_wchk   = 8'b1111_1111; // Injected bit error on byte 0 parity!

        @(posedge clk);
        #1;
        tests_run++;
        if (o_parity_err) begin
            $display("[PASS] Test 4: Corrupted parity correctly asserted o_parity_err = 1");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 4: Parity error failed to trigger alert (o_parity_err=%b)", o_parity_err);
            tests_failed++;
        end
        s_axi_wvalid = 0;
        @(posedge clk);

        #(ClkPeriod * 4);
        $display("================================================================");
        $display("[TB_AXI5] SUMMARY: %0d/%0d TESTS PASSED, %0d FAILED",
                 tests_passed, tests_run, tests_failed);
        $display("================================================================");

        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED SUCCESSFULLY]");
            $finish;
        end else begin
            $fatal(1, "[TESTBENCH COMPLETED WITH FAILURES]");
        end
    end

endmodule: tb_axi5_compliance
