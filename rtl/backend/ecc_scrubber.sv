//=============================================================================
// File:        ecc_scrubber.sv
// Chức năng:   Quét tuần tra bộ nhớ nền và tự động sửa lỗi ngầm 1-bit bằng mã Hamming SEC-DED (72, 64).
//=============================================================================
`timescale 1ns / 1ps

module ecc_scrubber #(
    parameter int DATA_WIDTH     = 64,
    parameter int ECC_WIDTH      = DATA_WIDTH / 8,   // SEC-DED (72,64) cho mỗi làn 64 bit
    parameter int BG_COUNT       = 8,
    parameter int BG_WIDTH       = $clog2(BG_COUNT),
    parameter int BANK_COUNT     = 4,
    parameter int BANK_WIDTH     = $clog2(BANK_COUNT),
    parameter int ROW_WIDTH      = 17,
    parameter int COL_WIDTH      = 13,
    parameter int DEFAULT_INTERVAL = 1000,
    parameter int ZEM_ENTRIES    = 16
)(
    input  logic                                         clk,
    input  logic                                         rst_n,

    // Configuration & Control
    input  logic                                         cfg_enable,
    input  logic [15:0]                                  cfg_interval,

    // Scrubbing Request Interface (to slack_aware_arbiter)
    output logic                                         o_scrub_req,
    output logic [BG_WIDTH-1:0]                          o_scrub_bg,
    output logic [BANK_WIDTH-1:0]                        o_scrub_bank,
    output logic [ROW_WIDTH-1:0]                         o_scrub_row,
    input  logic                                         i_scrub_grant,

    // Read Data Return from Memory for verification
    input  logic                                         i_data_valid,
    input  logic [DATA_WIDTH-1:0]                        i_raw_data,
    input  logic [ECC_WIDTH-1:0]                         i_raw_ecc,
    // Địa chỉ của beat đang kiểm (ZEM ghi đúng hàng và cột có lỗi, không phải toạ độ patrol)
    input  logic [BG_WIDTH-1:0]                          i_data_bg   = '0,
    input  logic [BANK_WIDTH-1:0]                        i_data_bank = '0,
    input  logic [ROW_WIDTH-1:0]                         i_data_row  = '0,
    input  logic [COL_WIDTH-1:0]                         i_data_col  = '0,

    // OpenTitan-inspired Fault Injection Interface (for Verification & Diagnostic Testing)
    input  logic                                         i_fault_inject_en,
    input  logic [1:0]                                   i_fault_inject_type, // 01: Single-Bit, 10: Double-Bit
    input  logic [5:0]                                   i_fault_inject_bit,

    // Error Reporting & Corrected Output
    output logic                                         o_corrected_valid,
    output logic [DATA_WIDTH-1:0]                        o_corrected_data,
    output logic                                         o_single_err,
    output logic                                         o_double_err,
    output logic [15:0]                                  o_single_err_cnt,
    output logic [15:0]                                  o_double_err_cnt,

    // SOTA ECCfail Miscorrection Trap & Fallback Interface
    output logic                                         o_ecc_miscorrect_alert,
    output logic [15:0]                                  o_ecc_miscorrect_cnt,
    output logic                                         o_chipkill_fallback_req,

    // ZEM Zero-Cycle Fault Masking Cache Interface (Le Minh Son et al., HCMUTE / NUS)
    input  logic                                         i_zem_lookup_valid = 1'b0,
    input  logic [BG_WIDTH-1:0]                          i_zem_lookup_bg    = '0,
    input  logic [BANK_WIDTH-1:0]                        i_zem_lookup_bank  = '0,
    input  logic [ROW_WIDTH-1:0]                         i_zem_lookup_row   = '0,
    input  logic [COL_WIDTH-1:0]                         i_zem_lookup_col   = '0,
    output logic                                         o_zem_hit,
    output logic [DATA_WIDTH-1:0]                        o_zem_mask,
    output logic [15:0]                                  o_zem_hit_cnt
);

    //=========================================================================
    // Fault Injection Pre-processing (OpenTitan Architecture Reference)
    //=========================================================================
    logic [DATA_WIDTH-1:0] effective_data;
    logic [ECC_WIDTH-1:0]  effective_ecc;

    always_comb begin
        effective_data = i_raw_data;
        effective_ecc  = i_raw_ecc;
        if (i_fault_inject_en) begin
            case (i_fault_inject_type)
                2'b01: begin // Single-bit flip
                    effective_data[i_fault_inject_bit] = ~i_raw_data[i_fault_inject_bit];
                end
                2'b10: begin // Double-bit flip (SDC injection)
                    effective_data[i_fault_inject_bit] = ~i_raw_data[i_fault_inject_bit];
                    effective_data[(i_fault_inject_bit == 6'd63) ? 6'd0 : (i_fault_inject_bit + 1'b1)] = 
                        ~i_raw_data[(i_fault_inject_bit == 6'd63) ? 6'd0 : (i_fault_inject_bit + 1'b1)];
                end
                2'b11: begin // 3-bit flip cluster (ECCfail attack)
                    effective_data[i_fault_inject_bit] = ~i_raw_data[i_fault_inject_bit];
                    effective_data[(i_fault_inject_bit >= 6'd63) ? 6'd0 : (i_fault_inject_bit + 6'd1)] = 
                        ~i_raw_data[(i_fault_inject_bit >= 6'd63) ? 6'd0 : (i_fault_inject_bit + 6'd1)];
                    effective_data[(i_fault_inject_bit >= 6'd62) ? 6'd1 : (i_fault_inject_bit + 6'd2)] = 
                        ~i_raw_data[(i_fault_inject_bit >= 6'd62) ? 6'd1 : (i_fault_inject_bit + 6'd2)];
                end
                default: ;
            endcase
        end
    end

    //=========================================================================
    // Giải mã SEC-DED (72,64) thật (secded_72_64_pkg)
    //=========================================================================
    function automatic logic syn7_is_data_bit(input logic [6:0] p);
        logic low6_non_pow2;
        begin
            case (p[5:0])
                6'd0, 6'd1, 6'd2, 6'd4, 6'd8, 6'd16, 6'd32: low6_non_pow2 = 1'b0;
                default:                                     low6_non_pow2 = 1'b1;
            endcase
            syn7_is_data_bit = (!p[6]) ? low6_non_pow2 : (!(|p[5:3]) && (|p[2:0]));
        end
    endfunction

    function automatic logic [5:0] syn7_to_bit(input logic [6:0] p);
        begin
            case (p)
                7'd3:  syn7_to_bit = 6'd0;
                7'd5:  syn7_to_bit = 6'd1;   7'd6:  syn7_to_bit = 6'd2;   7'd7:  syn7_to_bit = 6'd3;
                7'd9:  syn7_to_bit = 6'd4;   7'd10: syn7_to_bit = 6'd5;   7'd11: syn7_to_bit = 6'd6;
                7'd12: syn7_to_bit = 6'd7;   7'd13: syn7_to_bit = 6'd8;   7'd14: syn7_to_bit = 6'd9;   7'd15: syn7_to_bit = 6'd10;
                7'd17: syn7_to_bit = 6'd11;  7'd18: syn7_to_bit = 6'd12;  7'd19: syn7_to_bit = 6'd13;  7'd20: syn7_to_bit = 6'd14;
                7'd21: syn7_to_bit = 6'd15;  7'd22: syn7_to_bit = 6'd16;  7'd23: syn7_to_bit = 6'd17;  7'd24: syn7_to_bit = 6'd18;
                7'd25: syn7_to_bit = 6'd19;  7'd26: syn7_to_bit = 6'd20;  7'd27: syn7_to_bit = 6'd21;  7'd28: syn7_to_bit = 6'd22;
                7'd29: syn7_to_bit = 6'd23;  7'd30: syn7_to_bit = 6'd24;  7'd31: syn7_to_bit = 6'd25;
                7'd33: syn7_to_bit = 6'd26;  7'd34: syn7_to_bit = 6'd27;  7'd35: syn7_to_bit = 6'd28;  7'd36: syn7_to_bit = 6'd29;
                7'd37: syn7_to_bit = 6'd30;  7'd38: syn7_to_bit = 6'd31;  7'd39: syn7_to_bit = 6'd32;  7'd40: syn7_to_bit = 6'd33;
                7'd41: syn7_to_bit = 6'd34;  7'd42: syn7_to_bit = 6'd35;  7'd43: syn7_to_bit = 6'd36;  7'd44: syn7_to_bit = 6'd37;
                7'd45: syn7_to_bit = 6'd38;  7'd46: syn7_to_bit = 6'd39;  7'd47: syn7_to_bit = 6'd40;  7'd48: syn7_to_bit = 6'd41;
                7'd49: syn7_to_bit = 6'd42;  7'd50: syn7_to_bit = 6'd43;  7'd51: syn7_to_bit = 6'd44;  7'd52: syn7_to_bit = 6'd45;
                7'd53: syn7_to_bit = 6'd46;  7'd54: syn7_to_bit = 6'd47;  7'd55: syn7_to_bit = 6'd48;  7'd56: syn7_to_bit = 6'd49;
                7'd57: syn7_to_bit = 6'd50;  7'd58: syn7_to_bit = 6'd51;  7'd59: syn7_to_bit = 6'd52;  7'd60: syn7_to_bit = 6'd53;
                7'd61: syn7_to_bit = 6'd54;  7'd62: syn7_to_bit = 6'd55;  7'd63: syn7_to_bit = 6'd56;
                7'd65: syn7_to_bit = 6'd57;  7'd66: syn7_to_bit = 6'd58;  7'd67: syn7_to_bit = 6'd59;  7'd68: syn7_to_bit = 6'd60;
                7'd69: syn7_to_bit = 6'd61;  7'd70: syn7_to_bit = 6'd62;  7'd71: syn7_to_bit = 6'd63;
                default: syn7_to_bit = 6'd0;
            endcase
        end
    endfunction

    localparam int LANES = DATA_WIDTH / 64;
    localparam int CBW   = $clog2(DATA_WIDTH);
    logic [7:0]            syn;
    logic [DATA_WIDTH-1:0] bit_correction_mask;
    logic                  is_single_err, is_double_err, is_miscorrect;
    logic                  syn_is_data_ce;
    logic [CBW-1:0]        corr_bit;

    always_comb begin
        logic ce_any;
        ce_any         = 1'b0;
        is_double_err  = 1'b0;
        is_miscorrect  = 1'b0;
        syn_is_data_ce = 1'b0;
        syn            = '0;
        for (int l = 0; l < LANES; l++) begin
            logic [7:0] s;
            logic       l_ce;
            s = secded_72_64_pkg::secded72_syndrome(effective_data[l*64 +: 64], effective_ecc[l*8 +: 8]);
            l_ce = secded_72_64_pkg::secded72_ce(s);
            bit_correction_mask[l*64 +: 64] = secded_72_64_pkg::secded72_flip(s);
            ce_any         = ce_any | l_ce;
            syn_is_data_ce = syn_is_data_ce | (l_ce && syn7_is_data_bit(s[6:0]));
            // Lỗi lẻ ở vị trí Hamming không tồn tại: >=3 bit giả dạng lỗi đơn (ECCfail), không được sửa
            is_miscorrect  = is_miscorrect | (s[7] && !l_ce);
            is_double_err  = is_double_err | ((s != 8'h00) && !s[7]);
            syn            = syn | s;
        end
        // Beat có một làn không sửa được thì cả beat bị coi là hỏng (poison), không đếm là lỗi đã sửa
        is_single_err = ce_any && !is_double_err && !is_miscorrect;
    end

    assign o_corrected_valid = i_data_valid;
    assign o_corrected_data  = effective_data ^ bit_correction_mask;
    assign o_single_err      = i_data_valid && is_single_err;
    assign o_double_err      = i_data_valid && is_double_err;

    assign o_ecc_miscorrect_alert  = i_data_valid && is_miscorrect;
    assign o_chipkill_fallback_req = o_ecc_miscorrect_alert || o_double_err;

    // Giải mã vị trí bit lỗi trực tiếp từ syndrome 7-bit để cắt phụ thuộc cây OR 64-bit vào ZEM
    always_comb begin
        if (LANES == 1) begin
            corr_bit = CBW'(syn7_to_bit(syn[6:0]));
        end else begin
            corr_bit = '0;
            for (int j = 0; j < DATA_WIDTH; j++) if (bit_correction_mask[j]) corr_bit = CBW'(j);
        end
    end

    //=========================================================================
    // Patrol Memory Address Scanner & Scrubbing Interval Counter
    //=========================================================================
    logic [15:0]           interval_cnt;
    logic [BG_WIDTH-1:0]   patrol_bg;
    logic [BANK_WIDTH-1:0] patrol_bank;
    logic [ROW_WIDTH-1:0]  patrol_row;
    logic                  scrub_pending;

    logic [15:0]           single_err_counter;
    logic [15:0]           double_err_counter;
    logic [15:0]           miscorrect_counter;

    assign o_single_err_cnt    = single_err_counter;
    assign o_double_err_cnt    = double_err_counter;
    assign o_ecc_miscorrect_cnt = miscorrect_counter;

    assign o_scrub_req  = scrub_pending;
    assign o_scrub_bg   = patrol_bg;
    assign o_scrub_bank = patrol_bank;
    assign o_scrub_row  = patrol_row;

    wire [15:0] target_interval = (cfg_interval != '0) ? cfg_interval : 16'(DEFAULT_INTERVAL);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            interval_cnt       <= '0;
            patrol_bg          <= '0;
            patrol_bank        <= '0;
            patrol_row         <= '0;
            scrub_pending      <= 1'b0;
            single_err_counter <= '0;
            double_err_counter <= '0;
            miscorrect_counter <= '0;
        end else begin
            if (cfg_enable) begin
                // Interval Timer
                if (interval_cnt >= target_interval) begin
                    interval_cnt  <= '0;
                    scrub_pending <= 1'b1;
                end else begin
                    interval_cnt  <= interval_cnt + 1'b1;
                end

                // Address progression upon scrub grant
                if (scrub_pending && i_scrub_grant) begin
                    scrub_pending <= 1'b0;
                    // Increment patrol coordinate (BG -> Bank -> Row)
                    if (patrol_bg == BG_WIDTH'(BG_COUNT - 1)) begin
                        patrol_bg <= '0;
                        if (patrol_bank == BANK_WIDTH'(BANK_COUNT - 1)) begin
                            patrol_bank <= '0;
                            patrol_row  <= patrol_row + 1'b1;
                        end else begin
                            patrol_bank <= patrol_bank + 1'b1;
                        end
                    end else begin
                        patrol_bg <= patrol_bg + 1'b1;
                    end
                end

                // Error Telemetry Accumulation
                if (i_data_valid) begin
                    if (is_single_err) begin
                        single_err_counter <= single_err_counter + 1'b1;
                    end
                    if (is_double_err) begin
                        double_err_counter <= double_err_counter + 1'b1;
                    end
                    if (is_miscorrect) begin
                        miscorrect_counter <= miscorrect_counter + 1'b1;
                    end
                end
            end else begin
                scrub_pending <= 1'b0;
                interval_cnt  <= '0;
            end
        end
    end

    //=========================================================================
    // ZEM Zero-Cycle Asymmetric Fault-Masking Cache (Le Minh Son et al., HCMUTE/NUS)
    // Bộ đệm CAM 16 mục theo toạ độ {bg, bank, row, col}; chỉ kích hoạt mask sau
    // >= 2 lần xác nhận stuck-at cùng bit tại cùng ô để chặn tấn công đầu độc ZEM,
    // và tự vô hiệu hoá mục khi gặp lỗi check-bit / UE hoặc ô tự hết lỗi (R-69).
    //=========================================================================
    localparam int ZEM_PTR_W = (ZEM_ENTRIES > 1) ? $clog2(ZEM_ENTRIES) : 1;
    logic [ZEM_ENTRIES-1:0]          zem_valid;
    logic [ZEM_ENTRIES-1:0]          zem_active;
    logic [BG_WIDTH-1:0]             zem_bg   [ZEM_ENTRIES];
    logic [BANK_WIDTH-1:0]           zem_bank [ZEM_ENTRIES];
    logic [ROW_WIDTH-1:0]            zem_row  [ZEM_ENTRIES];
    logic [COL_WIDTH-1:0]            zem_col  [ZEM_ENTRIES];
    logic [CBW-1:0]                  zem_bit  [ZEM_ENTRIES];
    logic [6:0]                      zem_syn  [ZEM_ENTRIES];
    logic [ZEM_PTR_W-1:0]            zem_alloc_ptr;
    logic [15:0]                     zem_hit_counter;

    assign o_zem_hit_cnt = zem_hit_counter;

    // Rút gọn one-hot theo chỉ số bit (CBW bit thay vì 64 bit mỗi mục) rồi giải mã 1 << bit để giảm tầng LUT trên đường đọc
    logic [ZEM_ENTRIES-1:0] lk_match;
    logic [CBW-1:0]         lk_bit;
    always_comb begin
        lk_match = '0;
        lk_bit   = '0;
        if (i_zem_lookup_valid) begin
            for (int k = 0; k < ZEM_ENTRIES; k++) begin
                lk_match[k] = zem_valid[k] && zem_active[k] &&
                              (zem_bg[k]   == i_zem_lookup_bg)   &&
                              (zem_bank[k] == i_zem_lookup_bank) &&
                              (zem_row[k]  == i_zem_lookup_row)  &&
                              (zem_col[k]  == i_zem_lookup_col);
                if (lk_match[k]) lk_bit = lk_bit | zem_bit[k];
            end
        end
        o_zem_hit  = |lk_match;
        o_zem_mask = o_zem_hit ? ({{(DATA_WIDTH-1){1'b0}}, 1'b1} << lk_bit) : '0;
    end

    // Phân loại 3 sự kiện loại trừ lẫn nhau và so bit lỗi trực tiếp qua 7-bit syndrome để rút ngắn đường CE của ZEM
    logic                   ev_data_ce, ev_clean, ev_inv_row;
    logic [ZEM_ENTRIES-1:0] zem_row_hit, zem_coord_hit;
    logic                   zem_coord_exists;
    logic [ZEM_PTR_W-1:0]   alloc_slot;
    logic [ZEM_ENTRIES-1:0] alloc_mask, bit_match, slot_alloc;
    always_comb begin
        if (LANES == 1) begin
            ev_clean   = (syn == 8'h00);
            ev_data_ce = syn[7] && syn_is_data_ce;
        end else begin
            ev_clean   = !is_single_err && !is_double_err && !is_miscorrect;
            ev_data_ce = is_single_err && syn_is_data_ce;
        end
        ev_inv_row = !ev_clean && !ev_data_ce;

        for (int k = 0; k < ZEM_ENTRIES; k++) begin
            zem_row_hit[k]   = zem_valid[k] &&
                               (zem_bg[k]   == i_data_bg)   &&
                               (zem_bank[k] == i_data_bank) &&
                               (zem_row[k]  == i_data_row);
            zem_coord_hit[k] = zem_row_hit[k] && (zem_col[k] == i_data_col);
            bit_match[k]     = (LANES == 1) ? (syn[7] && (syn[6:0] == zem_syn[k]))
                                            : (ev_data_ce && (corr_bit == zem_bit[k]));
        end
        zem_coord_exists = |zem_coord_hit;

        // Ưu tiên khe trống -> khe chưa xác nhận để lỗi đơn lẻ ở ngoài không đẩy mất mục stuck-at đã xác nhận
        alloc_slot = zem_alloc_ptr;
        for (int k = ZEM_ENTRIES - 1; k >= 0; k--) begin
            if (!zem_active[k]) alloc_slot = ZEM_PTR_W'(k);
        end
        for (int k = ZEM_ENTRIES - 1; k >= 0; k--) begin
            if (!zem_valid[k]) alloc_slot = ZEM_PTR_W'(k);
        end
        for (int k = 0; k < ZEM_ENTRIES; k++) begin
            alloc_mask[k] = (alloc_slot == ZEM_PTR_W'(k));
            slot_alloc[k] = ev_data_ce && !zem_coord_exists && alloc_mask[k];
        end
    end

    // Máy trạng thái học 2 bước, tự vô hiệu khi gặp check-bit/UE hoặc khi mục đang mask lại phát sinh đúng bit đó
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            zem_valid       <= '0;
            zem_active      <= '0;
            zem_alloc_ptr   <= '0;
            zem_hit_counter <= '0;
            for (int k = 0; k < ZEM_ENTRIES; k++) begin
                zem_bg[k]   <= '0;
                zem_bank[k] <= '0;
                zem_row[k]  <= '0;
                zem_col[k]  <= '0;
                zem_bit[k]  <= '0;
                zem_syn[k]  <= '0;
            end
        end else begin
            if (i_zem_lookup_valid && o_zem_hit) begin
                zem_hit_counter <= zem_hit_counter + 1'b1;
            end

            if (i_data_valid) begin
                if (ev_data_ce && !zem_coord_exists) begin
                    zem_alloc_ptr <= alloc_slot + ZEM_PTR_W'(1);
                end
                for (int k = 0; k < ZEM_ENTRIES; k++) begin
                    if (slot_alloc[k]) begin
                        zem_valid[k]  <= 1'b1;
                        zem_active[k] <= 1'b0;
                        zem_bg[k]     <= i_data_bg;
                        zem_bank[k]   <= i_data_bank;
                        zem_row[k]    <= i_data_row;
                        zem_col[k]    <= i_data_col;
                        zem_bit[k]    <= corr_bit;
                        zem_syn[k]    <= syn[6:0];
                    end else begin
                        if (ev_data_ce && zem_coord_hit[k] && !zem_active[k]) begin
                            zem_bit[k] <= corr_bit;
                            zem_syn[k] <= syn[6:0];
                        end
                        if ((ev_inv_row && zem_row_hit[k]) ||
                            (ev_clean && zem_coord_hit[k] && !zem_active[k]) ||
                            (zem_coord_hit[k] && zem_active[k] && bit_match[k])) begin
                            zem_valid[k]  <= 1'b0;
                            zem_active[k] <= 1'b0;
                        end else if (zem_coord_hit[k] && !zem_active[k] && bit_match[k]) begin
                            zem_active[k] <= 1'b1;
                        end
                    end
                end
            end
        end
    end

`ifdef FORMAL
    initial assume (!rst_n);

    always_ff @(posedge clk) begin
        if ($past(!rst_n)) assume (rst_n);
        if ($past(rst_n))  assume (rst_n);
    end

    // Giả định codeword ECC hợp lệ trên bus đọc DRAM gốc
    logic [ECC_WIDTH-1:0] expected_ecc;
    always_comb for (int l = 0; l < LANES; l++) expected_ecc[l*8 +: 8] = secded_72_64_pkg::secded72_enc(i_raw_data[l*64 +: 64]);

    always_comb begin
        if (i_data_valid) begin
            assume (i_raw_ecc == expected_ecc);
        end
    end

    // 1. Trạng thái sau reset
    always_comb begin
        if (!rst_n) begin
            assert (!o_scrub_req);
            assert (single_err_counter == '0);
            assert (double_err_counter == '0);
        end
    end

    // 2. Dữ liệu sạch (Clean Codeword): Không báo lỗi sai, dữ liệu truyền suốt nguyên vẹn
    always_comb begin
        if (rst_n && i_data_valid && !i_fault_inject_en) begin
            assert (!o_single_err);
            assert (!o_double_err);
            assert (o_corrected_data == i_raw_data);
        end
    end

    // 2b. SEC: lỗi 1 bit ở bất kỳ vị trí dữ liệu nào của codeword sạch được sửa về đúng dữ liệu gốc (mọi giá trị dữ liệu)
    always_comb begin
        if (rst_n && i_data_valid && i_fault_inject_en && i_fault_inject_type == 2'b01) begin
            assert (o_single_err && !o_double_err && o_corrected_data == i_raw_data);
        end
    end

    // 2c. DED: lỗi 2 bit luôn bị phát hiện và không bao giờ bị "sửa" như lỗi đơn
    always_comb begin
        if (rst_n && i_data_valid && i_fault_inject_en && i_fault_inject_type == 2'b10) begin
            assert (o_double_err && !o_single_err);
        end
    end

    // 3. Phân loại lỗi SEC / DED khi có sự cố
    always_comb begin
        if (rst_n && i_data_valid) begin
            // Không bao giờ đồng thời vừa là lỗi 1-bit vừa là lỗi 2-bit
            assert (!(o_single_err && o_double_err));
        end
    end

    // 4. Tính đơn điệu của bộ đếm viễn trắc telemetry lỗi
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(cfg_enable && i_data_valid && is_single_err)) begin
                assert (single_err_counter == $past(single_err_counter) + 16'd1);
            end
            if ($past(cfg_enable && i_data_valid && is_double_err)) begin
                assert (double_err_counter == $past(double_err_counter) + 16'd1);
            end
        end
    end

    // 5. Tiến trình quét tuần tra bộ nhớ (Patrol Scanner): Khi được cấp phép, scrub_pending hạ xuống
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(cfg_enable && scrub_pending && i_scrub_grant)) begin
                assert (!scrub_pending);
            end
        end
    end

    // 6. SOTA ECCfail Miscorrection Trap Invariant
    always_comb begin
        if (rst_n && i_data_valid) begin
            if (is_miscorrect) begin
                assert (o_ecc_miscorrect_alert);
                assert (o_chipkill_fallback_req);
            end
        end
    end

    // 7. ZEM CAM Lookup Invariant (Le Minh Son et al.)
    // Khi toa do tra cuu khop voi entry hop le trong CAM, o_zem_hit phai assert va bit mat na tuong ung phai duoc set
    always_comb begin
        if (rst_n && i_zem_lookup_valid) begin
            for (int k = 0; k < ZEM_ENTRIES; k++) begin
                if (zem_valid[k] && zem_active[k] &&
                    (zem_bg[k]   == i_zem_lookup_bg) &&
                    (zem_bank[k] == i_zem_lookup_bank) &&
                    (zem_row[k]  == i_zem_lookup_row) &&
                    (zem_col[k]  == i_zem_lookup_col)) begin
                    assert (o_zem_hit);
                    assert (o_zem_mask[zem_bit[k]]);
                end
            end
        end
    end

    // Cover properties
    always_ff @(posedge clk) begin
        cover (o_single_err);
        cover (o_double_err);
        cover (o_ecc_miscorrect_alert);
        cover (o_single_err && o_corrected_data == i_raw_data);
        cover (o_chipkill_fallback_req);
        cover (o_scrub_req);
        cover (patrol_row > '0);
        cover (o_zem_hit);
    end
`endif

endmodule
