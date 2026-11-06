//=============================================================================
// File:        slack_aware_arbiter.sv
// Chức năng:   Trọng tài ma trận nhận thức khe hở định thời JEDEC và điều phối chuyển mạch Write-Drain / Read-Burst.
//=============================================================================
`timescale 1ns / 1ps

module slack_aware_arbiter #(
    parameter int BG_COUNT        = 8,
    parameter int BG_WIDTH        = $clog2(BG_COUNT),
    parameter int BANK_WIDTH      = 2,
    parameter int ROW_WIDTH       = 17,
    parameter int COL_WIDTH       = 10,
    parameter int AXI_ID_WIDTH    = 4,
    parameter int AXI_LEN_WIDTH   = 8,
    parameter int QUEUE_PTR_WIDTH = 3,
    parameter int DRAIN_HIGH_THRESH = 4,
    parameter int DRAIN_LOW_THRESH  = 0
)(
    input  logic                                         clk,
    input  logic                                         rst_n,

    //-------------------------------------------------------------------------
    // Candidates from 8 Bank Group Queues
    //-------------------------------------------------------------------------
    input  logic [BG_COUNT-1:0]                          i_cand_valid,
    input  logic [BG_COUNT*AXI_ID_WIDTH-1:0]             i_cand_id,
    input  logic [BG_COUNT-1:0]                          i_cand_is_write,
    input  logic [BG_COUNT*BANK_WIDTH-1:0]               i_cand_bank,
    input  logic [BG_COUNT*ROW_WIDTH-1:0]                i_cand_row,
    input  logic [BG_COUNT*COL_WIDTH-1:0]                i_cand_col,
    input  logic [BG_COUNT*AXI_LEN_WIDTH-1:0]            i_cand_len,
    input  logic [BG_COUNT*4-1:0]                        i_cand_qos,
    input  logic [BG_COUNT-1:0]                          i_cand_throttled,
    input  logic [BG_COUNT-1:0]                          i_cand_starved,
    input  logic [BG_COUNT*QUEUE_PTR_WIDTH-1:0]          i_cand_queue_idx,

    //-------------------------------------------------------------------------
    // Timing & Readiness from DDR5 Command Engine
    //-------------------------------------------------------------------------
    input  logic [BG_COUNT-1:0]                          i_bg_ready,
    input  logic                                         i_engine_ready,
    // Slot lệnh từng bank của engine còn trống ({bg, bank})
    input  logic [BG_COUNT*(1<<BANK_WIDTH)-1:0]          i_bank_free = '1,
    // ABO: engine chỉ nhận lệnh giảm thiểu
    input  logic                                         i_engine_mit_only = 1'b0,
    input  logic                                         i_slack_cycle,

    //-------------------------------------------------------------------------
    // Mitigation / ECC Scrubbing Injection Interface
    //-------------------------------------------------------------------------
    input  logic                                         i_mitigation_req,
    input  logic [BG_WIDTH-1:0]                          i_mitigation_bg,
    input  logic [BANK_WIDTH-1:0]                        i_mitigation_bank,
    input  logic [ROW_WIDTH-1:0]                         i_mitigation_row,
    output logic                                         o_mitigation_grant,

    //-------------------------------------------------------------------------
    // In-Flight Blacklist (PROQ, MORDOR MICRO 2026): kết quả kiểm tra đã đăng ký cho ứng viên từng BG
    //-------------------------------------------------------------------------
    input  logic [BG_COUNT-1:0]                          i_proq_blk = '0,  // không được phát (chạm PROQ hoặc kết quả cũ)
    input  logic [BG_COUNT-1:0]                          i_proq_hit = '0,  // chạm PROQ thật: ưu tiên lệnh giảm thiểu

    //-------------------------------------------------------------------------
    // Arbitration Issue Grant to qos_scheduler_queue
    //-------------------------------------------------------------------------
    output logic                                         o_issue_grant_valid,
    output logic [BG_WIDTH-1:0]                          o_issue_grant_bg,
    output logic [QUEUE_PTR_WIDTH-1:0]                   o_issue_grant_idx,

    //-------------------------------------------------------------------------
    // Dispatched Command to ddr5_cmd_engine
    //-------------------------------------------------------------------------
    output logic                                         o_cmd_valid,
    output logic                                         o_cmd_is_write,
    output logic [AXI_ID_WIDTH-1:0]                      o_cmd_id,
    output logic [BG_WIDTH-1:0]                          o_cmd_bg,
    // BG của lệnh dạng one-hot (lấy thẳng từ vector thắng, không mã hoá rồi giải mã lại ở phía dùng)
    output logic [BG_COUNT-1:0]                          o_cmd_bg_oh,
    output logic [BANK_WIDTH-1:0]                        o_cmd_bank,
    output logic [ROW_WIDTH-1:0]                         o_cmd_row,
    output logic [COL_WIDTH-1:0]                         o_cmd_col,
    output logic [AXI_LEN_WIDTH-1:0]                     o_cmd_len,
    output logic                                         o_cmd_is_mitigation,
    output logic                                         o_drain_mode
);

    //=========================================================================
    // Internal Signals & Bit Unpacking
    //=========================================================================
    logic [AXI_ID_WIDTH-1:0]    cand_id       [BG_COUNT];
    logic [BANK_WIDTH-1:0]      cand_bank     [BG_COUNT];
    logic [ROW_WIDTH-1:0]       cand_row      [BG_COUNT];
    logic [COL_WIDTH-1:0]       cand_col      [BG_COUNT];
    logic [AXI_LEN_WIDTH-1:0]   cand_len      [BG_COUNT];
    logic [3:0]                 cand_qos      [BG_COUNT];
    logic [QUEUE_PTR_WIDTH-1:0] cand_queue_idx[BG_COUNT];

    always_comb begin
        for (int bg = 0; bg < BG_COUNT; bg++) begin
            cand_id[bg]        = i_cand_id[bg*AXI_ID_WIDTH +: AXI_ID_WIDTH];
            cand_bank[bg]      = i_cand_bank[bg*BANK_WIDTH +: BANK_WIDTH];
            cand_row[bg]       = i_cand_row[bg*ROW_WIDTH +: ROW_WIDTH];
            cand_col[bg]       = i_cand_col[bg*COL_WIDTH +: COL_WIDTH];
            cand_len[bg]       = i_cand_len[bg*AXI_LEN_WIDTH +: AXI_LEN_WIDTH];
            cand_qos[bg]       = i_cand_qos[bg*4 +: 4];
            cand_queue_idx[bg] = i_cand_queue_idx[bg*QUEUE_PTR_WIDTH +: QUEUE_PTR_WIDTH];
        end
    end

    // Grant tới hàng đợi được đăng ký (dequeue ở cạnh sau): BG vừa cấp bị che một chu kỳ vì ứng viên của nó
    // (thanh ghi trong hàng đợi) vẫn có thể là entry vừa cấp. Lệnh tới engine vẫn đi thẳng trong chu kỳ chọn.
    logic                       grant_r_v;
    logic [BG_WIDTH-1:0]        grant_r_bg;
    logic [QUEUE_PTR_WIDTH-1:0] grant_r_idx;
    wire  [BG_COUNT-1:0]        grant_mask = grant_r_v ? (BG_COUNT'(1) << grant_r_bg) : '0;

    // Slot của bank đích còn trống (engine giữ một giao dịch mỗi bank)
    logic [BG_COUNT-1:0] cand_bank_free;
    always_comb
        for (int bg = 0; bg < BG_COUNT; bg++)
            cand_bank_free[bg] = i_bank_free[bg * (1 << BANK_WIDTH) + int'(i_cand_bank[bg*BANK_WIDTH +: BANK_WIDTH])];
    wire mit_bank_free = i_bank_free[{i_mitigation_bg, i_mitigation_bank}];

    // Ứng viên đủ điều kiện: slot bank trống, tCCD của BG đã hết và không chạm hàng đang chờ refresh nạn nhân
    wire [BG_COUNT-1:0] eligible_cand = i_cand_valid & i_bg_ready & cand_bank_free & ~i_proq_blk & ~grant_mask;

    //=========================================================================
    // Write-Drain / Read-Burst Mode State Machine
    //=========================================================================
    logic [3:0] eligible_write_count;
    always_comb begin
        eligible_write_count = '0;
        for (int bg = 0; bg < BG_COUNT; bg++)
            // Đếm cả BG đang bị che sau grant: mặt nạ một chu kỳ không phản ánh lượng lệnh ghi đang chờ
            if (i_cand_valid[bg] && i_bg_ready[bg] && !i_proq_blk[bg] && i_cand_is_write[bg])
                eligible_write_count = eligible_write_count + 1'b1;
    end

    logic reg_drain_mode;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_drain_mode <= 1'b0;
        end else if (!reg_drain_mode) begin
            if (int'(eligible_write_count) >= DRAIN_HIGH_THRESH) reg_drain_mode <= 1'b1;
        end else begin
            if (int'(eligible_write_count) <= DRAIN_LOW_THRESH) reg_drain_mode <= 1'b0;
        end
    end
    assign o_drain_mode = reg_drain_mode;

    //=========================================================================
    // Chọn ứng viên song song (thay 5 lượt quét nối tiếp 8 BG).
    // Khoá: ứng viên đói > không throttle > đúng hướng drain/burst > QoS cao. Ứng viên đói chỉ xét round-robin
    // (khoá chung), giống Tier 1 cũ. Hoà khoá thì BG đứng trước trong thứ tự round-robin (bắt đầu sau BG phục vụ gần
    // nhất) thắng. Thắng = không có BG đủ điều kiện nào thắng nó trong so sánh cặp: một mức so sánh + một mức AND.
    //=========================================================================
    logic [BG_WIDTH-1:0] last_served_bg;
    logic [6:0]          key [BG_COUNT];
    logic [BG_COUNT-1:0] win, win_all;
    // beats[j][i] = 1: BG j đứng trước BG i (khoá lớn hơn, hoặc bằng khoá và đứng trước trong vòng round-robin)
    logic [BG_COUNT-1:0] beats [BG_COUNT];
    wire  [BG_COUNT-1:0] ready_cand = i_cand_valid & i_bg_ready & cand_bank_free & ~grant_mask;
    always_comb begin
        for (int i = 0; i < BG_COUNT; i++)
            key[i] = i_cand_starved[i] ? 7'b100_0000 :
                     {1'b0, !i_cand_throttled[i], i_cand_is_write[i] == reg_drain_mode, cand_qos[i]};
        for (int j = 0; j < BG_COUNT; j++)
            for (int i = 0; i < BG_COUNT; i++) begin
                logic [BG_WIDTH-1:0] pos_i, pos_j;
                pos_i = BG_WIDTH'(i) - last_served_bg - 1'b1;
                pos_j = BG_WIDTH'(j) - last_served_bg - 1'b1;
                beats[j][i] = (j != i) && (key[j] > key[i] || (key[j] == key[i] && pos_j < pos_i));
            end
        // win: thắng trong số ứng viên được phép phát; win_all: ứng viên ưu tiên nhất kể cả ứng viên bị PROQ chặn
        for (int i = 0; i < BG_COUNT; i++) begin
            win[i]     = eligible_cand[i];
            win_all[i] = ready_cand[i];
            for (int j = 0; j < BG_COUNT; j++) begin
                if (eligible_cand[j] && beats[j][i]) win[i]     = 1'b0;
                if (ready_cand[j]    && beats[j][i]) win_all[i] = 1'b0;
            end
        end
    end
    wire winner_found = |win;

    // Lệnh giảm thiểu thắng khi ứng viên ưu tiên nhất đang bị PROQ chặn (chính lệnh này gỡ chặn), khi ABO đòi chỉ
    // nhận lệnh giảm thiểu, hoặc khi không còn lệnh người dùng nào phát được và bus có khe hở / có ứng viên bị chặn.
    // Ứng viên bị chặn ở BG khác không được giữ lệnh QoS cao tới BG rảnh (R20).
    wire can_issue_mitigation = i_mitigation_req && i_engine_ready && mit_bank_free &&
                                (i_engine_mit_only || (|(win_all & i_proq_hit)) ||
                                 (!winner_found && (i_slack_cycle || (|(i_cand_valid & i_proq_hit)))));
    wire can_issue_user_cmd   = winner_found && i_engine_ready && !i_engine_mit_only && !can_issue_mitigation;

    assign o_mitigation_grant  = can_issue_mitigation;
    assign o_issue_grant_valid = grant_r_v;

    // Trường lệnh chọn bằng one-hot AND-OR
    logic [BG_WIDTH-1:0]        w_bg;
    logic [QUEUE_PTR_WIDTH-1:0] w_idx;
    logic                       w_wr;
    logic [AXI_ID_WIDTH-1:0]    w_id;
    logic [BANK_WIDTH-1:0]      w_bank;
    logic [ROW_WIDTH-1:0]       w_row;
    logic [COL_WIDTH-1:0]       w_col;
    logic [AXI_LEN_WIDTH-1:0]   w_len;
    always_comb begin
        w_bg = '0; w_idx = '0; w_wr = 1'b0; w_id = '0; w_bank = '0; w_row = '0; w_col = '0; w_len = '0;
        for (int i = 0; i < BG_COUNT; i++)
            if (win[i]) begin
                w_bg   = w_bg   | BG_WIDTH'(i);
                w_idx  = w_idx  | cand_queue_idx[i];
                w_wr   = w_wr   | i_cand_is_write[i];
                w_id   = w_id   | cand_id[i];
                w_bank = w_bank | cand_bank[i];
                w_row  = w_row  | cand_row[i];
                w_col  = w_col  | cand_col[i];
                w_len  = w_len  | cand_len[i];
            end
    end
    assign o_issue_grant_bg  = grant_r_bg;
    assign o_issue_grant_idx = grant_r_idx;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) grant_r_v <= 1'b0;
        else        grant_r_v <= can_issue_user_cmd;
    end
    always_ff @(posedge clk) begin
        grant_r_bg  <= w_bg;
        grant_r_idx <= w_idx;
    end

    always_comb begin
        o_cmd_valid         = can_issue_user_cmd || can_issue_mitigation;
        o_cmd_is_mitigation = can_issue_mitigation;
        if (can_issue_mitigation) begin
            o_cmd_is_write = 1'b0;
            o_cmd_id       = '0;
            o_cmd_bg       = i_mitigation_bg;
            o_cmd_bg_oh    = BG_COUNT'(1) << i_mitigation_bg;
            o_cmd_bank     = i_mitigation_bank;
            o_cmd_row      = i_mitigation_row;
            o_cmd_col      = '0;
            o_cmd_len      = '0;
        end else begin
            o_cmd_is_write = w_wr;
            o_cmd_id       = w_id;
            o_cmd_bg       = w_bg;
            o_cmd_bg_oh    = win;
            o_cmd_bank     = w_bank;
            o_cmd_row      = w_row;
            o_cmd_col      = w_col;
            o_cmd_len      = w_len;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)                  last_served_bg <= '0;
        else if (can_issue_user_cmd) last_served_bg <= w_bg;
    end

`ifdef FORMAL
    //=========================================================================
    // Formal Verification Properties & Safety Invariants (SVA)
    //=========================================================================
    always_comb begin
        if (rst_n) begin
            // 1. Mutual Exclusion: Mitigation grant and User Issue grant are strictly mutually exclusive
            assert (!(can_issue_user_cmd && o_mitigation_grant));

            // 2. Mitigation Command Integrity
            if (o_cmd_valid && o_cmd_is_mitigation) begin
                assert (!can_issue_user_cmd);
                assert (o_mitigation_grant);
                assert (o_cmd_bg == i_mitigation_bg);
                assert (o_cmd_bank == i_mitigation_bank);
                assert (o_cmd_row == i_mitigation_row);
            end

            // 3. User Command Integrity: Issued BG must have had valid candidate
            if (o_cmd_valid && !o_cmd_is_mitigation) begin
                assert (can_issue_user_cmd);
                assert (o_cmd_bg == w_bg);
                assert (i_cand_valid[o_cmd_bg] && !i_proq_blk[o_cmd_bg] && i_bg_ready[o_cmd_bg]);
                assert ($onehot(win));
            end

            // 4. Idle Bus Invariant: When neither user nor mitigation is legal, o_cmd_valid must be 0
            if (!can_issue_user_cmd && !can_issue_mitigation) begin
                assert (!o_cmd_valid);
                assert (!o_mitigation_grant);
            end
        end
    end
`endif

endmodule


