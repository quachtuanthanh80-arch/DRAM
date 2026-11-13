// File: qshield_axi_crypto_bridge.sv
// Chức năng: Cầu nối AXI4 mật mã hoá AES-256-XTS và toàn vẹn Carter-Wegman MAC / Bonsai Merkle Tree ngoài lõi DDR5.

`timescale 1ns / 1ps

module qshield_axi_crypto_bridge #(
    parameter int AXI_ID_WIDTH    = 4,
    parameter int AXI_ADDR_WIDTH  = 32,
    parameter int AXI_DATA_WIDTH  = 64,
    parameter int AXI_STRB_WIDTH  = AXI_DATA_WIDTH / 8,
    parameter int AXI_LEN_WIDTH   = 8,
    parameter int AXI_QOS_WIDTH   = 4,
    parameter logic [63:0] PROT_BASE_DEFAULT  = 64'h0000_0000_0000_0000,
    parameter logic [63:0] PROT_LINES_DEFAULT = 64'd4096
)(
    input  logic                                         clk,
    input  logic                                         rst_n,

    // Giao diện điều khiển mật mã AES-256-XTS (Đặc tả S8)
    input  logic                                         i_enc_enable,
    input  logic                                         i_keys_valid,
    input  logic [255:0]                                 i_key1,
    input  logic [255:0]                                 i_key2,
    input  logic [3:0]                                   i_asid,
    input  logic [18:0]                                  i_epoch,
    output logic                                         o_crypto_busy,
    output logic [15:0]                                  o_crypto_reject_cnt,
    output logic [15:0]                                  o_crypto_err_cnt,

    // Giao diện điều khiển toàn vẹn & Bonsai Merkle Tree (Đặc tả S8 & D14)
    input  logic                                         i_integ_enable,
    input  logic                                         i_k3_valid,
    input  logic [255:0]                                 i_k3,
    input  logic [127:0]                                 i_h,
    input  logic                                         i_meta_init_start,
    output logic                                         o_meta_init_done,
    output logic [31:0]                                  o_meta_init_cycles,
    input  logic                                         i_meta_flush_start,
    output logic                                         o_meta_flush_done,
    input  logic                                         i_cache_clear,
    input  logic [63:0]                                  i_prot_base,
    input  logic [63:0]                                  i_prot_lines,
    output logic [63:0]                                  o_tree_root,
    output logic [31:0]                                  o_integrity_fail_cnt,
    output logic [31:0]                                  o_tree_fail_cnt,
    output logic [31:0]                                  o_reencrypt_events,
    output logic [31:0]                                  o_mc_hit_cnt,
    output logic [31:0]                                  o_mc_miss_cnt,
    output logic [31:0]                                  o_meta_rd_cnt,
    output logic [31:0]                                  o_meta_wr_cnt,
    output logic                                         o_integrity_alert,

    // Giao diện APB4 Slave cấu hình CSR toàn vẹn & khóa cứng (Đặc tả S8)
    input  logic                                         i_sec_locked = 1'b0,
    input  logic                                         psel = 1'b0,
    input  logic                                         penable = 1'b0,
    input  logic                                         pwrite = 1'b0,
    input  logic [7:0]                                   paddr = 8'h0,
    input  logic [31:0]                                  pwdata = 32'h0,
    input  logic [2:0]                                   pprot = 3'b0,
    output logic [31:0]                                  prdata,
    output logic                                         pready,
    output logic                                         pslverr,

    // Giao diện AXI4 Slave (Từ Master / Host)
    input  logic [AXI_ID_WIDTH-1:0]                      s_axi_awid,
    input  logic [AXI_ADDR_WIDTH-1:0]                    s_axi_awaddr,
    input  logic [AXI_LEN_WIDTH-1:0]                     s_axi_awlen,
    input  logic [2:0]                                   s_axi_awsize,
    input  logic [1:0]                                   s_axi_awburst,
    input  logic [AXI_QOS_WIDTH-1:0]                     s_axi_awqos,
    input  logic                                         s_axi_awvalid,
    output logic                                         s_axi_awready,

    input  logic [AXI_DATA_WIDTH-1:0]                    s_axi_wdata,
    input  logic [AXI_STRB_WIDTH-1:0]                    s_axi_wstrb,
    input  logic                                         s_axi_wlast,
    input  logic                                         s_axi_wvalid,
    output logic                                         s_axi_wready,

    output logic [AXI_ID_WIDTH-1:0]                      s_axi_bid,
    output logic [1:0]                                   s_axi_bresp,
    output logic                                         s_axi_bvalid,
    input  logic                                         s_axi_bready,

    input  logic [AXI_ID_WIDTH-1:0]                      s_axi_arid,
    input  logic [AXI_ADDR_WIDTH-1:0]                    s_axi_araddr,
    input  logic [AXI_LEN_WIDTH-1:0]                     s_axi_arlen,
    input  logic [2:0]                                   s_axi_arsize,
    input  logic [1:0]                                   s_axi_arburst,
    input  logic [AXI_QOS_WIDTH-1:0]                     s_axi_arqos,
    input  logic                                         s_axi_arvalid,
    output logic                                         s_axi_arready,

    output logic [AXI_ID_WIDTH-1:0]                      s_axi_rid,
    output logic [AXI_DATA_WIDTH-1:0]                    s_axi_rdata,
    output logic [1:0]                                   s_axi_rresp,
    output logic                                         s_axi_rlast,
    output logic                                         s_axi_rvalid,
    input  logic                                         s_axi_rready,

    // Giao diện AXI4 Master (Nối vào Slave của lõi axi_ddr5_mc_top)
    output logic [AXI_ID_WIDTH-1:0]                      m_axi_awid,
    output logic [AXI_ADDR_WIDTH-1:0]                    m_axi_awaddr,
    output logic [AXI_LEN_WIDTH-1:0]                     m_axi_awlen,
    output logic [2:0]                                   m_axi_awsize,
    output logic [1:0]                                   m_axi_awburst,
    output logic [AXI_QOS_WIDTH-1:0]                     m_axi_awqos,
    output logic                                         m_axi_awvalid,
    input  logic                                         m_axi_awready,

    output logic [AXI_DATA_WIDTH-1:0]                    m_axi_wdata,
    output logic [AXI_STRB_WIDTH-1:0]                    m_axi_wstrb,
    output logic                                         m_axi_wlast,
    output logic                                         m_axi_wvalid,
    input  logic                                         m_axi_wready,

    input  logic [AXI_ID_WIDTH-1:0]                      m_axi_bid,
    input  logic [1:0]                                   m_axi_bresp,
    input  logic                                         m_axi_bvalid,
    output logic                                         m_axi_bready,

    output logic [AXI_ID_WIDTH-1:0]                      m_axi_arid,
    output logic [AXI_ADDR_WIDTH-1:0]                    m_axi_araddr,
    output logic [AXI_LEN_WIDTH-1:0]                     m_axi_arlen,
    output logic [2:0]                                   m_axi_arsize,
    output logic [1:0]                                   m_axi_arburst,
    output logic [AXI_QOS_WIDTH-1:0]                     m_axi_arqos,
    output logic                                         m_axi_arvalid,
    input  logic                                         m_axi_arready,

    input  logic [AXI_ID_WIDTH-1:0]                      m_axi_rid,
    input  logic [AXI_DATA_WIDTH-1:0]                    m_axi_rdata,
    input  logic [1:0]                                   m_axi_rresp,
    input  logic                                         m_axi_rlast,
    input  logic                                         m_axi_rvalid,
    output logic                                         m_axi_rready
`ifdef QSHIELD_TEST
    ,
    // Đường nạp cưỡng bức minor gần tràn (127) phục vụ kiểm chứng V-7 (Đặc tả S7)
    input  logic                                         i_test_force_minor_valid = 1'b0,
    input  logic [63:0]                                  i_test_force_minor_addr  = 64'h0,
    input  logic [6:0]                                   i_test_force_minor_val   = 7'd127,
    output logic                                         o_test_force_minor_done
