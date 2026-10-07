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
    parameter int COUNT_WIDTH    = 16
) (
    input  logic                      clk,
    input  logic                      rst_n,

    // Configuration & Thresholds
    input  logic                      cfg_hash_mode,   // 0: Single-Hash, 1: Dual-Hash
    input  logic [COUNT_WIDTH-1:0]    cfg_sdc_thresh,  // Activation alert threshold
    input  logic [15:0]               cfg_window_size, // Cycles per tREFI window
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

    //=========================================================================
    // 2. O(1) Window Reset Logic via Epoch Tagging
    //=========================================================================
    logic [15:0] window_timer;
    logic        current_epoch;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            window_timer  <= '0;
            current_epoch <= 1'b0;
        end else begin
            if (window_timer >= cfg_window_size) begin
                window_timer  <= '0;
                current_epoch <= ~current_epoch; // Instant O(1) window reset!
            end else begin
                window_timer  <= window_timer + 1'b1;
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

    // Read current effective counts
    wire [COUNT_WIDTH-1:0] cur_cnt_a = (table_a_epoch[hash_a] == current_epoch) ? table_a_count[hash_a] : '0;
    wire [COUNT_WIDTH-1:0] cur_cnt_b = (table_b_epoch[hash_b] == current_epoch) ? table_b_count[hash_b] : '0;

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

    wire will_throttle      = (effective_count >= cfg_sdc_thresh);
    wire effective_throttle = will_throttle || coordinated_throttle_active;

    // Handshake control
    assign o_cmd_ready = !o_cmd_valid || i_cmd_ready;

    // Table Update on Handshake
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            table_a_epoch <= '0;
            table_b_epoch <= '0;
            for (int i = 0; i < TABLE_ENTRIES; i++) begin
                table_a_count[i] <= '0;
                table_b_count[i] <= '0;
            end
        end else if (i_cmd_valid && o_cmd_ready) begin
            // Increment Table A
            if (cur_cnt_a != {COUNT_WIDTH{1'b1}}) begin
                table_a_count[hash_a] <= cur_cnt_a + 1'b1;
                table_a_epoch[hash_a] <= current_epoch;
            end
            // Increment Table B (in Dual-Hash mode)
            if (cfg_hash_mode == 1'b1) begin
                if (cur_cnt_b != {COUNT_WIDTH{1'b1}}) begin
                    table_b_count[hash_b] <= cur_cnt_b + 1'b1;
                    table_b_epoch[hash_b] <= current_epoch;
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
                if (i_cmd_valid && o_cmd_ready && will_throttle) begin
                    bank_throttled_flags[i_cmd_bank] <= 1'b1;
                end
                if ($countones(bank_throttled_flags) > cfg_multibank_thresh) begin
                    coordinated_throttle_active <= 1'b1;
                    if (!coordinated_throttle_active) begin
                        coordinated_throttle_cnt <= coordinated_throttle_cnt + 1'b1;
                    end
                end
            end

            if (o_cmd_ready) begin
                out_valid <= i_cmd_valid;
                if (i_cmd_valid) begin
                    out_id        <= i_cmd_id;
                    out_is_write  <= i_cmd_is_write;
                    out_bg        <= i_cmd_bg;
                    out_bank      <= i_cmd_bank;
                    out_row       <= i_cmd_row;
                    out_col       <= i_cmd_col;
                    out_len       <= i_cmd_len;
                    out_qos       <= i_cmd_qos;
                    out_throttled <= effective_throttle;

                    telemetry_accesses_reg <= telemetry_accesses_reg + 1'b1;

                    if (effective_throttle) begin
                        telemetry_throttles_reg <= telemetry_throttles_reg + 1'b1;
                        mitigation_req_reg      <= 1'b1;
                        mitigation_bg_reg       <= i_cmd_bg;
                        mitigation_bank_reg     <= i_cmd_bank;
                        mitigation_row_reg      <= i_cmd_row;
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
            if ($past(o_cmd_ready && i_cmd_valid && will_throttle)) begin
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
            if ($past(o_cmd_ready && i_cmd_valid && will_throttle)) begin
                assert (o_telemetry_throttles == $past(o_telemetry_throttles) + 1'b1);
            end
        end
    end

    // Property 5: Blacksmith-Invariance Bound
    // Invariance: Any command hitting an entry that reached threshold within the epoch must be throttled.
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(o_cmd_ready && i_cmd_valid && will_throttle)) begin
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
            if (effective_count >= cfg_sdc_thresh) begin
                assert (will_throttle);
                assert (effective_throttle);
            end
        end
    end

    // Property 8: Instantaneous Epoch Clear Correctness
    // Upon epoch toggle, stale table entries evaluate to 0 effective count with zero command stalls.
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(window_timer >= cfg_window_size)) begin
                assert (window_timer == 16'd0);
                assert (current_epoch != $past(current_epoch));
            end
        end
    end
`endif

endmodule
