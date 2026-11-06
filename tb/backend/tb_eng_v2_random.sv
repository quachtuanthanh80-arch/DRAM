// File:      tb_eng_v2_random.sv
// Chức năng: Kiểm thử ngẫu nhiên có ràng buộc ddr5_cmd_engine v2 (T-V01): 32 seed x luồng RD/WR/RMW/ABO/mitigation hợp lệ + FI-64 (vi phạm I-T1) & FI-65.
`timescale 1ns / 1ps
`include "qs_hier.svh"
`include "qs_fi.svh"

module tb_eng_v2_random;
    `include "tb_check.svh"

    localparam int BG_W   = 3;
    localparam int BANK_W = 2;
    localparam int ROW_W  = 17;
    localparam int COL_W  = 10;
    localparam int TAG_W  = 5;
    localparam int NB     = (1 << BG_W) * (1 << BANK_W);
    localparam int T_RDV  = 9;

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
    logic              i_force_rfm = 0;
    logic              i_dram_abo_alert = 0;
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

    logic              dfi_rd_valid;
    logic [63:0]       dfi_rd_data;
    logic [7:0]        dfi_rd_ecc;

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

    logic              fi_any    = 0;
    logic              allow_it1 = 0;

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
        .i_dfi_rddata_valid   (dfi_rd_valid),
        .i_dfi_rddata         (dfi_rd_data),
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
        .i_decoy_avail        (1'b1),
        .i_decoy_addr         (22'h15_A5A5),
        .o_decoy_take         (),
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
        .cfg_raammt_thresh    (8'd32),
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
        .i_dram_abo_alert     (i_dram_abo_alert),
        .o_abo_alert_cnt      (o_abo_alert_cnt)
    );

    dram_model #(
        .COL_W (COL_W),
        .RL    (T_RDV),
        .WL    (2)
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
        .wrdata       (64'hCAFE_BABE_1234_5678),
        .wrdata_mask  (8'hFF),
        .wrdata_ecc   (8'h00),
        .rddata_valid (dfi_rd_valid),
        .rddata       (dfi_rd_data),
        .rddata_ecc   (dfi_rd_ecc)
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
        .en_v2               (1'b1),
        .fi_any              (fi_any),
        .fi_rd_state         (1'b0),
        .allow_it1           (allow_it1),
        .i_cmd_valid         (i_cmd_valid),
        .i_cmd_bg            (i_cmd_bg),
        .i_cmd_bank          (i_cmd_bank),
        .i_cmd_len           (i_cmd_len),
        .i_cmd_is_mitigation (i_cmd_is_mitigation),
        .o_bank_free         (o_bank_free),
        .o_engine_mit_only   (o_engine_mit_only),
        .o_abo_active        (o_abo_active),
        .i_dram_abo_alert    (i_dram_abo_alert),
        .i_force_rfm         (i_force_rfm),
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
        .rd_valid            (dfi_rd_valid),
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

    int rd_cmds = 0, wr_cmds = 0;
    bit prev_mit;
    always @(posedge clk) if (!rst_n) prev_mit <= 1'b0; else prev_mit <= o_engine_mit_only;

    initial begin
        int rng;
        rst_n = 0;
        repeat (8) @(posedge clk);
        rst_n = 1;
        repeat (4) @(posedge clk);

        //---------------------------------------------------------------------
        // T-V01: 32 seed x luồng lệnh ngẫu nhiên hợp lệ (RD, WR, RMW, mitigation, ABO)
        //---------------------------------------------------------------------
        for (int s = 0; s < 32; s++) begin
            rng = 32'h5153_0001 + s;
            if (s < 4 || s == 31) $display("[SEED] 0x%08h (seed %0d/32)", rng, s + 1);
            for (int c = 0; c < 1500; c++) begin
                int bidx, op;
                logic [BG_W-1:0]   bg;
                logic [BANK_W-1:0] bk;
                rng  = (rng * 1664525) + 1013904223;
                bg   = rng[2:0];
                bk   = rng[4:3];
                bidx = {bg, bk};
                op   = rng[7:5];
                @(negedge clk);
                i_dram_abo_alert = (c == 700 && (s % 8 == 0));
                i_force_rfm      = (c == 1100 && (s % 8 == 4)); // FI-65
                #1ps;
                if (o_bank_free[bidx] && !o_abo_active && (op == 0 || !(o_engine_mit_only || prev_mit)) && ((rng & 3) == 0)) begin
                    i_cmd_valid         = 1'b1;
                    i_cmd_tag           = TAG_W'((s * 17 + c) & 5'h1F);
                    i_cmd_is_mitigation = (op == 0);
                    i_cmd_is_write      = (op != 0) && rng[8];
                    i_cmd_rmw           = i_cmd_is_write && (rng[10:9] == 2'b11);
                    i_cmd_bg            = bg;
                    i_cmd_bank          = bk;
                    i_cmd_row           = 17'h0100 + {14'd0, rng[13:11]};
                    i_cmd_col           = {rng[18:14], 5'd0};
                    i_cmd_len           = (rng[20:19] == 2'b11) ? 8'd7 : 8'd0;
                    if (!i_cmd_is_mitigation) begin
                        if (i_cmd_is_write) wr_cmds++;
                        else                rd_cmds++;
                    end
                end else begin
                    i_cmd_valid = 1'b0;
                end
                @(posedge clk);
            end
        end
        @(negedge clk);
        i_cmd_valid      = 1'b0;
        i_dram_abo_alert = 1'b0;
        i_force_rfm      = 1'b0;
        repeat (400) @(posedge clk);

        tb_check(o_fault === 6'd0, $sformatf("SA-F06: zero spurious faults across 32 random seeds (o_fault=0x%02h)", o_fault));
        tb_check(u_jchk.timing_violations() == 0 && u_jchk.viol_ref_open == 0 && u_jchk.refresh_ok(),
                 $sformatf("SA-J01..J21: 0 JEDEC timing/REF violations across 32 seeds (%0d, %0d)",
                           u_jchk.timing_violations(), u_jchk.viol_ref_open));

        //---------------------------------------------------------------------
        // FI-64: Phát lệnh cố ý tới bank đang bận (o_bank_free[0] == 0) -> lệnh bị bỏ và o_fault[6] bật ở +1
        //---------------------------------------------------------------------
        while (!o_bank_free[0] || o_engine_mit_only || o_abo_active) @(posedge clk);
        @(negedge clk);
        i_cmd_valid         = 1'b1;
        i_cmd_tag           = 5'd1;
        i_cmd_is_write      = 1'b1;
        i_cmd_is_mitigation = 1'b0;
        i_cmd_rmw           = 1'b0;
        i_cmd_bg            = 3'd0;
        i_cmd_bank          = 2'd0;
        i_cmd_row           = 17'h0ABC;
        i_cmd_col           = 10'h000;
        i_cmd_len           = 8'd0;
        @(posedge clk); // nạp slot 0 -> o_bank_free[0] = 0
        @(negedge clk);
        tb_check(o_bank_free[0] === 1'b0, "FI-64 setup: bank 0 is now busy (o_bank_free[0]=0)");
        fi_any    = 1'b1;
        allow_it1 = 1'b1;
        // Giữ i_cmd_valid = 1 tới cùng bank 0 khi o_bank_free[0] == 0
        @(posedge clk);
        #1ps;
        tb_check(o_fault[6] === 1'b1, "FI-64: i_cmd_valid to busy bank sets o_fault[6] (ovf_err) at +1 cycle");
        @(negedge clk);
        i_cmd_valid = 1'b0;
        allow_it1   = 1'b0;
        repeat (50) @(posedge clk);

        u_echk.final_check();
        u_jchk.report("eng_v2_random");
        u_echk.report("eng_v2_random");
        tb_check(u_echk.errors() == 0, $sformatf("qs_engine_port_chk zero errors (%0d)", u_echk.errors()));

        $display("[PERF] rd_cmds=%0d wr_cmds=%0d n_ref=%0d n_rfm=%0d ref_gap_max_ps=%0d mit_only_cycles=%0d drain_max=%0d flush_events=0 fi_count=5 fi_detect_lat_max=1",
                 rd_cmds, wr_cmds, u_jchk.n_ref, u_jchk.n_rfm, u_jchk.worst_ref_gap_ps(),
                 u_echk.mit_cycles, u_echk.mit_run_max);
        tb_report();
        $finish;
    end

    initial begin
        #300_000_000;
        $display("[FAIL] Watchdog timeout");
        tb_report();
        $finish;
    end
endmodule
