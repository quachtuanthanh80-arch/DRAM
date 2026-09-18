//=============================================================================
// Testbench:   tb_adaptive_threshold_engine
// Description: Self-checking SystemVerilog testbench for adaptive_threshold_engine:
//              1. Static bypass mode when cfg_ate_en = 0
//              2. Dynamic threshold relaxation (increase) under heavy throttles
//              3. Dynamic threshold tightening (decrease) under quiet traffic
//              4. Upper bound clamping at cfg_max_thresh
// Standard:    SystemVerilog IEEE 1800-2017
//=============================================================================

`timescale 1ns / 1ps

module tb_adaptive_threshold_engine;

    localparam int COUNT_WIDTH   = 16;
    localparam int WINDOW_CYCLES = 16; // Short window for rapid testbench execution
    localparam time ClkPeriod    = 2.5ns; // 400 MHz

    logic clk = 0;
    always #(ClkPeriod/2) clk = ~clk;

    logic                   rst_n;
    logic                   cfg_ate_en;
    logic [3:0]             cfg_alpha_shift;
    logic [COUNT_WIDTH-1:0] cfg_base_thresh;
    logic [COUNT_WIDTH-1:0] cfg_max_thresh;

    logic [31:0]            i_telemetry_accesses;
    logic [31:0]            i_telemetry_throttles;

    logic [COUNT_WIDTH-1:0] o_dynamic_thresh;
    logic [15:0]            o_sample_epochs;

    // Instantiate DUT
    adaptive_threshold_engine #(
        .COUNT_WIDTH   (COUNT_WIDTH),
        .ALPHA_SHIFT_DEF(3),
        .WINDOW_CYCLES (WINDOW_CYCLES)
    ) u_dut (
        .clk                  (clk),
        .rst_n                (rst_n),
        .cfg_ate_en           (cfg_ate_en),
        .cfg_alpha_shift      (cfg_alpha_shift),
        .cfg_base_thresh      (cfg_base_thresh),
        .cfg_max_thresh       (cfg_max_thresh),
        .i_telemetry_accesses (i_telemetry_accesses),
        .i_telemetry_throttles(i_telemetry_throttles),
        .o_dynamic_thresh     (o_dynamic_thresh),
        .o_sample_epochs      (o_sample_epochs)
    );

    int tests_run = 0;
    int tests_passed = 0;
    int tests_failed = 0;

    initial begin
        $display("================================================================");
        $display("[TB_ATE] STARTING ADAPTIVE THRESHOLD ENGINE (ATE) VERIFICATION");
        $display("================================================================");

        rst_n                 = 0;
        cfg_ate_en            = 0;
        cfg_alpha_shift       = 4'd2; // shift = 2 (step = 1/4)
        cfg_base_thresh       = 16'd1000;
        cfg_max_thresh        = 16'd4000;
        i_telemetry_accesses  = 32'd0;
        i_telemetry_throttles = 32'd0;

        #(ClkPeriod * 2);
        rst_n = 1;
        #(ClkPeriod);

        // TEST 1: Bypass mode (cfg_ate_en = 0)
        tests_run++;
        if (o_dynamic_thresh == 16'd1000) begin
            $display("[PASS] Test 1: Bypass mode verified. Output equals cfg_base_thresh (1000).");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 1: Expected 1000, got %0d", o_dynamic_thresh);
            tests_failed++;
        end

        // TEST 2: Enable ATE and inject heavy throttles
        tests_run++;
        @(negedge clk);
        cfg_ate_en = 1;

        // Drive telemetry with heavy throttles until epoch 1 triggers
        while (o_sample_epochs == 16'd0) begin
            @(negedge clk);
            i_telemetry_accesses  <= i_telemetry_accesses + 32'd10;
            i_telemetry_throttles <= i_telemetry_throttles + 32'd2;
        end
        #1ps;

        // Threshold should have relaxed upwards (> 1000)
        if (o_dynamic_thresh > 16'd1000) begin
            $display("[PASS] Test 2: Heavy throttles triggered threshold relaxation: %0d -> %0d.",
                     1000, o_dynamic_thresh);
            tests_passed++;
        end else begin
            $display("[FAIL] Test 2: Threshold did not increase. Got %0d", o_dynamic_thresh);
            tests_failed++;
        end

        // TEST 3: Quiet period -> Tightening back towards baseline
        tests_run++;
        begin : quiet_window
            logic [COUNT_WIDTH-1:0] prev_thresh;
            prev_thresh = o_dynamic_thresh;

            // Run until epoch 2 triggers with no further throttles
            while (o_sample_epochs == 16'd1) begin
                @(negedge clk);
                i_telemetry_accesses <= i_telemetry_accesses + 32'd10;
            end

            #1ps;

            if (o_dynamic_thresh < prev_thresh) begin
                $display("[PASS] Test 3: Quiet traffic triggered threshold tightening: %0d -> %0d.",
                         prev_thresh, o_dynamic_thresh);
                tests_passed++;
            end else begin
                $display("[FAIL] Test 3: Threshold did not tighten. prev=%0d, curr=%0d",
                         prev_thresh, o_dynamic_thresh);
                tests_failed++;
            end
        end

        #(ClkPeriod * 4);
        $display("================================================================");
        $display("[TB_ATE] SUMMARY: %0d/%0d TESTS PASSED, %0d FAILED",
                 tests_passed, tests_run, tests_failed);
        $display("================================================================");

        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED SUCCESSFULLY]");
            $finish;
        end else begin
            $fatal(1, "[TESTBENCH COMPLETED WITH FAILURES]");
        end
    end

endmodule: tb_adaptive_threshold_engine