`endif
);
    import aes_pkg::*;

    function automatic logic [255:0] rev256(input logic [255:0] x);
        for (int i = 0; i < 32; i++) rev256[i*8 +: 8] = x[(31 - i)*8 +: 8];
    endfunction
    function automatic logic [127:0] rev128(input logic [127:0] x);
        for (int i = 0; i < 16; i++) rev128[i*8 +: 8] = x[(15 - i)*8 +: 8];
    endfunction

    //-------------------------------------------------------------------------
    // 0. Bộ thanh ghi cấu hình toàn vẹn APB4 CSR & Thiết lập vùng nhớ bảo vệ
    //-------------------------------------------------------------------------
    wire          csr_integ_enable;
    wire          csr_meta_init_start;
    wire          csr_meta_flush_start;
    wire  [63:0]  csr_prot_base;
    wire  [5:0]   csr_prot_lines_log2;
    wire  [255:0] csr_k3;
    wire          csr_k3_valid;

    qshield_integrity_csr #(
        .APB_ADDR_WIDTH (8),
        .APB_DATA_WIDTH (32)
    ) u_integ_csr (
        .pclk                 (clk),
        .presetn              (rst_n),
        .psel                 (psel),
        .penable              (penable),
        .pwrite               (pwrite),
        .paddr                (paddr),
        .pwdata               (pwdata),
        .pprot                (pprot),
        .prdata               (prdata),
        .pready               (pready),
        .pslverr              (pslverr),
        .i_sec_locked         (i_sec_locked),
        .o_integ_enable       (csr_integ_enable),
        .o_meta_init_start    (csr_meta_init_start),
        .i_meta_init_done     (o_meta_init_done),
        .o_meta_flush_start   (csr_meta_flush_start),
        .i_meta_flush_done    (o_meta_flush_done),
        .o_prot_base          (csr_prot_base),
        .o_prot_lines_log2    (csr_prot_lines_log2),
        .o_k3                 (csr_k3),
        .o_k3_valid           (csr_k3_valid),
        .i_tree_root          (o_tree_root),
        .i_integrity_fail_cnt (o_integrity_fail_cnt),
        .i_tree_fail_cnt      (o_tree_fail_cnt),
        .i_reencrypt_events   (o_reencrypt_events),
        .i_mc_hit_cnt         (o_mc_hit_cnt),
        .i_mc_miss_cnt        (o_mc_miss_cnt),
        .i_meta_rd_cnt        (o_meta_rd_cnt),
        .i_meta_wr_cnt        (o_meta_wr_cnt)
    );

    // Đăng ký 1 nhịp tín hiệu kích hoạt & khóa k3 từ CSR để tách chuỗi định thời sang u_mc_core;
    // giữ nguyên xung 1-chu-kỳ meta_init_start/meta_flush_start để không trễ pha xóa cờ done.
    logic         csr_integ_enable_q;
    logic [255:0] csr_k3_q;
    logic         csr_k3_valid_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            csr_integ_enable_q <= 1'b0;
            csr_k3_q           <= 256'h0;
            csr_k3_valid_q     <= 1'b0;
        end else begin
            csr_integ_enable_q <= csr_integ_enable;
            csr_k3_q           <= csr_k3;
            csr_k3_valid_q     <= csr_k3_valid;
        end
    end

    // Kết hợp điều khiển từ cổng trực tiếp (tương thích TB cũ) và thanh ghi CSR APB
    wire          eff_integ_enable     = i_integ_enable || csr_integ_enable_q;
    wire          eff_k3_valid         = csr_k3_valid_q ? 1'b1 : i_k3_valid;
    wire [255:0]  eff_k3_w             = csr_k3_valid_q ? csr_k3_q : i_k3;
    wire          eff_meta_init_start  = i_meta_init_start || csr_meta_init_start;
    wire          eff_meta_flush_start = i_meta_flush_start || csr_meta_flush_start;

    wire [63:0] csr_prot_lines_dec = (csr_prot_lines_log2 <= 6'd20) ?
                                     (64'd1 << csr_prot_lines_log2) : PROT_LINES_DEFAULT;
    wire [63:0] eff_prot_base_w  = (i_prot_base != 64'd0) ? i_prot_base : csr_prot_base;
    wire [63:0] eff_prot_lines_w = (i_prot_lines != 64'd0) ? i_prot_lines :
                                   (csr_integ_enable_q ? csr_prot_lines_dec : PROT_LINES_DEFAULT);
    wire [63:0] eff_prot_bytes_w = eff_prot_lines_w * 64;
    wire [63:0] eff_prot_end_w   = eff_prot_base_w + eff_prot_bytes_w;

    wire [63:0] eff_num_cb_w   = eff_prot_lines_w / 64;
    wire [63:0] eff_cb_bytes_w = eff_num_cb_w * 64;
    wire [63:0] eff_cb_base_w  = eff_prot_end_w;

    wire [63:0] eff_num_ml_w   = eff_prot_lines_w / 8;
    wire [63:0] eff_ml_bytes_w = eff_num_ml_w * 64;
    wire [63:0] eff_ml_base_w  = eff_cb_base_w + eff_cb_bytes_w;

    wire [63:0] eff_tn_base_w  = eff_ml_base_w + eff_ml_bytes_w;
    wire [63:0] eff_tn_bytes_w = ((eff_num_cb_w / 8) + ((eff_num_cb_w / 8) / 8)) * 64;
    wire [63:0] eff_meta_end_w = eff_tn_base_w + eff_tn_bytes_w;

    // Register CSR-derived protection bounds to break csr_prot_lines_log2->u_mc_core timing path
    logic [63:0] eff_prot_base;
    logic [63:0] eff_prot_lines;
    logic [63:0] eff_prot_end;
    logic [63:0] eff_cb_base;
    logic [63:0] eff_ml_base;
    logic [63:0] eff_tn_base;
    logic [63:0] eff_meta_end;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            eff_prot_base  <= PROT_BASE_DEFAULT;
            eff_prot_lines <= PROT_LINES_DEFAULT;
            eff_prot_end   <= PROT_BASE_DEFAULT + (PROT_LINES_DEFAULT * 64);
            eff_cb_base    <= PROT_BASE_DEFAULT + (PROT_LINES_DEFAULT * 64);
            eff_ml_base    <= PROT_BASE_DEFAULT + (PROT_LINES_DEFAULT * 64) + ((PROT_LINES_DEFAULT / 64) * 64);
            eff_tn_base    <= PROT_BASE_DEFAULT + (PROT_LINES_DEFAULT * 64) + ((PROT_LINES_DEFAULT / 64) * 64) + ((PROT_LINES_DEFAULT / 8) * 64);
            eff_meta_end   <= PROT_BASE_DEFAULT + (PROT_LINES_DEFAULT * 64) + ((PROT_LINES_DEFAULT / 64) * 64) + ((PROT_LINES_DEFAULT / 8) * 64) +
                              (((PROT_LINES_DEFAULT / 512) + (PROT_LINES_DEFAULT / 4096)) * 64);
        end else begin
            eff_prot_base  <= eff_prot_base_w;
            eff_prot_lines <= eff_prot_lines_w;
            eff_prot_end   <= eff_prot_end_w;
            eff_cb_base    <= eff_cb_base_w;
            eff_ml_base    <= eff_ml_base_w;
            eff_tn_base    <= eff_tn_base_w;
            eff_meta_end   <= eff_meta_end_w;
        end
    end

    //-------------------------------------------------------------------------
    // 1. Mở rộng khoá AES-256 (Key Expansion) cho K1, K2 và K3
    //-------------------------------------------------------------------------
    logic         k1_valid, k2_valid, k3_valid;
    logic [15*128-1:0] k1_round_keys;
    logic [15*128-1:0] k2_round_keys;
    logic [15*128-1:0] k3_round_keys;

    logic [255:0] eff_k3_r;
    logic         k3_eq_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            eff_k3_r <= 256'h0;
            k3_eq_q  <= 1'b0;
        end else begin
            eff_k3_r <= eff_k3_w;
            k3_eq_q  <= (eff_k3_w == eff_k3_r);
        end
    end

    logic [127:0] h_auto_reg;
    logic         h_auto_valid;
    wire [255:0]  eff_k3     = eff_k3_r;
    wire          k3_stable  = eff_k3_valid && k3_valid && k3_eq_q;
    wire  [127:0] eff_h      = (i_h != 128'h0) ? i_h : h_auto_reg;
    wire          k3_h_ready = k3_stable && ((i_h != 128'h0) || h_auto_valid);

    aes256_key_expand u_k1_expand (
        .clk         (clk),
        .rst_n       (rst_n),
        .i_key       (i_key1),
        .o_valid     (k1_valid),
        .o_round_keys(k1_round_keys)
    );

    aes256_key_expand u_k2_expand (
        .clk         (clk),
        .rst_n       (rst_n),
        .i_key       (i_key2),
        .o_valid     (k2_valid),
        .o_round_keys(k2_round_keys)
    );

    // K3 đảo thứ tự byte sang chuẩn NIST MSB-first giống BMT engine và vector Python
    aes256_key_expand u_k3_expand (
        .clk         (clk),
        .rst_n       (rst_n),
        .i_key       (rev256(eff_k3)),
        .o_valid     (k3_valid),
        .o_round_keys(k3_round_keys)
    );

    wire keys_ready = i_keys_valid && k1_valid && k2_valid &&
                      (!eff_integ_enable || k3_h_ready);

    logic [127:0] k1_rk [15];
    for (genvar k = 0; k < 15; k++) begin : g_unpack_k1
        assign k1_rk[k] = k1_round_keys[k*128 +: 128];
    end

    logic [127:0] k3_rk [15];
    for (genvar m = 0; m < 15; m++) begin : g_unpack_k3
        assign k3_rk[m] = k3_round_keys[m*128 +: 128];
    end

    //-------------------------------------------------------------------------
    // 2. Bộ đếm lỗi, từ chối và viễn trắc toàn vẹn
    //-------------------------------------------------------------------------
    logic [15:0] reject_cnt_reg;
    logic [15:0] err_cnt_reg;
    assign o_crypto_reject_cnt = reject_cnt_reg;
    assign o_crypto_err_cnt    = err_cnt_reg;

    logic [31:0] reg_integ_fail_cnt;
    logic [31:0] reg_tree_fail_cnt;
    logic [31:0] reg_reencrypt_events;
    logic [31:0] reg_mc_hit_cnt;
    logic [31:0] reg_mc_miss_cnt;
    logic [31:0] reg_meta_rd_cnt;
    logic [31:0] reg_meta_wr_cnt;
    logic        reg_integ_alert;
    logic        bmt_saw_dram_rd;

    assign o_integrity_fail_cnt = reg_integ_fail_cnt;
    assign o_tree_fail_cnt      = bmt_tree_fail_cnt_out;
    assign o_reencrypt_events   = reg_reencrypt_events;
    assign o_mc_hit_cnt         = reg_mc_hit_cnt;
    assign o_mc_miss_cnt        = reg_mc_miss_cnt;
    assign o_meta_rd_cnt        = reg_meta_rd_cnt;
    assign o_meta_wr_cnt        = reg_meta_wr_cnt;
    assign o_integrity_alert    = reg_integ_alert;

    wire b_err = m_axi_bvalid && m_axi_bready && (m_axi_bid[3] == 1'b0) && m_axi_bresp[1];
    wire r_err = m_axi_rvalid && m_axi_rready && (m_axi_rid[3] == 1'b0) && m_axi_rresp[1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            err_cnt_reg <= 16'h0;
        end else if ((b_err || r_err) && (err_cnt_reg != 16'hFFFF)) begin
            err_cnt_reg <= err_cnt_reg + 1'b1;
        end
    end

    //-------------------------------------------------------------------------
    // 3. Động cơ Bonsai Merkle Tree (BMT 8-ary) và Giao diện DRAM Metadata
    //-------------------------------------------------------------------------
    logic         bmt_verify_valid;
    logic [63:0]  bmt_verify_addr;
    wire          bmt_verify_ready;
    wire          bmt_verify_done;
    wire          bmt_verify_pass;
    wire          bmt_verify_fail;
    wire  [511:0] bmt_cb_data;
    wire  [5:0]   bmt_cb_slot;

    logic         bmt_update_valid;
    logic [63:0]  bmt_update_addr;
    logic [511:0] bmt_update_cb_data;
    wire          bmt_update_ready;
    wire          bmt_update_done;

    wire          bmt_dram_rd_valid;
    wire  [63:0]  bmt_dram_rd_addr;
    logic         bmt_dram_rd_ready;
    logic         bmt_dram_rd_valid_in;
    logic [511:0] bmt_dram_rd_data_in;

    wire          bmt_dram_wr_valid;
    wire  [63:0]  bmt_dram_wr_addr;
    wire  [511:0] bmt_dram_wr_data;
    logic         bmt_dram_wr_ready;

    wire  [63:0]  bmt_tree_root;
    wire  [31:0]  bmt_tree_fail_cnt_out;
    wire          bmt_integ_alert_out;
    wire          bmt_init_done;
    wire  [31:0]  bmt_init_cycles;
    wire          bmt_flush_done;

    assign o_tree_root = bmt_tree_root;

    // Trạng thái giữ cờ hoàn thành khởi tạo & flush (chờ rút cạn meta_fifo & BRESP)
    logic        reg_meta_init_done;
    logic        reg_meta_init_ever_done;
    logic        bmt_init_seen;
    logic [31:0] reg_meta_init_cycles;
    logic        reg_meta_flush_done;
    logic        bmt_flush_seen;
    logic        ml_flush_busy;
    logic        ml_flush_done_seen;

    localparam int META_FIFO_D = 64;
    (* ram_style = "distributed" *) logic [63:0]  meta_fifo_addr [META_FIFO_D];
    (* ram_style = "distributed" *) logic [511:0] meta_fifo_data [META_FIFO_D];
    (* ram_style = "distributed" *) logic [3:0]   meta_fifo_id   [META_FIFO_D];
    logic [5:0]   meta_fifo_wptr;
    logic [5:0]   meta_fifo_rptr;
    logic [6:0]   meta_fifo_cnt;

    logic         meta_rd_ar_pending;
    logic [63:0]  meta_rd_addr;
    logic [3:0]   meta_rd_id;
    logic         meta_rd_active;
    logic [1:0]   meta_rd_owner; // 0: BMT, 1: ML, 2: REENC
    logic [7:0]   meta_wr_inflight;

    logic         meta_aw_valid;
    logic         meta_w_valid;
    logic [63:0]  meta_wr_addr;
    logic [511:0] meta_wr_data;
    logic [3:0]   meta_wr_id;
    logic [2:0]   meta_wr_beat;

    // Theo dõi quyền sở hữu kênh AW+W master (chống đan xen W beat giữa user và metadata)
    typedef enum logic [1:0] {
        WR_NONE = 2'd0,
        WR_USER = 2'd1,
        WR_META = 2'd2
    } wr_bus_owner_t;
    wr_bus_owner_t wr_bus_owner;
    logic          meta_aw_done_q;
    logic          meta_w_done_q;
    logic          user_w_done_q;
    logic          user_aw_done_q;

    // Khai báo trước tín hiệu ML & REENC để trọng tài FIFO / Read DRAM
    logic         ml_dram_wr_valid;
    logic [63:0]  ml_dram_wr_addr;
    logic [511:0] ml_dram_wr_data;
    logic         ml_dram_wr_ack;
    logic         ml_dram_rd_req;
    logic [63:0]  ml_dram_rd_addr;
    logic         ml_dram_rd_valid_in;
    logic [511:0] ml_dram_rd_data_in;

    logic         reenc_dram_wr_valid;
    logic [63:0]  reenc_dram_wr_addr;
    logic [511:0] reenc_dram_wr_data;
    logic         reenc_dram_wr_ack;
    logic         reenc_dram_rd_req;
    logic [63:0]  reenc_dram_rd_addr;
    logic         reenc_dram_rd_valid_in;
    logic [511:0] reenc_dram_rd_data_in;

    logic         bmt_rd_req_q;
    logic [63:0]  bmt_rd_addr_q;

    wire meta_pipe_idle = (meta_fifo_cnt == 7'd0) && !meta_aw_valid && !meta_w_valid &&
                          (wr_bus_owner != WR_META) && (meta_wr_inflight == 8'd0);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_meta_init_done      <= 1'b0;
            reg_meta_init_ever_done <= 1'b0;
            bmt_init_seen           <= 1'b0;
            reg_meta_init_cycles    <= 32'd0;
            reg_meta_flush_done     <= 1'b0;
            bmt_flush_seen          <= 1'b0;
            ml_flush_done_seen      <= 1'b0;
        end else begin
            if (eff_meta_init_start) begin
                reg_meta_init_done <= 1'b0;
                bmt_init_seen      <= 1'b0;
            end else begin
                if (bmt_init_done) begin
                    bmt_init_seen        <= 1'b1;
                    reg_meta_init_cycles <= bmt_init_cycles;
                end
                if ((bmt_init_seen || bmt_init_done) && meta_pipe_idle && !reg_meta_init_done) begin
                    reg_meta_init_done      <= 1'b1;
                    reg_meta_init_ever_done <= 1'b1;
                end
            end

            if (eff_meta_flush_start) begin
                reg_meta_flush_done <= 1'b0;
                bmt_flush_seen      <= 1'b0;
                ml_flush_done_seen  <= 1'b0;
            end else begin
                if (bmt_flush_done) bmt_flush_seen <= 1'b1;
                if (!ml_flush_busy) ml_flush_done_seen <= 1'b1;
                if (bmt_flush_seen && !ml_flush_busy && meta_pipe_idle && !reg_meta_flush_done) begin
                    reg_meta_flush_done <= 1'b1;
                end
            end
        end
    end
    assign o_meta_init_done   = reg_meta_init_done;
    assign o_meta_init_cycles = bmt_init_done ? bmt_init_cycles : reg_meta_init_cycles;
    assign o_meta_flush_done  = reg_meta_flush_done;

    qshield_bmt_engine #(
        .PROT_BASE  (64'h0000_0000_0000_0000),
        .PROT_LINES (64'd4096),
        .TREE_ARITY (8),
        .MC_SETS    (16),
        .MC_WAYS    (4)
    ) u_bmt_engine (
        .clk               (clk),
        .rst_n             (rst_n),
        .i_h               (eff_h),
        .i_k3              (eff_k3),
        .i_keys_valid      (k3_h_ready),
        .i_verify_valid    (bmt_verify_valid),
        .i_verify_addr     (bmt_verify_addr),
        .o_verify_ready    (bmt_verify_ready),
        .o_verify_done     (bmt_verify_done),
        .o_verify_pass     (bmt_verify_pass),
        .o_verify_fail     (bmt_verify_fail),
        .o_cb_data         (bmt_cb_data),
        .o_cb_slot         (bmt_cb_slot),
        .i_update_valid    (bmt_update_valid),
        .i_update_addr     (bmt_update_addr),
        .i_update_cb_data  (bmt_update_cb_data),
        .o_update_ready    (bmt_update_ready),
        .o_update_done     (bmt_update_done),
        .i_init_start      (eff_meta_init_start),
        .o_init_busy       (),
        .o_init_done       (bmt_init_done),
        .o_init_cycles     (bmt_init_cycles),
        .i_flush_start     (eff_meta_flush_start),
        .o_flush_busy      (),
        .o_flush_done      (bmt_flush_done),
        .i_cache_clear     (i_cache_clear),
        .o_dram_rd_valid   (bmt_dram_rd_valid),
        .o_dram_rd_addr    (bmt_dram_rd_addr),
        .i_dram_rd_ready   (bmt_dram_rd_ready),
        .i_dram_rd_valid   (bmt_dram_rd_valid_in),
        .i_dram_rd_data    (bmt_dram_rd_data_in),
        .o_dram_wr_valid   (bmt_dram_wr_valid),
        .o_dram_wr_addr    (bmt_dram_wr_addr),
        .o_dram_wr_data    (bmt_dram_wr_data),
        .i_dram_wr_ready   (bmt_dram_wr_ready),
        .o_tree_root       (bmt_tree_root),
        .o_tree_root_slots (),
        .o_tree_fail_cnt   (bmt_tree_fail_cnt_out),
        .o_verify_cnt      (),
        .o_update_cnt      (),
        .o_integrity_alert (bmt_integ_alert_out)
    );

    wire meta_fifo_push_bmt   = bmt_dram_wr_valid && (meta_fifo_cnt < META_FIFO_D);
    wire meta_fifo_push_ml    = !bmt_dram_wr_valid && ml_dram_wr_valid && (meta_fifo_cnt < META_FIFO_D - 2);
    wire meta_fifo_push_reenc = !bmt_dram_wr_valid && !ml_dram_wr_valid && reenc_dram_wr_valid && (meta_fifo_cnt < META_FIFO_D - 2);
    wire meta_fifo_push_any   = meta_fifo_push_bmt || meta_fifo_push_ml || meta_fifo_push_reenc;
    wire meta_fifo_pop_en     = (wr_bus_owner == WR_NONE) && (meta_fifo_cnt > 0);

    // No-reset SDP distributed RAM write port for metadata write FIFO (~800 LUT6 vs ~37k FFs)
    wire [63:0]  meta_fifo_din_addr = meta_fifo_push_bmt ? bmt_dram_wr_addr :
                                      (meta_fifo_push_ml ? ml_dram_wr_addr : reenc_dram_wr_addr);
    wire [511:0] meta_fifo_din_data = meta_fifo_push_bmt ? bmt_dram_wr_data :
                                      (meta_fifo_push_ml ? ml_dram_wr_data : reenc_dram_wr_data);
    wire [3:0]   meta_fifo_din_id   = meta_fifo_push_bmt ? 4'b1000 :
                                      (meta_fifo_push_ml ? 4'b1001 : 4'b1010);
    always_ff @(posedge clk) begin
        if (meta_fifo_push_any) begin
            meta_fifo_addr[meta_fifo_wptr] <= meta_fifo_din_addr;
            meta_fifo_data[meta_fifo_wptr] <= meta_fifo_din_data;
            meta_fifo_id[meta_fifo_wptr]   <= meta_fifo_din_id;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            meta_rd_ar_pending <= 1'b0;
            meta_rd_addr       <= 64'h0;
            meta_rd_id         <= 4'b1000;
            meta_rd_active     <= 1'b0;
            meta_rd_owner      <= 2'd0;
            bmt_dram_rd_ready  <= 1'b0;
            bmt_rd_req_q       <= 1'b0;
            bmt_rd_addr_q      <= 64'h0;

            meta_fifo_wptr     <= 6'd0;
            meta_fifo_rptr     <= 6'd0;
            meta_fifo_cnt      <= 7'd0;
            ml_dram_wr_ack     <= 1'b0;
            reenc_dram_wr_ack  <= 1'b0;

            meta_aw_valid      <= 1'b0;
            meta_w_valid       <= 1'b0;
            meta_wr_addr       <= 64'h0;
            meta_wr_data       <= 512'h0;
            meta_wr_id         <= 4'b1000;
            meta_wr_beat       <= 3'd0;
            bmt_dram_wr_ready  <= 1'b0;
            meta_wr_inflight   <= 8'd0;

            wr_bus_owner       <= WR_NONE;
            meta_aw_done_q     <= 1'b0;
            meta_w_done_q      <= 1'b0;
            user_aw_done_q     <= 1'b0;
            user_w_done_q      <= 1'b0;

            reg_meta_rd_cnt    <= 32'h0;
            reg_meta_wr_cnt    <= 32'h0;
        end else begin
            bmt_dram_rd_ready <= 1'b0;
            bmt_dram_wr_ready <= 1'b0;
            ml_dram_wr_ack    <= 1'b0;
            reenc_dram_wr_ack <= 1'b0;

            // Đẩy lệnh ghi metadata (BMT ưu tiên cao nhất không mất xung; ML/REENC chờ ack)
            if (meta_fifo_push_bmt) begin
                meta_fifo_wptr    <= meta_fifo_wptr + 1'b1;
                bmt_dram_wr_ready <= 1'b1;
                reg_meta_wr_cnt   <= reg_meta_wr_cnt + 1'b1;
            end else if (meta_fifo_push_ml) begin
                meta_fifo_wptr  <= meta_fifo_wptr + 1'b1;
                ml_dram_wr_ack  <= 1'b1;
                reg_meta_wr_cnt <= reg_meta_wr_cnt + 1'b1;
            end else if (meta_fifo_push_reenc) begin
                meta_fifo_wptr    <= meta_fifo_wptr + 1'b1;
                reenc_dram_wr_ack <= 1'b1;
                reg_meta_wr_cnt   <= reg_meta_wr_cnt + 1'b1;
            end

            if (meta_fifo_push_any && !meta_fifo_pop_en) begin
                meta_fifo_cnt <= meta_fifo_cnt + 1'b1;
            end else if (!meta_fifo_push_any && meta_fifo_pop_en) begin
                meta_fifo_cnt <= meta_fifo_cnt - 1'b1;
            end

            // Đếm lệnh ghi metadata đang chờ BRESP từ lõi DDR5
            if ((meta_aw_valid && m_axi_awready && (m_axi_awid[3] == 1'b1)) &&
                !(m_axi_bvalid && m_axi_bready && (m_axi_bid[3] == 1'b1))) begin
                meta_wr_inflight <= meta_wr_inflight + 1'b1;
            end else if (!(meta_aw_valid && m_axi_awready && (m_axi_awid[3] == 1'b1)) &&
                         (m_axi_bvalid && m_axi_bready && (m_axi_bid[3] == 1'b1)) &&
                         (meta_wr_inflight > 0)) begin
                meta_wr_inflight <= meta_wr_inflight - 1'b1;
            end

            // Trọng tài kênh AW+W: phát tuần tự trọn burst, tuyệt đối không xen giữa user burst
            case (wr_bus_owner)
                WR_NONE: begin
                    if (meta_fifo_cnt > 0) begin
                        wr_bus_owner   <= WR_META;
                        meta_aw_valid  <= 1'b1;
                        meta_w_valid   <= 1'b1;
                        meta_wr_addr   <= meta_fifo_addr[meta_fifo_rptr];
                        meta_wr_data   <= meta_fifo_data[meta_fifo_rptr];
                        meta_wr_id     <= meta_fifo_id[meta_fifo_rptr];
                        meta_wr_beat   <= 3'd0;
                        meta_aw_done_q <= 1'b0;
                        meta_w_done_q  <= 1'b0;
                        meta_fifo_rptr <= meta_fifo_rptr + 1'b1;
                    end else if (m_axi_awvalid && m_axi_awready && (m_axi_awid[3] == 1'b0)) begin
                        wr_bus_owner   <= WR_USER;
                        user_aw_done_q <= 1'b1;
                        user_w_done_q  <= (m_axi_wvalid && m_axi_wready && m_axi_wlast);
                    end else if (m_axi_wvalid && m_axi_wready && !meta_w_valid) begin
                        wr_bus_owner   <= WR_USER;
                        user_aw_done_q <= 1'b0;
                        user_w_done_q  <= m_axi_wlast;
                    end
                end

                WR_META: begin
                    if (meta_aw_valid && m_axi_awready && (m_axi_awid[3] == 1'b1)) begin
                        meta_aw_valid  <= 1'b0;
                        meta_aw_done_q <= 1'b1;
                    end
                    if (meta_w_valid && m_axi_wready) begin
                        if (meta_wr_beat < 3'd7) begin
                            meta_wr_beat <= meta_wr_beat + 1'b1;
                        end else begin
                            meta_w_valid  <= 1'b0;
                            meta_w_done_q <= 1'b1;
                        end
                    end
                    if ((meta_aw_done_q || (meta_aw_valid && m_axi_awready)) &&
                        (meta_w_done_q  || (meta_w_valid && m_axi_wready && (meta_wr_beat == 3'd7)))) begin
                        wr_bus_owner <= WR_NONE;
                    end
                end

                WR_USER: begin
                    if (m_axi_awvalid && m_axi_awready && (m_axi_awid[3] == 1'b0)) begin
                        user_aw_done_q <= 1'b1;
                    end
                    if (m_axi_wvalid && m_axi_wready && m_axi_wlast) begin
                        user_w_done_q <= 1'b1;
                    end
                    if ((user_aw_done_q || (m_axi_awvalid && m_axi_awready && !m_axi_awid[3])) &&
                        (user_w_done_q  || (m_axi_wvalid && m_axi_wready && m_axi_wlast))) begin
                        wr_bus_owner <= WR_NONE;
                    end
                end

                default: wr_bus_owner <= WR_NONE;
            endcase

            // Trọng tài đọc DRAM cho Metadata (BMT 4'b1000, ML 4'b1001, REENC 4'b1010)
            if (bmt_dram_rd_valid) begin
                bmt_rd_req_q  <= 1'b1;
                bmt_rd_addr_q <= bmt_dram_rd_addr;
            end

            if (!meta_rd_active) begin
                if (bmt_dram_rd_valid || bmt_rd_req_q) begin
                    meta_rd_active     <= 1'b1;
                    meta_rd_ar_pending <= 1'b1;
                    meta_rd_owner      <= 2'd0;
                    meta_rd_id         <= 4'b1000;
                    meta_rd_addr       <= bmt_dram_rd_valid ? bmt_dram_rd_addr : bmt_rd_addr_q;
                    bmt_rd_req_q       <= 1'b0;
                    bmt_dram_rd_ready  <= 1'b1;
                    reg_meta_rd_cnt    <= reg_meta_rd_cnt + 1'b1;
                end else if (ml_dram_rd_req) begin
                    meta_rd_active     <= 1'b1;
                    meta_rd_ar_pending <= 1'b1;
                    meta_rd_owner      <= 2'd1;
                    meta_rd_id         <= 4'b1001;
                    meta_rd_addr       <= ml_dram_rd_addr;
                    reg_meta_rd_cnt    <= reg_meta_rd_cnt + 1'b1;
                end else if (reenc_dram_rd_req) begin
                    meta_rd_active     <= 1'b1;
                    meta_rd_ar_pending <= 1'b1;
                    meta_rd_owner      <= 2'd2;
                    meta_rd_id         <= 4'b1010;
                    meta_rd_addr       <= reenc_dram_rd_addr;
                    reg_meta_rd_cnt    <= reg_meta_rd_cnt + 1'b1;
                end
            end else begin
                if (meta_rd_ar_pending && m_axi_arvalid && m_axi_arready && (m_axi_arid[3] == 1'b1)) begin
                    meta_rd_ar_pending <= 1'b0;
                end
                if (m_axi_rvalid && m_axi_rready && (m_axi_rid[3] == 1'b1) && m_axi_rlast) begin
                    meta_rd_active <= 1'b0;
                end
            end
        end
    end

    // Ghép 8 beat phản hồi đọc DRAM cho BMT / ML / REENC
    logic [511:0] meta_rd_accum;
    logic [2:0]   meta_rd_beat_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            meta_rd_beat_cnt       <= 3'd0;
            meta_rd_accum          <= 512'h0;
            bmt_dram_rd_valid_in   <= 1'b0;
            bmt_dram_rd_data_in    <= 512'h0;
            ml_dram_rd_valid_in    <= 1'b0;
            ml_dram_rd_data_in     <= 512'h0;
            reenc_dram_rd_valid_in <= 1'b0;
            reenc_dram_rd_data_in  <= 512'h0;
        end else begin
            bmt_dram_rd_valid_in   <= 1'b0;
            ml_dram_rd_valid_in    <= 1'b0;
            reenc_dram_rd_valid_in <= 1'b0;
            if (m_axi_rvalid && (m_axi_rid[3] == 1'b1)) begin
                meta_rd_accum[meta_rd_beat_cnt * 64 +: 64] <= m_axi_rdata;
                if (m_axi_rlast || (meta_rd_beat_cnt == 3'd7)) begin
                    meta_rd_beat_cnt <= 3'd0;
                    if (meta_rd_owner == 2'd0) begin
                        bmt_dram_rd_valid_in <= 1'b1;
                        bmt_dram_rd_data_in  <= {m_axi_rdata, meta_rd_accum[447:0]};
                    end else if (meta_rd_owner == 2'd1) begin
                        ml_dram_rd_valid_in <= 1'b1;
                        ml_dram_rd_data_in  <= {m_axi_rdata, meta_rd_accum[447:0]};
                    end else begin
                        reenc_dram_rd_valid_in <= 1'b1;
                        reenc_dram_rd_data_in  <= {m_axi_rdata, meta_rd_accum[447:0]};
                    end
                end else begin
                    meta_rd_beat_cnt <= meta_rd_beat_cnt + 1'b1;
                end
            end
        end
    end

    //-------------------------------------------------------------------------
    // 4. Bộ đệm MAC Lines (ML) 8 dòng (4 set x 2 way PLRU) gắn DRAM thực
    //    Thay mảng 512x512 FF để tổng hợp gọn và giữ nguyên dòng ML trong DRAM
    //-------------------------------------------------------------------------
    logic [511:0] ml_dram_inited; // 512 bit đánh dấu block ML đã có dữ liệu thật trong DRAM
    logic         ml_c_valid [4][2];
    logic         ml_c_dirty [4][2];
    logic [6:0]   ml_c_tag   [4][2];
    logic [511:0] ml_c_data  [4][2];
    logic         ml_c_plru  [4];

    typedef enum logic [2:0] {
        ML_IDLE      = 3'd0,
        ML_EVICT     = 3'd1,
        ML_FILL      = 3'd2,
        ML_FILL_WAIT = 3'd3,
        ML_FLUSH_CHK = 3'd4,
        ML_FLUSH_WR  = 3'd5
    } ml_fsm_t;
    ml_fsm_t ml_state;

    logic         ml_req_valid;
    logic         ml_req_we;
    logic [48:0]  ml_req_line;
    logic [63:0]  ml_req_wtag;
    logic         ml_rsp_valid;
    logic [63:0]  ml_rsp_rtag;
    wire          ml_busy = (ml_state != ML_IDLE);

    logic         ml_lat_we;
    logic [8:0]   ml_lat_idx;
    logic [2:0]   ml_lat_slot;
    logic [63:0]  ml_lat_wtag;
    logic         ml_vict_way_q;
    logic [2:0]   ml_flush_ptr;

    wire [8:0]    ml_req_idx_w  = ml_req_line[11:3];
    wire [1:0]    ml_req_set_w  = ml_req_idx_w[1:0];
    wire [6:0]    ml_req_tag_w  = ml_req_idx_w[8:2];
    wire          ml_hit0_w     = ml_c_valid[ml_req_set_w][0] && (ml_c_tag[ml_req_set_w][0] == ml_req_tag_w);
    wire          ml_hit1_w     = ml_c_valid[ml_req_set_w][1] && (ml_c_tag[ml_req_set_w][1] == ml_req_tag_w);
    wire          ml_hit_way_w  = ml_hit1_w ? 1'b1 : 1'b0;
    wire          ml_vict_sel_w = !ml_c_valid[ml_req_set_w][0] ? 1'b0 :
                                  (!ml_c_valid[ml_req_set_w][1] ? 1'b1 : ml_c_plru[ml_req_set_w]);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ml_dram_inited  <= 512'h0;
            ml_state        <= ML_IDLE;
            ml_flush_busy   <= 1'b0;
            ml_flush_ptr    <= 3'd0;
            ml_rsp_valid    <= 1'b0;
            ml_rsp_rtag     <= 64'h0;
            ml_dram_wr_valid<= 1'b0;
            ml_dram_wr_addr <= 64'h0;
            ml_dram_wr_data <= 512'h0;
            ml_dram_rd_req  <= 1'b0;
            ml_dram_rd_addr <= 64'h0;
            ml_lat_we       <= 1'b0;
            ml_lat_idx      <= 9'd0;
            ml_lat_slot     <= 3'd0;
            ml_lat_wtag     <= 64'h0;
            ml_vict_way_q   <= 1'b0;
            for (int s = 0; s < 4; s++) begin
                ml_c_plru[s] <= 1'b0;
                for (int w = 0; w < 2; w++) begin
                    ml_c_valid[s][w] <= 1'b0;
                    ml_c_dirty[s][w] <= 1'b0;
                    ml_c_tag[s][w]   <= 7'h0;
                    ml_c_data[s][w]  <= 512'h0;
                end
            end
        end else begin
            ml_rsp_valid <= 1'b0;
            if (ml_dram_wr_ack) begin
                ml_dram_wr_valid <= 1'b0;
            end
            if (ml_dram_rd_valid_in) begin
                ml_dram_rd_req <= 1'b0;
            end

            if (eff_meta_init_start) begin
                ml_dram_inited <= 512'h0;
                ml_state       <= ML_IDLE;
                ml_flush_busy  <= 1'b0;
                for (int s = 0; s < 4; s++) begin
                    ml_c_plru[s] <= 1'b0;
                    for (int w = 0; w < 2; w++) begin
                        ml_c_valid[s][w] <= 1'b0;
                        ml_c_dirty[s][w] <= 1'b0;
                    end
                end
            end else if (i_cache_clear) begin
                for (int s = 0; s < 4; s++) begin
                    for (int w = 0; w < 2; w++) begin
                        ml_c_valid[s][w] <= 1'b0;
                        ml_c_dirty[s][w] <= 1'b0;
                    end
                end
            end else begin
                case (ml_state)
                    ML_IDLE: begin
                        if (eff_meta_flush_start) begin
                            ml_flush_busy <= 1'b1;
                            ml_flush_ptr  <= 3'd0;
                            ml_state      <= ML_FLUSH_CHK;
                        end else if (ml_req_valid) begin
                            if (ml_hit0_w || ml_hit1_w) begin
                                ml_c_plru[ml_req_set_w] <= !ml_hit_way_w;
                                if (ml_req_we) begin
                                    ml_c_data[ml_req_set_w][ml_hit_way_w][ml_req_line[2:0]*64 +: 64] <= ml_req_wtag;
                                    ml_c_dirty[ml_req_set_w][ml_hit_way_w] <= 1'b1;
                                end else begin
                                    ml_rsp_rtag <= ml_c_data[ml_req_set_w][ml_hit_way_w][ml_req_line[2:0]*64 +: 64];
                                end
                                ml_rsp_valid <= 1'b1;
                            end else begin
                                ml_lat_we     <= ml_req_we;
                                ml_lat_idx    <= ml_req_idx_w;
                                ml_lat_slot   <= ml_req_line[2:0];
                                ml_lat_wtag   <= ml_req_wtag;
                                ml_vict_way_q <= ml_vict_sel_w;
                                if (ml_c_valid[ml_req_set_w][ml_vict_sel_w] && ml_c_dirty[ml_req_set_w][ml_vict_sel_w]) begin
                                    ml_dram_wr_valid <= 1'b1;
                                    ml_dram_wr_addr  <= eff_ml_base + {49'd0, ml_c_tag[ml_req_set_w][ml_vict_sel_w], ml_req_set_w, 6'h0};
                                    ml_dram_wr_data  <= ml_c_data[ml_req_set_w][ml_vict_sel_w];
                                    ml_dram_inited[{ml_c_tag[ml_req_set_w][ml_vict_sel_w], ml_req_set_w}] <= 1'b1;
                                    ml_c_dirty[ml_req_set_w][ml_vict_sel_w] <= 1'b0;
                                    ml_state <= ML_EVICT;
                                end else begin
                                    ml_state <= ML_FILL;
                                end
                            end
                        end
                    end

                    ML_EVICT: begin
                        if (ml_dram_wr_ack || !ml_dram_wr_valid) begin
                            ml_state <= ML_FILL;
                        end
                    end

                    ML_FILL: begin
                        if (!ml_dram_inited[ml_lat_idx]) begin
                            ml_c_valid[ml_lat_idx[1:0]][ml_vict_way_q] <= 1'b1;
                            ml_c_dirty[ml_lat_idx[1:0]][ml_vict_way_q] <= ml_lat_we;
                            ml_c_tag[ml_lat_idx[1:0]][ml_vict_way_q]   <= ml_lat_idx[8:2];
                            for (int b = 0; b < 8; b++) begin
                                ml_c_data[ml_lat_idx[1:0]][ml_vict_way_q][b*64 +: 64] <=
                                    (ml_lat_we && (b == int'(ml_lat_slot))) ? ml_lat_wtag : 64'h0;
                            end
                            ml_c_plru[ml_lat_idx[1:0]] <= !ml_vict_way_q;
                            ml_rsp_rtag  <= 64'h0;
                            ml_rsp_valid <= 1'b1;
                            ml_state     <= ML_IDLE;
                        end else begin
                            ml_dram_rd_req  <= 1'b1;
                            ml_dram_rd_addr <= eff_ml_base + {49'd0, ml_lat_idx, 6'h0};
                            ml_state        <= ML_FILL_WAIT;
                        end
                    end

                    ML_FILL_WAIT: begin
                        if (ml_dram_rd_valid_in) begin
                            ml_c_valid[ml_lat_idx[1:0]][ml_vict_way_q] <= 1'b1;
                            ml_c_dirty[ml_lat_idx[1:0]][ml_vict_way_q] <= ml_lat_we;
                            ml_c_tag[ml_lat_idx[1:0]][ml_vict_way_q]   <= ml_lat_idx[8:2];
                            for (int b = 0; b < 8; b++) begin
                                ml_c_data[ml_lat_idx[1:0]][ml_vict_way_q][b*64 +: 64] <=
                                    (ml_lat_we && (b == int'(ml_lat_slot))) ? ml_lat_wtag : ml_dram_rd_data_in[b*64 +: 64];
                            end
                            if (!ml_lat_we) begin
                                ml_rsp_rtag <= ml_dram_rd_data_in[ml_lat_slot*64 +: 64];
                            end
                            ml_c_plru[ml_lat_idx[1:0]] <= !ml_vict_way_q;
                            ml_rsp_valid <= 1'b1;
                            ml_state     <= ML_IDLE;
                        end
                    end

                    ML_FLUSH_CHK: begin
                        if (ml_c_valid[ml_flush_ptr[2:1]][ml_flush_ptr[0]] &&
                            ml_c_dirty[ml_flush_ptr[2:1]][ml_flush_ptr[0]]) begin
                            ml_dram_wr_valid <= 1'b1;
                            ml_dram_wr_addr  <= eff_ml_base + {49'd0, ml_c_tag[ml_flush_ptr[2:1]][ml_flush_ptr[0]], ml_flush_ptr[2:1], 6'h0};
                            ml_dram_wr_data  <= ml_c_data[ml_flush_ptr[2:1]][ml_flush_ptr[0]];
                            ml_dram_inited[{ml_c_tag[ml_flush_ptr[2:1]][ml_flush_ptr[0]], ml_flush_ptr[2:1]}] <= 1'b1;
                            ml_c_dirty[ml_flush_ptr[2:1]][ml_flush_ptr[0]] <= 1'b0;
                            ml_state <= ML_FLUSH_WR;
                        end else if (ml_flush_ptr == 3'd7) begin
                            ml_flush_busy <= 1'b0;
                            ml_state      <= ML_IDLE;
                        end else begin
                            ml_flush_ptr <= ml_flush_ptr + 1'b1;
                        end
                    end

                    ML_FLUSH_WR: begin
                        if (ml_dram_wr_ack || !ml_dram_wr_valid) begin
                            if (ml_flush_ptr == 3'd7) begin
                                ml_flush_busy <= 1'b0;
                                ml_state      <= ML_IDLE;
                            end else begin
                                ml_flush_ptr <= ml_flush_ptr + 1'b1;
                                ml_state     <= ML_FLUSH_CHK;
                            end
                        end
                    end

                    default: ml_state <= ML_IDLE;
                endcase
            end
        end
    end

    //-------------------------------------------------------------------------
    // 5. Đơn vị tính và kiểm tra MAC Carter-Wegman cho Dòng Dữ Liệu
    //-------------------------------------------------------------------------
    logic         data_mac_valid;
    wire          data_mac_ready;
    logic [511:0] data_mac_data;
    logic [127:0] data_mac_mask;
    logic [63:0]  data_mac_major;
    logic [6:0]   data_mac_minor;
    logic [48:0]  data_mac_line_idx;
    logic [63:0]  data_mac_expected_tag;
    wire          data_mac_out_valid;
    wire  [63:0]  data_mac_tag;
    wire          data_mac_match;
    wire          data_mac_mismatch;

    qshield_mac_unit #(
        .GF_STAGES(4)
    ) u_data_mac (
        .clk              (clk),
        .rst_n            (rst_n),
        .i_h              (eff_h),
        .i_valid          (data_mac_valid),
        .o_ready          (data_mac_ready),
        .i_mode           (1'b0), // 0: Data line (0x01)
        .i_data           (data_mac_data),
        .i_mask           (data_mac_mask),
        .i_major          (data_mac_major),
        .i_minor          (data_mac_minor),
        .i_line_idx       (data_mac_line_idx),
        .i_level          (4'd0),
        .i_node_idx       (60'd0),
        .o_mask_plaintext (),
        .i_expected_tag   (data_mac_expected_tag),
        .o_valid          (data_mac_out_valid),
        .i_ready          (1'b1),
        .o_tag            (data_mac_tag),
        .o_tag128         (),
        .o_ghash          (),
        .o_tag_match      (data_mac_match),
        .o_tag_mismatch   (data_mac_mismatch)
    );

    logic         mask_pipe_in_valid;
    logic [127:0] mask_pipe_in_pt;
    wire          mask_pipe_out_valid;
    wire  [127:0] mask_pipe_out_ct;

    logic [127:0] mask_pipe_st  [15];
    logic         mask_pipe_vld [15];

    assign mask_pipe_st[0]  = rev128(mask_pipe_in_pt) ^ k3_rk[0];
    assign mask_pipe_vld[0] = mask_pipe_in_valid;

    genvar mr;
    generate
        for (mr = 1; mr <= 14; mr++) begin : gen_mask_aes_round
            localparam bit IsFinal = (mr == 14);
            aes_round_pipe u_mask_rnd (
                .clk            (clk),
                .rst_n          (rst_n),
                .in_valid       (mask_pipe_vld[mr-1]),
                .in_ready       (),
                .is_final_round (IsFinal),
                .state_in       (mask_pipe_st[mr-1]),
                .round_key      (k3_rk[mr]),
                .out_valid      (mask_pipe_vld[mr]),
                .out_ready      (1'b1),
                .state_out      (mask_pipe_st[mr])
            );
        end
    endgenerate

    assign mask_pipe_out_valid = mask_pipe_vld[14];
    assign mask_pipe_out_ct    = rev128(mask_pipe_st[14]);

    // Trọng tài chia sẻ u_data_mac, mask_pipe và ML cache giữa Đọc, Ghi, Tính H và Re-encrypt
    typedef enum logic [3:0] {
        MAC_IDLE    = 4'd0,
        MAC_WAIT_H  = 4'd1,
        MAC_WR_MASK = 4'd2,
        MAC_WR_CALC = 4'd3,
        MAC_WR_ML   = 4'd4,
        MAC_WR_DONE = 4'd5,
        MAC_RD_MASK = 4'd6,
        MAC_RD_CALC = 4'd7,
        MAC_RD_DONE = 4'd8
    } mac_fsm_t;
    mac_fsm_t mac_fsm;

    logic         wr_mac_req;
    logic [511:0] wr_mac_cdata;
    logic [63:0]  wr_mac_maj;
    logic [6:0]   wr_mac_min;
    logic [48:0]  wr_mac_line;
    logic         wr_mac_done;
    logic [63:0]  wr_computed_tag;

    logic         rd_mac_req;
    logic [511:0] rd_mac_cdata;
    logic [63:0]  rd_mac_maj;
    logic [6:0]   rd_mac_min;
    logic [48:0]  rd_mac_line;
    logic         rd_mac_done;
    logic         rd_mac_match;
    logic         rd_mac_mismatch;

    logic         reenc_wr_mac_req;
    logic [511:0] reenc_wr_mac_cdata;
    logic [63:0]  reenc_wr_mac_maj;
    logic [6:0]   reenc_wr_mac_min;
    logic [48:0]  reenc_wr_mac_line;

    logic         reenc_rd_mac_req;
    logic [511:0] reenc_rd_mac_cdata;
    logic [63:0]  reenc_rd_mac_maj;
    logic [6:0]   reenc_rd_mac_min;
    logic [48:0]  reenc_rd_mac_line;

    logic [511:0] act_mac_cdata;
    logic [63:0]  act_mac_maj;
    logic [6:0]   act_mac_min;
    logic [48:0]  act_mac_line;
    logic [127:0] rd_mask_q;
    logic         rd_mask_got;
    logic [63:0]  rd_mac_exp_tag_q;
    logic         ml_exp_got;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mac_fsm               <= MAC_IDLE;
            h_auto_reg            <= 128'h0;
            h_auto_valid          <= 1'b0;
            mask_pipe_in_valid    <= 1'b0;
            mask_pipe_in_pt       <= 128'h0;
            data_mac_valid        <= 1'b0;
            data_mac_data         <= 512'h0;
            data_mac_mask         <= 128'h0;
            data_mac_major        <= 64'h0;
            data_mac_minor        <= 7'h0;
            data_mac_line_idx     <= 49'h0;
            data_mac_expected_tag <= 64'h0;
            ml_req_valid          <= 1'b0;
            ml_req_we             <= 1'b0;
            ml_req_line           <= 49'h0;
            ml_req_wtag           <= 64'h0;
            act_mac_cdata         <= 512'h0;
            act_mac_maj           <= 64'h0;
            act_mac_min           <= 7'h0;
            act_mac_line          <= 49'h0;
            rd_mask_q             <= 128'h0;
            rd_mask_got           <= 1'b0;
            rd_mac_exp_tag_q      <= 64'h0;
            ml_exp_got            <= 1'b0;
            wr_mac_done           <= 1'b0;
            wr_computed_tag       <= 64'h0;
            rd_mac_done           <= 1'b0;
            rd_mac_match          <= 1'b0;
            rd_mac_mismatch       <= 1'b0;
        end else begin
            mask_pipe_in_valid <= 1'b0;
            data_mac_valid     <= 1'b0;
            ml_req_valid       <= 1'b0;
            wr_mac_done        <= 1'b0;
            rd_mac_done        <= 1'b0;

            if (!k3_stable) begin
                h_auto_valid <= 1'b0;
            end

            case (mac_fsm)
                MAC_IDLE: begin
                    if (k3_stable && !h_auto_valid) begin
                        mask_pipe_in_valid <= 1'b1;
                        mask_pipe_in_pt    <= 128'h0;
                        mac_fsm            <= MAC_WAIT_H;
                    end else if ((wr_mac_req || reenc_wr_mac_req) && !ml_busy) begin
                        act_mac_cdata      <= reenc_wr_mac_req ? reenc_wr_mac_cdata : wr_mac_cdata;
                        act_mac_maj        <= reenc_wr_mac_req ? reenc_wr_mac_maj   : wr_mac_maj;
                        act_mac_min        <= reenc_wr_mac_req ? reenc_wr_mac_min   : wr_mac_min;
                        act_mac_line       <= reenc_wr_mac_req ? reenc_wr_mac_line  : wr_mac_line;
                        mask_pipe_in_valid <= 1'b1;
                        mask_pipe_in_pt    <= {8'h01,
                                               reenc_wr_mac_req ? reenc_wr_mac_maj  : wr_mac_maj,
                                               reenc_wr_mac_req ? reenc_wr_mac_min  : wr_mac_min,
                                               reenc_wr_mac_req ? reenc_wr_mac_line : wr_mac_line};
                        mac_fsm            <= MAC_WR_MASK;
                    end else if ((rd_mac_req || reenc_rd_mac_req) && !ml_busy) begin
                        act_mac_cdata      <= reenc_rd_mac_req ? reenc_rd_mac_cdata : rd_mac_cdata;
                        act_mac_maj        <= reenc_rd_mac_req ? reenc_rd_mac_maj   : rd_mac_maj;
                        act_mac_min        <= reenc_rd_mac_req ? reenc_rd_mac_min   : rd_mac_min;
                        act_mac_line       <= reenc_rd_mac_req ? reenc_rd_mac_line  : rd_mac_line;
                        mask_pipe_in_valid <= 1'b1;
                        mask_pipe_in_pt    <= {8'h01,
                                               reenc_rd_mac_req ? reenc_rd_mac_maj  : rd_mac_maj,
                                               reenc_rd_mac_req ? reenc_rd_mac_min  : rd_mac_min,
                                               reenc_rd_mac_req ? reenc_rd_mac_line : rd_mac_line};
                        ml_req_valid       <= 1'b1;
                        ml_req_we          <= 1'b0;
                        ml_req_line        <= reenc_rd_mac_req ? reenc_rd_mac_line  : rd_mac_line;
                        rd_mask_got        <= 1'b0;
                        ml_exp_got         <= 1'b0;
                        mac_fsm            <= MAC_RD_MASK;
                    end
                end

                MAC_WAIT_H: begin
                    if (!k3_stable) begin
                        mac_fsm <= MAC_IDLE;
                    end else if (mask_pipe_out_valid) begin
                        h_auto_reg   <= mask_pipe_out_ct;
                        h_auto_valid <= 1'b1;
                        mac_fsm      <= MAC_IDLE;
                    end
                end

                MAC_WR_MASK: begin
                    if (mask_pipe_out_valid && data_mac_ready) begin
                        data_mac_valid        <= 1'b1;
                        data_mac_data         <= act_mac_cdata;
                        data_mac_mask         <= mask_pipe_out_ct;
                        data_mac_major        <= act_mac_maj;
                        data_mac_minor        <= act_mac_min;
                        data_mac_line_idx     <= act_mac_line;
                        data_mac_expected_tag <= 64'h0;
                        mac_fsm               <= MAC_WR_CALC;
                    end
                end

                MAC_WR_CALC: begin
                    if (data_mac_out_valid) begin
                        wr_computed_tag <= data_mac_tag;
                        ml_req_valid    <= 1'b1;
                        ml_req_we       <= 1'b1;
                        ml_req_line     <= act_mac_line;
                        ml_req_wtag     <= data_mac_tag;
                        mac_fsm         <= MAC_WR_ML;
                    end
                end

                MAC_WR_ML: begin
                    if (ml_rsp_valid) begin
                        wr_mac_done <= 1'b1;
                        mac_fsm     <= MAC_WR_DONE;
                    end
                end

                MAC_WR_DONE: begin
                    mac_fsm <= MAC_IDLE;
                end

                MAC_RD_MASK: begin
                    if (mask_pipe_out_valid) begin
                        rd_mask_q   <= mask_pipe_out_ct;
                        rd_mask_got <= 1'b1;
                    end
                    if (ml_rsp_valid) begin
                        rd_mac_exp_tag_q <= ml_rsp_rtag;
                        ml_exp_got       <= 1'b1;
                    end
                    if ((rd_mask_got || mask_pipe_out_valid) && (ml_exp_got || ml_rsp_valid) && data_mac_ready) begin
                        data_mac_valid        <= 1'b1;
                        data_mac_data         <= act_mac_cdata;
                        data_mac_mask         <= rd_mask_got ? rd_mask_q : mask_pipe_out_ct;
                        data_mac_major        <= act_mac_maj;
                        data_mac_minor        <= act_mac_min;
                        data_mac_line_idx     <= act_mac_line;
                        data_mac_expected_tag <= ml_exp_got ? rd_mac_exp_tag_q : ml_rsp_rtag;
                        mac_fsm               <= MAC_RD_CALC;
                    end
                end

                MAC_RD_CALC: begin
                    if (data_mac_out_valid) begin
                        rd_mac_match    <= data_mac_match;
                        rd_mac_mismatch <= data_mac_mismatch;
                        rd_mac_done     <= 1'b1;
                        mac_fsm         <= MAC_RD_DONE;
                    end
                end

                MAC_RD_DONE: begin
                    mac_fsm <= MAC_IDLE;
                end

                default: mac_fsm <= MAC_IDLE;
            endcase
        end
    end

    //-------------------------------------------------------------------------
    // 6. Đơn vị sinh vector Tweak dùng chung (Shared Tweak Unit)
    //-------------------------------------------------------------------------
    logic         tweak_req_valid;
    wire          tweak_req_ready;
    logic [127:0] tweak_req_in;
    logic [7:0]   tweak_req_meta;

    wire          tweak_rsp_valid;
    wire  [127:0] tweak_rsp_t0, tweak_rsp_t1, tweak_rsp_t2, tweak_rsp_t3;
    wire  [7:0]   tweak_rsp_meta;

    qshield_xts_tweak_unit #(
        .MetaWidth(8)
    ) u_tweak_unit (
        .clk         (clk),
        .rst_n       (rst_n),
        .i_valid     (tweak_req_valid),
        .o_ready     (tweak_req_ready),
        .i_tweak     (tweak_req_in),
        .i_round_keys(k2_round_keys),
        .i_meta      (tweak_req_meta),
        .o_valid     (tweak_rsp_valid),
        .i_ready     (1'b1),
        .o_tweak0    (tweak_rsp_t0),
        .o_tweak1    (tweak_rsp_t1),
        .o_tweak2    (tweak_rsp_t2),
        .o_tweak3    (tweak_rsp_t3),
        .o_meta      (tweak_rsp_meta)
    );

    logic         wr_tweak_req_valid;
    logic [127:0] wr_tweak_req_in;
    logic [7:0]   wr_tweak_req_meta;
    logic         wr_tweak_req_ack;

    logic         rd_tweak_req_valid;
    logic [127:0] rd_tweak_req_in;
    logic [7:0]   rd_tweak_req_meta;
    logic         rd_tweak_req_ack;

    logic         reenc_tweak_req_valid;
    logic [127:0] reenc_tweak_req_in;
    logic [7:0]   reenc_tweak_req_meta;
    logic         reenc_tweak_req_ack;

    logic arb_last;

    always_comb begin
        tweak_req_valid     = 1'b0;
        tweak_req_in        = 128'h0;
        tweak_req_meta      = 8'h0;
        wr_tweak_req_ack    = 1'b0;
        rd_tweak_req_ack    = 1'b0;
        reenc_tweak_req_ack = 1'b0;

        if (reenc_tweak_req_valid) begin
            tweak_req_valid     = 1'b1;
            tweak_req_in        = reenc_tweak_req_in;
            tweak_req_meta      = reenc_tweak_req_meta;
            reenc_tweak_req_ack = tweak_req_ready;
        end else if (arb_last == 1'b0) begin
            if (rd_tweak_req_valid) begin
                tweak_req_valid  = 1'b1;
                tweak_req_in     = rd_tweak_req_in;
                tweak_req_meta   = rd_tweak_req_meta;
                rd_tweak_req_ack = tweak_req_ready;
            end else if (wr_tweak_req_valid) begin
                tweak_req_valid  = 1'b1;
                tweak_req_in     = wr_tweak_req_in;
                tweak_req_meta   = wr_tweak_req_meta;
                wr_tweak_req_ack = tweak_req_ready;
            end
        end else begin
            if (wr_tweak_req_valid) begin
                tweak_req_valid  = 1'b1;
                tweak_req_in     = wr_tweak_req_in;
                tweak_req_meta   = wr_tweak_req_meta;
                wr_tweak_req_ack = tweak_req_ready;
            end else if (rd_tweak_req_valid) begin
                tweak_req_valid  = 1'b1;
                tweak_req_in     = rd_tweak_req_in;
                tweak_req_meta   = rd_tweak_req_meta;
                rd_tweak_req_ack = tweak_req_ready;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arb_last <= 1'b0;
        end else if (tweak_req_valid && tweak_req_ready && !tweak_req_meta[7]) begin
            arb_last <= tweak_req_meta[6];
        end
    end

    //-------------------------------------------------------------------------
    // 7. Kiểm tra điều kiện đủ tư cách giao dịch (Qualification)
    //-------------------------------------------------------------------------
    wire aw_is_incr    = (s_axi_awburst == 2'b01);
    wire aw_is_size3   = (s_axi_awsize  == 3'b011);
    wire aw_is_aligned = (s_axi_awaddr[5:0] == 6'h0);
    wire aw_is_full64  = (s_axi_awlen   == 8'd7);
    wire aw_in_prot    = (s_axi_awaddr >= eff_prot_base) && (s_axi_awaddr < eff_prot_end);
    wire aw_is_meta    = (s_axi_awaddr >= eff_cb_base);

    wire aw_qualified  = keys_ready && aw_is_incr && aw_is_size3 &&
                         aw_is_aligned && aw_is_full64 &&
                         (!eff_integ_enable || (reg_meta_init_ever_done && aw_in_prot && !aw_is_meta));

    wire ar_is_incr    = (s_axi_arburst == 2'b01);
    wire ar_is_size3   = (s_axi_arsize  == 3'b011);
    wire ar_is_aligned = (s_axi_araddr[5:0] == 6'h0);
    wire ar_is_full64  = (s_axi_arlen   == 8'd7);
    wire ar_in_prot    = (s_axi_araddr >= eff_prot_base) && (s_axi_araddr < eff_prot_end);
    wire ar_is_meta    = (s_axi_araddr >= eff_cb_base);

    wire ar_qualified  = keys_ready && ar_is_incr && ar_is_size3 &&
                         ar_is_aligned && ar_is_full64 &&
                         (!eff_integ_enable || (reg_meta_init_ever_done && ar_in_prot && !ar_is_meta));

    //-------------------------------------------------------------------------
    // 8. Đường ghi (Write Path): AW FIFO, mã hoá AES-XTS, MAC, BMT & Re-encrypt S7
    //-------------------------------------------------------------------------
    logic [AXI_ID_WIDTH-1:0]   aw_fifo_id    [4];
    logic [AXI_ADDR_WIDTH-1:0] aw_fifo_addr  [4];
    logic [AXI_LEN_WIDTH-1:0]  aw_fifo_len   [4];
    logic [AXI_QOS_WIDTH-1:0]  aw_fifo_qos   [4];
    logic [1:0]                aw_fifo_burst [4];
    logic [2:0]                aw_fifo_size  [4];
    logic [3:0]                aw_fifo_asid  [4];
    logic [18:0]               aw_fifo_epoch [4];
    logic                      aw_fifo_is_bypass [4];
    logic                      aw_fifo_is_reject [4];

    logic [1:0] aw_wr_ptr;
    logic [1:0] aw_rd_ptr;
    logic [2:0] aw_count;

    logic [127:0] wr_tweak_tbl_t0 [4];
    logic [127:0] wr_tweak_tbl_t1 [4];
    logic [127:0] wr_tweak_tbl_t2 [4];
    logic [127:0] wr_tweak_tbl_t3 [4];
    logic         wr_tweak_valid  [4];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 4; i++) wr_tweak_valid[i] <= 1'b0;
        end else begin
            if (tweak_rsp_valid && !tweak_rsp_meta[7] && (tweak_rsp_meta[6] == 1'b0)) begin
                wr_tweak_tbl_t0[tweak_rsp_meta[1:0]] <= tweak_rsp_t0;
                wr_tweak_tbl_t1[tweak_rsp_meta[1:0]] <= tweak_rsp_t1;
                wr_tweak_tbl_t2[tweak_rsp_meta[1:0]] <= tweak_rsp_t2;
                wr_tweak_tbl_t3[tweak_rsp_meta[1:0]] <= tweak_rsp_t3;
                wr_tweak_valid[tweak_rsp_meta[1:0]]  <= 1'b1;
            end
            if (s_axi_bvalid && s_axi_bready) begin
                wr_tweak_valid[aw_rd_ptr] <= 1'b0;
            end
        end
    end

    //-------------------------------------------------------------------------
    // Khai báo cấu trúc hàng đợi đọc (AR FIFO) và FSM Re-encryption nền (S7)
    //-------------------------------------------------------------------------
    (* ram_style = "distributed" *) logic [AXI_ADDR_WIDTH-1:0] rd_fifo_addr  [64];
    (* ram_style = "distributed" *) logic [AXI_LEN_WIDTH-1:0]  rd_fifo_len   [64];
    (* ram_style = "distributed" *) logic [3:0]                rd_fifo_asid  [64];
    (* ram_style = "distributed" *) logic [18:0]               rd_fifo_epoch [64];
    (* ram_style = "distributed" *) logic [127:0]              rd_fifo_tweak0 [64];
    (* ram_style = "distributed" *) logic [127:0]              rd_fifo_tweak1 [64];
    (* ram_style = "distributed" *) logic [127:0]              rd_fifo_tweak2 [64];
    (* ram_style = "distributed" *) logic [127:0]              rd_fifo_tweak3 [64];
    logic                      rd_fifo_tweak_valid [64];
    logic                      rd_fifo_is_bypass   [64];
    (* ram_style = "distributed" *) logic [63:0]               rd_fifo_maj   [64];
    (* ram_style = "distributed" *) logic [6:0]                rd_fifo_min   [64];
    logic                      rd_fifo_bmt_fail    [64];

    logic [1:0] rd_head  [16];
    logic [1:0] rd_tail  [16];
    logic [2:0] rd_count [16];

    wire [3:0] cur_arid = s_axi_arid[3:0];
    wire [5:0] cur_ar_slot = {cur_arid, rd_tail[cur_arid]};
    wire rd_id_full = (rd_count[cur_arid] == 3'd4);

    logic        rej_rd_active;
    logic [AXI_ID_WIDTH-1:0] rej_rd_id;
    logic [7:0]  rej_rd_len;
    logic [7:0]  rej_rd_beat_cnt;

    typedef enum logic [3:0] {
        REENC_IDLE      = 4'd0,
        REENC_WAIT_TRIG = 4'd1,
        REENC_SCAN      = 4'd2,
        REENC_YIELD     = 4'd3,
        REENC_FETCH_OLD = 4'd4,
        REENC_CHK_MAC   = 4'd5,
        REENC_DEC       = 4'd6,
        REENC_ENC       = 4'd7,
        REENC_COMMIT    = 4'd8,
        REENC_NEXT      = 4'd9
    } reenc_fsm_t;
    reenc_fsm_t reenc_state;

    logic         reenc_active;
    logic         reenc_trigger_pulse;
    logic [511:0] reenc_trig_old_cb;
    logic [19:0]  reenc_trig_cb_idx;
    logic [63:0]  reenc_trig_new_maj;
    logic [5:0]   reenc_trig_slot_w;
    logic [3:0]   reenc_trig_asid_w;

    logic [511:0] reenc_old_cb;
    logic [19:0]  reenc_cb_idx;
    logic [63:0]  reenc_old_maj;
    logic [63:0]  reenc_new_maj;
    logic [5:0]   reenc_trig_slot;
    logic [3:0]   reenc_asid;
    logic [5:0]   reenc_slot;
    logic [6:0]   reenc_cur_min;
    logic [63:0]  reenc_sib_addr;
    logic [511:0] reenc_line_buf;
    logic [127:0] reenc_oldt0, reenc_oldt1, reenc_oldt2, reenc_oldt3;
    logic [127:0] reenc_newt0, reenc_newt1, reenc_newt2, reenc_newt3;
    logic         reenc_got_dram;
    logic         reenc_got_oldtweak;
    logic         reenc_got_mac_chk;
    logic         reenc_mac_ok;
    logic         reenc_got_newtweak;
    logic [2:0]   reenc_blk_in;
    logic [2:0]   reenc_blk_out;
    logic         reenc_got_mac_wr;
    logic         reenc_got_dram_wr;

    wire reenc_step_busy = (reenc_state != REENC_IDLE) &&
                           (reenc_state != REENC_WAIT_TRIG) &&
                           (reenc_state != REENC_SCAN) &&
                           (reenc_state != REENC_YIELD);

    // Chặn giao dịch tới đúng CB đang re-encrypt; các CB khác đi bình thường khi không kẹt step
    wire [19:0] aw_cb_idx = 20'((s_axi_awaddr - eff_prot_base) >> 12);
    wire [19:0] ar_cb_idx = 20'((s_axi_araddr - eff_prot_base) >> 12);
    wire reenc_aw_block = eff_integ_enable && reenc_active &&
                          (reenc_step_busy || (aw_in_prot && (aw_cb_idx == reenc_cb_idx)));
    wire reenc_ar_block = eff_integ_enable && reenc_active &&
                          (reenc_step_busy || (ar_in_prot && (ar_cb_idx == reenc_cb_idx)));

    // FSM đồng bộ xác minh và cập nhật BMT cho cả luồng Ghi và Đọc
    typedef enum logic [1:0] {
        BMT_IDLE,
        BMT_WAIT_VERIFY,
        BMT_WAIT_UPDATE
    } bmt_fsm_t;
    bmt_fsm_t bmt_state;

    logic        bmt_req_is_read;
    logic        bmt_req_is_force_minor;
    logic [5:0]  bmt_req_rd_slot;
    logic        bmt_wr_rejected_alert;

`ifdef QSHIELD_TEST
    logic [6:0]  test_force_minor_val_q;
