// File:      tb_bench_trace.sv
// Chức năng: Benchmark trên RTL thật: phát lại trace dòng 64B qua axi_ddr5_mc_top + mô hình DRAM, đo băng thông, độ trễ, row-hit và chi phí phòng thủ.
`timescale 1ns / 1ps
`include "qs_hier.svh"

module tb_bench_trace;
    localparam int AXI_ID_WIDTH = 4, AXI_ADDR_WIDTH = 32, AXI_DATA_WIDTH = 64, AXI_QOS_WIDTH = 4;
    localparam int BG_WIDTH = 3, BANK_WIDTH = 2, ROW_WIDTH = 17, COL_WIDTH = 13;
    localparam int TB_DFI_WRLAT = 9;
    // H-2: mọi điểm đo chạy clk_axi = clk_ddr = 2.5 ns; v2 tính hằng JEDEC từ TCK_PS nên DUT và checker cùng 2500 ps
    localparam int  TB_TCK_PS = 2500;
    localparam real CLK_NS = 2.5;
    localparam int  MAXLAT = 20000;
    localparam int  MAXWLAT = 20000;

    logic clk_axi = 0, clk_ddr = 0, aresetn_axi = 0, aresetn_ddr = 0;
    always #1.25 clk_axi = ~clk_axi;
    always #1.25 clk_ddr = ~clk_ddr;

    logic [AXI_ID_WIDTH-1:0] s_axi_awid, s_axi_bid, s_axi_arid, s_axi_rid;
    logic [31:0] s_axi_awaddr, s_axi_araddr;
    logic [7:0]  s_axi_awlen, s_axi_arlen;
    logic [2:0]  s_axi_awsize, s_axi_arsize;
    logic [1:0]  s_axi_awburst, s_axi_arburst, s_axi_bresp, s_axi_rresp;
    logic [3:0]  s_axi_awqos, s_axi_arqos;
    logic        s_axi_awvalid, s_axi_awready, s_axi_wlast, s_axi_wvalid, s_axi_wready, s_axi_bvalid, s_axi_bready;
    logic        s_axi_arvalid, s_axi_arready, s_axi_rlast, s_axi_rvalid, s_axi_rready;
    logic [63:0] s_axi_wdata, s_axi_rdata;
    logic [7:0]  s_axi_wstrb;
    logic [2:0]  dfi_cmd;
    logic [BG_WIDTH-1:0] dfi_bg;
    logic [BANK_WIDTH-1:0] dfi_bank;
    logic [ROW_WIDTH-1:0] dfi_row;
    logic [COL_WIDTH-1:0] dfi_col;
    logic [7:0]  dfi_len, dfi_wrdata_mask;
    logic        dfi_wrdata_en, dfi_rddata_valid;
    logic [63:0] dfi_wrdata, dfi_rddata;
    logic [7:0]  dfi_wrdata_ecc, dfi_rddata_ecc;
    // H-7: dây trung gian giữa dram_model và DUT để bơm lỗi beat đọc (dram_model không đổi)
    logic        dut_rd_valid;
    logic [63:0] dut_rd_data;
    logic [7:0]  dut_rd_ecc;
    logic        cfg_fault_clr = 1'b0;
    logic [8:0]  fault_cause;
    logic        glitch_alert;

    int  cfg_thresh   = 16'hFFFF;
    bit  cfg_scarf    = 0, cfg_scramble = 0, cfg_decoy = 0, cfg_coloring = 0;
    string trace_path, wl_name, cfg_name;

    axi_ddr5_mc_top #(.AXI_ID_WIDTH(AXI_ID_WIDTH), .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH), .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
                      .COL_WIDTH(COL_WIDTH), .DFI_WRLAT(TB_DFI_WRLAT)
`ifdef QS_V2
                      , .TCK_PS(TB_TCK_PS)
`endif
                      ) dut (
        .clk_axi(clk_axi), .aresetn_axi(aresetn_axi), .clk_ddr(clk_ddr), .aresetn_ddr(aresetn_ddr),
        .s_axi_awid(s_axi_awid), .s_axi_awaddr(s_axi_awaddr), .s_axi_awlen(s_axi_awlen), .s_axi_awsize(s_axi_awsize),
        .s_axi_awburst(s_axi_awburst), .s_axi_awqos(s_axi_awqos), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb), .s_axi_wlast(s_axi_wlast), .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bid(s_axi_bid), .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .s_axi_arid(s_axi_arid), .s_axi_araddr(s_axi_araddr), .s_axi_arlen(s_axi_arlen), .s_axi_arsize(s_axi_arsize),
        .s_axi_arburst(s_axi_arburst), .s_axi_arqos(s_axi_arqos), .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
        .s_axi_rid(s_axi_rid), .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp), .s_axi_rlast(s_axi_rlast),
        .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
        .s_axi_rpoison(), .s_axi_rchk(), .o_parity_err(),
        .dfi_cmd(dfi_cmd), .dfi_bg(dfi_bg), .dfi_bank(dfi_bank), .dfi_row(dfi_row), .dfi_col(dfi_col),
        .dfi_len(dfi_len), .dfi_wrdata_en(dfi_wrdata_en), .dfi_wrdata(dfi_wrdata), .dfi_wrdata_mask(dfi_wrdata_mask), .dfi_wrdata_ecc(dfi_wrdata_ecc),
        .dfi_rddata_valid(dut_rd_valid), .dfi_rddata(dut_rd_data), .dfi_rddata_ecc(dut_rd_ecc),
        .o_glitch_alert(glitch_alert),
