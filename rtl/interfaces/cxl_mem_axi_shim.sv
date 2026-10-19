// File: cxl_mem_axi_shim.sv
// Chức năng: Cầu nối chuyển đổi song hướng CXL.mem 3.0 Flits (M2S-Req/RwD, S2M-DRS/NDR) sang AMBA AXI5 512-bit.
`timescale 1ns / 1ps

/* verilator lint_off UNUSEDSIGNAL */
module cxl_mem_axi_shim #(
    parameter int AxiIdWidth   = 8,
    parameter int AxiAddrWidth = 34,
    parameter int AxiDataWidth = 512,
    parameter int AxiUserWidth = 8
)(
    input  logic                     clk,
    input  logic                     rst_n,

    //-------------------------------------------------------------------------
    // CXL.mem 3.0 Master-to-Subordinate (M2S) Request Channel (MemRd)
    //-------------------------------------------------------------------------
    input  logic                     cxl_m2s_req_valid,
    output logic                     cxl_m2s_req_ready,
    input  logic [3:0]               cxl_m2s_req_opcode, // 4'h1: MemRd, 4'h2: MemInv, 4'h3: MemRdBlk
    input  logic [AxiAddrWidth-7:0]  cxl_m2s_req_addr,   // 64-Byte Cacheline address
    input  logic [15:0]              cxl_m2s_req_tag,
    input  logic [7:0]               cxl_m2s_req_spid,   // Security VM Identifier
    input  logic [2:0]               cxl_m2s_req_tc,     // Traffic Class / QoS

    //-------------------------------------------------------------------------
    // CXL.mem 3.0 M2S Request with Data Channel (MemWr)
    //-------------------------------------------------------------------------
    input  logic                     cxl_m2s_rwd_valid,
    output logic                     cxl_m2s_rwd_ready,
    input  logic [3:0]               cxl_m2s_rwd_opcode, // 4'h4: MemWr
    input  logic [AxiAddrWidth-7:0]  cxl_m2s_rwd_addr,
    input  logic [15:0]              cxl_m2s_rwd_tag,
    input  logic [7:0]               cxl_m2s_rwd_spid,
    input  logic [AxiDataWidth-1:0]  cxl_m2s_rwd_data,
    input  logic [AxiDataWidth/8-1:0] cxl_m2s_rwd_byte_en,
    input  logic                     cxl_m2s_rwd_poison,

    //-------------------------------------------------------------------------
    // CXL.mem 3.0 Subordinate-to-Master (S2M) Data Response (S2M-DRS)
    //-------------------------------------------------------------------------
    output logic                     cxl_s2m_drs_valid,
    input  logic                     cxl_s2m_drs_ready,
    output logic [3:0]               cxl_s2m_drs_opcode, // 4'h1: MemData
    output logic [15:0]              cxl_s2m_drs_tag,
    output logic [AxiDataWidth-1:0]  cxl_s2m_drs_data,
    output logic                     cxl_s2m_drs_poison,

    //-------------------------------------------------------------------------
    // CXL.mem 3.0 S2M Non-Data Response (S2M-NDR - Completion)
    //-------------------------------------------------------------------------
    output logic                     cxl_s2m_ndr_valid,
    input  logic                     cxl_s2m_ndr_ready,
    output logic [3:0]               cxl_s2m_ndr_opcode, // 4'h0: Cmp, 4'h1: CmpE
    output logic [15:0]              cxl_s2m_ndr_tag,

    //-------------------------------------------------------------------------
    // AMBA AXI5 Master Interface (Driving Q-Shield axi_ddr5_mc_top.sv)
    //-------------------------------------------------------------------------
    // AW
    output logic [AxiIdWidth-1:0]    m_axi_awid,
    output logic [AxiAddrWidth-1:0]  m_axi_awaddr,
    output logic [7:0]               m_axi_awlen,
    output logic [2:0]               m_axi_awsize,
    output logic [1:0]               m_axi_awburst,
    output logic [3:0]               m_axi_awqos,
    output logic [AxiUserWidth-1:0]  m_axi_awuser,
    output logic                     m_axi_awvalid,
    input  logic                     m_axi_awready,

    // W
    output logic [AxiDataWidth-1:0]  m_axi_wdata,
    output logic [AxiDataWidth/8-1:0] m_axi_wstrb,
    output logic                     m_axi_wlast,
    output logic                     m_axi_wvalid,
    input  logic                     m_axi_wready,

    // B
    input  logic [AxiIdWidth-1:0]    m_axi_bid,
    input  logic [1:0]               m_axi_bresp,
    input  logic                     m_axi_bvalid,
    output logic                     m_axi_bready,

    // AR
    output logic [AxiIdWidth-1:0]    m_axi_arid,
    output logic [AxiAddrWidth-1:0]  m_axi_araddr,
    output logic [7:0]               m_axi_arlen,
    output logic [2:0]               m_axi_arsize,
    output logic [1:0]               m_axi_arburst,
    output logic [3:0]               m_axi_arqos,
    output logic [AxiUserWidth-1:0]  m_axi_aruser,
    output logic                     m_axi_arvalid,
    input  logic                     m_axi_arready,

    // R
    input  logic [AxiIdWidth-1:0]    m_axi_rid,
    input  logic [AxiDataWidth-1:0]  m_axi_rdata,
    input  logic [1:0]               m_axi_rresp,
    input  logic                     m_axi_rlast,
    input  logic                     m_axi_rvalid,
    output logic                     m_axi_rready,
    input  logic                     m_axi_rpoison
);

    // Write Path: Decouple M2S-RwD into AXI AW and W channels concurrently
    logic wr_aw_done_q, wr_aw_done_d;
    logic wr_w_done_q,  wr_w_done_d;

    assign m_axi_awid    = { {(AxiIdWidth-8 > 0 ? AxiIdWidth-8 : 0){1'b0}}, cxl_m2s_rwd_tag[7:0] };
    assign m_axi_awaddr  = {cxl_m2s_rwd_addr, 6'b000000};
    assign m_axi_awlen   = 8'h00; // 1 beat of 64 bytes (512 bits)
    assign m_axi_awsize  = 3'b110; // 64 bytes
    assign m_axi_awburst = 2'b01; // INCR
    assign m_axi_awqos   = 4'h0;
    assign m_axi_awuser  = cxl_m2s_rwd_spid;

    assign m_axi_wdata   = cxl_m2s_rwd_data;
    assign m_axi_wstrb   = cxl_m2s_rwd_byte_en;
    assign m_axi_wlast   = 1'b1;

    assign m_axi_awvalid = cxl_m2s_rwd_valid && !wr_aw_done_q;
    assign m_axi_wvalid  = cxl_m2s_rwd_valid && !wr_w_done_q;

    // Both AW and W must hand shake before releasing M2S-RwD flit
    assign cxl_m2s_rwd_ready = (wr_aw_done_q || (m_axi_awvalid && m_axi_awready)) &&
                               (wr_w_done_q  || (m_axi_wvalid  && m_axi_wready));

    always_comb begin
        wr_aw_done_d = wr_aw_done_q;
        wr_w_done_d  = wr_w_done_q;

        if (cxl_m2s_rwd_valid) begin
            if (m_axi_awvalid && m_axi_awready) wr_aw_done_d = 1'b1;
            if (m_axi_wvalid  && m_axi_wready)  wr_w_done_d  = 1'b1;

            if (cxl_m2s_rwd_ready) begin
                wr_aw_done_d = 1'b0;
                wr_w_done_d  = 1'b0;
            end
        end else begin
            wr_aw_done_d = 1'b0;
            wr_w_done_d  = 1'b0;
        end
    end

    // Read Path: Direct mapping from M2S-Req to AXI AR channel
    assign m_axi_arid    = { {(AxiIdWidth-8 > 0 ? AxiIdWidth-8 : 0){1'b0}}, cxl_m2s_req_tag[7:0] };
    assign m_axi_araddr  = {cxl_m2s_req_addr, 6'b000000};
    assign m_axi_arlen   = 8'h00;
    assign m_axi_arsize  = 3'b110;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arqos   = {1'b0, cxl_m2s_req_tc};
    assign m_axi_aruser  = cxl_m2s_req_spid;
    assign m_axi_arvalid = cxl_m2s_req_valid;
    assign cxl_m2s_req_ready = m_axi_arready;

    // Response S2M-DRS: Forwarding Read Data and Poison indication
    assign cxl_s2m_drs_valid  = m_axi_rvalid;
    assign m_axi_rready       = cxl_s2m_drs_ready;
    assign cxl_s2m_drs_opcode = 4'h1; // MemData
    assign cxl_s2m_drs_tag    = {8'h0, m_axi_rid};
    assign cxl_s2m_drs_data   = m_axi_rdata;
    assign cxl_s2m_drs_poison = m_axi_rpoison || (m_axi_rresp == 2'b10);

    // Response S2M-NDR: Forwarding Write Completion
    assign cxl_s2m_ndr_valid  = m_axi_bvalid;
    assign m_axi_bready       = cxl_s2m_ndr_ready;
    assign cxl_s2m_ndr_opcode = (m_axi_bresp == 2'b00) ? 4'h0 : 4'h1; // 0: Cmp, 1: CmpE
    assign cxl_s2m_ndr_tag    = {8'h0, m_axi_bid};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_aw_done_q <= 1'b0;
            wr_w_done_q  <= 1'b0;
        end else begin
            wr_aw_done_q <= wr_aw_done_d;
            wr_w_done_q  <= wr_w_done_d;
        end
    end

endmodule

// Module Wrapper tích hợp cxl_mem_axi_shim với axi_ddr5_mc_top phục vụ kiểm thử Form Factor A
module cxl_type3_expander_top #(
    parameter int AxiIdWidth   = 8,
    parameter int AxiAddrWidth = 34,
    parameter int AxiDataWidth = 512,
    parameter int AxiUserWidth = 8,
    parameter int BG_COUNT     = 8,
    parameter int BANK_COUNT   = 4,
    parameter int ROW_WIDTH    = 17,
    parameter int COL_WIDTH    = 10
)(
    input  logic                     clk_axi,
    input  logic                     aresetn_axi,
    input  logic                     clk_ddr,
    input  logic                     aresetn_ddr,

    // CXL.mem M2S-Req
    input  logic                     cxl_m2s_req_valid,
    output logic                     cxl_m2s_req_ready,
    input  logic [3:0]               cxl_m2s_req_opcode,
    input  logic [AxiAddrWidth-7:0]  cxl_m2s_req_addr,
    input  logic [15:0]              cxl_m2s_req_tag,
    input  logic [7:0]               cxl_m2s_req_spid,
    input  logic [2:0]               cxl_m2s_req_tc,

    // CXL.mem M2S-RwD
    input  logic                     cxl_m2s_rwd_valid,
    output logic                     cxl_m2s_rwd_ready,
    input  logic [3:0]               cxl_m2s_rwd_opcode,
    input  logic [AxiAddrWidth-7:0]  cxl_m2s_rwd_addr,
    input  logic [15:0]              cxl_m2s_rwd_tag,
    input  logic [7:0]               cxl_m2s_rwd_spid,
    input  logic [AxiDataWidth-1:0]  cxl_m2s_rwd_data,
    input  logic [AxiDataWidth/8-1:0] cxl_m2s_rwd_byte_en,
    input  logic                     cxl_m2s_rwd_poison,

    // CXL.mem S2M-DRS
    output logic                     cxl_s2m_drs_valid,
    input  logic                     cxl_s2m_drs_ready,
    output logic [3:0]               cxl_s2m_drs_opcode,
    output logic [15:0]              cxl_s2m_drs_tag,
    output logic [AxiDataWidth-1:0]  cxl_s2m_drs_data,
    output logic                     cxl_s2m_drs_poison,

    // CXL.mem S2M-NDR
    output logic                     cxl_s2m_ndr_valid,
    input  logic                     cxl_s2m_ndr_ready,
    output logic [3:0]               cxl_s2m_ndr_opcode,
    output logic [15:0]              cxl_s2m_ndr_tag,

    // DFI 5.0 Interface
    output logic [2:0]               dfi_cmd,
    output logic [$clog2(BG_COUNT)-1:0]   dfi_bg,
    output logic [$clog2(BANK_COUNT)-1:0] dfi_bank,
    output logic [ROW_WIDTH-1:0]     dfi_row,
    output logic [COL_WIDTH-1:0]     dfi_col,

    // Telemetry & Status
    output logic [15:0]              o_throttled_events,
    output logic [15:0]              o_ecc_single_err_cnt,
    output logic [15:0]              o_ecc_double_err_cnt
);

    // Internal AXI5 Interconnect
    logic [AxiIdWidth-1:0]    axi_awid;
    logic [AxiAddrWidth-1:0]  axi_awaddr;
    logic [7:0]               axi_awlen;
    logic [2:0]               axi_awsize;
    logic [1:0]               axi_awburst;
    logic [3:0]               axi_awqos;
    logic [AxiUserWidth-1:0]  axi_awuser;
    logic                     axi_awvalid;
    logic                     axi_awready;

    logic [AxiDataWidth-1:0]  axi_wdata;
    logic [AxiDataWidth/8-1:0] axi_wstrb;
    logic                     axi_wlast;
    logic                     axi_wvalid;
    logic                     axi_wready;

    logic [AxiIdWidth-1:0]    axi_bid;
    logic [1:0]               axi_bresp;
    logic                     axi_bvalid;
    logic                     axi_bready;

    logic [AxiIdWidth-1:0]    axi_arid;
    logic [AxiAddrWidth-1:0]  axi_araddr;
    logic [7:0]               axi_arlen;
    logic [2:0]               axi_arsize;
    logic [1:0]               axi_arburst;
    logic [3:0]               axi_arqos;
    logic [AxiUserWidth-1:0]  axi_aruser;
    logic                     axi_arvalid;
    logic                     axi_arready;

    logic [AxiIdWidth-1:0]    axi_rid;
    logic [AxiDataWidth-1:0]  axi_rdata;
    logic [1:0]               axi_rresp;
    logic                     axi_rlast;
    logic                     axi_rvalid;
    logic                     axi_rready;
    logic                     axi_rpoison;

    cxl_mem_axi_shim #(
        .AxiIdWidth  (AxiIdWidth),
        .AxiAddrWidth(AxiAddrWidth),
        .AxiDataWidth(AxiDataWidth),
        .AxiUserWidth(AxiUserWidth)
    ) u_cxl_shim (
        .clk                 (clk_axi),
        .rst_n               (aresetn_axi),
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
        .m_axi_awid          (axi_awid),
        .m_axi_awaddr        (axi_awaddr),
        .m_axi_awlen         (axi_awlen),
        .m_axi_awsize        (axi_awsize),
        .m_axi_awburst       (axi_awburst),
        .m_axi_awqos         (axi_awqos),
        .m_axi_awuser        (axi_awuser),
        .m_axi_awvalid       (axi_awvalid),
        .m_axi_awready       (axi_awready),
        .m_axi_wdata         (axi_wdata),
        .m_axi_wstrb         (axi_wstrb),
        .m_axi_wlast         (axi_wlast),
        .m_axi_wvalid        (axi_wvalid),
        .m_axi_wready        (axi_wready),
        .m_axi_bid           (axi_bid),
        .m_axi_bresp         (axi_bresp),
        .m_axi_bvalid        (axi_bvalid),
        .m_axi_bready        (axi_bready),
        .m_axi_arid          (axi_arid),
        .m_axi_araddr        (axi_araddr),
        .m_axi_arlen         (axi_arlen),
        .m_axi_arsize        (axi_arsize),
        .m_axi_arburst       (axi_arburst),
        .m_axi_arqos         (axi_arqos),
        .m_axi_aruser        (axi_aruser),
        .m_axi_arvalid       (axi_arvalid),
        .m_axi_arready       (axi_arready),
        .m_axi_rid           (axi_rid),
        .m_axi_rdata         (axi_rdata),
        .m_axi_rresp         (axi_rresp),
        .m_axi_rlast         (axi_rlast),
        .m_axi_rvalid        (axi_rvalid),
        .m_axi_rready        (axi_rready),
        .m_axi_rpoison       (axi_rpoison)
    );

    // Q-Shield Memory Controller Core
    logic [(AxiDataWidth>=64?AxiDataWidth/64:1)-1:0] rpoison_bus;
    assign axi_rpoison = rpoison_bus[0];

    axi_ddr5_mc_top #(
        .AXI_ID_WIDTH   (AxiIdWidth),
        .AXI_ADDR_WIDTH (AxiAddrWidth),
        .AXI_DATA_WIDTH (AxiDataWidth),
        .BG_COUNT       (BG_COUNT),
        .BANK_COUNT     (BANK_COUNT),
        .ROW_WIDTH      (ROW_WIDTH),
        .COL_WIDTH      (COL_WIDTH)
    ) u_mc_core (
        .clk_axi             (clk_axi),
        .aresetn_axi         (aresetn_axi),
        .clk_ddr             (clk_ddr),
        .aresetn_ddr         (aresetn_ddr),
        .s_axi_awid          (axi_awid),
        .s_axi_awaddr        (axi_awaddr),
        .s_axi_awlen         (axi_awlen),
        .s_axi_awsize        (axi_awsize),
        .s_axi_awburst       (axi_awburst),
        .s_axi_awqos         (axi_awqos),
        .s_axi_awvalid       (axi_awvalid),
        .s_axi_awready       (axi_awready),
        .s_axi_wdata         (axi_wdata),
        .s_axi_wstrb         (axi_wstrb),
        .s_axi_wlast         (axi_wlast),
        .s_axi_wvalid        (axi_wvalid),
        .s_axi_wready        (axi_wready),
        .s_axi_bid           (axi_bid),
        .s_axi_bresp         (axi_bresp),
        .s_axi_bvalid        (axi_bvalid),
        .s_axi_bready        (axi_bready),
        .s_axi_arid          (axi_arid),
        .s_axi_araddr        (axi_araddr),
        .s_axi_arlen         (axi_arlen),
        .s_axi_arsize        (axi_arsize),
        .s_axi_arburst       (axi_arburst),
        .s_axi_arqos         (axi_arqos),
        .s_axi_arvalid       (axi_arvalid),
        .s_axi_arready       (axi_arready),
        .s_axi_rid           (axi_rid),
        .s_axi_rdata         (axi_rdata),
        .s_axi_rresp         (axi_rresp),
        .s_axi_rlast         (axi_rlast),
        .s_axi_rvalid        (axi_rvalid),
        .s_axi_rready        (axi_rready),
        .s_axi_rpoison       (rpoison_bus),
        .s_axi_rchk          (),
        .o_parity_err        (),
        .dfi_cmd             (dfi_cmd),
        .dfi_bg              (dfi_bg),
        .dfi_bank            (dfi_bank),
        .dfi_row             (dfi_row),
        .dfi_col             (dfi_col),
        .cfg_is_ddr5         (1'b1),
        .cfg_dual_hash_en    (1'b1),
        .cfg_rh_threshold    (16'd32),
        .cfg_window_size     (16'd1024),
        .o_throttled_events  (o_throttled_events),
        .o_ecc_single_err_cnt(o_ecc_single_err_cnt),
        .o_ecc_double_err_cnt(o_ecc_double_err_cnt),
        .cfg_bank_coloring_en(1'b1),
        .cfg_mapping_mode    (2'b00),
        .cfg_scramble_en     (1'b0),
        .cfg_scramble_reseed (1'b0),
        .cfg_scramble_seed   (64'h0),
        .cfg_pmu_en          (1'b1),
        .cfg_pmu_reset       (1'b0),
        .o_pmu_counters      (),
        .cfg_rowpress_curve  (2'b00),
        .cfg_victim3_en      (1'b0),
        .i_dram_abo_alert    (1'b0),
        .o_abo_alert_cnt     (),
        .o_ecc_miscorrect_cnt(),
        .o_coordinated_throttle_active(),
        .o_rfm_auto_cnt      (),
        .o_tras_clamped_alert(),
        .cfg_scramble_mode   (2'b00),
        .cfg_decoy_en        (1'b0),
        .o_decoy_active      (),
        .o_decoy_cnt         (),
        .o_glitch_alert      (),
        .o_security_locked   ()
    );

endmodule
