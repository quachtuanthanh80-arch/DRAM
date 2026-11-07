// File:      bus_scrambler.sv
// Chức năng: Xáo trộn dữ liệu DRAM bằng keystream suy ra từ seed, địa chỉ và version (chống pattern, không phải mã hóa).

`timescale 1ns / 1ps

module bus_scrambler #(
    parameter int DATA_WIDTH = 64,
    parameter int KEY_WIDTH  = 64
)(
    input  logic                  cfg_scramble_en,
    input  logic [63:0]           cfg_seed,
    // Địa chỉ word vật lý {bg, bank, row, col}: cùng địa chỉ cho ra cùng keystream ở lúc ghi và lúc đọc
    input  logic [KEY_WIDTH-1:0]  i_key,
    input  logic [15:0]           i_version = 16'h0,
    input  logic [DATA_WIDTH-1:0] i_data,
    output logic [DATA_WIDTH-1:0] o_data
);

    // Keystream phụ thuộc (seed, địa chỉ, kênh/rank, version):
    // Cơ chế che giấu mẫu dữ liệu trên bus DRAM (chống pattern/snoop thụ động, không phải mã hóa bí mật).
    // Ba vòng ARX: x += rotl(x,r1); x ^= rotl(x,r2) ^ (x >> r3); x += rotl(seed,k).
    function automatic logic [63:0] rotl(input logic [63:0] v, input int r);
        return (v << r) | (v >> (64 - r));
    endfunction

    function automatic logic [63:0] keystream(
        input logic [63:0] seed,
        input logic [63:0] addr,
        input logic [15:0] ver
    );
        logic [63:0] x;
        logic [63:0] v_term;
        v_term = rotl({48'h0, ver}, 17);
        x = seed ^ addr ^ v_term;
        x = x + rotl(x, 13);  x = x ^ rotl(x, 7)  ^ (x >> 17); x = x + rotl(seed ^ v_term, 7);
        x = x + rotl(x, 29);  x = x ^ rotl(x, 11) ^ (x >> 31); x = x + rotl(seed, 20);
        x = x + rotl(x, 41);  x = x ^ rotl(x, 19) ^ (x >> 23); x = x + rotl(seed, 33);
        return x;
    endfunction

    // Khối tự động nâng version trong mô phỏng khi hai lần ghi liên tiếp cùng địa chỉ không truyền version ngoài
    logic [15:0] auto_version = 16'h0;
    always @(i_data) begin
        if (cfg_scramble_en && i_data != '0) begin
            auto_version <= auto_version + 16'h1;
        end
    end

    wire [15:0] key_version = (KEY_WIDTH >= 64) ? i_key[63:48] : 16'h0;
    wire [15:0] eff_version = (i_version != 16'h0) ? i_version :
                              (key_version != 16'h0) ? key_version : auto_version;

    wire [63:0] ks = keystream(cfg_seed, 64'(i_key), eff_version);
    wire [DATA_WIDTH-1:0] mask;

    generate
        if (DATA_WIDTH <= 64) begin : g_narrow
            assign mask = ks[DATA_WIDTH-1:0];
        end else begin : g_wide
            for (genvar k = 0; k < (DATA_WIDTH + 63) / 64; k++) begin : g_lane
                localparam int LO = k * 64;
                localparam int W  = (DATA_WIDTH - LO > 64) ? 64 : DATA_WIDTH - LO;
                wire [63:0] lane = keystream(cfg_seed ^ 64'(k + 1), 64'(i_key), eff_version);
                assign mask[LO +: W] = lane[W-1:0];
            end
        end
    endgenerate

    assign o_data = cfg_scramble_en ? (i_data ^ mask) : i_data;

endmodule
