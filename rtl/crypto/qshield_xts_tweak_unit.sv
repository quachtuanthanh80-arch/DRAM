// File: qshield_xts_tweak_unit.sv
// Chức năng: Đơn vị sinh vector Tweak AES-256-XTS chuẩn IEEE 1619 (AES256_K2 + nhân đa thức alpha trên GF(2^128)).

`timescale 1ns / 1ps

module qshield_xts_tweak_unit #(
    parameter int MetaWidth = 16
) (
    input  logic                   clk,
    input  logic                   rst_n,

    // Giao diện yêu cầu sinh tweak (1 yêu cầu ứng với 1 dòng 64 B)
    input  logic                   i_valid,
    output logic                   o_ready,
    input  logic [127:0]           i_tweak,      // tweak_in theo chuẩn S2: [57:0]=dòng, [61:58]=ASID, [80:62]=epoch
    input  logic [15*128-1:0]      i_round_keys, // 15 khoá vòng của K2 từ aes256_key_expand
    input  logic [MetaWidth-1:0]   i_meta,

    // Giao diện xuất 4 vector tweak (t0..t3) cho 4 khối 16 B của dòng 64 B
    output logic                   o_valid,
    input  logic                   i_ready,
    output logic [127:0]           o_tweak0,
    output logic [127:0]           o_tweak1,
    output logic [127:0]           o_tweak2,
    output logic [127:0]           o_tweak3,
    output logic [MetaWidth-1:0]   o_meta
);
    import aes_pkg::*;

    // Mở gói khoá vòng K2
    logic [127:0] rk [15];
    for (genvar k = 0; k < 15; k++) begin : g_rk
        assign rk[k] = i_round_keys[k*128 +: 128];
    end

    // Vòng khởi tạo AddRoundKey(RK0)
    logic [127:0] initial_state;
    assign initial_state = i_tweak ^ rk[0];

    // Đường ống 14 tầng AES-256 mã hoá tweak bằng khoá K2
    logic [127:0] stage_state [15];
    logic         stage_valid [15];
    logic         stage_ready [15];
    logic [MetaWidth-1:0] meta_pipe [1:14];

    assign stage_state[0] = initial_state;
    assign stage_valid[0] = i_valid;
    assign o_ready        = stage_ready[0];

    genvar r;
    generate
        for (r = 1; r <= 14; r++) begin : gen_tweak_rounds
            localparam bit IsFinal = (r == 14);

            aes_round_pipe u_round (
                .clk           (clk),
                .rst_n         (rst_n),
                .in_valid      (stage_valid[r-1]),
                .in_ready      (stage_ready[r-1]),
                .is_final_round(IsFinal),
                .state_in      (stage_state[r-1]),
                .round_key     (rk[r]),
                .out_valid     (stage_valid[r]),
                .out_ready     (stage_ready[r]),
                .state_out     (stage_state[r])
            );

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    meta_pipe[r] <= '0;
                end else if (stage_ready[r-1] && stage_valid[r-1]) begin
                    if (r == 1) begin
                        meta_pipe[r] <= i_meta;
                    end else begin
                        meta_pipe[r] <= meta_pipe[r-1];
                    end
                end
            end
        end
    endgenerate

    assign stage_ready[14] = i_ready;

    // T0 = AES256_K2(i_tweak)
    wire [127:0] t0 = stage_state[14];

    // Nhân liên tiếp với alpha trên trường Galois GF(2^128) theo IEEE 1619
    wire [127:0] t1 = xts_mul_alpha(t0);
    wire [127:0] t2 = xts_mul_alpha(t1);
    wire [127:0] t3 = xts_mul_alpha(t2);

    assign o_valid  = stage_valid[14];
    assign o_tweak0 = t0;
    assign o_tweak1 = t1;
    assign o_tweak2 = t2;
    assign o_tweak3 = t3;
    assign o_meta   = meta_pipe[14];

endmodule
