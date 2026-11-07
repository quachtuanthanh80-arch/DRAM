// File: tb_key2_entropy.sv
// Chức năng: Kiểm chứng finding M-12: Nửa cao của key2_data lấy reg_key2[4..7] thật, không lặp nửa thấp.

`timescale 1ns / 1ps

module tb_key2_entropy;
    `include "tb_check.svh"

    logic        pclk = 0;
    logic        presetn = 0;
    always #2.5 pclk = ~pclk;

    logic [11:0]  paddr;
    logic         psel;
    logic         penable;
    logic         pwrite;
    logic [31:0]  pwdata;
    logic [3:0]   pstrb;
    logic [2:0]   pprot;
    wire          pready;
    wire  [31:0]  prdata;
    wire          pslverr;

    wire  [255:0] key1_data;
    wire  [255:0] key2_data;
    wire          keys_valid;

    apb_csr_regs #(
        .AddrWidth(12),
        .DataWidth(32)
    ) u_csr (
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
        .enc_enable            (),
        .soft_reset            (),
        .perf_cnt_en           (),
        .auto_tweak_en         (),
        .sec_locked            (),
        .key1_data             (key1_data),
        .key2_data             (key2_data),
        .keys_valid            (keys_valid),
        .pipe_busy             (1'b0),
        .core_status_flags     (8'h0),
        .block_encrypted_pulse (1'b0),
        .pipeline_stall_active (1'b0),
        .cfg_sdc_thresh        (),
        .cfg_window_size       (),
        .cfg_scrub_interval    (),
        .cfg_rowpress_thresh   (),
        .cfg_rowpress_curve    (),
        .cfg_drm_en            (),
        .cfg_drm_victim2_en    (),
        .cfg_ate_en            (),
        .cfg_ate_alpha_shift   (),
        .cfg_scramble_en       (),
        .cfg_scramble_reseed   (),
        .cfg_scramble_seed     (),
        .cfg_bank_coloring_en  (),
        .cfg_mapping_mode      (),
        .cfg_crypto_mode       (),
        .cfg_ecc_mode          (),
        .cfg_pmu_en            (),
        .cfg_pmu_reset         (),
        .cfg_crypto_profile    (),
        .cfg_default_key_id    (),
        .cfg_epoch_nonce       (),
        .sec_fault_status      (),
        .sec_fault_irq         (),
        .i_sec_fault_set       (5'b0),
        .i_fault_addr_log      (32'h0),
        .o_tmr_alert           (),
        .o_glitch_alert        (),
        .telem_accesses        (32'h0),
        .telem_throttles       (32'h0),
        .ecc_single_err_cnt    (16'h0),
        .ecc_double_err_cnt    (16'h0),
        .rowpress_alert_cnt    (16'h0),
        .ate_dynamic_thresh    (16'h0),
        .pmu_counters          ('0)
    );

    initial begin
        paddr   = '0;
        psel    = 0;
        penable = 0;
        pwrite  = 0;
        pwdata  = '0;
        pstrb   = 4'hF;
        pprot   = 3'b000;

        #20;
        presetn = 1;
        #10;

        // Tải reg_key2[0..3] qua APB (0x030..0x03C)
        @(posedge pclk);
        for (int i = 0; i < 4; i++) begin
            paddr   <= 12'h030 + (i * 4);
            pwrite  <= 1'b1;
            psel    <= 1'b1;
            penable <= 1'b0;
            pwdata  <= 32'hA000_0000 + i;
            @(posedge pclk);
            penable <= 1'b1;
            @(posedge pclk);
            psel    <= 1'b0;
            penable <= 1'b0;
            pwrite  <= 1'b0;
        end

        // Cấp giá trị khác nhau cho reg_key2[4..7] qua backdoor phân cấp
        @(posedge pclk);
        u_csr.reg_key2[4] = 32'hB000_0004;
        u_csr.reg_key2[5] = 32'hB000_0005;
        u_csr.reg_key2[6] = 32'hB000_0006;
        u_csr.reg_key2[7] = 32'hB000_0007;

        #1;
        // Check 1: Nửa cao (bits [255:128]) phải bằng {reg_key2[4], reg_key2[5], reg_key2[6], reg_key2[7]}
        tb_check(key2_data[255:128] == {32'hB000_0004, 32'hB000_0005, 32'hB000_0006, 32'hB000_0007},
                 "M-12: key2_data upper half reflects reg_key2[4..7]");

        // Check 2: Nửa thấp (bits [127:0]) phải bằng {reg_key2[0], reg_key2[1], reg_key2[2], reg_key2[3]}
        tb_check(key2_data[127:0] == {32'hA000_0000, 32'hA000_0001, 32'hA000_0002, 32'hA000_0003},
                 "M-12: key2_data lower half reflects reg_key2[0..3]");

        // Check 3: Nửa cao và nửa thấp PHẢI KHÁC NHAU (không bị lặp lại như lỗi M-12 cũ)
        tb_check(key2_data[255:128] != key2_data[127:0],
                 "M-12: key2_data upper half is distinct from lower half (256-bit entropy)");

        tb_report();
        $finish;
    end

endmodule
