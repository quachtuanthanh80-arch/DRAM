// File: tb_aes_inv_cipher_pipe.sv
// Chức năng: Kiểm chứng đường ống giải mã AES-256 aes_inv_cipher_pipe theo FIPS-197 C.3 và roundtrip với aes_round_pipe.

`timescale 1ns / 1ps

module tb_aes_inv_cipher_pipe;
    `include "tb_check.svh"

    logic clk = 0;
    logic rst_n = 0;
    always #2.5 clk = ~clk;

    localparam int MetaWidth = 16;

    // Khoá AES-256 mở rộng
    logic [255:0]       key;
    logic               kvalid;
    logic [15*128-1:0]  round_keys;
    logic [127:0]       rk [15];

    aes256_key_expand u_key_expand (
        .clk          (clk),
        .rst_n        (rst_n),
        .i_key        (key),
        .o_valid      (kvalid),
        .o_round_keys (round_keys)
    );
    always_comb for (int i = 0; i < 15; i++) rk[i] = round_keys[i*128 +: 128];

    // DUT: aes_inv_cipher_pipe
    logic                 inv_in_valid;
    wire                  inv_in_ready;
    logic [127:0]         inv_data_in;
    logic [MetaWidth-1:0] inv_meta_in;

    wire                  inv_out_valid;
    logic                 inv_out_ready;
    wire  [127:0]         inv_data_out;
    wire  [MetaWidth-1:0] inv_meta_out;

    aes_inv_cipher_pipe #(
        .DataWidth(128),
        .MetaWidth(MetaWidth)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .in_valid   (inv_in_valid),
        .in_ready   (inv_in_ready),
        .data_in    (inv_data_in),
        .meta_in    (inv_meta_in),
        .round_keys (round_keys),
        .out_valid  (inv_out_valid),
        .out_ready  (inv_out_ready),
        .data_out   (inv_data_out),
        .meta_out   (inv_meta_out)
    );

    // Forward 14-stage pipeline (for roundtrip verification)
    logic         fwd_v  [15];
    logic [127:0] fwd_st [15];
    logic [127:0] fwd_pt;
    logic         fwd_valid;
    assign fwd_v[0]  = fwd_valid;
    assign fwd_st[0] = fwd_pt ^ rk[0];

    genvar r;
    generate
        for (r = 1; r <= 14; r++) begin : g_fwd_rounds
            localparam bit IsFinal = (r == 14);
            aes_round_pipe u_fwd_round (
                .clk           (clk),
                .rst_n         (rst_n),
                .in_valid      (fwd_v[r-1]),
                .in_ready      (),
                .is_final_round(IsFinal),
                .state_in      (fwd_st[r-1]),
                .round_key     (rk[r]),
                .out_valid     (fwd_v[r]),
                .out_ready     (1'b1),
                .state_out     (fwd_st[r])
            );
        end
    endgenerate

    function automatic logic [255:0] rev256(input logic [255:0] x);
        for (int i = 0; i < 32; i++) rev256[i*8 +: 8] = x[(31 - i)*8 +: 8];
    endfunction
    function automatic logic [127:0] rev128(input logic [127:0] x);
        for (int i = 0; i < 16; i++) rev128[i*8 +: 8] = x[(15 - i)*8 +: 8];
    endfunction

    initial begin
        key           = '0;
        inv_in_valid  = 0;
        inv_data_in   = '0;
        inv_meta_in   = '0;
        inv_out_ready = 1;
        fwd_valid     = 0;
        fwd_pt        = '0;

        #20;
        rst_n = 1;
        #10;

        //---------------------------------------------------------------------
        // TEST 1: FIPS-197 C.3 AES-256 Decryption Known-Answer Test
        // Key: 000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f
        // Ciphertext: 8ea2b7ca516745bfeafc49904b496089
        // Plaintext : 00112233445566778899aabbccddeeff
        //---------------------------------------------------------------------
        @(negedge clk);
        key = rev256(256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f);
        @(negedge clk);
        while (!kvalid) @(negedge clk);

        @(posedge clk);
        while (!inv_in_ready) @(posedge clk);
        inv_in_valid <= 1'b1;
        inv_data_in  <= rev128(128'h8ea2b7ca516745bfeafc49904b496089);
        inv_meta_in  <= 16'hC003;
        @(posedge clk);
        inv_in_valid <= 1'b0;

        while (!inv_out_valid) @(posedge clk);
        #1;
        tb_check(inv_meta_out == 16'hC003, "Test 1: Metadata propagated cleanly");
        tb_check(rev128(inv_data_out) == 128'h00112233445566778899aabbccddeeff,
                 $sformatf("Test 1: FIPS-197 C.3 AES-256 decrypt matches (got %032h)", rev128(inv_data_out)));

        //---------------------------------------------------------------------
        // TEST 2: Backpressure Stall Recovery
        //---------------------------------------------------------------------
        @(posedge clk);
        inv_in_valid <= 1'b1;
        inv_data_in  <= rev128(128'h8ea2b7ca516745bfeafc49904b496089);
        inv_meta_in  <= 16'hD004;
        @(posedge clk);
        inv_in_valid <= 1'b0;

        repeat (5) @(posedge clk);
        inv_out_ready <= 1'b0; // Stall
        repeat (15) @(posedge clk);
        tb_check(inv_out_valid == 1'b1, "Test 2: Pipeline holds valid during stall");
        inv_out_ready <= 1'b1; // Resume
        @(posedge clk);
        #1;
        tb_check(inv_meta_out == 16'hD004 && rev128(inv_data_out) == 128'h00112233445566778899aabbccddeeff,
                 "Test 2: Decrypted plaintext preserved after stall resume");

        //---------------------------------------------------------------------
        // TEST 3: Roundtrip Verification across 10 random blocks
        // PT -> aes_round_pipe (14 rounds) -> CT -> aes_inv_cipher_pipe (14 rounds) -> PT' == PT
        //---------------------------------------------------------------------
        begin : test_rt
            int n_rt_ok;
            logic [127:0] test_pt [10];
            logic [127:0] test_ct [10];
            logic [127:0] test_dec[10];

            n_rt_ok = 0;

            for (int i = 0; i < 10; i++) begin
                test_pt[i] = {32'hA000_0000 ^ (i * 32'h1111_1111),
                              32'hB000_0000 ^ (i * 32'h2222_2222),
                              32'hC000_0000 ^ (i * 32'h3333_3333),
                              32'hD000_0000 ^ (i * 32'h4444_4444)};
            end

            // Forward encryption
            for (int i = 0; i < 10; i++) begin
                @(posedge clk);
                fwd_pt    <= test_pt[i];
                fwd_valid <= 1'b1;
                @(posedge clk);
                fwd_valid <= 1'b0;
                while (!fwd_v[14]) @(posedge clk);
                #1;
                test_ct[i] = fwd_st[14];
            end

            // Inverse decryption
            for (int i = 0; i < 10; i++) begin
                @(posedge clk);
                while (!inv_in_ready) @(posedge clk);
                inv_in_valid <= 1'b1;
                inv_data_in  <= test_ct[i];
                inv_meta_in  <= 16'(i);
                @(posedge clk);
                inv_in_valid <= 1'b0;

                while (!inv_out_valid) @(posedge clk);
                #1;
                test_dec[i] = inv_data_out;
                if (test_dec[i] === test_pt[i]) n_rt_ok++;
            end

            tb_check(n_rt_ok == 10,
                     $sformatf("Test 3: 10/10 blocks roundtrip encrypt-decrypt bit-exact match (%0d/10)", n_rt_ok));
        end

        tb_report();
        $finish;
    end

endmodule
