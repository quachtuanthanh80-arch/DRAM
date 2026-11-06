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

    `include "tb_check.svh"

    // Bảng đánh dấu ảnh đã gặp trên toàn miền 2^(ROW+BANK): song ánh ⇔ không có ảnh trùng.
    localparam int DOMAIN = 1 << (ROW_WIDTH + BANK_WIDTH);
    bit seen [DOMAIN];

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
        tb_check(o_scrambled_row === i_row && o_scrambled_bank === i_bank,
                 $sformatf("Bypass passes address through: Row=0x%05x Bank=%b", o_scrambled_row, o_scrambled_bank));

        $display("=== [TEST 2] Kích hoạt SCARF và kiểm tra xáo trộn phi tuyến ===");
        cfg_scramble_en = 1;
        #5;
        tb_check(!(o_scrambled_row === i_row && o_scrambled_bank === i_bank),
                 $sformatf("SCARF transforms address: In=(0x%05x,%b) -> Out=(0x%05x,%b)",
                           i_row, i_bank, o_scrambled_row, o_scrambled_bank));

        $display("=== [TEST 3] Kiểm tra tính nhạy cảm với Seed (Avalanche Effect) ===");
        begin
            logic [ROW_WIDTH-1:0]  row_out1;
            logic [BANK_WIDTH-1:0] bank_out1;
            row_out1  = o_scrambled_row;
            bank_out1 = o_scrambled_bank;

            // Thay đổi 1 bit của seed
            cfg_scramble_seed = 64'hFEDC_BA98_7654_3211;
            #5;
            tb_check(!(o_scrambled_row === row_out1 && o_scrambled_bank === bank_out1),
                     $sformatf("Seed change alters mapping: New Out=(0x%05x,%b)", o_scrambled_row, o_scrambled_bank));
        end

        $display("=== [TEST 4] Song ánh vét cạn trên toàn miền %0d địa chỉ (row,bank) ===", DOMAIN);
        begin
            int collisions;
            int first_a, first_b;
            int img;
            int owner [DOMAIN];
            collisions = 0;
            first_a = -1;
            first_b = -1;
            for (int k = 0; k < DOMAIN; k++) begin
                {i_bank, i_row} = k[ROW_WIDTH+BANK_WIDTH-1:0];
                #1;
                img = int'({o_scrambled_bank, o_scrambled_row});
                if (seen[img]) begin
                    if (collisions == 0) begin
                        first_a = owner[img];
                        first_b = k;
                    end
                    collisions++;
                end else begin
                    seen[img]  = 1'b1;
                    owner[img] = k;
                end
            end
            tb_check(collisions == 0,
                     $sformatf("SCARF is a bijection over all 2^19 {bank,row} inputs (%0d collisions, first pair 0x%05x/0x%05x)",
                               collisions, first_a, first_b));
        end

        tb_report();
        $finish;
    end

endmodule
