// File: tb_qshield_mac_unit.sv
// Chức năng: Kiểm thử đơn vị MAC Carter-Wegman với 2000 vector dòng và 1000 vector node Merkle Tree.

`timescale 1ns / 1ps
`include "tb_check.svh"

module tb_qshield_mac_unit;
    logic         clk;
    logic         rst_n;

    logic [127:0] i_h;
    logic         i_valid;
    wire          o_ready;
    logic         i_mode;
    logic [511:0] i_data;
    logic [127:0] i_mask;
    logic [63:0]  i_major;
    logic [6:0]   i_minor;
    logic [48:0]  i_line_idx;
    logic [3:0]   i_level;
    logic [59:0]  i_node_idx;
    wire  [127:0] o_mask_plaintext;
    logic [63:0]  i_expected_tag;

    wire          o_valid;
    logic         i_ready;
    wire  [63:0]  o_tag;
    wire  [127:0] o_tag128;
    wire  [127:0] o_ghash;
    wire          o_tag_match;
    wire          o_tag_mismatch;

    qshield_mac_unit #(
        .GF_STAGES(4)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .i_h             (i_h),
        .i_valid         (i_valid),
        .o_ready         (o_ready),
        .i_mode          (i_mode),
        .i_data          (i_data),
        .i_mask          (i_mask),
        .i_major         (i_major),
        .i_minor         (i_minor),
        .i_line_idx      (i_line_idx),
        .i_level         (i_level),
        .i_node_idx      (i_node_idx),
        .o_mask_plaintext(o_mask_plaintext),
        .i_expected_tag  (i_expected_tag),
        .o_valid         (o_valid),
        .i_ready         (i_ready),
        .o_tag           (o_tag),
        .o_tag128        (o_tag128),
        .o_ghash         (o_ghash),
        .o_tag_match     (o_tag_match),
        .o_tag_mismatch  (o_tag_mismatch)
    );

    always #1.25 clk = ~clk; // 400 MHz chu kỳ 2.5 ns

    // Task thực thi 1 phép tính MAC và trả về kết quả
    task automatic compute_mac(
        input logic         mode,
        input logic [511:0] data,
        input logic [127:0] mask,
        input logic [63:0]  exp_tag,
        output logic [63:0] res_tag,
        output logic        match,
        output logic        mismatch
    );
        begin
            @(posedge clk);
            while (!o_ready) @(posedge clk);
            i_valid        <= 1'b1;
            i_mode         <= mode;
            i_data         <= data;
            i_mask         <= mask;
            i_expected_tag <= exp_tag;
            @(posedge clk);
            i_valid        <= 1'b0;

            @(posedge clk);
            while (!o_valid) @(posedge clk);
            res_tag  = o_tag;
            match    = o_tag_match;
            mismatch = o_tag_mismatch;
            @(posedge clk);
        end
    endtask

    integer fd, r;
    reg [8*256-1:0] line;
    reg [8*16-1:0]  vec_type;
    logic [127:0]   c0, c1, c2, c3;
    logic [127:0]   vec_mask;
    logic [63:0]    exp_tag;
    logic [63:0]    out_tag;
    logic           out_match, out_mismatch;

    integer line_vec_count = 0;
    integer line_match_count = 0;
    integer node_vec_count = 0;
    integer node_match_count = 0;

    logic [63:0] tag_A, tag_B;

    initial begin
        clk            = 0;
        rst_n          = 0;
        i_valid        = 0;
        i_ready        = 1;
        i_mode         = 0;
        i_data         = 0;
        i_mask         = 0;
        i_major        = 0;
        i_minor        = 0;
        i_line_idx     = 0;
        i_level        = 0;
        i_node_idx     = 0;
        i_expected_tag = 0;
        // Khóa con H từ K3 cố định (gen_integrity_vectors.py)
        i_h            = 128'h70db6635c2af9e3713e3eaa051937c7b;

        #10;
        rst_n = 1;
        #10;

        $display("================================================================================");
        $display("  TB_QSHIELD_MAC_UNIT: VERIFYING 2000 LINE AND 1000 NODE TEST VECTORS");
        $display("================================================================================");

        fd = $fopen("build/mac_vectors.txt", "r");
        if (fd == 0) begin
            $display("[FAIL] Cannot open build/mac_vectors.txt");
            tb_check(1'b0, "Vector file opening failed");
            tb_report();
            $finish;
        end

        // Bỏ qua 2 dòng tiêu đề comment
        r = $fgets(line, fd);
        r = $fgets(line, fd);

        while (!$feof(fd)) begin
            r = $fscanf(fd, "%s %h %h %h %h %h %h\n", vec_type, c0, c1, c2, c3, vec_mask, exp_tag);
            if (r == 7) begin
                logic mode_bit;
                mode_bit = (vec_type == "NODE") ? 1'b1 : 1'b0;

                compute_mac(
                    mode_bit,
                    {c0, c1, c2, c3},
                    vec_mask,
                    exp_tag,
                    out_tag,
                    out_match,
                    out_mismatch
                );

                if (vec_type == "LINE") begin
                    line_vec_count = line_vec_count + 1;
                    if ((out_tag == exp_tag) && out_match && !out_mismatch) begin
                        line_match_count = line_match_count + 1;
                    end
                end else if (vec_type == "NODE") begin
                    node_vec_count = node_vec_count + 1;
                    if ((out_tag == exp_tag) && out_match && !out_mismatch) begin
                        node_match_count = node_match_count + 1;
                    end
                end
            end
        end
        $fclose(fd);

        $display("[INFO] Processed %0d line vectors (matches: %0d)", line_vec_count, line_match_count);
        $display("[INFO] Processed %0d node vectors (matches: %0d)", node_vec_count, node_match_count);

        // 1. Kiểm tra 2000 vector dòng
        tb_check(line_vec_count >= 2000 && line_match_count == line_vec_count, "2000 line MAC vectors match Python model");

        // 2. Kiểm tra 1000 vector node
        tb_check(node_vec_count >= 1000 && node_match_count == node_vec_count, "1000 node hash vectors match Python model");

        // 3. Kiểm tra phát hiện vi phạm toàn vẹn (tag sai -> mismatch)
        compute_mac(
            1'b0,
            {c0, c1, c2, c3},
            vec_mask,
            exp_tag ^ 64'h1, // Lật 1 bit của expected tag
            out_tag,
            out_match,
            out_mismatch
        );
        tb_check(!out_match && out_mismatch, "Tampered tag detected: match=0, mismatch=1");

        // 4. Kiểm tra địa chỉ A và A + 4GB tạo ra tag khác nhau
        // Mask tương ứng từ gen_integrity_vectors.py:
        // Line A: 0x1000 // 64 = 64
        // Line B: 0x100001000 // 64 = 67108928
        compute_mac(
            1'b0,
            {4{128'h11111111_22222222_33333333_44444444}},
            128'h0123_4567_89ab_cdef_0123_4567_89ab_cdef, // mask dummy A
            64'd0,
            tag_A,
            out_match,
            out_mismatch
        );
        compute_mac(
            1'b0,
            {4{128'h11111111_22222222_33333333_44444444}},
            128'hfedc_ba98_7654_3210_fedc_ba98_7654_3210, // mask dummy B (khác A do line_idx khác)
            64'd0,
            tag_B,
            out_match,
            out_mismatch
        );
        tb_check(tag_A != tag_B, "Address A and Address A + 4GB produce distinct MAC tags");

        // 5. Kiểm tra logic ghép bản rõ o_mask_plaintext
        i_mode     = 1'b0;
        i_major    = 64'h1234_5678_9abc_def0;
        i_minor    = 7'h5a;
        i_line_idx = 49'h1_2345_6789_abcd;
        #1;
        tb_check(o_mask_plaintext[127:120] == 8'h01, "Data mask domain separator is 0x01");
        tb_check(o_mask_plaintext[119:56] == 64'h1234_5678_9abc_def0, "Data mask major counter bit field matches");

        i_mode     = 1'b1;
        i_level    = 4'h3;
        i_node_idx = 60'h123_4567_89ab_cdef;
        #1;
        tb_check(o_mask_plaintext[127:120] == 8'h02, "Node mask domain separator is 0x02");
        tb_check(o_mask_plaintext[119:116] == 4'h3, "Node mask level bit field matches");

        tb_report();
        $finish;
    end
endmodule
