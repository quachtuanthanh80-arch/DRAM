// File: qshield_axi_crypto_bridge.sv
// Chức năng: Cầu nối AXI4 mật mã hoá AES-256-XTS IEEE 1619-2018 bảo vệ đường truyền ngoài lõi DDR5.

`timescale 1ns / 1ps

module qshield_axi_crypto_bridge #(
    parameter int AXI_ID_WIDTH    = 4,
    parameter int AXI_ADDR_WIDTH  = 32,
    parameter int AXI_DATA_WIDTH  = 64,
    parameter int AXI_STRB_WIDTH  = AXI_DATA_WIDTH / 8,
    parameter int AXI_LEN_WIDTH   = 8,
    parameter int AXI_QOS_WIDTH   = 4
)(
    input  logic                                         clk,
    input  logic                                         rst_n,

    // Giao diện điều khiển mật mã (Đặc tả S8)
    input  logic                                         i_enc_enable,
    input  logic                                         i_keys_valid,
    input  logic [255:0]                                 i_key1,
    input  logic [255:0]                                 i_key2,
    input  logic [3:0]                                   i_asid,
    input  logic [18:0]                                  i_epoch,
    output logic                                         o_crypto_busy,
    output logic [15:0]                                  o_crypto_reject_cnt,
    output logic [15:0]                                  o_crypto_err_cnt,

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
);
    import aes_pkg::*;

    //-------------------------------------------------------------------------
    // 1. Mở rộng khoá AES-256 (Key Expansion) cho K1 và K2
    //-------------------------------------------------------------------------
    logic         k1_valid, k2_valid;
    logic [15*128-1:0] k1_round_keys;
    logic [15*128-1:0] k2_round_keys;

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

    wire keys_ready = i_keys_valid && k1_valid && k2_valid;

    // Unpack K1 round keys cho aes_xts_lane
    logic [127:0] k1_rk [15];
    for (genvar k = 0; k < 15; k++) begin : g_unpack_k1
        assign k1_rk[k] = k1_round_keys[k*128 +: 128];
    end

    //-------------------------------------------------------------------------
    // 2. Bộ đếm lỗi và từ chối giao dịch (Saturating Counters)
    //-------------------------------------------------------------------------
    logic [15:0] reject_cnt_reg;
    logic [15:0] err_cnt_reg;
    assign o_crypto_reject_cnt = reject_cnt_reg;
    assign o_crypto_err_cnt    = err_cnt_reg;

    wire b_err = m_axi_bvalid && m_axi_bready && m_axi_bresp[1];
    wire r_err = m_axi_rvalid && m_axi_rready && m_axi_rresp[1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            err_cnt_reg <= 16'h0;
        end else if ((b_err || r_err) && (err_cnt_reg != 16'hFFFF)) begin
            err_cnt_reg <= err_cnt_reg + 1'b1;
        end
    end

    //-------------------------------------------------------------------------
    // 3. Đơn vị sinh vector Tweak dùng chung (Shared Tweak Unit)
    //-------------------------------------------------------------------------
    logic        tweak_req_valid;
    wire         tweak_req_ready;
    logic [127:0] tweak_req_in;
    logic [6:0]  tweak_req_meta;

    wire         tweak_rsp_valid;
    wire  [127:0] tweak_rsp_t0, tweak_rsp_t1, tweak_rsp_t2, tweak_rsp_t3;
    wire  [6:0]  tweak_rsp_meta;

    qshield_xts_tweak_unit #(
        .MetaWidth(7)
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

    logic        wr_tweak_req_valid;
    logic [127:0] wr_tweak_req_in;
    logic [6:0]  wr_tweak_req_meta;
    logic        wr_tweak_req_ack;

    logic        rd_tweak_req_valid;
    logic [127:0] rd_tweak_req_in;
    logic [6:0]  rd_tweak_req_meta;
    logic        rd_tweak_req_ack;

    logic arb_last;

    always_comb begin
        tweak_req_valid  = 1'b0;
        tweak_req_in     = 128'h0;
        tweak_req_meta   = 7'h0;
        wr_tweak_req_ack = 1'b0;
        rd_tweak_req_ack = 1'b0;

        if (arb_last == 1'b0) begin
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
        end else if (tweak_req_valid && tweak_req_ready) begin
            arb_last <= tweak_req_meta[6];
        end
    end

    //-------------------------------------------------------------------------
    // 4. Đường ghi (Write Path): AW FIFO (mảng 1D), ghép beat, mã hoá
    //-------------------------------------------------------------------------
    wire aw_is_incr    = (s_axi_awburst == 2'b01);
    wire aw_is_size3   = (s_axi_awsize  == 3'b011);
    wire aw_is_aligned = (s_axi_awaddr[3:0] == 4'h0);
    wire aw_is_even    = (s_axi_awlen[0] == 1'b1);
    wire aw_qualified  = keys_ready && aw_is_incr && aw_is_size3 && aw_is_aligned && aw_is_even;

    // Hàng đợi AW FIFO bằng mảng 1D để tương thích hoàn toàn với Icarus Verilog
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
    logic         wr_tweak_valid [4];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 4; i++) wr_tweak_valid[i] <= 1'b0;
        end else begin
            if (tweak_rsp_valid && (tweak_rsp_meta[6] == 1'b0)) begin
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

    wire aw_fire = s_axi_awvalid && s_axi_awready;
    assign s_axi_awready = (aw_count < 3'd4);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_wr_ptr          <= 2'd0;
            aw_count           <= 3'd0;
            reject_cnt_reg     <= 16'h0;
            wr_tweak_req_valid <= 1'b0;
            wr_tweak_req_in    <= 128'h0;
            wr_tweak_req_meta  <= 7'h0;
        end else begin
            if (wr_tweak_req_ack) begin
                wr_tweak_req_valid <= 1'b0;
            end

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
                end else begin
                    aw_fifo_is_bypass[aw_wr_ptr] <= 1'b0;
                    aw_fifo_is_reject[aw_wr_ptr] <= 1'b0;
                    wr_tweak_req_valid <= 1'b1;
                    wr_tweak_req_in    <= {47'h0, i_epoch[18:0], i_asid[3:0], 32'h0, s_axi_awaddr[31:6]};
                    wr_tweak_req_meta  <= {1'b0, 4'h0, aw_wr_ptr};
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
        end else if (m_axi_awvalid && m_axi_awready) begin
            aw_sent_to_core <= 1'b1;
        end
    end

    assign m_axi_awvalid = cur_aw_valid && !cur_aw_is_reject && !aw_sent_to_core;
    assign m_axi_awid    = aw_fifo_id[aw_rd_ptr];
    assign m_axi_awaddr  = aw_fifo_addr[aw_rd_ptr];
    assign m_axi_awlen   = aw_fifo_len[aw_rd_ptr];
    assign m_axi_awsize  = aw_fifo_size[aw_rd_ptr];
    assign m_axi_awburst = aw_fifo_burst[aw_rd_ptr];
    assign m_axi_awqos   = aw_fifo_qos[aw_rd_ptr];

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

        if (cur_aw_valid) begin
            if (cur_aw_is_bypass) begin
                s_axi_wready = m_axi_wready;
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
        end else if (cur_aw_valid && s_axi_wvalid && s_axi_wready) begin
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

    always_comb begin
        enc_out_ready = 1'b0;
        m_axi_wvalid  = 1'b0;
        m_axi_wdata   = 64'h0;
        m_axi_wstrb   = 8'hFF;
        m_axi_wlast   = 1'b0;

        if (cur_aw_valid && cur_aw_is_bypass) begin
            m_axi_wvalid = s_axi_wvalid;
            m_axi_wdata  = s_axi_wdata;
            m_axi_wstrb  = s_axi_wstrb;
            m_axi_wlast  = s_axi_wlast;
        end else if (enc_out_phase == 1'b1) begin
            m_axi_wvalid = 1'b1;
            m_axi_wdata  = enc_out_b1_reg;
            m_axi_wstrb  = 8'hFF;
            m_axi_wlast  = enc_out_last_reg;
        end else if (enc_out_valid) begin
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
        end else begin
            if (enc_out_phase == 1'b0) begin
                if (enc_out_valid && m_axi_wready && !cur_aw_is_bypass) begin
                    enc_out_b1_reg   <= enc_out_data[127:64];
                    enc_out_last_reg <= enc_out_meta[5];
                    enc_out_phase    <= 1'b1;
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
        end else if (cur_aw_valid && (cur_aw_is_reject || w_has_partial_strb) && s_axi_wvalid && s_axi_wready && s_axi_wlast) begin
            reject_bvalid <= 1'b1;
            reject_bid    <= aw_fifo_id[aw_rd_ptr];
        end else if (reject_bvalid && s_axi_bready) begin
            reject_bvalid <= 1'b0;
        end
    end

    always_comb begin
        if (reject_bvalid) begin
            s_axi_bvalid = 1'b1;
            s_axi_bid    = reject_bid;
            s_axi_bresp  = 2'b10;
            m_axi_bready = 1'b0;
        end else begin
            s_axi_bvalid = m_axi_bvalid;
            s_axi_bid    = m_axi_bid;
            s_axi_bresp  = m_axi_bresp;
            m_axi_bready = s_axi_bready;
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
    // 5. Đường đọc (Read Path): ID FIFO (mảng 1D 64 mục), giải mã InvCipher
    //-------------------------------------------------------------------------
    wire ar_is_incr    = (s_axi_arburst == 2'b01);
    wire ar_is_size3   = (s_axi_arsize  == 3'b011);
    wire ar_is_aligned = (s_axi_araddr[3:0] == 4'h0);
    wire ar_is_even    = (s_axi_arlen[0] == 1'b1);
    wire ar_qualified  = keys_ready && ar_is_incr && ar_is_size3 && ar_is_aligned && ar_is_even;

    // 16 hàng đợi theo ID, mỗi hàng 4 slot = 64 mục (mảng 1D phẳng hoàn toàn)
    logic [AXI_ADDR_WIDTH-1:0] rd_fifo_addr        [64];
    logic [AXI_LEN_WIDTH-1:0]  rd_fifo_len         [64];
    logic [3:0]                rd_fifo_asid        [64];
    logic [18:0]               rd_fifo_epoch       [64];
    logic [127:0]              rd_fifo_tweak0      [64];
    logic [127:0]              rd_fifo_tweak1      [64];
    logic [127:0]              rd_fifo_tweak2      [64];
    logic [127:0]              rd_fifo_tweak3      [64];
    logic                      rd_fifo_tweak_valid [64];
    logic                      rd_fifo_is_bypass   [64];

    logic [1:0] rd_head  [16];
    logic [1:0] rd_tail  [16];
    logic [2:0] rd_count [16];

    wire [3:0] cur_arid = s_axi_arid[3:0];
    wire [5:0] cur_ar_slot = {cur_arid, rd_tail[cur_arid]};
    wire rd_id_full = (rd_count[cur_arid] == 3'd4);

    wire ar_fire = s_axi_arvalid && s_axi_arready;

    logic        rej_rd_active;
    logic [AXI_ID_WIDTH-1:0] rej_rd_id;
    logic [7:0]  rej_rd_len;
    logic [7:0]  rej_rd_beat_cnt;

    assign s_axi_arready = !rej_rd_active && !rd_id_full && (i_enc_enable ? 1'b1 : m_axi_arready);
    assign m_axi_arvalid = ar_fire && (!i_enc_enable || ar_qualified);
    assign m_axi_arid    = s_axi_arid;
    assign m_axi_araddr  = s_axi_araddr;
    assign m_axi_arlen   = s_axi_arlen;
    assign m_axi_arsize  = s_axi_arsize;
    assign m_axi_arburst = s_axi_arburst;
    assign m_axi_arqos   = s_axi_arqos;

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
            end
            rej_rd_active      <= 1'b0;
            rej_rd_id          <= '0;
            rej_rd_len         <= 8'h0;
            rej_rd_beat_cnt    <= 8'h0;
            rd_tweak_req_valid <= 1'b0;
            rd_tweak_req_in    <= 128'h0;
            rd_tweak_req_meta  <= 7'h0;
        end else begin
            if (rd_tweak_req_ack) begin
                rd_tweak_req_valid <= 1'b0;
            end

            if (ar_fire) begin
                if (!i_enc_enable) begin
                    rd_fifo_is_bypass[cur_ar_slot]   <= 1'b1;
                    rd_fifo_tweak_valid[cur_ar_slot] <= 1'b1;
                    rd_fifo_addr[cur_ar_slot]        <= s_axi_araddr;
                    rd_fifo_len[cur_ar_slot]         <= s_axi_arlen;
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
                    rd_fifo_addr[cur_ar_slot]        <= s_axi_araddr;
                    rd_fifo_len[cur_ar_slot]         <= s_axi_arlen;
                    rd_fifo_asid[cur_ar_slot]        <= i_asid;
                    rd_fifo_epoch[cur_ar_slot]       <= i_epoch;

                    rd_tweak_req_valid <= 1'b1;
                    rd_tweak_req_in    <= {47'h0, i_epoch[18:0], i_asid[3:0], 32'h0, s_axi_araddr[31:6]};
                    rd_tweak_req_meta  <= {1'b1, cur_arid, rd_tail[cur_arid]};

                    rd_tail[cur_arid]  <= rd_tail[cur_arid] + 1'b1;
                    rd_count[cur_arid] <= rd_count[cur_arid] + 1'b1;
                end
            end

            if (tweak_rsp_valid && (tweak_rsp_meta[6] == 1'b1)) begin
                logic [5:0] rsp_slot_idx;
                rsp_slot_idx = {tweak_rsp_meta[5:2], tweak_rsp_meta[1:0]};

                rd_fifo_tweak0[rsp_slot_idx]      <= tweak_rsp_t0;
                rd_fifo_tweak1[rsp_slot_idx]      <= tweak_rsp_t1;
                rd_fifo_tweak2[rsp_slot_idx]      <= tweak_rsp_t2;
                rd_fifo_tweak3[rsp_slot_idx]      <= tweak_rsp_t3;
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

    // Ghép cặp beat đọc R từ lõi: 2 beat 64-bit -> InvCipher
    logic [63:0] rdata_b0_reg;
    logic [1:0]  rresp_b0_reg;
    logic        r_phase;
    logic [7:0]  r_beat_cnt;

    localparam int DecMetaW = 1 + 2 + AXI_ID_WIDTH + 128;

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

    always_comb begin
        m_axi_rready = 1'b0;
        dec_in_valid = 1'b0;
        dec_in_data  = 128'h0;
        dec_in_meta  = '0;

        if (cur_rd_is_bypass) begin
            m_axi_rready = s_axi_rready;
        end else begin
            if (r_phase == 1'b0) begin
                m_axi_rready = 1'b1;
            end else begin
                dec_in_valid = m_axi_rvalid && cur_rd_tweak_valid;
                dec_in_data  = {m_axi_rdata, rdata_b0_reg} ^ sel_rd_tweak;
                dec_in_meta  = {m_axi_rlast, (m_axi_rresp | rresp_b0_reg), m_axi_rid, sel_rd_tweak};
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
        end else if (m_axi_rvalid && m_axi_rready) begin
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

    // Phục hồi bản rõ P = InvCipher(C ^ T) ^ T và phát 2 beat ra s_axi_r
    wire [127:0] dec_tweak_meta = dec_out_meta[127:0];
    wire [AXI_ID_WIDTH-1:0] dec_rid_meta = dec_out_meta[128 +: AXI_ID_WIDTH];
    wire [1:0]   dec_rresp_meta = dec_out_meta[128+AXI_ID_WIDTH +: 2];
    wire         dec_rlast_meta = dec_out_meta[134];

    wire [127:0] plain_block = dec_out_data ^ dec_tweak_meta;

    logic [63:0] dec_out_b1_reg;
    logic        dec_out_phase;
    logic        dec_out_last_reg;
    logic [AXI_ID_WIDTH-1:0] dec_out_id_reg;
    logic [1:0]  dec_out_resp_reg;

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
            s_axi_rvalid = m_axi_rvalid;
            s_axi_rdata  = m_axi_rdata;
            s_axi_rresp  = m_axi_rresp;
            s_axi_rid    = m_axi_rid;
            s_axi_rlast  = m_axi_rlast;
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

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dec_out_phase    <= 1'b0;
            dec_out_b1_reg   <= 64'h0;
            dec_out_last_reg <= 1'b0;
            dec_out_id_reg   <= '0;
            dec_out_resp_reg <= 2'b00;
        end else begin
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
    end

    //-------------------------------------------------------------------------
    // 6. Trạng thái bận mật mã (Crypto Busy Telemetry)
    //-------------------------------------------------------------------------
    assign o_crypto_busy = !keys_ready || enc_lane_busy || (aw_count > 0) || rej_rd_active;

endmodule
