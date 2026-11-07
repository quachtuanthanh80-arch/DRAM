// File:        tb_axi_ddr5_mc_top.sv
// Chức năng:   Testbench tích hợp toàn cục cho axi_ddr5_mc_top (AXI4, Write-Drain, ATE, DRM, SDC Filter, JEDEC v2 + 3 checker bảo mật).
`timescale 1ns / 1ps

module tb_axi_ddr5_mc_top #(
    parameter int TB_TCK_PS     = 4000,
    parameter bit RANDOM_RREADY = 1'b0
);

    localparam int AXI_ID_WIDTH   = 4;
    localparam int AXI_ADDR_WIDTH = 32;
    localparam int AXI_DATA_WIDTH = 64;
    localparam int AXI_STRB_WIDTH = 8;
    localparam int AXI_LEN_WIDTH  = 8;
    localparam int AXI_QOS_WIDTH  = 4;
    localparam int BG_COUNT       = 8;
    localparam int BG_WIDTH       = 3;
    localparam int BANK_COUNT     = 4;
    localparam int BANK_WIDTH     = 2;
    localparam int ROW_WIDTH      = 17;
    localparam int COL_WIDTH      = 13;
    localparam int ROB_DEPTH      = 16;

    // Clocks and Resets
    logic clk_axi = 0;
    always #(0.0005ns * TB_TCK_PS) clk_axi = ~clk_axi;

    logic clk_ddr = 0;
    always #1.25 clk_ddr = ~clk_ddr; // 400 MHz

    logic aresetn_axi;
    logic aresetn_ddr;

    // AXI4 Interface
    logic [AXI_ID_WIDTH-1:0]   s_axi_awid;
    logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr;
    logic [AXI_LEN_WIDTH-1:0]  s_axi_awlen;
    logic [2:0]                s_axi_awsize;
    logic [1:0]                s_axi_awburst;
    logic [AXI_QOS_WIDTH-1:0]  s_axi_awqos;
    logic                      s_axi_awvalid;
    logic                      s_axi_awready;

    logic [AXI_DATA_WIDTH-1:0] s_axi_wdata;
    logic [AXI_STRB_WIDTH-1:0] s_axi_wstrb;
    logic                      s_axi_wlast;
    logic                      s_axi_wvalid;
    logic                      s_axi_wready;

    logic [AXI_ID_WIDTH-1:0]   s_axi_bid;
    logic [1:0]                s_axi_bresp;
    logic                      s_axi_bvalid;
    logic                      s_axi_bready;

    logic [AXI_ID_WIDTH-1:0]   s_axi_arid;
    logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr;
    logic [AXI_LEN_WIDTH-1:0]  s_axi_arlen;
    logic [2:0]                s_axi_arsize;
    logic [1:0]                s_axi_arburst;
    logic [AXI_QOS_WIDTH-1:0]  s_axi_arqos;
    logic                      s_axi_arvalid;
    logic                      s_axi_arready;

    logic [AXI_ID_WIDTH-1:0]   s_axi_rid;
    logic [AXI_DATA_WIDTH-1:0] s_axi_rdata;
    logic [1:0]                s_axi_rresp;
    logic                      s_axi_rlast;
    logic                      s_axi_rvalid;
    logic                      s_axi_rready;

    // DFI Interface
    logic [2:0]                dfi_cmd;
    logic [BG_WIDTH-1:0]       dfi_bg;
    logic [BANK_WIDTH-1:0]     dfi_bank;
    logic [ROW_WIDTH-1:0]      dfi_row;
    logic [COL_WIDTH-1:0]      dfi_col;
    logic [7:0]                dfi_len;
    logic                      dfi_wrdata_en;
    logic [63:0]               dfi_wrdata;
    logic [7:0]                dfi_wrdata_mask;
    logic                      dfi_rddata_valid;
    logic [63:0]               dfi_rddata;
    logic [7:0]  dfi_wrdata_ecc, dfi_rddata_ecc;

    // Config & Telemetry
    logic                      cfg_is_ddr5;
    logic                      cfg_dual_hash_en;
    logic [15:0]               cfg_rh_threshold;
    logic [15:0]               cfg_window_size;
    logic [15:0]               o_throttled_events;
    logic [15:0]               o_ecc_single_err_cnt;
    logic [15:0]               o_ecc_double_err_cnt;

    // DUT Instantiation
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
        .DFI_RDLAT      (8),
        .TCK_PS         (TB_TCK_PS)
    ) dut (
        .clk_axi             (clk_axi),
        .aresetn_axi         (aresetn_axi),
        .clk_ddr             (clk_ddr),
        .aresetn_ddr         (aresetn_ddr),

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

        .dfi_cmd             (dfi_cmd),
        .dfi_bg              (dfi_bg),
        .dfi_bank            (dfi_bank),
        .dfi_row             (dfi_row),
        .dfi_col             (dfi_col),
        .dfi_len             (dfi_len),
        .dfi_wrdata_en       (dfi_wrdata_en),
        .dfi_wrdata          (dfi_wrdata),
        .dfi_wrdata_mask     (dfi_wrdata_mask), .dfi_wrdata_ecc(dfi_wrdata_ecc),
        .dfi_rddata_valid    (dfi_rddata_valid),
        .dfi_rddata          (dfi_rddata), .dfi_rddata_ecc(dfi_rddata_ecc),

        .cfg_is_ddr5         (cfg_is_ddr5),
        .cfg_dual_hash_en    (cfg_dual_hash_en),
        .cfg_rh_threshold    (cfg_rh_threshold),
        .cfg_window_size     (cfg_window_size),
        .o_throttled_events  (o_throttled_events),
        .o_ecc_single_err_cnt(o_ecc_single_err_cnt),
        .o_ecc_double_err_cnt(o_ecc_double_err_cnt)
    );

    // Bộ kiểm tra giao thức JEDEC gắn trên đầu ra command engine (trước bus scrambler).
    // Mô hình DRAM hành vi: dữ liệu ghi lưu theo địa chỉ word vật lý, dữ liệu đọc trả về sau RL (= T_CL của engine)
    dram_model #(.COL_W(COL_WIDTH), .RL(8), .WL(9)) u_dram (
        .clk          (clk_axi),
        .rst_n        (aresetn_axi),
        .cmd          (dfi_cmd),
        .bg           (dfi_bg),
        .bank         (dfi_bank),
        .row          (dfi_row),
        .col          (dfi_col),
        .len          (dfi_len),
        .wrdata_en    (dfi_wrdata_en),
        .wrdata       (dfi_wrdata),
        .wrdata_mask  (dfi_wrdata_mask), .wrdata_ecc(dfi_wrdata_ecc),
        .rddata_valid (dfi_rddata_valid),
        .rddata       (dfi_rddata), .rddata_ecc(dfi_rddata_ecc)
    );

    dfi_jedec_checker #(.TCK_PS(TB_TCK_PS), .TB_DFI_WRLAT(9)) u_jchk (.len(dut.u_cmd_engine.o_dfi_len), 
        .clk  (clk_axi),
        .rst_n(aresetn_axi),
        .cmd  (dut.u_cmd_engine.o_dfi_cmd),
        .bg   (dut.u_cmd_engine.o_dfi_bg),
        .bank (dut.u_cmd_engine.o_dfi_bank),
        .row  (dut.u_cmd_engine.o_dfi_row)
    );

    qs_axi_txn_chk #(
        .AXI_ADDR_W (AXI_ADDR_WIDTH),
        .AXI_DATA_W (AXI_DATA_WIDTH),
        .AXI_ID_W   (AXI_ID_WIDTH),
        .AXI_LEN_W  (AXI_LEN_WIDTH)
    ) u_achk (
        .clk           (clk_axi),
        .rst_n         (aresetn_axi),
        .en_v2         (1'b1),
        .chk_data_en   (1'b1),
        .s_axi_awid    (s_axi_awid),
        .s_axi_awaddr  (s_axi_awaddr),
        .s_axi_awlen   (s_axi_awlen),
        .s_axi_awvalid (s_axi_awvalid),
        .s_axi_awready (s_axi_awready),
        .s_axi_wdata   (s_axi_wdata),
        .s_axi_wstrb   (s_axi_wstrb),
        .s_axi_wlast   (s_axi_wlast),
        .s_axi_wvalid  (s_axi_wvalid),
        .s_axi_wready  (s_axi_wready),
        .s_axi_bid     (s_axi_bid),
        .s_axi_bresp   (s_axi_bresp),
        .s_axi_bvalid  (s_axi_bvalid),
        .s_axi_bready  (s_axi_bready),
        .s_axi_arid    (s_axi_arid),
        .s_axi_araddr  (s_axi_araddr),
        .s_axi_arlen   (s_axi_arlen),
        .s_axi_arvalid (s_axi_arvalid),
        .s_axi_arready (s_axi_arready),
        .s_axi_rid     (s_axi_rid),
        .s_axi_rdata   (s_axi_rdata),
        .s_axi_rresp   (s_axi_rresp),
        .s_axi_rlast   (s_axi_rlast),
        .s_axi_rvalid  (s_axi_rvalid),
        .s_axi_rready  (s_axi_rready),
        .s_axi_rpoison (dut.s_axi_rpoison)
    );

    qs_engine_port_chk #(
        .NB      (BG_COUNT * BANK_COUNT),
        .BG_W    (BG_WIDTH),
        .BANK_W  (BANK_WIDTH),
        .ROW_W   (ROW_WIDTH),
        .COL_W   (COL_WIDTH),
        .TAG_W   ($clog2(ROB_DEPTH)),
        .T_RDV   (9)
    ) u_echk (
        .clk                 (clk_axi),
        .rst_n               (aresetn_axi),
        .en_v2               (1'b1),
        .fi_any              (1'b0),
        .fi_rd_state         (1'b0),
        .allow_it1           (1'b0),
        .i_cmd_valid         (dut.u_cmd_engine.i_cmd_valid),
        .i_cmd_bg            (dut.u_cmd_engine.i_cmd_bg),
        .i_cmd_bank          (dut.u_cmd_engine.i_cmd_bank),
        .i_cmd_len           (dut.u_cmd_engine.i_cmd_len),
        .i_cmd_is_mitigation (dut.u_cmd_engine.i_cmd_is_mitigation),
        .o_bank_free         (dut.u_cmd_engine.o_bank_free),
        .o_engine_mit_only   (dut.u_cmd_engine.o_engine_mit_only),
        .o_abo_active        (dut.u_cmd_engine.o_abo_active),
        .i_dram_abo_alert    (dut.u_cmd_engine.i_dram_abo_alert),
        .i_force_rfm         (dut.u_cmd_engine.i_force_rfm),
        .o_dfi_cmd           (dut.u_cmd_engine.o_dfi_cmd),
        .o_dfi_bg            (dut.u_cmd_engine.o_dfi_bg),
        .o_dfi_bank          (dut.u_cmd_engine.o_dfi_bank),
        .o_dfi_row           (dut.u_cmd_engine.o_dfi_row),
        .o_dfi_col           (dut.u_cmd_engine.o_dfi_col),
        .o_dfi_len           (dut.u_cmd_engine.o_dfi_len),
        .o_dfi_tag           (dut.u_cmd_engine.o_dfi_tag),
        .o_ref_tick          (dut.u_cmd_engine.o_ref_tick),
        .o_rfm_active        (dut.u_cmd_engine.o_rfm_active),
        .o_fault             (dut.u_cmd_engine.o_fault),
        .rd_valid            (dut.u_cmd_engine.i_dfi_rddata_valid),
        .o_rd_take           (dut.u_cmd_engine.o_rd_take),
        .o_rd_beat_ok        (dut.u_cmd_engine.o_rd_beat_ok),
        .o_rd_flush          (dut.u_cmd_engine.o_rd_flush),
        .o_rd_resync         (dut.u_cmd_engine.o_rd_resync),
        .o_wb_valid          (dut.u_cmd_engine.o_wb_valid),
        .o_wb_tag            (dut.u_cmd_engine.o_wb_tag),
        .o_wb_last           (dut.u_cmd_engine.o_wb_last),
        .o_wb_err            (dut.u_cmd_engine.o_wb_err),
        .o_wb_resp           (dut.u_cmd_engine.o_wb_resp),
        .o_rmw_valid         (dut.u_cmd_engine.o_rmw_valid)
    );

    qs_top_probe_chk #(
        .BG_COUNT   (BG_COUNT),
        .BANK_COUNT (BANK_COUNT),
        .ROB_DEPTH  (ROB_DEPTH)
    ) u_pchk (
        .clk   (clk_axi),
        .rst_n (aresetn_axi),
        .en_v2 (1'b1),
        .fi_any(1'b0)
    );

    int test_passed = 0;
    int test_failed = 0;
    `include "tb_check.svh"

    // Monitor DFI/B/R: đếm lệnh WR thật trên DFI, chốt phản hồi B và dữ liệu R để phán định bằng quan sát.
    int dfi_wr_cnt = 0;
    logic [AXI_ID_WIDTH-1:0]   last_bid;
    logic [1:0]                last_bresp;
    logic [AXI_DATA_WIDTH-1:0] last_rdata;
    logic [AXI_ID_WIDTH-1:0]   last_rid;
    int r_bursts = 0;

    // Scoreboard địa chỉ DFI đối chiếu với addr_mapper_ddr5 (T11 / C-3, C-4)
    logic                 ref_wr_valid;
    logic [BG_WIDTH-1:0]  ref_wr_bg;
    logic [BANK_WIDTH-1:0]ref_wr_bank;
    logic [ROW_WIDTH-1:0] ref_wr_row;
    logic [COL_WIDTH-1:0] ref_wr_col;

    addr_mapper_ddr5 #(
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_QOS_WIDTH  (AXI_QOS_WIDTH),
        .ROW_WIDTH      (ROW_WIDTH),
        .COL_WIDTH      (COL_WIDTH),
        .BG_WIDTH       (BG_WIDTH),
        .BANK_WIDTH     (BANK_WIDTH)
    ) u_ref_mapper_wr (
        .clk                  (clk_axi),
        .rst_n                (aresetn_axi),
        .cfg_is_ddr5          (cfg_is_ddr5),
        .cfg_bank_coloring_en (1'b0),
        .cfg_mapping_mode     (2'b00),
        .cfg_scramble_en      (1'b1),
        .cfg_scramble_mode    (2'b10),
        .cfg_scramble_seed    (64'hA5A5_5A5A_0123_4567),
        .i_req_valid          (s_axi_awvalid && s_axi_awready),
        .o_req_ready          (),
        .i_req_id             (s_axi_awid),
        .i_req_tenant         (s_axi_awid),
        .i_req_is_write       (1'b1),
        .i_req_addr           (s_axi_awaddr),
        .i_req_len            (s_axi_awlen),
        .i_req_qos            (s_axi_awqos),
        .o_cmd_valid          (ref_wr_valid),
        .i_cmd_ready          (1'b1),
        .o_cmd_id             (),
        .o_cmd_is_write       (),
        .o_cmd_bg             (ref_wr_bg),
        .o_cmd_bank           (ref_wr_bank),
        .o_cmd_row            (ref_wr_row),
        .o_cmd_col            (ref_wr_col),
        .o_cmd_len            (),
        .o_cmd_qos            (),
        .o_busy               ()
    );

    logic                 ref_rd_valid;
    logic [BG_WIDTH-1:0]  ref_rd_bg;
    logic [BANK_WIDTH-1:0]ref_rd_bank;
    logic [ROW_WIDTH-1:0] ref_rd_row;
    logic [COL_WIDTH-1:0] ref_rd_col;

    addr_mapper_ddr5 #(
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_QOS_WIDTH  (AXI_QOS_WIDTH),
        .ROW_WIDTH      (ROW_WIDTH),
        .COL_WIDTH      (COL_WIDTH),
        .BG_WIDTH       (BG_WIDTH),
        .BANK_WIDTH     (BANK_WIDTH)
    ) u_ref_mapper_rd (
        .clk                  (clk_axi),
        .rst_n                (aresetn_axi),
        .cfg_is_ddr5          (cfg_is_ddr5),
        .cfg_bank_coloring_en (1'b0),
        .cfg_mapping_mode     (2'b00),
        .cfg_scramble_en      (1'b1),
        .cfg_scramble_mode    (2'b10),
        .cfg_scramble_seed    (64'hA5A5_5A5A_0123_4567),
        .i_req_valid          (s_axi_arvalid && s_axi_arready),
        .o_req_ready          (),
        .i_req_id             (s_axi_arid),
        .i_req_tenant         (s_axi_arid),
        .i_req_is_write       (1'b0),
        .i_req_addr           (s_axi_araddr),
        .i_req_len            (s_axi_arlen),
        .i_req_qos            (s_axi_arqos),
        .o_cmd_valid          (ref_rd_valid),
        .i_cmd_ready          (1'b1),
        .o_cmd_id             (),
        .o_cmd_is_write       (),
        .o_cmd_bg             (ref_rd_bg),
        .o_cmd_bank           (ref_rd_bank),
        .o_cmd_row            (ref_rd_row),
        .o_cmd_col            (ref_rd_col),
        .o_cmd_len            (),
        .o_cmd_qos            (),
        .o_busy               ()
    );

    localparam int SB_TUPLE_W  = BG_WIDTH + BANK_WIDTH + ROW_WIDTH + COL_WIDTH;
    localparam int SB_MAX_PEND = 128;

    logic [SB_TUPLE_W-1:0] sb_wr_pool [SB_MAX_PEND];
    bit                    sb_wr_vld  [SB_MAX_PEND];
    logic [SB_TUPLE_W-1:0] sb_rd_pool [SB_MAX_PEND];
    bit                    sb_rd_vld  [SB_MAX_PEND];
    logic [ROW_WIDTH-1:0]  sb_open_row [BG_COUNT][BANK_COUNT];
    bit                    sb_row_open [BG_COUNT][BANK_COUNT];

    int sb_wr_matched = 0;
    int sb_wr_mismatch = 0;
    int sb_wr_pend_cnt = 0;
    int sb_rd_matched = 0;
    int sb_rd_mismatch = 0;
    int sb_rd_pend_cnt = 0;
    int b_done_cnt = 0;
    int r_beats_cnt = 0;
    bit sb_enable = 1'b1;

    logic [31:0] rready_lfsr = 32'hA5A5_1357;

    always @(posedge clk_axi or negedge aresetn_axi) begin
        if (!aresetn_axi) begin
            for (int i = 0; i < SB_MAX_PEND; i++) begin
                sb_wr_vld[i] = 1'b0;
                sb_rd_vld[i] = 1'b0;
            end
            for (int g = 0; g < BG_COUNT; g++) begin
                for (int b = 0; b < BANK_COUNT; b++) begin
                    sb_row_open[g][b] = 1'b0;
                    sb_open_row[g][b] = '0;
                end
            end
            sb_wr_pend_cnt = 0;
            sb_rd_pend_cnt = 0;
            rready_lfsr   <= 32'hA5A5_1357;
            s_axi_rready  <= 1'b1;
        end else begin
            if (RANDOM_RREADY || $test$plusargs("RANDOM_RREADY")) begin
                rready_lfsr  <= {rready_lfsr[30:0], rready_lfsr[31] ^ rready_lfsr[21] ^ rready_lfsr[1] ^ rready_lfsr[0]};
                s_axi_rready <= rready_lfsr[0];
            end else begin
                s_axi_rready <= 1'b1;
            end

            if (dfi_cmd == 3'b100) dfi_wr_cnt++;
            if (s_axi_bvalid && s_axi_bready) begin
                last_bid   <= s_axi_bid;
                last_bresp <= s_axi_bresp;
                b_done_cnt++;
            end
            // Gán blocking cùng thứ tự với r_bursts++: luồng chờ thức dậy cùng timestep phải thấy ID/dữ liệu mới
            if (s_axi_rvalid && s_axi_rready) begin
                last_rdata = s_axi_rdata;
                last_rid   = s_axi_rid;
                r_beats_cnt++;
                if (s_axi_rlast) r_bursts++;
            end

            if (sb_enable) begin
                if (ref_wr_valid) begin
                    bit placed;
                    placed = 1'b0;
                    for (int i = 0; i < SB_MAX_PEND; i++) begin
                        if (!placed && !sb_wr_vld[i]) begin
                            sb_wr_vld[i]  = 1'b1;
                            sb_wr_pool[i] = {ref_wr_bg, ref_wr_bank, ref_wr_row, ref_wr_col};
                            sb_wr_pend_cnt++;
                            placed = 1'b1;
                        end
                    end
                end
                if (ref_rd_valid) begin
                    bit placed;
                    placed = 1'b0;
                    for (int i = 0; i < SB_MAX_PEND; i++) begin
                        if (!placed && !sb_rd_vld[i]) begin
                            sb_rd_vld[i]  = 1'b1;
                            sb_rd_pool[i] = {ref_rd_bg, ref_rd_bank, ref_rd_row, ref_rd_col};
                            sb_rd_pend_cnt++;
                            placed = 1'b1;
                        end
                    end
                end

                if (dfi_cmd == 3'b001) begin
                    sb_row_open[dfi_bg][dfi_bank] = 1'b1;
                    sb_open_row[dfi_bg][dfi_bank] = dfi_row;
                end else if (dfi_cmd == 3'b010) begin
                    sb_row_open[dfi_bg][dfi_bank] = 1'b0;
                end else if (dfi_cmd == 3'b101 || dfi_cmd == 3'b110) begin
                    for (int g = 0; g < BG_COUNT; g++)
                        for (int b = 0; b < BANK_COUNT; b++)
                            sb_row_open[g][b] = 1'b0;
                end

                if (dfi_cmd == 3'b100) begin
                    logic [SB_TUPLE_W-1:0] actual_tuple;
                    bit matched;
                    actual_tuple = {dfi_bg, dfi_bank, sb_open_row[dfi_bg][dfi_bank], dfi_col};
                    matched = 1'b0;
                    if (sb_row_open[dfi_bg][dfi_bank] && (sb_open_row[dfi_bg][dfi_bank] === dfi_row)) begin
                        for (int i = 0; i < SB_MAX_PEND; i++) begin
                            if (!matched && sb_wr_vld[i] && (sb_wr_pool[i] === actual_tuple)) begin
                                sb_wr_vld[i] = 1'b0;
                                sb_wr_pend_cnt--;
                                sb_wr_matched++;
                                matched = 1'b1;
                            end
                        end
                    end
                    if (!matched) sb_wr_mismatch++;
                end

                if (dfi_cmd == 3'b011) begin
                    logic [SB_TUPLE_W-1:0] actual_tuple;
                    bit matched;
                    actual_tuple = {dfi_bg, dfi_bank, sb_open_row[dfi_bg][dfi_bank], dfi_col};
                    matched = 1'b0;
                    if (sb_row_open[dfi_bg][dfi_bank] && (sb_open_row[dfi_bg][dfi_bank] === dfi_row)) begin
                        for (int i = 0; i < SB_MAX_PEND; i++) begin
                            if (!matched && sb_rd_vld[i] && (sb_rd_pool[i] === actual_tuple)) begin
                                sb_rd_vld[i] = 1'b0;
                                sb_rd_pend_cnt--;
                                sb_rd_matched++;
                                matched = 1'b1;
                            end
                        end
                    end
                    if (!matched) sb_rd_mismatch++;
                end
            end
        end
    end

    function automatic logic [31:0] make_seeded_addr(input logic [31:0] rng, input int txn_idx);
        logic [2:0]  target_bg;
        logic [1:0]  target_bank;
        logic [13:0] target_row;
        logic [6:0]  target_col_hi;
        logic [2:0]  addr_8_6;
        int          epoch;
        logic [31:0] row_calc;
        epoch         = txn_idx >> 7;
        target_bg     = rng[2:0];
        target_bank   = epoch[1:0] ^ target_bg[1:0];
        row_calc      = (epoch * 17) + 32;
        target_row    = row_calc[13:0];
        target_col_hi = {txn_idx[0], rng[10:5]};
        addr_8_6      = target_bg ^ target_row[2:0];
        return {target_row, target_bank, target_col_hi, addr_8_6, 6'b000000};
    endfunction

    // Helper task: AXI4 write burst
    task automatic axi_write(
        input logic [AXI_ID_WIDTH-1:0]   id,
        input logic [AXI_ADDR_WIDTH-1:0] addr,
        input logic [AXI_DATA_WIDTH-1:0] data
    );
        @(negedge clk_axi);
        s_axi_awid    <= id;
        s_axi_awaddr  <= addr;
        s_axi_awlen   <= 8'd0; // 1 beat
        s_axi_awsize  <= 3'b011; // 8 bytes
        s_axi_awburst <= 2'b01; // INCR
        s_axi_awqos   <= 4'd2;
        s_axi_awvalid <= 1'b1;

        s_axi_wdata   <= data;
        s_axi_wstrb   <= 8'hFF;
        s_axi_wlast   <= 1'b1;
        s_axi_wvalid  <= 1'b1;
        s_axi_bready  <= 1'b1;

        fork
            begin
                while (!s_axi_awready) @(posedge clk_axi);
                @(negedge clk_axi);
                s_axi_awvalid <= 1'b0;
            end
            begin
                while (!s_axi_wready) @(posedge clk_axi);
                @(negedge clk_axi);
                s_axi_wvalid <= 1'b0;
            end
        join

        // Wait for B response
        while (!s_axi_bvalid) @(posedge clk_axi);
        @(posedge clk_axi);
        @(negedge clk_axi);
        s_axi_bready <= 1'b0;
    endtask

    // Helper task: AXI4 read request
    task automatic axi_read(
        input logic [AXI_ID_WIDTH-1:0]   id,
        input logic [AXI_ADDR_WIDTH-1:0] addr
    );
        @(negedge clk_axi);
        s_axi_arid    <= id;
        s_axi_araddr  <= addr;
        s_axi_arlen   <= 8'd0;
        s_axi_arsize  <= 3'b011;
        s_axi_arburst <= 2'b01;
        s_axi_arqos   <= 4'd2;
        s_axi_arvalid <= 1'b1;

        while (!s_axi_arready) @(posedge clk_axi);
        @(negedge clk_axi);
        s_axi_arvalid <= 1'b0;
    endtask

    // Main Test Sequence
    initial begin
        $display("================================================================");
        $display("  Q-SHIELD AXI_DDR5_MC_TOP INTEGRATION TESTBENCH");
        $display("  Verifying Top 5 SOTA Upgrades in Unified Memory Controller");
        $display("================================================================");

        // Initialize signals
        aresetn_axi      = 0;
        aresetn_ddr      = 0;
        s_axi_awid       = '0;
        s_axi_awaddr     = '0;
        s_axi_awlen      = '0;
        s_axi_awsize     = '0;
        s_axi_awburst    = '0;
        s_axi_awqos      = '0;
        s_axi_awvalid    = 0;
        s_axi_wdata      = '0;
        s_axi_wstrb      = '0;
        s_axi_wlast      = 0;
        s_axi_wvalid     = 0;
        s_axi_bready     = 0;
        s_axi_arid       = '0;
        s_axi_araddr     = '0;
        s_axi_arlen      = '0;
        s_axi_arsize     = '0;
        s_axi_arburst    = '0;
        s_axi_arqos      = '0;
        s_axi_arvalid    = 0;
        s_axi_rready     = 1;
        cfg_is_ddr5      = 1;
        cfg_dual_hash_en = 1;
        cfg_rh_threshold = 16'd50;
        cfg_window_size  = 16'd1000;

        // Reset sequence (assert for 10 cycles)
        repeat (10) @(posedge clk_axi);
        @(negedge clk_axi);
        aresetn_axi = 1;
        aresetn_ddr = 1;

        repeat (10) @(posedge clk_axi);

        //---------------------------------------------------------------------
        // TEST 1: Power-On Initialization & Ready Handshake
        //---------------------------------------------------------------------
        $display("[TEST 1] Power-On Initialization & Frontend Ready Verification");
        if (s_axi_awready && s_axi_arready) begin
            $display("[PASS] TEST 1: Frontend initialized with AWREADY=1 and ARREADY=1");
            test_passed++;
        end else begin
            $display("[FAIL] TEST 1: AWREADY=%b, ARREADY=%b (Expected 1, 1)", s_axi_awready, s_axi_arready);
            test_failed++;
        end

        //---------------------------------------------------------------------
        // TEST 2: AXI4 Write Burst & DFI Command Generation
        //---------------------------------------------------------------------
        $display("[TEST 2] AXI4 Single Write Transaction -> DFI Command Generation");
        axi_write(4'h1, 32'h0001_2040, 64'hDEAD_BEEF_CAFE_0001);

        // Allow command engine to process and issue ACT/WR on DFI
        repeat (40) @(posedge clk_axi);
        tb_check(last_bid == 4'h1 && last_bresp == 2'b00,
                 $sformatf("TEST 2: write response BID=%0h BRESP=%0d (expected 1, OKAY)", last_bid, last_bresp));
        tb_check(dfi_wr_cnt == 1, $sformatf("TEST 2: exactly one DFI WR command issued (%0d)", dfi_wr_cnt));

        //---------------------------------------------------------------------
        // TEST 3: Adaptive Threshold Engine (ATE) Dynamic Threshold Operation
        //---------------------------------------------------------------------
        $display("[TEST 3] ATE Telemetry & Dynamic Threshold Stability");
        // Verify ATE initialized properly and is outputting valid threshold
        if (dut.u_ate.o_dynamic_thresh == cfg_rh_threshold) begin
            $display("[PASS] TEST 3: ATE dynamically regulating threshold (Current: %0d)", dut.u_ate.o_dynamic_thresh);
            test_passed++;
        end else begin
            $display("[FAIL] TEST 3: Unexpected ATE dynamic threshold: %0d", dut.u_ate.o_dynamic_thresh);
            test_failed++;
        end

        //---------------------------------------------------------------------
        // TEST 4: Directed Refresh Manager (DRM) Integration & Ref Count
        //---------------------------------------------------------------------
        $display("[TEST 4] Directed Refresh Manager (DRM) & Arbiter Mitigation Interconnect");
        // Check that DRM is enabled and ready to receive aggressor notifications
        if (dut.u_drm.cfg_drm_en == 1'b1 && dut.u_drm.o_mitigation_req == 1'b0) begin
            $display("[PASS] TEST 4: DRM idle and listening for RowHammer/RowPress alerts");
            test_passed++;
        end else begin
            $display("[FAIL] TEST 4: DRM misconfigured (en=%b, req=%b)", dut.u_drm.cfg_drm_en, dut.u_drm.o_mitigation_req);
            test_failed++;
        end

        //---------------------------------------------------------------------
        // TEST 5: Write-Drain Mode Under Burst Traffic
        //---------------------------------------------------------------------
        $display("[TEST 5] Write-Drain Scheduler Activation Under Write Pressure");
        // Dispatch multiple writes in rapid succession to increase eligible write count
        begin
            int wr0;
            int bad_b;
            wr0   = dfi_wr_cnt;
            bad_b = 0;
            for (int i = 0; i < 6; i++) begin
                axi_write(4'h2 + i[3:0], 32'h0002_0000 + (i << 6), 64'h1122_3344_5566_7788 + i);
                if (last_bid != 4'h2 + i[3:0] || last_bresp != 2'b00) bad_b++;
            end
            repeat (60) @(posedge clk_axi);
            tb_check(bad_b == 0, $sformatf("TEST 5: all 6 write responses carry matching BID and OKAY (%0d bad)", bad_b));
            tb_check(dfi_wr_cnt - wr0 == 6, $sformatf("TEST 5: 6 DFI WR commands issued (%0d)", dfi_wr_cnt - wr0));
        end

        //---------------------------------------------------------------------
        // TEST 6: End-to-End RowHammer SDC Defense & Throttling Telemetry
        //---------------------------------------------------------------------
        $display("[TEST 6] RowHammer SDC Defense: Blasting Target Row > Threshold");
        cfg_rh_threshold = 16'd4;
        cfg_window_size  = 16'd1000;
        repeat (5) @(posedge clk_axi);

        for (int i = 0; i < 8; i++) begin
            axi_read(4'h1 + i[3:0], 32'h0005_0000);
            repeat (2) @(posedge clk_axi);
        end

        repeat (30) @(posedge clk_axi);

        if (o_throttled_events > 0) begin
            $display("[PASS] TEST 6: Observed %0d throttled events (Expected > 0)", o_throttled_events);
            test_passed++;
        end else begin
            $display("[FAIL] TEST 6: Expected throttled events > 0, got %0d", o_throttled_events);
            test_failed++;
        end

        //---------------------------------------------------------------------
        // TEST 7: Ghi rồi đọc lại phải trả đúng dữ liệu đã ghi (toàn vẹn end-to-end)
        //---------------------------------------------------------------------
        $display("[TEST 7] End-to-end write then read-back");
        cfg_rh_threshold = 16'd50;
        repeat (1100) @(posedge clk_axi);
        begin
            int rb0;
            axi_write(4'h9, 32'h0040_1000, 64'h0123_4567_89AB_CDEF);
            rb0 = r_bursts;
            axi_read(4'h9, 32'h0040_1000);
            for (int c = 0; c < 300 && r_bursts == rb0; c++) @(posedge clk_axi);
            repeat (2) @(posedge clk_axi);
            tb_check(r_bursts > rb0 && last_rid == 4'h9, $sformatf("TEST 7: read-back completed with RID=%0h", last_rid));
            tb_check(last_rdata === 64'h0123_4567_89AB_CDEF,
                     $sformatf("TEST 7: read-back data %h equals written 0123456789abcdef", last_rdata));
        end

        //---------------------------------------------------------------------
        // TEST 8: 1000 giao dịch ngẫu nhiên có seed (C-3 DFI address scoreboard + C-4 read liveness)
        //---------------------------------------------------------------------
        $display("[TEST 8] 1000 Seeded Random Transactions (DFI Address Scoreboard vs addr_mapper_ddr5 & Read Liveness)");
        begin
            logic [31:0] prng;
            int wr0_match, rd0_match, b0_cnt, rb0_cnt;
            int wr_sent, rd_sent;
            repeat (40) @(posedge clk_axi);
            prng      = 32'h2026_1107;
            wr0_match = sb_wr_matched;
            rd0_match = sb_rd_matched;
            b0_cnt    = b_done_cnt;
            rb0_cnt   = r_bursts;
            wr_sent   = 0;
            rd_sent   = 0;
            s_axi_bready <= 1'b1;

            for (int t = 0; t < 1000; t++) begin
                logic [31:0] tx_addr;
                logic [3:0]  tx_id;
                bit          do_wr;

                prng    = {prng[30:0], prng[31] ^ prng[21] ^ prng[1] ^ prng[0]};
                tx_addr = make_seeded_addr(prng, t);
                tx_id   = prng[15:12];

                if (wr_sent == 500)
                    do_wr = 1'b0;
                else if (rd_sent == 500)
                    do_wr = 1'b1;
                else
                    do_wr = ~t[0];

                while ((wr_sent - (b_done_cnt - b0_cnt)) >= 8 || (rd_sent - (r_bursts - rb0_cnt)) >= 8)
                    @(posedge clk_axi);

                if (do_wr) begin
                    @(negedge clk_axi);
                    s_axi_awid    <= tx_id;
                    s_axi_awaddr  <= tx_addr;
                    s_axi_awlen   <= 8'd0;
                    s_axi_awsize  <= 3'b011;
                    s_axi_awburst <= 2'b01;
                    s_axi_awqos   <= 4'd2;
                    s_axi_awvalid <= 1'b1;
                    s_axi_wdata   <= {prng, 32'(t)};
                    s_axi_wstrb   <= 8'hFF;
                    s_axi_wlast   <= 1'b1;
                    s_axi_wvalid  <= 1'b1;
                    fork
                        begin
                            while (!s_axi_awready) @(posedge clk_axi);
                            @(negedge clk_axi);
                            s_axi_awvalid <= 1'b0;
                        end
                        begin
                            while (!s_axi_wready) @(posedge clk_axi);
                            @(negedge clk_axi);
                            s_axi_wvalid <= 1'b0;
                            s_axi_wlast  <= 1'b0;
                        end
                    join
                    wr_sent++;
                end else begin
                    @(negedge clk_axi);
                    s_axi_arid    <= tx_id;
                    s_axi_araddr  <= tx_addr;
                    s_axi_arlen   <= 8'd0;
                    s_axi_arsize  <= 3'b011;
                    s_axi_arburst <= 2'b01;
                    s_axi_arqos   <= 4'd2;
                    s_axi_arvalid <= 1'b1;
                    while (!s_axi_arready) @(posedge clk_axi);
                    @(negedge clk_axi);
                    s_axi_arvalid <= 1'b0;
                    rd_sent++;
                end
            end

            for (int c = 0; c < 3000; c++) begin
                if ((b_done_cnt - b0_cnt) == 500 && (r_bursts - rb0_cnt) == 500 &&
                    (sb_wr_matched - wr0_match) == 500 && (sb_rd_matched - rd0_match) == 500)
                    c = 3000;
                else
                    @(posedge clk_axi);
            end
            repeat (20) @(posedge clk_axi);

            tb_check((sb_wr_matched - wr0_match) == 500 && (sb_rd_matched - rd0_match) == 500 &&
                     sb_wr_mismatch == 0 && sb_rd_mismatch == 0 && sb_wr_pend_cnt == 0 && sb_rd_pend_cnt == 0,
                     $sformatf("TEST 8 (C-3): 1000/1000 DFI (bg,bank,row,col) matched addr_mapper_ddr5 (WR=%0d RD=%0d mis=%0d/%0d)",
                               sb_wr_matched - wr0_match, sb_rd_matched - rd0_match, sb_wr_mismatch, sb_rd_mismatch));
            tb_check((b_done_cnt - b0_cnt) == 500 && (r_bursts - rb0_cnt) == 500,
                     $sformatf("TEST 8 (C-4): all 500 writes and 500 reads completed with BVALID/RVALID+RLAST without hang (WR=%0d RD=%0d)",
                               b_done_cnt - b0_cnt, r_bursts - rb0_cnt));
        end

        //---------------------------------------------------------------------
        // TEST 9: Reset giữa burst không để lại entry ma ở FIFO/ROB (H-1 / L-2)
        //---------------------------------------------------------------------
        $display("[TEST 9] Mid-Burst Reset Cleanliness (No Phantom FIFO/ROB Entries)");
        begin
            int rb_post;
            sb_enable = 1'b0;
            @(negedge clk_axi);
            s_axi_awid    <= 4'hA;
            s_axi_awaddr  <= 32'h0048_1000;
            s_axi_awlen   <= 8'd7;
            s_axi_awvalid <= 1'b1;
            while (!s_axi_awready) @(posedge clk_axi);
            @(negedge clk_axi);
            s_axi_awvalid <= 1'b0;

            for (int b = 0; b < 3; b++) begin
                s_axi_wdata  <= 64'hBAD0_0000_0000_0000 | 64'(b);
                s_axi_wstrb  <= 8'hFF;
                s_axi_wlast  <= 1'b0;
                s_axi_wvalid <= 1'b1;
                while (!s_axi_wready) @(posedge clk_axi);
                @(negedge clk_axi);
            end
            s_axi_wvalid <= 1'b0;

            axi_read(4'hB, 32'h0049_0000);
            axi_read(4'hC, 32'h0049_0040);

            @(negedge clk_axi);
            aresetn_axi = 1'b0;
            aresetn_ddr = 1'b0;
            repeat (5) @(posedge clk_axi);
            @(negedge clk_axi);
            aresetn_axi = 1'b1;
            aresetn_ddr = 1'b1;
            repeat (10) @(posedge clk_axi);

            tb_check(dut.u_rob.o_rob_empty === 1'b1 && dut.u_rob.o_rob_count === '0 &&
                     dut.u_wdata_buffer.o_cmd_valid === 1'b0 && dut.u_wds.slot_busy === '0 &&
                     dut.u_rd_iq.o_empty === 1'b1 && dut.u_qos_queue.o_cand_valid === '0 &&
                     s_axi_bvalid === 1'b0 && s_axi_rvalid === 1'b0,
                     "TEST 9 (H-1): zero phantom entries in ROB/FIFO/WDS/IQ/QoS queue after mid-burst reset");

            sb_enable = 1'b1;
            axi_write(4'h6, 32'h0050_2000, 64'hCAFE_BABE_1234_5678);
            rb_post = r_bursts;
            axi_read(4'h6, 32'h0050_2000);
            for (int c = 0; c < 300 && r_bursts == rb_post; c++) @(posedge clk_axi);
            repeat (10) @(posedge clk_axi);
            tb_check(r_bursts > rb_post && last_rid == 4'h6 && last_rdata === 64'hCAFE_BABE_1234_5678,
                     $sformatf("TEST 9 (H-1): post-reset write+read recovered cleanly (RID=%0h RDATA=%h)", last_rid, last_rdata));
        end

        //---------------------------------------------------------------------
        // Summary
        //---------------------------------------------------------------------
        $display("\n================================================================");
        $display("  Q-SHIELD INTEGRATION REGRESSION SUMMARY");
        $display("  Passed: %0d / %0d", test_passed, (test_passed + test_failed));
        $display("  Failed: %0d / %0d", test_failed, (test_passed + test_failed));
        $display("================================================================");

        tb_merge_legacy(test_passed + test_failed, test_failed);
        u_jchk.report("integration");
        u_achk.final_check();
        u_echk.final_check();
        u_achk.report("integration");
        u_echk.report("integration");
        u_pchk.report("integration");
        tb_check(u_jchk.timing_violations() == 0 && u_jchk.viol_ref_open == 0,
                 $sformatf("JEDEC timing: no tRCD/tRP/tRAS/tRFC/bank-state violations on DFI (%0d timing, %0d REF/RFM-open)",
                           u_jchk.timing_violations(), u_jchk.viol_ref_open));
        if (u_jchk.cyc_total > 5 * u_jchk.REFI_CYC)
            tb_check(u_jchk.refresh_ok(),
                     $sformatf("Periodic refresh: REF interval <= 5 x tREFI (worst %0d cycles)", u_jchk.worst_ref_gap()));
        tb_check(u_achk.errors() == 0, $sformatf("qs_axi_txn_chk zero errors (%0d)", u_achk.errors()));
        tb_check(u_echk.errors() == 0, $sformatf("qs_engine_port_chk zero errors (%0d)", u_echk.errors()));
        tb_check(u_pchk.errors() == 0, $sformatf("qs_top_probe_chk zero errors (%0d)", u_pchk.errors()));
        tb_report();
        $finish;
    end

    // Simulation watchdog (50 us timeout)
    initial begin
        #200_000;
        $fatal(1, "[WATCHDOG TIMEOUT] Simulation exceeded maximum duration.");
    end

endmodule
