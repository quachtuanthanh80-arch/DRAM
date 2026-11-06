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
    wire                   o_wr_valid;

    logic [ASID_WIDTH-1:0] i_rd_asid;
    logic                  i_rd_c_bit;
    wire  [255:0]          o_rd_key;
    wire  [127:0]          o_rd_tweak_key;
    wire                   o_rd_bypass;
    wire                   o_rd_valid;

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
        .o_wr_valid      (o_wr_valid),
        .i_rd_asid       (i_rd_asid),
        .i_rd_c_bit      (i_rd_c_bit),
        .o_rd_key        (o_rd_key),
        .o_rd_tweak_key  (o_rd_tweak_key),
        .o_rd_bypass     (o_rd_bypass),
        .o_rd_valid      (o_rd_valid)
    );

    initial clk = 0;
    always #1.25 clk = ~clk;

    `include "tb_check.svh"

    initial begin
        rst_n = 0;
        s_apb_psel = 0;
        s_apb_penable = 0;
        s_apb_pwrite = 0;
        s_apb_paddr = '0;
        s_apb_pwdata = '0;
        s_apb_pprot = 3'b001; // AMBA APB4: secure + privileged
        i_wr_asid = 0;
        i_wr_c_bit = 1;
        i_rd_asid = 1;
        i_rd_c_bit = 1;

        #10;
        rst_n = 1;
        #10;

        $display("=== [TEST 1] Kiểm tra cô lập khóa giữa các máy ảo (Key Isolation) ===");
        // Sau reset không có khoá dùng được: valid = 0 cho mọi ASID
        tb_check(o_wr_valid === 1'b0 && o_rd_valid === 1'b0, "No usable key after reset (valid = 0 for VM0 and VM1)");
        // Nạp hai khoá khác nhau cho VM0 và VM1 rồi kiểm tra mỗi VM chỉ thấy khoá của mình
        for (int v = 0; v < 2; v++) begin
            s_apb_psel = 1; s_apb_penable = 1; s_apb_pwrite = 1;
            s_apb_paddr = {4'(v), 4'h0};
            s_apb_pwdata = 32'hC0DE_0000 | 32'(v);
            @(posedge clk); #0.1;
            s_apb_paddr = {4'(v), 4'hC};
            s_apb_pwdata = 32'h1;
            @(posedge clk); #0.1;
        end
        s_apb_psel = 0; s_apb_penable = 0; s_apb_pwrite = 0;
        #5;
        tb_check(o_wr_valid === 1'b1 && o_rd_valid === 1'b1, "Both VMs valid after programming");
        tb_check(!(o_wr_key === o_rd_key), $sformatf("Cô lập khóa thành công: VM0 Key[31:0]=0x%08x, VM1 Key[31:0]=0x%08x" , o_wr_key[31:0], o_rd_key[31:0]));

        $display("=== [TEST 2] Kiểm tra logic Bypass theo C-Bit ===");
        i_wr_c_bit = 0; // DMA unencrypted
        #5;
        tb_check(!(!o_wr_bypass), "C-bit = 0 kích hoạt bypass thành công!");

        $display("=== [TEST 3] Kiểm tra bảo vệ quyền đặc quyền APB4 (Privilege Protection) ===");
        // Ghi với non-privileged access (pprot[1] = 0)
        s_apb_psel = 1;
        s_apb_penable = 1;
        s_apb_pwrite = 1;
        s_apb_pprot = 3'b000; // User mode (unprivileged)
        s_apb_paddr = 8'h00;
        s_apb_pwdata = 32'hDEAD_BEEF;
        #2.5;

        tb_check(!(!s_apb_pslverr), "Từ chối truy cập không đặc quyền và báo PSLVERR thành công!");

        s_apb_psel = 0;
        s_apb_penable = 0;
        #5;

        $display("=== [TEST 4] Cập nhật khóa hợp lệ từ Hypervisor (Privileged APB4 Write) ===");
        s_apb_psel = 1;
        s_apb_penable = 1;
        s_apb_pwrite = 1;
        s_apb_pprot = 3'b001; // Secure privileged
        s_apb_paddr = 8'h00; // ASID 0, Word 0
        s_apb_pwdata = 32'h1234_5678;
        #2.5;

        s_apb_psel = 0;
        s_apb_penable = 0;
        i_wr_asid = 0;
        i_wr_c_bit = 1;
        #5;

        tb_check(!(o_wr_key[31:0] !== 32'h1234_5678), $sformatf("Cập nhật khóa thành công từ mức đặc quyền: New Key[31:0]=0x%08x" , o_wr_key[31:0]));

        // Red team S7: AMBA PPROT[0]=privileged, PPROT[1]=non-secure. Truy cập non-secure/unprivileged phải bị từ chối,
        // và khóa không bao giờ được đọc ngược qua APB (write-only key).
        $display("=== [TEST 5] S7: AMBA PPROT semantics & key readback ===");
        s_apb_psel = 1;
        s_apb_penable = 1;
        s_apb_pwrite = 0;
        s_apb_paddr = 8'h00;
        s_apb_pprot = 3'b010;
        #1;
        tb_check(s_apb_pslverr === 1'b1, "Non-secure unprivileged access (PPROT=3'b010) must get PSLVERR");
        s_apb_pprot = 3'b001;
        #1;
        tb_check(s_apb_pslverr === 1'b0, "Secure privileged access (PPROT=3'b001) must be accepted");
        // Khóa phải là write-only với mọi giá trị PPROT, kể cả secure privileged; còn bản non-secure privileged phải bị từ chối
        tb_check(s_apb_prdata === 32'h0, $sformatf("Key word must not be readable over APB (secure privileged), got 0x%08x", s_apb_prdata));
        s_apb_pprot = 3'b011;
        #1;
        tb_check(s_apb_pslverr === 1'b1 && s_apb_prdata === 32'h0,
                 $sformatf("Non-secure privileged access (PPROT=3'b011) rejected, prdata 0x%08x", s_apb_prdata));
        s_apb_psel = 0;
        s_apb_penable = 0;

        tb_report();
        $finish;
    end

endmodule
