// File: tb_secure_top_integrity.sv
// Chức năng: Testbench xác minh toàn vẹn, Carter-Wegman MAC và Bonsai Merkle Tree (V-1 .. V-10) cho Q-Shield.

`timescale 1ns / 1ps

module tb_secure_top_integrity #(
    parameter int TB_TCK_PS     = 4000,
    parameter bit RANDOM_RREADY = 1'b1
);
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

    logic clk_axi = 1'b0;
    always #(0.0005ns * TB_TCK_PS) clk_axi = ~clk_axi;

    logic clk_ddr = 1'b0;
    always #1.25 clk_ddr = ~clk_ddr;

    logic aresetn_axi;
    logic aresetn_ddr;

    // Security & Integrity Ports
    logic         i_enc_enable;
    logic         i_keys_valid;
    logic [255:0] i_key1;
    logic [255:0] i_key2;
    logic [3:0]   i_asid;
    logic [18:0]  i_epoch;
    wire          o_crypto_busy;
    wire  [15:0]  o_crypto_reject_cnt;
    wire  [15:0]  o_crypto_err_cnt;

    logic         i_integ_enable;
    logic         i_k3_valid;
    logic [255:0] i_k3;
    logic [127:0] i_h;
    logic         i_meta_init_start;
    wire          o_meta_init_done;
    wire  [31:0]  o_meta_init_cycles;
    logic         i_meta_flush_start;
    wire          o_meta_flush_done;
    logic         i_cache_clear;
    logic [63:0]  i_prot_base;
    logic [63:0]  i_prot_lines;
    wire  [63:0]  o_tree_root;
    wire  [31:0]  o_integrity_fail_cnt;
    wire  [31:0]  o_tree_fail_cnt;
    wire  [31:0]  o_reencrypt_events;
    wire  [31:0]  o_mc_hit_cnt;
    wire  [31:0]  o_mc_miss_cnt;
    wire  [31:0]  o_meta_rd_cnt;
    wire  [31:0]  o_meta_wr_cnt;
    wire          o_integrity_alert;

    // APB4 CSR & Lock
    logic         psel;
    logic         penable;
    logic         pwrite;
    logic [7:0]   paddr;
    logic [31:0]  pwdata;
    logic [2:0]   pprot;
    wire  [31:0]  prdata;
    wire          pready;
    wire          pslverr;
    logic         i_ext_sec_locked;
`ifdef QSHIELD_TEST
    logic         i_test_force_minor_valid;
    logic [63:0]  i_test_force_minor_addr;
    logic [6:0]   i_test_force_minor_val;
    wire          o_test_force_minor_done;
`endif

    // AXI4 Interface
    logic [AXI_ID_WIDTH-1:0]   s_axi_awid;
    logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr;
    logic [AXI_LEN_WIDTH-1:0]  s_axi_awlen;
    logic [2:0]                s_axi_awsize;
    logic [1:0]                s_axi_awburst;
    logic [AXI_QOS_WIDTH-1:0]  s_axi_awqos;
    logic                      s_axi_awvalid;
    wire                       s_axi_awready;

    logic [AXI_DATA_WIDTH-1:0] s_axi_wdata;
    logic [AXI_STRB_WIDTH-1:0] s_axi_wstrb;
    logic                      s_axi_wlast;
    logic                      s_axi_wvalid;
    wire                       s_axi_wready;

    wire  [AXI_ID_WIDTH-1:0]   s_axi_bid;
    wire  [1:0]                s_axi_bresp;
    wire                       s_axi_bvalid;
    logic                      s_axi_bready;

    logic [AXI_ID_WIDTH-1:0]   s_axi_arid;
    logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr;
    logic [AXI_LEN_WIDTH-1:0]  s_axi_arlen;
    logic [2:0]                s_axi_arsize;
    logic [1:0]                s_axi_arburst;
    logic [AXI_QOS_WIDTH-1:0]  s_axi_arqos;
    logic                      s_axi_arvalid;
    wire                       s_axi_arready;

    wire  [AXI_ID_WIDTH-1:0]   s_axi_rid;
    wire  [AXI_DATA_WIDTH-1:0] s_axi_rdata;
    wire  [1:0]                s_axi_rresp;
    wire                       s_axi_rlast;
    wire                       s_axi_rvalid;
    logic                      s_axi_rready;

    // DFI Interface
    wire  [2:0]                dfi_cmd;
    wire  [BG_WIDTH-1:0]       dfi_bg;
    wire  [BANK_WIDTH-1:0]     dfi_bank;
    wire  [ROW_WIDTH-1:0]      dfi_row;
    wire  [COL_WIDTH-1:0]      dfi_col;
    wire  [7:0]                dfi_len;
    wire                       dfi_wrdata_en;
    wire  [63:0]               dfi_wrdata;
    wire  [7:0]                dfi_wrdata_mask;
    wire  [7:0]                dfi_wrdata_ecc;
    wire                       dfi_rddata_valid;
    wire  [63:0]               dfi_rddata;
    wire  [7:0]                dfi_rddata_ecc;

    axi_ddr5_mc_secure_top #(
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_STRB_WIDTH (AXI_STRB_WIDTH),
        .AXI_LEN_WIDTH  (AXI_LEN_WIDTH),
        .AXI_QOS_WIDTH  (AXI_QOS_WIDTH),
        .BG_COUNT       (BG_COUNT),
        .BG_WIDTH       (BG_WIDTH),
        .BANK_COUNT     (BANK_COUNT),
        .BANK_WIDTH     (BANK_WIDTH),
        .ROW_WIDTH      (ROW_WIDTH),
        .COL_WIDTH      (COL_WIDTH),
        .ROB_DEPTH      (ROB_DEPTH),
        .DFI_WRLAT      (9),
        .DFI_RDLAT      (8),
        .TCK_PS         (TB_TCK_PS)
    ) dut (
        .clk_axi             (clk_axi),
        .aresetn_axi         (aresetn_axi),
        .clk_ddr             (clk_ddr),
        .aresetn_ddr         (aresetn_ddr),

        // Crypto & Integrity
        .i_enc_enable        (i_enc_enable),
        .i_keys_valid        (i_keys_valid),
        .i_key1              (i_key1),
        .i_key2              (i_key2),
        .i_asid              (i_asid),
        .i_epoch             (i_epoch),
        .o_crypto_busy       (o_crypto_busy),
        .o_crypto_reject_cnt (o_crypto_reject_cnt),
        .o_crypto_err_cnt    (o_crypto_err_cnt),

        .i_integ_enable      (i_integ_enable),
        .i_k3_valid          (i_k3_valid),
        .i_k3                (i_k3),
        .i_h                 (i_h),
        .i_meta_init_start   (i_meta_init_start),
        .o_meta_init_done    (o_meta_init_done),
        .o_meta_init_cycles  (o_meta_init_cycles),
        .i_meta_flush_start  (i_meta_flush_start),
        .o_meta_flush_done   (o_meta_flush_done),
        .i_cache_clear       (i_cache_clear),
        .i_prot_base         (i_prot_base),
        .i_prot_lines        (i_prot_lines),
        .o_tree_root         (o_tree_root),
        .o_integrity_fail_cnt(o_integrity_fail_cnt),
        .o_tree_fail_cnt     (o_tree_fail_cnt),
        .o_reencrypt_events  (o_reencrypt_events),
        .o_mc_hit_cnt        (o_mc_hit_cnt),
        .o_mc_miss_cnt       (o_mc_miss_cnt),
        .o_meta_rd_cnt       (o_meta_rd_cnt),
        .o_meta_wr_cnt       (o_meta_wr_cnt),
        .o_integrity_alert   (o_integrity_alert),

        // APB4 Integrity CSR
        .psel                (psel),
        .penable             (penable),
        .pwrite              (pwrite),
        .paddr               (paddr),
        .pwdata              (pwdata),
        .pprot               (pprot),
        .prdata              (prdata),
        .pready              (pready),
        .pslverr             (pslverr),
        .i_ext_sec_locked    (i_ext_sec_locked),
`ifdef QSHIELD_TEST
        .i_test_force_minor_valid (i_test_force_minor_valid),
        .i_test_force_minor_addr  (i_test_force_minor_addr),
        .i_test_force_minor_val   (i_test_force_minor_val),
        .o_test_force_minor_done  (o_test_force_minor_done),
