// File: scarf_dram_randomizer.sv
// Chức năng: Bộ mã hóa Feistel hoán vị ngẫu nhiên địa chỉ hàng và bank DRAM theo kiến trúc SCARF (tổ hợp hoặc pipeline).
`timescale 1ns / 1ps

/* verilator lint_off UNOPTFLAT */
module scarf_dram_randomizer #(
    parameter int ROW_WIDTH   = 17,
    parameter int BANK_WIDTH  = 2,
    parameter int TWEAK_WIDTH = 16,
    parameter int ROUNDS      = 10,
    // 0: tổ hợp (một chu kỳ, như cũ). N > 0: thanh ghi sau mỗi N vòng và ở đầu ra, độ trễ ceil(ROUNDS/N) chu kỳ.
    // 10 vòng tổ hợp là ~25 mức LUT: không đạt 400 MHz, nên bộ ánh xạ địa chỉ dùng N = 2.
    parameter int RPS         = 0
) (
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   cfg_scramble_en,
    input  logic [63:0]            cfg_scramble_seed,
    // Cho phép pipeline tiến (stall toàn tuyến khi đầu ra bị giữ); bỏ qua khi RPS = 0
    input  logic                   i_en = 1'b1,
    input  logic [TWEAK_WIDTH-1:0] i_tweak,
    input  logic [ROW_WIDTH-1:0]   i_row,
    input  logic [BANK_WIDTH-1:0]  i_bank,
    output logic [ROW_WIDTH-1:0]   o_scrambled_row,
    output logic [BANK_WIDTH-1:0]  o_scrambled_bank
);

    localparam int TOTAL_W = ROW_WIDTH + BANK_WIDTH; // 19 bits
    localparam int L_W     = TOTAL_W / 2;             // 9 bits
    localparam int R_W     = TOTAL_W - L_W;         // 10 bits

    // Trích xuất vector địa chỉ phẳng kết hợp (Bank, Row)
    wire [TOTAL_W-1:0] raw_input = {i_bank, i_row};

    // Hàm hoán vị S-Box 4-bit phi tuyến của SCARF (tối ưu hóa độ trễ mức cổng logic)
    function automatic logic [3:0] scarf_sbox(input logic [3:0] x);
        case (x)
            4'h0: scarf_sbox = 4'hC;
            4'h1: scarf_sbox = 4'h5;
            4'h2: scarf_sbox = 4'h6;
            4'h3: scarf_sbox = 4'hB;
            4'h4: scarf_sbox = 4'h9;
            4'h5: scarf_sbox = 4'h0;
            4'h6: scarf_sbox = 4'hA;
            4'h7: scarf_sbox = 4'hD;
            4'h8: scarf_sbox = 4'h3;
            4'h9: scarf_sbox = 4'hE;
            4'hA: scarf_sbox = 4'hF;
            4'hB: scarf_sbox = 4'h8;
            4'hC: scarf_sbox = 4'h4;
            4'hD: scarf_sbox = 4'h7;
            4'hE: scarf_sbox = 4'h1;
            4'hF: scarf_sbox = 4'h2;
            default: scarf_sbox = 4'h0;
        endcase
    endfunction

    // Hàm vòng Feistel F-Function: kết hợp khóa vòng, tweak và tầng thế phi tuyến S-Box
    function automatic logic [L_W-1:0] feistel_f(
        input logic [R_W-1:0]         r_in,
        input logic [7:0]             round_key,
        input logic [TWEAK_WIDTH-1:0] twk,
        input int                     rnd_idx
    );
        logic [R_W-1:0] mixed;
        logic [R_W-1:0] subbed;
        logic [L_W-1:0] truncated_res;

        // Trộn dữ liệu nhánh phải với khóa phụ và tweak được dịch vòng theo chỉ số round
        mixed = r_in ^ {twk[R_W-1:0]} ^ {round_key, round_key[1:0]};

        // Áp dụng thế phi tuyến S-Box trên từng nibble để phá vỡ tính chất tuyến tính của ZenHammer
        subbed[3:0] = scarf_sbox(mixed[3:0]);
        subbed[7:4] = scarf_sbox(mixed[7:4]);
        subbed[9:8] = mixed[9:8] ^ {subbed[1], subbed[0]};

        // Hoán vị tuyến tính khuếch tán bit và cắt về kích thước nhánh trái
        truncated_res = {subbed[7:0], subbed[9]} ^ {subbed[3:0], subbed[8:4]};
        return truncated_res;
    endfunction

    // Hàm vòng chiều ngược (nhánh 9 bit -> 10 bit) cho nửa vòng cập nhật nhánh cao
    function automatic logic [R_W-1:0] feistel_g(
        input logic [L_W-1:0]         l_in,
        input logic [7:0]             round_key,
        input logic [TWEAK_WIDTH-1:0] twk
    );
        logic [R_W-1:0] mixed;
        logic [R_W-1:0] subbed;

        mixed = {l_in[0], l_in} ^ twk[R_W-1:0] ^ {round_key[1:0], round_key};
        subbed[3:0] = scarf_sbox(mixed[3:0]);
        subbed[7:4] = scarf_sbox(mixed[7:4]);
        subbed[9:8] = mixed[9:8] ^ {subbed[5], subbed[2]};
        return {subbed[6:0], subbed[9:7]} ^ {subbed[4:0], subbed[9:5]};
    endfunction

    // Mạng Feistel không cân bằng mở phẳng (độ trễ <= 1 chu kỳ). 19 bit lẻ nên hai nhánh lệch 9/10 bit:
    // mỗi nửa vòng chỉ XOR một nhánh với hàm của nhánh kia, nên luôn khả nghịch và toàn ánh xạ là song ánh.
    // Phiên bản cũ hoán đổi nhánh lệch độ rộng, bỏ mất 1 bit mỗi vòng -> 2^18 cặp địa chỉ trùng ảnh (S15).
    wire [L_W-1:0]         l_pipe   [0:ROUNDS];
    wire [R_W-1:0]         r_pipe   [0:ROUNDS];
    // Tweak và địa chỉ gốc đi kèm từng tầng: mỗi vòng dùng tweak của chính yêu cầu đó, bypass trả lại địa chỉ gốc
    wire [TWEAK_WIDTH-1:0] twk_pipe [0:ROUNDS];
    wire [TOTAL_W-1:0]     raw_pipe [0:ROUNDS];

    assign l_pipe[0]   = raw_input[L_W-1:0];
    assign r_pipe[0]   = raw_input[TOTAL_W-1:L_W];
    assign twk_pipe[0] = i_tweak;
    assign raw_pipe[0] = raw_input;

    genvar r;
    generate
        for (r = 0; r < ROUNDS; r = r + 1) begin : gen_feistel_rounds
            wire [7:0]     rkey = 8'(cfg_scramble_seed >> ((r * 6) % 56)) ^ 8'(r);
            wire [L_W-1:0] l_nx;
            wire [R_W-1:0] r_nx;
            if (r % 2 == 0) begin : g_upd_lo
                assign l_nx = l_pipe[r] ^ feistel_f(r_pipe[r], rkey, twk_pipe[r], r);
                assign r_nx = r_pipe[r];
            end else begin : g_upd_hi
                assign l_nx = l_pipe[r];
                assign r_nx = r_pipe[r] ^ feistel_g(l_pipe[r], rkey, twk_pipe[r]);
            end
            localparam bit REG = (RPS > 0) && (((r + 1) % (RPS > 0 ? RPS : 1) == 0) || (r == ROUNDS - 1));
            if (REG) begin : g_reg
                logic [L_W-1:0]         l_q;
                logic [R_W-1:0]         r_q;
                logic [TWEAK_WIDTH-1:0] t_q;
                logic [TOTAL_W-1:0]     w_q;
                // Tầng cuối: chọn bypass trước thanh ghi để đầu ra là thanh ghi thuần (không mux sau flop)
                localparam bit LAST = (r == ROUNDS - 1);
                always_ff @(posedge clk)
                    if (i_en) begin
                        l_q <= (LAST && !cfg_scramble_en) ? raw_pipe[r][L_W-1:0]       : l_nx;
                        r_q <= (LAST && !cfg_scramble_en) ? raw_pipe[r][TOTAL_W-1:L_W] : r_nx;
                        t_q <= twk_pipe[r];
                        w_q <= raw_pipe[r];
                    end
                assign l_pipe[r+1]   = l_q;
                assign r_pipe[r+1]   = r_q;
                assign twk_pipe[r+1] = t_q;
                assign raw_pipe[r+1] = w_q;
            end else begin : g_comb
                assign l_pipe[r+1]   = l_nx;
                assign r_pipe[r+1]   = r_nx;
                assign twk_pipe[r+1] = twk_pipe[r];
                assign raw_pipe[r+1] = raw_pipe[r];
            end
        end
    endgenerate

    // Khi tắt scramble trả địa chỉ gốc (cùng độ trễ với nhánh xáo trộn)
    wire [TOTAL_W-1:0] scrambled_full = {r_pipe[ROUNDS], l_pipe[ROUNDS]};

    generate
        if (RPS > 0) begin : g_out_reg
            assign o_scrambled_bank = scrambled_full[TOTAL_W-1:ROW_WIDTH];
            assign o_scrambled_row  = scrambled_full[ROW_WIDTH-1:0];
        end else begin : g_out_comb
            assign o_scrambled_bank = cfg_scramble_en ? scrambled_full[TOTAL_W-1:ROW_WIDTH] : i_bank;
            assign o_scrambled_row  = cfg_scramble_en ? scrambled_full[ROW_WIDTH-1:0]       : i_row;
        end
    endgenerate

    wire _unused_rst = rst_n;

endmodule
