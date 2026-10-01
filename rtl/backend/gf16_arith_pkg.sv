// gf16_arith_pkg.sv
// Package phep toan truong Galois GF(2^4) voi da thuc toi dai P(x) = x^4 + x + 1 cho ma Chipkill RS(18,16)

`timescale 1ns / 1ps

package gf16_arith_pkg;

    typedef logic [3:0] gf16_t;

    // Phep cong/tru trong truong dac trung 2: A + B = A ^ B
    function automatic gf16_t gf16_add(input gf16_t a, input gf16_t b);
        return a ^ b;
    endfunction

    // Phep nhan Galois GF(2^4) modulo P(x) = x^4 + x + 1 (0x13)
    function automatic gf16_t gf16_mul(input gf16_t a, input gf16_t b);
        logic [6:0] p;
        p = 7'b0;
        for (int i = 0; i < 4; i++) begin
            if (b[i]) p = p ^ ({3'b0, a} << i);
        end
        // Rut gon modulo x^4 + x + 1: x^4 = x + 1 (3), x^5 = x^2 + x (6), x^6 = x^3 + x^2 (12)
        if (p[6]) p = p ^ (7'b0010011 << 2);
        if (p[5]) p = p ^ (7'b0010011 << 1);
        if (p[4]) p = p ^ (7'b0010011);
        return p[3:0];
    endfunction

    // Phep nghich dao trong GF(2^4): a^(-1) = a^14 (theo dinh ly nho Fermat)
    function automatic gf16_t gf16_inv(input gf16_t a);
        case (a)
            4'h0: return 4'h0;
            4'h1: return 4'h1;
            4'h2: return 4'h9;
            4'h3: return 4'he;
            4'h4: return 4'hd;
            4'h5: return 4'hb;
            4'h6: return 4'h7;
            4'h7: return 4'h6;
            4'h8: return 4'hf;
            4'h9: return 4'h2;
            4'ha: return 4'hc;
            4'hb: return 4'h5;
            4'hc: return 4'ha;
            4'hd: return 4'h4;
            4'he: return 4'h3;
            4'hf: return 4'h8;
            default: return 4'h0;
        endcase
    endfunction

endpackage
