// File: check_c2.sv
// Chức năng: Kiểm tra finding C-2: Tweak XTS được mã hoá bằng K2 qua qshield_xts_tweak_unit, loại bỏ tính malleable.

`timescale 1ns / 1ps

`include "../../rtl/crypto/qshield_xts_tweak_unit.sv"

module check_c2;
    `include "tb_check.svh"

    logic clk = 0;
    logic rst_n;
    always #2.5 clk = ~clk;

    localparam int NumRounds = 14;

    logic [127:0] k1_round_keys [NumRounds + 1];
    logic [15*128-1:0] k2_round_keys_flat;
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

    // Lõi mã hoá dữ liệu AES-XTS
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
        .round_keys (k1_round_keys),
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

    // Đơn vị sinh tweak chuẩn IEEE 1619 (AES256_K2 + nhân alpha)
    logic         tw_valid;
    wire          tw_ready;
    logic [127:0] tw_in;
    wire          tw_out_valid;
    wire  [127:0] tw_t0, tw_t1, tw_t2, tw_t3;

    qshield_xts_tweak_unit #(
        .MetaWidth(16)
    ) u_tweak_gen (
        .clk          (clk),
        .rst_n        (rst_n),
        .i_valid      (tw_valid),
        .o_ready      (tw_ready),
        .i_tweak      (tw_in),
        .i_round_keys (k2_round_keys_flat),
        .i_meta       (16'h0),
        .o_valid      (tw_out_valid),
        .i_ready      (1'b1),
        .o_tweak0     (tw_t0),
        .o_tweak1     (tw_t1),
        .o_tweak2     (tw_t2),
        .o_tweak3     (tw_t3),
        .o_meta       ()
    );

    logic [127:0] c1, c2;
    logic [127:0] p1, p2;
    logic [127:0] t1, t2;
    logic [127:0] enc_t1, enc_t2;

    initial begin
        rst_n      = 0;
        enc_enable = 1;
        valid_in   = 0;
        ready_out  = 1;
        data_in    = '0;
        tweak_in   = '0;
        meta_in    = '0;
        tw_valid   = 0;
        tw_in      = '0;

        // Khởi tạo khoá K1 (dữ liệu) và K2 (tweak) độc lập
        for (int i = 0; i <= NumRounds; i++) begin
            k1_round_keys[i] = 128'h00112233445566778899AABBCCDDEEFF ^ (128'(i) << 16);
            k2_round_keys_flat[i*128 +: 128] = 128'hFEDCBA9876543210FEDCBA9876543210 ^ (128'(i) << 24);
        end

        #20;
        rst_n = 1;
        #10;

        t1 = 128'h0000_0000_0000_0000_0000_0000_0000_0010;
        t2 = 128'h0000_0000_0000_0000_0000_0000_0000_0020;

        // 1. Mã hoá tweak T1 qua qshield_xts_tweak_unit (AES256_K2)
        @(posedge clk);
        tw_valid <= 1'b1;
        tw_in    <= t1;
        @(posedge clk);
        tw_valid <= 1'b0;
        while (!tw_out_valid) @(posedge clk);
        #1;
        enc_t1 = tw_t0;

        // 2. Mã hoá tweak T2 qua qshield_xts_tweak_unit (AES256_K2)
        @(posedge clk);
        tw_valid <= 1'b1;
        tw_in    <= t2;
        @(posedge clk);
        tw_valid <= 1'b0;
        while (!tw_out_valid) @(posedge clk);
        #1;
        enc_t2 = tw_t0;

        // Khối 1: Bản rõ P1 tại địa chỉ T1 mã hoá bằng tweak enc_t1
        p1 = 128'h0123_4567_89AB_CDEF_FEDC_BA98_7654_3210;

        @(posedge clk);
        valid_in <= 1'b1;
        data_in  <= p1;
        tweak_in <= enc_t1;
        meta_in  <= 16'hA1;
        @(posedge clk);
        valid_in <= 1'b0;

        while (!(valid_out && meta_out == 16'hA1)) @(posedge clk);
        #1;
        c1 = data_out;
        @(posedge clk);

        // Khối 2: Kẻ tấn công chọn P2 = P1 ^ (T1 ^ T2) theo hiệu địa chỉ công khai thô
        // Nhưng vì Tweak thực tế là AES_K2(T1) và AES_K2(T2) độc lập, hiệu bản mã C1 ^ C2
        // sẽ không bao giờ bằng T1 ^ T2 -> Không còn tính malleable!
        p2 = p1 ^ (t1 ^ t2);

        @(posedge clk);
        valid_in <= 1'b1;
        data_in  <= p2;
        tweak_in <= enc_t2;
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
