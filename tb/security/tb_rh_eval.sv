// File:      tb_rh_eval.sv
// Chức năng: Testbench đánh giá bảo mật RowHammer/RowPress trên RTL axi_ddr5_mc_top và đo tách va chạm bin R-82.
`timescale 1ns / 1ps

module tb_rh_eval #(
    parameter int RH_RADIUS = 2
);
    `include "tb_check.svh"

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
    localparam int TCK_PS         = 2500;
    localparam int DFI_WRLAT      = 9;
    localparam int DFI_RDLAT      = 8;

    localparam logic [ROW_WIDTH-1:0] VICTIM_BASE = 17'h00100;
    localparam int MAX_WATCH = 80;
    localparam int WATCH_LO  = 17'h000FC;

    // 400 MHz đồng bộ đơn miền clock theo thiết kế lõi chuẩn
    logic clk_axi = 1'b0;
    always #1.25 clk_axi = ~clk_axi;

    logic aresetn_axi;

    // Giao diện AXI4
    logic [AXI_ID_WIDTH-1:0]   s_axi_awid    = 4'd0;
    logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr  = 32'd0;
    logic [AXI_LEN_WIDTH-1:0]  s_axi_awlen   = 8'd0;
    logic [2:0]                s_axi_awsize  = 3'b011;
    logic [1:0]                s_axi_awburst = 2'b01;
    logic [AXI_QOS_WIDTH-1:0]  s_axi_awqos   = 4'd0;
    logic                      s_axi_awvalid = 1'b0;
    logic                      s_axi_awready;

    logic [AXI_DATA_WIDTH-1:0] s_axi_wdata   = 64'd0;
    logic [AXI_STRB_WIDTH-1:0] s_axi_wstrb   = 8'hFF;
    logic                      s_axi_wlast   = 1'b0;
    logic                      s_axi_wvalid  = 1'b0;
    logic                      s_axi_wready;

    logic [AXI_ID_WIDTH-1:0]   s_axi_bid;
    logic [1:0]                s_axi_bresp;
    logic                      s_axi_bvalid;
    logic                      s_axi_bready  = 1'b1;

    logic [AXI_ID_WIDTH-1:0]   s_axi_arid    = 4'd0;
    logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr  = 32'd0;
    logic [AXI_LEN_WIDTH-1:0]  s_axi_arlen   = 8'd0;
    logic [2:0]                s_axi_arsize  = 3'b011;
    logic [1:0]                s_axi_arburst = 2'b01;
    logic [AXI_QOS_WIDTH-1:0]  s_axi_arqos   = 4'd0;
    logic                      s_axi_arvalid = 1'b0;
    logic                      s_axi_arready;

    logic [AXI_ID_WIDTH-1:0]   s_axi_rid;
    logic [AXI_DATA_WIDTH-1:0] s_axi_rdata;
    logic [1:0]                s_axi_rresp;
    logic                      s_axi_rlast;
    logic                      s_axi_rvalid;
    logic                      s_axi_rready  = 1'b1;

    // Giao diện DFI 5.0
    logic [2:0]                dfi_cmd;
    logic [BG_WIDTH-1:0]       dfi_bg;
    logic [BANK_WIDTH-1:0]     dfi_bank;
    logic [ROW_WIDTH-1:0]      dfi_row;
    logic [COL_WIDTH-1:0]      dfi_col;
    logic [7:0]                dfi_len;
    logic                      dfi_wrdata_en;
    logic [AXI_DATA_WIDTH-1:0] dfi_wrdata;
    logic [7:0]                dfi_wrdata_mask;
    logic [7:0]                dfi_wrdata_ecc;
    logic                      dfi_rddata_valid;
    logic [AXI_DATA_WIDTH-1:0] dfi_rddata;
    logic [7:0]                dfi_rddata_ecc;

    // Tham số cấu hình runtime từ plusargs số nguyên
    int        p_case_id  = 2;
    int        p_nrh      = 128;
    int        p_thresh   = 16;
    int        p_n_agg    = 8;
    int        p_benign   = 1;
    int        p_rp_curve = 3;
    int        p_rp_hold  = 850;
    int        p_waves    = 4;
    int        p_dummy_m  = 128;
    int        p_max_cyc  = 400000;
    bit [31:0] p_seed_hi  = 32'hA5A5_5A5A;
    bit [31:0] p_seed_lo  = 32'h0123_4567;
    int        p_da_bg    = 1;
    int        p_da_bk    = 1;
    int        p_da_row   = 1024;
    int        p_db_bg    = 1;
    int        p_db_bk    = 2;
    int        p_db_row   = 1025;
    int        p_far_row  = 768;
    int        p_force_vic3_en = -1;
    int        p_ignore_mit_act = 0;
    int        p_dummy_banks = 1;
    int        p_diag_dump = 0;

    logic [15:0] cfg_rh_threshold;
    logic [1:0]  cfg_rowpress_curve;
    logic [63:0] cfg_scramble_seed;
    logic        cfg_victim3_en;
    logic [15:0] o_throttled_events, o_ecc_single_err_cnt, o_ecc_double_err_cnt;
    logic [7:0][31:0] o_pmu_counters;
    logic [15:0] o_abo_alert_cnt, o_ecc_miscorrect_cnt, o_rfm_auto_cnt, o_decoy_cnt;
    logic [8:0]  o_fault_cause;
    logic        o_coordinated_throttle_active, o_tras_clamped_alert, o_decoy_active, o_glitch_alert, o_security_locked;
    logic        o_parity_err, o_rob_raw_hazard;

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
        .TCK_PS         (TCK_PS)
    ) dut (
        .clk_axi                      (clk_axi),
        .aresetn_axi                  (aresetn_axi),
        .clk_ddr                      (clk_axi),
        .aresetn_ddr                  (aresetn_axi),

        .s_axi_awid                   (s_axi_awid),
        .s_axi_awaddr                 (s_axi_awaddr),
        .s_axi_awlen                  (s_axi_awlen),
        .s_axi_awsize                 (s_axi_awsize),
        .s_axi_awburst                (s_axi_awburst),
        .s_axi_awqos                  (s_axi_awqos),
        .s_axi_awvalid                (s_axi_awvalid),
        .s_axi_awready                (s_axi_awready),

        .s_axi_wdata                  (s_axi_wdata),
        .s_axi_wstrb                  (s_axi_wstrb),
        .s_axi_wlast                  (s_axi_wlast),
        .s_axi_wvalid                 (s_axi_wvalid),
        .s_axi_wready                 (s_axi_wready),

        .s_axi_bid                    (s_axi_bid),
        .s_axi_bresp                  (s_axi_bresp),
        .s_axi_bvalid                 (s_axi_bvalid),
        .s_axi_bready                 (s_axi_bready),

        .s_axi_arid                   (s_axi_arid),
        .s_axi_araddr                 (s_axi_araddr),
        .s_axi_arlen                  (s_axi_arlen),
        .s_axi_arsize                 (s_axi_arsize),
        .s_axi_arburst                (s_axi_arburst),
        .s_axi_arqos                  (s_axi_arqos),
        .s_axi_arvalid                (s_axi_arvalid),
        .s_axi_arready                (s_axi_arready),

        .s_axi_rid                    (s_axi_rid),
        .s_axi_rdata                  (s_axi_rdata),
        .s_axi_rresp                  (s_axi_rresp),
        .s_axi_rlast                  (s_axi_rlast),
        .s_axi_rvalid                 (s_axi_rvalid),
        .s_axi_rready                 (s_axi_rready),
        .s_axi_rpoison                (),
        .s_axi_rchk                   (),
        .o_parity_err                 (o_parity_err),

        .dfi_cmd                      (dfi_cmd),
        .dfi_bg                       (dfi_bg),
        .dfi_bank                     (dfi_bank),
        .dfi_row                      (dfi_row),
        .dfi_col                      (dfi_col),
        .dfi_len                      (dfi_len),
        .dfi_wrdata_en                (dfi_wrdata_en),
        .dfi_wrdata                   (dfi_wrdata),
        .dfi_wrdata_mask              (dfi_wrdata_mask),
        .dfi_wrdata_ecc               (dfi_wrdata_ecc),
        .dfi_rddata_valid             (dfi_rddata_valid),
        .dfi_rddata                   (dfi_rddata),
        .dfi_rddata_ecc               (dfi_rddata_ecc),

        .cfg_is_ddr5                  (1'b1),
        .cfg_dual_hash_en             (1'b1),
        .cfg_rh_threshold             (cfg_rh_threshold),
        .cfg_window_size              (16'd60000),
        .o_throttled_events           (o_throttled_events),
        .o_ecc_single_err_cnt         (o_ecc_single_err_cnt),
        .o_ecc_double_err_cnt         (o_ecc_double_err_cnt),

        .cfg_bank_coloring_en         (1'b0),
        .cfg_mapping_mode             (2'b00),
        .cfg_scramble_en              (1'b0),
        .cfg_scramble_reseed          (1'b0),
        .cfg_scramble_seed            (cfg_scramble_seed),
        .cfg_pmu_en                   (1'b1),
        .cfg_pmu_reset                (1'b0),
        .o_pmu_counters               (o_pmu_counters),

        .cfg_rowpress_curve           (cfg_rowpress_curve),
        .cfg_victim3_en               (cfg_victim3_en),
        .i_dram_abo_alert             (1'b0),
        .o_abo_alert_cnt              (o_abo_alert_cnt),
        .o_ecc_miscorrect_cnt         (o_ecc_miscorrect_cnt),
        .o_coordinated_throttle_active(o_coordinated_throttle_active),
        .o_rfm_auto_cnt               (o_rfm_auto_cnt),
        .o_tras_clamped_alert         (o_tras_clamped_alert),

        .cfg_scramble_mode            (2'b00),
        .cfg_decoy_en                 (1'b0),
        .cfg_fault_clr                (1'b0),
        .o_decoy_active               (o_decoy_active),
        .o_decoy_cnt                  (o_decoy_cnt),
        .o_fault_cause                (o_fault_cause),
        .o_glitch_alert               (o_glitch_alert),
        .o_security_locked            (o_security_locked),
        .cfg_parity_check_en          (1'b0),
        .o_rob_raw_hazard             (o_rob_raw_hazard)
    );

    dram_model #(
        .COL_W        (COL_WIDTH),
        .RL           (DFI_RDLAT),
        .WL           (DFI_WRLAT),
        .TRACK_RH     (1'b1),
        .RH_RADIUS    (RH_RADIUS),
        .RH_W1        (1),
        .RH_W2        (1),
        .RH_W3        (1),
        .RH_TABLE_LOG (14)
    ) u_dram (
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
        .wrdata_mask  (dfi_wrdata_mask),
        .wrdata_ecc   (dfi_wrdata_ecc),
        .rddata_valid (dfi_rddata_valid),
        .rddata       (dfi_rddata),
        .rddata_ecc   (dfi_rddata_ecc)
    );

    always @(*) u_dram.rh_cur_act_is_mit = dut.u_cmd_engine.dfi_act_mit;

    dfi_jedec_checker #(
        .TCK_PS       (TCK_PS),
        .TB_DFI_WRLAT (DFI_WRLAT)
    ) u_jchk (
        .clk   (clk_axi),
        .rst_n (aresetn_axi),
        .cmd   (dfi_cmd),
        .bg    (dfi_bg),
        .bank  (dfi_bank),
        .row   (dfi_row),
        .len   (dfi_len)
    );

    // Kiểm tra đối chiếu hash PXOR cho kịch bản va chạm biết seed (CASE_ID=8)
    wire [21:0] px_tag_va = {3'd0, 2'd0, 17'(VICTIM_BASE - 17'd1)};
    wire [21:0] px_tag_vb = {3'd0, 2'd0, 17'(VICTIM_BASE + 17'd1)};
    wire [21:0] px_tag_da = {3'(p_da_bg), 2'(p_da_bk), 17'(p_da_row)};
    wire [21:0] px_tag_db = {3'(p_db_bg), 2'(p_db_bk), 17'(p_db_row)};
    wire [63:0] px_seed_b = ~cfg_scramble_seed ^ 64'hF0F0_0F0F_AAAA_5555;
    wire [7:0]  px_ha_va, px_hb_va, px_ha_da, px_hb_da;
    wire [7:0]  px_ha_vb, px_hb_vb, px_ha_db, px_hb_db;

    pxor_hash_engine #(.TAG_WIDTH(22), .HASH_WIDTH(8)) u_chk_ha_va (.i_tag(px_tag_va), .i_seed(cfg_scramble_seed), .o_hash(px_ha_va));
    pxor_hash_engine #(.TAG_WIDTH(22), .HASH_WIDTH(8)) u_chk_hb_va (.i_tag(px_tag_va), .i_seed(px_seed_b),         .o_hash(px_hb_va));
    pxor_hash_engine #(.TAG_WIDTH(22), .HASH_WIDTH(8)) u_chk_ha_da (.i_tag(px_tag_da), .i_seed(cfg_scramble_seed), .o_hash(px_ha_da));
    pxor_hash_engine #(.TAG_WIDTH(22), .HASH_WIDTH(8)) u_chk_hb_da (.i_tag(px_tag_da), .i_seed(px_seed_b),         .o_hash(px_hb_da));
    pxor_hash_engine #(.TAG_WIDTH(22), .HASH_WIDTH(8)) u_chk_ha_vb (.i_tag(px_tag_vb), .i_seed(cfg_scramble_seed), .o_hash(px_ha_vb));
    pxor_hash_engine #(.TAG_WIDTH(22), .HASH_WIDTH(8)) u_chk_hb_vb (.i_tag(px_tag_vb), .i_seed(px_seed_b),         .o_hash(px_hb_vb));
    pxor_hash_engine #(.TAG_WIDTH(22), .HASH_WIDTH(8)) u_chk_ha_db (.i_tag(px_tag_db), .i_seed(cfg_scramble_seed), .o_hash(px_ha_db));
    pxor_hash_engine #(.TAG_WIDTH(22), .HASH_WIDTH(8)) u_chk_hb_db (.i_tag(px_tag_db), .i_seed(px_seed_b),         .o_hash(px_hb_db));

    // Thực thể độc lập sdc_resilient_filter dùng cho phép đo R-82 (8 hàng, cfg_sdc_thresh=4, 6 vs 8 vòng)
    logic        r82_rst_n      = 1'b0;
    logic        r82_pxor_mode  = 1'b0;
    logic        r82_cmd_valid  = 1'b0;
    logic        r82_cmd_ready;
    logic [2:0]  r82_cmd_bg     = 3'd0;
    logic [1:0]  r82_cmd_bank   = 2'd0;
    logic [16:0] r82_cmd_row    = 17'd0;
    logic        r82_out_valid;
    logic [16:0] r82_out_row;
    logic        r82_out_throttled;

    sdc_resilient_filter #(
        .TABLE_ENTRIES (256),
        .COUNT_WIDTH   (16)
    ) u_r82_sdc (
        .clk                           (clk_axi),
        .rst_n                         (r82_rst_n),
        .cfg_hash_mode                 (1'b1),
        .cfg_pxor_mode                 (r82_pxor_mode),
        .cfg_pxor_seed                 (64'hA5A5_5A5A_0123_4567),
        .cfg_sdc_thresh                (16'd4),
        .cfg_window_size               (16'd500),
        .i_ref_tick                    (1'b0),
        .cfg_multibank_thresh          (3'd2),
        .i_cmd_valid                   (r82_cmd_valid),
        .o_cmd_ready                   (r82_cmd_ready),
        .i_cmd_id                      (4'd0),
        .i_cmd_is_write                (1'b0),
        .i_cmd_bg                      (r82_cmd_bg),
        .i_cmd_bank                    (r82_cmd_bank),
        .i_cmd_row                     (r82_cmd_row),
        .i_cmd_col                     (10'd0),
        .i_cmd_len                     (8'd0),
        .i_cmd_qos                     (4'd0),
        .i_rowpress_weight             (8'd0),
        .o_cmd_valid                   (r82_out_valid),
        .i_cmd_ready                   (1'b1),
        .o_cmd_id                      (),
        .o_cmd_is_write                (),
        .o_cmd_bg                      (),
        .o_cmd_bank                    (),
        .o_cmd_row                     (r82_out_row),
        .o_cmd_col                     (),
        .o_cmd_len                     (),
        .o_cmd_qos                     (),
        .o_cmd_throttled               (r82_out_throttled),
        .o_mitigation_req              (),
        .o_mitigation_bg               (),
        .o_mitigation_bank             (),
        .o_mitigation_row              (),
        .o_sdc_alert                   (),
        .o_coordinated_throttle_active (),
        .o_bank_throttled_flags        (),
        .o_coordinated_throttle_cnt    (),
        .o_telemetry_accesses          (),
        .o_telemetry_throttles         ()
    );

    // Ánh xạ nghịch AXI từ (bg, bank, row, col_line) đúng theo domain_bank_coloring mode 00
    function automatic logic [31:0] make_addr(
        input logic [2:0]  bg,
        input logic [1:0]  bank,
        input logic [13:0] row,
        input logic [6:0]  col_line
    );
        logic [2:0] bg_bits;
        bg_bits = bg ^ row[2:0];
        return {row, bank, col_line, bg_bits, 6'b000000};
    endfunction

    // Giám sát trực tiếp RTL: độ trễ giảm thiểu Λ, L_mit, số lần mất đếm do va chạm bin và thông lượng lành tính
    longint sim_cyc;
    bit     meas_active;
    longint meas_start_cyc;
    longint meas_end_cyc;
    longint benign_r_beats;
    int     atk_inflight;
    int     ben_inflight;
    int     atk_completed;

    bit     mit_pend     [MAX_WATCH];
    longint mit_trig_cyc [MAX_WATCH];
    int     mit_acts_all [MAX_WATCH];
    int     mit_acts_usr [MAX_WATCH];
    int     max_lambda_all;
    int     max_lambda_user;
    longint max_l_mit_cyc;
    int     mit_completed_cnt;
    int     max_pending_l_mit_acts;

    // Theo dõi các bin của hai hàng tấn công chính (v-1, v+1) trong u_sdc_filter để đếm số lần bị hàng khác xóa
    bit     tgt_bin_a_live [256];
    bit     tgt_bin_b_live [256];
    int     bin_wipe_events;
    int     dummy_resets_obs;

    always @(posedge clk_axi or negedge aresetn_axi) begin
        if (!aresetn_axi) begin
            sim_cyc                <= 0;
            benign_r_beats         <= 0;
            atk_inflight           <= 0;
            ben_inflight           <= 0;
            atk_completed          <= 0;
            max_lambda_all         <= 0;
            max_lambda_user        <= 0;
            max_l_mit_cyc          <= 0;
            mit_completed_cnt      <= 0;
            max_pending_l_mit_acts <= 0;
            bin_wipe_events        <= 0;
            dummy_resets_obs       <= 0;
            for (int w = 0; w < MAX_WATCH; w++) begin
                mit_pend[w]     <= 1'b0;
                mit_trig_cyc[w] <= 0;
                mit_acts_all[w] <= 0;
                mit_acts_usr[w] <= 0;
            end
            for (int b = 0; b < 256; b++) begin
                tgt_bin_a_live[b] <= 1'b0;
                tgt_bin_b_live[b] <= 1'b0;
            end
        end else begin
            sim_cyc <= sim_cyc + 1;

            begin
                int atk_d, ben_d;
                atk_d = 0;
                ben_d = 0;
                if (s_axi_arvalid && s_axi_arready) begin
                    if (s_axi_arid == 4'h1) atk_d = atk_d + 1;
                    if (s_axi_arid == 4'h8) ben_d = ben_d + 1;
                end
                if (s_axi_rvalid && s_axi_rready && s_axi_rlast) begin
                    if (s_axi_rid == 4'h1) begin
                        atk_d         = atk_d - 1;
                        atk_completed <= atk_completed + 1;
                    end
                    if (s_axi_rid == 4'h8) begin
                        ben_d = ben_d - 1;
                    end
                end
                atk_inflight <= atk_inflight + atk_d;
                ben_inflight <= ben_inflight + ben_d;
            end
            if (meas_active && s_axi_rvalid && s_axi_rready && (s_axi_rid == 4'h8)) begin
                benign_r_beats <= benign_r_beats + 1;
            end

            // Đếm sự kiện bộ lọc SDC đặt lại bin của hàng mục tiêu do hàng khác chạm ngưỡng
            if (dut.u_sdc_filter.s_fire) begin
                int ha_i, hb_i;
                bit is_tgt;
                ha_i   = int'(dut.u_sdc_filter.eff_hash_a);
                hb_i   = int'(dut.u_sdc_filter.eff_hash_b);
                if ((p_case_id == 7) || (p_case_id == 8)) begin
                    is_tgt = (dut.u_sdc_filter.s_bg == 3'd0) && (dut.u_sdc_filter.s_bank == 2'd0) &&
                             ((dut.u_sdc_filter.s_row == (VICTIM_BASE - 17'd1)) ||
                              (dut.u_sdc_filter.s_row == (VICTIM_BASE + 17'd1)));
                end else begin
                    is_tgt = (dut.u_sdc_filter.s_bg == 3'd0) && (dut.u_sdc_filter.s_bank == 2'd0) &&
                             (int'(dut.u_sdc_filter.s_row) >= WATCH_LO) &&
                             (int'(dut.u_sdc_filter.s_row) < (WATCH_LO + MAX_WATCH));
                end
                if (dut.u_sdc_filter.will_throttle) begin
                    if (!is_tgt) begin
                        dummy_resets_obs <= dummy_resets_obs + 1;
                        if ((tgt_bin_a_live[ha_i] && (dut.u_sdc_filter.new_cnt_a == '0)) ||
                            (tgt_bin_b_live[hb_i] && (dut.u_sdc_filter.new_cnt_b == '0)))
                            bin_wipe_events <= bin_wipe_events + 1;
                    end
                    if (dut.u_sdc_filter.new_cnt_a == '0) tgt_bin_a_live[ha_i] <= 1'b0;
                    if (dut.u_sdc_filter.new_cnt_b == '0) tgt_bin_b_live[hb_i] <= 1'b0;
                end else if (is_tgt) begin
                    tgt_bin_a_live[ha_i] <= 1'b1;
                    tgt_bin_b_live[hb_i] <= 1'b1;
                end
            end

            // Đo Λ và L_mit trực tiếp trên Bank (0, 0) cho vùng nạn nhân WATCH_LO .. WATCH_LO+MAX_WATCH-1
            if (dut.u_sdc_filter.o_mitigation_req &&
                (dut.u_sdc_filter.o_mitigation_bg == 3'd0) &&
                (dut.u_sdc_filter.o_mitigation_bank == 2'd0)) begin
                for (int w = 0; w < MAX_WATCH; w++) begin
                    int vr, mr, diff;
                    vr   = WATCH_LO + w;
                    mr   = int'(dut.u_sdc_filter.o_mitigation_row);
                    diff = (mr > vr) ? (mr - vr) : (vr - mr);
                    if ((diff >= 1) && (diff <= RH_RADIUS) && !mit_pend[w]) begin
                        mit_pend[w]     <= 1'b1;
                        mit_trig_cyc[w] <= sim_cyc;
                        mit_acts_all[w] <= 0;
                        mit_acts_usr[w] <= 0;
                    end
                end
            end
            if (dut.u_cmd_engine.o_rowpress_alert &&
                (dut.u_cmd_engine.o_rowpress_bg == 3'd0) &&
                (dut.u_cmd_engine.o_rowpress_bank == 2'd0)) begin
                for (int w = 0; w < MAX_WATCH; w++) begin
                    int vr, mr, diff;
                    vr   = WATCH_LO + w;
                    mr   = int'(dut.u_cmd_engine.o_rowpress_row);
                    diff = (mr > vr) ? (mr - vr) : (vr - mr);
                    if ((diff >= 1) && (diff <= RH_RADIUS) && !mit_pend[w]) begin
                        mit_pend[w]     <= 1'b1;
                        mit_trig_cyc[w] <= sim_cyc;
                        mit_acts_all[w] <= 0;
                        mit_acts_usr[w] <= 0;
                    end
                end
            end

            if ((dfi_cmd == 3'd1) && (dfi_bg == 3'd0) && (dfi_bank == 2'd0)) begin
                int dr;
                dr = int'(dfi_row);
                for (int w = 0; w < MAX_WATCH; w++) begin
                    if (mit_pend[w]) begin
                        int vr, diff;
                        vr   = WATCH_LO + w;
                        diff = (dr > vr) ? (dr - vr) : (vr - dr);
                        if (dr == vr) begin
                            longint lm;
                            lm = (sim_cyc - mit_trig_cyc[w]) + 3;
                            if (lm > max_l_mit_cyc)            max_l_mit_cyc   <= lm;
                            if (mit_acts_all[w] > max_lambda_all)  max_lambda_all  <= mit_acts_all[w];
                            if (mit_acts_usr[w] > max_lambda_user) max_lambda_user <= mit_acts_usr[w];
                            mit_completed_cnt <= mit_completed_cnt + 1;
                            mit_pend[w]       <= 1'b0;
                            mit_acts_all[w]   <= 0;
                            mit_acts_usr[w]   <= 0;
                        end else if ((diff >= 1) && (diff <= RH_RADIUS)) begin
                            mit_acts_all[w] <= mit_acts_all[w] + 1;
                            if (!dut.u_cmd_engine.dfi_act_mit)
                                mit_acts_usr[w] <= mit_acts_usr[w] + 1;
                            if ((mit_acts_all[w] + 1) > max_pending_l_mit_acts)
                                max_pending_l_mit_acts <= mit_acts_all[w] + 1;
                        end
                    end
                end
            end
        end
    end

    // Bộ lái AXI4 ở sườn xuống: giữ ARVALID & payload bất biến cho tới khi bắt tay s_axi_arready == 1
    bit                        ar_wait_ready = 1'b0;
    bit                        atk_has_req   = 1'b0;
    logic [AXI_ADDR_WIDTH-1:0] atk_next_addr = 32'd0;
    logic [7:0]                atk_next_len  = 8'd0;
    int                        ben_seq_idx   = 0;

    task automatic step_axi_cycle(input bit allow_benign, output bit atk_hs);
        logic [2:0]  bg_b;
        logic [1:0]  bk_b;
        logic [13:0] row_b;
        logic [6:0]  col_b;
        atk_hs = 1'b0;
        @(negedge clk_axi);
        if (!ar_wait_ready) begin
            if (atk_has_req && (atk_inflight < 8)) begin
                s_axi_arvalid = 1'b1;
                s_axi_arid    = 4'h1;
                s_axi_araddr  = atk_next_addr;
                s_axi_arlen   = atk_next_len;
                s_axi_arsize  = 3'b011;
                s_axi_arburst = 2'b01;
                s_axi_arqos   = 4'd0;
                atk_has_req   = 1'b0;
            end else if (allow_benign && (p_benign != 0) && (ben_inflight < 6)) begin
                bg_b  = ((ben_seq_idx & 1) != 0) ? 3'd7 : 3'd6;
                bk_b  = 2'((ben_seq_idx >> 1) & 3);
                row_b = 14'h0800 + 14'((ben_seq_idx >> 3) & 127);
                col_b = 7'((ben_seq_idx >> 10) & 127);
                s_axi_arvalid = 1'b1;
                s_axi_arid    = 4'h8;
                s_axi_araddr  = make_addr(bg_b, bk_b, row_b, col_b);
                s_axi_arlen   = 8'd7;
                s_axi_arsize  = 3'b011;
                s_axi_arburst = 2'b01;
                s_axi_arqos   = 4'd12;
                ben_seq_idx++;
            end else begin
                s_axi_arvalid = 1'b0;
            end
        end
        #0.1;
        if (s_axi_arvalid && s_axi_arready) begin
            ar_wait_ready = 1'b0;
            if (s_axi_arid == 4'h1) atk_hs = 1'b1;
        end else if (s_axi_arvalid) begin
            ar_wait_ready = 1'b1;
        end else begin
            ar_wait_ready = 1'b0;
        end
        @(posedge clk_axi);
    endtask

    task automatic issue_atk_read(input logic [2:0] bg, input logic [1:0] bk,
                                  input logic [13:0] row, input logic [6:0] col_line,
                                  input bit allow_benign);
        bit sent;
        atk_next_addr = make_addr(bg, bk, row, col_line);
        atk_next_len  = 8'd0;
        atk_has_req   = 1'b1;
        sent          = 1'b0;
        while (!sent && (sim_cyc < p_max_cyc)) begin
            step_axi_cycle(allow_benign, sent);
        end
        atk_has_req = 1'b0;
    endtask

    task automatic idle_cycles(input int n_cyc, input bit allow_benign);
        int k;
        bit hs;
        for (k = 0; k < n_cyc && (sim_cyc < p_max_cyc); k++) begin
            step_axi_cycle(allow_benign, hs);
        end
    endtask

    task automatic drain_attacker(input int extra_cyc, input bit allow_benign);
        int guard;
        bit hs;
        guard = 0;
        while ((atk_inflight > 0 || ar_wait_ready) && (guard < 6000)) begin
            step_axi_cycle(allow_benign, hs);
            guard++;
        end
        if (!allow_benign) begin
            @(negedge clk_axi);
            s_axi_arvalid = 1'b0;
            ar_wait_ready = 1'b0;
            repeat (extra_cyc) @(posedge clk_axi);
        end else begin
            idle_cycles(extra_cyc, 1'b1);
        end
    endtask

    // Bài đo độc lập R-82: test_many_sided_hammering_distribution với 6 vs 8 vòng và PXOR 0 vs 1
    task automatic run_r82_subrun(input int tag_id, input bit use_pxor, input int n_rounds);
        int aggs[8];
        int th_out[8];
        int th_old[8];
        int ha_val[8];
        int hb_val[8];
        bit in_bin_a[256][8];
        bit in_bin_b[256][8];
        int bin_a_resets_other;
        int bin_b_resets_other;
        int out_rows_throttled;
        int old_rows_throttled;
        int victim_rows_reset_mask;
        int r, i, b, j;
        int row_v, sha, shb, src_idx, oi;

        for (i = 0; i < 8; i++) begin
            aggs[i]   = 16 + i * 4;
            th_out[i] = 0;
            th_old[i] = 0;
            ha_val[i] = 0;
            hb_val[i] = 0;
        end
        for (b = 0; b < 256; b++) begin
            for (i = 0; i < 8; i++) begin
                in_bin_a[b][i] = 1'b0;
                in_bin_b[b][i] = 1'b0;
            end
        end
        bin_a_resets_other     = 0;
        bin_b_resets_other     = 0;
        victim_rows_reset_mask = 0;

        r82_rst_n     = 1'b0;
        r82_pxor_mode = use_pxor;
        r82_cmd_valid = 1'b0;
        repeat (4) @(posedge clk_axi);
        r82_rst_n = 1'b1;
        repeat (2) @(posedge clk_axi);

        for (r = 0; r < n_rounds; r++) begin
            for (i = 0; i < 8; i++) begin
                row_v         = aggs[i];
                r82_cmd_valid = 1'b1;
                r82_cmd_bg    = 3'((row_v >> 2) & 7);
                r82_cmd_bank  = 2'((row_v >> 1) & 3);
                r82_cmd_row   = 17'(row_v);
                @(posedge clk_axi);
                #0.1;
                if (r == 0) begin
                    ha_val[i] = int'(u_r82_sdc.in_hash_a);
                    hb_val[i] = int'(u_r82_sdc.in_hash_b);
                end
                if (u_r82_sdc.s_fire) begin
                    sha     = int'(u_r82_sdc.eff_hash_a);
                    shb     = int'(u_r82_sdc.eff_hash_b);
                    src_idx = (int'(u_r82_sdc.s_row) - 16) / 4;
                    if (u_r82_sdc.will_throttle) begin
                        for (j = 0; j < 8; j++) begin
                            if (j != src_idx) begin
                                if (in_bin_a[sha][j] && (u_r82_sdc.new_cnt_a == '0)) begin
                                    bin_a_resets_other++;
                                    victim_rows_reset_mask = victim_rows_reset_mask | (1 << j);
                                end
                                if (in_bin_b[shb][j] && (u_r82_sdc.new_cnt_b == '0)) begin
                                    bin_b_resets_other++;
                                    victim_rows_reset_mask = victim_rows_reset_mask | (1 << j);
                                end
                            end
                            if (u_r82_sdc.new_cnt_a == '0) in_bin_a[sha][j] = 1'b0;
                            if (u_r82_sdc.new_cnt_b == '0) in_bin_b[shb][j] = 1'b0;
                        end
                    end else if (src_idx >= 0 && src_idx < 8) begin
                        in_bin_a[sha][src_idx] = 1'b1;
                        in_bin_b[shb][src_idx] = 1'b1;
                    end
                end
                if (r82_out_throttled) th_old[i]++;
                if (r82_out_valid && r82_out_throttled) begin
                    oi = (int'(r82_out_row) - 16) / 4;
                    if (oi >= 0 && oi < 8) th_out[oi]++;
                end
            end
        end

        r82_cmd_valid = 1'b0;
        for (i = 0; i < 4; i++) begin
            @(posedge clk_axi);
            #0.1;
            if (u_r82_sdc.s_fire) begin
                sha     = int'(u_r82_sdc.eff_hash_a);
                shb     = int'(u_r82_sdc.eff_hash_b);
                src_idx = (int'(u_r82_sdc.s_row) - 16) / 4;
                if (u_r82_sdc.will_throttle) begin
                    for (j = 0; j < 8; j++) begin
                        if (j != src_idx) begin
                            if (in_bin_a[sha][j] && (u_r82_sdc.new_cnt_a == '0)) begin
                                bin_a_resets_other++;
                                victim_rows_reset_mask = victim_rows_reset_mask | (1 << j);
                            end
                            if (in_bin_b[shb][j] && (u_r82_sdc.new_cnt_b == '0)) begin
                                bin_b_resets_other++;
                                victim_rows_reset_mask = victim_rows_reset_mask | (1 << j);
                            end
                        end
                        if (u_r82_sdc.new_cnt_a == '0) in_bin_a[sha][j] = 1'b0;
                        if (u_r82_sdc.new_cnt_b == '0) in_bin_b[shb][j] = 1'b0;
                    end
                end else if (src_idx >= 0 && src_idx < 8) begin
                    in_bin_a[sha][src_idx] = 1'b1;
                    in_bin_b[shb][src_idx] = 1'b1;
                end
            end
            if (r82_out_valid && r82_out_throttled) begin
                oi = (int'(r82_out_row) - 16) / 4;
                if (oi >= 0 && oi < 8) th_out[oi]++;
            end
        end

        out_rows_throttled = 0;
        old_rows_throttled = 0;
        for (i = 0; i < 8; i++) begin
            if (th_out[i] > 0) out_rows_throttled++;
            if (th_old[i] > 0) old_rows_throttled++;
        end
        $display("[R82_RESULT] sub=%0d pxor=%0d rounds=%0d out_throttled_rows=%0d/8 old_in_rows=%0d/8 bin_a_resets_by_other=%0d bin_b_resets_by_other=%0d victim_rows_reset_mask=0x%02x counts_out=%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d ha=%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d hb=%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                 tag_id, int'(use_pxor), n_rounds, out_rows_throttled, old_rows_throttled,
                 bin_a_resets_other, bin_b_resets_other, victim_rows_reset_mask,
                 th_out[0], th_out[1], th_out[2], th_out[3], th_out[4], th_out[5], th_out[6], th_out[7],
                 ha_val[0], ha_val[1], ha_val[2], ha_val[3], ha_val[4], ha_val[5], ha_val[6], ha_val[7],
                 hb_val[0], hb_val[1], hb_val[2], hb_val[3], hb_val[4], hb_val[5], hb_val[6], hb_val[7]);
    endtask

    // Biến điều khiển kịch bản chính
    int          d_max_target;
    int          d_max_global;
    longint      rp_open_max_tgt;
    longint      rp_single_max_tgt;
    longint      rp_open_max_glb;
    longint      rp_single_max_glb;
    longint      meas_cyc;
    int          rounds;
    int          i, j, w;
    int          decoy_idx, dec_per_round;
    int          dummy_base, b_off, t_cyc, batch_sz;
    int          target_waves, num_hits;
    int          margin, step, d_hits, k;
    logic [2:0]  dbg;
    logic [1:0]  dbk;
    logic [13:0] drow;

    initial begin
        if ($value$plusargs("CASE_ID=%d",  p_case_id))  begin end
        if ($value$plusargs("NRH=%d",      p_nrh))      begin end
        if ($value$plusargs("THRESH=%d",   p_thresh))   begin end
        if ($value$plusargs("N_AGG=%d",    p_n_agg))    begin end
        if ($value$plusargs("BENIGN=%d",   p_benign))   begin end
        if ($value$plusargs("RP_CURVE=%d", p_rp_curve)) begin end
        if ($value$plusargs("RP_HOLD=%d",  p_rp_hold))  begin end
        if ($value$plusargs("WAVES=%d",    p_waves))    begin end
        if ($value$plusargs("DUMMY_M=%d",  p_dummy_m))  begin end
        if ($value$plusargs("MAX_CYC=%d",  p_max_cyc))  begin end
        if ($value$plusargs("SEED_HI=%h",  p_seed_hi))  begin end
        if ($value$plusargs("SEED_LO=%h",  p_seed_lo))  begin end
        if ($value$plusargs("DA_BG=%d",    p_da_bg))    begin end
        if ($value$plusargs("DA_BK=%d",    p_da_bk))    begin end
        if ($value$plusargs("DA_ROW=%d",   p_da_row))   begin end
        if ($value$plusargs("DB_BG=%d",    p_db_bg))    begin end
        if ($value$plusargs("DB_BK=%d",    p_db_bk))    begin end
        if ($value$plusargs("DB_ROW=%d",   p_db_row))   begin end
        if ($value$plusargs("FAR_ROW=%d",  p_far_row))  begin end
        if ($value$plusargs("FORCE_VIC3_EN=%d",  p_force_vic3_en))  begin end
        if ($value$plusargs("IGNORE_MIT_ACT=%d", p_ignore_mit_act)) begin end
        if ($value$plusargs("DUMMY_BANKS=%d",    p_dummy_banks))    begin end
        if ($value$plusargs("DIAG_DUMP=%d",      p_diag_dump))      begin end

        cfg_rh_threshold   = 16'(p_thresh);
        cfg_rowpress_curve = 2'(p_rp_curve);
        cfg_scramble_seed  = {p_seed_hi, p_seed_lo};
        cfg_victim3_en     = (p_force_vic3_en >= 0) ? (p_force_vic3_en != 0) : ((RH_RADIUS >= 3) ? 1'b1 : 1'b0);
        u_dram.rh_ignore_mit_act = (p_ignore_mit_act != 0);

        aresetn_axi = 1'b0;
        meas_active = 1'b0;

        if (p_case_id == 11) begin
            repeat (8) @(posedge clk_axi);
            run_r82_subrun(0, 1'b0, 6);
            run_r82_subrun(1, 1'b0, 8);
            run_r82_subrun(2, 1'b1, 6);
            run_r82_subrun(3, 1'b1, 8);
            tb_check(u_jchk.all_violations() == 0, "R82: 0 JEDEC violations");
            tb_check(u_dram.errors() == 0, "R82: 0 DRAM model errors");
            tb_report();
            $finish;
        end

        repeat (16) @(posedge clk_axi);
        aresetn_axi = 1'b1;
        repeat (32) @(posedge clk_axi);

        tb_check(dut.u_ate.base_thresh == 16'(p_thresh),
                 $sformatf("ATE base_thresh configured to %0d (got %0d)", p_thresh, dut.u_ate.base_thresh));
        tb_check(dut.u_ate.max_thresh == 16'(p_thresh),
                 $sformatf("ATE max_thresh configured to %0d (got %0d)", p_thresh, dut.u_ate.max_thresh));
        tb_check(dut.u_ate.o_dynamic_thresh == 16'(p_thresh),
                 $sformatf("ATE dynamic_thresh active == %0d (got %0d)", p_thresh, dut.u_ate.o_dynamic_thresh));
        tb_check(dut.u_sdc_filter.thresh_q == 16'(p_thresh),
                 $sformatf("SDC thresh_q latched == %0d (got %0d)", p_thresh, dut.u_sdc_filter.thresh_q));
        tb_check(dut.eff_scramble_mode == 2'b00,
                 $sformatf("Physical-row eval mode: SCARF disabled (got %0d)", dut.eff_scramble_mode));

        if (p_case_id == 8) begin
            tb_check((px_ha_da == px_ha_va) && (px_hb_da == px_hb_va),
                     $sformatf("Known-seed PXOR match for v-1: A(%02x==%02x) B(%02x==%02x)",
                               px_ha_da, px_ha_va, px_hb_da, px_hb_va));
            tb_check((px_ha_db == px_ha_vb) && (px_hb_db == px_hb_vb),
                     $sformatf("Known-seed PXOR match for v+1: A(%02x==%02x) B(%02x==%02x)",
                               px_ha_db, px_ha_vb, px_hb_db, px_hb_vb));
        end

        meas_start_cyc = sim_cyc;
        meas_active    = 1'b1;

        case (p_case_id)
            0: begin
                // Luồng lành tính đơn độc (đo băng thông cơ sở)
                idle_cycles(p_max_cyc - 100, 1'b1);
            end

            1: begin
                // Hiệu chuẩn Λ và L_mit: pha 1 (2R hàng kề), pha 2 (8 hàng gây tranh chấp DRM), pha 3 (đồng bộ hóa pha B)
                rounds = (p_thresh * 3 > 48) ? (p_thresh * 3) : 48;
                for (i = 0; i < rounds && (sim_cyc < p_max_cyc); i++) begin
                    if (RH_RADIUS >= 3) issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE - 3), 7'(i & 127), 1'b1);
                    issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE - 2), 7'(i & 127), 1'b1);
                    issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE - 1), 7'(i & 127), 1'b1);
                    issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE + 1), 7'(i & 127), 1'b1);
                    issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE + 2), 7'(i & 127), 1'b1);
                    if (RH_RADIUS >= 3) issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE + 3), 7'(i & 127), 1'b1);
                end
                for (i = 0; i < rounds && (sim_cyc < p_max_cyc); i++) begin
                    for (j = 0; j < 8; j++) begin
                        issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE - 1 + j * 2), 7'(i & 127), 1'b1);
                    end
                end
                drain_attacker(32, 1'b1);
                for (i = 0; i < p_thresh && (sim_cyc < p_max_cyc); i++) begin
                    if (RH_RADIUS >= 3) issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE - 3), 7'(i & 127), 1'b1);
                    issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE - 2), 7'(i & 127), 1'b1);
                    issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE - 1), 7'(i & 127), 1'b1);
                    issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE + 1), 7'(i & 127), 1'b1);
                    issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE + 2), 7'(i & 127), 1'b1);
                    if (RH_RADIUS >= 3) issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE + 3), 7'(i & 127), 1'b1);
                end
                drain_attacker(8, 1'b1);
                issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE - 2), 7'd0, 1'b1);
                issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE + 2), 7'd0, 1'b1);
                drain_attacker(32, 1'b1);
            end

            2: begin
                // Single-sided: v-1 xen kẽ hàng xa p_far_row để mỗi truy cập đều miss row buffer -> ACT thật
                rounds = (p_thresh * 2 + 16 > 96) ? (p_thresh * 2 + 16) : 96;
                for (i = 0; i < rounds && (sim_cyc < p_max_cyc); i++) begin
                    issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE - 1), 7'(i & 127), 1'b1);
                    issue_atk_read(3'd0, 2'd0, 14'(p_far_row),       7'(i & 127), 1'b1);
                end
            end

            3: begin
                // Double-sided: kẹp chặt v giữa v-1 và v+1
                rounds = (p_thresh * 2 + 16 > 96) ? (p_thresh * 2 + 16) : 96;
                for (i = 0; i < rounds && (sim_cyc < p_max_cyc); i++) begin
                    issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE - 1), 7'(i & 127), 1'b1);
                    issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE + 1), 7'(i & 127), 1'b1);
                end
            end

            4: begin
                // Many-sided (n = 4..32 hàng) trên cùng bank (0, 0)
                if (p_n_agg <= 8)
                    rounds = (p_thresh * 2 + 8 > 64) ? (p_thresh * 2 + 8) : 64;
                else if (p_n_agg <= 16)
                    rounds = (p_thresh + 16 > 48) ? (p_thresh + 16) : 48;
                else
                    rounds = (p_thresh + 8 > 40) ? (p_thresh + 8) : 40;
                for (i = 0; i < rounds && (sim_cyc < p_max_cyc); i++) begin
                    for (j = 0; j < p_n_agg && (sim_cyc < p_max_cyc); j++) begin
                        issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE - 1 + j * 2), 7'(i & 127), 1'b1);
                    end
                end
            end

            5: begin
                // Half-double: pha A xen kẽ liên tục, pha B đồng bộ hóa ngưỡng + xung kích đồng thời tất cả 2R hàng kề
                rounds = (p_thresh * 2 + 16 > 96) ? (p_thresh * 2 + 16) : 96;
                for (i = 0; i < rounds && (sim_cyc < p_max_cyc); i++) begin
                    if (RH_RADIUS >= 3) issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE - 3), 7'(i & 127), 1'b1);
                    issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE - 2), 7'(i & 127), 1'b1);
                    issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE - 1), 7'(i & 127), 1'b1);
                    issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE + 1), 7'(i & 127), 1'b1);
                    issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE + 2), 7'(i & 127), 1'b1);
                    if (RH_RADIUS >= 3) issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE + 3), 7'(i & 127), 1'b1);
                end
                drain_attacker(32, 1'b1);
                for (i = 0; i < p_thresh && (sim_cyc < p_max_cyc); i++) begin
                    if (RH_RADIUS >= 3) issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE - 3), 7'(i & 127), 1'b1);
                    issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE - 2), 7'(i & 127), 1'b1);
                    issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE - 1), 7'(i & 127), 1'b1);
                    issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE + 1), 7'(i & 127), 1'b1);
                    issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE + 2), 7'(i & 127), 1'b1);
                    if (RH_RADIUS >= 3) issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE + 3), 7'(i & 127), 1'b1);
                end
                drain_attacker(8, 1'b1);
                issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE - 2), 7'd0, 1'b1);
                issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE + 2), 7'd0, 1'b1);
                drain_attacker(32, 1'b1);
            end

            6: begin
                // Decoy/feinting nhắm bảng theo dõi & ATE: xen kẽ hàng mồi phân tán (< T mỗi hàng) với kẹp đôi v-1, v+1
                decoy_idx = 0;
                rounds = (p_thresh * 2 + 16 > 96) ? (p_thresh * 2 + 16) : 96;
                for (i = 0; i < rounds && (sim_cyc < p_max_cyc); i++) begin
                    issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE - 1), 7'(i & 127), 1'b1);
                    issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE + 1), 7'(i & 127), 1'b1);
                    dec_per_round = (p_thresh <= 20) ? 2 : 4;
                    for (j = 0; j < dec_per_round; j++) begin
                        dbg  = 3'(1 + (decoy_idx % 5));
                        dbk  = 2'((decoy_idx / 5) & 3);
                        drow = 14'h1800 + 14'((decoy_idx / 20) & 511);
                        issue_atk_read(dbg, dbk, drow, 7'd0, 1'b1);
                        decoy_idx = (decoy_idx + 1) % 600;
                    end
                end
            end

            7: begin
                // Va chạm hash có chủ đích (KHÔNG biết seed): kẹp đơn v-1 xen p_far_row (tránh RowPress), rồi quét M hàng mồi ở bg=1..5, bank=1 (tránh SledgeHammer >2 bank)
                for (w = 0; w < p_waves && (sim_cyc < p_max_cyc); w++) begin
                    step = (w == 0) ? ((p_thresh > 1) ? (p_thresh - 1) : 1) : p_thresh;
                    for (i = 0; i < step && (sim_cyc < p_max_cyc); i++) begin
                        issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE - 1), 7'(i & 127), 1'b1);
                        issue_atk_read(3'd0, 2'd0, 14'(p_far_row),       7'(i & 127), 1'b1);
                    end
                    drain_attacker(8, 1'b1);
                    for (j = 0; j < p_dummy_m && (sim_cyc < p_max_cyc); j += 5) begin
                        batch_sz = ((j + 5) <= p_dummy_m) ? 5 : (p_dummy_m - j);
                        for (t_cyc = 0; t_cyc <= p_thresh && (sim_cyc < p_max_cyc); t_cyc++) begin
                            for (b_off = 0; b_off < batch_sz && (sim_cyc < p_max_cyc); b_off++) begin
                                dummy_base = w * p_dummy_m + j + b_off;
                                dbg  = 3'(1 + b_off);
                                dbk  = (p_dummy_banks >= 2) ? 2'(1 + (dummy_base & 1)) : 2'd1;
                                drow = 14'h1000 + 14'(dummy_base);
                                issue_atk_read(dbg, dbk, drow, 7'(t_cyc & 127), 1'b1);
                            end
                        end
                    end
                    drain_attacker(8, 1'b1);
                end
                for (i = 0; i < p_thresh && (sim_cyc < p_max_cyc); i++) begin
                    issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE - 1), 7'(i & 127), 1'b1);
                    issue_atk_read(3'd0, 2'd0, 14'(p_far_row),       7'(i & 127), 1'b1);
                end
            end

            8: begin
                // Va chạm hash có chủ đích (BIẾT seed): chừa biên chống khóa pha nhiễu nền, rồi nạp d_a/d_b trùng cả 2 bảng PXOR để xóa bin
                margin       = (p_thresh >= 32) ? 4 : ((p_thresh >= 8) ? 2 : 1);
                step         = (p_thresh > margin) ? (p_thresh - margin) : 1;
                d_hits       = margin + 1;
                target_waves = ((p_nrh * 2) / (2 * step)) + 2;
                if (target_waves > p_waves) target_waves = p_waves;
                for (w = 0; w < target_waves && (sim_cyc < p_max_cyc); w++) begin
                    for (i = 0; i < step && (sim_cyc < p_max_cyc); i++) begin
                        issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE - 1), 7'(i & 127), 1'b1);
                        issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE + 1), 7'(i & 127), 1'b1);
                    end
                    for (k = 0; k < d_hits && (sim_cyc < p_max_cyc); k++) begin
                        issue_atk_read(3'(p_da_bg), 2'(p_da_bk), 14'(p_da_row), 7'((w * d_hits + k) & 127), 1'b1);
                        issue_atk_read(3'(p_db_bg), 2'(p_db_bk), 14'(p_db_row), 7'((w * d_hits + k) & 127), 1'b1);
                    end
                    drain_attacker(12, 1'b1);
                end
            end

            9: begin
                // RowPress giữ hàng lâu (> 1001 chu kỳ/lần ở curve=3): kích hoạt thật o_rowpress_alert & làm tươi nạn nhân
                for (i = 0; i < 6 && (sim_cyc < p_max_cyc); i++) begin
                    issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE - 1), 7'(i & 127), 1'b0);
                    idle_cycles(1250, 1'b0);
                    issue_atk_read(3'd0, 2'd0, 14'(p_far_row),       7'(i & 127), 1'b0);
                    idle_cycles(40, 1'b0);
                end
            end

            10: begin
                // RowPress lặp dưới ngưỡng đơn lần (mở p_rp_hold < 1001 chu kỳ rồi đóng bằng hàng xa, lặp T+4 lần)
                rounds = p_thresh + 4;
                for (i = 0; i < rounds && (sim_cyc < p_max_cyc); i++) begin
                    issue_atk_read(3'd0, 2'd0, 14'(VICTIM_BASE - 1), 7'(i & 127), 1'b1);
                    idle_cycles(p_rp_hold, 1'b1);
                    issue_atk_read(3'd0, 2'd0, 14'(p_far_row),       7'(i & 127), 1'b1);
                    idle_cycles(30, 1'b1);
                end
            end

            default: begin
                idle_cycles(2000, 1'b1);
            end
        endcase

        drain_attacker(128, 1'b1);
        meas_active  = 1'b0;
        meas_end_cyc = sim_cyc;
        meas_cyc     = meas_end_cyc - meas_start_cyc;

        u_dram.rh_flush_open_banks();

        d_max_target      = 0;
        rp_open_max_tgt   = 0;
        rp_single_max_tgt = 0;
        for (w = 0; w < MAX_WATCH; w++) begin
            int dm;
            longint rpm, rps;
            dm  = u_dram.rh_get_disturb_max(3'd0, 2'd0, 17'(WATCH_LO + w));
            rpm = u_dram.rh_get_rp_open_max(3'd0, 2'd0, 17'(WATCH_LO + w));
            rps = u_dram.rh_get_rp_single_max(3'd0, 2'd0, 17'(WATCH_LO + w));
            if (dm  > d_max_target)      d_max_target      = dm;
            if (rpm > rp_open_max_tgt)   rp_open_max_tgt   = rpm;
            if (rps > rp_single_max_tgt) rp_single_max_tgt = rps;
        end
        if (p_case_id == 2 || p_case_id == 10) begin
            for (w = -3; w <= 3; w++) begin
                int dm;
                dm = u_dram.rh_get_disturb_max(3'd0, 2'd0, 17'(p_far_row + w));
                if (dm > d_max_target) d_max_target = dm;
            end
        end

        d_max_global      = u_dram.rh_get_global_max_disturb();
        rp_open_max_glb   = u_dram.rh_get_global_max_rp_open();
        rp_single_max_glb = u_dram.rh_get_global_max_single_open();

        tb_check(u_jchk.all_violations() == 0,
                 $sformatf("JEDEC DFI clean: all_violations=%0d (timing=%0d ref_open=%0d ref_gap=%0d)",
                           u_jchk.all_violations(), u_jchk.timing_violations(), u_jchk.viol_ref_open, u_jchk.viol_refgap));
        tb_check(u_dram.errors() == 0,
                 $sformatf("DRAM model clean: errors=%0d (rh_table_full=%0d)", u_dram.errors(), u_dram.rh_err_table_full));
        tb_check(o_fault_cause == 9'd0 && !o_glitch_alert,
                 $sformatf("No silicon fault/glitch alert (o_fault_cause=0x%03x, glitch=%0d)", o_fault_cause, o_glitch_alert));

        $display("[RH_EVAL_RESULT] case_id=%0d nrh=%0d radius=%0d thresh=%0d n_agg=%0d d_max_target=%0d d_max_global=%0d max_key=0x%08x lambda_all=%0d lambda_user=%0d l_mit_cyc=%0d lam_pend=%0d mit_done=%0d rp_open_max=%0d rp_single_max=%0d rp_open_glb=%0d rp_single_glb=%0d rp_alerts=%0d tras_clamps=%0d total_acts=%0d refs=%0d rfms=%0d dummy_resets=%0d bin_wipes=%0d meas_cyc=%0d ben_beats=%0d atk_done=%0d jedec_viol=%0d dram_err=%0d",
                 p_case_id, p_nrh, RH_RADIUS, p_thresh, p_n_agg,
                 d_max_target, d_max_global, u_dram.rh_global_max_disturb_key,
                 max_lambda_all, max_lambda_user, max_l_mit_cyc, max_pending_l_mit_acts, mit_completed_cnt,
                 rp_open_max_tgt, rp_single_max_tgt, rp_open_max_glb, rp_single_max_glb,
                 dut.u_cmd_engine.o_rowpress_alert_cnt, dut.u_cmd_engine.o_tras_clamped_cnt,
                 u_dram.rh_total_acts, u_dram.rh_total_refs, u_dram.rh_total_rfms,
                 dummy_resets_obs, bin_wipe_events,
                 meas_cyc, benign_r_beats, atk_completed,
                 u_jchk.all_violations(), u_dram.errors());

        if (p_diag_dump != 0) begin
            for (int rr = int'(VICTIM_BASE) - 7; rr <= int'(VICTIM_BASE) + 7; rr++) begin
                $display("[RH_DIAG_ROW] row=0x%04x user_acts=%0d mit_acts=%0d disturb_max=%0d",
                         rr,
                         u_dram.rh_get_user_act_self(3'd0, 2'd0, 17'(rr)),
                         u_dram.rh_get_mit_act_self(3'd0, 2'd0, 17'(rr)),
                         u_dram.rh_get_disturb_max(3'd0, 2'd0, 17'(rr)));
            end
        end

        u_jchk.report($sformatf("rh_case%0d_nrh%0d", p_case_id, p_nrh));
        tb_report();
        $finish;
    end

    initial begin
        #2_500_000_000;
        $display("[FAIL] Watchdog timeout in tb_rh_eval (case_id=%0d, nrh=%0d, sim_cyc=%0d)",
                 p_case_id, p_nrh, sim_cyc);
        tb_report();
        $finish;
    end

endmodule
