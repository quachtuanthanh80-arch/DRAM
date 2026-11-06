// File: check_c4.sv
// Chức năng: Kiểm tra tái hiện finding C-4 (Đường đọc adapter bị stub: ARVALID không bao giờ có RVALID).

`timescale 1ns / 1ps

module check_c4;
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

    logic [IdWidth-1:0]    s_axi_arid;
    logic [AddrWidth-1:0]  s_axi_araddr;
    logic [7:0]            s_axi_arlen;
    logic [2:0]            s_axi_arsize;
    logic [1:0]            s_axi_arburst;
    logic                  s_axi_arvalid;
    wire                   s_axi_arready;

    wire  [IdWidth-1:0]    s_axi_rid;
    wire  [DataWidth-1:0]  s_axi_rdata;
    wire  [1:0]            s_axi_rresp;
    wire                   s_axi_rlast;
    wire                   s_axi_rvalid;
    logic                  s_axi_rready;

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
        .s_axi_awid        (8'h0),
        .s_axi_awaddr      (34'h0),
        .s_axi_awlen       (8'h0),
        .s_axi_awsize      (3'b100),
        .s_axi_awburst     (2'b01),
        .s_axi_awvalid     (1'b0),
        .s_axi_awready     (),
        .s_axi_wdata       (128'h0),
        .s_axi_wstrb       (16'h0),
        .s_axi_wlast       (1'b0),
        .s_axi_wvalid      (1'b0),
        .s_axi_wready      (),
        .s_axi_bid         (),
        .s_axi_bresp       (),
        .s_axi_bvalid      (),
        .s_axi_bready      (1'b1),
        .s_axi_arid        (s_axi_arid),
        .s_axi_araddr      (s_axi_araddr),
        .s_axi_arlen       (s_axi_arlen),
        .s_axi_arsize      (s_axi_arsize),
        .s_axi_arburst     (s_axi_arburst),
        .s_axi_arvalid     (s_axi_arvalid),
        .s_axi_arready     (s_axi_arready),
        .s_axi_rid         (s_axi_rid),
        .s_axi_rdata       (s_axi_rdata),
        .s_axi_rresp       (s_axi_rresp),
        .s_axi_rlast       (s_axi_rlast),
        .s_axi_rvalid      (s_axi_rvalid),
        .s_axi_rready      (s_axi_rready),
        .paddr             (12'h0),
        .psel              (1'b0),
        .penable           (1'b0),
        .pwrite            (1'b0),
        .pwdata            (32'h0),
        .pstrb             (4'h0),
        .pprot             (3'b0),
        .pready            (),
        .prdata            (),
        .pslverr           (),
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

    logic rvalid_seen = 1'b0;

    initial begin
        rst_axi_n     = 0;
        rst_ddr_n     = 0;
        s_axi_arvalid = 0;
        s_axi_rready  = 1;

        #20;
        rst_axi_n = 1;
        rst_ddr_n = 1;
        #20;

        // Phát yêu cầu đọc AXI (ARVALID = 1)
        @(posedge clk_axi);
        s_axi_arid    <= 8'h01;
        s_axi_araddr  <= 34'h1000;
        s_axi_arlen   <= 8'd0; // 1 beat
        s_axi_arsize  <= 3'b100;
        s_axi_arburst <= 2'b01;
        s_axi_arvalid <= 1'b1;

        while (!s_axi_arready) @(posedge clk_axi);
        @(posedge clk_axi);
        s_axi_arvalid <= 1'b0;

        // Chờ RVALID từ bộ điều khiển
        repeat (30) begin
            @(posedge clk_axi);
            if (s_axi_rvalid) begin
                rvalid_seen = 1'b1;
            end
        end

        // Check C-4: Kênh đọc ARVALID phải nhận được phản hồi RVALID từ bộ nhớ
        tb_check(rvalid_seen == 1'b1, "C-4: AXI read request must produce RVALID response");

        tb_report();
        $finish;
    end

endmodule
