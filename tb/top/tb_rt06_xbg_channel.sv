// File:      tb_rt06_xbg_channel.sv
// Chức năng: Testbench cấp top cho T-RT06: đo kênh ngầm xuyên Bank Group qua PROQ (64-bit LeakyHammer), độ trễ đơn sự kiện (A-S1) và kênh dư M-02 (Q16).
`timescale 1ns / 1ps
`include "qs_hier.svh"

module tb_rt06_xbg_channel;
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
    localparam int TCK_PS         = 4000;
    localparam int RL_CYC         = 8;
    localparam int WL_CYC         = 9;

    logic clk_axi = 0;
    always #2.0 clk_axi = ~clk_axi;
    wire clk_ddr = clk_axi;
    logic aresetn_axi, aresetn_ddr;

    logic [AXI_ID_WIDTH-1:0]   s_axi_awid, s_axi_bid, s_axi_arid, s_axi_rid;
    logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr, s_axi_araddr;
    logic [AXI_LEN_WIDTH-1:0]  s_axi_awlen, s_axi_arlen;
    logic [2:0]                s_axi_awsize, s_axi_arsize;
    logic [1:0]                s_axi_awburst, s_axi_arburst;
    logic [AXI_QOS_WIDTH-1:0]  s_axi_awqos, s_axi_arqos;
    logic                      s_axi_awvalid, s_axi_awready, s_axi_arvalid, s_axi_arready;
    logic [AXI_DATA_WIDTH-1:0] s_axi_wdata, s_axi_rdata;
    logic [AXI_STRB_WIDTH-1:0] s_axi_wstrb;
    logic                      s_axi_wlast, s_axi_wvalid, s_axi_wready;
    logic [1:0]                s_axi_bresp, s_axi_rresp;
    logic                      s_axi_bvalid, s_axi_bready;
    logic                      s_axi_rlast, s_axi_rvalid, s_axi_rready;

    logic [2:0]                dfi_cmd;
    logic [BG_WIDTH-1:0]       dfi_bg;
    logic [BANK_WIDTH-1:0]     dfi_bank;
    logic [ROW_WIDTH-1:0]      dfi_row;
    logic [COL_WIDTH-1:0]      dfi_col;
    logic [7:0]                dfi_len;
    logic                      dfi_wrdata_en;
    logic [AXI_DATA_WIDTH-1:0] dfi_wrdata, dfi_rddata;
    logic [7:0]                dfi_wrdata_mask, dfi_wrdata_ecc, dfi_rddata_ecc;
    logic                      dfi_rddata_valid;

    logic                      cfg_is_ddr5, cfg_dual_hash_en;
    logic [15:0]               cfg_rh_threshold, cfg_window_size;
    logic [15:0]               o_throttled_events, o_ecc_single_err_cnt, o_ecc_double_err_cnt;

    int cyc;
    // Biến tĩnh cho lệnh force (Icarus không cho force tham chiếu biến automatic)
    logic [ROW_WIDTH-1:0] fi_sdc_row;
    always @(posedge clk_axi) if (!aresetn_axi) cyc <= 0; else cyc <= cyc + 1;

    axi_ddr5_mc_top #(
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_LEN_WIDTH (AXI_LEN_WIDTH),
        .AXI_QOS_WIDTH (AXI_QOS_WIDTH),
        .BG_COUNT      (BG_COUNT),
        .BANK_COUNT    (BANK_COUNT),
        .ROW_WIDTH     (ROW_WIDTH),
        .COL_WIDTH     (COL_WIDTH),
        .ROB_DEPTH     (ROB_DEPTH),
        .DFI_RDLAT     (RL_CYC)
