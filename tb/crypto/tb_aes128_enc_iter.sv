// File:      tb_aes128_enc_iter.sv
// Chức năng: Kiểm tra lõi AES-128 với vector FIPS-197 C.1 và 64 vector ngẫu nhiên sinh bằng thư viện cryptography (Python).
`timescale 1ns / 1ps

module tb_aes128_enc_iter;
    `include "tb_check.svh"

    logic clk = 0, rst_n = 0;
    always #1.25 clk = ~clk;
    logic         start = 0, busy, done;
    logic [127:0] key, pt, ct;

    aes128_enc_iter dut (.clk(clk), .rst_n(rst_n), .i_start(start), .i_key(key), .i_pt(pt), .o_busy(busy), .o_done(done), .o_ct(ct));

    initial begin
        int fd, n, bad, lat;
        logic [127:0] k, p, e;
        repeat (3) @(posedge clk);
        rst_n = 1;
        fd = $fopen("tb/crypto/aes128_kat.txt", "r");
        if (fd == 0) fd = $fopen("../../../tb/crypto/aes128_kat.txt", "r");
        n = 0; bad = 0; lat = 0;
        while ($fscanf(fd, "%h %h %h\n", k, p, e) == 3) begin
            @(negedge clk);
            key = k; pt = p; start = 1;
            @(negedge clk);
            start = 0;
            lat = 1;
            while (!done) begin @(negedge clk); lat++; end
            if (ct !== e) begin
                bad++;
                if (bad <= 3) $display("  [DIAG] key %h pt %h: got %h expected %h", k, p, ct, e);
            end
            if (n == 0) tb_check(ct === e, $sformatf("FIPS-197 C.1: AES-128(000102..0f, 00112233..ff) = %h", ct));
            n++;
        end
        $fclose(fd);
        tb_check(n == 65 && bad == 0, $sformatf("%0d/%0d vectors match the Python cryptography reference (%0d bad)", n - bad, n, bad));
        $display("  [PERF] latency %0d cycles per block", lat);
        tb_report();
        $finish;
    end
endmodule
