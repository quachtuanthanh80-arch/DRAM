// File: tb_apb_csr_fault.sv
// Chức năng: Kiểm chứng fault injection lật bit các ray TMR sec_locked và tính bất biến của ngưỡng RowHammer/RowPress sau khóa.

`timescale 1ns / 1ps

module tb_apb_csr_fault;
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

    wire                  enc_enable;
    wire                  soft_reset;
    wire                  sec_locked;
    wire [255:0]          key1_data;
    wire [255:0]          key2_data;
    wire                  keys_valid;
    wire [15:0]           cfg_rowpress_thresh;
    wire [1:0]            cfg_rowpress_curve;
    wire                  o_tmr_alert;
    wire                  o_glitch_alert;

    apb_csr_regs #(
        .AddrWidth(AddrWidth),
        .DataWidth(DataWidth)
    ) u_dut (
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
        .perf_cnt_en           (),
        .auto_tweak_en         (),
        .sec_locked            (sec_locked),
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
        .cfg_rowpress_thresh   (cfg_rowpress_thresh),
        .cfg_rowpress_curve    (cfg_rowpress_curve),
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
        .o_tmr_alert           (o_tmr_alert),
        .o_glitch_alert        (o_glitch_alert),
        .telem_accesses        (32'h0),
        .telem_throttles       (32'h0),
        .ecc_single_err_cnt    (16'h0),
        .ecc_double_err_cnt    (16'h0),
        .rowpress_alert_cnt    (16'h0),
        .ate_dynamic_thresh    (16'h0),
        .pmu_counters          ('0),
        .abo_alert_cnt         (16'h0),
        .ecc_miscorrect_cnt    (16'h0)
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
        #20;

        $display("=== [TEST 1] Cấu hình RowHammer / RowPress trước khi khóa ===");
        apb_write(12'h07C, 32'd2048); // RowPress threshold = 2048
        apb_write(12'h088, 32'd1);    // RowPress curve = 1 (Linear)
        @(posedge pclk);
        tb_check(cfg_rowpress_thresh == 16'd2048 && cfg_rowpress_curve == 2'd1,
                 "Test 1: Cấu hình RowPress trước lock thành công (Thresh=2048, Curve=1)");

        $display("=== [TEST 2] Khóa bảo mật bằng SecLockMagic (0xA55A0001) tại 0x008 ===");
        apb_write(12'h008, 32'hA55A_0001);
        @(posedge pclk);
        tb_check(sec_locked == 1'b1, "Test 2: sec_locked = 1 sau khi ghi SecLockMagic");
        tb_check(o_tmr_alert == 1'b0, "Test 2: Không có cảnh báo TMR alert khi chưa có fault");

        $display("=== [TEST 3] Bơm lỗi lật 1 bit trên Rail 0 của sec_locked ===");
        // Laser fault injection: lật rail0 từ 1 về 0
        @(negedge pclk);
        u_dut.rail0_sec_locked = 1'b0;
        #1;
        tb_check(sec_locked == 1'b1, "Test 3a: sec_locked vẫn giữ 1 khi Rail 0 bị lật về 0 (fail-closed / 2-out-of-3)");
        tb_check(o_tmr_alert == 1'b1, "Test 3b: o_tmr_alert kích hoạt thành công khi phát hiện lệch ray Rail 0");
        @(posedge pclk);
        #1;
        tb_check(sec_locked == 1'b1, "Test 3c: sec_locked vẫn giữ 1 sau auto-healing");
        u_dut.rail0_sec_locked = 1'b1;
        @(posedge pclk);

        $display("=== [TEST 4] Bơm lỗi lật 1 bit trên Rail 1 của sec_locked ===");
        @(negedge pclk);
        u_dut.rail1_sec_locked = 1'b0;
        #1;
        tb_check(sec_locked == 1'b1, "Test 4a: sec_locked vẫn giữ 1 khi Rail 1 bị lật về 0");
        tb_check(o_tmr_alert == 1'b1, "Test 4b: o_tmr_alert kích hoạt thành công khi phát hiện lệch ray Rail 1");
        @(posedge pclk);
        #1;
        tb_check(sec_locked == 1'b1, "Test 4c: sec_locked vẫn giữ 1 sau auto-healing");
        u_dut.rail1_sec_locked = 1'b1;
        @(posedge pclk);

        $display("=== [TEST 5] Bơm lỗi lật 1 bit trên Rail 2 của sec_locked ===");
        @(negedge pclk);
        u_dut.rail2_sec_locked = 1'b0;
        #1;
        tb_check(sec_locked == 1'b1, "Test 5a: sec_locked vẫn giữ 1 khi Rail 2 bị lật về 0");
        tb_check(o_tmr_alert == 1'b1, "Test 5b: o_tmr_alert kích hoạt thành công khi phát hiện lệch ray Rail 2");
        @(posedge pclk);
        #1;
        tb_check(sec_locked == 1'b1, "Test 5c: sec_locked vẫn giữ 1 sau auto-healing");
        u_dut.rail2_sec_locked = 1'b1;
        @(posedge pclk);

        $display("=== [TEST 6] Kiểm tra chống ghi đè ngưỡng RowHammer sau khi khóa ===");
        // Kẻ tấn công cố tình ghi giá trị lớn vào AddrRowPressThresh (0x07C) để làm tê liệt cơ chế phòng vệ
        apb_write(12'h07C, 32'h0000_FFFF);
        @(posedge pclk);
        tb_check(cfg_rowpress_thresh == 16'd2048,
                 "Test 6a: AddrRowPressThresh bị chặn sau sec_locked (retains 2048, không đổi sang 0xFFFF)");

        // Kẻ tấn công cố tình ghi đè AddrRowPressCurve (0x088)
        apb_write(12'h088, 32'h0000_0003);
        @(posedge pclk);
        tb_check(cfg_rowpress_curve == 2'd1,
                 "Test 6b: AddrRowPressCurve bị chặn sau sec_locked (retains 1, không đổi sang 3)");

        tb_report();
        $finish;
    end

endmodule
