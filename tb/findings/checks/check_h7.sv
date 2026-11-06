// File: check_h7.sv
// Chức năng: Kiểm tra tái hiện finding H-7 (Keystream bus_scrambler tái sử dụng cho cùng địa chỉ).

`timescale 1ns / 1ps

module check_h7;
    `include "tb_check.svh"

    logic        cfg_scramble_en;
    logic [63:0] cfg_seed;
    logic [63:0] i_key;
    logic [63:0] i_data;
    wire  [63:0] o_data;

    bus_scrambler #(
        .DATA_WIDTH(64),
        .KEY_WIDTH (64)
    ) dut (
        .cfg_scramble_en (cfg_scramble_en),
        .cfg_seed        (cfg_seed),
        .i_key           (i_key),
        .i_data          (i_data),
        .o_data          (o_data)
    );

    logic [63:0] mask1, mask2;

    initial begin
        cfg_scramble_en = 1;
        cfg_seed        = 64'hFEED_FACE_CAFE_BABE;

        // Ghi lần 1 vào địa chỉ 0x1000 với dữ liệu D1
        i_key  = 64'h1000;
        i_data = 64'h1122_3344_5566_7788;
        #1;
        mask1 = o_data ^ i_data;

        // Ghi lần 2 vào cùng địa chỉ 0x1000 với dữ liệu D2 (giao thức bảo mật yêu cầu mặt nạ mới tránh two-time pad)
        #10;
        i_key  = 64'h1000;
        i_data = 64'hAABB_CCDD_EEFF_0011;
        #1;
        mask2 = o_data ^ i_data;

        // Check H-7: Nếu mặt nạ 2 lần ghi cùng địa chỉ trùng nhau hoàn toàn, bus bị lộ hiệu hai bản rõ D1 ^ D2
        tb_check(mask1 != mask2, "H-7: Successive writes to same address must produce distinct keystream masks");

        tb_report();
        $finish;
    end

endmodule
