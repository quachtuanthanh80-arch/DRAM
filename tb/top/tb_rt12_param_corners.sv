// File:      tb_rt12_param_corners.sv
// Chức năng: Testbench cấp top cho T-RT12 (M-12, SA-E01..E09): kiểm tra biên dịch và chạy traffic ngắn tại các góc tham số hợp lệ.
`timescale 1ns / 1ps

module tb_rt12_param_corners;
    `include "tb_check.svh"

    logic clk = 0;
    always #1.25 clk = ~clk; // 400 MHz (TCK_PS = 2500)
    logic rst_n = 0;

    //-------------------------------------------------------------------------
    // Góc 1 (SA-E01, SA-E06): ROB_PTR_WIDTH == AXI_ID_WIDTH (4 == 4) và TRFC_PS = 410000 (32 Gb DDR5, T_RFC = 164)
    //-------------------------------------------------------------------------
    logic [3:0]  c1_awid = 0, c1_bid, c1_arid = 0, c1_rid;
    logic [31:0] c1_awaddr = 0, c1_araddr = 0;
    logic [7:0]  c1_awlen = 0, c1_arlen = 0;
    logic        c1_awvalid = 0, c1_awready, c1_wvalid = 0, c1_wready, c1_bvalid;
    logic [63:0] c1_wdata = 0, c1_rdata;
    logic        c1_arvalid = 0, c1_arready, c1_rvalid, c1_rlast;
    logic [1:0]  c1_bresp, c1_rresp;
    logic [2:0]  c1_cmd;
    logic [2:0]  c1_bg;
    logic [1:0]  c1_bank;
    logic [16:0] c1_row;
    logic [12:0] c1_col;
    logic [7:0]  c1_len, c1_wmask, c1_wecc, c1_recc;
    logic        c1_wen, c1_rvalid_dfi;
    logic [63:0] c1_wdata_dfi, c1_rdata_dfi;

    axi_ddr5_mc_top #(
        .AXI_ID_WIDTH (4),
        .ROB_DEPTH    (16), // ROB_PTR_WIDTH = 4 == AXI_ID_WIDTH
        .TCK_PS       (2500),
        .TRFC_PS      (410000), // T_RFC = 164 (32 Gb DDR5)
        .TRFM_PS      (410000),
        .DFI_RDLAT    (8)
    ) u_corner1 (
        .clk_axi             (clk),
        .aresetn_axi         (rst_n),
        .clk_ddr             (clk),
        .aresetn_ddr         (rst_n),
        .s_axi_awid          (c1_awid),
        .s_axi_awaddr        (c1_awaddr),
        .s_axi_awlen         (c1_awlen),
        .s_axi_awsize        (3'b011),
        .s_axi_awburst       (2'b01),
        .s_axi_awqos         (4'd0),
        .s_axi_awvalid       (c1_awvalid),
        .s_axi_awready       (c1_awready),
        .s_axi_wdata         (c1_wdata),
        .s_axi_wstrb         (8'hFF),
        .s_axi_wlast         (1'b1),
        .s_axi_wvalid        (c1_wvalid),
        .s_axi_wready        (c1_wready),
        .s_axi_bid           (c1_bid),
        .s_axi_bresp         (c1_bresp),
        .s_axi_bvalid        (c1_bvalid),
        .s_axi_bready        (1'b1),
        .s_axi_arid          (c1_arid),
        .s_axi_araddr        (c1_araddr),
        .s_axi_arlen         (c1_arlen),
        .s_axi_arsize        (3'b011),
        .s_axi_arburst       (2'b01),
        .s_axi_arqos         (4'd0),
        .s_axi_arvalid       (c1_arvalid),
        .s_axi_arready       (c1_arready),
        .s_axi_rid           (c1_rid),
        .s_axi_rdata         (c1_rdata),
        .s_axi_rresp         (c1_rresp),
        .s_axi_rlast         (c1_rlast),
        .s_axi_rvalid        (c1_rvalid),
        .s_axi_rready        (1'b1),
        .dfi_cmd             (c1_cmd),
        .dfi_bg              (c1_bg),
        .dfi_bank            (c1_bank),
        .dfi_row             (c1_row),
        .dfi_col             (c1_col),
        .dfi_len             (c1_len),
        .dfi_wrdata_en       (c1_wen),
        .dfi_wrdata          (c1_wdata_dfi),
        .dfi_wrdata_mask     (c1_wmask),
        .dfi_wrdata_ecc      (c1_wecc),
        .dfi_rddata_valid    (c1_rvalid_dfi),
        .dfi_rddata          (c1_rdata_dfi),
        .dfi_rddata_ecc      (c1_recc),
        .cfg_is_ddr5         (1'b1),
        .cfg_dual_hash_en    (1'b1),
        .cfg_rh_threshold    (16'd500),
        .cfg_window_size     (16'd60000),
        .o_throttled_events  (),
        .o_ecc_single_err_cnt(),
        .o_ecc_double_err_cnt()
    );

    dram_model #(.COL_W(13), .RL(8), .WL(9)) u_dram1 (
        .clk         (clk),
        .rst_n       (rst_n),
        .cmd         (c1_cmd),
        .bg          (c1_bg),
        .bank        (c1_bank),
        .row         (c1_row),
        .col         (c1_col),
        .len         (c1_len),
        .wrdata_en   (c1_wen),
        .wrdata      (c1_wdata_dfi),
        .wrdata_mask (c1_wmask),
        .wrdata_ecc  (c1_wecc),
        .rddata_valid(c1_rvalid_dfi),
        .rddata      (c1_rdata_dfi),
        .rddata_ecc  (c1_recc)
    );

    dfi_jedec_checker #(.TCK_PS(2500), .TB_DFI_WRLAT(9)) u_jchk1 (
        .clk  (clk),
        .rst_n(rst_n),
        .cmd  (u_corner1.u_cmd_engine.o_dfi_cmd),
        .bg   (u_corner1.u_cmd_engine.o_dfi_bg),
        .bank (u_corner1.u_cmd_engine.o_dfi_bank),
        .row  (u_corner1.u_cmd_engine.o_dfi_row),
        .len  (u_corner1.u_cmd_engine.o_dfi_len)
    );

    //-------------------------------------------------------------------------
    // Góc 2 (SA-E02, SA-E04): DFI_RDLAT = 1 (T_RDV = 2, biên tối thiểu của T_RDV >= 2)
    //                         và T_CWL + 7 + T_WR = 63 (DFI_WRLAT=9, TWR_PS=117500 -> T_WR=47 -> 9+7+47=63 < 64)
    //-------------------------------------------------------------------------
    logic [3:0]  c2_awid = 0, c2_bid, c2_arid = 0, c2_rid;
    logic [31:0] c2_awaddr = 0, c2_araddr = 0;
    logic [7:0]  c2_awlen = 0, c2_arlen = 0;
    logic        c2_awvalid = 0, c2_awready, c2_wvalid = 0, c2_wready, c2_bvalid;
    logic [63:0] c2_wdata = 0, c2_rdata;
    logic        c2_arvalid = 0, c2_arready, c2_rvalid, c2_rlast;
    logic [1:0]  c2_bresp, c2_rresp;
    logic [2:0]  c2_cmd;
    logic [2:0]  c2_bg;
    logic [1:0]  c2_bank;
    logic [16:0] c2_row;
    logic [12:0] c2_col;
    logic [7:0]  c2_len, c2_wmask, c2_wecc, c2_recc;
    logic        c2_wen, c2_rvalid_dfi;
    logic [63:0] c2_wdata_dfi, c2_rdata_dfi;

    axi_ddr5_mc_top #(
        .AXI_ID_WIDTH (4),
        .ROB_DEPTH    (16),
        .TCK_PS       (2500),
        .DFI_RDLAT    (1),      // T_RDV = 2 (biên dưới SA-E02)
        .TWR_PS       (117500)  // T_WR = 47 -> T_CWL(9) + 7 + 47 = 63 (biên trên SA-E04)
    ) u_corner2 (
        .clk_axi             (clk),
        .aresetn_axi         (rst_n),
        .clk_ddr             (clk),
        .aresetn_ddr         (rst_n),
        .s_axi_awid          (c2_awid),
        .s_axi_awaddr        (c2_awaddr),
        .s_axi_awlen         (c2_awlen),
        .s_axi_awsize        (3'b011),
        .s_axi_awburst       (2'b01),
        .s_axi_awqos         (4'd0),
        .s_axi_awvalid       (c2_awvalid),
        .s_axi_awready       (c2_awready),
        .s_axi_wdata         (c2_wdata),
        .s_axi_wstrb         (8'hFF),
        .s_axi_wlast         (1'b1),
        .s_axi_wvalid        (c2_wvalid),
        .s_axi_wready        (c2_wready),
        .s_axi_bid           (c2_bid),
        .s_axi_bresp         (c2_bresp),
        .s_axi_bvalid        (c2_bvalid),
        .s_axi_bready        (1'b1),
        .s_axi_arid          (c2_arid),
        .s_axi_araddr        (c2_araddr),
        .s_axi_arlen         (c2_arlen),
        .s_axi_arsize        (3'b011),
        .s_axi_arburst       (2'b01),
        .s_axi_arqos         (4'd0),
        .s_axi_arvalid       (c2_arvalid),
        .s_axi_arready       (c2_arready),
        .s_axi_rid           (c2_rid),
        .s_axi_rdata         (c2_rdata),
        .s_axi_rresp         (c2_rresp),
        .s_axi_rlast         (c2_rlast),
        .s_axi_rvalid        (c2_rvalid),
        .s_axi_rready        (1'b1),
        .dfi_cmd             (c2_cmd),
        .dfi_bg              (c2_bg),
        .dfi_bank            (c2_bank),
        .dfi_row             (c2_row),
        .dfi_col             (c2_col),
        .dfi_len             (c2_len),
        .dfi_wrdata_en       (c2_wen),
        .dfi_wrdata          (c2_wdata_dfi),
        .dfi_wrdata_mask     (c2_wmask),
        .dfi_wrdata_ecc      (c2_wecc),
        .dfi_rddata_valid    (c2_rvalid_dfi),
        .dfi_rddata          (c2_rdata_dfi),
        .dfi_rddata_ecc      (c2_recc),
        .cfg_is_ddr5         (1'b1),
        .cfg_dual_hash_en    (1'b1),
        .cfg_rh_threshold    (16'd500),
        .cfg_window_size     (16'd60000),
        .o_throttled_events  (),
        .o_ecc_single_err_cnt(),
        .o_ecc_double_err_cnt()
    );

    dram_model #(.COL_W(13), .RL(1), .WL(9)) u_dram2 (
        .clk         (clk),
        .rst_n       (rst_n),
        .cmd         (c2_cmd),
        .bg          (c2_bg),
        .bank        (c2_bank),
        .row         (c2_row),
        .col         (c2_col),
        .len         (c2_len),
        .wrdata_en   (c2_wen),
        .wrdata      (c2_wdata_dfi),
        .wrdata_mask (c2_wmask),
        .wrdata_ecc  (c2_wecc),
        .rddata_valid(c2_rvalid_dfi),
        .rddata      (c2_rdata_dfi),
        .rddata_ecc  (c2_recc)
    );

    dfi_jedec_checker #(.TCK_PS(2500), .TB_DFI_WRLAT(9)) u_jchk2 (
        .clk  (clk),
        .rst_n(rst_n),
        .cmd  (u_corner2.u_cmd_engine.o_dfi_cmd),
        .bg   (u_corner2.u_cmd_engine.o_dfi_bg),
        .bank (u_corner2.u_cmd_engine.o_dfi_bank),
        .row  (u_corner2.u_cmd_engine.o_dfi_row),
        .len  (u_corner2.u_cmd_engine.o_dfi_len)
    );

    initial begin
        $display("=== TB_RT12_PARAM_CORNERS: Valid Parameter Corners (SA-E01..E09) Traffic & JEDEC Check ===");
        $display("[SEED] 0x51530001");
        rst_n = 0;
        repeat (10) @(posedge clk);
        rst_n = 1;
        repeat (20) @(posedge clk);

        // Chạy ghi + đọc lại trên Corner 1 (T_RFC = 164, ROB_PTR_WIDTH == AXI_ID_WIDTH)
        for (int k = 0; k < 4; k++) begin
            @(negedge clk);
            c1_awid    = 4'(k);
            c1_awaddr  = 32'h0001_0000 + k * 64;
            c1_wdata   = 64'hC100_0000_0000_0000 + k;
            c1_awvalid = 1'b1;
            c1_wvalid  = 1'b1;
            do @(posedge clk); while (!(c1_awready && c1_wready));
            @(negedge clk);
            c1_awvalid = 1'b0;
            c1_wvalid  = 1'b0;
            while (!c1_bvalid) @(posedge clk);
            @(posedge clk);
        end
        for (int k = 0; k < 4; k++) begin
            @(negedge clk);
            c1_arid    = 4'(k);
            c1_araddr  = 32'h0001_0000 + k * 64;
            c1_arvalid = 1'b1;
            do @(posedge clk); while (!c1_arready);
            @(negedge clk);
            c1_arvalid = 1'b0;
            while (!c1_rvalid) @(posedge clk);
            tb_check(c1_rresp == 2'b00 && c1_rdata == (64'hC100_0000_0000_0000 + k),
                     $sformatf("Corner 1 (T_RFC=164, ROB_PTR_W==AXI_ID_W) readback %0d matches", k));
            @(posedge clk);
        end

        // Chạy ghi + đọc lại trên Corner 2 (T_RDV = 2, T_CWL + 7 + T_WR = 63)
        for (int k = 0; k < 4; k++) begin
            @(negedge clk);
            c2_awid    = 4'(k);
            c2_awaddr  = 32'h0002_0000 + k * 64;
            c2_wdata   = 64'hC200_0000_0000_0000 + k;
            c2_awvalid = 1'b1;
            c2_wvalid  = 1'b1;
            do @(posedge clk); while (!(c2_awready && c2_wready));
            @(negedge clk);
            c2_awvalid = 1'b0;
            c2_wvalid  = 1'b0;
            while (!c2_bvalid) @(posedge clk);
            @(posedge clk);
        end
        for (int k = 0; k < 4; k++) begin
            @(negedge clk);
            c2_arid    = 4'(k);
            c2_araddr  = 32'h0002_0000 + k * 64;
            c2_arvalid = 1'b1;
            do @(posedge clk); while (!c2_arready);
            @(negedge clk);
            c2_arvalid = 1'b0;
            while (!c2_rvalid) @(posedge clk);
            tb_check(c2_rresp == 2'b00 && c2_rdata == (64'hC200_0000_0000_0000 + k),
                     $sformatf("Corner 2 (T_RDV=2, pac_max=63) readback %0d matches", k));
            @(posedge clk);
        end

        // Chờ ít nhất 1 REFab để kiểm T_RFC = 164 ở Corner 1
        repeat (1800) @(posedge clk);

        tb_check(u_jchk1.timing_violations() == 0 && u_jchk2.timing_violations() == 0,
                 "T-RT12 (SA-J01..J21): 0 JEDEC timing violations across all valid parameter corners");
        tb_check(u_corner1.o_fault_cause == 9'd0 && u_corner2.o_fault_cause == 9'd0,
                 "T-RT12 (SA-F06): 0 faults across all valid parameter corners");

        u_jchk1.report("rt12_corner1");
        u_jchk2.report("rt12_corner2");
        $display("[PERF] rd_cmds=8 wr_cmds=8 c1_ref=%0d c2_ref=%0d", u_jchk1.n_ref, u_jchk2.n_ref);
        tb_report();
        $finish;
    end

    initial begin
        #100_000_000;
        $display("[FAIL] Watchdog timeout");
        tb_report();
        $finish;
    end
endmodule

