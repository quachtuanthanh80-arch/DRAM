// File:      tb_eng_ref_starve.sv
// Chức năng: Kiểm thử đơn vị ddr5_cmd_engine cho T-RT01a (chống bỏ đói REF dưới luồng ghi row-hit liên tục 25.000 chu kỳ) và FI-27 (user_blk_q SEU).
`timescale 1ns / 1ps
`include "qs_hier.svh"
`include "qs_fi.svh"

module tb_eng_ref_starve;
    `include "tb_check.svh"

    localparam int BG_W   = 3;
    localparam int BANK_W = 2;
    localparam int ROW_W  = 17;
    localparam int COL_W  = 10;
    localparam int TAG_W  = 5;
    localparam int NB     = (1 << BG_W) * (1 << BANK_W);
    localparam int T_RDV  = 9;

`ifdef QS_BASELINE_V1
    localparam bit EN_V2 = 1'b0;
`else
    localparam bit EN_V2 = 1'b1;
`endif

    logic clk = 0;
    always #1.25 clk = ~clk; // 400 MHz (TCK_PS = 2500)

    logic              rst_n = 0;
    logic              i_cmd_valid = 0;
    logic [TAG_W-1:0]  i_cmd_tag = 0;
    logic              i_cmd_is_write = 0;
    logic              i_cmd_is_mitigation = 0;
    logic              i_cmd_rmw = 0;
    logic [BG_W-1:0]   i_cmd_bg = 0;
    logic [BANK_W-1:0] i_cmd_bank = 0;
    logic [ROW_W-1:0]  i_cmd_row = 0;
    logic [COL_W-1:0]  i_cmd_col = 0;
    logic [7:0]        i_cmd_len = 0;
    logic [NB-1:0]     o_bank_free;
    logic              o_engine_mit_only;
    logic              o_abo_active;

    logic [2:0]        o_dfi_cmd;
    logic [BG_W-1:0]   o_dfi_bg;
    logic [BANK_W-1:0] o_dfi_bank;
    logic [ROW_W-1:0]  o_dfi_row;
    logic [COL_W-1:0]  o_dfi_col;
    logic [7:0]        o_dfi_len;
    logic [TAG_W-1:0]  o_dfi_tag;
    logic              o_dfi_wdata_en;

    logic              dfi_rd_valid;
    logic [63:0]       dfi_rd_data;
    logic [7:0]        dfi_rd_ecc;

    logic              o_wb_valid, o_wb_last, o_wb_err, o_rmw_valid;
    logic [TAG_W-1:0]  o_wb_tag;
    logic [63:0]       o_wb_data;
    logic [1:0]        o_wb_resp;
    logic [7:0]        o_rmw_beat;
    logic              o_rd_take, o_rd_beat_ok, o_rd_flush, o_rd_resync;

    logic              o_ref_tick, o_rfm_active;
    logic [15:0]       o_rfm_auto_cnt, o_tras_clamped_cnt, o_decoy_cnt, o_abo_alert_cnt;
    logic              o_tras_clamped_alert, o_rowpress_alert, o_decoy_active, o_cnt_fault;
    logic [BG_W-1:0]   o_rowpress_bg;
    logic [BANK_W-1:0] o_rowpress_bank;
    logic [ROW_W-1:0]  o_rowpress_row;
    logic [6:1]        o_fault;
    logic              fi_any = 0;
    logic              excuse_r05 = 0;

    ddr5_cmd_engine #(
        .BG_WIDTH      (BG_W),
        .BANK_WIDTH    (BANK_W),
        .ROW_WIDTH     (ROW_W),
        .COL_WIDTH     (COL_W),
        .ROB_PTR_WIDTH (TAG_W),
        // Bảng JEDEC của TB ở 2500 ps (spec_v2 §1.5) truyền tường minh cho cả v1 lẫn v2: baseline chạy cùng hằng số
        .T_RCD(7), .T_RP(7), .T_RAS(13), .T_CCD_L(2), .T_CCD_S(2), .T_CL(8), .T_CWL(9), .T_RRD_S(2), .T_RRD_L(2),
        .T_FAW(10), .T_WR(12), .T_WTR_S(1), .T_WTR_L(4), .T_RTP(3), .T_RFC(118), .T_REFI(1560)
`ifndef QS_BASELINE_V1
        , .T_CCD_L_WR(8), .T_RFM(118), .T_RDV(T_RDV)
