// File:      tb_dfi_jedec_checker.sv
// Chức năng: Tự kiểm checker JEDEC v2 theo ps: mỗi luật SA-J01..J21 có một dãy DFI vi phạm (phải bị bắt) và một dãy sát ngưỡng hợp lệ (phải sạch).
`timescale 1ns / 1ps

module tb_dfi_jedec_checker;
    `include "tb_check.svh"

    localparam logic [2:0] NOP = 3'd0, ACT = 3'd1, PRE = 3'd2, RD = 3'd3, WR = 3'd4, REF = 3'd5, RFM = 3'd6;
    localparam int TCK_PS = 2500;

    logic        clk = 0, rst_n = 0;
    logic [2:0]  cmd = NOP;
    logic [2:0]  bg = 0;
    logic [1:0]  bank = 0;
    logic [16:0] row = 0;
    logic [7:0]  len = 0;

    dfi_jedec_checker #(.TCK_PS(TCK_PS), .TB_DFI_WRLAT(9)) u_chk (.clk(clk), .rst_n(rst_n), .cmd(cmd), .bg(bg), .bank(bank), .row(row), .len(len));

    always #1.25 clk = ~clk;

    // go(): lệnh chiếm đúng 1 chu kỳ, trả về ở negedge kế tiếp; khoảng cách giữa hai go() liên tiếp = 1 + w(n)
    task automatic go(input logic [2:0] c, input int g, input int b, input int r);
        cmd  = c;
        bg   = g;
        bank = b;
        row  = r;
        @(negedge clk);
        cmd  = NOP;
    endtask

    task automatic w(input int n);
        repeat (n) @(negedge clk);
    endtask

    // Khoảng cách k chu kỳ từ lệnh trước tới lệnh kế
    task automatic after(input int k);
        if (k > 1) w(k - 1);
    endtask

    task automatic restart();
        @(negedge clk);
        rst_n = 0;
        @(negedge clk);
        rst_n = 1;
        w(2);
    endtask

    task automatic expect_viol(input string name, input int got_delta, input bit want);
        tb_check(want ? (got_delta > 0) : (got_delta == 0),
                 $sformatf("%s: checker %s (%0d new violations)", name, want ? "flags it" : "stays clean", got_delta));
    endtask

    int v0, a0;

    initial begin
        restart();

        // Đối chứng tổng hợp: ACT -> RD -> PRE -> REF -> ACT, mọi khoảng đúng sát ngưỡng ps
        a0 = u_chk.all_violations();
        go(ACT, 0, 0, 5); after(7); go(RD, 0, 0, 5); after(6); go(PRE, 0, 0, 0); after(7);
        go(REF, 0, 0, 0); after(118); go(ACT, 1, 0, 9); after(13); go(PRE, 1, 0, 0); w(8);
        expect_viol("Legal ACT/RD/PRE/REF sequence at 2500 ps", u_chk.all_violations() - a0, 0);
        tb_check(u_chk.REFI_CYC == 1560 && u_chk.RFC_CYC == 118,
                 $sformatf("Derived REFI_CYC %0d / RFC_CYC %0d at 2500 ps", u_chk.REFI_CYC, u_chk.RFC_CYC));

        // SA-J01 tRCD 17.5 ns = 7 chu kỳ
        restart(); v0 = u_chk.viol_trcd;
        go(ACT, 2, 1, 7); after(6); go(RD, 2, 1, 7); w(20); go(PRE, 2, 1, 0); w(8);
        expect_viol("SA-J01 RD 6 cycles after ACT (tRCD)", u_chk.viol_trcd - v0, 1);
        restart(); a0 = u_chk.all_violations();
        go(ACT, 2, 1, 7); after(7); go(RD, 2, 1, 7); w(20); go(PRE, 2, 1, 0); w(8);
        expect_viol("SA-J01 RD exactly 7 cycles after ACT", u_chk.all_violations() - a0, 0);

        // SA-J02 tRP 17.5 ns = 7 chu kỳ
        restart(); v0 = u_chk.viol_trp;
        go(ACT, 4, 1, 7); after(20); go(PRE, 4, 1, 0); after(6); go(ACT, 4, 1, 8); w(20); go(PRE, 4, 1, 0); w(8);
        expect_viol("SA-J02 ACT 6 cycles after PRE (tRP)", u_chk.viol_trp - v0, 1);
        restart(); a0 = u_chk.all_violations();
        go(ACT, 4, 1, 7); after(20); go(PRE, 4, 1, 0); after(7); go(ACT, 4, 1, 8); w(20); go(PRE, 4, 1, 0); w(8);
        expect_viol("SA-J02 ACT exactly 7 cycles after PRE", u_chk.all_violations() - a0, 0);

        // SA-J03 tRAS 32 ns = 12.8 chu kỳ -> 13
        restart(); v0 = u_chk.viol_tras;
        go(ACT, 3, 1, 7); after(12); go(PRE, 3, 1, 0); w(8);
        expect_viol("SA-J03 PRE 12 cycles after ACT (tRAS)", u_chk.viol_tras - v0, 1);
        restart(); a0 = u_chk.all_violations();
        go(ACT, 3, 1, 7); after(13); go(PRE, 3, 1, 0); w(8);
        expect_viol("SA-J03 PRE 13 cycles after ACT", u_chk.all_violations() - a0, 0);

        // SA-J05 tRC 49.5 ns: tRC = tRAS + tRP nên không vi phạm riêng được; kiểm bộ đếm tRC có tăng khi ACT-ACT quá gần
        restart(); v0 = u_chk.viol_trc;
        go(ACT, 5, 2, 1); after(5); go(PRE, 5, 2, 0); after(7); go(ACT, 5, 2, 2); w(20); go(PRE, 5, 2, 0); w(8);
        expect_viol("SA-J05 ACT-ACT same bank 12 cycles apart (tRC)", u_chk.viol_trc - v0, 1);
        restart(); a0 = u_chk.all_violations();
        go(ACT, 5, 2, 1); after(13); go(PRE, 5, 2, 0); after(7); go(ACT, 5, 2, 2); w(20); go(PRE, 5, 2, 0); w(8);
        expect_viol("SA-J05 ACT-ACT same bank 20 cycles apart", u_chk.all_violations() - a0, 0);

        // SA-J06 tRRD_S, SA-J07 tRRD_L: 5 ns = 2 chu kỳ
        restart(); v0 = u_chk.viol_trrd;
        go(ACT, 5, 0, 1); go(ACT, 6, 0, 1); w(20); go(PRE, 5, 0, 0); after(2); go(PRE, 6, 0, 0); w(8);
        expect_viol("SA-J06 ACTs on different BGs 1 cycle apart (tRRD_S)", u_chk.viol_trrd - v0, 1);
        restart(); a0 = u_chk.all_violations();
        go(ACT, 5, 0, 1); after(2); go(ACT, 6, 0, 1); w(20); go(PRE, 5, 0, 0); after(2); go(PRE, 6, 0, 0); w(8);
        expect_viol("SA-J06 ACTs on different BGs 2 cycles apart", u_chk.all_violations() - a0, 0);
        restart(); v0 = u_chk.viol_trrd;
        go(ACT, 5, 0, 1); go(ACT, 5, 1, 1); w(20); go(PRE, 5, 0, 0); after(2); go(PRE, 5, 1, 0); w(8);
        expect_viol("SA-J07 ACTs in the same BG 1 cycle apart (tRRD_L)", u_chk.viol_trrd - v0, 1);
        restart(); a0 = u_chk.all_violations();
        go(ACT, 5, 0, 1); after(2); go(ACT, 5, 1, 1); w(20); go(PRE, 5, 0, 0); after(2); go(PRE, 5, 1, 0); w(8);
        expect_viol("SA-J07 ACTs in the same BG 2 cycles apart", u_chk.all_violations() - a0, 0);

        // SA-J08 tFAW 25 ns = 10 chu kỳ: ACT thứ 5 ở +8 vi phạm, ở +10 hợp lệ (mọi cặp liên tiếp cách 2 = tRRD)
        restart(); v0 = u_chk.viol_tfaw;
        for (int k = 0; k < 5; k++) begin go(ACT, k, 2, 3); if (k < 4) after(2); end
        w(20);
        for (int k = 0; k < 5; k++) begin go(PRE, k, 2, 0); after(2); end
        w(8);
        expect_viol("SA-J08 five ACTs within 8 cycles (tFAW)", u_chk.viol_tfaw - v0, 1);
        restart(); a0 = u_chk.all_violations();
        for (int k = 0; k < 5; k++) begin go(ACT, k, 2, 3); if (k < 3) after(2); else if (k == 3) after(4); end
        w(20);
        for (int k = 0; k < 5; k++) begin go(PRE, k, 2, 0); after(2); end
        w(8);
        expect_viol("SA-J08 fifth ACT exactly 10 cycles after the first", u_chk.all_violations() - a0, 0);

        // SA-J09 tCCD_S, SA-J10 tCCD_L: 5 ns = 2 chu kỳ giữa hai CAS
        restart(); v0 = u_chk.viol_tccd;
        go(ACT, 0, 0, 1); after(2); go(ACT, 1, 0, 1); after(8); go(RD, 0, 0, 1); go(RD, 1, 0, 1); w(20);
        go(PRE, 0, 0, 0); after(2); go(PRE, 1, 0, 0); w(8);
        expect_viol("SA-J09 RDs on different BGs 1 cycle apart (tCCD_S)", u_chk.viol_tccd - v0, 1);
        restart(); a0 = u_chk.all_violations();
        go(ACT, 0, 0, 1); after(2); go(ACT, 1, 0, 1); after(8); go(RD, 0, 0, 1); after(2); go(RD, 1, 0, 1); w(20);
        go(PRE, 0, 0, 0); after(2); go(PRE, 1, 0, 0); w(8);
        expect_viol("SA-J09 RDs on different BGs 2 cycles apart", u_chk.all_violations() - a0, 0);
        restart(); v0 = u_chk.viol_tccd;
        go(ACT, 0, 0, 1); after(2); go(ACT, 0, 1, 1); after(8); go(RD, 0, 0, 1); go(RD, 0, 1, 1); w(20);
        go(PRE, 0, 0, 0); after(2); go(PRE, 0, 1, 0); w(8);
        expect_viol("SA-J10 RDs in the same BG 1 cycle apart (tCCD_L)", u_chk.viol_tccd - v0, 1);
        restart(); a0 = u_chk.all_violations();
        go(ACT, 0, 0, 1); after(2); go(ACT, 0, 1, 1); after(8); go(RD, 0, 0, 1); after(2); go(RD, 0, 1, 1); w(20);
        go(PRE, 0, 0, 0); after(2); go(PRE, 0, 1, 0); w(8);
        expect_viol("SA-J10 RDs in the same BG 2 cycles apart", u_chk.all_violations() - a0, 0);

        // SA-J11 tCCD_L_WR 20 ns = 8 chu kỳ giữa hai WR cùng BG
        restart(); v0 = u_chk.viol_tccd_wr;
        go(ACT, 2, 0, 1); after(2); go(ACT, 2, 1, 1); after(8); go(WR, 2, 0, 1); after(4); go(WR, 2, 1, 1); w(40);
        go(PRE, 2, 0, 0); after(2); go(PRE, 2, 1, 0); w(8);
        expect_viol("SA-J11 WRs in the same BG 4 cycles apart (tCCD_L_WR)", u_chk.viol_tccd_wr - v0, 1);
        restart(); a0 = u_chk.all_violations();
        go(ACT, 2, 0, 1); after(2); go(ACT, 2, 1, 1); after(8); go(WR, 2, 0, 1); after(8); go(WR, 2, 1, 1); w(40);
        go(PRE, 2, 0, 0); after(2); go(PRE, 2, 1, 0); w(8);
        expect_viol("SA-J11 WRs in the same BG 8 cycles apart", u_chk.all_violations() - a0, 0);

        // SA-J12 tWR: beat cuối = WR + max(21.25 ns, (9+0+1)*2.5 ns) = WR + 10 chu kỳ; PRE >= +10 +12 = +22
        restart(); v0 = u_chk.viol_twr;
        go(ACT, 7, 3, 2); after(14); go(WR, 7, 3, 2); after(21); go(PRE, 7, 3, 0); w(8);
        expect_viol("SA-J12 PRE 21 cycles after WR len 0 (tWR)", u_chk.viol_twr - v0, 1);
        restart(); a0 = u_chk.all_violations();
        go(ACT, 7, 3, 2); after(14); go(WR, 7, 3, 2); after(22); go(PRE, 7, 3, 0); w(8);
        expect_viol("SA-J12 PRE 22 cycles after WR len 0", u_chk.all_violations() - a0, 0);
        // Burst 8 beat: beat cuối ở WR + 17, PRE cần >= WR + 29
        restart(); v0 = u_chk.viol_twr; len = 7;
        go(ACT, 6, 3, 2); after(14); go(WR, 6, 3, 2); after(28); go(PRE, 6, 3, 0); w(8);
        expect_viol("SA-J12 PRE 28 cycles after an 8-beat WR (tWR from last beat)", u_chk.viol_twr - v0, 1);
        restart(); a0 = u_chk.all_violations();
        go(ACT, 6, 3, 2); after(14); go(WR, 6, 3, 2); after(29); go(PRE, 6, 3, 0); w(8);
        expect_viol("SA-J12 PRE 29 cycles after an 8-beat WR", u_chk.all_violations() - a0, 0);
        len = 0;

        // SA-J13 tRTP 7.5 ns = 3 chu kỳ
        restart(); v0 = u_chk.viol_trtp;
        go(ACT, 1, 2, 4); after(13); go(RD, 1, 2, 4); after(2); go(PRE, 1, 2, 0); w(8);
        expect_viol("SA-J13 PRE 2 cycles after RD (tRTP)", u_chk.viol_trtp - v0, 1);
        restart(); a0 = u_chk.all_violations();
        go(ACT, 1, 2, 4); after(13); go(RD, 1, 2, 4); after(3); go(PRE, 1, 2, 0); w(8);
        expect_viol("SA-J13 PRE 3 cycles after RD", u_chk.all_violations() - a0, 0);

        // SA-J14 tWTR_S: RD khác BG >= WR + 25 + 2.5 ns = +11; SA-J15 tWTR_L: cùng BG >= WR + 25 + 10 ns = +14
        restart(); v0 = u_chk.viol_twtr;
        go(ACT, 3, 1, 1); after(2); go(ACT, 4, 1, 1); after(14); go(WR, 3, 1, 1); after(10); go(RD, 4, 1, 1); w(30);
        go(PRE, 3, 1, 0); after(2); go(PRE, 4, 1, 0); w(8);
        expect_viol("SA-J14 RD to another BG 10 cycles after WR (tWTR_S)", u_chk.viol_twtr - v0, 1);
        restart(); a0 = u_chk.all_violations();
        go(ACT, 3, 1, 1); after(2); go(ACT, 4, 1, 1); after(14); go(WR, 3, 1, 1); after(11); go(RD, 4, 1, 1); w(30);
        go(PRE, 3, 1, 0); after(2); go(PRE, 4, 1, 0); w(8);
        expect_viol("SA-J14 RD to another BG 11 cycles after WR", u_chk.all_violations() - a0, 0);
        restart(); v0 = u_chk.viol_twtr;
        go(ACT, 3, 0, 1); after(2); go(ACT, 3, 2, 1); after(14); go(WR, 3, 0, 1); after(13); go(RD, 3, 2, 1); w(30);
        go(PRE, 3, 0, 0); after(2); go(PRE, 3, 2, 0); w(8);
        expect_viol("SA-J15 RD to the same BG 13 cycles after WR (tWTR_L)", u_chk.viol_twtr - v0, 1);
        restart(); a0 = u_chk.all_violations();
        go(ACT, 3, 0, 1); after(2); go(ACT, 3, 2, 1); after(14); go(WR, 3, 0, 1); after(14); go(RD, 3, 2, 1); w(30);
        go(PRE, 3, 0, 0); after(2); go(PRE, 3, 2, 0); w(8);
        expect_viol("SA-J15 RD to the same BG 14 cycles after WR", u_chk.all_violations() - a0, 0);

        // SA-J16 tRFC 295 ns = 118 chu kỳ (REF -> ACT, REF -> REF)
        restart(); v0 = u_chk.viol_trfc;
        go(REF, 0, 0, 0); after(117); go(ACT, 2, 2, 2); w(20); go(PRE, 2, 2, 0); w(8);
        expect_viol("SA-J16 ACT 117 cycles after REF (tRFC)", u_chk.viol_trfc - v0, 1);
        restart(); v0 = u_chk.viol_trfc;
        go(REF, 0, 0, 0); after(60); go(REF, 0, 0, 0); w(130);
        expect_viol("SA-J16 REF 60 cycles after REF (tRFC)", u_chk.viol_trfc - v0, 1);
        restart(); a0 = u_chk.all_violations();
        go(REF, 0, 0, 0); after(118); go(ACT, 2, 2, 2); after(13); go(PRE, 2, 2, 0); w(8);
        expect_viol("SA-J16 ACT exactly 118 cycles after REF", u_chk.all_violations() - a0, 0);

        // SA-J17 tRFM = 295 ns (RFM -> ACT / RFM -> REF)
        restart(); v0 = u_chk.viol_trfm;
        go(RFM, 0, 0, 0); after(117); go(ACT, 2, 2, 2); w(20); go(PRE, 2, 2, 0); w(8);
        expect_viol("SA-J17 ACT 117 cycles after RFM (tRFM)", u_chk.viol_trfm - v0, 1);
        restart(); v0 = u_chk.viol_trfm;
        go(RFM, 0, 0, 0); after(100); go(REF, 0, 0, 0); w(130);
        expect_viol("SA-J17 REF 100 cycles after RFM (tRFM)", u_chk.viol_trfm - v0, 1);
        restart(); a0 = u_chk.all_violations();
        go(RFM, 0, 0, 0); after(118); go(REF, 0, 0, 0); after(118); go(ACT, 1, 1, 1); after(13); go(PRE, 1, 1, 0); w(8);
        expect_viol("SA-J17 REF 118 cycles after RFM, ACT 118 after REF", u_chk.all_violations() - a0, 0);

        // SA-J18 REF/RFM khi có bank mở hoặc chưa qua tRP sau PRE
        restart(); v0 = u_chk.viol_ref_open;
        go(ACT, 0, 3, 4); after(14); go(REF, 0, 0, 0); w(130); go(PRE, 0, 3, 0); w(8);
        expect_viol("SA-J18 REF with a bank open", u_chk.viol_ref_open - v0, 1);
        restart(); v0 = u_chk.viol_ref_open;
        go(ACT, 1, 3, 4); after(14); go(RFM, 0, 0, 0); w(130); go(PRE, 1, 3, 0); w(8);
        expect_viol("SA-J18 RFM with a bank open", u_chk.viol_ref_open - v0, 1);
        restart(); v0 = u_chk.viol_ref_open;
        go(ACT, 1, 3, 4); after(14); go(PRE, 1, 3, 0); after(6); go(REF, 0, 0, 0); w(130);
        expect_viol("SA-J18 REF 6 cycles after PRE (tRP)", u_chk.viol_ref_open - v0, 1);
        restart(); a0 = u_chk.all_violations();
        go(ACT, 1, 3, 4); after(14); go(PRE, 1, 3, 0); after(7); go(REF, 0, 0, 0); w(130);
        expect_viol("SA-J18 REF exactly 7 cycles after PRE", u_chk.all_violations() - a0, 0);

        // SA-J19 CAS vào bank đóng / hàng khác; SA-J20 ACT vào bank đang mở
        restart(); v0 = u_chk.viol_cas_closed;
        go(RD, 2, 3, 9); w(10);
        expect_viol("SA-J19 RD to a closed bank", u_chk.viol_cas_closed - v0, 1);
        restart(); v0 = u_chk.viol_cas_closed;
        go(ACT, 2, 3, 9); after(8); go(WR, 2, 3, 10); w(30); go(PRE, 2, 3, 0); w(8);
        expect_viol("SA-J19 WR to the wrong open row", u_chk.viol_cas_closed - v0, 1);
        restart(); v0 = u_chk.viol_act_open;
        go(ACT, 2, 3, 9); after(25); go(ACT, 2, 3, 10); w(20); go(PRE, 2, 3, 0); w(8);
        expect_viol("SA-J20 ACT to an open bank", u_chk.viol_act_open - v0, 1);

        // SA-J04 tRAS(max) = 9 x tREFI = 35.1 µs = 14040 chu kỳ
        restart(); a0 = u_chk.all_violations();
        go(ACT, 4, 0, 1); after(14030); go(PRE, 4, 0, 0); w(8);
        expect_viol("SA-J04 row open 14030 cycles (< tRAS(max))", u_chk.all_violations() - a0, 0);
        restart(); v0 = u_chk.viol_trasmax;
        go(ACT, 4, 0, 1); after(14100); go(PRE, 4, 0, 0); w(8);
        expect_viol("SA-J04 row open 14100 cycles (tRAS(max))", u_chk.viol_trasmax - v0, 1);
        tb_check(u_chk.viol_trasmax - v0 == 1, $sformatf("SA-J04 one long open counted once (%0d)", u_chk.viol_trasmax - v0));

        // SA-J21 khoảng REF <= 5 x tREFI = 19.5 µs = 7800 chu kỳ
        restart(); a0 = u_chk.all_violations();
        go(REF, 0, 0, 0); after(7800); go(REF, 0, 0, 0); w(130);
        expect_viol("SA-J21 REF-REF exactly 7800 cycles", u_chk.all_violations() - a0, 0);
        restart(); v0 = u_chk.viol_refgap;
        go(REF, 0, 0, 0); after(7801); go(REF, 0, 0, 0); w(130);
        expect_viol("SA-J21 REF-REF 7801 cycles (5 x tREFI)", u_chk.viol_refgap - v0, 1);
        tb_check(!u_chk.refresh_ok(), $sformatf("SA-J21 refresh_ok() reports the long gap (worst %0d ps)", u_chk.worst_ref_gap_ps()));

        u_chk.report("self-test");
        tb_report();
        $finish;
    end

    initial begin
        #400_000;
        tb_check(0, "watchdog: self-test did not finish");
        tb_report();
        $finish;
    end
endmodule
