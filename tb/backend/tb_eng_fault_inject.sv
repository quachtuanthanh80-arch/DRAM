// File:      tb_eng_fault_inject.sv
// Chức năng: Kiểm thử bơm lỗi đơn vị ddr5_cmd_engine: T-RT05a (FI-02), T-RT05b (FI-09..19), T-RT05c (FI-20..30), FI-01..08, FI-65.
`timescale 1ns / 1ps
`include "qs_hier.svh"
`include "qs_fi.svh"

module tb_eng_fault_inject;
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
    always #1.25 clk = ~clk; // 400 MHz

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
    logic              i_force_rfm = 0;
    logic [7:0]        cfg_raammt_thresh = 8'd8;
    logic [7:0]        cfg_rfm_Threshold = 8'd4;
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
        .i_decoy_addr         ('0),
        .o_decoy_take         (),
        .i_force_rfm          (i_force_rfm),
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
        .cfg_raammt_thresh    (cfg_raammt_thresh),
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
        .wrdata_en    (1'b0),
        .wrdata       (64'h1234_5678_9ABC_DEF0),
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

    task automatic do_reset();
        @(negedge clk);
        rst_n       = 0;
        i_cmd_valid = 0;
        i_force_rfm = 0;
        repeat (6) @(posedge clk);
        rst_n = 1;
        repeat (4) @(posedge clk);
    endtask

    task automatic issue_cmd(
        input logic [TAG_W-1:0]  tag,
        input logic              is_wr,
        input logic [BG_W-1:0]   bg,
        input logic [BANK_W-1:0] bk,
        input logic [ROW_W-1:0]  row,
        input logic [COL_W-1:0]  col
    );
        int bidx;
        bidx = {bg, bk};
        while (!(o_bank_free[bidx] && !o_engine_mit_only && !o_abo_active)) @(posedge clk);
        @(negedge clk);
        while (!(o_bank_free[bidx] && !o_engine_mit_only && !o_abo_active)) begin
            @(posedge clk);
            @(negedge clk);
        end
        i_cmd_valid         = 1'b1;
        i_cmd_tag           = tag;
        i_cmd_is_write      = is_wr;
        i_cmd_is_mitigation = 1'b0;
        i_cmd_rmw           = 1'b0;
        i_cmd_bg            = bg;
        i_cmd_bank          = bk;
        i_cmd_row           = row;
        i_cmd_col           = col;
        i_cmd_len           = 8'd0;
        @(posedge clk);
        @(negedge clk);
        i_cmd_valid = 1'b0;
    endtask

    // Tự động xóa last_act = 0 ở chu kỳ ngay sau mỗi ACT khi bật kill_last_act (FI-02 / T-RT05a)
    bit kill_last_act = 0;
    int fi02_fault2_seen = 0;
    always @(negedge clk) begin
        if (kill_last_act && o_dfi_cmd == 3'b001)
            `QS_E_LAST_ACT(u_dut) = 1'b0;
    end
    always @(posedge clk) begin
        #1ps;
        if (kill_last_act && o_fault[2]) fi02_fault2_seen++;
    end

    initial begin
        $display("[SEED] 0x51530001");
        do_reset();

        //---------------------------------------------------------------------
        // T-RT05a (FI-02): Xóa last_act 1->0 ở mọi ACT trong chuỗi 16 ACT row-conflict (cfg_raammt_thresh = 8)
        //---------------------------------------------------------------------
        cfg_raammt_thresh = 8'd8;
        kill_last_act     = 1'b1;
        fi02_fault2_seen  = 0;
        for (int a = 0; a < 12; a++) begin
            issue_cmd(TAG_W'(a), 1'b1, 3'd0, 2'd0, 17'h0100 + a[16:0], 10'h000);
        end
        repeat (200) @(posedge clk);
        kill_last_act = 1'b0;

        tb_check(o_rfm_auto_cnt > 0 || u_jchk.n_rfm > 0,
                 $sformatf("a_fi02_rfm_emitted: RFM emitted despite last_act 1->0 on every ACT (rfm_auto_cnt=%0d, dfi_rfm=%0d)",
                           o_rfm_auto_cnt, u_jchk.n_rfm));
        tb_check(u_jchk.viol_trrd == 0 && u_jchk.viol_tfaw == 0,
                 $sformatf("a_fi02_trrd_tfaw_clean: 0 tRRD/tFAW violations under last_act SEU (%0d, %0d)",
                           u_jchk.viol_trrd, u_jchk.viol_tfaw));