`endif

    wire bmt_can_accept = (bmt_state == BMT_IDLE) && !bmt_verify_valid && !reenc_step_busy;
    assign s_axi_awready = (aw_count < 3'd4) && (!eff_integ_enable || (bmt_can_accept && !reenc_aw_block && (aw_count == 3'd0)));
    wire aw_fire = s_axi_awvalid && s_axi_awready;

    wire ar_bridge_ready = !rej_rd_active && !rd_id_full && !meta_rd_active && !reenc_ar_block &&
                           (!eff_integ_enable || (bmt_can_accept && !s_axi_awvalid && !user_rd_pending));
    assign s_axi_arready = ar_bridge_ready && (i_enc_enable ? 1'b1 : m_axi_arready);
    wire ar_fire = s_axi_arvalid && s_axi_arready;

    // Quản lý BMT verify và update cho Ghi & Đọc
    logic [63:0] cur_wr_maj;
    logic [6:0]  cur_wr_min;

    logic                      user_rd_pending;
    logic [5:0]                user_rd_slot;
    logic [AXI_ID_WIDTH-1:0]   user_rd_id;
    logic [AXI_ADDR_WIDTH-1:0] user_rd_addr;
    logic [7:0]                user_rd_len;
    logic [AXI_QOS_WIDTH-1:0]  user_rd_qos;
    logic                      user_rd_dispatch;
    logic                      user_rd_tweak_ready_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bmt_state              <= BMT_IDLE;
            bmt_req_is_read        <= 1'b0;
            bmt_req_is_force_minor <= 1'b0;
            bmt_req_rd_slot        <= 6'd0;
            bmt_wr_rejected_alert  <= 1'b0;
            aw_wr_ptr              <= 2'd0;
            aw_count               <= 3'd0;
            reject_cnt_reg         <= 16'h0;
            wr_tweak_req_valid     <= 1'b0;
            wr_tweak_req_in        <= 128'h0;
            wr_tweak_req_meta      <= 8'h0;
            bmt_verify_valid       <= 1'b0;
            bmt_verify_addr        <= 64'h0;
            bmt_update_valid       <= 1'b0;
            bmt_update_addr        <= 64'h0;
            bmt_update_cb_data     <= 512'h0;
            reg_reencrypt_events   <= 32'h0;
            cur_wr_maj             <= 64'h0;
            cur_wr_min             <= 7'h1;
            user_rd_pending        <= 1'b0;
            user_rd_slot           <= 6'd0;
            user_rd_id             <= '0;
            user_rd_addr           <= 32'h0;
            user_rd_len            <= 8'h0;
            user_rd_qos            <= '0;
            user_rd_dispatch       <= 1'b0;
            user_rd_tweak_ready_q  <= 1'b0;
            reenc_trigger_pulse    <= 1'b0;
            reenc_trig_old_cb      <= 512'h0;
            reenc_trig_cb_idx      <= 20'd0;
            reenc_trig_new_maj     <= 64'h0;
            reenc_trig_slot_w      <= 6'd0;
            reenc_trig_asid_w      <= 4'h0;
`ifdef QSHIELD_TEST
            o_test_force_minor_done <= 1'b0;
            test_force_minor_val_q  <= 7'd0;