`endif

        // AXI Slave
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
        .s_axi_rpoison       (),
        .s_axi_rchk          (),
        .o_parity_err        (),

        // DFI
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

        .cfg_is_ddr5         (1'b1),
        .cfg_scramble_mode   (2'b00),
        .cfg_scramble_en     (1'b0),
        .cfg_dual_hash_en    (1'b1),
        .cfg_rh_threshold    (16'd32),
        .cfg_window_size     (16'd1024),
        .o_throttled_events  (),
        .o_ecc_single_err_cnt(),
        .o_ecc_double_err_cnt()
    );

    // DRAM Model
    dram_model #(
        .COL_W  (COL_WIDTH),
        .RL     (8),
        .WL     (9)
    ) u_dram (
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
        .wrdata_mask  (dfi_wrdata_mask),
        .wrdata_ecc   (dfi_wrdata_ecc),
        .rddata_valid (dfi_rddata_valid),
        .rddata       (dfi_rddata),
        .rddata_ecc   (dfi_rddata_ecc)
    );

    // Thu thập kết quả AXI phản hồi
    logic [1:0]  captured_bresp;
    logic [AXI_ID_WIDTH-1:0] captured_bid;
    int          b_done_count = 0;

    // Kiểm toán giao dịch AXI metadata theo ID (BMT=8, ML=9, REENC=10) so với số giao dịch logic
    int axi_aw_id8_cnt = 0, axi_aw_id9_cnt = 0, axi_aw_id10_cnt = 0;
    int axi_ar_id8_cnt = 0, axi_ar_id9_cnt = 0, axi_ar_id10_cnt = 0;
    int logic_bmt_wr_cnt = 0, logic_ml_wr_cnt = 0, logic_reenc_wr_cnt = 0;
    int logic_bmt_rd_cnt = 0, logic_ml_rd_cnt = 0, logic_reenc_rd_cnt = 0;
    bit ml_wr_q = 0, reenc_wr_q = 0, ml_rd_q = 0, reenc_rd_q = 0;

    always @(posedge clk_axi) begin
        if (!aresetn_axi) begin
            ml_wr_q    <= 1'b0;
            reenc_wr_q <= 1'b0;
            ml_rd_q    <= 1'b0;
            reenc_rd_q <= 1'b0;
        end else begin
            if (dut.u_crypto_bridge.m_axi_awvalid && dut.u_crypto_bridge.m_axi_awready) begin
                if (dut.u_crypto_bridge.m_axi_awid == 4'd8)  axi_aw_id8_cnt++;
                if (dut.u_crypto_bridge.m_axi_awid == 4'd9)  axi_aw_id9_cnt++;
                if (dut.u_crypto_bridge.m_axi_awid == 4'd10) axi_aw_id10_cnt++;
            end
            if (dut.u_crypto_bridge.m_axi_arvalid && dut.u_crypto_bridge.m_axi_arready) begin
                if (dut.u_crypto_bridge.m_axi_arid == 4'd8)  axi_ar_id8_cnt++;
                if (dut.u_crypto_bridge.m_axi_arid == 4'd9)  axi_ar_id9_cnt++;
                if (dut.u_crypto_bridge.m_axi_arid == 4'd10) axi_ar_id10_cnt++;
            end
            if (dut.u_crypto_bridge.bmt_dram_wr_ready) logic_bmt_wr_cnt++;
            if (dut.u_crypto_bridge.ml_dram_wr_valid && !ml_wr_q)       logic_ml_wr_cnt++;
            if (dut.u_crypto_bridge.reenc_dram_wr_valid && !reenc_wr_q) logic_reenc_wr_cnt++;
            if (dut.u_crypto_bridge.bmt_dram_rd_ready) logic_bmt_rd_cnt++;
            if (dut.u_crypto_bridge.ml_dram_rd_req && !ml_rd_q)         logic_ml_rd_cnt++;
            if (dut.u_crypto_bridge.reenc_dram_rd_req && !reenc_rd_q)   logic_reenc_rd_cnt++;
            ml_wr_q    <= dut.u_crypto_bridge.ml_dram_wr_valid;
            reenc_wr_q <= dut.u_crypto_bridge.reenc_dram_wr_valid;
            ml_rd_q    <= dut.u_crypto_bridge.ml_dram_rd_req;
            reenc_rd_q <= dut.u_crypto_bridge.reenc_dram_rd_req;
        end
    end

    always @(posedge clk_axi) begin
        if (s_axi_bvalid && s_axi_bready) begin
            captured_bresp <= s_axi_bresp;
            captured_bid   <= s_axi_bid;
            b_done_count   <= b_done_count + 1;
        end
    end

    logic [63:0] r_data_captured [256];
    logic [1:0]  r_resp_captured [256];
    logic [AXI_ID_WIDTH-1:0] r_id_captured [256];
    int          r_beat_count = 0;

    always @(posedge clk_axi) begin
        if (s_axi_rvalid && s_axi_rready) begin
            r_data_captured[r_beat_count] <= s_axi_rdata;
            r_resp_captured[r_beat_count] <= s_axi_rresp;
            r_id_captured[r_beat_count]   <= s_axi_rid;
            r_beat_count <= r_beat_count + 1;
        end
    end

    // Bộ tạo sẵn sàng ngẫu nhiên
    logic [31:0] lfsr = 32'hA5A5_5A5A;
    always @(posedge clk_axi or negedge aresetn_axi) begin
        if (!aresetn_axi) begin
            lfsr         <= 32'hA5A5_5A5A;
            s_axi_rready <= 1'b1;
            s_axi_bready <= 1'b1;
        end else if (RANDOM_RREADY) begin
            lfsr         <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
            s_axi_rready <= lfsr[0] | lfsr[1];
            s_axi_bready <= lfsr[2] | lfsr[3];
        end else begin
            s_axi_rready <= 1'b1;
            s_axi_bready <= 1'b1;
        end
    end

    // Tasks phát lệnh AXI chuẩn 64B và APB4 CSR
    task automatic write_line_resp(
        input  logic [AXI_ID_WIDTH-1:0]   id,
        input  logic [AXI_ADDR_WIDTH-1:0] addr,
        input  logic [511:0]              data_512,
        output logic [1:0]                bresp_out
    );
        int wt;
        bresp_out = 2'b11;
        @(negedge clk_axi);
        s_axi_awid    <= id;
        s_axi_awaddr  <= addr;
        s_axi_awlen   <= 8'd7;
        s_axi_awsize  <= 3'b011;
        s_axi_awburst <= 2'b01;
        s_axi_awqos   <= 4'd2;
        s_axi_awvalid <= 1'b1;

        wt = 0;
        while (!s_axi_awready && wt < 20000) begin
            @(posedge clk_axi);
            wt++;
        end
        if (wt >= 20000) tb_check(1'b0, $sformatf("AWREADY timeout at 0x%08h", addr));
        @(negedge clk_axi);
        s_axi_awvalid <= 1'b0;

        for (int b = 0; b < 8; b++) begin
            s_axi_wdata  <= data_512[b*64 +: 64];
            s_axi_wstrb  <= 8'hFF;
            s_axi_wlast  <= (b == 7);
            s_axi_wvalid <= 1'b1;
            wt = 0;
            while (!s_axi_wready && wt < 20000) begin
                @(posedge clk_axi);
                wt++;
            end
            if (wt >= 20000) tb_check(1'b0, $sformatf("WREADY timeout beat %0d at 0x%08h", b, addr));
            @(negedge clk_axi);
        end
        s_axi_wvalid <= 1'b0;

        wt = 0;
        while (!(s_axi_bvalid && s_axi_bready) && wt < 20000) begin
            @(posedge clk_axi);
            wt++;
        end
        if (wt >= 20000) tb_check(1'b0, $sformatf("BVALID timeout at 0x%08h", addr));
        bresp_out = s_axi_bresp;
        @(negedge clk_axi);
    endtask

    task automatic write_line(
        input logic [AXI_ID_WIDTH-1:0]   id,
        input logic [AXI_ADDR_WIDTH-1:0] addr,
        input logic [511:0]              data_512
    );
        logic [1:0] br;
        write_line_resp(id, addr, data_512, br);
        tb_check(br === 2'b00, $sformatf("AXI WR BRESP=OKAY at 0x%08h (got %0b)", addr, br));
    endtask

    task automatic read_line(
        input logic [AXI_ID_WIDTH-1:0]   id,
        input logic [AXI_ADDR_WIDTH-1:0] addr
    );
        int wt;
        @(negedge clk_axi);
        s_axi_arid    <= id;
        s_axi_araddr  <= addr;
        s_axi_arlen   <= 8'd7;
        s_axi_arsize  <= 3'b011;
        s_axi_arburst <= 2'b01;
        s_axi_arqos   <= 4'd2;
        s_axi_arvalid <= 1'b1;

        wt = 0;
        while (!s_axi_arready && wt < 20000) begin
            @(posedge clk_axi);
            wt++;
        end
        if (wt >= 20000) tb_check(1'b0, $sformatf("ARREADY timeout at 0x%08h", addr));
        @(negedge clk_axi);
        s_axi_arvalid <= 1'b0;
    endtask

    task automatic wait_read_beats(input int expected_beats);
        int timeout_cyc = 0;
        while (r_beat_count < expected_beats && timeout_cyc < 8000) begin
            @(posedge clk_axi);
            timeout_cyc++;
        end
        if (timeout_cyc >= 8000) begin
            tb_check(1'b0, $sformatf("Read beat timeout (got %0d/%0d)", r_beat_count, expected_beats));
        end
    endtask

    task automatic apb_write(input logic [7:0] addr, input logic [31:0] data, output logic err);
        @(negedge clk_axi);
        psel    <= 1'b1;
        penable <= 1'b0;
        pwrite  <= 1'b1;
        paddr   <= addr;
        pwdata  <= data;
        @(posedge clk_axi);
        @(negedge clk_axi);
        penable <= 1'b1;
        #1ps;
        while (!pready) begin
            @(posedge clk_axi);
            #1ps;
        end
        err = pslverr;
        @(posedge clk_axi);
        @(negedge clk_axi);
        psel    <= 1'b0;
        penable <= 1'b0;
        pwrite  <= 1'b0;
    endtask

    task automatic apb_read(input logic [7:0] addr, output logic [31:0] data, output logic err);
        @(negedge clk_axi);
        psel    <= 1'b1;
        penable <= 1'b0;
        pwrite  <= 1'b0;
        paddr   <= addr;
        @(posedge clk_axi);
        @(negedge clk_axi);
        penable <= 1'b1;
        #1ps;
        while (!pready) begin
            @(posedge clk_axi);
            #1ps;
        end
        data = prdata;
        err  = pslverr;
        @(posedge clk_axi);
        @(negedge clk_axi);
        psel    <= 1'b0;
        penable <= 1'b0;
    endtask

    // Ánh xạ địa chỉ AXI tuyến tính sang tọa độ DRAM thực tế (Bank Group, Bank, Row, Col)
    task automatic get_dram_coords(
        input  logic [31:0] addr,
        output logic [2:0]  bg,
        output logic [1:0]  bank,
        output logic [16:0] row,
        output logic [12:0] col
    );
        bg   = addr[8:6] ^ addr[20:18];
        bank = addr[17:16];
        row  = {3'b0, addr[31:18]};
        col  = addr[15:3];
    endtask

    function automatic logic [31:0] get_ml_addr(input logic [31:0] data_addr);
        return 32'h0004_1000 + ({data_addr[31:9], 6'b0});
    endfunction

    task automatic wait_dram_idle();
        int wd = 0;
        while (o_crypto_busy && wd < 30000) begin
            @(posedge clk_axi);
            wd++;
        end
        if (wd >= 30000) $display("[WARN] wait_dram_idle o_crypto_busy timeout!");
        repeat (120) @(posedge clk_axi);
        while (u_dram.wq_base.size() > 0 && wd < 40000) begin
            @(posedge clk_axi);
            wd++;
        end
        repeat (20) @(posedge clk_axi);
    endtask

    task automatic clear_meta_caches();
        @(negedge clk_axi);
        i_cache_clear <= 1'b1;
        @(posedge clk_axi);
        @(negedge clk_axi);
        i_cache_clear <= 1'b0;
        @(posedge clk_axi);
    endtask

    task automatic flush_and_drain();
        logic apb_e;
        int ft;
        apb_write(8'h00, 32'h0000_0005, apb_e); // integ_enable=1, flush_start=1
        repeat (2) @(posedge clk_axi);
        ft = 0;
        while (!o_meta_flush_done && ft < 20000) begin
            @(posedge clk_axi);
            ft++;
        end
        if (ft >= 20000) tb_check(1'b0, "flush_and_drain: o_meta_flush_done timeout");
        wait_dram_idle();
    endtask

    task automatic save_line_dram(input logic [31:0] addr, output logic [511:0] line_data);
        logic [2:0]  bg;
        logic [1:0]  bank;
        logic [16:0] row;
        logic [12:0] col;
        get_dram_coords(addr, bg, bank, row, col);
        for (int w = 0; w < 8; w++) begin
            bit [63:0] val;
            u_dram.backdoor_read_word(bg, bank, row, 13'(col + w), val);
            line_data[w*64 +: 64] = val;
        end
    endtask

    task automatic restore_line_dram(input logic [31:0] addr, input logic [511:0] line_data);
        logic [2:0]  bg;
        logic [1:0]  bank;
        logic [16:0] row;
        logic [12:0] col;
        get_dram_coords(addr, bg, bank, row, col);
        for (int w = 0; w < 8; w++) begin
            u_dram.backdoor_write_word(bg, bank, row, 13'(col + w), line_data[w*64 +: 64]);
        end
    endtask

    task automatic dump_dram_bmt(input string filepath);
        int fd;
        logic [511:0] blk;
        logic [31:0]  addr;
        fd = $fopen(filepath, "w");
        if (fd == 0) begin
            $display("[ERROR] Cannot open %s for BMT dump", filepath);
            tb_check(1'b0, "BMT DRAM dump file creation");
        end else begin
            for (int i = 0; i < 64; i++) begin
                addr = 32'h0004_0000 + i * 64;
                save_line_dram(addr, blk);
                $fdisplay(fd, "%016x %0128x", {32'h0, addr}, blk);
            end
            for (int i = 0; i < 8; i++) begin
                addr = 32'h0004_9000 + i * 64;
                save_line_dram(addr, blk);
                $fdisplay(fd, "%016x %0128x", {32'h0, addr}, blk);
            end
            addr = 32'h0004_9200;
            save_line_dram(addr, blk);
            $fdisplay(fd, "%016x %0128x", {32'h0, addr}, blk);
            $fclose(fd);
            $display("[V-8] Dumped 73 BMT DRAM blocks to %s", filepath);
        end
    endtask

    // Mảng dữ liệu tham chiếu
    logic [511:0] golden_mem [1024];

    // Đo hiệu năng cho Paper
    longint t_start, t_end;
    longint cyc_integ, cyc_no_integ;

    initial begin
        logic [255:0] K3_REF;
        logic [127:0] H_EXP;
        logic [31:0]  rdata32;
        logic         apb_err;
        logic [1:0]   br_pre;
        logic [31:0]  prng;

        K3_REF = 256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f;
        H_EXP  = 128'hf29000b62a499fd0a9f39a6add2e7780;

        $display("================================================================================");
        $display("  Q-SHIELD INTEGRATED SECURITY TESTBENCH (Stage 0 APB CSR + V-1 .. V-10)");
        $display("  Target: tb_secure_top_integrity (Carter-Wegman MAC, BMT, Split-Counters)");
        $display("================================================================================");
        $fflush();

        aresetn_axi        = 1'b0;
        aresetn_ddr        = 1'b0;
        i_enc_enable       = 1'b1;
        i_keys_valid       = 1'b1;
        i_key1             = 256'h2718281828459045235360287471352662497757247093699959574966967627;
        i_key2             = 256'h3141592653589793238462643383279502884197169399375105820974944592;
        i_asid             = 4'h1;
        i_epoch            = 19'h00001;

        // Để APB CSR làm nguồn cấu hình chính và kiểm tra Auto-H khi i_h == 0
        i_integ_enable     = 1'b0;
        i_k3_valid         = 1'b0;
        i_k3               = 256'h0;
        i_h                = 128'h0;
        i_meta_init_start  = 1'b0;
        i_meta_flush_start = 1'b0;
        i_cache_clear      = 1'b0;
        i_prot_base        = 64'h0000_0000;
        i_prot_lines       = 64'd0;

        psel               = 1'b0;
        penable            = 1'b0;
        pwrite             = 1'b0;
        paddr              = 8'h0;
        pwdata             = 32'h0;
        pprot              = 3'b0;
        i_ext_sec_locked   = 1'b0;
`ifdef QSHIELD_TEST
        i_test_force_minor_valid = 1'b0;
        i_test_force_minor_addr  = 64'h0;
        i_test_force_minor_val   = 7'd127;