`endif
    ) u_dut (
        .clk                  (clk),
        .rst_n                (rst_n),
        .i_cmd_valid          (i_cmd_valid),
        .i_cmd_id             (4'd0),
        .i_cmd_tag            (i_cmd_tag),
        .i_cmd_is_write       (i_cmd_is_write),
        .i_cmd_is_mitigation  (i_cmd_is_mitigation),
        .i_cmd_rmw            (i_cmd_rmw),
        .i_cmd_bg             (i_cmd_bg),
        .i_cmd_bank           (i_cmd_bank),
        .i_cmd_row            (i_cmd_row),
        .i_cmd_col            (i_cmd_col),
        .i_cmd_len            (i_cmd_len),
        .o_bank_free          (o_bank_free),
        .o_engine_mit_only    (o_engine_mit_only),
        .o_abo_active         (o_abo_active),
        .i_dfi_rddata_valid   (dfi_rd_valid),
        .i_dfi_rddata         (dfi_rd_data),
        .o_wb_valid           (o_wb_valid),
        .o_wb_tag             (o_wb_tag),
        .o_wb_data            (o_wb_data),
        .o_wb_resp            (o_wb_resp),
        .o_wb_last            (o_wb_last),
`ifndef QS_BASELINE_V1
        .o_wb_err             (o_wb_err),
        .o_rd_take            (o_rd_take),
        .o_rd_beat_ok         (o_rd_beat_ok),
        .o_rd_flush           (o_rd_flush),
        .o_rd_resync          (o_rd_resync),
        .o_fault              (o_fault),
        .i_decoy_avail        (1'b0),
        .i_decoy_addr         (22'd0),
        .o_decoy_take         (),
        .i_force_rfm          (1'b0),
`endif
        .o_rmw_valid          (o_rmw_valid),
        .o_rmw_beat           (o_rmw_beat),
        .o_dfi_cmd            (o_dfi_cmd),
        .o_dfi_bg             (o_dfi_bg),
        .o_dfi_bank           (o_dfi_bank),
        .o_dfi_row            (o_dfi_row),
        .o_dfi_col            (o_dfi_col),
        .o_dfi_len            (o_dfi_len),
        .o_dfi_tag            (o_dfi_tag),
        .o_ref_tick           (o_ref_tick),
        .o_rfm_active         (o_rfm_active),
        .cfg_raammt_thresh    (8'd160),
        .cfg_tras_max_thresh  (16'd8000),
        .cfg_rowpress_thresh  (16'd5000),
        .o_rfm_auto_cnt       (o_rfm_auto_cnt),
        .o_tras_clamped_alert (o_tras_clamped_alert),
        .o_tras_clamped_cnt   (o_tras_clamped_cnt),
        .o_rowpress_alert     (o_rowpress_alert),
        .o_rowpress_bg        (o_rowpress_bg),
        .o_rowpress_bank      (o_rowpress_bank),
        .o_rowpress_row       (o_rowpress_row),
        .cfg_decoy_en         (1'b0),
        .o_decoy_active       (o_decoy_active),
        .o_decoy_cnt          (o_decoy_cnt),
        .o_cnt_fault          (o_cnt_fault),
        .i_dram_abo_alert     (1'b0),
        .o_abo_alert_cnt      (o_abo_alert_cnt)
    );

    assign o_dfi_wdata_en = 1'b0;

`ifdef QS_BASELINE_V1
    assign o_wb_err      = 1'b0;
    assign o_rd_take     = dfi_rd_valid;
    assign o_rd_beat_ok  = dfi_rd_valid;
    assign o_rd_flush    = 1'b0;
    assign o_rd_resync   = 1'b0;
    assign o_fault       = {5'b0, o_cnt_fault};
`endif

    dram_model #(
        .COL_W (COL_W),
        .RL    (T_RDV),
        .WL    (2)
    ) u_dram (
        .clk          (clk),
        .rst_n        (rst_n),
        .cmd          (o_dfi_cmd),
        .bg           (o_dfi_bg),
        .bank         (o_dfi_bank),
        .row          (o_dfi_row),
        .col          (o_dfi_col),
        .len          (o_dfi_len),
        .wrdata_en    (o_dfi_wdata_en),
        .wrdata       (64'hCAFE_0000_0000_0001),
        .wrdata_mask  (8'hFF),
        .wrdata_ecc   (8'h00),
        .rddata_valid (dfi_rd_valid),
        .rddata       (dfi_rd_data),
        .rddata_ecc   (dfi_rd_ecc)
    );

    dfi_jedec_checker #(
        .TCK_PS       (2500),
        .TB_DFI_WRLAT (2)
    ) u_jchk (
        .clk   (clk),
        .rst_n (rst_n),
        .cmd   (o_dfi_cmd),
        .bg    (o_dfi_bg),
        .bank  (o_dfi_bank),
        .row   (o_dfi_row),
        .len   (o_dfi_len)
    );

    qs_engine_port_chk #(
        .NB    (NB),
        .BG_W  (BG_W),
        .BANK_W(BANK_W),
        .ROW_W (ROW_W),
        .COL_W (COL_W),
        .TAG_W (TAG_W),
        .T_RDV (T_RDV)
    ) u_echk (
        .clk                 (clk),
        .rst_n               (rst_n),
        .en_v2               (EN_V2),
        .fi_any              (fi_any),
        .fi_rd_state         (1'b0),
        .allow_it1           (excuse_r05),
        .i_cmd_valid         (i_cmd_valid),
        .i_cmd_bg            (i_cmd_bg),
        .i_cmd_bank          (i_cmd_bank),
        .i_cmd_len           (i_cmd_len),
        .i_cmd_is_mitigation (i_cmd_is_mitigation),
        .o_bank_free         (o_bank_free),
        .o_engine_mit_only   (o_engine_mit_only),
        .o_abo_active        (o_abo_active),
        .i_dram_abo_alert    (1'b0),
        .i_force_rfm         (1'b0),
        .o_dfi_cmd           (o_dfi_cmd),
        .o_dfi_bg            (o_dfi_bg),
        .o_dfi_bank          (o_dfi_bank),
        .o_dfi_row           (o_dfi_row),
        .o_dfi_col           (o_dfi_col),
        .o_dfi_len           (o_dfi_len),
        .o_dfi_tag           (o_dfi_tag),
        .o_ref_tick          (o_ref_tick),
        .o_rfm_active        (o_rfm_active),
        .o_fault             (o_fault),
        .rd_valid            (dfi_rd_valid),
        .o_rd_take           (o_rd_take),
        .o_rd_beat_ok        (o_rd_beat_ok),
        .o_rd_flush          (o_rd_flush),
        .o_rd_resync         (o_rd_resync),
        .o_wb_valid          (o_wb_valid),
        .o_wb_tag            (o_wb_tag),
        .o_wb_last           (o_wb_last),
        .o_wb_err            (o_wb_err),
        .o_wb_resp           (o_wb_resp),
        .o_rmw_valid         (o_rmw_valid)
    );

    int wr_cmds = 0;
    int free_wait = 0;

    initial begin
        $display("[SEED] 0x51530001");
        rst_n = 0;
        repeat (8) @(posedge clk);
        rst_n = 1;
        repeat (4) @(posedge clk);

        //---------------------------------------------------------------------
        // T-RT01a: Luồng ghi cùng hàng (BG 0, bank 0, row 17'h01234, len 0) trong 25.000 chu kỳ.
        // Arbiter mô hình: cấp lệnh kế 3 chu kỳ sau khi o_bank_free[0] = 1 và !o_engine_mit_only.
        //---------------------------------------------------------------------
        free_wait = 0;
        for (int cyc = 0; cyc < 25000; cyc++) begin
            @(negedge clk);
            if (o_bank_free[0] && !o_engine_mit_only) begin
                if (free_wait >= 2) begin
                    i_cmd_valid         = 1'b1;
                    i_cmd_tag           = TAG_W'(wr_cmds);
                    i_cmd_is_write      = 1'b1;
                    i_cmd_is_mitigation = 1'b0;
                    i_cmd_rmw           = 1'b0;
                    i_cmd_bg            = 3'd0;
                    i_cmd_bank          = 2'd0;
                    i_cmd_row           = 17'h01234;
                    i_cmd_col           = COL_W'((wr_cmds * 8) & 10'h3F8);
                    i_cmd_len           = 8'd0;
                    wr_cmds++;
                    free_wait = 0;
                end else begin
                    i_cmd_valid = 1'b0;
                    free_wait++;
                end
            end else begin
                i_cmd_valid = 1'b0;
                free_wait   = 0;
            end
            @(posedge clk);
        end
        @(negedge clk);
        i_cmd_valid = 1'b0;
        repeat (300) @(posedge clk);

        tb_check(u_jchk.refresh_ok(),
                 $sformatf("a_ref_gap: SA-J21 worst REF gap %0d cyc <= 5*tREFI (%0d cyc)",
                           u_jchk.worst_ref_gap(), 5 * u_jchk.REFI_CYC));
        tb_check(u_jchk.n_ref >= (25000 / u_jchk.REFI_CYC) - 4,
                 $sformatf("a_ref_cnt: SA-R04 issued %0d REFs over 25000 cycles (min %0d)",
                           u_jchk.n_ref, (25000 / u_jchk.REFI_CYC) - 4));
        tb_check(u_jchk.timing_violations() == 0 && u_jchk.viol_ref_open == 0,
                 $sformatf("a_jedec_clean: 0 JEDEC timing/REF-open violations (%0d, %0d)",
                           u_jchk.timing_violations(), u_jchk.viol_ref_open));

`ifndef QS_BASELINE_V1
        //---------------------------------------------------------------------
        // FI-27: Bơm user_blk_q 1 -> 0 giữa lúc đang drain REF (M-01.1)
        //---------------------------------------------------------------------
        for (int s = 0; s < 8; s++) begin
            int w;
            // Đợi sườn lên o_engine_mit_only (bắt đầu drain REF)
            w = 0;
            while (!o_engine_mit_only && w < 3000) begin
                @(negedge clk);
                if (o_bank_free[0] && !o_engine_mit_only) begin
                    i_cmd_valid    = 1'b1;
                    i_cmd_is_write = 1'b1;
                    i_cmd_bg       = 3'd0;
                    i_cmd_bank     = 2'd0;
                    i_cmd_row      = 17'h01234;
                    i_cmd_col      = COL_W'((s * 8) & 10'h3F8);
                    i_cmd_len      = 8'd0;
                end else begin
                    i_cmd_valid = 1'b0;
                end
                @(posedge clk);
                w++;
            end
            @(negedge clk);
            i_cmd_valid = 1'b0;
            if (o_engine_mit_only && `QS_E_USER_BLK_Q(u_dut)) begin
                fi_any     = 1'b1;
                excuse_r05 = 1'b1;
                `QS_E_USER_BLK_Q(u_dut) = 1'b0;
                @(posedge clk);
                #1ps;
                tb_check(o_fault[4] === 1'b1,
                         $sformatf("FI-27 iter %0d: user_blk_q 1->0 detected on o_fault[4] at +1 cycle", s));
                @(negedge clk);
                excuse_r05 = 1'b0;
                // Chờ kết thúc drain
                w = 0;
                while (o_engine_mit_only && w < 300) begin
                    @(posedge clk);
                    w++;
                end
                tb_check(!o_engine_mit_only && w < 220,
                         $sformatf("FI-27 iter %0d: drain completed within DRAIN_MAX (%0d cycles)", s, w));
                fi_any = 1'b0;
            end
        end
`endif

        repeat (2) @(posedge clk);
        u_echk.final_check();
        u_jchk.report("eng_ref_starve");
        u_echk.report("eng_ref_starve");
        tb_check(u_echk.errors() == 0, $sformatf("qs_engine_port_chk zero errors (%0d)", u_echk.errors()));

        $display("[PERF] rd_cmds=0 wr_cmds=%0d n_ref=%0d n_rfm=%0d ref_gap_max_ps=%0d mit_only_cycles=%0d drain_max=%0d fi_count=8 fi_detect_lat_max=1",
                 wr_cmds, u_jchk.n_ref, u_jchk.n_rfm, u_jchk.worst_ref_gap_ps(), u_echk.mit_cycles, u_echk.mit_run_max);
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