`endif
        end else begin
            reenc_trigger_pulse   <= 1'b0;
            bmt_wr_rejected_alert <= 1'b0;
`ifdef QSHIELD_TEST
            o_test_force_minor_done <= 1'b0;
`endif
            if (wr_tweak_req_ack) begin
                wr_tweak_req_valid <= 1'b0;
            end
            if (bmt_verify_valid && bmt_verify_ready) begin
                bmt_verify_valid <= 1'b0;
            end
            if (bmt_update_valid && bmt_update_ready) begin
                bmt_update_valid <= 1'b0;
            end
            if (tweak_rsp_valid && !tweak_rsp_meta[7] && (tweak_rsp_meta[6] == 1'b1) &&
                user_rd_dispatch && ({tweak_rsp_meta[5:2], tweak_rsp_meta[1:0]} == user_rd_slot)) begin
                user_rd_tweak_ready_q <= 1'b1;
            end
            if (m_axi_arvalid && m_axi_arready && (m_axi_arid[3] == 1'b0) && user_rd_dispatch) begin
                user_rd_dispatch      <= 1'b0;
                user_rd_pending       <= 1'b0;
                user_rd_tweak_ready_q <= 1'b0;
            end

            case (bmt_state)
                BMT_IDLE: begin
`ifdef QSHIELD_TEST
                    if (i_test_force_minor_valid && !reenc_active && !reenc_step_busy) begin
                        bmt_verify_valid       <= 1'b1;
                        bmt_verify_addr        <= i_test_force_minor_addr;
                        bmt_req_is_read        <= 1'b0;
                        bmt_req_is_force_minor <= 1'b1;
                        test_force_minor_val_q <= i_test_force_minor_val;
                        bmt_state              <= BMT_WAIT_VERIFY;
                    end else
