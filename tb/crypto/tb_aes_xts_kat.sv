// File: tb_aes_xts_kat.sv
// Chức năng: Kiểm chứng KAT phần cứng RTL toàn diện 2048 khối AES-256-XTS chuẩn IEEE 1619 (Tweak, Mã hóa, Giải mã).

`timescale 1ns / 1ps

module tb_aes_xts_kat;
    import aes_pkg::*;
    `include "tb_check.svh"

    logic clk = 0;
    always #1.25 clk = ~clk;

    logic rst_n;

    // Keys
    logic [255:0] k1_key, k2_key;
    wire  [15*128-1:0] k1_round_keys_packed;
    wire  [15*128-1:0] k2_round_keys_packed;
    wire          k1_valid, k2_valid;

    logic [127:0] k1_round_keys_unpacked [15];
    always_comb begin
        for (int i = 0; i < 15; i++) begin
            k1_round_keys_unpacked[i] = k1_round_keys_packed[i*128 +: 128];
        end
    end

    // K1 Key Expander
    aes256_key_expand u_k1_expand (
        .clk          (clk),
        .rst_n        (rst_n),
        .i_key        (k1_key),
        .o_valid      (k1_valid),
        .o_round_keys (k1_round_keys_packed)
    );

    // K2 Key Expander
    aes256_key_expand u_k2_expand (
        .clk          (clk),
        .rst_n        (rst_n),
        .i_key        (k2_key),
        .o_valid      (k2_valid),
        .o_round_keys (k2_round_keys_packed)
    );

    // IEEE 1619 Tweak Generation Unit
    logic         tw_valid;
    wire          tw_ready;
    logic [127:0] tw_in;
    wire          tw_out_valid;
    wire  [127:0] o_tweak0, o_tweak1, o_tweak2, o_tweak3;

    qshield_xts_tweak_unit #(
        .MetaWidth(16)
    ) u_tweak_unit (
        .clk          (clk),
        .rst_n        (rst_n),
        .i_valid      (tw_valid),
        .o_ready      (tw_ready),
        .i_tweak      (tw_in),
        .i_round_keys (k2_round_keys_packed),
        .i_meta       (16'h0),
        .o_valid      (tw_out_valid),
        .i_ready      (1'b1),
        .o_tweak0     (o_tweak0),
        .o_tweak1     (o_tweak1),
        .o_tweak2     (o_tweak2),
        .o_tweak3     (o_tweak3),
        .o_meta       ()
    );

    // AES-256 Encryption Lane (aes_xts_lane)
    logic         enc_valid_in;
    wire          enc_ready_in;
    logic [127:0] enc_data_in;
    logic [127:0] enc_tweak_in;
    logic [15:0]  enc_meta_in;
    wire          enc_valid_out;
    wire  [127:0] enc_data_out;
    wire  [15:0]  enc_meta_out;

    aes_xts_lane #(
        .DataWidth(128),
        .TweakWidth(128),
        .MetaWidth(16),
        .NumRounds(14)
    ) u_enc_lane (
        .clk          (clk),
        .rst_n        (rst_n),
        .enc_enable   (1'b1),
        .lane_busy    (),
        .round_keys   (k1_round_keys_unpacked),
        .valid_in     (enc_valid_in),
        .ready_in     (enc_ready_in),
        .data_in      (enc_data_in),
        .tweak_in     (enc_tweak_in),
        .meta_in      (enc_meta_in),
        .valid_out    (enc_valid_out),
        .ready_out    (1'b1),
        .data_out     (enc_data_out),
        .meta_out     (enc_meta_out)
    );

    // AES-256 Decryption Pipeline (aes_inv_cipher_pipe)
    logic         dec_valid_in;
    wire          dec_ready_in;
    logic [127:0] dec_data_in;
    logic [15:0]  dec_meta_in;
    wire          dec_valid_out;
    wire  [127:0] dec_data_out;
    wire  [15:0]  dec_meta_out;

    aes_inv_cipher_pipe #(
        .DataWidth(128),
        .MetaWidth(16)
    ) u_dec_pipe (
        .clk          (clk),
        .rst_n        (rst_n),
        .in_valid     (dec_valid_in),
        .in_ready     (dec_ready_in),
        .data_in      (dec_data_in),
        .meta_in      (dec_meta_in),
        .round_keys   (k1_round_keys_packed),
        .out_valid    (dec_valid_out),
        .out_ready    (1'b1),
        .data_out     (dec_data_out),
        .meta_out     (dec_meta_out)
    );

    // Endianness converters
    function automatic logic [255:0] rev256(input logic [255:0] x);
        for (int i = 0; i < 32; i++) rev256[i*8 +: 8] = x[(31 - i)*8 +: 8];
    endfunction
    function automatic logic [127:0] rev128(input logic [127:0] x);
        for (int i = 0; i < 16; i++) rev128[i*8 +: 8] = x[(15 - i)*8 +: 8];
    endfunction

    initial begin
        int fd, total_blocks, tweak_errs, enc_errs, dec_errs;
        logic [255:0] prev_k1, prev_k2;
        logic [255:0] file_k1, file_k2;
        logic [127:0] file_tweak_in, file_tweak_j, file_pt, file_ct;
        int file_blk;
        int enc_received, dec_received;

        // Buffers for one sector (4 blocks)
        logic [127:0] sec_tweak_in;
        logic [127:0] sec_tweak_exp [4];
        logic [127:0] sec_pt [4];
        logic [127:0] sec_ct [4];
        logic [127:0] sec_tw_gen [4];
        logic [127:0] enc_result [4];
        logic [127:0] dec_result [4];

        rst_n = 0;
        k1_key = '0;
        k2_key = '0;
        tw_valid = 0;
        tw_in = '0;
        enc_valid_in = 0;
        enc_data_in = '0;
        enc_tweak_in = '0;
        enc_meta_in = '0;
        dec_valid_in = 0;
        dec_data_in = '0;
        dec_meta_in = '0;

        total_blocks = 0;
        tweak_errs = 0;
        enc_errs = 0;
        dec_errs = 0;
        prev_k1 = ~256'h0;
        prev_k2 = ~256'h0;

        #20;
        rst_n = 1;
        #10;

        $display("==========================================================================");
        $display("  Q-SHIELD RTL KAT VERIFICATION: 2048 AES-256-XTS BLOCKS (IEEE 1619)");
        $display("==========================================================================");

        fd = $fopen("tb/crypto/xts_kat_2000.txt", "r");
        if (fd == 0) fd = $fopen("../../../tb/crypto/xts_kat_2000.txt", "r");

        if (fd == 0) begin
            $display("[FATAL] Missing required KAT vector file: tb/crypto/xts_kat_2000.txt");
            tb_check(0, "File tb/crypto/xts_kat_2000.txt must exist for RTL KAT verification");
            tb_report();
            $finish;
        end

        while (!$feof(fd) && total_blocks < 2048) begin
            // Read 4 consecutive blocks for one 64-byte sector
            for (int b = 0; b < 4; b++) begin
                if ($fscanf(fd, "%h %h %h %h %h %h %d\n",
                            file_k1, file_k2, file_tweak_in, file_tweak_j, file_pt, file_ct, file_blk) == 7) begin
                    sec_tweak_in = rev128(file_tweak_in);
                    sec_tweak_exp[b] = rev128(file_tweak_j);
                    sec_pt[b] = rev128(file_pt);
                    sec_ct[b] = rev128(file_ct);
                end
            end

            // 1. Expand K1 and K2 if changed
            if (file_k1 != prev_k1 || file_k2 != prev_k2) begin
                @(negedge clk);
                k1_key = rev256(file_k1);
                k2_key = rev256(file_k2);
                @(negedge clk);
                while (!k1_valid || !k2_valid) @(negedge clk);
                prev_k1 = file_k1;
                prev_k2 = file_k2;
            end

            // 2. Generate tweaks T0..T3 via qshield_xts_tweak_unit
            @(posedge clk);
            while (!tw_ready) @(posedge clk);
            tw_valid <= 1'b1;
            tw_in    <= sec_tweak_in;
            @(posedge clk);
            tw_valid <= 1'b0;
            while (!tw_out_valid) @(posedge clk);
            #1;
            sec_tw_gen[0] = o_tweak0;
            sec_tw_gen[1] = o_tweak1;
            sec_tw_gen[2] = o_tweak2;
            sec_tw_gen[3] = o_tweak3;

            // 3. Compare tweaks against IEEE 1619 model
            for (int b = 0; b < 4; b++) begin
                if (sec_tw_gen[b] !== sec_tweak_exp[b]) begin
                    $display("[TWEAK MISMATCH] block=%0d got=%032h exp=%032h",
                             total_blocks + b, sec_tw_gen[b], sec_tweak_exp[b]);
                    tweak_errs++;
                end
            end

            // 4. Stream 4 blocks through AES-256 encryption pipeline (aes_xts_lane)
            for (int b = 0; b < 4; b++) begin
                @(posedge clk);
                while (!enc_ready_in) @(posedge clk);
                enc_valid_in <= 1'b1;
                enc_data_in  <= sec_pt[b];
                enc_tweak_in <= sec_tw_gen[b];
                enc_meta_in  <= 16'(b);
            end
            @(posedge clk);
            enc_valid_in <= 1'b0;

            enc_received = 0;
            while (enc_received < 4) begin
                @(posedge clk);
                if (enc_valid_out) begin
                    enc_result[enc_meta_out] = enc_data_out;
                    enc_received++;
                end
            end

            for (int b = 0; b < 4; b++) begin
                if (enc_result[b] !== sec_ct[b]) begin
                    $display("[ENC MISMATCH] block=%0d got=%032h exp=%032h",
                             total_blocks + b, enc_result[b], sec_ct[b]);
                    enc_errs++;
                end
            end

            // 5. Stream 4 blocks through AES-256 decryption pipeline (aes_inv_cipher_pipe)
            // Decryption input is (Ciphertext ^ Tweak), output is (Plaintext ^ Tweak)
            for (int b = 0; b < 4; b++) begin
                @(posedge clk);
                while (!dec_ready_in) @(posedge clk);
                dec_valid_in <= 1'b1;
                dec_data_in  <= sec_ct[b] ^ sec_tw_gen[b];
                dec_meta_in  <= 16'(b);
            end
            @(posedge clk);
            dec_valid_in <= 1'b0;

            dec_received = 0;
            while (dec_received < 4) begin
                @(posedge clk);
                if (dec_valid_out) begin
                    dec_result[dec_meta_out] = dec_data_out ^ sec_tw_gen[dec_meta_out];
                    dec_received++;
                end
            end

            for (int b = 0; b < 4; b++) begin
                if (dec_result[b] !== sec_pt[b]) begin
                    $display("[DEC MISMATCH] block=%0d got=%032h exp=%032h",
                             total_blocks + b, dec_result[b], sec_pt[b]);
                    dec_errs++;
                end
            end

            total_blocks += 4;
            if (total_blocks % 256 == 0) begin
                $display("[PROGRESS] Verified %0d/2048 blocks (tweak_errs=%0d enc_errs=%0d dec_errs=%0d)...",
                         total_blocks, tweak_errs, enc_errs, dec_errs);
            end
        end

        $fclose(fd);

        tb_check(total_blocks == 2048,
                 $sformatf("KAT: Total blocks processed matches expected 2048 (got %0d)", total_blocks));
        tb_check(tweak_errs == 0,
                 $sformatf("KAT: Tweak generation matches IEEE 1619 for all 2048 blocks (errors=%0d)", tweak_errs));
        tb_check(enc_errs == 0,
                 $sformatf("KAT: AES-256-XTS Encryption matches bit-for-bit across all 2048 blocks (errors=%0d)", enc_errs));
        tb_check(dec_errs == 0,
                 $sformatf("KAT: AES-256-XTS Decryption (InvCipher) matches bit-for-bit across all 2048 blocks (errors=%0d)", dec_errs));

        tb_report();
        $finish;
    end

endmodule
