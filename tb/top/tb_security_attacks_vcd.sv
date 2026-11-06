//=============================================================================
// File:        tb_security_attacks_vcd.sv
// Chức năng:   Bộ kiểm thử tấn công phần cứng (red team) trên axi_ddr5_mc_top: mỗi vector phán định bằng lệnh DFI/phản hồi AXI quan sát được.
//=============================================================================
`timescale 1ns / 1ps

module tb_security_attacks_vcd;

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
    localparam int TB_DFI_WRLAT   = 9;

    // Clocks and Resets
    logic clk_axi = 0;
    always #2.0 clk_axi = ~clk_axi; // 250 MHz

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

    logic                      cfg_bank_coloring_en;
    logic [1:0]                cfg_mapping_mode;
    logic                      cfg_scramble_en;
    logic                      cfg_scramble_reseed;
    logic [63:0]               cfg_scramble_seed;
    logic                      cfg_pmu_en;
    logic                      cfg_pmu_reset;
    logic [7:0][31:0]          o_pmu_counters;

    logic [1:0]                cfg_rowpress_curve;
    logic                      cfg_victim3_en;
    logic                      i_dram_abo_alert;
    logic [15:0]               o_abo_alert_cnt;
    logic [15:0]               o_ecc_miscorrect_cnt;
    logic                      o_coordinated_throttle_active;
    logic [15:0]               o_rfm_auto_cnt;
    logic                      o_tras_clamped_alert;

    logic [1:0]                cfg_scramble_mode;
    logic                      cfg_decoy_en;
    logic                      cfg_fault_clr = 1'b0;
    logic                      fi_v9         = 1'b0;
    logic                      o_decoy_active;
    logic [15:0]               o_decoy_cnt;
    logic [8:0]                o_fault_cause;
    logic                      o_glitch_alert;
    logic                      o_security_locked;

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
        .DFI_WRLAT      (TB_DFI_WRLAT),
        .TCK_PS         (4000)
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
        .o_security_locked   (o_security_locked)
    );

    // Bộ kiểm tra giao thức JEDEC gắn trên đầu ra command engine (trước bus scrambler).
    // Mô hình DRAM hành vi: dữ liệu ghi lưu theo địa chỉ word vật lý, dữ liệu đọc trả về sau RL (= T_CL của engine)
    dram_model #(.COL_W(COL_WIDTH), .RL(8), .WL(TB_DFI_WRLAT)) u_dram (
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

    dfi_jedec_checker #(.TCK_PS(4000), .TB_DFI_WRLAT(TB_DFI_WRLAT)) u_jchk (.len(dut.u_cmd_engine.o_dfi_len), 
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
        .AXI_ID_W   (AXI_ID_WIDTH)
    ) u_achk (
        .clk           (clk_axi),
        .rst_n         (dut.rst_n_axi),
        .en_v2         (1'b1),
        .chk_data_en   (1'b0),
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
        .TAG_W   (4),
        .T_RDV   (9)
    ) u_echk (
        .clk                 (clk_axi),
        .rst_n               (dut.rst_n_axi),
        .en_v2               (1'b1),
        .fi_any              (fi_v9),
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
        .ROB_DEPTH (ROB_DEPTH)
    ) u_pchk (
        .clk    (clk_axi),
        .rst_n  (dut.rst_n_axi),
        .en_v2  (1'b1),
        .fi_any (fi_v9)
    );

    initial begin
        $dumpfile("waveform_security_attacks.vcd");
        $dumpvars(0, tb_security_attacks_vcd);
    end

    `include "tb_check.svh"

    localparam logic [2:0] CMD_ACT = 3'b001;
    localparam logic [2:0] CMD_REF = 3'b101;
    localparam int KEY_W = BG_WIDTH + BANK_WIDTH + ROW_WIDTH;

    //-------------------------------------------------------------------------
    // Monitor DFI: ghi lại mọi ACT (kẻ tấn công thực sự gây nhiễu hàng) và mọi lệnh giảm thiểu (REF kèm row).
    // Phán định dựa trên lệnh thực sự xuất ra DRAM, không dựa trên cờ nội bộ tự báo cáo của DUT.
    //-------------------------------------------------------------------------
    logic [KEY_W-1:0] act_log [$];
    logic [KEY_W-1:0] ref_log [$];
    bit coord_seen;
    bit tras_clamp_seen;
    logic [BG_WIDTH+BANK_WIDTH-1:0] rp_watch;
    int rp_watch_cnt;

    always @(posedge clk_axi) begin
        if (aresetn_axi && dut.ddr_rowpress_alert && {dut.ddr_rowpress_bg, dut.ddr_rowpress_bank} == rp_watch)
            rp_watch_cnt <= rp_watch_cnt + 1;
    end
    logic [BG_WIDTH+BANK_WIDTH-1:0] pre_log [$];

    // Beat ghi cuối cùng thấy trên bus DQ (kiểm tra xáo trộn dữ liệu ở V15)
    logic [63:0] dq_last_wrdata;
    bit          dq_wr_seen;
    always @(posedge clk_axi) if (dfi_wrdata_en) begin dq_last_wrdata <= dfi_wrdata; dq_wr_seen <= 1; end

    // Thời gian mở hàng dài nhất của bank rp_watch, đo trên DFI (ACT tới PRE hoặc REFab/RFMab đóng mọi bank).
    int  open_max;
    int  open_t0;
    bit  open_now;
    int  mon_cyc;
    always @(posedge clk_axi) begin
        mon_cyc <= mon_cyc + 1;
        if (!aresetn_axi) begin
            open_now <= 0;
        end else begin
            if (open_now && (mon_cyc - open_t0) > open_max) open_max <= mon_cyc - open_t0;
            if (dut.u_cmd_engine.o_dfi_cmd == CMD_ACT &&
                {dut.u_cmd_engine.o_dfi_bg, dut.u_cmd_engine.o_dfi_bank} == rp_watch) begin
                open_now <= 1;
                open_t0  <= mon_cyc;
            end else if ((dut.u_cmd_engine.o_dfi_cmd == 3'b010 &&
                          {dut.u_cmd_engine.o_dfi_bg, dut.u_cmd_engine.o_dfi_bank} == rp_watch) ||
                         dut.u_cmd_engine.o_dfi_cmd == CMD_REF || dut.u_cmd_engine.o_dfi_cmd == 3'b110) begin
                open_now <= 0;
            end
        end
    end

    wire victim_act = dut.u_cmd_engine.dfi_act_mit;

    always @(posedge clk_axi) begin
        if (aresetn_axi) begin
            // Refresh nạn nhân là ACT phát ở chế độ giảm thiểu (ACT -> tRAS -> PRE); REFab định kỳ không mang địa chỉ hàng.
            // ref_log giữ nghĩa "hàng nạn nhân đã được làm tươi", act_log chỉ chứa ACT do traffic.
            if (dfi_cmd == CMD_ACT) begin
                if (victim_act) ref_log.push_back({dfi_bg, dfi_bank, dfi_row});
                else            act_log.push_back({dfi_bg, dfi_bank, dfi_row});
            end
            if (dfi_cmd == 3'b010) pre_log.push_back({dfi_bg, dfi_bank});
            if (o_coordinated_throttle_active) coord_seen <= 1'b1;
            if (o_tras_clamped_alert) tras_clamp_seen <= 1'b1;
        end
    end

    // Monitor Jailbreak (MOAT): số ACT lớn nhất mà hàng mục tiêu tích lũy giữa hai lần refresh nạn nhân kề (R±1).
    logic [KEY_W-1:0] jb_key;
    bit               jb_on;
    int               jb_acts;
    int               jb_run;
    int               jb_max_run;

    always @(posedge clk_axi) begin
        if (aresetn_axi && jb_on) begin
            if (dfi_cmd == CMD_ACT && !victim_act && {dfi_bg, dfi_bank, dfi_row} == jb_key) begin
                jb_acts <= jb_acts + 1;
                jb_run  <= jb_run + 1;
                if (jb_run + 1 > jb_max_run) jb_max_run <= jb_run + 1;
            end else if (dfi_cmd == CMD_ACT && victim_act && {dfi_bg, dfi_bank} == jb_key[KEY_W-1:ROW_WIDTH] &&
                         (dfi_row == jb_key[ROW_WIDTH-1:0] + 1 || dfi_row == jb_key[ROW_WIDTH-1:0] - 1)) begin
                jb_run <= 0;
            end
        end
    end

    // Monitor kênh R: đếm burst hoàn tất theo ID để kiểm tra không mất/nhân đôi phản hồi và đo độ trễ QoS.
    int                         r_done_cnt [16];
    logic [AXI_DATA_WIDTH-1:0]  r_last_data [16];
    logic [1:0]                 r_last_resp [16];
    int                         ar_issued_cnt;
    int                         r_total_bursts;

    always @(posedge clk_axi) begin
        if (aresetn_axi && s_axi_rvalid && s_axi_rready) begin
            r_last_data[s_axi_rid] <= s_axi_rdata;
            r_last_resp[s_axi_rid] <= s_axi_rresp;
            if (s_axi_rlast) begin
                r_done_cnt[s_axi_rid] <= r_done_cnt[s_axi_rid] + 1;
                r_total_bursts        <= r_total_bursts + 1;
            end
        end
    end

    function automatic logic [AXI_ADDR_WIDTH-1:0] mk_addr(input int row, input int bg, input int bank);
        logic [AXI_ADDR_WIDTH-1:0] a;
        a = '0;
        a[31:18] = row[13:0];
        a[17:16] = bank[1:0];
        a[8:6]   = bg[2:0] ^ row[2:0];
        return a;
    endfunction

    // Hàng vật lý của ACT đầu tiên trong log (-1 nếu chưa có ACT).
    function automatic int first_act_row();
        logic [KEY_W-1:0] e;
        if (act_log.size() == 0) return -1;
        e = act_log[0];
        return int'(e[ROW_WIDTH-1:0]);
    endfunction

    function automatic logic [KEY_W-1:0] mk_key(input int row, input int bg, input int bank);
        return {bg[BG_WIDTH-1:0], bank[BANK_WIDTH-1:0], row[ROW_WIDTH-1:0]};
    endfunction

    function automatic int count_acts(input logic [KEY_W-1:0] key);
        int n = 0;
        logic [KEY_W-1:0] e;
        for (int i = 0; i < act_log.size(); i++) begin
            e = act_log[i];
            if (e == key) n++;
        end
        return n;
    endfunction

    // Số lệnh giảm thiểu nhắm vào hàng nạn nhân ở khoảng cách [dmin, dmax] quanh hàng aggressor cùng BG/bank.
    function automatic int mitig_near(input logic [KEY_W-1:0] aggr, input int dmin, input int dmax);
        int n = 0;
        int d;
        logic [KEY_W-1:0] e;
        for (int i = 0; i < ref_log.size(); i++) begin
            e = ref_log[i];
            if (e[KEY_W-1:ROW_WIDTH] == aggr[KEY_W-1:ROW_WIDTH]) begin
                d = int'(e[ROW_WIDTH-1:0]) - int'(aggr[ROW_WIDTH-1:0]);
                if (d < 0) d = -d;
                if (d >= dmin && d <= dmax) n++;
            end
        end
        return n;
    endfunction

    // Một master AXI chỉ phát một AR tại một thời điểm: khóa tránh hai luồng fork ghi đè arid/araddr của nhau.
    bit ar_busy;

    // Đo độ trễ phía DRAM: số chu kỳ từ khi AR được chấp nhận tới khi ACT của hàng đích xuất hiện trên DFI.
    // Tách khỏi chặn đầu hàng ở ROB (R18) để chỉ đo tác động của lệnh giảm thiểu lên lịch DRAM.
    task automatic dram_latency(input int row, input int bg, input int bank, input logic [AXI_ID_WIDTH-1:0] id,
                                input int max_cycles, output int lat);
        logic [KEY_W-1:0] key;
        int base;
        key = mk_key(row, bg, bank);
        base = count_acts(key);
        axi_read(id, mk_addr(row, bg, bank), 4'd7);
        lat = -1;
        for (int c = 0; c < max_cycles && lat < 0; c++) begin
            @(posedge clk_axi);
            if (count_acts(key) > base) lat = c;
        end
    endtask

    // Kẻ tấn công rải hammer qua nhiều hàng, mỗi hàng đúng ngưỡng: né throttle theo hàng nhưng ép nhiều lệnh giảm thiểu.
    // spread=0: mỗi hàng đúng ngưỡng (ép lệnh giảm thiểu); spread=1: cùng số request nhưng mỗi request một hàng (đối chứng).
    task automatic perf_attack_burst(input int base_row, input int n_rows, input bit spread);
        for (int r = 0; r < n_rows; r++) begin
            for (int k = 0; k < 3; k++) begin
                axi_read(4'hA, mk_addr(base_row + 4 * (spread ? (3 * r + k) : r), 1, 1), 4'd0);
            end
        end
    endtask

    task automatic clear_logs();
        act_log.delete();
        ref_log.delete();
        pre_log.delete();
    endtask

    task automatic axi_read(input logic [AXI_ID_WIDTH-1:0] id, input logic [AXI_ADDR_WIDTH-1:0] addr,
                            input logic [AXI_QOS_WIDTH-1:0] qos);
        while (ar_busy) @(posedge clk_axi);
        ar_busy = 1'b1;
        @(negedge clk_axi);
        s_axi_arid    <= id;
        s_axi_araddr  <= addr;
        s_axi_arlen   <= 8'd0;
        s_axi_arsize  <= 3'd3;
        s_axi_arburst <= 2'b01;
        s_axi_arqos   <= qos;
        s_axi_arvalid <= 1'b1;
        @(posedge clk_axi);
        while (!s_axi_arready) @(posedge clk_axi);
        ar_issued_cnt++;
        @(negedge clk_axi);
        s_axi_arvalid <= 1'b0;
        ar_busy = 1'b0;
    endtask

    // Reset DUT giữa các vector để mỗi cơ chế phòng thủ được đánh giá độc lập (không bị trạng thái ATE/hàng đợi tích lũy che lấp).
    task automatic reset_dut();
        @(negedge clk_axi);
        aresetn_axi = 0;
        aresetn_ddr = 0;
        repeat (5) @(posedge clk_axi);
        aresetn_axi = 1;
        aresetn_ddr = 1;
        repeat (15) @(posedge clk_axi);
        clear_logs();
        coord_seen = 0;
        tras_clamp_seen = 0;
        jb_on = 0;
    endtask

    task automatic axi_write(input logic [AXI_ID_WIDTH-1:0] id, input logic [AXI_ADDR_WIDTH-1:0] addr,
                             input logic [AXI_DATA_WIDTH-1:0] data, input logic [AXI_QOS_WIDTH-1:0] qos);
        @(negedge clk_axi);
        s_axi_awid    <= id;
        s_axi_awaddr  <= addr;
        s_axi_awlen   <= 8'd0;
        s_axi_awsize  <= 3'd3;
        s_axi_awburst <= 2'b01;
        s_axi_awqos   <= qos;
        s_axi_awvalid <= 1'b1;
        s_axi_wdata   <= data;
        s_axi_wstrb   <= 8'hFF;
        s_axi_wlast   <= 1'b1;
        s_axi_wvalid  <= 1'b1;
        fork
            begin
                @(posedge clk_axi);
                while (!s_axi_awready) @(posedge clk_axi);
                @(negedge clk_axi);
                s_axi_awvalid <= 1'b0;
            end
            begin
                @(posedge clk_axi);
                while (!s_axi_wready) @(posedge clk_axi);
                @(negedge clk_axi);
                s_axi_wvalid <= 1'b0;
            end
        join
        while (!s_axi_bvalid) @(posedge clk_axi);
    endtask

    // Chờ burst R của một ID hoàn tất; trả về độ trễ (chu kỳ) hoặc -1 nếu quá thời hạn.
    task automatic wait_r(input int id, input int prev_cnt, input int max_cycles, output int latency);
        latency = -1;
        for (int c = 0; c < max_cycles && latency < 0; c++) begin
            @(posedge clk_axi);
            if (r_done_cnt[id] > prev_cnt) latency = c;
        end
    endtask

    // Chờ hệ thống tĩnh: mọi AR đã có R, hàng đợi cảnh báo/PROQ của DRM rỗng, command engine rảnh.
    // Refresh nạn nhân bằng ACT và REF/RFM định kỳ có chi phí thật, nên chờ số chu kỳ cố định không còn đáng tin.
    task automatic wait_quiesce(input int max_cycles);
        int c;
        c = 0;
        while (c < max_cycles && !(ar_issued_cnt == r_total_bursts && dut.u_drm.queue_empty && dut.u_drm.af_empty &&
                                   dut.u_drm.inj_oh == 7'b0000001 && dut.u_cmd_engine.s_v == '0)) begin
            @(posedge clk_axi);
            c++;
        end
        repeat (5) @(posedge clk_axi);
    endtask

    task automatic hammer_pair(input int row_a, input int row_b, input int bg, input int bank,
                               input int rounds, input int gap, input logic [AXI_ID_WIDTH-1:0] id);
        for (int i = 0; i < rounds; i++) begin
            axi_read(id, mk_addr(row_a, bg, bank), 4'd1);
            repeat (gap) @(posedge clk_axi);
            axi_read(id, mk_addr(row_b, bg, bank), 4'd1);
            repeat (gap) @(posedge clk_axi);
        end
    endtask

    initial begin
        int thr0, d, lat, prev, hot, covered, k, acts_before, base_lat;
        int phys [8];
        logic [AXI_DATA_WIDTH-1:0] wdat;

        aresetn_axi = 0;
        aresetn_ddr = 0;
        s_axi_awid = 0; s_axi_awaddr = 0; s_axi_awlen = 0; s_axi_awsize = 3; s_axi_awburst = 1; s_axi_awqos = 0; s_axi_awvalid = 0;
        s_axi_wdata = 0; s_axi_wstrb = 0; s_axi_wlast = 0; s_axi_wvalid = 0;
        s_axi_bready = 1;
        s_axi_arid = 0; s_axi_araddr = 0; s_axi_arlen = 0; s_axi_arsize = 3; s_axi_arburst = 1; s_axi_arqos = 0; s_axi_arvalid = 0;
        s_axi_rready = 1;
        foreach (r_done_cnt[i]) r_done_cnt[i] = 0;
        ar_issued_cnt = 0;
        r_total_bursts = 0;
        coord_seen = 0;
        tras_clamp_seen = 0;

        cfg_is_ddr5 = 1;
        cfg_dual_hash_en = 1;
        cfg_rh_threshold = 16'd3;
        cfg_window_size = 16'd1000;
        cfg_bank_coloring_en = 0;
        cfg_mapping_mode = 2'b00;
        cfg_scramble_en = 0;
        cfg_scramble_mode = 2'b00;
        cfg_scramble_seed = 64'hFEDC_BA98_7654_3210;
        cfg_scramble_reseed = 0;
        cfg_pmu_en = 1;
        cfg_pmu_reset = 0;
        cfg_rowpress_curve = 2'b01;
        cfg_victim3_en = 1;
        i_dram_abo_alert = 0;
        cfg_decoy_en = 0;

        repeat (10) @(posedge clk_axi);
        aresetn_axi = 1;
        aresetn_ddr = 1;
        repeat (15) @(posedge clk_axi);

        // Độ trễ đọc nền khi không tải: làm mốc cho các giới hạn QoS (không dùng hằng số tùy ý).
        prev = r_done_cnt[8];
        axi_read(4'h8, mk_addr(16'h0E0, 2, 2), 4'd7);
        wait_r(8, prev, 400, base_lat);
        tb_check(base_lat >= 0, $sformatf("Baseline unloaded read latency = %0d cycles", base_lat));

        // V0 Adaptive threshold: hammer kéo dài không được nới lỏng ngưỡng phát hiện vượt quá giá trị cấu hình.
        $display("[VECTOR 0] Adaptive threshold must not loosen under sustained hammering");
        hammer_pair(16'h050, 16'h052, 1, 2, 40, 1, 4'h1);
        repeat (50) @(posedge clk_axi);
        tb_check(dut.ate_dynamic_thresh <= cfg_rh_threshold,
                       $sformatf("V0 effective SDC threshold %0d after hammering (configured %0d)",
                                 dut.ate_dynamic_thresh, cfg_rh_threshold));

        // V1 Double-sided RowHammer: aggressor R-1/R+1 cùng BG/bank kẹp nạn nhân R → phải có REF tới R.
        reset_dut();
        $display("[VECTOR 1] Double-sided RowHammer (R-1, R+1) around victim R=0x40");
        clear_logs();
        thr0 = o_throttled_events;
        hammer_pair(16'h3F, 16'h41, 2, 1, 8, 2, 4'h1);
        wait_quiesce(20000);
        tb_check(count_acts(mk_key(16'h3F, 2, 1)) >= cfg_rh_threshold && count_acts(mk_key(16'h41, 2, 1)) >= cfg_rh_threshold,
                 $sformatf("V1 precondition: aggressors activated on DFI (%0d, %0d ACTs)",
                           count_acts(mk_key(16'h3F, 2, 1)), count_acts(mk_key(16'h41, 2, 1))));
        tb_check(o_throttled_events > thr0, $sformatf("V1 SDC filter throttled aggressors (+%0d)", o_throttled_events - thr0));
        tb_check(mitig_near(mk_key(16'h3F, 2, 1), 1, 1) > 0 || mitig_near(mk_key(16'h41, 2, 1), 1, 1) > 0,
                 $sformatf("V1 targeted refresh reached victim neighbourhood (%0d REF issued in total)", ref_log.size()));

        // V2 Cross-epoch split: (ngưỡng-1) lần/cửa sổ trong nhiều cửa sổ → tổng ACT vượt xa ngưỡng trong tREFW.
        reset_dut();
        $display("[VECTOR 2] Cross-epoch split hammer: threshold-1 ACTs per window, 10 windows");
        cfg_window_size = 16'd200;
        repeat (5) @(posedge clk_axi);
        clear_logs();
        thr0 = o_throttled_events;
        for (int w = 0; w < 10; w++) begin
            hammer_pair(16'h101, 16'h103, 3, 2, 1, 1, 4'h2);
            repeat (170) @(posedge clk_axi);
        end
        repeat (40) @(posedge clk_axi);
        tb_check(count_acts(mk_key(16'h101, 3, 2)) >= 8,
                 $sformatf("V2 precondition: aggressor accumulated %0d ACTs (>> threshold 3)", count_acts(mk_key(16'h101, 3, 2))));
        tb_check(o_throttled_events > thr0 || mitig_near(mk_key(16'h101, 3, 2), 1, 1) > 0,
                 $sformatf("V2 cumulative hammering across epochs must be mitigated (throttle +%0d, victim refresh %0d)",
                           o_throttled_events - thr0, ref_log.size()));
        cfg_window_size = 16'd1000;

        // V3 Blacksmith: 8 aggressor tần số không đều; mọi hàng "nóng" (ACT ≥ 2×ngưỡng) phải được giảm thiểu.
        reset_dut();
        $display("[VECTOR 3] Blacksmith non-uniform many-sided hammer (8 aggressors)");
        clear_logs();
        for (int rep = 0; rep < 6; rep++) begin
            for (int a = 0; a < 8; a++) begin
                if ((rep % (1 + (a % 3))) == 0) begin
                    axi_read(4'h3, mk_addr(16'h200 + 2 * a, 4, 0), 4'd1);
                    repeat (1 + (a % 2)) @(posedge clk_axi);
                end
            end
        end
        wait_quiesce(20000);
        hot = 0;
        covered = 0;
        // Bộ lọc cho phép đúng T ACT và giảm thiểu ở ACT thứ T+1: "nóng" = vượt ngưỡng (> T).
        for (int a = 0; a < 8; a++) begin
            if (count_acts(mk_key(16'h200 + 2 * a, 4, 0)) > cfg_rh_threshold) begin
                hot++;
                if (mitig_near(mk_key(16'h200 + 2 * a, 4, 0), 1, 2) > 0) covered++;
            end
        end
        tb_check(hot > 0, $sformatf("V3 precondition: %0d hot aggressor rows", hot));
        tb_check(covered == hot, $sformatf("V3 every hot aggressor got targeted refresh (%0d/%0d)", covered, hot));

        // V4 RowPress: giữ hàng mở lâu hơn ngưỡng RowPress (5000 chu kỳ) → phải có cảnh báo/PRE cưỡng bức.
        reset_dut();
        $display("[VECTOR 4] RowPress: keep row open > RowPress threshold");
        clear_logs();
        rp_watch = {3'd5, 2'd3};
        rp_watch_cnt = 0;
        open_max = 0;
        axi_read(4'h4, mk_addr(16'h300, 5, 3), 4'd1);
        repeat (5600) @(posedge clk_axi);
        // REFab định kỳ đóng mọi hàng nên thời gian mở bị chặn trên bởi ~tREFI (hoãn tối đa 5 x tREFI).
        // Curve 1 chỉ cảnh báo khi hàng mở >= 2500 chu kỳ: an toàn nếu hàng bị đóng trước mốc đó, ngược lại phải có cảnh báo.
        $display("  [DIAG] V4 curve 1: longest open interval %0d cycles, %0d alerts", open_max, rp_watch_cnt);
        tb_check(open_max < 2500 || rp_watch_cnt > 0,
                 $sformatf("V4 RowPress curve 1: row closed before alert point or alert raised (open %0d, %0d alerts)", open_max, rp_watch_cnt));
        tb_check(open_max <= 5 * u_jchk.REFI_CYC, $sformatf("V4 row-open time bounded by refresh (%0d cycles)", open_max));
        // Reset để hàng của phần trước không chạm tRAS(max) và gây cảnh báo lẫn vào phép đo curve 2.
        reset_dut();
        cfg_rowpress_curve = 2'b10;
        repeat (5) @(posedge clk_axi);
        rp_watch = {3'd5, 2'd2};
        rp_watch_cnt = 0;
        open_max = 0;
        axi_read(4'h4, mk_addr(16'h310, 5, 2), 4'd1);
        repeat (5600) @(posedge clk_axi);
        // Curve 2 cảnh báo ở mốc 1501 chu kỳ (ngưỡng giảm còn 1250): kiểm tra phép so sánh >= với ngưỡng giảm dần.
        $display("  [DIAG] V4 curve 2: longest open interval %0d cycles, %0d alerts", open_max, rp_watch_cnt);
        tb_check(open_max < 1501 || rp_watch_cnt > 0,
                 $sformatf("V4 RowPress curve 2: row closed before alert point or alert raised (open %0d, %0d alerts)", open_max, rp_watch_cnt));
        cfg_rowpress_curve = 2'b01;

        // V5 SledgeHammer: tấn công đồng thời 4 bank → phải kích hoạt throttling phối hợp đa bank.
        reset_dut();
        $display("[VECTOR 5] SledgeHammer synchronized multi-bank burst");
        coord_seen = 0;
        for (int r = 0; r < 8; r++) begin
            for (int b = 0; b < 4; b++) begin
                axi_read(4'h5, mk_addr(16'h400 + 2 * (r % 2), 6, b), 4'd2);
                @(posedge clk_axi);
            end
        end
        repeat (40) @(posedge clk_axi);
        $display("  [DIAG] V5 adaptive SDC threshold = %0d (configured %0d)", dut.ate_dynamic_thresh, cfg_rh_threshold);
        tb_check(coord_seen, "V5 coordinated multi-bank throttle activated");

        // V7 Dual-hash false positive: sau khi hàng A "nóng", một truy cập đơn lẻ tới hàng B lành tính không được bị chặn.
        reset_dut();
        $display("[VECTOR 7] Dual-hash: benign row must not be throttled after hot row");
        hammer_pair(16'h500, 16'h502, 7, 1, 4, 1, 4'h7);
        // Mốc đếm lấy sau khi luồng hammer đã chảy hết: lệnh hammer còn trong pipeline bị điều tiết sau mốc không được
        // tính nhầm cho truy cập lành tính
        wait_quiesce(5000);
        thr0 = o_throttled_events;
        axi_read(4'h7, mk_addr(16'h1A55, 1, 3), 4'd1);
        repeat (30) @(posedge clk_axi);
        tb_check(o_throttled_events == thr0, $sformatf("V7 benign single access not throttled (+%0d)", o_throttled_events - thr0));

        // V8 QoS: yêu cầu QoS cao phải hoàn tất trong giới hạn khi bank khác đang bị hammer bởi QoS thấp.
        reset_dut();
        $display("[VECTOR 8] High-QoS latency under low-QoS hammering");
        fork
            hammer_pair(16'h600, 16'h602, 0, 0, 6, 0, 4'h0);
            begin
                repeat (10) @(posedge clk_axi);
                prev = r_done_cnt[9];
                axi_read(4'h9, mk_addr(16'h0F0, 3, 1), 4'd7);
                wait_r(9, prev, 400, lat);
            end
        join
        // ROB đã retire theo từng ID (R18 đóng); phần trễ còn lại là chặn đầu hàng trước DRAM (R20).
        // R20 đóng: engine song song theo bank, hàng đợi phát lệnh có tín dụng BG và điều khiển nhập AR theo QoS
        tb_check(lat >= 0 && lat <= 2 * base_lat,
                 $sformatf("V8 high-QoS read completed in %0d cycles (bound 2x baseline = %0d)", lat, 2 * base_lat));

        // V10 Toàn vẹn dữ liệu: ghi rồi đọc lại phải ra đúng dữ liệu, phản hồi OKAY.
        reset_dut();
        $display("[VECTOR 10] Write/read-back data integrity");
        wdat = 64'hDEAD_BEEF_CAFE_BABE;
        axi_write(4'h1, mk_addr(16'h700, 1, 0), wdat, 4'd4);
        prev = r_done_cnt[1];
        axi_read(4'h1, mk_addr(16'h700, 1, 0), 4'd4);
        wait_r(1, prev, 400, lat);
        tb_check(lat >= 0, "V10 read-back completed");
        tb_check(r_last_data[1] === wdat,
                       $sformatf("V10 read-back data equals written (wrote %h, read %h)", wdat, r_last_data[1]));

        // V11 Fuzz: mọi AR phải nhận đúng một burst R (không mất, không nhân đôi phản hồi).
        reset_dut();
        $display("[VECTOR 11] Adversarial fuzz: 50 reads, response accounting");
        repeat (200) @(posedge clk_axi);
        prev = r_total_bursts;
        k = ar_issued_cnt;
        for (int beat = 0; beat < 50; beat++) begin
            axi_read(beat[3:0], {$urandom} & 32'hFFFF_FFC0, beat[2:0]);
            repeat (1 + (beat % 3)) @(posedge clk_axi);
        end
        repeat (600) @(posedge clk_axi);
        tb_check(r_total_bursts - prev == ar_issued_cnt - k,
                 $sformatf("V11 R bursts (%0d) match AR issued (%0d)", r_total_bursts - prev, ar_issued_cnt - k));

        // V12 Phoenix: hammer kéo dài liên tục → bộ đếm RFM tự động phải tăng (RFM không bị đói bởi lưu lượng).
        reset_dut();
        $display("[VECTOR 12] Phoenix: sustained hammering must trigger autonomous RFM");
        thr0 = o_rfm_auto_cnt;
        hammer_pair(16'h800, 16'h802, 5, 0, 40, 0, 4'hC);
        repeat (100) @(posedge clk_axi);
        tb_check(o_rfm_auto_cnt > thr0, $sformatf("V12 autonomous RFM issued (+%0d)", o_rfm_auto_cnt - thr0));

        // V13 Half-Double: phải có refresh tới nạn nhân ở khoảng cách 2.
        reset_dut();
        $display("[VECTOR 13] Half-Double: distance-2 victim refresh");
        clear_logs();
        hammer_pair(16'h900, 16'h904, 6, 2, 10, 1, 4'hD);
        repeat (80) @(posedge clk_axi);
        tb_check(mitig_near(mk_key(16'h900, 6, 2), 2, 2) > 0 || mitig_near(mk_key(16'h904, 6, 2), 2, 2) > 0,
                 $sformatf("V13 distance-2 victim refresh issued (%0d REF total)", ref_log.size()));

        // V14 TRRespass: 16 aggressor; mọi hàng nóng phải được giảm thiểu (không tràn bảng theo dõi).
        reset_dut();
        $display("[VECTOR 14] TRRespass 16-aggressor many-sided");
        clear_logs();
        for (int round = 0; round < 4; round++) begin
            for (int r = 0; r < 16; r++) begin
                axi_read(r[3:0], mk_addr(16'hA00 + 2 * r, 2, 3), 4'd2);
                @(posedge clk_axi);
            end
        end
        wait_quiesce(40000);
        $display("  [DIAG] V14 adaptive SDC threshold = %0d, victim refreshes = %0d", dut.ate_dynamic_thresh, ref_log.size());
        hot = 0;
        covered = 0;
        for (int r = 0; r < 16; r++) begin
            if (count_acts(mk_key(16'hA00 + 2 * r, 2, 3)) > cfg_rh_threshold) begin
                hot++;
                if (mitig_near(mk_key(16'hA00 + 2 * r, 2, 3), 1, 2) > 0) covered++;
                else $display("  [DIAG] V14 unmitigated aggressor row 0x%0h (%0d ACT)", 16'hA00 + 2 * r,
                              count_acts(mk_key(16'hA00 + 2 * r, 2, 3)));
            end
        end
        tb_check(hot > 0, $sformatf("V14 precondition: %0d hot aggressor rows", hot));
        tb_check(covered == hot, $sformatf("V14 every hot aggressor got targeted refresh (%0d/%0d)", covered, hot));

        // V16 Throwhammer: burst DMA QoS thấp vào một hàng phải bị throttle, request QoS cao vẫn được phục vụ.
        reset_dut();
        $display("[VECTOR 16] Throwhammer DMA burst");
        thr0 = o_throttled_events;
        for (int i = 0; i < 10; i++) axi_read(4'hE, mk_addr(16'hB00 + 2 * (i % 2), 0, 2), 4'd0);
        prev = r_done_cnt[15];
        axi_read(4'hF, mk_addr(16'h0C0, 4, 1), 4'd7);
        wait_r(15, prev, 400, lat);
        $display("  [DIAG] V16 adaptive SDC threshold = %0d (configured %0d)", dut.ate_dynamic_thresh, cfg_rh_threshold);
        tb_check(o_throttled_events > thr0, $sformatf("V16 DMA burst throttled (+%0d)", o_throttled_events - thr0));
        // JEDEC cho phép một REFab/RFMab chặn mọi bank trong tRFC: cận = 2x baseline + một tRFC.
        tb_check(lat >= 0 && lat <= 2 * base_lat + u_jchk.RFC_CYC,
                 $sformatf("V16 high-QoS read served in %0d cycles (bound 2x baseline + tRFC = %0d)", lat, 2 * base_lat + u_jchk.RFC_CYC));

        // V17 Decoy: decoy phải tạo truy cập DRAM thật (ACT) để che giấu mẫu truy cập; NOP không che giấu được gì.
        reset_dut();
        $display("[VECTOR 17] Decoy accesses must reach DRAM");
        repeat (200) @(posedge clk_axi);
        clear_logs();
        k = o_decoy_cnt;
        cfg_decoy_en = 1;
        repeat (60) @(posedge clk_axi);
        cfg_decoy_en = 0;
        tb_check(o_decoy_cnt > k, $sformatf("V17 decoy engine active (+%0d)", o_decoy_cnt - k));
        tb_check(act_log.size() > 0,
                       $sformatf("V17 decoy produced real DRAM activations (%0d ACT)", act_log.size()));

        // V18 Perf-Attack (BreakHammer, MICRO'24): ép nhiều preventive action để làm chậm tenant lành tính ở BG khác.
        reset_dut();
        $display("[VECTOR 18] Perf-attack: mitigation flood must not starve a benign tenant");
        begin
            int base_sum, att_sum, l, n_ok;
            base_sum = 0;
            n_ok = 0;
            for (int t = 0; t < 6; t++) begin
                dram_latency(16'h1100 + 2 * t, 7, 3, 4'h6, 400, l);
                if (l >= 0) begin
                    base_sum += l;
                    n_ok++;
                end
                repeat (30) @(posedge clk_axi);
            end
            tb_check(n_ok == 6, $sformatf("V18 baseline benign requests reached DRAM (%0d/6)", n_ok));
            // Đối chứng: cùng khối lượng request nhưng không hàng nào vượt ngưỡng → tách tác động của lệnh giảm thiểu khỏi xếp hàng.
            begin
                int ctl_sum, ctl_ok, att_ok, ref_att, ref_ctl;
                reset_dut();
                k = ref_log.size();
                ctl_sum = 0;
                ctl_ok = 0;
                for (int t = 0; t < 6; t++) begin
                    perf_attack_burst(16'h1200 + 128 * t, 6, 1'b1);
                    dram_latency(16'h1180 + 2 * t, 7, 3, 4'h6, 2000, l);
                    if (l >= 0) begin
                        ctl_sum += l;
                        ctl_ok++;
                    end
                end
                ref_ctl = ref_log.size() - k;
                reset_dut();
                k = ref_log.size();
                att_sum = 0;
                att_ok = 0;
                for (int t = 0; t < 6; t++) begin
                    perf_attack_burst(16'h1200 + 128 * t, 6, 1'b0);
                    dram_latency(16'h1180 + 2 * t, 7, 3, 4'h6, 2000, l);
                    if (l >= 0) begin
                        att_sum += l;
                        att_ok++;
                    end
                end
                ref_att = ref_log.size() - k;
                $display("  [DIAG] V18 benign DRAM latency avg: baseline %0d, control load %0d, perf-attack %0d cycles; REF control %0d, attack %0d",
                         base_sum / 6, ctl_sum / 6, att_sum / 6, ref_ctl, ref_att);
                tb_check(ref_att > ref_ctl, $sformatf("V18 precondition: attack forced extra preventive refreshes (%0d vs %0d)", ref_att, ref_ctl));
                tb_check(att_ok == 6 && ctl_ok == 6 && 2 * att_sum <= 3 * ctl_sum,
                         $sformatf("V18a mitigation flood adds <= 50%% benign latency over same-volume control (%0d vs %0d)", att_sum, ctl_sum));
                tb_check(ctl_sum <= 2 * base_sum,
                               $sformatf("V18b QoS7 request to idle BG bypasses queued QoS0 traffic (%0d vs baseline %0d)", ctl_sum, base_sum));
            end
        end

        // V19 LeakyHammer/PRACLeak (MICRO'25, ISCA'25): người gửi bật/tắt hành động giảm thiểu, người nhận đo độ trễ của chính mình.
        reset_dut();
        $display("[VECTOR 19] LeakyHammer covert channel through mitigation timing");
        begin
            int lat1 [16];
            int msg [16];
            int sum0, sum1, n0, n1, correct, l;
            real thr_mid;
            for (int b = 0; b < 16; b++) begin
                msg[b] = (32'hB5A3 >> b) & 1;
                lat1[b] = 0;
                // Mỗi bit gửi 3 lần, người nhận lấy trung bình: lọc nhiễu do REF định kỳ trùng phép đo (một mẫu lẻ có thể lệch vài trăm chu kỳ)
                for (int rep = 0; rep < 3; rep++) begin
                    // Cả hai ký hiệu phát cùng số request; chỉ ký hiệu 1 dồn vào 2 hàng (vượt ngưỡng), ký hiệu 0 rải 12 hàng khác nhau.
                    for (int k2 = 0; k2 < 12; k2++) begin
                        if (msg[b] == 1) axi_read(4'hB, mk_addr(16'h0400 + 64 * (3 * b + rep) + 2 * (k2 % 2), 2, 0), 4'd0);
                        else             axi_read(4'hB, mk_addr(16'h2000 + 64 * (3 * b + rep) + 4 * k2, 2, 0), 4'd0);
                    end
                    dram_latency(16'h3C00 + 2 * (3 * b + rep), 2, 3, 4'h3, 2000, l);
                    lat1[b] += l;
                    repeat (100) @(posedge clk_axi);
                end
                lat1[b] = lat1[b] / 3;
            end
            sum0 = 0; sum1 = 0; n0 = 0; n1 = 0;
            for (int b = 0; b < 16; b++) begin
                if (msg[b] == 1) begin sum1 += lat1[b]; n1++; end
                else             begin sum0 += lat1[b]; n0++; end
            end
            // Ngưỡng = trung vị 16 mẫu: trung bình bị vài mẫu trùng REF kéo lệch (vòng 5: avg 59 vs 108 nhưng chỉ 9/16),
            // kẻ tấn công thật dùng bộ thu bền vững nên phép đo phải dùng ít nhất mức này
            begin
                int srt [16];
                for (int b = 0; b < 16; b++) srt[b] = lat1[b];
                for (int i = 1; i < 16; i++) begin
                    int v, j;
                    v = srt[i];
                    j = i - 1;
                    while (j >= 0 && srt[j] > v) begin srt[j + 1] = srt[j]; j--; end
                    srt[j + 1] = v;
                end
                thr_mid = (real'(srt[7]) + real'(srt[8])) / 2.0;
            end
            correct = 0;
            for (int b = 0; b < 16; b++) begin
                if (((real'(lat1[b]) > thr_mid) ? 1 : 0) == ((sum1 / n1 > sum0 / n0) ? msg[b] : 1 - msg[b])) correct++;
            end
            for (int b = 0; b < 16; b++) $display("  [DIAG] V19 bit %0d sent %0d latency %0d", b, msg[b], lat1[b]);
            $display("  [DIAG] V19 receiver latency: symbol0 avg %0d, symbol1 avg %0d cycles; decoded %0d/16 bits",
                     sum0 / n0, sum1 / n1, correct);
            // Giảm thiểu nay có chi phí thật (ACT -> tRAS -> PRE) nên thời gian của nó quan sát được: kênh LeakyHammer mở (S24).
            // S24 đóng cho bên nhận ở bank khác: lệnh giảm thiểu chỉ chiếm bank của nó (engine song song theo bank) và
            // hàng đợi QoS chia chỗ theo bank (một chỗ riêng mỗi bank + quỹ chung), nên lệnh của bên gửi bị PROQ chặn không
            // lấy hết chỗ của bank bên nhận (trước đó bên nhận chờ tín dụng BG: 62 vs 134 chu kỳ).
            // Bên nhận cùng bank vẫn thấy được vì đó là tài nguyên vật lý dùng chung (giới hạn ghi trong LIMITATIONS.md).
            tb_check(correct <= 12, $sformatf("V19 receiver cannot decode sender bits from timing (%0d/16 correct, chance = 8)", correct));
        end

        // V20 ColumnDisturb (MICRO'25) / RowPress: một hàng không được mở quá JEDEC tRAS(max) = 9 x tREFI.
        // tREFI(DDR5) = 3.9 us -> 975 chu kỳ clk_axi 250 MHz -> tRAS(max) = 8775 chu kỳ.
        reset_dut();
        $display("[VECTOR 20] ColumnDisturb/RowPress: row open time bounded by JEDEC tRAS(max)");
        begin
            int opened_at, closed_after;
            logic [BG_WIDTH+BANK_WIDTH-1:0] bk;
            bk = {3'd6, 2'd1};
            axi_read(4'h4, mk_addr(16'h1E00, 6, 1), 4'd1);
            // Đo từ lúc ACT xuất hiện trên DFI (tRAS tính từ ACT, không tính độ trễ front-end).
            for (int c = 0; c < 200 && count_acts(mk_key(16'h1E00, 6, 1)) == 0; c++) @(posedge clk_axi);
            pre_log.delete();
            closed_after = -1;
            for (int c = 0; c < 12000 && closed_after < 0; c++) begin
                @(posedge clk_axi);
                for (int i = 0; i < pre_log.size(); i++) if (pre_log[i] == bk) closed_after = c;
            end
            tb_check(closed_after >= 0 && closed_after <= 8775,
                     $sformatf("V20 idle open row force-precharged within 8775 cycles (closed after %0d)", closed_after));
        end

        // V22 Jailbreak (MOAT, MICRO'23): lấp đầy hàng đợi refresh FIFO bằng nhiều aggressor rồi hammer phần tử trẻ nhất.
        reset_dut();
        $display("[VECTOR 22] Jailbreak: hammer the youngest entry of the mitigation queue");
        begin
            for (int a = 0; a < 6; a++) hammer_pair(16'h2000 + 16 * a, 16'h2000 + 16 * a + 64, 5, 2, 4, 0, 4'h2);
            jb_key = mk_key(16'h2200, 5, 2);
            jb_acts = 0;
            jb_run = 0;
            jb_max_run = 0;
            jb_on = 1'b1;
            hammer_pair(16'h2200, 16'h2240, 5, 2, 24, 0, 4'h2);
            repeat (400) @(posedge clk_axi);
            jb_on = 1'b0;
            $display("  [DIAG] V22 target row: %0d ACT total, max %0d ACT between victim refreshes", jb_acts, jb_max_run);
            tb_check(jb_acts >= 4 * cfg_rh_threshold, $sformatf("V22 precondition: target row hammered (%0d ACT)", jb_acts));
            tb_check(jb_max_run <= 2 * cfg_rh_threshold,
                     $sformatf("V22 youngest aggressor never exceeds 2x threshold ACTs unrefreshed (max run %0d)", jb_max_run));
        end

        // V23 DRAMA (USENIX'16): kênh row-buffer giữa hai tenant. Không tô màu bank: kênh phải tồn tại (đối chứng);
        // bật bank coloring: tenant nhận không được giải mã bit của tenant gửi.
        for (int col = 0; col < 2; col++) begin
            int lat_r [16];
            int msg [16];
            int s0, s1, n0, n1, correct, l;
            real mid;
            reset_dut();
            cfg_bank_coloring_en = col[0];
            repeat (5) @(posedge clk_axi);
            $display("[VECTOR 23] DRAMA row-buffer covert channel, bank coloring %s", col ? "ON" : "OFF");
            // Mỗi ký hiệu đo 3 lần, lấy min: REFab/RFMab chỉ thỉnh thoảng cộng độ trễ lớn, min lọc nhiễu mà giữ chênh lệch xung đột hàng.
            for (int b = 0; b < 16; b++) begin
                msg[b] = (32'h6C3A >> b) & 1;
                lat_r[b] = 1 << 30;
                for (int rep = 0; rep < 3; rep++) begin
                    prev = r_done_cnt[9];
                    axi_read(4'h9, mk_addr(16'h2400, 3, 2), 4'd2);
                    wait_r(9, prev, 400, l);
                    if (msg[b] == 1) begin
                        prev = r_done_cnt[5];
                        axi_read(4'h5, mk_addr(16'h2480, 3, 2), 4'd2);
                        wait_r(5, prev, 400, l);
                    end else begin
                        repeat (30) @(posedge clk_axi);
                    end
                    prev = r_done_cnt[9];
                    axi_read(4'h9, mk_addr(16'h2400, 3, 2), 4'd2);
                    wait_r(9, prev, 400, l);
                    if (l >= 0 && l < lat_r[b]) lat_r[b] = l;
                end
            end
            s0 = 0; s1 = 0; n0 = 0; n1 = 0;
            for (int b = 0; b < 16; b++) begin
                if (msg[b] == 1) begin s1 += lat_r[b]; n1++; end
                else             begin s0 += lat_r[b]; n0++; end
            end
            // Ngưỡng = trung vị 16 mẫu (cùng bộ thu bền vững như V19): một mẫu trùng REF/RFM kéo lệch trung bình và làm
            // bộ thu trung điểm đánh giá thấp kênh có thật ở phép đối chứng
            begin
                int srt [16];
                for (int b = 0; b < 16; b++) srt[b] = lat_r[b];
                for (int i = 1; i < 16; i++) begin
                    int v, j;
                    v = srt[i];
                    j = i - 1;
                    while (j >= 0 && srt[j] > v) begin srt[j + 1] = srt[j]; j--; end
                    srt[j + 1] = v;
                end
                mid = (real'(srt[7]) + real'(srt[8])) / 2.0;
            end
            correct = 0;
            for (int b = 0; b < 16; b++) begin
                if (((real'(lat_r[b]) > mid) ? 1 : 0) == ((s1 / n1 > s0 / n0) ? msg[b] : 1 - msg[b])) correct++;
            end
            for (int b = 0; b < 16; b++) $display("  [DIAG] V23 coloring %0d bit %0d sent %0d latency %0d", col, b, msg[b], lat_r[b]);
            $display("  [DIAG] V23 coloring %0d: receiver latency symbol0 %0d, symbol1 %0d cycles; decoded %0d/16",
                     col, s0 / n0, s1 / n1, correct);
            if (col == 0) tb_check(correct >= 14, $sformatf("V23 control: shared-bank channel exists without coloring (%0d/16)", correct));
            else          tb_check(correct <= 12, $sformatf("V23 bank coloring closes the row-buffer channel (%0d/16, chance = 8)", correct));
        end
        cfg_bank_coloring_en = 0;

        // V6 SCARF: cùng địa chỉ logic phải luôn ánh xạ cùng hàng vật lý; các hàng logic kề nhau không kề nhau vật lý.
        reset_dut();
        $display("[VECTOR 6] SCARF adjacency disruption and mapping consistency");
        cfg_scramble_en = 1;
        cfg_scramble_mode = 2'b10;
        repeat (10) @(posedge clk_axi);
        for (int r = 0; r < 8; r++) begin
            clear_logs();
            axi_read(4'h6, mk_addr(16'hC00 + r, 3, 0), 4'd2);
            repeat (40) @(posedge clk_axi);
            phys[r] = first_act_row();
        end
        covered = 0;
        for (int r = 0; r < 7; r++) begin
            d = phys[r + 1] - phys[r];
            if (d < 0) d = -d;
            if (phys[r] >= 0 && phys[r + 1] >= 0 && d > 2) covered++;
        end
        tb_check(covered == 7, $sformatf("V6 logical neighbours mapped to non-adjacent physical rows (%0d/7)", covered));
        clear_logs();
        axi_read(4'h6, mk_addr(16'hC03, 3, 0), 4'd2);
        repeat (40) @(posedge clk_axi);
        tb_check(first_act_row() >= 0 && first_act_row() == phys[3],
                 $sformatf("V6 same logical row maps to same physical row (first 0x%0h, again 0x%0h)",
                                 phys[3], first_act_row()));

        // V15 RAMBleed: dữ liệu ghi xuống DRAM phải được xáo trộn/mã hóa; top này không có bus dữ liệu DFI để quan sát.
        reset_dut();
        $display("[VECTOR 15] RAMBleed data scrambling");
        cfg_scramble_mode = 2'b01;
        dq_wr_seen = 0;
        wdat = 64'hAAAA_5555_AAAA_5555;
        axi_write(4'h5, mk_addr(16'hD00, 2, 1), wdat, 4'd3);
        prev = r_done_cnt[5];
        axi_read(4'h5, mk_addr(16'hD00, 2, 1), 4'd3);
        wait_r(5, prev, 400, lat);
        // Dữ liệu trên bus DQ phải đã được xáo (khác bản rõ), còn dữ liệu đọc về phải được giải xáo đúng
        tb_check(dq_wr_seen && dq_last_wrdata !== wdat,
                 $sformatf("V15 DQ bus carries scrambled data (bus %h, plaintext %h)", dq_last_wrdata, wdat));
        tb_check(lat >= 0 && r_last_data[5] === wdat, "V15 read-back with scrambling enabled equals written data");
        cfg_scramble_en = 0;
        cfg_scramble_mode = 2'b00;

        // V9 TMR: lật một ray cấu hình → đầu ra bỏ phiếu giữ nguyên và cảnh báo glitch được chốt (để cuối vì khóa hệ thống).
        reset_dut();
        $display("[VECTOR 9] TMR single-rail upset");
        repeat (10) @(posedge clk_axi);
        @(negedge clk_axi);
        fi_v9 = 1'b1;
        dut.u_fh_csr.rail0_rh_thresh = 16'hFFFF;
        repeat (3) @(posedge clk_axi);
        tb_check(dut.voted_rh_threshold == cfg_rh_threshold,
                 $sformatf("V9 voted threshold unchanged after single-rail upset (%0d)", dut.voted_rh_threshold));
        tb_check(o_glitch_alert === 1'b1 && o_fault_cause[0] === 1'b1,
                 $sformatf("V9 glitch alert and o_fault_cause[0] raised within <=5 cycles (alert=%0b, cause=0x%03h)",
                           o_glitch_alert, o_fault_cause));
        @(negedge clk_axi);
        dut.u_fh_csr.rail0_rh_thresh = cfg_rh_threshold;
        repeat (2) @(posedge clk_axi);
        @(negedge clk_axi);
        cfg_fault_clr = 1'b1;
        @(posedge clk_axi);
        @(negedge clk_axi);
        cfg_fault_clr = 1'b0;
        repeat (2) @(posedge clk_axi);
        tb_check(o_glitch_alert === 1'b0 && o_fault_cause === 9'd0,
                 $sformatf("V9 fault cleared after rail repair + cfg_fault_clr (alert=%0b, cause=0x%03h)",
                           o_glitch_alert, o_fault_cause));
        fi_v9 = 1'b0;

        $display("[SUMMARY] REF=%0d R bursts=%0d AR issued=%0d", ref_log.size(), r_total_bursts, ar_issued_cnt);
        u_jchk.report("red-team");
        repeat (2) @(posedge clk_axi);
        u_achk.final_check();
        u_echk.final_check();
        u_achk.report("red-team");
        u_echk.report("red-team");
        u_pchk.report("red-team");
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

    initial begin
        #2_000_000;
        $display("[FAIL] Watchdog timeout");
        tb_report();
        $fatal(1, "[WATCHDOG TIMEOUT]");
    end

endmodule
