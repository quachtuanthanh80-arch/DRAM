// File: tb_standard_benchmarks.sv
// Chức năng: Kiểm tra 8 mẫu lưu lượng AXI tổng hợp (mô phỏng dáng truy cập của các workload đã công bố): không throttle nhầm và mọi yêu cầu hoàn tất.

`timescale 1ns / 1ps

module tb_standard_benchmarks;

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

    logic clk_axi = 0;
    always #2.0 clk_axi = ~clk_axi; // 250 MHz

    logic clk_ddr = 0;
    always #1.25 clk_ddr = ~clk_ddr; // 400 MHz

    logic aresetn_axi;
    logic aresetn_ddr;

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

    logic                      cfg_is_ddr5;
    logic                      cfg_dual_hash_en;
    logic [15:0]               cfg_rh_threshold;
    logic [15:0]               cfg_window_size;
    logic [15:0]               o_throttled_events;
    logic [15:0]               o_ecc_single_err_cnt;
    logic [15:0]               o_ecc_double_err_cnt;

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
        .o_ecc_double_err_cnt(o_ecc_double_err_cnt)
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
        .s_axi_rpoison (dut.s_axi_rpoison)
    );

    qs_engine_port_chk #(
        .TAG_W   (4),
        .T_RDV   (9)
    ) u_echk (
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

    qs_top_probe_chk #(
        .ROB_DEPTH (ROB_DEPTH)
    ) u_pchk (
        .clk    (clk_axi),
        .rst_n  (dut.rst_n_axi),
        .en_v2  (1'b1),
        .fi_any (1'b0)
    );

    int ddr_cycles = 0;
    int dfi_act_cnt = 0;
    int dfi_cas_cnt = 0;

    always @(posedge clk_ddr) begin
        if (aresetn_ddr) begin
            ddr_cycles <= ddr_cycles + 1;
            if (dfi_cmd == 3'd1) dfi_act_cnt <= dfi_act_cnt + 1;
            if (dfi_cmd == 3'd3 || dfi_cmd == 3'd4) dfi_cas_cnt <= dfi_cas_cnt + 1;
        end
    end

    task automatic axi_write_tx(
        input logic [AXI_ID_WIDTH-1:0]   id,
        input logic [AXI_ADDR_WIDTH-1:0] addr,
        input logic [AXI_DATA_WIDTH-1:0] data
    );
        @(negedge clk_axi);
        s_axi_awid    <= id;
        s_axi_awaddr  <= addr;
        s_axi_awlen   <= 8'd0;
        s_axi_awsize  <= 3'b011;
        s_axi_awburst <= 2'b01;
        s_axi_awqos   <= 4'd3;
        s_axi_awvalid <= 1'b1;
        s_axi_wdata   <= data;
        s_axi_wstrb   <= 8'hFF;
        s_axi_wlast   <= 1'b1;
        s_axi_wvalid  <= 1'b1;
        @(posedge clk_axi);
        while (!(s_axi_awready && s_axi_wready)) @(posedge clk_axi);
        aw_cnt++;
        @(negedge clk_axi);
        s_axi_awvalid <= 1'b0;
        s_axi_wvalid  <= 1'b0;
        s_axi_wlast   <= 1'b0;
    endtask

    task automatic axi_read_tx(
        input logic [AXI_ID_WIDTH-1:0]   id,
        input logic [AXI_ADDR_WIDTH-1:0] addr
    );
        @(negedge clk_axi);
        s_axi_arid    <= id;
        s_axi_araddr  <= addr;
        s_axi_arlen   <= 8'd0;
        s_axi_arsize  <= 3'b011;
        s_axi_arburst <= 2'b01;
        s_axi_arqos   <= 4'd3;
        s_axi_arvalid <= 1'b1;
        @(posedge clk_axi);
        while (!s_axi_arready) @(posedge clk_axi);
        ar_cnt++;
        @(negedge clk_axi);
        s_axi_arvalid <= 1'b0;
    endtask

    `include "tb_check.svh"

    // Monitor hoàn tất giao dịch: mỗi AR phải có đúng một burst R, mỗi AW phải có một B.
    int ar_cnt = 0, aw_cnt = 0, r_bursts = 0, b_cnt = 0;
    logic [AXI_DATA_WIDTH-1:0] last_rdata;
    int thr_s, ar_s, aw_s, r_s, b_s;

    always @(posedge clk_axi) begin
        if (aresetn_axi) begin
            if (s_axi_rvalid && s_axi_rready) begin
                last_rdata <= s_axi_rdata;
                if (s_axi_rlast) r_bursts <= r_bursts + 1;
            end
            if (s_axi_bvalid && s_axi_bready) b_cnt <= b_cnt + 1;
        end
    end

    task automatic snap();
        thr_s = o_throttled_events;
        ar_s  = ar_cnt;
        aw_s  = aw_cnt;
        r_s   = r_bursts;
        b_s   = b_cnt;
    endtask

    // Mẫu lưu lượng lành tính: không được throttle nhầm và mọi yêu cầu phải hoàn tất.
    task automatic check_pattern(input string name);
        for (int c = 0; c < 1000 && ((r_bursts - r_s) < (ar_cnt - ar_s) || (b_cnt - b_s) < (aw_cnt - aw_s)); c++)
            @(posedge clk_axi);
        tb_check(o_throttled_events == thr_s,
                 $sformatf("%s: no false-positive throttling on benign traffic (+%0d)", name, o_throttled_events - thr_s));
        tb_check(r_bursts - r_s == ar_cnt - ar_s && b_cnt - b_s == aw_cnt - aw_s,
                 $sformatf("%s: every request completed (R %0d/%0d, B %0d/%0d)", name,
                           r_bursts - r_s, ar_cnt - ar_s, b_cnt - b_s, aw_cnt - aw_s));
    endtask

    initial begin
        aresetn_axi      = 1'b0;
        aresetn_ddr      = 1'b0;
        s_axi_awid       = '0;
        s_axi_awaddr     = '0;
        s_axi_awlen      = '0;
        s_axi_awsize     = 3'b011;
        s_axi_awburst    = 2'b01;
        s_axi_awqos      = '0;
        s_axi_awvalid    = 1'b0;
        s_axi_wdata      = '0;
        s_axi_wstrb      = '0;
        s_axi_wlast      = 1'b0;
        s_axi_wvalid     = 1'b0;
        s_axi_bready     = 1'b1;
        s_axi_arid       = '0;
        s_axi_araddr     = '0;
        s_axi_arlen      = '0;
        s_axi_arsize     = 3'b011;
        s_axi_arburst    = 2'b01;
        s_axi_arqos      = '0;
        s_axi_arvalid    = 1'b0;
        s_axi_rready     = 1'b1;
        cfg_is_ddr5      = 1'b1;
        cfg_dual_hash_en = 1'b1;
        cfg_rh_threshold = 16'd64;
        cfg_window_size  = 16'd4096;

        repeat (8) @(posedge clk_axi);
        aresetn_axi = 1'b1;
        aresetn_ddr = 1'b1;
        repeat (4) @(posedge clk_axi);

        $display("================================================================");
        $display("[TB_STD_BENCH] 8 synthetic AXI traffic patterns modelled after published workloads (not the workloads themselves)");
        $display("================================================================");

        // 1. McCalpin STREAM Triad (University of Virginia / HPC Standard)
        snap();
        for (int i = 0; i < 8; i++) begin
            axi_read_tx(4'd1, 32'h0010_0000 + (i * 64));
            axi_read_tx(4'd2, 32'h0020_0000 + (i * 64));
            axi_write_tx(4'd3, 32'h0030_0000 + (i * 64), 64'hA5A5_0000_0000_0000 + i);
        end
        repeat (16) @(posedge clk_axi);
        check_pattern("Pattern 1 (McCalpin STREAM Triad traffic pattern)");

        // 2. SPEC CPU2017 505.mcf_r (SPEC Consortium - Pointer-Chasing High-MPKI)
        snap();
        for (int i = 0; i < 10; i++) begin
            axi_read_tx(i[3:0], 32'h0040_0000 ^ ((i * 32'h0001_4800) & 32'h00FF_FFC0));
            repeat (2) @(posedge clk_axi);
        end
        repeat (16) @(posedge clk_axi);
        check_pattern("Pattern 2 (SPEC CPU2017 505.mcf_r traffic pattern)");

        // 3. UC Berkeley GAPBS bfs / pr (Graph Analytics Performance Benchmark Suite)
        snap();
        for (int v = 0; v < 10; v++) begin
            axi_read_tx(v[3:0], 32'h0080_0000 + ((v * 7) << 13) + ((v * 3) << 6));
        end
        repeat (16) @(posedge clk_axi);
        check_pattern("Pattern 3 (UC Berkeley GAPBS bfs traffic pattern)");

        // 4. Yahoo! YCSB Workload-A (Cloud Key-Value Store 50% Read / 50% Update)
        snap();
        for (int k = 0; k < 6; k++) begin
            axi_read_tx(4'd8, 32'h00C0_0000 + (k << 12));
            axi_write_tx(4'd9, 32'h00C0_0000 + (k << 12), 64'hCAFE_0000_0000_0000 | k);
        end
        repeat (16) @(posedge clk_axi);
        check_pattern("Pattern 4 (Yahoo! YCSB Workload-A traffic pattern)");

        // 5. TPC-H / TPC-C In-Memory Database Scan & Commit (TPC Council)
        snap();
        for (int q = 0; q < 6; q++) begin
            axi_read_tx(4'd4, 32'h0100_0000 + (q * 128));
            axi_read_tx(4'd5, 32'h0100_0040 + (q * 128));
        end
        axi_write_tx(4'd6, 32'h0108_0000, 64'hDB00_C011_1170_0001);
        repeat (16) @(posedge clk_axi);
        check_pattern("Pattern 5 (TPC-H / TPC-C In-Memory DB traffic pattern)");

        // 6. MLCommons MLPerf DLRM Embedding Lookup & LLM KV-Cache Append
        snap();
        for (int e = 0; e < 6; e++) begin
            axi_read_tx(e[3:0], 32'h0140_0000 + ((e * 11) << 11)); // Sparse Embedding Gather
            axi_write_tx(4'd10, 32'h0180_0000 + (e * 64), 64'h4B56_4341_4348_0000 | e); // KV-Cache Append
        end
        repeat (16) @(posedge clk_axi);
        check_pattern("Pattern 6 (MLCommons MLPerf DLRM/KV-Cache traffic pattern)");

        // 7. Princeton PARSEC 3.0 canneal / streamcluster (Shared-Memory RMW Hazard Check)
        snap();
        for (int p = 0; p < 5; p++) begin
            axi_write_tx(4'd11, 32'h01C0_0000 + (p * 256), 64'h5041_5253_4543_0000 | p);
            axi_read_tx(4'd11, 32'h01C0_0000 + (p * 256)); // Immediate Read-After-Write (RAW)
        end
        repeat (16) @(posedge clk_axi);
        check_pattern("Pattern 7 (Princeton PARSEC 3.0 canneal traffic pattern)");

        // 8. Delft Univ. Van de Goor March C- Post-Silicon Memory BIST Standard
        snap();
        for (int m = 0; m < 4; m++) begin
            axi_write_tx(4'd12, 32'h0200_0000 + (m * 64), 64'h0000_0000_0000_0000); // w0
            axi_read_tx(4'd12,  32'h0200_0000 + (m * 64));                          // r0
            axi_write_tx(4'd12, 32'h0200_0000 + (m * 64), 64'hFFFF_FFFF_FFFF_FFFF); // w1
            axi_read_tx(4'd12,  32'h0200_0000 + (m * 64));                          // r1
        end
        repeat (20) @(posedge clk_axi);
        check_pattern("Pattern 8 (Delft Univ. March C- Memory BIST traffic pattern)");
        tb_check(last_rdata === 64'hFFFF_FFFF_FFFF_FFFF,
                 $sformatf("Pattern 8 (March C-): final r1 returns written 1s, got %h", last_rdata));

        u_jchk.report("benchmarks");
        repeat (2) @(posedge clk_axi);
        u_achk.final_check();
        u_echk.final_check();
        u_achk.report("benchmarks");
        u_echk.report("benchmarks");
        u_pchk.report("benchmarks");
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

endmodule
