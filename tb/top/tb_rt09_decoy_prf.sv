// File:      tb_rt09_decoy_prf.sv
// Chức năng: Testbench cấp top cho T-RT09 (M-09): kiểm tra địa chỉ decoy bằng PRF có khóa (SCARF), tính độc lập row[1:0] vs bank, kiểm định runs BG và chống dự đoán LFSR 17-bit.
`timescale 1ns / 1ps

module tb_rt09_decoy_prf;
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
    localparam int TCK_PS         = 4000;

    logic clk_axi = 0;
    always #2.0 clk_axi = ~clk_axi;
    wire clk_ddr = clk_axi;
    logic aresetn_axi, aresetn_ddr;

    logic [AXI_ID_WIDTH-1:0]   s_axi_awid = 0, s_axi_bid, s_axi_arid = 0, s_axi_rid;
    logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr = 0, s_axi_araddr = 0;
    logic [AXI_LEN_WIDTH-1:0]  s_axi_awlen = 0, s_axi_arlen = 0;
    logic [2:0]                s_axi_awsize = 3'b011, s_axi_arsize = 3'b011;
    logic [1:0]                s_axi_awburst = 2'b01, s_axi_arburst = 2'b01;
    logic [AXI_QOS_WIDTH-1:0]  s_axi_awqos = 0, s_axi_arqos = 0;
    logic                      s_axi_awvalid = 0, s_axi_awready, s_axi_arvalid = 0, s_axi_arready;
    logic [AXI_DATA_WIDTH-1:0] s_axi_wdata = 0, s_axi_rdata;
    logic [AXI_STRB_WIDTH-1:0] s_axi_wstrb = 8'hFF;
    logic                      s_axi_wlast = 0, s_axi_wvalid = 0, s_axi_wready;
    logic [1:0]                s_axi_bresp, s_axi_rresp;
    logic                      s_axi_bvalid, s_axi_bready = 1;
    logic                      s_axi_rlast, s_axi_rvalid, s_axi_rready = 1;

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

    logic                      cfg_is_ddr5 = 1, cfg_dual_hash_en = 1;
    logic [15:0]               cfg_rh_threshold = 16'd500, cfg_window_size = 16'd60000;
    logic [15:0]               o_throttled_events, o_ecc_single_err_cnt, o_ecc_double_err_cnt;
    logic                      cfg_decoy_en;
    logic                      o_decoy_active;
    logic [15:0]               o_decoy_cnt;
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
        .DFI_RDLAT     (8),
        .TCK_PS        (TCK_PS)
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
        .cfg_decoy_en        (cfg_decoy_en),
        .o_decoy_active      (o_decoy_active),
        .o_decoy_cnt         (o_decoy_cnt),
        .o_fault_cause       (o_fault_cause),
        .o_glitch_alert      (o_glitch_alert)
    );

    dram_model #(.COL_W(COL_WIDTH), .RL(8), .WL(9)) u_dram (
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

    dfi_jedec_checker #(.TCK_PS(TCK_PS), .TB_DFI_WRLAT(9)) u_jchk (
        .clk  (clk_axi),
        .rst_n(aresetn_axi),
        .cmd  (dut.u_cmd_engine.o_dfi_cmd),
        .bg   (dut.u_cmd_engine.o_dfi_bg),
        .bank (dut.u_cmd_engine.o_dfi_bank),
        .row  (dut.u_cmd_engine.o_dfi_row),
        .len  (dut.u_cmd_engine.o_dfi_len)
    );

    // Thu thập mọi lệnh ACT decoy (o_decoy_active == 1) trong 50 000 chu kỳ idle
    int decoy_total;
    int row_eq_bank_cnt;
    int bg_seq_inc_cnt;
    int lfsr17_pred_hits;
    logic [BG_WIDTH-1:0]  prev_decoy_bg;
    logic [ROW_WIDTH-1:0] lfsr17_state;

    always @(posedge clk_axi) begin
        if (!aresetn_axi) begin
            decoy_total      <= 0;
            row_eq_bank_cnt  <= 0;
            bg_seq_inc_cnt   <= 0;
            lfsr17_pred_hits <= 0;
            prev_decoy_bg    <= '0;
            lfsr17_state     <= 17'h1_ACE1;
        end else if (dut.u_cmd_engine.o_decoy_active && dut.u_cmd_engine.o_dfi_cmd == 3'd1) begin
            logic [ROW_WIDTH-1:0] next_lfsr;
            next_lfsr = {lfsr17_state[15:0], lfsr17_state[16] ^ lfsr17_state[13]};
            if (decoy_total > 0) begin
                if (dut.u_cmd_engine.o_dfi_bg == BG_WIDTH'(prev_decoy_bg + 1'b1))
                    bg_seq_inc_cnt <= bg_seq_inc_cnt + 1;
                if (dut.u_cmd_engine.o_dfi_row == next_lfsr)
                    lfsr17_pred_hits <= lfsr17_pred_hits + 1;
            end
            if (dut.u_cmd_engine.o_dfi_row[1:0] == dut.u_cmd_engine.o_dfi_bank)
                row_eq_bank_cnt <= row_eq_bank_cnt + 1;

            prev_decoy_bg <= dut.u_cmd_engine.o_dfi_bg;
            lfsr17_state  <= dut.u_cmd_engine.o_dfi_row;
            decoy_total   <= decoy_total + 1;
        end
    end

    initial begin
        $display("=== TB_RT09_DECOY_PRF: Keyed-PRF (SCARF) Decoy Address Unpredictability & Independence ===");
        $display("[SEED] 0x51530001");
        aresetn_axi  = 0;
        aresetn_ddr  = 0;
        cfg_decoy_en = 1'b1;

        repeat (10) @(posedge clk_axi);
        aresetn_axi = 1; aresetn_ddr = 1;

        // Chạy 50 000 chu kỳ idle để thu thập mẫu ACT decoy
        repeat (50000) @(posedge clk_axi);

        $display("[INFO] Collected %0d decoy ACTs: row[1:0]==bank=%0d, bg_seq_inc=%0d, lfsr17_hits=%0d",
                 decoy_total, row_eq_bank_cnt, bg_seq_inc_cnt, lfsr17_pred_hits);

        tb_check(decoy_total >= 100, $sformatf("T-RT09: observed %0d decoy ACTs in 50,000 idle cycles (>= 100)", decoy_total));
        // Trên v1: row[1:0] === bank 100% (decoy_total / decoy_total) và bg tăng tuần tự +1 100% và LFSR 17-bit đoán trúng 100%!
        // Trên v2: row[1:0] == bank xấp xỉ 25% ± 3*sigma (nằm trong [15%, 35%]), bg_seq_inc < 30%, lfsr17_pred_hits == 0!
        tb_check((row_eq_bank_cnt * 100 >= decoy_total * 15) && (row_eq_bank_cnt * 100 <= decoy_total * 35),
                 $sformatf("T-RT09: row[1:0]==bank rate %0d/%0d within 25%% +/- 3 sigma (v1 was 100%%)",
                           row_eq_bank_cnt, decoy_total));
        tb_check(bg_seq_inc_cnt * 100 < decoy_total * 30,
                 $sformatf("T-RT09: BG sequential increment rate %0d/%0d < 30%% (v1 was 100%%)",
                           bg_seq_inc_cnt, decoy_total));
        tb_check(lfsr17_pred_hits * 1024 <= decoy_total,
                 $sformatf("T-RT09: 17-bit LFSR predictor hits %0d/%0d <= 1/2^10 (v1 was 100%%)",
                           lfsr17_pred_hits, decoy_total));
        tb_check(u_jchk.timing_violations() == 0, "SA-J01..J21: 0 JEDEC timing violations during 50,000-cycle decoy run");
        tb_check(o_fault_cause == 9'd0 && o_glitch_alert == 1'b0, "SA-F06: no false fault or glitch alert");

        u_jchk.report("rt09");
        $display("[PERF] decoy_acts=%0d n_ref=%0d n_rfm=%0d ref_gap_max_ps=%0d",
                 decoy_total, u_jchk.n_ref, u_jchk.n_rfm, u_jchk.worst_ref_gap_ps());
        tb_report();
        $finish;
    end

    initial begin
        #300_000_000;
        $display("[FAIL] Watchdog timeout");
        tb_report();
        $finish;
    end
endmodule

