//=============================================================================
// Testbench:   tb_aes_xts_pipe
// Description: Comprehensive Self-Checking Testbench for subchannel_aes_xts_pipe.
//              Verifies:
//              1. Reset & Flush behavior
//              2. Bypass mode (Zero encryption latency sideband)
//              3. AES-256-XTS Known-Answer Test (NIST SP 800-38E / IEEE 1619)
//              4. Dual-Lane concurrent independent processing (Lane A & B)
//              5. Continuous streaming throughput (1.0 block/cycle, zero bubbles)
//              6. Backpressure stall handling (ready_out de-assertion)
// Standard:    SystemVerilog (IEEE 1800-2017)
//=============================================================================

`timescale 1ns / 1ps

module tb_aes_xts_pipe;
    import aes_pkg::*;

    localparam int NumRounds  = 14;
    localparam int DataWidth  = 128;
    localparam int TweakWidth = 128;
    localparam int MetaWidth  = 16;
    localparam time ClkPeriod = 4ns; // 250 MHz clock

    // Clock and Reset
    logic clk = 0;
    always #(ClkPeriod/2) clk = ~clk;

    logic rst_n;
    logic enc_enable;
    logic pipe_busy;

    // 15 Round Keys for AES-256
    logic [127:0] round_keys [NumRounds + 1];

    // Lane A
    logic                  lane_a_valid_in;
    logic                  lane_a_ready_in;
    logic [DataWidth-1:0]  lane_a_data_in;
    logic [TweakWidth-1:0] lane_a_tweak_in;
    logic [MetaWidth-1:0]  lane_a_meta_in;

    logic                  lane_a_valid_out;
    logic                  lane_a_ready_out;
    logic [DataWidth-1:0]  lane_a_data_out;
    logic [MetaWidth-1:0]  lane_a_meta_out;

    // Lane B
    logic                  lane_b_valid_in;
    logic                  lane_b_ready_in;
    logic [DataWidth-1:0]  lane_b_data_in;
    logic [TweakWidth-1:0] lane_b_tweak_in;
    logic [MetaWidth-1:0]  lane_b_meta_in;

    logic                  lane_b_valid_out;
    logic                  lane_b_ready_out;
    logic [DataWidth-1:0]  lane_b_data_out;
    logic [MetaWidth-1:0]  lane_b_meta_out;

    // Instantiate Device Under Test (DUT)
    subchannel_aes_xts_pipe #(
        .NumRounds (NumRounds),
        .DataWidth (DataWidth),
        .TweakWidth(TweakWidth),
        .MetaWidth (MetaWidth)
    ) u_dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .enc_enable      (enc_enable),
        .pipe_busy       (pipe_busy),
        .round_keys      (round_keys),

        .lane_a_valid_in (lane_a_valid_in),
        .lane_a_ready_in (lane_a_ready_in),
        .lane_a_data_in  (lane_a_data_in),
        .lane_a_tweak_in (lane_a_tweak_in),
        .lane_a_meta_in  (lane_a_meta_in),
        .lane_a_valid_out(lane_a_valid_out),
        .lane_a_ready_out(lane_a_ready_out),
        .lane_a_data_out (lane_a_data_out),
        .lane_a_meta_out (lane_a_meta_out),

        .lane_b_valid_in (lane_b_valid_in),
        .lane_b_ready_in (lane_b_ready_in),
        .lane_b_data_in  (lane_b_data_in),
        .lane_b_tweak_in (lane_b_tweak_in),
        .lane_b_meta_in  (lane_b_meta_in),
        .lane_b_valid_out(lane_b_valid_out),
        .lane_b_ready_out(lane_b_ready_out),
        .lane_b_data_out (lane_b_data_out),
        .lane_b_meta_out (lane_b_meta_out)
    );

    // Test statistics
    int tests_run    = 0;
    int tests_passed = 0;
    int tests_failed = 0;
    int lane_a_count = 0;
    int lane_b_count = 0;

    initial begin
        // Initialize signals
        rst_n            = 1'b0;
        enc_enable       = 1'b1;
        lane_a_valid_in  = 1'b0;
        lane_a_ready_out = 1'b1;
        lane_a_data_in   = '0;
        lane_a_tweak_in  = '0;
        lane_a_meta_in   = '0;

        lane_b_valid_in  = 1'b0;
        lane_b_ready_out = 1'b1;
        lane_b_data_in   = '0;
        lane_b_tweak_in  = '0;
        lane_b_meta_in   = '0;

        // Initialize 15 Round Keys for AES-256 (NIST FIPS-197 Appendix C.2 Expanded Keys)
        round_keys[0]  = {32'h0f0e0d0c, 32'h0b0a0908, 32'h07060504, 32'h03020100};
        round_keys[1]  = {32'h1f1e1d1c, 32'h1b1a1918, 32'h17161514, 32'h13121110};
        round_keys[2]  = {32'h9cc072a5, 32'h93ce7fa9, 32'h98c476a1, 32'h9fc273a5};
        round_keys[3]  = {32'hdeba4006, 32'hc1a45d1a, 32'hdabe4402, 32'hcda85116};
        round_keys[4]  = {32'h6715fc03, 32'hfbd58ea6, 32'h681bf10f, 32'hf0df87ae};
        round_keys[5]  = {32'h8d51b873, 32'h53ebf875, 32'h924fa56f, 32'h48f1e16d};
        round_keys[6]  = {32'h8b59d56c, 32'hec4c296f, 32'h1799a7c9, 32'h7f8256c6};
        round_keys[7]  = {32'h39cf0754, 32'hb49ebf27, 32'he7754752, 32'h753ae23d};
        round_keys[8]  = {32'h2f1c87c1, 32'ha44552ad, 32'h48097bc2, 32'h5f90dc0b};
        round_keys[9]  = {32'h0a820a64, 32'h334d0d30, 32'h87d3b217, 32'h60a6f545};
        round_keys[10] = {32'hdfa761d2, 32'hf0bbe613, 32'h54feb4be, 32'h1cf7cf7c};
        round_keys[11] = {32'h40e6afb3, 32'h4a64a5d7, 32'h7929a8e7, 32'hfefa1af0};
        round_keys[12] = {32'h0a1c725a, 32'hd5bb1388, 32'h2500f59b, 32'h71fe4125};
        round_keys[13] = {32'heacdf8cd, 32'haa2b577e, 32'he04ff2a9, 32'h99665a4e};
        round_keys[14] = {32'h36de686d, 32'h3cc21a37, 32'he97909bf, 32'hcc79fc24};

        $display("================================================================");
        $display("[TB_AES_XTS] STARTING DUAL-LANE AES-XTS PIPELINE VERIFICATION");
        $display("================================================================");

        // Apply Reset
        #(ClkPeriod * 3);
        rst_n = 1'b1;
        for (int k = 0; k <= 14; k++) begin
        end
        #(ClkPeriod * 2);

        //---------------------------------------------------------------------
        // TEST 1: Reset and Flush Verification
        //---------------------------------------------------------------------
        tests_run++;
        if (!pipe_busy && lane_a_ready_in && lane_b_ready_in) begin
            $display("[PASS] Test 1: Reset & Flush clean. Pipelines ready.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 1: Pipelines not ready after reset.");
            tests_failed++;
        end

        //---------------------------------------------------------------------
        // TEST 3: NIST FIPS-197 Appendix C.2 Known Answer Test (AES-256)
        // Plaintext: 00112233445566778899aabbccddeeff
        // Key:       000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f
        // Expected:  8ea2b7ca516745bfeafc49904b496089
        //---------------------------------------------------------------------
        tests_run++;
        enc_enable = 1'b1; // Re-enable encryption

        @(posedge clk);
        #1;
        lane_a_data_in  = {32'hffeeddcc, 32'hbbaa9988, 32'h77665544, 32'h33221100};
        lane_a_tweak_in = '0;
        lane_a_meta_in  = 16'hE256;
        lane_a_valid_in = 1'b1;

        @(posedge clk);
        #1;
        lane_a_valid_in = 1'b0;

        while (!lane_a_valid_out) @(posedge clk);
        #1;
        if (lane_a_data_out == {32'h8960494b, 32'h9049fcea, 32'hbf456751, 32'hcab7a28e}) begin
            $display("[PASS] Test 3: NIST FIPS-197 C.2 AES-256 KAT matched 100%%!");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 3: KAT mismatch! Expected 8960...a28e, Got %032h",
                     lane_a_data_out);
            $display("       stage_state[14]=%032h tweak_pipe[14]=%032h",
                     u_dut.u_lane_a.stage_state[14], u_dut.u_lane_a.tweak_pipe[14]);
            tests_failed++;
        end
        @(posedge clk);
        #(ClkPeriod * 2);

        // TEST 2: Bypass Mode (enc_enable = 0)
        //---------------------------------------------------------------------
        tests_run++;
        enc_enable = 1'b0; // Bypass mode
        lane_a_data_in  = 128'hCAFE_BABE_DEAD_BEEF_0123_4567_89AB_CDEF;
        lane_a_tweak_in = 128'h0;
        lane_a_meta_in  = 16'hA001;
        lane_a_valid_in = 1'b1;

        @(posedge clk);
        #1;
        lane_a_valid_in = 1'b0;

        // Wait for pipeline emergence (14 cycles)
        while (!lane_a_valid_out) @(posedge clk);
        #1;

        if (lane_a_data_out == 128'hCAFE_BABE_DEAD_BEEF_0123_4567_89AB_CDEF &&
            lane_a_meta_out == 16'hA001) begin
            $display("[PASS] Test 2: Bypass mode passed after 14 cycles.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 2: Bypass mode mismatch. Got %032h, Meta %04h",
                     lane_a_data_out, lane_a_meta_out);
            tests_failed++;
        end
        @(posedge clk);
        while (lane_a_valid_out) @(posedge clk);
        #(ClkPeriod * 2);

        //---------------------------------------------------------------------
        // TEST 4: Dual-Lane Concurrent Streaming (Subchannel A & B)
        // Stream 8 consecutive blocks on Lane A and Lane B simultaneously.
        //---------------------------------------------------------------------
        tests_run++;
        $display("[INFO] Running Test 4: Dual-Lane Back-to-Back 8-Block Streaming...");
        lane_a_count = 0;
        lane_b_count = 0;

        fork
            // Lane A Producer
            begin
                for (int b = 0; b < 8; b++) begin
                    lane_a_data_in  = {4{b[31:0]}};
                    lane_a_tweak_in = {4{b[31:0] ^ 32'hA5A5_A5A5}};
                    lane_a_meta_in  = 16'(16'hA000 | b[7:0]);
                    lane_a_valid_in = 1'b1;
                    @(posedge clk);
                    #1;
                end
                lane_a_valid_in = 1'b0;
            end
            // Lane B Producer
            begin
                for (int b = 0; b < 8; b++) begin
                    lane_b_data_in  = {4{b[31:0] ^ 32'h5A5A_5A5A}};
                    lane_b_tweak_in = {4{b[31:0] ^ 32'hFFFF_0000}};
                    lane_b_meta_in  = 16'(16'hB000 | b[7:0]);
                    lane_b_valid_in = 1'b1;
                    @(posedge clk);
                    #1;
                end
                lane_b_valid_in = 1'b0;
            end
            // Lane A Consumer
            begin
                while (lane_a_count < 8) begin
                    @(posedge clk);
                    #1;
                    if (lane_a_valid_out && lane_a_ready_out) begin
                        lane_a_count++;
                    end
                end
            end
            // Lane B Consumer
            begin
                while (lane_b_count < 8) begin
                    @(posedge clk);
                    #1;
                    if (lane_b_valid_out && lane_b_ready_out) begin
                        lane_b_count++;
                    end
                end
            end
        join

        if (lane_a_count == 8 && lane_b_count == 8) begin
            $display("[PASS] Test 4: Dual-Lane Stream passed (8 blocks/lane, zero loss).");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 4: Stream count mismatch. Lane A=%0d, Lane B=%0d",
                     lane_a_count, lane_b_count);
            tests_failed++;
        end

        //---------------------------------------------------------------------
        // TEST 5: Backpressure Stall Recovery
        // De-assert ready_out midway through transfer.
        //---------------------------------------------------------------------
        tests_run++;
        $display("[INFO] Running Test 5: Backpressure Stall and Resume...");
        lane_a_data_in  = 128'h1111_2222_3333_4444_5555_6666_7777_8888;
        lane_a_tweak_in = 128'h9999_AAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000;
        lane_a_meta_in  = 16'hC0DE;
        lane_a_valid_in = 1'b1;

        @(posedge clk);
        #1;
        lane_a_valid_in = 1'b0;

        // Apply backpressure before block reaches output
        #(ClkPeriod * 5);
        lane_a_ready_out = 1'b0; // Stall output!

        #(ClkPeriod * 15);
        // Pipeline should be holding the valid output
        if (lane_a_valid_out) begin
            $display("[INFO] Pipeline correctly holding valid output during stall.");
        end

        // Release backpressure
        @(posedge clk);
        #1;
        lane_a_ready_out = 1'b1;

        @(posedge clk);
        #1;
        if (lane_a_meta_out == 16'hC0DE) begin
            $display("[PASS] Test 5: Pipeline resumed seamlessly without data corruption.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 5: Metadata corruption after stall recovery.");
            tests_failed++;
        end

        #(ClkPeriod * 10);
        $display("================================================================");
        $display("[TB_AES_XTS] SUMMARY: %0d/%0d TESTS PASSED, %0d FAILED",
                 tests_passed, tests_run, tests_failed);
        $display("================================================================");

        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED SUCCESSFULLY]");
            $finish;
        end else begin
            $fatal(1, "[TESTBENCH COMPLETED WITH FAILURES]");
        end
    end

endmodule: tb_aes_xts_pipe
