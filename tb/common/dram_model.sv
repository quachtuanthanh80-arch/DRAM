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
    parameter int MEM_LOG = 16    // bảng băm 2^MEM_LOG word (dò tuyến tính, lưu khoá đầy đủ)
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
    localparam logic [2:0] RD = 3'd3, WR = 3'd4;
    localparam int MEM_N = 1 << MEM_LOG;
    localparam int RING  = 64;

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

    task automatic drop_head();
        longint a, t;
        int l;
        a = wq_base.pop_front();
        l = wq_len.pop_front();
        t = wq_t0.pop_front();
    endtask

    function automatic int errors();
        return err_dq_conflict + err_wr_beats + err_wr_orphan + err_mem_full;
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
        end else begin
            cyc++;
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
