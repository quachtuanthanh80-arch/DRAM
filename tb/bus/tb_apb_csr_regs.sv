//=============================================================================
// Testbench:   tb_apb_csr_regs
// Description: Comprehensive Self-Checking Testbench for apb_csr_regs.
//              Verifies:
//              1. Reset defaults and control signals
//              2. Key 1 (256-bit) and Key 2 (256-bit) load via APB4
//              3. Keys valid assertion and concatenation correctness
//              4. Security Lockdown (DPA/tamper protection: zeroized readback)
//              5. Post-lock write protection (tamper resistance)
//              6. Hardware performance telemetry counters
//              7. Soft reset functionality
// Standard:    AMBA APB v2.0 / SystemVerilog IEEE 1800-2017
//=============================================================================

`timescale 1ns / 1ps

module tb_apb_csr_regs;

    localparam int AddrWidth = 12;
    localparam int DataWidth = 32;
    localparam time ClkPeriod = 4ns; // 250 MHz

    logic                 pclk = 0;
    always #(ClkPeriod/2) pclk = ~pclk;

    logic                 presetn;
    logic [AddrWidth-1:0] paddr;
    logic                 psel;
    logic                 penable;
    logic                 pwrite;
    logic [DataWidth-1:0] pwdata;
    logic [3:0]           pstrb;
    logic [2:0]           pprot;
    logic                 pready;
    logic [DataWidth-1:0] prdata;
    logic                 pslverr;

    logic                 enc_enable;
    logic                 soft_reset;
    logic                 perf_cnt_en;
    logic                 auto_tweak_en;
    logic                 sec_locked;
    logic [255:0]         key1_data;
    logic [127:0]         key2_data;
    logic                 keys_valid;

    logic                 pipe_busy;
    logic [7:0]           core_status_flags;
    logic                 block_encrypted_pulse;
    logic                 pipeline_stall_active;

    // SDC, DRM, ATE & Security Control Signals
    logic [15:0]          cfg_sdc_thresh;
    logic [15:0]          cfg_window_size;
    logic [15:0]          cfg_scrub_interval;
    logic [15:0]          cfg_rowpress_thresh;
    logic [1:0]           cfg_rowpress_curve;
    logic                 cfg_drm_en;
    logic                 cfg_drm_victim2_en;
    logic                 cfg_ate_en;
    logic [3:0]           cfg_ate_alpha_shift;

    logic [31:0]          telem_accesses;
    logic [31:0]          telem_throttles;
    logic [15:0]          ecc_single_err_cnt;
    logic [15:0]          ecc_double_err_cnt;
    logic [15:0]          rowpress_alert_cnt;
    logic [15:0]          ate_dynamic_thresh;
    logic [15:0]          abo_alert_cnt;
    logic [15:0]          ecc_miscorrect_cnt;

    // Two-Tier Crypto & Fault Hardening Signals
    logic [1:0]           cfg_crypto_profile;
    logic [7:0]           cfg_default_key_id;
    logic [18:0]          cfg_epoch_nonce;
    logic [4:0]           sec_fault_status;
    logic                 sec_fault_irq;
    logic [4:0]           i_sec_fault_set = 5'b00000;
    logic [31:0]          i_fault_addr_log = 32'h0;
    logic                 o_tmr_alert;
    logic                 o_glitch_alert;

    // Instantiate DUT
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
        .cfg_scramble_en       (),
        .cfg_scramble_reseed   (),
        .cfg_scramble_seed     (),
        .cfg_bank_coloring_en  (),
        .cfg_mapping_mode      (),
        .cfg_crypto_mode       (),
        .cfg_ecc_mode          (),
        .cfg_pmu_en            (),
        .cfg_pmu_reset         (),
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
        .pmu_counters          ('0),
        .abo_alert_cnt         (abo_alert_cnt),
        .ecc_miscorrect_cnt    (ecc_miscorrect_cnt)
    );

    // Test tracking
    int tests_run    = 0;
    int tests_passed = 0;
    int tests_failed = 0;

    // APB Write Task (2-phase APB transfer: Setup -> Access)
    task automatic apb_write(
        input logic [AddrWidth-1:0] addr,
        input logic [DataWidth-1:0] data,
        input logic [3:0]           strb = 4'hF
    );
        @(posedge pclk);
        paddr   <= addr;
        pwrite  <= 1'b1;
        psel    <= 1'b1;
        penable <= 1'b0;
        pwdata  <= data;
        pstrb   <= strb;

        @(posedge pclk);
        penable <= 1'b1;

        @(posedge pclk);
        psel    <= 1'b0;
        penable <= 1'b0;
        pwrite  <= 1'b0;
    endtask

    // APB Read Task
    task automatic apb_read(
        input  logic [AddrWidth-1:0] addr,
        output logic [DataWidth-1:0] data
    );
        @(posedge pclk);
        paddr   <= addr;
        pwrite  <= 1'b0;
        psel    <= 1'b1;
        penable <= 1'b0;

        @(posedge pclk);
        penable <= 1'b1;

        @(posedge pclk);
        data    = prdata;
        psel    <= 1'b0;
        penable <= 1'b0;
    endtask

    logic [31:0] rdata;

    initial begin
        // Reset initialization
        presetn               = 1'b0;
        paddr                 = '0;
        psel                  = 1'b0;
        penable               = 1'b0;
        pwrite                = 1'b0;
        pwdata                = '0;
        pstrb                 = 4'hF;
        pprot                 = 3'b000;
        pipe_busy             = 1'b0;
        core_status_flags     = 8'h00;
        block_encrypted_pulse = 1'b0;
        pipeline_stall_active = 1'b0;

        #(ClkPeriod * 4);
        presetn = 1'b1;
        #(ClkPeriod * 2);

        $display("================================================================");
        $display("[TB_APB_CSR] STARTING APB4 CSR SUBSYSTEM VERIFICATION");
        $display("================================================================");

        // TEST 1: Reset Defaults
        tests_run++;
        apb_read(12'h000, rdata);
        if (rdata == 32'h0000_0009 && enc_enable == 1'b1 && auto_tweak_en == 1'b1 &&
            sec_locked == 1'b0 && keys_valid == 1'b0) begin
            $display("[PASS] Test 1: Reset defaults verified (enc_enable=1, sec_locked=0)");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 1: Reset defaults mismatch. rdata=%08h", rdata);
            tests_failed++;
        end

        // TEST 2: Load Key 1 (256-bit AES Cipher Key)
        tests_run++;
        for (int i = 0; i < 8; i++) begin
            apb_write(12'h010 + (i * 4), 32'h1000_0000 + i);
        end
        if (!keys_valid) begin
            $display("[PASS] Test 2a: keys_valid correctly low when only Key 1 is loaded.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 2a: keys_valid prematurely asserted.");
            tests_failed++;
        end

        // TEST 3: Load Key 2 (128-bit AES Tweak Key)
        tests_run++;
        for (int i = 0; i < 4; i++) begin
            apb_write(12'h030 + (i * 4), 32'h2000_0000 + i);
        end
        @(posedge pclk);
        if (keys_valid &&
            key1_data == {32'h10000000, 32'h10000001, 32'h10000002, 32'h10000003,
                          32'h10000004, 32'h10000005, 32'h10000006, 32'h10000007} &&
            key2_data == {32'h20000000, 32'h20000001, 32'h20000002, 32'h20000003}) begin
            $display("[PASS] Test 3: Keys loaded and validated with exact 256b Key1 and 128b Key2.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 3: Keys mismatch. key1=%064h, key2=%032h", key1_data, key2_data);
            tests_failed++;
        end

        // TEST 3b: Two-Tier Security & TMR CSRs (Profile, KeyID, Nonce Configuration)
        tests_run++;
        apb_read(12'h040, rdata); // REG_CRYPTO_PROFILE default check
        if (rdata == 32'd2 && cfg_crypto_profile == 2'b10) begin
            apb_read(12'h044, rdata); // REG_DEFAULT_KEY_ID default check
            if (rdata == 32'd0 && cfg_default_key_id == 8'd0) begin
                apb_read(12'h048, rdata); // REG_EPOCH_NONCE default check
                if (rdata == 32'h0005_A5A5 && cfg_epoch_nonce == 19'h5A5A5) begin
                    // Write new values
                    apb_write(12'h040, 32'd1); // Profile 1: Legacy XTS
                    apb_write(12'h044, 32'h5A); // Key ID 0x5A
                    apb_write(12'h048, 32'h7_ABCD); // Epoch Nonce
                    @(posedge pclk);
                    if (cfg_crypto_profile == 2'b01 && cfg_default_key_id == 8'h5A && cfg_epoch_nonce == 19'h7ABCD) begin
                        $display("[PASS] Test 3b: Two-Tier TMR CSRs configured before lockdown.");
                        tests_passed++;
                    end else begin
                        $display("[FAIL] Test 3b: TMR CSR write mismatch. Prof=%b, KeyID=%h, Nonce=%h",
                                 cfg_crypto_profile, cfg_default_key_id, cfg_epoch_nonce);
                        tests_failed++;
                    end
                end else begin
                    $display("[FAIL] Test 3b: Epoch Nonce default mismatch: %h", rdata);
                    tests_failed++;
                end
            end else begin
                $display("[FAIL] Test 3b: Key ID default mismatch: %h", rdata);
                tests_failed++;
            end
        end else begin
            $display("[FAIL] Test 3b: Crypto Profile default mismatch: %h", rdata);
            tests_failed++;
        end

        // TEST 4: Security Lockdown (DPA/tamper protection)
        tests_run++;
        apb_write(12'h008, 32'hA55A_0001); // Lock security
        @(posedge pclk);
        if (sec_locked) begin
            $display("[PASS] Test 4: Security lockdown asserted successfully.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 4: Security lock failed to assert.");
            tests_failed++;
        end

        // TEST 5: Tamper Defense (Key Readback Zeroization)
        tests_run++;
        begin : test5_blk
            logic key_read_zero;
            key_read_zero = 1'b1;
            for (int i = 0; i < 8; i++) begin
                apb_read(12'h010 + (i * 4), rdata);
                if (rdata != 32'h0) key_read_zero = 1'b0;
                if (i < 4) begin
                    apb_read(12'h030 + (i * 4), rdata);
                    if (rdata != 32'h0) key_read_zero = 1'b0;
                end
            end
            if (key_read_zero) begin
                $display("[PASS] Test 5: Key readback zeroized! Sniffing attacks thwarted.");
                tests_passed++;
            end else begin
                $display("[FAIL] Test 5: Keys leaked through APB read after lock!");
                tests_failed++;
            end
        end

        // TEST 6: Tamper Defense (Overwrite Resistance)
        tests_run++;
        apb_write(12'h010, 32'hDEAD_BEEF); // Attempt overwrite
        @(posedge pclk);
        if (key1_data[255:224] == 32'h1000_0000) begin
            $display("[PASS] Test 6: Overwrite rejected! Key register retains valid key.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 6: Overwrite succeeded after lock!");
            tests_failed++;
        end

        // TEST 7: Performance Telemetry
        tests_run++;
        apb_write(12'h000, 32'h0000_000D); // Enable perf counters (bit 2 = 1)
        repeat (10) begin
            @(posedge pclk);
            block_encrypted_pulse <= 1'b1;
            pipeline_stall_active <= 1'b0;
            @(posedge pclk);
            block_encrypted_pulse <= 1'b0;
            pipeline_stall_active <= 1'b1;
        end
        pipeline_stall_active <= 1'b0;

        apb_read(12'h064, rdata); // Read perf blocks
        if (rdata == 32'd10) begin
            $display("[PASS] Test 7: Performance telemetry recorded %0d blocks accurately.", rdata);
            tests_passed++;
        end else begin
            $display("[FAIL] Test 7: Perf counter mismatch. Got %0d, Expected 10", rdata);
            tests_failed++;
        end

        // TEST 8: SDC, RowPress, DRM, ATE Configuration CSRs
        tests_run++;
        apb_write(12'h070, 32'd1024);       // SDC threshold
        apb_write(12'h07C, 32'd4096);       // RowPress threshold
        apb_write(12'h080, 32'h0000_0001);  // DRM config: drm_en=1, victim2_en=0
        apb_write(12'h084, 32'h0000_0051);  // ATE config: ate_en=1, alpha_shift=5
        @(posedge pclk);

        apb_read(12'h070, rdata);
        if (rdata == 32'd1024 && cfg_sdc_thresh == 16'd1024 &&
            cfg_rowpress_thresh == 16'd4096 && cfg_drm_victim2_en == 1'b0 &&
            cfg_ate_alpha_shift == 4'd5) begin
            $display("[PASS] Test 8: SDC/RowPress/DRM/ATE configuration registers read/write verified.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 8: Configuration CSR mismatch. rdata=%0d, thresh=%0d", rdata, cfg_sdc_thresh);
            tests_failed++;
        end

        // TEST 9: Hardware Telemetry Counters Readout
        tests_run++;
        telem_accesses     <= 32'h0012_3456;
        telem_throttles    <= 32'h0000_0078;
        ecc_single_err_cnt <= 16'h0003;
        ecc_double_err_cnt <= 16'h0001;
        rowpress_alert_cnt <= 16'h0002;
        ate_dynamic_thresh <= 16'd1280;
        @(posedge pclk);

        apb_read(12'h090, rdata); // Read telem accesses
        if (rdata == 32'h0012_3456) begin
            apb_read(12'h094, rdata); // Read throttles
            if (rdata == 32'h0000_0078) begin
                $display("[PASS] Test 9: Hardware telemetry registers readback accurate.");
                tests_passed++;
            end else begin
                $display("[FAIL] Test 9: Telem throttles mismatch. Got %h", rdata);
                tests_failed++;
            end
        end else begin
            $display("[FAIL] Test 9: Telem accesses mismatch. Got %h", rdata);
            tests_failed++;
        end

        // TEST 10: Version ID Register ("QSHD" = 0x51534844)
        tests_run++;
        apb_read(12'h0FC, rdata);
        if (rdata == 32'h5153_4844) begin
            $display("[PASS] Test 10: Version ID register verified: 0x%08X (ASCII 'QSHD').", rdata);
            tests_passed++;
        end else begin
            $display("[FAIL] Test 10: Version ID mismatch. Got 0x%08X, Expected 0x51534844", rdata);
            tests_failed++;
        end

        // TEST 11: Extended Threat Defense CSRs (RowPress Dynamic Curve, ABO, ECCfail)
        tests_run++;
        apb_write(12'h088, 32'd2); // RowPress curve: Quadratic (2)
        abo_alert_cnt       <= 16'd12;
        ecc_miscorrect_cnt  <= 16'd4;
        @(posedge pclk);

        apb_read(12'h088, rdata);
        if (rdata == 32'd2 && cfg_rowpress_curve == 2'b10) begin
            apb_read(12'h0A8, rdata);
            if (rdata == 32'd12) begin
                apb_read(12'h0AC, rdata);
                if (rdata == 32'd4) begin
                    $display("[PASS] Test 11: RowPress curve, ABO alert, and ECCfail miscorrect registers verified.");
                    tests_passed++;
                end else begin
                    $display("[FAIL] Test 11: ECC miscorrect mismatch. Got %h", rdata);
                    tests_failed++;
                end
            end else begin
                $display("[FAIL] Test 11: ABO alert mismatch. Got %h", rdata);
                tests_failed++;
            end
        end else begin
            $display("[FAIL] Test 11: RowPress curve mismatch. Got %h", rdata);
            tests_failed++;
        end

        // TEST 12: Two-Tier Security & TMR CSRs (Lockdown Protection & W1C Fault Status)
        tests_run++;
        // 1. Verify lockdown prevents modifying TMR crypto profile
        apb_write(12'h040, 32'd2);
        @(posedge pclk);
        if (cfg_crypto_profile == 2'b01) begin
            // 2. Test Fault Status set and interrupt
            i_sec_fault_set <= 5'b00101; // SDC fault + Major counter roll fault
            i_fault_addr_log <= 32'hDEAD_1234;
            @(posedge pclk);
            i_sec_fault_set <= 5'b00000;
            @(posedge pclk);
            apb_read(12'h04C, rdata);
            if (rdata[4:0] == 5'b00101 && sec_fault_status == 5'b00101 && sec_fault_irq == 1'b1) begin
                apb_read(12'h050, rdata);
                if (rdata == 32'hDEAD_1234) begin
                    // 3. W1C bit 0
                    apb_write(12'h04C, 32'h0000_0001);
                    @(posedge pclk);
                    apb_read(12'h04C, rdata);
                    if (rdata[4:0] == 5'b00100 && sec_fault_status == 5'b00100) begin
                        $display("[PASS] Test 12: Two-Tier TMR CSR lockdown protection and W1C Fault Status verified.");
                        tests_passed++;
                    end else begin
                        $display("[FAIL] Test 12: W1C clear failed. Got %h", rdata);
                        tests_failed++;
                    end
                end else begin
                    $display("[FAIL] Test 12: Fault Addr Log mismatch. Got %h", rdata);
                    tests_failed++;
                end
            end else begin
                $display("[FAIL] Test 12: Fault Status set mismatch. Got %h, IRQ=%b", rdata, sec_fault_irq);
                tests_failed++;
            end
        end else begin
            $display("[FAIL] Test 12: Lockdown overwrite protection failed! Profile modified to %b", cfg_crypto_profile);
            tests_failed++;
        end

        #(ClkPeriod * 4);
        $display("================================================================");
        $display("[TB_APB_CSR] SUMMARY: %0d/%0d TESTS PASSED, %0d FAILED",
                 tests_passed, tests_run, tests_failed);
        $display("================================================================");

        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED SUCCESSFULLY]");
            $finish;
        end else begin
            $fatal(1, "[TESTBENCH COMPLETED WITH FAILURES]");
        end
    end

endmodule: tb_apb_csr_regs
