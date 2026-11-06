// File:      integrity_mac_gen.sv
// Chức năng: Sinh và kiểm tra MAC toàn vẹn AES-CMAC (RFC 4493) trên {dữ liệu, địa chỉ, bộ đếm ghi} chống sửa, dời chỗ và phát lại.

`timescale 1ns / 1ps

module integrity_mac_gen #(
    parameter int DATA_WIDTH = 128,
    parameter int ADDR_WIDTH = 32,
    parameter int MAC_WIDTH  = 64
)(
    input  logic                   clk,
    input  logic                   rst_n,

    input  logic                   cfg_mac_en,
    input  logic [127:0]           cfg_mac_key,

    // Sinh MAC chiều ghi
    input  logic                   i_wr_valid,
    output logic                   o_wr_ready,
    input  logic [ADDR_WIDTH-1:0]  i_wr_addr,
    input  logic [31:0]            i_wr_counter,
    input  logic [DATA_WIDTH-1:0]  i_wr_data,
    output logic                   o_wr_mac_valid,
    output logic [MAC_WIDTH-1:0]   o_wr_mac,

    // Kiểm tra MAC chiều đọc
    input  logic                   i_rd_valid,
    output logic                   o_rd_ready,
    input  logic [ADDR_WIDTH-1:0]  i_rd_addr,
    input  logic [31:0]            i_rd_counter,
    input  logic [DATA_WIDTH-1:0]  i_rd_data,
    input  logic [MAC_WIDTH-1:0]   i_rd_stored_mac,
    output logic                   o_rd_mac_valid,
    output logic                   o_integrity_violation
);
    // Thông điệp NB+1 khối trọn vẹn: M_0..M_{NB-1} = dữ liệu (khối i = data[128i +: 128]), M_NB = {địa chỉ, bộ đếm, 0}.
    // Chuỗi CBC-MAC: X = 0; X = AES_K(X ^ M_i) với i < NB; T = AES_K(X ^ M_NB ^ K1), K1 = dbl(L), L = AES_K(0^128).
    // MAC là MAC_WIDTH bit trái nhất của T (cắt theo RFC 4493). Mọi bit dữ liệu đều vào MAC: bản trước chỉ nối
    // 128 bit thấp của dòng 512 bit nên 384 bit còn lại bị sửa mà không bị phát hiện (S25).
    // Bản cũ chỉ XOR dữ liệu với khoá (không có AES) và lấy 64 bit thấp nên địa chỉ/bộ đếm không ảnh hưởng MAC:
    // giả mạo tuyến tính, dời chỗ và phát lại đều thành công (S4).
    function automatic logic [127:0] dbl(input logic [127:0] x);
        return {x[126:0], 1'b0} ^ (x[127] ? 128'h87 : 128'h0);
    endfunction

    function automatic logic [127:0] blk2(input logic [ADDR_WIDTH-1:0] a, input logic [31:0] c);
        return {32'(a), c, 64'h0};
    endfunction

    // Khoá con L tính lại mỗi khi khoá đổi; hai luồng ghi/đọc dùng chung kết quả
    logic [127:0] l_key_q, k1_q;
    logic         l_valid;

    //------------------------------------------------------------------
    // Mỗi luồng một lõi AES-128 lặp: L (nếu cần) -> NB lần AES(X ^ M_i) -> AES(X ^ M_NB ^ K1)
    //------------------------------------------------------------------
    typedef enum logic [2:0] {P_IDLE, P_L, P_M1, P_M2, P_OUT} pstate_t;

    pstate_t                wst, rst_q;
    logic                   w_start, r_start;
    logic [127:0]           w_pt, r_pt;
    logic                   w_busy, r_busy, w_done, r_done;
    logic [127:0]           w_ct, r_ct;
    localparam int NB = DATA_WIDTH / 128;
    localparam int BW = (NB > 1) ? $clog2(NB) : 1;
    logic [DATA_WIDTH-1:0]  w_m1, r_m1;
    logic [127:0]           w_m2, r_m2, w_x, r_x;
    logic [BW-1:0]          w_blk, r_blk;
    logic [MAC_WIDTH-1:0]   r_stored;

    aes128_enc_iter u_wr_aes (.clk(clk), .rst_n(rst_n), .i_start(w_start), .i_key(cfg_mac_key), .i_pt(w_pt),
                              .o_busy(w_busy), .o_done(w_done), .o_ct(w_ct));
    aes128_enc_iter u_rd_aes (.clk(clk), .rst_n(rst_n), .i_start(r_start), .i_key(cfg_mac_key), .i_pt(r_pt),
                              .o_busy(r_busy), .o_done(r_done), .o_ct(r_ct));

    wire l_fresh = l_valid && (l_key_q == cfg_mac_key);

    assign o_wr_ready = cfg_mac_en && (wst == P_IDLE);
    assign o_rd_ready = cfg_mac_en && (rst_q == P_IDLE);

    always_comb begin
        w_start = 1'b0;
        w_pt    = '0;
        case (wst)
            P_L:  begin w_start = !w_busy && !w_done; w_pt = '0; end
            P_M1: begin w_start = !w_busy && !w_done; w_pt = w_x ^ w_m1[w_blk*128 +: 128]; end
            P_M2: begin w_start = !w_busy && !w_done; w_pt = w_x ^ w_m2 ^ k1_q; end
            default: ;
        endcase
        r_start = 1'b0;
        r_pt    = '0;
        case (rst_q)
            P_L:  begin r_start = !r_busy && !r_done; r_pt = '0; end
            P_M1: begin r_start = !r_busy && !r_done; r_pt = r_x ^ r_m1[r_blk*128 +: 128]; end
            P_M2: begin r_start = !r_busy && !r_done; r_pt = r_x ^ r_m2 ^ k1_q; end
            default: ;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wst <= P_IDLE; rst_q <= P_IDLE;
            l_valid <= 1'b0; l_key_q <= '0; k1_q <= '0;
            w_m1 <= '0; w_m2 <= '0; r_m1 <= '0; r_m2 <= '0;
            w_x <= '0; r_x <= '0; w_blk <= '0; r_blk <= '0;
            r_stored <= '0;
            o_wr_mac_valid <= 1'b0; o_wr_mac <= '0;
            o_rd_mac_valid <= 1'b0; o_integrity_violation <= 1'b0;
        end else begin
            o_wr_mac_valid        <= 1'b0;
            o_rd_mac_valid        <= 1'b0;
            o_integrity_violation <= 1'b0;

            // Luồng ghi
            case (wst)
                P_IDLE: if (cfg_mac_en && i_wr_valid) begin
                    w_m1  <= i_wr_data;
                    w_m2  <= blk2(i_wr_addr, i_wr_counter);
                    w_x   <= '0;
                    w_blk <= '0;
                    wst  <= l_fresh ? P_M1 : P_L;
                end
                P_L: if (w_done) begin
                    l_valid <= 1'b1;
                    l_key_q <= cfg_mac_key;
                    k1_q    <= dbl(w_ct);
                    wst     <= P_M1;
                end
                P_M1: if (w_done) begin
                    w_x <= w_ct;
                    if (w_blk == BW'(NB - 1)) wst <= P_M2;
                    else                      w_blk <= w_blk + 1'b1;
                end
                P_M2: if (w_done) begin
                    o_wr_mac_valid <= 1'b1;
                    o_wr_mac       <= w_ct[127 -: MAC_WIDTH];
                    wst            <= P_IDLE;
                end
                default: wst <= P_IDLE;
            endcase

            // Luồng đọc: tính lại MAC trên dữ liệu đọc về và so với MAC đã lưu
            case (rst_q)
                P_IDLE: if (cfg_mac_en && i_rd_valid) begin
                    r_m1     <= i_rd_data;
                    r_m2     <= blk2(i_rd_addr, i_rd_counter);
                    r_x      <= '0;
                    r_blk    <= '0;
                    r_stored <= i_rd_stored_mac;
                    rst_q    <= l_fresh ? P_M1 : P_L;
                end
                P_L: if (r_done) begin
                    l_valid <= 1'b1;
                    l_key_q <= cfg_mac_key;
                    k1_q    <= dbl(r_ct);
                    rst_q   <= P_M1;
                end
                P_M1: if (r_done) begin
                    r_x <= r_ct;
                    if (r_blk == BW'(NB - 1)) rst_q <= P_M2;
                    else                      r_blk <= r_blk + 1'b1;
                end
                P_M2: if (r_done) begin
                    o_rd_mac_valid        <= 1'b1;
                    o_integrity_violation <= (r_ct[127 -: MAC_WIDTH] != r_stored);
                    rst_q                 <= P_IDLE;
                end
                default: rst_q <= P_IDLE;
            endcase
        end
    end
endmodule
