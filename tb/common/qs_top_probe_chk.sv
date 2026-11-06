// File:      qs_top_probe_chk.sv
// Chức năng: Checker hộp xám có kiểm soát trên các tín hiệu nội bộ có tên trong spec_v2 §4.2/§8 của axi_ddr5_mc_top: SA-C01..C10, SA-D12, SA-R07, SA-F02..F06, SA-F10.
`timescale 1ns / 1ps
`include "qs_hier.svh"

module qs_top_probe_chk #(
    parameter int BG_COUNT      = 8,
    parameter int BANK_COUNT    = 4,
    parameter int BG_QDEPTH     = 8,
    parameter int ROB_DEPTH     = 16,
    parameter int MAX_POSTPONE  = 4,
    parameter int N_CFG         = 4096
) (
    input  logic clk,
    input  logic rst_n,
    input  logic en_v2      = 1'b1,
    input  logic fi_any     = 1'b0,
    input  logic excuse_f02 = 1'b0, // miễn SA-F02 ở chu kỳ bơm trực tiếp vào fault_sticky (FI-61)
    input  logic excuse_f05 = 1'b0  // miễn SA-F05 ở chu kỳ bơm trực tiếp vào o_glitch_alert (FI-60)
);
    localparam int NB    = BG_COUNT * BANK_COUNT;
    localparam int BG_W  = $clog2(BG_COUNT);
    localparam int TAG_W = $clog2(ROB_DEPTH);

    longint cyc;
    int     cfg_pend_run, cfg_pend_max;
    int     max_bg_sum_seen;
    int     dual_rw_same_bg_sat7_cnt;

    logic [69:0] prev_map_cfg;
    logic        prev_map_idle;
    logic        prev_cfg_pend;
    logic [8:0]  prev_fault_cause;
    logic [8:0]  prev_fault_vec;
    logic        prev_fault_clr;
    logic        resync_d1;

    logic [BG_W-1:0] rd_tag_bg [ROB_DEPTH];
    logic [BG_W-1:0] wr_tag_bg [ROB_DEPTH];
    bit              rd_tag_v  [ROB_DEPTH];
    bit              wr_tag_v  [ROB_DEPTH];

    int err_c01, err_c02, err_c03, err_c04, err_c05, err_c06, err_c07, err_c08, err_c09, err_c10;
    int err_d12, err_r07, err_f02, err_f03, err_f04, err_f05, err_f06, err_f10;

    function automatic int errors();
        return err_c01 + err_c02 + err_c03 + err_c04 + err_c05 + err_c06 + err_c07 + err_c08 + err_c09 + err_c10 +
               err_d12 + err_r07 + err_f02 + err_f03 + err_f04 + err_f05 + err_f06 + err_f10;
    endfunction

    task automatic bad(inout int cnt, input string what);
        cnt++;
        if (errors() <= 12) $display("[TOPCHK-ERR] t=%0t cyc=%0d %s", $time, cyc, what);
    endtask

    task automatic report(input string tag);
        $display("  [TOPCHK] %s: max_bg_credit_sum=%0d dual_rw_same_bg(sum>=7)=%0d cfg_pend_max=%0d",
                 tag, max_bg_sum_seen, dual_rw_same_bg_sat7_cnt, cfg_pend_max);
        $display("  [TOPCHK] %s: err C01..C10=%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d/%0d D12=%0d R07=%0d F02..F06,F10=%0d/%0d/%0d/%0d/%0d/%0d",
                 tag, err_c01, err_c02, err_c03, err_c04, err_c05, err_c06, err_c07, err_c08, err_c09, err_c10,
                 err_d12, err_r07, err_f02, err_f03, err_f04, err_f05, err_f06, err_f10);
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (rst_n !== 1'b1) begin
            cyc                      = 0;
            cfg_pend_run             = 0;
            prev_map_cfg             = {1'b1, 1'b0, 2'b00, 2'b00, 64'hA5A5_5A5A_0123_4567};
            prev_map_idle            = 1'b1;
            prev_cfg_pend            = 1'b0;
            prev_fault_cause         = '0;
            prev_fault_vec           = '0;
            prev_fault_clr           = 1'b0;
            resync_d1                = 1'b0;
            for (int t = 0; t < ROB_DEPTH; t++) begin
                rd_tag_v[t] = 1'b0;
                wr_tag_v[t] = 1'b0;
            end
        end else if (en_v2) begin
            cyc++;

            // SA-C01: hàng đợi QoS không bao giờ bỏ lệnh khi không bơm lỗi
            if (!fi_any && (`QS_T_Q_IN_VALID(dut) && !`QS_T_SDC_CMD_READY(dut)))
                bad(err_c01, "q_in_valid asserted when sdc_cmd_ready=0");
            if (!fi_any && dut.o_fault_cause[8])
                bad(err_c01, "o_fault_cause[8] (credit_fault) asserted without fault injection");

            // SA-C02 & SA-C03: tổng tín dụng mỗi BG <= BG_QDEPTH, từng bank <= BG_QDEPTH
            for (int g = 0; g < BG_COUNT; g++) begin
                int s;
                s = 0;
                for (int b = 0; b < BANK_COUNT; b++) begin
                    int c;
                    c = int'(`QS_T_BK_CNT(dut)[g * BANK_COUNT + b]);
                    if (!fi_any && c > BG_QDEPTH)
                        bad(err_c03, $sformatf("bk_cnt[%0d]=%0d > BG_QDEPTH", g * BANK_COUNT + b, c));
                    s += c;
                end
                if (s > max_bg_sum_seen) max_bg_sum_seen = s;
                if (!fi_any && s > BG_QDEPTH)
                    bad(err_c02, $sformatf("BG %0d credit sum %0d > BG_QDEPTH (%0d)", g, s, BG_QDEPTH));

                if (dut.iq_sel_fire && dut.wr_fire && (int'(dut.iq_sel_bg) == g) && (int'(dut.wcmd_bg) == g) && (s >= 7))
                    dual_rw_same_bg_sat7_cnt++;
            end

            // SA-C04: đọc + ghi cùng BG cùng chu kỳ
            if (!fi_any && dut.iq_sel_fire && dut.wr_fire && (dut.iq_sel_bg == dut.wcmd_bg)) begin
                if (dut.fe_rd_req_valid || !dut.iq_bg_pend[dut.wcmd_bg] ||
                    !`QS_T_WBANK_CREDIT(dut)[{dut.wcmd_bg, dut.wcmd_bank}]) begin
                    bad(err_c04, "simultaneous RD+WR same BG violated M-02.4/5 conditions");
                end
            end

            // SA-C05: wbank_credit chặt hơn hoặc bằng bank_credit
            if (!fi_any && ((`QS_T_WBANK_CREDIT(dut) & ~`QS_T_BANK_CREDIT(dut)) != '0))
                bad(err_c05, "wbank_credit=1 while bank_credit=0");

            // SA-C06: cấu hình ánh xạ chỉ đổi khi đường ống đã idle
            if (!fi_any && (`QS_T_MAP_CFG_Q(dut) !== prev_map_cfg)) begin
                if (!prev_map_idle)
                    bad(err_c06, "map_cfg_q changed while map_idle_q was 0 in previous cycle");
            end
            prev_map_cfg  = `QS_T_MAP_CFG_Q(dut);
            prev_map_idle = `QS_T_MAP_IDLE_Q(dut);
            prev_cfg_pend = `QS_T_CFG_PEND_Q(dut);

            // SA-C07: chặn nhận AR vào IQ khi đang chờ đổi cấu hình
            if (!fi_any && `QS_T_CFG_PEND_Q(dut) && (`QS_TOP_IQ(dut).i_valid && `QS_TOP_IQ(dut).o_ready))
                bad(err_c07, "RD issue queue accepted new AR while cfg_pend_q=1");

            // SA-C08: BG lúc trừ tín dụng == BG lúc trả tín dụng
            if (dut.fe_rd_req_valid && dut.fe_rd_req_ready) begin
                rd_tag_bg[dut.rob_alloc_tag] = dut.fe_rd_req_bg;
                rd_tag_v[dut.rob_alloc_tag]  = 1'b1;
            end
            if (dut.wr_fire) begin
                wr_tag_bg[dut.wcmd_tag] = dut.wcmd_bg;
                wr_tag_v[dut.wcmd_tag]  = 1'b1;
            end
            if (!fi_any && `QS_T_CS_VALID(dut) && !`QS_T_CS_IS_MIT(dut)) begin
                if (dut.cs_is_write) begin
                    if (wr_tag_v[dut.cs_id[TAG_W-1:0]] && (`QS_T_CS_BG(dut) !== wr_tag_bg[dut.cs_id[TAG_W-1:0]]))
                        bad(err_c08, $sformatf("WR tag %0d released BG %0d != charged BG %0d",
                                               dut.cs_id[TAG_W-1:0], `QS_T_CS_BG(dut), wr_tag_bg[dut.cs_id[TAG_W-1:0]]));
                end else begin
                    if (rd_tag_v[dut.cs_id[TAG_W-1:0]] && (`QS_T_CS_BG(dut) !== rd_tag_bg[dut.cs_id[TAG_W-1:0]]))
                        bad(err_c08, $sformatf("RD tag %0d released BG %0d != charged BG %0d",
                                               dut.cs_id[TAG_W-1:0], `QS_T_CS_BG(dut), rd_tag_bg[dut.cs_id[TAG_W-1:0]]));
                end
            end

            // SA-C09: ROB không tràn
            if (`QS_T_ROB_USED(dut) > ROB_DEPTH)
                bad(err_c09, $sformatf("rob_used=%0d > ROB_DEPTH (%0d)", `QS_T_ROB_USED(dut), ROB_DEPTH));

            // SA-C10: thời gian chờ cấu hình có cận
            if (`QS_T_CFG_PEND_Q(dut)) begin
                cfg_pend_run++;
                if (cfg_pend_run > cfg_pend_max) cfg_pend_max = cfg_pend_run;
                if (cfg_pend_run == N_CFG + 1)
                    bad(err_c10, $sformatf("cfg_pend_q stuck > N_CFG (%0d) cycles", N_CFG));
            end else begin
                cfg_pend_run = 0;
            end

            // SA-D12: sau o_rd_resync con trỏ FIFO beat đọc được đặt lại đồng bộ
            if (resync_d1 && (`QS_TOP_ENG(dut).o_dfi_cmd != 3'd3)) begin
                if ((`QS_T_KF_WR(dut) !== `QS_T_KF_RD(dut)) || (`QS_T_RA_WR(dut) !== `QS_T_RA_RD(dut)))
                    bad(err_d12, "kf/ra FIFO pointers not equal after o_rd_resync");
            end
            resync_d1 = `QS_TOP_ENG(dut).o_rd_resync;

            // SA-R07: biên ref_owed
            if (!fi_any && (`QS_E_REF_OWED(`QS_TOP_ENG(dut)) > 3'(MAX_POSTPONE + 1)))
                bad(err_r07, $sformatf("ref_owed=%0d > MAX_POSTPONE+1", `QS_E_REF_OWED(`QS_TOP_ENG(dut))));

            // SA-F02..F06: bộ gom lỗi sticky và cảnh báo
            if (cyc > 1) begin
                if (!prev_fault_clr && !excuse_f02) begin
                    if ((dut.o_fault_cause & prev_fault_cause) !== prev_fault_cause)
                        bad(err_f02, $sformatf("o_fault_cause lost sticky bits without cfg_fault_clr: prev=0x%03h now=0x%03h",
                                               prev_fault_cause, dut.o_fault_cause));
                end
                if (!excuse_f02) begin
                    if ((dut.o_fault_cause & prev_fault_vec) !== prev_fault_vec)
                        bad(err_f03, $sformatf("new fault_vec=0x%03h not captured into o_fault_cause=0x%03h",
                                               prev_fault_vec, dut.o_fault_cause));
                end
                if (prev_fault_clr && !excuse_f02) begin
                    if ((dut.o_fault_cause & ~prev_fault_vec) !== 9'd0)
                        bad(err_f04, $sformatf("cfg_fault_clr did not clear inactive fault bits: vec=0x%03h cause=0x%03h",
                                               prev_fault_vec, dut.o_fault_cause));
                end
            end
            if (!excuse_f05 && (dut.o_glitch_alert !== (|dut.o_fault_cause)))
                bad(err_f05, $sformatf("o_glitch_alert=%0b != |o_fault_cause (0x%03h)",
                                       dut.o_glitch_alert, dut.o_fault_cause));
            if (!fi_any && (dut.o_fault_cause !== 9'd0 || dut.o_glitch_alert !== 1'b0))
                bad(err_f06, $sformatf("spurious fault/alert without FI: cause=0x%03h alert=%0b",
                                       dut.o_fault_cause, dut.o_glitch_alert));

            // SA-F10: bất biến DRM khi không bơm lỗi
            if (!fi_any && (`QS_TOP_DRM(dut).o_drm_fault || (`QS_D_BLKP_A(`QS_TOP_DRM(dut)) !== `QS_D_BLKP_B(`QS_TOP_DRM(dut)))))
                bad(err_f10, "DRM fault or blkp mismatch without fault injection");

            prev_fault_cause = dut.o_fault_cause;
            prev_fault_vec   = dut.fault_vec;
            prev_fault_clr   = dut.cfg_fault_clr;
        end
    end
endmodule
