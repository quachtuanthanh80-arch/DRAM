// File: tb_qshield_counter_unit.sv
// Chức năng: Testbench kiểm tra toàn diện đơn vị xử lý split counter và rollover.

`timescale 1ns / 1ps

module tb_qshield_counter_unit;
    `include "tb_check.svh"

    logic [511:0] i_cb_data;
    logic [63:0]  i_line_idx;
    logic [3:0]   i_asid;
    logic         i_inc;

    wire  [511:0] o_new_cb_data;
    wire  [127:0] o_tweak;
    wire          o_overflow;
    wire  [63:0]  o_eff_major;
    wire  [6:0]   o_eff_minor;

    qshield_counter_unit dut (
        .i_cb_data     (i_cb_data),
        .i_line_idx    (i_line_idx),
        .i_asid        (i_asid),
        .i_inc         (i_inc),
        .o_new_cb_data (o_new_cb_data),
        .o_tweak       (o_tweak),
        .o_overflow    (o_overflow),
        .o_eff_major   (o_eff_major),
        .o_eff_minor   (o_eff_minor)
    );

    integer m;
    integer step_ok = 1;
    logic [63:0] test_major;

    initial begin
        $display("================================================================================");
        $display("  TB_QSHIELD_COUNTER_UNIT: VERIFYING SPLIT COUNTER INCREMENT & ROLLOVER");
        $display("================================================================================");

        test_major = 64'hCAFE_BABE_0123_4567;
        i_asid     = 4'hA;
        i_line_idx = 64'h0000_0000_0000_1005; // slot = 5 (1005 % 64 = 5)
        i_inc      = 1'b1;

        // 1. Kiểm tra tăng tuần tự mọi giá trị minor từ 0 đến 126
        i_cb_data = {test_major, 448'h0};
        for (m = 0; m < 127; m = m + 1) begin
            i_cb_data[5*7 +: 7] = m[6:0];
            #1;
            if (o_overflow !== 1'b0 ||
                o_eff_major !== test_major ||
                o_eff_minor !== (m[6:0] + 1'b1) ||
                o_new_cb_data[5*7 +: 7] !== (m[6:0] + 1'b1) ||
                o_tweak !== {test_major, (m[6:0] + 1'b1), i_asid, i_line_idx[52:0]}) begin
                step_ok = 0;
            end
        end
        tb_check(step_ok == 1, "Counter unit correctly increments minor across all values 0..126 without overflow");

        // 2. Kiểm tra tràn minor tại 127 (minor rollover)
        // Khi minor[5] = 127: o_overflow phải bật, major tăng 1, toàn bộ 64 minor reset về 0
        i_cb_data = {test_major, 448'h0};
        i_cb_data[5*7 +: 7] = 7'd127;
        // Đặt thêm dữ liệu ở slot khác để đảm bảo toàn bộ minor được reset về 0
        i_cb_data[1*7 +: 7] = 7'd42;
        i_cb_data[63*7 +: 7] = 7'd99;
        #1;
        tb_check(o_overflow == 1'b1, "Overflow flag asserts when minor reaches 127 and increment requested");
        tb_check(o_eff_major == (test_major + 1'b1), "Effective major increments by 1 on overflow");
        tb_check(o_eff_minor == 7'd0, "Effective minor resets to 0 on overflow");
        tb_check(o_new_cb_data[511:448] == (test_major + 1'b1), "New CB major is updated to major + 1");
        tb_check(o_new_cb_data[447:0] == 448'h0, "All 64 minors in new CB are cleared to zero on rollover");
        tb_check(o_tweak == {(test_major + 1'b1), 7'd0, i_asid, i_line_idx[52:0]}, "Tweak format correctly embeds eff_major and eff_minor 0 on overflow");

        // 3. Kiểm tra chế độ đọc (i_inc = 0)
        i_inc = 1'b0;
        i_cb_data = {test_major, 448'h0};
        i_cb_data[5*7 +: 7] = 7'd77;
        #1;
        tb_check(o_overflow == 1'b0, "Overflow flag remains 0 during read lookup");
        tb_check(o_eff_major == test_major && o_eff_minor == 7'd77, "Read lookup returns current counter values unchanged");
        tb_check(o_new_cb_data == i_cb_data, "New CB data identical to input CB data during read lookup");
        tb_check(o_tweak == {test_major, 7'd77, i_asid, i_line_idx[52:0]}, "Read lookup tweak reflects current major and minor");

        // 4. Kiểm tra trên nhiều slot biên: slot 0 và slot 63
        i_inc = 1'b1;
        i_line_idx = 64'd0; // slot 0
        i_cb_data = {test_major, 448'h0};
        i_cb_data[0 +: 7] = 7'd126;
        #1;
        tb_check(o_eff_minor == 7'd127 && o_new_cb_data[0 +: 7] == 7'd127, "Slot 0 increments to 127 correctly");

        i_line_idx = 64'd63; // slot 63
        i_cb_data = {test_major, 448'h0};
        i_cb_data[63*7 +: 7] = 7'd126;
        #1;
        tb_check(o_eff_minor == 7'd127 && o_new_cb_data[63*7 +: 7] == 7'd127, "Slot 63 increments to 127 correctly");

        tb_report();
        $finish;
    end

endmodule
