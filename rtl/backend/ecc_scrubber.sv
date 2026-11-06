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
    // Địa chỉ của beat đang kiểm (ZEM ghi đúng hàng có lỗi, không phải toạ độ patrol)
    input  logic [BG_WIDTH-1:0]                          i_data_bg   = '0,
    input  logic [BANK_WIDTH-1:0]                        i_data_bank = '0,
    input  logic [ROW_WIDTH-1:0]                         i_data_row  = '0,

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
    // Giải mã SEC-DED (72,64) thật (secded_72_64_pkg). Ma trận cũ không phải mã Hamming: sửa bit syn-1 với
    // mặt nạ kiểu chẵn lẻ vị trí cho dữ liệu không đặt ở vị trí Hamming nên đảo nhầm bit, và cổng ECC ở top
    // được nối 8'h00 nên mọi lần đọc đều "có lỗi" (R30).
    //=========================================================================
    localparam int LANES = DATA_WIDTH / 64;
    localparam int CBW   = $clog2(DATA_WIDTH);
    logic [7:0]            syn;
    logic [DATA_WIDTH-1:0] bit_correction_mask;
    logic                  is_single_err, is_double_err, is_miscorrect;

    always_comb begin
        logic ce_any;
        ce_any        = 1'b0;
        is_double_err = 1'b0;
        is_miscorrect = 1'b0;
        syn           = '0;
        for (int l = 0; l < LANES; l++) begin
            logic [7:0] s;
            s = secded_72_64_pkg::secded72_syndrome(effective_data[l*64 +: 64], effective_ecc[l*8 +: 8]);
            bit_correction_mask[l*64 +: 64] = secded_72_64_pkg::secded72_flip(s);
            ce_any        = ce_any | secded_72_64_pkg::secded72_ce(s);
            // Lỗi lẻ ở vị trí Hamming không tồn tại: >=3 bit giả dạng lỗi đơn (ECCfail), không được sửa
            is_miscorrect = is_miscorrect | (s[7] && !secded_72_64_pkg::secded72_ce(s));
            is_double_err = is_double_err | ((s != 8'h00) && !s[7]);
            syn           = syn | s;
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

    // Vị trí bit dữ liệu đã sửa (cho ZEM)
    logic [CBW-1:0] corr_bit;
    always_comb begin
        corr_bit = '0;
        for (int j = 0; j < DATA_WIDTH; j++) if (bit_correction_mask[j]) corr_bit = CBW'(j);
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
    // 16-entry fully associative CAM storing single-bit retention/soft fault coordinates.
    // Enables instant 0-cycle XOR bit correction on read path without stalling for scrub.
    //=========================================================================
    localparam int ZEM_PTR_W = (ZEM_ENTRIES > 1) ? $clog2(ZEM_ENTRIES) : 1;
    logic [ZEM_ENTRIES-1:0]          zem_valid;
    logic [BG_WIDTH-1:0]             zem_bg   [ZEM_ENTRIES];
    logic [BANK_WIDTH-1:0]           zem_bank [ZEM_ENTRIES];
    logic [ROW_WIDTH-1:0]            zem_row  [ZEM_ENTRIES];
    logic [CBW-1:0]                  zem_bit  [ZEM_ENTRIES];
    logic [ZEM_PTR_W-1:0]            zem_alloc_ptr;
    logic [15:0]                     zem_hit_counter;

    assign o_zem_hit_cnt = zem_hit_counter;

    // Combinational 0-cycle lookup match
    always_comb begin
        o_zem_hit  = 1'b0;
        o_zem_mask = '0;
        if (i_zem_lookup_valid) begin
            for (int k = 0; k < ZEM_ENTRIES; k++) begin
                if (zem_valid[k] &&
                    (zem_bg[k]   == i_zem_lookup_bg) &&
                    (zem_bank[k] == i_zem_lookup_bank) &&
                    (zem_row[k]  == i_zem_lookup_row)) begin
                    o_zem_hit = 1'b1;
                    o_zem_mask[zem_bit[k]] = 1'b1;
                end
            end
        end
    end

    // Sequential entry allocation & hit telemetry accumulation
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            zem_valid       <= '0;
            zem_alloc_ptr   <= '0;
            zem_hit_counter <= '0;
            for (int k = 0; k < ZEM_ENTRIES; k++) begin
                zem_bg[k]   <= '0;
                zem_bank[k] <= '0;
                zem_row[k]  <= '0;
                zem_bit[k]  <= '0;
            end
        end else begin
            if (i_zem_lookup_valid && o_zem_hit) begin
                zem_hit_counter <= zem_hit_counter + 1'b1;
            end

            // Record single-bit error into ZEM Cache upon detection
            if (i_data_valid && is_single_err && (|bit_correction_mask)) begin
                logic already_exists;
                already_exists = 1'b0;
                for (int k = 0; k < ZEM_ENTRIES; k++) begin
                    if (zem_valid[k] &&
                        (zem_bg[k]   == i_data_bg) &&
                        (zem_bank[k] == i_data_bank) &&
                        (zem_row[k]  == i_data_row)) begin
                        already_exists = 1'b1;
                        zem_bit[k]    <= corr_bit;
                    end
                end

                if (!already_exists) begin
                    zem_valid[zem_alloc_ptr] <= 1'b1;
                    zem_bg[zem_alloc_ptr]    <= i_data_bg;
                    zem_bank[zem_alloc_ptr]  <= i_data_bank;
                    zem_row[zem_alloc_ptr]   <= i_data_row;
                    zem_bit[zem_alloc_ptr]   <= corr_bit;
                    zem_alloc_ptr            <= zem_alloc_ptr + 1'b1;
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
                if (zem_valid[k] &&
                    (zem_bg[k]   == i_zem_lookup_bg) &&
                    (zem_bank[k] == i_zem_lookup_bank) &&
                    (zem_row[k]  == i_zem_lookup_row)) begin
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
