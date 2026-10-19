// File: ucie_fdi_axi_shim.sv
// Chức năng: Cầu nối AXI-over-UCIe (AoU) theo chuẩn UCIe 1.1 FDI kèm FSM huấn luyện liên kết và mô hình hóa trễ Tau-scaling.
`timescale 1ns / 1ps

/* verilator lint_off UNUSEDSIGNAL */
module ucie_fdi_axi_shim #(
    parameter int AxiIdWidth         = 8,
    parameter int AxiAddrWidth       = 34,
    parameter int AxiDataWidth       = 512,
    parameter int AxiUserWidth       = 8,
    parameter int D2D_LATENCY_CYCLES = 1
)(
    input  logic                     clk,
    input  logic                     rst_n,

    //-------------------------------------------------------------------------
    // UCIe 1.1 FDI (Flit-aware Die-to-Die Interface) Signals
    //-------------------------------------------------------------------------
    // Adapter/Link to Physical Layer (LP - Transmit)
    output logic [AxiDataWidth-1:0]  lp_data,
    output logic                     lp_valid,
    input  logic                     lp_ready,
    output logic [3:0]               lp_state_req,
    output logic                     lp_rx_active_ack,

    // Physical Layer to Adapter (PL - Receive)
    input  logic [AxiDataWidth-1:0]  pl_data,
    input  logic                     pl_valid,
    output logic                     pl_ready,
    input  logic [3:0]               pl_state_sts,
    input  logic                     pl_rx_active_req,

    // Link Status
    output logic                     ucie_link_active,

    //-------------------------------------------------------------------------
    // AMBA AXI5 Master Interface (Driving Q-Shield Controller Core)
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

    // UCIe 1.1 FDI Link State Definitions
    typedef enum logic [2:0] {
        FDI_ST_RESET      = 3'b000,
        FDI_ST_ACTIVE_REQ = 3'b001,
        FDI_ST_ACTIVE     = 3'b010,
        FDI_ST_L1_SLEEP   = 3'b011,
        FDI_ST_ERROR      = 3'b100
    } fdi_state_t;

    fdi_state_t fdi_state_q, fdi_state_d;
    logic       link_active_q;

    assign ucie_link_active = (fdi_state_q == FDI_ST_ACTIVE);

    // 1. UCIe 1.1 FDI Link Bring-Up FSM
    always_comb begin
        fdi_state_d      = fdi_state_q;
        lp_state_req     = 4'h0; // NOP
        lp_rx_active_ack = 1'b0;

        case (fdi_state_q)
            FDI_ST_RESET: begin
                lp_state_req = 4'h0;
                fdi_state_d  = FDI_ST_ACTIVE_REQ;
            end

            FDI_ST_ACTIVE_REQ: begin
                lp_state_req = 4'h1; // Request ACTIVE state
                if (pl_rx_active_req) begin
                    lp_rx_active_ack = 1'b1;
                end
                if (pl_state_sts == 4'h1 && pl_rx_active_req) begin
                    fdi_state_d = FDI_ST_ACTIVE;
                end
            end

            FDI_ST_ACTIVE: begin
                lp_state_req     = 4'h1; // Keep ACTIVE
                lp_rx_active_ack = 1'b1;
                if (pl_state_sts == 4'h2) begin
                    fdi_state_d = FDI_ST_L1_SLEEP;
                end else if (pl_state_sts == 4'hF) begin
                    fdi_state_d = FDI_ST_ERROR;
                end
            end

            FDI_ST_L1_SLEEP: begin
                lp_state_req = 4'h2; // L1 Low Power
                if (pl_state_sts == 4'h1) begin
                    fdi_state_d = FDI_ST_ACTIVE_REQ;
                end
            end

            FDI_ST_ERROR: begin
                lp_state_req = 4'h0;
                fdi_state_d  = FDI_ST_RESET;
            end

            default: fdi_state_d = FDI_ST_RESET;
        endcase
    end

    // 2. AXI-over-UCIe (AoU) Flit Packet Unpacker (Receive Path from Compute Die)
    // Flit Format:
    // [511:508]: Opcode (0: NOP, 1: READ_REQ, 2: WRITE_REQ+DATA)
    // [507:500]: KeyID / User VM ID (8-bit)
    // [499:492]: AXI ID (8-bit)
    // [491:458]: Address (34-bit)
    // [457:0]  : Payload (For Read: zero padded; For Write: 512-bit data beats interleaved)
    logic [3:0]  rx_opcode;
    logic [7:0]  rx_vm_id;
    logic [7:0]  rx_tag;
    logic [33:0] rx_addr;

    assign rx_opcode = pl_data[511:508];
    assign rx_vm_id  = pl_data[507:500];
    assign rx_tag    = pl_data[499:492];
    assign rx_addr   = pl_data[491:458];

    // AR Channel Generation
    assign m_axi_arid    = { {(AxiIdWidth-8 > 0 ? AxiIdWidth-8 : 0){1'b0}}, rx_tag };
    assign m_axi_araddr  = rx_addr;
    assign m_axi_arlen   = 8'h00;
    assign m_axi_arsize  = 3'b110;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arqos   = 4'h0;
    assign m_axi_aruser  = rx_vm_id;
    assign m_axi_arvalid = ucie_link_active && pl_valid && (rx_opcode == 4'h1);

    // AW & W Channel Generation
    assign m_axi_awid    = { {(AxiIdWidth-8 > 0 ? AxiIdWidth-8 : 0){1'b0}}, rx_tag };
    assign m_axi_awaddr  = rx_addr;
    assign m_axi_awlen   = 8'h00;
    assign m_axi_awsize  = 3'b110;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awqos   = 4'h0;
    assign m_axi_awuser  = rx_vm_id;
    assign m_axi_awvalid = ucie_link_active && pl_valid && (rx_opcode == 4'h2);

    assign m_axi_wdata   = pl_data; // Lower bits contain the 512-bit data
    assign m_axi_wstrb   = '1;
    assign m_axi_wlast   = 1'b1;
    assign m_axi_wvalid  = ucie_link_active && pl_valid && (rx_opcode == 4'h2);

    assign pl_ready      = ucie_link_active && (
        (rx_opcode == 4'h1 && m_axi_arready) ||
        (rx_opcode == 4'h2 && m_axi_awready && m_axi_wready) ||
        (rx_opcode == 4'h0)
    );

    // 3. AXI-over-UCIe (AoU) Flit Packet Packer (Transmit Path to Compute Die)
    // Response Flit:
    // [511:508]: Opcode (1: READ_DATA, 2: WRITE_RESP)
    // [507:500]: Poison & Status Flags
    // [499:492]: AXI ID
    // [491:0]  : Read Data / Status
    logic [AxiDataWidth-1:0] tx_flit_comb;
    logic                    tx_valid_comb;

    always_comb begin
        tx_flit_comb  = '0;
        tx_valid_comb = 1'b0;
        m_axi_rready  = 1'b0;
        m_axi_bready  = 1'b0;

        if (m_axi_rvalid) begin
            tx_valid_comb = 1'b1;
            m_axi_rready  = lp_ready;
            tx_flit_comb  = m_axi_rdata;
            tx_flit_comb[511:508] = 4'h1; // READ_DATA
            tx_flit_comb[507]     = m_axi_rpoison || (m_axi_rresp == 2'b10);
            tx_flit_comb[499:492] = m_axi_rid[7:0];
        end else if (m_axi_bvalid) begin
            tx_valid_comb = 1'b1;
            m_axi_bready  = lp_ready;
            tx_flit_comb[511:508] = 4'h2; // WRITE_RESP
            tx_flit_comb[501:500] = m_axi_bresp;
            tx_flit_comb[499:492] = m_axi_bid[7:0];
        end
    end

    // 4. Programmable D2D Delay Pipeline Line (Emulating tau-scaling law)
    generate
        if (D2D_LATENCY_CYCLES > 0) begin : gen_d2d_pipe
            logic [AxiDataWidth-1:0] pipe_data [D2D_LATENCY_CYCLES];
            logic                    pipe_valid[D2D_LATENCY_CYCLES];

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    for (int i = 0; i < D2D_LATENCY_CYCLES; i++) begin
                        pipe_data[i]  <= '0;
                        pipe_valid[i] <= 1'b0;
                    end
                end else begin
                    pipe_data[0]  <= tx_flit_comb;
                    pipe_valid[0] <= tx_valid_comb;
                    for (int i = 1; i < D2D_LATENCY_CYCLES; i++) begin
                        pipe_data[i]  <= pipe_data[i-1];
                        pipe_valid[i] <= pipe_valid[i-1];
                    end
                end
            end

            assign lp_data  = pipe_data[D2D_LATENCY_CYCLES-1];
            assign lp_valid = pipe_valid[D2D_LATENCY_CYCLES-1];
        end else begin : gen_d2d_direct
            assign lp_data  = tx_flit_comb;
            assign lp_valid = tx_valid_comb;
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fdi_state_q   <= FDI_ST_RESET;
            link_active_q <= 1'b0;
        end else begin
            fdi_state_q   <= fdi_state_d;
            link_active_q <= ucie_link_active;
        end
    end

endmodule

// Module Wrapper tích hợp ucie_fdi_axi_shim với axi_ddr5_mc_top phục vụ kiểm thử Form Factor B
module ucie_chiplet_iod_top #(
    parameter int AxiIdWidth         = 8,
    parameter int AxiAddrWidth       = 34,
    parameter int AxiDataWidth       = 512,
    parameter int AxiUserWidth       = 8,
    parameter int D2D_LATENCY_CYCLES = 1,
    parameter int BG_COUNT           = 8,
    parameter int BANK_COUNT         = 4,
    parameter int ROW_WIDTH          = 17,
    parameter int COL_WIDTH          = 10
)(
    input  logic                     clk_axi,
    input  logic                     aresetn_axi,
    input  logic                     clk_ddr,
    input  logic                     aresetn_ddr,

    // UCIe 1.1 FDI Interface
    output logic [AxiDataWidth-1:0]  lp_data,
    output logic                     lp_valid,
    input  logic                     lp_ready,
    output logic [3:0]               lp_state_req,
    output logic                     lp_rx_active_ack,

    input  logic [AxiDataWidth-1:0]  pl_data,
    input  logic                     pl_valid,
    output logic                     pl_ready,
    input  logic [3:0]               pl_state_sts,
    input  logic                     pl_rx_active_req,
    output logic                     o_ucie_link_active,

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

    ucie_fdi_axi_shim #(
        .AxiIdWidth        (AxiIdWidth),
        .AxiAddrWidth      (AxiAddrWidth),
        .AxiDataWidth      (AxiDataWidth),
        .AxiUserWidth      (AxiUserWidth),
        .D2D_LATENCY_CYCLES(D2D_LATENCY_CYCLES)
    ) u_ucie_shim (
        .clk             (clk_axi),
        .rst_n           (aresetn_axi),
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
        .ucie_link_active(o_ucie_link_active),
        .m_axi_awid      (axi_awid),
        .m_axi_awaddr    (axi_awaddr),
        .m_axi_awlen     (axi_awlen),
        .m_axi_awsize    (axi_awsize),
        .m_axi_awburst   (axi_awburst),
        .m_axi_awqos     (axi_awqos),
        .m_axi_awuser    (axi_awuser),
        .m_axi_awvalid   (axi_awvalid),
        .m_axi_awready   (axi_awready),
        .m_axi_wdata     (axi_wdata),
        .m_axi_wstrb     (axi_wstrb),
        .m_axi_wlast     (axi_wlast),
        .m_axi_wvalid    (axi_wvalid),
        .m_axi_wready    (axi_wready),
        .m_axi_bid       (axi_bid),
        .m_axi_bresp     (axi_bresp),
        .m_axi_bvalid    (axi_bvalid),
        .m_axi_bready    (axi_bready),
        .m_axi_arid      (axi_arid),
        .m_axi_araddr    (axi_araddr),
        .m_axi_arlen     (axi_arlen),
        .m_axi_arsize    (axi_arsize),
        .m_axi_arburst   (axi_arburst),
        .m_axi_arqos     (axi_arqos),
        .m_axi_aruser    (axi_aruser),
        .m_axi_arvalid   (axi_arvalid),
        .m_axi_arready   (axi_arready),
        .m_axi_rid       (axi_rid),
        .m_axi_rdata     (axi_rdata),
        .m_axi_rresp     (axi_rresp),
        .m_axi_rlast     (axi_rlast),
        .m_axi_rvalid    (axi_rvalid),
        .m_axi_rready    (axi_rready),
        .m_axi_rpoison   (axi_rpoison)
    );

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
