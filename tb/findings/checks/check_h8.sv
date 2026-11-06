// File: check_h8.sv
// Chức năng: Kiểm tra tái hiện finding H-8 (Minor=127 không tăng major counter trong khối CTR).

`timescale 1ns / 1ps

module check_h8;
    `include "tb_check.svh"

    logic clk = 0;
    logic rst_n;

    always #5 clk = ~clk;

    logic        i_lookup_valid;
    logic        i_lookup_is_write;
    logic [7:0]  i_lookup_key_id;
    logic [18:0] i_lookup_epoch_nonce;
    logic [33:0] i_lookup_addr;

    wire         o_lookup_valid;
    wire [127:0] o_ctr_blocks [4];
    wire [63:0]  o_major_ctr;
    wire [6:0]   o_minor_ctr;

    logic        i_commit_valid;
    logic [33:0] i_commit_addr;
    wire         o_major_roll_alert;
    wire [9:0]   o_major_roll_page;

    split_counter_table #(
        .ADDR_WIDTH      (34),
        .TABLE_DEPTH     (1024),
        .PAGE_ADDR_WIDTH (10),
        .MAJOR_WIDTH     (64),
        .MINOR_WIDTH     (7)
    ) dut (
        .clk                  (clk),
        .rst_n                (rst_n),
        .i_lookup_valid       (i_lookup_valid),
        .i_lookup_is_write    (i_lookup_is_write),
        .i_lookup_key_id      (i_lookup_key_id),
        .i_lookup_epoch_nonce (i_lookup_epoch_nonce),
        .i_lookup_addr        (i_lookup_addr),
        .o_lookup_valid       (o_lookup_valid),
        .o_ctr_blocks         (o_ctr_blocks),
        .o_major_ctr          (o_major_ctr),
        .o_minor_ctr          (o_minor_ctr),
        .i_commit_valid       (i_commit_valid),
        .i_commit_addr        (i_commit_addr),
        .o_major_roll_alert   (o_major_roll_alert),
        .o_major_roll_page    (o_major_roll_page)
    );

    initial begin
        rst_n                = 0;
        i_lookup_valid       = 0;
        i_lookup_is_write    = 0;
        i_lookup_key_id      = 8'h01;
        i_lookup_epoch_nonce = 19'h12345;
        i_lookup_addr        = 34'h0;
        i_commit_valid       = 0;
        i_commit_addr        = 34'h0;

        #20;
        rst_n = 1;
        #10;

        // Đúng 127 lần commit để đưa minor counter từ 0 lên 127
        @(posedge clk);
        i_commit_valid = 1;
        i_commit_addr  = 34'h0;
        repeat (126) @(posedge clk);
        @(posedge clk);
        i_commit_valid = 0;
        #1;

        // Thực hiện Write Pre-computation Lookup:
        // Do minor counter đang ở 127, giá trị ghi tiếp theo phải sang epoch mới (eff_minor = 0, major = cur_major + 1).
        // Nếu major không tăng mà giữ nguyên 0, khối CTR tạo ra sẽ trùng hoàn toàn với lần ghi đầu tiên (major=0, minor=0) -> Two-time pad collision!
        i_lookup_valid    = 1;
        i_lookup_is_write = 1;
        i_lookup_addr     = 34'h0;
        #1;

        // Kiểm tra H-8: Ở minor=127, major_ctr dùng cho khối CTR mã hoá phải là major + 1 (= 64'd1)
        tb_check(dut.cur_minor == 7'd127 && o_major_ctr == 64'd1, "H-8: Write lookup when minor=127 must advance major counter to prevent keystream collision");

        tb_report();
        $finish;
    end

endmodule
