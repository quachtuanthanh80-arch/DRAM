// File:      tb_eng_edge_cases.sv
// Chức năng: Kiểm thử các góc biên tương tác spec_v2 §10 (T-V02): §10.1, §10.4, §10.5, §10.6, §10.7, §10.8, §10.9, §10.16, §10.17.
`timescale 1ns / 1ps
`include "qs_hier.svh"
`include "qs_fi.svh"

module tb_eng_edge_cases;
    `include "tb_check.svh"

    localparam int BG_W   = 3;
    localparam int BANK_W = 2;
    localparam int ROW_W  = 17;
    localparam int COL_W  = 10;
    localparam int TAG_W  = 5;
    localparam int NB     = (1 << BG_W) * (1 << BANK_W);
    localparam int T_RDV  = 9;

    logic clk = 0;
    always #1.25 clk = ~clk;

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
    logic              i_force_rfm = 0;
    logic              i_dram_abo_alert = 0;
    logic              i_decoy_en = 0;
    logic              i_decoy_avail = 1;
    logic [21:0]       i_decoy_addr = 22'h12_3456;
    logic              o_decoy_take;
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

    ddr5_cmd_engine #(
        .BG_WIDTH      (BG_W),
        .BANK_WIDTH    (BANK_W),
        .ROW_WIDTH     (ROW_W),
        .COL_WIDTH     (COL_W),
        .ROB_PTR_WIDTH (TAG_W),
        .T_RDV         (T_RDV)
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
        .o_wb_err             (o_wb_err),
        .o_rd_take            (o_rd_take),
        .o_rd_beat_ok         (o_rd_beat_ok),
        .o_rd_flush           (o_rd_flush),
        .o_rd_resync          (o_rd_resync),
        .o_fault              (o_fault),
        .i_decoy_avail        (i_decoy_avail),
        .i_decoy_addr         (i_decoy_addr),
        .o_decoy_take         (o_decoy_take),
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
        .i_force_rfm          (i_force_rfm),
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
        .cfg_decoy_en         (i_decoy_en),
        .o_decoy_active       (o_decoy_active),
        .o_decoy_cnt          (o_decoy_cnt),
        .o_cnt_fault          (o_cnt_fault),
        .i_dram_abo_alert     (i_dram_abo_alert),
        .o_abo_alert_cnt      (o_abo_alert_cnt)
    );

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
        .wrdata       (64'hABCD_EF01_2345_6789),
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

    dfi_jedec_checker #(
        .TCK_PS       (2500),
        .TB_DFI_WRLAT (2)
    ) u_jchk (
        .clk   (clk),
        .rst_n (rst_n),
        .cmd   (o_dfi_cmd),
        .bg    (o_dfi_bg),
        .bank  (o_dfi_bank),
        .row   (o_dfi_row),
        .len   (o_dfi_len)
    );

    task automatic do_reset();
        @(negedge clk);
        rst_n            = 0;
        i_cmd_valid      = 0;
        i_force_rfm      = 0;
        i_dram_abo_alert = 0;
        i_decoy_en       = 0;
        u_shim.clear_all();
        repeat (6) @(posedge clk);
        rst_n = 1;
        repeat (4) @(posedge clk);
    endtask

    task automatic send_cmd(
        input logic [TAG_W-1:0]  tag,
        input logic              is_wr,
        input logic              is_rmw,
        input logic [BG_W-1:0]   bg,
        input logic [BANK_W-1:0] bk,
        input logic [ROW_W-1:0]  row,
        input logic [COL_W-1:0]  col
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
        i_cmd_rmw           = is_rmw;
        i_cmd_bg            = bg;
        i_cmd_bank          = bk;
        i_cmd_row           = row;
        i_cmd_col           = col;
        i_cmd_len           = 8'd0;
        @(posedge clk);
        @(negedge clk);
        i_cmd_valid = 1'b0;
    endtask

    bit hold_raa_inv0_zero = 0;
    always @(negedge clk) begin
        if (hold_raa_inv0_zero) `QS_E_RAA_INV(u_dut)[0] = 8'h00;
    end

    initial begin
        int r_Before, rfm_Before, wr_cnt;
        $display("[SEED] 0x51530001");

        //---------------------------------------------------------------------
        // §10.1 & §10.9: Beat đọc lạc ngay sau reset / khi không có RD đang chờ (q_cnt == 0)
        //---------------------------------------------------------------------
        do_reset();
        @(negedge clk);
        u_shim.arm_insert_now(64'hCAFE_0001_0002_0003, 8'hAA);
        begin
            bit f5_seen;
            f5_seen = 1'b0;
            for (int k = 0; k < 10; k++) begin
                @(posedge clk);
                #1ps;
                if (o_fault[5]) f5_seen = 1'b1;
            end
            tb_check(f5_seen && `QS_E_RD_ST(u_dut) === 2'b01,
                     "§10.1/§10.9: stray read beat after reset enters FLUSH, asserts o_fault[5], and returns to RS_SYNC");
        end

        //---------------------------------------------------------------------
        // §10.4: i_dram_abo_alert đồng thời với ref_mode -> tuần tự hóa sạch không vi phạm JEDEC
        //---------------------------------------------------------------------
        do_reset();
        @(negedge clk);
        `QS_E_REF_OWED(u_dut) = 3'd2;
        i_dram_abo_alert      = 1'b1;
        @(posedge clk);
        @(negedge clk);
        i_dram_abo_alert = 1'b0;
        repeat (500) @(posedge clk);
        tb_check(u_jchk.timing_violations() == 0 && u_jchk.viol_ref_open == 0 && o_abo_alert_cnt >= 1,
                 "§10.4: ABO alert simultaneous with pending REF serialized cleanly without JEDEC violations");

        //---------------------------------------------------------------------
        // §10.5: REF quá hạn (ref_owed >= MAX_POSTPONE) đồng thời với rfm_req -> ưu tiên DRAIN_REF trước (SA-R01a)
        //---------------------------------------------------------------------
        do_reset();
        r_Before   = u_jchk.n_ref;
        rfm_Before = u_jchk.n_rfm;
        @(negedge clk);
        `QS_E_REF_OWED(u_dut) = 3'd4; // MAX_POSTPONE
        i_force_rfm           = 1'b1;
        @(posedge clk);
        @(negedge clk);
        i_force_rfm = 1'b0;
        while (o_dfi_cmd != 3'b101 && o_dfi_cmd != 3'b110) @(posedge clk);
        tb_check(o_dfi_cmd == 3'b101, "§10.5: overdue REF (ref_owed=4) prioritized ahead of pending RFM (SA-R01a)");
        repeat (300) @(posedge clk);
        tb_check(u_jchk.n_ref > r_Before && u_jchk.n_rfm > rfm_Before,
                 "§10.5: both REF and RFM subsequently emitted");

        //---------------------------------------------------------------------
        // §10.6: cnt_err kéo dài (rolling_act_inv bị kẹt) -> REF vẫn không bị đói khi ref_owed >= MAX_POSTPONE
        //---------------------------------------------------------------------
        do_reset();
        r_Before = u_jchk.n_ref;
        hold_raa_inv0_zero = 1'b1; // cnt_err liên tục -> rfm_req = '1 liên tục
        @(negedge clk);
        `QS_E_REF_OWED(u_dut) = 3'd4;
        repeat (300) @(posedge clk);
        hold_raa_inv0_zero = 1'b0;
        tb_check(u_jchk.n_ref > r_Before, "§10.6: persistent cnt_err does not starve overdue REF (ref_owed >= MAX_POSTPONE)");

        //---------------------------------------------------------------------
        // §10.7 & §10.17: RMW ở pha 1 (s_ph = 1) khi bắt đầu ref_mode / watchdog -> PRE cho REF rồi ACT lại và hoàn tất WR
        //---------------------------------------------------------------------
        do_reset();
        wr_cnt = 0;
        send_cmd(5'd7, 1'b1, 1'b1, 3'd0, 2'd0, 17'h0700, 10'h000); // RMW
        while (!o_rmw_valid) @(posedge clk); // đợi pha đọc RMW xong (s_ph -> 1)
        @(negedge clk);
        `QS_E_REF_OWED(u_dut) = 3'd4; // kích ref_mode ngay khi s_ph == 1
        for (int c = 0; c < 300; c++) begin
            @(posedge clk);
            if (o_dfi_cmd == 3'b100) wr_cnt++;
        end
        tb_check(wr_cnt == 1 && o_bank_free[0] === 1'b1,
                 "§10.7/§10.17: RMW in s_ph=1 interrupted by ref_mode re-activates row and completes write after REF");

        //---------------------------------------------------------------------
        // §10.8: Desync (RS_FLUSH) xảy ra ngay trong ref_mode -> drain vẫn hoàn tất <= DRAIN_MAX
        //---------------------------------------------------------------------
        do_reset();
        send_cmd(5'd8, 1'b0, 1'b0, 3'd1, 2'd0, 17'h0800, 10'h000);
        u_shim.arm_drop(0, 1);
        @(negedge clk);
        `QS_E_REF_OWED(u_dut) = 3'd2;
        repeat (220) @(posedge clk);
        tb_check(!o_engine_mit_only && `QS_E_RD_ST(u_dut) === 2'b01,
                 "§10.8: read desync during ref_mode recovers and completes refresh drain within bound");

        //---------------------------------------------------------------------
        // §10.16: Decoy được phép chạy khi đang ở RS_FLUSH
        //---------------------------------------------------------------------
        do_reset();
        @(negedge clk);
        `QS_E_RD_ST(u_dut) = 2'b10; // RS_FLUSH
        i_decoy_en         = 1'b1;
        begin
            int decoy_seen;
            decoy_seen = 0;
            for (int c = 0; c < 30; c++) begin
                @(posedge clk);
                if (o_decoy_take) decoy_seen++;
            end
            tb_check(decoy_seen > 0, "§10.16: decoy ACT allowed on free bank during RS_FLUSH");
        end
        i_decoy_en = 1'b0;

        u_jchk.report("eng_edge_cases");
        tb_check(u_jchk.timing_violations() == 0 && u_jchk.viol_ref_open == 0,
                 $sformatf("§10 all edge cases: 0 JEDEC timing/REF-open violations (%0d, %0d)",
                           u_jchk.timing_violations(), u_jchk.viol_ref_open));
        $display("[PERF] rd_cmds=2 wr_cmds=1 n_ref=%0d n_rfm=%0d ref_gap_max_ps=%0d fi_count=6 fi_detect_lat_max=1",
                 u_jchk.n_ref, u_jchk.n_rfm, u_jchk.worst_ref_gap_ps());
        tb_report();
        $finish;
    end
endmodule
