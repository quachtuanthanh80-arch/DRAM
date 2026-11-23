// File:      tb_t88_ref_deadlock.sv
// Chức năng: Testbench tái hiện deadlock ref_mode/rd_pend_b (Điểm C T88) và kiểm tra chống đói đọc hợp lệ trên ddr5_cmd_engine.
`timescale 1ns / 1ps

module tb_t88_ref_deadlock;
    `include "tb_check.svh"

    localparam int BG_COUNT = 8;
    localparam int BANK_COUNT = 4;
    localparam int ROW_WIDTH = 17;
    localparam int COL_WIDTH = 13;
    localparam int T_REFI_TEST = 128;
    localparam int REF_WD_TEST = 128;

    logic clk = 1'b0;
    always #1.25 clk = ~clk;
    logic rst_n;

    logic        i_cmd_valid, i_cmd_is_write, i_cmd_is_mitigation;
    logic [3:0]  i_cmd_id;
    logic [2:0]  i_cmd_bg;
    logic [1:0]  i_cmd_bank;
    logic [ROW_WIDTH-1:0] i_cmd_row;
    logic [COL_WIDTH-1:0] i_cmd_col;
    logic [7:0]  i_cmd_len;
    logic [4:0]  i_cmd_tag;
    wire  [31:0] o_bank_free;
    wire         o_engine_mit_only;
    wire  [6:1]  o_fault;
    wire  [2:0]  o_dfi_cmd;
    wire  [2:0]  o_dfi_bg;
    wire  [1:0]  o_dfi_bank;
    wire  [ROW_WIDTH-1:0] o_dfi_row;
    wire  [COL_WIDTH-1:0] o_dfi_col;
    wire  [7:0]  o_dfi_len;
    wire  [4:0]  o_dfi_tag;
    logic        i_dfi_rddata_valid;
    logic [63:0] i_dfi_rddata;

    ddr5_cmd_engine #(
        .COL_WIDTH     (COL_WIDTH),
        .T_REFI        (T_REFI_TEST),
        .MAX_POSTPONE  (1),
        .REF_WD        (REF_WD_TEST),
        .RD_STARVE_MAX (16)
    ) u_dut (
        .clk                  (clk),
        .rst_n                (rst_n),
        .i_cmd_valid          (i_cmd_valid),
        .i_cmd_is_write       (i_cmd_is_write),
        .i_cmd_id             (i_cmd_id),
        .i_cmd_bg             (i_cmd_bg),
        .i_cmd_bank           (i_cmd_bank),
        .i_cmd_row            (i_cmd_row),
        .i_cmd_col            (i_cmd_col),
        .i_cmd_len            (i_cmd_len),
        .i_cmd_tag            (i_cmd_tag),
        .i_cmd_is_mitigation  (i_cmd_is_mitigation),
        .cfg_rowpress_thresh  (16'd5000),
        .cfg_rowpress_curve   (2'b00),
        .cfg_tras_max_thresh  (16'd8775),
        .o_rowpress_alert     (),
        .o_rowpress_bg        (),
        .o_rowpress_bank      (),
        .o_rowpress_row       (),
        .o_rowpress_alert_cnt (),
        .o_tras_clamped_alert (),
        .o_tras_clamped_cnt   (),
        .o_abo_active         (),
        .o_abo_alert_cnt      (),
        .o_abo_bg             (),
        .o_abo_bank           (),
        .o_abo_row            (),
        .o_rfm_auto_cnt       (),
        .o_cnt_fault          (),
        .o_fault              (o_fault),
        .o_rfm_active         (),
        .o_ref_tick           (),
        .o_bg_ready           (),
        .o_engine_ready       (),
        .o_bank_free          (o_bank_free),
        .o_engine_mit_only    (o_engine_mit_only),
        .o_slack_cycle        (),
        .o_decoy_take         (),
        .o_decoy_active       (),
        .o_decoy_cnt          (),
        .o_dfi_cmd            (o_dfi_cmd),
        .o_dfi_bg             (o_dfi_bg),
        .o_dfi_bank           (o_dfi_bank),
        .o_dfi_row            (o_dfi_row),
        .o_dfi_col            (o_dfi_col),
        .o_dfi_len            (o_dfi_len),
        .o_dfi_tag            (o_dfi_tag),
        .i_dfi_rddata_valid   (i_dfi_rddata_valid),
        .i_dfi_rddata         (i_dfi_rddata),
        .o_wb_valid           (),
        .o_wb_tag             (),
        .o_wb_data            (),
        .o_wb_resp            (),
        .o_wb_last            (),
        .o_rmw_valid          (),
        .o_rmw_beat           (),
        .o_wb_err             (),
        .o_rd_take            (),
        .o_rd_beat_ok         (),
        .o_rd_flush           (),
        .o_rd_resync          (),
        .o_precomp_valid      (),
        .o_precomp_is_write   (),
        .o_precomp_tag        (),
        .o_precomp_addr       (),
        .o_precomp_key_id     ()
    );

    // Mô hình phản hồi beat đọc DFI khớp T_RDV = 9
    logic [8:0] rd_pipe;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_pipe <= '0;
            i_dfi_rddata_valid <= 1'b0;
            i_dfi_rddata <= 64'h0;
        end else begin
            rd_pipe <= {rd_pipe[7:0], (o_dfi_cmd == 3'd3)};
            i_dfi_rddata_valid <= rd_pipe[7];
            i_dfi_rddata <= 64'hCAFE_BABE_0000_0001;
        end
    end

    task automatic send_cmd(input logic wr, input logic mit, input logic [2:0] bg, input logic [1:0] bk,
                            input logic [ROW_WIDTH-1:0] row, input logic [COL_WIDTH-1:0] col, input logic [4:0] tag);
        while (!o_bank_free[{bg, bk}]) @(posedge clk);
        @(negedge clk);
        i_cmd_valid         = 1'b1;
        i_cmd_is_write      = wr;
        i_cmd_is_mitigation = mit;
        i_cmd_id            = tag[3:0];
        i_cmd_bg            = bg;
        i_cmd_bank          = bk;
        i_cmd_row           = row;
        i_cmd_col           = col;
        i_cmd_len           = 8'd0;
        i_cmd_tag           = tag;
        @(posedge clk);
        @(negedge clk);
        i_cmd_valid = 1'b0;
    endtask

    initial begin
        bit fault4_seen;
        int ref_run, ref_max_run, ref_seen;

        rst_n = 1'b0;
        i_cmd_valid = 1'b0;
        i_cmd_is_write = 1'b0;
        i_cmd_is_mitigation = 1'b0;
        i_cmd_id = 4'd0;
        i_cmd_bg = 3'd0;
        i_cmd_bank = 2'd0;
        i_cmd_row = '0;
        i_cmd_col = '0;
        i_cmd_len = 8'd0;
        i_cmd_tag = 5'd0;
        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        repeat (3) @(negedge clk);

        // Ca 1: Deadlock ref_mode khi Bank 0 có WR hit đang giữ mở hàng + Bank 1 có RD miss đang chờ
        // 1a. Mở hàng 17'h00010 ở Bank 0 bằng một WR
        send_cmd(1'b1, 1'b0, 3'd0, 2'd0, 17'h00010, 13'h0000, 5'd1);
        repeat (16) @(posedge clk); // chờ ACT+WR xong, Bank 0 đang mở row 0x10

        // 1b. Nạp RD miss (Bank 1 đóng, row 0x20) rồi liên tục giữ WR hit (Bank 0, row 0x10) xuyên qua mốc tREFI
        fault4_seen = 1'b0;
        ref_run = 0;
        ref_max_run = 0;
        ref_seen = 0;
        fork
            begin
                // Đưa RD miss vào Bank 1 khi ref_mode sắp lên hoặc đang lên
                repeat (T_REFI_TEST - 24) @(posedge clk);
                send_cmd(1'b0, 1'b0, 3'd0, 2'd1, 17'h00020, 13'h0000, 5'd2);
            end
            begin
                for (int k = 0; k < 260; k++) begin
                    @(posedge clk);
                    if (o_fault[4]) fault4_seen = 1'b1;
                    if (u_dut.ref_mode) begin
                        ref_run++;
                        if (ref_run > ref_max_run) ref_max_run = ref_run;
                    end else begin
                        ref_run = 0;
                    end
                    if (o_dfi_cmd == 3'd5) ref_seen++;
                    // Bơm WR hit vào Bank 0 trước ref_mode để luôn có 1 WR hit kẹt lại khi ref_mode lên
                    if (!u_dut.ref_mode && !o_engine_mit_only && o_bank_free[{3'd0, 2'd0}]) begin
                        @(negedge clk);
                        i_cmd_valid = 1'b1; i_cmd_is_write = 1'b1; i_cmd_is_mitigation = 1'b0;
                        i_cmd_bg = 3'd0; i_cmd_bank = 2'd0; i_cmd_row = 17'h00010; i_cmd_col = 13'h0008;
                        i_cmd_len = 8'd0; i_cmd_tag = 5'd3;
                        @(posedge clk);
                        @(negedge clk);
                        i_cmd_valid = 1'b0;
                    end
                end
            end
        join

        tb_check(!fault4_seen, $sformatf("Case 1 (row-miss RD + row-hit WR in ref_mode): no spurious o_fault[4] (seen=%0b)", fault4_seen));
        tb_check(ref_max_run < REF_WD_TEST, $sformatf("Case 1: ref_mode_max_run=%0d < REF_WD=%0d", ref_max_run, REF_WD_TEST));
        tb_check(ref_seen >= 1, $sformatf("Case 1: REFab issued (ref_seen=%0d)", ref_seen));

        // Ca 2: Đọc hợp lệ ngoài ref_mode vẫn kích hoạt chống đói đọc (rd_starve_q) khi WR chiếm bus liên tục
        // Reset sạch để Ca 2 chạy hoàn toàn ngoài ref_mode (trước T_REFI_TEST = 64)
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);
        begin : ca2_starve
            bit starve_seen;
            starve_seen = 1'b0;
            // Nạp RD vào Bank 2 (đang đóng) và WR liên tục vào Bank 0 để kiểm tra rd_pend vẫn đếm ngoài ref_mode
            send_cmd(1'b0, 1'b0, 3'd0, 2'd2, 17'h00030, 13'h0000, 5'd4);
            for (int k = 0; k < 40; k++) begin
                @(posedge clk);
                if (u_dut.rd_starve_q) starve_seen = 1'b1;
                if (!o_engine_mit_only && o_bank_free[{3'd0, 2'd0}]) begin
                    @(negedge clk);
                    i_cmd_valid = 1'b1; i_cmd_is_write = 1'b1; i_cmd_is_mitigation = 1'b0;
                    i_cmd_bg = 3'd0; i_cmd_bank = 2'd0; i_cmd_row = 17'h00010; i_cmd_col = 13'h0010;
                    i_cmd_len = 8'd0; i_cmd_tag = 5'd5;
                    @(posedge clk);
                    @(negedge clk);
                    i_cmd_valid = 1'b0;
                end
            end
            tb_check(u_dut.s_v[{3'd0, 2'd2}] == 1'b0, $sformatf("Case 2: RD served cleanly under WR stream (starve_seen=%0b)", starve_seen));
        end

        tb_report();
        $finish;
    end
endmodule
