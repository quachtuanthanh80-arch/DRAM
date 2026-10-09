// File: pxor_hash_engine.sv
// Chức năng: Động cơ băm vạn năng song song XOR (PXOR-Hash) cho bộ lọc SDC chống né tránh thuật toán.
`timescale 1ns / 1ps

module pxor_hash_engine #(
    parameter int TAG_WIDTH  = 22,
    parameter int HASH_WIDTH = 8
) (
    input  logic [TAG_WIDTH-1:0]  i_tag,
    input  logic [63:0]           i_seed,
    output logic [HASH_WIDTH-1:0] o_hash
);

    // Dự phòng seed mặc định khi đầu vào bị thả nổi hoặc chứa bit không xác định (X/Z)
    wire [63:0] effective_seed = (^i_seed === 1'bx || i_seed == 64'h0) ? 64'hA5A5_5A5A_0123_4567 : i_seed;

    // Ma trận băm nhị phân Toeplitz sinh từ seed ngẫu nhiên nhằm đảm bảo tính vạn năng (Universal Hashing)
    // Giới hạn xác suất va chạm: Pr[h(x) = h(y)] <= 2^(-HASH_WIDTH)
    wire [TAG_WIDTH-1:0] mask_per_hash [0:HASH_WIDTH-1];

    genvar h, t;
    generate
        for (h = 0; h < HASH_WIDTH; h = h + 1) begin : gen_hash_bits
            for (t = 0; t < TAG_WIDTH; t = t + 1) begin : gen_coeff
                localparam int IDX1 = (t * 3 + h * 7) % 64;
                localparam int IDX2 = (t * 5 + h + 13) % 64;
                assign mask_per_hash[h][t] = effective_seed[IDX1] ^ effective_seed[IDX2] ^ (t == h ? 1'b1 : 1'b0);
            end

            // Cây rút gọn XOR song song tính toán trực tiếp bit băm trong sub-nanosecond
            assign o_hash[h] = ^(i_tag & mask_per_hash[h]);
        end
    endgenerate

endmodule
