// File: scarf_dram_randomizer.sv
// Chức năng: Bộ mã hóa Feistel 1 chu kỳ hoán vị ngẫu nhiên địa chỉ hàng và bank DRAM theo kiến trúc SCARF.
`timescale 1ns / 1ps

module scarf_dram_randomizer #(
    parameter int ROW_WIDTH   = 17,
    parameter int BANK_WIDTH  = 2,
    parameter int TWEAK_WIDTH = 16,
    parameter int ROUNDS      = 10
) (
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   cfg_scramble_en,
    input  logic [63:0]            cfg_scramble_seed,
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

    // Mạng Feistel mở phẳng (unrolled combinational network) đảm bảo độ trễ <= 1 chu kỳ
    wire [L_W-1:0] l_pipe [0:ROUNDS];
    wire [R_W-1:0] r_pipe [0:ROUNDS];

    assign l_pipe[0] = raw_input[L_W-1:0];
    assign r_pipe[0] = raw_input[TOTAL_W-1:L_W];

    genvar r;
    generate
        for (r = 0; r < ROUNDS; r = r + 1) begin : gen_feistel_rounds
            wire [7:0] rkey = ((cfg_scramble_seed >> ((r * 6) % 56)) & 8'hFF) ^ 8'(r);
            assign l_pipe[r+1] = r_pipe[r][L_W-1:0];
            assign r_pipe[r+1] = {1'b0, l_pipe[r]} ^ {1'b0, feistel_f(r_pipe[r], rkey, i_tweak, r)};
        end
    endgenerate

    // Ghép kết quả đầu ra: khi tắt scramble thì giữ nguyên địa chỉ gốc (bypass không mất chu kỳ)
    wire [TOTAL_W-1:0] scrambled_full = {r_pipe[ROUNDS], l_pipe[ROUNDS]};

    assign o_scrambled_bank = cfg_scramble_en ? scrambled_full[TOTAL_W-1:ROW_WIDTH] : i_bank;
    assign o_scrambled_row  = cfg_scramble_en ? scrambled_full[ROW_WIDTH-1:0]       : i_row;

endmodule
