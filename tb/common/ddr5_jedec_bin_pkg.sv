// File:      ddr5_jedec_bin_pkg.sv
// Chức năng: Bảng thông số JEDEC DDR5-3200 16 Gb theo ps chỉ dùng cho testbench (gõ lại từ JESD79-5 / spec_v2 §1.5), độc lập với tham số DUT.
`timescale 1ns / 1ps

package ddr5_jedec_bin_pkg;
    // Giá trị tuyệt đối: checker đo (chu kỳ * TCK_PS) so với các hằng này nên không "mù" khi DUT sai tham số
    localparam longint TRCD_PS      = 17500;
    localparam longint TRP_PS       = 17500;
    localparam longint TRAS_PS      = 32000;
    localparam longint TRC_PS       = 49500;      // tRAS + tRP
    localparam longint TRRD_S_PS    = 5000;
    localparam longint TRRD_L_PS    = 5000;
    localparam longint TFAW_PS      = 25000;
    localparam longint TCCD_S_PS    = 5000;
    localparam longint TCCD_L_PS    = 5000;
    localparam longint TCCD_L_WR_PS = 20000;
    localparam longint TWR_PS       = 30000;
    localparam longint TRTP_PS      = 7500;
    localparam longint TWTR_S_PS    = 2500;
    localparam longint TWTR_L_PS    = 10000;
    localparam longint TRFC_PS      = 295000;
    // tRFMab lấy bằng tRFC1 (bảo thủ như spec_v2 §1.5)
    localparam longint TRFM_PS      = 295000;
    localparam longint TREFI_PS     = 3900000;
    // tRAS(max) = 9 x tREFI
    localparam longint TRASMAX_PS   = 35100000;
    // CWL + BL16/2 của bin 3200C: mốc sớm nhất có thể của beat ghi cuối trên chân DRAM
    localparam longint TCWL_BL_PS   = 21250;
    localparam int     MAX_POSTPONE = 4;
endpackage
