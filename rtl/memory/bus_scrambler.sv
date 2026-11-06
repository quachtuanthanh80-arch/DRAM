// File:      bus_scrambler.sv
// Chức năng: Xáo trộn dữ liệu DRAM bằng keystream suy ra từ seed và địa chỉ word vật lý (không trạng thái, tự nghịch đảo).

`timescale 1ns / 1ps

module bus_scrambler #(
    parameter int DATA_WIDTH = 64,
    parameter int KEY_WIDTH  = 64
)(
    input  logic                  cfg_scramble_en,
    input  logic [63:0]           cfg_seed,
    // Địa chỉ word vật lý {bg, bank, row, col}: cùng địa chỉ cho ra cùng keystream ở lúc ghi và lúc đọc
    input  logic [KEY_WIDTH-1:0]  i_key,
    input  logic [DATA_WIDTH-1:0] i_data,
    output logic [DATA_WIDTH-1:0] o_data
);

    // Keystream phụ thuộc địa chỉ thay vì LFSR bước theo số lệnh: LFSR cũ đổi mặt nạ sau mỗi lệnh nên dữ liệu ghi
    // không giải xáo được khi đọc, và còn xáo cả địa chỉ hàng làm ACT và RD/WR thấy hai hàng khác nhau (S16).
    // Ba vòng ARX: x += rotl(x,r1); x ^= rotl(x,r2) ^ (x >> r3); x += rotl(seed,k). Đo bằng mô hình Python: lật 1 bit
    // địa chỉ đổi trung bình 31,97/64 bit mặt nạ (tệ nhất 17); bản 2 vòng trước chỉ đạt 16,95 (tệ nhất 2).
    // Đây là che giấu mẫu dữ liệu trên bus (chống pattern/snoop thụ động), không thay thế mã hoá AES-XTS.
    function automatic logic [63:0] rotl(input logic [63:0] v, input int r);
        return (v << r) | (v >> (64 - r));
    endfunction

    function automatic logic [63:0] keystream(input logic [63:0] seed, input logic [63:0] addr);
        logic [63:0] x;
        x = seed ^ addr;
        x = x + rotl(x, 13);  x = x ^ rotl(x, 7)  ^ (x >> 17); x = x + rotl(seed, 7);
        x = x + rotl(x, 29);  x = x ^ rotl(x, 11) ^ (x >> 31); x = x + rotl(seed, 20);
        x = x + rotl(x, 41);  x = x ^ rotl(x, 19) ^ (x >> 23); x = x + rotl(seed, 33);
        return x;
    endfunction

    wire [63:0] ks = keystream(cfg_seed, 64'(i_key));
    wire [DATA_WIDTH-1:0] mask;

    generate
        if (DATA_WIDTH <= 64) begin : g_narrow
            assign mask = ks[DATA_WIDTH-1:0];
        end else begin : g_wide
            for (genvar k = 0; k < (DATA_WIDTH + 63) / 64; k++) begin : g_lane
                localparam int LO = k * 64;
                localparam int W  = (DATA_WIDTH - LO > 64) ? 64 : DATA_WIDTH - LO;
                wire [63:0] lane = keystream(cfg_seed ^ 64'(k + 1), 64'(i_key));
                assign mask[LO +: W] = lane[W-1:0];
            end
        end
    endgenerate

    assign o_data = cfg_scramble_en ? (i_data ^ mask) : i_data;

endmodule