`ifndef QS_BASELINE_V1
        ,
        .TCK_PS        (TCK_PS)
`endif
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
        .dfi_wrdata_mask     (dfi_wrdata_mask),
        .dfi_wrdata_ecc      (dfi_wrdata_ecc),
        .dfi_rddata_valid    (dfi_rddata_valid),
        .dfi_rddata          (dfi_rddata),
        .dfi_rddata_ecc      (dfi_rddata_ecc),
        .cfg_is_ddr5         (cfg_is_ddr5),
        .cfg_dual_hash_en    (cfg_dual_hash_en),
        .cfg_rh_threshold    (cfg_rh_threshold),
        .cfg_window_size     (cfg_window_size),
        .o_throttled_events  (o_throttled_events),
        .o_ecc_single_err_cnt(o_ecc_single_err_cnt),
        .o_ecc_double_err_cnt(o_ecc_double_err_cnt)
    );

    dram_model #(.COL_W(COL_WIDTH), .RL(RL_CYC), .WL(WL_CYC)) u_dram (
        .clk         (clk_axi),
        .rst_n       (aresetn_axi),
        .cmd         (dfi_cmd),
        .bg          (dfi_bg),
        .bank        (dfi_bank),
        .row         (dfi_row),
        .col         (dfi_col),
        .len         (dfi_len),
        .wrdata_en   (dfi_wrdata_en),
        .wrdata      (dfi_wrdata),
        .wrdata_mask (dfi_wrdata_mask),
        .wrdata_ecc  (dfi_wrdata_ecc),
        .rddata_valid(dfi_rddata_valid),
        .rddata      (dfi_rddata),
        .rddata_ecc  (dfi_rddata_ecc)
    );

