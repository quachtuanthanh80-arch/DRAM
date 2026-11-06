// File:      tb_aes256_key_expand.sv
// Chức năng: Kiểm tra AES-256 thật: mở rộng khoá FIPS-197 (A.3) và 14 tầng aes_round_pipe so với FIPS-197 C.3 và 64 vector Python cryptography.
`timescale 1ns / 1ps

module tb_aes256_key_expand;
    `include "tb_check.svh"

    logic clk = 0, rst_n = 0;
    always #1.25 clk = ~clk;

    logic [255:0] key = '0;
    logic         kvalid;
    logic [15*128-1:0] rk_flat;
    logic [127:0]      rk [15];
    aes256_key_expand u_kx (.clk(clk), .rst_n(rst_n), .i_key(key), .o_valid(kvalid), .o_round_keys(rk_flat));
    always_comb for (int i = 0; i < 15; i++) rk[i] = rk_flat[i*128 +: 128];

    // 14 vòng thật của dự án (aes_round_pipe), luồng đơn giản: valid đi kèm dữ liệu
    logic         v  [15];
    logic [127:0] st [15];
    logic [127:0] pt = '0;
    logic         pt_valid = 0;
    assign v[0]  = pt_valid;
    assign st[0] = pt ^ rk[0];
    genvar r;
    generate
    for (r = 1; r <= 14; r++) begin : g_round
        localparam bit IsFinal = (r == 14);
        aes_round_pipe u_round (
            .clk(clk), .rst_n(rst_n), .in_valid(v[r-1]), .in_ready(), .is_final_round(IsFinal),
            .state_in(st[r-1]), .round_key(rk[r]), .out_valid(v[r]), .out_ready(1'b1), .state_out(st[r])
        );
    end
    endgenerate

    // Chuỗi hex FIPS (byte 0 đứng đầu) <-> quy ước RTL (byte i ở bit [8i+7:8i])
    function automatic logic [255:0] rev256(input logic [255:0] x);
        for (int i = 0; i < 32; i++) rev256[i*8 +: 8] = x[(31 - i)*8 +: 8];
    endfunction
    function automatic logic [127:0] rev128(input logic [127:0] x);
        for (int i = 0; i < 16; i++) rev128[i*8 +: 8] = x[(15 - i)*8 +: 8];
    endfunction

    task automatic encrypt(input logic [255:0] k_fips, input logic [127:0] p_fips, output logic [127:0] c_fips);
        @(negedge clk);
        key = rev256(k_fips);
        @(negedge clk);
        while (!kvalid) @(negedge clk);
        pt = rev128(p_fips);
        pt_valid = 1;
        @(negedge clk);
        pt_valid = 0;
        while (!v[14]) @(negedge clk);
        c_fips = rev128(st[14]);
    endtask

    initial begin
        int fd, n, bad;
        logic [255:0] k;
        logic [127:0] p, e, c;
        repeat (3) @(posedge clk);
        rst_n = 1;

        // FIPS-197 A.3: w[8] = 0x9ba35411 và w[59] = 0x706c631e cho khoá 603deb10...0914dff4
        @(negedge clk);
        key = rev256(256'h603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4);
        @(negedge clk);
        while (!kvalid) @(negedge clk);
        begin
            logic [127:0] rk2, rk14;
            rk2  = rev128(rk[2]);
            rk14 = rev128(rk[14]);
            tb_check(rk2[127:96] == 32'h9ba35411 && rk14[31:0] == 32'h706c631e,
                     $sformatf("FIPS-197 A.3 key expansion: w[8]=%h w[59]=%h", rk2[127:96], rk14[31:0]));
        end

        fd = $fopen("tb/crypto/aes256_kat.txt", "r");
        if (fd == 0) fd = $fopen("../../../tb/crypto/aes256_kat.txt", "r");
        n = 0;
        bad = 0;
        while ($fscanf(fd, "%h %h %h\n", k, p, e) == 3) begin
            encrypt(k, p, c);
            if (n == 0) tb_check(c === e, $sformatf("FIPS-197 C.3 AES-256: got %h expected %h", c, e));
            if (c !== e) bad++;
            n++;
        end
        $fclose(fd);
        tb_check(n == 65 && bad == 0, $sformatf("AES-256 vs Python cryptography: %0d/%0d vectors match", n - bad, n));

        // Đổi khoá: o_valid phải hạ trong lúc tính lại (không dùng khoá vòng dở dang)
        @(negedge clk);
        key = ~key;
        @(negedge clk);
        @(negedge clk);
        tb_check(!kvalid, "Round keys are flagged invalid while the schedule is being recomputed");
        tb_report();
        $finish;
    end
endmodule
