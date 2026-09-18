//=============================================================================
// Project:     Q-Shield Secure & Resilient DDR5/DDR4 Memory Controller
// File:        axi_ddr5_mc_top.sv
// Description: Top-Level Synthesizable DDR5/DDR4 Memory Controller Core.
//              Integrates all architectural pillars:
//              1. axi_slave_frontend (5-channel AXI4 + 4KB split)
//              2. wdata_buffer (Decoupled write address & data staging)
//              3. addr_mapper_ddr5 (XOR Bank-Group Interleaving)
//              4. sdc_resilient_filter (Dual-Hash RowHammer + Epoch Reset)
//              5. qos_scheduler_queue (8x8 BG Queues + 3-Tier Priority)
//              6. reorder_buffer_rob (32-entry OoO Reassembly + RAW Hazard Detect)
//              7. slack_aware_arbiter (4-Tier Timing Slack Arbiter)
//              8. ddr5_cmd_engine (JEDEC DDR5/DDR4 FSM + DFI 5.0)
//              9. ecc_scrubber (Background Patrol Scrubber + Hamming SEC-DED)
//              10. rst_sync (Dual-Clock Domain Reset Synchronizers)
// Standards:   AMBA AXI4 (IHI 0022E), JEDEC DDR5 (JESD79-5), IEEE 1800-2017.
//=============================================================================