`endif
                    if (aw_fire && eff_integ_enable && aw_qualified) begin
                        bmt_verify_valid       <= 1'b1;
                        bmt_verify_addr        <= s_axi_awaddr;
                        bmt_req_is_read        <= 1'b0;
                        bmt_req_is_force_minor <= 1'b0;
                        bmt_state              <= BMT_WAIT_VERIFY;
                    end else if (ar_fire && eff_integ_enable && ar_qualified) begin
                        bmt_verify_valid       <= 1'b1;
                        bmt_verify_addr        <= s_axi_araddr;
                        bmt_req_is_read        <= 1'b1;
                        bmt_req_is_force_minor <= 1'b0;
                        bmt_req_rd_slot        <= cur_ar_slot;
                        bmt_state              <= BMT_WAIT_VERIFY;
                        user_rd_pending        <= 1'b1;
                        user_rd_slot           <= cur_ar_slot;
                        user_rd_id             <= s_axi_arid;
                        user_rd_addr           <= s_axi_araddr;
                        user_rd_len            <= s_axi_arlen;
                        user_rd_qos            <= s_axi_arqos;
                        user_rd_dispatch       <= 1'b0;
                        user_rd_tweak_ready_q  <= 1'b0;
                    end
                end

                BMT_WAIT_VERIFY: begin
                    if (bmt_verify_done) begin
`ifdef QSHIELD_TEST
                        if (bmt_req_is_force_minor) begin
                            if (bmt_verify_pass) begin
                                logic [511:0] f_cb;
                                f_cb = bmt_cb_data;
                                f_cb[bmt_cb_slot * 7 +: 7] = test_force_minor_val_q;
                                bmt_update_valid   <= 1'b1;
                                bmt_update_addr    <= bmt_verify_addr;
                                bmt_update_cb_data <= f_cb;
                                bmt_state          <= BMT_WAIT_UPDATE;
                            end else begin
                                bmt_req_is_force_minor <= 1'b0;
                                bmt_state              <= BMT_IDLE;
                            end
                        end else
`endif
                        if (!bmt_req_is_read) begin
                            // Xác minh xong cho luồng Ghi
                            if (bmt_verify_pass) begin
                                logic [63:0] c_maj;
                                logic [6:0]  c_min;
                                c_maj = bmt_cb_data[511:448];
                                c_min = bmt_cb_data[bmt_cb_slot * 7 +: 7];

                                if (c_min == 7'd127) begin
                                    reg_reencrypt_events <= reg_reencrypt_events + 1'b1;
                                    cur_wr_maj           <= c_maj + 1'b1;
                                    cur_wr_min           <= 7'd0;

                                    bmt_update_valid     <= 1'b1;
                                    bmt_update_addr      <= aw_fifo_addr[aw_rd_ptr];
                                    bmt_update_cb_data   <= {c_maj + 1'b1, 448'h0};

                                    wr_tweak_req_valid   <= 1'b1;
                                    wr_tweak_req_in      <= {c_maj + 1'b1, 7'd0, aw_fifo_asid[aw_rd_ptr], 27'h0, aw_fifo_addr[aw_rd_ptr][31:6]};
                                    wr_tweak_req_meta    <= {1'b0, 1'b0, 4'h0, aw_rd_ptr};

                                    // Kích hoạt FSM re-encryption toàn bộ sibling đã ghi của CB này
                                    reenc_trigger_pulse  <= 1'b1;
                                    reenc_trig_old_cb    <= bmt_cb_data;
                                    reenc_trig_cb_idx    <= 20'((aw_fifo_addr[aw_rd_ptr] - eff_prot_base) >> 12);
                                    reenc_trig_new_maj   <= c_maj + 1'b1;
                                    reenc_trig_slot_w    <= bmt_cb_slot;
                                    reenc_trig_asid_w    <= aw_fifo_asid[aw_rd_ptr];
                                end else begin
                                    logic [511:0] n_cb;
                                    n_cb = bmt_cb_data;
                                    n_cb[bmt_cb_slot * 7 +: 7] = c_min + 1'b1;

                                    cur_wr_maj         <= c_maj;
                                    cur_wr_min         <= c_min + 1'b1;

                                    bmt_update_valid   <= 1'b1;
                                    bmt_update_addr    <= aw_fifo_addr[aw_rd_ptr];
                                    bmt_update_cb_data <= n_cb;

                                    wr_tweak_req_valid <= 1'b1;
                                    wr_tweak_req_in    <= {c_maj, c_min + 1'b1, aw_fifo_asid[aw_rd_ptr], 27'h0, aw_fifo_addr[aw_rd_ptr][31:6]};
                                    wr_tweak_req_meta  <= {1'b0, 1'b0, 4'h0, aw_rd_ptr};
                                end
                                bmt_state <= BMT_WAIT_UPDATE;
                            end else begin
                                bmt_wr_rejected_alert        <= 1'b1;
                                aw_fifo_is_reject[aw_rd_ptr] <= 1'b1;
                                bmt_state                    <= BMT_IDLE;
                            end
                        end else begin
                            // Xác minh xong cho luồng Đọc
                            if (bmt_verify_pass) begin
                                logic [63:0] c_maj;
                                logic [6:0]  c_min;
                                c_maj = bmt_cb_data[511:448];
                                c_min = bmt_cb_data[bmt_cb_slot * 7 +: 7];

                                rd_fifo_bmt_fail[bmt_req_rd_slot] <= 1'b0;

                                rd_tweak_req_valid    <= 1'b1;
                                rd_tweak_req_in       <= {c_maj, c_min, rd_fifo_asid[bmt_req_rd_slot], 27'h0, rd_fifo_addr[bmt_req_rd_slot][31:6]};
                                rd_tweak_req_meta     <= {1'b0, 1'b1, bmt_req_rd_slot[5:2], bmt_req_rd_slot[1:0]};
                                user_rd_dispatch      <= 1'b1;
                                user_rd_tweak_ready_q <= !i_enc_enable;
                            end else begin
                                rd_fifo_bmt_fail[bmt_req_rd_slot]    <= 1'b1;
                                rd_fifo_tweak_valid[bmt_req_rd_slot] <= 1'b1;
                                bmt_wr_rejected_alert                <= 1'b1;
                                user_rd_pending       <= 1'b0;
                                user_rd_dispatch      <= 1'b0;
                                user_rd_tweak_ready_q <= 1'b0;
                                rd_stream_active  <= 1'b1;
                                rd_stream_fail    <= 1'b1;
                                rd_stream_id      <= user_rd_id;
                                rd_stream_beat    <= 3'd0;
                            end
                            bmt_state <= BMT_IDLE;
                        end
                    end
                end

                BMT_WAIT_UPDATE: begin
                    if (bmt_update_done) begin
`ifdef QSHIELD_TEST
                        if (bmt_req_is_force_minor) begin
                            o_test_force_minor_done <= 1'b1;
                            bmt_req_is_force_minor  <= 1'b0;
                        end
