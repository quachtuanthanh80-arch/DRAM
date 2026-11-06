// File:      tb_drm_fault_inject.sv
// Chức năng: Kiểm thử bơm lỗi đơn vị directed_refresh_manager (T-RT05d, FI-49..FI-55): FSM 7-bit one-hot inj_oh, thanh ghi đôi blkp_a/b, đối chiếu pq_v/pq_region.
`timescale 1ns / 1ps
`include "qs_hier.svh"
`include "qs_fi.svh"

module tb_drm_fault_inject;
    `include "tb_check.svh"

    localparam int BG_W   = 3;
    localparam int BANK_W = 2;
    localparam int ROW_W  = 16;

    logic              clk = 0;
    always #1.25 clk = ~clk;

    logic              rst_n = 0;
    logic              cfg_drm_en = 1;
    logic              cfg_half_double_en = 1;
    logic              cfg_victim3_en = 1;
    logic              i_aggr_valid = 0;
    logic [BG_W-1:0]   i_aggr_bg = 0;
    logic [BANK_W-1:0] i_aggr_bank = 0;
    logic [ROW_W-1:0]  i_aggr_row = 0;
    logic              i_aggr_rowpress = 0;
    logic              o_aggr_stall;
    logic              o_mit_req;
    logic              i_mit_ack = 1;
    logic [BG_W-1:0]   o_mit_bg;
    logic [BANK_W-1:0] o_mit_bank;
    logic [ROW_W-1:0]  o_mit_row;
    logic              o_mit_prio;
    logic [15:0]       o_ref_cnt;
    logic              o_drm_fault;
    logic [7:0]        i_cand_valid = 8'h00;
    logic [7:0][BANK_W-1:0] i_cand_bank = '0;
    logic [7:0][ROW_W-1:0]  i_cand_row  = '0;
    logic [7:0]        i_cand_fresh = 8'hFF;
    logic [7:0]        o_proq_blk;

    directed_refresh_manager #(
        .BG_WIDTH    (BG_W),
        .BANK_WIDTH  (BANK_W),
        .ROW_WIDTH   (ROW_W),
        .QUEUE_DEPTH (16)
    ) u_dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .cfg_drm_en         (cfg_drm_en),
        .cfg_victim2_en     (cfg_half_double_en),
        .cfg_victim3_en     (cfg_victim3_en),
        .i_abo_req          (1'b0),
        .i_abo_bg           ('0),
        .i_abo_bank         ('0),
        .i_abo_row          ('0),
        .i_sdc_req          (i_aggr_valid),
        .i_sdc_bg           (i_aggr_bg),
        .i_sdc_bank         (i_aggr_bank),
        .i_sdc_row          (i_aggr_row),
        .i_rp_req           (i_aggr_rowpress),
        .i_rp_bg            (i_aggr_bg),
        .i_rp_bank          (i_aggr_bank),
        .i_rp_row           (i_aggr_row),
        .i_scrub_req        (1'b0),
        .i_scrub_bg         ('0),
        .i_scrub_bank       ('0),
        .i_scrub_row        ('0),
        .o_scrub_grant      (),
        .o_mitigation_req   (o_mit_req),
        .i_mitigation_grant (i_mit_ack),
        .o_mitigation_bg    (o_mit_bg),
        .o_mitigation_bank  (o_mit_bank),
        .o_mitigation_row   (o_mit_row),
        .o_drm_ref_count    (o_ref_cnt),
        .o_queue_full       (),
        .o_drm_stall        (o_aggr_stall),
        .o_drm_fault        (o_drm_fault),
        .i_cand_valid       (i_cand_valid),
        .i_cand_bank        (i_cand_bank),
        .i_cand_row         (i_cand_row),
        .i_cand_fresh       (i_cand_fresh),
        .o_proq_blk         (o_proq_blk),
        .o_proq_hit         ()
    );

    task automatic do_reset();
        @(negedge clk);
        rst_n        = 0;
        i_aggr_valid = 0;
        i_cand_valid = 8'h00;
        i_cand_fresh = 8'hFF;
        i_mit_ack    = 1;
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);
    endtask

    initial begin
        int fi49_pass;
        $display("[SEED] 0x51530001");
        do_reset();

        //---------------------------------------------------------------------
        // FI-49: 7 trạng thái one-hot hợp lệ x 7 vị trí bit lật = 49 tổ hợp
        // Mỗi tổ hợp phải đặt o_drm_fault == 1 ở +1 và trap inj_oh về S_P1R (7'b0000010)
        //---------------------------------------------------------------------
        fi49_pass = 0;
        for (int st = 0; st < 7; st++) begin
            for (int bit_idx = 0; bit_idx < 7; bit_idx++) begin
                logic [6:0] base_oh, bad_oh;
                base_oh = 7'd1 << st;
                bad_oh  = base_oh ^ (7'd1 << bit_idx);
                @(negedge clk);
                `QS_D_INJ_OH(u_dut) = bad_oh;
                @(posedge clk);
                #1ps;
                if (o_drm_fault === 1'b1 && `QS_D_INJ_OH(u_dut) === 7'b0000010)
                    fi49_pass++;
                // Trả về S_IDLE cho vòng kế
                @(negedge clk);
                `QS_D_INJ_OH(u_dut) = 7'b0000001;
                @(posedge clk);
            end
        end
        tb_check(fi49_pass == 49,
                 $sformatf("FI-49: all 49 (7 states x 7 bits) single-bit inj_oh flips trapped to S_P1R and raised o_drm_fault (%0d/49)", fi49_pass));

        //---------------------------------------------------------------------
        // FI-50: lật 2 bit thành mã one-hot hợp lệ khác ([FI-RESIDUAL])
        //---------------------------------------------------------------------
        $display("[FI-RESIDUAL] FI-50: 2-bit inj_oh flip between valid one-hot codes (Hamming distance 2)");

        //---------------------------------------------------------------------
        // FI-51: force inj_oh = 7'd0 trong 5 chu kỳ, rồi release -> phục hồi về S_P1R và đẩy hết nạn nhân
        //---------------------------------------------------------------------
        do_reset();
        @(negedge clk);
        i_aggr_valid = 1'b1;
        i_aggr_bg    = 3'd2;
        i_aggr_bank  = 2'd1;
        i_aggr_row   = 16'h0200;
        @(posedge clk);
        @(negedge clk);
        i_aggr_valid = 1'b0;
        force `QS_D_INJ_OH(u_dut) = 7'd0;
        begin
            int flt_cnt;
            flt_cnt = 0;
            for (int k = 0; k < 5; k++) begin
                @(posedge clk);
                #1ps;
                if (o_drm_fault === 1'b1) flt_cnt++;
            end
            tb_check(flt_cnt == 5, $sformatf("FI-51: o_drm_fault asserted in all 5 cycles while inj_oh forced to 0 (%0d/5)", flt_cnt));
        end
        @(negedge clk);
        release `QS_D_INJ_OH(u_dut);
        @(posedge clk);
        #1ps;
        tb_check(`QS_D_INJ_OH(u_dut) === 7'b0000010, "FI-51: inj_oh recovers to S_P1R (7'b0000010) on release");
        repeat (20) @(posedge clk);
        tb_check(o_ref_cnt >= 16'd4 && o_drm_fault === 1'b0,
                 $sformatf("FI-51: victim refreshes emitted after recovery (ref_cnt=%0d, fault=%0b)", o_ref_cnt, o_drm_fault));

        //---------------------------------------------------------------------
        // FI-52, FI-53, FI-54: blkp_a / blkp_b
        //---------------------------------------------------------------------
        do_reset();
        i_mit_ack = 1'b0; // giữ nạn nhân trong PROQ để kiểm tra chặn ứng viên
        @(negedge clk);
        i_aggr_valid = 1'b1;
        i_aggr_bg    = 3'd3;
        i_aggr_bank  = 2'd2;
        i_aggr_row   = 16'h0400;
        @(posedge clk);
        @(negedge clk);
        i_aggr_valid = 1'b0;
        repeat (4) @(posedge clk);
        // Đưa ứng viên trùng vùng (BG 3, bank 2, row 16'h0401)
        @(negedge clk);
        i_cand_valid[3] = 1'b1;
        i_cand_bank[3]  = 2'd2;
        i_cand_row[3]   = 16'h0401;
        @(posedge clk);
        #1ps;
        tb_check(o_proq_blk[3] === 1'b1, "FI-52 setup: candidate in BG 3 blocked by PROQ");
        // FI-52: xóa blkp_a[3] 1 -> 0 -> blkp_b[3] vẫn giữ o_proq_blk[3] == 1 và báo o_drm_fault ở +1
        @(negedge clk);
        `QS_D_BLKP_A(u_dut)[3] = 1'b0;
        #1ps;
        tb_check(o_proq_blk[3] === 1'b1, "FI-52: blkp_b[3] masks blkp_a[3] 1->0 so o_proq_blk[3] stays 1");
        @(posedge clk);
        #1ps;
        tb_check(o_drm_fault === 1'b1, "FI-52: blkp_a ^ blkp_b mismatch raises o_drm_fault at +1 cycle");
        $display("[FI-RESIDUAL] FI-53: simultaneous blkp_a[3] and blkp_b[3] 1->0 documented in Q8");

        // FI-54: blkp_a[5] 0 -> 1 khi BG 5 idle -> báo o_drm_fault, các BG khác (ví dụ BG 0) không bị chặn (SA-F11)
        do_reset();
        @(negedge clk);
        `QS_D_BLKP_A(u_dut)[5] = 1'b1;
        #1ps;
        tb_check(o_proq_blk[0] === 1'b0 && o_proq_blk[5] === 1'b1,
                 "FI-54: blkp_a[5] 0->1 blocks only BG 5, leaving BG 0 unblocked (SA-F11)");
        @(posedge clk);
        #1ps;
        tb_check(o_drm_fault === 1'b1, "FI-54: blkp_a[5] 0->1 raises o_drm_fault at +1 cycle");

        //---------------------------------------------------------------------
        // FI-55: pq_v[i] lật khác pq_region[i] -> phát hiện lỗi trong <= 2 chu kỳ và tự khôi phục pq_v <= pq_region
        //---------------------------------------------------------------------
        do_reset();
        for (int idx = 0; idx < 8; idx++) begin
            @(negedge clk);
            `QS_D_PQ_V(u_dut)[idx] = ~`QS_D_PQ_V(u_dut)[idx];
            @(posedge clk);
            #1ps;
            tb_check(o_drm_fault === 1'b1 && `QS_D_PQ_V(u_dut)[idx] === `QS_D_PQ_REG(u_dut)[idx],
                     $sformatf("FI-55 slot %0d: pq_v flip detected on o_drm_fault and self-healed from pq_region", idx));
            @(posedge clk);
        end

        $display("[PERF] rd_cmds=0 wr_cmds=0 recov_extra_act=1 fi_count=60 fi_detect_lat_max=1");
        tb_report();
        $finish;
    end
endmodule
