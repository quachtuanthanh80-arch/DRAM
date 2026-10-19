// File: tb_pcie_cxl_io_shim.sv
// Chức năng: Testbench SystemVerilog tự kiểm chứng cầu nối PCIe / CXL.io APB CSR và bảng thanh ghi CXL DVSEC Header.
`timescale 1ns / 1ps

module tb_pcie_cxl_io_shim;

    logic        clk = 0;
    always #2.0 clk = ~clk; // 250 MHz

    logic        rst_n;
    logic [31:0] s_axil_awaddr;
    logic [2:0]  s_axil_awprot;
    logic        s_axil_awvalid;
    logic        s_axil_awready;

    logic [31:0] s_axil_wdata;
    logic [3:0]  s_axil_wstrb;
    logic        s_axil_wvalid;
    logic        s_axil_wready;

    logic [1:0]  s_axil_bresp;
    logic        s_axil_bvalid;
    logic        s_axil_bready;

    logic [31:0] s_axil_araddr;
    logic [2:0]  s_axil_arprot;
    logic        s_axil_arvalid;
    logic        s_axil_arready;

    logic [31:0] s_axil_rdata;
    logic [1:0]  s_axil_rresp;
    logic        s_axil_rvalid;
    logic        s_axil_rready;

    logic [1:0]  o_cfg_crypto_profile;
    logic [18:0] o_cfg_epoch_nonce;
    logic [7:0]  o_cfg_default_key_id;
    logic        o_sec_fault_irq;
    logic        o_tmr_alert;

    pcie_cxl_io_csr_top #(
        .AxilAddrWidth(32),
        .AxilDataWidth(32)
    ) dut (
        .clk                 (clk),
        .rst_n               (rst_n),
        .s_axil_awaddr        (s_axil_awaddr),
        .s_axil_awprot        (s_axil_awprot),
        .s_axil_awvalid       (s_axil_awvalid),
        .s_axil_awready       (s_axil_awready),
        .s_axil_wdata         (s_axil_wdata),
        .s_axil_wstrb         (s_axil_wstrb),
        .s_axil_wvalid        (s_axil_wvalid),
        .s_axil_wready        (s_axil_wready),
        .s_axil_bresp         (s_axil_bresp),
        .s_axil_bvalid        (s_axil_bvalid),
        .s_axil_bready        (s_axil_bready),
        .s_axil_araddr        (s_axil_araddr),
        .s_axil_arprot        (s_axil_arprot),
        .s_axil_arvalid       (s_axil_arvalid),
        .s_axil_arready       (s_axil_arready),
        .s_axil_rdata         (s_axil_rdata),
        .s_axil_rresp         (s_axil_rresp),
        .s_axil_rvalid        (s_axil_rvalid),
        .s_axil_rready        (s_axil_rready),
        .o_cfg_crypto_profile (o_cfg_crypto_profile),
        .o_cfg_epoch_nonce    (o_cfg_epoch_nonce),
        .o_cfg_default_key_id (o_cfg_default_key_id),
        .o_sec_fault_irq      (o_sec_fault_irq),
        .o_tmr_alert          (o_tmr_alert)
    );

    task automatic axil_write(input [31:0] addr, input [31:0] data);
        s_axil_awaddr  <= addr;
        s_axil_awprot  <= 3'b000;
        s_axil_awvalid <= 1'b1;
        s_axil_wdata   <= data;
        s_axil_wstrb   <= 4'hF;
        s_axil_wvalid  <= 1'b1;
        s_axil_bready  <= 1'b1;

        @(posedge clk);
        while (!(s_axil_awready && s_axil_wready)) @(posedge clk);
        s_axil_awvalid <= 1'b0;
        s_axil_wvalid  <= 1'b0;

        while (!s_axil_bvalid) @(posedge clk);
        s_axil_bready <= 1'b0;
        @(posedge clk);
    endtask

    task automatic axil_read(input [31:0] addr, output [31:0] data);
        s_axil_araddr  <= addr;
        s_axil_arprot  <= 3'b000;
        s_axil_arvalid <= 1'b1;
        s_axil_rready  <= 1'b1;

        @(posedge clk);
        while (!s_axil_arready) @(posedge clk);
        s_axil_arvalid <= 1'b0;

        while (!s_axil_rvalid) @(posedge clk);
        data = s_axil_rdata;
        s_axil_rready <= 1'b0;
        @(posedge clk);
    endtask

    logic [31:0] rdata;

    initial begin
        rst_n          = 0;
        s_axil_awaddr  = 0;
        s_axil_awprot  = 0;
        s_axil_awvalid = 0;
        s_axil_wdata   = 0;
        s_axil_wstrb   = 0;
        s_axil_wvalid  = 0;
        s_axil_bready  = 0;
        s_axil_araddr  = 0;
        s_axil_arprot  = 0;
        s_axil_arvalid = 0;
        s_axil_rready  = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        $display("=== START: tb_pcie_cxl_io_shim ===");

        // 1. Verify DVSEC Header Reads
        axil_read(32'h100, rdata);
        if (rdata !== 32'h03C11E98) begin
            $display("[FAIL] DVSEC Hdr1 mismatch: %h", rdata);
            $fatal(1);
        end

        axil_read(32'h108, rdata);
        if (rdata !== 32'h00000005) begin
            $display("[FAIL] CXL Cap mismatch: %h", rdata);
            $fatal(1);
        end

        // 2. Configure Q-Shield TMR Security CSRs via CXL.io APB bridge
        axil_write(32'h040, 32'h00000002); // Profile 2
        axil_read(32'h040, rdata);
        if ((rdata & 32'h3) !== 32'h2 || o_cfg_crypto_profile !== 2'b10) begin
            $display("[FAIL] Profile mismatch: %h", rdata);
            $fatal(1);
        end

        axil_write(32'h048, 32'h0003ABCD); // Epoch Nonce
        axil_read(32'h048, rdata);
        if ((rdata & 32'h7FFFF) !== 32'h0003ABCD || o_cfg_epoch_nonce !== 19'h3ABCD) begin
            $display("[FAIL] Nonce mismatch: %h", rdata);
            $fatal(1);
        end

        $display("[PASS] PCIe CXL.io APB Shim Verification Completed Successfully");
        $finish;
    end

endmodule
