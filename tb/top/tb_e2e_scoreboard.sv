// File:      tb_e2e_scoreboard.sv
// Chức năng: Scoreboard end-to-end AXI -> DRAM -> AXI: lưu lượng ngẫu nhiên nhiều ID, burst 1-8 beat, WSTRB ngẫu nhiên, xung đột RAW/WAR/WAW, có/không scrambler.
`timescale 1ns / 1ps

module tb_e2e_scoreboard #(
    parameter int TB_TCK_PS    = 4000,
    parameter int TB_DFI_WRLAT = 9
);
    import secded_72_64_pkg::*;
    `include "tb_check.svh"

    localparam int AXI_ID_WIDTH   = 4;
    localparam int AXI_ADDR_WIDTH = 32;
    localparam int AXI_DATA_WIDTH = 64;
    localparam int AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8;
    localparam int AXI_QOS_WIDTH  = 4;
    localparam int BG_WIDTH       = 3;
    localparam int BANK_WIDTH     = 2;
    localparam int ROW_WIDTH      = 17;
    localparam int COL_WIDTH      = 13;
    localparam real HALF_CLK_NS   = TB_TCK_PS / 2000.0;

    // Vùng địa chỉ: 16 dòng 64B rải trên 4 hàng x 2 bank (tạo row hit/conflict) -> 128 word
    localparam int LINES = 16;
    localparam int WORDS = LINES * 8;
    localparam int N_OPS = 600;

    logic clk_axi = 0, clk_ddr = 0;
    logic aresetn_axi = 0, aresetn_ddr = 0;
    always #(HALF_CLK_NS) clk_axi = ~clk_axi;
    always #1.25 clk_ddr = ~clk_ddr;

    logic [AXI_ID_WIDTH-1:0]   s_axi_awid;
    logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr;
    logic [7:0]                s_axi_awlen;
    logic [2:0]                s_axi_awsize;
    logic [1:0]                s_axi_awburst;
    logic [AXI_QOS_WIDTH-1:0]  s_axi_awqos;
    logic                      s_axi_awvalid, s_axi_awready;
    logic [AXI_DATA_WIDTH-1:0] s_axi_wdata;
    logic [AXI_STRB_WIDTH-1:0] s_axi_wstrb;
    logic                      s_axi_wlast, s_axi_wvalid, s_axi_wready;
    logic [AXI_ID_WIDTH-1:0]   s_axi_bid;
    logic [1:0]                s_axi_bresp;
    logic                      s_axi_bvalid, s_axi_bready;
    logic [AXI_ID_WIDTH-1:0]   s_axi_arid;
    logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr;
    logic [7:0]                s_axi_arlen;
    logic [2:0]                s_axi_arsize;
    logic [1:0]                s_axi_arburst;
    logic [AXI_QOS_WIDTH-1:0]  s_axi_arqos;
    logic                      s_axi_arvalid, s_axi_arready;
    logic [AXI_ID_WIDTH-1:0]   s_axi_rid;
    logic [AXI_DATA_WIDTH-1:0] s_axi_rdata;
    logic [1:0]                s_axi_rresp;
    logic                      s_axi_rlast, s_axi_rvalid, s_axi_rready;

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

    logic                      cfg_scramble_en = 0;
    logic                      cfg_fault_clr   = 0;
    logic                      fi_ecc_phase    = 0;
    logic                      s_axi_rpoison;
    logic [8:0]                o_fault_cause;
    logic                      o_glitch_alert;

    axi_ddr5_mc_top #(
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .COL_WIDTH      (COL_WIDTH),
        .TCK_PS         (TB_TCK_PS)
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
        .s_axi_rpoison(s_axi_rpoison), .s_axi_rchk(), .o_parity_err(),
        .dfi_cmd(dfi_cmd), .dfi_bg(dfi_bg), .dfi_bank(dfi_bank), .dfi_row(dfi_row), .dfi_col(dfi_col),
        .dfi_len(dfi_len), .dfi_wrdata_en(dfi_wrdata_en), .dfi_wrdata(dfi_wrdata), .dfi_wrdata_mask(dfi_wrdata_mask), .dfi_wrdata_ecc(dfi_wrdata_ecc),
        .dfi_rddata_valid(dfi_rddata_valid), .dfi_rddata(dfi_rddata), .dfi_rddata_ecc(dfi_rddata_ecc),
        .cfg_is_ddr5(1'b1), .cfg_dual_hash_en(1'b1), .cfg_rh_threshold(16'd2000), .cfg_window_size(16'd1000),
        .cfg_scramble_en(cfg_scramble_en), .cfg_scramble_seed(64'h1357_9BDF_2468_ACE0),
        .cfg_fault_clr(cfg_fault_clr), .o_fault_cause(o_fault_cause), .o_glitch_alert(o_glitch_alert)
    );

    dram_model #(.COL_W(COL_WIDTH), .RL(8), .WL(TB_DFI_WRLAT)) u_dram (
        .clk(clk_axi), .rst_n(aresetn_axi), .cmd(dfi_cmd), .bg(dfi_bg), .bank(dfi_bank), .row(dfi_row), .col(dfi_col),
        .len(dfi_len), .wrdata_en(dfi_wrdata_en), .wrdata(dfi_wrdata), .wrdata_mask(dfi_wrdata_mask), .wrdata_ecc(dfi_wrdata_ecc),
        .rddata_valid(dfi_rddata_valid), .rddata(dfi_rddata), .rddata_ecc(dfi_rddata_ecc)
    );

    dfi_jedec_checker #(.TCK_PS(TB_TCK_PS), .TB_DFI_WRLAT(TB_DFI_WRLAT)) u_jchk (.len(dut.u_cmd_engine.o_dfi_len), 
        .clk(clk_axi), .rst_n(aresetn_axi), .cmd(dut.u_cmd_engine.o_dfi_cmd), .bg(dut.u_cmd_engine.o_dfi_bg),
        .bank(dut.u_cmd_engine.o_dfi_bank), .row(dut.u_cmd_engine.o_dfi_row)
    );

    qs_axi_txn_chk #(
        .AXI_ADDR_W (AXI_ADDR_WIDTH),
        .AXI_DATA_W (AXI_DATA_WIDTH),
        .AXI_ID_W   (AXI_ID_WIDTH),
        .N_TXN      (8192)
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
        .s_axi_rpoison (s_axi_rpoison)
    );

    qs_engine_port_chk #(
        .TAG_W   (4),
        .T_RDV   (9)
    ) u_echk (
        .clk                 (clk_axi),
        .rst_n               (dut.rst_n_axi),
        .en_v2               (1'b1),
        .fi_any              (fi_ecc_phase),
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
        .fi_any (fi_ecc_phase)
    );

    //-------------------------------------------------------------------------
    // Mô hình tham chiếu: mỗi lệnh ghi tạo một phiên bản mới của các word nó phủ (thứ tự AW), byte không ghi giữ giá trị cũ.
    // Ngữ nghĩa AXI4: lệnh đọc có handshake AR sau khi đã nhận B của một lệnh ghi phải thấy lệnh ghi đó; lệnh ghi
    // còn chưa có B khi AR xảy ra thì đọc thấy hay không đều hợp lệ. Beat đọc hợp lệ khi phiên bản của nó không cũ hơn
    // phiên bản mới nhất đã hoàn tất (có B) trước AR. Lịch sử giữ HIST phiên bản gần nhất của mỗi word.
    //-------------------------------------------------------------------------
    longint cyc = 0;
    localparam int HIST = 32;
    logic [63:0] ref_mem [WORDS];
    logic [63:0] hist_val [WORDS][HIST];
    longint      hist_t   [WORDS][HIST];   // chu kỳ handshake AW
    longint      hist_b   [WORDS][HIST];   // chu kỳ nhận B (vô cùng khi chưa có)
    int          hist_n   [WORDS];

    // Lệnh ghi chờ B: B trả về theo thứ tự AW (kho ghi gom theo thứ tự AW)
    int          bq_w0    [$];
    int          bq_nb    [$];
    int          bq_ver   [$];   // hist_n của word đầu tại thời điểm ghi (phiên bản của lệnh này)

    task automatic hist_push(input int w);
        int k;
        k = hist_n[w] % HIST;
        hist_val[w][k] = ref_mem[w];
        hist_t[w][k]   = cyc;
        hist_b[w][k]   = 64'h7FFF_FFFF_FFFF_FFFF;
        hist_n[w]++;
    endtask

    // Đánh dấu phiên bản của lệnh ghi cũ nhất đang chờ là đã hoàn tất (có B)
    task automatic mark_b();
        int w0, nb, v;
        w0 = bq_w0.pop_front();
        nb = bq_nb.pop_front();
        v  = bq_ver.pop_front();
        for (int b = 0; b < nb; b++) begin
            // phiên bản của lệnh này ở word (w0+b) là phiên bản thứ v_b; tìm theo thời điểm AW đã lưu
            for (int k = 0; k < HIST; k++)
                if (hist_t[w0 + b][k] == longint'(v) && hist_b[w0 + b][k] > cyc) hist_b[w0 + b][k] = cyc;
        end
    endtask

    // Cam kết mạnh hơn AXI của thiết kế: lệnh đọc có AR sau AW của lệnh ghi phải thấy lệnh ghi đó (RAW tính từ AW)
    function automatic bit strict_value(input int w, input longint t_ar, input logic [63:0] v);
        longint floor_t;
        int k, n;
        floor_t = -1;
        n = (hist_n[w] < HIST) ? hist_n[w] : HIST;
        for (int i = 0; i < n; i++) begin
            k = (hist_n[w] - 1 - i) % HIST;
            if (hist_t[w][k] <= t_ar && hist_t[w][k] > floor_t) floor_t = hist_t[w][k];
        end
        for (int i = 0; i < n; i++) begin
            k = (hist_n[w] - 1 - i) % HIST;
            if (hist_t[w][k] >= floor_t && hist_val[w][k] === v) return 1;
        end
        return 0;
    endfunction
    int strict_bad = 0;

    // Hợp lệ khi phiên bản trả về có thời điểm AW >= phiên bản mới nhất đã có B trước AR
    function automatic bit legal_value(input int w, input longint t_ar, input logic [63:0] v);
        longint floor_t;
        int k, n;
        floor_t = -1;
        n = (hist_n[w] < HIST) ? hist_n[w] : HIST;
        for (int i = 0; i < n; i++) begin
            k = (hist_n[w] - 1 - i) % HIST;
            if (hist_b[w][k] <= t_ar && hist_t[w][k] > floor_t) floor_t = hist_t[w][k];
        end
        for (int i = 0; i < n; i++) begin
            k = (hist_n[w] - 1 - i) % HIST;
            if (hist_t[w][k] >= floor_t && hist_val[w][k] === v) return 1;
        end
        return 0;
    endfunction
    int          line_base [LINES];

    function automatic logic [31:0] word_addr(input int w);
        return 32'(line_base[w / 8] + (w % 8) * 8);
    endfunction

    // Lệnh đọc đang chờ (mảng slot cố định, Icarus không hỗ trợ queue chứa struct): dữ liệu dự kiến chụp tại
    // handshake AR; RID khớp với lệnh cùng ID có số thứ tự phát nhỏ nhất (AXI4 giữ thứ tự trong cùng ID)
    localparam int PEND = 64;
    bit          pend_v   [PEND];
    int          pend_id  [PEND];
    int          pend_nb  [PEND];
    longint      pend_seq [PEND];
    longint      pend_t0  [PEND];
    int          pend_w0  [PEND];
    logic [63:0] pend_exp [PEND][8];
    longint      seq_ctr = 0;
    int          n_pend = 0;
    int  r_beats_ok, r_beats_bad, r_bursts, r_id_err, r_last_err, r_resp_err;
    logic [63:0] last_rdata;
    logic [1:0]  last_rresp;
    logic        last_rpoison;

    // Beat đọc RMW (dữ liệu cũ trộn vào slot ghi) và địa chỉ DFI của lệnh RD gần nhất
    int          n_rmw_beats = 0;
    bit [63:0]   last_rd_key;
    always @(posedge clk_axi) begin
        if (dut.u_cmd_engine.o_rmw_valid) n_rmw_beats++;
        if (dfi_cmd == 3'd3) last_rd_key = u_dram.key_of(dfi_bg, dfi_bank, dfi_row, dfi_col);
    end
    int  b_count, b_err;
    int  ar_count, aw_count;

    // Dữ liệu W chờ phát theo thứ tự AW
    logic [63:0] wq_data [$];
    logic [7:0]  wq_strb [$];
    bit          wq_last [$];

    // Latency đo theo chu kỳ (AR handshake -> RLAST)
    bit     trace_en = 0;
    initial if ($test$plusargs("trace")) trace_en = 1;
    always @(posedge clk_axi) cyc++;
    longint lat_sum = 0, lat_max = 0;
    int     lat_n = 0;

    // Bộ thu kênh R: so từng beat với dữ liệu dự kiến của lệnh đọc cũ nhất cùng ID
    int cur_beat [16];
    initial begin
        for (int i = 0; i < 16; i++) cur_beat[i] = 0;
        for (int k = 0; k < PEND; k++) pend_v[k] = 0;
    end
    // Pha 3 (AXI đầy đủ) kiểm tra tuần tự: beat R và phản hồi B được gom riêng, không qua bộ so khớp ngẫu nhiên
    bit          p3 = 0;
    logic [63:0] r3_data [$];
    bit          r3_last [$];
    logic [1:0]  r3_resp [$];
    int          b3_count = 0, b3_err = 0;
    always @(posedge clk_axi) begin
        if (p3) begin
            if (aresetn_axi && s_axi_rvalid && s_axi_rready) begin
                r3_data.push_back(s_axi_rdata);
                r3_last.push_back(s_axi_rlast);
                r3_resp.push_back(s_axi_rresp);
            end
            if (aresetn_axi && s_axi_bvalid && s_axi_bready) begin
                b3_count++;
                if (s_axi_bresp != 2'b00) b3_err++;
            end
        end else if (aresetn_axi && s_axi_rvalid && s_axi_rready) begin
            int idx, id;
            id  = s_axi_rid;
            last_rdata   = s_axi_rdata;
            last_rresp   = s_axi_rresp;
            last_rpoison = s_axi_rpoison;
            idx = -1;
            for (int k = 0; k < PEND; k++)
                if (pend_v[k] && pend_id[k] == id && (idx < 0 || pend_seq[k] < pend_seq[idx])) idx = k;
            if (idx < 0) begin
                r_id_err++;
            end else begin
                if (s_axi_rresp != 2'b00) r_resp_err++;
                if (!strict_value(pend_w0[idx] + cur_beat[id], pend_t0[idx], s_axi_rdata)) strict_bad++;
                if (legal_value(pend_w0[idx] + cur_beat[id], pend_t0[idx], s_axi_rdata)) r_beats_ok++;
                else begin
                    r_beats_bad++;
                    if (r_beats_bad <= 6)
                        $display("  [DIAG] cyc %0d RID %0d word %0d (AR at cyc %0d) beat %0d: got %h expected %h", cyc, id,
                                 pend_w0[idx] + cur_beat[id], pend_t0[idx], cur_beat[id], s_axi_rdata, pend_exp[idx][cur_beat[id]]);
                    if (trace_en)
                        for (int i = 0; i < hist_n[pend_w0[idx] + cur_beat[id]] && i < HIST; i++)
                            $display("      version written at cyc %0d = %h", hist_t[pend_w0[idx] + cur_beat[id]][i],
                                     hist_val[pend_w0[idx] + cur_beat[id]][i]);
                end
                if (s_axi_rlast !== (cur_beat[id] == pend_nb[idx] - 1)) r_last_err++;
                if (s_axi_rlast || cur_beat[id] == pend_nb[idx] - 1) begin
                    lat_sum += cyc - pend_t0[idx];
                    if (cyc - pend_t0[idx] > lat_max) lat_max = cyc - pend_t0[idx];
                    lat_n++;
                    pend_v[idx] = 0;
                    n_pend--;
                    cur_beat[id] = 0;
                    r_bursts++;
                end else begin
                    cur_beat[id]++;
                end
            end
        end
        if (!p3 && aresetn_axi && s_axi_bvalid && s_axi_bready) begin
            b_count++;
            if (bq_w0.size() > 0) mark_b();
            if (s_axi_bresp != 2'b00) b_err++;
        end
    end

    // Luồng W: phát beat theo thứ tự AW, độc lập với AR
    initial begin
        s_axi_wvalid = 0;
        s_axi_wlast  = 0;
        s_axi_wdata  = 0;
        s_axi_wstrb  = 0;
        forever begin
            @(posedge clk_axi);
            if (wq_data.size() > 0) begin
                @(negedge clk_axi);
                s_axi_wdata  = wq_data[0];
                s_axi_wstrb  = wq_strb[0];
                s_axi_wlast  = wq_last[0];
                s_axi_wvalid = 1;
                do @(posedge clk_axi); while (!s_axi_wready);
                begin
                    logic [63:0] d; logic [7:0] st; bit l;
                    d = wq_data.pop_front(); st = wq_strb.pop_front(); l = wq_last.pop_front();
                end
                @(negedge clk_axi);
                s_axi_wvalid = 0;
            end
        end
    end

    task automatic do_write(input int id, input int w0, input int nbeats, input bit full_strb);
        @(negedge clk_axi);
        s_axi_awid    = id;
        s_axi_awaddr  = word_addr(w0);
        s_axi_awlen   = nbeats - 1;
        s_axi_awsize  = 3'd3;
        s_axi_awburst = 2'b01;
        s_axi_awqos   = $urandom_range(0, 15);
        s_axi_awvalid = 1;
        do @(posedge clk_axi); while (!s_axi_awready);
        // Handshake AW: cập nhật mô hình tham chiếu và xếp dữ liệu W
        if (trace_en) $display("  [TRACE] cyc %0d AW id %0d words %0d..%0d", cyc, id, w0, w0 + nbeats - 1);
        for (int b = 0; b < nbeats; b++) begin
            logic [63:0] d;
            logic [7:0]  st;
            d  = {$urandom, $urandom};
            st = full_strb ? 8'hFF : 8'($urandom_range(1, 255));
            for (int by = 0; by < 8; by++)
                if (st[by]) ref_mem[w0 + b][by*8 +: 8] = d[by*8 +: 8];
            hist_push(w0 + b);
            if (b == 0) begin
                bq_w0.push_back(w0);
                bq_nb.push_back(nbeats);
                bq_ver.push_back(int'(cyc));
            end
            wq_data.push_back(d);
            wq_strb.push_back(st);
            wq_last.push_back(b == nbeats - 1);
        end
        aw_count++;
        @(negedge clk_axi);
        s_axi_awvalid = 0;
    endtask

    task automatic do_read(input int id, input int w0, input int nbeats);
        int slot;
        while (n_pend >= PEND - 1) @(posedge clk_axi);
        @(negedge clk_axi);
        s_axi_arid    = id;
        s_axi_araddr  = word_addr(w0);
        s_axi_arlen   = nbeats - 1;
        s_axi_arsize  = 3'd3;
        s_axi_arburst = 2'b01;
        s_axi_arqos   = $urandom_range(0, 15);
        s_axi_arvalid = 1;
        do @(posedge clk_axi); while (!s_axi_arready);
        slot = -1;
        for (int k = 0; k < PEND; k++) if (!pend_v[k] && slot < 0) slot = k;
        pend_v[slot]   = 1;
        pend_id[slot]  = id;
        pend_nb[slot]  = nbeats;
        pend_seq[slot] = seq_ctr++;
        pend_t0[slot]  = cyc;
        pend_w0[slot]  = w0;
        for (int b = 0; b < 8; b++) pend_exp[slot][b] = (b < nbeats) ? ref_mem[w0 + b] : '0;
        n_pend++;
        ar_count++;
        @(negedge clk_axi);
        s_axi_arvalid = 0;
    endtask

    // Ghi một word với WSTRB cho trước rồi chờ dữ liệu xuống DRAM
    task automatic write_word(input int w, input logic [63:0] d, input logic [7:0] st);
        int nw;
        nw = u_dram.n_wr;
        @(negedge clk_axi);
        s_axi_awid = 1; s_axi_awaddr = word_addr(w); s_axi_awlen = 0; s_axi_awsize = 3'd3; s_axi_awburst = 2'b01;
        s_axi_awqos = 0; s_axi_awvalid = 1;
        do @(posedge clk_axi); while (!s_axi_awready);
        for (int by = 0; by < 8; by++) if (st[by]) ref_mem[w][by*8 +: 8] = d[by*8 +: 8];
        hist_push(w);
        bq_w0.push_back(w); bq_nb.push_back(1); bq_ver.push_back(int'(cyc));
        wq_data.push_back(d); wq_strb.push_back(st); wq_last.push_back(1'b1);
        aw_count++;
        @(negedge clk_axi);
        s_axi_awvalid = 0;
        while (u_dram.n_wr == nw) @(posedge clk_axi);
        drain(2000);
    endtask

    // Đọc một word, chờ beat trả về; trả về khoá DRAM của lệnh RD đã phát
    task automatic read_word(input int w, output bit [63:0] key);
        int nb;
        nb = r_bursts;
        do_read(9, w, 1);
        while (r_bursts == nb) @(posedge clk_axi);
        key = last_rd_key;
    endtask

    // Ba bit dữ liệu 0, 4, 58 ở vị trí Hamming 3, 9, 66: tổng hội chứng {1, 3^9^66 = 72}, vị trí không tồn tại (>71).
    // Lỗi >=3 bit giả dạng lỗi đơn; tính ngược lại từ SECDED_DATA_SYN để hằng số không lệch với package.
    function automatic logic [63:0] triple_alias_mask();
        logic [7:0] s;
        s = SECDED_DATA_SYN[0*8 +: 8] ^ SECDED_DATA_SYN[4*8 +: 8] ^ SECDED_DATA_SYN[58*8 +: 8];
        return (s[7] && s[6:0] > 7'd71) ? 64'h0400_0000_0000_0011 : 64'h0;
    endfunction

    // Pha ECC: tiêm lỗi vào word đã lưu trong DRAM (scrambler bật), đọc lại qua AXI
    task automatic ecc_phase();
        bit [63:0]   k;
        bit          found;
        logic [63:0] m3;
        int          ce0, bad_ok, bad0;
        $display("[PHASE 2] ECC fault injection on stored words (scrambler ON)");
        fi_ecc_phase = 1'b1;
        bad0 = r_beats_bad;
        m3   = triple_alias_mask();

        // (a) lỗi 1 bit dữ liệu: đọc ra đúng giá trị, OKAY, bộ đếm lỗi đã sửa tăng
        read_word(3, k);
        ce0 = dut.o_ecc_single_err_cnt;
        u_dram.flip(k, 64'h0000_0100_0000_0000, 8'h00, found);
        read_word(3, k);
        tb_check(found && last_rdata === ref_mem[3] && last_rresp == 2'b00 && !last_rpoison &&
                 dut.o_ecc_single_err_cnt == ce0 + 1,
                 $sformatf("ECC: single data-bit flip in DRAM is corrected (data %s, RRESP %0d, CE count +%0d)",
                           last_rdata === ref_mem[3] ? "exact" : "WRONG", last_rresp, dut.o_ecc_single_err_cnt - ce0));

        // (b) lỗi 1 bit kiểm tra: dữ liệu không đổi
        read_word(12, k);
        u_dram.flip(k, '0, 8'h10, found);
        read_word(12, k);
        tb_check(found && last_rdata === ref_mem[12] && last_rresp == 2'b00,
                 "ECC: single check-bit flip leaves data intact");

        // (c) lỗi 2 bit: không sửa được, beat bị poison (RRESP=SLVERR, RPOISON)
        read_word(21, k);
        u_dram.flip(k, 64'h0000_0000_0000_0011, 8'h00, found);
        read_word(21, k);
        tb_check(found && last_rresp == 2'b10 && last_rpoison,
                 $sformatf("ECC: double-bit flip is detected and poisoned (RRESP %0d, RPOISON %0d)", last_rresp, last_rpoison));

        // (d) lỗi 3 bit giả dạng lỗi đơn ở vị trí không tồn tại: phải poison, không được sửa nhầm
        read_word(30, k);
        u_dram.flip(k, m3, 8'h00, found);
        read_word(30, k);
        tb_check(m3 != 0 && found && last_rresp == 2'b10 && last_rpoison,
                 $sformatf("ECC: 3-bit flip aliasing to a non-existent position is poisoned, not miscorrected (mask %h)", m3));

        // (e) RMW trên word có lỗi 1 bit: byte cũ được sửa trước khi trộn, word sau đó sạch và đúng
        read_word(40, k);
        u_dram.flip(k, 64'h8000_0000_0000_0000, 8'h00, found);
        write_word(40, 64'h0123_4567_89AB_CDEF, 8'h0F);
        read_word(40, k);
        tb_check(found && last_rdata === ref_mem[40] && last_rresp == 2'b00,
                 $sformatf("ECC+RMW: partial write over a corrected word merges corrected old bytes (got %h exp %h)", last_rdata, ref_mem[40]));

        // (f) RMW trên word hỏng 2 bit: lỗi không được "tẩy" thành dữ liệu sạch bởi ECC mới
        read_word(50, k);
        u_dram.flip(k, 64'h0000_0000_0300_0000, 8'h00, found);
        write_word(50, 64'hFFFF_0000_FFFF_0000, 8'hF0);
        read_word(50, k);
        tb_check(found && last_rresp == 2'b10 && last_rpoison,
                 $sformatf("ECC+RMW: partial write over an uncorrectable word keeps it poisoned (RRESP %0d)", last_rresp));
        // Chỉ các beat bị poison (c, d, f) được phép lệch mô hình tham chiếu
        bad_ok = r_beats_bad - bad0;
        tb_check(bad_ok <= 3, $sformatf("ECC phase: only poisoned beats differ from the reference (%0d)", bad_ok));
        @(negedge clk_axi);
        cfg_fault_clr = 1'b1;
        @(posedge clk_axi);
        @(negedge clk_axi);
        cfg_fault_clr = 1'b0;
        repeat (2) @(posedge clk_axi);
        fi_ecc_phase = 1'b0;
    endtask

    //-------------------------------------------------------------------------
    // Pha 3: giao thức AXI4 đầy đủ (R27). Burst INCR tới 256 beat bắt đầu lệch dòng, WRAP 2/4/8/16, FIXED, truyền
    // hẹp 1/2/4 byte. Mỗi lệnh chạy riêng (chờ B / RLAST) và được so từng beat trên đúng làn byte theo A3.4.1.
    //-------------------------------------------------------------------------
    localparam longint P3_BASE  = 64'h0020_0000;
    localparam int     P3_WORDS = 1024;               // 2 trang 4 KB
    logic [63:0] ref3  [P3_WORDS];  // chỉ số: (địa chỉ - P3_BASE) >> 3
    logic [7:0]  ref3m [P3_WORDS];  // byte đã từng được ghi
    int p3_beats_ok = 0, p3_beats_bad = 0, p3_last_err = 0, p3_resp_err = 0, p3_timeout = 0, p3_bursts = 0;

    function automatic longint p3_baddr(input longint start, input int sz, input int ln, input int bt, input int n);
        longint nb, al, wb, a;
        nb = longint'(1) << sz;
        if (bt == 0 || n == 0) return start;
        al = (start / nb) * nb;
        a  = al + n * nb;
        if (bt == 2) begin
            wb = (start / (nb * (ln + 1))) * (nb * (ln + 1));
            if (a >= wb + nb * (ln + 1)) a = a - nb * (ln + 1);
        end
        return a;
    endfunction

    // Làn byte hoạt động của beat n (A3.4.1): từ địa chỉ beat tới hết vùng căn theo AxSIZE
    function automatic logic [7:0] p3_lanes(input longint start, input int sz, input int ln, input int bt, input int n);
        longint nb, a, al, wb;
        logic [7:0] m;
        nb = longint'(1) << sz;
        a  = p3_baddr(start, sz, ln, bt, n);
        al = (a / nb) * nb;
        wb = (a / 8) * 8;
        m  = '0;
        for (longint by = a - wb; by <= al + nb - 1 - wb; by++) m[by] = 1'b1;
        return m;
    endfunction

    task automatic p3_write(input longint start, input int sz, input int ln, input int bt);
        int b0, c;
        b0 = b3_count;
        @(negedge clk_axi);
        s_axi_awid = 3; s_axi_awaddr = 32'(start); s_axi_awlen = 8'(ln); s_axi_awsize = 3'(sz); s_axi_awburst = 2'(bt);
        s_axi_awqos = 0; s_axi_awvalid = 1;
        do @(posedge clk_axi); while (!s_axi_awready);
        for (int n = 0; n <= ln; n++) begin
            longint w;
            logic [63:0] d;
            logic [7:0]  st;
            w  = (p3_baddr(start, sz, ln, bt, n) - P3_BASE) >> 3;
            d  = {$urandom, $urandom};
            st = p3_lanes(start, sz, ln, bt, n) & (($urandom_range(0, 7) == 0) ? 8'($urandom) : 8'hFF);
            for (int by = 0; by < 8; by++)
                if (st[by]) begin ref3[w][by*8 +: 8] = d[by*8 +: 8]; ref3m[w][by] = 1'b1; end
            wq_data.push_back(d); wq_strb.push_back(st); wq_last.push_back(n == ln);
        end
        @(negedge clk_axi);
        s_axi_awvalid = 0;
        c = 0;
        while (b3_count == b0 && c < 40000) begin @(posedge clk_axi); c++; end
        if (b3_count == b0) p3_timeout++;
    endtask

    task automatic p3_read(input longint start, input int sz, input int ln, input int bt);
        int c;
        r3_data.delete(); r3_last.delete(); r3_resp.delete();
        @(negedge clk_axi);
        s_axi_arid = 11; s_axi_araddr = 32'(start); s_axi_arlen = 8'(ln); s_axi_arsize = 3'(sz); s_axi_arburst = 2'(bt);
        s_axi_arqos = 0; s_axi_arvalid = 1;
        do @(posedge clk_axi); while (!s_axi_arready);
        @(negedge clk_axi);
        s_axi_arvalid = 0;
        c = 0;
        while (r3_data.size() < ln + 1 && c < 40000) begin @(posedge clk_axi); c++; end
        repeat (4) @(posedge clk_axi);
        if (r3_data.size() != ln + 1) begin
            p3_timeout++;
            if (p3_timeout <= 4) $display("  [DIAG] P3 read %h len %0d size %0d burst %0d: %0d/%0d beats", start, ln, sz, bt, r3_data.size(), ln + 1);
        end else begin
            p3_bursts++;
            for (int n = 0; n <= ln; n++) begin
                longint      w;
                logic [7:0]  m;
                logic [63:0] got, exp;
                bit          ok, lst;
                logic [1:0]  rsp;
                w   = (p3_baddr(start, sz, ln, bt, n) - P3_BASE) >> 3;
                m   = p3_lanes(start, sz, ln, bt, n) & ref3m[w];
                got = r3_data.pop_front();
                lst = r3_last.pop_front();
                rsp = r3_resp.pop_front();
                exp = ref3[w];
                ok  = 1;
                for (int by = 0; by < 8; by++) if (m[by] && got[by*8 +: 8] !== exp[by*8 +: 8]) ok = 0;
                if (ok) p3_beats_ok++;
                else begin
                    p3_beats_bad++;
                    if (p3_beats_bad <= 6)
                        $display("  [DIAG] P3 read %h len %0d size %0d burst %0d beat %0d word %0d: got %h exp %h lanes %b",
                                 start, ln, sz, bt, n, w, got, exp, m);
                end
                if (lst !== (n == ln)) p3_last_err++;
                if (rsp != 2'b00) p3_resp_err++;
            end
        end
    endtask

    task automatic axi_full_phase();
        longint BASE;
        BASE = P3_BASE;
        for (int i = 0; i < P3_WORDS; i++) begin ref3[i] = '0; ref3m[i] = '0; end
        $display("[PHASE 3] AXI4 full protocol: long INCR, line-crossing, WRAP, FIXED, narrow");
        drain(20000);
        p3 = 1;
        // Khởi tạo 2 trang 4 KB bằng burst INCR 256 beat (vượt 32 dòng mỗi burst)
        for (int pg = 0; pg < 2; pg++)
            for (int h = 0; h < 2; h++) p3_write(BASE + pg * 4096 + h * 2048, 3, 255, 1);
        p3_read(BASE, 3, 255, 1);
        for (int t = 0; t < 160; t++) begin
            int sz, ln, bt, maxb;
            longint st, pg;
            bt = $urandom_range(0, 2);
            sz = ($urandom_range(0, 2) == 0) ? $urandom_range(0, 2) : 3;
            pg = BASE + $urandom_range(0, 1) * 4096;
            if (bt == 2) begin
                ln = (1 << $urandom_range(1, 4)) - 1;
                st = pg + ($urandom_range(0, 4095) & ~((1 << sz) - 1));
            end else begin
                st = pg + $urandom_range(0, 4095);
                if (bt == 1) begin
                    // INCR không được vượt biên 4 KB
                    maxb = (4096 - (st - pg)) >> sz;
                    if (maxb < 1) begin st = pg; maxb = 4096 >> sz; end
                    ln = $urandom_range(0, (maxb > 64 ? 64 : maxb) - 1);
                    if ($urandom_range(0, 7) == 0) ln = (maxb > 256 ? 256 : maxb) - 1;
                end else begin
                    st = st & ~((1 << sz) - 1);
                    ln = $urandom_range(0, 15);
                end
            end
            if ($urandom_range(0, 1)) p3_write(st, sz, ln, bt);
            p3_read(st, sz, ln, bt);
        end
        p3 = 0;
        $display("  [DIAG] phase 3: %0d read bursts, %0d beats OK, %0d bad, RLAST errors %0d, RRESP errors %0d, timeouts %0d, B %0d",
                 p3_bursts, p3_beats_ok, p3_beats_bad, p3_last_err, p3_resp_err, p3_timeout, b3_count);
        tb_check(p3_timeout == 0 && p3_beats_bad == 0 && p3_beats_ok > 2000,
                 $sformatf("AXI4 full bursts: every beat matches the reference on its byte lanes (%0d OK, %0d bad, %0d timeouts)",
                           p3_beats_ok, p3_beats_bad, p3_timeout));
        tb_check(p3_last_err == 0 && p3_resp_err == 0 && b3_err == 0,
                 $sformatf("AXI4 full bursts: RLAST only on the last beat, OKAY responses (%0d RLAST, %0d RRESP, %0d BRESP errors)",
                           p3_last_err, p3_resp_err, b3_err));
    endtask

    // Burst ngẫu nhiên gọn trong một dòng 64B (mô hình tham chiếu theo dòng); burst vượt dòng/dài được kiểm ở pha 3
    task automatic random_op(input bit allow_partial);
        int w0, nb, id;
        w0 = $urandom_range(0, WORDS - 1);
        nb = $urandom_range(1, 8 - (w0 % 8));
        id = $urandom_range(0, 7);
        if ($urandom_range(0, 1)) do_write(id, w0, nb, !allow_partial || $urandom_range(0, 1));
        else                      do_read(id + 8, w0, nb);
    endtask

    task automatic drain(input int max_cycles);
        int c;
        c = 0;
        // B là phản hồi posted: chờ cả lệnh ghi xuống DRAM, nếu không reset giữa hai pha sẽ huỷ lệnh ghi còn trong hàng đợi
        while ((n_pend > 0 || wq_data.size() > 0 || b_count < aw_count || u_dram.n_wr < aw_count) && c < max_cycles) begin
            @(posedge clk_axi);
            c++;
        end
    endtask

    initial begin
        s_axi_awvalid = 0; s_axi_arvalid = 0; s_axi_bready = 1; s_axi_rready = 1;
        s_axi_awid = 0; s_axi_awaddr = 0; s_axi_awlen = 0; s_axi_awsize = 3; s_axi_awburst = 1; s_axi_awqos = 0;
        s_axi_arid = 0; s_axi_araddr = 0; s_axi_arlen = 0; s_axi_arsize = 3; s_axi_arburst = 1; s_axi_arqos = 0;
        // 16 dòng: 4 hàng x 2 bank x 2 cột, tất cả cùng BG nên có cả row hit lẫn row conflict
        for (int l = 0; l < LINES; l++)
            line_base[l] = ((l % 4) << 18) | (((l / 4) % 2) << 16) | ((l / 8) << 9);
        for (int w = 0; w < WORDS; w++) begin
            ref_mem[w] = '0;
            hist_n[w]  = 0;
        end

        for (int phase = 0; phase < 2; phase++) begin
            int ok0, bad0, n0;
            cfg_scramble_en = phase[0];
            aresetn_axi = 0; aresetn_ddr = 0;
            repeat (10) @(posedge clk_axi);
            aresetn_axi = 1; aresetn_ddr = 1;
            repeat (20) @(posedge clk_axi);
            ok0 = r_beats_ok; bad0 = r_beats_bad; n0 = r_bursts;
            $display("[PHASE %0d] scrambler %s: init + %0d random ops", phase, phase ? "ON" : "OFF", N_OPS);
            // Khởi tạo toàn bộ vùng bằng ghi đủ byte để mọi lần đọc sau đều có giá trị tham chiếu xác định
            for (int l = 0; l < LINES; l++) do_write(l % 8, l * 8, 8, 1);
            drain(20000);
            for (int n = 0; n < N_OPS; n++) begin
                random_op(1);
                if ($urandom_range(0, 3) == 0) repeat ($urandom_range(1, 6)) @(posedge clk_axi);
            end
            drain(200000);
            $display("  [DIAG] phase %0d: %0d read bursts, %0d beats OK, %0d beats BAD", phase,
                     r_bursts - n0, r_beats_ok - ok0, r_beats_bad - bad0);
            tb_check(n_pend == 0, $sformatf("Phase %0d: every read burst completed (%0d outstanding)", phase, n_pend));
            tb_check(r_beats_bad == bad0 && r_beats_ok > ok0,
                     $sformatf("Phase %0d (scrambler %s): every read beat equals the reference memory (%0d OK, %0d bad)",
                               phase, phase ? "ON" : "OFF", r_beats_ok - ok0, r_beats_bad - bad0));
            if (phase == 1) begin
                // Với scrambler bật, word lưu trong DRAM phải khác bản rõ (kiểm trên toàn vùng)
                tb_check(scramble_differs(), "Phase 1: DRAM holds scrambled words that differ from plaintext");
            end
        end

        // B là phản hồi posted (sau khi dữ liệu vào kho ghi): chờ mọi lệnh ghi thật sự xuống DRAM
        begin
            int c;
            c = 0;
            while (u_dram.n_wr < aw_count && c < 20000) begin @(posedge clk_axi); c++; end
        end
        tb_check(u_dram.n_wr == aw_count, $sformatf("Every posted write reached DRAM (%0d WR for %0d AW)", u_dram.n_wr, aw_count));
        tb_check(strict_bad == 0, $sformatf("RAW from AW handshake (design claim, stronger than AXI): %0d beats missed an earlier AW", strict_bad));
        tb_check(r_id_err == 0 && r_last_err == 0 && r_resp_err == 0,
                 $sformatf("R channel protocol: unexpected RID %0d, wrong RLAST %0d, non-OKAY RRESP %0d", r_id_err, r_last_err, r_resp_err));
        tb_check(b_count == aw_count && b_err == 0, $sformatf("B channel: %0d/%0d write responses, %0d non-OKAY", b_count, aw_count, b_err));
        // ECC phủ cả word 64 bit: ghi thiếu byte phải đi qua RMW, DRAM không bao giờ nhận beat có data mask
        $display("  [ECC] RMW read beats %0d, partial-mask beats seen by DRAM %0d", n_rmw_beats, u_dram.n_partial_wr);
        tb_check(n_rmw_beats > 0 && u_dram.n_partial_wr == 0,
                 $sformatf("Partial writes go through read-modify-write (%0d RMW beats, %0d masked DRAM beats)", n_rmw_beats, u_dram.n_partial_wr));
        ecc_phase();
        axi_full_phase();
        $display("  [PERF] reads %0d, writes %0d, avg read latency %0d cycles, max %0d cycles",
                 ar_count, aw_count, lat_n ? int'(lat_sum / lat_n) : 0, int'(lat_max));
        u_dram.report("e2e");
        u_jchk.report("e2e");
        repeat (2) @(posedge clk_axi);
        u_achk.final_check();
        u_echk.final_check();
        u_achk.report("e2e");
        u_echk.report("e2e");
        u_pchk.report("e2e");
        tb_check(u_dram.errors() == 0, $sformatf("DRAM model saw no DQ overlap / beat-count / orphan-data error (%0d)", u_dram.errors()));
        tb_check(u_jchk.timing_violations() == 0 && u_jchk.viol_ref_open == 0,
                 $sformatf("JEDEC timing clean under random traffic (%0d timing, %0d REF-open)", u_jchk.timing_violations(), u_jchk.viol_ref_open));
        tb_check(u_achk.errors() == 0, $sformatf("qs_axi_txn_chk zero errors (%0d)", u_achk.errors()));
        tb_check(u_echk.errors() == 0, $sformatf("qs_engine_port_chk zero errors (%0d)", u_echk.errors()));
        tb_check(u_pchk.errors() == 0, $sformatf("qs_top_probe_chk zero errors (%0d)", u_pchk.errors()));
        tb_report();
        $finish;
    end

    // Đếm số word mà nội dung DRAM bằng đúng bản rõ trong mô hình tham chiếu (chỉ có ý nghĩa khi scrambler bật)
    function automatic bit scramble_differs();
        int equal, total;
        equal = 0;
        total = 0;
        for (int i = 0; i < (1 << 16); i++) begin
            if (u_dram.mem_used[i]) begin
                bit hit;
                hit = 0;
                total++;
                for (int w = 0; w < WORDS; w++)
                    if (u_dram.mem_dat[i] == ref_mem[w]) hit = 1;
                if (hit) equal++;
            end
        end
        $display("  [DIAG] scrambler: %0d of %0d stored DRAM words equal some plaintext word", equal, total);
        return total > 0 && equal * 10 < total;
    endfunction

    initial begin
        #20_000_000;
        $display("[FAIL] watchdog timeout");
        tb_report();
        $finish;
    end
endmodule
