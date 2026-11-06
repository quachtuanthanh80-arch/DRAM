// File:      tb_rt01_ref_starvation.sv
// Chức năng: Kiểm thử Red-Team T-RT01a/b/c ở mức axi_ddr5_mc_top: chống bỏ đói REF và DoS chéo master dưới luồng ghi cùng hàng liên tục 25.000 chu kỳ.
`timescale 1ns / 1ps
`include "qs_hier.svh"
`include "qs_fi.svh"

module tb_rt01_ref_starvation;
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

`ifdef QS_BASELINE_V1
    localparam bit EN_V2 = 1'b0;
`else
    localparam bit EN_V2 = 1'b1;
`endif

    logic clk_axi = 0, clk_ddr = 0;
    always #1.25 clk_axi = ~clk_axi; // 400 MHz (TCK_PS = 2500)
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

    logic [8:0]                o_fault_cause;
    logic                      o_glitch_alert;

    axi_ddr5_mc_top #(
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .COL_WIDTH      (COL_WIDTH),
        .ROB_DEPTH      (ROB_DEPTH),
        .DFI_WRLAT      (TB_DFI_WRLAT)
`ifndef QS_BASELINE_V1
        , .TCK_PS       (TB_TCK_PS)
`endif
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
`ifndef QS_BASELINE_V1
        .cfg_fault_clr  (1'b0),
        .o_fault_cause  (o_fault_cause),
`endif
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
        .en_v2         (EN_V2),
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

