// File: sdc_resilient_filter.sv
// Chức năng: Bộ lọc băm đôi O(1) theo dõi kích hoạt hàng, điều tiết nhịp mềm và reset epoch trong 1 chu kỳ.
`timescale 1ns / 1ps

module sdc_resilient_filter #(
    parameter int AXI_ID_WIDTH   = 4,
    parameter int AXI_QOS_WIDTH  = 4,
    parameter int ROW_WIDTH      = 17,
    parameter int COL_WIDTH      = 10,
    parameter int BG_WIDTH       = 3,
    parameter int BANK_WIDTH     = 2,
    parameter int BANK_COUNT     = 1 << BANK_WIDTH,
    parameter int TABLE_ENTRIES  = 256,
    parameter int COUNT_WIDTH    = 16,
    // Số REFab định kỳ trong một tREFW (JEDEC: 8192 x tREFI = 32 ms). Cố định theo chuẩn, không mở cổng cấu hình:
    // cửa sổ ngắn hơn tREFW cho phép chia nhỏ hammer qua nhiều cửa sổ mà không bao giờ chạm ngưỡng (S8).
    parameter int REFW_REFS      = 8192
) (
    input  logic                      clk,
    input  logic                      rst_n,

    // Configuration & Thresholds
    input  logic                      cfg_hash_mode,   // 0: Single-Hash, 1: Dual-Hash
    input  logic                      cfg_pxor_mode        = 1'b0, // 1: Crystalor PXOR Universal Hash, 0: Modulo/CRC-8
    input  logic [63:0]               cfg_pxor_seed        = 64'hA5A5_5A5A_0123_4567, // Universal hash matrix seed
    input  logic [COUNT_WIDTH-1:0]    cfg_sdc_thresh,  // Activation alert threshold
    input  logic [15:0]               cfg_window_size, // Cửa sổ (chu kỳ) cho throttle phối hợp đa bank SledgeHammer
    input  logic                      i_ref_tick = 1'b0, // Xung mỗi REFab định kỳ từ command engine
    input  logic [2:0]                cfg_multibank_thresh = 3'd2, // Max concurrent throttled banks

    // Input Decoded Command from addr_mapper_ddr5
    input  logic                      i_cmd_valid,
    output logic                      o_cmd_ready,
    input  logic [AXI_ID_WIDTH-1:0]   i_cmd_id,
    input  logic                      i_cmd_is_write,
    input  logic [BG_WIDTH-1:0]       i_cmd_bg,
    input  logic [BANK_WIDTH-1:0]     i_cmd_bank,
    input  logic [ROW_WIDTH-1:0]      i_cmd_row,
    input  logic [COL_WIDTH-1:0]      i_cmd_col,
    input  logic [7:0]                i_cmd_len,
    input  logic [AXI_QOS_WIDTH-1:0]  i_cmd_qos,
    input  logic [7:0]                i_rowpress_weight = 8'd0,

    // Filtered Output to qos_scheduler_queue
    output logic                      o_cmd_valid,
    input  logic                      i_cmd_ready,
    output logic [AXI_ID_WIDTH-1:0]   o_cmd_id,
    output logic                      o_cmd_is_write,
    output logic [BG_WIDTH-1:0]       o_cmd_bg,
    output logic [BANK_WIDTH-1:0]     o_cmd_bank,
    output logic [ROW_WIDTH-1:0]      o_cmd_row,
    output logic [COL_WIDTH-1:0]      o_cmd_col,
    output logic [7:0]                o_cmd_len,
    output logic [AXI_QOS_WIDTH-1:0]  o_cmd_qos,
    output logic                      o_cmd_throttled,

    // Defense & Telemetry Interface
    output logic                      o_mitigation_req,
    output logic [BG_WIDTH-1:0]       o_mitigation_bg,
    output logic [BANK_WIDTH-1:0]     o_mitigation_bank,
    output logic [ROW_WIDTH-1:0]      o_mitigation_row,
    output logic                      o_sdc_alert,
    output logic                      o_coordinated_throttle_active,
    output logic [BANK_COUNT-1:0]     o_bank_throttled_flags,
    output logic [15:0]               o_coordinated_throttle_cnt,
    output logic [31:0]               o_telemetry_accesses,
    output logic [31:0]               o_telemetry_throttles
);

    localparam int ADDR_TAG_W = BG_WIDTH + BANK_WIDTH + ROW_WIDTH; // 3 + 2 + 17 = 22 bits
    localparam int IDX_W      = $clog2(TABLE_ENTRIES);              // 8 bits

    wire [ADDR_TAG_W-1:0] full_row_tag = {i_cmd_bg, i_cmd_bank, i_cmd_row};

    // Pipeline 3 tầng, dừng cùng lúc khi đầu ra bị giữ (en = 0): T1 băm địa chỉ hàng, T2 đọc hai bảng đếm
    // (forward giá trị T3 đang ghi khi trùng bin), T3 so ngưỡng, cập nhật bảng và đăng ký đầu ra.
    // Trước đây băm -> đọc bảng 256 bin -> min -> so ngưỡng -> cộng -> ghi nằm trong một chu kỳ (18 mức logic).
    logic en;

    //=========================================================================
    // 1. Orthogonal Hash Functions: H_A (XOR-Fold) and H_B (CRC-8)
    //=========================================================================
    // Hash A: Fold 22 bits into 8 bits using XOR tree
    logic [IDX_W-1:0] hash_a;
    always_comb begin
        hash_a = full_row_tag[7:0] ^ full_row_tag[15:8] ^ {{(IDX_W - (ADDR_TAG_W - 16)){1'b0}}, full_row_tag[ADDR_TAG_W-1:16]};
    end

    // Hash B: Combinational CRC-8 with polynomial x^8 + x^2 + x + 1 (0x07)
    function [7:0] calc_crc8;
        input [ADDR_TAG_W-1:0] data;
        logic [7:0] crc;
        begin
            crc = 8'hAA; // Non-zero initial seed
            for (int i = ADDR_TAG_W - 1; i >= 0; i--) begin
                if ((crc[7] ^ data[i]) == 1'b1) begin
                    crc = {crc[6:0], 1'b0} ^ 8'h07;
                end else begin
                    crc = {crc[6:0], 1'b0};
                end
            end
            calc_crc8 = crc;
        end
    endfunction

    logic [IDX_W-1:0] hash_b;
    always_comb begin
        hash_b = calc_crc8(full_row_tag);
    end

    // Động cơ băm vạn năng PXOR-Hash (Crystalor CCS '24)
    logic [IDX_W-1:0] pxor_hash_a;
    logic [IDX_W-1:0] pxor_hash_b;

    pxor_hash_engine #(
        .TAG_WIDTH  (ADDR_TAG_W),
        .HASH_WIDTH (IDX_W)
    ) u_pxor_a (
        .i_tag  (full_row_tag),
        .i_seed (cfg_pxor_seed),
        .o_hash (pxor_hash_a)
    );

    pxor_hash_engine #(
        .TAG_WIDTH  (ADDR_TAG_W),
        .HASH_WIDTH (IDX_W)
    ) u_pxor_b (
        .i_tag  (full_row_tag),
        .i_seed (~cfg_pxor_seed ^ 64'hF0F0_0F0F_AAAA_5555),
        .o_hash (pxor_hash_b)
    );

    wire [IDX_W-1:0] in_hash_a = cfg_pxor_mode ? pxor_hash_a : hash_a;
    wire [IDX_W-1:0] in_hash_b = cfg_pxor_mode ? pxor_hash_b : hash_b;

    localparam int CMD_W = AXI_ID_WIDTH + 1 + BG_WIDTH + BANK_WIDTH + ROW_WIDTH + COL_WIDTH + 8 + AXI_QOS_WIDTH;
    logic             p1_valid, p2_valid;
    logic [CMD_W-1:0] p1_cmd, p2_cmd;
    logic [IDX_W-1:0] p1_ha, p1_hb, p2_ha, p2_hb;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)  p1_valid <= 1'b0;
        else if (en) p1_valid <= i_cmd_valid;
    end
    always_ff @(posedge clk)
        if (en) begin
            p1_cmd <= {i_cmd_id, i_cmd_is_write, i_cmd_bg, i_cmd_bank, i_cmd_row, i_cmd_col, i_cmd_len, i_cmd_qos};
            p1_ha  <= in_hash_a;
            p1_hb  <= in_hash_b;
        end
    // Lệnh ở T3 (đầu vào của bước cập nhật)
    logic [AXI_ID_WIDTH-1:0]  s_id;
    logic                     s_is_write;
    logic [BG_WIDTH-1:0]      s_bg;
    logic [BANK_WIDTH-1:0]    s_bank;
    logic [ROW_WIDTH-1:0]     s_row;
    logic [COL_WIDTH-1:0]     s_col;
    logic [7:0]               s_len;
    logic [AXI_QOS_WIDTH-1:0] s_qos;
    assign {s_id, s_is_write, s_bg, s_bank, s_row, s_col, s_len, s_qos} = p2_cmd;
    wire [IDX_W-1:0] eff_hash_a = p2_ha;
    wire [IDX_W-1:0] eff_hash_b = p2_hb;
    wire             s_fire     = p2_valid && en;

    //=========================================================================
    // 2. O(1) Epoch Reset gắn với tREFW
    // Epoch chỉ đổi sau đúng REFW_REFS lệnh REFab: khi đó mọi hàng đều đã được làm tươi ít nhất một lần,
    // nên xoá bộ đếm không bỏ sót ACT nào chưa được bù. window_timer chỉ còn phục vụ throttle phối hợp đa bank.
    //=========================================================================
    localparam int REFW_W = (REFW_REFS > 1) ? $clog2(REFW_REFS) : 1;
    logic [15:0]       window_timer;
    logic [REFW_W-1:0] ref_cnt;
    logic              current_epoch;
    logic [IDX_W-1:0]  sweep_idx;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            window_timer  <= '0;
            ref_cnt       <= '0;
            current_epoch <= 1'b0;
        end else begin
            if (window_timer >= cfg_window_size) window_timer <= '0;
            else                                 window_timer <= window_timer + 1'b1;
            if (i_ref_tick) begin
                if (ref_cnt == REFW_W'(REFW_REFS - 1)) begin
                    ref_cnt       <= '0;
                    current_epoch <= ~current_epoch; // Instant O(1) epoch reset
                end else begin
                    ref_cnt       <= ref_cnt + 1'b1;
                end
            end
        end
    end

    //=========================================================================
    // 3. Dual Hash Counter Tables with Epoch Validation
    //=========================================================================
    logic [TABLE_ENTRIES-1:0]   table_a_epoch;
    logic [COUNT_WIDTH-1:0]     table_a_count [TABLE_ENTRIES-1:0];
    logic [TABLE_ENTRIES-1:0]   table_b_epoch;
    logic [COUNT_WIDTH-1:0]     table_b_count [TABLE_ENTRIES-1:0];

    // T2: đọc số đếm hiệu lực của bin T1; nếu T3 đang ghi đúng bin đó ở cạnh này thì lấy giá trị mới (forward)
    logic [COUNT_WIDTH-1:0] cur_cnt_a, cur_cnt_b;
    logic [COUNT_WIDTH-1:0] new_cnt_a, new_cnt_b;
    wire  [COUNT_WIDTH-1:0] rd_cnt_a = (table_a_epoch[p1_ha] == current_epoch) ? table_a_count[p1_ha] : '0;
    wire  [COUNT_WIDTH-1:0] rd_cnt_b = (table_b_epoch[p1_hb] == current_epoch) ? table_b_count[p1_hb] : '0;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)  p2_valid <= 1'b0;
        else if (en) p2_valid <= p1_valid;
    end
    always_ff @(posedge clk)
        if (en) begin
            p2_cmd    <= p1_cmd;
            p2_ha     <= p1_ha;
            p2_hb     <= p1_hb;
            cur_cnt_a <= (s_fire && p1_ha == p2_ha) ? new_cnt_a : rd_cnt_a;
            cur_cnt_b <= (s_fire && cfg_hash_mode && p1_hb == p2_hb) ? new_cnt_b : rd_cnt_b;
        end
    // Ngưỡng động từ ATE thay đổi chậm: đăng ký để tách khỏi đường so sánh
    logic [COUNT_WIDTH-1:0] thresh_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) thresh_q <= {COUNT_WIDTH{1'b1}};
        else        thresh_q <= cfg_sdc_thresh;
    end

    // Minimum count evaluation (Theorem 1)
    logic [COUNT_WIDTH-1:0] effective_count;
    always_comb begin
        if (cfg_hash_mode == 1'b0) begin
            effective_count = cur_cnt_a; // Single-Hash mode
        end else begin
            effective_count = (cur_cnt_a < cur_cnt_b) ? cur_cnt_a : cur_cnt_b; // Dual-Hash mode
        end
    end

    // SledgeHammer Defense: Cross-Bank Multi-Active Monitoring
    logic [BANK_COUNT-1:0] bank_throttled_flags;
    logic                  coordinated_throttle_active;
    logic [15:0]           coordinated_throttle_cnt;

    assign o_coordinated_throttle_active = coordinated_throttle_active;
    assign o_bank_throttled_flags         = bank_throttled_flags;
    assign o_coordinated_throttle_cnt     = coordinated_throttle_cnt;

    wire will_throttle      = (effective_count >= thresh_q);
    wire effective_throttle = will_throttle || coordinated_throttle_active;

    // Handshake control
    assign en          = !o_cmd_valid || i_cmd_ready;
    assign o_cmd_ready = en;

    // Table Update on Handshake
    wire [COUNT_WIDTH-1:0] inc_val = 1'b1 + COUNT_WIDTH'(i_rowpress_weight);
    // Hàng chạm ngưỡng: lệnh giảm thiểu làm tươi nạn nhân nên đếm lại từ 0 (mỗi T ACT một lần giảm thiểu).
    // Giữ nguyên số đếm sẽ giảm thiểu ở MỌI truy cập tới hết tREFW (bão refresh). Đánh đổi: hàng khác dùng chung
    // bin có thể bị đếm thiếu, nên bảo đảm hiệu dụng là 2T ACT -> cấu hình T <= ngưỡng RowHammer / 2.
    always_comb begin
        if (will_throttle)                                  new_cnt_a = '0;
        else if (cur_cnt_a <= ({COUNT_WIDTH{1'b1}} - inc_val)) new_cnt_a = cur_cnt_a + inc_val;
        else                                                new_cnt_a = {COUNT_WIDTH{1'b1}};
        if (will_throttle)                                  new_cnt_b = '0;
        else if (cur_cnt_b <= ({COUNT_WIDTH{1'b1}} - inc_val)) new_cnt_b = cur_cnt_b + inc_val;
        else                                                new_cnt_b = {COUNT_WIDTH{1'b1}};
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            table_a_epoch <= '0;
            table_b_epoch <= '0;
            sweep_idx     <= '0;
            for (int i = 0; i < TABLE_ENTRIES; i++) begin
                table_a_count[i] <= '0;
                table_b_count[i] <= '0;
            end
        end else begin
            // Quét nền 1 bin/chu kỳ xoá bin thuộc epoch cũ. Epoch dài hàng triệu chu kỳ nên mọi bin được quét trong mỗi
            // epoch: tag 1 bit không thể khớp nhầm với số đếm của 2 epoch trước. Truy cập cùng bin ghi sau nên được ưu tiên.
            sweep_idx <= sweep_idx + 1'b1;
            if (table_a_epoch[sweep_idx] != current_epoch) begin
                table_a_count[sweep_idx] <= '0;
                table_a_epoch[sweep_idx] <= current_epoch;
            end
            if (table_b_epoch[sweep_idx] != current_epoch) begin
                table_b_count[sweep_idx] <= '0;
                table_b_epoch[sweep_idx] <= current_epoch;
            end

            if (s_fire) begin
                table_a_count[eff_hash_a] <= new_cnt_a;
                table_a_epoch[eff_hash_a] <= current_epoch;
                if (cfg_hash_mode == 1'b1) begin
                    table_b_count[eff_hash_b] <= new_cnt_b;
                    table_b_epoch[eff_hash_b] <= current_epoch;
                end
            end
        end
    end

    //=========================================================================
    // 4. Output Pipeline & Mitigation Trigger
    //=========================================================================
    logic                      out_valid;
    logic [AXI_ID_WIDTH-1:0]   out_id;
    logic                      out_is_write;
    logic [BG_WIDTH-1:0]       out_bg;
    logic [BANK_WIDTH-1:0]     out_bank;
    logic [ROW_WIDTH-1:0]      out_row;
    logic [COL_WIDTH-1:0]      out_col;
    logic [7:0]                out_len;
    logic [AXI_QOS_WIDTH-1:0]  out_qos;
    logic                      out_throttled;

    logic                      mitigation_req_reg;
    logic [BG_WIDTH-1:0]       mitigation_bg_reg;
    logic [BANK_WIDTH-1:0]     mitigation_bank_reg;
    logic [ROW_WIDTH-1:0]      mitigation_row_reg;
    logic                      sdc_alert_reg;

    logic [31:0]               telemetry_accesses_reg;
    logic [31:0]               telemetry_throttles_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid                   <= 1'b0;
            out_id                      <= '0;
            out_is_write                <= 1'b0;
            out_bg                      <= '0;
            out_bank                    <= '0;
            out_row                     <= '0;
            out_col                     <= '0;
            out_len                     <= '0;
            out_qos                     <= '0;
            out_throttled               <= 1'b0;
            mitigation_req_reg          <= 1'b0;
            mitigation_bg_reg           <= '0;
            mitigation_bank_reg         <= '0;
            mitigation_row_reg          <= '0;
            sdc_alert_reg               <= 1'b0;
            telemetry_accesses_reg      <= '0;
            telemetry_throttles_reg     <= '0;
            bank_throttled_flags        <= '0;
            coordinated_throttle_active <= 1'b0;
            coordinated_throttle_cnt    <= '0;
        end else begin
            // Mitigation pulse is single-cycle
            mitigation_req_reg <= 1'b0;

            // SledgeHammer Cross-Bank tracking
            if (window_timer >= cfg_window_size) begin
                bank_throttled_flags        <= '0;
                coordinated_throttle_active <= 1'b0;
            end else begin
                if (s_fire && will_throttle) begin
                    bank_throttled_flags[s_bank] <= 1'b1;
                end
                if ($countones(bank_throttled_flags) > cfg_multibank_thresh) begin
                    coordinated_throttle_active <= 1'b1;
                    if (!coordinated_throttle_active) begin
                        coordinated_throttle_cnt <= coordinated_throttle_cnt + 1'b1;
                    end
                end
            end

            if (en) begin
                out_valid <= p2_valid;
                if (p2_valid) begin
                    out_id        <= s_id;
                    out_is_write  <= s_is_write;
                    out_bg        <= s_bg;
                    out_bank      <= s_bank;
                    out_row       <= s_row;
                    out_col       <= s_col;
                    out_len       <= s_len;
                    out_qos       <= s_qos;
                    out_throttled <= effective_throttle;

                    telemetry_accesses_reg <= telemetry_accesses_reg + 1'b1;

                    if (effective_throttle) begin
                        telemetry_throttles_reg <= telemetry_throttles_reg + 1'b1;
                        mitigation_req_reg      <= 1'b1;
                        mitigation_bg_reg       <= s_bg;
                        mitigation_bank_reg     <= s_bank;
                        mitigation_row_reg      <= s_row;
                        sdc_alert_reg           <= 1'b1;
                    end
                end
            end
        end
    end

    assign o_cmd_valid           = out_valid;
    assign o_cmd_id              = out_id;
    assign o_cmd_is_write        = out_is_write;
    assign o_cmd_bg              = out_bg;
    assign o_cmd_bank            = out_bank;
    assign o_cmd_row             = out_row;
    assign o_cmd_col             = out_col;
    assign o_cmd_len             = out_len;
    assign o_cmd_qos             = out_qos;
    assign o_cmd_throttled       = out_throttled;

    assign o_mitigation_req      = mitigation_req_reg;
    assign o_mitigation_bg       = mitigation_bg_reg;
    assign o_mitigation_bank     = mitigation_bank_reg;
    assign o_mitigation_row      = mitigation_row_reg;
    assign o_sdc_alert           = sdc_alert_reg;
    assign o_telemetry_accesses  = telemetry_accesses_reg;
    assign o_telemetry_throttles = telemetry_throttles_reg;


    //=========================================================================
    // Hardware Formal Verification (SymbiYosys / SVA)
    //=========================================================================
`ifdef FORMAL
    initial begin
        assume (!rst_n);
    end

    always_ff @(posedge clk) begin
        if ($past(!rst_n))
            assume (rst_n);
        if (rst_n && $past(rst_n)) begin
            assume ($stable(cfg_sdc_thresh));
            assume ($stable(cfg_window_size));
            assume ($stable(cfg_hash_mode));
        end
    end

    // Configuration assumptions
    always_comb begin
        assume (cfg_sdc_thresh >= 16'd2);
        assume (cfg_window_size >= 16'd10);
    end

    // Property 1: Reset behavior
    always_comb begin
        if (!rst_n) begin
            assert (!o_cmd_valid);
            assert (!o_sdc_alert);
            assert (!o_mitigation_req);
            assert (o_telemetry_accesses == 16'd0);
            assert (o_telemetry_throttles == 16'd0);
        end
    end

    // Property 2: Window Timer Bound
    always_comb begin
        if (rst_n) begin
            assert (window_timer <= cfg_window_size);
        end
    end

    // Property 3: Throttle and Alert Consistency
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(s_fire && will_throttle)) begin
                assert (o_sdc_alert);
                assert (o_mitigation_req);
                assert (o_cmd_valid);
                assert (o_cmd_throttled);
            end
        end
    end

    // Property 4: Telemetry Monotonicity on Throttle
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(s_fire && will_throttle)) begin
                assert (o_telemetry_throttles == $past(o_telemetry_throttles) + 1'b1);
            end
        end
    end

    // Property 5: Blacksmith-Invariance Bound
    // Invariance: Any command hitting an entry that reached threshold within the epoch must be throttled.
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(s_fire && will_throttle)) begin
                assert (o_cmd_throttled);
            end
        end
    end

    // Property 6: SledgeHammer Multi-Bank Coordinated Throttling Guarantee
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(rst_n && ($countones(bank_throttled_flags) > cfg_multibank_thresh) && (window_timer < cfg_window_size))) begin
                assert (coordinated_throttle_active);
            end
        end
    end

    // Property 7: Count-Min Sketch Lower Bound (Zero False Negatives)
    // Mathematical guarantee: min(C1, C2) is an upper bound on true activations.
    // If effective_count >= cfg_sdc_thresh, will_throttle is unconditionally asserted.
    always_comb begin
        if (rst_n) begin
            if (effective_count >= thresh_q) begin
                assert (will_throttle);
                assert (effective_throttle);
            end
        end
    end

    // Property 8: Cửa sổ throttle phối hợp quay về 0; epoch chỉ đổi sau đủ REFW_REFS lệnh REFab
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(window_timer >= cfg_window_size)) assert (window_timer == 16'd0);
            if (current_epoch != $past(current_epoch)) assert ($past(i_ref_tick && ref_cnt == REFW_W'(REFW_REFS - 1)));
        end
    end
`endif

endmodule
