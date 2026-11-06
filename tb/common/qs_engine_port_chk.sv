// File:      qs_engine_port_chk.sv
// Chức năng: Checker tuần tự trên cổng ddr5_cmd_engine (thay SVA concurrent cho Icarus): SA-P05..P08, SA-R01/R02/R05/R08, SA-F12/F13, F06 mức engine; kèm mô hình beat đọc.
`timescale 1ns / 1ps

module qs_engine_port_chk #(
    parameter int NB        = 32,
    parameter int BG_W      = 3,
    parameter int BANK_W    = 2,
    parameter int ROW_W     = 17,
    parameter int COL_W     = 10,
    parameter int TAG_W     = 5,
    parameter int T_RDV     = 9,
    parameter int REF_WD    = 512,
    parameter int DRAIN_MAX = 555,
    parameter int N_SLOT    = 1024,
    parameter int K_RFM     = 1536,
    parameter int D2_MAX    = 145,
    parameter int FLUSH_MAX = 160
) (
    input  logic                clk,
    input  logic                rst_n,
    input  logic                en_v2,         // 0 = RTL v1: bỏ các luật cần cổng/ngữ nghĩa v2
    input  logic                fi_any,        // đã có bơm lỗi trong lần chạy: bỏ các luật "không báo động giả"
    input  logic                fi_rd_state,   // đang bơm vào rd_st/exp_v: mô hình beat không còn so khớp
    input  logic                allow_it1,     // TB cố ý vi phạm I-T1 (FI-64)
    input  logic                i_cmd_valid,
    input  logic [BG_W-1:0]     i_cmd_bg,
    input  logic [BANK_W-1:0]   i_cmd_bank,
    input  logic [7:0]          i_cmd_len,
    input  logic                i_cmd_is_mitigation,
    input  logic [NB-1:0]       o_bank_free,
    input  logic                o_engine_mit_only,
    input  logic                o_abo_active,
    input  logic                i_dram_abo_alert,
    input  logic                i_force_rfm,
    input  logic [2:0]          o_dfi_cmd,
    input  logic [BG_W-1:0]     o_dfi_bg,
    input  logic [BANK_W-1:0]   o_dfi_bank,
    input  logic [ROW_W-1:0]    o_dfi_row,
    input  logic [COL_W-1:0]    o_dfi_col,
    input  logic [7:0]          o_dfi_len,
    input  logic [TAG_W-1:0]    o_dfi_tag,
    input  logic                o_ref_tick,
    input  logic                o_rfm_active,
    input  logic [6:1]          o_fault,
    input  logic                rd_valid,
    input  logic                o_rd_take,
    input  logic                o_rd_beat_ok,
    input  logic                o_rd_flush,
    input  logic                o_rd_resync,
    input  logic                o_wb_valid,
    input  logic [TAG_W-1:0]    o_wb_tag,
    input  logic                o_wb_last,
    input  logic                o_wb_err,
    input  logic [1:0]          o_wb_resp,
    input  logic                o_rmw_valid
);
    localparam logic [2:0] CMD_REF = 3'd5, CMD_RFM = 3'd6, CMD_RD = 3'd3, CMD_WR = 3'd4;

    qs_rd_beat_model #(.T_RDV(T_RDV), .TAG_W(TAG_W), .BG_W(BG_W), .BANK_W(BANK_W), .ROW_W(ROW_W), .COL_W(COL_W),
                       .D2_MAX(D2_MAX), .FLUSH_MAX(FLUSH_MAX)) u_model (
        .clk(clk), .rst_n(rst_n), .en(en_v2), .excuse(fi_rd_state),
        .dfi_cmd(o_dfi_cmd), .dfi_len(o_dfi_len), .dfi_tag(o_dfi_tag), .dfi_bg(o_dfi_bg), .dfi_bank(o_dfi_bank),
        .dfi_row(o_dfi_row), .dfi_col(o_dfi_col),
        .rd_valid(rd_valid), .rd_take(o_rd_take), .rd_beat_ok(o_rd_beat_ok), .rd_flush(o_rd_flush),
        .rd_resync(o_rd_resync), .wb_valid(o_wb_valid), .wb_tag(o_wb_tag), .wb_last(o_wb_last), .wb_err(o_wb_err),
        .wb_resp(o_wb_resp), .rmw_valid(o_rmw_valid), .fault5(o_fault[5]),
        .o_head_valid(), .o_head_tag(), .o_head_len(), .o_head_k(), .o_head_bg(), .o_head_bank(), .o_head_row(),
        .o_head_col(), .o_exp0(), .o_pend()
    );

    longint cyc;
    int busy_run [NB];
    int mit_run, mit_run_max, mit_cycles;
    bit abo_seen_run, prev_mit;
    int n_ref, n_rfm, n_tick, n_rfm_rise;
    bit prev_rfm_active;
    longint rfm_deadline = -1;
    bit prev_f12;
    int fault_seen [7];
    int err_p05, err_p06, err_p07, err_p08, err_r01, err_r02, err_r05, err_r08, err_f12, err_f13, err_f06;
    int slot_busy_max;

    function automatic int errors();
        return err_p05 + err_p06 + err_p07 + err_p08 + err_r01 + err_r02 + err_r05 + err_r08 + err_f12 + err_f13 + err_f06 +
               u_model.errors();
    endfunction

    task automatic bad(inout int cnt, input string what);
        cnt++;
        if (errors() <= 12) $display("[ENGCHK-ERR] t=%0t cyc=%0d %s", $time, cyc, what);
    endtask

    // Kiểm tra cuối test (SA-R08 dạng bằng nhau sau khi hết lưu lượng, SA-F12 còn hạn chưa đến)
    task automatic final_check();
        if (n_tick != n_ref) bad(err_r08, $sformatf("o_ref_tick pulses %0d != REF on DFI %0d", n_tick, n_ref));
        if (en_v2 && rfm_deadline >= 0) bad(err_f12, "RFM still owed at end of test");
    endtask

    task automatic report(input string tag);
        $display("  [ENGCHK] %s: REF %0d tick %0d RFM %0d rfm_active rises %0d; mit_only cycles %0d max run %0d; slot busy max %0d; faults seen [1..6] %0d %0d %0d %0d %0d %0d",
                 tag, n_ref, n_tick, n_rfm, n_rfm_rise, mit_cycles, mit_run_max, slot_busy_max,
                 fault_seen[1], fault_seen[2], fault_seen[3], fault_seen[4], fault_seen[5], fault_seen[6]);
        $display("  [ENGCHK] %s: err P05 %0d P06 %0d P07 %0d P08 %0d R01 %0d R02 %0d R05 %0d R08 %0d F12 %0d F13 %0d F06 %0d",
                 tag, err_p05, err_p06, err_p07, err_p08, err_r01, err_r02, err_r05, err_r08, err_f12, err_f13, err_f06);
        u_model.report(tag);
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (rst_n !== 1'b1) begin
            cyc = 0;
            for (int b = 0; b < NB; b++) busy_run[b] = 0;
            mit_run = 0;
            abo_seen_run = 0;
            prev_mit = 0;
            prev_rfm_active = 0;
            rfm_deadline = -1;
            prev_f12 = 0;
        end else begin
            bit f12_now;
            cyc++;
            // SA-P05: I-T1, lệnh chỉ tới bank có slot trống; SA-P06/P07: độ dài CAS và mã DFI hợp lệ
            if (i_cmd_valid && !o_bank_free[{i_cmd_bg, i_cmd_bank}] && !allow_it1)
                bad(err_p05, $sformatf("i_cmd_valid to busy bank bg%0d bank%0d", i_cmd_bg, i_cmd_bank));
            if (i_cmd_valid && i_cmd_len >= 8) bad(err_p06, $sformatf("i_cmd_len %0d >= 8", i_cmd_len));
            if (o_dfi_cmd == 3'b111) bad(err_p07, "o_dfi_cmd = 3'b111");
            if ((o_dfi_cmd == CMD_RD || o_dfi_cmd == CMD_WR) && o_dfi_len >= 8) bad(err_p07, "CAS with o_dfi_len >= 8");
            // SA-P08: slot bank không kẹt
            for (int b = 0; b < NB; b++) begin
                busy_run[b] = o_bank_free[b] ? 0 : busy_run[b] + 1;
                if (busy_run[b] > slot_busy_max) slot_busy_max = busy_run[b];
                if (busy_run[b] == N_SLOT + 1) bad(err_p08, $sformatf("bank slot %0d busy > %0d cycles", b, N_SLOT));
            end
            // SA-R01: khi không có ABO, o_engine_mit_only chính là ref_mode; thời gian drain có cận
            if (i_dram_abo_alert || o_abo_active) abo_seen_run = 1;
            if (o_engine_mit_only) mit_cycles++;
            if (o_engine_mit_only && !abo_seen_run) mit_run++;
            else begin
                mit_run = 0;
                if (!o_engine_mit_only) abo_seen_run = 0;
            end
            if (mit_run > mit_run_max) mit_run_max = mit_run;
            if (en_v2) begin
                if (!fi_any && mit_run == REF_WD + 1) bad(err_r01, $sformatf("ref_mode drain > REF_WD (%0d)", REF_WD));
                if (fi_any && mit_run == DRAIN_MAX + 1) bad(err_r01, $sformatf("ref_mode drain > DRAIN_MAX (%0d) under FI", DRAIN_MAX));
                // SA-R02 / SA-F13 / F06 mức engine: không báo động giả khi không bơm lỗi
                if (!fi_any && o_fault[4]) bad(err_r02, "o_fault[4] without fault injection");
                if (!fi_any && !allow_it1 && o_fault[6]) bad(err_f13, "o_fault[6] (dropped command) without fault injection");
                if (!fi_any && (o_fault[1] || o_fault[2] || o_fault[3] || o_fault[5])) bad(err_f06, $sformatf("o_fault=%b without fault injection", o_fault));
                // SA-R05: mit_only ở chu kỳ trước -> không lệnh người dùng mới
                if (prev_mit && i_cmd_valid && !i_cmd_is_mitigation && !fi_any) bad(err_r05, "user command presented one cycle after o_engine_mit_only");
            end
            for (int k = 1; k <= 6; k++) if (o_fault[k]) fault_seen[k]++;
            // SA-R08: xung báo khớp lệnh (lệch tức thời <= 1)
            if (o_dfi_cmd == CMD_REF) n_ref++;
            if (o_dfi_cmd == CMD_RFM) n_rfm++;
            if (o_ref_tick) n_tick++;
            if (o_rfm_active && !prev_rfm_active) n_rfm_rise++;
            if (n_tick - n_ref > 1 || n_ref - n_tick > 1) bad(err_r08, $sformatf("o_ref_tick count %0d vs REF %0d", n_tick, n_ref));
            // SA-F12: lỗi RAA/sự kiện hoặc DRM ép -> RFM trong K_RFM
            f12_now = o_fault[1] || o_fault[2];
            if (en_v2 && ((f12_now && !prev_f12) || i_force_rfm) && rfm_deadline < 0) rfm_deadline = cyc + K_RFM;
            if (o_dfi_cmd == CMD_RFM) rfm_deadline = -1;
            if (en_v2 && rfm_deadline >= 0 && cyc > rfm_deadline) begin
                bad(err_f12, $sformatf("no RFM within %0d cycles of RAA/event fault or i_force_rfm", K_RFM));
                rfm_deadline = -1;
            end
            prev_f12 = f12_now;
            prev_mit = o_engine_mit_only;
            prev_rfm_active = o_rfm_active;
        end
    end
endmodule
