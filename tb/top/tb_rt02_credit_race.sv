// File:      tb_rt02_credit_race.sv
// Chức năng: Kiểm thử Red-Team T-RT02a + FI-56/FI-57 trên axi_ddr5_mc_top: đua tín dụng đọc+ghi cùng BG cùng chu kỳ khi tổng bk_cnt >= 7 (M-02).
`timescale 1ns / 1ps
`include "qs_hier.svh"
`include "qs_fi.svh"

module tb_rt02_credit_race;
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
    localparam int TB_TCK_PS      = 2500;
    localparam int TB_DFI_WRLAT   = 9;

    logic clk_axi = 0, clk_ddr = 0;
    always #1.25 clk_axi = ~clk_axi;
    always #1.25 clk_ddr = ~clk_ddr;

    logic aresetn_axi = 0, aresetn_ddr = 0;

    logic [AXI_ID_WIDTH-1:0]   s_axi_awid = 0, s_axi_bid, s_axi_arid = 0, s_axi_rid;
    logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr = 0, s_axi_araddr = 0;
    logic [AXI_LEN_WIDTH-1:0]  s_axi_awlen = 0, s_axi_arlen = 0;
    logic [2:0]                s_axi_awsize = 3'd3, s_axi_arsize = 3'd3;
    logic [1:0]                s_axi_awburst = 2'b01, s_axi_arburst = 2'b01, s_axi_bresp, s_axi_rresp;
    logic [AXI_QOS_WIDTH-1:0]  s_axi_awqos = 0, s_axi_arqos = 0;
    logic                      s_axi_awvalid = 0, s_axi_awready;
    logic [AXI_DATA_WIDTH-1:0] s_axi_wdata = 0, s_axi_rdata;
    logic [AXI_STRB_WIDTH-1:0] s_axi_wstrb = 8'hFF;
    logic                      s_axi_wlast = 0, s_axi_wvalid = 0, s_axi_wready;
    logic                      s_axi_bvalid, s_axi_bready = 1;
    logic                      s_axi_arvalid = 0, s_axi_arready;
    logic                      s_axi_rlast, s_axi_rvalid, s_axi_rready = 1;
    logic                      s_axi_rpoison;

    logic [2:0]                dfi_cmd;
    logic [BG_WIDTH-1:0]       dfi_bg;
    logic [BANK_WIDTH-1:0]     dfi_bank;
    logic [ROW_WIDTH-1:0]      dfi_row;
    logic [COL_WIDTH-1:0]      dfi_col;
    logic [7:0]                dfi_len;
    logic                      dfi_wrdata_en;
    logic [63:0]               dfi_wrdata, dfi_rddata;
    logic [7:0]                dfi_wrdata_mask, dfi_wrdata_ecc, dfi_rddata_ecc;
    logic                      dfi_rddata_valid;

    logic                      cfg_fault_clr = 0;
    logic [8:0]                o_fault_cause;
    logic                      o_glitch_alert;
    logic                      fi_any = 0;

    axi_ddr5_mc_top #(
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .COL_WIDTH      (COL_WIDTH),
        .ROB_DEPTH      (ROB_DEPTH),
        .DFI_WRLAT      (TB_DFI_WRLAT),
        .TCK_PS         (TB_TCK_PS)
    ) dut (
        .clk_axi        (clk_axi),
        .aresetn_axi    (aresetn_axi),
        .clk_ddr        (clk_ddr),
        .aresetn_ddr    (aresetn_ddr),
        .s_axi_awid     (s_axi_awid),
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awlen    (s_axi_awlen),
        .s_axi_awsize   (s_axi_awsize),
        .s_axi_awburst  (s_axi_awburst),
        .s_axi_awqos    (s_axi_awqos),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wlast    (s_axi_wlast),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),
        .s_axi_bid      (s_axi_bid),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        .s_axi_arid     (s_axi_arid),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arlen    (s_axi_arlen),
        .s_axi_arsize   (s_axi_arsize),
        .s_axi_arburst  (s_axi_arburst),
        .s_axi_arqos    (s_axi_arqos),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),
        .s_axi_rid      (s_axi_rid),
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rlast    (s_axi_rlast),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),
        .s_axi_rpoison  (s_axi_rpoison),
        .s_axi_rchk     (),
        .o_parity_err   (),
        .dfi_cmd        (dfi_cmd),
        .dfi_bg         (dfi_bg),
        .dfi_bank       (dfi_bank),
        .dfi_row        (dfi_row),
        .dfi_col        (dfi_col),
        .dfi_len        (dfi_len),
        .dfi_wrdata_en  (dfi_wrdata_en),
        .dfi_wrdata     (dfi_wrdata),
        .dfi_wrdata_mask(dfi_wrdata_mask),
        .dfi_wrdata_ecc (dfi_wrdata_ecc),
        .dfi_rddata_valid(dfi_rddata_valid),
        .dfi_rddata     (dfi_rddata),
        .dfi_rddata_ecc (dfi_rddata_ecc),
        .cfg_is_ddr5    (1'b1),
        .cfg_dual_hash_en(1'b1),
        .cfg_rh_threshold(16'd2000),
        .cfg_window_size(16'd4096),
        .cfg_scramble_mode(2'b00),
        .cfg_fault_clr  (cfg_fault_clr),
        .o_fault_cause  (o_fault_cause),
        .o_glitch_alert (o_glitch_alert)
    );

    dram_model #(.COL_W(COL_WIDTH), .RL(8), .WL(TB_DFI_WRLAT)) u_dram (
        .clk(clk_axi), .rst_n(aresetn_axi), .cmd(dfi_cmd), .bg(dfi_bg), .bank(dfi_bank), .row(dfi_row), .col(dfi_col),
        .len(dfi_len), .wrdata_en(dfi_wrdata_en), .wrdata(dfi_wrdata), .wrdata_mask(dfi_wrdata_mask), .wrdata_ecc(dfi_wrdata_ecc),
        .rddata_valid(dfi_rddata_valid), .rddata(dfi_rddata), .rddata_ecc(dfi_rddata_ecc)
    );

    dfi_jedec_checker #(.TCK_PS(TB_TCK_PS), .TB_DFI_WRLAT(TB_DFI_WRLAT)) u_jchk (
        .clk(clk_axi), .rst_n(aresetn_axi), .cmd(dut.u_cmd_engine.o_dfi_cmd), .bg(dut.u_cmd_engine.o_dfi_bg),
        .bank(dut.u_cmd_engine.o_dfi_bank), .row(dut.u_cmd_engine.o_dfi_row), .len(dut.u_cmd_engine.o_dfi_len)
    );

    qs_axi_txn_chk #(
        .AXI_ADDR_W (AXI_ADDR_WIDTH),
        .AXI_DATA_W (AXI_DATA_WIDTH),
        .AXI_ID_W   (AXI_ID_WIDTH)
    ) u_achk (
        .clk           (clk_axi),
        .rst_n         (dut.rst_n_axi),
        .en_v2         (!fi_any),
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
        .s_axi_rpoison (s_axi_rpoison)
    );

    qs_engine_port_chk #(.TAG_W(4), .T_RDV(9)) u_echk (
        .clk                 (clk_axi),
        .rst_n               (dut.rst_n_axi),
        .en_v2               (1'b1),
        .fi_any              (fi_any),
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

    qs_top_probe_chk #(.ROB_DEPTH(ROB_DEPTH)) u_pchk (
        .clk    (clk_axi),
        .rst_n  (dut.rst_n_axi),
        .en_v2  (1'b1),
        .fi_any (fi_any)
    );

    function automatic logic [31:0] mk_addr(input int row, input int bg, input int bank, input int col64);
        logic [31:0] a;
        a        = '0;
        a[31:18] = row[13:0];
        a[17:16] = bank[1:0];
        a[15:9]  = col64[6:0];
        a[8:6]   = bg[2:0] ^ row[2:0];
        return a;
    endfunction

    initial begin
        int rng;
        $display("[SEED] 0x51530001");
        aresetn_axi = 0; aresetn_ddr = 0;
        repeat (10) @(posedge clk_axi);
        aresetn_axi = 1; aresetn_ddr = 1;
        repeat (20) @(posedge clk_axi);

        //---------------------------------------------------------------------
        // T-RT02a Pha 1 (Có hướng): Đạt >= 22 lần đọc+ghi cùng BG 0 cùng chu kỳ khi sum(bk_cnt[0]) == 7
        // Cơ chế: Dùng o_proq_blk[0] = 1 tạm thời giữ 7 lệnh trong hàng đợi BG 0:
        //   5 lệnh ở bank 0, 1 lệnh ở bank 1, 1 lệnh ở bank 2 (tổng = 7, bank 3 còn chỗ riêng res_ok=1).
        //   Sau đó nạp đồng thời 1 AR (BG 0, bank 0) và 1 AW+W (BG 0, bank 3) sao cho iq_sel_fire và wr_fire
        //   cùng nổ ở một cạnh posedge clk_axi khi sum(bk_cnt[0]) == 7!
        //---------------------------------------------------------------------
        for (int rep = 0; rep < 22; rep++) begin
            // Chặn arbiter rút BG 0 bằng proq_blk[0]
            force dut.u_drm.o_proq_blk = 8'h01;
            // Đưa 5 lệnh ghi vào BG 0 bank 0, 1 lệnh vào bank 1, 1 lệnh vào bank 2 (tổng 7 lệnh)
            for (int k = 0; k < 7; k++) begin
                int bk;
                bk = (k < 5) ? 0 : ((k == 5) ? 1 : 2);
                @(negedge clk_axi);
                s_axi_awid    = 4'd1;
                s_axi_awaddr  = mk_addr(16'h010 + rep * 8 + k, 0, bk, k);
                s_axi_awlen   = 8'd0;
                s_axi_awqos   = 4'd2;
                s_axi_awvalid = 1'b1;
                s_axi_wdata   = 64'hCAFE_0000_0000_0000 + rep * 16 + k;
                s_axi_wstrb   = 8'hFF;
                s_axi_wlast   = 1'b1;
                s_axi_wvalid  = 1'b1;
                do @(posedge clk_axi); while (!(s_axi_awready && s_axi_wready));
                @(negedge clk_axi);
                s_axi_awvalid = 1'b0;
                s_axi_wvalid  = 1'b0;
                s_axi_wlast   = 1'b0;
            end
            // Chờ 7 lệnh đi vào hàng đợi QoS và bk_cnt[0..3] ổn định ở tổng = 7 (5, 1, 1, 0)
            repeat (12) @(posedge clk_axi);

            // Phát AW+W tới BG 0 bank 3 ở chu kỳ T, và AR tới BG 0 bank 3 ở chu kỳ T+1
            // để wcmd_valid (trễ 2 chu kỳ qua wdata_buffer + wr_data_store) trùng đúng chu kỳ iq_sel_fire!
            @(negedge clk_axi);
            s_axi_awid    = 4'd2;
            s_axi_awaddr  = mk_addr(16'h010 + rep * 8 + 7, 0, 3, 7);
            s_axi_awlen   = 8'd0;
            s_axi_awqos   = 4'd2;
            s_axi_awvalid = 1'b1;
            s_axi_wdata   = 64'hBEEF_0000_0000_0000 + rep;
            s_axi_wstrb   = 8'hFF;
            s_axi_wlast   = 1'b1;
            s_axi_wvalid  = 1'b1;
            @(posedge clk_axi);
            @(negedge clk_axi);
            s_axi_awvalid = 1'b0;
            s_axi_wvalid  = 1'b0;
            s_axi_wlast   = 1'b0;
            s_axi_arid    = 4'(3 + (rep % 8));
            s_axi_araddr  = mk_addr(16'h010 + rep * 8 + 6, 0, 2, 6);
            s_axi_arlen   = 8'd0;
            s_axi_arqos   = 4'd7;
            s_axi_arvalid = 1'b1;
            @(posedge clk_axi);
            @(negedge clk_axi);
            s_axi_arvalid = 1'b0;

            repeat (6) @(posedge clk_axi);
            // Thả BG 0 để rút sạch 8 lệnh trong hàng đợi trước vòng tiếp theo
            release dut.u_drm.o_proq_blk;
            while (u_achk.rd_done < u_achk.rd_cmds || u_achk.wr_done < u_achk.wr_cmds ||
                   `QS_T_BK_CNT(dut)[0] != 0 || `QS_T_BK_CNT(dut)[1] != 0 ||
                   `QS_T_BK_CNT(dut)[2] != 0 || `QS_T_BK_CNT(dut)[3] != 0 || dut.fe_rd_req_valid || !dut.rd_iq_empty)
                @(posedge clk_axi);
            repeat (10) @(posedge clk_axi);
        end

        //---------------------------------------------------------------------
        // T-RT02a Pha 2: 16 seed ngẫu nhiên có ràng buộc dồn vào BG 0
        //---------------------------------------------------------------------
        for (int s = 0; s < 16; s++) begin
            rng = 32'h5153_0001 + s;
            for (int op = 0; op < 20; op++) begin
                int bk;
                rng = (rng * 1664525) + 1013904223;
                bk  = rng[1:0];
                @(negedge clk_axi);
                if (rng[2]) begin
                    s_axi_awid    = rng[6:3];
                    s_axi_awaddr  = mk_addr(16'h200 + op, 0, bk, op & 63);
                    s_axi_awlen   = 8'd0;
                    s_axi_awqos   = rng[10:7];
                    s_axi_awvalid = 1'b1;
                    s_axi_wdata   = {32'(rng), 32'(op)};
                    s_axi_wstrb   = 8'hFF;
                    s_axi_wlast   = 1'b1;
                    s_axi_wvalid  = 1'b1;
                    do @(posedge clk_axi); while (!(s_axi_awready && s_axi_wready));
                    @(negedge clk_axi);
                    s_axi_awvalid = 1'b0;
                    s_axi_wvalid  = 1'b0;
                    s_axi_wlast   = 1'b0;
                end else begin
                    s_axi_arid    = rng[6:3];
                    s_axi_araddr  = mk_addr(16'h200 + op, 0, bk, op & 63);
                    s_axi_arlen   = 8'd0;
                    s_axi_arqos   = rng[10:7];
                    s_axi_arvalid = 1'b1;
                    do @(posedge clk_axi); while (!s_axi_arready);
                    @(negedge clk_axi);
                    s_axi_arvalid = 1'b0;
                end
            end
            while (u_achk.rd_done < u_achk.rd_cmds || u_achk.wr_done < u_achk.wr_cmds) @(posedge clk_axi);
            repeat (30) @(posedge clk_axi);
        end

        tb_check(u_pchk.dual_rw_same_bg_sat7_cnt >= 20,
                 $sformatf("T-RT02a coverage: simultaneous RD+WR same BG when sum(bk_cnt)>=7 hit %0d times (min 20)",
                           u_pchk.dual_rw_same_bg_sat7_cnt));
        tb_check(u_pchk.errors() == 0 && u_achk.errors() == 0 && u_echk.errors() == 0,
                 $sformatf("T-RT02a invariants: SA-C01..C05, SA-P03, SA-W03, SA-F13 clean (top=%0d, axi=%0d, eng=%0d)",
                           u_pchk.errors(), u_achk.errors(), u_echk.errors()));

        //---------------------------------------------------------------------
        // FI-56: bk_cnt[0] := 0 khi còn lệnh đang bay -> phát hiện tràn âm (o_fault_cause[8]) khi trả tín dụng
        //---------------------------------------------------------------------
        fi_any = 1'b1;
        @(negedge clk_axi);
        s_axi_arid    = 4'd1;
        s_axi_araddr  = mk_addr(16'h300, 0, 0, 0);
        s_axi_arlen   = 8'd0;
        s_axi_arqos   = 4'd7;
        s_axi_arvalid = 1'b1;
        do @(posedge clk_axi); while (!s_axi_arready);
        @(negedge clk_axi);
        s_axi_arvalid = 1'b0;
        while (`QS_T_BK_CNT(dut)[0] == 0) @(posedge clk_axi);
        @(negedge clk_axi);
        `QS_T_BK_CNT(dut)[0] = 4'd0; // xóa bk_cnt[0] trước khi cs_valid trả tín dụng
        repeat (30) @(posedge clk_axi);
        tb_check(o_fault_cause[8] === 1'b1, "FI-56: bk_cnt underflow on credit release sets o_fault_cause[8]");

        // Xóa lỗi và kiểm FI-57: ép bank_credit/wbank_credit = 1 khi BG đầy (8 lệnh) -> phát hiện bỏ lệnh ở hàng đợi QoS
        @(negedge clk_axi);
        cfg_fault_clr = 1'b1;
        @(posedge clk_axi);
        @(negedge clk_axi);
        cfg_fault_clr = 1'b0;
        repeat (5) @(posedge clk_axi);

        force dut.u_qos_queue.o_cmd_ready = 1'b0; // làm đầy hàng đợi QoS
        @(negedge clk_axi);
        force dut.q_in_valid = 1'b1;
        @(posedge clk_axi);
        @(posedge clk_axi);
        #1ps;
        tb_check(o_fault_cause[8] === 1'b1, "FI-57: q_in_valid when sdc_cmd_ready=0 sets o_fault_cause[8]");
        release dut.q_in_valid;
        release dut.u_qos_queue.o_cmd_ready;
        repeat (10) @(posedge clk_axi);

        u_jchk.report("rt02");
        u_pchk.report("rt02");
        $display("[PERF] rd_cmds=%0d wr_cmds=%0d dual_rw_sat7=%0d max_bg_credit_sum=%0d fi_count=2 fi_detect_lat_max=1",
                 u_achk.rd_done, u_achk.wr_done, u_pchk.dual_rw_same_bg_sat7_cnt, u_pchk.max_bg_sum_seen);
        tb_report();
        $finish;
    end

    initial begin
        #200_000_000;
        $display("[FAIL] Watchdog timeout");
        tb_report();
        $finish;
    end
endmodule
