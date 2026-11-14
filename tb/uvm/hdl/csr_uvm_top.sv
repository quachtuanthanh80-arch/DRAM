// File: csr_uvm_top.sv
// Chức năng: Khối bọc HDL cho môi trường pyuvm kiểm chứng apb_csr_regs và TMR bằng bộ bơm lỗi $deposit.
`timescale 1ns / 1ps

module csr_uvm_top;
    localparam int AddrWidth = 12;
    localparam int DataWidth = 32;

    logic                 pclk = 1'b0;
    logic                 presetn = 1'b0;
    logic [AddrWidth-1:0] paddr = '0;
    logic                 psel = 1'b0;
    logic                 penable = 1'b0;
    logic                 pwrite = 1'b0;
    logic [DataWidth-1:0] pwdata = '0;
    logic [3:0]           pstrb = 4'hF;
    logic [2:0]           pprot = 3'b000;
    logic                 pready;
    logic [DataWidth-1:0] prdata;
    logic                 pslverr;

    logic                 enc_enable;
    logic                 soft_reset;
    logic                 perf_cnt_en;
    logic                 auto_tweak_en;
    logic                 sec_locked;
    logic [255:0]         key1_data;
    logic [255:0]         key2_data;
    logic                 keys_valid;

    logic                 pipe_busy = 1'b0;
    logic [7:0]           core_status_flags = '0;
    logic                 block_encrypted_pulse = 1'b0;
    logic                 pipeline_stall_active = 1'b0;

    logic [15:0]          cfg_sdc_thresh;
    logic [15:0]          cfg_window_size;
    logic [15:0]          cfg_scrub_interval;
    logic [15:0]          cfg_rowpress_thresh;
    logic [1:0]           cfg_rowpress_curve;
    logic                 cfg_drm_en;
    logic                 cfg_drm_victim2_en;
    logic                 cfg_ate_en;
    logic [3:0]           cfg_ate_alpha_shift;

    logic                 cfg_scramble_en;
    logic                 cfg_scramble_reseed;
    logic [63:0]          cfg_scramble_seed;
    logic                 cfg_bank_coloring_en;
    logic [1:0]           cfg_mapping_mode;
    logic [1:0]           cfg_crypto_mode;
    logic [1:0]           cfg_ecc_mode;
    logic                 cfg_parity_check_en;
    logic                 cfg_pmu_en;
    logic                 cfg_pmu_reset;

    logic [1:0]           cfg_crypto_profile;
    logic [7:0]           cfg_default_key_id;
    logic [18:0]          cfg_epoch_nonce;
    logic [4:0]           sec_fault_status;
    logic                 sec_fault_irq;
    logic [4:0]           i_sec_fault_set = '0;
    logic [31:0]          i_fault_addr_log = '0;
    logic                 o_tmr_alert;
    logic                 o_glitch_alert;

    logic [31:0]          telem_accesses = '0;
    logic [31:0]          telem_throttles = '0;
    logic [15:0]          ecc_single_err_cnt = '0;
    logic [15:0]          ecc_double_err_cnt = '0;
    logic [15:0]          rowpress_alert_cnt = '0;
    logic [15:0]          ate_dynamic_thresh = '0;
    logic [7:0][31:0]     pmu_counters = '0;

    apb_csr_regs dut (
        .pclk                  (pclk),
        .presetn               (presetn),
        .paddr                 (paddr),
        .psel                  (psel),
        .penable               (penable),
        .pwrite                (pwrite),
        .pwdata                (pwdata),
        .pstrb                 (pstrb),
        .pprot                 (pprot),
        .pready                (pready),
        .prdata                (prdata),
        .pslverr               (pslverr),
        .enc_enable            (enc_enable),
        .soft_reset            (soft_reset),
        .perf_cnt_en           (perf_cnt_en),
        .auto_tweak_en         (auto_tweak_en),
        .sec_locked            (sec_locked),
        .key1_data             (key1_data),
        .key2_data             (key2_data),
        .keys_valid            (keys_valid),
        .pipe_busy             (pipe_busy),
        .core_status_flags     (core_status_flags),
        .block_encrypted_pulse (block_encrypted_pulse),
        .pipeline_stall_active (pipeline_stall_active),
        .cfg_sdc_thresh        (cfg_sdc_thresh),
        .cfg_window_size       (cfg_window_size),
        .cfg_scrub_interval    (cfg_scrub_interval),
        .cfg_rowpress_thresh   (cfg_rowpress_thresh),
        .cfg_rowpress_curve    (cfg_rowpress_curve),
        .cfg_drm_en            (cfg_drm_en),
        .cfg_drm_victim2_en    (cfg_drm_victim2_en),
        .cfg_ate_en            (cfg_ate_en),
        .cfg_ate_alpha_shift   (cfg_ate_alpha_shift),
        .cfg_scramble_en       (cfg_scramble_en),
        .cfg_scramble_reseed   (cfg_scramble_reseed),
        .cfg_scramble_seed     (cfg_scramble_seed),
        .cfg_bank_coloring_en  (cfg_bank_coloring_en),
        .cfg_mapping_mode      (cfg_mapping_mode),
        .cfg_crypto_mode       (cfg_crypto_mode),
        .cfg_ecc_mode          (cfg_ecc_mode),
        .cfg_parity_check_en   (cfg_parity_check_en),
        .cfg_pmu_en            (cfg_pmu_en),
        .cfg_pmu_reset         (cfg_pmu_reset),
        .cfg_crypto_profile    (cfg_crypto_profile),
        .cfg_default_key_id    (cfg_default_key_id),
        .cfg_epoch_nonce       (cfg_epoch_nonce),
        .sec_fault_status      (sec_fault_status),
        .sec_fault_irq         (sec_fault_irq),
        .i_sec_fault_set       (i_sec_fault_set),
        .i_fault_addr_log      (i_fault_addr_log),
        .o_tmr_alert           (o_tmr_alert),
        .o_glitch_alert        (o_glitch_alert),
        .telem_accesses        (telem_accesses),
        .telem_throttles       (telem_throttles),
        .ecc_single_err_cnt    (ecc_single_err_cnt),
        .ecc_double_err_cnt    (ecc_double_err_cnt),
        .rowpress_alert_cnt    (rowpress_alert_cnt),
        .ate_dynamic_thresh    (ate_dynamic_thresh),
        .pmu_counters          (pmu_counters)
    );

    // Bộ bơm lỗi TMR qua $deposit cho FaultAgent (0=rail0_sec_locked, 1=rail0_crypto_profile)
    logic       fi_trig = 1'b0;
    logic [1:0] fi_mode = 2'd1;
    logic [2:0] fi_target = 3'd0;
    logic [7:0] fi_val = 8'd1;
    logic       fi_done = 1'b0;

    always @(negedge pclk) begin
        fi_done <= 1'b0;
        if (fi_trig) begin
            case (fi_target)
                3'd0: $deposit(dut.rail0_sec_locked, dut.rail0_sec_locked ^ fi_val[0]);
                default: $deposit(dut.rail0_crypto_profile, dut.rail0_crypto_profile ^ {24'h0, fi_val});
            endcase
            fi_done <= 1'b1;
        end
    end
endmodule