`ifndef QS_BASELINE_V1
    qs_engine_port_chk #(.TAG_W(4), .T_RDV(9)) u_echk (
        .clk                 (clk_axi),
        .rst_n               (dut.rst_n_axi),
        .en_v2               (1'b1),
        .fi_any              (1'b0),
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
        .fi_any (1'b0)
    );
`endif

    longint cyc = 0;
    always @(posedge clk_axi) if (aresetn_axi) cyc++;

    // Theo dõi độ trễ đọc của Master 2 (ID=9)
    longint m2_ar_t0 [$];
    int     m2_max_lat = 0;
    int     m2_done = 0;

    always @(posedge clk_axi) begin
        if (aresetn_axi && s_axi_rvalid && s_axi_rready && s_axi_rlast && s_axi_rid == 4'd9) begin
            longint t0;
            int lat;
            if (m2_ar_t0.size() > 0) begin
                t0  = m2_ar_t0.pop_front();
                lat = int'(cyc - t0);
                if (lat > m2_max_lat) m2_max_lat = lat;
                m2_done++;
            end
        end
    end

    initial begin
        int base_lat, w_issued, r_issued, ref_before_c;
        $display("[SEED] 0x51530001");
        aresetn_axi = 0; aresetn_ddr = 0;
        repeat (10) @(posedge clk_axi);
        aresetn_axi = 1; aresetn_ddr = 1;
        repeat (20) @(posedge clk_axi);

        //---------------------------------------------------------------------
        // Đo độ trễ đọc không tải của Master 2 (ID=9, BG 3, bank 1)
        //---------------------------------------------------------------------
        @(negedge clk_axi);
        s_axi_arid    = 4'd9;
        s_axi_araddr  = 32'h0041_00C0; // BG 3, bank 1
        s_axi_arlen   = 8'd0;
        s_axi_arqos   = 4'd7;
        s_axi_arvalid = 1'b1;
        do @(posedge clk_axi); while (!s_axi_arready);
        m2_ar_t0.push_back(cyc);
        @(negedge clk_axi);
        s_axi_arvalid = 1'b0;
        while (m2_done == 0) @(posedge clk_axi);
        base_lat   = m2_max_lat;
        m2_max_lat = 0;

        //---------------------------------------------------------------------
        // T-RT01a & T-RT01b: Master 1 (ID=1) ghi liên tục cùng một hàng (BG 0, bank 0, row 0x0010)
        // trong 25.000 chu kỳ; Master 2 (ID=9) phát lệnh đọc tới BG khác (BG 3, bank 1, hàng đổi mỗi lần) mỗi 200 chu kỳ.
        // Giữ tối đa 5 lệnh ghi đang bay trong wdata_buffer (depth 8) để fe_wr_addr_ready không nghẽn fe_aw_backlog
        // ở frontend, trong khi hàng đợi QoS + slot bank (0,0) luôn bão hòa 100% lệnh ghi row-hit.
        //---------------------------------------------------------------------
        w_issued = 0;
        r_issued = 1;
        begin
            int w_inflight;
            bit aw_done, w_done;
            w_inflight = 0;
            aw_done    = 0;
            w_done     = 0;
            for (int c = 0; c < 25000; c++) begin
                @(negedge clk_axi);
                if (w_inflight < 5) begin
                    s_axi_awid    = 4'd1;
                    s_axi_awaddr  = 32'h0040_0000 + ((w_issued & 7) << 6); // cùng BG 0, bank 0, row 0x10
                    s_axi_awlen   = 8'd0;
                    s_axi_awqos   = 4'd2;
                    s_axi_awvalid = !aw_done;
                    s_axi_wdata   = 64'hA5A5_0000_0000_0000 + w_issued;
                    s_axi_wstrb   = 8'hFF;
                    s_axi_wlast   = 1'b1;
                    s_axi_wvalid  = !w_done;
                end else begin
                    s_axi_awvalid = 1'b0;
                    s_axi_wvalid  = 1'b0;
                    s_axi_wlast   = 1'b0;
                end

                // Master 2: mỗi 200 chu kỳ phát 1 AR tới BG khác (BG 3, bank 1, đổi hàng để luôn cần ACT)
                if ((c % 200 == 100) && (c < 24600) && !s_axi_arvalid) begin
                    int r_row;
                    r_row         = 16'h020 + (c / 200);
                    s_axi_arid    = 4'd9;
                    s_axi_araddr  = {r_row[13:0], 2'b01, 7'd0, (3'd3 ^ r_row[2:0]), 6'd0};
                    s_axi_arlen   = 8'd0;
                    s_axi_arqos   = 4'd7;
                    s_axi_arvalid = 1'b1;
                end
                @(posedge clk_axi);
                if (s_axi_bvalid && s_axi_bready && s_axi_bid == 4'd1 && w_inflight > 0)
                    w_inflight--;
                if (s_axi_awvalid && s_axi_awready) aw_done = 1'b1;
                if (s_axi_wvalid  && s_axi_wready)  w_done  = 1'b1;
                if (aw_done && w_done) begin
                    w_issued++;
                    w_inflight++;
                    aw_done = 1'b0;
                    w_done  = 1'b0;
                end
                if (s_axi_arvalid && s_axi_arready) begin
                    m2_ar_t0.push_back(cyc);
                    r_issued++;
                    @(negedge clk_axi);
                    s_axi_arvalid = 1'b0;
                end
            end
        end
        @(negedge clk_axi);
        s_axi_awvalid = 1'b0;
        s_axi_wvalid  = 1'b0;
        s_axi_wlast   = 1'b0;
        s_axi_arvalid = 1'b0;
        repeat (600) @(posedge clk_axi);

        tb_check(u_jchk.refresh_ok(),
                 $sformatf("a_ref_gap: SA-J21 worst REF gap %0d cyc <= 5*tREFI (%0d cyc)",
                           u_jchk.worst_ref_gap(), 5 * u_jchk.REFI_CYC));
        tb_check(u_jchk.n_ref >= (25000 / u_jchk.REFI_CYC) - 4,
                 $sformatf("a_ref_cnt: SA-R04 issued %0d REFs during 25000-cycle write stream", u_jchk.n_ref));
        tb_check(m2_done == r_issued && m2_max_lat <= base_lat + u_jchk.RFC_CYC + 2 + 192,
                 $sformatf("b_m2_latency: Master 2 max AR->R latency %0d cyc <= bound %0d cyc (done %0d/%0d)",
                           m2_max_lat, base_lat + u_jchk.RFC_CYC + 2 + 192, m2_done, r_issued));

        //---------------------------------------------------------------------
        // T-RT01c (Đối chứng): Luồng đọc liên tục cùng hàng trong 5.000 chu kỳ
        //---------------------------------------------------------------------
        ref_before_c = u_jchk.n_ref;
        for (int c = 0; c < 5000; c++) begin
            @(negedge clk_axi);
            s_axi_arid    = 4'd2;
            s_axi_araddr  = 32'h0040_0000 + ((c & 7) << 6);
            s_axi_arlen   = 8'd0;
            s_axi_arqos   = 4'd2;
            s_axi_arvalid = 1'b1;
            @(posedge clk_axi);
            if (s_axi_arvalid && s_axi_arready) r_issued++;
        end
        @(negedge clk_axi);
        s_axi_arvalid = 1'b0;
        repeat (600) @(posedge clk_axi);

        tb_check(u_jchk.refresh_ok() && (u_jchk.n_ref > ref_before_c),
                 $sformatf("c_read_stream_ref: SA-J21 and SA-R04 clean under read stream (+%0d REFs)",
                           u_jchk.n_ref - ref_before_c));
        tb_check(u_jchk.timing_violations() == 0 && u_jchk.viol_ref_open == 0,
                 $sformatf("a_jedec_clean: 0 JEDEC timing/REF-open violations (%0d, %0d)",
                           u_jchk.timing_violations(), u_jchk.viol_ref_open));

        repeat (2) @(posedge clk_axi);
        u_achk.final_check();
        u_jchk.report("rt01");
        u_achk.report("rt01");
`ifndef QS_BASELINE_V1
        u_echk.final_check();
        u_echk.report("rt01");
        u_pchk.report("rt01");
        tb_check(u_achk.errors() == 0, $sformatf("qs_axi_txn_chk zero errors (%0d)", u_achk.errors()));
        tb_check(u_echk.errors() == 0, $sformatf("qs_engine_port_chk zero errors (%0d)", u_echk.errors()));
        tb_check(u_pchk.errors() == 0, $sformatf("qs_top_probe_chk zero errors (%0d)", u_pchk.errors()));
`endif
        $display("[PERF] rd_cmds=%0d wr_cmds=%0d rd_lat_max=%0d n_ref=%0d n_rfm=%0d ref_gap_max_ps=%0d",
                 r_issued, w_issued, m2_max_lat, u_jchk.n_ref, u_jchk.n_rfm, u_jchk.worst_ref_gap_ps());
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
