// File: pcie_cxl_io_apb_shim.sv
// Chức năng: Cầu nối giao thức CXL.io (PCIe TLP / AXI4-Lite) sang APB4 CSR kèm bảng thanh ghi CXL 3.0 DVSEC Capability.
`timescale 1ns / 1ps

/* verilator lint_off UNUSEDSIGNAL */
module pcie_cxl_io_apb_shim #(
    parameter int AxilAddrWidth = 32,
    parameter int AxilDataWidth = 32,
    parameter int ApbAddrWidth  = 12,
    parameter int ApbDataWidth  = 32
)(
    input  logic                     clk,
    input  logic                     rst_n,

    //-------------------------------------------------------------------------
    // AXI4-Lite Slave Interface (PCIe TLP / MMIO Subsystem)
    //-------------------------------------------------------------------------
    // Write Address
    input  logic [AxilAddrWidth-1:0] s_axil_awaddr,
    input  logic [2:0]               s_axil_awprot,
    input  logic                     s_axil_awvalid,
    output logic                     s_axil_awready,

    // Write Data
    input  logic [AxilDataWidth-1:0] s_axil_wdata,
    input  logic [3:0]               s_axil_wstrb,
    input  logic                     s_axil_wvalid,
    output logic                     s_axil_wready,

    // Write Response
    output logic [1:0]               s_axil_bresp,
    output logic                     s_axil_bvalid,
    input  logic                     s_axil_bready,

    // Read Address
    input  logic [AxilAddrWidth-1:0] s_axil_araddr,
    input  logic [2:0]               s_axil_arprot,
    input  logic                     s_axil_arvalid,
    output logic                     s_axil_arready,

    // Read Data
    output logic [AxilDataWidth-1:0] s_axil_rdata,
    output logic [1:0]               s_axil_rresp,
    output logic                     s_axil_rvalid,
    input  logic                     s_axil_rready,

    //-------------------------------------------------------------------------
    // APB4 Master Interface (Connecting to apb_csr_regs.sv)
    //-------------------------------------------------------------------------
    output logic [ApbAddrWidth-1:0]  m_apb_paddr,
    output logic                     m_apb_psel,
    output logic                     m_apb_penable,
    output logic                     m_apb_pwrite,
    output logic [ApbDataWidth-1:0]  m_apb_pwdata,
    output logic [3:0]               m_apb_pstrb,
    output logic [2:0]               m_apb_pprot,
    input  logic                     m_apb_pready,
    input  logic [ApbDataWidth-1:0]  m_apb_prdata,
    input  logic                     m_apb_pslverr
);

    // CXL 3.0 Type-3 DVSEC Capability Register Offsets (0x100 - 0x13C)
    localparam logic [11:0] CXL_DVSEC_HDR1_ADDR   = 12'h100;
    localparam logic [11:0] CXL_DVSEC_HDR2_ADDR   = 12'h104;
    localparam logic [11:0] CXL_CAP_ADDR          = 12'h108;
    localparam logic [11:0] CXL_CTRL_ADDR         = 12'h10C;
    localparam logic [11:0] CXL_STATUS_ADDR       = 12'h110;
    localparam logic [11:0] CXL_HDM_BASE_LO_ADDR  = 12'h114;
    localparam logic [11:0] CXL_HDM_BASE_HI_ADDR  = 12'h118;
    localparam logic [11:0] CXL_HDM_SIZE_LO_ADDR  = 12'h11C;
    localparam logic [11:0] CXL_HDM_SIZE_HI_ADDR  = 12'h120;
    localparam logic [11:0] CXL_HDM_CTRL_ADDR     = 12'h124;

    // DVSEC Register Content: CXL Consortium Vendor 0x1E98, Revision 1, Length 0x3C
    localparam logic [31:0] CXL_DVSEC_HDR1_VAL    = 32'h03C1_1E98;
    localparam logic [31:0] CXL_DVSEC_HDR2_VAL    = 32'h0003_0000; // CXL 3.0 Type 3
    localparam logic [31:0] CXL_CAP_VAL           = 32'h0000_0005; // Mem & IO Capable
    localparam logic [31:0] CXL_HDM_SIZE_LO_VAL   = 32'h4000_0000; // 1 GB Window default

    logic [31:0] cxl_ctrl_reg;
    logic [31:0] cxl_hdm_base_lo_reg;
    logic [31:0] cxl_hdm_base_hi_reg;

    typedef enum logic [2:0] {
        ST_IDLE       = 3'b000,
        ST_WR_APB_SETUP  = 3'b001,
        ST_WR_APB_ACCESS = 3'b010,
        ST_WR_RESP       = 3'b011,
        ST_RD_APB_SETUP  = 3'b100,
        ST_RD_APB_ACCESS = 3'b101,
        ST_RD_RESP       = 3'b110
    } state_t;

    state_t state_q, state_d;

    logic [AxilAddrWidth-1:0] req_addr_q, req_addr_d;
    logic [AxilDataWidth-1:0] req_wdata_q, req_wdata_d;
    logic [3:0]               req_wstrb_q, req_wstrb_d;
    logic [2:0]               req_prot_q, req_prot_d;
    logic [AxilDataWidth-1:0] resp_rdata_q, resp_rdata_d;
    logic [1:0]               resp_status_q, resp_status_d;
    logic                     is_dvsec_access;

    assign is_dvsec_access = (req_addr_q[11:8] == 4'h1);

    always_comb begin
        state_d       = state_q;
        req_addr_d    = req_addr_q;
        req_wdata_d   = req_wdata_q;
        req_wstrb_d   = req_wstrb_q;
        req_prot_d    = req_prot_q;
        resp_rdata_d  = resp_rdata_q;
        resp_status_d = resp_status_q;

        s_axil_awready = 1'b0;
        s_axil_wready  = 1'b0;
        s_axil_bvalid  = 1'b0;
        s_axil_bresp   = resp_status_q;
        s_axil_arready = 1'b0;
        s_axil_rvalid  = 1'b0;
        s_axil_rdata   = resp_rdata_q;
        s_axil_rresp   = resp_status_q;

        m_apb_paddr   = req_addr_q[ApbAddrWidth-1:0];
        m_apb_pwdata  = req_wdata_q;
        m_apb_pstrb   = req_wstrb_q;
        m_apb_pprot   = req_prot_q;
        m_apb_pwrite  = 1'b0;
        m_apb_psel    = 1'b0;
        m_apb_penable = 1'b0;

        case (state_q)
            ST_IDLE: begin
                // Priority given to Write commands
                if (s_axil_awvalid && s_axil_wvalid) begin
                    s_axil_awready = 1'b1;
                    s_axil_wready  = 1'b1;
                    req_addr_d     = s_axil_awaddr;
                    req_wdata_d    = s_axil_wdata;
                    req_wstrb_d    = s_axil_wstrb;
                    req_prot_d     = s_axil_awprot;

                    if (s_axil_awaddr[11:8] == 4'h1) begin
                        state_d = ST_WR_RESP;
                        resp_status_d = 2'b00;
                    end else begin
                        state_d = ST_WR_APB_SETUP;
                    end
                end else if (s_axil_arvalid) begin
                    s_axil_arready = 1'b1;
                    req_addr_d     = s_axil_araddr;
                    req_prot_d     = s_axil_arprot;

                    if (s_axil_araddr[11:8] == 4'h1) begin
                        state_d = ST_RD_RESP;
                        resp_status_d = 2'b00;
                        case (s_axil_araddr[11:0])
                            CXL_DVSEC_HDR1_ADDR:  resp_rdata_d = CXL_DVSEC_HDR1_VAL;
                            CXL_DVSEC_HDR2_ADDR:  resp_rdata_d = CXL_DVSEC_HDR2_VAL;
                            CXL_CAP_ADDR:         resp_rdata_d = CXL_CAP_VAL;
                            CXL_CTRL_ADDR:        resp_rdata_d = cxl_ctrl_reg;
                            CXL_STATUS_ADDR:      resp_rdata_d = 32'h0;
                            CXL_HDM_BASE_LO_ADDR: resp_rdata_d = cxl_hdm_base_lo_reg;
                            CXL_HDM_BASE_HI_ADDR: resp_rdata_d = cxl_hdm_base_hi_reg;
                            CXL_HDM_SIZE_LO_ADDR: resp_rdata_d = CXL_HDM_SIZE_LO_VAL;
                            CXL_HDM_SIZE_HI_ADDR: resp_rdata_d = 32'h0;
                            CXL_HDM_CTRL_ADDR:    resp_rdata_d = 32'h0000_0001;
                            default:              resp_rdata_d = 32'h0;
                        endcase
                    end else begin
                        state_d = ST_RD_APB_SETUP;
                    end
                end
            end

            ST_WR_APB_SETUP: begin
                m_apb_psel    = 1'b1;
                m_apb_pwrite  = 1'b1;
                m_apb_penable = 1'b0;
                state_d       = ST_WR_APB_ACCESS;
            end

            ST_WR_APB_ACCESS: begin
                m_apb_psel    = 1'b1;
                m_apb_pwrite  = 1'b1;
                m_apb_penable = 1'b1;
                if (m_apb_pready) begin
                    resp_status_d = m_apb_pslverr ? 2'b10 : 2'b00;
                    state_d       = ST_WR_RESP;
                end
            end

            ST_WR_RESP: begin
                s_axil_bvalid = 1'b1;
                if (s_axil_bready) begin
                    state_d = ST_IDLE;
                end
            end

            ST_RD_APB_SETUP: begin
                m_apb_psel    = 1'b1;
                m_apb_pwrite  = 1'b0;
                m_apb_penable = 1'b0;
                state_d       = ST_RD_APB_ACCESS;
            end

            ST_RD_APB_ACCESS: begin
                m_apb_psel    = 1'b1;
                m_apb_pwrite  = 1'b0;
                m_apb_penable = 1'b1;
                if (m_apb_pready) begin
                    resp_rdata_d  = m_apb_prdata;
                    resp_status_d = m_apb_pslverr ? 2'b10 : 2'b00;
                    state_d       = ST_RD_RESP;
                end
            end

            ST_RD_RESP: begin
                s_axil_rvalid = 1'b1;
                if (s_axil_rready) begin
                    state_d = ST_IDLE;
                end
            end

            default: state_d = ST_IDLE;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q             <= ST_IDLE;
            req_addr_q          <= '0;
            req_wdata_q         <= '0;
            req_wstrb_q         <= '0;
            req_prot_q          <= '0;
            resp_rdata_q        <= '0;
            resp_status_q       <= '0;
            cxl_ctrl_reg        <= 32'h0000_0003; // Default Mem & IO Enabled
            cxl_hdm_base_lo_reg <= 32'h0000_0000;
            cxl_hdm_base_hi_reg <= 32'h0000_0000;
        end else begin
            state_q       <= state_d;
            req_addr_q    <= req_addr_d;
            req_wdata_q   <= req_wdata_d;
            req_wstrb_q   <= req_wstrb_d;
            req_prot_q    <= req_prot_d;
            resp_rdata_q  <= resp_rdata_d;
            resp_status_q <= resp_status_d;

            // Handle CXL DVSEC configuration writes
            if (state_q == ST_IDLE && s_axil_awvalid && s_axil_wvalid && (s_axil_awaddr[11:8] == 4'h1)) begin
                case (s_axil_awaddr[11:0])
                    CXL_CTRL_ADDR:        cxl_ctrl_reg        <= s_axil_wdata;
                    CXL_HDM_BASE_LO_ADDR: cxl_hdm_base_lo_reg <= s_axil_wdata;
                    CXL_HDM_BASE_HI_ADDR: cxl_hdm_base_hi_reg <= s_axil_wdata;
                    default: ;
                endcase
            end
        end
    end

endmodule

// Module Wrapper tích hợp sẵn pcie_cxl_io_apb_shim với apb_csr_regs phục vụ kiểm chứng
module pcie_cxl_io_csr_top #(
    parameter int AxilAddrWidth = 32,
    parameter int AxilDataWidth = 32
)(
    input  logic                     clk,
    input  logic                     rst_n,

    // AXI4-Lite
    input  logic [AxilAddrWidth-1:0] s_axil_awaddr,
    input  logic [2:0]               s_axil_awprot,
    input  logic                     s_axil_awvalid,
    output logic                     s_axil_awready,

    input  logic [AxilDataWidth-1:0] s_axil_wdata,
    input  logic [3:0]               s_axil_wstrb,
    input  logic                     s_axil_wvalid,
    output logic                     s_axil_wready,

    output logic [1:0]               s_axil_bresp,
    output logic                     s_axil_bvalid,
    input  logic                     s_axil_bready,

    input  logic [AxilAddrWidth-1:0] s_axil_araddr,
    input  logic [2:0]               s_axil_arprot,
    input  logic                     s_axil_arvalid,
    output logic                     s_axil_arready,

    output logic [AxilDataWidth-1:0] s_axil_rdata,
    output logic [1:0]               s_axil_rresp,
    output logic                     s_axil_rvalid,
    input  logic                     s_axil_rready,

    // Telemetry & Profile Observability
    output logic [1:0]               o_cfg_crypto_profile,
    output logic [18:0]              o_cfg_epoch_nonce,
    output logic [7:0]               o_cfg_default_key_id,
    output logic                     o_sec_fault_irq,
    output logic                     o_tmr_alert
);

    logic [11:0] apb_paddr;
    logic        apb_psel;
    logic        apb_penable;
    logic        apb_pwrite;
    logic [31:0] apb_pwdata;
    logic [3:0]  apb_pstrb;
    logic [2:0]  apb_pprot;
    logic        apb_pready;
    logic [31:0] apb_prdata;
    logic        apb_pslverr;

    pcie_cxl_io_apb_shim #(
        .AxilAddrWidth(AxilAddrWidth),
        .AxilDataWidth(AxilDataWidth),
        .ApbAddrWidth (12),
        .ApbDataWidth (32)
    ) u_shim (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_axil_awaddr (s_axil_awaddr),
        .s_axil_awprot (s_axil_awprot),
        .s_axil_awvalid(s_axil_awvalid),
        .s_axil_awready(s_axil_awready),
        .s_axil_wdata  (s_axil_wdata),
        .s_axil_wstrb  (s_axil_wstrb),
        .s_axil_wvalid (s_axil_wvalid),
        .s_axil_wready (s_axil_wready),
        .s_axil_bresp  (s_axil_bresp),
        .s_axil_bvalid (s_axil_bvalid),
        .s_axil_bready (s_axil_bready),
        .s_axil_araddr (s_axil_araddr),
        .s_axil_arprot (s_axil_arprot),
        .s_axil_arvalid(s_axil_arvalid),
        .s_axil_arready(s_axil_arready),
        .s_axil_rdata  (s_axil_rdata),
        .s_axil_rresp  (s_axil_rresp),
        .s_axil_rvalid (s_axil_rvalid),
        .s_axil_rready (s_axil_rready),
        .m_apb_paddr   (apb_paddr),
        .m_apb_psel    (apb_psel),
        .m_apb_penable (apb_penable),
        .m_apb_pwrite  (apb_pwrite),
        .m_apb_pwdata  (apb_pwdata),
        .m_apb_pstrb   (apb_pstrb),
        .m_apb_pprot   (apb_pprot),
        .m_apb_pready  (apb_pready),
        .m_apb_prdata  (apb_prdata),
        .m_apb_pslverr (apb_pslverr)
    );

    apb_csr_regs #(
        .AddrWidth(12),
        .DataWidth(32)
    ) u_csr (
        .pclk                  (clk),
        .presetn               (rst_n),
        .paddr                 (apb_paddr),
        .psel                  (apb_psel),
        .penable               (apb_penable),
        .pwrite                (apb_pwrite),
        .pwdata                (apb_pwdata),
        .pstrb                 (apb_pstrb),
        .pprot                 (apb_pprot),
        .pready                (apb_pready),
        .prdata                (apb_prdata),
        .pslverr               (apb_pslverr),
        .enc_enable            (),
        .soft_reset            (),
        .perf_cnt_en           (),
        .auto_tweak_en         (),
        .sec_locked            (),
        .key1_data             (),
        .key2_data             (),
        .keys_valid            (),
        .pipe_busy             (1'b0),
        .core_status_flags     (8'h0),
        .block_encrypted_pulse (1'b0),
        .pipeline_stall_active (1'b0),
        .cfg_sdc_thresh        (),
        .cfg_window_size       (),
        .cfg_scrub_interval    (),
        .cfg_rowpress_thresh   (),
        .cfg_rowpress_curve    (),
        .cfg_drm_en            (),
        .cfg_drm_victim2_en    (),
        .cfg_ate_en            (),
        .cfg_ate_alpha_shift   (),
        .cfg_scramble_en       (),
        .cfg_scramble_reseed   (),
        .cfg_scramble_seed     (),
        .cfg_bank_coloring_en  (),
        .cfg_mapping_mode      (),
        .cfg_crypto_mode       (),
        .cfg_ecc_mode          (),
        .cfg_pmu_en            (),
        .cfg_pmu_reset         (),
        .cfg_crypto_profile    (o_cfg_crypto_profile),
        .cfg_default_key_id    (o_cfg_default_key_id),
        .cfg_epoch_nonce       (o_cfg_epoch_nonce),
        .sec_fault_status      (),
        .sec_fault_irq         (o_sec_fault_irq),
        .i_sec_fault_set       (5'b0),
        .i_fault_addr_log      (32'h0),
        .o_tmr_alert           (o_tmr_alert),
        .o_glitch_alert        (),
        .telem_accesses        (32'h0),
        .telem_throttles       (32'h0),
        .ecc_single_err_cnt    (16'h0),
        .ecc_double_err_cnt    (16'h0),
        .rowpress_alert_cnt    (16'h0),
        .ate_dynamic_thresh    (16'h0),
        .pmu_counters          (256'h0)
    );

endmodule
