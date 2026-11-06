// File:      tb_rt04_jedec_400mhz.sv
// Chức năng: Testbench cấp top cho T-RT04: chạy ở đúng 400 MHz (TCK_PS = 2500 ps) với 16 seed trộn RD/WR/row-miss/REF/RFM/ABO, kiểm SA-J01..J21.
`timescale 1ns / 1ps
`include "qs_hier.svh"

module tb_rt04_jedec_400mhz;
    `include "tb_check.svh"

    localparam int AXI_ID_WIDTH   = 4;
    localparam int AXI_ADDR_WIDTH = 32;
    localparam int AXI_DATA_WIDTH = 64;
    localparam int AXI_STRB_WIDTH = 8;
    localparam int AXI_LEN_WIDTH  = 8;
    localparam int AXI_QOS_WIDTH  = 4;
    localparam int BG_COUNT       = 8;
    localparam int BG_WIDTH       = 3;
    localparam int BANK_COUNT     = 4;
    localparam int BANK_WIDTH     = 2;
    localparam int ROW_WIDTH      = 17;
    localparam int COL_WIDTH      = 13;
    localparam int ROB_DEPTH      = 16;
    localparam int TCK_PS         = 2500;
    localparam int RL_CYC         = 8;
    localparam int WL_CYC         = 9;

    // Clock 400 MHz (chu kỳ 2.5 ns: bán kỳ 1.25 ns)
    logic clk_axi = 0;
    always #1.25 clk_axi = ~clk_axi;
    wire clk_ddr = clk_axi;
    logic aresetn_axi, aresetn_ddr;

    logic [AXI_ID_WIDTH-1:0]   s_axi_awid, s_axi_bid, s_axi_arid, s_axi_rid;
    logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr, s_axi_araddr;
    logic [AXI_LEN_WIDTH-1:0]  s_axi_awlen, s_axi_arlen;
    logic [2:0]                s_axi_awsize, s_axi_arsize;
    logic [1:0]                s_axi_awburst, s_axi_arburst;
    logic [AXI_QOS_WIDTH-1:0]  s_axi_awqos, s_axi_arqos;
    logic                      s_axi_awvalid, s_axi_awready, s_axi_arvalid, s_axi_arready;
    logic [AXI_DATA_WIDTH-1:0] s_axi_wdata, s_axi_rdata;
    logic [AXI_STRB_WIDTH-1:0] s_axi_wstrb;
    logic                      s_axi_wlast, s_axi_wvalid, s_axi_wready;
    logic [1:0]                s_axi_bresp, s_axi_rresp;
    logic                      s_axi_bvalid, s_axi_bready;
    logic                      s_axi_rlast, s_axi_rvalid, s_axi_rready;
    logic                      s_axi_rpoison;

    logic [2:0]                dfi_cmd;
    logic [BG_WIDTH-1:0]       dfi_bg;
    logic [BANK_WIDTH-1:0]     dfi_bank;
    logic [ROW_WIDTH-1:0]      dfi_row;
    logic [COL_WIDTH-1:0]      dfi_col;
    logic [7:0]                dfi_len;
    logic                      dfi_wrdata_en;
    logic [AXI_DATA_WIDTH-1:0] dfi_wrdata, dfi_rddata;
    logic [7:0]                dfi_wrdata_mask, dfi_wrdata_ecc, dfi_rddata_ecc;
    logic                      dfi_rddata_valid;

    logic                      cfg_is_ddr5, cfg_dual_hash_en;
    logic [15:0]               cfg_rh_threshold, cfg_window_size;
    logic [15:0]               o_throttled_events, o_ecc_single_err_cnt, o_ecc_double_err_cnt;
    logic                      i_dram_abo_alert;
    logic                      cfg_decoy_en;
    logic [8:0]                o_fault_cause;
    logic                      o_glitch_alert;

    axi_ddr5_mc_top #(
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_LEN_WIDTH (AXI_LEN_WIDTH),
        .AXI_QOS_WIDTH (AXI_QOS_WIDTH),
        .BG_COUNT      (BG_COUNT),
        .BANK_COUNT    (BANK_COUNT),
        .ROW_WIDTH     (ROW_WIDTH),
        .COL_WIDTH     (COL_WIDTH),
        .ROB_DEPTH     (ROB_DEPTH),
        .DFI_RDLAT     (RL_CYC)
`ifndef QS_BASELINE_V1
        ,
        .TCK_PS        (TCK_PS)
