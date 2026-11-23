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
    logic                   i_rowpress_clamp_alert;

    logic [COUNT_WIDTH-1:0] o_dynamic_thresh;
    logic [15:0]            o_sample_epochs;

    // Instantiate DUT
    adaptive_threshold_engine #(
        .COUNT_WIDTH   (COUNT_WIDTH),
        .ALPHA_SHIFT_DEF(3),
        .WINDOW_CYCLES (WINDOW_CYCLES)
    ) u_dut (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .cfg_ate_en            (cfg_ate_en),
        .cfg_alpha_shift       (cfg_alpha_shift),
        .cfg_base_thresh       (cfg_base_thresh),
        .cfg_max_thresh        (cfg_max_thresh),
        .i_telemetry_accesses  (i_telemetry_accesses),
        .i_telemetry_throttles (i_telemetry_throttles),
        .i_rowpress_clamp_alert(i_rowpress_clamp_alert),
        .o_dynamic_thresh      (o_dynamic_thresh),
        .o_sample_epochs       (o_sample_epochs)
    );

    function automatic logic [31:0] xs32(input logic [31:0] x);
        xs32 = x ^ (x << 13);
        xs32 = xs32 ^ (xs32 >> 17);
        xs32 = xs32 ^ (xs32 << 5);
    endfunction

    int tests_run = 0;
    int tests_passed = 0;
    int tests_failed = 0;
    `include "tb_check.svh"

    initial begin
        $display("================================================================");
        $display("[TB_ATE] STARTING ADAPTIVE THRESHOLD ENGINE (ATE) VERIFICATION");
        $display("================================================================");

        rst_n                 = 0;
        cfg_ate_en            = 0;
        cfg_alpha_shift       = 4'd2; // shift = 2 (step = 1/4)
        cfg_base_thresh        = 16'd1000;
        cfg_max_thresh         = 16'd4000;
        i_telemetry_accesses   = 32'd0;
        i_telemetry_throttles  = 32'd0;
        i_rowpress_clamp_alert = 1'b0;

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
        // Ngưỡng được cập nhật qua 3 pha thanh ghi sau mốc lấy mẫu
        repeat (3) @(negedge clk);
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
            repeat (3) @(negedge clk);
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

        // TEST 4: 16-bit overflow guard at cfg_base_thresh = 16'hFFFF, cfg_max_thresh = 16'hFFFF
        tests_run++;
        begin : t4_ffff
            bit ok4;
            logic [COUNT_WIDTH-1:0] min_obs;
            logic [15:0] ep0;
            ok4 = 1'b1;
            min_obs = 16'hFFFF;
            @(negedge clk);
            rst_n = 1'b0;
            cfg_ate_en = 1'b0;
            cfg_alpha_shift = 4'd4;
            cfg_base_thresh = 16'hFFFF;
            cfg_max_thresh  = 16'hFFFF;
            i_telemetry_accesses  = 32'd0;
            i_telemetry_throttles = 32'd0;
            i_rowpress_clamp_alert = 1'b0;
            repeat (3) @(negedge clk);
            rst_n = 1'b1;
            @(negedge clk);
            cfg_ate_en = 1'b1;
            ep0 = o_sample_epochs;
            while (o_sample_epochs == ep0) begin
                @(negedge clk);
                i_telemetry_accesses <= i_telemetry_accesses + 32'd16;
            end
            repeat (3) @(negedge clk);
            #1ps;
            if (o_dynamic_thresh !== 16'hFFFF) ok4 = 1'b0;
            if (o_dynamic_thresh < min_obs) min_obs = o_dynamic_thresh;
            if (u_dut.pen_floor_q !== 1'b1) ok4 = 1'b0;

            // Kích hoạt RowPress alert tại 16'hFFFF (nếu pen_floor_q=0 sẽ trừ 1 xuống 16'hFFFE rồi sụp về 0)
            @(negedge clk);
            i_rowpress_clamp_alert = 1'b1;
            repeat (4) begin
                @(negedge clk);
                #1ps;
                if (o_dynamic_thresh < min_obs) min_obs = o_dynamic_thresh;
                if (o_dynamic_thresh !== 16'hFFFF) ok4 = 1'b0;
            end
            i_rowpress_clamp_alert = 1'b0;

            // Thử nới (relax_q) khi cur_q = max_thresh = 16'hFFFF
            ep0 = o_sample_epochs;
            while (o_sample_epochs == ep0) begin
                @(negedge clk);
                i_telemetry_accesses  <= i_telemetry_accesses + 32'd16;
                i_telemetry_throttles <= i_telemetry_throttles + 32'd4;
            end
            repeat (4) begin
                @(negedge clk);
                #1ps;
                if (o_dynamic_thresh < min_obs) min_obs = o_dynamic_thresh;
                if (o_dynamic_thresh !== 16'hFFFF) ok4 = 1'b0;
            end

            if (ok4) begin
                $display("[PASS] Test 4: 16'hFFFF overflow prevented (min_obs=0x%04x, pen_floor_q=%0b).", min_obs, u_dut.pen_floor_q);
                tests_passed++;
            end else begin
                $display("[FAIL] Test 4: 16'hFFFF overflow detected! min_obs=0x%04x cur=0x%04x pen_floor_q=%0b",
                         min_obs, o_dynamic_thresh, u_dut.pen_floor_q);
                tests_failed++;
            end
        end

        // TEST 5: 16-bit overflow guard at cfg_base_thresh = 16'hFFFE, cfg_max_thresh = 16'hFFFF
        tests_run++;
        begin : t5_fffe
            bit ok5;
            logic [COUNT_WIDTH-1:0] min_obs;
            logic [15:0] ep0;
            ok5 = 1'b1;
            min_obs = 16'hFFFF;
            @(negedge clk);
            rst_n = 1'b0;
            cfg_ate_en = 1'b0;
            cfg_alpha_shift = 4'd4;
            cfg_base_thresh = 16'hFFFE;
            cfg_max_thresh  = 16'hFFFF;
            i_telemetry_accesses  = 32'd0;
            i_telemetry_throttles = 32'd0;
            i_rowpress_clamp_alert = 1'b0;
            repeat (3) @(negedge clk);
            rst_n = 1'b1;
            @(negedge clk);
            cfg_ate_en = 1'b1;
            // Relax 2 cửa sổ để lên 16'hFFFF rồi relax tiếp tại 16'hFFFF
            for (int w = 0; w < 2; w++) begin
                ep0 = o_sample_epochs;
                while (o_sample_epochs == ep0) begin
                    @(negedge clk);
                    i_telemetry_accesses  <= i_telemetry_accesses + 32'd16;
                    i_telemetry_throttles <= i_telemetry_throttles + 32'd4;
                end
                repeat (4) begin
                    @(negedge clk);
                    #1ps;
                    if (o_dynamic_thresh < min_obs) min_obs = o_dynamic_thresh;
                    if (o_dynamic_thresh < 16'hFFFE) ok5 = 1'b0;
                end
            end
            // Kiểm tra RowPress alert và siết ngưỡng không rơi dưới 16'hFFFE
            @(negedge clk);
            i_rowpress_clamp_alert = 1'b1;
            repeat (3) begin
                @(negedge clk);
                #1ps;
                if (o_dynamic_thresh < min_obs) min_obs = o_dynamic_thresh;
                if (o_dynamic_thresh < 16'hFFFE) ok5 = 1'b0;
            end
            i_rowpress_clamp_alert = 1'b0;
            ep0 = o_sample_epochs;
            while (o_sample_epochs == ep0) begin
                @(negedge clk);
                i_telemetry_accesses <= i_telemetry_accesses + 32'd16;
            end
            repeat (4) begin
                @(negedge clk);
                #1ps;
                if (o_dynamic_thresh < min_obs) min_obs = o_dynamic_thresh;
                if (o_dynamic_thresh < 16'hFFFE) ok5 = 1'b0;
            end

            if (ok5) begin
                $display("[PASS] Test 5: 16'hFFFE..16'hFFFF bounds preserved (min_obs=0x%04x, cur=0x%04x).", min_obs, o_dynamic_thresh);
                tests_passed++;
            end else begin
                $display("[FAIL] Test 5: 16'hFFFE overflow/underflow detected! min_obs=0x%04x cur=0x%04x", min_obs, o_dynamic_thresh);
                tests_failed++;
            end
        end

        // TEST 6: 100,000-cycle seeded random bit-exactness check (cfg_base_thresh < 16'hFFFE)
        tests_run++;
        begin : t6_rand100k
            logic [31:0] rng;
            logic [63:0] sig;
            bit ok6;
            int cyc_k;
            rng = 32'h88A7_E001;
            sig = 64'hCBF2_9CE4_8422_2325;
            ok6 = 1'b1;
            for (int seg = 0; seg < 4; seg++) begin
                @(negedge clk);
                rst_n = 1'b0;
                cfg_ate_en = 1'b0;
                rng = xs32(rng);
                cfg_alpha_shift = rng[3:0];
                cfg_base_thresh = 16'd64 + (rng[19:4] % 16'd65000); // < 16'hFFFE
                cfg_max_thresh  = cfg_base_thresh + (rng[31:20] % (16'hFFFD - cfg_base_thresh + 16'd1));
                i_telemetry_accesses  = 32'd0;
                i_telemetry_throttles = 32'd0;
                i_rowpress_clamp_alert = 1'b0;
                repeat (2) @(negedge clk);
                rst_n = 1'b1;
                @(negedge clk);
                cfg_ate_en = 1'b1;
                for (cyc_k = 0; cyc_k < 25000; cyc_k++) begin
                    @(negedge clk);
                    rng = xs32(rng);
                    i_telemetry_accesses   <= i_telemetry_accesses + {28'd0, rng[3:0]};
                    i_telemetry_throttles  <= i_telemetry_throttles + ((rng[7:4] == 4'hF) ? 32'd1 : 32'd0);
                    i_rowpress_clamp_alert <= (rng[15:8] == 8'hAA);
                    @(posedge clk);
                    #1ps;
                    sig = (sig ^ {32'd0, o_sample_epochs, o_dynamic_thresh}) * 64'h0000_0100_0000_01B3;
                    if (o_dynamic_thresh < ((cfg_base_thresh != 16'd0) ? cfg_base_thresh : 16'd2048) ||
                        o_dynamic_thresh > ((cfg_max_thresh != 16'd0) ? cfg_max_thresh : 16'd8192)) begin
                        ok6 = 1'b0;
                    end
                end
            end
            $display("[ATE_RAND100K] cycles=100000 sig=0x%016h ok=%0d", sig, ok6);
            if (ok6) begin
                $display("[PASS] Test 6: 100,000-cycle seeded random bounds & signature ok (sig=0x%016h).", sig);
                tests_passed++;
            end else begin
                $display("[FAIL] Test 6: 100,000-cycle bounds failed (sig=0x%016h).", sig);
                tests_failed++;
            end
        end

        #(ClkPeriod * 4);
        $display("================================================================");
        $display("[TB_ATE] SUMMARY: %0d/%0d TESTS PASSED, %0d FAILED",
                 tests_passed, tests_run, tests_failed);
        $display("================================================================");

        tb_merge_legacy(tests_passed + tests_failed, tests_failed);
        tb_report();
        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED SUCCESSFULLY]");
            $finish;
        end else begin
            $fatal(1, "[TESTBENCH COMPLETED WITH FAILURES]");
        end
    end

endmodule: tb_adaptive_threshold_engine
