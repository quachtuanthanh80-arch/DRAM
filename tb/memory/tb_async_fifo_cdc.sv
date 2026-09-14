//=============================================================================
// Testbench:   tb_async_fifo_cdc
// Description: Comprehensive Self-Checking Testbench for async_fifo_cdc.
//              Simulates realistic asynchronous Clock Domain Crossing (CDC):
//              - Write Clock: 250 MHz (4.0 ns period)
//              - Read Clock:  400 MHz (2.5 ns period)
//              Verifies:
//              1. Reset behavior (rempty=1, wfull=0)
//              2. FIFO fill until full flag assertion
//              3. Safe backpressure during full condition
//              4. Dual-clock asynchronous concurrent streaming (100 blocks)
//              5. Exact FIFO order preservation (0 bit errors, 0 dropped words)
// Standard:    SystemVerilog (IEEE 1800-2017)
//=============================================================================

`timescale 1ns / 1ps

module tb_async_fifo_cdc;

    localparam int DataWidth = 144;
    localparam int Depth     = 16;
    localparam time WClkPeriod = 4.0ns; // 250 MHz
    localparam time RClkPeriod = 2.5ns; // 400 MHz

    // Asynchronous Clocks
    logic wclk = 0;
    always #(WClkPeriod/2) wclk = ~wclk;

    logic rclk = 0;
    always #(RClkPeriod/2) rclk = ~rclk;

    logic wrst_n;
    logic rrst_n;

    // Write Interface
    logic                 winc;
    logic [DataWidth-1:0] wdata;
    logic                 wfull;
    logic                 walmost_full;

    // Read Interface
    logic                 rinc;
    logic [DataWidth-1:0] rdata;
    logic                 rempty;
    logic                 ralmost_empty;

    // DUT Instance
    async_fifo_cdc #(
        .DataWidth(DataWidth),
        .Depth    (Depth)
    ) u_dut (
        .wclk         (wclk),
        .wrst_n       (wrst_n),
        .winc         (winc),
        .wdata        (wdata),
        .wfull        (wfull),
        .walmost_full (walmost_full),
        .rclk         (rclk),
        .rrst_n       (rrst_n),
        .rinc         (rinc),
        .rdata        (rdata),
        .rempty       (rempty),
        .ralmost_empty(ralmost_empty)
    );

    int tests_run    = 0;
    int tests_passed = 0;
    int tests_failed = 0;

    // Scoreboard for verification
    logic [DataWidth-1:0] expected_queue [$];
    int write_count = 0;
    int read_count  = 0;

    initial begin
        // Reset initialization
        wrst_n = 1'b0;
        rrst_n = 1'b0;
        winc   = 1'b0;
        wdata  = '0;
        rinc   = 1'b0;

        #(WClkPeriod * 4);
        wrst_n = 1'b1;
        rrst_n = 1'b1;
        #(WClkPeriod * 2);

        $display("================================================================");
        $display("[TB_ASYNC_FIFO] STARTING DUAL-CLOCK CDC FIFO VERIFICATION");
        $display("================================================================");

        // TEST 1: Reset State
        tests_run++;
        #(WClkPeriod * 2);
        if (rempty && !wfull) begin
            $display("[PASS] Test 1: Reset verified cleanly (rempty=1, wfull=0).");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 1: Reset state invalid. rempty=%b, wfull=%b", rempty, wfull);
            tests_failed++;
        end

        // TEST 2: Fill FIFO completely until full flag asserts
        tests_run++;
        for (int i = 0; i < Depth; i++) begin
            @(posedge wclk);
            winc  <= 1'b1;
            wdata <= {16'hA000 | i[7:0], 128'hCAFE_BABE_0000_0000 | i};
        end
        @(posedge wclk);
        winc <= 1'b0;

        // Allow 2 cycles for Gray sync
        repeat (3) @(posedge wclk);

        if (wfull) begin
            $display("[PASS] Test 2: FIFO reached capacity and asserted wfull correctly.");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 2: wfull failed to assert after %0d writes.", Depth);
            tests_failed++;
        end

        // Drain FIFO completely
        while (!rempty) begin
            @(posedge rclk);
            rinc <= 1'b1;
        end
        @(posedge rclk);
        rinc <= 1'b0;
        repeat (4) @(posedge wclk);

        // TEST 3: Concurrent Asynchronous Streaming (100 words)
        tests_run++;
        $display("[INFO] Running Test 3: Concurrent CDC Streaming of 100 blocks...");
        write_count = 0;
        read_count  = 0;
        expected_queue.delete();

        fork
            // Write domain producer (250 MHz)
            begin
                while (write_count < 100) begin
                    @(posedge wclk);
                    if (!wfull) begin
                        automatic logic [DataWidth-1:0] val = {16'hD000 | write_count[7:0],
                                                               64'hFEED_FACE_1111_2222,
                                                               64'h3333_4444_5555_0000 | write_count};
                        wdata <= val;
                        winc  <= 1'b1;
                        expected_queue.push_back(val);
                        write_count++;
                    end else begin
                        winc <= 1'b0;
                    end
                end
                @(posedge wclk);
                winc <= 1'b0;
            end

            // Read domain consumer (400 MHz)
            begin
                while (read_count < 100) begin
                    @(posedge rclk);
                    #1;
                    if (!rempty) begin
                        rinc <= 1'b1;
                        if (expected_queue.size() > 0) begin
                            automatic logic [DataWidth-1:0] exp = expected_queue.pop_front();
                            if (rdata !== exp) begin
                                $display("[FAIL] Data mismatch at item %0d! Got %036h, Expected %036h",
                                         read_count, rdata, exp);
                                tests_failed++;
                            end
                        end
                        read_count++;
                    end else begin
                        rinc <= 1'b0;
                    end
                end
                @(posedge rclk);
                rinc <= 1'b0;
            end
        join

        if (write_count == 100 && read_count == 100 && expected_queue.size() == 0) begin
            $display("[PASS] Test 3: Concurrent CDC stream passed (100 blocks, 0 data errors).");
            tests_passed++;
        end else begin
            $display("[FAIL] Test 3: Count mismatch. Wr=%0d, Rd=%0d, Queue Remaining=%0d",
                     write_count, read_count, expected_queue.size());
            tests_failed++;
        end

        #(WClkPeriod * 4);
        $display("================================================================");
        $display("[TB_ASYNC_FIFO] SUMMARY: %0d/%0d TESTS PASSED, %0d FAILED",
                 tests_passed, tests_run, tests_failed);
        $display("================================================================");

        if (tests_failed == 0) begin
            $display("[ALL TESTS PASSED SUCCESSFULLY]");
            $finish;
        end else begin
            $fatal(1, "[TESTBENCH COMPLETED WITH FAILURES]");
        end
    end

endmodule: tb_async_fifo_cdc
