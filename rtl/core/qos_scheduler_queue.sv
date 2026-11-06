//=============================================================================
// File:        qos_scheduler_queue.sv
// Chức năng:   Hàng đợi lệnh phân bổ theo QoS cho từng Bank Group có bộ đếm tăng tuổi chống bỏ đói luồng.
//=============================================================================
`timescale 1ns / 1ps

/* verilator lint_off UNUSEDPARAM */
module qos_scheduler_queue #(
    parameter int AXI_ID_WIDTH     = 4,
    parameter int AXI_QOS_WIDTH    = 4,
    parameter int NUM_BG           = 8,
    parameter int BG_WIDTH          = 3,
    parameter int QUEUE_DEPTH      = 4,
    parameter int BANK_WIDTH       = 2,
    parameter int ROW_WIDTH        = 16,
    parameter int COL_WIDTH        = 10,
    parameter int STARVATION_LIMIT = 64
)(
    input  logic                                         clk,
    input  logic                                         rst_n,

    // Ingress from Frontend / SDC Filter
    input  logic                                         i_cmd_valid,
    input  logic [AXI_ID_WIDTH-1:0]                      i_cmd_id,
    input  logic                                         i_cmd_is_write,
    input  logic [$clog2(NUM_BG)-1:0]                    i_cmd_bg,
    input  logic [BANK_WIDTH-1:0]                        i_cmd_bank,
    input  logic [ROW_WIDTH-1:0]                         i_cmd_row,
    input  logic [COL_WIDTH-1:0]                         i_cmd_col,
    input  logic [7:0]                                   i_cmd_len,
    input  logic [AXI_QOS_WIDTH-1:0]                     i_cmd_qos,
    input  logic                                         i_cmd_throttled,
    output logic                                         o_cmd_ready,

    // Egress Candidates per Bank Group to Arbiter
    output logic [NUM_BG-1:0]                            o_cand_valid,
    output logic [NUM_BG*AXI_ID_WIDTH-1:0]               o_cand_id,
    output logic [NUM_BG-1:0]                            o_cand_is_write,
    output logic [NUM_BG*BANK_WIDTH-1:0]                 o_cand_bank,
    output logic [NUM_BG*ROW_WIDTH-1:0]                  o_cand_row,
    output logic [NUM_BG*COL_WIDTH-1:0]                  o_cand_col,
    output logic [NUM_BG*8-1:0]                          o_cand_len,
    output logic [NUM_BG*AXI_QOS_WIDTH-1:0]              o_cand_qos,
    output logic [NUM_BG-1:0]                            o_cand_throttled,
    output logic [NUM_BG-1:0]                            o_cand_starved,
    output logic [NUM_BG*$clog2(QUEUE_DEPTH)-1:0]        o_cand_entry_idx,
    // Ứng viên giữ nguyên entry so với chu kỳ trước: kết quả kiểm tra PROQ (trễ một chu kỳ) còn áp dụng được
    output logic [NUM_BG-1:0]                            o_cand_fresh,

    // Slot lệnh từng bank của engine còn trống: entry tới bank đang bận không được chọn làm ứng viên,
    // nên một bank bận không chặn các bank khác cùng BG
    input  logic [NUM_BG*(1<<BANK_WIDTH)-1:0]            i_bank_free = '1,

    // Issue Feedback from Backend Arbiter
    input  logic                                         i_issue_grant_valid,
    input  logic [$clog2(NUM_BG)-1:0]                    i_issue_grant_bg,
    input  logic [$clog2(QUEUE_DEPTH)-1:0]               i_issue_grant_idx
);

    localparam int TOTAL_ENTRIES = NUM_BG * QUEUE_DEPTH;
    localparam int BG_W          = $clog2(NUM_BG);
    localparam int IDX_W         = $clog2(QUEUE_DEPTH);

    // Parallel 1D Logic Arrays for Synthesis & Formal
    logic [TOTAL_ENTRIES-1:0]                    q_valid;
    logic [AXI_ID_WIDTH-1:0]  q_id               [TOTAL_ENTRIES-1:0];
    logic                     q_is_write         [TOTAL_ENTRIES-1:0];
    logic [BANK_WIDTH-1:0]    q_bank             [TOTAL_ENTRIES-1:0];
    logic [ROW_WIDTH-1:0]     q_row              [TOTAL_ENTRIES-1:0];
    logic [COL_WIDTH-1:0]     q_col              [TOTAL_ENTRIES-1:0];
    logic [7:0]               q_len              [TOTAL_ENTRIES-1:0];
    logic [AXI_QOS_WIDTH-1:0] q_qos              [TOTAL_ENTRIES-1:0];
    logic [TOTAL_ENTRIES-1:0]                    q_throttled;
    logic [7:0]               q_age              [TOTAL_ENTRIES-1:0];
    // q_dep[s][k] = 1: entry s phải chờ entry k cùng BG (cũ hơn, cùng {bank,row,col}, ít nhất một bên là ghi).
    // Chọn theo QoS/tuổi tự do sẽ đảo RAW/WAR/WAW: lệnh ghi đã rời wdata_buffer không còn được ROB chặn (R21).
    logic [QUEUE_DEPTH-1:0]   q_dep              [TOTAL_ENTRIES-1:0];

    // Status: full per BG
    logic [NUM_BG-1:0] bg_queue_full;
    always_comb begin
        for (int bg = 0; bg < NUM_BG; bg++) begin
            bg_queue_full[bg] = 1'b1;
            for (int e = 0; e < QUEUE_DEPTH; e++) begin
                if (!q_valid[bg * QUEUE_DEPTH + e]) begin
                    bg_queue_full[bg] = 1'b0;
                end
            end
        end
    end

    // Ready if target Bank Group queue has at least 1 free slot
    assign o_cmd_ready = !bg_queue_full[i_cmd_bg];

    // Find free slot for ingress
    logic [IDX_W-1:0] free_slot_idx;
    logic             free_slot_found;
    always_comb begin
        free_slot_found = 1'b0;
        free_slot_idx   = '0;
        for (int e = 0; e < QUEUE_DEPTH; e++) begin
            if (!free_slot_found && !q_valid[i_cmd_bg * QUEUE_DEPTH + e]) begin
                free_slot_found = 1'b1;
                free_slot_idx   = IDX_W'(e);
            end
        end
    end

    // Ô sẽ nhận lệnh mới dạng one-hot trên toàn bảng: ô trống đầu tiên của mỗi BG tính song song từ q_valid, AND với BG
    // đích. Cập nhật tuổi/khoá của từng entry dùng bit này thay vì so sánh lại chỉ số đã mã hoá.
    logic [TOTAL_ENTRIES-1:0] enq_oh;
    always_comb
        for (int bg = 0; bg < NUM_BG; bg++) begin
            logic [QUEUE_DEPTH-1:0] fr;
            fr = ~q_valid[bg * QUEUE_DEPTH +: QUEUE_DEPTH];
            enq_oh[bg * QUEUE_DEPTH +: QUEUE_DEPTH] = (i_cmd_valid && i_cmd_bg == BG_W'(bg)) ? (fr & (~fr + 1'b1)) : '0;
        end

    // Phụ thuộc của lệnh mới: so với 8 entry của BG đích tại thời điểm nạp (rẻ hơn so sánh cặp mỗi chu kỳ).
    // Entry đang được cấp trong cùng chu kỳ bị loại vì nó đã rời hàng đợi.
    logic [QUEUE_DEPTH-1:0] new_dep;
    always_comb begin
        for (int e = 0; e < QUEUE_DEPTH; e++) begin
            int s_idx;
            s_idx = 32'(i_cmd_bg) * QUEUE_DEPTH + e;
            // Burst phủ khoảng word [col, col+len]: xung đột khi hai khoảng chồng nhau, không chỉ khi trùng cột bắt đầu
            new_dep[e] = q_valid[s_idx] &&
                         !(i_issue_grant_valid && i_issue_grant_bg == i_cmd_bg && i_issue_grant_idx == IDX_W'(e)) &&
                         (q_bank[s_idx] == i_cmd_bank) && (q_row[s_idx] == i_cmd_row) &&
                         !((COL_WIDTH+1)'(q_col[s_idx]) + (COL_WIDTH+1)'(q_len[s_idx]) < (COL_WIDTH+1)'(i_cmd_col) ||
                           (COL_WIDTH+1)'(i_cmd_col) + (COL_WIDTH+1)'(i_cmd_len) < (COL_WIDTH+1)'(q_col[s_idx])) &&
                         (q_is_write[s_idx] || i_cmd_is_write);
        end
    end

    // Sequential Queue Management: Enqueue, Dequeue, Age increment
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q_valid     <= '0;
            q_throttled <= '0;
            for (int i = 0; i < TOTAL_ENTRIES; i++) begin
                q_id[i]       <= '0;
                q_is_write[i] <= 1'b0;
                q_bank[i]     <= '0;
                q_row[i]      <= '0;
                q_col[i]      <= '0;
                q_len[i]      <= '0;
                q_qos[i]      <= '0;
                q_age[i]      <= 8'd0;
                q_dep[i]      <= '0;
            end
        end else begin
            // 1. Dequeue on Grant: giải phóng mọi entry cùng BG đang chờ entry này
            if (i_issue_grant_valid) begin
                q_valid[i_issue_grant_bg * QUEUE_DEPTH + 32'(i_issue_grant_idx)] <= 1'b0;
                for (int e = 0; e < QUEUE_DEPTH; e++)
                    q_dep[i_issue_grant_bg * QUEUE_DEPTH + e][i_issue_grant_idx] <= 1'b0;
            end

            // 2. Enqueue incoming command
            if (i_cmd_valid && o_cmd_ready && free_slot_found) begin
                q_valid[i_cmd_bg * QUEUE_DEPTH + 32'(free_slot_idx)]     <= 1'b1;
                q_id[i_cmd_bg * QUEUE_DEPTH + 32'(free_slot_idx)]        <= i_cmd_id;
                q_is_write[i_cmd_bg * QUEUE_DEPTH + 32'(free_slot_idx)]  <= i_cmd_is_write;
                q_bank[i_cmd_bg * QUEUE_DEPTH + 32'(free_slot_idx)]      <= i_cmd_bank;
                q_row[i_cmd_bg * QUEUE_DEPTH + 32'(free_slot_idx)]       <= i_cmd_row;
                q_col[i_cmd_bg * QUEUE_DEPTH + 32'(free_slot_idx)]       <= i_cmd_col;
                q_len[i_cmd_bg * QUEUE_DEPTH + 32'(free_slot_idx)]       <= i_cmd_len;
                q_qos[i_cmd_bg * QUEUE_DEPTH + 32'(free_slot_idx)]       <= i_cmd_qos;
                q_throttled[i_cmd_bg * QUEUE_DEPTH + 32'(free_slot_idx)] <= i_cmd_throttled;
                q_age[i_cmd_bg * QUEUE_DEPTH + 32'(free_slot_idx)]       <= 8'd0;
                q_dep[i_cmd_bg * QUEUE_DEPTH + 32'(free_slot_idx)]       <= new_dep;
            end

            // 3. Age increment for all waiting entries (saturating at 255)
            for (int bg = 0; bg < NUM_BG; bg++) begin
                for (int e = 0; e < QUEUE_DEPTH; e++) begin
                    int s_idx;
                    bit is_deq;
                    bit is_enq;
                    s_idx = bg * QUEUE_DEPTH + e;
                    is_deq = (i_issue_grant_valid && (i_issue_grant_bg == BG_W'(bg)) && (i_issue_grant_idx == IDX_W'(e)));
                    is_enq = enq_oh[s_idx];

                    if (q_valid[s_idx] && !is_deq && !is_enq) begin
                        if (q_age[s_idx] != 8'hFF) begin
                            q_age[s_idx] <= q_age[s_idx] + 1'b1;
                        end
                    end
                end
            end
        end
    end

    //=========================================================================
    // Chọn ứng viên mỗi Bank Group: so sánh cặp song song thay cho chuỗi "is_better" nối tiếp 8 tầng.
    // Khoá ưu tiên = {đói, không bị throttle, QoS hiệu dụng (QoS + age/16, bão hoà 15), tuổi}; so sánh từ điển trên
    // khoá này trùng thứ tự của chuỗi nối tiếp cũ (thay khi tốt hơn hẳn), hoà thì entry chỉ số thấp thắng.
    // Leo thang ưu tiên theo tuổi (Le et al. 2017): +1 mức QoS mỗi 16 chu kỳ chờ, chặn nghẽn luồng nền.
    //=========================================================================
    localparam int KEY_W = 2 + AXI_QOS_WIDTH + 8;
    // Khoá ưu tiên được đăng ký (tuổi trễ một chu kỳ chỉ đổi thứ tự ưu tiên, không đổi tính hợp lệ); tính hợp lệ
    // (valid, phụ thuộc, slot bank) vẫn lấy theo trạng thái hiện tại. Entry vừa nạp lấy khoá từ chính lệnh vào (tuổi 0)
    // để lệnh QoS cao vượt được ngay từ chu kỳ đầu tiên nó hợp lệ.
    logic [KEY_W-1:0]         ent_key  [TOTAL_ENTRIES];
    logic [TOTAL_ENTRIES-1:0] ent_elig;
    // Khoá kế tiếp; ma trận "f thắng e" của cùng BG được tính cho khoá kế tiếp và đăng ký cùng khoá, nên bộ chọn ứng
    // viên chỉ còn AND/OR trên flop. Phép so sánh 13 bit chỉ dùng khoá "già thêm" key_a (từ thanh ghi) và so khoá của
    // lệnh mới với từng entry (song song); ô vừa nạp (enq_oh) chỉ chọn kết quả ở tầng cuối.
    logic [KEY_W-1:0]       key_a   [TOTAL_ENTRIES];
    logic [KEY_W-1:0]       key_n   [TOTAL_ENTRIES];
    logic [TOTAL_ENTRIES-1:0] ge_new, gt_new;
    logic [QUEUE_DEPTH-1:0] beats_q [TOTAL_ENTRIES];   // beats_q[e][f]: entry f của cùng BG thắng entry e
    wire  [KEY_W-1:0]       new_key = {1'b0, !i_cmd_throttled, i_cmd_qos, 8'd0};
    always_comb
        for (int i = 0; i < TOTAL_ENTRIES; i++) begin
            logic [4:0] eff;
            eff = 5'(q_qos[i]) + 5'(q_age[i][7:4]);
            if (eff > 5'd15) eff = 5'd15;
            key_a[i]  = {q_age[i] >= STARVATION_LIMIT[7:0], !q_throttled[i], AXI_QOS_WIDTH'(eff), q_age[i]};
            key_n[i]  = enq_oh[i] ? new_key : key_a[i];
            ge_new[i] = key_a[i] >= new_key;
            gt_new[i] = key_a[i] >  new_key;
        end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < TOTAL_ENTRIES; i++) begin
                ent_key[i] <= '0;
                beats_q[i] <= '0;
            end
        end else begin
            for (int bg = 0; bg < NUM_BG; bg++)
                for (int e = 0; e < QUEUE_DEPTH; e++) begin
                    ent_key[bg * QUEUE_DEPTH + e] <= key_n[bg * QUEUE_DEPTH + e];
                    // Hoà khoá: entry chỉ số thấp thắng
                    for (int f = 0; f < QUEUE_DEPTH; f++) begin
                        int ie, jf;
                        ie = bg * QUEUE_DEPTH + e;
                        jf = bg * QUEUE_DEPTH + f;
                        if (f == e)          beats_q[ie][f] <= 1'b0;
                        else if (enq_oh[ie]) beats_q[ie][f] <= (f < e) ? ge_new[jf] : gt_new[jf];
                        else if (enq_oh[jf]) beats_q[ie][f] <= (f < e) ? !gt_new[ie] : !ge_new[ie];
                        else                 beats_q[ie][f] <= (f < e) ? (key_a[jf] >= key_a[ie]) : (key_a[jf] > key_a[ie]);
                    end
                end
        end
    end
    always_comb
        for (int i = 0; i < TOTAL_ENTRIES; i++)
            ent_elig[i] = q_valid[i] && (q_dep[i] == '0);

    // Chọn ứng viên = chọn toàn cục trên các entry có bank rảnh, viết lại để bank_free của engine chỉ vào ở tầng cuối:
    // X[k][e] = có entry hợp lệ ở bank k thắng e (chỉ từ thanh ghi, tính song song), khi đó
    // win[e] = ok[e] & free[bank(e)] & AND_k (!free[k] | !X[k][e]).
    localparam int NBK = 1 << BANK_WIDTH;
    logic [QUEUE_DEPTH-1:0] win [NUM_BG];
    always_comb begin
        for (int bg = 0; bg < NUM_BG; bg++)
            for (int e = 0; e < QUEUE_DEPTH; e++) begin
                logic [NBK-1:0] x, fr;
                x = '0;
                for (int f = 0; f < QUEUE_DEPTH; f++)
                    if (ent_elig[bg * QUEUE_DEPTH + f] && beats_q[bg * QUEUE_DEPTH + e][f])
                        x[q_bank[bg * QUEUE_DEPTH + f]] = 1'b1;
                fr = i_bank_free[bg * NBK +: NBK];
                win[bg][e] = ent_elig[bg * QUEUE_DEPTH + e] && fr[q_bank[bg * QUEUE_DEPTH + e]] && ((x & fr) == '0);
            end
    end

`ifndef SYNTHESIS
    // Tự kiểm: công thức tách bank_free luôn trùng chọn toàn cục trên các entry có bank rảnh
    always_ff @(posedge clk)
        if (rst_n)
            for (int bg = 0; bg < NUM_BG; bg++) begin
                logic [QUEUE_DEPTH-1:0] ref_win, el;
                for (int e = 0; e < QUEUE_DEPTH; e++)
                    el[e] = ent_elig[bg * QUEUE_DEPTH + e] && i_bank_free[bg * NBK + int'(q_bank[bg * QUEUE_DEPTH + e])];
                for (int e = 0; e < QUEUE_DEPTH; e++) begin
                    ref_win[e] = el[e];
                    for (int f = 0; f < QUEUE_DEPTH; f++)
                        if (f != e && el[f] && ((ent_key[bg * QUEUE_DEPTH + f] > ent_key[bg * QUEUE_DEPTH + e]) ||
                                                (f < e && ent_key[bg * QUEUE_DEPTH + f] == ent_key[bg * QUEUE_DEPTH + e])))
                            ref_win[e] = 1'b0;
                end
                if (ref_win != win[bg])
                    $error("qos_scheduler_queue: BG %0d select %b != global select %b", bg, win[bg], ref_win);
            end
`endif

    // One-hot của entry đang là ứng viên (song song với o_cand_entry_idx): kiểm tra "ứng viên vẫn thắng" không cần mux
    logic [QUEUE_DEPTH-1:0] cand_oh [NUM_BG];
    // Ứng viên được đăng ký: cắt đường queue -> arbiter -> engine. Ứng viên tính trong chu kỳ có grant tới cùng BG
    // có thể chính là entry vừa được cấp (q_valid chỉ xoá ở cạnh này) nên bị vô hiệu một chu kỳ; tCCD_L của BG vừa
    // được cấp lệnh vẫn chặn BG đó lâu hơn nên không mất băng thông.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_cand_valid <= '0;
            o_cand_fresh <= '0;
        end else begin
            for (int bg = 0; bg < NUM_BG; bg++) begin
                logic v;
                v = (|win[bg]) && !(i_issue_grant_valid && i_issue_grant_bg == BG_W'(bg));
                o_cand_valid[bg] <= v;
                o_cand_fresh[bg] <= v && o_cand_valid[bg] && ((win[bg] & cand_oh[bg]) != '0);
            end
        end
    end
    always_ff @(posedge clk) begin
        for (int bg = 0; bg < NUM_BG; bg++) begin
            logic [IDX_W-1:0]         idx;
            logic [AXI_ID_WIDTH-1:0]  id;
            logic                     wr, thr, stv;
            logic [BANK_WIDTH-1:0]    bank;
            logic [ROW_WIDTH-1:0]     row;
            logic [COL_WIDTH-1:0]     col;
            logic [7:0]               len;
            logic [AXI_QOS_WIDTH-1:0] qos;
            idx = '0; id = '0; wr = 1'b0; thr = 1'b0; stv = 1'b0; bank = '0; row = '0; col = '0; len = '0; qos = '0;
            // Chọn bằng one-hot AND-OR: không giải mã lại chỉ số thành mux
            for (int e = 0; e < QUEUE_DEPTH; e++)
                if (win[bg][e]) begin
                    idx  = idx  | IDX_W'(e);
                    id   = id   | q_id      [bg * QUEUE_DEPTH + e];
                    wr   = wr   | q_is_write[bg * QUEUE_DEPTH + e];
                    thr  = thr  | q_throttled[bg * QUEUE_DEPTH + e];
                    stv  = stv  | ent_key[bg * QUEUE_DEPTH + e][KEY_W-1];
                    bank = bank | q_bank    [bg * QUEUE_DEPTH + e];
                    row  = row  | q_row     [bg * QUEUE_DEPTH + e];
                    col  = col  | q_col     [bg * QUEUE_DEPTH + e];
                    len  = len  | q_len     [bg * QUEUE_DEPTH + e];
                    qos  = qos  | ent_key[bg * QUEUE_DEPTH + e][8 +: AXI_QOS_WIDTH];
                end
            cand_oh[bg] <= win[bg];
            o_cand_entry_idx[bg*IDX_W +: IDX_W]           <= idx;
            o_cand_id[bg*AXI_ID_WIDTH +: AXI_ID_WIDTH]    <= id;
            o_cand_is_write[bg]                           <= wr;
            o_cand_bank[bg*BANK_WIDTH +: BANK_WIDTH]      <= bank;
            o_cand_row[bg*ROW_WIDTH +: ROW_WIDTH]         <= row;
            o_cand_col[bg*COL_WIDTH +: COL_WIDTH]         <= col;
            // Độ dài burst phải đi tiếp xuống engine: thiếu nó mọi burst bị cắt còn 1 beat trên DFI (R28)
            o_cand_len[bg*8 +: 8]                         <= len;
            o_cand_qos[bg*AXI_QOS_WIDTH +: AXI_QOS_WIDTH] <= qos;
            o_cand_throttled[bg]                          <= thr;
            o_cand_starved[bg]                            <= stv;
        end
    end

`ifdef FORMAL
    initial assume (!rst_n);

    always_ff @(posedge clk) begin
        if ($past(!rst_n)) assume (rst_n);
        if ($past(rst_n))  assume (rst_n);
    end

    // 1. Trạng thái reset
    always_comb begin
        if (!rst_n) begin
            assert (q_valid == '0);
            assert (o_cand_valid == '0);
            assert (o_cand_starved == '0);
        end
    end

    // 2. Tính toàn vẹn ứng viên (ứng viên đăng ký trễ một chu kỳ): chu kỳ trước BG có entry hợp lệ và không bị cấp
    //    lệnh thì nay phải có ứng viên; chu kỳ trước BG rỗng thì nay không có ứng viên.
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            for (int bg = 0; bg < NUM_BG; bg++) begin
                logic has_entry;
                has_entry = 1'b0;
                for (int e = 0; e < QUEUE_DEPTH; e++)
                    if ($past(q_valid[bg * QUEUE_DEPTH + e])) has_entry = 1'b1;
                if (!has_entry) assert (!o_cand_valid[bg]);
                else if (!$past(i_issue_grant_valid && i_issue_grant_bg == BG_W'(bg))) assert (o_cand_valid[bg]);
            end
        end
    end

    // 3. Chống bỏ đói: nếu chu kỳ trước BG có entry đói thì ứng viên hiện tại là entry đói
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            for (int bg = 0; bg < NUM_BG; bg++) begin
                logic any_starved;
                any_starved = 1'b0;
                for (int e = 0; e < QUEUE_DEPTH; e++)
                    if ($past(q_valid[bg * QUEUE_DEPTH + e] && q_age[bg * QUEUE_DEPTH + e] >= STARVATION_LIMIT[7:0]))
                        any_starved = 1'b1;
                if (any_starved && o_cand_valid[bg]) assert (o_cand_starved[bg]);
            end
        end
    end

    // 2b. Bộ chọn song song: mỗi BG có đúng tối đa một entry thắng, và entry thắng là entry hợp lệ
    always_comb begin
        if (rst_n)
            for (int bg = 0; bg < NUM_BG; bg++) begin
                assert ($onehot0(win[bg]));
                for (int e = 0; e < QUEUE_DEPTH; e++)
                    if (win[bg][e]) assert (q_valid[bg * QUEUE_DEPTH + e]);
            end
    end

    // 4. Giải phóng hàng đợi: Khi grant được phát, slot tương ứng phải được dequeue (nếu không đồng thời nạp lệnh mới vào đúng slot đó)
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            for (int bg = 0; bg < NUM_BG; bg++) begin
                for (int e = 0; e < QUEUE_DEPTH; e++) begin
                    bit was_deq;
                    bit was_enq;
                    was_deq = $past(i_issue_grant_valid && (i_issue_grant_bg == BG_W'(bg)) && (i_issue_grant_idx == IDX_W'(e)));
                    was_enq = $past(i_cmd_valid && o_cmd_ready && free_slot_found && (i_cmd_bg == BG_W'(bg)) && (free_slot_idx == IDX_W'(e)));
                    if (was_deq && !was_enq) begin
                        assert (!q_valid[bg * QUEUE_DEPTH + e]);
                    end
                end
            end
        end
    end

    // 5. QoS hiệu dụng của entry thắng không nhỏ hơn QoS gốc (leo thang chỉ tăng)
    always_comb begin
        if (rst_n)
            for (int i = 0; i < TOTAL_ENTRIES; i++)
                if (q_valid[i]) assert (ent_key[i][8 +: AXI_QOS_WIDTH] >= q_qos[i]);
    end

    // Cover properties
    always_ff @(posedge clk) begin
        cover (|o_cand_valid);
        cover (|o_cand_starved);
        cover (|bg_queue_full);
    end
`endif

endmodule
