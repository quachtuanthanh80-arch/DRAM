// File: aes_inv_cipher_pipe.sv
// Chức năng: Đường ống giải mã AES-256 (InvCipher) 14 tầng FIPS-197 chuẩn xác, dùng cùng round keys theo thứ tự đảo.

`timescale 1ns / 1ps

//-----------------------------------------------------------------------------
// Module: aes_inv_sbox
// Cơ chế: Bảng tra thế ngược (Inverse S-Box) chuẩn NIST FIPS-197 Table 6.
//-----------------------------------------------------------------------------
module aes_inv_sbox (
    input  logic [7:0] in_byte,
    output logic [7:0] out_byte
);
    always_comb begin
        case (in_byte)
            8'h00: out_byte = 8'h52; 8'h01: out_byte = 8'h09; 8'h02: out_byte = 8'h6a; 8'h03: out_byte = 8'hd5;
            8'h04: out_byte = 8'h30; 8'h05: out_byte = 8'h36; 8'h06: out_byte = 8'ha5; 8'h07: out_byte = 8'h38;
            8'h08: out_byte = 8'hbf; 8'h09: out_byte = 8'h40; 8'h0a: out_byte = 8'ha3; 8'h0b: out_byte = 8'h9e;
            8'h0c: out_byte = 8'h81; 8'h0d: out_byte = 8'hf3; 8'h0e: out_byte = 8'hd7; 8'h0f: out_byte = 8'hfb;
            8'h10: out_byte = 8'h7c; 8'h11: out_byte = 8'he3; 8'h12: out_byte = 8'h39; 8'h13: out_byte = 8'h82;
            8'h14: out_byte = 8'h9b; 8'h15: out_byte = 8'h2f; 8'h16: out_byte = 8'hff; 8'h17: out_byte = 8'h87;
            8'h18: out_byte = 8'h34; 8'h19: out_byte = 8'h8e; 8'h1a: out_byte = 8'h43; 8'h1b: out_byte = 8'h44;
            8'h1c: out_byte = 8'hc4; 8'h1d: out_byte = 8'hde; 8'h1e: out_byte = 8'he9; 8'h1f: out_byte = 8'hcb;
            8'h20: out_byte = 8'h54; 8'h21: out_byte = 8'h7b; 8'h22: out_byte = 8'h94; 8'h23: out_byte = 8'h32;
            8'h24: out_byte = 8'ha6; 8'h25: out_byte = 8'hc2; 8'h26: out_byte = 8'h23; 8'h27: out_byte = 8'h3d;
            8'h28: out_byte = 8'hee; 8'h29: out_byte = 8'h4c; 8'h2a: out_byte = 8'h95; 8'h2b: out_byte = 8'h0b;
            8'h2c: out_byte = 8'h42; 8'h2d: out_byte = 8'hfa; 8'h2e: out_byte = 8'hc3; 8'h2f: out_byte = 8'h4e;
            8'h30: out_byte = 8'h08; 8'h31: out_byte = 8'h2e; 8'h32: out_byte = 8'ha1; 8'h33: out_byte = 8'h66;
            8'h34: out_byte = 8'h28; 8'h35: out_byte = 8'hd9; 8'h36: out_byte = 8'h24; 8'h37: out_byte = 8'hb2;
            8'h38: out_byte = 8'h76; 8'h39: out_byte = 8'h5b; 8'h3a: out_byte = 8'ha2; 8'h3b: out_byte = 8'h49;
            8'h3c: out_byte = 8'h6d; 8'h3d: out_byte = 8'h8b; 8'h3e: out_byte = 8'hd1; 8'h3f: out_byte = 8'h25;
            8'h40: out_byte = 8'h72; 8'h41: out_byte = 8'hf8; 8'h42: out_byte = 8'hf6; 8'h43: out_byte = 8'h64;
            8'h44: out_byte = 8'h86; 8'h45: out_byte = 8'h68; 8'h46: out_byte = 8'h98; 8'h47: out_byte = 8'h16;
            8'h48: out_byte = 8'hd4; 8'h49: out_byte = 8'ha4; 8'h4a: out_byte = 8'h5c; 8'h4b: out_byte = 8'hcc;
            8'h4c: out_byte = 8'h5d; 8'h4d: out_byte = 8'h65; 8'h4e: out_byte = 8'hb6; 8'h4f: out_byte = 8'h92;
            8'h50: out_byte = 8'h6c; 8'h51: out_byte = 8'h70; 8'h52: out_byte = 8'h48; 8'h53: out_byte = 8'h50;
            8'h54: out_byte = 8'hfd; 8'h55: out_byte = 8'hed; 8'h56: out_byte = 8'hb9; 8'h57: out_byte = 8'hda;
            8'h58: out_byte = 8'h5e; 8'h59: out_byte = 8'h15; 8'h5a: out_byte = 8'h46; 8'h5b: out_byte = 8'h57;
            8'h5c: out_byte = 8'ha7; 8'h5d: out_byte = 8'h8d; 8'h5e: out_byte = 8'h9d; 8'h5f: out_byte = 8'h84;
            8'h60: out_byte = 8'h90; 8'h61: out_byte = 8'hd8; 8'h62: out_byte = 8'hab; 8'h63: out_byte = 8'h00;
            8'h64: out_byte = 8'h8c; 8'h65: out_byte = 8'hbc; 8'h66: out_byte = 8'hd3; 8'h67: out_byte = 8'h0a;
            8'h68: out_byte = 8'hf7; 8'h69: out_byte = 8'he4; 8'h6a: out_byte = 8'h58; 8'h6b: out_byte = 8'h05;
            8'h6c: out_byte = 8'hb8; 8'h6d: out_byte = 8'hb3; 8'h6e: out_byte = 8'h45; 8'h6f: out_byte = 8'h06;
            8'h70: out_byte = 8'hd0; 8'h71: out_byte = 8'h2c; 8'h72: out_byte = 8'h1e; 8'h73: out_byte = 8'h8f;
            8'h74: out_byte = 8'hca; 8'h75: out_byte = 8'h3f; 8'h76: out_byte = 8'h0f; 8'h77: out_byte = 8'h02;
            8'h78: out_byte = 8'hc1; 8'h79: out_byte = 8'haf; 8'h7a: out_byte = 8'hbd; 8'h7b: out_byte = 8'h03;
            8'h7c: out_byte = 8'h01; 8'h7d: out_byte = 8'h13; 8'h7e: out_byte = 8'h8a; 8'h7f: out_byte = 8'h6b;
            8'h80: out_byte = 8'h3a; 8'h81: out_byte = 8'h91; 8'h82: out_byte = 8'h11; 8'h83: out_byte = 8'h41;
            8'h84: out_byte = 8'h4f; 8'h85: out_byte = 8'h67; 8'h86: out_byte = 8'hdc; 8'h87: out_byte = 8'hea;
            8'h88: out_byte = 8'h97; 8'h89: out_byte = 8'hf2; 8'h8a: out_byte = 8'hcf; 8'h8b: out_byte = 8'hce;
            8'h8c: out_byte = 8'hf0; 8'h8d: out_byte = 8'hb4; 8'h8e: out_byte = 8'he6; 8'h8f: out_byte = 8'h73;
            8'h90: out_byte = 8'h96; 8'h91: out_byte = 8'hac; 8'h92: out_byte = 8'h74; 8'h93: out_byte = 8'h22;
            8'h94: out_byte = 8'he7; 8'h95: out_byte = 8'had; 8'h96: out_byte = 8'h35; 8'h97: out_byte = 8'h85;
            8'h98: out_byte = 8'he2; 8'h99: out_byte = 8'hf9; 8'h9a: out_byte = 8'h37; 8'h9b: out_byte = 8'he8;
            8'h9c: out_byte = 8'h1c; 8'h9d: out_byte = 8'h75; 8'h9e: out_byte = 8'hdf; 8'h9f: out_byte = 8'h6e;
            8'ha0: out_byte = 8'h47; 8'ha1: out_byte = 8'hf1; 8'ha2: out_byte = 8'h1a; 8'ha3: out_byte = 8'h71;
            8'ha4: out_byte = 8'h1d; 8'ha5: out_byte = 8'h29; 8'ha6: out_byte = 8'hc5; 8'ha7: out_byte = 8'h89;
            8'ha8: out_byte = 8'h6f; 8'ha9: out_byte = 8'hb7; 8'haa: out_byte = 8'h62; 8'hab: out_byte = 8'h0e;
            8'hac: out_byte = 8'haa; 8'had: out_byte = 8'h18; 8'hae: out_byte = 8'hbe; 8'haf: out_byte = 8'h1b;
            8'hb0: out_byte = 8'hfc; 8'hb1: out_byte = 8'h56; 8'hb2: out_byte = 8'h3e; 8'hb3: out_byte = 8'h4b;
            8'hb4: out_byte = 8'hc6; 8'hb5: out_byte = 8'hd2; 8'hb6: out_byte = 8'h79; 8'hb7: out_byte = 8'h20;
            8'hb8: out_byte = 8'h9a; 8'hb9: out_byte = 8'hdb; 8'hba: out_byte = 8'hc0; 8'hbb: out_byte = 8'hfe;
            8'hbc: out_byte = 8'h78; 8'hbd: out_byte = 8'hcd; 8'hbe: out_byte = 8'h5a; 8'hbf: out_byte = 8'hf4;
            8'hc0: out_byte = 8'h1f; 8'hc1: out_byte = 8'hdd; 8'hc2: out_byte = 8'ha8; 8'hc3: out_byte = 8'h33;
            8'hc4: out_byte = 8'h88; 8'hc5: out_byte = 8'h07; 8'hc6: out_byte = 8'hc7; 8'hc7: out_byte = 8'h31;
            8'hc8: out_byte = 8'hb1; 8'hc9: out_byte = 8'h12; 8'hca: out_byte = 8'h10; 8'hcb: out_byte = 8'h59;
            8'hcc: out_byte = 8'h27; 8'hcd: out_byte = 8'h80; 8'hce: out_byte = 8'hec; 8'hcf: out_byte = 8'h5f;
            8'hd0: out_byte = 8'h60; 8'hd1: out_byte = 8'h51; 8'hd2: out_byte = 8'h7f; 8'hd3: out_byte = 8'ha9;
            8'hd4: out_byte = 8'h19; 8'hd5: out_byte = 8'hb5; 8'hd6: out_byte = 8'h4a; 8'hd7: out_byte = 8'h0d;
            8'hd8: out_byte = 8'h2d; 8'hd9: out_byte = 8'he5; 8'hda: out_byte = 8'h7a; 8'hdb: out_byte = 8'h9f;
            8'hdc: out_byte = 8'h93; 8'hdd: out_byte = 8'hc9; 8'hde: out_byte = 8'h9c; 8'hdf: out_byte = 8'hef;
            8'he0: out_byte = 8'ha0; 8'he1: out_byte = 8'he0; 8'he2: out_byte = 8'h3b; 8'he3: out_byte = 8'h4d;
            8'he4: out_byte = 8'hae; 8'he5: out_byte = 8'h2a; 8'he6: out_byte = 8'hf5; 8'he7: out_byte = 8'hb0;
            8'he8: out_byte = 8'hc8; 8'he9: out_byte = 8'heb; 8'hea: out_byte = 8'hbb; 8'heb: out_byte = 8'h3c;
            8'hec: out_byte = 8'h83; 8'hed: out_byte = 8'h53; 8'hee: out_byte = 8'h99; 8'hef: out_byte = 8'h61;
            8'hf0: out_byte = 8'h17; 8'hf1: out_byte = 8'h2b; 8'hf2: out_byte = 8'h04; 8'hf3: out_byte = 8'h7e;
            8'hf4: out_byte = 8'hba; 8'hf5: out_byte = 8'h77; 8'hf6: out_byte = 8'hd6; 8'hf7: out_byte = 8'h26;
            8'hf8: out_byte = 8'he1; 8'hf9: out_byte = 8'h69; 8'hfa: out_byte = 8'h14; 8'hfb: out_byte = 8'h63;
            8'hfc: out_byte = 8'h55; 8'hfd: out_byte = 8'h21; 8'hfe: out_byte = 8'h0c; 8'hff: out_byte = 8'h7d;
            default: out_byte = 8'h52;
        endcase
    end
endmodule

//-----------------------------------------------------------------------------
// Module: aes_inv_round_pipe
// Cơ chế: Một tầng đường ống InvCipher: InvShiftRows -> InvSubBytes -> AddRoundKey -> InvMixColumns.
// Mục đích: Thực thi một vòng giải mã AES độc lập với độ trễ 1 chu kỳ có bắt tay valid/ready.
//-----------------------------------------------------------------------------
module aes_inv_round_pipe (
    input  logic         clk,
    input  logic         rst_n,

    input  logic         in_valid,
    output logic         in_ready,
    input  logic         is_final_round,

    input  logic [127:0] state_in,
    input  logic [127:0] round_key,

    output logic         out_valid,
    input  logic         out_ready,
    output logic [127:0] state_out
);
    import aes_pkg::*;

    // 1. InvShiftRows: Dịch chuyển hàng ngược lại (hàng 1 sang phải 1, hàng 2 sang phải 2, hàng 3 sang phải 3)
    function automatic aes_block_t inv_shift_rows(input aes_block_t in);
        aes_block_t out;
        out.matrix[0][0] = in.matrix[0][0];
        out.matrix[1][0] = in.matrix[1][0];
        out.matrix[2][0] = in.matrix[2][0];
        out.matrix[3][0] = in.matrix[3][0];

        out.matrix[0][1] = in.matrix[3][1];
        out.matrix[1][1] = in.matrix[0][1];
        out.matrix[2][1] = in.matrix[1][1];
        out.matrix[3][1] = in.matrix[2][1];

        out.matrix[0][2] = in.matrix[2][2];
        out.matrix[1][2] = in.matrix[3][2];
        out.matrix[2][2] = in.matrix[0][2];
        out.matrix[3][2] = in.matrix[1][2];

        out.matrix[0][3] = in.matrix[1][3];
        out.matrix[1][3] = in.matrix[2][3];
        out.matrix[2][3] = in.matrix[3][3];
        out.matrix[3][3] = in.matrix[0][3];
        return out;
    endfunction

    aes_block_t inv_shifted;
    assign inv_shifted = inv_shift_rows(aes_block_t'(state_in));

    // 2. InvSubBytes: 16 hộp thế ngược song song
    logic [127:0] inv_sub_raw;
    genvar i;
    generate
        for (i = 0; i < 16; i++) begin : gen_inv_sbox
            aes_inv_sbox u_inv_sbox (
                .in_byte (inv_shifted.raw[i*8 +: 8]),
                .out_byte(inv_sub_raw[i*8 +: 8])
            );
        end
    endgenerate

    // 3. AddRoundKey: Cộng khoá vòng tương ứng
    logic [127:0] ark_state;
    assign ark_state = inv_sub_raw ^ round_key;

    // 4. InvMixColumns: Nhân ma trận trường GF(2^8) với các hệ số {0e, 0b, 0d, 09} (bỏ qua ở vòng cuối)
    function automatic logic [7:0] mul09(input logic [7:0] b);
        logic [7:0] x1, x2, x3;
        x1 = gf256_xtime(b);
        x2 = gf256_xtime(x1);
        x3 = gf256_xtime(x2);
        return x3 ^ b;
    endfunction

    function automatic logic [7:0] mul0b(input logic [7:0] b);
        logic [7:0] x1, x2, x3;
        x1 = gf256_xtime(b);
        x2 = gf256_xtime(x1);
        x3 = gf256_xtime(x2);
        return x3 ^ x1 ^ b;
    endfunction

    function automatic logic [7:0] mul0d(input logic [7:0] b);
        logic [7:0] x1, x2, x3;
        x1 = gf256_xtime(b);
        x2 = gf256_xtime(x1);
        x3 = gf256_xtime(x2);
        return x3 ^ x2 ^ b;
    endfunction

    function automatic logic [7:0] mul0e(input logic [7:0] b);
        logic [7:0] x1, x2, x3;
        x1 = gf256_xtime(b);
        x2 = gf256_xtime(x1);
        x3 = gf256_xtime(x2);
        return x3 ^ x2 ^ x1;
    endfunction

    function automatic logic [3:0][7:0] inv_mix_single_col(input logic [3:0][7:0] col);
        logic [3:0][7:0] out_col;
        out_col[0] = mul0e(col[0]) ^ mul0b(col[1]) ^ mul0d(col[2]) ^ mul09(col[3]);
        out_col[1] = mul09(col[0]) ^ mul0e(col[1]) ^ mul0b(col[2]) ^ mul0d(col[3]);
        out_col[2] = mul0d(col[0]) ^ mul09(col[1]) ^ mul0e(col[2]) ^ mul0b(col[3]);
        out_col[3] = mul0b(col[0]) ^ mul0d(col[1]) ^ mul09(col[2]) ^ mul0e(col[3]);
        return out_col;
    endfunction

    logic [127:0] round_result;
    aes_block_t ark_block;
    assign ark_block = aes_block_t'(ark_state);

    genvar c;
    generate
        for (c = 0; c < 4; c++) begin : gen_inv_mixcol
            assign round_result[c*32 +: 32] = is_final_round ?
                ark_block.matrix[c] :
                inv_mix_single_col(ark_block.matrix[c]);
        end
    endgenerate

    // 5. Thanh ghi đường ống chuẩn skid/ready-valid
    logic [127:0] state_reg;
    logic         valid_reg;

    assign in_ready = out_ready || !valid_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_reg <= 128'h0;
            valid_reg <= 1'b0;
        end else if (in_ready) begin
            valid_reg <= in_valid;
            if (in_valid) begin
                state_reg <= round_result;
            end
        end
    end

    assign out_valid = valid_reg;
    assign state_out = state_reg;

endmodule

//-----------------------------------------------------------------------------
// Module: aes_inv_cipher_pipe
// Cơ chế: Toàn bộ đường ống 14 tầng giải mã AES-256 (InvCipher FIPS-197 Algorithm 5).
// Rationale: Nhận 15 khoá vòng chuẩn từ aes256_key_expand, áp dụng theo thứ tự đảo:
//            Vòng khởi tạo AddRoundKey(RK14), sau đó 13 vòng InvRound(RK13..RK1),
//            và vòng cuối InvRoundFinal(RK0).
//-----------------------------------------------------------------------------
module aes_inv_cipher_pipe #(
    parameter int DataWidth = 128,
    parameter int MetaWidth = 16
) (
    input  logic                   clk,
    input  logic                   rst_n,

    // Giao diện đầu vào dữ liệu cần giải mã
    input  logic                   in_valid,
    output logic                   in_ready,
    input  logic [DataWidth-1:0]   data_in,
    input  logic [MetaWidth-1:0]   meta_in,

    // 15 khoá vòng (phẳng 1920 bit hoặc unpacked array)
    input  logic [15*128-1:0]      round_keys,

    // Giao diện đầu ra dữ liệu đã giải mã (bản rõ)
    output logic                   out_valid,
    input  logic                   out_ready,
    output logic [DataWidth-1:0]   data_out,
    output logic [MetaWidth-1:0]   meta_out
);

    // Mở gói khoá vòng (RK0 .. RK14)
    logic [127:0] rk [15];
    for (genvar k = 0; k < 15; k++) begin : g_unpack_rk
        assign rk[k] = round_keys[k*128 +: 128];
    end

    // Vòng khởi đầu: Initial AddRoundKey với RK14
    logic [127:0] initial_state;
    assign initial_state = data_in ^ rk[14];

    // Các tầng trung gian trong 14 vòng
    logic [127:0] stage_state [15];
    logic         stage_valid [15];
    logic         stage_ready [15];
    logic [MetaWidth-1:0] meta_pipe [1:14];

    assign stage_state[0] = initial_state;
    assign stage_valid[0] = in_valid;
    assign in_ready       = stage_ready[0];

    // Khởi tạo 14 tầng giải mã:
    // Vòng 1 dùng rk[13], vòng 2 dùng rk[12], ..., vòng 13 dùng rk[1], vòng 14 dùng rk[0]
    genvar r;
    generate
        for (r = 1; r <= 14; r++) begin : gen_inv_rounds
            localparam bit IsFinal = (r == 14);

            aes_inv_round_pipe u_inv_round (
                .clk           (clk),
                .rst_n         (rst_n),
                .in_valid      (stage_valid[r-1]),
                .in_ready      (stage_ready[r-1]),
                .is_final_round(IsFinal),
                .state_in      (stage_state[r-1]),
                .round_key     (rk[14 - r]),
                .out_valid     (stage_valid[r]),
                .out_ready     (stage_ready[r]),
                .state_out     (stage_state[r])
            );

            // Bắt nhịp luồng metadata cùng dữ liệu
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    meta_pipe[r] <= '0;
                end else if (stage_ready[r-1] && stage_valid[r-1]) begin
                    if (r == 1) begin
                        meta_pipe[r] <= meta_in;
                    end else begin
                        meta_pipe[r] <= meta_pipe[r-1];
                    end
                end
            end
        end
    endgenerate

    assign stage_ready[14] = out_ready;
    assign out_valid       = stage_valid[14];
    assign data_out        = stage_state[14];
    assign meta_out        = meta_pipe[14];

endmodule
