//=============================================================================
// File:        axi_slave_frontend.sv
// Chức năng:   Tiếp nhận bus AMBA AXI4, tách kênh dữ liệu ghi và kiểm tra an toàn giao thức.
//=============================================================================
`timescale 1ns / 1ps

module axi_slave_frontend #(
    parameter int AXI_ID_WIDTH   = 4,
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 64,
    parameter int AXI_QOS_WIDTH  = 4
) (
    input  logic                      clk_axi,
    input  logic                      aresetn_axi,

    //-------------------------------------------------------------------------
    // AXI4 Slave Interface (External Bus)
    //-------------------------------------------------------------------------
    // AW Channel
    input  logic [AXI_ID_WIDTH-1:0]   s_axi_awid,
    input  logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic [7:0]                s_axi_awlen,
    input  logic [2:0]                s_axi_awsize,
    input  logic [1:0]                s_axi_awburst,
    input  logic [AXI_QOS_WIDTH-1:0]  s_axi_awqos,
    input  logic                      s_axi_awvalid,
    output logic                      s_axi_awready,

    // W Channel
    input  logic [AXI_DATA_WIDTH-1:0]   s_axi_wdata,
    input  logic [AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  logic                        s_axi_wlast,
    input  logic                        s_axi_wvalid,
    output logic                        s_axi_wready,

    // B Channel
    output logic [AXI_ID_WIDTH-1:0]   s_axi_bid,
    output logic [1:0]                s_axi_bresp,
    output logic                      s_axi_bvalid,
    input  logic                      s_axi_bready,

    // AR Channel
    input  logic [AXI_ID_WIDTH-1:0]   s_axi_arid,
    input  logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic [7:0]                s_axi_arlen,
    input  logic [2:0]                s_axi_arsize,
    input  logic [1:0]                s_axi_arburst,
    input  logic [AXI_QOS_WIDTH-1:0]  s_axi_arqos,
    input  logic                      s_axi_arvalid,
    output logic                      s_axi_arready,

    // R Channel
    output logic [AXI_ID_WIDTH-1:0]   s_axi_rid,
    output logic [AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output logic [1:0]                s_axi_rresp,
    output logic                      s_axi_rlast,
    output logic                      s_axi_rvalid,
    input  logic                      s_axi_rready,

    //-------------------------------------------------------------------------
    // Internal Core / Staging Buffer Interface
    //-------------------------------------------------------------------------
    // Internal Write Address Request (to wdata_buffer)
    output logic                      o_wr_addr_valid,
    input  logic                      i_wr_addr_ready,
    output logic [AXI_ID_WIDTH-1:0]   o_wr_addr_id,
    output logic [AXI_ADDR_WIDTH-1:0] o_wr_addr,
    output logic [7:0]                o_wr_len,
    output logic [2:0]                o_wr_size,
    output logic [1:0]                o_wr_burst,
    output logic [AXI_QOS_WIDTH-1:0]  o_wr_qos,
    output logic                      o_wr_addr_cross_4kb,

    // Internal Write Data Stream (to wdata_buffer)
    output logic                        o_wr_data_valid,
    input  logic                        i_wr_data_ready,
    output logic [AXI_DATA_WIDTH-1:0]   o_wr_data,
    output logic [AXI_DATA_WIDTH/8-1:0] o_wr_strb,
    output logic                        o_wr_last,

    // Internal Write Response (from Core/ROB)
    input  logic                      i_bresp_valid,
    output logic                      o_bresp_ready,
    input  logic [AXI_ID_WIDTH-1:0]   i_bresp_id,
    input  logic [1:0]                i_bresp_code,

    // Internal Read Request (to Address Mapper / CDC)
    output logic                      o_rd_req_valid,
    input  logic                      i_rd_req_ready,
    output logic [AXI_ID_WIDTH-1:0]   o_rd_req_id,
    output logic [AXI_ADDR_WIDTH-1:0] o_rd_req_addr,
    output logic [7:0]                o_rd_req_len,
    output logic [2:0]                o_rd_req_size,
    output logic [1:0]                o_rd_req_burst,
    output logic [AXI_QOS_WIDTH-1:0]  o_rd_req_qos,
    output logic                      o_rd_req_cross_4kb,

    // Internal Read Response (from ROB)
    input  logic                      i_rdata_valid,
    output logic                      o_rdata_ready,
    input  logic [AXI_ID_WIDTH-1:0]   i_rdata_id,
    input  logic [AXI_DATA_WIDTH-1:0] i_rdata,
    input  logic [1:0]                i_rdata_resp,
    input  logic                      i_rdata_last
);

    //=========================================================================
    // 1. Write Address Channel (AW) Skid Buffer & 4KB Detection
    //=========================================================================
    localparam int AW_PAYLOAD_W = AXI_ID_WIDTH + AXI_ADDR_WIDTH + 8 + 3 + 2 + AXI_QOS_WIDTH;
    logic [AW_PAYLOAD_W-1:0] aw_payload_in;
    logic [AW_PAYLOAD_W-1:0] aw_payload_out;
    logic                    aw_skid_valid;
    logic                    aw_skid_ready;

    assign aw_payload_in = {s_axi_awid, s_axi_awaddr, s_axi_awlen, s_axi_awsize, s_axi_awburst, s_axi_awqos};

    axi4_skid_buffer #(
        .DATA_WIDTH(AW_PAYLOAD_W)
    ) u_aw_skid (
        .clk     (clk_axi),
        .rst_n   (aresetn_axi),
        .s_valid (s_axi_awvalid),
        .s_ready (s_axi_awready),
        .s_data  (aw_payload_in),
        .m_valid (aw_skid_valid),
        .m_ready (aw_skid_ready),
        .m_data  (aw_payload_out)
    );

    assign {o_wr_addr_id, o_wr_addr, o_wr_len, o_wr_size, o_wr_burst, o_wr_qos} = aw_payload_out;
    assign o_wr_addr_valid = aw_skid_valid;
    assign aw_skid_ready   = i_wr_addr_ready;

    // 4KB boundary crossing detection for AW
    // AXI4 Spec section A3.4.1: A burst cannot cross a 4KB boundary
    logic [12:0] aw_bytes_total;
    logic [12:0] aw_offset_end;
    assign aw_bytes_total      = ({5'b0, o_wr_len} + 13'd1) << o_wr_size;
    assign aw_offset_end       = {1'b0, o_wr_addr[11:0]} + aw_bytes_total;
    assign o_wr_addr_cross_4kb = (aw_offset_end > 13'd4096);

    //=========================================================================
    // 2. Write Data Channel (W) Skid Buffer
    //=========================================================================
    localparam int W_PAYLOAD_W = AXI_DATA_WIDTH + (AXI_DATA_WIDTH / 8) + 1;
    logic [W_PAYLOAD_W-1:0] w_payload_in;
    logic [W_PAYLOAD_W-1:0] w_payload_out;
    logic                   w_skid_valid;
    logic                   w_skid_ready;

    assign w_payload_in = {s_axi_wdata, s_axi_wstrb, s_axi_wlast};

    axi4_skid_buffer #(
        .DATA_WIDTH(W_PAYLOAD_W)
    ) u_w_skid (
        .clk     (clk_axi),
        .rst_n   (aresetn_axi),
        .s_valid (s_axi_wvalid),
        .s_ready (s_axi_wready),
        .s_data  (w_payload_in),
        .m_valid (w_skid_valid),
        .m_ready (w_skid_ready),
        .m_data  (w_payload_out)
    );

    assign {o_wr_data, o_wr_strb, o_wr_last} = w_payload_out;
    assign o_wr_data_valid = w_skid_valid;
    assign w_skid_ready    = i_wr_data_ready;

    //=========================================================================
    // 3. Write Response Channel (B) Skid Buffer
    //=========================================================================
    localparam int B_PAYLOAD_W = AXI_ID_WIDTH + 2;
    logic [B_PAYLOAD_W-1:0] b_payload_in;
    logic [B_PAYLOAD_W-1:0] b_payload_out;

    assign b_payload_in = {i_bresp_id, i_bresp_code};

    axi4_skid_buffer #(
        .DATA_WIDTH(B_PAYLOAD_W)
    ) u_b_skid (
        .clk     (clk_axi),
        .rst_n   (aresetn_axi),
        .s_valid (i_bresp_valid),
        .s_ready (o_bresp_ready),
        .s_data  (b_payload_in),
        .m_valid (s_axi_bvalid),
        .m_ready (s_axi_bready),
        .m_data  (b_payload_out)
    );

    assign {s_axi_bid, s_axi_bresp} = b_payload_out;

    //=========================================================================
    // 4. Read Address Channel (AR) Skid Buffer & 4KB Detection
    //=========================================================================
    localparam int AR_PAYLOAD_W = AXI_ID_WIDTH + AXI_ADDR_WIDTH + 8 + 3 + 2 + AXI_QOS_WIDTH;
    logic [AR_PAYLOAD_W-1:0] ar_payload_in;
    logic [AR_PAYLOAD_W-1:0] ar_payload_out;
    logic                    ar_skid_valid;
    logic                    ar_skid_ready;

    assign ar_payload_in = {s_axi_arid, s_axi_araddr, s_axi_arlen, s_axi_arsize, s_axi_arburst, s_axi_arqos};

    axi4_skid_buffer #(
        .DATA_WIDTH(AR_PAYLOAD_W)
    ) u_ar_skid (
        .clk     (clk_axi),
        .rst_n   (aresetn_axi),
        .s_valid (s_axi_arvalid),
        .s_ready (s_axi_arready),
        .s_data  (ar_payload_in),
        .m_valid (ar_skid_valid),
        .m_ready (ar_skid_ready),
        .m_data  (ar_payload_out)
    );

    assign {o_rd_req_id, o_rd_req_addr, o_rd_req_len, o_rd_req_size, o_rd_req_burst, o_rd_req_qos} = ar_payload_out;
    assign o_rd_req_valid = ar_skid_valid;
    assign ar_skid_ready  = i_rd_req_ready;

    // 4KB boundary crossing detection for AR
    logic [12:0] ar_bytes_total;
    logic [12:0] ar_offset_end;
    assign ar_bytes_total      = ({5'b0, o_rd_req_len} + 13'd1) << o_rd_req_size;
    assign ar_offset_end       = {1'b0, o_rd_req_addr[11:0]} + ar_bytes_total;
    assign o_rd_req_cross_4kb  = (ar_offset_end > 13'd4096);

    //=========================================================================
    // 5. Read Data Channel (R) Skid Buffer
    //=========================================================================
    localparam int R_PAYLOAD_W = AXI_ID_WIDTH + AXI_DATA_WIDTH + 2 + 1;
    logic [R_PAYLOAD_W-1:0] r_payload_in;
    logic [R_PAYLOAD_W-1:0] r_payload_out;

    assign r_payload_in = {i_rdata_id, i_rdata, i_rdata_resp, i_rdata_last};

    axi4_skid_buffer #(
        .DATA_WIDTH(R_PAYLOAD_W)
    ) u_r_skid (
        .clk     (clk_axi),
        .rst_n   (aresetn_axi),
        .s_valid (i_rdata_valid),
        .s_ready (o_rdata_ready),
        .s_data  (r_payload_in),
        .m_valid (s_axi_rvalid),
        .m_ready (s_axi_rready),
        .m_data  (r_payload_out)
    );

    assign {s_axi_rid, s_axi_rdata, s_axi_rresp, s_axi_rlast} = r_payload_out;

    //=========================================================================
    // 6. SystemVerilog Assertions (SVA) for Protocol Formal Verification
    //=========================================================================
`ifdef FORMAL
    // Reset Check: All valid signals must drop to 0 upon reset assertion
    always_comb begin
        if (!aresetn_axi) begin
            assert (!s_axi_bvalid);
            assert (!s_axi_rvalid);
        end
    end

    // AXI4 Handshake Stability: When Valid is asserted and Ready is low, payload must not change
    always_ff @(posedge clk_axi) begin
        if (aresetn_axi) begin
            if ($past(s_axi_awvalid && !s_axi_awready)) begin
                assert (s_axi_awvalid);
                assert (s_axi_awid == $past(s_axi_awid));
                assert (s_axi_awaddr == $past(s_axi_awaddr));
            end
            if ($past(s_axi_arvalid && !s_axi_arready)) begin
                assert (s_axi_arvalid);
                assert (s_axi_arid == $past(s_axi_arid));
                assert (s_axi_araddr == $past(s_axi_araddr));
            end
            if ($past(s_axi_wvalid && !s_axi_wready)) begin
                assert (s_axi_wvalid);
                assert (s_axi_wdata == $past(s_axi_wdata));
            end
        end
    end
`endif

endmodule
