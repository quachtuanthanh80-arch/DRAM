// File: check_c1.sv
// Chức năng: Kiểm tra tái hiện finding C-1 (qshield_crypto_top không nằm trên đường dữ liệu, o_wr_valid không bao giờ lên).

`timescale 1ns / 1ps

module check_c1;
    `include "tb_check.svh"

    localparam int IdWidth    = 8;
    localparam int AddrWidth  = 34;
    localparam int DataWidth  = 128;
    localparam int ApbAddrW   = 12;

    logic clk_axi = 0;
    always #2.0 clk_axi = ~clk_axi; // 250 MHz

    logic clk_ddr = 0;
    always #1.25 clk_ddr = ~clk_ddr; // 400 MHz

    logic rst_axi_n, rst_ddr_n;

    logic [IdWidth-1:0]    s_axi_awid;
    logic [AddrWidth-1:0]  s_axi_awaddr;
    logic [7:0]            s_axi_awlen;
    logic [2:0]            s_axi_awsize;
    logic [1:0]            s_axi_awburst;
    logic                  s_axi_awvalid;
    wire                   s_axi_awready;

    logic [DataWidth-1:0]  s_axi_wdata;
    logic [DataWidth/8-1:0] s_axi_wstrb;
    logic                  s_axi_wlast;
    logic                  s_axi_wvalid;
    wire                   s_axi_wready;

    wire  [IdWidth-1:0]    s_axi_bid;
    wire  [1:0]            s_axi_bresp;
    wire                   s_axi_bvalid;
    logic                  s_axi_bready;

    logic [ApbAddrW-1:0]   paddr;
    logic                  psel;
    logic                  penable;
    logic                  pwrite;
    logic [31:0]           pwdata;
    logic [3:0]            pstrb;
    logic [2:0]            pprot;
    wire                   pready;
    wire  [31:0]           prdata;
    wire                   pslverr;

    sec_ddr5_controller_top #(
        .IdWidth   (IdWidth),
        .AddrWidth (AddrWidth),
        .DataWidth (DataWidth),
        .ApbAddrW  (ApbAddrW)
    ) dut (
        .clk_axi           (clk_axi),
        .rst_axi_n         (rst_axi_n),
        .clk_ddr           (clk_ddr),
        .rst_ddr_n         (rst_ddr_n),
        .s_axi_awid        (s_axi_awid),
        .s_axi_awaddr      (s_axi_awaddr),
        .s_axi_awlen       (s_axi_awlen),
        .s_axi_awsize      (s_axi_awsize),
        .s_axi_awburst     (s_axi_awburst),
        .s_axi_awvalid     (s_axi_awvalid),
        .s_axi_awready     (s_axi_awready),
        .s_axi_wdata       (s_axi_wdata),
        .s_axi_wstrb       (s_axi_wstrb),
        .s_axi_wlast       (s_axi_wlast),
        .s_axi_wvalid      (s_axi_wvalid),
        .s_axi_wready      (s_axi_wready),
        .s_axi_bid         (s_axi_bid),
        .s_axi_bresp       (s_axi_bresp),
        .s_axi_bvalid      (s_axi_bvalid),
        .s_axi_bready      (s_axi_bready),
        .s_axi_arid        (8'h0),
        .s_axi_araddr      (34'h0),
        .s_axi_arlen       (8'h0),
        .s_axi_arsize      (3'b100),
        .s_axi_arburst     (2'b01),
        .s_axi_arvalid     (1'b0),
        .s_axi_arready     (),
        .s_axi_rid         (),
        .s_axi_rdata       (),
        .s_axi_rresp       (),
        .s_axi_rlast       (),
        .s_axi_rvalid      (),
        .s_axi_rready      (1'b1),
        .paddr             (paddr),
        .psel              (psel),
        .penable           (penable),
        .pwrite            (pwrite),
        .pwdata            (pwdata),
        .pstrb             (pstrb),
        .pprot             (pprot),
        .pready            (pready),
        .prdata            (prdata),
        .pslverr           (pslverr),
        .dfi_a_address     (),
        .dfi_a_bank        (),
        .dfi_a_bank_group  (),
        .dfi_a_cs_n        (),
        .dfi_a_act_n       (),
        .dfi_a_ras_n       (),
        .dfi_a_cas_n       (),
        .dfi_a_we_n        (),
        .dfi_a_wrdata_en   (),
        .dfi_a_wrdata      (),
        .dfi_a_wrdata_mask (),
        .dfi_a_rddata      (128'h0),
        .dfi_a_rddata_valid(1'b0),
        .dfi_b_address     (),
        .dfi_b_bank        (),
        .dfi_b_bank_group  (),
        .dfi_b_cs_n        (),
        .dfi_b_act_n       (),
        .dfi_b_ras_n       (),
        .dfi_b_cas_n       (),
        .dfi_b_we_n        (),
        .dfi_b_wrdata_en   (),
        .dfi_b_wrdata      (),
        .dfi_b_wrdata_mask (),
        .dfi_b_rddata      (128'h0),
        .dfi_b_rddata_valid(1'b0),
        .controller_idle   ()
    );

    task automatic apb_write(input logic [ApbAddrW-1:0] addr, input logic [31:0] data);
        @(posedge clk_axi);
        paddr   <= addr;
        pwrite  <= 1'b1;
        psel    <= 1'b1;
        penable <= 1'b0;
        pwdata  <= data;
        pstrb   <= 4'hF;
        pprot   <= 3'b000;
        @(posedge clk_axi);
        penable <= 1'b1;
        @(posedge clk_axi);
        psel    <= 1'b0;
        penable <= 1'b0;
        pwrite  <= 1'b0;
    endtask

    logic crypto_wr_valid_seen = 1'b0;

    always @(posedge clk_axi) begin
        if (dut.u_qshield_crypto.o_wr_valid) begin
            crypto_wr_valid_seen <= 1'b1;
        end
    end

    initial begin
        rst_axi_n     = 0;
        rst_ddr_n     = 0;
        s_axi_awvalid = 0;
        s_axi_wvalid  = 0;
        s_axi_bready  = 1;
        psel          = 0;
        penable       = 0;
        pwrite        = 0;

        #20;
        rst_axi_n = 1;
        rst_ddr_n = 1;
        #20;

        // Cấu hình bật mã hoá qua APB
        apb_write(12'h000, 32'h0000_0001); // CTRL: enc_enable = 1
        #20;

        // Phát 1 burst ghi AXI 64B (4 beat 128-bit)
        @(posedge clk_axi);
        s_axi_awid    <= 8'h01;
        s_axi_awaddr  <= 34'h1000;
        s_axi_awlen   <= 8'd3;
        s_axi_awsize  <= 3'b100;
        s_axi_awburst <= 2'b01;
        s_axi_awvalid <= 1'b1;

        while (!s_axi_awready) @(posedge clk_axi);
        @(posedge clk_axi);
        s_axi_awvalid <= 1'b0;

        for (int b = 0; b < 4; b++) begin
            s_axi_wdata  <= 128'hA5A5_0000 + 128'(b);
            s_axi_wstrb  <= 16'hFFFF;
            s_axi_wlast  <= (b == 3);
            s_axi_wvalid <= 1'b1;
            while (!s_axi_wready) @(posedge clk_axi);
            @(posedge clk_axi);
        end
        s_axi_wvalid <= 1'b0;
        s_axi_wlast  <= 1'b0;

        // Chờ dữ liệu truyền qua crypto pipeline
        repeat (40) @(posedge clk_axi);

        // Check C-1: Khi có AXI write, qshield_crypto_top trên đường dữ liệu phải phát tín hiệu o_wr_valid
        tb_check(crypto_wr_valid_seen == 1'b1, "C-1: qshield_crypto_top o_wr_valid must assert during write burst");

        tb_report();
        $finish;
    end

endmodule
