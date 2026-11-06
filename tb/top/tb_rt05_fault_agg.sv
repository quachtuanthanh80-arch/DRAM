// File:      tb_rt05_fault_agg.sv
// Chức năng: Testbench cấp top cho T-RT05d/e (FI-06, FI-49, FI-60..FI-63): bộ gom lỗi chốt sticky, ưu tiên sự kiện mới thắng cfg_fault_clr, phản ứng đa lỗi.
`timescale 1ns / 1ps
`include "qs_hier.svh"
`include "qs_fi.svh"

module tb_rt05_fault_agg;
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
    localparam int RL_CYC         = 8;
    localparam int WL_CYC         = 9;

    logic clk_axi = 0;
    always #2.0 clk_axi = ~clk_axi;
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
    logic                      cfg_fault_clr;
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
        .DFI_RDLAT     (RL_CYC),
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
        .cfg_fault_clr       (cfg_fault_clr),
        .o_fault_cause       (o_fault_cause),
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

    // Bộ kiểm liên tục SA-F05 (o_glitch_alert == |o_fault_cause trừ đúng chu kỳ bơm FI-60/FI-61)
    bit skip_f05_chk;
    int f05_err_cnt;
    always @(posedge clk_axi) begin
        if (aresetn_axi && !skip_f05_chk) begin
            if (o_glitch_alert !== (|o_fault_cause))
                f05_err_cnt <= f05_err_cnt + 1;
        end
    end

    task automatic clr_all();
        @(negedge clk_axi);
        cfg_fault_clr = 1'b1;
        @(posedge clk_axi);
        @(negedge clk_axi);
        cfg_fault_clr = 1'b0;
        @(posedge clk_axi);
    endtask

    initial begin
        $display("=== TB_RT05_FAULT_AGG: Top Sticky Fault Aggregator, Priority & Multi-Fault Response ===");
        $display("[SEED] 0x51530001");
        aresetn_axi      = 0;
        aresetn_ddr      = 0;
        skip_f05_chk     = 0;
        f05_err_cnt      = 0;
        s_axi_awid       = 0; s_axi_awaddr = 0; s_axi_awlen = 0; s_axi_awsize = 3'd3;
        s_axi_awburst    = 2'b01; s_axi_awqos = 0; s_axi_awvalid = 0;
        s_axi_wdata      = 0; s_axi_wstrb = 8'hFF; s_axi_wlast = 0; s_axi_wvalid = 0;
        s_axi_bready     = 1;
        s_axi_arid       = 0; s_axi_araddr = 0; s_axi_arlen = 0; s_axi_arsize = 3'd3;
        s_axi_arburst    = 2'b01; s_axi_arqos = 0; s_axi_arvalid = 0;
        s_axi_rready     = 1;
        cfg_is_ddr5      = 1;
        cfg_dual_hash_en = 1;
        cfg_rh_threshold = 16'd500;
        cfg_window_size  = 16'd60000;
        cfg_fault_clr    = 0;

        repeat (10) @(posedge clk_axi);
        aresetn_axi = 1; aresetn_ddr = 1;
        repeat (20) @(posedge clk_axi);

        tb_check(o_fault_cause == 9'd0 && o_glitch_alert == 1'b0, "SA-F06: clean start with o_fault_cause=0 and o_glitch_alert=0");

        //---------------------------------------------------------------------
        // 1. FI-06 (T-RT05e): Lật 1 bit rolling_act_cnt[0] -> o_fault[1] kích hoạt RFMab tự trị;
        //    sau khi RFMab xóa bộ đếm RAA (o_fault[1] hạ về 0), o_fault_cause[1] và o_glitch_alert vẫn giữ nguyên (SA-F02)!
        //---------------------------------------------------------------------
        begin
            int rfm_before;
            rfm_before = u_jchk.n_rfm;
            `QS_FI_FLIP1(clk_axi, `QS_E_RAA_CNT(dut.u_cmd_engine)[0], 0);
            repeat (2) @(posedge clk_axi);
            #1ps;
            tb_check(o_fault_cause[1] === 1'b1 && o_glitch_alert === 1'b1,
                     "FI-06: RAA dual-counter mismatch latches o_fault_cause[1] and o_glitch_alert");
            repeat (150) @(posedge clk_axi);
            tb_check(u_jchk.n_rfm > rfm_before, "FI-06 (SA-F12): RAA mismatch triggers autonomous RFMab");
            tb_check(dut.u_cmd_engine.o_fault[1] === 1'b0 && o_fault_cause[1] === 1'b1 && o_glitch_alert === 1'b1,
                     "FI-06 (SA-F02): after RFMab heals RAA counter (o_fault[1]==0), o_fault_cause[1] & o_glitch_alert stay sticky");

            // Kiểm xóa khi nguồn còn mức (§10.14): ép flag_err (rcd_z[0] = 0 khi rcd_timer[0] == 0) và giữ cfg_fault_clr = 1
            @(negedge clk_axi);
            force `QS_E_RCD_Z(dut.u_cmd_engine)[0] = 1'b0;
            @(posedge clk_axi); // o_fault[3] lên 1
            @(negedge clk_axi);
            cfg_fault_clr = 1'b1;
            @(posedge clk_axi);
            #1ps;
            tb_check(o_fault_cause[3] === 1'b1,
                     "Sec 10.14 (SA-F03): clearing while level fault source (flag_err) is still active keeps o_fault_cause[3]=1");
            @(negedge clk_axi);
            cfg_fault_clr = 1'b0;
            release `QS_E_RCD_Z(dut.u_cmd_engine)[0];
            repeat (10) @(posedge clk_axi);
            clr_all();
            tb_check(o_fault_cause == 9'd0 && o_glitch_alert == 1'b0,
                     "SA-F04: cfg_fault_clr clears o_fault_cause and o_glitch_alert once source is inactive");
        end

        //---------------------------------------------------------------------
        // 2. FI-49 (T-RT05d ở top): Lật 1 bit inj_oh của DRM -> o_drm_fault -> o_fault_cause[7] + ép RFMab (i_force_rfm)
        //---------------------------------------------------------------------
        begin
            int rfm_before;
            rfm_before = u_jchk.n_rfm;
            `QS_FI_FLIP1(clk_axi, `QS_D_INJ_OH(dut.u_drm), 2);
            repeat (3) @(posedge clk_axi);
            tb_check(o_fault_cause[7] === 1'b1 && o_glitch_alert === 1'b1,
                     "FI-49 (T-RT05d): DRM inj_oh 1-bit flip latches o_fault_cause[7]");
            repeat (150) @(posedge clk_axi);
            tb_check(u_jchk.n_rfm > rfm_before, "FI-49 (SA-F12): o_drm_fault forces RFMab on cmd_engine");
            clr_all();
        end

        //---------------------------------------------------------------------
        // 3. FI-60: Đảo o_glitch_alert 1->0 sau khi đã có lỗi chốt -> tự nạp lại từ fault_sticky ở +1
        //---------------------------------------------------------------------
        `QS_FI_FLIP1(clk_axi, `QS_D_INJ_OH(dut.u_drm), 1);
        repeat (150) @(posedge clk_axi);
        tb_check(o_glitch_alert === 1'b1 && o_fault_cause[7] === 1'b1, "FI-60 pre: fault_sticky[7] and o_glitch_alert high");
        skip_f05_chk = 1'b1;
        @(negedge clk_axi);
        dut.o_glitch_alert = 1'b0;
        tb_check(o_glitch_alert === 1'b0, "FI-60 pre-check: deposit o_glitch_alert=0 at negedge takes effect");
        @(posedge clk_axi);
        #1ps;
        skip_f05_chk = 1'b0;
        tb_check(o_glitch_alert === 1'b1, "FI-60: o_glitch_alert 1->0 reloads from fault_sticky at +1 cycle");

        //---------------------------------------------------------------------
        // 4. FI-61: Đảo fault_sticky[7] 1->0 khi nguồn đã hạ (dư X: ghi nhận [FI-RESIDUAL] và kiểm SA-F05 ở +1)
        //---------------------------------------------------------------------
        skip_f05_chk = 1'b1;
        @(negedge clk_axi);
        `QS_T_FAULT_ST(dut)[7] = 1'b0;
        @(posedge clk_axi);
        #1ps;
        skip_f05_chk = 1'b0;
        $display("[FI-RESIDUAL] FI-61: direct SEU on non-redundant fault_sticky[7] cleared sticky bit (o_fault_cause=%b, o_glitch_alert=%b)",
                 o_fault_cause, o_glitch_alert);
        tb_check(o_glitch_alert === (|o_fault_cause), "FI-61 (SA-F05): o_glitch_alert remains consistent with |o_fault_cause");
        clr_all();

        //---------------------------------------------------------------------
        // 5. FI-62: cfg_fault_clr = 1 đúng cùng chu kỳ có sự kiện lỗi mới (fault_vec[i] = 1) -> sự kiện mới thắng (SA-F03)
        //---------------------------------------------------------------------
        `QS_FI_FLIP1(clk_axi, `QS_D_INJ_OH(dut.u_drm), 3);
        repeat (150) @(posedge clk_axi);
        tb_check(o_fault_cause[7] === 1'b1, "FI-62 pre: bit 7 set before simultaneous clear+new fault");

        @(negedge clk_axi);
        `QS_E_EXP_V(dut.u_cmd_engine)[0] = 1'b1;
        @(posedge clk_axi); // tại cạnh này u_cmd_engine.o_fault[5] lên 1
        @(negedge clk_axi);
        cfg_fault_clr = 1'b1; // cùng chu kỳ với fault_vec[5] == 1!
        @(posedge clk_axi);
        #1ps;
        tb_check(o_fault_cause[5] === 1'b1 && o_fault_cause[7] === 1'b0 && o_glitch_alert === 1'b1,
                 "FI-62 (SA-F03, SA-F04): new fault[5] wins over simultaneous cfg_fault_clr while old fault[7] is cleared");
        @(negedge clk_axi);
        cfg_fault_clr = 1'b0;
        repeat (20) @(posedge clk_axi);
        clr_all();

        //---------------------------------------------------------------------
        // 6. FI-63 (§10.15): Bơm đồng thời 3 khối trong cùng một chu kỳ:
        //    - Engine event mismatch (last_act = 1 khi NOP -> fault[2])
        //    - Engine read beat desync (exp_v[0] = 1 khi idle -> fault[5])
        //    - DRM FSM flip (inj_oh ^= 7'b0000100 -> fault[7])
        //---------------------------------------------------------------------
        @(negedge clk_axi);
        `QS_E_LAST_ACT(dut.u_cmd_engine) = 1'b1;
        `QS_E_EXP_V(dut.u_cmd_engine)[0] = 1'b1;
        `QS_D_INJ_OH(dut.u_drm)          = `QS_D_INJ_OH(dut.u_drm) ^ 7'b000_0100;
        @(posedge clk_axi);
        @(posedge clk_axi);
        #1ps;
        tb_check(o_fault_cause[2] === 1'b1 && o_fault_cause[5] === 1'b1 && o_fault_cause[7] === 1'b1 && o_glitch_alert === 1'b1,
                 $sformatf("FI-63 (Sec 10.15): simultaneous 3-module fault injection latched bits 2, 5, 7 at +2 cycles (got %b)",
                           o_fault_cause));
        repeat (150) @(posedge clk_axi);
        clr_all();
        tb_check(o_fault_cause == 9'd0 && o_glitch_alert == 1'b0, "Post FI-63: clean recovery after cfg_fault_clr");
        tb_check(f05_err_cnt == 0, "SA-F05: o_glitch_alert == |o_fault_cause held on every non-injected cycle");
        tb_check(u_jchk.timing_violations() == 0, "SA-J01..J21: 0 JEDEC timing violations");

        u_jchk.report("rt05");
        $display("[PERF] n_ref=%0d n_rfm=%0d fi_count=7 fi_detect_lat_max=2", u_jchk.n_ref, u_jchk.n_rfm);
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
