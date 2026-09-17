//=============================================================================
// Project:     Q-Shield Secure & Resilient DDR5/DDR4 Memory Controller
// File:        ecc_scrubber.sv
// Description: Background Patrol Memory Scrubber with Hamming SEC-DED.
//              - Periodically requests memory scrubbing cycles during slack time.
//              - Implements 64-bit data + 8-bit ECC Hamming SEC-DED codeword.
//              - Single-bit error correction in real-time.
//              - Double-bit Silent Data Corruption (SDC) detection & reporting.
//              - Maintains diagnostic error counters and telemetry registers.
// Standards:   IEEE Transactions on VLSI / Reliability Standards.
//=============================================================================

`timescale 1ns / 1ps

module ecc_scrubber #(
    parameter int DATA_WIDTH     = 64,
    parameter int ECC_WIDTH      = 8,   // 72-bit SEC-DED codeword
    parameter int BG_COUNT       = 8,
    parameter int BG_WIDTH       = $clog2(BG_COUNT),
    parameter int BANK_COUNT     = 4,
    parameter int BANK_WIDTH     = $clog2(BANK_COUNT),
    parameter int ROW_WIDTH      = 17,
    parameter int DEFAULT_INTERVAL = 1000
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
    output logic [15:0]                                  o_double_err_cnt
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
                default: ;
            endcase
        end
    end

    //=========================================================================
    // SEC-DED Syndrome & Parity Matrix (Standard 64-bit data + 8-bit ECC)
    // Parity bits P[0..6] check Hamming code subsets, P[7] is overall parity.
    //=========================================================================
    // Hamming syndrome parity equations using folded XOR trees
    logic overall_parity;
    logic [6:0] syn;
    logic syn_zero;

    assign overall_parity = (^effective_data) ^ (^effective_ecc);
    assign syn_zero       = (syn == 7'd0);

    always_comb begin
        syn[0] = effective_ecc[0] ^ ^(effective_data & 64'h5555_5555_5555_5555);
        syn[1] = effective_ecc[1] ^ ^(effective_data & 64'h6666_6666_6666_6666);
        syn[2] = effective_ecc[2] ^ ^(effective_data & 64'h7878_7878_7878_7878);
        syn[3] = effective_ecc[3] ^ ^(effective_data & 64'h7F80_7F80_7F80_7F80);
        syn[4] = effective_ecc[4] ^ ^(effective_data & 64'h7FFF_8000_7FFF_8000);
        syn[5] = effective_ecc[5] ^ ^(effective_data & 64'h7FFF_FFFF_8000_0000);
        syn[6] = effective_ecc[6] ^ ^(effective_data & 64'h8000_0000_0000_0000);
    end

    // SEC-DED Classification:
    // syn == 0 and overall parity == 0 -> No Error
    // syn != 0 and overall parity == 1 -> Single-Bit Error (Correctable)
    // syn != 0 and overall parity == 0 -> Double-Bit Error (SDC Alert)
    wire is_single_err = !syn_zero && overall_parity;
    wire is_double_err = !syn_zero && !overall_parity;

    // Single-bit correction mask
    logic [DATA_WIDTH-1:0] bit_correction_mask;
    always_comb begin
        bit_correction_mask = '0;
        if (is_single_err && (syn > 7'd0) && (syn <= 7'd64)) begin
            bit_correction_mask[6'(syn - 1'b1)] = 1'b1;
        end
    end

    // Corrected data
    assign o_corrected_valid = i_data_valid;
    assign o_corrected_data  = i_raw_data ^ bit_correction_mask;
    assign o_single_err      = i_data_valid && is_single_err;
    assign o_double_err      = i_data_valid && is_double_err;

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

    assign o_single_err_cnt = single_err_counter;
    assign o_double_err_cnt = double_err_counter;

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
                end
            end else begin
                scrub_pending <= 1'b0;
                interval_cnt  <= '0;
            end
        end
    end

endmodule