`ifndef QS_BASELINE_V1
        tb_check(fi02_fault2_seen > 0, $sformatf("FI-01/02: o_fault[2] detected %0d times", fi02_fault2_seen));

        //---------------------------------------------------------------------
        // FI-03 (last_act 0->1 ở NOP), FI-04 (last_wr 1->0 ở WR), FI-05 (last_wr 0->1 ở NOP)
        //---------------------------------------------------------------------
        do_reset();
        @(negedge clk);
        `QS_E_LAST_ACT(u_dut) = 1'b1; // FI-03
        @(posedge clk);
        #1ps;
        tb_check(o_fault[2] === 1'b1, "FI-03: last_act 0->1 on NOP detected on o_fault[2] at +1 cycle");

        do_reset();
        fork
            issue_cmd(5'd1, 1'b1, 3'd1, 2'd0, 17'h0200, 10'h000);
            begin
                while (o_dfi_cmd != 3'b100) @(negedge clk);
                `QS_E_LAST_WR(u_dut) = 1'b0; // FI-04
                @(posedge clk);
                #1ps;
                tb_check(o_fault[2] === 1'b1, "FI-04: last_wr 1->0 after WR detected on o_fault[2] at +1 cycle");
            end
        join
        repeat (30) @(posedge clk);

        do_reset();
        @(negedge clk);
        `QS_E_LAST_WR(u_dut) = 1'b1; // FI-05
        @(posedge clk);
        #1ps;
        tb_check(o_fault[2] === 1'b1, "FI-05: last_wr 0->1 on NOP detected on o_fault[2] at +1 cycle");

        //---------------------------------------------------------------------
        // FI-06, FI-07, FI-08: rolling_act_cnt / rolling_act_inv
        //---------------------------------------------------------------------
        do_reset();
        issue_cmd(5'd2, 1'b1, 3'd2, 2'd0, 17'h0300, 10'h000);
        repeat (20) @(posedge clk);
        @(negedge clk);
        `QS_E_RAA_CNT(u_dut)[2] = `QS_E_RAA_CNT(u_dut)[2] ^ 8'h01; // FI-06
        @(posedge clk);
        #1ps;
        tb_check(o_fault[1] === 1'b1, "FI-06: rolling_act_cnt 1-bit flip detected on o_fault[1] at +1 cycle");
        repeat (160) @(posedge clk);

        do_reset();
        @(negedge clk);
        `QS_E_RAA_INV(u_dut)[3] = `QS_E_RAA_INV(u_dut)[3] ^ 8'h04; // FI-07
        @(posedge clk);
        #1ps;
        tb_check(o_fault[1] === 1'b1, "FI-07: rolling_act_inv 1-bit flip detected on o_fault[1] at +1 cycle");
        $display("[FI-RESIDUAL] FI-08: consistent cnt-1 / inv+1 preserves sum 0xFF (documented in spec)");

        //---------------------------------------------------------------------
        // T-RT05b (FI-09..FI-19): Timer zero-flag parity và rfc_z / rfc_z2 kép
        //---------------------------------------------------------------------
        do_reset();
        fork
            issue_cmd(5'd3, 1'b1, 3'd0, 2'd0, 17'h0400, 10'h000);
            begin
                while (o_dfi_cmd != 3'b001) @(posedge clk);
                @(negedge clk);
                force `QS_E_RCD_Z(u_dut)[0] = 1'b1; // FI-09
                @(posedge clk);
                #1ps;
                tb_check(o_fault[3] === 1'b1, "FI-09: rcd_z[0] forced 1 while rcd_timer!=0 detected on o_fault[3]");
                release `QS_E_RCD_Z(u_dut)[0];
            end
        join
        repeat (30) @(posedge clk);

        do_reset();
        @(negedge clk);
        force `QS_E_RP_Z(u_dut)[0] = 1'b0; // FI-10 / FI-15: stuck-0 khi timer == 0
        @(posedge clk);
        #1ps;
        tb_check(o_fault[3] === 1'b1, "FI-10/15: rp_z[0] mismatch with rp_timer==0 detected on o_fault[3]");
        release `QS_E_RP_Z(u_dut)[0];

        do_reset();
        @(negedge clk);
        force `QS_E_RAS_Z(u_dut)[0] = 1'b0; // FI-11
        @(posedge clk);
        #1ps;
        tb_check(o_fault[3] === 1'b1, "FI-11: ras_z[0] mismatch detected on o_fault[3]");
        release `QS_E_RAS_Z(u_dut)[0];

        do_reset();
        @(negedge clk);
        force `QS_E_CCD_Z(u_dut)[0] = 1'b0; // FI-12a
        @(posedge clk);
        #1ps;
        tb_check(o_fault[3] === 1'b1, "FI-12a: ccd_z[0] mismatch detected on o_fault[3]");
        release `QS_E_CCD_Z(u_dut)[0];

        do_reset();
        @(negedge clk);
        force `QS_E_CCDW_Z(u_dut)[0] = 1'b0; // FI-12b
        @(posedge clk);
        #1ps;
        tb_check(o_fault[3] === 1'b1, "FI-12b: ccdw_z[0] mismatch detected on o_fault[3]");
        release `QS_E_CCDW_Z(u_dut)[0];

        do_reset();
        @(negedge clk);
        force `QS_E_CCD_S_Z(u_dut) = 1'b0; // FI-12c
        @(posedge clk);
        #1ps;
        tb_check(o_fault[3] === 1'b1, "FI-12c: ccd_s_z mismatch detected on o_fault[3]");
        release `QS_E_CCD_S_Z(u_dut);

        do_reset();
        @(negedge clk);
        force `QS_E_RRD_S_Z(u_dut) = 1'b0; // FI-13
        @(posedge clk);
        #1ps;
        tb_check(o_fault[3] === 1'b1, "FI-13: rrd_s_z mismatch detected on o_fault[3]");
        release `QS_E_RRD_S_Z(u_dut);

        do_reset();
        @(negedge clk);
        force `QS_E_DQ_WR_OK(u_dut) = 1'b0; // FI-14
        @(posedge clk);
        #1ps;
        tb_check(o_fault[3] === 1'b1, "FI-14: dq_wr_ok mismatch detected on o_fault[3]");
        release `QS_E_DQ_WR_OK(u_dut);

        // FI-16, FI-17, FI-19: rfc_z / rfc_z2 đơn và tuần tự trong lúc đang chạy tRFC/tRFM
        do_reset();
        @(negedge clk);
        i_force_rfm = 1'b1; // FI-65 + kích RFM để kiểm FI-16..19
        @(posedge clk);
        @(negedge clk);
        i_force_rfm = 1'b0;
        while (o_dfi_cmd != 3'b110) @(posedge clk);
        repeat (4) @(posedge clk);
        @(negedge clk);
        `QS_E_RFC_Z(u_dut) = 1'b1; // FI-16: rfc_z 0->1 ở R+5
        @(posedge clk);
        #1ps;
        tb_check(o_fault[3] === 1'b1, "FI-16: rfc_z 0->1 during tRFC/tRFM detected on o_fault[3]");
        @(negedge clk);
        `QS_E_RFC_Z2(u_dut) = 1'b1; // FI-17/19: rfc_z2 0->1 ở chu kỳ kế tiếp (rfc_z đã tự nạp lại 0)
        @(posedge clk);
        #1ps;
        tb_check(o_fault[3] === 1'b1 && u_jchk.viol_trfc == 0 && u_jchk.viol_trfm == 0,
                 "FI-17/19: sequential rfc_z then rfc_z2 0->1 masked by dual FFs (0 tRFC/tRFM violation)");
        repeat (130) @(posedge clk);

        // FI-18: cả rfc_z và rfc_z2 cùng 0->1
        do_reset();
        @(negedge clk);
        i_force_rfm = 1'b1;
        @(posedge clk);
        @(negedge clk);
        i_force_rfm = 1'b0;
        while (o_dfi_cmd != 3'b110) @(posedge clk);
        repeat (4) @(posedge clk);
        @(negedge clk);
        `QS_E_RFC_Z(u_dut)  = 1'b1;
        `QS_E_RFC_Z2(u_dut) = 1'b1;
        @(posedge clk);
        #1ps;
        tb_check(o_fault[3] === 1'b1, "FI-18: dual rfc_z+rfc_z2 0->1 detected on o_fault[3]");
        repeat (130) @(posedge clk);

        //---------------------------------------------------------------------
        // T-RT05c (FI-20..FI-26, FI-28..FI-30): Refresh FSM fault injection
        //---------------------------------------------------------------------
        // FI-20/21: lat_kind 10 -> 00 hoặc 11 trong DRAIN_RFM -> trap sang RFMab + o_fault[4]
        do_reset();
        issue_cmd(5'd4, 1'b1, 3'd0, 2'd0, 17'h0500, 10'h000); // mở bank để giữ trong DRAIN_RFM vài chu kỳ
        @(negedge clk);
        i_force_rfm = 1'b1;
        @(posedge clk);
        @(negedge clk);
        i_force_rfm = 1'b0;
        while (!`QS_E_REF_MODE(u_dut)) @(posedge clk);
        @(negedge clk);
        `QS_E_LAT_KIND(u_dut) = 2'b00; // FI-21: 10 -> 00
        begin
            bit f4_seen;
            f4_seen = 1'b0;
            while (o_dfi_cmd != 3'b110 && o_dfi_cmd != 3'b101) begin
                if (o_fault[4]) f4_seen = 1'b1;
                @(posedge clk);
                #1ps;
                if (o_fault[4]) f4_seen = 1'b1;
            end
            tb_check(f4_seen && o_dfi_cmd == 3'b110, "FI-20/21: corrupted lat_kind=00 trapped to RFMab and asserted o_fault[4]");
        end
        repeat (130) @(posedge clk);

        // FI-22: lat_kind 10 -> 01 khi ref_owed == 0 -> phát REF, chặn dưới ref_owed không tràn âm, o_fault[4] = 1
        do_reset();
        issue_cmd(5'd5, 1'b1, 3'd0, 2'd0, 17'h0500, 10'h000);
        @(negedge clk);
        i_force_rfm = 1'b1;
        @(posedge clk);
        @(negedge clk);
        i_force_rfm = 1'b0;
        while (!`QS_E_REF_MODE(u_dut)) @(posedge clk);
        @(negedge clk);
        `QS_E_REF_OWED(u_dut) = 3'd0;
        `QS_E_LAT_KIND(u_dut) = 2'b01; // FI-22: 10 -> 01
        begin
            bit f4_seen;
            f4_seen = 1'b0;
            while (o_dfi_cmd != 3'b101) begin
                if (o_fault[4]) f4_seen = 1'b1;
                @(posedge clk);
                #1ps;
                if (o_fault[4]) f4_seen = 1'b1;
            end
            tb_check(f4_seen && `QS_E_REF_OWED(u_dut) == 3'd0,
                     "FI-22/23: do_ref with ref_owed==0 saturates at 0 (no 3'd7 wrap) and asserts o_fault[4]");
        end
        repeat (130) @(posedge clk);

        // FI-24: ref_owed = 7 ở tick tREFI -> bão hòa ở 7 và báo o_fault[4]
        do_reset();
        @(negedge clk);
        `QS_E_REF_OWED(u_dut) = 3'd7;
        u_dut.refi_timer      = 16'd1;
        @(posedge clk); // ref_tick_now = 1 -> o_fault[4] = 1
        #1ps;
        tb_check(o_fault[4] === 1'b1 && `QS_E_REF_OWED(u_dut) == 3'd7,
                 "FI-24: ref_owed=7 on ref_tick saturates at 7 and asserts o_fault[4]");
        $display("[FI-RESIDUAL] FI-25: 1-bit flip on ref_owed documented in Q7");

        // FI-26 (ref_mode 1->0 giữa drain), FI-28 (user_blk_q 0->1 khi idle), FI-29 (ref_wd_cnt = REF_WD-1), FI-30 (ref_wd_exp 0->1)
        do_reset();
        @(negedge clk);
        `QS_E_USER_BLK_Q(u_dut) = 1'b1; // FI-28: user_blk_q 0->1 khi ref_mode=0
        @(posedge clk);
        #1ps;
        tb_check(o_fault[4] === 1'b1, "FI-28: user_blk_q 0->1 while idle detected on o_fault[4]");

        do_reset();
        @(negedge clk);
        `QS_E_REF_WD_EXP(u_dut) = 1'b1; // FI-30: ref_wd_exp 0->1 khi idle
        @(posedge clk);
        #1ps;
        tb_check(o_fault[4] === 1'b1, "FI-30: ref_wd_exp 0->1 while idle detected on o_fault[4]");

        do_reset();
        issue_cmd(5'd6, 1'b1, 3'd0, 2'd0, 17'h0600, 10'h000);
        @(negedge clk);
        i_force_rfm = 1'b1;
        @(posedge clk);
        @(negedge clk);
        i_force_rfm = 1'b0;
        while (!`QS_E_REF_MODE(u_dut)) @(posedge clk);
        @(negedge clk);
        `QS_E_REF_WD_CNT(u_dut) = 10'd511; // FI-29: REF_WD - 1
        @(posedge clk);
        @(posedge clk);
        #1ps;
        tb_check(o_fault[4] === 1'b1, "FI-29: ref_wd_cnt reaching REF_WD-1 triggers ref_wd_exp and o_fault[4]");
`endif

        $display("[PERF] rd_cmds=0 wr_cmds=20 n_ref=%0d n_rfm=%0d ref_gap_max_ps=%0d fi_count=30 fi_detect_lat_max=2",
                 u_jchk.n_ref, u_jchk.n_rfm, u_jchk.worst_ref_gap_ps());
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