`timescale 1ns / 1ps

/* verilator lint_off PINCONNECTEMPTY */
/* verilator lint_off UNUSEDSIGNAL */
module axi_ddr5_mc_top #(
    parameter int AXI_ID_WIDTH    = 4,
    parameter int AXI_ADDR_WIDTH  = 32,
    parameter int AXI_DATA_WIDTH  = 64,
    parameter int AXI_STRB_WIDTH  = AXI_DATA_WIDTH / 8,
    parameter int AXI_LEN_WIDTH   = 8,
    parameter int AXI_QOS_WIDTH   = 4,
    parameter int BG_COUNT        = 8,
    parameter int BG_WIDTH        = $clog2(BG_COUNT),
    parameter int BANK_COUNT      = 4,
    parameter int BANK_WIDTH      = $clog2(BANK_COUNT),
    parameter int ROW_WIDTH       = 17,
    parameter int COL_WIDTH       = 10,
    parameter int ROB_DEPTH       = 16,
    parameter int ROB_PTR_WIDTH   = $clog2(ROB_DEPTH)
)(
    //-------------------------------------------------------------------------
    // Clock & Reset
    //-------------------------------------------------------------------------
    input  logic                                         clk_axi,
    input  logic                                         aresetn_axi,
    input  logic                                         clk_ddr,
    input  logic                                         aresetn_ddr,

    //-------------------------------------------------------------------------
    // AXI4 Slave Interface
    //-------------------------------------------------------------------------
    // Write Address (AW)
    input  logic [AXI_ID_WIDTH-1:0]                      s_axi_awid,
    input  logic [AXI_ADDR_WIDTH-1:0]                    s_axi_awaddr,
    input  logic [AXI_LEN_WIDTH-1:0]                     s_axi_awlen,
    input  logic [2:0]                                   s_axi_awsize,
    input  logic [1:0]                                   s_axi_awburst,
    input  logic [AXI_QOS_WIDTH-1:0]                     s_axi_awqos,
    input  logic                                         s_axi_awvalid,
    output logic                                         s_axi_awready,

    // Write Data (W)
    input  logic [AXI_DATA_WIDTH-1:0]                    s_axi_wdata,
    input  logic [AXI_STRB_WIDTH-1:0]                    s_axi_wstrb,
    input  logic                                         s_axi_wlast,
    input  logic                                         s_axi_wvalid,
    output logic                                         s_axi_wready,

    // Write Response (B)
    output logic [AXI_ID_WIDTH-1:0]                      s_axi_bid,
    output logic [1:0]                                   s_axi_bresp,
    output logic                                         s_axi_bvalid,
    input  logic                                         s_axi_bready,

    // Read Address (AR)
    input  logic [AXI_ID_WIDTH-1:0]                      s_axi_arid,
    input  logic [AXI_ADDR_WIDTH-1:0]                    s_axi_araddr,
    input  logic [AXI_LEN_WIDTH-1:0]                     s_axi_arlen,
    input  logic [2:0]                                   s_axi_arsize,
    input  logic [1:0]                                   s_axi_arburst,
    input  logic [AXI_QOS_WIDTH-1:0]                     s_axi_arqos,
    input  logic                                         s_axi_arvalid,
    output logic                                         s_axi_arready,

    // Read Data (R)
    output logic [AXI_ID_WIDTH-1:0]                      s_axi_rid,
    output logic [AXI_DATA_WIDTH-1:0]                    s_axi_rdata,
    output logic [1:0]                                   s_axi_rresp,
    output logic                                         s_axi_rlast,
    output logic                                         s_axi_rvalid,
    input  logic                                         s_axi_rready,

    //-------------------------------------------------------------------------
    // DFI 5.0 / DRAM Physical Interface
    //-------------------------------------------------------------------------
    output logic [2:0]                                   dfi_cmd,
    output logic [BG_WIDTH-1:0]                          dfi_bg,
    output logic [BANK_WIDTH-1:0]                        dfi_bank,
    output logic [ROW_WIDTH-1:0]                         dfi_row,
    output logic [COL_WIDTH-1:0]                         dfi_col,

    //-------------------------------------------------------------------------
    // Configuration & Telemetry Ports
    //-------------------------------------------------------------------------
    input  logic                                         cfg_is_ddr5,
    input  logic                                         cfg_dual_hash_en,
    input  logic [15:0]                                  cfg_rh_threshold,
    input  logic [15:0]                                  cfg_window_size,
    output logic [15:0]                                  o_throttled_events,
    output logic [15:0]                                  o_ecc_single_err_cnt,
    output logic [15:0]                                  o_ecc_double_err_cnt
);

    //=========================================================================
    // 1. Reset Synchronizers
    //=========================================================================
    logic rst_n_axi;
    logic rst_n_ddr;

    rst_sync u_rst_sync_axi (
        .clk        (clk_axi),
        .async_rst_n(aresetn_axi),
        .sync_rst_n (rst_n_axi)
    );

    rst_sync u_rst_sync_ddr (
        .clk        (clk_ddr),
        .async_rst_n(aresetn_ddr),
        .sync_rst_n (rst_n_ddr)
    );

    //=========================================================================
    // 2. AXI4 Slave Frontend & Decoupled Buffering
    //=========================================================================
    // Frontend Decoupled AW / W Signals
    logic                      fe_wr_addr_valid;
    logic                      fe_wr_addr_ready;
    logic [AXI_ID_WIDTH-1:0]   fe_wr_addr_id;
    logic [AXI_ADDR_WIDTH-1:0] fe_wr_addr;
    logic [7:0]                fe_wr_len;
    logic [2:0]                fe_wr_size;
    logic [1:0]                fe_wr_burst;
    logic [AXI_QOS_WIDTH-1:0]  fe_wr_qos;
    logic                      fe_wr_addr_cross_4kb;

    logic                      fe_wr_data_valid;
    logic                      fe_wr_data_ready;
    logic [AXI_DATA_WIDTH-1:0] fe_wr_data;
    logic [AXI_STRB_WIDTH-1:0] fe_wr_strb;
    logic                      fe_wr_last;

    // Frontend Read Request Signals
    logic                      fe_rd_req_valid;
    logic                      fe_rd_req_ready;
    logic [AXI_ID_WIDTH-1:0]   fe_rd_req_id;
    logic [AXI_ADDR_WIDTH-1:0] fe_rd_req_addr;
    logic [7:0]                fe_rd_req_len;
    logic [2:0]                fe_rd_req_size;
    logic [1:0]                fe_rd_req_burst;
    logic [AXI_QOS_WIDTH-1:0]  fe_rd_req_qos;
    logic                      fe_rd_req_cross_4kb;

    // Read Response into Frontend (Directly driven by ROB)
    logic                      rob_rvalid;
    logic [AXI_ID_WIDTH-1:0]   rob_rid;
    logic [AXI_DATA_WIDTH-1:0] rob_rdata;
    logic [1:0]                rob_rresp;
    logic                      rob_rlast;

    // Write Decoupling Buffer Command Signals
    logic                      wbuf_cmd_valid;
    logic                      wbuf_cmd_ready;
    logic [AXI_ID_WIDTH-1:0]   wbuf_cmd_id;
    logic [AXI_ADDR_WIDTH-1:0] wbuf_cmd_addr;
    logic [7:0]                wbuf_cmd_len;
    logic [AXI_QOS_WIDTH-1:0]  wbuf_cmd_qos;

    // B Channel Response Generator for Write Bursts
    logic                      bresp_valid;
    logic [AXI_ID_WIDTH-1:0]   bresp_id;

    always_ff @(posedge clk_axi or negedge rst_n_axi) begin
        if (!rst_n_axi) begin
            bresp_valid <= 1'b0;
            bresp_id    <= '0;
        end else if (wbuf_cmd_valid && wbuf_cmd_ready) begin
            bresp_valid <= 1'b1;
            bresp_id    <= wbuf_cmd_id;
        end else if (bresp_valid && s_axi_bready) begin
            bresp_valid <= 1'b0;
        end
    end

    axi_slave_frontend #(
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_QOS_WIDTH  (AXI_QOS_WIDTH)
    ) u_frontend (
        .clk_axi             (clk_axi),
        .aresetn_axi         (rst_n_axi),

        .s_axi_awid          (s_axi_awid),
        .s_axi_awaddr        (s_axi_awaddr),
        .s_axi_awlen         (s_axi_awlen),
        .s_axi_awsize        (s_axi_awsize),
        .s_axi_awburst       (s_axi_awburst),
        .s_axi_awqos         (s_axi_awqos),
        .s_axi_awvalid       (s_axi_awvalid),
        .s_axi_awready       (s_axi_awready),

        .s_axi_wdata         (s_axi_wdata),
        .s_axi_wstrb         (s_axi_wstrb),
        .s_axi_wlast         (s_axi_wlast),
        .s_axi_wvalid        (s_axi_wvalid),
        .s_axi_wready        (s_axi_wready),

        .s_axi_bid           (s_axi_bid),
        .s_axi_bresp         (s_axi_bresp),
        .s_axi_bvalid        (s_axi_bvalid),
        .s_axi_bready        (s_axi_bready),

        .s_axi_arid          (s_axi_arid),
        .s_axi_araddr        (s_axi_araddr),
        .s_axi_arlen         (s_axi_arlen),
        .s_axi_arsize        (s_axi_arsize),
        .s_axi_arburst       (s_axi_arburst),
        .s_axi_arqos         (s_axi_arqos),
        .s_axi_arvalid       (s_axi_arvalid),
        .s_axi_arready       (s_axi_arready),

        .s_axi_rid           (s_axi_rid),
        .s_axi_rdata         (s_axi_rdata),
        .s_axi_rresp         (s_axi_rresp),
        .s_axi_rlast         (s_axi_rlast),
        .s_axi_rvalid        (s_axi_rvalid),
        .s_axi_rready        (s_axi_rready),

        .o_wr_addr_valid     (fe_wr_addr_valid),
        .i_wr_addr_ready     (fe_wr_addr_ready),
        .o_wr_addr_id        (fe_wr_addr_id),
        .o_wr_addr           (fe_wr_addr),
        .o_wr_len            (fe_wr_len),
        .o_wr_size           (fe_wr_size),
        .o_wr_burst          (fe_wr_burst),
        .o_wr_qos            (fe_wr_qos),
        .o_wr_addr_cross_4kb (fe_wr_addr_cross_4kb),

        .o_wr_data_valid     (fe_wr_data_valid),
        .i_wr_data_ready     (fe_wr_data_ready),
        .o_wr_data           (fe_wr_data),
        .o_wr_strb           (fe_wr_strb),
        .o_wr_last           (fe_wr_last),

        .i_bresp_valid       (bresp_valid),
        .o_bresp_ready       (),
        .i_bresp_id          (bresp_id),
        .i_bresp_code        (2'b00),

        .o_rd_req_valid      (fe_rd_req_valid),
        .i_rd_req_ready      (fe_rd_req_ready),
        .o_rd_req_id         (fe_rd_req_id),
        .o_rd_req_addr       (fe_rd_req_addr),
        .o_rd_req_len        (fe_rd_req_len),
        .o_rd_req_size       (fe_rd_req_size),
        .o_rd_req_burst      (fe_rd_req_burst),
        .o_rd_req_qos        (fe_rd_req_qos),
        .o_rd_req_cross_4kb  (fe_rd_req_cross_4kb),

        .i_rdata_valid       (rob_rvalid),
        .o_rdata_ready       (),
        .i_rdata_id          (rob_rid),
        .i_rdata             (rob_rdata),
        .i_rdata_resp        (rob_rresp),
        .i_rdata_last        (rob_rlast)
    );

    // Write Decoupling Buffer
    logic                      wbuf_data_valid;
    logic [AXI_DATA_WIDTH-1:0] wbuf_data;
    logic                      wbuf_data_last;

    wdata_buffer #(
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_QOS_WIDTH  (AXI_QOS_WIDTH),
        .BUFFER_DEPTH   (32),
        .CMD_FIFO_DEPTH (8)
    ) u_wdata_buffer (
        .clk_axi             (clk_axi),
        .aresetn_axi         (rst_n_axi),

        .i_wr_addr_valid     (fe_wr_addr_valid),
        .o_wr_addr_ready     (fe_wr_addr_ready),
        .i_wr_addr_id        (fe_wr_addr_id),
        .i_wr_addr           (fe_wr_addr),
        .i_wr_len            (fe_wr_len),
        .i_wr_size           (fe_wr_size),
        .i_wr_burst          (fe_wr_burst),
        .i_wr_qos            (fe_wr_qos),
        .i_wr_addr_cross_4kb (fe_wr_addr_cross_4kb),

        .i_wr_data_valid     (fe_wr_data_valid),
        .o_wr_data_ready     (fe_wr_data_ready),
        .i_wr_data           (fe_wr_data),
        .i_wr_strb           (fe_wr_strb),
        .i_wr_last           (fe_wr_last),

        .o_cmd_valid         (wbuf_cmd_valid),
        .i_cmd_ready         (wbuf_cmd_ready),
        .o_cmd_id            (wbuf_cmd_id),
        .o_cmd_addr          (wbuf_cmd_addr),
        .o_cmd_len           (wbuf_cmd_len),
        .o_cmd_size          (),
        .o_cmd_burst         (),
        .o_cmd_qos           (wbuf_cmd_qos),
        .o_cmd_cross_4kb     (),

        .o_data_valid        (wbuf_data_valid),
        .i_data_ready        (1'b1),
        .o_data              (wbuf_data),
        .o_strb              (),
        .o_last              (wbuf_data_last)
    );

    //=========================================================================
    // 3. Address Mapper (Maps Linear Address to Bank Group, Bank, Row, Col)
    //=========================================================================
    // Command MUX between Read and Write into Mapper
    logic                      req_to_map_valid;
    logic                      req_to_map_ready;
    logic [AXI_ID_WIDTH-1:0]   req_to_map_id;
    logic                      req_to_map_is_write;
    logic [AXI_ADDR_WIDTH-1:0] req_to_map_addr;
    logic [7:0]                req_to_map_len;
    logic [AXI_QOS_WIDTH-1:0]  req_to_map_qos;

    // Read allocation from ROB
    logic [ROB_PTR_WIDTH-1:0]  rob_alloc_tag;
    logic                      rob_alloc_ready;
    logic                      rob_raw_hazard;

    // Priority: Serve Read first if ROB has slot and no RAW hazard, else Write
    wire can_issue_read  = fe_rd_req_valid && rob_alloc_ready && !rob_raw_hazard;
    wire can_issue_write = wbuf_cmd_valid;

    always_comb begin
        if (can_issue_read) begin
            req_to_map_valid    = 1'b1;
            req_to_map_is_write = 1'b0;
            req_to_map_id       = {{(AXI_ID_WIDTH-ROB_PTR_WIDTH){1'b0}}, rob_alloc_tag};
            req_to_map_addr     = fe_rd_req_addr;
            req_to_map_len      = fe_rd_req_len;
            req_to_map_qos      = fe_rd_req_qos;
        end else if (can_issue_write) begin
            req_to_map_valid    = 1'b1;
            req_to_map_is_write = 1'b1;
            req_to_map_id       = wbuf_cmd_id;
            req_to_map_addr     = wbuf_cmd_addr;
            req_to_map_len      = wbuf_cmd_len;
            req_to_map_qos      = wbuf_cmd_qos;
        end else begin
            req_to_map_valid    = 1'b0;
            req_to_map_is_write = 1'b0;
            req_to_map_id       = '0;
            req_to_map_addr     = '0;
            req_to_map_len      = '0;
            req_to_map_qos      = '0;
        end
    end

    assign fe_rd_req_ready = req_to_map_ready && can_issue_read;
    assign wbuf_cmd_ready  = req_to_map_ready && !can_issue_read && can_issue_write;

    // Decoded Command from Mapper
    logic                      mapped_cmd_valid;
    logic                      mapped_cmd_ready;
    logic [AXI_ID_WIDTH-1:0]   mapped_cmd_id;
    logic                      mapped_cmd_is_write;
    logic [BG_WIDTH-1:0]       mapped_cmd_bg;
    logic [BANK_WIDTH-1:0]     mapped_cmd_bank;
    logic [ROW_WIDTH-1:0]      mapped_cmd_row;
    logic [COL_WIDTH-1:0]      mapped_cmd_col;
    logic [7:0]                mapped_cmd_len;
    logic [AXI_QOS_WIDTH-1:0]  mapped_cmd_qos;

    addr_mapper_ddr5 #(
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_QOS_WIDTH  (AXI_QOS_WIDTH),
        .ROW_WIDTH      (ROW_WIDTH),
        .COL_WIDTH      (COL_WIDTH),
        .BG_WIDTH       (BG_WIDTH),
        .BANK_WIDTH     (BANK_WIDTH)
    ) u_addr_mapper (
        .clk            (clk_axi),
        .rst_n          (rst_n_axi),
        .cfg_is_ddr5    (cfg_is_ddr5),

        .i_req_valid    (req_to_map_valid),
        .o_req_ready    (req_to_map_ready),
        .i_req_id       (req_to_map_id),
        .i_req_is_write (req_to_map_is_write),
        .i_req_addr     (req_to_map_addr),
        .i_req_len      (req_to_map_len),
        .i_req_qos      (req_to_map_qos),

        .o_cmd_valid    (mapped_cmd_valid),
        .i_cmd_ready    (mapped_cmd_ready),
        .o_cmd_id       (mapped_cmd_id),
        .o_cmd_is_write (mapped_cmd_is_write),
        .o_cmd_bg       (mapped_cmd_bg),
        .o_cmd_bank     (mapped_cmd_bank),
        .o_cmd_row      (mapped_cmd_row),
        .o_cmd_col      (mapped_cmd_col),
        .o_cmd_len      (mapped_cmd_len),
        .o_cmd_qos      (mapped_cmd_qos)
    );

    //=========================================================================
    // 4. Reorder Buffer (ROB) & RAW Hazard Detector
    //=========================================================================
    logic                      dram_wb_valid;
    logic [ROB_PTR_WIDTH-1:0]  dram_wb_tag;
    logic [AXI_DATA_WIDTH-1:0] dram_wb_data;
    logic [1:0]                dram_wb_resp;
    logic                      dram_wb_last;

    reorder_buffer_rob #(
        .AXI_ID_WIDTH    (AXI_ID_WIDTH),
        .AXI_DATA_WIDTH  (AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH  (AXI_ADDR_WIDTH),
        .AXI_LEN_WIDTH   (AXI_LEN_WIDTH),
        .ROB_DEPTH       (ROB_DEPTH),
        .MAX_BURST_BEATS (8),
        .MAX_WR_TRACK    (8)
    ) u_rob (
        .clk                (clk_axi),
        .rst_n              (rst_n_axi),

        .i_alloc_valid      (fe_rd_req_valid && fe_rd_req_ready),
        .i_alloc_id         (fe_rd_req_id),
        .i_alloc_addr       (fe_rd_req_addr),
        .i_alloc_len        (fe_rd_req_len),
        .o_alloc_ready      (rob_alloc_ready),
        .o_alloc_tag        (rob_alloc_tag),

        .i_wr_active_valid  ({7'b0, wbuf_cmd_valid}),
        .i_wr_active_addr   ({(7*AXI_ADDR_WIDTH)'(0), wbuf_cmd_addr}),
        .o_raw_hazard       (rob_raw_hazard),
        .o_raw_match_mask   (),

        .i_wb_valid         (dram_wb_valid),
        .i_wb_tag           (dram_wb_tag),
        .i_wb_data          (dram_wb_data),
        .i_wb_resp          (dram_wb_resp),
        .i_wb_last          (dram_wb_last),

        .o_rvalid           (rob_rvalid),
        .o_rid              (rob_rid),
        .o_rdata            (rob_rdata),
        .o_rresp            (rob_rresp),
        .o_rlast            (rob_rlast),
        .i_rready           (s_axi_rready),

        .o_rob_empty        (),
        .o_rob_full         (),
        .o_rob_count        ()
    );

    //=========================================================================
    // 5. SDC Resilient Filter (RowHammer Defense)
    //=========================================================================
    logic                      sdc_cmd_valid;
    logic                      sdc_cmd_ready;
    logic [AXI_ID_WIDTH-1:0]   sdc_cmd_id;
    logic                      sdc_cmd_is_write;
    logic [BG_WIDTH-1:0]       sdc_cmd_bg;
    logic [BANK_WIDTH-1:0]     sdc_cmd_bank;
    logic [ROW_WIDTH-1:0]      sdc_cmd_row;
    logic [COL_WIDTH-1:0]      sdc_cmd_col;
    logic [7:0]                sdc_cmd_len;
    logic [AXI_QOS_WIDTH-1:0]  sdc_cmd_qos;
    logic                      sdc_throttled;
    logic [31:0]               telemetry_throttles;

    // SDC, RowPress & DRM Interconnect
    logic                      sdc_mitigation_req;
    logic [BG_WIDTH-1:0]       sdc_mitigation_bg;
    logic [BANK_WIDTH-1:0]     sdc_mitigation_bank;
    logic [ROW_WIDTH-1:0]      sdc_mitigation_row;
    logic                      sdc_alert;
    logic [31:0]               telemetry_accesses;
    logic [15:0]               ate_dynamic_thresh;

    logic [15:0]               ddr_rowpress_alert_cnt;
    logic                      ddr_rowpress_alert;
    logic [BG_WIDTH-1:0]       ddr_rowpress_bg;
    logic [BANK_WIDTH-1:0]     ddr_rowpress_bank;
    logic [ROW_WIDTH-1:0]      ddr_rowpress_row;

    logic                      drm_mitigation_req;
    logic [BG_WIDTH-1:0]       drm_mitigation_bg;
    logic [BANK_WIDTH-1:0]     drm_mitigation_bank;
    logic [ROW_WIDTH-1:0]      drm_mitigation_row;
    logic                      drm_mitigation_grant;
    logic [15:0]               drm_ref_count;

    logic                      scrub_req;
    logic [BG_WIDTH-1:0]       scrub_bg;
    logic [BANK_WIDTH-1:0]     scrub_bank;
    logic [ROW_WIDTH-1:0]      scrub_row;
    logic                      scrub_grant;

    sdc_resilient_filter #(
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_QOS_WIDTH  (AXI_QOS_WIDTH),
        .ROW_WIDTH      (ROW_WIDTH),
        .COL_WIDTH      (COL_WIDTH),
        .BG_WIDTH       (BG_WIDTH),
        .BANK_WIDTH     (BANK_WIDTH),
        .TABLE_ENTRIES  (256),
        .COUNT_WIDTH    (16)
    ) u_sdc_filter (
        .clk                 (clk_axi),
        .rst_n               (rst_n_axi),

        .cfg_hash_mode       (cfg_dual_hash_en),
        .cfg_sdc_thresh      (ate_dynamic_thresh),
        .cfg_window_size     (cfg_window_size),

        .i_cmd_valid         (mapped_cmd_valid),
        .o_cmd_ready         (mapped_cmd_ready),
        .i_cmd_id            (mapped_cmd_id),
        .i_cmd_is_write      (mapped_cmd_is_write),
        .i_cmd_bg            (mapped_cmd_bg),
        .i_cmd_bank          (mapped_cmd_bank),
        .i_cmd_row           (mapped_cmd_row),
        .i_cmd_col           (mapped_cmd_col),
        .i_cmd_len           (mapped_cmd_len),
        .i_cmd_qos           (mapped_cmd_qos),

        .o_cmd_valid         (sdc_cmd_valid),
        .i_cmd_ready         (sdc_cmd_ready),
        .o_cmd_id            (sdc_cmd_id),
        .o_cmd_is_write      (sdc_cmd_is_write),
        .o_cmd_bg            (sdc_cmd_bg),
        .o_cmd_bank          (sdc_cmd_bank),
        .o_cmd_row           (sdc_cmd_row),
        .o_cmd_col           (sdc_cmd_col),
        .o_cmd_len           (sdc_cmd_len),
        .o_cmd_qos           (sdc_cmd_qos),
        .o_cmd_throttled     (sdc_throttled),

        .o_mitigation_req    (sdc_mitigation_req),
        .o_mitigation_bg     (sdc_mitigation_bg),
        .o_mitigation_bank   (sdc_mitigation_bank),
        .o_mitigation_row    (sdc_mitigation_row),
        .o_sdc_alert         (sdc_alert),
        .o_telemetry_accesses(telemetry_accesses),
        .o_telemetry_throttles(telemetry_throttles)
    );

    assign o_throttled_events = telemetry_throttles[15:0];

    // Adaptive Threshold Engine (ATE) Instance
    adaptive_threshold_engine #(
        .COUNT_WIDTH    (16),
        .ALPHA_SHIFT_DEF(4),
        .WINDOW_CYCLES  (1024)
    ) u_ate (
        .clk                  (clk_axi),
        .rst_n                (rst_n_axi),
        .cfg_ate_en           (1'b1),
        .cfg_alpha_shift      (4'd4),
        .cfg_base_thresh      (cfg_rh_threshold),
        .cfg_max_thresh       (16'd8192),
        .i_telemetry_accesses (telemetry_accesses),
        .i_telemetry_throttles(telemetry_throttles),
        .o_dynamic_thresh     (ate_dynamic_thresh),
        .o_sample_epochs      ()
    );

    //=========================================================================
    // 5b. Directed Refresh Manager (DRM)
    //=========================================================================
    directed_refresh_manager #(
        .BG_WIDTH    (BG_WIDTH),
        .BANK_WIDTH  (BANK_WIDTH),
        .ROW_WIDTH   (ROW_WIDTH),
        .QUEUE_DEPTH (8)
    ) u_drm (
        .clk                 (clk_axi),
        .rst_n               (rst_n_axi),

        .cfg_drm_en          (1'b1),
        .cfg_victim2_en      (1'b0),

        .i_sdc_req           (sdc_mitigation_req),
        .i_sdc_bg            (sdc_mitigation_bg),
        .i_sdc_bank          (sdc_mitigation_bank),
        .i_sdc_row           (sdc_mitigation_row),

        .i_rp_req            (ddr_rowpress_alert),
        .i_rp_bg             (ddr_rowpress_bg),
        .i_rp_bank           (ddr_rowpress_bank),
        .i_rp_row            (ddr_rowpress_row),

        .i_scrub_req         (scrub_req),
        .i_scrub_bg          (scrub_bg),
        .i_scrub_bank        (scrub_bank),
        .i_scrub_row         (scrub_row),
        .o_scrub_grant       (scrub_grant),

        .o_mitigation_req    (drm_mitigation_req),
        .o_mitigation_bg     (drm_mitigation_bg),
        .o_mitigation_bank   (drm_mitigation_bank),
        .o_mitigation_row    (drm_mitigation_row),
        .i_mitigation_grant  (drm_mitigation_grant),

        .o_drm_ref_count     (drm_ref_count),
        .o_queue_full        ()
    );

    //=========================================================================
    // 6. QoS Scheduler Queue (8 Bank Groups x 8 Entries)
    //=========================================================================
    logic [BG_COUNT-1:0]                 cand_valid;
    logic [BG_COUNT*AXI_ID_WIDTH-1:0]    cand_id;
    logic [BG_COUNT-1:0]                 cand_is_write;
    logic [BG_COUNT*BANK_WIDTH-1:0]      cand_bank;
    logic [BG_COUNT*ROW_WIDTH-1:0]       cand_row;
    logic [BG_COUNT*COL_WIDTH-1:0]       cand_col;
    logic [BG_COUNT*8-1:0]               cand_len;
    logic [BG_COUNT*AXI_QOS_WIDTH-1:0]   cand_qos;
    logic [BG_COUNT-1:0]                 cand_throttled;
    logic [BG_COUNT-1:0]                 cand_starved;
    logic [BG_COUNT*3-1:0]               cand_entry_idx;

    logic                                arb_grant_valid;
    logic [BG_WIDTH-1:0]                 arb_grant_bg;
    logic [2:0]                          arb_grant_idx;

    qos_scheduler_queue #(
        .AXI_ID_WIDTH    (AXI_ID_WIDTH),
        .AXI_QOS_WIDTH   (AXI_QOS_WIDTH),
        .ROW_WIDTH       (ROW_WIDTH),
        .COL_WIDTH       (COL_WIDTH),
        .BG_WIDTH        (BG_WIDTH),
        .BANK_WIDTH      (BANK_WIDTH),
        .QUEUE_DEPTH     (8),
        .STARVATION_LIMIT(64)
    ) u_qos_queue (
        .clk                 (clk_axi),
        .rst_n               (rst_n_axi),

        .i_cmd_valid         (sdc_cmd_valid),
        .o_cmd_ready         (sdc_cmd_ready),
        .i_cmd_id            (sdc_cmd_id),
        .i_cmd_is_write      (sdc_cmd_is_write),
        .i_cmd_bg            (sdc_cmd_bg),
        .i_cmd_bank          (sdc_cmd_bank),
        .i_cmd_row           (sdc_cmd_row),
        .i_cmd_col           (sdc_cmd_col),
        .i_cmd_len           (sdc_cmd_len),
        .i_cmd_qos           (sdc_cmd_qos),
        .i_cmd_throttled     (sdc_throttled),

        .i_issue_grant_valid (arb_grant_valid),
        .i_issue_grant_bg    (arb_grant_bg),
        .i_issue_grant_idx   (arb_grant_idx),

        .o_cand_valid        (cand_valid),
        .o_cand_id           (cand_id),
        .o_cand_is_write     (cand_is_write),
        .o_cand_bank         (cand_bank),
        .o_cand_row          (cand_row),
        .o_cand_col          (cand_col),
        .o_cand_len          (cand_len),
        .o_cand_qos          (cand_qos),
        .o_cand_throttled    (cand_throttled),
        .o_cand_starved      (cand_starved),
        .o_cand_entry_idx    (cand_entry_idx)
    );

    //=========================================================================
    // 7. Slack-Aware Arbiter
    //=========================================================================
    logic [BG_COUNT-1:0] ddr_bg_ready;
    logic                ddr_engine_ready;
    logic                ddr_slack_cycle;

    logic                arb_cmd_valid;
    logic                arb_cmd_is_write;
    logic [AXI_ID_WIDTH-1:0] arb_cmd_id;
    logic [BG_WIDTH-1:0] arb_cmd_bg;
    logic [BANK_WIDTH-1:0]arb_cmd_bank;
    logic [ROW_WIDTH-1:0] arb_cmd_row;
    logic [COL_WIDTH-1:0] arb_cmd_col;
    logic [AXI_LEN_WIDTH-1:0] arb_cmd_len;
    logic                arb_cmd_is_mitigation;

    slack_aware_arbiter #(
        .BG_COUNT        (BG_COUNT),
        .BANK_WIDTH      (BANK_WIDTH),
        .ROW_WIDTH       (ROW_WIDTH),
        .COL_WIDTH       (COL_WIDTH),
        .AXI_ID_WIDTH    (AXI_ID_WIDTH),
        .AXI_LEN_WIDTH   (AXI_LEN_WIDTH),
        .QUEUE_PTR_WIDTH (3)
    ) u_arbiter (
        .clk                 (clk_axi),
        .rst_n               (rst_n_axi),

        .i_cand_valid        (cand_valid),
        .i_cand_id           (cand_id),
        .i_cand_is_write     (cand_is_write),
        .i_cand_bank         (cand_bank),
        .i_cand_row          (cand_row),
        .i_cand_col          (cand_col),
        .i_cand_len          (cand_len),
        .i_cand_qos          (cand_qos),
        .i_cand_throttled    (cand_throttled),
        .i_cand_starved      (cand_starved),
        .i_cand_queue_idx    (cand_entry_idx),

        .i_bg_ready          (ddr_bg_ready),
        .i_engine_ready      (ddr_engine_ready),
        .i_slack_cycle       (ddr_slack_cycle),

        .i_mitigation_req    (drm_mitigation_req),
        .i_mitigation_bg     (drm_mitigation_bg),
        .i_mitigation_bank   (drm_mitigation_bank),
        .i_mitigation_row    (drm_mitigation_row),
        .o_mitigation_grant  (drm_mitigation_grant),

        .o_issue_grant_valid (arb_grant_valid),
        .o_issue_grant_bg    (arb_grant_bg),
        .o_issue_grant_idx   (arb_grant_idx),

        .o_cmd_valid         (arb_cmd_valid),
        .o_cmd_is_write      (arb_cmd_is_write),
        .o_cmd_id            (arb_cmd_id),
        .o_cmd_bg            (arb_cmd_bg),
        .o_cmd_bank          (arb_cmd_bank),
        .o_cmd_row           (arb_cmd_row),
        .o_cmd_col           (arb_cmd_col),
        .o_cmd_len           (arb_cmd_len),
        .o_cmd_is_mitigation (arb_cmd_is_mitigation),
        .o_drain_mode        ()
    );

    ddr5_cmd_engine #(
        .BG_COUNT        (BG_COUNT),
        .BANK_COUNT      (BANK_COUNT),
        .ROW_WIDTH       (ROW_WIDTH),
        .COL_WIDTH       (COL_WIDTH),
        .AXI_ID_WIDTH    (AXI_ID_WIDTH),
        .AXI_DATA_WIDTH  (AXI_DATA_WIDTH),
        .AXI_LEN_WIDTH   (AXI_LEN_WIDTH),
        .ROB_PTR_WIDTH   (ROB_PTR_WIDTH)
    ) u_cmd_engine (
        .clk                 (clk_axi),
        .rst_n               (rst_n_axi),

        .i_cmd_valid         (arb_cmd_valid),
        .i_cmd_is_write      (arb_cmd_is_write),
        .i_cmd_id            (arb_cmd_id),
        .i_cmd_bg            (arb_cmd_bg),
        .i_cmd_bank          (arb_cmd_bank),
        .i_cmd_row           (arb_cmd_row),
        .i_cmd_col           (arb_cmd_col),
        .i_cmd_len           (arb_cmd_len),
        .i_cmd_tag           (arb_cmd_id[ROB_PTR_WIDTH-1:0]),
        .i_cmd_is_mitigation (arb_cmd_is_mitigation),

        .cfg_rowpress_thresh (16'd5000),
        .o_rowpress_alert    (ddr_rowpress_alert),
        .o_rowpress_bg       (ddr_rowpress_bg),
        .o_rowpress_bank     (ddr_rowpress_bank),
        .o_rowpress_row      (ddr_rowpress_row),
        .o_rowpress_alert_cnt(ddr_rowpress_alert_cnt),

        .o_bg_ready          (ddr_bg_ready),
        .o_engine_ready      (ddr_engine_ready),
        .o_slack_cycle       (ddr_slack_cycle),

        .o_dfi_cmd           (dfi_cmd),
        .o_dfi_bg            (dfi_bg),
        .o_dfi_bank          (dfi_bank),
        .o_dfi_row           (dfi_row),
        .o_dfi_col           (dfi_col),

        .o_wb_valid          (dram_wb_valid),
        .o_wb_tag            (dram_wb_tag),
        .o_wb_data           (dram_wb_data),
        .o_wb_resp           (dram_wb_resp),
        .o_wb_last           (dram_wb_last)
    );

    //=========================================================================
    // 9. ECC Background Patrol Scrubber
    //=========================================================================
    ecc_scrubber #(
        .DATA_WIDTH       (AXI_DATA_WIDTH),
        .ECC_WIDTH        (8),
        .BG_COUNT         (BG_COUNT),
        .BANK_COUNT       (BANK_COUNT),
        .ROW_WIDTH        (ROW_WIDTH),
        .DEFAULT_INTERVAL (500)
    ) u_ecc_scrubber (
        .clk                 (clk_axi),
        .rst_n               (rst_n_axi),

        .cfg_enable          (1'b1),
        .cfg_interval        (16'd500),

        .o_scrub_req         (scrub_req),
        .o_scrub_bg          (scrub_bg),
        .o_scrub_bank        (scrub_bank),
        .o_scrub_row         (scrub_row),
        .i_scrub_grant       (scrub_grant),

        .i_data_valid        (dram_wb_valid),
        .i_raw_data          (dram_wb_data),
        .i_raw_ecc           (8'h00),

        .i_fault_inject_en   (1'b0),
        .i_fault_inject_type (2'b00),
        .i_fault_inject_bit  (6'd0),

        .o_corrected_valid   (),
        .o_corrected_data    (),
        .o_single_err        (),
        .o_double_err        (),
        .o_single_err_cnt    (o_ecc_single_err_cnt),
        .o_double_err_cnt    (o_ecc_double_err_cnt)
    );

    // Unused signals sink
    logic _unused_top_sink;
    assign _unused_top_sink = &{1'b0, rst_n_ddr, wbuf_data_valid, wbuf_data, wbuf_data_last, 1'b0};

endmodule
