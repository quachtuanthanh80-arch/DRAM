// File:      tb_rt08_cfg_change.sv
// Chức năng: Testbench cấp top cho T-RT08 (M-08, FI-58, FI-59): đổi cấu hình ánh xạ địa chỉ có rào chắn quiescence, chặn rò tín dụng BG và tránh deadlock RAW.
`timescale 1ns / 1ps
`include "qs_hier.svh"
`include "qs_fi.svh"

module tb_rt08_cfg_change;
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
    logic                      s_axi_rpoison;

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
    logic                      cfg_bank_coloring_en;
    logic [1:0]                cfg_mapping_mode;
    logic                      cfg_fault_clr;
    logic [8:0]                o_fault_cause;
    logic                      o_glitch_alert;

    bit fi_any;

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
        .DFI_RDLAT     (8),
        .TCK_PS        (TCK_PS)
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
        .s_axi_rpoison       (s_axi_rpoison),
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
        .o_ecc_double_err_cnt(o_ecc_double_err_cnt),
        .cfg_bank_coloring_en(cfg_bank_coloring_en),
        .cfg_mapping_mode    (cfg_mapping_mode),
        .cfg_fault_clr       (cfg_fault_clr),
        .o_fault_cause       (o_fault_cause),
        .o_glitch_alert      (o_glitch_alert)
    );

    dram_model #(.COL_W(COL_WIDTH), .RL(8), .WL(9)) u_dram (
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

    dfi_jedec_checker #(.TCK_PS(TCK_PS), .TB_DFI_WRLAT(9)) u_jchk (
        .clk  (clk_axi),
        .rst_n(aresetn_axi),
        .cmd  (dut.u_cmd_engine.o_dfi_cmd),
        .bg   (dut.u_cmd_engine.o_dfi_bg),
        .bank (dut.u_cmd_engine.o_dfi_bank),
        .row  (dut.u_cmd_engine.o_dfi_row),
        .len  (dut.u_cmd_engine.o_dfi_len)
    );

    qs_axi_txn_chk #(
        .AXI_ADDR_W(AXI_ADDR_WIDTH),
        .AXI_DATA_W(AXI_DATA_WIDTH),
        .AXI_ID_W  (AXI_ID_WIDTH),
        .AXI_LEN_W (AXI_LEN_WIDTH)
    ) u_achk (
        .clk          (clk_axi),
        .rst_n        (aresetn_axi),
        .en_v2        (1'b1),
        .chk_data_en  (1'b0),
        .s_axi_awid   (s_axi_awid),
        .s_axi_awaddr (s_axi_awaddr),
        .s_axi_awlen  (s_axi_awlen),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata  (s_axi_wdata),
        .s_axi_wstrb  (s_axi_wstrb),
        .s_axi_wlast  (s_axi_wlast),
        .s_axi_wvalid (s_axi_wvalid),
        .s_axi_wready (s_axi_wready),
        .s_axi_bid    (s_axi_bid),
        .s_axi_bresp  (s_axi_bresp),
        .s_axi_bvalid (s_axi_bvalid),
        .s_axi_bready (s_axi_bready),
        .s_axi_arid   (s_axi_arid),
        .s_axi_araddr (s_axi_araddr),
        .s_axi_arlen  (s_axi_arlen),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rid    (s_axi_rid),
        .s_axi_rdata  (s_axi_rdata),
        .s_axi_rresp  (s_axi_rresp),
        .s_axi_rlast  (s_axi_rlast),
        .s_axi_rvalid (s_axi_rvalid),
        .s_axi_rready (s_axi_rready),
        .s_axi_rpoison(s_axi_rpoison)
    );

    qs_top_probe_chk #(
        .BG_COUNT  (BG_COUNT),
        .BANK_COUNT(BANK_COUNT),
        .ROB_DEPTH (ROB_DEPTH)
    ) u_pchk (
        .clk       (clk_axi),
        .rst_n     (aresetn_axi),
        .en_v2     (1'b1),
        .fi_any    (fi_any),
        .excuse_f02(1'b0),
        .excuse_f05(1'b0)
    );

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

    initial begin
        $display("=== TB_RT08_CFG_CHANGE: Quiescence-Gated Mapping Config, RAW Hazard & FI-58/FI-59 ===");
        $display("[SEED] 0x51530001");
        aresetn_axi          = 0;
        aresetn_ddr          = 0;
        fi_any               = 0;
        s_axi_awid           = 0; s_axi_awaddr = 0; s_axi_awlen = 0; s_axi_awsize = 3'b011;
        s_axi_awburst        = 2'b01; s_axi_awqos = 0; s_axi_awvalid = 0;
        s_axi_wdata          = 0; s_axi_wstrb = 8'hFF; s_axi_wlast = 0; s_axi_wvalid = 0;
        s_axi_bready         = 1;
        s_axi_arid           = 0; s_axi_araddr = 0; s_axi_arlen = 0; s_axi_arsize = 3'b011;
        s_axi_arburst        = 2'b01; s_axi_arqos = 0; s_axi_arvalid = 0;
        s_axi_rready         = 1;
        cfg_is_ddr5          = 1;
        cfg_dual_hash_en     = 1;
        cfg_rh_threshold     = 16'd500;
        cfg_window_size      = 16'd60000;
        cfg_bank_coloring_en = 0;
        cfg_mapping_mode     = 2'b00;
        cfg_fault_clr        = 0;

        repeat (10) @(posedge clk_axi);
        aresetn_axi = 1; aresetn_ddr = 1;
        repeat (20) @(posedge clk_axi);

        //---------------------------------------------------------------------
        // 1. Giữ 4 đọc trong IQ + biến thể RAW trùng dòng với một lệnh ghi, đổi cfg_mapping_mode rồi cfg_bank_coloring_en,
        //    đổi cấu hình dồn dập nhanh hơn thời gian rút.
        //---------------------------------------------------------------------
        // Phát 1 lệnh ghi và 4 lệnh đọc liên tiếp (trong đó đọc thứ 1 trùng địa chỉ với lệnh ghi -> kiểm RAW hazard)
        @(negedge clk_axi);
        s_axi_awid    = 4'd1;
        s_axi_awaddr  = mk_addr(17'h050, 0, 0, 0);
        s_axi_awlen   = 8'd0;
        s_axi_awvalid = 1'b1;
        s_axi_wdata   = 64'hABCD_EF01_2345_6789;
        s_axi_wstrb   = 8'hFF;
        s_axi_wlast   = 1'b1;
        s_axi_wvalid  = 1'b1;
        do @(posedge clk_axi); while (!(s_axi_awready && s_axi_wready));
        @(negedge clk_axi);
        s_axi_awvalid = 1'b0;
        s_axi_wvalid  = 1'b0;
        s_axi_wlast   = 1'b0;

        for (int k = 0; k < 4; k++) begin
            @(negedge clk_axi);
            s_axi_arid    = 4'(2 + k);
            s_axi_araddr  = (k == 0) ? mk_addr(17'h050, 0, 0, 0) : mk_addr(17'h060 + k, k & 7, k & 3, k);
            s_axi_arlen   = 8'd0;
            s_axi_arvalid = 1'b1;
            do @(posedge clk_axi); while (!s_axi_arready);
        end
        @(negedge clk_axi);
        s_axi_arvalid = 1'b0;

        // Đổi cấu hình dồn dập khi 4 lệnh đọc vẫn đang trên đường ống/trong IQ
        @(negedge clk_axi);
        cfg_mapping_mode = 2'b01;
        repeat (3) @(posedge clk_axi);
        @(negedge clk_axi);
        cfg_bank_coloring_en = 1'b1;
        repeat (3) @(posedge clk_axi);
        @(negedge clk_axi);
        cfg_mapping_mode = 2'b10;
        repeat (3) @(posedge clk_axi);
        @(negedge clk_axi);
        cfg_mapping_mode     = 2'b00;
        cfg_bank_coloring_en = 1'b0;
        @(negedge clk_axi);
        cfg_mapping_mode     = 2'b01;

        while (u_achk.rd_done < u_achk.rd_cmds || u_achk.wr_done < u_achk.wr_cmds) @(posedge clk_axi);
        repeat (20) @(posedge clk_axi);

        // Kiểm mọi bk_cnt[0..31] == 0 (không rò tín dụng âm 4'hF như ở v1!)
        begin
            int leaked_banks;
            leaked_banks = 0;
            for (int i = 0; i < BG_COUNT * BANK_COUNT; i++) begin
                if (`QS_T_BK_CNT(dut)[i] != 4'd0) begin
                    $display("[LEAKED_BANK] Bank %0d (BG %0d, bk %0d) bk_cnt = %0d", i, i/4, i%4, `QS_T_BK_CNT(dut)[i]);
                    leaked_banks++;
                end
            end
            tb_check(leaked_banks == 0,
                     $sformatf("T-RT08 (SA-C03, SA-C08): 0 banks with leaked/underflowed bk_cnt after dynamic cfg change (got %0d)",
                               leaked_banks));
            tb_check(`QS_T_MAP_CFG_Q(dut)[67:66] == 2'b01,
                     "T-RT08 (SA-C06): new cfg_mapping_mode=2'b01 latched cleanly after pipeline quiescence");
        end

        // Kiểm mỗi BG nhận đủ 8 lệnh mới sau khi đổi cấu hình
        @(negedge clk_axi);
        cfg_mapping_mode = 2'b00;
        repeat (10) @(posedge clk_axi);
        for (int g = 0; g < BG_COUNT; g++) begin
            for (int k = 0; k < 8; k++) begin
                @(negedge clk_axi);
                s_axi_arid    = 4'(k & 15);
                s_axi_araddr  = mk_addr(17'h100 + k, g, k & 3, k);
                s_axi_arlen   = 8'd0;
                s_axi_arvalid = 1'b1;
                do @(posedge clk_axi); while (!s_axi_arready);
            end
            @(negedge clk_axi);
            s_axi_arvalid = 1'b0;
            while (u_achk.rd_done < u_achk.rd_cmds) @(posedge clk_axi);
        end
        repeat (10) @(posedge clk_axi);
        tb_check(u_pchk.errors() == 0 && u_achk.errors() == 0,
                 $sformatf("T-RT08: all %0d BGs accepted 8 commands cleanly with 0 checker errors (pchk=%0d, achk=%0d)",
                           BG_COUNT, u_pchk.errors(), u_achk.errors()));

        //---------------------------------------------------------------------
        // 2. FI-59: Đảo cfg_pend_q 1->0 giữa lúc đang chờ cấu hình -> tự bật lại ở +1 và không áp cấu hình khi chưa idle
        //---------------------------------------------------------------------
        for (int k = 0; k < 2; k++) begin
            @(negedge clk_axi);
            s_axi_arid    = 4'(1 + k);
            s_axi_araddr  = mk_addr(17'h200 + k, k, 0, k);
            s_axi_arlen   = 8'd0;
            s_axi_arvalid = 1'b1;
            do @(posedge clk_axi); while (!s_axi_arready);
        end
        @(negedge clk_axi);
        s_axi_arvalid    = 1'b0;
        cfg_mapping_mode = 2'b01;
        @(posedge clk_axi); // cfg_pend_q lên 1
        @(negedge clk_axi);
        `QS_T_CFG_PEND_Q(dut) = 1'b0; // FI-59: xóa cfg_pend_q khi vẫn còn lệnh đang bay
        @(posedge clk_axi);
        #1ps;
        tb_check(`QS_T_CFG_PEND_Q(dut) === 1'b1, "FI-59: cfg_pend_q 1->0 re-asserts at +1 cycle when cfg_in != map_cfg_q");
        while (u_achk.rd_done < u_achk.rd_cmds) @(posedge clk_axi);
        repeat (20) @(posedge clk_axi);
        tb_check(u_pchk.err_c06 == 0, "FI-59 (SA-C06): map_cfg_q never updated before map_idle_q=1");

        //---------------------------------------------------------------------
        // 3. FI-58: Lật 1 bit map_cfg_q khi có đọc trong IQ -> cfg_pend_q bật ở +1, drain rồi tự khôi phục map_cfg_q == cfg_in
        //---------------------------------------------------------------------
        fi_any = 1'b1;
        @(negedge clk_axi);
        s_axi_arid    = 4'd3;
        s_axi_araddr  = mk_addr(17'h300, 0, 0, 0);
        s_axi_arlen   = 8'd0;
        s_axi_arvalid = 1'b1;
        do @(posedge clk_axi); while (!s_axi_arready);
        @(negedge clk_axi);
        s_axi_arvalid = 1'b0;
        `QS_T_MAP_CFG_Q(dut)[66] = ~`QS_T_MAP_CFG_Q(dut)[66]; // FI-58: lật 1 bit map_cfg_q
        @(posedge clk_axi);
        #1ps;
        tb_check(`QS_T_CFG_PEND_Q(dut) === 1'b1, "FI-58: 1-bit flip on map_cfg_q asserts cfg_pend_q at +1 cycle");
        while (u_achk.rd_done < u_achk.rd_cmds) @(posedge clk_axi);
        repeat (25) @(posedge clk_axi);
        tb_check(`QS_T_MAP_CFG_Q(dut)[67:66] == cfg_mapping_mode && `QS_T_CFG_PEND_Q(dut) == 1'b0,
                 "FI-58: map_cfg_q self-healed (rolled back to cfg_in) after drain");

        repeat (2) @(posedge clk_axi);
        u_achk.final_check();
        tb_check(u_jchk.timing_violations() == 0, "SA-J01..J21: 0 JEDEC timing violations");

        u_jchk.report("rt08");
        u_pchk.report("rt08");
        $display("[PERF] rd_cmds=%0d wr_cmds=%0d cfg_pend_max=%0d fi_count=2 fi_detect_lat_max=1",
                 u_achk.rd_cmds, u_achk.wr_cmds, u_pchk.cfg_pend_max);
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

