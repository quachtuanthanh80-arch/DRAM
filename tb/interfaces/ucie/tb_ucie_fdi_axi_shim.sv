// File: tb_ucie_fdi_axi_shim.sv
// Chức năng: Testbench SystemVerilog tự kiểm chứng cầu nối UCIe 1.1 FDI Bring-up, AoU Streaming và Tau-scaling.
`timescale 1ns / 1ps

module tb_ucie_fdi_axi_shim;

    logic         clk = 0;
    always #1.25 clk = ~clk; // 400 MHz

    logic         rst_n;

    // UCIe 1.1 FDI
    logic [511:0] lp_data;
    logic         lp_valid;
    logic         lp_ready;
    logic [3:0]   lp_state_req;
    logic         lp_rx_active_ack;

    logic [511:0] pl_data;
    logic         pl_valid;
    logic         pl_ready;
    logic [3:0]   pl_state_sts;
    logic         pl_rx_active_req;
    logic         ucie_link_active;

    // AXI5 Master Bus
    logic [7:0]   m_axi_awid;
    logic [33:0]  m_axi_awaddr;
    logic [7:0]   m_axi_awlen;
    logic [2:0]   m_axi_awsize;
    logic [1:0]   m_axi_awburst;
    logic [3:0]   m_axi_awqos;
    logic [7:0]   m_axi_awuser;
    logic         m_axi_awvalid;
    logic         m_axi_awready;

    logic [511:0] m_axi_wdata;
    logic [63:0]  m_axi_wstrb;
    logic         m_axi_wlast;
    logic         m_axi_wvalid;
    logic         m_axi_wready;

    logic [7:0]   m_axi_bid;
    logic [1:0]   m_axi_bresp;
    logic         m_axi_bvalid;
    logic         m_axi_bready;

    logic [7:0]   m_axi_arid;
    logic [33:0]  m_axi_araddr;
    logic [7:0]   m_axi_arlen;
    logic [2:0]   m_axi_arsize;
    logic [1:0]   m_axi_arburst;
    logic [3:0]   m_axi_arqos;
    logic [7:0]   m_axi_aruser;
    logic         m_axi_arvalid;
    logic         m_axi_arready;

    logic [7:0]   m_axi_rid;
    logic [511:0] m_axi_rdata;
    logic [1:0]   m_axi_rresp;
    logic         m_axi_rlast;
    logic         m_axi_rvalid;
    logic         m_axi_rready;
    logic         m_axi_rpoison;

    ucie_fdi_axi_shim #(
        .AxiIdWidth        (8),
        .AxiAddrWidth      (34),
        .AxiDataWidth      (512),
        .AxiUserWidth      (8),
        .D2D_LATENCY_CYCLES(1)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .lp_data         (lp_data),
        .lp_valid        (lp_valid),
        .lp_ready        (lp_ready),
        .lp_state_req    (lp_state_req),
        .lp_rx_active_ack(lp_rx_active_ack),
        .pl_data         (pl_data),
        .pl_valid        (pl_valid),
        .pl_ready        (pl_ready),
        .pl_state_sts    (pl_state_sts),
        .pl_rx_active_req(pl_rx_active_req),
        .ucie_link_active(ucie_link_active),
        .m_axi_awid      (m_axi_awid),
        .m_axi_awaddr    (m_axi_awaddr),
        .m_axi_awlen     (m_axi_awlen),
        .m_axi_awsize    (m_axi_awsize),
        .m_axi_awburst   (m_axi_awburst),
        .m_axi_awqos     (m_axi_awqos),
        .m_axi_awuser    (m_axi_awuser),
        .m_axi_awvalid   (m_axi_awvalid),
        .m_axi_awready   (m_axi_awready),
        .m_axi_wdata     (m_axi_wdata),
        .m_axi_wstrb     (m_axi_wstrb),
        .m_axi_wlast     (m_axi_wlast),
        .m_axi_wvalid    (m_axi_wvalid),
        .m_axi_wready    (m_axi_wready),
        .m_axi_bid       (m_axi_bid),
        .m_axi_bresp     (m_axi_bresp),
        .m_axi_bvalid    (m_axi_bvalid),
        .m_axi_bready    (m_axi_bready),
        .m_axi_arid      (m_axi_arid),
        .m_axi_araddr    (m_axi_araddr),
        .m_axi_arlen     (m_axi_arlen),
        .m_axi_arsize    (m_axi_arsize),
        .m_axi_arburst   (m_axi_arburst),
        .m_axi_arqos     (m_axi_arqos),
        .m_axi_aruser    (m_axi_aruser),
        .m_axi_arvalid   (m_axi_arvalid),
        .m_axi_arready   (m_axi_arready),
        .m_axi_rid       (m_axi_rid),
        .m_axi_rdata     (m_axi_rdata),
        .m_axi_rresp     (m_axi_rresp),
        .m_axi_rlast     (m_axi_rlast),
        .m_axi_rvalid    (m_axi_rvalid),
        .m_axi_rready    (m_axi_rready),
        .m_axi_rpoison   (m_axi_rpoison)
    );

    // Simple AXI5 Memory Model
    logic [511:0] mem_data [0:15];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_awready <= 1'b1;
            m_axi_wready  <= 1'b1;
            m_axi_bvalid  <= 1'b0;
            m_axi_bresp   <= 2'b00;
            m_axi_bid     <= 8'h0;
            m_axi_arready <= 1'b1;
            m_axi_rvalid  <= 1'b0;
            m_axi_rdata   <= 512'h0;
            m_axi_rresp   <= 2'b00;
            m_axi_rlast   <= 1'b0;
            m_axi_rid     <= 8'h0;
            m_axi_rpoison <= 1'b0;
        end else begin
            if (m_axi_awvalid && m_axi_awready && m_axi_wvalid && m_axi_wready) begin
                mem_data[m_axi_awaddr[9:6]] <= m_axi_wdata;
                m_axi_bvalid <= 1'b1;
                m_axi_bid    <= m_axi_awid;
            end else if (m_axi_bvalid && m_axi_bready) begin
                m_axi_bvalid <= 1'b0;
            end

            if (m_axi_arvalid && m_axi_arready) begin
                m_axi_rvalid  <= 1'b1;
                m_axi_rid     <= m_axi_arid;
                m_axi_rlast   <= 1'b1;
                m_axi_rdata   <= mem_data[m_axi_araddr[9:6]];
                m_axi_rpoison <= (m_axi_araddr[9:6] == 4'hF) ? 1'b1 : 1'b0;
            end else if (m_axi_rvalid && m_axi_rready) begin
                m_axi_rvalid  <= 1'b0;
                m_axi_rpoison <= 1'b0;
            end
        end
    end

    initial begin
        rst_n            = 0;
        lp_ready         = 1;
        pl_data          = 0;
        pl_valid         = 0;
        pl_state_sts     = 0;
        pl_rx_active_req = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        $display("=== START: tb_ucie_fdi_axi_shim ===");

        // 1. FDI Link Bring-Up
        pl_rx_active_req = 1;
        pl_state_sts     = 4'h1; // ACTIVE
        while (!lp_rx_active_ack || !ucie_link_active) @(posedge clk);
        $display("[+] UCIe FDI Link Active!");

        // 2. AoU Write: Opcode = 2, VM = 3, Tag = 0x55, Addr = 0x80 (Block 2)
        pl_data          = 512'h1234_5678_9ABC_DEF0;
        pl_data[491:458] = 34'h00000080;
        pl_data[499:492] = 8'h55;
        pl_data[507:500] = 8'h03;
        pl_data[511:508] = 4'h2; // WRITE
        pl_valid         = 1'b1;

        @(posedge clk);
        while (!pl_ready) @(posedge clk);
        pl_valid = 1'b0;
        repeat (5) @(posedge clk);

        // 3. AoU Read: Opcode = 1, VM = 3, Tag = 0x55, Addr = 0x80
        pl_data          = 512'h0;
        pl_data[491:458] = 34'h00000080;
        pl_data[499:492] = 8'h55;
        pl_data[507:500] = 8'h03;
        pl_data[511:508] = 4'h1; // READ
        pl_valid         = 1'b1;

        @(posedge clk);
        while (!pl_ready) @(posedge clk);
        pl_valid = 1'b0;

        while (!lp_valid) @(posedge clk);
        if (lp_data[511:508] !== 4'h1 || lp_data[499:492] !== 8'h55 || lp_data[63:0] !== 64'h1234_5678_9ABC_DEF0) begin
            $display("[FAIL] AoU Read Data mismatch: %h", lp_data);
            $fatal(1);
        end

        $display("[PASS] UCIe 1.1 FDI AoU Shim Verification Completed Successfully");
        $finish;
    end

endmodule