`ifdef QS_V2
        .cfg_fault_clr(cfg_fault_clr), .o_fault_cause(fault_cause),
`endif
        .cfg_is_ddr5(1'b1), .cfg_dual_hash_en(1'b1), .cfg_rh_threshold(16'(cfg_thresh)), .cfg_window_size(16'd1000),
        .cfg_bank_coloring_en(cfg_coloring), .cfg_scramble_en(cfg_scramble), .cfg_scramble_seed(64'h1357_9BDF_2468_ACE0),
        .cfg_scramble_mode(cfg_scarf ? 2'b10 : 2'b00), .cfg_decoy_en(cfg_decoy)
    );
`ifndef QS_V2
    assign fault_cause = 9'd0;
`endif

    dram_model #(.COL_W(COL_WIDTH), .RL(8), .WL(TB_DFI_WRLAT)) u_dram (
        .clk(clk_axi), .rst_n(aresetn_axi), .cmd(dfi_cmd), .bg(dfi_bg), .bank(dfi_bank), .row(dfi_row), .col(dfi_col),
        .len(dfi_len), .wrdata_en(dfi_wrdata_en), .wrdata(dfi_wrdata), .wrdata_mask(dfi_wrdata_mask), .wrdata_ecc(dfi_wrdata_ecc),
        .rddata_valid(dfi_rddata_valid), .rddata(dfi_rddata), .rddata_ecc(dfi_rddata_ecc));

    dfi_jedec_checker #(.TCK_PS(TB_TCK_PS), .TB_DFI_WRLAT(TB_DFI_WRLAT)) u_jchk (.len(dut.u_cmd_engine.o_dfi_len), .clk(clk_axi), .rst_n(aresetn_axi), .cmd(dut.u_cmd_engine.o_dfi_cmd),
        .bg(dut.u_cmd_engine.o_dfi_bg), .bank(dut.u_cmd_engine.o_dfi_bank), .row(dut.u_cmd_engine.o_dfi_row));

    // H-3: checker v1 theo chu kỳ (đóng băng) chạy song song, chỉ để chứng minh P0 hợp lệ theo giả định của chính nó
    dfi_jedec_checker_cyc #(.T_CWL(TB_DFI_WRLAT)) u_jchk_cyc (.len(dut.u_cmd_engine.o_dfi_len), .clk(clk_axi), .rst_n(aresetn_axi),
        .cmd(dut.u_cmd_engine.o_dfi_cmd), .bg(dut.u_cmd_engine.o_dfi_bg), .bank(dut.u_cmd_engine.o_dfi_bank),
        .row(dut.u_cmd_engine.o_dfi_row));

    // Có bơm lỗi beat (H-7) thì miễn các luật "không báo động giả" của checker
    logic fi_any_bench = 1'b0;

    qs_axi_txn_chk #(
        .AXI_ADDR_W (AXI_ADDR_WIDTH),
        .AXI_DATA_W (AXI_DATA_WIDTH),
        .AXI_ID_W   (AXI_ID_WIDTH)
    ) u_achk (
        .clk           (clk_axi),
        .rst_n         (dut.rst_n_axi),
`ifdef QS_V2
        .en_v2         (1'b1),
`else
        .en_v2         (1'b0),
`endif
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

`ifdef QS_V2
    qs_engine_port_chk #(
        .TAG_W   (4),
        .T_RDV   (9)
    ) u_echk (
        .clk                 (clk_axi),
        .rst_n               (dut.rst_n_axi),
        .en_v2               (1'b1),
        .fi_any              (fi_any_bench),
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
        .ROB_DEPTH (16)
    ) u_pchk (
        .clk    (clk_axi),
        .rst_n  (dut.rst_n_axi),
        .en_v2  (1'b1),
        .fi_any (fi_any_bench)
    );
`endif

    //-------------------------------------------------------------------------
    // Bộ đếm sự kiện trên DFI: ACT do traffic, ACT làm tươi nạn nhân, ACT mồi, CAS, beat trên bus DQ
    //-------------------------------------------------------------------------
    longint cyc = 0;
    longint n_cas = 0, n_act_traffic = 0, n_act_victim = 0, n_act_decoy = 0, n_dq_beats = 0;
    // H-11: chẩn đoán (chỉ báo cáo, không điều khiển kích thích)
    longint ref_mode_cyc = 0, ref_mode_run = 0, ref_mode_max_run = 0;
    longint ref_wd_exp_cnt = 0, wcredit_block_cyc = 0, flush_cyc = 0, glitch_alert_cyc = 0;
    bit     ref_wd_exp_q = 0;
    always @(posedge clk_axi) begin
        cyc++;
        if (aresetn_axi) begin
            if (dut.u_cmd_engine.o_dfi_cmd == 3'd3 || dut.u_cmd_engine.o_dfi_cmd == 3'd4) n_cas++;
            if (dut.u_cmd_engine.o_dfi_cmd == 3'd1) begin
                if (dut.u_cmd_engine.o_decoy_active)         n_act_decoy++;
                else if (dut.u_cmd_engine.dfi_act_mit) n_act_victim++;
                else                                         n_act_traffic++;
            end
            if (dfi_wrdata_en || dfi_rddata_valid) n_dq_beats++;
            if (`QS_E_REF_MODE(dut.u_cmd_engine)) begin
                ref_mode_cyc++;
                ref_mode_run++;
                if (ref_mode_run > ref_mode_max_run) ref_mode_max_run = ref_mode_run;
            end else begin
                ref_mode_run = 0;
            end
            if (glitch_alert) glitch_alert_cyc++;
`ifdef QS_V2
            if (`QS_E_REF_WD_EXP(dut.u_cmd_engine) && !ref_wd_exp_q) ref_wd_exp_cnt++;
            ref_wd_exp_q = `QS_E_REF_WD_EXP(dut.u_cmd_engine);
            if (dut.u_cmd_engine.o_rd_flush) flush_cyc++;
            // Chi phí M-02: ghi có tín dụng thường nhưng bị chặn vì IQ còn đọc cùng BG và quỹ chung không đủ
            if (dut.wcmd_valid && `QS_T_BANK_CREDIT(dut)[{dut.wcmd_bg, dut.wcmd_bank}] &&
                !`QS_T_WBANK_CREDIT(dut)[{dut.wcmd_bg, dut.wcmd_bank}] && dut.iq_bg_pend[dut.wcmd_bg])
                wcredit_block_cyc++;
`endif
        end
    end

    //-------------------------------------------------------------------------
    // H-7: bơm lỗi beat đọc giữa dram_model và DUT (drop | extra_busy | extra_idle)
    //-------------------------------------------------------------------------
    string  fi_kind = "", fi_kind_s = "none";
    int     fi_n = 0, fi_gap = 1000, fi_after_reads = 0, fi_done = 0;
    bit [31:0] fi_rng = 32'h5153_0001;
    bit     fi_drop_now = 0, fi_ins_now = 0;
    logic [63:0] last_rd_data = 64'd0;
    logic [7:0]  last_rd_ecc = 8'd0;
    longint fi_last_cyc = -1;
    int     n_det = 0;
    longint det_lat_sum = 0, det_lat_max = 0;
    bit     fc5_q = 0;

    assign dut_rd_valid = (dfi_rddata_valid && !fi_drop_now) || (fi_ins_now && !dfi_rddata_valid);
    assign dut_rd_data  = (fi_ins_now && !dfi_rddata_valid) ? last_rd_data : dfi_rddata;
    assign dut_rd_ecc   = (fi_ins_now && !dfi_rddata_valid) ? last_rd_ecc  : dfi_rddata_ecc;

    always @(posedge clk_axi) begin
        if (dfi_rddata_valid) begin
            last_rd_data <= dfi_rddata;
            last_rd_ecc  <= dfi_rddata_ecc;
        end
    end

    function automatic bit [31:0] xs32(input bit [31:0] x);
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        return x;
    endfunction

    // v2: độ trễ phát hiện = tới cạnh lên o_fault_cause[5]; sau đó xoá bằng xung cfg_fault_clr 1 chu kỳ
    always @(posedge clk_axi) begin
        if (aresetn_axi) begin
            if (fault_cause[5] && !fc5_q && fi_last_cyc >= 0) begin
                n_det++;
                det_lat_sum += cyc - fi_last_cyc;
                if (cyc - fi_last_cyc > det_lat_max) det_lat_max = cyc - fi_last_cyc;
            end
            fc5_q = fault_cause[5];
        end
    end
    always @(negedge clk_axi) cfg_fault_clr = aresetn_axi && fault_cause[5] && fc5_q;

    task automatic fi_one(input int k);
        longint t0;
        bit hit;
        t0 = cyc;
        hit = 0;
        while (!hit && cyc - t0 < 100000) begin
            @(negedge clk_axi);
            if (fi_kind == "drop" && dfi_rddata_valid) hit = 1;
            else if (fi_kind == "extra_busy" && !dfi_rddata_valid && rd_issued > rd_done) hit = 1;
            else if (fi_kind == "extra_idle" && !dfi_rddata_valid && rd_issued == rd_done && wr_issued == b_done) hit = 1;
            if (hit) begin
                if (fi_kind == "drop") fi_drop_now = 1; else fi_ins_now = 1;
                fi_last_cyc = cyc;
                fi_done++;
                fi_any_bench = 1;
                $display("[FI-BENCH] k=%0d kind=%s cyc=%0d", k, fi_kind, cyc);
                @(negedge clk_axi);
                fi_drop_now = 0;
                fi_ins_now  = 0;
            end
        end
        if (!hit) $display("[FI-BENCH] k=%0d kind=%s no opportunity within 100000 cycles", k, fi_kind);
    endtask

    //-------------------------------------------------------------------------
    // Lệnh đọc/ghi đang chờ: độ trễ đọc AR -> RLAST, ghi AW -> B (B trả theo thứ tự trong ID)
    //-------------------------------------------------------------------------
    longint ar_t0 [16][64];
    longint aw_t0 [16][64];
    logic [31:0] ar_a [16][64];
    logic [31:0] aw_a [16][64];
    bit     ar_chk [16][64];
    int     ar_h [16], ar_t [16], aw_h [16], aw_t [16], r_beat [16];
    bit     r_slverr [16];
    int     lat [MAXLAT], vlat [MAXLAT], wlat [MAXWLAT], vwlat [MAXWLAT];
    int     n_lat = 0, n_vlat = 0, n_wlat = 0, n_vwlat = 0;
    int     rd_done = 0, rd_issued = 0, wr_issued = 0, b_done = 0;
    int     a_rd_issued = 0, a_rd_done = 0, v_reads = 0, v_writes = 0, v_rd_done = 0, v_b_done = 0;
    int     rd_okay_bad = 0, rd_slverr = 0, rd_poison = 0, rd_unchecked = 0, rd_checked = 0;
    initial for (int i = 0; i < 16; i++) begin ar_h[i] = 0; ar_t[i] = 0; aw_h[i] = 0; aw_t[i] = 0; r_beat[i] = 0; r_slverr[i] = 0; end

    // H-5: dữ liệu tất định theo địa chỉ; bảng các dòng 64B đã ghi xong (B) lưu địa chỉ gốc của burst ghi
    string  wdata_mode = "rand";
    localparam int WT_LOG = 16;
    localparam int WT_N   = 1 << WT_LOG;
    bit [25:0]  wt_key [WT_N];
    bit [31:0]  wt_base [WT_N];
    bit         wt_used [WT_N];

    function automatic int wt_find(input bit [25:0] line);
        int i, r;
        bit stop;
        i = int'((line * 26'd2654435) & (WT_N - 1));
        r = -1;
        stop = 0;
        for (int n = 0; n < WT_N && !stop; n++) begin
            if (!wt_used[i]) stop = 1;
            else if (wt_key[i] == line) begin r = i; stop = 1; end
            else i = (i + 1) % WT_N;
        end
        return r;
    endfunction

    task automatic wt_put(input bit [25:0] line, input bit [31:0] base);
        int i;
        bit done;
        i = int'((line * 26'd2654435) & (WT_N - 1));
        done = 0;
        for (int n = 0; n < WT_N && !done; n++) begin
            if (!wt_used[i] || wt_key[i] == line) begin
                wt_used[i] = 1; wt_key[i] = line; wt_base[i] = base; done = 1;
            end else i = (i + 1) % WT_N;
        end
    endtask

    function automatic logic [63:0] wbeat(input logic [31:0] base, input int b);
        return {base ^ 32'hA5C3_0F1E, 24'(b), 8'h5A};
    endfunction

    always @(posedge clk_axi) begin
        if (aresetn_axi && s_axi_rvalid && s_axi_rready) begin
            int id, slot, ix;
            logic [31:0] wa;
            id = s_axi_rid;
            slot = ar_h[id] % 64;
            if (s_axi_rresp == 2'b10) r_slverr[id] = 1;
            if (dut.s_axi_rpoison != '0) rd_poison++;
            if (wdata_mode == "addr") begin
                wa = ar_a[id][slot] + 32'(8 * r_beat[id]);
                ix = wt_find(wa[31:6]);
                if (!ar_chk[id][slot] || ix < 0) rd_unchecked++;
                else if (s_axi_rresp == 2'b00 && dut.s_axi_rpoison == '0) begin
                    rd_checked++;
                    if (s_axi_rdata !== wbeat(wt_base[ix], int'((wa - wt_base[ix]) >> 3))) begin
                        rd_okay_bad++;
                        if (rd_okay_bad <= 5)
                            $display("[BENCH-SB] OKAY beat with wrong data id=%0d addr=%h got=%h exp=%h", id, wa, s_axi_rdata,
                                     wbeat(wt_base[ix], int'((wa - wt_base[ix]) >> 3)));
                    end
                end
            end
            r_beat[id]++;
            if (s_axi_rlast) begin
                if (id >= 4 && id < 8) begin
                    if (n_vlat < MAXLAT) vlat[n_vlat++] = int'(cyc - ar_t0[id][slot]);
                    v_rd_done++;
                end else begin
                    if (n_lat < MAXLAT) lat[n_lat++] = int'(cyc - ar_t0[id][slot]);
                    a_rd_done++;
                end
                if (r_slverr[id]) rd_slverr++;
                r_slverr[id] = 0;
                r_beat[id] = 0;
                ar_h[id]++;
                rd_done++;
            end
        end
        if (aresetn_axi && s_axi_bvalid && s_axi_bready) begin
            int id, slot;
            id = s_axi_bid;
            slot = aw_h[id] % 64;
            if (id == 1) begin
                if (n_vwlat < MAXWLAT) vwlat[n_vwlat++] = int'(cyc - aw_t0[id][slot]);
                v_b_done++;
            end else if (n_wlat < MAXWLAT) wlat[n_wlat++] = int'(cyc - aw_t0[id][slot]);
            if (s_axi_bresp == 2'b00) wt_put(aw_a[id][slot][31:6], aw_a[id][slot]);
            aw_h[id]++;
            b_done++;
        end
    end

    // Dữ liệu W phát theo thứ tự handshake AW (dùng chung cho mọi luồng)
    int wq_n = 0;
    logic [31:0] wq_addr [$];
    initial begin
        s_axi_wvalid = 0; s_axi_wlast = 0; s_axi_wdata = 0; s_axi_wstrb = 8'hFF;
        forever begin
            @(posedge clk_axi);
            if (wq_n > 0) begin
                logic [31:0] base;
                base = wq_addr.pop_front();
                for (int b = 0; b < 8; b++) begin
                    @(negedge clk_axi);
                    s_axi_wdata  = (wdata_mode == "addr") ? wbeat(base, b) : {$urandom, $urandom};
                    s_axi_wlast  = (b == 7);
                    s_axi_wvalid = 1;
                    do @(posedge clk_axi); while (!s_axi_wready);
                end
                @(negedge clk_axi);
                s_axi_wvalid = 0;
                wq_n--;
            end
        end
    end

    // Hai luồng (H-6) dùng chung kênh AR/AW: khoá đơn giản, mô phỏng không tranh chấp giữa hai câu lệnh liền nhau
    bit ar_lock = 0, aw_lock = 0;

    task automatic issue_read(input logic [31:0] a, input int id);
        int slot;
        // Giữ tối đa 64 lệnh đọc đang chờ cho mỗi ID (giới hạn bộ đệm của testbench)
        while (ar_t[id] - ar_h[id] >= 63) @(posedge clk_axi);
        while (ar_lock) @(negedge clk_axi);
        ar_lock = 1;
        @(negedge clk_axi);
        s_axi_arid = id; s_axi_araddr = a; s_axi_arlen = 8'd7; s_axi_arsize = 3'd3; s_axi_arburst = 2'b01;
        s_axi_arqos = 4'd0; s_axi_arvalid = 1;
        do @(posedge clk_axi); while (!s_axi_arready);
        slot = ar_t[id] % 64;
        ar_t0[id][slot] = cyc;
        ar_a[id][slot]  = a;
        ar_chk[id][slot] = (wt_find(a[31:6]) >= 0);
        ar_t[id]++;
        rd_issued++;
        @(negedge clk_axi);
        s_axi_arvalid = 0;
        ar_lock = 0;
    endtask

    task automatic issue_write(input logic [31:0] a, input int id);
        int slot;
        while (aw_t[id] - aw_h[id] >= 63) @(posedge clk_axi);
        while (aw_lock) @(negedge clk_axi);
        aw_lock = 1;
        @(negedge clk_axi);
        s_axi_awid = id; s_axi_awaddr = a; s_axi_awlen = 8'd7; s_axi_awsize = 3'd3; s_axi_awburst = 2'b01;
        s_axi_awqos = 4'd0; s_axi_awvalid = 1;
        do @(posedge clk_axi); while (!s_axi_awready);
        slot = aw_t[id] % 64;
        aw_t0[id][slot] = cyc;
        aw_a[id][slot]  = a;
        aw_t[id]++;
        wq_addr.push_back(a);
        wq_n++;
        wr_issued++;
        @(negedge clk_axi);
        s_axi_awvalid = 0;
        aw_lock = 0;
    endtask

    // Sắp xếp chèn và phân vị trên một mảng độ trễ
`define BENCH_SORT(arr, n) for (int i = 1; i < n; i++) begin int v, j; v = arr[i]; j = i - 1; while (j >= 0 && arr[j] > v) begin arr[j + 1] = arr[j]; j--; end arr[j + 1] = v; end
`define BENCH_PCT(arr, n, p) ((n) ? arr[(((n) * (p)) / 100 >= (n)) ? (n) - 1 : ((n) * (p)) / 100] : 0)
`define BENCH_AVG(arr, n, res) begin longint s_; s_ = 0; for (int i = 0; i < n; i++) s_ += arr[i]; res = (n) ? real'(s_) / (n) : 0.0; end

    // H-6: luồng thứ hai mở (open-loop): mỗi op sau trace2_period chu kỳ, LD dùng ID 4..7, ST dùng ID 1
    string trace2_path = "";
    int    trace2_period = 100, trace2_start = 0;
    bit    trace2_done = 1;
    logic [31:0] t2_rd_q [$];
    logic [31:0] t2_wr_q [$];
    initial begin
        int vid;
        vid = 0;
        forever begin
            @(posedge clk_axi);
            while (t2_rd_q.size() > 0) begin
                issue_read(t2_rd_q.pop_front(), 4 + vid);
                vid = (vid + 1) % 4;
            end
        end
    end
    initial begin
        forever begin
            @(posedge clk_axi);
            while (t2_wr_q.size() > 0) issue_write(t2_wr_q.pop_front(), 1);
        end
    end
    initial begin
        int fd2;
        string op;
        logic [31:0] a;
        if ($value$plusargs("trace2=%s", trace2_path) && trace2_path != "") begin
            trace2_done = 0;
            if (!$value$plusargs("trace2_period=%d", trace2_period)) trace2_period = 100;
            if (!$value$plusargs("trace2_start=%d", trace2_start)) trace2_start = 0;
            wait (aresetn_axi);
            repeat (20 + trace2_start) @(posedge clk_axi);
            fd2 = $fopen(trace2_path, "r");
            if (fd2 == 0) $display("[BENCH-ERROR] cannot open trace2 %s", trace2_path);
            else begin
                while ($fscanf(fd2, "%s %h\n", op, a) == 2) begin
                    repeat (trace2_period) @(posedge clk_axi);
                    // Phát qua hàng chờ để luồng định nhịp không bị chặn bởi handshake (open-loop)
                    if (op == "LD") begin
                        t2_rd_q.push_back(a);
                        v_reads++;
                    end else if (op == "ST") begin
                        t2_wr_q.push_back(a);
                        v_writes++;
                    end
                end
                $fclose(fd2);
            end
            while (t2_rd_q.size() > 0 || t2_wr_q.size() > 0) @(posedge clk_axi);
            trace2_done = 1;
        end
    end

    initial begin
        int fd, maxops, n, rid, rd_out_lim, seed;
        longint drain_timeout;
        string op, rtl_tag;
        logic [31:0] a;
        longint t_start, t_end;
        longint thr0;
        s_axi_awvalid = 0; s_axi_arvalid = 0; s_axi_bready = 1; s_axi_rready = 1;
        if (!$value$plusargs("trace=%s", trace_path)) trace_path = "sim/traces/rtl_bench/stream_copy.trace";
        if (!$value$plusargs("wl=%s", wl_name)) wl_name = "unnamed";
        if (!$value$plusargs("cfg=%s", cfg_name)) cfg_name = "unnamed";
        if (!$value$plusargs("maxops=%d", maxops)) maxops = 1 << 30;
        if ($value$plusargs("thresh=%d", cfg_thresh)) ;
        if ($value$plusargs("scarf=%d", cfg_scarf)) ;
        if ($value$plusargs("scramble=%d", cfg_scramble)) ;
        if ($value$plusargs("decoy=%d", cfg_decoy)) ;
        if ($value$plusargs("coloring=%d", cfg_coloring)) ;
        // H-1, H-5, H-7, H-8, H-9
        if (!$value$plusargs("rtl=%s", rtl_tag)) rtl_tag = "unknown";
        if (!$value$plusargs("seed=%d", seed)) seed = 12345;
        if (!$value$plusargs("wdata_mode=%s", wdata_mode)) wdata_mode = "rand";
        if (!$value$plusargs("drain_timeout=%d", drain_timeout)) drain_timeout = 200000;
        if (!$value$plusargs("rd_outstanding=%d", rd_out_lim)) rd_out_lim = 0;
        if (!$value$plusargs("fi_kind=%s", fi_kind)) fi_kind = "";
        if (!$value$plusargs("fi_n=%d", fi_n)) fi_n = 0;
        if (!$value$plusargs("fi_gap=%d", fi_gap)) fi_gap = 1000;
        if (!$value$plusargs("fi_after_reads=%d", fi_after_reads)) fi_after_reads = 0;
        if (!$value$plusargs("fi_seed=%d", fi_rng)) fi_rng = 32'h5153_0001;
        if (fi_rng == 0) fi_rng = 32'h5153_0001;

        repeat (10) @(posedge clk_axi);
        aresetn_axi = 1; aresetn_ddr = 1;
        repeat (20) @(posedge clk_axi);

        if (fi_kind != "" && fi_n > 0)
            fork
                begin
                    while (rd_done < fi_after_reads) @(posedge clk_axi);
                    for (int k = 0; k < fi_n; k++) begin
                        fi_rng = xs32(fi_rng);
                        repeat (fi_gap + int'(fi_rng % 16)) @(posedge clk_axi);
                        fi_one(k);
                    end
                end
            join_none

        fd = $fopen(trace_path, "r");
        if (fd == 0) begin
            $display("[BENCH-ERROR] cannot open %s", trace_path);
            $finish;
        end
        thr0 = dut.u_sdc_filter.telemetry_throttles_reg;
        t_start = cyc;
        n = 0;
        rid = 0;
        while (n < maxops && $fscanf(fd, "%s %h\n", op, a) == 2) begin
            // Lệnh đọc dùng 8 ID xoay vòng (thứ tự AXI chỉ ràng buộc trong cùng ID), lệnh ghi dùng ID 0
            if (op == "LD") begin
                while (rd_out_lim > 0 && a_rd_issued - a_rd_done >= rd_out_lim) @(posedge clk_axi);
                issue_read(a, 8 + rid);
                a_rd_issued++;
                rid = (rid + 1) % 8;
            end else if (op == "BAR") begin
                // Rào: chờ mọi ghi đã có B và đã xuống DRAM, mọi đọc đã xong
                while ((b_done < wr_issued || u_dram.n_wr < wr_issued || rd_done < rd_issued) && cyc - t_start < drain_timeout * 16)
                    @(posedge clk_axi);
            end else begin
                issue_write(a, 0);
            end
            n++;
        end
        $fclose(fd);
        while (!trace2_done) @(posedge clk_axi);
        // Kết thúc khi mọi lệnh đọc có RLAST và mọi lệnh ghi đã xuống DRAM, hoặc hết drain_timeout (H-8)
        begin
            longint t_last;
            t_last = cyc;
            while ((rd_done < rd_issued || u_dram.n_wr < wr_issued || b_done < wr_issued) && cyc - t_last < drain_timeout)
                @(posedge clk_axi);
        end
        t_end = cyc;

        `BENCH_SORT(lat, n_lat)
        `BENCH_SORT(vlat, n_vlat)
        `BENCH_SORT(wlat, n_wlat)
        `BENCH_SORT(vwlat, n_vwlat)
        if (fi_kind == "") fi_kind_s = "none"; else fi_kind_s = fi_kind;
        begin
            int alllat [MAXLAT];
            int n_all;
            real secs, bw, avg, a_avg, v_avg, w_avg, vw_avg, all_avg;
            n_all = 0;
            for (int i = 0; i < n_lat && n_all < MAXLAT; i++) alllat[n_all++] = lat[i];
            for (int i = 0; i < n_vlat && n_all < MAXLAT; i++) alllat[n_all++] = vlat[i];
            `BENCH_SORT(alllat, n_all)
            `BENCH_AVG(alllat, n_all, all_avg)
            `BENCH_AVG(lat, n_lat, a_avg)
            `BENCH_AVG(vlat, n_vlat, v_avg)
            `BENCH_AVG(wlat, n_wlat, w_avg)
            `BENCH_AVG(vwlat, n_vwlat, vw_avg)
            avg  = all_avg;
            secs = real'(t_end - t_start) * CLK_NS * 1e-9;
            bw   = real'(64 * (rd_issued + wr_issued)) / secs / 1e9;
            $display("[BENCH] wl=%s cfg=%s rtl_tag=%s seed=%0d ops=%0d reads=%0d writes=%0d cycles=%0d clock_ns=%.2f bw_gbps=%.4f dq_util=%.4f rd_lat_avg_ns=%.1f rd_lat_p50_ns=%.1f rd_lat_p95_ns=%.1f rd_lat_p99_ns=%.1f rd_lat_max_ns=%.1f rd_lat_avg_cyc=%.2f rd_lat_p50_cyc=%0d rd_lat_p95_cyc=%0d rd_lat_p99_cyc=%0d rd_lat_max_cyc=%0d row_hit=%.4f act_traffic=%0d act_victim=%0d act_decoy=%0d cas=%0d ref=%0d rfm=%0d throttles=%0d jedec_viol=%0d dram_err=%0d complete=%0d",
                     wl_name, cfg_name, rtl_tag, seed, n, rd_issued, wr_issued, t_end - t_start, CLK_NS, bw,
                     real'(n_dq_beats) / real'(t_end - t_start), avg * CLK_NS,
                     `BENCH_PCT(alllat, n_all, 50) * CLK_NS, `BENCH_PCT(alllat, n_all, 95) * CLK_NS,
                     `BENCH_PCT(alllat, n_all, 99) * CLK_NS, (n_all ? alllat[n_all - 1] : 0) * CLK_NS,
                     avg, `BENCH_PCT(alllat, n_all, 50), `BENCH_PCT(alllat, n_all, 95), `BENCH_PCT(alllat, n_all, 99),
                     n_all ? alllat[n_all - 1] : 0,
                     n_cas ? 1.0 - real'(n_act_traffic) / real'(n_cas) : 0.0,
                     n_act_traffic, n_act_victim, n_act_decoy, n_cas, u_jchk.n_ref, u_jchk.n_rfm,
                     dut.u_sdc_filter.telemetry_throttles_reg - thr0, u_jchk.timing_violations() + u_jchk.viol_ref_open,
                     u_dram.errors(), (rd_done == rd_issued && u_dram.n_wr == wr_issued) ? 1 : 0);
            // H-3, H-4, H-5, H-6, H-7, H-8, H-11 trên dòng [BENCH] thứ hai cùng khoá wl/cfg/rtl_tag/seed
            $display("[BENCH] wl=%s cfg=%s rtl_tag=%s seed=%0d jedec_viol_ps=%0d jv_trcd=%0d jv_trp=%0d jv_tras=%0d jv_trc=%0d jv_trfc=%0d jv_trfm=%0d jv_trrd=%0d jv_tfaw=%0d jv_tccd=%0d jv_tccd_wr=%0d jv_twr=%0d jv_twtr=%0d jv_trasmax=%0d jv_ref_open=%0d jv_refgap=%0d jv_cyc=%0d ref_gap_max=%0d n_ref=%0d n_rfm=%0d",
                     wl_name, cfg_name, rtl_tag, seed, u_jchk.all_violations(), u_jchk.viol_trcd, u_jchk.viol_trp,
                     u_jchk.viol_tras, u_jchk.viol_trc, u_jchk.viol_trfc, u_jchk.viol_trfm, u_jchk.viol_trrd,
                     u_jchk.viol_tfaw, u_jchk.viol_tccd, u_jchk.viol_tccd_wr, u_jchk.viol_twr, u_jchk.viol_twtr,
                     u_jchk.viol_trasmax, u_jchk.viol_ref_open, u_jchk.viol_refgap,
                     u_jchk_cyc.timing_violations() + u_jchk_cyc.viol_ref_open, u_jchk.worst_ref_gap(), u_jchk.n_ref,
                     u_jchk.n_rfm);
            $display("[BENCH] wl=%s cfg=%s rtl_tag=%s seed=%0d wr_lat_avg_cyc=%.2f wr_lat_p50_cyc=%0d wr_lat_p99_cyc=%0d wr_lat_max_cyc=%0d a_reads=%0d a_rd_lat_avg_cyc=%.2f a_rd_lat_p50_cyc=%0d a_rd_lat_p99_cyc=%0d a_rd_lat_max_cyc=%0d v_reads=%0d v_writes=%0d v_rd_lat_avg_cyc=%.2f v_rd_lat_p50_cyc=%0d v_rd_lat_p99_cyc=%0d v_rd_lat_max_cyc=%0d v_wr_lat_avg_cyc=%.2f v_wr_lat_p99_cyc=%0d v_wr_lat_max_cyc=%0d",
                     wl_name, cfg_name, rtl_tag, seed, w_avg, `BENCH_PCT(wlat, n_wlat, 50), `BENCH_PCT(wlat, n_wlat, 99),
                     n_wlat ? wlat[n_wlat - 1] : 0, a_rd_done, a_avg, `BENCH_PCT(lat, n_lat, 50), `BENCH_PCT(lat, n_lat, 99),
                     n_lat ? lat[n_lat - 1] : 0, v_reads, v_writes, v_avg, `BENCH_PCT(vlat, n_vlat, 50),
                     `BENCH_PCT(vlat, n_vlat, 99), n_vlat ? vlat[n_vlat - 1] : 0, vw_avg, `BENCH_PCT(vwlat, n_vwlat, 99),
                     n_vwlat ? vwlat[n_vwlat - 1] : 0);
            $display("[BENCH] wl=%s cfg=%s rtl_tag=%s seed=%0d wdata_mode=%s rd_checked=%0d rd_okay_bad=%0d rd_slverr=%0d rd_poison=%0d rd_unchecked=%0d hung_reads=%0d hung_writes=%0d fi_kind=%s fi_done=%0d n_det=%0d det_lat_avg_cyc=%.2f det_lat_max_cyc=%0d flush_cyc=%0d glitch_alert_cyc=%0d ref_mode_cyc=%0d ref_mode_max_run=%0d ref_wd_exp_cnt=%0d fault_cause=0x%03h glitch_alert=%0d wcredit_block_cyc=%0d",
                     wl_name, cfg_name, rtl_tag, seed, wdata_mode, rd_checked, rd_okay_bad, rd_slverr, rd_poison,
                     rd_unchecked, rd_issued - rd_done, wr_issued - b_done, fi_kind_s, fi_done,
                     n_det, n_det ? real'(det_lat_sum) / n_det : 0.0, det_lat_max, flush_cyc, glitch_alert_cyc,
                     ref_mode_cyc, ref_mode_max_run, ref_wd_exp_cnt, fault_cause, glitch_alert, wcredit_block_cyc);
        end
        $finish;
    end
endmodule
