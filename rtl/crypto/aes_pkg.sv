//=============================================================================
// Package: aes_pkg
// Description: Common definitions, types, constants, and Galois Field operations
//              for AES-XTS (IEEE Std 1619) hardware pipeline.
// Standard:    SystemVerilog (IEEE 1800-2017)
//=============================================================================

`timescale 1ns / 1ps

package aes_pkg;

    // Data width constants
    localparam int AesBlockBits  = 128;
    localparam int AesBlockBytes = 16;
    localparam int Aes128KeyBits = 128;
    localparam int Aes256KeyBits = 256;
    localparam int Aes128Rounds   = 10;
    localparam int Aes256Rounds   = 14;

    // State array typedef (4x4 byte matrix)
    typedef logic [7:0] aes_state_t [4][4];

    // 128-bit block union/packing
    typedef union packed {
        logic [127:0] raw;
        logic [3:0][3:0][7:0] matrix; // [col][row][byte]
        logic [15:0][7:0] bytes;
    } aes_block_t;

    // Round Constants (Rcon) for Key Expansion (10 bytes packed)
    localparam logic [79:0] Rcon = 80'h361b8040201008040201;

    // Galois Field GF(2^8) xtime: multiplication by {02} modulo irreducible poly x^8 + x^4 + x^3 + x + 1 (0x11b)
    function automatic logic [7:0] gf256_xtime(input logic [7:0] b);
        return (b[7]) ? ({b[6:0], 1'b0} ^ 8'h1b) : {b[6:0], 1'b0};
    endfunction

    // Galois Field GF(2^8) multiplication by {03} = xtime(b) ^ b
    function automatic logic [7:0] gf256_mul03(input logic [7:0] b);
        return gf256_xtime(b) ^ b;
    endfunction

    // MixColumns Transformation for a 4-byte column
    function automatic logic [3:0][7:0] mix_single_column(input logic [3:0][7:0] col);
        logic [3:0][7:0] out_col;
        out_col[0] = gf256_xtime(col[0]) ^ gf256_mul03(col[1]) ^ col[2] ^ col[3];
        out_col[1] = col[0] ^ gf256_xtime(col[1]) ^ gf256_mul03(col[2]) ^ col[3];
        out_col[2] = col[0] ^ col[1] ^ gf256_xtime(col[2]) ^ gf256_mul03(col[3]);
        out_col[3] = gf256_mul03(col[0]) ^ col[1] ^ col[2] ^ gf256_xtime(col[3]);
        return out_col;
    endfunction

    // ShiftRows Transformation
    function automatic aes_block_t shift_rows(input aes_block_t in);
        aes_block_t out;
        // Row 0: no shift
        out.matrix[0][0] = in.matrix[0][0];
        out.matrix[1][0] = in.matrix[1][0];
        out.matrix[2][0] = in.matrix[2][0];
        out.matrix[3][0] = in.matrix[3][0];
        // Row 1: shift left by 1
        out.matrix[0][1] = in.matrix[1][1];
        out.matrix[1][1] = in.matrix[2][1];
        out.matrix[2][1] = in.matrix[3][1];
        out.matrix[3][1] = in.matrix[0][1];
        // Row 2: shift left by 2
        out.matrix[0][2] = in.matrix[2][2];
        out.matrix[1][2] = in.matrix[3][2];
        out.matrix[2][2] = in.matrix[0][2];
        out.matrix[3][2] = in.matrix[1][2];
        // Row 3: shift left by 3
        out.matrix[0][3] = in.matrix[3][3];
        out.matrix[1][3] = in.matrix[0][3];
        out.matrix[2][3] = in.matrix[1][3];
        out.matrix[3][3] = in.matrix[2][3];
        return out;
    endfunction

    // Galois Field GF(2^128) multiplication by alpha (x) for AES-XTS Tweak sequence:
    // P(x) = x^128 + x^7 + x^2 + x + 1 (Constant 0x87)
    function automatic logic [127:0] xts_mul_alpha(input logic [127:0] tweak);
        logic msb;
        msb = tweak[127];
        return {tweak[126:0], 1'b0} ^ (msb ? 128'h0000_0000_0000_0000_0000_0000_0000_0087 : 128'h0);
    endfunction

endpackage: aes_pkg