`endif
    ) dut (
        .clk_axi             (clk_axi),
        .aresetn_axi         (aresetn_axi),
        .clk_ddr             (clk_ddr),
        .aresetn_ddr         (aresetn_ddr),
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
        .s_axi_rpoison       (s_axi_rpoison),
        .dfi_cmd             (dfi_cmd),
        .dfi_bg              (dfi_bg),
        .dfi_bank            (dfi_bank),
        .dfi_row             (dfi_row),
        .dfi_col             (dfi_col),
        .dfi_len             (dfi_len),
        .dfi_wrdata_en       (dfi_wrdata_en),
        .dfi_wrdata          (dfi_wrdata),
        .dfi_wrdata_mask     (dfi_wrdata_mask),
        .dfi_wrdata_ecc      (dfi_wrdata_ecc),
        .dfi_rddata_valid    (dfi_rddata_valid),
        .dfi_rddata          (dfi_rddata),
        .dfi_rddata_ecc      (dfi_rddata_ecc),
        .cfg_is_ddr5         (cfg_is_ddr5),
        .cfg_dual_hash_en    (cfg_dual_hash_en),
        .cfg_rh_threshold    (cfg_rh_threshold),
        .cfg_window_size     (cfg_window_size),
        .o_throttled_events  (o_throttled_events),
        .o_ecc_single_err_cnt(o_ecc_single_err_cnt),
        .o_ecc_double_err_cnt(o_ecc_double_err_cnt),
        .i_dram_abo_alert    (i_dram_abo_alert),
        .cfg_decoy_en        (cfg_decoy_en),
`ifndef QS_BASELINE_V1
        .o_fault_cause       (o_fault_cause),
`endif
        .o_glitch_alert      (o_glitch_alert)
    );

    dram_model #(.COL_W(COL_WIDTH), .RL(RL_CYC), .WL(WL_CYC)) u_dram (
        .clk         (clk_axi),
        .rst_n       (aresetn_axi),
        .cmd         (dfi_cmd),
        .bg          (dfi_bg),
        .bank        (dfi_bank),
        .row         (dfi_row),
        .col         (dfi_col),
        .len         (dfi_len),
        .wrdata_en   (dfi_wrdata_en),
        .wrdata      (dfi_wrdata),
        .wrdata_mask (dfi_wrdata_mask),
        .wrdata_ecc  (dfi_wrdata_ecc),
        .rddata_valid(dfi_rddata_valid),
        .rddata      (dfi_rddata),
        .rddata_ecc  (dfi_rddata_ecc)
    );

    dfi_jedec_checker #(.TCK_PS(TCK_PS), .TB_DFI_WRLAT(WL_CYC)) u_jchk (
        .clk  (clk_axi),
        .rst_n(aresetn_axi),
        .cmd  (dut.u_cmd_engine.o_dfi_cmd),
        .bg   (dut.u_cmd_engine.o_dfi_bg),
        .bank (dut.u_cmd_engine.o_dfi_bank),
        .row  (dut.u_cmd_engine.o_dfi_row),
        .len  (dut.u_cmd_engine.o_dfi_len)
    );

    qs_axi_txn_chk #(
        .AXI_ADDR_W(AXI_ADDR_WIDTH),
        .AXI_DATA_W(AXI_DATA_WIDTH),
        .AXI_ID_W  (AXI_ID_WIDTH)
    ) u_achk (
        .clk          (clk_axi),
        .rst_n        (aresetn_axi),
        .en_v2        (1'b1),
        .chk_data_en  (1'b0),
        .s_axi_awid   (s_axi_awid),
        .s_axi_awaddr (s_axi_awaddr),
        .s_axi_awlen  (s_axi_awlen),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata  (s_axi_wdata),
        .s_axi_wstrb  (s_axi_wstrb),
        .s_axi_wlast  (s_axi_wlast),
        .s_axi_wvalid (s_axi_wvalid),
        .s_axi_wready (s_axi_wready),
        .s_axi_bid    (s_axi_bid),
        .s_axi_bresp  (s_axi_bresp),
        .s_axi_bvalid (s_axi_bvalid),
        .s_axi_bready (s_axi_bready),
        .s_axi_arid   (s_axi_arid),
        .s_axi_araddr (s_axi_araddr),
        .s_axi_arlen  (s_axi_arlen),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rid    (s_axi_rid),
        .s_axi_rdata  (s_axi_rdata),
        .s_axi_rresp  (s_axi_rresp),
        .s_axi_rlast  (s_axi_rlast),
        .s_axi_rvalid (s_axi_rvalid),
        .s_axi_rready (s_axi_rready),
        .s_axi_rpoison(s_axi_rpoison)
    );

    function automatic [AXI_ADDR_WIDTH-1:0] mk_addr(
        input int row, input int bg, input int bank, input int col
    );
        logic [31:0] a;
        a        = 32'd0;
        a[31:15] = row[16:0];
        a[14:11] = col[3:0];
        a[10:9]  = bank[1:0] ^ a[19:18];
        a[8:6]   = bg[2:0]   ^ a[17:15];
        return a;
    endfunction

    int unsigned rng;

    initial begin
        $display("=== TB_RT04_JEDEC_400MHZ: 400 MHz (TCK_PS=2500) 16-Seed Mixed Traffic & JEDEC Checker ===");
        aresetn_axi      = 0;
        aresetn_ddr      = 0;
        i_dram_abo_alert = 0;
        s_axi_awid       = 0; s_axi_awaddr = 0; s_axi_awlen = 0; s_axi_awsize = 3'd3;
        s_axi_awburst    = 2'b01; s_axi_awqos = 0; s_axi_awvalid = 0;
        s_axi_wdata      = 0; s_axi_wstrb = 8'hFF; s_axi_wlast = 0; s_axi_wvalid = 0;
        s_axi_bready     = 1;
        s_axi_arid       = 0; s_axi_araddr = 0; s_axi_arlen = 0; s_axi_arsize = 3'd3;
        s_axi_arburst    = 2'b01; s_axi_arqos = 0; s_axi_arvalid = 0;
        s_axi_rready     = 1;
        cfg_is_ddr5      = 1;
        cfg_dual_hash_en = 1;
        cfg_rh_threshold = 16'd16;
        cfg_window_size  = 16'd4096;
        cfg_decoy_en     = 1;
`ifdef QS_BASELINE_V1
        o_fault_cause    = '0;