`endif
                        bmt_state <= BMT_IDLE;
                    end
                end
            endcase

            if (aw_fire) begin
                aw_fifo_id[aw_wr_ptr]    <= s_axi_awid;
                aw_fifo_addr[aw_wr_ptr]  <= s_axi_awaddr;
                aw_fifo_len[aw_wr_ptr]   <= s_axi_awlen;
                aw_fifo_qos[aw_wr_ptr]   <= s_axi_awqos;
                aw_fifo_burst[aw_wr_ptr] <= s_axi_awburst;
                aw_fifo_size[aw_wr_ptr]  <= s_axi_awsize;
                aw_fifo_asid[aw_wr_ptr]  <= i_asid;
                aw_fifo_epoch[aw_wr_ptr] <= i_epoch;

                if (!i_enc_enable) begin
                    aw_fifo_is_bypass[aw_wr_ptr] <= 1'b1;
                    aw_fifo_is_reject[aw_wr_ptr] <= 1'b0;
                end else if (!aw_qualified) begin
                    aw_fifo_is_bypass[aw_wr_ptr] <= 1'b0;
                    aw_fifo_is_reject[aw_wr_ptr] <= 1'b1;
                    if (reject_cnt_reg != 16'hFFFF) reject_cnt_reg <= reject_cnt_reg + 1'b1;
                end else if (eff_integ_enable) begin
                    aw_fifo_is_bypass[aw_wr_ptr] <= 1'b0;
                    aw_fifo_is_reject[aw_wr_ptr] <= 1'b0;
                end else begin
                    aw_fifo_is_bypass[aw_wr_ptr] <= 1'b0;
                    aw_fifo_is_reject[aw_wr_ptr] <= 1'b0;
                    wr_tweak_req_valid <= 1'b1;
                    wr_tweak_req_in    <= {47'h0, i_epoch[18:0], i_asid[3:0], 32'h0, s_axi_awaddr[31:6]};
                    wr_tweak_req_meta  <= {1'b0, 1'b0, 4'h0, aw_wr_ptr};
                end

                aw_wr_ptr <= aw_wr_ptr + 1'b1;
                aw_count  <= aw_count + 1'b1;
            end else if (s_axi_bvalid && s_axi_bready && (aw_count > 0)) begin
                aw_count <= aw_count - 1'b1;
            end
        end
    end

    wire cur_aw_valid     = (aw_count > 0);
    wire cur_aw_is_bypass = aw_fifo_is_bypass[aw_rd_ptr];
    wire cur_aw_is_reject = aw_fifo_is_reject[aw_rd_ptr];

    logic aw_sent_to_core;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_sent_to_core <= 1'b0;
        end else if (s_axi_bvalid && s_axi_bready) begin
            aw_sent_to_core <= 1'b0;
        end else if (m_axi_awvalid && m_axi_awready && (m_axi_awid[3] == 1'b0)) begin
            aw_sent_to_core <= 1'b1;
        end
    end

    logic         reenc_enc_in_valid;
    logic [127:0] reenc_enc_in_data;
    logic [127:0] reenc_enc_in_tweak;
    logic         reenc_dec_in_valid;
    logic [127:0] reenc_dec_in_data;
    logic [127:0] reenc_dec_in_tweak;
    logic         reenc_fail_alert_pulse;

    wire user_aw_valid = cur_aw_valid && !cur_aw_is_reject && !aw_sent_to_core &&
                         (wr_bus_owner != WR_META) && !reenc_step_busy &&
                         (!eff_integ_enable || cur_aw_is_bypass || wr_tweak_valid[aw_rd_ptr]);

    always_comb begin
        if (meta_aw_valid) begin
            m_axi_awvalid = 1'b1;
            m_axi_awid    = meta_wr_id; // 4'b1000: BMT, 4'b1001: ML, 4'b1010: Re-encrypt
            m_axi_awaddr  = meta_wr_addr[31:0];
            m_axi_awlen   = 8'd7;
            m_axi_awsize  = 3'b011;
            m_axi_awburst = 2'b01;
            m_axi_awqos   = 4'h0;
        end else begin
            m_axi_awvalid = user_aw_valid;
            m_axi_awid    = {1'b0, aw_fifo_id[aw_rd_ptr][2:0]};
            m_axi_awaddr  = aw_fifo_addr[aw_rd_ptr];
            m_axi_awlen   = aw_fifo_len[aw_rd_ptr];
            m_axi_awsize  = aw_fifo_size[aw_rd_ptr];
            m_axi_awburst = aw_fifo_burst[aw_rd_ptr];
            m_axi_awqos   = aw_fifo_qos[aw_rd_ptr];
        end
    end

    // Ghép cặp beat ghi W
    logic [63:0] wdata_b0_reg;
    logic        w_phase;
    logic [7:0]  w_beat_cnt;
    logic        w_has_partial_strb;

    logic         enc_in_valid;
    wire          enc_in_ready;
    logic [127:0] enc_in_data;
    logic [127:0] enc_in_tweak;
    logic [5:0]   enc_in_meta;

    wire          enc_out_valid;
    logic         enc_out_ready;
    wire  [127:0] enc_out_data;
    wire  [5:0]   enc_out_meta;
    wire          enc_lane_busy;

    aes_xts_lane #(
        .NumRounds (14),
        .DataWidth (128),
        .TweakWidth(128),
        .MetaWidth (6)
    ) u_enc_lane (
        .clk       (clk),
        .rst_n     (rst_n),
        .enc_enable(1'b1),
        .lane_busy (enc_lane_busy),
        .round_keys(k1_rk),
        .valid_in  (enc_in_valid),
        .ready_in  (enc_in_ready),
        .data_in   (enc_in_data),
        .tweak_in  (enc_in_tweak),
        .meta_in   (enc_in_meta),
        .valid_out (enc_out_valid),
        .ready_out (enc_out_ready),
        .data_out  (enc_out_data),
        .meta_out  (enc_out_meta)
    );

    wire [AXI_ADDR_WIDTH-1:0] cur_wr_addr = aw_fifo_addr[aw_rd_ptr];
    wire [1:0] cur_wr_addr_slice = cur_wr_addr[5:4];
    wire [1:0] cur_block_idx = (w_beat_cnt[7:1]) + cur_wr_addr_slice;

    logic [127:0] sel_wr_tweak;
    always_comb begin
        case (cur_block_idx)
            2'b00: sel_wr_tweak = wr_tweak_tbl_t0[aw_rd_ptr];
            2'b01: sel_wr_tweak = wr_tweak_tbl_t1[aw_rd_ptr];
            2'b10: sel_wr_tweak = wr_tweak_tbl_t2[aw_rd_ptr];
            default: sel_wr_tweak = wr_tweak_tbl_t3[aw_rd_ptr];
        endcase
    end

    wire w_strb_full = (s_axi_wstrb == 8'hFF);

    always_comb begin
        s_axi_wready = 1'b0;
        enc_in_valid = 1'b0;
        enc_in_data  = 128'h0;
        enc_in_tweak = 128'h0;
        enc_in_meta  = 6'h0;

        if (reenc_step_busy) begin
            enc_in_valid = reenc_enc_in_valid;
            enc_in_data  = reenc_enc_in_data;
            enc_in_tweak = reenc_enc_in_tweak;
            enc_in_meta  = 6'h0;
        end else if (cur_aw_valid) begin
            if (cur_aw_is_bypass) begin
                s_axi_wready = (wr_bus_owner != WR_META) && !meta_w_valid && m_axi_wready;
            end else if (cur_aw_is_reject || w_has_partial_strb) begin
                s_axi_wready = 1'b1;
            end else begin
                if (w_phase == 1'b0) begin
                    s_axi_wready = 1'b1;
                end else begin
                    enc_in_valid = s_axi_wvalid && wr_tweak_valid[aw_rd_ptr];
                    enc_in_data  = {s_axi_wdata, wdata_b0_reg};
                    enc_in_tweak = sel_wr_tweak;
                    enc_in_meta  = {s_axi_wlast, !w_strb_full, aw_fifo_id[aw_rd_ptr]};
                    s_axi_wready = enc_in_ready && wr_tweak_valid[aw_rd_ptr];
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_phase            <= 1'b0;
            w_beat_cnt         <= 8'h0;
            wdata_b0_reg       <= 64'h0;
            w_has_partial_strb <= 1'b0;
        end else if (cur_aw_valid && !reenc_step_busy && s_axi_wvalid && s_axi_wready) begin
            if (s_axi_wlast) begin
                w_phase            <= 1'b0;
                w_beat_cnt         <= 8'h0;
                w_has_partial_strb <= 1'b0;
            end else begin
                w_beat_cnt <= w_beat_cnt + 1'b1;
                if (!cur_aw_is_bypass && !cur_aw_is_reject) begin
                    if (w_phase == 1'b0) begin
                        wdata_b0_reg <= s_axi_wdata;
                        if (!w_strb_full) w_has_partial_strb <= 1'b1;
                        w_phase <= 1'b1;
                    end else begin
                        if (!w_strb_full) w_has_partial_strb <= 1'b1;
                        w_phase <= 1'b0;
                    end
                end
            end
        end
    end

    // Phân tách khối 128 bit mã hoá ra 2 beat 64-bit gửi vào m_axi_w
    logic [63:0] enc_out_b1_reg;
    logic        enc_out_phase;
    logic        enc_out_last_reg;

    // Thu thập ciphertext của dòng ghi để tính MAC
    logic [511:0] wr_ct_accum;
    logic [1:0]   wr_enc_block_cnt;

    always_comb begin
        enc_out_ready = 1'b0;
        m_axi_wvalid  = 1'b0;
        m_axi_wdata   = 64'h0;
        m_axi_wstrb   = 8'hFF;
        m_axi_wlast   = 1'b0;

        if (meta_w_valid) begin
            m_axi_wvalid = 1'b1;
            m_axi_wdata  = meta_wr_data[meta_wr_beat * 64 +: 64];
            m_axi_wstrb  = 8'hFF;
            m_axi_wlast  = (meta_wr_beat == 3'd7);
        end else if (reenc_step_busy) begin
            enc_out_ready = 1'b1;
        end else if (cur_aw_valid && cur_aw_is_bypass && (wr_bus_owner != WR_META)) begin
            m_axi_wvalid = s_axi_wvalid;
            m_axi_wdata  = s_axi_wdata;
            m_axi_wstrb  = s_axi_wstrb;
            m_axi_wlast  = s_axi_wlast;
        end else if (enc_out_phase == 1'b1) begin
            m_axi_wvalid = 1'b1;
            m_axi_wdata  = enc_out_b1_reg;
            m_axi_wstrb  = 8'hFF;
            m_axi_wlast  = enc_out_last_reg;
        end else if (enc_out_valid && (wr_bus_owner != WR_META)) begin
            m_axi_wvalid  = 1'b1;
            m_axi_wdata   = enc_out_data[63:0];
            m_axi_wstrb   = 8'hFF;
            m_axi_wlast   = 1'b0;
            enc_out_ready = m_axi_wready;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enc_out_phase    <= 1'b0;
            enc_out_b1_reg   <= 64'h0;
            enc_out_last_reg <= 1'b0;
            wr_ct_accum      <= 512'h0;
            wr_enc_block_cnt <= 2'd0;
            wr_mac_req       <= 1'b0;
            wr_mac_cdata     <= 512'h0;
            wr_mac_maj       <= 64'h0;
            wr_mac_min       <= 7'h0;
            wr_mac_line      <= 49'h0;
        end else begin
            if (wr_mac_done) begin
                wr_mac_req <= 1'b0;
            end

            if (enc_out_phase == 1'b0) begin
                if (enc_out_valid && m_axi_wready && !reenc_step_busy && !cur_aw_is_bypass && !meta_w_valid && (wr_bus_owner != WR_META)) begin
                    enc_out_b1_reg   <= enc_out_data[127:64];
                    enc_out_last_reg <= enc_out_meta[5];
                    enc_out_phase    <= 1'b1;

                    wr_ct_accum[wr_enc_block_cnt * 128 +: 128] <= enc_out_data;
                    if (enc_out_meta[5] || (wr_enc_block_cnt == 2'd3)) begin
                        wr_enc_block_cnt <= 2'd0;
                        if (eff_integ_enable) begin
                            wr_mac_req   <= 1'b1;
                            wr_mac_cdata <= {enc_out_data, wr_ct_accum[383:0]};
                            wr_mac_maj   <= cur_wr_maj;
                            wr_mac_min   <= cur_wr_min;
                            wr_mac_line  <= 49'(cur_wr_addr[31:6]);
                        end
                    end else begin
                        wr_enc_block_cnt <= wr_enc_block_cnt + 1'b1;
                    end
                end
            end else begin
                if (m_axi_wready) begin
                    enc_out_phase <= 1'b0;
                end
            end
        end
    end

    // Phản hồi ghi B
    logic reject_bvalid;
    logic [AXI_ID_WIDTH-1:0] reject_bid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reject_bvalid <= 1'b0;
            reject_bid    <= '0;
        end else if (cur_aw_valid && !reenc_step_busy && (cur_aw_is_reject || w_has_partial_strb) && s_axi_wvalid && s_axi_wready && s_axi_wlast) begin
            reject_bvalid <= 1'b1;
            reject_bid    <= aw_fifo_id[aw_rd_ptr];
        end else if (reject_bvalid && s_axi_bready) begin
            reject_bvalid <= 1'b0;
        end
    end

    always_comb begin
        if (m_axi_bvalid && (m_axi_bid[3] == 1'b1)) begin
            m_axi_bready = 1'b1;
            s_axi_bvalid = 1'b0;
            s_axi_bid    = '0;
            s_axi_bresp  = 2'b00;
        end else if (reject_bvalid) begin
            s_axi_bvalid = 1'b1;
            s_axi_bid    = reject_bid;
            s_axi_bresp  = 2'b10;
            m_axi_bready = 1'b0;
        end else begin
            s_axi_bvalid = m_axi_bvalid && (m_axi_bid[3] == 1'b0) &&
                           (!eff_integ_enable || (!wr_mac_req && (mac_fsm == MAC_IDLE) && !ml_busy));
            s_axi_bid    = m_axi_bid;
            s_axi_bresp  = m_axi_bresp;
            m_axi_bready = s_axi_bready &&
                           (!eff_integ_enable || (!wr_mac_req && (mac_fsm == MAC_IDLE) && !ml_busy));
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_rd_ptr <= 2'd0;
        end else if (s_axi_bvalid && s_axi_bready && (aw_count > 0)) begin
            aw_rd_ptr <= aw_rd_ptr + 1'b1;
        end
    end

    //-------------------------------------------------------------------------
    // 9. Đường đọc (Read Path) & FSM Re-encryption nền cho sibling lines
    //-------------------------------------------------------------------------

    always_comb begin
        if (meta_rd_ar_pending) begin
            m_axi_arvalid = 1'b1;
            m_axi_arid    = meta_rd_id;
            m_axi_araddr  = meta_rd_addr[31:0];
            m_axi_arlen   = 8'd7;
            m_axi_arsize  = 3'b011;
            m_axi_arburst = 2'b01;
            m_axi_arqos   = 4'h0;
        // Thay mux 64:1 rd_fifo_tweak_valid[user_rd_slot] bằng FF 1-bit và tách m_axi_arvalid khỏi m_axi_arready để cắt vòng AR
        end else if (user_rd_dispatch && user_rd_tweak_ready_q) begin
            m_axi_arvalid = 1'b1;
            m_axi_arid    = {1'b0, user_rd_id[2:0]};
            m_axi_araddr  = user_rd_addr;
            m_axi_arlen   = user_rd_len;
            m_axi_arsize  = 3'b011;
            m_axi_arburst = 2'b01;
            m_axi_arqos   = user_rd_qos;
        end else begin
            m_axi_arvalid = (!eff_integ_enable) && s_axi_arvalid && ar_bridge_ready && (!i_enc_enable || ar_qualified);
            m_axi_arid    = {1'b0, s_axi_arid[2:0]};
            m_axi_araddr  = s_axi_araddr;
            m_axi_arlen   = s_axi_arlen;
            m_axi_arsize  = s_axi_arsize;
            m_axi_arburst = s_axi_arburst;
            m_axi_arqos   = s_axi_arqos;
        end
    end

    // Đệm bản rõ đã giải mã để chờ xác minh toàn vẹn (Non-speculative release)
    logic [63:0] rd_plain_buf [8];
    logic [2:0]  rd_plain_wptr;
    logic        rd_stream_active;
    logic        rd_stream_fail;
    logic [2:0]  rd_stream_beat;
    logic [AXI_ID_WIDTH-1:0] rd_stream_id;

    logic [63:0] cur_rd_maj;
    logic [6:0]  cur_rd_min;
    logic        cur_rd_bmt_fail;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 16; i++) begin
                rd_head[i]  <= 2'd0;
                rd_tail[i]  <= 2'd0;
                rd_count[i] <= 3'd0;
            end
            for (int j = 0; j < 64; j++) begin
                rd_fifo_tweak_valid[j] <= 1'b0;
                rd_fifo_is_bypass[j]   <= 1'b0;
                rd_fifo_bmt_fail[j]    <= 1'b0;
            end
            rej_rd_active      <= 1'b0;
            rej_rd_id          <= '0;
            rej_rd_len         <= 8'h0;
            rej_rd_beat_cnt    <= 8'h0;
            rd_tweak_req_valid <= 1'b0;
            rd_tweak_req_in    <= 128'h0;
            rd_tweak_req_meta  <= 8'h0;
            cur_rd_maj         <= 64'h0;
            cur_rd_min         <= 7'h1;
            cur_rd_bmt_fail    <= 1'b0;
        end else begin
            if (rd_tweak_req_ack) begin
                rd_tweak_req_valid <= 1'b0;
            end

            if (ar_fire) begin
                if (!i_enc_enable) begin
                    rd_fifo_is_bypass[cur_ar_slot]   <= 1'b1;
                    rd_fifo_tweak_valid[cur_ar_slot] <= 1'b1;
                    rd_tail[cur_arid]  <= rd_tail[cur_arid] + 1'b1;
                    rd_count[cur_arid] <= rd_count[cur_arid] + 1'b1;
                end else if (!ar_qualified) begin
                    rej_rd_active   <= 1'b1;
                    rej_rd_id       <= s_axi_arid;
                    rej_rd_len      <= s_axi_arlen;
                    rej_rd_beat_cnt <= 8'h0;
                    if (reject_cnt_reg != 16'hFFFF) reject_cnt_reg <= reject_cnt_reg + 1'b1;
                end else begin
                    rd_fifo_is_bypass[cur_ar_slot]   <= 1'b0;
                    rd_fifo_tweak_valid[cur_ar_slot] <= 1'b0;

                    if (!eff_integ_enable) begin
                        rd_tweak_req_valid <= 1'b1;
                        rd_tweak_req_in    <= {47'h0, i_epoch[18:0], i_asid[3:0], 32'h0, s_axi_araddr[31:6]};
                        rd_tweak_req_meta  <= {1'b0, 1'b1, cur_arid, rd_tail[cur_arid]};
                    end

                    rd_tail[cur_arid]  <= rd_tail[cur_arid] + 1'b1;
                    rd_count[cur_arid] <= rd_count[cur_arid] + 1'b1;
                end
            end

            if (tweak_rsp_valid && !tweak_rsp_meta[7] && (tweak_rsp_meta[6] == 1'b1)) begin
                logic [5:0] rsp_slot_idx;
                rsp_slot_idx = {tweak_rsp_meta[5:2], tweak_rsp_meta[1:0]};

                rd_fifo_tweak_valid[rsp_slot_idx] <= 1'b1;
            end

            if (rej_rd_active && s_axi_rvalid && s_axi_rready) begin
                if (rej_rd_beat_cnt == rej_rd_len) begin
                    rej_rd_active <= 1'b0;
                end else begin
                    rej_rd_beat_cnt <= rej_rd_beat_cnt + 1'b1;
                end
            end

            if (s_axi_rvalid && s_axi_rready && s_axi_rlast && !rej_rd_active) begin
                logic [3:0] fin_id;
                fin_id = s_axi_rid[3:0];
                if (rd_count[fin_id] > 0) begin
                    rd_head[fin_id]  <= rd_head[fin_id] + 1'b1;
                    rd_count[fin_id] <= rd_count[fin_id] - 1'b1;
                end
            end
        end
    end

    // No-reset distributed RAM write ports for read FIFO payload & tweaks (~1.4k LUT6 vs ~45k FFs)
`ifdef QSHIELD_TEST
    wire bmt_rd_maj_wr_en = (bmt_state == BMT_WAIT_VERIFY) && bmt_verify_done &&
                            !bmt_req_is_force_minor && bmt_req_is_read && bmt_verify_pass;
