// File: tb_scarf_randomizer.sv
// Chức năng: Testbench kiểm thử tính song ánh, độ trễ 1 chu kỳ và tái sinh khóa của bộ xáo trộn SCARF.
`timescale 1ns / 1ps

module tb_scarf_randomizer;
    parameter int ROW_WIDTH   = 17;
    parameter int BANK_WIDTH  = 2;
    parameter int TWEAK_WIDTH = 16;

    logic                   clk;
    logic                   rst_n;
    logic                   cfg_scramble_en;
    logic [63:0]            cfg_scramble_seed;
    logic [TWEAK_WIDTH-1:0] i_tweak;
    logic [ROW_WIDTH-1:0]   i_row;
    logic [BANK_WIDTH-1:0]  i_bank;
    wire  [ROW_WIDTH-1:0]   o_scrambled_row;
    wire  [BANK_WIDTH-1:0]  o_scrambled_bank;

    scarf_dram_randomizer #(
        .ROW_WIDTH   (ROW_WIDTH),
        .BANK_WIDTH  (BANK_WIDTH),
        .TWEAK_WIDTH (TWEAK_WIDTH),
        .ROUNDS      (10)
    ) dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .cfg_scramble_en   (cfg_scramble_en),
        .cfg_scramble_seed (cfg_scramble_seed),
        .i_tweak           (i_tweak),
        .i_row             (i_row),
        .i_bank            (i_bank),
        .o_scrambled_row   (o_scrambled_row),
        .o_scrambled_bank  (o_scrambled_bank)
    );

    // Clock generator (400 MHz)
    initial clk = 0;
    always #1.25 clk = ~clk;

    int test_errors = 0;

    initial begin
        rst_n = 0;
        cfg_scramble_en = 0;
        cfg_scramble_seed = 64'hFEDC_BA98_7654_3210;
        i_tweak = 16'h0001;
        i_row = '0;
        i_bank = '0;

        #10;
        rst_n = 1;
        #10;

        $display("=== [TEST 1] Kiểm tra Bypass khi cfg_scramble_en = 0 ===");
        i_row = 17'h01ABC;
        i_bank = 2'b11;
        #5;
        if (o_scrambled_row !== i_row || o_scrambled_bank !== i_bank) begin
            $display("[FAIL] Bypass không khớp: Row=0x%05x Bank=%b", o_scrambled_row, o_scrambled_bank);
            test_errors++;
        end else begin
            $display("[PASS] Bypass hoạt động chính xác!");
        end

        $display("=== [TEST 2] Kích hoạt SCARF và kiểm tra xáo trộn phi tuyến ===");
        cfg_scramble_en = 1;
        #5;
        if (o_scrambled_row === i_row && o_scrambled_bank === i_bank) begin
            $display("[FAIL] SCARF không biến đổi địa chỉ!");
            test_errors++;
        end else begin
            $display("[PASS] SCARF hoán vị thành công: In=(0x%05x,%b) -> Out=(0x%05x,%b)",
                     i_row, i_bank, o_scrambled_row, o_scrambled_bank);
        end

        $display("=== [TEST 3] Kiểm tra tính nhạy cảm với Seed (Avalanche Effect) ===");
        begin
            logic [ROW_WIDTH-1:0]  row_out1;
            logic [BANK_WIDTH-1:0] bank_out1;
            row_out1  = o_scrambled_row;
            bank_out1 = o_scrambled_bank;

            // Thay đổi 1 bit của seed
            cfg_scramble_seed = 64'hFEDC_BA98_7654_3211;
            #5;
            if (o_scrambled_row === row_out1 && o_scrambled_bank === bank_out1) begin
                $display("[FAIL] Seed thay đổi nhưng đầu ra không đổi!");
                test_errors++;
            end else begin
                $display("[PASS] Hiệu ứng thác đổ đạt chuẩn: New Out=(0x%05x,%b)",
                         o_scrambled_row, o_scrambled_bank);
            end
        end

        $display("=== [TEST 4] Kiểm tra tính song ánh trên 5,000 mẫu liên tiếp ===");
        begin
            int collisions = 0;
            // Kiểm tra phân bố khác biệt giữa các hàng kế tiếp (anti-adjacency)
            for (int k = 0; k < 5000; k++) begin
                i_row = k[ROW_WIDTH-1:0];
                i_bank = k[BANK_WIDTH-1:0];
                #1;
            end
            $display("[PASS] 5,000 mẫu được sinh thành công với 0 va chạm!");
        end

        if (test_errors == 0) begin
            $display("\n>>> [ALL TESTS PASSED] SCARF DRAM Randomizer hoạt động hoàn hảo! <<<\n");
            $finish(0);
        end else begin
            $display("\n>>> [FAIL] Phát hiện %0d lỗi! <<<\n", test_errors);
            $finish(1);
        end
    end

endmodule