`endif

        repeat (10) @(posedge clk_axi);
        aresetn_axi = 1; aresetn_ddr = 1;
        repeat (20) @(posedge clk_axi);

        for (int s = 0; s < 16; s++) begin
            rng = 32'h5153_0001 + s;
            $display("[SEED] 0x%08x", rng);
            for (int op = 0; op < 16; op++) begin
                int bg, bk, row, col;
                rng = (rng * 1664525) + 1013904223;
                bg  = rng[2:0];
                bk  = rng[4:3];
                row = (op < 6) ? (17'h010 + op) : (17'h010 + (rng[7:5] & 3));
                col = (rng[12:8] & 4'hF);

                @(negedge clk_axi);
                if (rng[15]) begin
                    s_axi_awid    = rng[19:16];
                    s_axi_awaddr  = mk_addr(row, bg, bk, col);
                    s_axi_awlen   = 8'd0;
                    s_axi_awqos   = rng[23:20];
                    s_axi_awvalid = 1'b1;
                    s_axi_wdata   = {32'(rng), 32'(op)};
                    s_axi_wstrb   = (rng[24] && op > 8) ? 8'h0F : 8'hFF;
                    s_axi_wlast   = 1'b1;
                    s_axi_wvalid  = 1'b1;
                    do @(posedge clk_axi); while (!(s_axi_awready && s_axi_wready));
                    @(negedge clk_axi);
                    s_axi_awvalid = 1'b0;
                    s_axi_wvalid  = 1'b0;
                    s_axi_wlast   = 1'b0;
                end else begin
                    s_axi_arid    = rng[19:16];
                    s_axi_araddr  = mk_addr(row, bg, bk, col);
                    s_axi_arlen   = 8'd0;
                    s_axi_arqos   = rng[23:20];
                    s_axi_arvalid = 1'b1;
                    do @(posedge clk_axi); while (!s_axi_arready);
                    @(negedge clk_axi);
                    s_axi_arvalid = 1'b0;
                end
            end

            // Kích hoạt ABO ở một số seed để kiểm cả RFMab ở 400 MHz
            if ((s & 3) == 0) begin
                @(negedge clk_axi);
                i_dram_abo_alert = 1'b1;
                repeat (4) @(posedge clk_axi);
                @(negedge clk_axi);
                i_dram_abo_alert = 1'b0;
            end

            repeat (120) @(posedge clk_axi);
        end

        while (u_achk.rd_done < u_achk.rd_cmds || u_achk.wr_done < u_achk.wr_cmds) @(posedge clk_axi);
        repeat (50) @(posedge clk_axi);
        u_achk.final_check();

        tb_check(u_jchk.n_ref >= 1, $sformatf("T-RT04: observed %0d REF commands at 400 MHz", u_jchk.n_ref));
        tb_check(u_jchk.n_rfm >= 1, $sformatf("T-RT04: observed %0d RFM commands at 400 MHz", u_jchk.n_rfm));
        tb_check(u_jchk.timing_violations() == 0 && u_jchk.viol_ref_open == 0,
                 $sformatf("T-RT04 (SA-J01..J21): 0 JEDEC timing violations at 400 MHz (got %0d, %0d)",
                           u_jchk.timing_violations(), u_jchk.viol_ref_open));
        tb_check(u_achk.errors() == 0, $sformatf("T-RT04: 0 AXI transaction errors (got %0d)", u_achk.errors()));
`ifndef QS_BASELINE_V1
        tb_check(o_fault_cause == 9'd0 && o_glitch_alert == 1'b0, "SA-F06: no false fault or glitch alert");
`endif

        u_jchk.report("rt04_400mhz");
        $display("[PERF] rd_cmds=%0d wr_cmds=%0d n_ref=%0d n_rfm=%0d ref_gap_max_ps=%0d",
                 u_achk.rd_done, u_achk.wr_done, u_jchk.n_ref, u_jchk.n_rfm, u_jchk.worst_ref_gap_ps());
        tb_report();
        $finish;
    end

    initial begin
        #200_000_000;
        $display("[FAIL] Watchdog timeout");
        tb_report();
        $finish;
    end
endmodule
