// File: tb_cxl_mem_axi_shim.sv
// Chức năng: Testbench SystemVerilog tự kiểm chứng cầu nối CXL.mem 3.0 Flits sang AXI5 512-bit, đa máy ảo SPID và Poisoning.
`timescale 1ns / 1ps

module tb_cxl_mem_axi_shim;

    logic        clk = 0;
    always #1.25 clk = ~clk; // 400 MHz

    logic        rst_n;

    // CXL.mem M2S-Req
    logic        cxl_m2s_req_valid;
    logic        cxl_m2s_req_ready;
    logic [3:0]  cxl_m2s_req_opcode;
    logic [27:0] cxl_m2s_req_addr;
    logic [15:0] cxl_m2s_req_tag;
    logic [7:0]  cxl_m2s_req_spid;
    logic [2:0]  cxl_m2s_req_tc;

    // CXL.mem M2S-RwD
    logic        cxl_m2s_rwd_valid;
    logic        cxl_m2s_rwd_ready;
    logic [3:0]  cxl_m2s_rwd_opcode;
    logic [27:0] cxl_m2s_rwd_addr;
    logic [15:0] cxl_m2s_rwd_tag;
    logic [7:0]  cxl_m2s_rwd_spid;
    logic [511:0] cxl_m2s_rwd_data;
    logic [63:0] cxl_m2s_rwd_byte_en;
    logic        cxl_m2s_rwd_poison;

    // CXL.mem S2M-DRS
    logic        cxl_s2m_drs_valid;
    logic        cxl_s2m_drs_ready;
    logic [3:0]  cxl_s2m_drs_opcode;
    logic [15:0] cxl_s2m_drs_tag;
    logic [511:0] cxl_s2m_drs_data;
    logic        cxl_s2m_drs_poison;

    // CXL.mem S2M-NDR
    logic        cxl_s2m_ndr_valid;
    logic        cxl_s2m_ndr_ready;
    logic [3:0]  cxl_s2m_ndr_opcode;
    logic [15:0] cxl_s2m_ndr_tag;

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

    cxl_mem_axi_shim #(
        .AxiIdWidth  (8),
        .AxiAddrWidth(34),
        .AxiDataWidth(512),
        .AxiUserWidth(8)
    ) dut (
        .clk                 (clk),
        .rst_n               (rst_n),
        .cxl_m2s_req_valid   (cxl_m2s_req_valid),
        .cxl_m2s_req_ready   (cxl_m2s_req_ready),
        .cxl_m2s_req_opcode  (cxl_m2s_req_opcode),
        .cxl_m2s_req_addr    (cxl_m2s_req_addr),
        .cxl_m2s_req_tag     (cxl_m2s_req_tag),
        .cxl_m2s_req_spid    (cxl_m2s_req_spid),
        .cxl_m2s_req_tc      (cxl_m2s_req_tc),
        .cxl_m2s_rwd_valid   (cxl_m2s_rwd_valid),
        .cxl_m2s_rwd_ready   (cxl_m2s_rwd_ready),
        .cxl_m2s_rwd_opcode  (cxl_m2s_rwd_opcode),
        .cxl_m2s_rwd_addr    (cxl_m2s_rwd_addr),
        .cxl_m2s_rwd_tag     (cxl_m2s_rwd_tag),
        .cxl_m2s_rwd_spid    (cxl_m2s_rwd_spid),
        .cxl_m2s_rwd_data    (cxl_m2s_rwd_data),
        .cxl_m2s_rwd_byte_en (cxl_m2s_rwd_byte_en),
        .cxl_m2s_rwd_poison  (cxl_m2s_rwd_poison),
        .cxl_s2m_drs_valid   (cxl_s2m_drs_valid),
        .cxl_s2m_drs_ready   (cxl_s2m_drs_ready),
        .cxl_s2m_drs_opcode  (cxl_s2m_drs_opcode),
        .cxl_s2m_drs_tag     (cxl_s2m_drs_tag),
        .cxl_s2m_drs_data    (cxl_s2m_drs_data),
        .cxl_s2m_drs_poison  (cxl_s2m_drs_poison),
        .cxl_s2m_ndr_valid   (cxl_s2m_ndr_valid),
        .cxl_s2m_ndr_ready   (cxl_s2m_ndr_ready),
        .cxl_s2m_ndr_opcode  (cxl_s2m_ndr_opcode),
        .cxl_s2m_ndr_tag     (cxl_s2m_ndr_tag),
        .m_axi_awid          (m_axi_awid),
        .m_axi_awaddr        (m_axi_awaddr),
        .m_axi_awlen         (m_axi_awlen),
        .m_axi_awsize        (m_axi_awsize),
        .m_axi_awburst       (m_axi_awburst),
        .m_axi_awqos         (m_axi_awqos),
        .m_axi_awuser        (m_axi_awuser),
        .m_axi_awvalid       (m_axi_awvalid),
        .m_axi_awready       (m_axi_awready),
        .m_axi_wdata         (m_axi_wdata),
        .m_axi_wstrb         (m_axi_wstrb),
        .m_axi_wlast         (m_axi_wlast),
        .m_axi_wvalid        (m_axi_wvalid),
        .m_axi_wready        (m_axi_wready),
        .m_axi_bid           (m_axi_bid),
        .m_axi_bresp         (m_axi_bresp),
        .m_axi_bvalid        (m_axi_bvalid),
        .m_axi_bready        (m_axi_bready),
        .m_axi_arid          (m_axi_arid),
        .m_axi_araddr        (m_axi_araddr),
        .m_axi_arlen         (m_axi_arlen),
        .m_axi_arsize        (m_axi_arsize),
        .m_axi_arburst       (m_axi_arburst),
        .m_axi_arqos         (m_axi_arqos),
        .m_axi_aruser        (m_axi_aruser),
        .m_axi_arvalid       (m_axi_arvalid),
        .m_axi_arready       (m_axi_arready),
        .m_axi_rid           (m_axi_rid),
        .m_axi_rdata         (m_axi_rdata),
        .m_axi_rresp         (m_axi_rresp),
        .m_axi_rlast         (m_axi_rlast),
        .m_axi_rvalid        (m_axi_rvalid),
        .m_axi_rready        (m_axi_rready),
        .m_axi_rpoison       (m_axi_rpoison)
    );

    // Simple AXI5 Memory Model
    logic [511:0] mem_data [0:15];
    logic [3:0]   mem_idx;

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
            // Write
            if (m_axi_awvalid && m_axi_awready && m_axi_wvalid && m_axi_wready) begin
                mem_data[m_axi_awaddr[9:6]] <= m_axi_wdata;
                m_axi_bvalid <= 1'b1;
                m_axi_bid    <= m_axi_awid;
            end else if (m_axi_bvalid && m_axi_bready) begin
                m_axi_bvalid <= 1'b0;
            end

            // Read
            if (m_axi_arvalid && m_axi_arready) begin
                m_axi_rvalid  <= 1'b1;
                m_axi_rid     <= m_axi_arid;
                m_axi_rlast   <= 1'b1;
                m_axi_rdata   <= mem_data[m_axi_araddr[9:6]];
                if (m_axi_araddr[9:6] == 4'hE) begin
                    m_axi_rpoison <= 1'b1;
                    m_axi_rresp   <= 2'b10; // SLVERR
                end else begin
                    m_axi_rpoison <= 1'b0;
                    m_axi_rresp   <= 2'b00;
                end
            end else if (m_axi_rvalid && m_axi_rready) begin
                m_axi_rvalid  <= 1'b0;
                m_axi_rpoison <= 1'b0;
            end
        end
    end

    initial begin
        rst_n               = 0;
        cxl_m2s_req_valid   = 0;
        cxl_m2s_req_opcode  = 0;
        cxl_m2s_req_addr    = 0;
        cxl_m2s_req_tag     = 0;
        cxl_m2s_req_spid    = 0;
        cxl_m2s_req_tc      = 0;
        cxl_m2s_rwd_valid   = 0;
        cxl_m2s_rwd_opcode  = 0;
        cxl_m2s_rwd_addr    = 0;
        cxl_m2s_rwd_tag     = 0;
        cxl_m2s_rwd_spid    = 0;
        cxl_m2s_rwd_data    = 0;
        cxl_m2s_rwd_byte_en = 0;
        cxl_m2s_rwd_poison  = 0;
        cxl_s2m_drs_ready   = 1;
        cxl_s2m_ndr_ready   = 1;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        $display("=== START: tb_cxl_mem_axi_shim ===");

        // 1. M2S-RwD Write
        cxl_m2s_rwd_valid   <= 1'b1;
        cxl_m2s_rwd_opcode  <= 4'h4;
        cxl_m2s_rwd_addr    <= 28'h0000001; // Block 1
        cxl_m2s_rwd_tag     <= 16'h0011;
        cxl_m2s_rwd_spid    <= 8'h03;
        cxl_m2s_rwd_data    <= 512'hCAFE_BABE_0123_4567;
        cxl_m2s_rwd_byte_en <= 64'hFFFF_FFFF_FFFF_FFFF;

        @(posedge clk);
        while (!cxl_m2s_rwd_ready) @(posedge clk);
        cxl_m2s_rwd_valid <= 1'b0;

        while (!cxl_s2m_ndr_valid) @(posedge clk);
        if (cxl_s2m_ndr_opcode !== 4'h0 || cxl_s2m_ndr_tag !== 16'h0011) begin
            $display("[FAIL] CXL NDR mismatch");
            $fatal(1);
        end
        @(posedge clk);

        // 2. M2S-Req Read
        cxl_m2s_req_valid  <= 1'b1;
        cxl_m2s_req_opcode <= 4'h1;
        cxl_m2s_req_addr   <= 28'h0000001;
        cxl_m2s_req_tag    <= 16'h0011;
        cxl_m2s_req_spid   <= 8'h03;

        @(posedge clk);
        while (!cxl_m2s_req_ready) @(posedge clk);
        cxl_m2s_req_valid <= 1'b0;

        while (!cxl_s2m_drs_valid) @(posedge clk);
        if (cxl_s2m_drs_data[63:0] !== 64'hCAFE_BABE_0123_4567 || cxl_s2m_drs_poison !== 1'b0) begin
            $display("[FAIL] CXL DRS data mismatch: %h", cxl_s2m_drs_data);
            $fatal(1);
        end
        @(posedge clk);

        // 3. Poison Forwarding test at Block 14 (4'hE)
        cxl_m2s_req_valid <= 1'b1;
        cxl_m2s_req_addr  <= 28'h000000E;
        cxl_m2s_req_tag   <= 16'h0099;
        @(posedge clk);
        cxl_m2s_req_valid <= 1'b0;

        while (!cxl_s2m_drs_valid) @(posedge clk);
        if (cxl_s2m_drs_poison !== 1'b1) begin
            $display("[FAIL] Expected Poison = 1");
            $fatal(1);
        end

        $display("[PASS] CXL.mem 3.0 Flit Expander Verification Completed Successfully");
        $finish;
    end

endmodule
