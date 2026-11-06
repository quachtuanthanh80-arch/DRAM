// File:      gf256_arith_pkg.sv
// Chức năng: Phép toán trường GF(2^8) (đa thức x^8+x^4+x^3+x^2+1, α = 2) và hằng số cho mã Chipkill RS(18,16).
`timescale 1ns / 1ps

package gf256_arith_pkg;

    typedef logic [7:0] gf256_t;

    // Nhân dịch-và-rút-gọn; với một toán hạng hằng, tổng hợp thành ma trận XOR 8x8
    function automatic gf256_t gf256_mul(input gf256_t a, input gf256_t b);
        logic [7:0] p, x;
        p = '0;
        x = a;
        for (int i = 0; i < 8; i++) begin
            if (b[i]) p = p ^ x;
            x = {x[6:0], 1'b0} ^ (x[7] ? 8'h1D : 8'h00);
        end
        return p;
    endfunction

    // Locator của symbol i là α^i (i = 0..17): 18 giá trị khác 0 và phân biệt. Mã RS trên GF(2^4) cũ cần 18 locator
    // trong 15 phần tử khác 0 nên bất khả (R19); GF(2^8) cho tới 255.
    localparam logic [18*8-1:0] RS_ALPHA = 144'h98_4c_26_13_87_cd_e8_74_3a_1d_80_40_20_10_08_04_02_01;
    // Hệ số giải parity: K = (α^16 + α^17)^-1
    localparam gf256_t RS_K = 8'hF9;

endpackage
