// File:      secded_72_64_pkg.sv
// Chức năng: Mã hoá/giải mã Hamming SEC-DED (72,64) dùng chung cho đường ghi, đường đọc và bộ scrub.
`timescale 1ns / 1ps

package secded_72_64_pkg;

    // Hamming mở rộng: bit dữ liệu j nằm ở vị trí Hamming thứ j không phải lũy thừa 2 (3,5,6,7,9,...,71),
    // bit kiểm tra i (i<7) ở vị trí 2^i, bit 7 là chẵn lẻ toàn cục. Mặt nạ trùng hệ số với
    // OpenTitan prim_secded_hamming_72_64 (Apache-2.0), đã đối chiếu cả 8 hằng số.
    // Mặt nạ của bit kiểm tra i nằm ở SECDED_MASK[i*64 +: 64]
    localparam logic [7*64-1:0] SECDED_MASK = {
        64'hFE00_0000_0000_0000,
        64'h01FF_FFFF_FC00_0000,
        64'h01FF_FE00_03FF_F800,
        64'h01FE_01FE_03FC_07F0,
        64'hF1E1_E1E1_E3C3_C78E,
        64'hCD99_9999_9B33_366D,
        64'hAB55_5555_56AA_AD5B
    };

    // Hội chứng của lỗi đơn ở bit dữ liệu j = {1, vị trí Hamming}, byte j của hằng số này
    localparam logic [64*8-1:0] SECDED_DATA_SYN =
        512'hc7c6c5c4c3c2c1bfbebdbcbbbab9b8b7b6b5b4b3b2b1b0afaeadacabaaa9a8a7a6a5a4a3a2a19f9e9d9c9b9a9998979695949392918f8e8d8c8b8a8987868583;

    // Bit kiểm tra được lưu ở dạng đảo (XOR hằng số, cùng cách prim_secded_inv của OpenTitan): word 72 bit toàn 0
    // hoặc toàn 1 (bus DQ kẹt, DIMM không trả lời, dòng bị xoá về 0 do tấn công cold-boot/xoá hàng loạt) không còn là
    // codeword hợp lệ mà giải mã thành lỗi không sửa được. 0xAA cho hội chứng chẵn khác 0 ở cả hai trường hợp
    // (đã kiểm tra trên toàn bộ 255 hằng số khả dĩ); khoảng cách mã và khả năng sửa lỗi không đổi.
    localparam logic [7:0] SECDED_INV = 8'hAA;

    function automatic logic [7:0] secded72_enc(input logic [63:0] d);
        logic [7:0] e;
        for (int i = 0; i < 7; i++) e[i] = ^(d & SECDED_MASK[i*64 +: 64]);
        e[7] = (^d) ^ (^e[6:0]);
        secded72_enc = e ^ SECDED_INV;
    endfunction

    function automatic logic [7:0] secded72_syndrome(input logic [63:0] d, input logic [7:0] e_stored);
        logic [7:0] e, s;
        e = e_stored ^ SECDED_INV;
        for (int i = 0; i < 7; i++) s[i] = e[i] ^ ^(d & SECDED_MASK[i*64 +: 64]);
        s[7] = (^d) ^ (^e);
        secded72_syndrome = s;
    endfunction

    // Mặt nạ đảo bit dữ liệu cho lỗi đơn; lỗi đơn ở bit kiểm tra cho mặt nạ 0
    function automatic logic [63:0] secded72_flip(input logic [7:0] s);
        logic [63:0] m;
        for (int j = 0; j < 64; j++) m[j] = (s == SECDED_DATA_SYN[j*8 +: 8]);
        secded72_flip = m;
    endfunction

    // Phân loại: s[7]=1 là lỗi lẻ; chỉ sửa được khi vị trí 1..71 tồn tại. Vị trí 72..127 không có bit nào,
    // tức lỗi nhiều bit (>=3) giả dạng lỗi đơn: báo không sửa được thay vì đảo nhầm (bẫy ECCfail).
    // s[7]=0 và s!=0 là lỗi chẵn (>=2): không sửa được.
    function automatic logic secded72_ce(input logic [7:0] s);
        secded72_ce = s[7] && (s[6:0] <= 7'd71);
    endfunction

    function automatic logic secded72_ue(input logic [7:0] s);
        secded72_ue = (s != 8'h00) && !secded72_ce(s);
    endfunction

endpackage
