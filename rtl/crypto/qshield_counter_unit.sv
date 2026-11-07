// File: qshield_counter_unit.sv
// Chức năng: Đơn vị xử lý split counter, cập nhật Counter Block và sinh tweak AES-XTS 128-bit.

`timescale 1ns / 1ps

module qshield_counter_unit (
    input  logic [511:0] i_cb_data,
    input  logic [63:0]  i_line_idx,
    input  logic [3:0]   i_asid,
    input  logic         i_inc,

    output logic [511:0] o_new_cb_data,
    output logic [127:0] o_tweak,
    output logic         o_overflow,
    output logic [63:0]  o_eff_major,
    output logic [6:0]   o_eff_minor
);

    wire [5:0]  slot      = i_line_idx[5:0];
    wire [63:0] cur_major = i_cb_data[511:448];
    wire [6:0]  cur_minor = i_cb_data[slot * 7 +: 7];

    logic [63:0] eff_major;
    logic [6:0]  eff_minor;

    always_comb begin
        if (i_inc) begin
            if (cur_minor == 7'd127) begin
                // Tràn minor: tăng major, thiết lập toàn bộ 64 minor về 0
                o_overflow               = 1'b1;
                eff_major                = cur_major + 1'b1;
                eff_minor                = 7'd0;
                o_new_cb_data            = {eff_major, 448'h0};
            end else begin
                // Tăng minor của dòng chỉ định, giữ nguyên major
                o_overflow               = 1'b0;
                eff_major                = cur_major;
                eff_minor                = cur_minor + 1'b1;
                o_new_cb_data            = i_cb_data;
                o_new_cb_data[slot * 7 +: 7] = eff_minor;
            end
        end else begin
            // Tra cứu kiểm tra tính toàn vẹn (đọc): giữ nguyên giá trị
            o_overflow    = 1'b0;
            eff_major     = cur_major;
            eff_minor     = cur_minor;
            o_new_cb_data = i_cb_data;
        end

        o_eff_major = eff_major;
        o_eff_minor = eff_minor;

        // Sinh tweak AES-XTS 128-bit: {major[63:0], minor[6:0], asid[3:0], L[52:0]}
        o_tweak = {eff_major[63:0], eff_minor[6:0], i_asid[3:0], i_line_idx[52:0]};
    end

endmodule
