// File: tb_qshield_meta_cache.sv
// Chức năng: Kiểm thử bộ nhớ đệm metadata tin cậy với 50.000 truy cập ngẫu nhiên đối chiếu mô hình Python.

`timescale 1ns / 1ps
`include "tb_check.svh"

module tb_qshield_meta_cache;
    logic         clk;
    logic         rst_n;

    // Giao diện tra cứu
    logic         i_lookup_valid;
    logic [63:0]  i_lookup_addr;
    logic         i_lookup_pin;
    wire          o_lookup_hit;
    wire  [1:0]   o_lookup_way;
    wire  [511:0] o_lookup_data;
    wire          o_lookup_dirty;
    wire          o_lookup_verified;
    wire          o_lookup_pinned;

    // Giao diện nạp dòng
    logic         i_fill_valid;
    logic [63:0]  i_fill_addr;
    logic [511:0] i_fill_data;
    logic         i_fill_verified;
    logic         i_fill_pin;
    wire  [1:0]   o_fill_way;
    wire          o_evict_valid;
    wire          o_evict_dirty;
    wire  [63:0]  o_evict_addr;
    wire  [511:0] o_evict_data;

    // Giao diện cập nhật
    logic         i_update_valid;
    logic [63:0]  i_update_addr;
    logic [511:0] i_update_data;
    logic         i_update_dirty;
    logic         i_update_data_en;
    wire          o_update_hit;
    wire  [1:0]   o_update_way;

    // Giao diện bỏ ghim
    logic         i_unpin_valid;
    logic [63:0]  i_unpin_addr;
    wire          o_unpin_hit;
    wire  [1:0]   o_unpin_way;

    // Giao diện Flush
    logic         i_flush_start;
    logic         i_flush_ready;
    wire          o_flush_busy;
    wire          o_flush_done;
    wire          o_flush_evict_valid;
    wire  [63:0]  o_flush_evict_addr;
    wire  [511:0] o_flush_evict_data;

    // CSR Counters
    wire  [31:0]  o_hit_cnt;
    wire  [31:0]  o_miss_cnt;
    wire  [31:0]  o_evict_cnt;
    wire  [31:0]  o_wb_cnt;
    wire  [15:0]  o_set_can_pin;
    wire          o_pin_violation;

    qshield_meta_cache #(
        .MC_SETS    (16),
        .MC_WAYS    (4),
        .ADDR_WIDTH (64),
        .DATA_WIDTH (512)
    ) dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .i_lookup_valid     (i_lookup_valid),
        .i_lookup_addr      (i_lookup_addr),
        .i_lookup_pin       (i_lookup_pin),
        .o_lookup_hit       (o_lookup_hit),
        .o_lookup_way       (o_lookup_way),
        .o_lookup_data      (o_lookup_data),
        .o_lookup_dirty     (o_lookup_dirty),
        .o_lookup_verified  (o_lookup_verified),
        .o_lookup_pinned    (o_lookup_pinned),
        .i_fill_valid       (i_fill_valid),
        .i_fill_addr        (i_fill_addr),
        .i_fill_data        (i_fill_data),
        .i_fill_verified    (i_fill_verified),
        .i_fill_pin         (i_fill_pin),
        .o_fill_way         (o_fill_way),
        .o_evict_valid      (o_evict_valid),
        .o_evict_dirty      (o_evict_dirty),
        .o_evict_addr       (o_evict_addr),
        .o_evict_data       (o_evict_data),
        .i_update_valid     (i_update_valid),
        .i_update_addr      (i_update_addr),
        .i_update_data      (i_update_data),
        .i_update_dirty     (i_update_dirty),
        .i_update_data_en   (i_update_data_en),
        .o_update_hit       (o_update_hit),
        .o_update_way       (o_update_way),
        .i_unpin_valid      (i_unpin_valid),
        .i_unpin_addr       (i_unpin_addr),
        .o_unpin_hit        (o_unpin_hit),
        .o_unpin_way        (o_unpin_way),
        .i_flush_start      (i_flush_start),
        .i_flush_ready      (i_flush_ready),
        .o_flush_busy       (o_flush_busy),
        .o_flush_done       (o_flush_done),
        .o_flush_evict_valid(o_flush_evict_valid),
        .o_flush_evict_addr (o_flush_evict_addr),
        .o_flush_evict_data (o_flush_evict_data),
        .o_hit_cnt          (o_hit_cnt),
        .o_miss_cnt         (o_miss_cnt),
        .o_evict_cnt        (o_evict_cnt),
        .o_wb_cnt           (o_wb_cnt),
        .o_set_can_pin      (o_set_can_pin),
        .o_pin_violation    (o_pin_violation)
    );

    always #1.25 clk = ~clk; // 400 MHz chu kỳ 2.5 ns

    integer fd, r;
    reg [8*256-1:0] line;
    integer op;
    logic [63:0] addr;
    integer pin, dirty;
    integer exp_hit, exp_way;
    integer exp_evict_val, exp_evict_dirty;
    logic [63:0] exp_evict_addr;

    integer total_ops = 0;
    integer match_ops = 0;
    integer pin_invariant_violations = 0;

    initial begin
        clk              = 0;
        rst_n            = 0;
        i_lookup_valid   = 0;
        i_lookup_addr    = 0;
        i_lookup_pin     = 0;
        i_fill_valid     = 0;
        i_fill_addr      = 0;
        i_fill_data      = 0;
        i_fill_verified  = 1;
        i_fill_pin       = 0;
        i_update_valid   = 0;
        i_update_addr    = 0;
        i_update_data    = 0;
        i_update_dirty   = 0;
        i_update_data_en = 0;
        i_unpin_valid    = 0;
        i_unpin_addr     = 0;
        i_flush_start    = 0;
        i_flush_ready    = 0;

        #10;
        rst_n = 1;
        #10;

        $display("================================================================================");
        $display("  TB_QSHIELD_META_CACHE: VERIFYING 50,000 TEST VECTORS VS PYTHON MODEL");
        $display("================================================================================");

        fd = $fopen("build/meta_cache_vectors.txt", "r");
        if (fd == 0) begin
            $display("[FAIL] Cannot open build/meta_cache_vectors.txt");
            tb_check(1'b0, "Vector file opening failed");
            tb_report();
            $finish;
        end

        // Bỏ qua dòng tiêu đề comment
        r = $fgets(line, fd);

        while (!$feof(fd)) begin
            r = $fscanf(fd, "%d %h %d %d %d %d %d %d %h\n", 
                        op, addr, pin, dirty, exp_hit, exp_way, 
                        exp_evict_val, exp_evict_dirty, exp_evict_addr);
            if (r == 9) begin
                total_ops = total_ops + 1;
                @(negedge clk);
                case (op)
                    0: begin // LOOKUP
                        i_lookup_valid = 1'b1;
                        i_lookup_addr  = addr;
                        i_lookup_pin   = pin[0];
                    end
                    1: begin // FILL
                        i_fill_valid    = 1'b1;
                        i_fill_addr     = addr;
                        i_fill_data     = {8{addr}};
                        i_fill_verified = 1'b1;
                        i_fill_pin      = pin[0];
                    end
                    2: begin // UPDATE
                        i_update_valid   = 1'b1;
                        i_update_addr    = addr;
                        i_update_dirty   = dirty[0];
                        i_update_data_en = 1'b0;
                    end
                    3: begin // UNPIN
                        i_unpin_valid = 1'b1;
                        i_unpin_addr  = addr;
                    end
                endcase

                #0.5; // Đợi các đường tổ hợp giải mã ổn định
                case (op)
                    0: begin
                        if ((o_lookup_hit == exp_hit[0]) &&
                            (!exp_hit[0] || (o_lookup_way == exp_way[1:0]))) begin
                            match_ops = match_ops + 1;
                        end else if (total_ops <= 15) begin
                            $display("[MISMATCH] Op %0d (LOOKUP): addr=%h pin=%b exp_hit=%b got_hit=%b exp_way=%0d got_way=%0d",
                                     total_ops, addr, pin[0], exp_hit[0], o_lookup_hit, exp_way, o_lookup_way);
                        end
                    end
                    1: begin
                        if ((o_fill_way == exp_way[1:0]) &&
                            (o_evict_valid == exp_evict_val[0]) &&
                            (o_evict_dirty == exp_evict_dirty[0]) &&
                            (!exp_evict_val[0] || (o_evict_addr == exp_evict_addr))) begin
                            match_ops = match_ops + 1;
                        end else if (total_ops <= 15) begin
                            $display("[MISMATCH] Op %0d (FILL): addr=%h pin=%b exp_way=%0d got_way=%0d exp_ev=%b got_ev=%b exp_dirty=%b got_dirty=%b exp_ev_addr=%h got_ev_addr=%h",
                                     total_ops, addr, pin[0], exp_way, o_fill_way, exp_evict_val[0], o_evict_valid, exp_evict_dirty[0], o_evict_dirty, exp_evict_addr, o_evict_addr);
                        end
                    end
                    2: begin
                        if ((o_update_hit == exp_hit[0]) &&
                            (!exp_hit[0] || (o_update_way == exp_way[1:0]))) begin
                            match_ops = match_ops + 1;
                        end
                    end
                    3: begin
                        if ((o_unpin_hit == exp_hit[0]) &&
                            (!exp_hit[0] || (o_unpin_way == exp_way[1:0]))) begin
                            match_ops = match_ops + 1;
                        end
                    end
                endcase

                @(posedge clk);
                #0.1;
                i_lookup_valid = 1'b0;
                i_fill_valid   = 1'b0;
                i_update_valid = 1'b0;
                i_unpin_valid  = 1'b0;

                // Bất biến an toàn: kiểm tra không có set nào bị ghim hết cả 4 way
                for (int s = 0; s < 16; s++) begin
                    if (dut.set_pinned_cnt[s] >= 4) begin
                        pin_invariant_violations = pin_invariant_violations + 1;
                    end
                end
            end
        end
        $fclose(fd);

        $display("[INFO] Processed %0d operations (matches: %0d)", total_ops, match_ops);
        $display("[INFO] CSR Counters: hits=%0d misses=%0d evicts=%0d wb=%0d", 
                 o_hit_cnt, o_miss_cnt, o_evict_cnt, o_wb_cnt);

        // 1. Kiểm tra 50,000 vector khớp từng bước với Python
        tb_check(total_ops >= 50000 && match_ops == total_ops, "50000 cache operations match Python model bit-exact");

        // 2. Kiểm tra bất biến không bao giờ ghim hết way
        tb_check(pin_invariant_violations == 0, "Safety invariant: no set ever has all ways pinned");

        // 3. Kiểm tra các bộ đếm CSR
        tb_check(o_hit_cnt > 0 && o_miss_cnt > 0 && o_evict_cnt > 0 && o_wb_cnt > 0, "CSR event counters active and tracking");

        // 4. Kiểm tra cơ chế Flush tuần tự
        $display("[INFO] Testing sequential flush...");
        i_flush_start <= 1'b1;
        i_flush_ready <= 1'b1;
        @(posedge clk);
        i_flush_start <= 1'b0;
        @(posedge clk);

        while (o_flush_busy) begin
            @(posedge clk);
        end
        tb_check(o_flush_done == 1'b1, "Flush completed successfully (o_flush_done=1)");

        // Sau khi flush xong, kiểm tra không còn dòng dirty nào trong cache
        begin : check_dirty_blk
            integer dirty_remaining;
            dirty_remaining = 0;
            for (int i = 0; i < 64; i++) begin
                if (dut.line_valid[i] && dut.line_dirty[i]) begin
                    dirty_remaining = dirty_remaining + 1;
                end
            end
            tb_check(dirty_remaining == 0, "All dirty lines written back after flush");
        end

        tb_report();
        $finish;
    end
endmodule
