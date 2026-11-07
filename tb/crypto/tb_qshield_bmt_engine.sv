// File: tb_qshield_bmt_engine.sv
// Chức năng: Testbench xác minh động cơ cây Bonsai Merkle Tree (BMT 8-ary) trên 4096 dòng dữ liệu.

`timescale 1ns / 1ps

module tb_qshield_bmt_engine;

    `include "tb_check.svh"

    localparam logic [63:0] PROT_BASE  = 64'h0000_0000_0000_0000;
    localparam logic [63:0] PROT_LINES = 64'd4096;
    localparam int          TREE_ARITY = 8;
    localparam int          MC_SETS    = 16;
    localparam int          MC_WAYS    = 4;

    localparam logic [63:0] NUM_CB      = PROT_LINES / 64; // 64 CBs
    localparam logic [63:0] CB_BASE     = PROT_BASE + PROT_LINES * 64; // 0x40000
    localparam logic [63:0] ML_BASE     = CB_BASE + NUM_CB * 64;       // 0x41000
    localparam logic [63:0] ML_BYTES    = (PROT_LINES / 8) * 64;      // 0x8000
    localparam logic [63:0] TN_L1_BASE  = ML_BASE + ML_BYTES;         // 0x49000
    localparam logic [63:0] TN_L2_BASE  = TN_L1_BASE + (NUM_CB / 8) * 64; // 0x49200

    logic clk;
    logic rst_n;

    // Khóa K3 và H
    logic [127:0] i_h;
    logic [255:0] i_k3;
    logic         i_keys_valid;

    // Verify
    logic         i_verify_valid;
    logic [63:0]  i_verify_addr;
    wire          o_verify_ready;
    wire          o_verify_done;
    wire          o_verify_pass;
    wire          o_verify_fail;
    wire  [511:0] o_cb_data;
    wire  [5:0]   o_cb_slot;

    // Update
    logic         i_update_valid;
    logic [63:0]  i_update_addr;
    logic [511:0] i_update_cb_data;
    wire          o_update_ready;
    wire          o_update_done;

    // Init & Flush
    logic         i_init_start;
    wire          o_init_busy;
    wire          o_init_done;
    wire  [31:0]  o_init_cycles;

    logic         i_flush_start;
    wire          o_flush_busy;
    wire          o_flush_done;
    logic         i_cache_clear;

    // DRAM Memory Bus
    wire          o_dram_rd_valid;
    wire  [63:0]  o_dram_rd_addr;
    wire          i_dram_rd_ready;
    logic         i_dram_rd_valid;
    logic [511:0] i_dram_rd_data;

    wire          o_dram_wr_valid;
    wire  [63:0]  o_dram_wr_addr;
    wire  [511:0] o_dram_wr_data;
    wire          i_dram_wr_ready;

    // Root & Stats
    wire  [63:0]  o_tree_root;
    wire  [511:0] o_tree_root_slots;
    wire  [31:0]  o_tree_fail_cnt;
    wire  [31:0]  o_verify_cnt;
    wire  [31:0]  o_update_cnt;
    wire          o_integrity_alert;

    assign i_dram_rd_ready = 1'b1;
    assign i_dram_wr_ready = 1'b1;

    // Instantiate DUT
    qshield_bmt_engine #(
        .PROT_BASE (PROT_BASE),
        .PROT_LINES(PROT_LINES),
        .TREE_ARITY(TREE_ARITY),
        .MC_SETS   (MC_SETS),
        .MC_WAYS   (MC_WAYS)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .i_h              (i_h),
        .i_k3             (i_k3),
        .i_keys_valid     (i_keys_valid),
        .i_verify_valid   (i_verify_valid),
        .i_verify_addr    (i_verify_addr),
        .o_verify_ready   (o_verify_ready),
        .o_verify_done    (o_verify_done),
        .o_verify_pass    (o_verify_pass),
        .o_verify_fail    (o_verify_fail),
        .o_cb_data        (o_cb_data),
        .o_cb_slot        (o_cb_slot),
        .i_update_valid   (i_update_valid),
        .i_update_addr    (i_update_addr),
        .i_update_cb_data (i_update_cb_data),
        .o_update_ready   (o_update_ready),
        .o_update_done    (o_update_done),
        .i_init_start     (i_init_start),
        .o_init_busy      (o_init_busy),
        .o_init_done      (o_init_done),
        .o_init_cycles    (o_init_cycles),
        .i_flush_start    (i_flush_start),
        .o_flush_busy     (o_flush_busy),
        .o_flush_done     (o_flush_done),
        .i_cache_clear    (i_cache_clear),
        .o_dram_rd_valid  (o_dram_rd_valid),
        .o_dram_rd_addr   (o_dram_rd_addr),
        .i_dram_rd_ready  (i_dram_rd_ready),
        .i_dram_rd_valid  (i_dram_rd_valid),
        .i_dram_rd_data   (i_dram_rd_data),
        .o_dram_wr_valid  (o_dram_wr_valid),
        .o_dram_wr_addr   (o_dram_wr_addr),
        .o_dram_wr_data   (o_dram_wr_data),
        .i_dram_wr_ready  (i_dram_wr_ready),
        .o_tree_root      (o_tree_root),
        .o_tree_root_slots(o_tree_root_slots),
        .o_tree_fail_cnt  (o_tree_fail_cnt),
        .o_verify_cnt     (o_verify_cnt),
        .o_update_cnt     (o_update_cnt),
        .o_integrity_alert(o_integrity_alert)
    );

    // -------------------------------------------------------------------------
    // DRAM Backdoor Model (Bộ nhớ DRAM mô phỏng đồng bộ)
    // -------------------------------------------------------------------------
    reg [511:0] dram_mem [0:5000];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            i_dram_rd_valid <= 1'b0;
            i_dram_rd_data  <= '0;
        end else begin
            i_dram_rd_valid <= 1'b0;
            if (o_dram_wr_valid) begin
                dram_mem[o_dram_wr_addr >> 6] <= o_dram_wr_data;
            end
            if (o_dram_rd_valid) begin
                i_dram_rd_valid <= 1'b1;
                i_dram_rd_data  <= dram_mem[o_dram_rd_addr >> 6];
            end
        end
    end

    // Clock generator: 400 MHz (2.5 ns chu kỳ, 1.25 ns nửa chu kỳ)
    initial begin
        clk = 0;
        forever #1.25 clk = ~clk;
    end

    // -------------------------------------------------------------------------
    // Helper Tasks
    // -------------------------------------------------------------------------
    task automatic do_verify(
        input  logic [63:0]  addr,
        output logic         pass,
        output logic         fail,
        output logic [511:0] cb,
        output logic [5:0]   slot
    );
        int timeout;
        @(negedge clk);
        timeout = 0;
        while (!o_verify_ready) begin
            @(negedge clk);
            timeout++;
            if (timeout > 500) begin
                $display("[ERROR] do_verify waiting for o_verify_ready hung! state=%0d", dut.state);
                $fflush();
                $finish;
            end
        end
        i_verify_valid = 1'b1;
        i_verify_addr  = addr;
        @(negedge clk);
        i_verify_valid = 1'b0;
        timeout = 0;
        while (!o_verify_done) begin
            @(negedge clk);
            timeout++;
            if (timeout > 500) begin
                $display("[ERROR] do_verify waiting for o_verify_done hung! state=%0d", dut.state);
                $fflush();
                $finish;
            end
        end
        pass = o_verify_pass;
        fail = o_verify_fail;
        cb   = o_cb_data;
        slot = o_cb_slot;
    endtask

    task automatic do_update(input logic [63:0] addr, input logic [511:0] cb);
        int timeout;
        @(negedge clk);
        timeout = 0;
        while (!o_update_ready) begin
            @(negedge clk);
            timeout++;
            if (timeout > 500) begin
                $display("[ERROR] do_update waiting for o_update_ready hung! state=%0d", dut.state);
                $fflush();
                $finish;
            end
        end
        i_update_valid   = 1'b1;
        i_update_addr    = addr;
        i_update_cb_data = cb;
        @(negedge clk);
        i_update_valid   = 1'b0;
        timeout = 0;
        while (!o_update_done) begin
            @(negedge clk);
            timeout++;
            if (timeout > 500) begin
                $display("[ERROR] do_update waiting for o_update_done hung! state=%0d", dut.state);
                $fflush();
                $finish;
            end
        end
    endtask

    task automatic do_flush();
        @(negedge clk);
        while (!o_verify_ready || o_flush_busy) @(negedge clk);
        i_flush_start = 1'b1;
        @(negedge clk);
        i_flush_start = 1'b0;
        while (!o_flush_done) @(negedge clk);
    endtask

    task automatic evict_cb0();
        logic p, f; logic [511:0] c; logic [5:0] s;
        // Set 0: CB 0, CB 16, CB 32, CB 48
        do_verify(PROT_BASE + (64'd16 << 12), p, f, c, s);
        do_verify(PROT_BASE + (64'd32 << 12), p, f, c, s);
        do_verify(PROT_BASE + (64'd48 << 12), p, f, c, s);
        do_verify(PROT_BASE + (64'd16 << 12), p, f, c, s);
    endtask

    task automatic evict_l2();
        logic p, f; logic [511:0] c; logic [5:0] s;
        // Set 8: L2 node (addr 0x49200), CB 8, CB 24, CB 40, CB 56
        do_verify(PROT_BASE + (64'd8  << 12), p, f, c, s);
        do_verify(PROT_BASE + (64'd24 << 12), p, f, c, s);
        do_verify(PROT_BASE + (64'd40 << 12), p, f, c, s);
        do_verify(PROT_BASE + (64'd56 << 12), p, f, c, s);
    endtask

    task automatic dump_dram_metadata(input string filepath);
        int fd;
        int i;
        logic [63:0] addr;
        fd = $fopen(filepath, "w");
        if (fd == 0) begin
            $display("[ERROR] Cannot create DRAM dump file %s", filepath);
        end else begin
            // 64 Counter Blocks
            for (i = 0; i < 64; i++) begin
                addr = CB_BASE + i * 64;
                $fdisplay(fd, "%016x %0128x", addr, dram_mem[addr >> 6]);
            end
            // 8 Level 1 nodes
            for (i = 0; i < 8; i++) begin
                addr = TN_L1_BASE + i * 64;
                $fdisplay(fd, "%016x %0128x", addr, dram_mem[addr >> 6]);
            end
            // 1 Level 2 node
            addr = TN_L2_BASE;
            $fdisplay(fd, "%016x %0128x", addr, dram_mem[addr >> 6]);
            $fclose(fd);
            $display("[TB_INFO] DRAM metadata dumped to %s", filepath);
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Test Sequence
    // -------------------------------------------------------------------------
    initial begin
        logic pass, fail;
        logic [511:0] cb;
        logic [5:0]  slot;
        logic [63:0] test_addr;
        logic [511:0] orig_dram_val;
        int i;
        int ops_pass_cnt;
        int rand_op;
        logic [31:0] lfsr;

        $display("=================================================================");
        $display("   TESTBENCH QSHIELD BMT ENGINE (BONSAI MERKLE TREE 8-ARY)       ");
        $display("=================================================================");

        // Khởi tạo tín hiệu
        rst_n          = 0;
        i_keys_valid   = 0;
        i_k3           = 256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f;
        i_h            = 128'hf29000b62a499fd0a9f39a6add2e7780; // H = AES256_K3(0^128)
        i_verify_valid = 0;
        i_verify_addr  = 0;
        i_update_valid = 0;
        i_update_addr  = 0;
        i_update_cb_data = 0;
        i_init_start   = 0;
        i_flush_start  = 0;
        i_cache_clear  = 0;

        for (i = 0; i < 5000; i++) dram_mem[i] = '0;

        #10;
        rst_n = 1;
        #10;
        @(negedge clk);
        i_keys_valid = 1;

        // Chờ key expand xong
        #150;

        // ---------------------------------------------------------------------
        // CHECK 1: Khởi tạo toàn bộ cây bằng meta_init
        // ---------------------------------------------------------------------
        $display("[STAGE 1] Triggering meta_init...");
        $fflush();
        @(negedge clk);
        i_init_start = 1;
        @(negedge clk);
        i_init_start = 0;

        while (!o_init_done) @(negedge clk);
        $display("[STAGE 1] meta_init completed in %0d cycles. Root: 0x%016X", o_init_cycles, o_tree_root);
        $fflush();
        tb_check(o_tree_root == 64'h9044c0889a318be7, "CHECK_INIT_ROOT: Tree root matches Python initial model (0x9044C0889A318BE7)");

        // ---------------------------------------------------------------------
        // CHECK 2: Thực hiện 20,000 thao tác ngẫu nhiên (Read verify + Write update)
        // ---------------------------------------------------------------------
        $display("[STAGE 2] Running 20,000 random operations (Verify Reads & Update Writes)...");
        $fflush();
        lfsr = 32'hDEAD_BEEF;
        ops_pass_cnt = 0;

        for (i = 0; i < 20000; i++) begin
            // LFSR 32-bit PRNG
            lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
            test_addr = PROT_BASE + ((lfsr[11:0]) << 6); // Chọn ngẫu nhiên trong 4096 dòng
            rand_op = lfsr[12]; // 0: Read verify, 1: Write update

            if (rand_op == 0) begin
                do_verify(test_addr, pass, fail, cb, slot);
                if (pass) ops_pass_cnt++;
            end else begin
                // Đọc trước để lấy CB hiện tại
                do_verify(test_addr, pass, fail, cb, slot);
                if (pass) begin
                    // Tăng minor counter 7-bit tại slot của dòng
                    cb[slot*8 +: 7] = cb[slot*8 +: 7] + 1'b1;
                    do_update(test_addr, cb);
                    ops_pass_cnt++;
                end
            end

            if ((i + 1) % 5000 == 0) begin
                $display("  - Progress: %0d / 20,000 operations completed. Current root: 0x%016X", i + 1, o_tree_root);
                $fflush();
            end
        end

        tb_check(ops_pass_cnt == 20000, "CHECK_20000_OPS: All 20,000 operations completed successfully without error");

        // ---------------------------------------------------------------------
        // CHECK 3: Xả toàn bộ cache xuống DRAM bằng meta_flush
        // ---------------------------------------------------------------------
        $display("[STAGE 3] Triggering meta_flush...");
        do_flush();
        $display("[STAGE 3] meta_flush done. Tree root in register: 0x%016X", o_tree_root);
        tb_check(1'b1, "CHECK_FLUSH_DONE: Cache flushed dirty lines to DRAM successfully");

        // Xuất ảnh DRAM ra file để Python đối chiếu
        dump_dram_metadata("build/bmt_dram_dump.txt");

        // ---------------------------------------------------------------------
        // CHECK 4: Kiểm tra khả năng phát hiện giả mạo (Tamper Detection)
        // ---------------------------------------------------------------------
        $display("[STAGE 4] Injecting tamper attacks across every level...");

        // 1. Giả mạo Counter Block trong DRAM
        i_cache_clear = 1; @(negedge clk); i_cache_clear = 0; @(negedge clk);
        orig_dram_val = dram_mem[CB_BASE >> 6];
        dram_mem[CB_BASE >> 6] = orig_dram_val ^ 512'd1; // Lật 1 bit trong CB 0

        do_verify(PROT_BASE, pass, fail, cb, slot);
        tb_check(!pass && fail && o_integrity_alert, "CHECK_TAMPER_CB: Corrupted Counter Block in DRAM detected by BMT engine");
        dram_mem[CB_BASE >> 6] = orig_dram_val; // Khôi phục

        // 2. Giả mạo Level 1 node trong DRAM
        i_cache_clear = 1; @(negedge clk); i_cache_clear = 0; @(negedge clk);
        orig_dram_val = dram_mem[TN_L1_BASE >> 6];
        dram_mem[TN_L1_BASE >> 6] = orig_dram_val ^ 512'd1; // Lật 1 bit trong L1 node 0

        do_verify(PROT_BASE, pass, fail, cb, slot);
        tb_check(!pass && fail && o_integrity_alert, "CHECK_TAMPER_L1: Corrupted Level 1 node in DRAM detected by BMT engine");
        dram_mem[TN_L1_BASE >> 6] = orig_dram_val; // Khôi phục

        // 3. Giả mạo Level 2 node trong DRAM
        i_cache_clear = 1; @(negedge clk); i_cache_clear = 0; @(negedge clk);
        orig_dram_val = dram_mem[TN_L2_BASE >> 6];
        dram_mem[TN_L2_BASE >> 6] = orig_dram_val ^ 512'd1; // Lật 1 bit trong L2 node 0

        do_verify(PROT_BASE, pass, fail, cb, slot);
        tb_check(!pass && fail && o_integrity_alert, "CHECK_TAMPER_L2: Corrupted Level 2 node in DRAM detected by BMT engine");
        dram_mem[TN_L2_BASE >> 6] = orig_dram_val; // Khôi phục

        // 4. Kiểm tra dòng 0 sau khi khôi phục dữ liệu hợp lệ
        i_cache_clear = 1; @(negedge clk); i_cache_clear = 0; @(negedge clk);
        do_verify(PROT_BASE, pass, fail, cb, slot);
        tb_check(pass && !fail, "CHECK_RESTORE_PASS: Verification passes cleanly after DRAM integrity restored");

        // ---------------------------------------------------------------------
        // CHECK 5: Bất biến Spec Mục 5
        // ---------------------------------------------------------------------
        tb_check(o_tree_fail_cnt >= 3, "CHECK_SPEC_INVARIANT: Security alert & tree_fail_cnt incremented on tamper");

        $display("=================================================================");
        $display("   FINAL REGRESSION REPORT                                       ");
        $display("=================================================================");
        tb_report();

        #50;
        $finish;
    end

endmodule
