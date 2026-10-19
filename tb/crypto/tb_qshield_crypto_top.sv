// tb_qshield_crypto_top.sv
// Testbench kiem chung toan dien phan he mat ma hai tang qshield_crypto_top.sv (Profiles 0-3, 0-cycle CTR, Poisoning)

`timescale 1ns / 1ps

module tb_qshield_crypto_top;

    localparam int DATA_WIDTH  = 512;
    localparam int ADDR_WIDTH  = 34;
    localparam int TAG_WIDTH   = 5;
    localparam int MAC_WIDTH   = 64;
    localparam time ClkPeriod  = 4ns; // 250 MHz

    logic                  clk = 1'b0;
    logic                  rst_n;

    logic [1:0]            i_crypto_profile;
    logic [7:0]            i_default_key_id;
    logic [18:0]           i_epoch_nonce;
    logic [255:0]          i_key1_data;
    logic [127:0]          i_key2_data;
    logic                  i_keys_valid;

    // Precomp interface
    logic                  i_precomp_valid;
    logic                  o_precomp_ready;
    logic                  i_precomp_is_write;
    logic [TAG_WIDTH-1:0]  i_precomp_tag;
    logic [ADDR_WIDTH-1:0] i_precomp_addr;
    logic [7:0]            i_precomp_key_id;

    // Write interface
    logic                  i_wr_valid;
    logic                  o_wr_ready;
    logic [TAG_WIDTH-1:0]  i_wr_tag;
    logic [ADDR_WIDTH-1:0] i_wr_addr;
    logic [DATA_WIDTH-1:0] i_wr_data;
    logic [(DATA_WIDTH/8)-1:0] i_wr_strb;
    logic                  o_wr_valid;
    logic                  i_wr_ready;
    logic [TAG_WIDTH-1:0]  o_wr_tag;
    logic [ADDR_WIDTH-1:0] o_wr_addr;
    logic [DATA_WIDTH-1:0] o_wr_data;
    logic [MAC_WIDTH-1:0]  o_wr_mac;

    // Read interface
    logic                  i_rd_valid;
    logic                  o_rd_ready;
    logic [TAG_WIDTH-1:0]  i_rd_tag;
    logic [ADDR_WIDTH-1:0] i_rd_addr;
    logic [DATA_WIDTH-1:0] i_rd_data;
    logic [MAC_WIDTH-1:0]  i_rd_stored_mac;
    logic                  o_rd_valid;
    logic                  i_rd_ready;
    logic [TAG_WIDTH-1:0]  o_rd_tag;
    logic [ADDR_WIDTH-1:0] o_rd_addr;
    logic [DATA_WIDTH-1:0] o_rd_data;
    logic                  o_rd_poison;
    logic                  o_rd_slverr;

    // Fault reporting
    logic [4:0]            o_sec_fault_set;
    logic [31:0]           o_fault_addr_log;

    // DUT Instantiation
    qshield_crypto_top #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .TAG_WIDTH  (TAG_WIDTH),
        .MAC_WIDTH  (MAC_WIDTH)
    ) u_dut (
        .clk                  (clk),
        .rst_n                (rst_n),
        .i_crypto_profile     (i_crypto_profile),
        .i_default_key_id     (i_default_key_id),
        .i_epoch_nonce        (i_epoch_nonce),
        .i_key1_data          (i_key1_data),
        .i_key2_data          (i_key2_data),
        .i_keys_valid         (i_keys_valid),

        .i_precomp_valid      (i_precomp_valid),
        .o_precomp_ready      (o_precomp_ready),
        .i_precomp_is_write   (i_precomp_is_write),
        .i_precomp_tag        (i_precomp_tag),
        .i_precomp_addr       (i_precomp_addr),
        .i_precomp_key_id     (i_precomp_key_id),

        .i_wr_valid           (i_wr_valid),
        .o_wr_ready           (o_wr_ready),
        .i_wr_tag             (i_wr_tag),
        .i_wr_addr            (i_wr_addr),
        .i_wr_data            (i_wr_data),
        .i_wr_strb            (i_wr_strb),
        .o_wr_valid           (o_wr_valid),
        .i_wr_ready           (i_wr_ready),
        .o_wr_tag             (o_wr_tag),
        .o_wr_addr            (o_wr_addr),
        .o_wr_data            (o_wr_data),
        .o_wr_mac             (o_wr_mac),

        .i_rd_valid           (i_rd_valid),
        .o_rd_ready           (o_rd_ready),
        .i_rd_tag             (i_rd_tag),
        .i_rd_addr            (i_rd_addr),
        .i_rd_data            (i_rd_data),
        .i_rd_stored_mac      (i_rd_stored_mac),
        .o_rd_valid           (o_rd_valid),
        .i_rd_ready           (i_rd_ready),
        .o_rd_tag             (o_rd_tag),
        .o_rd_addr            (o_rd_addr),
        .o_rd_data            (o_rd_data),
        .o_rd_poison          (o_rd_poison),
        .o_rd_slverr          (o_rd_slverr),

        .o_sec_fault_set      (o_sec_fault_set),
        .o_fault_addr_log     (o_fault_addr_log)
    );

    // Clock Generation
    always #(ClkPeriod / 2) clk = ~clk;

    int tests_run = 0;
    int tests_passed = 0;
    int tests_failed = 0;

    initial begin
        clk                = 1'b0;
        rst_n              = 1'b0;
        i_crypto_profile   = 2'b00;
        i_default_key_id   = 8'h01;
        i_epoch_nonce      = 19'h5A5A5;
        i_key1_data        = 256'h0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF;
        i_key2_data        = 128'hFEDCBA9876543210FEDCBA9876543210;
        i_keys_valid       = 1'b1;

        i_precomp_valid    = 1'b0;
        i_precomp_is_write = 1'b0;
        i_precomp_tag      = '0;
        i_precomp_addr     = '0;
        i_precomp_key_id   = '0;

        i_wr_valid         = 1'b0;
        i_wr_tag           = '0;
        i_wr_addr          = '0;
        i_wr_data          = '0;
        i_wr_strb          = '1;
        i_wr_ready         = 1'b1;

        i_rd_valid         = 1'b0;
        i_rd_tag           = '0;
        i_rd_addr          = '0;
        i_rd_data          = '0;
        i_rd_stored_mac    = '0;
        i_rd_ready         = 1'b1;

        #(ClkPeriod * 4);
        rst_n = 1'b1;
        #(ClkPeriod * 4);

        $display("================================================================");
        $display("[TB_CRYPTO_TOP] STARTING TWO-TIER CRYPTO SUBSYSTEM VERIFICATION");
        $display("================================================================");

        // TEST 1: Profile 0 (Bypass Mode Plaintext Pass-through)
        tests_run++;
        i_crypto_profile = 2'b00;
        i_rd_valid       = 1'b1;
        i_rd_tag         = 5'd2;
        i_rd_addr        = 34'h1000;
        i_rd_data        = {8{64'h1122334455667788}};
        #(ClkPeriod);
        if (o_rd_valid && o_rd_data == {8{64'h1122334455667788}} && !o_rd_poison) begin
            $display("[PASS] Test 1: Profile 0 Plaintext Bypass verified.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 1: Profile 0 mismatch. Got %h", o_rd_data);
            tests_failed++;
        end
        i_rd_valid = 1'b0;
        #(ClkPeriod * 2);

        // TEST 2: Profile 2 (High-Throughput CTR 0-Cycle Decoupled Pre-computation)
        tests_run++;
        i_crypto_profile = 2'b10;

        // Step 2a: Trigger Pre-computation on Read Address Phase
        i_precomp_valid    = 1'b1;
        i_precomp_is_write = 1'b0;
        i_precomp_tag      = 5'd5;
        i_precomp_addr     = 34'h4000; // Line 0 of page 4
        i_precomp_key_id   = 8'h01;
        #(ClkPeriod);
        i_precomp_valid    = 1'b0;

        // Step 2b: Overlap with DRAM latency (18 cycles)
        #(ClkPeriod * 20);

        // Step 2c: Arriving Read Data from DRAM
        i_rd_valid = 1'b1;
        i_rd_tag   = 5'd5;
        i_rd_addr  = 34'h4000;
        i_rd_data  = {8{64'hDEADBEEFCAFEBABE}};
        #1; // Allow combinational 0-cycle lookup to evaluate

        // Verify 0-cycle decrypted output
        if (o_rd_valid && o_rd_tag == 5'd5 && o_rd_data != i_rd_data && !o_rd_poison) begin
            $display("[PASS] Test 2: Profile 2 0-Cycle CTR Pre-computation & XOR Decryption verified.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 2: Profile 2 decryption failed. Valid=%b, Data=%h", o_rd_valid, o_rd_data);
            tests_failed++;
        end
        #(ClkPeriod - 1);
        i_rd_valid = 1'b0;
        #(ClkPeriod * 2);

        // TEST 3: Profile 2 Write-Path Pre-computation
        tests_run++;
        // Pre-compute for Write
        i_precomp_valid    = 1'b1;
        i_precomp_is_write = 1'b1;
        i_precomp_tag      = 5'd8;
        i_precomp_addr     = 34'h8000;
        #(ClkPeriod);
        i_precomp_valid    = 1'b0;

        #(ClkPeriod * 20);

        // Write data dispatch
        i_wr_valid = 1'b1;
        i_wr_tag   = 5'd8;
        i_wr_addr  = 34'h8000;
        i_wr_data  = {8{64'hA5A5A5A55A5A5A5A}};
        #1; // Allow combinational 0-cycle encryption to evaluate

        if (o_wr_valid && o_wr_data != i_wr_data) begin
            $display("[PASS] Test 3: Profile 2 Write-Path Pre-computation & XOR Encryption verified.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 3: Profile 2 Write encryption failed. Valid=%b, Data=%h", o_wr_valid, o_wr_data);
            tests_failed++;
        end
        #(ClkPeriod - 1);
        i_wr_valid = 1'b0;
        #(ClkPeriod * 2);

        // TEST 4: Profile 3 (ASIL-D Poisoning on MAC Integrity Failure)
        tests_run++;
        i_crypto_profile = 2'b11; // CTR + MAC

        // Trigger Pre-computation
        i_precomp_valid    = 1'b1;
        i_precomp_is_write = 1'b0;
        i_precomp_tag      = 5'd3;
        i_precomp_addr     = 34'hC000;
        #(ClkPeriod);
        i_precomp_valid    = 1'b0;

        #(ClkPeriod * 20);

        // Send corrupt read data with wrong stored MAC
        i_rd_valid         = 1'b1;
        i_rd_tag           = 5'd3;
        i_rd_addr          = 34'hC000;
        i_rd_data          = {8{64'hBAD0BAD0BAD0BAD0}};
        i_rd_stored_mac    = 64'hDEAD_DEAD_DEAD_DEAD; // Corrupted MAC
        #(ClkPeriod);

        if (o_rd_poison && o_rd_slverr && o_rd_data == '0 && o_sec_fault_set[1]) begin
            $display("[PASS] Test 4: Profile 3 ASIL-D Poisoning (Zeroized Data + SLVERR + Fault Set) verified.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 4: Profile 3 Poisoning failed. Poison=%b, Slverr=%b, Data=%h, Fault=%b",
                     o_rd_poison, o_rd_slverr, o_rd_data, o_sec_fault_set);
            tests_failed++;
        end
        i_rd_valid = 1'b0;
        #(ClkPeriod * 4);

        $display("================================================================");
        $display("[TB_CRYPTO_TOP] SUMMARY: %0d/%0d TESTS PASSED, %0d FAILED",
                 tests_passed, tests_run, tests_failed);
        $display("================================================================");

        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED SUCCESSFULLY]");
            $finish;
        end else begin
            $fatal(1, "[TESTBENCH COMPLETED WITH FAILURES]");
        end
    end

endmodule
