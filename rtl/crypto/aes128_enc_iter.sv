// File:      aes128_enc_iter.sv
// Chức năng: Mã hoá AES-128 (FIPS-197) lặp 1 vòng/chu kỳ, mở rộng khoá tại chỗ; dùng làm lõi cho AES-CMAC.
`timescale 1ns / 1ps

module aes128_enc_iter (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         i_start,
    input  logic [127:0] i_key,
    input  logic [127:0] i_pt,
    output logic         o_busy,
    output logic         o_done,     // xung 1 chu kỳ, o_ct hợp lệ cùng lúc và giữ tới lần start kế
    output logic [127:0] o_ct
);
    // Quy ước byte FIPS-197: byte 0 là bit [127:120]; trạng thái s[r][c] = byte (r + 4c)
    function automatic logic [7:0] byte_of(input logic [127:0] x, input int i);
        return x[127 - 8*i -: 8];
    endfunction

    function automatic logic [7:0] xtime(input logic [7:0] b);
        return {b[6:0], 1'b0} ^ (b[7] ? 8'h1b : 8'h00);
    endfunction

    logic [127:0] st, rk;
    logic [3:0]   rnd;

    // SubBytes cho trạng thái (16 S-box) và SubWord cho lịch khoá (4 S-box)
    logic [7:0] sb_in  [20];
    logic [7:0] sb_out [20];
    for (genvar k = 0; k < 20; k++) begin : g_sbox
        aes_sbox u_sbox (.in_byte(sb_in[k]), .out_byte(sb_out[k]));
    end

    logic [7:0]   rcon;
    logic [127:0] next_rk, round_out;
    always_comb begin
        logic [7:0] sh [16];
        logic [7:0] mc [16];
        logic [31:0] w0, w1, w2, w3, t;

        for (int i = 0; i < 16; i++) sb_in[i] = byte_of(st, i);
        // RotWord(w3) rồi SubWord
        sb_in[16] = rk[23:16];
        sb_in[17] = rk[15:8];
        sb_in[18] = rk[7:0];
        sb_in[19] = rk[31:24];

        case (rnd)
            4'd1: rcon = 8'h01;  4'd2: rcon = 8'h02;  4'd3: rcon = 8'h04;  4'd4: rcon = 8'h08;
            4'd5: rcon = 8'h10;  4'd6: rcon = 8'h20;  4'd7: rcon = 8'h40;  4'd8: rcon = 8'h80;
            4'd9: rcon = 8'h1b;  4'd10: rcon = 8'h36; default: rcon = 8'h00;
        endcase
        w0 = rk[127:96]; w1 = rk[95:64]; w2 = rk[63:32]; w3 = rk[31:0];
        t  = {sb_out[16] ^ rcon, sb_out[17], sb_out[18], sb_out[19]};
        w0 = w0 ^ t;
        w1 = w1 ^ w0;
        w2 = w2 ^ w1;
        w3 = w3 ^ w2;
        next_rk = {w0, w1, w2, w3};

        // ShiftRows: hàng r dịch trái r cột
        for (int c = 0; c < 4; c++)
            for (int r = 0; r < 4; r++)
                sh[r + 4*c] = sb_out[r + 4*((c + r) % 4)];
        // MixColumns (bỏ ở vòng cuối)
        for (int c = 0; c < 4; c++) begin
            logic [7:0] a0, a1, a2, a3;
            a0 = sh[4*c]; a1 = sh[4*c+1]; a2 = sh[4*c+2]; a3 = sh[4*c+3];
            if (rnd == 4'd10) begin
                mc[4*c] = a0; mc[4*c+1] = a1; mc[4*c+2] = a2; mc[4*c+3] = a3;
            end else begin
                mc[4*c]   = xtime(a0) ^ (xtime(a1) ^ a1) ^ a2 ^ a3;
                mc[4*c+1] = a0 ^ xtime(a1) ^ (xtime(a2) ^ a2) ^ a3;
                mc[4*c+2] = a0 ^ a1 ^ xtime(a2) ^ (xtime(a3) ^ a3);
                mc[4*c+3] = (xtime(a0) ^ a0) ^ a1 ^ a2 ^ xtime(a3);
            end
        end
        for (int i = 0; i < 16; i++) round_out[127 - 8*i -: 8] = mc[i] ^ byte_of(next_rk, i);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st     <= '0;
            rk     <= '0;
            rnd    <= '0;
            o_busy <= 1'b0;
            o_done <= 1'b0;
            o_ct   <= '0;
        end else begin
            o_done <= 1'b0;
            if (i_start && !o_busy) begin
                st     <= i_pt ^ i_key;    // AddRoundKey vòng 0
                rk     <= i_key;
                rnd    <= 4'd1;
                o_busy <= 1'b1;
            end else if (o_busy) begin
                st  <= round_out;
                rk  <= next_rk;
                rnd <= rnd + 1'b1;
                if (rnd == 4'd10) begin
                    o_busy <= 1'b0;
                    o_done <= 1'b1;
                    o_ct   <= round_out;
                end
            end
        end
    end
endmodule
