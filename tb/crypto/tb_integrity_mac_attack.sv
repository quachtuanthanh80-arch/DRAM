// File:      tb_integrity_mac_attack.sv
// Chức năng: Red-team cho integrity_mac_gen: giả mạo MAC tuyến tính, tái định vị (địa chỉ), phát lại (counter) và bit dữ liệu không được bảo vệ.
`timescale 1ns / 1ps

module tb_integrity_mac_attack;

    logic         clk = 1'b0;
    always #1.25 clk = ~clk;

    logic         rst_n;
    logic         cfg_mac_en;
    logic [127:0] cfg_mac_key;
    logic         i_wr_valid;
    logic         o_wr_ready;
    logic [31:0]  i_wr_addr;
    logic [31:0]  i_wr_counter;
    logic [127:0] i_wr_data;
    logic         o_wr_mac_valid;
    logic [63:0]  o_wr_mac;
    logic         o_rd_ready;
    logic         i_rd_valid = 1'b0;
    logic [31:0]  i_rd_addr = '0;
    logic [31:0]  i_rd_counter = '0;
    logic [127:0] i_rd_data = '0;
    logic [63:0]  i_rd_stored_mac = '0;
    logic         o_rd_mac_valid;
    logic         o_integrity_violation;

    integrity_mac_gen #(
        .DATA_WIDTH (128),
        .ADDR_WIDTH (32),
        .MAC_WIDTH  (64)
    ) dut (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .cfg_mac_en            (cfg_mac_en),
        .cfg_mac_key           (cfg_mac_key),
        .i_wr_valid            (i_wr_valid),
        .o_wr_ready            (o_wr_ready),
        .i_wr_addr             (i_wr_addr),
        .i_wr_counter          (i_wr_counter),
        .i_wr_data             (i_wr_data),
        .o_wr_mac_valid        (o_wr_mac_valid),
        .o_wr_mac              (o_wr_mac),
        .i_rd_valid            (i_rd_valid),
        .o_rd_ready            (o_rd_ready),
        .i_rd_addr             (i_rd_addr),
        .i_rd_counter          (i_rd_counter),
        .i_rd_data             (i_rd_data),
        .i_rd_stored_mac       (i_rd_stored_mac),
        .o_rd_mac_valid        (o_rd_mac_valid),
        .o_integrity_violation (o_integrity_violation)
    );

    `include "tb_check.svh"

    task automatic mac_of(input logic [31:0] addr, input logic [31:0] ctr, input logic [127:0] data,
                          output logic [63:0] mac);
        @(negedge clk);
        while (!o_wr_ready) @(negedge clk);
        i_wr_addr    = addr;
        i_wr_counter = ctr;
        i_wr_data    = data;
        i_wr_valid   = 1'b1;
        @(negedge clk);
        i_wr_valid   = 1'b0;
        while (!o_wr_mac_valid) @(negedge clk);
        mac = o_wr_mac;
    endtask

    task automatic verify(input logic [31:0] a, input logic [31:0] c, input logic [127:0] d, input logic [63:0] m,
                          output bit viol);
        @(negedge clk);
        i_rd_addr = a; i_rd_counter = c; i_rd_data = d; i_rd_stored_mac = m; i_rd_valid = 1'b1;
        while (!o_rd_ready) @(negedge clk);
        @(negedge clk);
        i_rd_valid = 1'b0;
        while (!o_rd_mac_valid) @(negedge clk);
        viol = o_integrity_violation;
    endtask

    initial begin
        logic [63:0] m1, m2, m_pred;
        logic [127:0] d1, d2;

        rst_n        = 1'b0;
        cfg_mac_en   = 1'b1;
        cfg_mac_key  = 128'h2B7E_1516_28AE_D2A6_ABF7_1588_09CF_4F3C;
        i_wr_valid   = 1'b0;
        i_wr_addr    = '0;
        i_wr_counter = '0;
        i_wr_data    = '0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        d1 = 128'h0011_2233_4455_6677_8899_AABB_CCDD_EEFF;
        d2 = 128'hDEAD_BEEF_0000_0000_1234_5678_9ABC_DEF0;

        mac_of(32'h0000_1000, 32'd7, d1, m1);
        mac_of(32'h0000_1000, 32'd7, d2, m2);
        tb_check(m1 != m2, "MAC depends on data (sanity)");

        // Một MAC an toàn không thể dự đoán từ một cặp (dữ liệu, MAC) đã biết mà không có khóa.
        m_pred = m1 ^ d1[63:0] ^ d2[63:0];
        tb_check(m2 != m_pred, $sformatf("Linear forgery: MAC(d2)=%h predicted without key as %h", m2, m_pred));
        // Tham chiếu độc lập: cryptography.hazmat CMAC(AES-128) trên data||addr||ctr||0^64, cắt 64 bit trái
        tb_check(m1 === 64'h70a2_8e32_2c3d_b0e6, $sformatf("Bit-exact AES-CMAC (RFC 4493) vs Python reference: %h", m1));

        mac_of(32'h0000_2000, 32'd7, d1, m2);
        tb_check(m1 != m2, "Relocation: same data at another address must give a different MAC");

        mac_of(32'h0000_1000, 32'd8, d1, m2);
        tb_check(m1 != m2, "Replay: same data with another write counter must give a different MAC");

        mac_of(32'h0000_1000, 32'd7, d1 ^ (128'h1 << 100), m2);
        tb_check(m1 != m2, "Coverage: flipping data bit 100 must change the MAC");

        // Chiều đọc: dữ liệu đúng không báo vi phạm; sửa dữ liệu, dời chỗ hoặc phát lại bộ đếm cũ phải bị phát hiện
        begin
            bit v;
            verify(32'h0000_1000, 32'd7, d1, m1, v);
            tb_check(!v, "Read check: untouched line verifies");
            verify(32'h0000_1000, 32'd7, d1 ^ 128'h1, m1, v);
            tb_check(v, "Read check: one flipped data bit is detected");
            verify(32'h0000_2000, 32'd7, d1, m1, v);
            tb_check(v, "Read check: line relocated to another address is detected");
            verify(32'h0000_1000, 32'd8, d1, m1, v);
            tb_check(v, "Read check: replayed (stale counter) line is detected");
        end

        tb_report();
        $finish;
    end

    initial begin
        #100_000;
        $display("[FAIL] Watchdog timeout");
        tb_report();
        $fatal(1);
    end

endmodule
