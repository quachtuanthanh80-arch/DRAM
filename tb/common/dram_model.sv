// File:      dram_model.sv
// Chức năng: Mô hình DRAM hành vi cho testbench: lưu dữ liệu theo {BG, bank, row, word}, trả dữ liệu đọc sau RL và tự phát hiện lỗi bus DQ.
`timescale 1ns / 1ps

module dram_model
    import secded_72_64_pkg::*;
#(
    parameter int BG_W    = 3,
    parameter int BANK_W  = 2,
    parameter int ROW_W   = 17,
    parameter int COL_W   = 13,   // địa chỉ word 8 byte
    parameter int DW      = 64,
    parameter int RL      = 8,    // RD -> beat dữ liệu đầu tiên
    parameter int WL      = 1,    // WR -> beat dữ liệu đầu tiên
    parameter int MEM_LOG = 16,   // bảng băm 2^MEM_LOG word (dò tuyến tính, lưu khoá đầy đủ)
    parameter bit TRACK_RH     = 1'b0, // Bật bộ đếm nhiễu RowHammer/RowPress theo hàng nạn nhân (T82)
    parameter int RH_RADIUS    = 2,    // Bán kính hàng nạn nhân ±1..RH_RADIUS
    parameter int RH_W1        = 1,    // Trọng số khoảng cách ±1
    parameter int RH_W2        = 1,    // Trọng số khoảng cách ±2
    parameter int RH_W3        = 1,    // Trọng số khoảng cách ±3
    parameter int RH_TABLE_LOG = 13    // 2^RH_TABLE_LOG mục theo dõi hàng nạn nhân khi TRACK_RH=1
) (
    input  logic              clk,
    input  logic              rst_n,
    input  logic [2:0]        cmd,
    input  logic [BG_W-1:0]   bg,
    input  logic [BANK_W-1:0] bank,
    input  logic [ROW_W-1:0]  row,
    input  logic [COL_W-1:0]  col,
    input  logic [7:0]        len,         // số beat - 1 của lệnh CAS
    input  logic              wrdata_en,
    input  logic [DW-1:0]     wrdata,
    input  logic [DW/8-1:0]   wrdata_mask, // 1 = byte được ghi
    input  logic [DW/8-1:0]   wrdata_ecc = '0,
    output logic              rddata_valid,
    output logic [DW-1:0]     rddata,
    output logic [DW/8-1:0]   rddata_ecc
);
    localparam logic [2:0] ACT = 3'd1, PRE = 3'd2, RD = 3'd3, WR = 3'd4, REF = 3'd5, RFM = 3'd6;
    localparam int MEM_N        = 1 << MEM_LOG;
    localparam int RING         = 64;
    localparam int NBANKS       = 1 << (BG_W + BANK_W);
    localparam int RH_SLOT_BITS = TRACK_RH ? RH_TABLE_LOG : 2;
    localparam int RH_SLOTS     = 1 << RH_SLOT_BITS;
    localparam logic [ROW_W-1:0] RH_ROW_MAX = {ROW_W{1'b1}};

    // Bộ nhớ: bảng băm lưu khoá đầy đủ nên không bao giờ trả nhầm dữ liệu của ô khác (Icarus không có mảng kết hợp)
    bit [63:0]   mem_key  [MEM_N];
    bit [DW-1:0] mem_dat  [MEM_N];
    bit [DW/8-1:0] mem_ecc [MEM_N];
    bit          mem_used [MEM_N];
    int          mem_fill;

    // Lịch beat đọc theo chu kỳ (vòng đệm): phát hiện hai burst đọc đè nhau trên bus DQ
    bit        rs_valid [RING];
    bit [63:0] rs_key   [RING];

    longint cyc;
    int     n_rd, n_wr, err_dq_conflict, err_wr_beats, err_wr_orphan, err_mem_full;
    // Beat ghi thiếu byte: với ECC phủ cả word, ECC ghi kèm sẽ không khớp phần byte cũ (bộ điều khiển phải RMW)
    int     n_partial_wr;

    // Lệnh WR đang chờ beat dữ liệu (thứ tự phát lệnh)
    longint wq_base [$];
    int     wq_len  [$];
    longint wq_t0   [$];
    int     w_beat;

    // Bộ đếm nhiễu RowHammer và thời gian mở RowPress theo từng hàng nạn nhân (chỉ cấp phát đầy đủ khi TRACK_RH=1)
    bit               rh_bank_open      [NBANKS];
    bit [ROW_W-1:0]   rh_open_row       [NBANKS];
    longint           rh_open_start_cyc [NBANKS];
    bit [31:0]        rh_key            [RH_SLOTS];
    bit               rh_used           [RH_SLOTS];
    int               rh_disturb        [RH_SLOTS];
    int               rh_disturb_max    [RH_SLOTS];
    longint           rh_rp_open_cyc    [RH_SLOTS];
    longint           rh_rp_open_max    [RH_SLOTS];
    longint           rh_rp_single_max  [RH_SLOTS];
    int               rh_act_self       [RH_SLOTS];
    int               rh_user_act_self  [RH_SLOTS];
    int               rh_mit_act_self   [RH_SLOTS];
    bit               rh_ignore_mit_act = 1'b0;
    bit               rh_cur_act_is_mit = 1'b0;
    int               rh_table_fill;
    int               rh_err_table_full;
    longint           rh_total_acts;
    longint           rh_total_refs;
    longint           rh_total_rfms;
    int               rh_ref_ptr;
    int               rh_global_max_disturb;
    bit [31:0]        rh_global_max_disturb_key;
    longint           rh_global_max_rp_open_cyc;
    bit [31:0]        rh_global_max_rp_key;
    longint           rh_global_max_single_open_cyc;

    function automatic bit [63:0] word_key(input logic [BG_W-1:0] g, input logic [BANK_W-1:0] b,
                                           input logic [ROW_W-1:0] r, input longint w);
        return (64'(g) << 48) | (64'(b) << 44) | (64'(r) << 20) | (64'(w) & 64'hFFFFF);
    endfunction

    function automatic int slot_of(input bit [63:0] k);
        bit [63:0] h;
        h = k * 64'h9E37_79B9_7F4A_7C15;
        return int'(h[63 -: MEM_LOG]);
    endfunction

    function automatic int find(input bit [63:0] k);
        int i;
        i = slot_of(k);
        for (int n = 0; n < MEM_N; n++) begin
            if (!mem_used[i]) return -1;
            if (mem_key[i] == k) return i;
            i = (i + 1) % MEM_N;
        end
        return -1;
    endfunction

    // Ô chưa ghi trả giá trị suy ra từ địa chỉ: đọc nhầm ô sẽ không trùng ngẫu nhiên với dữ liệu đã ghi
    function automatic bit [DW-1:0] peek(input bit [63:0] k);
        int i;
        i = find(k);
        if (i >= 0) return mem_dat[i];
        return DW'({16'hDEAD, k[47:0]});
    endfunction

    function automatic bit [DW/8-1:0] peek_ecc(input bit [63:0] k);
        int i;
        i = find(k);
        if (i >= 0) return mem_ecc[i];
        // Ô chưa ghi coi như đã khởi tạo ECC lúc boot (BIOS/ECC init): trả codeword hợp lệ của giá trị suy ra
        begin
            bit [DW-1:0]   v;
            bit [DW/8-1:0] e;
            v = peek(k);
            for (int l = 0; l < DW / 64; l++) e[l*8 +: 8] = secded72_enc(v[l*64 +: 64]);
            return e;
        end
    endfunction

    // Tiêm lỗi: đảo bit của word đã lưu (dữ liệu và/hoặc ECC), mô phỏng lỗi giữ điện tích hay bit lật do RowHammer
    function automatic bit [63:0] key_of(input logic [BG_W-1:0] g, input logic [BANK_W-1:0] b,
                                          input logic [ROW_W-1:0] r, input logic [COL_W-1:0] c);
        return word_key(g, b, r, longint'(c));
    endfunction

    task automatic flip(input bit [63:0] k, input bit [DW-1:0] dmask, input bit [DW/8-1:0] emask, output bit found);
        int i;
        i = find(k);
        found = (i >= 0);
        if (found) begin
            mem_dat[i] ^= dmask;
            mem_ecc[i] ^= emask;
        end
    endtask

    task automatic poke(input bit [63:0] k, input bit [DW-1:0] v, input bit [DW/8-1:0] e);
        int i;
        bit done;
        i = slot_of(k);
        done = 0;
        for (int n = 0; n < MEM_N && !done; n++) begin
            if (!mem_used[i] || mem_key[i] == k) begin
                if (!mem_used[i]) mem_fill++;
                mem_used[i] = 1;
                mem_key[i]  = k;
                mem_dat[i]  = v;
                mem_ecc[i]  = e;
                done = 1;
            end else begin
                i = (i + 1) % MEM_N;
            end
        end
        if (!done) err_mem_full++;
    endtask

    // Task backdoor hỗ trợ kiểm thử và tiêm lỗi toàn vẹn (T38)
    task automatic backdoor_read_word(input logic [BG_W-1:0] g, input logic [BANK_W-1:0] b,
                                      input logic [ROW_W-1:0] r, input logic [COL_W-1:0] c,
                                      output bit [DW-1:0] val);
        val = peek(word_key(g, b, r, longint'(c)));
    endtask

    task automatic backdoor_write_word(input logic [BG_W-1:0] g, input logic [BANK_W-1:0] b,
                                       input logic [ROW_W-1:0] r, input logic [COL_W-1:0] c,
                                       input bit [DW-1:0] val);
        bit [DW/8-1:0] e;
        for (int l = 0; l < DW / 64; l++) e[l*8 +: 8] = secded72_enc(val[l*64 +: 64]);
        poke(word_key(g, b, r, longint'(c)), val, e);
    endtask

    task automatic backdoor_flip_bit(input logic [BG_W-1:0] g, input logic [BANK_W-1:0] b,
                                     input logic [ROW_W-1:0] r, input logic [COL_W-1:0] c,
                                     input int bit_idx);
        int i;
        bit [63:0] k;
        k = word_key(g, b, r, longint'(c));
        i = find(k);
        if (i >= 0) begin
            mem_dat[i] ^= ({{(DW-1){1'b0}}, 1'b1} << bit_idx);
            for (int l = 0; l < DW / 64; l++) begin
                mem_ecc[i][l*8 +: 8] = secded72_enc(mem_dat[i][l*64 +: 64]);
            end
        end
    endtask

    task automatic drop_head();
        longint a, t;
        int l;
        a = wq_base.pop_front();
        l = wq_len.pop_front();
        t = wq_t0.pop_front();
    endtask

    // Hàm và task theo dõi nhiễu RowHammer / thời gian mở RowPress theo từng hàng nạn nhân
    function automatic bit [31:0] rh_row_key(input logic [BG_W-1:0] g, input logic [BANK_W-1:0] b,
                                             input logic [ROW_W-1:0] r);
        return (32'(g) << (BANK_W + ROW_W)) | (32'(b) << ROW_W) | 32'(r);
    endfunction

    function automatic int rh_slot_of(input bit [31:0] k);
        bit [31:0] h;
        h = k * 32'h9E37_79B1;
        return int'(h[31 -: RH_SLOT_BITS]);
    endfunction

    function automatic int rh_find(input bit [31:0] k);
        int i;
        i = rh_slot_of(k);
        for (int n = 0; n < RH_SLOTS; n++) begin
            if (!rh_used[i]) return -1;
            if (rh_key[i] == k) return i;
            i = (i + 1) % RH_SLOTS;
        end
        return -1;
    endfunction

    function automatic int rh_weight(input int d);
        if (d == 1) return RH_W1;
        if (d == 2) return RH_W2;
        if (d == 3) return RH_W3;
        return 0;
    endfunction

    task automatic rh_get_or_alloc(input bit [31:0] k, output int idx);
        int i;
        bit done;
        i = rh_slot_of(k);
        idx = -1;
        done = 1'b0;
        for (int n = 0; n < RH_SLOTS && !done; n++) begin
            if (!rh_used[i] || rh_key[i] == k) begin
                if (!rh_used[i]) begin
                    rh_used[i]          = 1'b1;
                    rh_key[i]           = k;
                    rh_disturb[i]       = 0;
                    rh_disturb_max[i]   = 0;
                    rh_rp_open_cyc[i]   = 0;
                    rh_rp_open_max[i]   = 0;
                    rh_rp_single_max[i] = 0;
                    rh_act_self[i]      = 0;
                    rh_user_act_self[i] = 0;
                    rh_mit_act_self[i]  = 0;
                    rh_table_fill++;
                end
                idx  = i;
                done = 1'b1;
            end else begin
                i = (i + 1) % RH_SLOTS;
            end
        end
        if (!done) rh_err_table_full++;
    endtask

    task automatic rh_credit_act_one(input bit [31:0] nk, input int w);
        int idx;
        rh_get_or_alloc(nk, idx);
        if (idx >= 0) begin
            rh_disturb[idx] += w;
            if (rh_disturb[idx] > rh_disturb_max[idx])
                rh_disturb_max[idx] = rh_disturb[idx];
            if (rh_disturb[idx] > rh_global_max_disturb) begin
                rh_global_max_disturb     = rh_disturb[idx];
                rh_global_max_disturb_key = nk;
            end
        end
    endtask

    task automatic rh_credit_rp_one(input bit [31:0] nk, input longint dur, input longint w_dur);
        int idx;
        rh_get_or_alloc(nk, idx);
        if (idx >= 0) begin
            rh_rp_open_cyc[idx] += w_dur;
            if (rh_rp_open_cyc[idx] > rh_rp_open_max[idx])
                rh_rp_open_max[idx] = rh_rp_open_cyc[idx];
            if (dur > rh_rp_single_max[idx])
                rh_rp_single_max[idx] = dur;
            if (rh_rp_open_cyc[idx] > rh_global_max_rp_open_cyc) begin
                rh_global_max_rp_open_cyc = rh_rp_open_cyc[idx];
                rh_global_max_rp_key      = nk;
            end
        end
    endtask

    task automatic rh_credit_rp(input logic [BG_W-1:0] g, input logic [BANK_W-1:0] b,
                                input logic [ROW_W-1:0] open_r, input longint dur);
        int d, w;
        longint r_base, w_dur;
        logic [ROW_W-1:0] n_row;
        if (dur > 0) begin
            if (dur > rh_global_max_single_open_cyc) rh_global_max_single_open_cyc = dur;
            r_base = longint'(open_r);
            for (d = 1; d <= RH_RADIUS; d++) begin
                w = rh_weight(d);
                if (w > 0) begin
                    w_dur = dur * longint'(w);
                    if (r_base + longint'(d) <= longint'(RH_ROW_MAX)) begin
                        n_row = ROW_W'(r_base + longint'(d));
                        rh_credit_rp_one(rh_row_key(g, b, n_row), dur, w_dur);
                    end
                    if (r_base >= longint'(d)) begin
                        n_row = ROW_W'(r_base - longint'(d));
                        rh_credit_rp_one(rh_row_key(g, b, n_row), dur, w_dur);
                    end
                end
            end
        end
    endtask

    task automatic rh_reset_counters();
        int i;
        for (i = 0; i < NBANKS; i++) begin
            rh_bank_open[i]      = 1'b0;
            rh_open_row[i]       = '0;
            rh_open_start_cyc[i] = 0;
        end
        for (i = 0; i < RH_SLOTS; i++) begin
            rh_key[i]           = '0;
            rh_used[i]          = 1'b0;
            rh_disturb[i]       = 0;
            rh_disturb_max[i]   = 0;
            rh_rp_open_cyc[i]   = 0;
            rh_rp_open_max[i]   = 0;
            rh_rp_single_max[i] = 0;
            rh_act_self[i]      = 0;
            rh_user_act_self[i] = 0;
            rh_mit_act_self[i]  = 0;
        end
        rh_table_fill                 = 0;
        rh_err_table_full             = 0;
        rh_total_acts                 = 0;
        rh_total_refs                 = 0;
        rh_total_rfms                 = 0;
        rh_ref_ptr                    = 0;
        rh_global_max_disturb         = 0;
        rh_global_max_disturb_key     = '0;
        rh_global_max_rp_open_cyc     = 0;
        rh_global_max_rp_key          = '0;
        rh_global_max_single_open_cyc = 0;
    endtask

    task automatic rh_flush_open_banks();
        int b_idx;
        logic [BG_W+BANK_W-1:0] gb_vec;
        logic [BG_W-1:0] g;
        logic [BANK_W-1:0] bk;
        if (TRACK_RH) begin
            for (b_idx = 0; b_idx < NBANKS; b_idx++) begin
                if (rh_bank_open[b_idx]) begin
                    gb_vec = (BG_W+BANK_W)'(b_idx);
                    g      = gb_vec[BG_W+BANK_W-1 : BANK_W];
                    bk     = gb_vec[BANK_W-1 : 0];
                    rh_credit_rp(g, bk, rh_open_row[b_idx], cyc - rh_open_start_cyc[b_idx]);
                    rh_open_start_cyc[b_idx] = cyc;
                end
            end
        end
    endtask

    function automatic int rh_get_disturb_max(input logic [BG_W-1:0] g, input logic [BANK_W-1:0] b,
                                              input logic [ROW_W-1:0] r);
        int idx;
        if (!TRACK_RH) return 0;
        idx = rh_find(rh_row_key(g, b, r));
        return (idx >= 0) ? rh_disturb_max[idx] : 0;
    endfunction

    function automatic int rh_get_disturb_cur(input logic [BG_W-1:0] g, input logic [BANK_W-1:0] b,
                                              input logic [ROW_W-1:0] r);
        int idx;
        if (!TRACK_RH) return 0;
        idx = rh_find(rh_row_key(g, b, r));
        return (idx >= 0) ? rh_disturb[idx] : 0;
    endfunction

    function automatic int rh_get_user_act_self(input logic [BG_W-1:0] g, input logic [BANK_W-1:0] b,
                                                input logic [ROW_W-1:0] r);
        int idx;
        if (!TRACK_RH) return 0;
        idx = rh_find(rh_row_key(g, b, r));
        return (idx >= 0) ? rh_user_act_self[idx] : 0;
    endfunction

    function automatic int rh_get_mit_act_self(input logic [BG_W-1:0] g, input logic [BANK_W-1:0] b,
                                               input logic [ROW_W-1:0] r);
        int idx;
        if (!TRACK_RH) return 0;
        idx = rh_find(rh_row_key(g, b, r));
        return (idx >= 0) ? rh_mit_act_self[idx] : 0;
    endfunction

    function automatic longint rh_get_rp_open_max(input logic [BG_W-1:0] g, input logic [BANK_W-1:0] b,
                                                  input logic [ROW_W-1:0] r);
        int idx;
        if (!TRACK_RH) return 0;
        idx = rh_find(rh_row_key(g, b, r));
        return (idx >= 0) ? rh_rp_open_max[idx] : 0;
    endfunction

    function automatic longint rh_get_rp_single_max(input logic [BG_W-1:0] g, input logic [BANK_W-1:0] b,
                                                    input logic [ROW_W-1:0] r);
        int idx;
        if (!TRACK_RH) return 0;
        idx = rh_find(rh_row_key(g, b, r));
        return (idx >= 0) ? rh_rp_single_max[idx] : 0;
    endfunction

    function automatic int rh_get_global_max_disturb();
        return TRACK_RH ? rh_global_max_disturb : 0;
    endfunction

    function automatic longint rh_get_global_max_rp_open();
        return TRACK_RH ? rh_global_max_rp_open_cyc : 0;
    endfunction

    function automatic longint rh_get_global_max_single_open();
        return TRACK_RH ? rh_global_max_single_open_cyc : 0;
    endfunction

    function automatic int errors();
        return err_dq_conflict + err_wr_beats + err_wr_orphan + err_mem_full + (TRACK_RH ? rh_err_table_full : 0);
    endfunction

    task automatic report(input string tag);
        $display("  [DRAM] %s: RD %0d, WR %0d, words stored %0d; DQ read-burst overlap %0d, WR beat-count mismatch %0d, orphan write data %0d",
                 tag, n_rd, n_wr, mem_fill, err_dq_conflict, err_wr_beats, err_wr_orphan);
    endtask

    // Nội dung DRAM giữ qua reset của bộ điều khiển (như DRAM thật); chỉ trạng thái bus/lệnh bị xoá
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cyc = 0;
            for (int r = 0; r < RING; r++) rs_valid[r] = 0;
            wq_base.delete();
            wq_len.delete();
            wq_t0.delete();
            w_beat = 0;
            rddata_valid <= 1'b0;
            if (TRACK_RH) rh_reset_counters();
        end else begin
            cyc++;
            if (TRACK_RH) begin
                if (cmd == ACT) begin
                    int b_idx, s_idx, d, w;
                    longint r_base;
                    logic [ROW_W-1:0] n_row;
                    bit [31:0] sk;
                    rh_total_acts++;
                    b_idx = (int'(bg) << BANK_W) | int'(bank);
                    rh_bank_open[b_idx]      = 1'b1;
                    rh_open_row[b_idx]       = row;
                    rh_open_start_cyc[b_idx] = cyc;
                    sk = rh_row_key(bg, bank, row);
                    rh_get_or_alloc(sk, s_idx);
                    if (s_idx >= 0) begin
                        rh_act_self[s_idx]++;
                        if (rh_cur_act_is_mit) rh_mit_act_self[s_idx]++;
                        else                   rh_user_act_self[s_idx]++;
                        rh_disturb[s_idx]     = 0;
                        rh_rp_open_cyc[s_idx] = 0;
                    end
                    if (!(rh_ignore_mit_act && rh_cur_act_is_mit)) begin
                        r_base = longint'(row);
                        for (d = 1; d <= RH_RADIUS; d++) begin
                            w = rh_weight(d);
                            if (w > 0) begin
                                if (r_base + longint'(d) <= longint'(RH_ROW_MAX)) begin
                                    n_row = ROW_W'(r_base + longint'(d));
                                    rh_credit_act_one(rh_row_key(bg, bank, n_row), w);
                                end
                                if (r_base >= longint'(d)) begin
                                    n_row = ROW_W'(r_base - longint'(d));
                                    rh_credit_act_one(rh_row_key(bg, bank, n_row), w);
                                end
                            end
                        end
                    end
                end
                if (cmd == PRE) begin
                    int b_idx;
                    b_idx = (int'(bg) << BANK_W) | int'(bank);
                    if (rh_bank_open[b_idx]) begin
                        rh_credit_rp(bg, bank, rh_open_row[b_idx], cyc - rh_open_start_cyc[b_idx]);
                        rh_bank_open[b_idx] = 1'b0;
                    end
                end
                if (cmd == REF) begin
                    bit [12:0] ref_row_lsb;
                    rh_total_refs++;
                    ref_row_lsb = 13'(rh_ref_ptr);
                    // Một tREFW gồm 8192 lệnh REFab: mỗi REFab làm tươi các hàng có row[12:0] khớp con trỏ xoay vòng
                    for (int i = 0; i < RH_SLOTS; i++) begin
                        if (rh_used[i] && (rh_key[i][12:0] == ref_row_lsb)) begin
                            rh_disturb[i]     = 0;
                            rh_rp_open_cyc[i] = 0;
                        end
                    end
                    rh_ref_ptr = (rh_ref_ptr + 1) & 8191;
                end
                if (cmd == RFM) begin
                    rh_total_rfms++;
                end
            end
            if (cmd == RD) begin
                n_rd++;
                for (int b = 0; b <= len; b++) begin
                    int r;
                    r = int'((cyc + RL + b) % RING);
                    if (rs_valid[r]) err_dq_conflict++;
                    rs_valid[r] = 1;
                    rs_key[r]   = word_key(bg, bank, row, longint'(col) + b);
                end
            end
            if (cmd == WR) begin
                n_wr++;
                wq_base.push_back(longint'(word_key(bg, bank, row, longint'(col))));
                wq_len.push_back(int'(len));
                wq_t0.push_back(cyc + WL);
            end
            if (wrdata_en) begin
                if (wq_base.size() == 0) begin
                    err_wr_orphan++;
                end else begin
                    bit [63:0] k;
                    bit [DW-1:0] v;
                    k = 64'(wq_base[0]) + 64'(w_beat);
                    v = peek(k);
                    for (int by = 0; by < DW / 8; by++)
                        if (wrdata_mask[by]) v[by*8 +: 8] = wrdata[by*8 +: 8];
                    if (wrdata_mask != '1) n_partial_wr++;
                    poke(k, v, wrdata_ecc);
                    if (w_beat == wq_len[0]) begin
                        w_beat = 0;
                        drop_head();
                    end else begin
                        w_beat++;
                    end
                end
            end else if (wq_t0.size() > 0 && cyc > wq_t0[0] + wq_len[0] + 2) begin
                // Lệnh WR quá hạn mà chưa nhận đủ beat
                err_wr_beats++;
                w_beat = 0;
                drop_head();
            end
            begin
                int r;
                r = int'((cyc + 1) % RING);
                if (rs_valid[r]) begin
                    rddata_valid <= 1'b1;
                    rddata       <= peek(rs_key[r]);
                    rddata_ecc   <= peek_ecc(rs_key[r]);
                    rs_valid[r]  = 0;
                end else begin
                    rddata_valid <= 1'b0;
                end
            end
        end
    end
endmodule
