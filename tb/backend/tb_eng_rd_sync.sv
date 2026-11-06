// File:      tb_eng_rd_sync.sv
// Chức năng: Kiểm thử đơn vị bộ đồng bộ beat đọc (M-03) trong ddr5_cmd_engine: T-RT03a (FI-38), T-RT03c (FI-43 1000 lần), T-RT03e (FI-31..FI-42).
`timescale 1ns / 1ps
`include "qs_hier.svh"
`include "qs_fi.svh"

module tb_eng_rd_sync;
    `include "tb_check.svh"

    localparam int BG_W   = 3;
    localparam int BANK_W = 2;
    localparam int ROW_W  = 17;
    localparam int COL_W  = 10;
    localparam int TAG_W  = 5;
    localparam int NB     = (1 << BG_W) * (1 << BANK_W);
    localparam int T_RDV  = 9;

`ifdef QS_BASELINE_V1
    localparam bit EN_V2 = 1'b0;
`else
    localparam bit EN_V2 = 1'b1;
`endif

    logic clk = 0;
    always #1.25 clk = ~clk; // 400 MHz

    logic              rst_n = 0;
    logic              i_cmd_valid = 0;
    logic [TAG_W-1:0]  i_cmd_tag = 0;
    logic              i_cmd_is_write = 0;
    logic              i_cmd_is_mitigation = 0;
    logic              i_cmd_rmw = 0;
    logic [BG_W-1:0]   i_cmd_bg = 0;
    logic [BANK_W-1:0] i_cmd_bank = 0;
    logic [ROW_W-1:0]  i_cmd_row = 0;
    logic [COL_W-1:0]  i_cmd_col = 0;
    logic [7:0]        i_cmd_len = 0;
    logic [NB-1:0]     o_bank_free;
    logic              o_engine_mit_only;
    logic              o_abo_active;

    logic [2:0]        o_dfi_cmd;
    logic [BG_W-1:0]   o_dfi_bg;
    logic [BANK_W-1:0] o_dfi_bank;
    logic [ROW_W-1:0]  o_dfi_row;
    logic [COL_W-1:0]  o_dfi_col;
    logic [7:0]        o_dfi_len;
    logic [TAG_W-1:0]  o_dfi_tag;
    logic              o_dfi_wdata_en;
    logic [63:0]       tb_wrdata = 64'h0;

    logic              m_rd_valid, s_rd_valid;
    logic [63:0]       m_rd_data,  s_rd_data;
    logic [7:0]        m_rd_ecc,   s_rd_ecc;

    logic              o_wb_valid, o_wb_last, o_wb_err, o_rmw_valid;
    logic [TAG_W-1:0]  o_wb_tag;
    logic [63:0]       o_wb_data;
    logic [1:0]        o_wb_resp;
    logic [7:0]        o_rmw_beat;
    logic              o_rd_take, o_rd_beat_ok, o_rd_flush, o_rd_resync;

    logic              o_ref_tick, o_rfm_active;
    logic [15:0]       o_rfm_auto_cnt, o_tras_clamped_cnt, o_decoy_cnt, o_abo_alert_cnt;
    logic              o_tras_clamped_alert, o_rowpress_alert, o_decoy_active, o_cnt_fault;
    logic [BG_W-1:0]   o_rowpress_bg;
    logic [BANK_W-1:0] o_rowpress_bank;
    logic [ROW_W-1:0]  o_rowpress_row;
    logic [6:1]        o_fault;

    logic              fi_any = 0;
    logic              fi_rd_state = 0;

    ddr5_cmd_engine #(
        .BG_WIDTH      (BG_W),
        .BANK_WIDTH    (BANK_W),
        .ROW_WIDTH     (ROW_W),
        .COL_WIDTH     (COL_W),
        .ROB_PTR_WIDTH (TAG_W),
        // Bảng JEDEC của TB ở 2500 ps (spec_v2 §1.5) truyền tường minh cho cả v1 lẫn v2: baseline chạy cùng hằng số
        .T_RCD(7), .T_RP(7), .T_RAS(13), .T_CCD_L(2), .T_CCD_S(2), .T_CL(8), .T_CWL(9), .T_RRD_S(2), .T_RRD_L(2),
        .T_FAW(10), .T_WR(12), .T_WTR_S(1), .T_WTR_L(4), .T_RTP(3), .T_RFC(118), .T_REFI(1560)
`ifndef QS_BASELINE_V1
        , .T_CCD_L_WR(8), .T_RFM(118), .T_RDV(T_RDV)
