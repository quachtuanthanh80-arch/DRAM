// File: tb_qshield_meta_layout.sv
// Chức năng: Testbench xác minh ánh xạ metadata và Bonsai Merkle Tree so với mô hình tham chiếu Python.

`timescale 1ns / 1ps

module tb_qshield_meta_layout;
    `include "tb_check.svh"

    logic [63:0] i_addr;
    wire  [63:0] o_line_idx;
    wire  [63:0] o_cb_addr;
    wire  [5:0]  o_cb_slot;
    wire  [63:0] o_ml_addr;
    wire  [2:0]  o_ml_slot;
    wire         o_is_prot;
    wire         o_is_meta;

    logic [3:0]  i_tn_level;
    logic [31:0] i_tn_index;
    wire  [63:0] o_tn_addr;
    wire  [2:0]  o_tn_slot;

    // Khởi tạo module DUT với tham số mặc định (64 MiB = 1048576 lines)
    qshield_meta_layout #(
        .PROT_BASE  (64'h0000_0000_0000_0000),
        .PROT_LINES (64'd1048576),
        .TREE_ARITY (8)
    ) dut (
        .i_addr     (i_addr),
        .o_line_idx (o_line_idx),
        .o_cb_addr  (o_cb_addr),
        .o_cb_slot  (o_cb_slot),
        .o_ml_addr  (o_ml_addr),
        .o_ml_slot  (o_ml_slot),
        .o_is_prot  (o_is_prot),
        .o_is_meta  (o_is_meta),
        .i_tn_level (i_tn_level),
        .i_tn_index (i_tn_index),
        .o_tn_addr  (o_tn_addr),
        .o_tn_slot  (o_tn_slot)
    );

    integer fd;
    integer r;
    reg [8*256-1:0] line;
    logic [63:0] exp_line_idx;
    logic [63:0] exp_addr;
    logic [63:0] exp_cb_addr;
    logic [5:0]  exp_cb_slot;
    logic [63:0] exp_ml_addr;
    logic [2:0]  exp_ml_slot;
    integer vector_count = 0;
    integer match_count = 0;

    initial begin
        $display("================================================================================");
        $display("  TB_QSHIELD_META_LAYOUT: VERIFYING 10,000 VECTORS VS PYTHON MODEL");
        $display("================================================================================");

        // 1. Kiểm tra 10,000 vector từ file do gen_integrity_vectors.py sinh ra
        fd = $fopen("build/meta_layout_vectors.txt", "r");
        if (fd == 0) begin
            $display("[FAIL] Cannot open build/meta_layout_vectors.txt");
            tb_check(1'b0, "Vector file opening failed");
            tb_report();
            $finish;
        end

        // Bỏ qua dòng comment đầu tiên
        r = $fgets(line, fd);

        while (!$feof(fd)) begin
            r = $fscanf(fd, "%h %h %h %h %h %h\n", exp_line_idx, exp_addr, exp_cb_addr, exp_cb_slot, exp_ml_addr, exp_ml_slot);
            if (r == 6) begin
                i_addr = exp_addr;
                #1;
                if ((o_line_idx == exp_line_idx) &&
                    (o_cb_addr == exp_cb_addr) &&
                    (o_cb_slot == exp_cb_slot) &&
                    (o_ml_addr == exp_ml_addr) &&
                    (o_ml_slot == exp_ml_slot) &&
                    (o_is_prot == 1'b1) &&
                    (o_is_meta == 1'b0)) begin
                    match_count = match_count + 1;
                end
                vector_count = vector_count + 1;
            end
        end
        $fclose(fd);

        $display("[INFO] Verified %0d / %0d vectors against reference model.", match_count, vector_count);
        tb_check(vector_count >= 10000 && match_count == vector_count, "All 10,000+ layout vectors match reference model bit-exact");

        // 2. Kiểm tra các điều kiện biên: ngoài vùng bảo vệ & bên trong vùng metadata
        i_addr = 64'h0000_0000_0400_0000; // Metadata Base
        #1;
        tb_check(o_is_prot == 1'b0 && o_is_meta == 1'b1, "Metadata base correctly identified as metadata and not protected");

        i_addr = 64'h0000_0000_0492_4900; // Ngay sau Metadata End
        #1;
        tb_check(o_is_prot == 1'b0 && o_is_meta == 1'b0, "Address beyond metadata correctly identified as unmapped");

        // 3. Kiểm tra địa chỉ node cây Bonsai Merkle Tree cho từng cấp
        // Level 1: Base = 0x04900000, Node 0 -> 0x04900000
        i_tn_level = 4'd1; i_tn_index = 32'd0; #1;
        tb_check(o_tn_addr == 64'h0000_0000_0490_0000 && o_tn_slot == 3'd0, "Tree Level 1 Node 0 address matches 0x04900000");

        // Level 1: Node 2047 -> Offset = 2047 * 64 = 0x1FFC0 -> 0x0491FFC0
        i_tn_level = 4'd1; i_tn_index = 32'd2047; #1;
        tb_check(o_tn_addr == 64'h0000_0000_0491_FFC0 && o_tn_slot == 3'd7, "Tree Level 1 Node 2047 matches 0x0491FFC0");

        // Level 2: Base = 0x04920000, Node 0 -> 0x04920000
        i_tn_level = 4'd2; i_tn_index = 32'd0; #1;
        tb_check(o_tn_addr == 64'h0000_0000_0492_0000 && o_tn_slot == 3'd0, "Tree Level 2 Node 0 matches 0x04920000");

        // Level 3: Base = 0x04924000, Node 0 -> 0x04924000
        i_tn_level = 4'd3; i_tn_index = 32'd0; #1;
        tb_check(o_tn_addr == 64'h0000_0000_0492_4000 && o_tn_slot == 3'd0, "Tree Level 3 Node 0 matches 0x04924000");

        // Level 4: Base = 0x04924800, Node 0 -> 0x04924800, Node 3 -> 0x049248C0
        i_tn_level = 4'd4; i_tn_index = 32'd3; #1;
        tb_check(o_tn_addr == 64'h0000_0000_0492_48C0 && o_tn_slot == 3'd3, "Tree Level 4 Node 3 matches 0x049248C0");

        tb_report();
        $finish;
    end

endmodule
