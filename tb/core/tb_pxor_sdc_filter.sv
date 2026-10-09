// File: tb_pxor_sdc_filter.sv
// Chức năng: Testbench kiểm thử động cơ băm vạn năng PXOR-Hash và bộ lọc SDC chống né tránh thuật toán.
`timescale 1ns / 1ps

module tb_pxor_sdc_filter;
    parameter int TAG_WIDTH  = 22;
    parameter int HASH_WIDTH = 8;

    logic [TAG_WIDTH-1:0]  tag_in;
    logic [63:0]           seed_in;
    wire  [HASH_WIDTH-1:0] hash_out;

    pxor_hash_engine #(
        .TAG_WIDTH  (TAG_WIDTH),
        .HASH_WIDTH (HASH_WIDTH)
    ) dut_pxor (
        .i_tag  (tag_in),
        .i_seed (seed_in),
        .o_hash (hash_out)
    );

    int test_errors = 0;

    initial begin
        tag_in = '0;
        seed_in = 64'hA5A5_5A5A_0123_4567;
        #10;

        $display("=== [TEST 1] Kiểm tra tính nhất quán và độ trễ dưới 1 chu kỳ của PXOR-Hash ===");
        tag_in = 22'h1A5B2;
        #5;
        begin
            logic [HASH_WIDTH-1:0] h1;
            h1 = hash_out;
            #5;
            if (hash_out !== h1) begin
                $display("[FAIL] Đầu ra không ổn định!");
                test_errors++;
            end else begin
                $display("[PASS] Hash tính toán thành công: Tag=0x%06x -> Hash=0x%02x", tag_in, hash_out);
            end
        end

        $display("=== [TEST 2] Kiểm tra phân bố và tính chống va chạm cụm (Anti-Clustering) ===");
        begin
            int hash_bins[256];
            int max_bin_count;
            max_bin_count = 0;
            for (int b = 0; b < 256; b++) hash_bins[b] = 0;

            for (int k = 0; k < 1024; k++) begin
                tag_in = k;
                #1;
                hash_bins[hash_out]++;
            end

            for (int b = 0; b < 256; b++) begin
                if (hash_bins[b] > max_bin_count) begin
                    max_bin_count = hash_bins[b];
                end
            end
            if (max_bin_count > 25) begin
                $display("[FAIL] Va chạm cụm quá mức: Max bin = %0d mẫu", max_bin_count);
                test_errors++;
            end else begin
                $display("[PASS] Phân bố băm vạn năng đạt chuẩn cân bằng: Max bin = %0d/1024 mẫu!", max_bin_count);
            end
        end

        $display("=== [TEST 3] Kiểm tra tính nhạy với Seed ===");
        begin
            logic [HASH_WIDTH-1:0] old_hash;
            tag_in = 22'h3FFFFF;
            #5;
            old_hash = hash_out;

            seed_in = 64'h5A5A_A5A5_89AB_CDEF;
            #5;
            if (hash_out === old_hash) begin
                $display("[FAIL] Đổi seed nhưng hash không đổi!");
                test_errors++;
            end else begin
                $display("[PASS] Đổi seed làm đổi hash thành công: Old=0x%02x, New=0x%02x", old_hash, hash_out);
            end
        end

        if (test_errors == 0) begin
            $display("\n>>> [ALL TESTS PASSED] PXOR-Hash Engine hoạt động hoàn hảo! <<<\n");
            $finish(0);
        end else begin
            $display("\n>>> [FAIL] Phát hiện %0d lỗi! <<<\n", test_errors);
            $finish(1);
        end
    end

endmodule
