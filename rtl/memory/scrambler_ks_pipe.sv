// File:      scrambler_ks_pipe.sv
// Chức năng: Pipeline 6 tầng sinh keystream ARX của bus_scrambler từ địa chỉ word vật lý, kèm sideband cùng độ trễ.
`timescale 1ns / 1ps

module scrambler_ks_pipe #(
    parameter int SIDE_W = 1
) (
    input  logic              clk,
    input  logic              rst_n,
    input  logic [63:0]       cfg_seed,
    input  logic              i_valid,
    input  logic [63:0]       i_key,
    input  logic [SIDE_W-1:0] i_side,
    output logic              o_valid,
    output logic [63:0]       o_ks,
    output logic [SIDE_W-1:0] o_side
);

    // Cùng hàm với bus_scrambler::keystream: ba vòng "x += rotl(x,a); x ^= rotl(x,b) ^ (x >> c); x += rotl(seed,k)".
    // Mỗi tầng chỉ một phép cộng 64 bit (chuỗi carry ~0.6 ns): 6 tầng thay cho 6 phép cộng nối tiếp tổ hợp
    // (~4 ns, không đạt 400 MHz). Keystream chỉ phụ thuộc địa chỉ nên được tính trước khi dữ liệu tới.
    localparam int LAT = 6;
    // Hằng số quay/dịch của từng vòng (hàm thay cho mảng localparam để mọi công cụ đều chấp nhận)
    function automatic int RA(input int r); return (r == 0) ? 13 : (r == 1) ? 29 : 41; endfunction
    function automatic int RB(input int r); return (r == 0) ? 7  : (r == 1) ? 11 : 19; endfunction
    function automatic int RC(input int r); return (r == 0) ? 17 : (r == 1) ? 31 : 23; endfunction
    function automatic int RK(input int r); return (r == 0) ? 7  : (r == 1) ? 20 : 33; endfunction

    function automatic logic [63:0] rotl(input logic [63:0] v, input int r);
        return (v << r) | (v >> (64 - r));
    endfunction

    wire [63:0]       x    [0:LAT];
    wire [SIDE_W-1:0] side [0:LAT];
    wire [LAT:0]      vld;

    assign x[0]    = cfg_seed ^ i_key;
    assign side[0] = i_side;
    assign vld[0]  = i_valid;

    for (genvar s = 0; s < LAT; s++) begin : g_stage
        wire  [63:0]       nx;
        logic [63:0]       x_q;
        logic [SIDE_W-1:0] side_q;
        logic              vld_q;
        if (s % 2 == 0) begin : g_add_rot
            assign nx = x[s] + rotl(x[s], RA(s / 2));
        end else begin : g_xs_add
            wire [63:0] t = x[s] ^ rotl(x[s], RB(s / 2)) ^ (x[s] >> RC(s / 2));
            assign nx = t + rotl(cfg_seed, RK(s / 2));
        end
        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) vld_q <= 1'b0;
            else        vld_q <= vld[s];
        end
        always_ff @(posedge clk) begin
            x_q    <= nx;
            side_q <= side[s];
        end
        assign x[s+1]    = x_q;
        assign side[s+1] = side_q;
        assign vld[s+1]  = vld_q;
    end

    assign o_valid = vld[LAT];
    assign o_ks    = x[LAT];
    assign o_side  = side[LAT];

endmodule
