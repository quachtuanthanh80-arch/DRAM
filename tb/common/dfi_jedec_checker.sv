// File:      dfi_jedec_checker.sv
// Chức năng: Checker JEDEC DDR5 trên DFI cho testbench (v2): đo khoảng cách lệnh theo ps với bảng riêng của TB (SA-J01..J21), không đọc tham số DUT.
`timescale 1ns / 1ps

module dfi_jedec_checker
    import ddr5_jedec_bin_pkg::*;
#(
    parameter int BG_COUNT     = 8,
    parameter int BANK_COUNT   = 4,
    parameter int BG_W         = 3,
    parameter int BANK_W       = 2,
    parameter int ROW_W        = 17,
    // Chu kỳ clock thật của TB lái DFI; TB phải truyền cùng giá trị cho DUT (spec_v2 §10.18)
    parameter int TCK_PS       = 2500,
    // Độ trễ WR -> beat ghi đầu mà TB đặt cho DUT và dram_model (Q10)
    parameter int TB_DFI_WRLAT = 9
) (
    input  logic              clk,
    input  logic              rst_n,
    input  logic [2:0]        cmd,
    input  logic [BG_W-1:0]   bg,
    input  logic [BANK_W-1:0] bank,
    input  logic [ROW_W-1:0]  row,
    input  logic [7:0]        len = 8'd0   // số beat - 1 của lệnh CAS
);
    localparam logic [2:0] ACT = 3'b001, PRE = 3'b010, RD = 3'b011, WR = 3'b100, REF = 3'b101, RFM = 3'b110;
    // Chu kỳ tương ứng (để TB tính thời lượng kịch bản): tối đa làm tròn xuống, tối thiểu làm tròn lên
    localparam int REFI_CYC = int'(TREFI_PS / TCK_PS);
    localparam int RFC_CYC  = int'((TRFC_PS + TCK_PS - 1) / TCK_PS);
    localparam int RFM_CYC  = int'((TRFM_PS + TCK_PS - 1) / TCK_PS);
    localparam longint REF_GAP_MAX_PS = longint'(MAX_POSTPONE + 1) * TREFI_PS;
    localparam longint NEVER = -64'sd1000000000;

    longint cyc;
    longint cyc_total;   // không xoá khi reset: khoảng refresh được đo xuyên qua các lần reset DUT của testbench
    longint now_ps;
    bit     open_b  [BG_COUNT][BANK_COUNT];
    bit     masflag [BG_COUNT][BANK_COUNT];
    logic [ROW_W-1:0] open_r [BG_COUNT][BANK_COUNT];
    longint t_act   [BG_COUNT][BANK_COUNT];
    longint t_pre   [BG_COUNT][BANK_COUNT];
    longint t_rd    [BG_COUNT][BANK_COUNT];
    // Mốc beat ghi cuối trên chân DRAM: muộn nhất giữa CWL+BL của bin và độ trễ DFI của TB (bảo thủ cho tWR/tWTR)
    longint t_wend  [BG_COUNT][BANK_COUNT];
    longint t_wend_any, t_wend_bg [BG_COUNT];
    longint t_cas_any, t_cas_bg [BG_COUNT], t_wr_bg [BG_COUNT];
    longint t_act_any, t_act_bg [BG_COUNT];
    longint t_ref, t_rfm, t_last_ref;
    longint act_hist [4];

    int n_act, n_ref, n_rfm, n_rd, n_wr, n_pre;
    int viol_trcd, viol_trp, viol_tras, viol_trasmax, viol_trc, viol_trfc, viol_trfm;
    int viol_cas_closed, viol_act_open, viol_ref_open, viol_refgap;
    int viol_trrd, viol_tfaw, viol_tccd, viol_tccd_wr, viol_twr, viol_trtp, viol_twtr;
    int n_notes;
    longint max_ref_gap;

    // viol_ref_open (SA-J18) và viol_refgap (SA-J21) tách riêng như v1: TB kiểm cả hai cùng timing_violations()
    function automatic int timing_violations();
        return viol_trcd + viol_trp + viol_tras + viol_trasmax + viol_trc + viol_trfc + viol_trfm + viol_cas_closed +
               viol_act_open + viol_trrd + viol_tfaw + viol_tccd + viol_tccd_wr + viol_twr + viol_twtr;
    endfunction

    function automatic int all_violations();
        return timing_violations() + viol_ref_open + viol_refgap;
    endfunction

    // Khoảng refresh tệ nhất tính tới hiện tại (kể cả đoạn từ REF cuối tới bây giờ), theo chu kỳ
    function automatic longint worst_ref_gap();
        longint g;
        g = cyc - t_last_ref;
        return (g > max_ref_gap) ? g : max_ref_gap;
    endfunction

    function automatic longint worst_ref_gap_ps();
        return worst_ref_gap() * longint'(TCK_PS);
    endfunction

    function automatic bit refresh_ok();
        return worst_ref_gap_ps() <= REF_GAP_MAX_PS;
    endfunction

    task automatic report(input string tag);
        $display("  [JEDEC] %s: TCK %0d ps; ACT %0d RD %0d WR %0d PRE %0d REF %0d RFM %0d; worst REF gap %0d cyc = %0d ps (limit %0d ps)",
                 tag, TCK_PS, n_act, n_rd, n_wr, n_pre, n_ref, n_rfm, worst_ref_gap(), worst_ref_gap_ps(), REF_GAP_MAX_PS);
        $display("  [JEDEC] %s: viol tRCD %0d tRP %0d tRAS %0d tRASmax %0d tRC %0d tRFC %0d tRFM %0d CAS-closed %0d ACT-open %0d REF-open %0d tRRD %0d tFAW %0d tCCD %0d tCCD_L_WR %0d tWR/tRTP %0d (tRTP %0d) tWTR %0d REF-gap %0d",
                 tag, viol_trcd, viol_trp, viol_tras, viol_trasmax, viol_trc, viol_trfc, viol_trfm, viol_cas_closed,
                 viol_act_open, viol_ref_open, viol_trrd, viol_tfaw, viol_tccd, viol_tccd_wr, viol_twr, viol_trtp, viol_twtr,
                 viol_refgap);
    endtask

    task automatic note(input string what);
        n_notes++;
        if (n_notes <= 8)
            $display("  [JEDEC-VIOL] t=%0t cyc=%0d %s bg%0d bank%0d row 0x%0h", $time, cyc, what, bg, bank, row);
    endtask

    function automatic longint wr_data_end(input longint t, input logic [7:0] l);
        longint d;
        d = longint'(TB_DFI_WRLAT + int'(l) + 1) * longint'(TCK_PS);
        return t + ((d > TCWL_BL_PS) ? d : TCWL_BL_PS);
    endfunction

    initial begin
        cyc_total   = 0;
        max_ref_gap = 0;
        cyc         = 0;
        t_last_ref  = 0;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if (cyc - t_last_ref > max_ref_gap) max_ref_gap = cyc - t_last_ref;
            cyc = 0;
            t_last_ref = 0;
            t_ref = NEVER;
            t_rfm = NEVER;
            t_act_any = NEVER;
            t_cas_any = NEVER;
            t_wend_any = NEVER;
            for (int k = 0; k < 4; k++) act_hist[k] = NEVER;
            for (int g = 0; g < BG_COUNT; g++) begin
                t_act_bg[g]  = NEVER;
                t_wend_bg[g] = NEVER;
                t_cas_bg[g]  = NEVER;
                t_wr_bg[g]   = NEVER;
                for (int b = 0; b < BANK_COUNT; b++) begin
                    open_b[g][b]  = 0;
                    masflag[g][b] = 0;
                    t_wend[g][b]  = NEVER;
                    t_act[g][b]   = NEVER;
                    t_pre[g][b]   = NEVER;
                    t_rd[g][b]    = NEVER;
                end
            end
        end else begin
            cyc++;
            cyc_total++;
            now_ps = cyc * longint'(TCK_PS);
            // tRAS(max) quét thưa (64 chu kỳ << 35 µs); PRE muộn còn được bắt chính xác tại lệnh PRE
            if (cyc[5:0] == 6'd0)
                for (int g = 0; g < BG_COUNT; g++)
                    for (int b = 0; b < BANK_COUNT; b++)
                        if (open_b[g][b] && !masflag[g][b] && now_ps - t_act[g][b] > TRASMAX_PS) begin
                            masflag[g][b] = 1;
                            viol_trasmax++;
                            note($sformatf("row open longer than tRAS(max) (bg%0d bank%0d)", g, b));
                        end
            case (cmd)
                ACT: begin
                    n_act++;
                    if (open_b[bg][bank])                     begin viol_act_open++; note("ACT to open bank"); end
                    if (now_ps - t_pre[bg][bank] < TRP_PS)    begin viol_trp++;      note("ACT before tRP"); end
                    if (now_ps - t_act[bg][bank] < TRC_PS)    begin viol_trc++;      note("ACT before tRC"); end
                    if (now_ps - t_ref < TRFC_PS)             begin viol_trfc++;     note("ACT before tRFC"); end
                    if (now_ps - t_rfm < TRFM_PS)             begin viol_trfm++;     note("ACT before tRFM"); end
                    // tRRD_L >= tRRD_S nên so ACT bất kỳ với tRRD_S và ACT cùng BG với tRRD_L là đủ
                    if (now_ps - t_act_any < TRRD_S_PS || now_ps - t_act_bg[bg] < TRRD_L_PS) begin
                        viol_trrd++; note("ACT before tRRD");
                    end
                    if (now_ps - act_hist[3] < TFAW_PS)       begin viol_tfaw++;     note("5th ACT inside tFAW"); end
                    act_hist[3] = act_hist[2];
                    act_hist[2] = act_hist[1];
                    act_hist[1] = act_hist[0];
                    act_hist[0] = now_ps;
                    t_act_any    = now_ps;
                    t_act_bg[bg] = now_ps;
                    open_b[bg][bank]  = 1;
                    masflag[bg][bank] = 0;
                    open_r[bg][bank]  = row;
                    t_act[bg][bank]   = now_ps;
                end
                RD, WR: begin
                    if (cmd == RD) n_rd++; else n_wr++;
                    if (!open_b[bg][bank] || open_r[bg][bank] != row) begin viol_cas_closed++; note("CAS to closed/wrong row"); end
                    else if (now_ps - t_act[bg][bank] < TRCD_PS)      begin viol_trcd++;       note("CAS before tRCD"); end
                    if (now_ps - t_cas_any < TCCD_S_PS || now_ps - t_cas_bg[bg] < TCCD_L_PS) begin
                        viol_tccd++; note("CAS before tCCD_S/tCCD_L");
                    end
                    if (cmd == WR && now_ps - t_wr_bg[bg] < TCCD_L_WR_PS) begin viol_tccd_wr++; note("WR before tCCD_L_WR"); end
                    if (cmd == RD && (now_ps < t_wend_any + TWTR_S_PS || now_ps < t_wend_bg[bg] + TWTR_L_PS)) begin
                        viol_twtr++; note("RD before tWTR");
                    end
                    t_cas_any    = now_ps;
                    t_cas_bg[bg] = now_ps;
                    if (cmd == WR) begin
                        t_wr_bg[bg] = now_ps;
                        t_wend[bg][bank] = wr_data_end(now_ps, len);
                        if (t_wend[bg][bank] > t_wend_any)    t_wend_any    = t_wend[bg][bank];
                        if (t_wend[bg][bank] > t_wend_bg[bg]) t_wend_bg[bg] = t_wend[bg][bank];
                    end else begin
                        t_rd[bg][bank] = now_ps;
                    end
                end
                PRE: begin
                    n_pre++;
                    if (open_b[bg][bank]) begin
                        if (now_ps - t_act[bg][bank] < TRAS_PS) begin viol_tras++; note("PRE before tRAS"); end
                        if (now_ps - t_act[bg][bank] > TRASMAX_PS && !masflag[bg][bank]) begin
                            viol_trasmax++; note("PRE after tRAS(max)");
                        end
                        if (now_ps < t_wend[bg][bank] + TWR_PS) begin viol_twr++; note("PRE before tWR"); end
                        if (now_ps - t_rd[bg][bank] < TRTP_PS) begin viol_twr++; viol_trtp++; note("PRE before tRTP"); end
                        t_pre[bg][bank] = now_ps;
                    end
                    open_b[bg][bank] = 0;
                end
                // REFab/RFMab cần mọi bank đã precharge đủ tRP; chỉ REFab tính vào khoảng refresh định kỳ
                REF, RFM: begin
                    bit any_open;
                    if (cmd == REF) n_ref++; else n_rfm++;
                    any_open = 0;
                    for (int g = 0; g < BG_COUNT; g++)
                        for (int b = 0; b < BANK_COUNT; b++)
                            if (open_b[g][b] || now_ps - t_pre[g][b] < TRP_PS) any_open = 1;
                    if (any_open) begin viol_ref_open++; note("REF/RFM with bank open / before tRP"); end
                    if (now_ps - t_ref < TRFC_PS) begin viol_trfc++; note("REF/RFM before tRFC"); end
                    if (now_ps - t_rfm < TRFM_PS) begin viol_trfm++; note("REF/RFM before tRFM"); end
                    if (cmd == REF) begin
                        if ((cyc - t_last_ref) * longint'(TCK_PS) > REF_GAP_MAX_PS) begin
                            viol_refgap++; note($sformatf("REF interval %0d cyc > (MAX_POSTPONE+1) x tREFI", cyc - t_last_ref));
                        end
                        if (cyc - t_last_ref > max_ref_gap) max_ref_gap = cyc - t_last_ref;
                        t_last_ref = cyc;
                        t_ref = now_ps;
                    end else begin
                        t_rfm = now_ps;
                    end
                end
                default: ;
            endcase
        end
    end
endmodule
