// File: tb_multi_vm_key_table.sv
// Chức năng: Testbench kiểm thử bảng quản lý khóa Multi-ASID và phân quyền APB4 theo chuẩn AMD SEV.
`timescale 1ns / 1ps

module tb_multi_vm_key_table;
    parameter int ASID_WIDTH = 4;

    logic        clk;
    logic        rst_n;

    logic        s_apb_psel;
    logic        s_apb_penable;
    logic        s_apb_pwrite;
    logic [7:0]  s_apb_paddr;
    logic [31:0] s_apb_pwdata;
    logic [2:0]  s_apb_pprot;
    wire  [31:0] s_apb_prdata;
    wire         s_apb_pready;
    wire         s_apb_pslverr;

    logic [ASID_WIDTH-1:0] i_wr_asid;
    logic                  i_wr_c_bit;
    wire  [255:0]          o_wr_key;
    wire  [127:0]          o_wr_tweak_key;
    wire                   o_wr_bypass;

    logic [ASID_WIDTH-1:0] i_rd_asid;
    logic                  i_rd_c_bit;
    wire  [255:0]          o_rd_key;
    wire  [127:0]          o_rd_tweak_key;
    wire                   o_rd_bypass;

    multi_vm_key_table #(
        .ASID_WIDTH (ASID_WIDTH)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .s_apb_psel      (s_apb_psel),
        .s_apb_penable   (s_apb_penable),
        .s_apb_pwrite    (s_apb_pwrite),
        .s_apb_paddr     (s_apb_paddr),
        .s_apb_pwdata    (s_apb_pwdata),
        .s_apb_pprot     (s_apb_pprot),
        .s_apb_prdata    (s_apb_prdata),
        .s_apb_pready    (s_apb_pready),
        .s_apb_pslverr   (s_apb_pslverr),
        .i_wr_asid       (i_wr_asid),
        .i_wr_c_bit      (i_wr_c_bit),
        .o_wr_key        (o_wr_key),
        .o_wr_tweak_key  (o_wr_tweak_key),
        .o_wr_bypass     (o_wr_bypass),
        .i_rd_asid       (i_rd_asid),
        .i_rd_c_bit      (i_rd_c_bit),
        .o_rd_key        (o_rd_key),
        .o_rd_tweak_key  (o_rd_tweak_key),
        .o_rd_bypass     (o_rd_bypass)
    );

    initial clk = 0;
    always #1.25 clk = ~clk;

    int test_errors = 0;

    initial begin
        rst_n = 0;
        s_apb_psel = 0;
        s_apb_penable = 0;
        s_apb_pwrite = 0;
        s_apb_paddr = '0;
        s_apb_pwdata = '0;
        s_apb_pprot = 3'b010; // Privileged
        i_wr_asid = 0;
        i_wr_c_bit = 1;
        i_rd_asid = 1;
        i_rd_c_bit = 1;

        #10;
        rst_n = 1;
        #10;

        $display("=== [TEST 1] Kiểm tra cô lập khóa giữa các máy ảo (Key Isolation) ===");
        #5;
        if (o_wr_key === o_rd_key) begin
            $display("[FAIL] Khóa của VM0 và VM1 trùng lặp!");
            test_errors++;
        end else begin
            $display("[PASS] Cô lập khóa thành công: VM0 Key[31:0]=0x%08x, VM1 Key[31:0]=0x%08x",
                     o_wr_key[31:0], o_rd_key[31:0]);
        end

        $display("=== [TEST 2] Kiểm tra logic Bypass theo C-Bit ===");
        i_wr_c_bit = 0; // DMA unencrypted
        #5;
        if (!o_wr_bypass) begin
            $display("[FAIL] C-bit = 0 nhưng o_wr_bypass không tích cực!");
            test_errors++;
        end else begin
            $display("[PASS] C-bit = 0 kích hoạt bypass thành công!");
        end

        $display("=== [TEST 3] Kiểm tra bảo vệ quyền đặc quyền APB4 (Privilege Protection) ===");
        // Ghi với non-privileged access (pprot[1] = 0)
        s_apb_psel = 1;
        s_apb_penable = 1;
        s_apb_pwrite = 1;
        s_apb_pprot = 3'b000; // User mode (unprivileged)
        s_apb_paddr = 8'h00;
        s_apb_pwdata = 32'hDEAD_BEEF;
        #2.5;

        if (!s_apb_pslverr) begin
            $display("[FAIL] Không báo lỗi PSLVERR khi truy cập trái phép!");
            test_errors++;
        end else begin
            $display("[PASS] Từ chối truy cập không đặc quyền và báo PSLVERR thành công!");
        end

        s_apb_psel = 0;
        s_apb_penable = 0;
        #5;

        $display("=== [TEST 4] Cập nhật khóa hợp lệ từ Hypervisor (Privileged APB4 Write) ===");
        s_apb_psel = 1;
        s_apb_penable = 1;
        s_apb_pwrite = 1;
        s_apb_pprot = 3'b010; // Privileged mode
        s_apb_paddr = 8'h00; // ASID 0, Word 0
        s_apb_pwdata = 32'h1234_5678;
        #2.5;

        s_apb_psel = 0;
        s_apb_penable = 0;
        i_wr_asid = 0;
        i_wr_c_bit = 1;
        #5;

        if (o_wr_key[31:0] !== 32'h1234_5678) begin
            $display("[FAIL] Cập nhật khóa không thành công: Got 0x%08x", o_wr_key[31:0]);
            test_errors++;
        end else begin
            $display("[PASS] Cập nhật khóa thành công từ mức đặc quyền: New Key[31:0]=0x%08x", o_wr_key[31:0]);
        end

        if (test_errors == 0) begin
            $display("\n>>> [ALL TESTS PASSED] Multi-VM Key Table hoạt động hoàn hảo! <<<\n");
            $finish(0);
        end else begin
            $display("\n>>> [FAIL] Phát hiện %0d lỗi! <<<\n", test_errors);
            $finish(1);
        end
    end

endmodule
