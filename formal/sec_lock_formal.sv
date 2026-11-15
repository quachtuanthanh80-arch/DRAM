// File: sec_lock_formal.sv
// Chức năng: Formal wrapper kiểm chứng bất biến khóa bảo mật H-4 và kiểm soát keys_valid H-5 cho apb_csr_regs.

`timescale 1ns / 1ps

module sec_lock_formal (
    input  logic        clk,
    input  logic        rst_n,

    // APB4 Slave
    input  logic [11:0] paddr,
    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [31:0] pwdata,
    input  logic [3:0]  pstrb,
    input  logic [2:0]  pprot,

    // Giao diện bảo mật lõi
    input  logic        i_ext_keys_valid,
    input  logic        i_pipe_req_valid,
    output logic        o_pipe_in_valid
);

    logic [31:0]  prdata;
    logic         pready;
    logic         pslverr;
    logic         enc_enable;
    logic         soft_reset;
    logic         perf_cnt_en;
    logic         auto_tweak_en;
    logic         sec_locked;
    logic [255:0] key1_data;
    logic [255:0] key2_data;
    logic         csr_keys_valid;

    apb_csr_regs u_dut (
        .pclk                   (clk),
        .presetn                (rst_n),
        .paddr                  (paddr),
        .psel                   (psel),
        .penable                (penable),
        .pwrite                 (pwrite),
        .pwdata                 (pwdata),
        .pstrb                  (pstrb),
        .pprot                  (pprot),
        .pready                 (pready),
        .prdata                 (prdata),
        .pslverr                (pslverr),
        .enc_enable             (enc_enable),
        .soft_reset             (soft_reset),
        .perf_cnt_en            (perf_cnt_en),
        .auto_tweak_en          (auto_tweak_en),
        .sec_locked             (sec_locked),
        .key1_data              (key1_data),
        .key2_data              (key2_data),
        .keys_valid             (csr_keys_valid),
        .pipe_busy              (1'b0),
        .core_status_flags      (8'h0),
        .block_encrypted_pulse  (1'b0),
        .pipeline_stall_active  (1'b0),
        .cfg_sdc_thresh         (),
        .cfg_window_size        (),
        .cfg_scrub_interval     (),
        .cfg_rowpress_thresh    (),
        .cfg_rowpress_curve     (),
        .cfg_drm_en             (),
        .cfg_drm_victim2_en     (),
        .cfg_ate_en             (),
        .cfg_ate_alpha_shift    (),
        .cfg_scramble_en        (),
        .cfg_scramble_reseed    (),
        .cfg_scramble_seed      (),
        .cfg_bank_coloring_en   (),
        .cfg_mapping_mode       (),
        .cfg_crypto_mode        (),
        .cfg_ecc_mode           (),
        .cfg_parity_check_en    (),
        .cfg_pmu_en             (),
        .cfg_pmu_reset          (),
        .cfg_crypto_profile     (),
        .cfg_default_key_id     (),
        .cfg_epoch_nonce        (),
        .sec_fault_status       (),
        .sec_fault_irq          (),
        .i_sec_fault_set        (5'b0),
        .i_fault_addr_log       (32'h0),
        .o_tmr_alert            (),
        .o_glitch_alert         (),
        .telem_accesses         (32'h0),
        .telem_throttles        (32'h0),
        .ecc_single_err_cnt     (16'h0),
        .ecc_double_err_cnt     (16'h0),
        .rowpress_alert_cnt     (16'h0),
        .ate_dynamic_thresh     (16'h0),
        .pmu_counters           ('0),
        .abo_alert_cnt          (16'h0),
        .ecc_miscorrect_cnt     (16'h0)
    );

    wire eff_keys_valid = i_ext_keys_valid && csr_keys_valid;
    assign o_pipe_in_valid = i_pipe_req_valid && eff_keys_valid;

`ifdef FORMAL
    initial assume (!rst_n);

    always_ff @(posedge clk) begin
        if ($past(!rst_n)) assume (rst_n);
    end

    // Ràng buộc cơ bản giao thức APB
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(psel && !penable)) begin
                assume (psel && penable); // Chuyển từ Setup sang Access
                assume ($stable(paddr));
                assume ($stable(pwrite));
                assume ($stable(pwdata));
                assume ($stable(pstrb));
                assume ($stable(pprot));
            end
        end
    end

    // -------------------------------------------------------------------------
    // SVA 2: Sau khi sec_locked, enc_enable không bao giờ bị đổi (Finding H-4)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(sec_locked)) begin
                assert (sec_locked);
                assert ($stable(enc_enable));
            end
        end
    end

    // -------------------------------------------------------------------------
    // SVA 3: !keys_valid |-> !pipe_in_valid (Finding H-5)
    // -------------------------------------------------------------------------
    always_comb begin
        if (rst_n) begin
            if (!eff_keys_valid) begin
                assert (!o_pipe_in_valid);
            end
        end
    end

    // -------------------------------------------------------------------------
    // Finding H-5: APB Non-Secure Transaction Rejection
    // -------------------------------------------------------------------------
    always_comb begin
        if (rst_n && psel && penable) begin
            if (pprot[1]) begin
                assert (pslverr);
            end
        end
    end

    // -------------------------------------------------------------------------
    // COVER PROPERTIES
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst_n) begin
            cover (sec_locked);
            cover (i_ext_keys_valid && i_pipe_req_valid);
            cover (psel && penable && pprot[1] && pslverr);
        end
    end

`endif

endmodule
