// File:      qs_rd_beat_model.sv
// Chức năng: Mô hình beat đọc của TB dựng từ lệnh RD trên DFI (lịch E + T_RDV + b) và checker tuần tự SA-D01..D11, SA-P09 trên cổng đọc của engine.
`timescale 1ns / 1ps

module qs_rd_beat_model #(
    parameter int T_RDV     = 9,
    parameter int TAG_W     = 5,
    parameter int BG_W      = 3,
    parameter int BANK_W    = 2,
    parameter int ROW_W     = 17,
    parameter int COL_W     = 10,
    parameter int D2_MAX    = 145,  // T_RDV + 8 + 128 (A-D2)
    parameter int FLUSH_MAX = 160   // §6.6 ước 130 + biên
) (
    input  logic              clk,
    input  logic              rst_n,
    input  logic              en,          // 1 = kiểm cổng v2 (o_rd_*), 0 = chỉ dựng mô hình
    input  logic              excuse,      // bơm lỗi vào trạng thái nội bộ rd_st/exp_v: mô hình không còn so khớp được
    input  logic [2:0]        dfi_cmd,
    input  logic [7:0]        dfi_len,
    input  logic [TAG_W-1:0]  dfi_tag,
    input  logic [BG_W-1:0]   dfi_bg,
    input  logic [BANK_W-1:0] dfi_bank,
    input  logic [ROW_W-1:0]  dfi_row,
    input  logic [COL_W-1:0]  dfi_col,
    input  logic              rd_valid,    // i_dfi_rddata_valid tại engine
    input  logic              rd_take,
    input  logic              rd_beat_ok,
    input  logic              rd_flush,
    input  logic              rd_resync,
    input  logic              wb_valid,
    input  logic [TAG_W-1:0]  wb_tag,
    input  logic              wb_last,
    input  logic              wb_err,
    input  logic [1:0]        wb_resp,
    input  logic              rmw_valid,
    input  logic              fault5,
    // Đầu RD đang được rút trong chu kỳ hiện tại (NBA: khối posedge khác đọc giá trị của chu kỳ vừa qua)
    output logic              o_head_valid,
    output logic [TAG_W-1:0]  o_head_tag,
    output logic [7:0]        o_head_len,
    output logic [7:0]        o_head_k,
    output logic [BG_W-1:0]   o_head_bg,
    output logic [BANK_W-1:0] o_head_bank,
    output logic [ROW_W-1:0]  o_head_row,
    output logic [COL_W-1:0]  o_head_col,
    output logic              o_exp0,
    output int                o_pend
);
    localparam logic [2:0] CMD_RD = 3'd3;
    localparam int RING = 256;

    longint cyc;
    int     sched [RING];
    // Hàng RD theo thứ tự phát (như FIFO tag của engine)
    int     q_tag [$];
    int     q_len [$];
    longint q_e   [$];
    int     q_bg [$], q_bank [$], q_row [$], q_col [$];
    int     head_k;
    int     sched_total;

    int n_rd_issued, n_rd_done, n_beats_real, n_beats_synth;
    int flush_events, flush_cycles, flush_run, flush_max_run, resync_cnt;
    int err_d01, err_d02, err_d03, err_d04, err_d07, err_d08, err_d09, err_d10, err_d11, err_p09, err_take;
    int d2_max_seen;
    bit prev_flush, prev_valid, prev_pend0, prev_resync, pend_d02;
    bit d09_flag;

    function automatic int errors();
        return err_d01 + err_d02 + err_d03 + err_d04 + err_d07 + err_d08 + err_d09 + err_d10 + err_d11 + err_p09 + err_take;
    endfunction

    function automatic int beats_expected_now();
        return sched[int'(cyc % RING)];
    endfunction

    function automatic bit exp_any();
        return sched_total != 0;
    endfunction

    task automatic report(input string tag);
        $display("  [RDMODEL] %s: RD %0d done %0d, real beats %0d synth beats %0d, flush events %0d cycles %0d max run %0d, resync %0d, worst RD completion %0d cyc",
                 tag, n_rd_issued, n_rd_done, n_beats_real, n_beats_synth, flush_events, flush_cycles, flush_max_run,
                 resync_cnt, d2_max_seen);
        $display("  [RDMODEL] %s: err D01 %0d D02 %0d D03 %0d D04 %0d D07 %0d D08 %0d D09 %0d D10 %0d D11 %0d P09 %0d take %0d",
                 tag, err_d01, err_d02, err_d03, err_d04, err_d07, err_d08, err_d09, err_d10, err_d11, err_p09, err_take);
    endtask

    task automatic bad(inout int cnt, input string what);
        cnt++;
        if (errors() <= 10) $display("[RDMODEL-ERR] t=%0t cyc=%0d %s", $time, cyc, what);
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (rst_n !== 1'b1) begin
            cyc = 0;
            for (int k = 0; k < RING; k++) sched[k] = 0;
            q_tag.delete(); q_len.delete(); q_e.delete();
            q_bg.delete(); q_bank.delete(); q_row.delete(); q_col.delete();
            head_k = 0;
            sched_total = 0;
            prev_flush = 0; prev_valid = 0; prev_pend0 = 1; prev_resync = 0; pend_d02 = 0;
            flush_run = 0;
            d09_flag = 0;
            o_head_valid <= 1'b0;
            o_exp0 <= 1'b0;
            o_pend <= 0;
        end else begin
            bit e0, pend, idle_now;
            int slot;
            slot = int'(cyc % RING);
            e0   = (sched[slot] != 0);
            pend = (q_tag.size() != 0);
            // Điều kiện thoát FLUSH của spec (§5.2) đánh giá trên trạng thái trong chu kỳ, trước khi rút beat
            idle_now = !pend && (sched_total == 0) && !rd_valid;

            if (en && !excuse) begin
                // SA-D02 (phần +1): lệch ở chu kỳ trước phải đưa engine vào FLUSH và báo fault[5]
                if (pend_d02 && !(rd_flush && fault5)) bad(err_d02, "beat mismatch not followed by FLUSH + o_fault[5]");
                // SA-D01: ở SYNC chỉ nhận beat đúng chu kỳ kỳ vọng
                if (!rd_flush && (rd_beat_ok != (rd_valid && e0 && pend))) bad(err_d01, $sformatf("rd_beat_ok=%0b valid=%0b exp0=%0b pend=%0b", rd_beat_ok, rd_valid, e0, pend));
                if (rd_beat_ok && !rd_valid) bad(err_d01, "rd_beat_ok without i_dfi_rddata_valid");
                // SA-D03: RD muộn nhất ở chu kỳ đầu của FLUSH
                if (prev_flush && dfi_cmd == CMD_RD) bad(err_d03, "RD issued while FLUSH was active in the previous cycle");
                // SA-D04: đánh dấu beat lỗi nhất quán
                if (wb_err && wb_resp != 2'b10) bad(err_d04, "o_wb_err without SLVERR");
                if ((wb_valid || rmw_valid) && rd_flush && !wb_err) bad(err_d04, "beat delivered in FLUSH without o_wb_err");
                if ((wb_valid || rmw_valid) && !rd_flush && (wb_err || wb_resp != 2'b00)) bad(err_d04, "beat in SYNC flagged as error");
                // SA-D07: đồng bộ lại sạch
                if (rd_resync && !(prev_flush && !rd_flush)) bad(err_d07, "o_rd_resync not at FLUSH->SYNC edge");
                if (rd_resync && !prev_pend0) bad(err_d07, "o_rd_resync while beats were still pending");
                if (rd_resync && prev_resync) bad(err_d07, "o_rd_resync longer than one cycle");
                // SA-D11: trong FLUSH rút đều mỗi chu kỳ một beat tổng hợp
                if (rd_flush && pend && !rd_take) bad(err_d11, "FLUSH with pending beats but no o_rd_take");
                // SA-D10
                if (flush_run > FLUSH_MAX) begin
                    if (flush_run == FLUSH_MAX + 1) bad(err_d10, $sformatf("FLUSH longer than %0d cycles", FLUSH_MAX));
                end
            end
            pend_d02 = en && !excuse && !rd_flush && (rd_valid != e0);

            // Rút beat (cả v1 lẫn v2: o_rd_take do TB suy ra ở v1 = wb_valid || rmw_valid)
            if (en && rd_take != (wb_valid || rmw_valid)) bad(err_take, "o_rd_take differs from (o_wb_valid || o_rmw_valid)");
            if (rd_take) begin
                if (!pend) begin
                    if (en && !excuse) bad(err_take, "beat consumed with no RD pending");
                end else begin
                    if (rd_flush) n_beats_synth++; else n_beats_real++;
                    if (en && !excuse) begin
                        if (wb_valid && wb_tag != TAG_W'(q_tag[0])) bad(err_p09, $sformatf("beat tag %0d, head RD tag %0d", wb_tag, q_tag[0]));
                        if (wb_last != (head_k == q_len[0])) bad(err_p09, $sformatf("o_wb_last=%0b at beat %0d of len %0d", wb_last, head_k, q_len[0]));
                    end
                    if (head_k == q_len[0]) begin
                        int dt, d_i;
                        longint d_l;
                        dt = int'(cyc - q_e[0]);
                        if (dt > d2_max_seen) d2_max_seen = dt;
                        if (dt > D2_MAX && en && !excuse) bad(err_d09, $sformatf("RD completed %0d cycles after issue", dt));
                        n_rd_done++;
                        d_i = q_tag.pop_front(); d_i = q_len.pop_front(); d_l = q_e.pop_front();
                        d_i = q_bg.pop_front(); d_i = q_bank.pop_front(); d_i = q_row.pop_front(); d_i = q_col.pop_front();
                        head_k = 0;
                        d09_flag = 0;
                    end else begin
                        head_k++;
                    end
                end
            end
            // SA-D09 dạng watchdog: RD đầu hàng quá hạn mà chưa xong
            if (q_e.size() != 0 && !d09_flag && cyc - q_e[0] > D2_MAX && en && !excuse) begin
                d09_flag = 1;
                bad(err_d09, $sformatf("head RD (tag %0d) still incomplete %0d cycles after issue", q_tag[0], cyc - q_e[0]));
            end

            if (rd_flush) begin
                flush_cycles++;
                flush_run++;
                if (!prev_flush) flush_events++;
                if (flush_run > flush_max_run) flush_max_run = flush_run;
            end else begin
                flush_run = 0;
            end
            if (rd_resync) resync_cnt++;

            sched_total -= sched[slot];
            sched[slot] = 0;
            // Lệnh RD trong chu kỳ này: beat b tới engine ở chu kỳ cyc + T_RDV + b
            if (dfi_cmd == CMD_RD) begin
                n_rd_issued++;
                for (int b = 0; b <= int'(dfi_len[2:0]); b++) begin
                    int s;
                    s = int'((cyc + T_RDV + b) % RING);
                    if (sched[s] != 0) bad(err_d08, "read beat windows overlap (A-D6)");
                    sched[s]++;
                    sched_total++;
                end
                q_tag.push_back(int'(dfi_tag)); q_len.push_back(int'(dfi_len[2:0])); q_e.push_back(cyc);
                q_bg.push_back(int'(dfi_bg)); q_bank.push_back(int'(dfi_bank)); q_row.push_back(int'(dfi_row)); q_col.push_back(int'(dfi_col));
            end

            prev_flush  = rd_flush;
            prev_valid  = rd_valid;
            prev_pend0  = idle_now;
            prev_resync = rd_resync;
            cyc++;

            o_head_valid <= (q_tag.size() != 0);
            o_head_tag   <= (q_tag.size() != 0) ? TAG_W'(q_tag[0]) : '0;
            o_head_len   <= (q_tag.size() != 0) ? 8'(q_len[0]) : 8'd0;
            o_head_k     <= 8'(head_k);
            o_head_bg    <= (q_tag.size() != 0) ? BG_W'(q_bg[0]) : '0;
            o_head_bank  <= (q_tag.size() != 0) ? BANK_W'(q_bank[0]) : '0;
            o_head_row   <= (q_tag.size() != 0) ? ROW_W'(q_row[0]) : '0;
            o_head_col   <= (q_tag.size() != 0) ? COL_W'(q_col[0]) : '0;
            o_exp0       <= (sched[int'(cyc % RING)] != 0);
            o_pend       <= q_tag.size();
        end
    end
endmodule
