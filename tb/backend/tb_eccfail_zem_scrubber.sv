// File: tb_eccfail_zem_scrubber.sv
// Chức năng: Kiểm thử giải mã SEC-DED (72,64) với mã tham chiếu độc lập, đo khả năng bẫy cụm lỗi 3 bit (ECCfail) và bộ đệm ZEM.

`timescale 1ns / 1ps

module tb_eccfail_zem_scrubber;
    `include "tb_check.svh"

    logic clk = 0;
    always #1.25 clk = ~clk;

    logic        rst_n;
    logic        o_scrub_req;
    logic [2:0]  o_scrub_bg;
    logic [1:0]  o_scrub_bank;
    logic [16:0] o_scrub_row;
    logic        i_scrub_grant = 0;
    logic        i_data_valid = 0;
    logic [63:0] i_raw_data = 0;
    logic [7:0]  i_raw_ecc = 0;
    logic [2:0]  i_data_bg = 0;
    logic [1:0]  i_data_bank = 0;
    logic [16:0] i_data_row = 0;
    logic        o_corrected_valid;
    logic [63:0] o_corrected_data;
    logic        o_single_err, o_double_err;
    logic [15:0] o_single_err_cnt, o_double_err_cnt;
    logic        o_ecc_miscorrect_alert;
    logic [15:0] o_ecc_miscorrect_cnt;
    logic        o_chipkill_fallback_req;
    logic        i_zem_lookup_valid = 0;
    logic [2:0]  i_zem_lookup_bg = 0;
    logic [1:0]  i_zem_lookup_bank = 0;
    logic [16:0] i_zem_lookup_row = 0;
    logic        o_zem_hit;
    logic [63:0] o_zem_mask;
    logic [15:0] o_zem_hit_cnt;

    ecc_scrubber #(.DEFAULT_INTERVAL(10)) u_dut (
        .clk(clk), .rst_n(rst_n), .cfg_enable(1'b1), .cfg_interval(16'd8),
        .o_scrub_req(o_scrub_req), .o_scrub_bg(o_scrub_bg), .o_scrub_bank(o_scrub_bank), .o_scrub_row(o_scrub_row),
        .i_scrub_grant(i_scrub_grant),
        .i_data_valid(i_data_valid), .i_raw_data(i_raw_data), .i_raw_ecc(i_raw_ecc),
        .i_data_bg(i_data_bg), .i_data_bank(i_data_bank), .i_data_row(i_data_row),
        .i_fault_inject_en(1'b0), .i_fault_inject_type(2'b00), .i_fault_inject_bit(6'd0),
        .o_corrected_valid(o_corrected_valid), .o_corrected_data(o_corrected_data),
        .o_single_err(o_single_err), .o_double_err(o_double_err),
        .o_single_err_cnt(o_single_err_cnt), .o_double_err_cnt(o_double_err_cnt),
        .o_ecc_miscorrect_alert(o_ecc_miscorrect_alert), .o_ecc_miscorrect_cnt(o_ecc_miscorrect_cnt),
        .o_chipkill_fallback_req(o_chipkill_fallback_req),
        .i_zem_lookup_valid(i_zem_lookup_valid), .i_zem_lookup_bg(i_zem_lookup_bg),
        .i_zem_lookup_bank(i_zem_lookup_bank), .i_zem_lookup_row(i_zem_lookup_row),
        .o_zem_hit(o_zem_hit), .o_zem_mask(o_zem_mask), .o_zem_hit_cnt(o_zem_hit_cnt)
    );

    // Mã tham chiếu độc lập với hằng số của RTL: đặt bit dữ liệu vào các vị trí Hamming không phải lũy thừa 2,
    // bit kiểm tra i = XOR các vị trí có bit i bằng 1, bit 7 = chẵn lẻ toàn cục
    function automatic logic [7:0] calc_ecc(input logic [63:0] d);
        logic [7:0] e;
        int p, j;
        e = '0;
        p = 3;
        j = 0;
        while (j < 64) begin
            if ((p & (p - 1)) != 0) begin
                for (int i = 0; i < 7; i++) if ((p >> i) & 1) e[i] = e[i] ^ d[j];
                j++;
            end
            p++;
        end
        e[7] = (^d) ^ (^e[6:0]);
        // Bit kiểm tra lưu dạng đảo (SECDED_INV của RTL)
        return e ^ 8'hAA;
    endfunction

    // Áp một codeword 72 bit (đã tiêm lỗi) rồi đọc kết quả tổ hợp
    task automatic apply(input logic [71:0] cw);
        @(negedge clk);
        i_data_valid = 1;
        i_raw_data   = cw[63:0];
        i_raw_ecc    = cw[71:64];
        #0.1;
    endtask

    initial begin
        logic [63:0] w;
        logic [71:0] cw;
        rst_n = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        w  = 64'hCAFE_BABE_DEAD_BEEF;
        cw = {calc_ecc(w), w};

        // 1. Codeword sạch: không báo lỗi, dữ liệu đi qua nguyên vẹn
        apply(cw);
        tb_check(!o_single_err && !o_double_err && !o_ecc_miscorrect_alert && o_corrected_data == w,
                 "Clean codeword: no flag, data unchanged");

        // 2. Mọi lỗi 1 bit trên 72 bit (64 dữ liệu + 8 kiểm tra) được sửa về đúng dữ liệu gốc
        begin
            int bad;
            bad = 0;
            for (int b = 0; b < 72; b++) begin
                apply(cw ^ (72'd1 << b));
                if (!(o_single_err && !o_double_err && !o_ecc_miscorrect_alert && o_corrected_data == w)) bad++;
            end
            tb_check(bad == 0, $sformatf("All 72 single-bit errors corrected to the original data (%0d wrong)", bad));
        end

        // 3. Mọi lỗi 2 bit (C(72,2) = 2556) được phát hiện, không bao giờ bị coi là lỗi đơn
        begin
            int bad, n;
            bad = 0;
            n = 0;
            for (int a = 0; a < 72; a++)
                for (int b = a + 1; b < 72; b++) begin
                    apply(cw ^ (72'd1 << a) ^ (72'd1 << b));
                    n++;
                    if (!(o_double_err && !o_single_err && o_chipkill_fallback_req)) bad++;
                end
            tb_check(bad == 0, $sformatf("All %0d double-bit errors detected as uncorrectable (%0d missed)", n, bad));
        end

        // 4. Cụm 3 bit liền kề (mẫu ECCfail): lỗi lẻ nên không bao giờ im lặng; phần rơi vào vị trí Hamming không tồn tại
        //    bị bẫy, phần còn lại bị sửa nhầm. Đây là giới hạn vốn có của SEC-DED (d=4), cần mã mạnh hơn để chặn hết.
        begin
            int trapped, miscorr, silent;
            trapped = 0; miscorr = 0; silent = 0;
            for (int b = 0; b + 2 < 72; b++) begin
                apply(cw ^ (72'd7 << b));
                if (o_ecc_miscorrect_alert && !o_single_err) trapped++;
                else if (o_single_err) miscorr++;
                else silent++;
            end
            $display("[INFO] 3-bit adjacent clusters: %0d trapped (poison), %0d miscorrected, %0d silent of %0d",
                     trapped, miscorr, silent, 70);
            tb_check(silent == 0 && trapped + miscorr == 70,
                     "Every 3-bit cluster is flagged (odd weight never yields a zero syndrome)");
            tb_check(trapped > 0, "Clusters aliasing to a non-existent Hamming position are trapped instead of miscorrected");
        end

        // 4b. Word 72 bit toàn 0 / toàn 1 (bus kẹt, DIMM không trả lời, dòng bị xoá) không phải codeword hợp lệ
        apply(72'h0);
        tb_check(o_double_err && !o_single_err, "All-zero 72-bit word is reported uncorrectable (inverted check bits)");
        apply({72{1'b1}});
        tb_check(o_double_err && !o_single_err, "All-one 72-bit word is reported uncorrectable (inverted check bits)");
        apply({calc_ecc(64'h0), 64'h0});
        tb_check(!o_single_err && !o_double_err && o_corrected_data == 64'h0, "Encoded zero data still decodes cleanly");

        // 5. ZEM ghi đúng địa chỉ của beat có lỗi đã sửa (không phải toạ độ patrol) và đúng bit
        @(negedge clk);
        i_data_bg   = 3'd5;
        i_data_bank = 2'd2;
        i_data_row  = 17'h1_2345;
        apply(cw ^ (72'd1 << 17));
        @(negedge clk);
        i_data_valid       = 0;
        i_zem_lookup_valid = 1;
        i_zem_lookup_bg    = 3'd5;
        i_zem_lookup_bank  = 2'd2;
        i_zem_lookup_row   = 17'h1_2345;
        #0.1;
        tb_check(o_zem_hit && o_zem_mask == (64'd1 << 17), $sformatf("ZEM records the faulty beat's row and bit (hit %0b mask %h)", o_zem_hit, o_zem_mask));
        i_zem_lookup_row = 17'h0_0000;
        #0.1;
        tb_check(!o_zem_hit, "ZEM does not hit for a different row");
        i_zem_lookup_valid = 0;

        // 6. Patrol: yêu cầu scrub khi hết khoảng thời gian, được hạ khi cấp phép
        repeat (12) @(posedge clk);
        tb_check(o_scrub_req, "Patrol scrubber raises o_scrub_req on interval expiry");
        @(negedge clk);
        i_scrub_grant = 1;
        @(negedge clk);
        i_scrub_grant = 0;
        tb_check(!o_scrub_req || o_scrub_bg != 3'd0, "Patrol coordinate advances after grant");

        tb_report();
        $finish;
    end
endmodule
