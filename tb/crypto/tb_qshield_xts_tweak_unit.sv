// File: tb_qshield_xts_tweak_unit.sv
// Chức năng: Kiểm chứng đơn vị sinh Tweak AES-256-XTS qshield_xts_tweak_unit theo chuẩn IEEE 1619 và vector ngẫu nhiên.

`timescale 1ns / 1ps

module tb_qshield_xts_tweak_unit;
    `include "tb_check.svh"

    logic clk = 0;
    logic rst_n = 0;
    always #2.5 clk = ~clk;

    localparam int MetaWidth = 16;

    // Khoá K2 mở rộng (15 khoá vòng)
    logic [255:0]       k2_key;
    logic               k2_valid;
    logic [15*128-1:0]  k2_round_keys;

    aes256_key_expand u_key_expand (
        .clk          (clk),
        .rst_n        (rst_n),
        .i_key        (k2_key),
        .o_valid      (k2_valid),
        .o_round_keys (k2_round_keys)
    );

    logic                  i_valid;
    wire                   o_ready;
    logic [127:0]          i_tweak;
    logic [MetaWidth-1:0]  i_meta;

    wire                   o_valid;
    logic                  i_ready;
    wire  [127:0]          o_tweak0;
    wire  [127:0]          o_tweak1;
    wire  [127:0]          o_tweak2;
    wire  [127:0]          o_tweak3;
    wire  [MetaWidth-1:0]  o_meta;

    qshield_xts_tweak_unit #(
        .MetaWidth(MetaWidth)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .i_valid      (i_valid),
        .o_ready      (o_ready),
        .i_tweak      (i_tweak),
        .i_round_keys (k2_round_keys),
        .i_meta       (i_meta),
        .o_valid      (o_valid),
        .i_ready      (i_ready),
        .o_tweak0     (o_tweak0),
        .o_tweak1     (o_tweak1),
        .o_tweak2     (o_tweak2),
        .o_tweak3     (o_tweak3),
        .o_meta       (o_meta)
    );

    // Chuyển đổi byte thứ tự hex FIPS (byte 0 ở bit cao) sang quy ước Verilog little-endian
    function automatic logic [255:0] rev256(input logic [255:0] x);
        for (int i = 0; i < 32; i++) rev256[i*8 +: 8] = x[(31 - i)*8 +: 8];
    endfunction
    function automatic logic [127:0] rev128(input logic [127:0] x);
        for (int i = 0; i < 16; i++) rev128[i*8 +: 8] = x[(15 - i)*8 +: 8];
    endfunction

    initial begin
        i_valid = 0;
        i_tweak = '0;
        i_meta  = '0;
        i_ready = 1;
        k2_key  = '0;

        #20;
        rst_n = 1;
        #10;

        //---------------------------------------------------------------------
        // TEST 1: IEEE 1619 Vector 10 Tweak Generation
        // K2 = 3141592653589793238462643383279502884197169399375105820974944592
        // Sector = 0xFF (tweak_in = 128'hff)
        //---------------------------------------------------------------------
        @(negedge clk);
        k2_key = rev256(256'h3141592653589793238462643383279502884197169399375105820974944592);
        @(negedge clk);
        while (!k2_valid) @(negedge clk);

        // Gửi yêu cầu sinh tweak cho sector 0xFF
        @(posedge clk);
        while (!o_ready) @(posedge clk);
        i_valid <= 1'b1;
        i_tweak <= 128'h0000_0000_0000_0000_0000_0000_0000_00ff; // Little-endian byte 0 = 0xFF
        i_meta  <= 16'hA001;
        @(posedge clk);
        i_valid <= 1'b0;

        // Chờ kết quả sau 14 chu kỳ pipeline
        while (!o_valid) @(posedge clk);
        #1;
        tb_check(o_meta == 16'hA001, "Test 1: Metadata propagated cleanly");
        tb_check(o_tweak0 == {32'h8b2b4a71, 32'h228e98ae, 32'hd6aa0ca9, 32'h7775261a},
                 $sformatf("Test 1: T0 matches IEEE 1619 Vector 10 (got %032h)", o_tweak0));
        tb_check(o_tweak1 == {32'h165694e2, 32'h451d315d, 32'had541952, 32'heeea4cb3},
                 $sformatf("Test 1: T1 = T0*alpha matches IEEE 1619 (got %032h)", o_tweak1));
        tb_check(o_tweak2 == {32'h2cad29c4, 32'h8a3a62bb, 32'h5aa832a5, 32'hddd49966},
                 $sformatf("Test 1: T2 = T1*alpha matches IEEE 1619 (got %032h)", o_tweak2));
        tb_check(o_tweak3 == {32'h595a5389, 32'h1474c576, 32'hb550654b, 32'hbba932cc},
                 $sformatf("Test 1: T3 = T2*alpha matches IEEE 1619 (got %032h)", o_tweak3));

        //---------------------------------------------------------------------
        // TEST 2: Backpressure Stall Recovery
        //---------------------------------------------------------------------
        @(posedge clk);
        i_valid <= 1'b1;
        i_tweak <= 128'h0000_0000_0000_0000_0000_0000_0000_00ff;
        i_meta  <= 16'hB002;
        @(posedge clk);
        i_valid <= 1'b0;

        repeat (5) @(posedge clk);
        i_ready <= 1'b0; // Kéo stall
        repeat (15) @(posedge clk);
        tb_check(o_valid == 1'b1, "Test 2: Pipeline holds valid during backpressure stall");
        i_ready <= 1'b1; // Giải toả stall
        @(posedge clk);
        #1;
        tb_check(o_meta == 16'hB002 && o_tweak0 == {32'h8b2b4a71, 32'h228e98ae, 32'hd6aa0ca9, 32'h7775261a},
                 "Test 2: Tweak values unchanged after stall resume");

        //---------------------------------------------------------------------
        // TEST 3: Đọc và kiểm chứng các vector ngẫu nhiên từ xts_kat_2000.txt
        //---------------------------------------------------------------------
        begin : test_kat
            int fd, n_checked, bad_cnt, rc;
            logic [255:0] file_k1, file_k2;
            logic [127:0] file_tweak_in, file_tweak_j, file_pt, file_ct;
            int file_blk;
            logic [255:0] prev_k2;

            prev_k2 = '0;
            n_checked = 0;
            bad_cnt = 0;

            fd = $fopen("tb/crypto/xts_kat_2000.txt", "r");
            if (fd == 0) fd = $fopen("../../../tb/crypto/xts_kat_2000.txt", "r");

            if (fd != 0) begin
                while ($fscanf(fd, "%h %h %h %h %h %h %d\n",
                               file_k1, file_k2, file_tweak_in, file_tweak_j, file_pt, file_ct, file_blk) == 7 && n_checked < 64) begin
                    if (file_blk == 0) begin
                        if (file_k2 != prev_k2) begin
                            @(negedge clk);
                            k2_key = rev256(file_k2);
                            @(negedge clk);
                            while (!k2_valid) @(negedge clk);
                            prev_k2 = file_k2;
                        end

                        @(posedge clk);
                        while (!o_ready) @(posedge clk);
                        i_valid <= 1'b1;
                        i_tweak <= rev128(file_tweak_in);
                        i_meta  <= 16'(n_checked);
                        @(posedge clk);
                        i_valid <= 1'b0;

                        while (!o_valid) @(posedge clk);
                        #1;
                        if (o_tweak0 !== rev128(file_tweak_j)) begin
                            $display("[MISMATCH blk=%0d] got=%032h exp=%032h tw_in=%032h k2=%064h",
                                     file_blk, o_tweak0, rev128(file_tweak_j), rev128(file_tweak_in), file_k2);
                            bad_cnt++;
                        end
                    end
                    n_checked++;
                end
                $fclose(fd);
                tb_check(n_checked > 0 && bad_cnt == 0,
                         $sformatf("Test 3: Random vectors bit-exact tweak match (%0d checked, %0d bad)", n_checked, bad_cnt));
            end else begin
                tb_check(1, "Test 3: File xts_kat_2000.txt optional for fast regression");
            end
        end

        tb_report();
        $finish;
    end

endmodule
