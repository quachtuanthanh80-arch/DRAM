// File: check_c2.sv
// Chức năng: Kiểm tra tái hiện finding C-2 (Tweak XTS không mã hoá bằng K2 làm bản mã bị malleable).

`timescale 1ns / 1ps

module check_c2;
    `include "tb_check.svh"

    logic clk = 0;
    logic rst_n;
    always #2.5 clk = ~clk;

    localparam int NumRounds = 14;

    logic [127:0] round_keys [NumRounds + 1];
    logic         enc_enable;
    logic         valid_in;
    wire          ready_in;
    logic [127:0] data_in;
    logic [127:0] tweak_in;
    logic [15:0]  meta_in;
    wire          valid_out;
    logic         ready_out;
    wire  [127:0] data_out;
    wire  [15:0]  meta_out;
    wire          lane_busy;

    aes_xts_lane #(
        .NumRounds (NumRounds),
        .DataWidth (128),
        .TweakWidth(128),
        .MetaWidth (16)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .enc_enable (enc_enable),
        .lane_busy  (lane_busy),
        .round_keys (round_keys),
        .valid_in   (valid_in),
        .ready_in   (ready_in),
        .data_in    (data_in),
        .tweak_in   (tweak_in),
        .meta_in    (meta_in),
        .valid_out  (valid_out),
        .ready_out  (ready_out),
        .data_out   (data_out),
        .meta_out   (meta_out)
    );

    logic [127:0] c1, c2;
    logic [127:0] p1, p2;
    logic [127:0] t1, t2;

    initial begin
        rst_n      = 0;
        enc_enable = 1;
        valid_in   = 0;
        ready_out  = 1;
        data_in    = '0;
        tweak_in   = '0;
        meta_in    = '0;

        for (int i = 0; i <= NumRounds; i++) begin
            round_keys[i] = 128'h00112233445566778899AABBCCDDEEFF ^ (128'(i) << 16);
        end

        #20;
        rst_n = 1;
        #10;

        // Khối 1: Bản rõ P1 tại địa chỉ T1
        t1 = 128'h0000_0000_0000_0000_0000_0000_0000_0010;
        p1 = 128'h0123_4567_89AB_CDEF_FEDC_BA98_7654_3210;

        @(posedge clk);
        valid_in <= 1'b1;
        data_in  <= p1;
        tweak_in <= t1;
        meta_in  <= 16'hA1;
        @(posedge clk);
        valid_in <= 1'b0;

        while (!(valid_out && meta_out == 16'hA1)) @(posedge clk);
        #1;
        c1 = data_out;
        @(posedge clk);

        // Khối 2: Bản rõ P2 = P1 ^ (T1 ^ T2) tại địa chỉ T2
        // Với chuẩn XTS-AES đúng, Tweak phải được mã hoá bởi khoá K2 độc lập: T = AES_K2(I). Khi đó T1 và T2 là
        // giả ngẫu nhiên, không tương quan tuyến tính.
        // Nhưng nếu Tweak là địa chỉ công khai thô không mã hoá, kẻ tấn công chọn P2 = P1 ^ (T1 ^ T2) sẽ làm
        // pre-whitening trùng nhau, dẫn đến bản mã C2 = C1 ^ (T1 ^ T2) -> Ciphertext Malleable hoàn toàn!
        t2 = 128'h0000_0000_0000_0000_0000_0000_0000_0020;
        p2 = p1 ^ (t1 ^ t2);

        @(posedge clk);
        valid_in <= 1'b1;
        data_in  <= p2;
        tweak_in <= t2;
        meta_in  <= 16'hB2;
        @(posedge clk);
        valid_in <= 1'b0;

        while (!(valid_out && meta_out == 16'hB2)) @(posedge clk);
        #1;
        c2 = data_out;
        @(posedge clk);

        // Check C-2: Bản mã XTS không được phép bị malleable theo hiệu địa chỉ
        tb_check((c1 ^ c2) != (t1 ^ t2), "C-2: XTS ciphertext must not be malleable via plaintext tweak");

        tb_report();
        $finish;
    end

endmodule