`else
    wire bmt_rd_maj_wr_en = (bmt_state == BMT_WAIT_VERIFY) && bmt_verify_done &&
                            bmt_req_is_read && bmt_verify_pass;
`endif
    wire       rd_tw_wr_en   = tweak_rsp_valid && !tweak_rsp_meta[7] && (tweak_rsp_meta[6] == 1'b1);
    wire [5:0] rd_tw_wr_addr = {tweak_rsp_meta[5:2], tweak_rsp_meta[1:0]};
    wire       ar_info_wr_en = ar_fire && (!i_enc_enable || ar_qualified);

    always_ff @(posedge clk) begin
        if (ar_info_wr_en) begin
            rd_fifo_addr[cur_ar_slot] <= s_axi_araddr;
            rd_fifo_len[cur_ar_slot]  <= s_axi_arlen;
        end
        if (ar_fire && i_enc_enable && ar_qualified) begin
            rd_fifo_asid[cur_ar_slot]  <= i_asid;
            rd_fifo_epoch[cur_ar_slot] <= i_epoch;
        end
        if (rd_tw_wr_en) begin
            rd_fifo_tweak0[rd_tw_wr_addr] <= tweak_rsp_t0;
            rd_fifo_tweak1[rd_tw_wr_addr] <= tweak_rsp_t1;
            rd_fifo_tweak2[rd_tw_wr_addr] <= tweak_rsp_t2;
            rd_fifo_tweak3[rd_tw_wr_addr] <= tweak_rsp_t3;
        end
        if (bmt_rd_maj_wr_en) begin
            rd_fifo_maj[bmt_req_rd_slot] <= bmt_cb_data[511:448];
            rd_fifo_min[bmt_req_rd_slot] <= bmt_cb_data[bmt_cb_slot * 7 +: 7];
        end
    end

    // Ghép cặp beat đọc R từ lõi: 2 beat 64-bit -> InvCipher
    logic [63:0] rdata_b0_reg;
    logic [1:0]  rresp_b0_reg;
    logic        r_phase;
    logic [7:0]  r_beat_cnt;

    localparam int DecMetaW = 1 + 2 + AXI_ID_WIDTH + 6 + 128;

    logic                 dec_in_valid;
    wire                  dec_in_ready;
    logic [127:0]         dec_in_data;
    logic [DecMetaW-1:0]  dec_in_meta;

    wire                  dec_out_valid;
    logic                 dec_out_ready;
    wire  [127:0]         dec_out_data;
    wire  [DecMetaW-1:0]  dec_out_meta;

    aes_inv_cipher_pipe #(
        .DataWidth(128),
        .MetaWidth(DecMetaW)
    ) u_dec_pipe (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (dec_in_valid),
        .in_ready  (dec_in_ready),
        .data_in   (dec_in_data),
        .meta_in   (dec_in_meta),
        .round_keys(k1_round_keys),
        .out_valid (dec_out_valid),
        .out_ready (dec_out_ready),
        .data_out  (dec_out_data),
        .meta_out  (dec_out_meta)
    );

    wire [3:0] cur_m_rid = m_axi_rid[3:0];
    wire [1:0] cur_m_head = rd_head[cur_m_rid];
    wire [5:0] cur_rd_slot_idx = {cur_m_rid, cur_m_head};

    wire cur_rd_is_bypass   = rd_fifo_is_bypass[cur_rd_slot_idx];
    wire cur_rd_tweak_valid = rd_fifo_tweak_valid[cur_rd_slot_idx];
    wire [AXI_ADDR_WIDTH-1:0] cur_rd_addr = rd_fifo_addr[cur_rd_slot_idx];
    wire [1:0] cur_rd_addr_slice = cur_rd_addr[5:4];
    wire [1:0] cur_rd_block_idx = (r_beat_cnt[7:1]) + cur_rd_addr_slice;

    logic [127:0] sel_rd_tweak;
    always_comb begin
        case (cur_rd_block_idx)
            2'b00: sel_rd_tweak = rd_fifo_tweak0[cur_rd_slot_idx];
            2'b01: sel_rd_tweak = rd_fifo_tweak1[cur_rd_slot_idx];
            2'b10: sel_rd_tweak = rd_fifo_tweak2[cur_rd_slot_idx];
            default: sel_rd_tweak = rd_fifo_tweak3[cur_rd_slot_idx];
        endcase
    end

    // Thu thập ciphertext đọc để kiểm tra MAC
    logic [511:0] rd_ct_buffer;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ct_buffer <= 512'h0;
        end else if (m_axi_rvalid && m_axi_rready && (m_axi_rid[3] == 1'b0)) begin
            rd_ct_buffer[r_beat_cnt * 64 +: 64] <= m_axi_rdata;
        end
    end

    always_comb begin
        m_axi_rready = 1'b0;
        dec_in_valid = 1'b0;
        dec_in_data  = 128'h0;
        dec_in_meta  = '0;

        if (reenc_step_busy) begin
            m_axi_rready = (m_axi_rid[3] == 1'b1);
            dec_in_valid = reenc_dec_in_valid;
            dec_in_data  = reenc_dec_in_data;
            dec_in_meta  = {{(DecMetaW-128){1'b0}}, reenc_dec_in_tweak};
        end else if (m_axi_rid[3] == 1'b1) begin
            m_axi_rready = 1'b1;
        end else if (cur_rd_is_bypass) begin
            m_axi_rready = s_axi_rready;
        end else begin
            if (r_phase == 1'b0) begin
                m_axi_rready = 1'b1;
            end else begin
                dec_in_valid = m_axi_rvalid && cur_rd_tweak_valid;
                dec_in_data  = {m_axi_rdata, rdata_b0_reg} ^ sel_rd_tweak;
                dec_in_meta  = {m_axi_rlast, (m_axi_rresp | rresp_b0_reg), m_axi_rid, cur_rd_slot_idx, sel_rd_tweak};
                m_axi_rready = dec_in_ready && cur_rd_tweak_valid;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_phase      <= 1'b0;
            r_beat_cnt   <= 8'h0;
            rdata_b0_reg <= 64'h0;
            rresp_b0_reg <= 2'b00;
        end else if (m_axi_rvalid && m_axi_rready && (m_axi_rid[3] == 1'b0)) begin
            if (m_axi_rlast) begin
                r_phase    <= 1'b0;
                r_beat_cnt <= 8'h0;
            end else begin
                r_beat_cnt <= r_beat_cnt + 1'b1;
                if (!cur_rd_is_bypass) begin
                    if (r_phase == 1'b0) begin
                        rdata_b0_reg <= m_axi_rdata;
                        rresp_b0_reg <= m_axi_rresp;
                        r_phase      <= 1'b1;
                    end else begin
                        r_phase <= 1'b0;
                    end
                end
            end
        end
    end

    // Phục hồi bản rõ P = InvCipher(C ^ T) ^ T
    wire [127:0]            dec_tweak_meta = dec_out_meta[127:0];
    wire [5:0]              dec_slot_meta  = dec_out_meta[128 +: 6];
    wire [AXI_ID_WIDTH-1:0] dec_rid_meta   = dec_out_meta[134 +: AXI_ID_WIDTH];
    wire [1:0]              dec_rresp_meta = dec_out_meta[134+AXI_ID_WIDTH +: 2];
    wire                    dec_rlast_meta = dec_out_meta[134+AXI_ID_WIDTH+2];

    wire [127:0] plain_block = dec_out_data ^ dec_tweak_meta;

    // FSM Re-encryption nền cho các dòng sibling cùng CB khi minor=127 tràn (Đặc tả S7)
    wire user_rd_active_any = (rd_count[0]  != 3'd0) || (rd_count[1]  != 3'd0) ||
                              (rd_count[2]  != 3'd0) || (rd_count[3]  != 3'd0) ||
                              (rd_count[4]  != 3'd0) || (rd_count[5]  != 3'd0) ||
                              (rd_count[6]  != 3'd0) || (rd_count[7]  != 3'd0) ||
                              (rd_count[8]  != 3'd0) || (rd_count[9]  != 3'd0) ||
                              (rd_count[10] != 3'd0) || (rd_count[11] != 3'd0) ||
                              (rd_count[12] != 3'd0) || (rd_count[13] != 3'd0) ||
                              (rd_count[14] != 3'd0) || (rd_count[15] != 3'd0);

    wire user_nonblock_waiting = (s_axi_awvalid && !(aw_in_prot && (aw_cb_idx == reenc_cb_idx))) ||
                                 (s_axi_arvalid && !(ar_in_prot && (ar_cb_idx == reenc_cb_idx)));

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reenc_state           <= REENC_IDLE;
            reenc_active          <= 1'b0;
            reenc_old_cb          <= 512'h0;
            reenc_cb_idx          <= 20'd0;
            reenc_old_maj         <= 64'h0;
            reenc_new_maj         <= 64'h0;
            reenc_trig_slot       <= 6'd0;
            reenc_asid            <= 4'h0;
            reenc_slot            <= 6'd0;
            reenc_cur_min         <= 7'd0;
            reenc_sib_addr        <= 64'h0;
            reenc_line_buf        <= 512'h0;
            reenc_oldt0           <= 128'h0;
            reenc_oldt1           <= 128'h0;
            reenc_oldt2           <= 128'h0;
            reenc_oldt3           <= 128'h0;
            reenc_newt0           <= 128'h0;
            reenc_newt1           <= 128'h0;
            reenc_newt2           <= 128'h0;
            reenc_newt3           <= 128'h0;
            reenc_got_dram        <= 1'b0;
            reenc_got_oldtweak    <= 1'b0;
            reenc_got_mac_chk     <= 1'b0;
            reenc_mac_ok          <= 1'b0;
            reenc_got_newtweak    <= 1'b0;
            reenc_blk_in          <= 3'd0;
            reenc_blk_out         <= 3'd0;
            reenc_got_mac_wr      <= 1'b0;
            reenc_got_dram_wr     <= 1'b0;
            reenc_dram_rd_req     <= 1'b0;
            reenc_dram_rd_addr    <= 64'h0;
            reenc_dram_wr_valid   <= 1'b0;
            reenc_dram_wr_addr    <= 64'h0;
            reenc_dram_wr_data    <= 512'h0;
            reenc_tweak_req_valid <= 1'b0;
            reenc_tweak_req_in    <= 128'h0;
            reenc_tweak_req_meta  <= 8'h0;
            reenc_rd_mac_req      <= 1'b0;
            reenc_rd_mac_cdata    <= 512'h0;
            reenc_rd_mac_maj      <= 64'h0;
            reenc_rd_mac_min      <= 7'd0;
            reenc_rd_mac_line     <= 49'h0;
            reenc_wr_mac_req      <= 1'b0;
            reenc_wr_mac_cdata    <= 512'h0;
            reenc_wr_mac_maj      <= 64'h0;
            reenc_wr_mac_min      <= 7'd0;
            reenc_wr_mac_line     <= 49'h0;
            reenc_dec_in_valid    <= 1'b0;
            reenc_dec_in_data     <= 128'h0;
            reenc_dec_in_tweak    <= 128'h0;
            reenc_enc_in_valid    <= 1'b0;
            reenc_enc_in_data     <= 128'h0;
            reenc_enc_in_tweak    <= 128'h0;
            reenc_fail_alert_pulse<= 1'b0;
        end else begin
            reenc_dec_in_valid     <= 1'b0;
            reenc_enc_in_valid     <= 1'b0;
            reenc_fail_alert_pulse <= 1'b0;

            if (reenc_tweak_req_ack) reenc_tweak_req_valid <= 1'b0;
            if (reenc_dram_rd_valid_in) reenc_dram_rd_req <= 1'b0;
            if (reenc_dram_wr_ack) begin
                reenc_dram_wr_valid <= 1'b0;
                reenc_got_dram_wr   <= 1'b1;
            end

            if (reenc_trigger_pulse) begin
                reenc_active    <= 1'b1;
                reenc_old_cb    <= reenc_trig_old_cb;
                reenc_old_maj   <= reenc_trig_old_cb[511:448];
                reenc_cb_idx    <= reenc_trig_cb_idx;
                reenc_new_maj   <= reenc_trig_new_maj;
                reenc_trig_slot <= reenc_trig_slot_w;
                reenc_asid      <= reenc_trig_asid_w;
                reenc_slot      <= 6'd0;
                reenc_state     <= REENC_WAIT_TRIG;
            end else begin
                case (reenc_state)
                    REENC_IDLE: begin
                        reenc_active <= 1'b0;
                    end

                    REENC_WAIT_TRIG: begin
                        if ((bmt_state == BMT_IDLE) && (aw_count == 3'd0) && !wr_mac_req && (mac_fsm == MAC_IDLE) && !ml_busy) begin
                            reenc_state <= REENC_SCAN;
                        end
                    end

                    REENC_SCAN: begin
                        if ((aw_count > 3'd0) || user_rd_pending || user_rd_active_any || rd_stream_active ||
                            dec_out_phase || (rd_plain_wptr != 3'd0) || enc_out_phase ||
                            meta_rd_active || (meta_fifo_cnt > 0) || (meta_wr_inflight > 0) || (wr_bus_owner != WR_NONE) ||
                            (bmt_state != BMT_IDLE) || (mac_fsm != MAC_IDLE) || wr_mac_req || rd_mac_req || ml_busy) begin
                            reenc_state <= REENC_SCAN;
                        end else if (user_nonblock_waiting) begin
                            // Nhường 1 chu kỳ cho giao dịch tới CB khác không bị block
                            reenc_state <= REENC_YIELD;
                        end else if ((reenc_slot == reenc_trig_slot) || (reenc_old_cb[reenc_slot*7 +: 7] == 7'd0)) begin
                            reenc_state <= REENC_NEXT;
                        end else begin
                            logic [63:0] sib_addr_next;
                            logic [6:0]  old_min_v;
                            sib_addr_next = eff_prot_base + {32'd0, reenc_cb_idx, reenc_slot, 6'h0};
                            old_min_v     = reenc_old_cb[reenc_slot*7 +: 7];
                            reenc_cur_min <= old_min_v;
                            reenc_sib_addr<= sib_addr_next;

                            reenc_dram_rd_req     <= 1'b1;
                            reenc_dram_rd_addr    <= sib_addr_next;
                            reenc_tweak_req_valid <= 1'b1;
                            reenc_tweak_req_in    <= {reenc_old_maj, old_min_v, reenc_asid, 27'h0, sib_addr_next[31:6]};
                            reenc_tweak_req_meta  <= 8'b1000_0000;
                            reenc_got_dram        <= 1'b0;
                            reenc_got_oldtweak    <= 1'b0;
                            reenc_state           <= REENC_FETCH_OLD;
                        end
                    end

                    REENC_YIELD: begin
                        reenc_state <= REENC_SCAN;
                    end

                    REENC_FETCH_OLD: begin
                        if (reenc_dram_rd_valid_in) begin
                            reenc_line_buf <= reenc_dram_rd_data_in;
                            reenc_got_dram <= 1'b1;
                        end
                        if (tweak_rsp_valid && (tweak_rsp_meta == 8'b1000_0000)) begin
                            reenc_oldt0        <= tweak_rsp_t0;
                            reenc_oldt1        <= tweak_rsp_t1;
                            reenc_oldt2        <= tweak_rsp_t2;
                            reenc_oldt3        <= tweak_rsp_t3;
                            reenc_got_oldtweak <= 1'b1;
                        end
                        if ((reenc_got_dram || reenc_dram_rd_valid_in) &&
                            (reenc_got_oldtweak || (tweak_rsp_valid && (tweak_rsp_meta == 8'b1000_0000)))) begin
                            reenc_rd_mac_req      <= 1'b1;
                            reenc_rd_mac_cdata    <= reenc_dram_rd_valid_in ? reenc_dram_rd_data_in : reenc_line_buf;
                            reenc_rd_mac_maj      <= reenc_old_maj;
                            reenc_rd_mac_min      <= reenc_cur_min;
                            reenc_rd_mac_line     <= 49'(reenc_sib_addr[31:6]);
                            reenc_tweak_req_valid <= 1'b1;
                            reenc_tweak_req_in    <= {reenc_new_maj, 7'd0, reenc_asid, 27'h0, reenc_sib_addr[31:6]};
                            reenc_tweak_req_meta  <= 8'b1000_0001;
                            reenc_got_mac_chk     <= 1'b0;
                            reenc_got_newtweak    <= 1'b0;
                            reenc_state           <= REENC_CHK_MAC;
                        end
                    end

                    REENC_CHK_MAC: begin
                        if (rd_mac_done) begin
                            reenc_rd_mac_req  <= 1'b0;
                            reenc_got_mac_chk <= 1'b1;
                            reenc_mac_ok      <= !rd_mac_mismatch;
                        end
                        if (tweak_rsp_valid && (tweak_rsp_meta == 8'b1000_0001)) begin
                            reenc_newt0        <= tweak_rsp_t0;
                            reenc_newt1        <= tweak_rsp_t1;
                            reenc_newt2        <= tweak_rsp_t2;
                            reenc_newt3        <= tweak_rsp_t3;
                            reenc_got_newtweak <= 1'b1;
                        end
                        if ((reenc_got_mac_chk || rd_mac_done) &&
                            (reenc_got_newtweak || (tweak_rsp_valid && (tweak_rsp_meta == 8'b1000_0001)))) begin
                            if (rd_mac_done ? rd_mac_mismatch : !reenc_mac_ok) begin
                                reenc_fail_alert_pulse <= 1'b1;
                                reenc_state            <= REENC_NEXT;
                            end else begin
                                reenc_blk_in  <= 3'd0;
                                reenc_blk_out <= 3'd0;
                                reenc_state   <= REENC_DEC;
                            end
                        end
                    end

                    REENC_DEC: begin
                        if ((reenc_blk_in < 3'd4) && (!reenc_dec_in_valid || dec_in_ready)) begin
                            logic [127:0] sel_ot;
                            case (reenc_blk_in[1:0])
                                2'd0: sel_ot = reenc_oldt0;
                                2'd1: sel_ot = reenc_oldt1;
                                2'd2: sel_ot = reenc_oldt2;
                                default: sel_ot = reenc_oldt3;
                            endcase
                            reenc_dec_in_valid <= 1'b1;
                            reenc_dec_in_data  <= reenc_line_buf[reenc_blk_in[1:0]*128 +: 128] ^ sel_ot;
                            reenc_dec_in_tweak <= sel_ot;
                            reenc_blk_in       <= reenc_blk_in + 1'b1;
                        end
                        if (dec_out_valid) begin
                            reenc_line_buf[reenc_blk_out[1:0]*128 +: 128] <= plain_block;
                            if (reenc_blk_out == 3'd3) begin
                                reenc_blk_in  <= 3'd0;
                                reenc_blk_out <= 3'd0;
                                reenc_state   <= REENC_ENC;
                            end else begin
                                reenc_blk_out <= reenc_blk_out + 1'b1;
                            end
                        end
                    end

                    REENC_ENC: begin
                        if ((reenc_blk_in < 3'd4) && (!reenc_enc_in_valid || enc_in_ready)) begin
                            logic [127:0] sel_nt;
                            case (reenc_blk_in[1:0])
                                2'd0: sel_nt = reenc_newt0;
                                2'd1: sel_nt = reenc_newt1;
                                2'd2: sel_nt = reenc_newt2;
                                default: sel_nt = reenc_newt3;
                            endcase
                            reenc_enc_in_valid <= 1'b1;
                            reenc_enc_in_data  <= reenc_line_buf[reenc_blk_in[1:0]*128 +: 128];
                            reenc_enc_in_tweak <= sel_nt;
                            reenc_blk_in       <= reenc_blk_in + 1'b1;
                        end
                        if (enc_out_valid) begin
                            reenc_line_buf[reenc_blk_out[1:0]*128 +: 128] <= enc_out_data;
                            if (reenc_blk_out == 3'd3) begin
                                logic [511:0] final_ct;
                                final_ct = {enc_out_data, reenc_line_buf[383:0]};
                                reenc_wr_mac_req    <= 1'b1;
                                reenc_wr_mac_cdata  <= final_ct;
                                reenc_wr_mac_maj    <= reenc_new_maj;
                                reenc_wr_mac_min    <= 7'd0;
                                reenc_wr_mac_line   <= 49'(reenc_sib_addr[31:6]);
                                reenc_dram_wr_valid <= 1'b1;
                                reenc_dram_wr_addr  <= reenc_sib_addr;
                                reenc_dram_wr_data  <= final_ct;
                                reenc_got_mac_wr    <= 1'b0;
                                reenc_got_dram_wr   <= 1'b0;
                                reenc_state         <= REENC_COMMIT;
                            end else begin
                                reenc_blk_out <= reenc_blk_out + 1'b1;
                            end
                        end
                    end

                    REENC_COMMIT: begin
                        if (wr_mac_done) begin
                            reenc_wr_mac_req <= 1'b0;
                            reenc_got_mac_wr <= 1'b1;
                        end
                        if ((reenc_got_mac_wr || wr_mac_done) &&
                            (reenc_got_dram_wr || reenc_dram_wr_ack || !reenc_dram_wr_valid)) begin
                            reenc_state <= REENC_NEXT;
                        end
                    end

                    REENC_NEXT: begin
                        if (reenc_slot == 6'd63) begin
                            reenc_active <= 1'b0;
                            reenc_state  <= REENC_IDLE;
                        end else begin
                            reenc_slot  <= reenc_slot + 1'b1;
                            reenc_state <= REENC_SCAN;
                        end
                    end

                    default: reenc_state <= REENC_IDLE;
                endcase
            end
        end
    end

    // Buffer và Non-Speculative Release FSM
    logic [63:0] dec_out_b1_reg;
    logic        dec_out_phase;
    logic        dec_out_last_reg;
    logic [AXI_ID_WIDTH-1:0] dec_out_id_reg;
    logic [1:0]  dec_out_resp_reg;
    logic [5:0]  dec_out_slot_reg;
    logic [5:0]  rd_mac_slot;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dec_out_phase      <= 1'b0;
            dec_out_b1_reg     <= 64'h0;
            dec_out_last_reg   <= 1'b0;
            dec_out_id_reg     <= '0;
            dec_out_resp_reg   <= 2'b00;
            dec_out_slot_reg   <= 6'd0;
            rd_mac_slot        <= 6'd0;
            reg_integ_fail_cnt <= 32'h0;
            reg_integ_alert    <= 1'b0;
            reg_mc_hit_cnt     <= 32'd0;
            reg_mc_miss_cnt    <= 32'd0;
            bmt_saw_dram_rd    <= 1'b0;
            rd_plain_wptr      <= 3'd0;
            rd_stream_active   <= 1'b0;
            rd_stream_fail     <= 1'b0;
            rd_stream_beat     <= 3'd0;
            rd_stream_id       <= '0;
            rd_mac_req         <= 1'b0;
            rd_mac_cdata       <= 512'h0;
            rd_mac_maj         <= 64'h0;
            rd_mac_min         <= 7'h0;
            rd_mac_line        <= 49'h0;
        end else begin
            // Chế độ toàn vẹn: nạp 8 beat bản rõ vào rd_plain_buf
            if (eff_integ_enable && !cur_rd_is_bypass && !reenc_step_busy) begin
                if (dec_out_phase == 1'b0) begin
                    if (dec_out_valid) begin
                        rd_plain_buf[rd_plain_wptr] <= plain_block[63:0];
                        rd_plain_wptr    <= rd_plain_wptr + 1'b1;
                        dec_out_b1_reg   <= plain_block[127:64];
                        dec_out_last_reg <= dec_rlast_meta;
                        dec_out_id_reg   <= dec_rid_meta;
                        dec_out_resp_reg <= dec_rresp_meta;
                        dec_out_slot_reg <= dec_slot_meta;
                        dec_out_phase    <= 1'b1;
                    end
                end else begin
                    rd_plain_buf[rd_plain_wptr] <= dec_out_b1_reg;
                    dec_out_phase <= 1'b0;
                    if (dec_out_last_reg || (rd_plain_wptr == 3'd7)) begin
                        rd_plain_wptr  <= 3'd0;
                        // Kích hoạt kiểm tra MAC cho dòng vừa giải mã (tag lấy từ ML cache/DRAM)
                        rd_mac_slot    <= dec_out_slot_reg;
                        rd_mac_req     <= 1'b1;
                        rd_mac_cdata   <= rd_ct_buffer;
                        rd_mac_maj     <= rd_fifo_maj[dec_out_slot_reg];
                        rd_mac_min     <= rd_fifo_min[dec_out_slot_reg];
                        rd_mac_line    <= 49'(rd_fifo_addr[dec_out_slot_reg][31:6]);
                        rd_stream_id   <= dec_out_id_reg;
                    end else begin
                        rd_plain_wptr <= rd_plain_wptr + 1'b1;
                    end
                end

                // Khi MAC xong: quyết định phát bản rõ hay SLVERR (Non-speculative release)
                if (rd_mac_done) begin
                    rd_mac_req       <= 1'b0;
                    rd_stream_active <= 1'b1;
                    rd_stream_beat   <= 3'd0;

                    if (rd_mac_mismatch || rd_fifo_bmt_fail[rd_mac_slot]) begin
                        rd_stream_fail  <= 1'b1;
                        reg_integ_alert <= 1'b1;
                        if (rd_mac_mismatch) reg_integ_fail_cnt <= reg_integ_fail_cnt + 1'b1;
                    end else begin
                        rd_stream_fail  <= 1'b0;
                    end
                end

                if (rd_stream_active && s_axi_rready) begin
                    if (rd_stream_beat == 3'd7) begin
                        rd_stream_active <= 1'b0;
                    end else begin
                        rd_stream_beat <= rd_stream_beat + 1'b1;
                    end
                end
            end else if (!reenc_step_busy) begin
                // Chế độ bypass hoặc tắt toàn vẹn: luồng trực tiếp như T30
                if (dec_out_phase == 1'b0) begin
                    if (dec_out_valid && s_axi_rready && !cur_rd_is_bypass && !rej_rd_active) begin
                        dec_out_b1_reg   <= plain_block[127:64];
                        dec_out_last_reg <= dec_rlast_meta;
                        dec_out_id_reg   <= dec_rid_meta;
                        dec_out_resp_reg <= dec_rresp_meta;
                        dec_out_phase    <= 1'b1;
                    end
                end else begin
                    if (s_axi_rready) begin
                        dec_out_phase <= 1'b0;
                    end
                end
            end

            // Cập nhật cảnh báo từ BMT Engine & Re-encryption FSM
            if (bmt_integ_alert_out || bmt_wr_rejected_alert || reenc_fail_alert_pulse) begin
                reg_integ_alert <= 1'b1;
            end
            if (reenc_fail_alert_pulse) begin
                reg_integ_fail_cnt <= reg_integ_fail_cnt + 1'b1;
            end

            // Theo dõi telemetry Metadata Cache BMT + ML (Hit / Miss)
            if (bmt_dram_rd_valid) begin
                bmt_saw_dram_rd <= 1'b1;
            end
            if ((bmt_verify_done || bmt_update_done) && !ml_req_valid) begin
                if (bmt_saw_dram_rd) begin
                    reg_mc_miss_cnt <= reg_mc_miss_cnt + 1'b1;
                end else begin
                    reg_mc_hit_cnt <= reg_mc_hit_cnt + 1'b1;
                end
                bmt_saw_dram_rd <= 1'b0;
            end else if (ml_req_valid && (ml_state == ML_IDLE)) begin
                if (ml_hit0_w || ml_hit1_w) begin
                    reg_mc_hit_cnt <= reg_mc_hit_cnt + 1'b1;
                end else if (ml_dram_inited[ml_req_idx_w]) begin
                    reg_mc_miss_cnt <= reg_mc_miss_cnt + 1'b1;
                end
            end else if (bmt_verify_done || bmt_update_done) begin
                bmt_saw_dram_rd <= 1'b0;
            end
        end
    end

    // Gán tín hiệu phản hồi AXI Read (s_axi_r)
    always_comb begin
        dec_out_ready = 1'b0;
        s_axi_rvalid  = 1'b0;
        s_axi_rdata   = 64'h0;
        s_axi_rresp   = 2'b00;
        s_axi_rid     = '0;
        s_axi_rlast   = 1'b0;

        if (rej_rd_active) begin
            s_axi_rvalid = 1'b1;
            s_axi_rdata  = 64'h0;
            s_axi_rresp  = 2'b10;
            s_axi_rid    = rej_rd_id;
            s_axi_rlast  = (rej_rd_beat_cnt == rej_rd_len);
        end else if (cur_rd_is_bypass) begin
            s_axi_rvalid = m_axi_rvalid && (m_axi_rid[3] == 1'b0);
            s_axi_rdata  = m_axi_rdata;
            s_axi_rresp  = m_axi_rresp;
            s_axi_rid    = m_axi_rid;
            s_axi_rlast  = m_axi_rlast;
        end else if (reenc_step_busy) begin
            dec_out_ready = 1'b1;
        end else if (eff_integ_enable) begin
            dec_out_ready = 1'b1;
            if (rd_stream_active) begin
                s_axi_rvalid = 1'b1;
                s_axi_rdata  = rd_stream_fail ? 64'h0 : rd_plain_buf[rd_stream_beat];
                s_axi_rresp  = rd_stream_fail ? 2'b10 : 2'b00;
                s_axi_rid    = rd_stream_id;
                s_axi_rlast  = (rd_stream_beat == 3'd7);
            end
        end else if (dec_out_phase == 1'b1) begin
            s_axi_rvalid = 1'b1;
            s_axi_rdata  = dec_out_b1_reg;
            s_axi_rresp  = dec_out_resp_reg;
            s_axi_rid    = dec_out_id_reg;
            s_axi_rlast  = dec_out_last_reg;
        end else if (dec_out_valid) begin
            s_axi_rvalid  = 1'b1;
            s_axi_rdata   = plain_block[63:0];
            s_axi_rresp   = dec_rresp_meta;
            s_axi_rid     = dec_rid_meta;
            s_axi_rlast   = 1'b0;
            dec_out_ready = s_axi_rready;
        end
    end

    //-------------------------------------------------------------------------
    // 10. Trạng thái bận mật mã (Crypto Busy Telemetry)
    //-------------------------------------------------------------------------
    assign o_crypto_busy = !keys_ready || enc_lane_busy || (aw_count > 0) ||
                           rej_rd_active || meta_rd_active || meta_aw_valid || meta_w_valid ||
                           (meta_fifo_cnt > 0) || (meta_wr_inflight > 0) || rd_stream_active ||
                           (mac_fsm != MAC_IDLE) || (bmt_state != BMT_IDLE) ||
                           (ml_state != ML_IDLE) || reenc_active;

endmodule