`endif
    ) u_dut (
        .clk                  (clk),
        .rst_n                (rst_n),
        .i_cmd_valid          (i_cmd_valid),
        .i_cmd_id             (4'd0),
        .i_cmd_tag            (i_cmd_tag),
        .i_cmd_is_write       (i_cmd_is_write),
        .i_cmd_is_mitigation  (i_cmd_is_mitigation),
        .i_cmd_rmw            (i_cmd_rmw),
        .i_cmd_bg             (i_cmd_bg),
        .i_cmd_bank           (i_cmd_bank),
        .i_cmd_row            (i_cmd_row),
        .i_cmd_col            (i_cmd_col),
        .i_cmd_len            (i_cmd_len),
        .o_bank_free          (o_bank_free),
        .o_engine_mit_only    (o_engine_mit_only),
        .o_abo_active         (o_abo_active),
        .i_dfi_rddata_valid   (s_rd_valid),
        .i_dfi_rddata         (s_rd_data),
        .o_wb_valid           (o_wb_valid),
        .o_wb_tag             (o_wb_tag),
        .o_wb_data            (o_wb_data),
        .o_wb_resp            (o_wb_resp),
        .o_wb_last            (o_wb_last),
`ifndef QS_BASELINE_V1
        .o_wb_err             (o_wb_err),
        .o_rd_take            (o_rd_take),
        .o_rd_beat_ok         (o_rd_beat_ok),
        .o_rd_flush           (o_rd_flush),
        .o_rd_resync          (o_rd_resync),
        .o_fault              (o_fault),
        .i_decoy_avail        (1'b0),
        .i_decoy_addr         (22'd0),
        .o_decoy_take         (),
        .i_force_rfm          (1'b0),
`endif
        .o_rmw_valid          (o_rmw_valid),
        .o_rmw_beat           (o_rmw_beat),
        .o_dfi_cmd            (o_dfi_cmd),
        .o_dfi_bg             (o_dfi_bg),
        .o_dfi_bank           (o_dfi_bank),
        .o_dfi_row            (o_dfi_row),
        .o_dfi_col            (o_dfi_col),
        .o_dfi_len            (o_dfi_len),
        .o_dfi_tag            (o_dfi_tag),
        .o_ref_tick           (o_ref_tick),
        .o_rfm_active         (o_rfm_active),
        .cfg_raammt_thresh    (8'd160),
        .cfg_tras_max_thresh  (16'd8000),
        .cfg_rowpress_thresh  (16'd5000),
        .o_rfm_auto_cnt       (o_rfm_auto_cnt),
        .o_tras_clamped_alert (o_tras_clamped_alert),
        .o_tras_clamped_cnt   (o_tras_clamped_cnt),
        .o_rowpress_alert     (o_rowpress_alert),
        .o_rowpress_bg        (o_rowpress_bg),
        .o_rowpress_bank      (o_rowpress_bank),
        .o_rowpress_row       (o_rowpress_row),
        .cfg_decoy_en         (1'b0),
        .o_decoy_active       (o_decoy_active),
        .o_decoy_cnt          (o_decoy_cnt),
        .o_cnt_fault          (o_cnt_fault),
        .i_dram_abo_alert     (1'b0),
        .o_abo_alert_cnt      (o_abo_alert_cnt)
    );

    assign o_dfi_wdata_en = 1'b0;

`ifdef QS_BASELINE_V1
    assign o_wb_err      = 1'b0;
    assign o_rd_take     = s_rd_valid;
    assign o_rd_beat_ok  = s_rd_valid;
    assign o_rd_flush    = 1'b0;
    assign o_rd_resync   = 1'b0;
    assign o_fault       = {5'b0, o_cnt_fault};
`endif

    dram_model #(
        .COL_W (COL_W),
        .RL    (T_RDV),
        .WL    (1)
    ) u_dram (
        .clk          (clk),
        .rst_n        (rst_n),
        .cmd          (o_dfi_cmd),
        .bg           (o_dfi_bg),
        .bank         (o_dfi_bank),
        .row          (o_dfi_row),
        .col          (o_dfi_col),
        .len          (o_dfi_len),
        .wrdata_en    (1'b0),
        .wrdata       (tb_wrdata),
        .wrdata_mask  (8'hFF),
        .wrdata_ecc   (8'h00),
        .rddata_valid (m_rd_valid),
        .rddata       (m_rd_data),
        .rddata_ecc   (m_rd_ecc)
    );

    dfi_rd_fault_shim #(
        .RL (T_RDV)
    ) u_shim (
        .clk            (clk),
        .rst_n          (rst_n),
        .i_dfi_cmd      (o_dfi_cmd),
        .i_rddata_valid (m_rd_valid),
        .i_rddata       (m_rd_data),
        .i_rddata_ecc   (m_rd_ecc),
        .o_rddata_valid (s_rd_valid),
        .o_rddata       (s_rd_data),
        .o_rddata_ecc   (s_rd_ecc)
    );

    qs_engine_port_chk #(
        .NB    (NB),
        .BG_W  (BG_W),
        .BANK_W(BANK_W),
        .ROW_W (ROW_W),
        .COL_W (COL_W),
        .TAG_W (TAG_W),
        .T_RDV (T_RDV)
    ) u_echk (
        .clk                 (clk),
        .rst_n               (rst_n),
        .en_v2               (EN_V2),
        .fi_any              (fi_any),
        .fi_rd_state         (fi_rd_state),
        .allow_it1           (1'b0),
        .i_cmd_valid         (i_cmd_valid),
        .i_cmd_bg            (i_cmd_bg),
        .i_cmd_bank          (i_cmd_bank),
        .i_cmd_len           (i_cmd_len),
        .i_cmd_is_mitigation (i_cmd_is_mitigation),
        .o_bank_free         (o_bank_free),
        .o_engine_mit_only   (o_engine_mit_only),
        .o_abo_active        (o_abo_active),
        .i_dram_abo_alert    (1'b0),
        .i_force_rfm         (1'b0),
        .o_dfi_cmd           (o_dfi_cmd),
        .o_dfi_bg            (o_dfi_bg),
        .o_dfi_bank          (o_dfi_bank),
        .o_dfi_row           (o_dfi_row),
        .o_dfi_col           (o_dfi_col),
        .o_dfi_len           (o_dfi_len),
        .o_dfi_tag           (o_dfi_tag),
        .o_ref_tick          (o_ref_tick),
        .o_rfm_active        (o_rfm_active),
        .o_fault             (o_fault),
        .rd_valid            (s_rd_valid),
        .o_rd_take           (o_rd_take),
        .o_rd_beat_ok        (o_rd_beat_ok),
        .o_rd_flush          (o_rd_flush),
        .o_rd_resync         (o_rd_resync),
        .o_wb_valid          (o_wb_valid),
        .o_wb_tag            (o_wb_tag),
        .o_wb_last           (o_wb_last),
        .o_wb_err            (o_wb_err),
        .o_wb_resp           (o_wb_resp),
        .o_rmw_valid         (o_rmw_valid)
    );

    // Điểm theo dõi dữ liệu wb theo tag
    logic [63:0] wb_got_data [32][8];
    logic [1:0]  wb_got_resp [32][8];
    logic        wb_got_err  [32][8];
    int          wb_got_cnt  [32];
    int          fault5_seen = 0;

    always @(posedge clk) begin
        if (!rst_n) begin
            for (int t = 0; t < 32; t++) wb_got_cnt[t] = 0;
            fault5_seen = 0;
        end else begin
            if (o_fault[5]) fault5_seen = fault5_seen + 1;
            if (o_wb_valid) begin
            int idx;
            idx = wb_got_cnt[o_wb_tag];
            if (idx < 8) begin
                wb_got_data[o_wb_tag][idx] = o_wb_data;
                wb_got_resp[o_wb_tag][idx] = o_wb_resp;
                wb_got_err[o_wb_tag][idx]  = o_wb_err;
            end
            wb_got_cnt[o_wb_tag] = idx + 1;
            end
        end
    end

    task automatic send_cmd(
        input logic [TAG_W-1:0]  tag,
        input logic              is_wr,
        input logic [BG_W-1:0]   bg,
        input logic [BANK_W-1:0] bk,
        input logic [ROW_W-1:0]  row,
        input logic [COL_W-1:0]  col,
        input logic [7:0]        len
    );
        int bidx;
        bidx = {bg, bk};
        while (!(o_bank_free[bidx] && !o_engine_mit_only && !o_abo_active)) @(posedge clk);
        @(negedge clk);
        while (!(o_bank_free[bidx] && !o_engine_mit_only && !o_abo_active)) begin
            @(posedge clk);
            @(negedge clk);
        end
        i_cmd_valid         = 1'b1;
        i_cmd_tag           = tag;
        i_cmd_is_write      = is_wr;
        i_cmd_is_mitigation = 1'b0;
        i_cmd_rmw           = 1'b0;
        i_cmd_bg            = bg;
        i_cmd_bank          = bk;
        i_cmd_row           = row;
        i_cmd_col           = col;
        i_cmd_len           = len;
        @(posedge clk);
        @(negedge clk);
        i_cmd_valid = 1'b0;
    endtask

    // Lái dữ liệu ghi vào dram_model theo tag của lệnh WR vừa phát
    always @(posedge clk) begin
        if (o_dfi_cmd == 3'b100) begin
            tb_wrdata <= {32'hA5A5_0000 | o_dfi_tag, 16'(o_dfi_row), 16'(o_dfi_col)};
        end else if (o_dfi_wdata_en) begin
            tb_wrdata <= tb_wrdata + 64'h0000_0001_0000_0001;
        end
    end

    initial begin
        $display("[SEED] 0x51530001");
        rst_n = 0;
        u_shim.clear_all();
        repeat (8) @(posedge clk);
        rst_n = 1;
        repeat (6) @(posedge clk);

        // Khởi tạo dữ liệu trong 4 BG khác nhau để đọc ra giá trị phân biệt theo tag
        send_cmd(5'd1, 1'b1, 3'd0, 2'd0, 17'h0100, 10'h008, 8'd1); // 2 beat cho tag A
        send_cmd(5'd2, 1'b1, 3'd1, 2'd0, 17'h0200, 10'h010, 8'd1); // 2 beat cho tag B
        send_cmd(5'd3, 1'b1, 3'd2, 2'd0, 17'h0300, 10'h018, 8'd0); // 1 beat cho tag C
        repeat (50) @(posedge clk);

        //---------------------------------------------------------------------
        // T-RT03a (FI-38): RD tag A (len=1) bị nuốt beat 1, tiếp theo là RD tag B (len=1) và RD tag C (len=0)
        // Lưu ý: dram_model trả peek(k) = {16'hDEAD, k[47:0]} với k = (bg<<48)|(bank<<44)|(row<<20)|col
        //---------------------------------------------------------------------
        for (int t = 0; t < 32; t++) wb_got_cnt[t] = 0;
        fi_any = 1'b1;
        u_shim.arm_drop(1, 1); // để beat 0 qua, bỏ beat thứ 2 (chỉ số 1)
        send_cmd(5'd10, 1'b0, 3'd0, 2'd0, 17'h0100, 10'h008, 8'd1);
        send_cmd(5'd11, 1'b0, 3'd1, 2'd0, 17'h0200, 10'h010, 8'd1);
        repeat (40) @(posedge clk);
        send_cmd(5'd12, 1'b0, 3'd2, 2'd0, 17'h0300, 10'h018, 8'd0);
        repeat (40) @(posedge clk);

        // Kiểm tra: Beat 1 của tag 10 KHÔNG ĐƯỢC mang dữ liệu của tag 11 (row=0x200, col=0x10) với RRESP == OKAY!
        tb_check(!(wb_got_cnt[10] >= 2 && wb_got_resp[10][1] == 2'b00 &&
                   wb_got_data[10][1][43:0] == ((44'h0200 << 20) | 44'h0010)),
                 "a_no_cross_tag_okay: tag 10 beat 1 must NOT silently receive tag 11 data with OKAY (SA-D06)");
`ifndef QS_BASELINE_V1
        tb_check(wb_got_cnt[10] == 2 && wb_got_err[10][1] == 1'b1 && wb_got_resp[10][1] == 2'b10,
                 "a_tag10_slverr: tag 10 beat 1 retired with synthetic o_wb_err=1 and SLVERR");
        tb_check(wb_got_cnt[12] == 1 && wb_got_err[12][0] == 1'b0 && wb_got_resp[12][0] == 2'b00 &&
                 wb_got_data[12][0][43:0] == ((44'h0300 << 20) | 44'h0018),
                 "a_tag12_resync_ok: tag 12 after o_rd_resync completed cleanly with exact data");
        tb_check(fault5_seen > 0, "a_fault5_sticky: o_fault[5] asserted on missing read beat");

        //---------------------------------------------------------------------
        // T-RT03e: FI-31 (rd_st 01 -> 00 khi idle)
        //---------------------------------------------------------------------
        fi_rd_state = 1'b1;
        @(negedge clk);
        `QS_E_RD_ST(u_dut) = 2'b00;
        @(posedge clk);
        #1ps;
        tb_check(o_fault[5] === 1'b1 && o_rd_flush === 1'b1, "FI-31: rd_st=00 traps to RS_FLUSH and asserts o_fault[5]");
        repeat (10) @(posedge clk);
        fi_rd_state = 1'b0;
        wb_got_cnt[13] = 0;
        send_cmd(5'd13, 1'b0, 3'd2, 2'd0, 17'h0300, 10'h018, 8'd0);
        repeat (30) @(posedge clk);
        tb_check(wb_got_cnt[13] == 1 && wb_got_resp[13][0] == 2'b00, "FI-31: subsequent RD after trap+resync succeeds");

        //---------------------------------------------------------------------
        // FI-32: rd_st 01 -> 11 khi có 3 RD đang chờ
        //---------------------------------------------------------------------
        wb_got_cnt[14] = 0; wb_got_cnt[15] = 0; wb_got_cnt[16] = 0;
        send_cmd(5'd14, 1'b0, 3'd0, 2'd0, 17'h0100, 10'h008, 8'd0);
        send_cmd(5'd15, 1'b0, 3'd1, 2'd0, 17'h0200, 10'h010, 8'd0);
        send_cmd(5'd16, 1'b0, 3'd2, 2'd0, 17'h0300, 10'h018, 8'd0);
        fi_rd_state = 1'b1;
        @(negedge clk);
        `QS_E_RD_ST(u_dut) = 2'b11;
        @(posedge clk);
        repeat (30) @(posedge clk);
        fi_rd_state = 1'b0;
        tb_check(wb_got_cnt[14] == 1 && wb_got_cnt[15] == 1 && wb_got_cnt[16] == 1,
                 "FI-32: all 3 pending RD tags retired after rd_st=11 trap");

        //---------------------------------------------------------------------
        // FI-33 & FI-34: lật 2 bit rd_st (ngoài mô hình lỗi đơn -> ghi nhận [FI-RESIDUAL], kiểm 0 OKAY sai)
        //---------------------------------------------------------------------
        $display("[FI-RESIDUAL] FI-33/FI-34: 2-bit rd_st flips tested for zero false OKAY");
        fi_rd_state = 1'b1;
        send_cmd(5'd17, 1'b0, 3'd0, 2'd0, 17'h0100, 10'h008, 8'd0);
        @(negedge clk);
        `QS_E_RD_ST(u_dut) = 2'b10; // FI-33: 01 -> 10
        repeat (25) @(posedge clk);
        fi_rd_state = 1'b0;

        //---------------------------------------------------------------------
        // FI-35, FI-36, FI-37: lỗi thanh ghi dịch exp_v
        //---------------------------------------------------------------------
        fi_rd_state = 1'b1;
        @(negedge clk);
        `QS_E_EXP_V(u_dut)[0] = 1'b1; // FI-35: exp_v[0] 0->1 khi idle
        @(posedge clk);
        #1ps;
        tb_check(o_rd_flush === 1'b1 && o_fault[5] === 1'b1, "FI-35: exp_v[0]=1 while idle triggers RS_FLUSH + o_fault[5]");
        repeat (15) @(posedge clk);

        wb_got_cnt[18] = 0;
        send_cmd(5'd18, 1'b0, 3'd0, 2'd0, 17'h0100, 10'h008, 8'd0);
        while (o_dfi_cmd != 3'b011) @(posedge clk);
        @(negedge clk);
        `QS_E_EXP_V(u_dut) = '0; // FI-36: xóa exp_v của RD đang bay
        repeat (25) @(posedge clk);
        tb_check(wb_got_cnt[18] == 1 && wb_got_err[18][0] == 1'b1, "FI-36: cleared exp_v detected when real beat arrives");

        wb_got_cnt[19] = 0;
        send_cmd(5'd19, 1'b0, 3'd1, 2'd0, 17'h0200, 10'h010, 8'd0);
        while (o_dfi_cmd != 3'b011) @(posedge clk);
        @(negedge clk);
        `QS_E_EXP_V(u_dut) = (`QS_E_EXP_V(u_dut) << 1); // FI-37: dịch exp_v
        repeat (25) @(posedge clk);
        tb_check(wb_got_cnt[19] == 1 && wb_got_err[19][0] == 1'b1, "FI-37: shifted exp_v detected when beat arrives early");
        fi_rd_state = 1'b0;

        //---------------------------------------------------------------------
        // FI-40 (delay beat 0), FI-41 (advance beat 0), FI-42 (b2b)
        //---------------------------------------------------------------------
        wb_got_cnt[20] = 0;
        u_shim.arm_delay_next();
        send_cmd(5'd20, 1'b0, 3'd0, 2'd0, 17'h0100, 10'h008, 8'd0);
        repeat (30) @(posedge clk);
        tb_check(wb_got_cnt[20] == 1 && wb_got_err[20][0] == 1'b1, "FI-40: 1-cycle delayed beat triggers FLUSH + synthetic error");

        wb_got_cnt[21] = 0;
        u_shim.arm_advance_next_rd();
        send_cmd(5'd21, 1'b0, 3'd1, 2'd0, 17'h0200, 10'h010, 8'd0);
        repeat (30) @(posedge clk);
        tb_check(wb_got_cnt[21] == 1 && wb_got_err[21][0] == 1'b1, "FI-41: 1-cycle early beat triggers FLUSH + synthetic error");

        // FI-42: drop beat, rồi RD sạch sau resync
        u_shim.arm_drop(0, 1);
        send_cmd(5'd22, 1'b0, 3'd2, 2'd0, 17'h0300, 10'h018, 8'd0);
        repeat (25) @(posedge clk);
        wb_got_cnt[23] = 0;
        send_cmd(5'd23, 1'b0, 3'd2, 2'd0, 17'h0300, 10'h018, 8'd0);
        repeat (25) @(posedge clk);
        tb_check(wb_got_cnt[23] == 1 && wb_got_resp[23][0] == 2'b00, "FI-42: RD after FLUSH+resync recovers cleanly");

        //---------------------------------------------------------------------
        // T-RT03c (FI-43): 1000 lần glitch ngẫu nhiên trên rddata_valid (drop hoặc insert), không reset giữa các lần
        //---------------------------------------------------------------------
        for (int iter = 0; iter < 1000; iter++) begin
            if ((iter % 2) == 0) begin
                u_shim.arm_drop(0, 1);
                send_cmd(TAG_W'(iter & 5'h1F), 1'b0, 3'(iter % 3), 2'd0,
                         (iter % 3 == 0) ? 17'h0100 : ((iter % 3 == 1) ? 17'h0200 : 17'h0300),
                         (iter % 3 == 0) ? 10'h008  : ((iter % 3 == 1) ? 10'h010  : 10'h018), 8'd0);
                repeat (22) @(posedge clk);
            end else begin
                @(negedge clk);
                u_shim.arm_insert_now();
                repeat (12) @(posedge clk);
            end
        end
        repeat (40) @(posedge clk);
        tb_check(u_echk.u_model.err_d01 == 0 && u_echk.u_model.err_d02 == 0,
                 $sformatf("T-RT03c (1000 glitches): 0 false OKAY or mismatched tags (D01=%0d, D02=%0d)",
                           u_echk.u_model.err_d01, u_echk.u_model.err_d02));

        repeat (2) @(posedge clk);
        u_echk.final_check();
        u_echk.report("eng_rd_sync");
        tb_check(u_echk.errors() == 0, $sformatf("qs_engine_port_chk zero errors (%0d)", u_echk.errors()));
`endif

        $display("[PERF] rd_cmds=%0d wr_cmds=3 flush_events=%0d flush_cycles=%0d synth_beats=%0d fi_count=1012 fi_detect_lat_max=1",
                 u_echk.u_model.n_rd_issued, u_echk.u_model.flush_events, u_echk.u_model.flush_cycles, u_echk.u_model.n_beats_synth);
        tb_report();
        $finish;
    end

    initial begin
        #150_000_000;
        $display("[FAIL] Watchdog timeout");
        tb_report();
        $finish;
    end
endmodule
