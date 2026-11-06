// File:      qs_axi_txn_chk.sv
// Chức năng: Checker giao thức AXI4/5 + scoreboard bộ nhớ tham chiếu theo địa chỉ: SA-P01..P04, SA-D05, SA-D06, SA-W01, SA-W03 và thống kê độ trễ [PERF].
`timescale 1ns / 1ps

module qs_axi_txn_chk #(
    parameter int AXI_ADDR_W = 34,
    parameter int AXI_DATA_W = 64,
    parameter int AXI_ID_W   = 6,
    parameter int AXI_LEN_W  = 8,
    parameter int N_TXN      = 4096,
    parameter int MEM_LOG    = 14
) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    en_v2        = 1'b1,
    input  logic                    chk_data_en  = 1'b1,
    // AW channel
    input  logic [AXI_ID_W-1:0]     s_axi_awid,
    input  logic [AXI_ADDR_W-1:0]   s_axi_awaddr,
    input  logic [AXI_LEN_W-1:0]    s_axi_awlen,
    input  logic                    s_axi_awvalid,
    input  logic                    s_axi_awready,
    // W channel
    input  logic [AXI_DATA_W-1:0]   s_axi_wdata,
    input  logic [AXI_DATA_W/8-1:0] s_axi_wstrb,
    input  logic                    s_axi_wlast,
    input  logic                    s_axi_wvalid,
    input  logic                    s_axi_wready,
    // B channel
    input  logic [AXI_ID_W-1:0]     s_axi_bid,
    input  logic [1:0]              s_axi_bresp,
    input  logic                    s_axi_bvalid,
    input  logic                    s_axi_bready,
    // AR channel
    input  logic [AXI_ID_W-1:0]     s_axi_arid,
    input  logic [AXI_ADDR_W-1:0]   s_axi_araddr,
    input  logic [AXI_LEN_W-1:0]    s_axi_arlen,
    input  logic                    s_axi_arvalid,
    input  logic                    s_axi_arready,
    // R channel
    input  logic [AXI_ID_W-1:0]     s_axi_rid,
    input  logic [AXI_DATA_W-1:0]   s_axi_rdata,
    input  logic [1:0]              s_axi_rresp,
    input  logic                    s_axi_rlast,
    input  logic                    s_axi_rvalid,
    input  logic                    s_axi_rready,
    input  logic [AXI_DATA_W/64-1:0] s_axi_rpoison = '0
);
    localparam int N_IDS = 1 << AXI_ID_W;
    localparam int ID_Q  = 64;
    localparam int MEM_N = 1 << MEM_LOG;

    longint cyc;

    // Trạng thái giữ ổn định R và B (SA-P01, SA-P02)
    bit                       r_hold;
    logic [AXI_ID_W-1:0]      r_hold_id;
    logic [AXI_DATA_W-1:0]    r_hold_data;
    logic [1:0]               r_hold_resp;
    logic                     r_hold_last;
    logic [AXI_DATA_W/64-1:0] r_hold_poison;

    bit                       b_hold;
    logic [AXI_ID_W-1:0]      b_hold_id;
    logic [1:0]               b_hold_resp;

    // Hàng đợi vòng giao dịch đọc/ghi theo ID (SA-P03, SA-P04, SA-D06)
    longint ar_q_addr [N_IDS][ID_Q];
    int     ar_q_len  [N_IDS][ID_Q];
    int     ar_q_beat [N_IDS][ID_Q];
    longint ar_q_cyc  [N_IDS][ID_Q];
    int     ar_q_rd   [N_IDS];
    int     ar_q_wr   [N_IDS];

    longint wr_b_cyc  [N_IDS][ID_Q];
    int     wr_b_rd   [N_IDS];
    int     wr_b_wr   [N_IDS];

    // Hàng đợi AW và W để ghép ghi vào bộ nhớ tham chiếu
    longint aw_pend_addr [$];
    int     aw_pend_len  [$];
    int     aw_pend_id   [$];
    longint aw_pend_cyc  [$];

    logic [AXI_DATA_W-1:0]   w_pend_data [$];
    logic [AXI_DATA_W/8-1:0] w_pend_strb [$];
    bit                      w_pend_last [$];
    int                      w_beat_idx;

    // Bảng băm bộ nhớ tham chiếu theo địa chỉ word 8-byte (Icarus không có mảng kết hợp)
    bit [63:0]               mem_key    [MEM_N];
    logic [AXI_DATA_W-1:0]   mem_data   [MEM_N];
    logic [AXI_DATA_W/8-1:0] mem_vld    [MEM_N];
    bit                      mem_poison [MEM_N];
    bit                      mem_used   [MEM_N];

    // Thống kê lỗi và hiệu năng
    int     err_p01, err_p02, err_p03, err_p04, err_d05, err_d06, err_w01;
    int     rd_cmds, wr_cmds, rd_done, wr_done;
    int     rd_err_beats, rd_ok_beats;
    int     rd_lat_min, rd_lat_max;
    longint rd_lat_sum;
    int     wr_lat_min, wr_lat_max;
    longint wr_lat_sum;
    bit     p04_flagged;

    function automatic int slot_of(input bit [63:0] k);
        bit [63:0] h;
        h = k * 64'h9E37_79B9_7F4A_7C15;
        return int'(h[63 -: MEM_LOG]);
    endfunction

    function automatic int find_slot(input bit [63:0] k);
        int i;
        i = slot_of(k);
        for (int n = 0; n < MEM_N; n++) begin
            if (!mem_used[i]) return -1;
            if (mem_key[i] == k) return i;
            i = (i + 1) % MEM_N;
        end
        return -1;
    endfunction

    function automatic int alloc_slot(input bit [63:0] k);
        int i;
        i = slot_of(k);
        for (int n = 0; n < MEM_N; n++) begin
            if (!mem_used[i] || mem_key[i] == k) begin
                if (!mem_used[i]) begin
                    mem_used[i]   = 1'b1;
                    mem_key[i]    = k;
                    mem_data[i]   = '0;
                    mem_vld[i]    = '0;
                    mem_poison[i] = 1'b0;
                end
                return i;
            end
            i = (i + 1) % MEM_N;
        end
        return -1;
    endfunction

    function automatic int errors();
        return err_p01 + err_p02 + err_p03 + err_p04 + err_d05 + err_d06 + err_w01;
    endfunction

    function automatic int rd_lat_avg();
        return (rd_done > 0) ? int'(rd_lat_sum / rd_done) : 0;
    endfunction

    function automatic int wr_lat_avg();
        return (wr_done > 0) ? int'(wr_lat_sum / wr_done) : 0;
    endfunction

    task automatic clear_mem();
        for (int i = 0; i < MEM_N; i++) begin
            mem_used[i]   = 1'b0;
            mem_vld[i]    = '0;
            mem_poison[i] = 1'b0;
        end
    endtask

    task automatic mark_poison_addr(input logic [AXI_ADDR_W-1:0] byte_addr);
        int s;
        s = alloc_slot(64'(byte_addr >> 3));
        if (s >= 0) mem_poison[s] = 1'b1;
    endtask

    task automatic bad(inout int cnt, input string what);
        cnt++;
        if (errors() <= 12) $display("[AXICHK-ERR] t=%0t cyc=%0d %s", $time, cyc, what);
    endtask

    task automatic final_check();
        for (int id = 0; id < N_IDS; id++) begin
            if (ar_q_wr[id] != ar_q_rd[id])
                bad(err_p03, $sformatf("end of test with %0d outstanding AR on ID %0d", ar_q_wr[id] - ar_q_rd[id], id));
            if (wr_b_wr[id] != wr_b_rd[id])
                bad(err_p03, $sformatf("end of test with %0d outstanding B on ID %0d", wr_b_wr[id] - wr_b_rd[id], id));
        end
        if (aw_pend_id.size() != 0)
            bad(err_p03, $sformatf("end of test with %0d AW awaiting W beats", aw_pend_id.size()));
    endtask

    task automatic report(input string tag);
        $display("  [AXICHK] %s: RD %0d/%0d (ok_beats=%0d err_beats=%0d lat min/avg/max=%0d/%0d/%0d) WR %0d/%0d (lat min/avg/max=%0d/%0d/%0d)",
                 tag, rd_done, rd_cmds, rd_ok_beats, rd_err_beats,
                 (rd_done > 0 ? rd_lat_min : 0), rd_lat_avg(), rd_lat_max,
                 wr_done, wr_cmds,
                 (wr_done > 0 ? wr_lat_min : 0), wr_lat_avg(), wr_lat_max);
        $display("  [AXICHK] %s: err P01 %0d P02 %0d P03 %0d P04 %0d D05 %0d D06 %0d W01 %0d",
                 tag, err_p01, err_p02, err_p03, err_p04, err_d05, err_d06, err_w01);
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (rst_n !== 1'b1) begin
            cyc         = 0;
            r_hold      = 0;
            b_hold      = 0;
            w_beat_idx  = 0;
            p04_flagged = 0;
            for (int id = 0; id < N_IDS; id++) begin
                ar_q_rd[id] = 0;
                ar_q_wr[id] = 0;
                wr_b_rd[id] = 0;
                wr_b_wr[id] = 0;
            end
            aw_pend_addr.delete();
            aw_pend_len.delete();
            aw_pend_id.delete();
            aw_pend_cyc.delete();
            w_pend_data.delete();
            w_pend_strb.delete();
            w_pend_last.delete();
        end else begin
            cyc++;

            // SA-P01: R giữ valid và payload tới khi bắt tay
            if (r_hold) begin
                if (!s_axi_rvalid ||
                    s_axi_rid     !== r_hold_id   ||
                    s_axi_rdata   !== r_hold_data ||
                    s_axi_rresp   !== r_hold_resp ||
                    s_axi_rlast   !== r_hold_last ||
                    s_axi_rpoison !== r_hold_poison) begin
                    bad(err_p01, "R channel changed or dropped valid before rready");
                end
            end
            r_hold        = s_axi_rvalid && !s_axi_rready;
            r_hold_id     = s_axi_rid;
            r_hold_data   = s_axi_rdata;
            r_hold_resp   = s_axi_rresp;
            r_hold_last   = s_axi_rlast;
            r_hold_poison = s_axi_rpoison;

            // SA-P02: B giữ valid và payload tới khi bắt tay
            if (b_hold) begin
                if (!s_axi_bvalid ||
                    s_axi_bid   !== b_hold_id ||
                    s_axi_bresp !== b_hold_resp) begin
                    bad(err_p02, "B channel changed or dropped valid before bready");
                end
            end
            b_hold      = s_axi_bvalid && !s_axi_bready;
            b_hold_id   = s_axi_bid;
            b_hold_resp = s_axi_bresp;

            // SA-D05: khi response lỗi hoặc poison, rdata phải bằng 0 (M-03.7)
            if (en_v2 && s_axi_rvalid && (s_axi_rresp != 2'b00 || (|s_axi_rpoison))) begin
                if (s_axi_rdata !== '0)
                    bad(err_d05, $sformatf("R error/poison with non-zero rdata=0x%016h (resp=%0b poison=%0b)",
                                           s_axi_rdata, s_axi_rresp, s_axi_rpoison));
            end

            // Ghi nhận AR bắt tay
            if (s_axi_arvalid && s_axi_arready) begin
                int id, slot;
                id   = int'(s_axi_arid);
                slot = ar_q_wr[id] % ID_Q;
                ar_q_addr[id][slot] = longint'(s_axi_araddr);
                ar_q_len[id][slot]  = int'(s_axi_arlen);
                ar_q_beat[id][slot] = 0;
                ar_q_cyc[id][slot]  = cyc;
                ar_q_wr[id]++;
                rd_cmds++;
                if (rd_cmds == 1 && wr_cmds == 0) rd_lat_min = 999999999;
            end

            // Ghi nhận AW bắt tay
            if (s_axi_awvalid && s_axi_awready) begin
                int id, slot;
                id   = int'(s_axi_awid);
                slot = wr_b_wr[id] % ID_Q;
                aw_pend_addr.push_back(longint'(s_axi_awaddr));
                aw_pend_len.push_back(int'(s_axi_awlen));
                aw_pend_id.push_back(id);
                aw_pend_cyc.push_back(cyc);
                wr_b_cyc[id][slot] = cyc;
                wr_b_wr[id]++;
                wr_cmds++;
                if (wr_cmds == 1 && rd_cmds <= 1) wr_lat_min = 999999999;
            end

            // Ghi nhận W bắt tay
            if (s_axi_wvalid && s_axi_wready) begin
                w_pend_data.push_back(s_axi_wdata);
                w_pend_strb.push_back(s_axi_wstrb);
                w_pend_last.push_back(s_axi_wlast);
            end

            // Ghép AW + W vào bộ nhớ tham chiếu theo thứ tự
            while (aw_pend_id.size() > 0 && w_pend_data.size() > 0) begin
                longint base_a, waddr, d_l;
                int     s, d_i;
                logic [AXI_DATA_W-1:0]   wd, cur_d;
                logic [AXI_DATA_W/8-1:0] ws, cur_v;
                bit                      wl;
                base_a = aw_pend_addr[0];
                waddr  = (base_a >> 3) + w_beat_idx;
                wd     = w_pend_data.pop_front();
                ws     = w_pend_strb.pop_front();
                wl     = w_pend_last.pop_front();

                s = alloc_slot(64'(waddr));
                if (s >= 0) begin
                    cur_d = mem_data[s];
                    cur_v = mem_vld[s];
                    for (int b = 0; b < AXI_DATA_W/8; b++) begin
                        if (ws[b]) begin
                            cur_d[b*8 +: 8] = wd[b*8 +: 8];
                            cur_v[b]        = 1'b1;
                        end
                    end
                    mem_data[s] = cur_d;
                    mem_vld[s]  = cur_v;
                    if (&ws) mem_poison[s] = 1'b0;
                end

                if (wl != (w_beat_idx == aw_pend_len[0])) begin
                    bad(err_p03, $sformatf("Wlast=%0b at beat %0d of awlen=%0d", wl, w_beat_idx, aw_pend_len[0]));
                end
                if (wl || (w_beat_idx == aw_pend_len[0])) begin
                    d_l = aw_pend_addr.pop_front();
                    d_i = aw_pend_len.pop_front();
                    d_i = aw_pend_id.pop_front();
                    d_l = aw_pend_cyc.pop_front();
                    w_beat_idx = 0;
                end else begin
                    w_beat_idx++;
                end
            end

            // Kiểm tra R bắt tay (SA-P03, SA-D06, SA-W01)
            if (s_axi_rvalid && s_axi_rready) begin
                int id;
                id = int'(s_axi_rid);
                if (ar_q_wr[id] == ar_q_rd[id]) begin
                    bad(err_p03, $sformatf("Unexpected R beat on ID %0d with no outstanding AR", id));
                end else begin
                    int     slot, k, ln, lat, s;
                    longint waddr;
                    slot  = ar_q_rd[id] % ID_Q;
                    k     = ar_q_beat[id][slot];
                    ln    = ar_q_len[id][slot];
                    waddr = (ar_q_addr[id][slot] >> 3) + k;

                    if (s_axi_rlast != (k == ln)) begin
                        bad(err_p03, $sformatf("ID %0d rlast=%0b at beat %0d of arlen=%0d", id, s_axi_rlast, k, ln));
                    end

                    if (s_axi_rresp == 2'b00 && s_axi_rpoison == '0) begin
                        rd_ok_beats++;
                        s = find_slot(64'(waddr));
                        if (chk_data_en && s >= 0 && mem_poison[s]) begin
                            bad(err_w01, $sformatf("Poisoned word addr=0x%0h returned OKAY without rpoison", waddr << 3));
                        end else if (chk_data_en && s >= 0 && (mem_vld[s] != '0)) begin
                            logic [AXI_DATA_W-1:0]   exp_d;
                            logic [AXI_DATA_W/8-1:0] vmask;
                            exp_d = mem_data[s];
                            vmask = mem_vld[s];
                            for (int b = 0; b < AXI_DATA_W/8; b++) begin
                                if (vmask[b] && (s_axi_rdata[b*8 +: 8] !== exp_d[b*8 +: 8])) begin
                                    bad(err_d06, $sformatf("SA-D06 mismatch at addr=0x%0h byte %0d: got 0x%02h exp 0x%02h (rdata=0x%016h exp=0x%016h)",
                                                           waddr << 3, b, s_axi_rdata[b*8 +: 8], exp_d[b*8 +: 8], s_axi_rdata, exp_d));
                                end
                            end
                        end
                    end else begin
                        rd_err_beats++;
                    end

                    if (s_axi_rlast || (k == ln)) begin
                        lat = int'(cyc - ar_q_cyc[id][slot]);
                        if (rd_done == 0 || lat < rd_lat_min) rd_lat_min = lat;
                        if (lat > rd_lat_max) rd_lat_max = lat;
                        rd_lat_sum += lat;
                        rd_done++;
                        ar_q_rd[id]++;
                    end else begin
                        ar_q_beat[id][slot] = k + 1;
                    end
                end
            end

            // Kiểm tra B bắt tay (SA-P03)
            if (s_axi_bvalid && s_axi_bready) begin
                int id, slot, lat;
                id = int'(s_axi_bid);
                if (wr_b_wr[id] == wr_b_rd[id]) begin
                    bad(err_p03, $sformatf("Unexpected B response on ID %0d with no outstanding AW", id));
                end else begin
                    slot = wr_b_rd[id] % ID_Q;
                    lat  = int'(cyc - wr_b_cyc[id][slot]);
                    wr_b_rd[id]++;
                    if (wr_done == 0 || lat < wr_lat_min) wr_lat_min = lat;
                    if (lat > wr_lat_max) wr_lat_max = lat;
                    wr_lat_sum += lat;
                    wr_done++;
                end
            end

            // SA-P04: kiểm tra tuổi giao dịch cũ nhất không vượt N_TXN
            if (!p04_flagged) begin
                for (int id = 0; id < N_IDS; id++) begin
                    if (ar_q_wr[id] != ar_q_rd[id]) begin
                        int slot;
                        slot = ar_q_rd[id] % ID_Q;
                        if (cyc - ar_q_cyc[id][slot] > N_TXN) begin
                            p04_flagged = 1'b1;
                            bad(err_p04, $sformatf("AR on ID %0d age %0d > N_TXN (%0d)", id, cyc - ar_q_cyc[id][slot], N_TXN));
                        end
                    end
                    if (wr_b_wr[id] != wr_b_rd[id]) begin
                        int slot;
                        slot = wr_b_rd[id] % ID_Q;
                        if (cyc - wr_b_cyc[id][slot] > N_TXN) begin
                            p04_flagged = 1'b1;
                            bad(err_p04, $sformatf("AW on ID %0d age %0d > N_TXN (%0d)", id, cyc - wr_b_cyc[id][slot], N_TXN));
                        end
                    end
                end
            end
        end
    end
endmodule