`ifndef QS_BASELINE_V1
    qs_top_probe_chk #(.ROB_DEPTH(ROB_DEPTH)) u_pchk (
        .clk    (clk_axi),
        .rst_n  (aresetn_axi),
        .en_v2  (1'b1),
        .fi_any (1'b0)
    );
`endif

    function automatic [AXI_ADDR_WIDTH-1:0] mk_addr(
        input int row, input int bg, input int bank, input int col
    );
        logic [31:0] a;
        a        = 32'd0;
        a[31:15] = row[16:0];
        a[14:11] = col[3:0];
        a[10:9]  = bank[1:0] ^ a[19:18];
        a[8:6]   = bg[2:0]   ^ a[17:15];
        return a;
    endfunction

    function automatic int median3(input int a, input int b, input int c);
        if ((a <= b && b <= c) || (c <= b && b <= a)) return b;
        if ((b <= a && a <= c) || (c <= a && a <= b)) return a;
        return c;
    endfunction

    // Đo độ trễ AR -> R của một lệnh đọc ở BG b = 1, bank 1, hàng mở sẵn 17'h100;
    // nếu trig_alert_bg0 = 1 thì bên gửi tạo đồng thời 1 cảnh báo SDC ở BG a = 0 đúng chu kỳ lệnh BG 1 đi vào hàng đợi QoS!
    task automatic measure_bg1_probe(
        input bit trig_alert_bg0,
        input int col_idx,
        output int lat_out
    );
        int t_start;
        @(negedge clk_axi);
        s_axi_arid    = 4'd2;
        s_axi_araddr  = mk_addr(17'h100, 1, 1, col_idx & 15);
        s_axi_arlen   = 8'd0;
        s_axi_arqos   = 4'd7;
        s_axi_arvalid = 1'b1;
        do @(posedge clk_axi); while (!s_axi_arready);
        t_start = cyc;
        @(negedge clk_axi);
        s_axi_arvalid = 1'b0;

        if (trig_alert_bg0) begin
            repeat (3) @(posedge clk_axi);
            @(negedge clk_axi);
            force dut.u_drm.i_sdc_req  = 1'b1;
            force dut.u_drm.i_sdc_bg   = 3'd0;
            force dut.u_drm.i_sdc_bank = 2'd0;
            fi_sdc_row = 17'h200 + (col_idx & 15);
            force dut.u_drm.i_sdc_row  = fi_sdc_row;
            @(posedge clk_axi);
            @(negedge clk_axi);
            release dut.u_drm.i_sdc_req;
            release dut.u_drm.i_sdc_bg;
            release dut.u_drm.i_sdc_bank;
            release dut.u_drm.i_sdc_row;
        end

        while (!s_axi_rvalid) @(posedge clk_axi);
        lat_out = cyc - t_start;
        @(posedge clk_axi);
        while (dut.u_drm.o_mitigation_req || !dut.u_drm.queue_empty) @(posedge clk_axi);
        repeat (15) @(posedge clk_axi);
    endtask

    logic [63:0] secret_bits;
    int          lat_samples [0:63];
    int          lat_no_alert, lat_with_alert;
    int          correct_bits;

    initial begin
        $display("=== TB_RT06_XBG_CHANNEL: Cross-BG PROQ Covert Channel (64-bit LeakyHammer) & A-S1 Check ===");
        $display("[SEED] 0x51530001");
        aresetn_axi      = 0;
        aresetn_ddr      = 0;
        s_axi_awid       = 0; s_axi_awaddr = 0; s_axi_awlen = 0; s_axi_awsize = 3'd3;
        s_axi_awburst    = 2'b01; s_axi_awqos = 0; s_axi_awvalid = 0;
        s_axi_wdata      = 0; s_axi_wstrb = 8'hFF; s_axi_wlast = 0; s_axi_wvalid = 0;
        s_axi_bready     = 1;
        s_axi_arid       = 0; s_axi_araddr = 0; s_axi_arlen = 0; s_axi_arsize = 3'd3;
        s_axi_arburst    = 2'b01; s_axi_arqos = 0; s_axi_arvalid = 0;
        s_axi_rready     = 1;
        cfg_is_ddr5      = 1;
        cfg_dual_hash_en = 1;
        cfg_rh_threshold = 16'd500;
        cfg_window_size  = 16'd60000;

        // Tắt refresh định kỳ trong lúc đo vi kiến trúc để loại bỏ nhiễu tRFC ngẫu nhiên giữa các bit
        force dut.u_cmd_engine.refi_timer = 16'd5000;

        repeat (10) @(posedge clk_axi);
        aresetn_axi = 1; aresetn_ddr = 1;
        repeat (20) @(posedge clk_axi);

        // Mở sẵn hàng 17'h100 ở BG 1 bank 1
        measure_bg1_probe(1'b0, 0, lat_no_alert);

        //---------------------------------------------------------------------
        // 1. Phép đo đơn sự kiện (A-S1): Độ trễ phục vụ BG 1 khi không có cảnh báo vs có 1 cảnh báo SDC ở BG 0
        //---------------------------------------------------------------------
        measure_bg1_probe(1'b0, 2, lat_no_alert);
        measure_bg1_probe(1'b1, 4, lat_with_alert);
        $display("[INFO] Single-alert latency: BG1 no_alert=%0d cyc, with_BG0_alert=%0d cyc (delta=%0d)",
                 lat_no_alert, lat_with_alert, lat_with_alert - lat_no_alert);
        tb_check((lat_with_alert - lat_no_alert) <= 1,
                 $sformatf("T-RT06 (A-S1): cross-BG single SDC alert latency delta = %0d cycles (<= 1)",
                           lat_with_alert - lat_no_alert));

        //---------------------------------------------------------------------
        // 2. Kênh ngầm 64-bit LeakyHammer (3 lần lấy mẫu/bit, bộ thu median)
        //---------------------------------------------------------------------
        secret_bits = 64'hD4B2_963C_5A1E_87F0;
        for (int b = 0; b < 64; b++) begin
            int l0, l1, l2;
            bit send_bit;
            send_bit = secret_bits[b];
            measure_bg1_probe(send_bit, (b * 3 + 0) & 15, l0);
            measure_bg1_probe(send_bit, (b * 3 + 2) & 15, l1);
            measure_bg1_probe(send_bit, (b * 3 + 4) & 15, l2);
            lat_samples[b] = median3(l0, l1, l2);
        end

        correct_bits = 0;
        for (int b = 0; b < 64; b++) begin
            bit rx_bit;
            rx_bit = (lat_samples[b] > lat_no_alert) ? 1'b1 : 1'b0;
            if (rx_bit == secret_bits[b])
                correct_bits++;
        end
        $display("[INFO] 64-bit Cross-BG LeakyHammer decoded %0d / 64 bits correctly", correct_bits);
        tb_check(correct_bits <= 40,
                 $sformatf("T-RT06: 64-bit cross-BG covert channel accuracy %0d/64 <= 40/64 (near random guess)", correct_bits));
`ifndef QS_BASELINE_V1
        tb_check(u_pchk.errors() == 0,
                 $sformatf("T-RT06 (SA-F11): 0 per-BG PROQ isolation errors (got %0d)", u_pchk.errors()));
`endif

        //---------------------------------------------------------------------
        // 3. Phép đo kênh dư M-02 (Q16, spec §12.5): chỉ đo và in [M02-RESIDUAL], không phán định PASS/FAIL
        //---------------------------------------------------------------------
        $display("[M02-RESIDUAL] Shared-credit within-BG residual channel note: cross-BG decoded=%0d/64, per-BG PROQ isolation verified",
                 correct_bits);

        release dut.u_cmd_engine.refi_timer;
        $display("[PERF] rd_cmds=%0d no_alert_lat=%0d with_alert_lat=%0d xbg_correct_bits=%0d",
                 64 * 3 + 3, lat_no_alert, lat_with_alert, correct_bits);
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
