// File: aes_tweak_gen.sv
// Chức năng: [DEPRECATED - C-2] Khối sinh tweak cũ không có AES; đã thay bằng qshield_xts_tweak_unit chuẩn IEEE 1619.

`timescale 1ns / 1ps

module aes_tweak_gen
    import aes_pkg::*;
#(
    parameter int AddrWidth = 32
) (
    input  logic                   clk,
    input  logic                   rst_n,

    // Trigger from AXI Address Channel (AW or AR)
    input  logic                   addr_valid,
    input  logic [AddrWidth-1:0]   addr_in,
    input  logic [127:0]           tweak_key,

    output logic                   tweak_ready,
    output logic [127:0]           tweak_t0,
    output logic [127:0]           tweak_t1,
    output logic [127:0]           tweak_t2,
    output logic [127:0]           tweak_t3
);

    // Module này đã bị đánh dấu DEPRECATED (Finding C-2).
    // Trong kiến trúc mới, toàn bộ việc sinh tweak AES-256-XTS được thực hiện qua
    // qshield_xts_tweak_unit với khoá K2 256-bit được mở rộng đầy đủ.

    assign tweak_ready = 1'b0;
    assign tweak_t0    = 128'h0;
    assign tweak_t1    = 128'h0;
    assign tweak_t2    = 128'h0;
    assign tweak_t3    = 128'h0;

endmodule: aes_tweak_gen
