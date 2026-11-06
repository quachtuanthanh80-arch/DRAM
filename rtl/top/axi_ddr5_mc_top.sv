// File:        axi_ddr5_mc_top.sv
// Chức năng:   Khối đỉnh tích hợp bộ điều khiển bộ nhớ DDR5/DDR4 không chu kỳ rỗng (Zero-Bubble MC Top).
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
    parameter int COL_WIDTH       = 13, // địa chỉ word 8 byte addr[15:3]: hai word cùng dòng 64B không được trùng cột
    parameter int ROB_DEPTH       = 16,
    parameter int ROB_PTR_WIDTH   = $clog2(ROB_DEPTH),
    // Độ trễ ghi DFI (WR -> beat dữ liệu đầu, tphy_wrlat) = 1 (sinh beat) + 6 (keystream) + 2 (thanh ghi XOR, ECC).
    // Mô hình DRAM/PHY phải dùng cùng giá trị.
    parameter int DFI_WRLAT       = 9,
    // Độ trễ đọc DFI (RD -> beat đầu ở dfi_rddata_valid); cộng 1 chu kỳ thanh ghi rdq_valid thành T_RDV của engine
    parameter int DFI_RDLAT       = 8,
    // Định thời JEDEC theo picosecond và chu kỳ clock bộ điều khiển (M-04)
    parameter int TCK_PS          = 2500,
    parameter int TRCD_PS         = 17500,
    parameter int TRP_PS          = 17500,
    parameter int TRAS_PS         = 32000,
    parameter int TRFC_PS         = 295000,
    parameter int TRFM_PS         = 295000,
    parameter int TREFI_PS        = 3900000,
    parameter int TWR_PS          = 30000,
    parameter int TRTP_PS         = 7500,
    parameter int TRRD_S_PS       = 5000,
    parameter int TRRD_L_PS       = 5000,
    parameter int TFAW_PS         = 25000,
    parameter int TCCD_S_PS       = 5000,
    parameter int TCCD_L_PS       = 5000,
    parameter int TCCD_L_WR_PS    = 20000,
    parameter int TWTR_S_PS       = 2500,
    parameter int TWTR_L_PS       = 10000,
    // CWL + BL16/2 của DRAM: mốc cuối dữ liệu ghi của engine ((DFI_WRLAT + 1) chu kỳ) không được sớm hơn (M-12)
    parameter int TCWL_BL_PS      = 21250
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
    output logic [(AXI_DATA_WIDTH>=64?AXI_DATA_WIDTH/64:1)-1:0] s_axi_rpoison,
    output logic [AXI_DATA_WIDTH/8-1:0]                  s_axi_rchk,
    output logic                                         o_parity_err,

    //-------------------------------------------------------------------------
    // DFI 5.0 / DRAM Physical Interface
    //-------------------------------------------------------------------------
    output logic [2:0]                                   dfi_cmd,
    output logic [BG_WIDTH-1:0]                          dfi_bg,
    output logic [BANK_WIDTH-1:0]                        dfi_bank,
    output logic [ROW_WIDTH-1:0]                         dfi_row,
    output logic [COL_WIDTH-1:0]                         dfi_col,
    output logic [7:0]                                   dfi_len,          // số beat - 1 của lệnh CAS
    output logic                                         dfi_wrdata_en,
    output logic [AXI_DATA_WIDTH-1:0]                    dfi_wrdata,
    output logic [AXI_DATA_WIDTH/8-1:0]                  dfi_wrdata_mask,  // 1 = byte được ghi (WSTRB)
    output logic [AXI_DATA_WIDTH/8-1:0]                  dfi_wrdata_ecc,   // SEC-DED (72,64): 8 bit cho mỗi làn 64 bit
    input  logic                                         dfi_rddata_valid,
    input  logic [AXI_DATA_WIDTH-1:0]                    dfi_rddata,
    input  logic [AXI_DATA_WIDTH/8-1:0]                  dfi_rddata_ecc,

    //-------------------------------------------------------------------------
    // Configuration & Telemetry Ports
    //-------------------------------------------------------------------------
    input  logic                                         cfg_is_ddr5,
    input  logic                                         cfg_dual_hash_en,
    input  logic [15:0]                                  cfg_rh_threshold,
    input  logic [15:0]                                  cfg_window_size,
    output logic [15:0]                                  o_throttled_events,
    output logic [15:0]                                  o_ecc_single_err_cnt,
    output logic [15:0]                                  o_ecc_double_err_cnt,

    // Extended Architecture & Telemetry Ports (Upgrade V3)
    input  logic                                         cfg_bank_coloring_en = 1'b0,
    input  logic [1:0]                                   cfg_mapping_mode     = 2'b00,
    input  logic                                         cfg_scramble_en      = 1'b0,
    input  logic                                         cfg_scramble_reseed  = 1'b0,
    input  logic [63:0]                                  cfg_scramble_seed    = 64'hA5A5_5A5A_0123_4567,
    input  logic                                         cfg_pmu_en           = 1'b1,
    input  logic                                         cfg_pmu_reset        = 1'b0,
    output logic [7:0][31:0]                             o_pmu_counters,

    // Advanced Threat Defense & PRAC Alerts (Upgrade P0)
    input  logic [1:0]                                   cfg_rowpress_curve = 2'b00,
    input  logic                                         cfg_victim3_en     = 1'b0,
    input  logic                                         i_dram_abo_alert   = 1'b0,
    output logic [15:0]                                  o_abo_alert_cnt,
    output logic [15:0]                                  o_ecc_miscorrect_cnt,
    output logic                                         o_coordinated_throttle_active,
    output logic [15:0]                                  o_rfm_auto_cnt,
    output logic                                         o_tras_clamped_alert,

    // Cryptographic & Fault-Tolerant Enhancements (Upgrade V3.0)
    input  logic [1:0]                                   cfg_scramble_mode  = 2'b10, // 0: None, 1: LFSR, 2: SCARF
    input  logic                                         cfg_decoy_en       = 1'b0,
    input  logic                                         cfg_fault_clr      = 1'b0,
    output logic                                         o_decoy_active,
    output logic [15:0]                                  o_decoy_cnt,
    output logic [8:0]                                   o_fault_cause,
    output logic                                         o_glitch_alert,
    output logic                                         o_security_locked
);
    import secded_72_64_pkg::*;

    // Quy đổi tham số định thời JEDEC từ picosecond sang số chu kỳ clock bộ điều khiển (M-04)
    localparam int T_RCD_C      = (TRCD_PS      + TCK_PS - 1) / TCK_PS;
    localparam int T_RP_C       = (TRP_PS       + TCK_PS - 1) / TCK_PS;
    localparam int T_RAS_C      = (TRAS_PS      + TCK_PS - 1) / TCK_PS;
    localparam int T_RFC_C      = (TRFC_PS      + TCK_PS - 1) / TCK_PS;
    localparam int T_RFM_C      = (TRFM_PS      + TCK_PS - 1) / TCK_PS;
    localparam int T_REFI_C     = TREFI_PS / TCK_PS;
    localparam int T_WR_C       = (TWR_PS       + TCK_PS - 1) / TCK_PS;
    localparam int T_RTP_C      = (TRTP_PS      + TCK_PS - 1) / TCK_PS;
    localparam int T_RRD_S_C    = (TRRD_S_PS    + TCK_PS - 1) / TCK_PS;
    localparam int T_RRD_L_C    = (TRRD_L_PS    + TCK_PS - 1) / TCK_PS;
    localparam int T_FAW_C      = (TFAW_PS      + TCK_PS - 1) / TCK_PS;
    localparam int T_CCD_S_C    = (TCCD_S_PS    + TCK_PS - 1) / TCK_PS;
    localparam int T_CCD_L_C    = (TCCD_L_PS    + TCK_PS - 1) / TCK_PS;
    localparam int T_CCD_L_WR_C = (TCCD_L_WR_PS + TCK_PS - 1) / TCK_PS;
    localparam int T_WTR_S_C    = (TWTR_S_PS    + TCK_PS - 1) / TCK_PS;
    localparam int T_WTR_L_C    = (TWTR_L_PS    + TCK_PS - 1) / TCK_PS;
    // Kẹp mở hàng = min(8775, floor(9 x tREFI / tCK) - 64) (spec_v2 M-04): 8775 ở 2.5 ns, 8711 ở 4 ns
    localparam int TRAS_MAX_JED = (9 * TREFI_PS) / TCK_PS - 64;
    localparam int TRAS_MAX_DEF = (TRAS_MAX_JED < 8775) ? TRAS_MAX_JED : 8775;

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
    logic [AXI_QOS_WIDTH-1:0]  fe_rd_req_qos;
    logic                      fe_rd_req_cross_4kb;
    logic                      fe_rd_req_last;

    // Kênh AW/AR thô từ frontend, trước bộ tách burst
    logic                      fe_aw_valid, fe_aw_ready;
    logic [AXI_ID_WIDTH-1:0]   fe_aw_id;
    logic [AXI_ADDR_WIDTH-1:0] fe_aw_addr;
    logic [7:0]                fe_aw_len;
    logic [2:0]                fe_aw_size;
    logic [1:0]                fe_aw_burst;
    logic [AXI_QOS_WIDTH-1:0]  fe_aw_qos;
    logic                      fe_ar_valid, fe_ar_ready;
    logic [AXI_ID_WIDTH-1:0]   fe_ar_id;
    logic [AXI_ADDR_WIDTH-1:0] fe_ar_addr;
    logic [7:0]                fe_ar_len;
    logic [2:0]                fe_ar_size;
    logic [1:0]                fe_ar_burst;
    logic [AXI_QOS_WIDTH-1:0]  fe_ar_qos;
    logic                      fe_wr_chunk_last;
    logic                      ar_chunk_valid, ar_chunk_ready, ar_chunk_last;
    logic [AXI_ID_WIDTH-1:0]   ar_chunk_id;
    logic [AXI_ADDR_WIDTH-1:0] ar_chunk_addr;
    logic [7:0]                ar_chunk_len;
    logic [AXI_QOS_WIDTH-1:0]  ar_chunk_qos;
    logic [BG_WIDTH-1:0]       fe_rd_req_bg;
    logic                      iq_sel_fire;
    logic [BG_WIDTH-1:0]       iq_sel_bg;
    logic                      aw_split_busy;

    // Read Response into Frontend (Directly driven by ROB)
    logic                      rob_rvalid;
    logic [AXI_ID_WIDTH-1:0]   rob_rid;
    logic [AXI_DATA_WIDTH-1:0] rob_rdata;
    logic [1:0]                rob_rresp;
    logic                      rob_rlast;

    // Early declarations for cross-module error signals
    logic                      ecc_double_err;
    logic                      ecc_miscorrect_alert;
    logic                      drm_stall;

    // Write Decoupling Buffer Command Signals
    logic                      wbuf_cmd_valid;
    logic                      wbuf_cmd_ready;
    logic [AXI_ID_WIDTH-1:0]   wbuf_cmd_id;
    logic [AXI_ADDR_WIDTH-1:0] wbuf_cmd_addr;
    logic [7:0]                wbuf_cmd_len;
    logic [AXI_QOS_WIDTH-1:0]  wbuf_cmd_qos;
    logic                      wbuf_cmd_last;

    // Phản hồi B do wr_data_store phát sau khi beat cuối (WLAST) đã được lưu.
    // Trước đây B được phát ngay khi lệnh AW rời wdata_buffer, có thể trước cả dữ liệu W (vi phạm AXI4, R26).
    logic                      bresp_valid;
    logic                      bresp_ready;
    logic [AXI_ID_WIDTH-1:0]   bresp_id;

    // Điều khiển nhập AR theo QoS: tối đa LO_AR_CAP lệnh đọc QoS thấp đã nhận mà chưa phát vào bộ ánh xạ.
    // Lệnh QoS thấp vượt ngân sách được giữ ở cổng (ARREADY = 0 cho chính lệnh đó); lệnh QoS cao luôn được nhận nên
    // không bị chặn sau luồng QoS thấp bên trong controller (R20). Điều tiết công bằng giữa các master trên cùng
    // cổng là nhiệm vụ của interconnect (bộ điều tiết QoS kiểu QoS-400).
    localparam int QOS_RSV   = 4;
    localparam int LO_AR_CAP = 6;
    logic       fe_arready;
    logic [4:0] lo_ar_cnt;
    logic       cfg_pend_q;
    wire        ar_lo     = s_axi_arqos < AXI_QOS_WIDTH'(QOS_RSV);
    wire        ar_admit  = (!ar_lo || (lo_ar_cnt < 5'(LO_AR_CAP))) && !cfg_pend_q;
    assign      s_axi_arready = fe_arready && ar_admit;
    wire        lo_ar_in  = s_axi_arvalid && s_axi_arready && ar_lo;
    wire        lo_ar_out = fe_rd_req_valid && fe_rd_req_ready && fe_rd_req_last && (fe_rd_req_qos < AXI_QOS_WIDTH'(QOS_RSV));
    always_ff @(posedge clk_axi or negedge rst_n_axi) begin
        if (!rst_n_axi) lo_ar_cnt <= '0;
        else            lo_ar_cnt <= lo_ar_cnt + (lo_ar_in ? 5'd1 : 5'd0) - (lo_ar_out ? 5'd1 : 5'd0);
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
        .s_axi_arvalid       (s_axi_arvalid && ar_admit),
        .s_axi_arready       (fe_arready),

        .s_axi_rid           (s_axi_rid),
        .s_axi_rdata         (s_axi_rdata),
        .s_axi_rresp         (s_axi_rresp),
        .s_axi_rlast         (s_axi_rlast),
        .s_axi_rvalid        (s_axi_rvalid),
        .s_axi_rready        (s_axi_rready),

        .o_wr_addr_valid     (fe_aw_valid),
        .i_wr_addr_ready     (fe_aw_ready),
        .o_wr_addr_id        (fe_aw_id),
        .o_wr_addr           (fe_aw_addr),
        .o_wr_len            (fe_aw_len),
        .o_wr_size           (fe_aw_size),
        .o_wr_burst          (fe_aw_burst),
        .o_wr_qos            (fe_aw_qos),
        .o_wr_addr_cross_4kb (fe_wr_addr_cross_4kb),

        .o_wr_data_valid     (fe_wr_data_valid),
        .i_wr_data_ready     (fe_wr_data_ready),
        .o_wr_data           (fe_wr_data),
        .o_wr_strb           (fe_wr_strb),
        .o_wr_last           (fe_wr_last),

        .i_bresp_valid       (bresp_valid),
        .o_bresp_ready       (bresp_ready),
        .i_bresp_id          (bresp_id),
        .i_bresp_code        (2'b00),

        .o_rd_req_valid      (fe_ar_valid),
        .i_rd_req_ready      (fe_ar_ready),
        .o_rd_req_id         (fe_ar_id),
        .o_rd_req_addr       (fe_ar_addr),
        .o_rd_req_len        (fe_ar_len),
        .o_rd_req_size       (fe_ar_size),
        .o_rd_req_burst      (fe_ar_burst),
        .o_rd_req_qos        (fe_ar_qos),
        .o_rd_req_cross_4kb  (fe_rd_req_cross_4kb),

        .i_rdata_valid       (rob_rvalid),
        .o_rdata_ready       (),
        .i_rdata_id          (rob_rid),
        .i_rdata             (rob_rdata),
        .i_rdata_resp        (rob_rresp),
        .i_rdata_last        (rob_rlast),
        .s_axi_rpoison       (s_axi_rpoison),
        .s_axi_rchk          (s_axi_rchk),
        .o_parity_err        (o_parity_err),
        // Poison đi theo từng beat qua RRESP=SLVERR (gắn ở đường dữ liệu DRAM); cờ scrubber không căn theo beat
        .i_rdata_poison      (1'b0)
    );

    //=========================================================================
    // 2a. Tách burst AXI (R27): ROB, kho dữ liệu ghi và lệnh DRAM làm việc theo đoạn nằm trong một dòng 64B,
    // tối đa 8 beat. Burst INCR tới 256 beat, WRAP, FIXED và truyền hẹp đều được chia thành các đoạn đó;
    // chỉ đoạn cuối mang RLAST/phản hồi B. Trước đây burst > 8 beat bị cắt (ROB treo chờ beat, dữ liệu ghi bị bỏ).
    //=========================================================================
    axi_burst_splitter #(
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_QOS_WIDTH  (AXI_QOS_WIDTH),
        .DATA_BYTES     (AXI_DATA_WIDTH / 8)
    ) u_ar_split (
        .clk     (clk_axi),
        .rst_n   (rst_n_axi),
        .i_valid (fe_ar_valid),
        .o_ready (fe_ar_ready),
        .i_id    (fe_ar_id),
        .i_addr  (fe_ar_addr),
        .i_len   (fe_ar_len),
        .i_size  (fe_ar_size),
        .i_burst (fe_ar_burst),
        .i_qos   (fe_ar_qos),
        .o_valid (ar_chunk_valid),
        .i_ready (ar_chunk_ready),
        .o_id    (ar_chunk_id),
        .o_addr  (ar_chunk_addr),
        .o_len   (ar_chunk_len),
        .o_qos   (ar_chunk_qos),
        .o_last  (ar_chunk_last),
        .o_busy  ()
    );

    axi_burst_splitter #(
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_QOS_WIDTH  (AXI_QOS_WIDTH),
        .DATA_BYTES     (AXI_DATA_WIDTH / 8)
    ) u_aw_split (
        .clk     (clk_axi),
        .rst_n   (rst_n_axi),
        .i_valid (fe_aw_valid),
        .o_ready (fe_aw_ready),
        .i_id    (fe_aw_id),
        .i_addr  (fe_aw_addr),
        .i_len   (fe_aw_len),
        .i_size  (fe_aw_size),
        .i_burst (fe_aw_burst),
        .i_qos   (fe_aw_qos),
        .o_valid (fe_wr_addr_valid),
        .i_ready (fe_wr_addr_ready),
        .o_id    (fe_wr_addr_id),
        .o_addr  (fe_wr_addr),
        .o_len   (fe_wr_len),
        .o_qos   (fe_wr_qos),
        .o_last  (fe_wr_chunk_last),
        .o_busy  (aw_split_busy)
    );
    assign fe_wr_size = 3'($clog2(AXI_DATA_WIDTH / 8));
    assign fe_wr_burst = 2'b01;

    // Write Decoupling Buffer
    logic                      wbuf_data_valid;
    logic                      wbuf_data_ready;
    logic [AXI_DATA_WIDTH-1:0] wbuf_data;
    logic [AXI_DATA_WIDTH/8-1:0] wbuf_data_strb;
    logic                      wbuf_data_last;
    logic [7:0]                wbuf_wr_active_valid;
    logic [8*AXI_ADDR_WIDTH-1:0] wbuf_wr_active_addr;

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
        .i_wr_addr_cross_4kb (1'b0),
        .i_wr_chunk_last     (fe_wr_chunk_last),

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
        .o_cmd_last          (wbuf_cmd_last),

        .o_data_valid        (wbuf_data_valid),
        .i_data_ready        (wbuf_data_ready),
        .o_data              (wbuf_data),
        .o_strb              (wbuf_data_strb),
        .o_last              (wbuf_data_last),

        .o_wr_active_valid   (wbuf_wr_active_valid),
        .o_wr_active_addr    (wbuf_wr_active_addr)
    );

    //=========================================================================
    // 2b. Write Data Store: gom trọn burst ghi vào slot có tag trước khi lệnh vào pipeline
    //=========================================================================
    localparam int WDS_SLOTS = 1 << ROB_PTR_WIDTH;
    logic                      wcmd_valid;
    logic                      wcmd_ready;
    logic [AXI_ID_WIDTH-1:0]   wcmd_id;
    logic [ROB_PTR_WIDTH-1:0]  wcmd_tag;
    logic [AXI_ADDR_WIDTH-1:0] wcmd_addr;
    logic [7:0]                wcmd_len;
    logic [AXI_QOS_WIDTH-1:0]  wcmd_qos;
    logic                      wstage_busy;
    logic [AXI_ADDR_WIDTH-1:0] wstage_addr;
    logic [ROB_PTR_WIDTH-1:0]  wds_rd_tag;
    logic [2:0]                wds_rd_beat;
    logic [AXI_DATA_WIDTH-1:0] wds_rd_data;
    logic [AXI_DATA_WIDTH/8-1:0] wds_rd_strb;
    logic                      wds_rd_poison;
    logic                      wds_free;
    logic [WDS_SLOTS-1:0]      wds_partial;
    logic                      rmw_valid;
    logic                      wbq_valid, wbq_rmw, wbq_last, wbq_ue;
    logic [ROB_PTR_WIDTH-1:0]  wbq_tag;
    logic [AXI_DATA_WIDTH-1:0] wbq_data;
    logic [1:0]                wbq_resp;
    logic [2:0]                wbq_beat;
    logic [AXI_LEN_WIDTH-1:0]  rmw_beat;
    logic [ROB_PTR_WIDTH-1:0]  rmw_tag;
    logic [AXI_DATA_WIDTH-1:0] rd_descrambled;
    logic                      rd_ue;

    wr_data_store #(
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_QOS_WIDTH  (AXI_QOS_WIDTH),
        .SLOTS          (WDS_SLOTS),
        .MAX_BEATS      (8)
    ) u_wds (
        .clk              (clk_axi),
        .rst_n            (rst_n_axi),
        .i_cmd_valid      (wbuf_cmd_valid),
        .o_cmd_ready      (wbuf_cmd_ready),
        .i_cmd_id         (wbuf_cmd_id),
        .i_cmd_addr       (wbuf_cmd_addr),
        .i_cmd_len        (wbuf_cmd_len),
        .i_cmd_qos        (wbuf_cmd_qos),
        .i_cmd_last       (wbuf_cmd_last),
        .i_data_valid     (wbuf_data_valid),
        .o_data_ready     (wbuf_data_ready),
        .i_data           (wbuf_data),
        .i_strb           (wbuf_data_strb),
        .i_last           (wbuf_data_last),
        .i_wbeat_accepted (fe_wr_data_valid && fe_wr_data_ready),
        .o_wcmd_valid     (wcmd_valid),
        .i_wcmd_ready     (wcmd_ready),
        .o_wcmd_id        (wcmd_id),
        .o_wcmd_tag       (wcmd_tag),
        .o_wcmd_addr      (wcmd_addr),
        .o_wcmd_len       (wcmd_len),
        .o_wcmd_qos       (wcmd_qos),
        .o_bresp_valid    (bresp_valid),
        .i_bresp_ready    (bresp_ready),
        .o_bresp_id       (bresp_id),
        .o_stage_busy     (wstage_busy),
        .o_stage_addr     (wstage_addr),
        .i_rd_tag         (wds_rd_tag),
        .i_rd_beat        (wds_rd_beat),
        .o_rd_data        (wds_rd_data),
        .o_rd_strb        (wds_rd_strb),
        .o_rd_poison      (wds_rd_poison),
        .i_free_valid     (wds_free),
        .i_free_tag       (wds_rd_tag),
        .o_partial        (wds_partial),
        .i_mrg_valid      (wbq_rmw),
        .i_mrg_tag        (wbq_tag),
        .i_mrg_beat       (wbq_beat),
        .i_mrg_data       (wbq_data),
        .i_mrg_poison     (wbq_ue)
    );

    //=========================================================================
    // 3. Address Mapper (Maps Linear Address to Bank Group, Bank, Row, Col)
    //=========================================================================
    // Command MUX between Read and Write into Mapper
    logic                      req_to_map_valid;
    logic                      req_to_map_ready;
    logic [AXI_ID_WIDTH-1:0]   req_to_map_id;
    logic [AXI_ID_WIDTH-1:0]   req_to_map_tenant;
    logic                      req_to_map_is_write;
    logic [AXI_ADDR_WIDTH-1:0] req_to_map_addr;
    logic [7:0]                req_to_map_len;
    logic [AXI_QOS_WIDTH-1:0]  req_to_map_qos;

    // Read allocation from ROB
    logic [ROB_PTR_WIDTH-1:0]  rob_alloc_tag;
    logic                      rob_alloc_ready;
    logic                      rob_raw_hazard;

    //=========================================================================
    // Tín dụng bank group (R20): số lệnh của mỗi BG đang nằm giữa điểm phát và hàng đợi QoS (pipeline ánh xạ,
    // SDC, hàng đợi) không vượt quá độ sâu hàng đợi BG. Pipeline phía sau vì vậy không bao giờ dừng do một BG đầy,
    // và lệnh tới BG khác không bị chặn đầu hàng. Tăng khi lệnh vào bộ ánh xạ, giảm khi arbiter cấp lệnh của BG.
    //=========================================================================
    localparam int BG_QDEPTH = 8;
    // Dự trữ entry ROB theo QoS (kiểu QoS-based reservation của bộ điều khiển AXI): lệnh đọc QoS thấp không lấy được
    // ROB_RSV entry cuối, nên luồng QoS thấp làm đầy ROB không chặn được lệnh QoS cao (R20). Lệnh đã nằm ở thanh ghi
    // đầu ra của hàng đợi phát lệnh được tính là đã chiếm một entry.
    localparam int ROB_RSV = 2;
    logic [ROB_PTR_WIDTH:0] rob_count;
    wire  [ROB_PTR_WIDTH+1:0] rob_used = (ROB_PTR_WIDTH+2)'(rob_count) + (fe_rd_req_valid ? 1 : 0);
    // Đăng ký với biên +1: rob_used tăng tối đa 1 mỗi chu kỳ (một lần cấp entry, thay bằng lệnh kế ở thanh ghi đầu ra
    // hàng đợi phát lệnh), nên giá trị đăng ký không bao giờ cho phép vượt giới hạn
    logic rob_hi_ok, rob_lo_ok;
    always_ff @(posedge clk_axi or negedge rst_n_axi) begin
        if (!rst_n_axi) begin
            rob_hi_ok <= 1'b1;
            rob_lo_ok <= 1'b1;
        end else begin
            rob_hi_ok <= rob_used + 1'b1 < (ROB_PTR_WIDTH+2)'(ROB_DEPTH);
            rob_lo_ok <= rob_used + 1'b1 < (ROB_PTR_WIDTH+2)'(ROB_DEPTH - ROB_RSV);
        end
    end
    logic                                arb_grant_valid;
    logic [BG_WIDTH-1:0]                 arb_grant_bg;
    logic [2:0]                          arb_grant_idx;
    logic [BG_WIDTH-1:0]   wcmd_bg;
    logic [BANK_WIDTH-1:0] wcmd_bank;
    logic [BANK_WIDTH-1:0] iq_sel_bank, fe_rd_req_bank;
    // SCARF xáo trộn cả bank trong bộ ánh xạ nên bank vật lý ở arbiter không suy ra được từ địa chỉ: bank logic dùng
    // khi trừ tín dụng được lưu theo tag của lệnh (ROB tag cho đọc, tag slot cho ghi) lúc lệnh vào bộ ánh xạ, và
    // tín dụng được trả đúng bank đó khi lệnh rời arbiter.
    logic [BANK_WIDTH-1:0] rd_cbank [1 << ROB_PTR_WIDTH];
    logic [BANK_WIDTH-1:0] wr_cbank [1 << ROB_PTR_WIDTH];
    logic [BG_WIDTH-1:0]   rd_cbg   [1 << ROB_PTR_WIDTH];
    logic [BG_WIDTH-1:0]   wr_cbg   [1 << ROB_PTR_WIDTH];

    // Tín dụng hàng đợi QoS theo bank: dành riêng + dùng chung (như credit theo VC của NoC). Mỗi bank có một chỗ riêng
    // trong hàng đợi của BG, các chỗ còn lại (BG_QDEPTH - BANK_COUNT) dùng chung. Lệnh bị PROQ chặn ở một bank
    // (đang chờ refresh nạn nhân) chỉ chiếm được chỗ riêng của bank đó và quỹ chung, nên không bao giờ lấy hết chỗ
    // của bank khác cùng BG: đóng kênh thời gian LeakyHammer xuyên bank qua dung lượng hàng đợi (V19).
    // Sự kiện chiếm (đọc chọn khỏi hàng đợi phát lệnh, ghi bắt tay) được đăng ký trước khi cộng vào bộ đếm; trả khi
    // lệnh người dùng rời arbiter (thanh ghi lệnh cs_*). bank_credit là thanh ghi tính cho chu kỳ kế tiếp từ trạng thái
    // đăng ký và lệnh ghi của chu kỳ này; lệnh đọc vừa được chọn chưa có trong đó (giữ bộ chọn của hàng đợi phát lệnh
    // ngoài vòng tín dụng), nên BG của nó bị che một chu kỳ cho cả đọc lẫn ghi (bg_hold), sau đó lệnh đọc đã nằm trong
    // chg_rd_q. Hai lệnh đọc cùng BG vốn cách nhau ít nhất tCCD_L nên che một chu kỳ không mất băng thông.
    localparam int NBK          = BG_COUNT * BANK_COUNT;
    localparam int BKW          = BG_WIDTH + BANK_WIDTH;
    logic                     cs_valid, cs_is_write, cs_is_mitigation;
    logic [AXI_ID_WIDTH-1:0]  cs_id;
    logic [BG_WIDTH-1:0]      cs_bg;
    logic [BANK_WIDTH-1:0]    cs_bank;
    logic [ROW_WIDTH-1:0]     cs_row;
    logic [COL_WIDTH-1:0]     cs_col;
    logic [AXI_LEN_WIDTH-1:0] cs_len;
    wire  [BANK_WIDTH-1:0] rel_bank = cs_is_write ? wr_cbank[cs_id[ROB_PTR_WIDTH-1:0]] : rd_cbank[cs_id[ROB_PTR_WIDTH-1:0]];
    wire  [BG_WIDTH-1:0]   rel_bg   = cs_is_write ? wr_cbg[cs_id[ROB_PTR_WIDTH-1:0]]   : rd_cbg[cs_id[ROB_PTR_WIDTH-1:0]];
    logic [NBK-1:0]      bank_credit, wbank_credit;
    logic [BG_COUNT-1:0] iq_bg_pend;
    logic                rd_iq_empty, mapper_busy;
    logic                chg_rd_q, credit_cnt_err;
    logic [BG_WIDTH-1:0] chg_rd_bg_q;
    wire                 rd_fire = iq_sel_fire;
    wire                 wr_fire = wcmd_valid && wcmd_ready;
    // Khối tín dụng tách thành module riêng để chứng minh induction (formal_credit_v2, spec_v2 Q3)
    bank_credit_ctrl #(
        .BG_COUNT   (BG_COUNT),
        .BANK_COUNT (BANK_COUNT),
        .BG_WIDTH   (BG_WIDTH),
        .BANK_WIDTH (BANK_WIDTH),
        .BG_QDEPTH  (BG_QDEPTH)
    ) u_bank_credit (
        .clk            (clk_axi),
        .rst_n          (rst_n_axi),
        .i_rd_fire      (rd_fire),
        .i_rd_bg        (iq_sel_bg),
        .i_rd_bank      (iq_sel_bank),
        .i_wr_fire      (wr_fire),
        .i_wr_bg        (wcmd_bg),
        .i_wr_bank      (wcmd_bank),
        .i_rel_valid    (cs_valid && !cs_is_mitigation),
        .i_rel_bg       (rel_bg),
        .i_rel_bank     (rel_bank),
        .o_bank_credit  (bank_credit),
        .o_wbank_credit (wbank_credit),
        .o_chg_rd_q     (chg_rd_q),
        .o_chg_rd_bg_q  (chg_rd_bg_q),
        .o_cnt_err      (credit_cnt_err)
    );

    // Chốt cấu hình ánh xạ địa chỉ khi pipeline rỗng (M-08): tránh hai lệnh cùng địa chỉ tính khác BG trong lúc đang bay
    logic [15:0] voted_rh_threshold;
    logic [1:0]  voted_rowpress_curve;
    logic        voted_dual_hash_en;
    logic [1:0]  voted_scramble_mode;
    logic        voted_decoy_en;
    logic [69:0] map_cfg_q;
    logic        map_idle_q, wr_blk_cfg_q;
    wire  [69:0] live_map_cfg = {cfg_is_ddr5, cfg_bank_coloring_en, cfg_mapping_mode, voted_scramble_mode, cfg_scramble_seed};
    wire         cfg_diff     = (live_map_cfg != map_cfg_q);
    // Rỗng = IQ và thanh ghi đầu ra rỗng, bộ ánh xạ rỗng và không bắt tay trong chu kỳ (bộ ánh xạ chọn bank ở đầu ra theo
    // cấu hình hiện tại). Không đòi lệnh ghi rỗng: lệnh ghi chỉ bị chặn sau khi IQ rỗng (wr_blk_cfg_q), vì mục IQ có thể
    // đang chờ RAW trên chính lệnh ghi đó; đoạn AR bị chặn ở đầu vào IQ nên không cần ar_chunk_valid = 0.
    wire         map_idle_c   = !fe_rd_req_valid && rd_iq_empty && !mapper_busy && !(req_to_map_valid && req_to_map_ready);
    wire         eff_is_ddr5          = map_cfg_q[69];
    wire         eff_bank_coloring_en = map_cfg_q[68];
    wire  [1:0]  eff_mapping_mode     = map_cfg_q[67:66];
    wire  [1:0]  eff_scramble_mode    = map_cfg_q[65:64];
    wire  [63:0] eff_scramble_seed    = map_cfg_q[63:0];

    always_ff @(posedge clk_axi or negedge rst_n_axi) begin
        if (!rst_n_axi) begin
            map_cfg_q    <= {1'b1, 1'b0, 2'b00, 2'b00, 64'hA5A5_5A5A_0123_4567};
            cfg_pend_q   <= 1'b0;
            map_idle_q   <= 1'b1;
            wr_blk_cfg_q <= 1'b0;
        end else begin
            map_idle_q <= map_idle_c;
            if (cfg_diff) begin
                // Doi cau hinh chi khi duong ong da idle (map_idle_q=1 va map_idle_c=1) va cfg_pend_q da bat (M-08)
                if (cfg_pend_q && map_idle_q && map_idle_c) begin
                    map_cfg_q    <= live_map_cfg;
                    cfg_pend_q   <= 1'b0;
                    wr_blk_cfg_q <= 1'b0;
                end else begin
                    cfg_pend_q   <= 1'b1;
                    // Trong cfg_pend_q IQ khong nhan muc moi nen khong the het rong: ban tre mot chu ky an toan
                    wr_blk_cfg_q <= cfg_pend_q && rd_iq_empty && !fe_rd_req_valid;
                end
            end else begin
                cfg_pend_q   <= 1'b0;
                wr_blk_cfg_q <= 1'b0;
            end
        end
    end

    // Hàng đợi phát lệnh đọc: chọn lệnh có tín dụng theo QoS/tuổi, giữ thứ tự cùng ID, chặn RAW từng mục.
    // RAW: lệnh ghi đang gom chưa vào pipeline nên chưa có phụ thuộc trong hàng đợi QoS; AW đã bắt tay nhưng còn
    // ở frontend/bộ tách burst thì CAM của ROB không thấy (R29): chặn đọc trùng dòng 64B hoặc khi AW còn tồn đọng.
    wire fe_aw_backlog   = (fe_wr_addr_valid && !fe_wr_addr_ready) || aw_split_busy || fe_aw_valid;
    // Đoạn AR của burst đã nhận trước khi cấu hình đổi không được vào IQ trong lúc chờ (BG tính theo cấu hình cũ)
    logic iq_in_ready;
    assign ar_chunk_ready = iq_in_ready && !cfg_pend_q;
    rd_issue_queue #(
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_QOS_WIDTH  (AXI_QOS_WIDTH),
        .BG_WIDTH       (BG_WIDTH),
        .BANK_WIDTH     (BANK_WIDTH),
        .DEPTH          (8),
        .WR_TRACK       (8)
    ) u_rd_iq (
        .clk                  (clk_axi),
        .rst_n                (rst_n_axi),
        .cfg_bank_coloring_en (eff_bank_coloring_en),
        .cfg_mapping_mode     (eff_mapping_mode),
        .cfg_is_ddr5          (eff_is_ddr5),
        .i_valid              (ar_chunk_valid && !cfg_pend_q),
        .o_ready              (iq_in_ready),
        .i_id                 (ar_chunk_id),
        .i_addr               (ar_chunk_addr),
        .i_len                (ar_chunk_len),
        .i_qos                (ar_chunk_qos),
        .i_last               (ar_chunk_last),
        .o_valid              (fe_rd_req_valid),
        .i_ready              (fe_rd_req_ready),
        .o_id                 (fe_rd_req_id),
        .o_addr               (fe_rd_req_addr),
        .o_len                (fe_rd_req_len),
        .o_qos                (fe_rd_req_qos),
        .o_last               (fe_rd_req_last),
        .o_bg                 (fe_rd_req_bg),
        .o_bank               (fe_rd_req_bank),
        .o_sel_fire           (iq_sel_fire),
        .o_sel_bg             (iq_sel_bg),
        .o_sel_bank           (iq_sel_bank),
        .o_bg_pend            (iq_bg_pend),
        .o_empty              (rd_iq_empty),
        .i_bank_credit        (bank_credit),
        .i_bg_hold_valid      (chg_rd_q),
        .i_bg_hold            (chg_rd_bg_q),
        .i_rob_lo_ok          (rob_lo_ok),
        .i_rob_hi_ok          (rob_hi_ok),
        .i_wstage_busy        (wstage_busy),
        .i_wstage_addr        (wstage_addr),
        .i_fe_aw_valid        (fe_wr_addr_valid),
        .i_fe_aw_addr         (fe_wr_addr),
        .i_wr_active_valid    (wbuf_wr_active_valid),
        .i_wr_active_addr     (wbuf_wr_active_addr),
        .i_aw_backlog         (fe_aw_backlog)
    );

    // BG của lệnh ghi (cùng hàm băm/bank coloring với bộ ánh xạ)
    domain_bank_coloring #(
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .BG_WIDTH       (BG_WIDTH),
        .BANK_WIDTH     (BANK_WIDTH)
    ) u_wcmd_bg (
        .cfg_bank_coloring_en (eff_bank_coloring_en),
        .cfg_mapping_mode     (eff_mapping_mode),
        .cfg_is_ddr5          (eff_is_ddr5),
        .i_req_id             (wcmd_id),
        .i_req_addr           (wcmd_addr),
        .o_bg                 (wcmd_bg),
        .o_bank               (wcmd_bank)
    );

    wire can_issue_read  = fe_rd_req_valid && rob_alloc_ready;
    wire bg_hold_w       = chg_rd_q && chg_rd_bg_q == wcmd_bg;
    // Đọc và ghi cùng BG cùng chu kỳ chỉ khi thanh ghi đầu ra IQ rỗng, khi đó mục đọc đã có trong IQ từ chu kỳ trước nên
    // iq_bg_pend của BG đó đã bật: ghi dùng tín dụng chừa chỗ cho đọc đồng thời (RT-02). Hai mux 32:1 và mux 8:1 song song.
    wire wr_use_wbank    = iq_bg_pend[wcmd_bg];
    wire w_cred_ok       = wr_use_wbank ? wbank_credit[{wcmd_bg, wcmd_bank}] : bank_credit[{wcmd_bg, wcmd_bank}];
    wire can_issue_write = wcmd_valid && w_cred_ok && !bg_hold_w && !wr_blk_cfg_q;

    // Hợp đồng cổng req_to_map_* (RT-11): valid/payload được đổi khi chưa bắt tay (đọc ưu tiên, tín dụng đổi mỗi chu kỳ);
    // hợp lệ vì bộ ánh xạ là pipeline stall-all chỉ chốt khi en = 1. Không chèn skid buffer hay assert ổn định kiểu AXI ở đây.
    always_comb begin
        if (can_issue_read) begin
            req_to_map_valid    = 1'b1;
            req_to_map_is_write = 1'b0;
            // ID đi qua pipeline là ROB tag để định tuyến dữ liệu trả về; bank coloring phải dùng AXI ID gốc,
            // nếu không lệnh đọc và lệnh ghi của cùng tenant rơi vào các bank group khác nhau (S19).
            req_to_map_id       = AXI_ID_WIDTH'(rob_alloc_tag);
            req_to_map_tenant   = fe_rd_req_id;
            req_to_map_addr     = fe_rd_req_addr;
            req_to_map_len      = fe_rd_req_len;
            req_to_map_qos      = fe_rd_req_qos;
        end else if (can_issue_write) begin
            req_to_map_valid    = 1'b1;
            req_to_map_is_write = 1'b1;
            // Lệnh ghi mang tag slot dữ liệu qua pipeline (như lệnh đọc mang ROB tag); tenant vẫn là AXI ID gốc
            req_to_map_id       = AXI_ID_WIDTH'(wcmd_tag);
            req_to_map_tenant   = wcmd_id;
            req_to_map_addr     = wcmd_addr;
            req_to_map_len      = wcmd_len;
            req_to_map_qos      = wcmd_qos;
        end else begin
            req_to_map_valid    = 1'b0;
            req_to_map_is_write = 1'b0;
            req_to_map_id       = '0;
            req_to_map_tenant   = '0;
            req_to_map_addr     = '0;
            req_to_map_len      = '0;
            req_to_map_qos      = '0;
        end
    end

    assign fe_rd_req_ready = req_to_map_ready && rob_alloc_ready;
    assign wcmd_ready      = req_to_map_ready && !can_issue_read && can_issue_write;

    always_ff @(posedge clk_axi) begin
        if (fe_rd_req_valid && fe_rd_req_ready) begin
            rd_cbank[rob_alloc_tag] <= fe_rd_req_bank;
            rd_cbg[rob_alloc_tag]   <= fe_rd_req_bg;
        end
        if (wr_fire) begin
            wr_cbank[wcmd_tag]      <= wcmd_bank;
            wr_cbg[wcmd_tag]        <= wcmd_bg;
        end
    end

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

    // Bộ phát hiện xung thay đổi cấu hình để cập nhật đồng bộ vào 3 đường ray TMR
    logic [15:0] prev_rh_thresh;
    logic [1:0]  prev_rowpress;
    logic        prev_dual_hash;
    logic [1:0]  prev_scramble;
    logic        prev_decoy_en;
    logic        cfg_we_reg;

    always_ff @(posedge clk_axi or negedge rst_n_axi) begin
        if (!rst_n_axi) begin
            prev_rh_thresh <= 16'd0;
            prev_rowpress  <= 2'b00;
            prev_dual_hash <= 1'b0;
            prev_scramble  <= 2'b00;
            prev_decoy_en  <= 1'b0;
            cfg_we_reg     <= 1'b1; // Cập nhật ngay chu kỳ đầu sau reset
        end else begin
            prev_rh_thresh <= cfg_rh_threshold;
            prev_rowpress  <= cfg_rowpress_curve;
            prev_dual_hash <= cfg_dual_hash_en;
            prev_scramble  <= cfg_scramble_mode;
            prev_decoy_en  <= cfg_decoy_en;
            cfg_we_reg     <= (cfg_rh_threshold   != prev_rh_thresh) ||
                              (cfg_rowpress_curve != prev_rowpress)  ||
                              (cfg_dual_hash_en   != prev_dual_hash)  ||
                              (cfg_scramble_mode  != prev_scramble)   ||
                              (cfg_decoy_en       != prev_decoy_en);
        end
    end

    logic       csr_glitch_alert, eng_cnt_fault, drm_fault;
    logic [6:1] eng_fault;
    fault_hardened_csr u_fh_csr (
        .clk                  (clk_axi),
        .rst_n                (rst_n_axi),
        .i_cfg_we             (cfg_we_reg),
        .i_cfg_rh_threshold   (prev_rh_thresh),
        .i_cfg_rowpress_curve (prev_rowpress),
        .i_cfg_dual_hash_en   (prev_dual_hash),
        .i_cfg_scramble_mode  (prev_scramble),
        .i_cfg_decoy_en       (prev_decoy_en),
        .o_cfg_rh_threshold   (voted_rh_threshold),
        .o_cfg_rowpress_curve (voted_rowpress_curve),
        .o_cfg_dual_hash_en   (voted_dual_hash_en),
        .o_cfg_scramble_mode  (voted_scramble_mode),
        .o_cfg_decoy_en       (voted_decoy_en),
        .o_glitch_alert       (csr_glitch_alert),
        .o_security_locked    (o_security_locked)
    );

    // Multi-ASID Confidential Key Table (AMD SEV-style)
    logic [255:0] vm_wr_key, vm_rd_key;
    logic [127:0] vm_wr_tweak, vm_rd_tweak;
    logic         vm_wr_bypass, vm_rd_bypass;

    multi_vm_key_table #(
        .ASID_WIDTH (4)
    ) u_vm_key_table (
        .clk             (clk_axi),
        .rst_n           (rst_n_axi),
        .s_apb_psel      (1'b0),
        .s_apb_penable   (1'b0),
        .s_apb_pwrite    (1'b0),
        .s_apb_paddr     (8'h0),
        .s_apb_pwdata    (32'h0),
        .s_apb_pprot     (3'b001),
        .s_apb_prdata    (),
        .s_apb_pready    (),
        .s_apb_pslverr   (),
        .i_wr_asid       (4'h0),
        .i_wr_c_bit      (1'b1),
        .o_wr_key        (vm_wr_key),
        .o_wr_tweak_key  (vm_wr_tweak),
        .o_wr_bypass     (vm_wr_bypass),
        .i_rd_asid       (4'h0),
        .i_rd_c_bit      (1'b1),
        .o_rd_key        (vm_rd_key),
        .o_rd_tweak_key  (vm_rd_tweak),
        .o_rd_bypass     (vm_rd_bypass)
    );

    addr_mapper_ddr5 #(
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_QOS_WIDTH  (AXI_QOS_WIDTH),
        .ROW_WIDTH      (ROW_WIDTH),
        .COL_WIDTH      (COL_WIDTH),
        .BG_WIDTH       (BG_WIDTH),
        .BANK_WIDTH     (BANK_WIDTH)
    ) u_addr_mapper (
        .clk                  (clk_axi),
        .rst_n                (rst_n_axi),
        .cfg_is_ddr5          (eff_is_ddr5),
        .cfg_bank_coloring_en (eff_bank_coloring_en),
        .cfg_mapping_mode     (eff_mapping_mode),
        .cfg_scramble_en      (eff_scramble_mode != 2'b00),
        .cfg_scramble_mode    (eff_scramble_mode),
        .cfg_scramble_seed    (eff_scramble_seed),

        .i_req_valid    (req_to_map_valid),
        .o_req_ready    (req_to_map_ready),
        .i_req_id       (req_to_map_id),
        .i_req_tenant   (req_to_map_tenant),
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
        .o_cmd_qos      (mapped_cmd_qos),
        .o_busy         (mapper_busy)
    );

    //=========================================================================
    // 4. Reorder Buffer (ROB) & RAW Hazard Detector
    //=========================================================================
    logic                      dram_wb_valid;
    logic [ROB_PTR_WIDTH-1:0]  dram_wb_tag;
    logic [AXI_DATA_WIDTH-1:0] dram_wb_data;
    logic [1:0]                dram_wb_resp;
    logic                      dram_wb_last;
    logic [1:0]                eng_wb_resp;
    logic                      eng_wb_err, eng_rd_take, eng_rd_beat_ok, eng_rd_flush, eng_rd_resync;
    wire                       rd_err = rd_ue || eng_wb_err;
    // Beat đọc hỏng không sửa được hoặc beat tổng hợp khi FLUSH trả SLVERR; dữ liệu bị xoá về 0 để chống rò rỉ
    assign dram_wb_resp = rd_err ? 2'b10 : eng_wb_resp;
    assign rmw_tag      = dram_wb_tag;

    // Tầng thanh ghi ghi ngược dữ liệu đọc: cắt đường giải mã ECC -> giải xáo trộn -> ROB (đếm beat theo tag, chọn entry
    // retire) và -> trộn RMW vào kho ghi. Engine đã đánh dấu RMW xong ở chu kỳ beat cuối; lệnh WR tương ứng đọc dữ liệu
    // slot sau ít nhất 1 + 6 chu kỳ (bộ sinh beat + keystream) nên bản trộn trễ một chu kỳ vẫn kịp.
    always_ff @(posedge clk_axi or negedge rst_n_axi) begin
        if (!rst_n_axi) begin
            wbq_valid <= 1'b0;
            wbq_rmw   <= 1'b0;
        end else begin
            wbq_valid <= dram_wb_valid;
            wbq_rmw   <= rmw_valid;
        end
    end
    always_ff @(posedge clk_axi) begin
        wbq_tag  <= dram_wb_tag;
        wbq_data <= rd_err ? '0 : dram_wb_data;
        wbq_resp <= dram_wb_resp;
        wbq_last <= dram_wb_last;
        wbq_beat <= rmw_beat[2:0];
        wbq_ue   <= rd_err;
    end

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
        .i_alloc_last       (fe_rd_req_last),
        .o_alloc_ready      (rob_alloc_ready),
        .o_alloc_tag        (rob_alloc_tag),

        .i_wr_active_valid  ('0),
        .i_wr_active_addr   (wbuf_wr_active_addr),
        .o_raw_hazard       (rob_raw_hazard),
        .o_raw_match_mask   (),

        .i_wb_valid         (wbq_valid),
        .i_wb_tag           (wbq_tag),
        .i_wb_data          (wbq_data),
        .i_wb_resp          (wbq_resp),
        .i_wb_last          (wbq_last),

        .o_rvalid           (rob_rvalid),
        .o_rid              (rob_rid),
        .o_rdata            (rob_rdata),
        .o_rresp            (rob_rresp),
        .o_rlast            (rob_rlast),
        .i_rready           (s_axi_rready),

        .o_rob_empty        (),
        .o_rob_full         (),
        .o_rob_count        (rob_count)
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
    logic                      ddr_ref_tick;
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

        .cfg_hash_mode       (voted_dual_hash_en),
        .cfg_pxor_mode       (1'b1),
        .cfg_pxor_seed       (cfg_scramble_seed),
        .cfg_sdc_thresh      (ate_dynamic_thresh),
        .cfg_window_size     (cfg_window_size),
        .i_ref_tick          (ddr_ref_tick),

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
        .i_rowpress_weight   (8'd0),

        .o_cmd_valid         (sdc_cmd_valid),
        .i_cmd_ready         (!drm_stall),
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
        .o_coordinated_throttle_active (o_coordinated_throttle_active),
        .o_bank_throttled_flags         (),
        .o_coordinated_throttle_cnt     (),
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
        .cfg_base_thresh      (voted_rh_threshold),
        // Trần = ngưỡng cấu hình: ATE chỉ được siết, không được nới khi throttle tăng (nới lỏng giúp kẻ tấn công tự vô hiệu bộ dò).
        .cfg_max_thresh       (voted_rh_threshold),
        .i_telemetry_accesses (telemetry_accesses),
        .i_telemetry_throttles(telemetry_throttles),
        .i_rowpress_clamp_alert(ddr_rowpress_alert),
        .o_dynamic_thresh     (ate_dynamic_thresh),
        .o_sample_epochs      ()
    );

    //=========================================================================
    // 5b. Directed Refresh Manager (DRM)
    //=========================================================================
    logic                  abo_active;
    logic [BG_WIDTH-1:0]   abo_bg;
    logic [BANK_WIDTH-1:0] abo_bank;
    logic [ROW_WIDTH-1:0]  abo_row;
    logic                  ecc_chipkill_fallback_req;
    logic [ROW_WIDTH-1:0]  raw_dfi_row;
    logic [ROB_PTR_WIDTH-1:0] dfi_cas_tag;

    // PROQ CAM Interconnect to Arbiter (MORDOR MICRO 2026)
    // Ứng viên đã đăng ký của QoS queue (dùng chung cho kiểm tra PROQ ở DRM và arbiter)
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
    logic [BG_COUNT-1:0]                 cand_fresh;
    logic [BG_COUNT*BANK_COUNT-1:0] ddr_bank_free, eng_bank_free;
    logic [BG_COUNT-1:0]                 proq_blk;
    logic [BG_COUNT-1:0]                 proq_hit;

    directed_refresh_manager #(
        .BG_WIDTH    (BG_WIDTH),
        .BANK_WIDTH  (BANK_WIDTH),
        .ROW_WIDTH   (ROW_WIDTH),
        .QUEUE_DEPTH (32) // PROQ 32-entry CAM from MORDOR MICRO 2026
    ) u_drm (
        .clk                 (clk_axi),
        .rst_n               (rst_n_axi),

        .cfg_drm_en          (1'b1),
        // Refresh nạn nhân khoảng cách 2 để chặn Half-Double (USENIX'22).
        .cfg_victim2_en      (1'b1),
        .cfg_victim3_en      (cfg_victim3_en),

        .i_abo_req           (abo_active),
        .i_abo_bg            (abo_bg),
        .i_abo_bank          (abo_bank),
        .i_abo_row           (abo_row),

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

        .o_proq_row_hit      (),
        .i_cand_valid        (cand_valid),
        .i_cand_fresh        (cand_fresh),
        .i_cand_bank         (cand_bank),
        .i_cand_row          (cand_row),
        .o_proq_blk          (proq_blk),
        .o_proq_hit          (proq_hit),

        .o_drm_ref_count     (drm_ref_count),
        .o_queue_full        (),
        .o_drm_stall         (drm_stall),
        .o_drm_fault         (drm_fault)
    );

    //=========================================================================
    // 6. QoS Scheduler Queue (8 Bank Groups x 8 Entries)
    //=========================================================================


    // Luồng lệnh vào hàng đợi QoS được điều khiển bằng tín dụng bank (tổng mỗi BG <= BG_QDEPTH = độ sâu hàng đợi, trừ
    // trước khi lệnh vào pipeline, trả khi được cấp) nên hàng đợi luôn còn chỗ: READY của nó không nằm trên chuỗi stall-all
    // của SDC/bộ ánh xạ.
    wire q_in_valid = sdc_cmd_valid && !drm_stall;
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

        .i_cmd_valid         (q_in_valid),
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
        .o_cand_entry_idx    (cand_entry_idx),
        .o_cand_fresh        (cand_fresh),
        .i_bank_free         (ddr_bank_free)
    );

    //=========================================================================
    // 7. Slack-Aware Arbiter
    //=========================================================================
    logic [BG_COUNT-1:0] ddr_bg_ready;
    logic                ddr_engine_ready;
    logic                ddr_engine_mit_only;
    logic [ROB_PTR_WIDTH-1:0] eng_slice_tag;
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
    logic [BG_COUNT-1:0] arb_cmd_bg_oh;

    // Thanh ghi lệnh giữa arbiter và engine: cắt đường ứng viên queue -> chọn arbiter -> nạp slot engine (một chu kỳ).
    // Lệnh nằm trong thanh ghi chưa chiếm slot của engine, nên bank của nó bị che khỏi bank_free cho queue và arbiter:
    // không bao giờ cấp lệnh thứ hai vào cùng slot, engine luôn nhận được lệnh ở chu kỳ sau.
    // Mặt nạ bank của lệnh trong thanh ghi được giải mã sẵn thành hai one-hot nhỏ (BG, bank): bộ giải mã 5->32 không
    // nằm ở cuối đường arbiter, cũng không nằm trước queue/arbiter (chỉ còn một cổng AND ở phía dùng)
    logic [BG_COUNT-1:0]   cs_bg_oh;
    logic [BANK_COUNT-1:0] cs_bank_oh;
    logic [BG_COUNT*BANK_COUNT-1:0] cs_oh;
    always_ff @(posedge clk_axi or negedge rst_n_axi) begin
        if (!rst_n_axi) begin
            cs_valid   <= 1'b0;
            cs_bg_oh   <= '0;
            cs_bank_oh <= '0;
        end else begin
            cs_valid   <= arb_cmd_valid;
            cs_bg_oh   <= arb_cmd_valid ? arb_cmd_bg_oh : '0;
            cs_bank_oh <= BANK_COUNT'(1) << arb_cmd_bank;
        end
    end
    always_comb
        for (int g = 0; g < BG_COUNT; g++)
            for (int k = 0; k < BANK_COUNT; k++) cs_oh[g*BANK_COUNT + k] = cs_bg_oh[g] && cs_bank_oh[k];
    always_ff @(posedge clk_axi) begin
        cs_is_write      <= arb_cmd_is_write;
        cs_is_mitigation <= arb_cmd_is_mitigation;
        cs_id            <= arb_cmd_id;
        cs_bg            <= arb_cmd_bg;
        cs_bank          <= arb_cmd_bank;
        cs_row           <= arb_cmd_row;
        cs_col           <= arb_cmd_col;
        cs_len           <= arb_cmd_len;
    end
    assign ddr_bank_free = eng_bank_free & ~cs_oh;


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
        .i_engine_ready      (1'b1),
        .i_bank_free         (ddr_bank_free),
        .i_engine_mit_only   (ddr_engine_mit_only),
        .i_slack_cycle       (ddr_slack_cycle),

        .i_mitigation_req    (drm_mitigation_req),
        .i_mitigation_bg     (drm_mitigation_bg),
        .i_mitigation_bank   (drm_mitigation_bank),
        .i_mitigation_row    (drm_mitigation_row),
        .o_mitigation_grant  (drm_mitigation_grant),

        .i_proq_blk          (proq_blk),
        .i_proq_hit          (proq_hit),

        .o_issue_grant_valid (arb_grant_valid),
        .o_issue_grant_bg    (arb_grant_bg),
        .o_issue_grant_idx   (arb_grant_idx),

        .o_cmd_valid         (arb_cmd_valid),
        .o_cmd_is_write      (arb_cmd_is_write),
        .o_cmd_id            (arb_cmd_id),
        .o_cmd_bg            (arb_cmd_bg),
        .o_cmd_bg_oh         (arb_cmd_bg_oh),
        .o_cmd_bank          (arb_cmd_bank),
        .o_cmd_row           (arb_cmd_row),
        .o_cmd_col           (arb_cmd_col),
        .o_cmd_len           (arb_cmd_len),
        .o_cmd_is_mitigation (arb_cmd_is_mitigation),
        .o_drain_mode        ()
    );

    // Thanh ghi đầu vào DFI đọc (khai báo trước engine vì engine dùng rdq_valid)
    logic                        rdq_valid;
    logic [AXI_DATA_WIDTH-1:0]   rdq_data;
    logic [AXI_DATA_WIDTH/8-1:0] rdq_ecc;

    // Bộ sinh địa chỉ truy cập mồi bằng PRF có khoá (SCARF 10 vòng, tweak miền 16'hDEC0, M-09)
    logic [BG_WIDTH+BANK_WIDTH+ROW_WIDTH-1:0] decoy_ctr;
    logic [ROW_WIDTH-1:0]                     decoy_prf_row;
    logic [BANK_WIDTH-1:0]                    decoy_prf_bank;
    logic [BANK_WIDTH+ROW_WIDTH-1:0]          decoy_p0;
    logic                                     decoy_ph;
    logic [4:0]                               decoy_vld_pipe;
    logic                                     decoy_avail;
    logic [BG_WIDTH+BANK_WIDTH+ROW_WIDTH-1:0] decoy_addr;
    logic                                     decoy_take;
    wire                                      decoy_pipe_en = !decoy_avail || decoy_take;

    always_ff @(posedge clk_axi or negedge rst_n_axi) begin
        if (!rst_n_axi) begin
            decoy_ctr      <= 22'h1A_CE51;
            decoy_vld_pipe <= '0;
            decoy_avail    <= 1'b0;
            decoy_addr     <= '0;
            decoy_p0       <= '0;
            decoy_ph       <= 1'b0;
        end else if (cfg_scramble_reseed) begin
            decoy_ctr      <= cfg_scramble_seed[21:0] ^ 22'h1A_CE51;
            decoy_vld_pipe <= '0;
            decoy_avail    <= 1'b0;
            decoy_ph       <= 1'b0;
        end else if (decoy_pipe_en) begin
            decoy_ctr         <= decoy_ctr + 1'b1;
            decoy_vld_pipe    <= {decoy_vld_pipe[3:0], 1'b1};
            // Mỗi địa chỉ dùng hai đầu ra PRF liên tiếp: {bank, row} từ lần đầu, BG từ lần thứ hai (BG không suy được
            // từ bộ đếm hay từ decoy trước, spec_v2 M-09)
            if (decoy_vld_pipe[4] && !decoy_ph) begin
                decoy_p0    <= {decoy_prf_bank, decoy_prf_row};
                decoy_ph    <= 1'b1;
                decoy_avail <= 1'b0;
            end else if (decoy_vld_pipe[4]) begin
                decoy_addr  <= {decoy_prf_row[BG_WIDTH-1:0], decoy_p0};
                decoy_ph    <= 1'b0;
                decoy_avail <= 1'b1;
            end else begin
                decoy_avail <= 1'b0;
            end
        end
    end

    scarf_dram_randomizer #(
        .ROW_WIDTH   (ROW_WIDTH),
        .BANK_WIDTH  (BANK_WIDTH),
        .TWEAK_WIDTH (16),
        .ROUNDS      (10),
        .RPS         (2)
    ) u_decoy_prf (
        .clk               (clk_axi),
        .rst_n             (rst_n_axi),
        .cfg_scramble_en   (1'b1),
        .cfg_scramble_seed (cfg_scramble_seed),
        .i_en              (decoy_pipe_en),
        .i_tweak           (16'hDEC0),
        .i_row             (decoy_ctr[ROW_WIDTH-1:0]),
        .i_bank            (decoy_ctr[ROW_WIDTH +: BANK_WIDTH]),
        .o_scrambled_row   (decoy_prf_row),
        .o_scrambled_bank  (decoy_prf_bank)
    );

    ddr5_cmd_engine #(
        .BG_COUNT        (BG_COUNT),
        .BANK_COUNT      (BANK_COUNT),
        .ROW_WIDTH       (ROW_WIDTH),
        .COL_WIDTH       (COL_WIDTH),
        .AXI_ID_WIDTH    (AXI_ID_WIDTH),
        .AXI_DATA_WIDTH  (AXI_DATA_WIDTH),
        .AXI_LEN_WIDTH   (AXI_LEN_WIDTH),
        .ROB_PTR_WIDTH   (ROB_PTR_WIDTH),
        .T_RCD           (T_RCD_C),
        .T_RP            (T_RP_C),
        .T_RAS           (T_RAS_C),
        .T_CCD_L         (T_CCD_L_C),
        .T_CCD_S         (T_CCD_S_C),
        .T_CCD_L_WR      (T_CCD_L_WR_C),
        .T_CL            (DFI_RDLAT),
        .T_RDV           (DFI_RDLAT + 1),
        .T_CWL           (DFI_WRLAT),
        .T_RRD_S         (T_RRD_S_C),
        .T_RRD_L         (T_RRD_L_C),
        .T_FAW           (T_FAW_C),
        .T_WR            (T_WR_C),
        .T_WTR_S         (T_WTR_S_C),
        .T_WTR_L         (T_WTR_L_C),
        .T_RTP           (T_RTP_C),
        .T_RFC           (T_RFC_C),
        .T_RFM           (T_RFM_C),
        .T_REFI          (T_REFI_C)
    ) u_cmd_engine (
        .clk                 (clk_axi),
        .rst_n               (rst_n_axi),

        .i_cmd_valid         (cs_valid),
        .i_cmd_is_write      (cs_is_write),
        .i_cmd_id            (cs_id),
        .i_cmd_bg            (cs_bg),
        .i_cmd_bank          (cs_bank),
        .i_cmd_row           (cs_row),
        .i_cmd_col           (cs_col),
        .i_cmd_len           (cs_len),
        .i_cmd_tag           (cs_id[ROB_PTR_WIDTH-1:0]),
        .i_cmd_is_mitigation (cs_is_mitigation),
        // ECC phủ cả word 64 bit nên ghi thiếu byte không thể dùng data mask: engine làm RMW
        .i_cmd_rmw           (1'b0),
        .o_slice_tag         (eng_slice_tag),
        .i_slice_rmw         (wds_partial[eng_slice_tag]),

        .cfg_rowpress_thresh (16'd5000),
        .cfg_rowpress_curve  (cfg_rowpress_curve),
        .cfg_tras_max_thresh (16'(TRAS_MAX_DEF)),
        .i_dram_abo_alert    (i_dram_abo_alert),
        .o_abo_active        (abo_active),
        .o_abo_alert_cnt     (o_abo_alert_cnt),
        .o_abo_bg            (abo_bg),
        .o_abo_bank          (abo_bank),
        .o_abo_row           (abo_row),

        .o_rowpress_alert    (ddr_rowpress_alert),
        .o_rowpress_bg       (ddr_rowpress_bg),
        .o_rowpress_bank     (ddr_rowpress_bank),
        .o_rowpress_row      (ddr_rowpress_row),
        .o_rowpress_alert_cnt(ddr_rowpress_alert_cnt),
        .o_tras_clamped_alert(o_tras_clamped_alert),
        .o_tras_clamped_cnt  (),
        .o_rfm_auto_cnt      (o_rfm_auto_cnt),
        .o_cnt_fault         (eng_cnt_fault),
        .o_fault             (eng_fault),
        .i_force_rfm         (drm_fault),
        .o_rfm_active        (),
        .o_ref_tick          (ddr_ref_tick),
        .cfg_decoy_en        (voted_decoy_en),
        .i_decoy_avail       (decoy_avail),
        .i_decoy_addr        (decoy_addr),
        .o_decoy_take        (decoy_take),
        .o_decoy_active      (o_decoy_active),
        .o_decoy_cnt         (o_decoy_cnt),

        .o_bg_ready          (ddr_bg_ready),
        .o_engine_ready      (ddr_engine_ready),
        .o_bank_free         (eng_bank_free),
        .o_engine_mit_only   (ddr_engine_mit_only),
        .o_slack_cycle       (ddr_slack_cycle),

        .o_dfi_cmd           (dfi_cmd),
        .o_dfi_bg            (dfi_bg),
        .o_dfi_bank          (dfi_bank),
        .o_dfi_row           (raw_dfi_row),
        .o_dfi_col           (dfi_col),
        .o_dfi_len           (dfi_len),
        .o_dfi_tag           (dfi_cas_tag),
        .i_dfi_rddata_valid  (rdq_valid),
        .i_dfi_rddata        (rd_descrambled),

        .o_wb_valid          (dram_wb_valid),
        .o_wb_tag            (dram_wb_tag),
        .o_wb_data           (dram_wb_data),
        .o_wb_resp           (eng_wb_resp),
        .o_wb_last           (dram_wb_last),
        .o_rmw_valid         (rmw_valid),
        .o_rmw_beat          (rmw_beat),
        .o_wb_err            (eng_wb_err),
        .o_rd_take           (eng_rd_take),
        .o_rd_beat_ok        (eng_rd_beat_ok),
        .o_rd_flush          (eng_rd_flush),
        .o_rd_resync         (eng_rd_resync),

        .o_precomp_valid     (),
        .o_precomp_is_write  (),
        .o_precomp_tag       (),
        .o_precomp_addr      (),
        .o_precomp_key_id    ()
    );

    // Bộ tổng hợp lỗi phần cứng chốt giữ (Sticky Fault Aggregator, M-05.6)
    wire        credit_fault = credit_cnt_err || (q_in_valid && !sdc_cmd_ready);
    wire  [8:0] fault_vec    = {credit_fault, drm_fault, eng_fault[6:1], csr_glitch_alert};
    logic [8:0] fault_sticky;
    always_ff @(posedge clk_axi or negedge rst_n_axi) begin
        if (!rst_n_axi)         fault_sticky <= '0;
        else if (cfg_fault_clr) fault_sticky <= fault_vec;
        else                    fault_sticky <= fault_sticky | fault_vec;
    end
    assign o_fault_cause  = fault_sticky;
    // FF nạp cùng cạnh với fault_sticky (spec_v2 §5.6, Q6): bị glitch xoá thì nạp lại ở chu kỳ sau
    always_ff @(posedge clk_axi or negedge rst_n_axi) begin
        if (!rst_n_axi) o_glitch_alert <= 1'b0;
        else            o_glitch_alert <= |(cfg_fault_clr ? fault_vec : (fault_sticky | fault_vec));
    end

    //=========================================================================
    // 9. ECC Background Patrol Scrubber
    //=========================================================================
    logic ecc_single_err;

    // Thanh ghi đầu vào DFI đọc: cắt đường từ chân vào qua giải mã ECC, giải xáo trộn tới ROB (Fmax 400 MHz)
    logic [AXI_DATA_WIDTH-1:0]   rd_corrected;
    // Địa chỉ word của beat đọc hiện tại (FIFO địa chỉ RD ở mục 10)
    logic [BG_WIDTH+BANK_WIDTH+ROW_WIDTH+COL_WIDTH-1:0] rd_word;
    always_ff @(posedge clk_axi or negedge rst_n_axi) begin
        if (!rst_n_axi) rdq_valid <= 1'b0;
        else            rdq_valid <= dfi_rddata_valid;
    end
    always_ff @(posedge clk_axi) begin
        rdq_data <= dfi_rddata;
        rdq_ecc  <= dfi_rddata_ecc;
    end
    assign rd_ue = rdq_valid && (ecc_double_err || ecc_miscorrect_alert);

    ecc_scrubber #(
        .DATA_WIDTH       (AXI_DATA_WIDTH),
        .ECC_WIDTH        (AXI_DATA_WIDTH/8),
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

        // Giải mã trên dữ liệu đã lưu (đã xáo trộn) ngay sau thanh ghi đầu vào DFI; chỉ tính beat đọc đồng bộ hợp lệ
        .i_data_valid        (rdq_valid && eng_rd_beat_ok),
        .i_raw_data          (rdq_data),
        .i_raw_ecc           (rdq_ecc),
        .i_data_bg           (rd_word[BG_WIDTH+BANK_WIDTH+ROW_WIDTH+COL_WIDTH-1 -: BG_WIDTH]),
        .i_data_bank         (rd_word[BANK_WIDTH+ROW_WIDTH+COL_WIDTH-1 -: BANK_WIDTH]),
        .i_data_row          (rd_word[ROW_WIDTH+COL_WIDTH-1 -: ROW_WIDTH]),

        .i_fault_inject_en   (1'b0),
        .i_fault_inject_type (2'b00),
        .i_fault_inject_bit  (6'd0),

        .o_corrected_valid   (),
        .o_corrected_data    (rd_corrected),
        .o_single_err        (ecc_single_err),
        .o_double_err        (ecc_double_err),
        .o_single_err_cnt    (o_ecc_single_err_cnt),
        .o_double_err_cnt    (o_ecc_double_err_cnt),
        .o_ecc_miscorrect_alert (ecc_miscorrect_alert),
        .o_ecc_miscorrect_cnt   (o_ecc_miscorrect_cnt),
        .o_chipkill_fallback_req(ecc_chipkill_fallback_req),

        .i_zem_lookup_valid     (1'b0),
        .i_zem_lookup_bg        ({BG_WIDTH{1'b0}}),
        .i_zem_lookup_bank      ({BANK_WIDTH{1'b0}}),
        .i_zem_lookup_row       ({ROW_WIDTH{1'b0}}),
        .o_zem_hit              (),
        .o_zem_mask             (),
        .o_zem_hit_cnt          ()
    );

    //=========================================================================
    // 10. DRAM Bus Scrambler (Galois LFSR Anti-Snooping)
    //=========================================================================

    // Pha dữ liệu ghi (pipeline, mọi đầu ra DFI đều là thanh ghi):
    //   chu kỳ WR trên DFI -> bộ sinh beat phát khoá {bg,bank,row,col+beat} mỗi chu kỳ -> keystream 6 tầng ->
    //   đọc slot ghi + XOR keystream (thanh ghi) -> mã SEC-DED trên dữ liệu đã xáo trộn (thanh ghi) -> DFI.
    // Beat đầu ra DFI sau WR đúng DFI_WRLAT = 1 + KS_LAT + 2 chu kỳ (tphy_wrlat); engine dùng giá trị này làm T_CWL
    // để tính cửa sổ bus DQ, tWR và tWTR. Trước đây keystream ARX (6 phép cộng 64 bit) và ECC nằm tổ hợp ngay trên
    // đường tới chân dfi_wrdata.
    logic                     wg_active;
    logic [ROB_PTR_WIDTH-1:0] wg_tag;
    logic [2:0]               wg_beat, wg_last;
    logic [BG_WIDTH-1:0]      wg_bg;
    logic [BANK_WIDTH-1:0]    wg_bank;
    logic [ROW_WIDTH-1:0]     wg_row;
    logic [COL_WIDTH-1:0]     wg_col;
    always_ff @(posedge clk_axi or negedge rst_n_axi) begin
        if (!rst_n_axi) begin
            wg_active <= 1'b0;
            wg_beat   <= '0;
        end else if (dfi_cmd == 3'b100) begin
            wg_active <= 1'b1;
            wg_beat   <= '0;
        end else if (wg_active) begin
            if (wg_beat == wg_last) wg_active <= 1'b0;
            else                    wg_beat   <= wg_beat + 1'b1;
        end
    end
    always_ff @(posedge clk_axi)
        if (dfi_cmd == 3'b100) begin
            wg_tag  <= dfi_cas_tag;
            wg_last <= dfi_len[2:0];
            wg_bg   <= dfi_bg;
            wg_bank <= dfi_bank;
            wg_row  <= dfi_row;
            wg_col  <= dfi_col;
        end

    // Khoá keystream = địa chỉ word vật lý của beat: {bg, bank, row, col + beat}
    wire [63:0] wr_key = 64'({wg_bg, wg_bank, wg_row, wg_col + COL_WIDTH'(wg_beat)});
    logic                     kw_valid;
    logic [63:0]              kw_ks;
    logic [ROB_PTR_WIDTH+5:0] kw_side;
    scrambler_ks_pipe #(.SIDE_W(ROB_PTR_WIDTH + 6)) u_wr_ks (
        .clk      (clk_axi),
        .rst_n    (rst_n_axi),
        .cfg_seed (cfg_scramble_seed),
        .i_valid  (wg_active),
        .i_key    (wr_key),
        .i_side   ({wg_tag, wg_beat, wg_last}),
        .o_valid  (kw_valid),
        .o_ks     (kw_ks),
        .o_side   (kw_side)
    );
    assign wds_rd_tag  = kw_side[ROB_PTR_WIDTH+5 -: ROB_PTR_WIDTH];
    assign wds_rd_beat = kw_side[5:3];
    // Slot được giải phóng khi beat cuối của nó đã được đọc ra
    assign wds_free    = kw_valid && (kw_side[5:3] == kw_side[2:0]);

    logic                        wx_valid;
    logic [AXI_DATA_WIDTH-1:0]   wx_data;
    logic [AXI_DATA_WIDTH/8-1:0] wx_strb;
    logic                        wx_psn;
    always_ff @(posedge clk_axi or negedge rst_n_axi) begin
        if (!rst_n_axi) wx_valid <= 1'b0;
        else            wx_valid <= kw_valid;
    end
    always_ff @(posedge clk_axi) begin
        wx_data <= wds_rd_data ^ (cfg_scramble_en ? AXI_DATA_WIDTH'(kw_ks) : '0);
        wx_strb <= wds_rd_strb;
        wx_psn  <= wds_rd_poison;
    end

    // ECC tính trên dữ liệu đã xáo trộn (dạng lưu trong DRAM). Beat mang dữ liệu cũ hỏng (RMW gặp lỗi không sửa
    // được) được ghi kèm ECC lệch 2 bit: lần đọc sau vẫn báo không sửa được thay vì lỗi bị "tẩy" thành dữ liệu sạch.
    always_ff @(posedge clk_axi or negedge rst_n_axi) begin
        if (!rst_n_axi) dfi_wrdata_en <= 1'b0;
        else            dfi_wrdata_en <= wx_valid;
    end
    always_ff @(posedge clk_axi) begin
        dfi_wrdata <= wx_data;
        // RMW bảo đảm mọi beat ghi ra DRAM đều đủ byte (mask toàn 1) nên ECC luôn khớp cả word
        dfi_wrdata_mask <= wx_strb;
        for (int l = 0; l < AXI_DATA_WIDTH / 64; l++)
            dfi_wrdata_ecc[l*8 +: 8] <= secded72_enc(wx_data[l*64 +: 64]) ^ (wx_psn ? 8'h03 : 8'h00);
    end

    // Đường đọc cần địa chỉ word của từng beat (ZEM ghi địa chỉ lỗi): ghi lại theo thứ tự lệnh RD như engine
    localparam int RA_DEPTH = 16;
    logic [BG_WIDTH+BANK_WIDTH+ROW_WIDTH+COL_WIDTH-1:0] ra_addr [RA_DEPTH];
    logic [4:0] ra_wr, ra_rd;
    logic [2:0] ra_beat;
    always_ff @(posedge clk_axi or negedge rst_n_axi) begin
        if (!rst_n_axi) begin
            ra_wr   <= '0;
            ra_rd   <= '0;
            ra_beat <= '0;
        end else if (eng_rd_resync) begin
            ra_rd   <= ra_wr;
            ra_beat <= '0;
        end else begin
            if (dfi_cmd == 3'b011) ra_wr <= ra_wr + 1'b1;
            if (eng_rd_take) begin
                if (dram_wb_last) begin
                    ra_beat <= '0;
                    ra_rd   <= ra_rd + 1'b1;
                end else begin
                    ra_beat <= ra_beat + 1'b1;
                end
            end
        end
    end
    // Mảng dữ liệu FIFO không cần reset: tách khỏi khối reset bất đồng bộ để suy ra LUTRAM/FF không có set/reset
    always_ff @(posedge clk_axi)
        if (dfi_cmd == 3'b011) ra_addr[ra_wr[3:0]] <= {dfi_bg, dfi_bank, dfi_row, dfi_col};
    assign rd_word = ra_addr[ra_rd[3:0]];

    // Keystream đọc tính trước từ lệnh RD (dữ liệu về sau CL + 1 chu kỳ thanh ghi vào, keystream sau 1 + KS_LAT):
    // FIFO giữ keystream theo đúng thứ tự beat, mỗi beat dữ liệu đọc lấy một phần tử.
    logic                     rg_active;
    logic [2:0]               rg_beat, rg_last;
    logic [BG_WIDTH-1:0]      rg_bg;
    logic [BANK_WIDTH-1:0]    rg_bank;
    logic [ROW_WIDTH-1:0]     rg_row;
    logic [COL_WIDTH-1:0]     rg_col;
    always_ff @(posedge clk_axi or negedge rst_n_axi) begin
        if (!rst_n_axi) begin
            rg_active <= 1'b0;
            rg_beat   <= '0;
        end else if (dfi_cmd == 3'b011) begin
            rg_active <= 1'b1;
            rg_beat   <= '0;
        end else if (rg_active) begin
            if (rg_beat == rg_last) rg_active <= 1'b0;
            else                    rg_beat   <= rg_beat + 1'b1;
        end
    end
    always_ff @(posedge clk_axi)
        if (dfi_cmd == 3'b011) begin
            rg_last <= dfi_len[2:0];
            rg_bg   <= dfi_bg;
            rg_bank <= dfi_bank;
            rg_row  <= dfi_row;
            rg_col  <= dfi_col;
        end
    wire [63:0] rd_key = 64'({rg_bg, rg_bank, rg_row, rg_col + COL_WIDTH'(rg_beat)});
    logic        kr_valid;
    logic [63:0] kr_ks;
    scrambler_ks_pipe #(.SIDE_W(1)) u_rd_ks (
        .clk      (clk_axi),
        .rst_n    (rst_n_axi),
        .cfg_seed (cfg_scramble_seed),
        .i_valid  (rg_active),
        .i_key    (rd_key),
        .i_side   (1'b0),
        .o_valid  (kr_valid),
        .o_ks     (kr_ks),
        .o_side   ()
    );
    localparam int KF_DEPTH = 16;
    logic [63:0] kf_mem [KF_DEPTH];
    logic [4:0]  kf_wr, kf_rd;
    always_ff @(posedge clk_axi or negedge rst_n_axi) begin
        if (!rst_n_axi) begin
            kf_wr <= '0;
            kf_rd <= '0;
        end else if (eng_rd_resync) begin
            kf_rd <= kf_wr;
        end else begin
            if (kr_valid)       kf_wr <= kf_wr + 1'b1;
            if (eng_rd_beat_ok) kf_rd <= kf_rd + 1'b1;
        end
    end
    always_ff @(posedge clk_axi)
        if (kr_valid) kf_mem[kf_wr[3:0]] <= kr_ks;
    assign rd_descrambled = rd_corrected ^ (cfg_scramble_en ? AXI_DATA_WIDTH'(kf_mem[kf_rd[3:0]]) : '0);

    assign dfi_row         = raw_dfi_row;

`ifndef SYNTHESIS
    initial begin
        if (!(TCK_PS > 0 && TRAS_MAX_DEF <= 9 * T_REFI_C))
            $fatal(1, "SA-E01: TCK_PS must be > 0 and TRAS_MAX_DEF must be <= 9 * T_REFI_C");
        // M-12: tag ROB đi qua trường ID; mốc dữ liệu ghi của engine không sớm hơn CWL + BL của DRAM
        if (ROB_PTR_WIDTH > AXI_ID_WIDTH)
            $fatal(1, "SA-E01: ROB_PTR_WIDTH=%0d > AXI_ID_WIDTH=%0d", ROB_PTR_WIDTH, AXI_ID_WIDTH);
        if ((DFI_WRLAT + 1) * TCK_PS < TCWL_BL_PS)
            $fatal(1, "SA-E03: (DFI_WRLAT + 1) * TCK_PS = %0d ps < TCWL_BL_PS", (DFI_WRLAT + 1) * TCK_PS);
    end

    // Tự kiểm mô phỏng các bất biến cấu trúc của khối đỉnh (TB bơm lỗi đặt sim_chk_en = 0 trước khi bơm)
    bit sim_chk_en = 1'b1;
    always_ff @(posedge clk_axi)
        if (rst_n_axi && sim_chk_en) begin
            // A-T1: thanh ghi cs_* chỉ mang lệnh tới bank có slot trống
            if (cs_valid && !eng_bank_free[{cs_bg, cs_bank}])
                $error("axi_ddr5_mc_top: command to busy engine slot BG %0d bank %0d (A-T1)", cs_bg, cs_bank);
            // M-12: bộ sinh beat dùng dfi_len[2:0]
            if (cs_valid && cs_len >= AXI_LEN_WIDTH'(8))
                $error("axi_ddr5_mc_top: CAS length %0d >= 8", cs_len);
            // A-C2b: đọc và ghi cùng BG cùng chu kỳ chỉ khi thanh ghi đầu ra IQ rỗng và ghi dùng wbank_credit
            if (rd_fire && wr_fire && iq_sel_bg == wcmd_bg && !(!fe_rd_req_valid && wr_use_wbank))
                $error("axi_ddr5_mc_top: same-BG read+write without write reserve credit (A-C2b)");
        end
`endif

    //=========================================================================
    // 11. Performance Monitor Unit (PMU - Intel PCM Architecture Compatible)
    //=========================================================================
    perf_monitor_unit #(
        .NUM_COUNTERS  (8),
        .COUNTER_WIDTH (32)
    ) u_pmu (
        .clk               (clk_axi),
        .rst_n             (rst_n_axi),
        .cfg_perf_en       (cfg_pmu_en),
        .cfg_counter_reset (cfg_pmu_reset),
        .ev_act_cmd        (dfi_cmd == 3'b001),
        .ev_rd_cmd         (dfi_cmd == 3'b011),
        .ev_wr_cmd         (dfi_cmd == 3'b100),
        .ev_bg_bypass      (ddr_slack_cycle && arb_grant_valid),
        .ev_sdc_throttle   (sdc_cmd_valid && sdc_throttled),
        .ev_rowpress_alert (ddr_rowpress_alert),
        .ev_ecc_corrected  (ecc_single_err),
        .ev_rob_stall      (fe_rd_req_valid && !rob_alloc_ready),
        .i_pmu_reg_sel     (3'b0),
        .o_pmu_reg_data    (),
        .o_all_counters    (o_pmu_counters)
    );

    // Unused signals sink
    logic _unused_top_sink;
    assign _unused_top_sink = &{1'b0, rst_n_ddr, wbuf_data_valid, wbuf_data_last, ecc_double_err,
                                vm_wr_key[0], vm_rd_key[0], vm_wr_tweak[0], vm_rd_tweak[0],
                                vm_wr_bypass, vm_rd_bypass, voted_rowpress_curve[0],
                                eng_cnt_fault, eng_rd_flush, 1'b0};

endmodule
