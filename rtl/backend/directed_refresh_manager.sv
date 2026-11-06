// File:        directed_refresh_manager.sv
// Chức năng:   Quản lý hàng đợi phát xung làm tươi định hướng (DRFM/PRAC) cho các dòng lân cận Row ±1, ±2, ±3.
`timescale 1ns / 1ps

module directed_refresh_manager #(
    parameter int BG_WIDTH    = 3,
    parameter int BANK_WIDTH  = 2,
    parameter int ROW_WIDTH   = 17,
    parameter int QUEUE_DEPTH = 32 // PROQ 32-entry CAM from MORDOR MICRO 2026
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // Configuration
    input  logic                   cfg_drm_en,        // 1: Enable directed refresh
    input  logic                   cfg_victim2_en,    // 1: Refresh row +/- 2 in addition to +/- 1
    input  logic                   cfg_victim3_en = 1'b0, // 1: Refresh row +/- 3 (mở rộng blast radius cho chip có nhiễu lan xa)

    // Aggressor Alert from JEDEC PRAC / QPRAC Alert-Back-Off (Highest Priority)
    input  logic                   i_abo_req = 1'b0,
    input  logic [BG_WIDTH-1:0]    i_abo_bg = '0,
    input  logic [BANK_WIDTH-1:0]  i_abo_bank = '0,
    input  logic [ROW_WIDTH-1:0]   i_abo_row = '0,

    // Aggressor Alert from SDC Resilient Filter
    input  logic                   i_sdc_req,
    input  logic [BG_WIDTH-1:0]    i_sdc_bg,
    input  logic [BANK_WIDTH-1:0]  i_sdc_bank,
    input  logic [ROW_WIDTH-1:0]   i_sdc_row,

    // Aggressor Alert from RowPress Monitor
    input  logic                   i_rp_req,
    input  logic [BG_WIDTH-1:0]    i_rp_bg,
    input  logic [BANK_WIDTH-1:0]  i_rp_bank,
    input  logic [ROW_WIDTH-1:0]   i_rp_row,

    // ECC Patrol Scrubber Input (Lower Priority with Anti-Starvation)
    input  logic                   i_scrub_req,
    input  logic [BG_WIDTH-1:0]    i_scrub_bg,
    input  logic [BANK_WIDTH-1:0]  i_scrub_bank,
    input  logic [ROW_WIDTH-1:0]   i_scrub_row,
    output logic                   o_scrub_grant,

    // Interface to slack_aware_arbiter
    output logic                   o_mitigation_req,
    output logic [BG_WIDTH-1:0]    o_mitigation_bg,
    output logic [BANK_WIDTH-1:0]  o_mitigation_bank,
    output logic [ROW_WIDTH-1:0]   o_mitigation_row,
    input  logic                   i_mitigation_grant,

    // In-Flight Blacklist Check Interface (PROQ CAM from MORDOR MICRO 2026)
    input  logic                   i_check_cand_valid = 1'b0,
    input  logic [BG_WIDTH-1:0]    i_check_cand_bg    = '0,
    input  logic [BANK_WIDTH-1:0]  i_check_cand_bank  = '0,
    input  logic [ROW_WIDTH-1:0]   i_check_cand_row   = '0,
    output logic                   o_proq_row_hit,
    // Kiểm tra song song ứng viên của mọi BG (đăng ký): o_proq_blk[b] = ứng viên BG b chạm hàng đang chờ refresh
    // nạn nhân (hoặc kết quả chưa cập nhật). Bỏ CAM ra khỏi đường arbiter -> engine (Fmax 400 MHz).
    input  logic [(1<<BG_WIDTH)-1:0]            i_cand_valid = '0,
    input  logic [(1<<BG_WIDTH)-1:0]            i_cand_fresh = {(1<<BG_WIDTH){1'b1}},
    input  logic [(1<<BG_WIDTH)*BANK_WIDTH-1:0] i_cand_bank  = '0,
    input  logic [(1<<BG_WIDTH)*ROW_WIDTH-1:0]  i_cand_row   = '0,
    output logic [(1<<BG_WIDTH)-1:0]            o_proq_blk,
    output logic [(1<<BG_WIDTH)-1:0]            o_proq_hit,   // chạm thật (không tính trạng thái cũ): arbiter ưu tiên lệnh giảm thiểu

    // Telemetry & Flow Control
    output logic [15:0]            o_drm_ref_count,
    output logic                   o_queue_full,
    output logic                   o_drm_stall,
    output logic                   o_drm_fault
);

    localparam int PTR_W = $clog2(QUEUE_DEPTH);

    // Victim Queue Storage
    logic [BG_WIDTH-1:0]   q_bg   [QUEUE_DEPTH];
    logic [BANK_WIDTH-1:0] q_bank [QUEUE_DEPTH];
    logic [ROW_WIDTH-1:0]  q_row  [QUEUE_DEPTH];
    // Hàng ±1 của mỗi mục, ghi cùng lúc với q_row: phép kiểm tra PROQ so ứng viên với ba giá trị đã có sẵn thay vì
    // cộng/trừ 1 trên hàng ứng viên (bộ cộng 17 bit nằm trên đường queue -> DRM)
    logic [ROW_WIDTH-1:0]  q_rp1  [QUEUE_DEPTH];
    logic [ROW_WIDTH-1:0]  q_rm1  [QUEUE_DEPTH];

    logic [PTR_W:0] wr_ptr;
    // Bit hợp lệ từng mục PROQ (đặt khi nạp, xoá khi rút): CAM chặn ứng viên không so sánh con trỏ trên đường tới hạn
    logic [QUEUE_DEPTH-1:0] pq_v;
    logic [PTR_W:0] rd_ptr;
    wire [PTR_W:0]  count = wr_ptr - rd_ptr;

    wire queue_empty = (count == '0);
    wire queue_full  = (count >= QUEUE_DEPTH[PTR_W:0]);
    assign o_queue_full = queue_full;

    // Phát hiện sự kiện cảnh báo: sườn lên HOẶC đổi định danh hàng khi req giữ mức cao.
    // Chỉ bắt sườn lên làm mất mọi aggressor kế tiếp khi SDC giữ req liên tục cho nhiều hàng (Jailbreak/many-sided).
    localparam int AW = BG_WIDTH + BANK_WIDTH + ROW_WIDTH;
    wire [AW-1:0] abo_id = {i_abo_bg, i_abo_bank, i_abo_row};
    wire [AW-1:0] sdc_id = {i_sdc_bg, i_sdc_bank, i_sdc_row};
    wire [AW-1:0] rp_id  = {i_rp_bg,  i_rp_bank,  i_rp_row};

    logic          abo_req_d, sdc_req_d, rp_req_d;
    logic [AW-1:0] sdc_id_d, rp_id_d;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            abo_req_d <= 1'b0;
            sdc_req_d <= 1'b0;
            rp_req_d  <= 1'b0;
            sdc_id_d  <= '0;
            rp_id_d   <= '0;
        end else begin
            abo_req_d <= i_abo_req;
            sdc_req_d <= i_sdc_req;
            rp_req_d  <= i_rp_req;
            sdc_id_d  <= sdc_id;
            rp_id_d   <= rp_id;
        end
    end
    wire abo_evt = cfg_drm_en && i_abo_req && !abo_req_d;
    wire sdc_evt = cfg_drm_en && i_sdc_req && (!sdc_req_d || (sdc_id != sdc_id_d));
    wire rp_evt  = cfg_drm_en && i_rp_req  && (!rp_req_d  || (rp_id  != rp_id_d));

    // Hàng đợi cảnh báo aggressor: nhận tối đa 3 sự kiện/chu kỳ (ABO > SDC > RowPress), sequencer rút 1 mục/lần.
    // Dự trữ 6 chỗ (3 nguồn x 2 chu kỳ trễ của stall đăng ký) trước khi báo stall để không bao giờ tràn.
    localparam int unsigned AF_DEPTH   = 16;
    localparam int AF_W       = $clog2(AF_DEPTH);
    localparam int unsigned AF_RESERVE = 6;
    logic [AW-1:0] af_mem [AF_DEPTH];
    logic [AF_W:0] af_wr, af_rd;
    // Bit hợp lệ từng ô (giữ cùng lúc với push/pop): CAM chặn PROQ không cần phép trừ con trỏ trên đường so sánh
    logic [AF_DEPTH-1:0] af_v;
    wire  [AF_W:0] af_cnt   = af_wr - af_rd;
    wire           af_empty = (af_cnt == '0);
    localparam logic [AF_W:0] AF_STALL_LVL = AF_DEPTH - AF_RESERVE;
    wire           af_near_full = (af_cnt > AF_STALL_LVL);
    wire [AW-1:0]  af_head  = af_mem[af_rd[AF_W-1:0]];

    wire [BG_WIDTH-1:0]   head_bg   = af_head[AW-1 -: BG_WIDTH];
    wire [BANK_WIDTH-1:0] head_bank = af_head[ROW_WIDTH +: BANK_WIDTH];
    wire [ROW_WIDTH-1:0]  head_row  = af_head[ROW_WIDTH-1:0];

    // Multi-cycle injection generator for victim rows (+1, -1, +2, -2, +3, -3) với mã hóa one-hot chống lỗi bit-flip (M-05.4)
    localparam logic [6:0] S_IDLE = 7'b0000_001;
    localparam logic [6:0] S_P1R  = 7'b0000_010;
    localparam logic [6:0] S_M1   = 7'b0000_100;
    localparam logic [6:0] S_P2   = 7'b0001_000;
    localparam logic [6:0] S_M2   = 7'b0010_000;
    localparam logic [6:0] S_P3   = 7'b0100_000;
    localparam logic [6:0] S_M3   = 7'b1000_000;

    logic [6:0]            inj_oh;
    logic [BG_WIDTH-1:0]   inj_bg;
    logic [BANK_WIDTH-1:0] inj_bank;
    logic [ROW_WIDTH-1:0]  inj_row;
    logic                  inj_victim2;
    logic                  inj_victim3;

    wire [PTR_W-1:0] wr_idx = wr_ptr[PTR_W-1:0];
    wire [PTR_W-1:0] rd_idx = rd_ptr[PTR_W-1:0];

    wire [PTR_W:0] max_victims = cfg_victim3_en ? (PTR_W+1)'(6) : (cfg_victim2_en ? (PTR_W+1)'(4) : (PTR_W+1)'(2));

    // Backpressure lên luồng lệnh: đăng ký để con trỏ FIFO không nằm trên chuỗi READY của toàn pipeline lệnh
    // (queue -> SDC -> bộ ánh xạ). An toàn với độ trễ một chu kỳ: hàng đợi nạn nhân chỉ nhận qua seq_accept (đã tự
    // kiểm chỗ trống), còn FIFO cảnh báo giữ AF_RESERVE chỗ cho các sự kiện tới trong lúc stall chưa có hiệu lực.
    wire stall_c = queue_full || ((count + max_victims) > QUEUE_DEPTH[PTR_W:0]) || af_near_full;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) o_drm_stall <= 1'b0;
        else        o_drm_stall <= stall_c;
    end

    wire seq_accept = (inj_oh == S_IDLE) && !af_empty && ((count + max_victims) <= QUEUE_DEPTH[PTR_W:0]);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            af_wr <= '0;
            af_rd <= '0;
            af_v  <= '0;
            for (int unsigned i = 0; i < AF_DEPTH; i++) af_mem[i] <= '0;
        end else begin
            logic [AF_W:0] w;
            w = af_wr;
            // Pop trước push: khi FIFO đầy, ô vừa rút có thể được ghi lại ngay trong cùng chu kỳ
            if (seq_accept) af_v[af_rd[AF_W-1:0]] <= 1'b0;
            if (abo_evt) begin
                af_mem[w[AF_W-1:0]] <= abo_id;
                af_v[w[AF_W-1:0]]   <= 1'b1;
                w = w + 1'b1;
            end
            if (sdc_evt) begin
                af_mem[w[AF_W-1:0]] <= sdc_id;
                af_v[w[AF_W-1:0]]   <= 1'b1;
                w = w + 1'b1;
            end
            if (rp_evt) begin
                af_mem[w[AF_W-1:0]] <= rp_id;
                af_v[w[AF_W-1:0]]   <= 1'b1;
                w = w + 1'b1;
            end
            af_wr <= w;
            if (seq_accept) af_rd <= af_rd + 1'b1;
        end
    end

    // PROQ In-Flight Blacklist CAM Match Logic (MORDOR MICRO 2026)
    // Chặn cả hàng kề (±1) nạn nhân đang chờ: đó là aggressor; refresh nạn nhân bằng ACT mất ~tRAS+tRP nên nếu chỉ chặn
    // chính hàng nạn nhân, aggressor vẫn hammer tiếp trong lúc chờ (Jailbreak/MOAT: hàng chục ACT chưa được bù).
    wire [ROW_WIDTH-1:0] cand_row_p1 = i_check_cand_row + 1'b1;
    wire [ROW_WIDTH-1:0] cand_row_m1 = i_check_cand_row - 1'b1;
    logic [QUEUE_DEPTH-1:0] pq_region;
    logic [QUEUE_DEPTH-1:0] cam_match;
    always_comb begin
        for (int i = 0; i < QUEUE_DEPTH; i++) begin
            if (queue_empty) begin
                pq_region[i] = 1'b0;
            end else if (wr_ptr[PTR_W] == rd_ptr[PTR_W]) begin
                pq_region[i] = (PTR_W'(i) >= rd_idx) && (PTR_W'(i) < wr_idx);
            end else begin
                pq_region[i] = (PTR_W'(i) >= rd_idx) || (PTR_W'(i) < wr_idx);
            end

            cam_match[i] = pq_region[i] &&
                           (q_bg[i]   == i_check_cand_bg) &&
                           (q_bank[i] == i_check_cand_bank) &&
                           ((q_row[i] == i_check_cand_row) || (q_row[i] == cand_row_p1) || (q_row[i] == cand_row_m1));
        end
    end

    // Aggressor đang chờ trong hàng đợi cảnh báo cũng bị chặn như mục PROQ.
    logic af_match;
    always_comb begin
        af_match = 1'b0;
        for (int unsigned i = 0; i < AF_DEPTH; i++) begin
            if ((AF_W+1)'(i) < af_cnt &&
                af_mem[af_rd[AF_W-1:0] + AF_W'(i)] == {i_check_cand_bg, i_check_cand_bank, i_check_cand_row})
                af_match = 1'b1;
        end
    end

    assign o_proq_row_hit = i_check_cand_valid && ((|cam_match) || af_match);

    localparam int NBG = 1 << BG_WIDTH;
    wire [QUEUE_DEPTH-1:0] pq_live = pq_v;
    wire  [AF_DEPTH-1:0] af_live = af_v;
    logic [NBG-1:0] blk_c, blk_r, push_now_bg;
    (* keep = "true" *) logic [NBG-1:0] blkp_a, blkp_b;
    always_comb begin
        for (int b = 0; b < NBG; b++) begin
            logic [BANK_WIDTH-1:0] cb;
            logic [ROW_WIDTH-1:0]  cr;
            cb  = i_cand_bank[b*BANK_WIDTH +: BANK_WIDTH];
            cr  = i_cand_row[b*ROW_WIDTH +: ROW_WIDTH];
            blk_c[b] = 1'b0;
            // q_row == cr+1 <=> q_rm1 == cr; q_row == cr-1 <=> q_rp1 == cr (cùng số học modulo 2^ROW_WIDTH)
            for (int i = 0; i < QUEUE_DEPTH; i++)
                if (pq_live[i] && q_bg[i] == BG_WIDTH'(b) && q_bank[i] == cb && (q_row[i] == cr || q_rm1[i] == cr || q_rp1[i] == cr))
                    blk_c[b] = 1'b1;
            for (int unsigned i = 0; i < AF_DEPTH; i++)
                if (af_live[i] && af_mem[i] == {BG_WIDTH'(b), cb, cr})
                    blk_c[b] = 1'b1;

            push_now_bg[b] = (abo_evt    && (i_abo_bg == BG_WIDTH'(b))) ||
                             (sdc_evt    && (i_sdc_bg == BG_WIDTH'(b))) ||
                             (rp_evt     && (i_rp_bg  == BG_WIDTH'(b))) ||
                             (seq_accept && (head_bg  == BG_WIDTH'(b))) ||
                             ((inj_oh != S_IDLE) && (inj_bg == BG_WIDTH'(b)));
        end
    end
    // Kết quả trễ một chu kỳ: nhân đôi thanh ghi chặn (blkp_a/blkp_b) và kiểm tra theo từng BG để chống lỗi bit-flip đơn lẻ
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            blk_r  <= '0;
            blkp_a <= '0;
            blkp_b <= '0;
        end else begin
            blk_r  <= blk_c & i_cand_valid;
            blkp_a <= (blk_c & i_cand_valid) | push_now_bg;
            blkp_b <= (blk_c & i_cand_valid) | push_now_bg;
        end
    end
    assign o_proq_hit = blk_r;
    assign o_proq_blk = blkp_a | blkp_b | ~i_cand_fresh;

    wire inj_oh_err = !$onehot(inj_oh);
    wire blkp_err   = (blkp_a != blkp_b);
    wire pq_v_err   = (pq_v != pq_region);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) o_drm_fault <= 1'b0;
        else        o_drm_fault <= inj_oh_err || blkp_err || pq_v_err;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr             <= '0;
            rd_ptr             <= '0;
            pq_v               <= '0;
            inj_oh             <= S_IDLE;
            inj_bg             <= '0;
            inj_bank           <= '0;
            inj_row            <= '0;
            inj_victim2        <= 1'b0;
            inj_victim3        <= 1'b0;
            o_drm_ref_count    <= 16'd0;
            for (int i = 0; i < QUEUE_DEPTH; i++) begin
                q_bg[i]   <= '0;
                q_bank[i] <= '0;
                q_row[i]  <= '0;
                q_rp1[i]  <= '0;
                q_rm1[i]  <= '0;
            end
        end else begin
            // Tự phục hồi mặt nạ hợp lệ PROQ khi phát hiện sai lệch với vùng [rd_ptr, wr_ptr)
            if (pq_v_err) pq_v <= pq_region;

            // 1. Dequeue on mitigation grant when serving DRM queue
            if (pend_pop && !pend_src) begin
                rd_ptr          <= rd_ptr + 1'b1;
                pq_v[rd_idx]    <= 1'b0;
                o_drm_ref_count <= o_drm_ref_count + 1'b1;
            end

            // 2. Multi-victim enqueue sequencer (guaranteed no drops; fault recovery via S_P1R)
            if (inj_oh_err) begin
                inj_oh <= S_P1R;
            end else begin
                case (inj_oh)
                    S_IDLE: begin
                        if (seq_accept) begin
                            // Enqueue Victim 1: Row + 1
                            q_bg[wr_idx]   <= head_bg;
                            q_bank[wr_idx] <= head_bank;
                            q_row[wr_idx]  <= head_row + {{(ROW_WIDTH-1){1'b0}}, 1'b1};
                            q_rp1[wr_idx]  <= (head_row + {{(ROW_WIDTH-1){1'b0}}, 1'b1}) + 1'b1;
                            q_rm1[wr_idx]  <= (head_row + {{(ROW_WIDTH-1){1'b0}}, 1'b1}) - 1'b1;
                            wr_ptr         <= wr_ptr + 1'b1;
                            pq_v[wr_idx]   <= 1'b1;

                            inj_bg      <= head_bg;
                            inj_bank    <= head_bank;
                            inj_row     <= head_row;
                            inj_victim2 <= cfg_victim2_en;
                            inj_victim3 <= cfg_victim3_en;
                            inj_oh      <= S_M1;
                        end
                    end

                    S_P1R: begin
                        // Phục hồi sau lỗi FSM: nạp lại từ Victim 1 (Row + 1) để không bỏ sót dòng nạn nhân nào
                        if (!queue_full) begin
                            q_bg[wr_idx]   <= inj_bg;
                            q_bank[wr_idx] <= inj_bank;
                            q_row[wr_idx]  <= inj_row + {{(ROW_WIDTH-1){1'b0}}, 1'b1};
                            q_rp1[wr_idx]  <= (inj_row + {{(ROW_WIDTH-1){1'b0}}, 1'b1}) + 1'b1;
                            q_rm1[wr_idx]  <= (inj_row + {{(ROW_WIDTH-1){1'b0}}, 1'b1}) - 1'b1;
                            wr_ptr         <= wr_ptr + 1'b1;
                            pq_v[wr_idx]   <= 1'b1;
                        end
                        inj_victim2 <= cfg_victim2_en;
                        inj_victim3 <= cfg_victim3_en;
                        inj_oh      <= S_M1;
                    end

                    S_M1: begin
                        // Enqueue Victim 2: Row - 1
                        if (!queue_full) begin
                            q_bg[wr_idx]   <= inj_bg;
                            q_bank[wr_idx] <= inj_bank;
                            q_row[wr_idx]  <= inj_row - {{(ROW_WIDTH-1){1'b0}}, 1'b1};
                            q_rp1[wr_idx]  <= (inj_row - {{(ROW_WIDTH-1){1'b0}}, 1'b1}) + 1'b1;
                            q_rm1[wr_idx]  <= (inj_row - {{(ROW_WIDTH-1){1'b0}}, 1'b1}) - 1'b1;
                            wr_ptr         <= wr_ptr + 1'b1;
                            pq_v[wr_idx]   <= 1'b1;
                        end
                        inj_oh <= inj_victim2 ? S_P2 : S_IDLE;
                    end

                    S_P2: begin
                        // Enqueue Victim 3: Row + 2
                        if (!queue_full) begin
                            q_bg[wr_idx]   <= inj_bg;
                            q_bank[wr_idx] <= inj_bank;
                            q_row[wr_idx]  <= inj_row + {{(ROW_WIDTH-2){1'b0}}, 2'd2};
                            q_rp1[wr_idx]  <= (inj_row + {{(ROW_WIDTH-2){1'b0}}, 2'd2}) + 1'b1;
                            q_rm1[wr_idx]  <= (inj_row + {{(ROW_WIDTH-2){1'b0}}, 2'd2}) - 1'b1;
                            wr_ptr         <= wr_ptr + 1'b1;
                            pq_v[wr_idx]   <= 1'b1;
                        end
                        inj_oh <= S_M2;
                    end

                    S_M2: begin
                        // Enqueue Victim 4: Row - 2
                        if (!queue_full) begin
                            q_bg[wr_idx]   <= inj_bg;
                            q_bank[wr_idx] <= inj_bank;
                            q_row[wr_idx]  <= inj_row - {{(ROW_WIDTH-2){1'b0}}, 2'd2};
                            q_rp1[wr_idx]  <= (inj_row - {{(ROW_WIDTH-2){1'b0}}, 2'd2}) + 1'b1;
                            q_rm1[wr_idx]  <= (inj_row - {{(ROW_WIDTH-2){1'b0}}, 2'd2}) - 1'b1;
                            wr_ptr         <= wr_ptr + 1'b1;
                            pq_v[wr_idx]   <= 1'b1;
                        end
                        inj_oh <= inj_victim3 ? S_P3 : S_IDLE;
                    end

                    S_P3: begin
                        // Enqueue Victim 5: Row + 3 (blast radius ±3)
                        if (!queue_full) begin
                            q_bg[wr_idx]   <= inj_bg;
                            q_bank[wr_idx] <= inj_bank;
                            q_row[wr_idx]  <= inj_row + {{(ROW_WIDTH-2){1'b0}}, 2'd3};
                            q_rp1[wr_idx]  <= (inj_row + {{(ROW_WIDTH-2){1'b0}}, 2'd3}) + 1'b1;
                            q_rm1[wr_idx]  <= (inj_row + {{(ROW_WIDTH-2){1'b0}}, 2'd3}) - 1'b1;
                            wr_ptr         <= wr_ptr + 1'b1;
                            pq_v[wr_idx]   <= 1'b1;
                        end
                        inj_oh <= S_M3;
                    end

                    S_M3: begin
                        // Enqueue Victim 6: Row - 3 (blast radius ±3)
                        if (!queue_full) begin
                            q_bg[wr_idx]   <= inj_bg;
                            q_bank[wr_idx] <= inj_bank;
                            q_row[wr_idx]  <= inj_row - {{(ROW_WIDTH-2){1'b0}}, 2'd3};
                            q_rp1[wr_idx]  <= (inj_row - {{(ROW_WIDTH-2){1'b0}}, 2'd3}) + 1'b1;
                            q_rm1[wr_idx]  <= (inj_row - {{(ROW_WIDTH-2){1'b0}}, 2'd3}) - 1'b1;
                            wr_ptr         <= wr_ptr + 1'b1;
                            pq_v[wr_idx]   <= 1'b1;
                        end
                        inj_oh <= S_IDLE;
                    end

                    default: inj_oh <= S_P1R;
                endcase
            end
        end
    end

    // Scrubber Anti-Starvation Tracking Counter
    logic [3:0] drm_consec_grants;
    wire scrub_prio_boost = (drm_consec_grants >= 4'd8) && i_scrub_req;

    // Đề nghị (offer) lệnh giảm thiểu được đăng ký và giữ ổn định tới khi arbiter cấp: arbiter đọc thanh ghi,
    // grant chỉ xoá offer; nguồn được cấp (PROQ hay scrubber) đã chốt trong offer nên việc pop/báo scrubber ở chu kỳ
    // sau luôn đúng nguồn kể cả khi hàng đợi vừa nhận nạn nhân mới. Offer chỉ nạp lại sau khi pop xong.
    logic                  offer_v, offer_src;   // offer_src: 0 = PROQ, 1 = scrubber
    logic [BG_WIDTH-1:0]   offer_bg;
    logic [BANK_WIDTH-1:0] offer_bank;
    logic [ROW_WIDTH-1:0]  offer_row;
    logic                  pend_pop, pend_src;
    wire                   sel_scrub = scrub_prio_boost || (queue_empty && i_scrub_req);
    wire                   sel_any   = scrub_prio_boost || !queue_empty || i_scrub_req;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            offer_v           <= 1'b0;
            offer_src         <= 1'b0;
            offer_bg          <= '0;
            offer_bank        <= '0;
            offer_row         <= '0;
            pend_pop          <= 1'b0;
            pend_src          <= 1'b0;
            drm_consec_grants <= 4'd0;
        end else begin
            pend_pop <= 1'b0;
            // Đếm theo grant đã đăng ký (pend_pop): bộ đếm chỉ được đọc khi nạp offer kế tiếp, tức sau chu kỳ pend_pop
            if (pend_pop) begin
                if (pend_src)                      drm_consec_grants <= 4'd0;
                else if (drm_consec_grants < 4'd15) drm_consec_grants <= drm_consec_grants + 1'b1;
            end
            if (offer_v && i_mitigation_grant) begin
                offer_v  <= 1'b0;
                pend_pop <= 1'b1;
                pend_src <= offer_src;
            end else if (!offer_v && !pend_pop && sel_any) begin
                offer_v    <= 1'b1;
                offer_src  <= sel_scrub;
                offer_bg   <= sel_scrub ? i_scrub_bg   : q_bg[rd_idx];
                offer_bank <= sel_scrub ? i_scrub_bank : q_bank[rd_idx];
                offer_row  <= sel_scrub ? i_scrub_row  : q_row[rd_idx];
            end
        end
    end

    assign o_mitigation_req  = offer_v;
    assign o_mitigation_bg   = offer_bg;
    assign o_mitigation_bank = offer_bank;
    assign o_mitigation_row  = offer_row;
    assign o_scrub_grant     = pend_pop && pend_src;

`ifdef FORMAL
    initial assume (!rst_n);
    always_ff @(posedge clk) begin
        if ($past(!rst_n))
            assume (rst_n);
    end

    //=========================================================================
    // Formal Verification Properties & Safety Invariants (SVA)
    //=========================================================================
    always_comb begin
        if (!rst_n) begin
            assert (count == '0);
            assert (queue_empty);
            assert (!o_queue_full);
            assert (!o_mitigation_req);
            assert (!o_scrub_grant);
            assert (af_empty);
        end else begin
            // 0. Alert FIFO never overflows (no aggressor alert is ever dropped)
            assert (af_cnt <= (AF_W+1)'(AF_DEPTH));

            // 1. Queue Occupancy Invariant: count must never exceed QUEUE_DEPTH
            assert (count <= QUEUE_DEPTH[PTR_W:0]);

            // 2. Full Flag Determinism
            if (count >= QUEUE_DEPTH[PTR_W:0]) begin
                assert (o_queue_full);
            end else begin
                assert (!o_queue_full);
            end

            // 4. Offer chỉ đến từ một nguồn có thật: offer PROQ chỉ tồn tại khi PROQ còn mục
            if (offer_v && !offer_src) assert (!queue_empty);

            // 5. Báo scrubber chỉ khi offer scrubber vừa được cấp ở chu kỳ trước
            if (o_scrub_grant) assert (pend_pop && pend_src);
        end
    end

    // A-M1: FSM chèn nạn nhân luôn one-hot, hai bản chặn PROQ luôn bằng nhau khi không tiêm lỗi
    always_comb begin
        if (rst_n) begin
            assert (!inj_oh_err);
            assert (blkp_a == blkp_b);
        end
    end

    // 7. Bit hợp lệ PROQ khớp vùng [rd_ptr, wr_ptr)
    always_comb begin
        if (rst_n)
            for (int i = 0; i < QUEUE_DEPTH; i++)
                assert (pq_v[i] == (!queue_empty && ((wr_ptr[PTR_W] == rd_ptr[PTR_W]) ? (PTR_W'(i) >= rd_idx && PTR_W'(i) < wr_idx)
                                                                                       : (PTR_W'(i) >= rd_idx || PTR_W'(i) < wr_idx))));
    end

    // 6. Bit hợp lệ khớp vùng [af_rd, af_wr) của FIFO cảnh báo
    always_comb begin
        if (rst_n)
            for (int unsigned i = 0; i < AF_DEPTH; i++)
                assert (af_v[i] == ((AF_W'(i) - af_rd[AF_W-1:0]) < af_cnt[AF_W-1:0] || (af_cnt == (AF_W+1)'(AF_DEPTH))));
    end

    // 3. Backpressure Stall Invariant: stall đăng ký phản ánh đúng tình trạng chật của chu kỳ trước
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            assert (o_drm_stall == $past(stall_c));
            // SA-F08: Trạng thái lỗi one-hot của inj_oh phải bật o_drm_fault và chuyển về S_P1R
            if (!$onehot($past(inj_oh))) assert (o_drm_fault && (inj_oh == S_P1R));
            // SA-F10: Sai lệch mặt nạ pq_v phải bật o_drm_fault và tự phục hồi khớp pq_region ở chu kỳ kế tiếp
            if ($past(pq_v) != $past(pq_region)) assert (o_drm_fault && (pq_v == pq_region));
        end
    end
`endif

endmodule: directed_refresh_manager
