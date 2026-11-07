// File: axi_ddr5_mc_secure_top.sv
// Chức năng: Bộ điều khiển bộ nhớ bảo mật DDR5 bọc lõi chuẩn axi_ddr5_mc_top với cầu nối mật mã ngoài lõi.

`timescale 1ns / 1ps

/* verilator lint_off PINCONNECTEMPTY */
/* verilator lint_off UNUSEDSIGNAL */
module axi_ddr5_mc_secure_top #(
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
    parameter int COL_WIDTH       = 13,
    parameter int ROB_DEPTH       = 16,
    parameter int ROB_PTR_WIDTH   = $clog2(ROB_DEPTH),
    parameter int DFI_WRLAT       = 9,
    parameter int DFI_RDLAT       = 8,
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
    parameter int TCWL_BL_PS      = 21250
)(
    //-------------------------------------------------------------------------
    // Clock & Reset
    //-------------------------------------------------------------------------
    input  logic                                         clk_axi,
    input  logic                                         aresetn_axi,
    input  logic                                         clk_ddr = 1'b0,
    input  logic                                         aresetn_ddr = 1'b1,

    //-------------------------------------------------------------------------
    // Giao diện điều khiển mật mã (Đặc tả S8)
    //-------------------------------------------------------------------------
    input  logic                                         i_enc_enable,
    input  logic                                         i_keys_valid,
    input  logic [255:0]                                 i_key1,
    input  logic [255:0]                                 i_key2,
    input  logic [3:0]                                   i_asid,
    input  logic [18:0]                                  i_epoch,
    output logic                                         o_crypto_busy,
    output logic [15:0]                                  o_crypto_reject_cnt,
    output logic [15:0]                                  o_crypto_err_cnt,

    //-------------------------------------------------------------------------
    // AXI4 Slave Interface (Từ Host / Master)
    //-------------------------------------------------------------------------
    input  logic [AXI_ID_WIDTH-1:0]                      s_axi_awid,
    input  logic [AXI_ADDR_WIDTH-1:0]                    s_axi_awaddr,
    input  logic [AXI_LEN_WIDTH-1:0]                     s_axi_awlen,
    input  logic [2:0]                                   s_axi_awsize,
    input  logic [1:0]                                   s_axi_awburst,
    input  logic [AXI_QOS_WIDTH-1:0]                     s_axi_awqos,
    input  logic                                         s_axi_awvalid,
    output logic                                         s_axi_awready,

    input  logic [AXI_DATA_WIDTH-1:0]                    s_axi_wdata,
    input  logic [AXI_STRB_WIDTH-1:0]                    s_axi_wstrb,
    input  logic                                         s_axi_wlast,
    input  logic                                         s_axi_wvalid,
    output logic                                         s_axi_wready,

    output logic [AXI_ID_WIDTH-1:0]                      s_axi_bid,
    output logic [1:0]                                   s_axi_bresp,
    output logic                                         s_axi_bvalid,
    input  logic                                         s_axi_bready,

    input  logic [AXI_ID_WIDTH-1:0]                      s_axi_arid,
    input  logic [AXI_ADDR_WIDTH-1:0]                    s_axi_araddr,
    input  logic [AXI_LEN_WIDTH-1:0]                     s_axi_arlen,
    input  logic [2:0]                                   s_axi_arsize,
    input  logic [1:0]                                   s_axi_arburst,
    input  logic [AXI_QOS_WIDTH-1:0]                     s_axi_arqos,
    input  logic                                         s_axi_arvalid,
    output logic                                         s_axi_arready,

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
    output logic [7:0]                                   dfi_len,
    output logic                                         dfi_wrdata_en,
    output logic [AXI_DATA_WIDTH-1:0]                    dfi_wrdata,
    output logic [AXI_DATA_WIDTH/8-1:0]                  dfi_wrdata_mask,
    output logic [AXI_DATA_WIDTH/8-1:0]                  dfi_wrdata_ecc,
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
    input  logic [1:0]                                   cfg_scramble_mode  = 2'b10,
    input  logic                                         cfg_decoy_en       = 1'b0,
    input  logic                                         cfg_fault_clr      = 1'b0,
    output logic                                         o_decoy_active,
    output logic [15:0]                                  o_decoy_cnt,
    output logic [8:0]                                   o_fault_cause,
    output logic                                         o_glitch_alert,
    output logic                                         o_security_locked,
    input  logic                                         cfg_parity_check_en = 1'b0,
    output logic                                         o_rob_raw_hazard
);

    //-------------------------------------------------------------------------
    // Đường AXI nội bộ giữa Cầu nối Mật mã và Lõi axi_ddr5_mc_top
    //-------------------------------------------------------------------------
    logic [AXI_ID_WIDTH-1:0]     core_axi_awid;
    logic [AXI_ADDR_WIDTH-1:0]   core_axi_awaddr;
    logic [AXI_LEN_WIDTH-1:0]    core_axi_awlen;
    logic [2:0]                  core_axi_awsize;
    logic [1:0]                  core_axi_awburst;
    logic [AXI_QOS_WIDTH-1:0]    core_axi_awqos;
    logic                        core_axi_awvalid;
    logic                        core_axi_awready;

    logic [AXI_DATA_WIDTH-1:0]   core_axi_wdata;
    logic [AXI_STRB_WIDTH-1:0]   core_axi_wstrb;
    logic                        core_axi_wlast;
    logic                        core_axi_wvalid;
    logic                        core_axi_wready;

    logic [AXI_ID_WIDTH-1:0]     core_axi_bid;
    logic [1:0]                  core_axi_bresp;
    logic                        core_axi_bvalid;
    logic                        core_axi_bready;

    logic [AXI_ID_WIDTH-1:0]     core_axi_arid;
    logic [AXI_ADDR_WIDTH-1:0]   core_axi_araddr;
    logic [AXI_LEN_WIDTH-1:0]    core_axi_arlen;
    logic [2:0]                  core_axi_arsize;
    logic [1:0]                  core_axi_arburst;
    logic [AXI_QOS_WIDTH-1:0]    core_axi_arqos;
    logic                        core_axi_arvalid;
    logic                        core_axi_arready;

    logic [AXI_ID_WIDTH-1:0]     core_axi_rid;
    logic [AXI_DATA_WIDTH-1:0]   core_axi_rdata;
    logic [1:0]                  core_axi_rresp;
    logic                        core_axi_rlast;
    logic                        core_axi_rvalid;
    logic                        core_axi_rready;

    //-------------------------------------------------------------------------
    // Khởi tạo Cầu nối Mật mã AXI (Đặc tả S1: Bridge bên ngoài lõi)
    //-------------------------------------------------------------------------
    qshield_axi_crypto_bridge #(
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_STRB_WIDTH (AXI_STRB_WIDTH),
        .AXI_LEN_WIDTH  (AXI_LEN_WIDTH),
        .AXI_QOS_WIDTH  (AXI_QOS_WIDTH)
    ) u_crypto_bridge (
        .clk                 (clk_axi),
        .rst_n               (aresetn_axi),

        // Cổng điều khiển bảo mật
        .i_enc_enable        (i_enc_enable),
        .i_keys_valid        (i_keys_valid),
        .i_key1              (i_key1),
        .i_key2              (i_key2),
        .i_asid              (i_asid),
        .i_epoch             (i_epoch),
        .o_crypto_busy       (o_crypto_busy),
        .o_crypto_reject_cnt (o_crypto_reject_cnt),
        .o_crypto_err_cnt    (o_crypto_err_cnt),

        // AXI Slave (Host ngoài)
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

        // AXI Master (xuống lõi)
        .m_axi_awid          (core_axi_awid),
        .m_axi_awaddr        (core_axi_awaddr),
        .m_axi_awlen         (core_axi_awlen),
        .m_axi_awsize        (core_axi_awsize),
        .m_axi_awburst       (core_axi_awburst),
        .m_axi_awqos         (core_axi_awqos),
        .m_axi_awvalid       (core_axi_awvalid),
        .m_axi_awready       (core_axi_awready),

        .m_axi_wdata         (core_axi_wdata),
        .m_axi_wstrb         (core_axi_wstrb),
        .m_axi_wlast         (core_axi_wlast),
        .m_axi_wvalid        (core_axi_wvalid),
        .m_axi_wready        (core_axi_wready),

        .m_axi_bid           (core_axi_bid),
        .m_axi_bresp         (core_axi_bresp),
        .m_axi_bvalid        (core_axi_bvalid),
        .m_axi_bready        (core_axi_bready),

        .m_axi_arid          (core_axi_arid),
        .m_axi_araddr        (core_axi_araddr),
        .m_axi_arlen         (core_axi_arlen),
        .m_axi_arsize        (core_axi_arsize),
        .m_axi_arburst       (core_axi_arburst),
        .m_axi_arqos         (core_axi_arqos),
        .m_axi_arvalid       (core_axi_arvalid),
        .m_axi_arready       (core_axi_arready),

        .m_axi_rid           (core_axi_rid),
        .m_axi_rdata         (core_axi_rdata),
        .m_axi_rresp         (core_axi_rresp),
        .m_axi_rlast         (core_axi_rlast),
        .m_axi_rvalid        (core_axi_rvalid),
        .m_axi_rready        (core_axi_rready)
    );

    //-------------------------------------------------------------------------
    // Khởi tạo Lõi chuẩn axi_ddr5_mc_top (Nguyên vẹn, không chỉnh sửa)
    //-------------------------------------------------------------------------
    axi_ddr5_mc_top #(
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_LEN_WIDTH  (AXI_LEN_WIDTH),
        .AXI_QOS_WIDTH  (AXI_QOS_WIDTH),
        .BG_COUNT       (BG_COUNT),
        .BANK_COUNT     (BANK_COUNT),
        .ROW_WIDTH      (ROW_WIDTH),
        .COL_WIDTH      (COL_WIDTH),
        .ROB_DEPTH      (ROB_DEPTH),
        .DFI_WRLAT      (DFI_WRLAT),
        .DFI_RDLAT      (DFI_RDLAT),
        .TCK_PS         (TCK_PS),
        .TRCD_PS        (TRCD_PS),
        .TRP_PS         (TRP_PS),
        .TRAS_PS        (TRAS_PS),
        .TRFC_PS        (TRFC_PS),
        .TRFM_PS        (TRFM_PS),
        .TREFI_PS       (TREFI_PS),
        .TWR_PS         (TWR_PS),
        .TRTP_PS        (TRTP_PS),
        .TRRD_S_PS      (TRRD_S_PS),
        .TRRD_L_PS      (TRRD_L_PS),
        .TFAW_PS        (TFAW_PS),
        .TCCD_S_PS      (TCCD_S_PS),
        .TCCD_L_PS      (TCCD_L_PS),
        .TCCD_L_WR_PS   (TCCD_L_WR_PS),
        .TWTR_S_PS      (TWTR_S_PS),
        .TWTR_L_PS      (TWTR_L_PS),
        .TCWL_BL_PS     (TCWL_BL_PS)
    ) u_mc_core (
        .clk_axi             (clk_axi),
        .aresetn_axi         (aresetn_axi),
        .clk_ddr             (clk_ddr),
        .aresetn_ddr         (aresetn_ddr),

        .s_axi_awid          (core_axi_awid),
        .s_axi_awaddr        (core_axi_awaddr),
        .s_axi_awlen         (core_axi_awlen),
        .s_axi_awsize        (core_axi_awsize),
        .s_axi_awburst       (core_axi_awburst),
        .s_axi_awqos         (core_axi_awqos),
        .s_axi_awvalid       (core_axi_awvalid),
        .s_axi_awready       (core_axi_awready),

        .s_axi_wdata         (core_axi_wdata),
        .s_axi_wstrb         (core_axi_wstrb),
        .s_axi_wlast         (core_axi_wlast),
        .s_axi_wvalid        (core_axi_wvalid),
        .s_axi_wready        (core_axi_wready),

        .s_axi_bid           (core_axi_bid),
        .s_axi_bresp         (core_axi_bresp),
        .s_axi_bvalid        (core_axi_bvalid),
        .s_axi_bready        (core_axi_bready),

        .s_axi_arid          (core_axi_arid),
        .s_axi_araddr        (core_axi_araddr),
        .s_axi_arlen         (core_axi_arlen),
        .s_axi_arsize        (core_axi_arsize),
        .s_axi_arburst       (core_axi_arburst),
        .s_axi_arqos         (core_axi_arqos),
        .s_axi_arvalid       (core_axi_arvalid),
        .s_axi_arready       (core_axi_arready),

        .s_axi_rid           (core_axi_rid),
        .s_axi_rdata         (core_axi_rdata),
        .s_axi_rresp         (core_axi_rresp),
        .s_axi_rlast         (core_axi_rlast),
        .s_axi_rvalid        (core_axi_rvalid),
        .s_axi_rready        (core_axi_rready),
        .s_axi_rpoison       (s_axi_rpoison),
        .s_axi_rchk          (s_axi_rchk),
        .o_parity_err        (o_parity_err),

        .dfi_cmd             (dfi_cmd),
        .dfi_bg              (dfi_bg),
        .dfi_bank            (dfi_bank),
        .dfi_row             (dfi_row),
        .dfi_col             (dfi_col),
        .dfi_len             (dfi_len),
        .dfi_wrdata_en       (dfi_wrdata_en),
        .dfi_wrdata          (dfi_wrdata),
        .dfi_wrdata_mask     (dfi_wrdata_mask),
        .dfi_wrdata_ecc      (dfi_wrdata_ecc),
        .dfi_rddata_valid    (dfi_rddata_valid),
        .dfi_rddata          (dfi_rddata),
        .dfi_rddata_ecc      (dfi_rddata_ecc),

        .cfg_is_ddr5         (cfg_is_ddr5),
        .cfg_dual_hash_en    (cfg_dual_hash_en),
        .cfg_rh_threshold    (cfg_rh_threshold),
        .cfg_window_size     (cfg_window_size),
        .o_throttled_events  (o_throttled_events),
        .o_ecc_single_err_cnt(o_ecc_single_err_cnt),
        .o_ecc_double_err_cnt(o_ecc_double_err_cnt),

        .cfg_bank_coloring_en(cfg_bank_coloring_en),
        .cfg_mapping_mode    (cfg_mapping_mode),
        .cfg_scramble_en     (cfg_scramble_en),
        .cfg_scramble_reseed (cfg_scramble_reseed),
        .cfg_scramble_seed   (cfg_scramble_seed),
        .cfg_pmu_en          (cfg_pmu_en),
        .cfg_pmu_reset       (cfg_pmu_reset),
        .o_pmu_counters      (o_pmu_counters),

        .cfg_rowpress_curve  (cfg_rowpress_curve),
        .cfg_victim3_en      (cfg_victim3_en),
        .i_dram_abo_alert    (i_dram_abo_alert),
        .o_abo_alert_cnt     (o_abo_alert_cnt),
        .o_ecc_miscorrect_cnt(o_ecc_miscorrect_cnt),
        .o_coordinated_throttle_active(o_coordinated_throttle_active),
        .o_rfm_auto_cnt      (o_rfm_auto_cnt),
        .o_tras_clamped_alert(o_tras_clamped_alert),

        .cfg_scramble_mode   (cfg_scramble_mode),
        .cfg_decoy_en        (cfg_decoy_en),
        .cfg_fault_clr       (cfg_fault_clr),
        .o_decoy_active      (o_decoy_active),
        .o_decoy_cnt         (o_decoy_cnt),
        .o_fault_cause       (o_fault_cause),
        .o_glitch_alert      (o_glitch_alert),
        .o_security_locked   (o_security_locked),
        .cfg_parity_check_en (cfg_parity_check_en),
        .o_rob_raw_hazard    (o_rob_raw_hazard)
    );

endmodule
