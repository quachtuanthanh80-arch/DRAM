// File:      dfi_jedec_checker_cyc.sv
// Chức năng: Bản đóng băng của checker JEDEC v1 (theo chu kỳ, tham số trùng DUT v1): chỉ để chứng minh điểm đo P0 hợp lệ theo giả định của chính nó (benchmark H-3).
`timescale 1ns / 1ps

module dfi_jedec_checker_cyc #(
    parameter int BG_COUNT   = 8,
    parameter int BANK_COUNT = 4,
    parameter int BG_W       = 3,
    parameter int BANK_W     = 2,
    parameter int ROW_W      = 17,
    parameter int T_RCD      = 6,
    parameter int T_RP       = 6,
    parameter int T_RAS      = 14,
    parameter int T_RRD_S    = 2,
    parameter int T_RRD_L    = 3,
    parameter int T_FAW      = 8,
    parameter int T_WR       = 8,
    parameter int T_CWL      = 1,     // WR -> beat dữ liệu đầu (độ trễ ghi DFI)
    parameter int T_WTR_S    = 2,     // cuối dữ liệu ghi -> RD khác BG
    parameter int T_WTR_L    = 3,     // cuối dữ liệu ghi -> RD cùng BG
    parameter int T_RTP      = 2,
    parameter int T_RFC      = 74,    // DDR5 16Gb tRFC1 295 ns @ 250 MHz
    parameter int T_REFI     = 975,   // DDR5 tREFI 3.9 us @ 250 MHz
    parameter int MAX_POSTPONE = 4    // JEDEC cho phép hoãn tối đa 4 REF -> khoảng tối đa 5 x tREFI
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

    longint cyc;
    longint cyc_total;   // không xoá khi reset: khoảng refresh được đo xuyên qua các lần reset DUT của testbench
    bit     open_b  [BG_COUNT][BANK_COUNT];
    logic [ROW_W-1:0] open_r [BG_COUNT][BANK_COUNT];
    longint t_act   [BG_COUNT][BANK_COUNT];
    longint t_pre   [BG_COUNT][BANK_COUNT];
    longint t_ref, t_last_ref;
    longint t_cas  [BG_COUNT][BANK_COUNT];
    bit     cas_wr [BG_COUNT][BANK_COUNT];
    longint t_act_any, t_act_bg [BG_COUNT];
    // JEDEC đo tWR và tWTR từ beat dữ liệu ghi cuối (WR + CWL + BL), không từ lệnh WR
    longint t_wend [BG_COUNT][BANK_COUNT];
    longint t_wend_any, t_wend_bg [BG_COUNT];
    longint act_hist [4];

    int n_act, n_ref, n_rfm;
    int viol_trcd, viol_trp, viol_tras, viol_trfc, viol_cas_closed, viol_act_open, viol_ref_open;
    int viol_trrd, viol_tfaw, viol_twr, viol_twtr;
    longint max_ref_gap;

    function automatic int timing_violations();
        return viol_trcd + viol_trp + viol_tras + viol_trfc + viol_cas_closed + viol_act_open + viol_trrd + viol_tfaw + viol_twr +
               viol_twtr;
    endfunction

    // Khoảng refresh tệ nhất tính tới hiện tại (kể cả đoạn từ REF cuối tới bây giờ).
    function automatic longint worst_ref_gap();
        longint g;
        g = cyc - t_last_ref;
        return (g > max_ref_gap) ? g : max_ref_gap;
    endfunction

    function automatic bit refresh_ok();
        return worst_ref_gap() <= longint'((MAX_POSTPONE + 1) * T_REFI);
    endfunction

    task automatic report(input string tag);
        $display("  [JEDEC] %s: ACT %0d, REF %0d, RFM %0d, worst REF gap %0d cyc (limit %0d); viol tRCD %0d tRP %0d tRAS %0d tRFC %0d CAS-closed %0d ACT-open %0d REF-open %0d tRRD %0d tFAW %0d tWR/tRTP %0d tWTR %0d",
                 tag, n_act, n_ref, n_rfm, worst_ref_gap(), (MAX_POSTPONE + 1) * T_REFI,
                 viol_trcd, viol_trp, viol_tras, viol_trfc, viol_cas_closed, viol_act_open, viol_ref_open, viol_trrd, viol_tfaw, viol_twr, viol_twtr);
    endtask

    task automatic note(input string what);
        if (timing_violations() + viol_ref_open <= 3)
            $display("  [JEDEC-VIOL] t=%0t %s bg%0d bank%0d row 0x%0h", $time, what, bg, bank, row);
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Kết thúc khoảng refresh đang mở trước khi reset (REF đầu tiên sau reset được phép tới sau tREFI)
            if (cyc - t_last_ref > max_ref_gap) max_ref_gap = cyc - t_last_ref;
            cyc = 0;
            t_ref = -100000;
            t_last_ref = 0;
            t_act_any = -100000;
            for (int g = 0; g < BG_COUNT; g++) t_act_bg[g] = -100000;
            t_wend_any = -100000;
            for (int g = 0; g < BG_COUNT; g++) t_wend_bg[g] = -100000;
            for (int k = 0; k < 4; k++) act_hist[k] = -100000;
            for (int g = 0; g < BG_COUNT; g++)
                for (int b = 0; b < BANK_COUNT; b++) begin
                    open_b[g][b] = 0;
                    t_wend[g][b] = -100000;
                    t_act[g][b]  = -100000;
                    t_pre[g][b]  = -100000;
                    t_cas[g][b]  = -100000;
                end
        end else begin
            cyc++;
            cyc_total++;
            case (cmd)
                ACT: begin
                    n_act++;
                    if (open_b[bg][bank])               begin viol_act_open++; note("ACT to open bank"); end
                    if (cyc - t_pre[bg][bank] < T_RP)   begin viol_trp++;      note("ACT before tRP"); end
                    if (cyc - t_ref < T_RFC)            begin viol_trfc++;     note("ACT before tRFC"); end
                    if (cyc - t_act_any < T_RRD_S || cyc - t_act_bg[bg] < T_RRD_L) begin viol_trrd++; note("ACT before tRRD"); end
                    if (cyc - act_hist[3] < T_FAW)      begin viol_tfaw++;     note("5th ACT inside tFAW"); end
                    act_hist[3] = act_hist[2];
                    act_hist[2] = act_hist[1];
                    act_hist[1] = act_hist[0];
                    act_hist[0] = cyc;
                    t_act_any = cyc;
                    t_act_bg[bg] = cyc;
                    open_b[bg][bank] = 1;
                    open_r[bg][bank] = row;
                    t_act[bg][bank]  = cyc;
                end
                RD, WR: begin
                    if (!open_b[bg][bank] || open_r[bg][bank] != row) begin viol_cas_closed++; note("CAS to closed/wrong row"); end
                    else if (cyc - t_act[bg][bank] < T_RCD)          begin viol_trcd++;       note("CAS before tRCD"); end
                    if (cmd == RD && (cyc < t_wend_any + T_WTR_S || cyc < t_wend_bg[bg] + T_WTR_L)) begin
                        viol_twtr++; note($sformatf("RD before tWTR (cyc %0d, write data end any %0d / bg %0d)", cyc, t_wend_any, t_wend_bg[bg]));
                    end
                    t_cas[bg][bank]  = cyc;
                    cas_wr[bg][bank] = (cmd == WR);
                    if (cmd == WR) begin
                        t_wend[bg][bank] = cyc + T_CWL + len + 1;
                        if (t_wend[bg][bank] > t_wend_any)  t_wend_any  = t_wend[bg][bank];
                        if (t_wend[bg][bank] > t_wend_bg[bg]) t_wend_bg[bg] = t_wend[bg][bank];
                    end
                end
                PRE: begin
                    if (open_b[bg][bank] && cyc - t_act[bg][bank] < T_RAS) begin viol_tras++; note("PRE before tRAS"); end
                    if (open_b[bg][bank] && (cas_wr[bg][bank] ? (cyc < t_wend[bg][bank] + T_WR) : (cyc - t_cas[bg][bank] < T_RTP))) begin
                        viol_twr++; note("PRE before tWR/tRTP");
                    end
                    if (open_b[bg][bank]) t_pre[bg][bank] = cyc;
                    open_b[bg][bank] = 0;
                end
                // REFab và RFMab đều yêu cầu mọi bank đã precharge đủ tRP; chỉ REFab tính vào khoảng refresh định kỳ
                REF, RFM: begin
                    bit any_open;
                    if (cmd == REF) n_ref++; else n_rfm++;
                    any_open = 0;
                    for (int g = 0; g < BG_COUNT; g++)
                        for (int b = 0; b < BANK_COUNT; b++)
                            if (open_b[g][b] || cyc - t_pre[g][b] < T_RP) any_open = 1;
                    if (any_open) begin viol_ref_open++; note("REF with bank open / before tRP"); end
                    if (cmd == REF) begin
                        if (cyc - t_last_ref > max_ref_gap) max_ref_gap = cyc - t_last_ref;
                        t_last_ref = cyc;
                    end
                    t_ref = cyc;
                end
                default: ;
            endcase
        end
    end
endmodule
