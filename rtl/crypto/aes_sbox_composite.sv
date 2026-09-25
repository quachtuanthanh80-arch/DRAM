//=============================================================================
// File:        aes_sbox_composite.sv
// Chức năng:   Hộp thế S-Box sử dụng đại số trường phức hợp GF(((2^2)^2)^2) diện tích nhỏ cho ASIC.
//=============================================================================
`timescale 1ns / 1ps

module aes_sbox_composite (
    input  logic [7:0] in_byte,
    output logic [7:0] out_byte
);

    // Step 1: Isomorphism mapping from GF(2^8) to GF((2^4)^2)
    logic [7:0] gamma;
    assign gamma[7] = in_byte[7] ^ in_byte[5];
    assign gamma[6] = in_byte[7] ^ in_byte[6] ^ in_byte[4] ^ in_byte[3] ^ in_byte[1];
    assign gamma[5] = in_byte[7] ^ in_byte[5] ^ in_byte[3] ^ in_byte[2];
    assign gamma[4] = in_byte[7] ^ in_byte[5] ^ in_byte[3] ^ in_byte[2] ^ in_byte[1];
    assign gamma[3] = in_byte[7] ^ in_byte[6] ^ in_byte[2] ^ in_byte[1];
    assign gamma[2] = in_byte[7] ^ in_byte[4] ^ in_byte[3] ^ in_byte[2] ^ in_byte[1];
    assign gamma[1] = in_byte[6] ^ in_byte[4] ^ in_byte[1];
    assign gamma[0] = in_byte[6] ^ in_byte[1] ^ in_byte[0];

    // Decompose into two GF(2^4) elements: gamma = {g_h, g_l}
    logic [3:0] g_h, g_l;
    assign g_h = gamma[7:4];
    assign g_l = gamma[3:0];

    // GF(2^4) Squarer and multiplication by lambda in GF(2^4)
    logic [3:0] g_h_sq, g_l_sq, gh_gl, d, d_inv;

    // Squaring in GF(2^4)
    function automatic logic [3:0] gf4_sq(input logic [3:0] a);
        logic [3:0] q;
        q[3] = a[3];
        q[2] = a[3] ^ a[2];
        q[1] = a[2] ^ a[1];
        q[0] = a[3] ^ a[1] ^ a[0];
        return q;
    endfunction

    // Multiplication by lambda {1100}_2 in GF(2^4)
    function automatic logic [3:0] gf4_mul_lambda(input logic [3:0] a);
        logic [3:0] p;
        p[3] = a[2] ^ a[0];
        p[2] = a[3] ^ a[2] ^ a[1] ^ a[0];
        p[1] = a[3];
        p[0] = a[2];
        return p;
    endfunction

    // Multiplication in GF(2^4)
    function automatic logic [3:0] gf4_mul(input logic [3:0] a, input logic [3:0] b);
        logic [3:0] p;
        logic [1:0] ah, al, bh, bl, ph, pl, p_mid;
        logic [1:0] term_xor, term_prod;
        ah = a[3:2]; al = a[1:0];
        bh = b[3:2]; bl = b[1:0];
        // Karatsuba-like multiplication in GF((2^2)^2)
        ph = { (ah[1]&bh[1]) ^ ((ah[1]^ah[0])&(bh[1]^bh[0])), ((ah[1]&bh[1]) ^ (ah[0]&bh[0])) };
        pl = { (al[1]&bl[1]) ^ ((al[1]^al[0])&(bl[1]^bl[0])), ((al[1]&bl[1]) ^ (al[0]&bl[0])) };
        term_xor  = (ah ^ al) ^ (bh ^ bl);
        term_prod = { ((ah[1]^al[1])&(bh[1]^bl[1])) ^ (((ah[1]^al[1])^(ah[0]^al[0])) &
                      ((bh[1]^bl[1])^(bh[0]^bl[0]))),
                      (((ah[1]^al[1])&(bh[1]^bl[1])) ^ ((ah[0]^al[0])&(bh[0]^bl[0]))) };
        p_mid = term_prod ^ ph ^ pl;
        p[3:2] = ph ^ {p_mid[1], p_mid[0]};
        p[1:0] = pl ^ {p_mid[1] ^ p_mid[0], p_mid[1]};
        return p;
    endfunction

    // Inversion in GF(2^4)
    function automatic logic [3:0] gf4_inv(input logic [3:0] a);
        logic [3:0] inv;
        logic a0, a1, a2, a3;
        a3 = a[3]; a2 = a[2]; a1 = a[1]; a0 = a[0];
        inv[3] = a3 ^ (a3 & a2 & a1) ^ (a3 & a0) ^ (a2 & a0);
        inv[2] = a2 ^ (a3 & a2 & a0) ^ (a3 & a1) ^ (a2 & a1) ^ (a1 & a0);
        inv[1] = a1 ^ (a3 & a2 & a1) ^ (a3 & a1 & a0) ^ (a3 & a0) ^ (a2 & a0);
        inv[0] = a0 ^ (a3 & a2 & a0) ^ (a3 & a1) ^ (a2 & a1) ^ (a2 & a0) ^ (a1 & a0) ^
                 (a3 & a2 & a1 & a0) ^ (a3 & a2) ^ (a1);
        return inv;
    endfunction

    assign g_h_sq = gf4_sq(g_h);
    assign g_l_sq = gf4_sq(g_l);
    assign gh_gl  = gf4_mul(g_h, g_l);

    // d = g_h^2 * lambda + g_h * g_l + g_l^2
    assign d      = gf4_mul_lambda(g_h_sq) ^ gh_gl ^ g_l_sq;
    assign d_inv  = gf4_inv(d);

    // Multiplicative inversion in GF((2^4)^2):
    // inv_h = g_h * d^-1,  inv_l = (g_h + g_l) * d^-1
    logic [3:0] inv_h, inv_l;
    assign inv_h = gf4_mul(g_h, d_inv);
    assign inv_l = gf4_mul((g_h ^ g_l), d_inv);

    // Inverse isomorphism back to GF(2^8) combined with Affine Transformation + 0x63
    logic [7:0] inv_byte;
    assign inv_byte = {inv_h, inv_l};

    // Combined Inverse Isomorphism & Affine Transformation matrix
    assign out_byte[7] = inv_byte[7] ^ inv_byte[6] ^ inv_byte[4] ^ inv_byte[1];
    assign out_byte[6] = ~ (inv_byte[7] ^ inv_byte[3] ^ inv_byte[2] ^ inv_byte[1] ^ inv_byte[0]);
    assign out_byte[5] = ~ (inv_byte[6] ^ inv_byte[5] ^ inv_byte[4] ^ inv_byte[2] ^ inv_byte[0]);
    assign out_byte[4] = inv_byte[6] ^ inv_byte[5] ^ inv_byte[3] ^ inv_byte[2] ^
                           inv_byte[1] ^ inv_byte[0];
    assign out_byte[3] = inv_byte[7] ^ inv_byte[6] ^ inv_byte[3] ^ inv_byte[2] ^
                           inv_byte[1] ^ inv_byte[0];
    assign out_byte[2] = inv_byte[7] ^ inv_byte[4] ^ inv_byte[3] ^ inv_byte[2] ^ inv_byte[1];
    assign out_byte[1] = ~ (inv_byte[6] ^ inv_byte[4] ^ inv_byte[1] ^ inv_byte[0]);
    assign out_byte[0] = ~ (inv_byte[7] ^ inv_byte[6] ^ inv_byte[5] ^ inv_byte[2] ^
                           inv_byte[1] ^ inv_byte[0]);

endmodule: aes_sbox_composite
