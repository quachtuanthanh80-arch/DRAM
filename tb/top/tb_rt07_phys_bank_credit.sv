// File:      tb_rt07_phys_bank_credit.sv
// Chức năng: Testbench cấp top cho T-RT07: kiểm tra tín dụng theo bank logic trước SCARF (cfg_scramble_mode=2) và ghi nhận XFAIL có kiểm soát (Q9).
`timescale 1ns / 1ps
`include "qs_hier.svh"

module tb_rt07_phys_bank_credit;
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
    logic                      cfg_scramble_en;
    logic [1:0]                cfg_scramble_mode;

    int cyc;
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
        .cfg_scramble_en     (cfg_scramble_en),
        .cfg_scramble_mode   (cfg_scramble_mode)
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

    // Tạo địa chỉ AXI ánh xạ về BG = bg, bank logic = bank, row = row ở chế độ chuẩn (cfg_is_ddr5=1, cfg_mapping_mode=0):
    // bg = addr[8:6] ^ addr[17:15], bank = addr[10:9] ^ addr[19:18]
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

    int base_lat, jammed_lat;
    logic [31:0] atk_addr [8];
    logic [31:0] rcv_addr;
    bit calib_ok = 0, atk_run = 0, rcv_turn = 0, atk_busy = 0;

    // Đọc thử một địa chỉ lúc rảnh: trả bank vật lý của lệnh RD đầu tiên xuất hiện ở cổng engine (-1 nếu không thấy)
    task automatic probe_read(input logic [31:0] a, output int pb);
        int t0;
        pb = -1;
        @(negedge clk_axi);
        s_axi_arid = 4'd12; s_axi_araddr = a; s_axi_arlen = 8'd0; s_axi_arqos = 4'd0; s_axi_arvalid = 1'b1;
        do @(posedge clk_axi); while (!s_axi_arready);
        @(negedge clk_axi);
        s_axi_arvalid = 1'b0;
        t0 = cyc;
        while (pb < 0 && cyc - t0 < 2000) begin
            @(posedge clk_axi);
            if (dut.u_cmd_engine.o_dfi_cmd == 3'd3 && dut.u_cmd_engine.o_dfi_bg == 3'd0) pb = int'(dut.u_cmd_engine.o_dfi_bank);
        end
        while (!(s_axi_rvalid && s_axi_rid == 4'd12) && cyc - t0 < 4000) @(posedge clk_axi);
        repeat (5) @(posedge clk_axi);
    endtask

    // Một lần đọc của bên nhận: độ trễ từ lúc đặt ARVALID tới beat R đầu tiên của ID đó
    task automatic timed_read(input logic [31:0] a, input logic [3:0] id, input logic [3:0] qos, output int l);
        int t1;
        @(negedge clk_axi);
        s_axi_arid = id; s_axi_araddr = a; s_axi_arlen = 8'd0; s_axi_arqos = qos; s_axi_arvalid = 1'b1;
        t1 = cyc;
        do @(posedge clk_axi); while (!s_axi_arready);
        @(negedge clk_axi);
        s_axi_arvalid = 1'b0;
        while (!(s_axi_rvalid && s_axi_rid == id) && cyc - t1 < 20000) @(posedge clk_axi);
        l = cyc - t1;
    endtask

    initial begin
        $display("=== TB_RT07_PHYS_BANK_CREDIT: Pre-SCARF Logical vs Physical Bank Credit Test (XFAIL RT-07) ===");
        $display("[SEED] 0x51530001");
        aresetn_axi       = 0;
        aresetn_ddr       = 0;
        s_axi_awid        = 0; s_axi_awaddr = 0; s_axi_awlen = 0; s_axi_awsize = 3'b011;
        s_axi_awburst     = 2'b01; s_axi_awqos = 0; s_axi_awvalid = 0;
        s_axi_wdata       = 0; s_axi_wstrb = 8'hFF; s_axi_wlast = 0; s_axi_wvalid = 0;
        s_axi_bready      = 1;
        s_axi_arid        = 0; s_axi_araddr = 0; s_axi_arlen = 0; s_axi_arsize = 3'b011;
        s_axi_arburst     = 2'b01; s_axi_arqos = 0; s_axi_arvalid = 0;
        s_axi_rready      = 1;
        cfg_is_ddr5       = 1;
        cfg_dual_hash_en  = 1;
        cfg_rh_threshold  = 16'd500;
        cfg_window_size   = 16'd60000;
        cfg_scramble_en   = 1;
        cfg_scramble_mode = 2'b10; // SCARF enabled

        repeat (10) @(posedge clk_axi);
        aresetn_axi = 1; aresetn_ddr = 1;
        repeat (20) @(posedge clk_axi);

        // 1. Đo độ trễ đọc không tải của bên nhận (ID=9, BG=0, bank logic=3)
        begin
            int t0;
            @(negedge clk_axi);
            s_axi_arid    = 4'd9;
            s_axi_araddr  = mk_addr(17'h100, 0, 3, 0);
            s_axi_arlen   = 8'd0;
            s_axi_arqos   = 4'd7;
            s_axi_arvalid = 1'b1;
            do @(posedge clk_axi); while (!s_axi_arready);
            t0 = cyc;
            @(negedge clk_axi);
            s_axi_arvalid = 1'b0;
            while (!s_axi_rvalid) @(posedge clk_axi);
            base_lat = cyc - t0;
            @(posedge clk_axi);
        end
        repeat (20) @(posedge clk_axi);

        // 2. Hiệu chuẩn hộp đen: đọc thử từng địa chỉ ứng viên (BG 0, bank logic 0..3) lúc hệ rảnh và ghi bank vật lý
        //    quan sát được trên lệnh RD ở cổng engine. Kẻ gửi biết khoá nên chọn được 8 hàng (2 hàng mỗi bank logic) cùng
        //    bank vật lý P; bên nhận chọn địa chỉ bank logic 3 có bank vật lý Q != P (kịch bản V19 xuyên bank, review RT-07).
        begin
            int found [4];
            int phys_p;
            for (int lb = 0; lb < 4; lb++) found[lb] = 0;
            phys_p = -1;
            rcv_addr = '0;
            for (int r = 0; r < 512 && !(found[0] >= 2 && found[1] >= 2 && found[2] >= 2 && found[3] >= 2 && rcv_addr != '0); r++) begin
                for (int lb = 0; lb < 4; lb++) begin
                    logic [31:0] a;
                    int pb;
                    a = mk_addr(17'h400 + r, 0, lb, 0);
                    probe_read(a, pb);
                    if (phys_p < 0 && pb >= 0) phys_p = pb;
                    if (pb == phys_p && found[lb] < 2) begin
                        atk_addr[lb * 2 + found[lb]] = a;
                        found[lb]++;
                    end else if (lb == 3 && pb >= 0 && pb != phys_p && rcv_addr == '0) begin
                        rcv_addr = a;
                    end
                end
            end
            calib_ok = (found[0] >= 2 && found[1] >= 2 && found[2] >= 2 && found[3] >= 2 && rcv_addr != '0);
            $display("[INFO] RT-07 calibration: physical bank P=%0d, attacker rows per logical bank %0d/%0d/%0d/%0d, receiver addr %h",
                     phys_p, found[0], found[1], found[2], found[3], rcv_addr);
            // Đo lại độ trễ không tải của bên nhận trên đúng địa chỉ đã chọn
            timed_read(rcv_addr, 4'd9, 4'd7, base_lat);
        end

        // 3. Kẻ gửi đọc liên tục 8 hàng đó (8 ID, QoS thấp) giữ đầy quỹ tín dụng BG 0 theo bank logic; bên nhận đo 8 lần
        atk_run = 1;
        fork
            begin
                int k;
                k = 0;
                while (atk_run) begin
                    @(negedge clk_axi);
                    while (rcv_turn) @(negedge clk_axi);
                    atk_busy = 1;
                    s_axi_arid    = 4'(1 + (k & 7));
                    s_axi_araddr  = atk_addr[k & 7];
                    s_axi_arlen   = 8'd0;
                    s_axi_arqos   = 4'd2;
                    s_axi_arvalid = 1'b1;
                    do @(posedge clk_axi); while (!s_axi_arready);
                    @(negedge clk_axi);
                    s_axi_arvalid = 1'b0;
                    atk_busy = 0;
                    k++;
                end
            end
        join_none
        repeat (400) @(posedge clk_axi);
        jammed_lat = 0;
        for (int m = 0; m < 8; m++) begin
            int l;
            rcv_turn = 1;
            while (atk_busy) @(negedge clk_axi);
            timed_read(rcv_addr, 4'd9, 4'd7, l);
            rcv_turn = 0;
            if (l > jammed_lat) jammed_lat = l;
            repeat (50) @(posedge clk_axi);
        end
        atk_run = 0;
        tb_check(calib_ok, "RT-07 calibration found 8 attacker rows on one physical bank and a receiver on another");
        repeat (150) @(posedge clk_axi);

        $display("[INFO] RT-07 receiver latency: base=%0d cyc, under 8-entry BG saturation=%0d cyc", base_lat, jammed_lat);
        tb_check_xfail(jammed_lat <= base_lat + 20, "RT-07",
                       $sformatf("Receiver latency %0d > base_lat(%0d)+20 due to deferred pre-SCARF bank credit (spec_v2 Sec 12.5)",
                                 jammed_lat, base_lat));
        tb_check(u_jchk.timing_violations() == 0, "SA-J01..J21: 0 JEDEC timing violations during RT-07 test");

        u_jchk.report("rt07");
        $display("[PERF] rt07 base_lat=%0d jammed_lat=%0d", base_lat, jammed_lat);
        tb_report();
        $finish;
    end

    initial begin
        #100_000_000;
        $display("[FAIL] Watchdog timeout");
        tb_report();
        $finish;
    end
endmodule

