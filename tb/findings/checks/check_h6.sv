// File: check_h6.sv
// Chức năng: Kiểm tra tái hiện finding H-6 (Đọc ngược AddrScrambleSeed sau khi đã sec_locked).

`timescale 1ns / 1ps

module check_h6;
    `include "tb_check.svh"

    localparam int AddrWidth = 12;
    localparam int DataWidth = 32;

    logic                 pclk = 0;
    always #2 pclk = ~pclk;

    logic                 presetn;
    logic [AddrWidth-1:0] paddr;
    logic                 psel;
    logic                 penable;
    logic                 pwrite;
    logic [DataWidth-1:0] pwdata;
    logic [3:0]           pstrb;
    logic [2:0]           pprot;
    wire                  pready;
    wire  [DataWidth-1:0] prdata;
    wire                  pslverr;

    wire                  sec_locked;

    apb_csr_regs #(
        .AddrWidth(AddrWidth),
        .DataWidth(DataWidth)
    ) dut (
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
        .sec_locked            (sec_locked),
        .key1_data             (),
        .key2_data             (),
        .keys_valid            (),
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
        .telem_accesses        (),
        .telem_throttles       (),
        .ecc_single_err_cnt    (),
        .ecc_double_err_cnt    (),
        .rowpress_alert_cnt    (),
        .ate_dynamic_thresh    (),
        .pmu_counters          (256'd0),
        .abo_alert_cnt         (),
        .ecc_miscorrect_cnt    ()
    );

    task automatic apb_write(
        input logic [AddrWidth-1:0] addr,
        input logic [DataWidth-1:0] data
    );
        @(posedge pclk);
        paddr   <= addr;
        pwrite  <= 1'b1;
        psel    <= 1'b1;
        penable <= 1'b0;
        pwdata  <= data;
        pstrb   <= 4'hF;
        pprot   <= 3'b000;

        @(posedge pclk);
        penable <= 1'b1;

        @(posedge pclk);
        psel    <= 1'b0;
        penable <= 1'b0;
        pwrite  <= 1'b0;
    endtask

    logic [31:0] read_val;
    task automatic apb_read(
        input  logic [AddrWidth-1:0] addr,
        output logic [DataWidth-1:0] data
    );
        @(posedge pclk);
        paddr   <= addr;
        pwrite  <= 1'b0;
        psel    <= 1'b1;
        penable <= 1'b0;
        pstrb   <= 4'h0;
        pprot   <= 3'b000;

        @(posedge pclk);
        penable <= 1'b1;

        @(posedge pclk);
        data    = prdata;
        psel    <= 1'b0;
        penable <= 1'b0;
    endtask

    initial begin
        presetn = 0;
        psel    = 0;
        penable = 0;
        pwrite  = 0;
        paddr   = 0;
        pwdata  = 0;
        pstrb   = 0;
        pprot   = 0;

        #20;
        presetn = 1;
        #10;

        // Khoá bảo mật bằng SecLockMagic (0xA55A0001 tại AddrSecLock 0x008)
        apb_write(12'h008, 32'hA55A_0001);
        #10;

        // Đọc ngược seed xáo trộn AddrScrambleSeedL (0x100) sau khi đã khoá
        apb_read(12'h100, read_val);

        // Check H-6: Sau khi sec_locked, seed bí mật không được phép đọc ngược ra ngoài (phải trả về 0x0)
        tb_check(sec_locked == 1'b1 && read_val == 32'h0, "H-6: AddrScrambleSeedL must return 0 when read after sec_locked");

        tb_report();
        $finish;
    end

endmodule