`endif

        s_axi_awvalid      = 1'b0;
        s_axi_wvalid       = 1'b0;
        s_axi_bready       = 1'b1;
        s_axi_arvalid      = 1'b0;
        s_axi_rready       = 1'b1;

        repeat (10) @(posedge clk_axi);
        @(negedge clk_axi);
        aresetn_axi = 1'b1;
        aresetn_ddr = 1'b1;
        repeat (25) @(posedge clk_axi);

        // ---------------------------------------------------------------------
        // Stage 0: APB4 CSR, K3 write-only, lock, pre-init SLVERR, Auto-H
        // ---------------------------------------------------------------------
        $display("[Stage 0] APB4 CSR configuration, Auto-H, lock & pre-init SLVERR checks...");
        apb_write(8'h04, 32'h0000_0000, apb_err); // PROT_BASE_LO
        tb_check(apb_err === 1'b0, "CSR write PROT_BASE_LO OKAY");
        apb_write(8'h08, 32'h0000_0000, apb_err); // PROT_BASE_HI
        tb_check(apb_err === 1'b0, "CSR write PROT_BASE_HI OKAY");
        apb_write(8'h0C, 32'd12, apb_err);        // PROT_LINES_LOG2 = 12 (4096 lines)
        tb_check(apb_err === 1'b0, "CSR write PROT_LINES_LOG2 OKAY");
        apb_read(8'h0C, rdata32, apb_err);
        tb_check(apb_err === 1'b0 && rdata32 === 32'd12, "CSR readback PROT_LINES_LOG2 == 12");

        for (int w = 0; w < 8; w++) begin
            apb_write(8'h10 + 8'(w * 4), K3_REF[w*32 +: 32], apb_err);
            tb_check(apb_err === 1'b0, $sformatf("CSR write K3_%0d OKAY", w));
        end
        apb_read(8'h30, rdata32, apb_err); // K3_VALID
        tb_check(apb_err === 1'b0 && rdata32 === 32'h1, "CSR K3_VALID == 1 after writing K3_0..7");

        apb_read(8'h10, rdata32, apb_err); // Đọc ngược K3 phải báo PSLVERR
        tb_check(apb_err === 1'b1, "CSR read K3_0 rejected with PSLVERR (write-only)");

        // Kiểm tra khóa bảo mật i_ext_sec_locked
        i_ext_sec_locked = 1'b1;
        apb_write(8'h04, 32'hDEAD_BEEF, apb_err);
        tb_check(apb_err === 1'b1, "CSR write rejected with PSLVERR when i_ext_sec_locked=1");
        i_ext_sec_locked = 1'b0;

        // Chờ Auto-H = AES256_K3(0^128) và key expansion (tối đa ~120 chu kỳ)
        begin
            int h_wait = 0;
            while (!dut.u_crypto_bridge.h_auto_valid && h_wait < 120) begin
                @(posedge clk_axi);
                h_wait++;
            end
        end
        tb_check(dut.u_crypto_bridge.h_auto_valid === 1'b1, "Auto-H computation valid");
        $display("[Stage 0] Auto-H=%032x (Expected=%032x)", dut.u_crypto_bridge.h_auto_reg, H_EXP); $fflush();
        tb_check(dut.u_crypto_bridge.h_auto_reg === H_EXP, "Auto-H matches AES256_K3(0^128) vector");
        tb_check(dut.u_crypto_bridge.keys_ready === 1'b1, "K1, K2, K3, H keys_ready valid");

        // Spec S8: Bật integ_enable trước meta_init phải trả SLVERR trên cả WR và RD
        apb_write(8'h00, 32'h0000_0001, apb_err);
        write_line_resp(4'h0, 32'h0000_0000, {8{64'hCAFE_BABE_0000_0001}}, br_pre);
        tb_check(br_pre === 2'b10, "Pre-init WR returns SLVERR when integ_enable=1");
        r_beat_count = 0;
        read_line(4'h0, 32'h0000_0000);
        wait_read_beats(8);
        tb_check(r_resp_captured[0] === 2'b10 && r_data_captured[0] === 64'h0,
                 "Pre-init RD returns SLVERR with zeroed RDATA");

        // Khởi tạo cây BMT qua CSR INTEG_CTRL[1]
        apb_write(8'h00, 32'h0000_0003, apb_err); // integ_enable=1, meta_init_start=1
        repeat (2) @(posedge clk_axi);
        begin
            int it = 0;
            while (!o_meta_init_done && it < 50000) begin
                @(posedge clk_axi);
                it++;
            end
            if (it >= 50000) tb_check(1'b0, "INIT: o_meta_init_done timeout");
        end
        wait_dram_idle();
        $display("[INIT] meta_init done in %0d cycles. Tree Root = 0x%016X",
                 o_meta_init_cycles, o_tree_root);
        $fflush();
        tb_check(o_meta_init_done === 1'b1 && o_meta_init_cycles > 0, "meta_init completed with cycles > 0");

        // ---------------------------------------------------------------------
        // V-1: 16 Seeded Random WR/RD Transactions across CB0..CB1, 0 SLVERR
        // ---------------------------------------------------------------------
        $display("\n[V-1 @ %0t] Seeded Random 16-Line Multi-CB WR/RD & Golden Comparison", $time);
        prng = 32'h1357_9BDF;
        t_start = $time;
        for (int i = 0; i < 16; i++) begin
            logic [31:0]  addr;
            logic [511:0] p_data;
            // Dải qua CB0 (lines 0..7) và CB1 (lines 64..71)
            addr = (i < 8) ? (i * 64) : ((64 + (i - 8)) * 64);
            for (int w = 0; w < 8; w++) begin
                prng = {prng[30:0], prng[31] ^ prng[21] ^ prng[1] ^ prng[0]};
                p_data[w*64 +: 64] = {prng, prng ^ 32'hA5A5_5A5A ^ 32'(i*8 + w)};
            end
            golden_mem[i] = p_data;
            write_line(4'(i & 4'h7), addr, p_data);
        end

        // Đọc lại theo thứ tự ngược
        for (int i = 15; i >= 0; i--) begin
            logic [31:0] addr;
            addr = (i < 8) ? (i * 64) : ((64 + (i - 8)) * 64);
            r_beat_count = 0;
            read_line(4'(i & 4'h7), addr);
            wait_read_beats(8);

            tb_check(r_resp_captured[0] === 2'b00, $sformatf("V-1 line %0d RRESP is OKAY", i));
            for (int b = 0; b < 8; b++) begin
                tb_check(r_data_captured[b] === golden_mem[i][b*64 +: 64],
                         $sformatf("V-1 line %0d beat %0d matches golden", i, b));
            end
        end
        t_end = $time;
        cyc_integ = (t_end - t_start) / (TB_TCK_PS / 1000);
        tb_check(o_integrity_fail_cnt === 32'd0 && o_tree_fail_cnt === 32'd0, "V-1: 0 SLVERR on valid transactions");

        // ---------------------------------------------------------------------
        // V-2: Flip 1 random bit in DRAM data via backdoor -> SLVERR, fail_cnt+1
        // ---------------------------------------------------------------------
        $display("\n[V-2 @ %0t] Single-Bit DRAM Data Tampering -> SLVERR & Zero Plaintext", $time);
        begin
            logic [2:0]  bg;
            logic [1:0]  bank;
            logic [16:0] row;
            logic [12:0] col;
            int prev_fail;
            int prev_wr;
            int wc;
            prev_fail = o_integrity_fail_cnt;
            prev_wr   = u_dram.n_wr;
            wc        = 0;
            write_line(4'h1, 32'h0000_0140, {8{64'hA1B2_C3D4_E5F6_0718}});
            while ((u_dram.n_wr <= prev_wr || u_dram.wq_base.size() > 0) && wc < 5000) begin
                @(posedge clk_axi);
                wc++;
            end
            wait_dram_idle();
            $fflush();

            get_dram_coords(32'h0000_0140, bg, bank, row, col);
            u_dram.backdoor_flip_bit(bg, bank, row, col, 13);

            r_beat_count = 0;
            read_line(4'h1, 32'h0000_0140);
            wait_read_beats(8);

            tb_check(r_resp_captured[0] === 2'b10, "V-2: RRESP returned SLVERR on tampered data");
            tb_check(r_data_captured[0] === 64'h0, "V-2: RDATA zeroed (no plaintext leaked)");
            tb_check(o_integrity_fail_cnt === prev_fail + 1, "V-2: integrity_fail_cnt incremented by 1");
            tb_check(o_integrity_alert === 1'b1, "V-2: o_integrity_alert asserted");

            // Khôi phục lại bit để dữ liệu line 5 luôn toàn vẹn
            u_dram.backdoor_flip_bit(bg, bank, row, col, 13);
            golden_mem[5] = {8{64'hA1B2_C3D4_E5F6_0718}};
        end

        // ---------------------------------------------------------------------
        // V-3: Flip bit in ML, CB, L1, and L2 tree nodes -> SLVERR & fail cnt
        // ---------------------------------------------------------------------
        $display("\n[V-3] Tampering in All Metadata Tiers (ML, CB, L1, L2) -> SLVERR");
        begin
            logic [2:0]  bg;
            logic [1:0]  bank;
            logic [16:0] row;
            logic [12:0] col;
            int prev_int_fail;
            int prev_tree_fail;

            flush_and_drain();

            // 3a. Lật bit trong MAC Line ML0 (0x0004_1000) của line 0
            prev_int_fail = o_integrity_fail_cnt;
            clear_meta_caches();
            get_dram_coords(32'h0004_1000, bg, bank, row, col);
            u_dram.backdoor_flip_bit(bg, bank, row, col, 3);
            r_beat_count = 0;
            read_line(4'h2, 32'h0000_0000);
            wait_read_beats(8);
            tb_check(r_resp_captured[0] === 2'b10, "V-3a: Tampered DRAM ML -> SLVERR");
            tb_check(o_integrity_fail_cnt === prev_int_fail + 1, "V-3a: integrity_fail_cnt incremented on ML tamper");
            u_dram.backdoor_flip_bit(bg, bank, row, col, 3);

            // 3b. Lật bit trong Counter Block CB0 (0x0004_0000)
            prev_tree_fail = o_tree_fail_cnt;
            clear_meta_caches();
            get_dram_coords(32'h0004_0000, bg, bank, row, col);
            u_dram.backdoor_flip_bit(bg, bank, row, col, 7);
            r_beat_count = 0;
            read_line(4'h2, 32'h0000_0000);
            wait_read_beats(8);
            tb_check(r_resp_captured[0] === 2'b10, "V-3b: Tampered CB0 -> SLVERR");
            tb_check(o_tree_fail_cnt === prev_tree_fail + 1, "V-3b: tree_fail_cnt incremented on CB0 tamper");
            u_dram.backdoor_flip_bit(bg, bank, row, col, 7);

            // 3c. Lật bit trong Tree Node L1[0] (0x0004_9000)
            prev_tree_fail = o_tree_fail_cnt;
            clear_meta_caches();
            get_dram_coords(32'h0004_9000, bg, bank, row, col);
            u_dram.backdoor_flip_bit(bg, bank, row, col, 11);
            r_beat_count = 0;
            read_line(4'h2, 32'h0000_0000);
            wait_read_beats(8);
            tb_check(r_resp_captured[0] === 2'b10, "V-3c: Tampered Tree L1[0] -> SLVERR");
            tb_check(o_tree_fail_cnt === prev_tree_fail + 1, "V-3c: tree_fail_cnt incremented on L1 tamper");
            u_dram.backdoor_flip_bit(bg, bank, row, col, 11);

            // 3d. Lật bit trong Tree Node L2[0] (0x0004_9200)
            prev_tree_fail = o_tree_fail_cnt;
            clear_meta_caches();
            get_dram_coords(32'h0004_9200, bg, bank, row, col);
            u_dram.backdoor_flip_bit(bg, bank, row, col, 5);
            r_beat_count = 0;
            read_line(4'h2, 32'h0000_0000);
            wait_read_beats(8);
            tb_check(r_resp_captured[0] === 2'b10, "V-3d: Tampered Tree L2[0] -> SLVERR");
            tb_check(o_tree_fail_cnt === prev_tree_fail + 1, "V-3d: tree_fail_cnt incremented on L2 tamper");
            u_dram.backdoor_flip_bit(bg, bank, row, col, 5);

            // Xác nhận khôi phục toàn vẹn sau clear cache
            clear_meta_caches();
            r_beat_count = 0;
            read_line(4'h2, 32'h0000_0000);
            wait_read_beats(8);
            tb_check(r_resp_captured[0] === 2'b00 && r_data_captured[0] === golden_mem[0][63:0],
                     "V-3e: Read line 0 OKAY after metadata restored");
        end

        // ---------------------------------------------------------------------
        // V-4: Splicing (copy ciphertext line 1 sang line 2) -> SLVERR & restore
        // ---------------------------------------------------------------------
        $display("\n[V-4 @ %0t] Splicing Attack (Line A Ciphertext -> Line B) -> SLVERR", $time);
        $fflush();
        begin
            logic [511:0] blk_a, blk_b_orig;
            int prev_fail;
            int prev_wr;
            int wc;
            prev_fail = o_integrity_fail_cnt;
            prev_wr   = u_dram.n_wr;
            wc        = 0;

            write_line(4'h3, 32'h0000_0080, {8{64'h2222_2222_2222_2222}});
            while ((u_dram.n_wr <= prev_wr || u_dram.wq_base.size() > 0) && wc < 5000) begin
                @(posedge clk_axi);
                wc++;
            end
            wait_dram_idle();
            $fflush();

            save_line_dram(32'h0000_0040, blk_a);
            save_line_dram(32'h0000_0080, blk_b_orig);
            restore_line_dram(32'h0000_0080, blk_a);

            r_beat_count = 0;
            read_line(4'h3, 32'h0000_0080);
            wait_read_beats(8);

            tb_check(r_resp_captured[0] === 2'b10, "V-4: Splicing detected due to address binding -> SLVERR");
            tb_check(o_integrity_fail_cnt === prev_fail + 1, "V-4: integrity_fail_cnt incremented");

            // Khôi phục bản mã gốc của line 2 để CB0 toàn vẹn cho V-7/V-8
            restore_line_dram(32'h0000_0080, blk_b_orig);
            golden_mem[2] = {8{64'h2222_2222_2222_2222}};
        end

        // ---------------------------------------------------------------------
        // V-5: True Replay Attack (save V1 snapshot, write V2, restore V1, clear MC)
        // ---------------------------------------------------------------------
        $display("\n[V-5] True Replay Attack (Full V1 Data+Metadata Snapshot Restore) -> SLVERR");
        $fflush();
        begin
            logic [511:0] v1_d, v1_ml, v1_cb, v1_l1, v1_l2;
            logic [511:0] v2_d, v2_ml, v2_cb, v2_l1, v2_l2;
            int prev_tree;
            prev_tree = o_tree_fail_cnt;

            write_line(4'h4, 32'h0000_0280, {8{64'hAAAA_BBBB_CCCC_DDDD}});
            flush_and_drain();
            save_line_dram(32'h0000_0280, v1_d);
            save_line_dram(get_ml_addr(32'h0000_0280), v1_ml);
            save_line_dram(32'h0004_0000, v1_cb);
            save_line_dram(32'h0004_9000, v1_l1);
            save_line_dram(32'h0004_9200, v1_l2);

            write_line(4'h4, 32'h0000_0280, {8{64'h1111_2222_3333_4444}});
            flush_and_drain();
            save_line_dram(32'h0000_0280, v2_d);
            save_line_dram(get_ml_addr(32'h0000_0280), v2_ml);
            save_line_dram(32'h0004_0000, v2_cb);
            save_line_dram(32'h0004_9000, v2_l1);
            save_line_dram(32'h0004_9200, v2_l2);

            // Khôi phục toàn bộ ảnh V1 (data + ML + CB + L1 + L2) nhưng giữ TREE_ROOT của V2
            restore_line_dram(32'h0000_0280, v1_d);
            restore_line_dram(get_ml_addr(32'h0000_0280), v1_ml);
            restore_line_dram(32'h0004_0000, v1_cb);
            restore_line_dram(32'h0004_9000, v1_l1);
            restore_line_dram(32'h0004_9200, v1_l2);
            clear_meta_caches();

            r_beat_count = 0;
            read_line(4'h4, 32'h0000_0280);
            wait_read_beats(8);

            tb_check(r_resp_captured[0] === 2'b10 && o_tree_fail_cnt === prev_tree + 1,
                     "V-5: Replayed V1 state rejected by BMT root check -> SLVERR");

            // Khôi phục V2 khớp on-chip TREE_ROOT để trạng thái CB0 sạch sẽ cho V-6..V-8
            restore_line_dram(32'h0000_0280, v2_d);
            restore_line_dram(get_ml_addr(32'h0000_0280), v2_ml);
            restore_line_dram(32'h0004_0000, v2_cb);
            restore_line_dram(32'h0004_9000, v2_l1);
            restore_line_dram(32'h0004_9200, v2_l2);
            clear_meta_caches();
            golden_mem[10] = {8{64'h1111_2222_3333_4444}};
        end

        // ---------------------------------------------------------------------
        // V-6: Replay data + MAC only, keeping new CB -> SLVERR by MAC
        // ---------------------------------------------------------------------
        $display("\n[V-6] Replay Data + MAC Only with Current CB -> SLVERR by MAC");
        $fflush();
        begin
            logic [511:0] v1_d6, v1_ml6, v2_d6, v2_ml6;
            int prev_fail;
            int prev_tree;
            prev_fail = o_integrity_fail_cnt;
            prev_tree = o_tree_fail_cnt;

            write_line(4'h5, 32'h0000_0300, {8{64'h1234_5678_9ABC_DEF0}});
            flush_and_drain();
            save_line_dram(32'h0000_0300, v1_d6);
            save_line_dram(get_ml_addr(32'h0000_0300), v1_ml6);

            write_line(4'h5, 32'h0000_0300, {8{64'hFEDC_BA98_7654_3210}});
            flush_and_drain();
            save_line_dram(32'h0000_0300, v2_d6);
            save_line_dram(get_ml_addr(32'h0000_0300), v2_ml6);

            // Chỉ khôi phục (data, ML) của V1, giữ CB/Tree ở V2
            restore_line_dram(32'h0000_0300, v1_d6);
            restore_line_dram(get_ml_addr(32'h0000_0300), v1_ml6);
            clear_meta_caches();

            r_beat_count = 0;
            read_line(4'h5, 32'h0000_0300);
            wait_read_beats(8);

            tb_check(r_resp_captured[0] === 2'b10, "V-6: Old (data, MAC) with new CB rejected -> SLVERR");
            tb_check(o_integrity_fail_cnt === prev_fail + 1 && o_tree_fail_cnt === prev_tree,
                     "V-6: integrity_fail_cnt incremented, tree_fail_cnt unchanged");

            restore_line_dram(32'h0000_0300, v2_d6);
            restore_line_dram(get_ml_addr(32'h0000_0300), v2_ml6);
            clear_meta_caches();
            golden_mem[12] = {8{64'hFEDC_BA98_7654_3210}};
        end

        // ---------------------------------------------------------------------
        // V-7: Minor overflow on CB0 -> REENC_FSM while CB1 traffic proceeds
        // ---------------------------------------------------------------------
        $display("\n[V-7] Minor Overflow & Seamless Re-Encryption + Independent CB Traffic");
        $fflush();
        begin
            logic [511:0] sib18, sib19, line20_new;
            int prev_reenc;
            logic cb1_ok_during_or_after;

            sib18 = {8{64'hD180_1818_1818_1818}};
            sib19 = {8{64'hD190_1919_1919_1919}};
            line20_new = {8{64'h0707_0707_1234_5678}};

            write_line(4'h6, 32'h0000_0480, sib18);
            write_line(4'h6, 32'h0000_04C0, sib19);
            write_line(4'h6, 32'h0000_0500, {8{64'hD200_2020_2020_2020}});
            $display("[V-7-DBG] sib18/19/line20 pre-writes done @ %0t", $time);
            $fflush();

`ifdef QSHIELD_TEST
            wait_dram_idle();
            @(negedge clk_axi);
            i_test_force_minor_valid <= 1'b1;
            i_test_force_minor_addr  <= 64'h0000_0500;
            i_test_force_minor_val   <= 7'd127;
            @(posedge clk_axi);
            @(negedge clk_axi);
            i_test_force_minor_valid <= 1'b0;
            begin
                int fmt;
                fmt = 0;
                while (!o_test_force_minor_done && fmt < 20000) begin
                    @(negedge clk_axi);
                    fmt++;
                end
                if (fmt >= 20000) tb_check(1'b0, "V-7: o_test_force_minor_done timeout");
            end
            repeat (2) @(posedge clk_axi);
            $display("[V-7-DBG] force_minor done @ %0t", $time);
            $fflush();
`else
            for (int k = 0; k < 126; k++) begin
                write_line(4'h6, 32'h0000_0500, {8{64'(k + 100)}});
            end
`endif

            prev_reenc = o_reencrypt_events;
            // Ghi tràn minor == 127 trên line 20 (CB0) -> kích hoạt REENC_FSM
            write_line(4'h6, 32'h0000_0500, line20_new);
            $display("[V-7-DBG] overflow write done @ %0t, reenc=%0d", $time, o_reencrypt_events);
            $fflush();

            // Giao dịch ngay tới CB khác (CB1: 0x1000) trong khi REENC đang chạy nền trên CB0
            write_line(4'h7, 32'h0000_1000, {8{64'hCAFE_F00D_1234_5678}});
            r_beat_count = 0;
            read_line(4'h7, 32'h0000_1000);
            wait_read_beats(8);
            cb1_ok_during_or_after = (r_resp_captured[0] === 2'b00 && r_data_captured[0] === 64'hCAFE_F00D_1234_5678);
            tb_check(cb1_ok_during_or_after, "V-7: Independent CB1 WR/RD proceeds cleanly");
            golden_mem[16] = {8{64'hCAFE_F00D_1234_5678}};
            $fflush();

            // Chờ tái mã hóa nền CB0 hoàn tất
            wait_dram_idle();
            $display("[V-7-DBG] wait_dram_idle done @ %0t, crypto_busy=%b", $time, o_crypto_busy);
            $fflush();
            tb_check(o_reencrypt_events === prev_reenc + 1, "V-7: reencrypt_events incremented by 1");

            // Đọc kiểm tra line tràn (0x0500) và các sibling lines (0x0480, 0x04C0, 0x0000) sau tái mã hóa
            r_beat_count = 0; read_line(4'h6, 32'h0000_0500); wait_read_beats(8);
            tb_check(r_resp_captured[0] === 2'b00 && r_data_captured[0] === line20_new[63:0],
                     "V-7: Overflowed line 0x0500 intact after major rollover");

            r_beat_count = 0; read_line(4'h6, 32'h0000_0480); wait_read_beats(8);
            tb_check(r_resp_captured[0] === 2'b00 && r_data_captured[0] === sib18[63:0],
                     "V-7: Sibling line 0x0480 intact after CB0 re-encryption");

            r_beat_count = 0; read_line(4'h6, 32'h0000_04C0); wait_read_beats(8);
            tb_check(r_resp_captured[0] === 2'b00 && r_data_captured[0] === sib19[63:0],
                     "V-7: Sibling line 0x04C0 intact after CB0 re-encryption");

            r_beat_count = 0; read_line(4'h0, 32'h0000_0000); wait_read_beats(8);
            tb_check(r_resp_captured[0] === 2'b00 && r_data_captured[0] === golden_mem[0][63:0],
                     "V-7: Sibling line 0x0000 intact after CB0 re-encryption");
        end

        // ---------------------------------------------------------------------
        // V-8: meta_flush & dump DRAM BMT blocks for Python bit-exact verify
        // ---------------------------------------------------------------------
        $display("\n[V-8] Metadata Flush Consistency & Python Merkle Tree Verification");
        $fflush();
        begin
            int rfd;
            logic [31:0] root_lo, root_hi;
            flush_and_drain();

            apb_read(8'h34, root_lo, apb_err);
            apb_read(8'h38, root_hi, apb_err);
            tb_check(o_meta_flush_done === 1'b1, "V-8: meta_flush completed");
            tb_check(o_tree_root !== 64'h0 && {root_hi, root_lo} === o_tree_root,
                     "V-8: CSR TREE_ROOT matches o_tree_root");

            dump_dram_bmt("build/top_bmt_dram_dump.txt");
            rfd = $fopen("build/top_bmt_hw_root.txt", "w");
            if (rfd != 0) begin
                $fdisplay(rfd, "%016x", o_tree_root);
                $fclose(rfd);
            end
        end

        // ---------------------------------------------------------------------
        // V-9: MC + ML Set-Conflict Pressure (> 4 ways in Set 0/8 & > 2 ways ML)
        // ---------------------------------------------------------------------
        $display("\n[V-9 @ %0t] BMT & ML Cache Set-Conflict Pressure + Random Backpressure", $time);
        $fflush();
        begin
            int prev_misses;
            prev_misses = o_mc_miss_cnt;
            for (int s = 0; s < 10; s++) begin
                int cb_id;
                logic [31:0] test_addr;
                cb_id = (s < 8) ? (s * 8) : ((s - 8) * 8 + 4); // 0,8,16,24,32,40,48,56 (set 0/8) + 4,12
                test_addr = 32'(cb_id * 64 * 64 + 32'h0000_0040);
                write_line(4'(s & 4'h7), test_addr, {8{64'(s + 32'h5000)}});
            end

            for (int s = 0; s < 10; s++) begin
                int cb_id;
                logic [31:0] test_addr;
                cb_id = (s < 8) ? (s * 8) : ((s - 8) * 8 + 4);
                test_addr = 32'(cb_id * 64 * 64 + 32'h0000_0040);
                r_beat_count = 0;
                read_line(4'(s & 4'h7), test_addr);
                wait_read_beats(8);
                tb_check(r_resp_captured[0] === 2'b00 && r_data_captured[0] === 64'(s + 32'h5000),
                         $sformatf("V-9: Pressure CB%0d read OKAY & intact", cb_id));
            end
            tb_check(o_mc_miss_cnt > prev_misses, "V-9: mc_miss_cnt increased under set-conflict pressure");
        end

        // ---------------------------------------------------------------------
        // V-10: Disable Integrity -> Identical 16-line XTS baseline + overhead
        // ---------------------------------------------------------------------
        $display("\n[V-10 @ %0t] Integrity Disabled Mode (Pure AES-256-XTS Backward Compatibility)", $time);
        $fflush();
        begin
            int prev_mrd, prev_mwr;
            apb_write(8'h00, 32'h0000_0000, apb_err); // Tắt integ_enable qua CSR
            wait_dram_idle();
            prev_mrd = o_meta_rd_cnt;
            prev_mwr = o_meta_wr_cnt;

            t_start = $time;
            for (int i = 0; i < 16; i++) begin
                logic [31:0] addr;
                addr = (i < 8) ? (i * 64) : ((64 + (i - 8)) * 64);
                write_line(4'(i & 4'h7), addr, golden_mem[i] ^ {8{64'h0F0F_0F0F_0F0F_0F0F}});
            end
            for (int i = 15; i >= 0; i--) begin
                logic [31:0] addr;
                addr = (i < 8) ? (i * 64) : ((64 + (i - 8)) * 64);
                r_beat_count = 0;
                read_line(4'(i & 4'h7), addr);
                wait_read_beats(8);
                tb_check(r_resp_captured[0] === 2'b00 &&
                         r_data_captured[0] === (golden_mem[i][63:0] ^ 64'h0F0F_0F0F_0F0F_0F0F),
                         $sformatf("V-10: Pure XTS line %0d OKAY", i));
            end
            t_end = $time;
            cyc_no_integ = (t_end - t_start) / (TB_TCK_PS / 1000);
            tb_check(o_meta_rd_cnt === prev_mrd && o_meta_wr_cnt === prev_mwr,
                     "V-10: Zero metadata traffic when integ_enable=0");
        end

        // ---------------------------------------------------------------------
        // Thống kê hiệu năng & Báo cáo kết quả
        // ---------------------------------------------------------------------
        $display("\n================================================================================");
        $display("  [INTEG_PERF] PERFORMANCE & HARDWARE OVERHEAD TELEMETRY SUMMARY");
        $display("================================================================================");
        $display("[INTEG_PERF] cycles_integ=%0d cycles_no_integ=%0d", cyc_integ, cyc_no_integ);
        $display("[INTEG_PERF] meta_rd_cnt=%0d meta_wr_cnt=%0d reencrypt_events=%0d",
                 o_meta_rd_cnt, o_meta_wr_cnt, o_reencrypt_events);
        $display("[INTEG_PERF] mc_hit_cnt=%0d mc_miss_cnt=%0d mc_hit_rate=%0.1f%%",
                 o_mc_hit_cnt, o_mc_miss_cnt,
                 (o_mc_hit_cnt + o_mc_miss_cnt > 0) ? (real'(o_mc_hit_cnt) * 100.0 / real'(o_mc_hit_cnt + o_mc_miss_cnt)) : 0.0);
        $display("================================================================================");

        $display("[META_AXI_AUDIT] AW id8=%0d (logic=%0d) id9=%0d (logic=%0d) id10=%0d (logic=%0d)",
                 axi_aw_id8_cnt, logic_bmt_wr_cnt, axi_aw_id9_cnt, logic_ml_wr_cnt, axi_aw_id10_cnt, logic_reenc_wr_cnt);
        $display("[META_AXI_AUDIT] AR id8=%0d (logic=%0d) id9=%0d (logic=%0d) id10=%0d (logic=%0d)",
                 axi_ar_id8_cnt, logic_bmt_rd_cnt, axi_ar_id9_cnt, logic_ml_rd_cnt, axi_ar_id10_cnt, logic_reenc_rd_cnt);
        tb_check(axi_aw_id8_cnt  === logic_bmt_wr_cnt,   $sformatf("META_AXI_AUDIT: BMT AW id8=%0d == logic=%0d", axi_aw_id8_cnt, logic_bmt_wr_cnt));
        tb_check(axi_aw_id9_cnt  === logic_ml_wr_cnt,    $sformatf("META_AXI_AUDIT: ML AW id9=%0d == logic=%0d", axi_aw_id9_cnt, logic_ml_wr_cnt));
        tb_check(axi_aw_id10_cnt === logic_reenc_wr_cnt, $sformatf("META_AXI_AUDIT: REENC AW id10=%0d == logic=%0d", axi_aw_id10_cnt, logic_reenc_wr_cnt));
        tb_check(axi_ar_id8_cnt  === logic_bmt_rd_cnt,   $sformatf("META_AXI_AUDIT: BMT AR id8=%0d == logic=%0d", axi_ar_id8_cnt, logic_bmt_rd_cnt));
        tb_check(axi_ar_id9_cnt  === logic_ml_rd_cnt,    $sformatf("META_AXI_AUDIT: ML AR id9=%0d == logic=%0d", axi_ar_id9_cnt, logic_ml_rd_cnt));
        tb_check(axi_ar_id10_cnt === logic_reenc_rd_cnt, $sformatf("META_AXI_AUDIT: REENC AR id10=%0d == logic=%0d", axi_ar_id10_cnt, logic_reenc_rd_cnt));

        tb_report();
        $finish;
    end

endmodule
