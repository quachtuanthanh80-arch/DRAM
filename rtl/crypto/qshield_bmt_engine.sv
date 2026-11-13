// File: qshield_bmt_engine.sv
// Chức năng: Động cơ cây Bonsai Merkle Tree (BMT 8-ary) xác minh toàn vẹn, cập nhật lười và bảo vệ chống replay.

`timescale 1ns / 1ps

module qshield_bmt_engine #(
    parameter logic [63:0] PROT_BASE  = 64'h0000_0000_0000_0000,
    parameter logic [63:0] PROT_LINES = 64'd4096, // 4096 dòng dữ liệu -> 64 CBs, 8 L1, 1 L2
    parameter int          TREE_ARITY = 8,
    parameter int          MC_SETS    = 16,
    parameter int          MC_WAYS    = 4
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // Giao diện cấu hình khóa bảo mật K3
    input  logic [127:0]           i_h,              // Khóa con GHASH H = AES256_K3(0^128)
    input  logic [255:0]           i_k3,             // Khóa K3 256-bit
    input  logic                   i_keys_valid,

    // Giao diện xác minh (Verify Request)
    input  logic                   i_verify_valid,
    input  logic [63:0]            i_verify_addr,    // Địa chỉ dòng dữ liệu cần đọc
    output logic                   o_verify_ready,
    output logic                   o_verify_done,
    output logic                   o_verify_pass,
    output logic                   o_verify_fail,
    output logic [511:0]           o_cb_data,        // Dữ liệu CB đã xác minh
    output logic [5:0]             o_cb_slot,        // Khe dòng trong CB

    // Giao diện cập nhật (Update Request khi ghi dữ liệu)
    input  logic                   i_update_valid,
    input  logic [63:0]            i_update_addr,
    input  logic [511:0]           i_update_cb_data, // Dữ liệu CB mới (đã tăng minor)
    output logic                   o_update_ready,
    output logic                   o_update_done,

    // Giao diện khởi tạo cây (meta_init)
    input  logic                   i_init_start,
    output logic                   o_init_busy,
    output logic                   o_init_done,
    output logic [31:0]            o_init_cycles,

    // Giao diện xả đệm cây (meta_flush) và xóa cache
    input  logic                   i_flush_start,
    output logic                   o_flush_busy,
    output logic                   o_flush_done,
    input  logic                   i_cache_clear,    // Xóa trắng MC (giữ nguyên root)

    // Giao diện truy cập DRAM (Backdoor / Memory Bus)
    output logic                   o_dram_rd_valid,
    output logic [63:0]            o_dram_rd_addr,
    input  logic                   i_dram_rd_ready,
    input  logic                   i_dram_rd_valid,
    input  logic [511:0]           i_dram_rd_data,

    output logic                   o_dram_wr_valid,
    output logic [63:0]            o_dram_wr_addr,
    output logic [511:0]           o_dram_wr_data,
    input  logic                   i_dram_wr_ready,

    // Gốc cây Merkle trên chip (64-bit)
    output logic [63:0]            o_tree_root,
    output logic [511:0]           o_tree_root_slots,

    // Thống kê CSR và Cảnh báo
    output logic [31:0]            o_tree_fail_cnt,
    output logic [31:0]            o_verify_cnt,
    output logic [31:0]            o_update_cnt,
    output logic                   o_integrity_alert
);
    import aes_pkg::*;

    // -------------------------------------------------------------------------
    // Hằng số hình học cây Bonsai Merkle Tree
    // -------------------------------------------------------------------------
    localparam logic [63:0] NUM_CB      = PROT_LINES / 64; // 64 CBs
    localparam logic [63:0] CB_BYTES    = NUM_CB * 64;
    localparam logic [63:0] CB_BASE     = PROT_BASE + PROT_LINES * 64;
    localparam logic [63:0] ML_BASE     = CB_BASE + CB_BYTES;
    localparam logic [63:0] ML_BYTES    = (PROT_LINES / 8) * 64;
    localparam logic [63:0] TN_BASE     = ML_BASE + ML_BYTES;

    localparam logic [63:0] TN_L1_COUNT = NUM_CB / 8; // 8 nodes
    localparam logic [63:0] TN_L2_COUNT = TN_L1_COUNT / 8; // 1 node
    localparam logic [63:0] TN_L1_BASE  = TN_BASE;
    localparam logic [63:0] TN_L2_BASE  = TN_BASE + TN_L1_COUNT * 64;

    // -------------------------------------------------------------------------
    // Khối mở rộng khóa AES-256 cho K3 và sinh mask node
    // -------------------------------------------------------------------------
    function automatic logic [255:0] rev256(input logic [255:0] x);
        for (int i = 0; i < 32; i++) rev256[i*8 +: 8] = x[(31 - i)*8 +: 8];
    endfunction
    function automatic logic [127:0] rev128(input logic [127:0] x);
        for (int i = 0; i < 16; i++) rev128[i*8 +: 8] = x[(15 - i)*8 +: 8];
    endfunction

    wire [15*128-1:0] k3_round_keys;
    wire              k3_exp_valid;
    aes256_key_expand u_key_expand (
        .clk          (clk),
        .rst_n        (rst_n),
        .i_key        (rev256(i_k3)),
        .o_valid      (k3_exp_valid),
        .o_round_keys (k3_round_keys)
    );

    wire [127:0] rk3 [0:14];
    for (genvar k = 0; k < 15; k++) begin : gen_rk3
        assign rk3[k] = k3_round_keys[k*128 +: 128];
    end

    // Đường ống 14 tầng tính Mask: AES256_K3(0x02 || level[3:0] || node_idx[59:0] || pad[56:0])
    logic         aes_in_valid;
    logic [127:0] aes_in_pt;
    wire          aes_out_valid;
    wire  [127:0] aes_out_ct;

    logic [127:0] pipe_st  [15];
    logic         pipe_vld [15];

    assign pipe_st[0]   = rev128(aes_in_pt) ^ rk3[0];
    assign pipe_vld[0]  = aes_in_valid;

    genvar r;
    generate
        for (r = 1; r <= 14; r++) begin : gen_aes_round
            localparam bit IsFinal = (r == 14);
            aes_round_pipe u_rnd (
                .clk            (clk),
                .rst_n          (rst_n),
                .in_valid       (pipe_vld[r-1]),
                .in_ready       (),
                .is_final_round (IsFinal),
                .state_in       (pipe_st[r-1]),
                .round_key      (rk3[r]),
                .out_valid      (pipe_vld[r]),
                .out_ready      (1'b1),
                .state_out      (pipe_st[r])
            );
        end
    endgenerate
    assign aes_out_valid = pipe_vld[14];
    assign aes_out_ct    = rev128(pipe_st[14]);

    // -------------------------------------------------------------------------
    // Khối tính Carter-Wegman MAC / Node Hash (qshield_mac_unit)
    // -------------------------------------------------------------------------
    logic         mac_valid;
    wire          mac_ready;
    logic [511:0] mac_data;
    logic [127:0] mac_mask;
    logic [3:0]   mac_level;
    logic [59:0]  mac_node_idx;
    logic [63:0]  mac_expected_tag;
    wire          mac_out_valid;
    wire  [63:0]  mac_tag;
    wire          mac_tag_match;
    wire          mac_tag_mismatch;

    qshield_mac_unit #(
        .GF_STAGES(4)
    ) u_mac_unit (
        .clk             (clk),
        .rst_n           (rst_n),
        .i_h             (i_h),
        .i_valid         (mac_valid),
        .o_ready         (mac_ready),
        .i_mode          (1'b1), // Node cây / Counter block
        .i_data          (mac_data),
        .i_mask          (mac_mask),
        .i_major         (64'd0),
        .i_minor         (7'd0),
        .i_line_idx      (49'd0),
        .i_level         (mac_level),
        .i_node_idx      (mac_node_idx),
        .o_mask_plaintext(),
        .i_expected_tag  (mac_expected_tag),
        .o_valid         (mac_out_valid),
        .i_ready         (1'b1),
        .o_tag           (mac_tag),
        .o_tag128        (),
        .o_ghash         (),
        .o_tag_match     (mac_tag_match),
        .o_tag_mismatch  (mac_tag_mismatch)
    );

    // -------------------------------------------------------------------------
    // Bộ nhớ đệm Metadata Cache trên chip (qshield_meta_cache)
    // -------------------------------------------------------------------------
    logic         mc_lk_valid;
    logic [63:0]  mc_lk_addr;
    logic         mc_lk_pin;
    wire          mc_lk_hit;
    wire  [1:0]   mc_lk_way;
    wire  [511:0] mc_lk_data;
    wire          mc_lk_dirty;
    wire          mc_lk_verified;
    wire          mc_lk_pinned;

    logic         mc_fl_valid;
    logic [63:0]  mc_fl_addr;
    logic [511:0] mc_fl_data;
    logic         mc_fl_verified;
    logic         mc_fl_pin;
    wire  [1:0]   mc_fl_way;
    wire          mc_ev_valid;
    wire          mc_ev_dirty;
    wire  [63:0]  mc_ev_addr;
    wire  [511:0] mc_ev_data;

    logic         mc_up_valid;
    logic [63:0]  mc_up_addr;
    logic [511:0] mc_up_data;
    logic         mc_up_dirty;
    logic         mc_up_data_en;
    wire          mc_up_hit;
    wire  [1:0]   mc_up_way;

    logic         mc_un_valid;
    logic [63:0]  mc_un_addr;

    logic         mc_flush_start;
    logic         mc_flush_ready;
    wire          mc_flush_busy;
    wire          mc_flush_done;
    wire          mc_flush_ev_valid;
    wire  [63:0]  mc_flush_ev_addr;
    wire  [511:0] mc_flush_ev_data;

    wire mc_rst_n = rst_n && !i_cache_clear;

    qshield_meta_cache #(
        .MC_SETS    (MC_SETS),
        .MC_WAYS    (MC_WAYS),
        .ADDR_WIDTH (64),
        .DATA_WIDTH (512)
    ) u_meta_cache (
        .clk                (clk),
        .rst_n              (mc_rst_n),
        .i_lookup_valid     (mc_lk_valid),
        .i_lookup_addr      (mc_lk_addr),
        .i_lookup_pin       (mc_lk_pin),
        .o_lookup_hit       (mc_lk_hit),
        .o_lookup_way       (mc_lk_way),
        .o_lookup_data      (mc_lk_data),
        .o_lookup_dirty     (mc_lk_dirty),
        .o_lookup_verified  (mc_lk_verified),
        .o_lookup_pinned    (mc_lk_pinned),
        .i_fill_valid       (mc_fl_valid),
        .i_fill_addr        (mc_fl_addr),
        .i_fill_data        (mc_fl_data),
        .i_fill_verified    (mc_fl_verified),
        .i_fill_pin         (mc_fl_pin),
        .o_fill_way         (mc_fl_way),
        .o_evict_valid      (mc_ev_valid),
        .o_evict_dirty      (mc_ev_dirty),
        .o_evict_addr       (mc_ev_addr),
        .o_evict_data       (mc_ev_data),
        .i_update_valid     (mc_up_valid),
        .i_update_addr      (mc_up_addr),
        .i_update_data      (mc_up_data),
        .i_update_dirty     (mc_up_dirty),
        .i_update_data_en   (mc_up_data_en),
        .o_update_hit       (mc_up_hit),
        .o_update_way       (mc_up_way),
        .i_unpin_valid      (mc_un_valid),
        .i_unpin_addr       (mc_un_addr),
        .o_unpin_hit        (),
        .o_unpin_way        (),
        .i_flush_start      (mc_flush_start),
        .i_flush_ready      (mc_flush_ready),
        .o_flush_busy       (mc_flush_busy),
        .o_flush_done       (mc_flush_done),
        .o_flush_evict_valid(mc_flush_ev_valid),
        .o_flush_evict_addr (mc_flush_ev_addr),
        .o_flush_evict_data (mc_flush_ev_data),
        .o_hit_cnt          (),
        .o_miss_cnt         (),
        .o_evict_cnt        (),
        .o_wb_cnt           (),
        .o_set_can_pin      (),
        .o_pin_violation    ()
    );

    // -------------------------------------------------------------------------
    // Khối layout địa chỉ qshield_meta_layout
    // -------------------------------------------------------------------------
    logic [63:0] ml_addr;
    wire  [63:0] ml_line_idx;
    wire  [63:0] ml_cb_addr;
    wire  [5:0]  ml_cb_slot;
    wire  [63:0] ml_ml_addr;
    wire  [2:0]  ml_ml_slot;
    wire         ml_is_prot;
    wire         ml_is_meta;

    qshield_meta_layout #(
        .PROT_BASE  (PROT_BASE),
        .PROT_LINES (PROT_LINES),
        .TREE_ARITY (TREE_ARITY)
    ) u_meta_layout (
        .i_addr     (ml_addr),
        .o_line_idx (ml_line_idx),
        .o_cb_addr  (ml_cb_addr),
        .o_cb_slot  (ml_cb_slot),
        .o_ml_addr  (ml_ml_addr),
        .o_ml_slot  (ml_ml_slot),
        .o_is_prot  (ml_is_prot),
        .o_is_meta  (ml_is_meta),
        .i_tn_level (4'd0),
        .i_tn_index (32'd0),
        .o_tn_addr  (),
        .o_tn_slot  ()
    );

    // -------------------------------------------------------------------------
    // Các thanh ghi trạng thái, bộ đệm node và FSM Engine
    // -------------------------------------------------------------------------
    logic [63:0]  reg_tree_root;
    logic [511:0] reg_tree_root_slots;
    logic [31:0]  reg_tree_fail_cnt;
    logic [31:0]  reg_verify_cnt;
    logic [31:0]  reg_update_cnt;
    logic [31:0]  reg_init_cycles;
    logic         reg_integrity_alert;

    // Bộ nhớ đệm tạm thời khi meta_init
    logic [511:0] l1_init_buf [0:7];
    logic [511:0] l2_init_buf [0:0];

    // FSM States
    typedef enum logic [5:0] {
        ST_IDLE                 = 6'd0,
        // Init flow
        ST_INIT_CB_WR           = 6'd1,
        ST_INIT_CB_HASH         = 6'd2,
        ST_INIT_CB_WAIT         = 6'd3,
        ST_INIT_L1_WR           = 6'd4,
        ST_INIT_L1_HASH         = 6'd5,
        ST_INIT_L1_WAIT         = 6'd6,
        ST_INIT_L2_WR           = 6'd7,
        ST_INIT_L2_HASH         = 6'd8,
        ST_INIT_L2_WAIT         = 6'd9,
        ST_INIT_DONE            = 6'd10,
        // Verify flow
        ST_VERIFY_LK_CB         = 6'd11,
        ST_VERIFY_RD_CB         = 6'd12,
        ST_VERIFY_CB_HASH       = 6'd13,
        ST_VERIFY_CB_HWAIT      = 6'd14,
        ST_VERIFY_LK_L1         = 6'd15,
        ST_VERIFY_RD_L1         = 6'd16,
        ST_VERIFY_L1_HASH       = 6'd17,
        ST_VERIFY_L1_HWAIT      = 6'd18,
        ST_VERIFY_LK_L2         = 6'd19,
        ST_VERIFY_RD_L2         = 6'd20,
        ST_VERIFY_L2_HASH       = 6'd21,
        ST_VERIFY_L2_HWAIT      = 6'd22,
        ST_VERIFY_FILL_L2       = 6'd23,
        ST_VERIFY_FILL_L1       = 6'd24,
        ST_VERIFY_FINISH        = 6'd25,
        // Update flow
        ST_UPDATE_EXEC          = 6'd26,
        ST_UPDATE_SET_DIRTY     = 6'd27,
        // Evict / Flush flow
        ST_EVICT_HASH           = 6'd28,
        ST_EVICT_HWAIT          = 6'd29,
        ST_EVICT_DRAM_WR        = 6'd30,
        ST_EVICT_UP_PARENT      = 6'd31,
        ST_EVICT_LK_PARENT      = 6'd32,
        ST_EVICT_RD_PARENT      = 6'd33,
        ST_EVICT_FILL_PARENT    = 6'd34,
        ST_EVICT_DIRTY_PARENT   = 6'd35,
        ST_EVICT_ACK            = 6'd36
    } state_t;

    state_t state;

    // Biến phụ trợ FSM
    logic [31:0] loop_idx;
    logic [63:0] cur_req_addr;
    logic [511:0] cur_req_data;
    logic [63:0] cur_cb_addr;
    logic [5:0]  cur_cb_slot;
    logic [31:0] cur_cb_idx;

    logic [63:0] cur_l1_addr;
    logic [31:0] cur_l1_idx;
    logic [2:0]  cur_l1_slot;

    logic [63:0] cur_l2_addr;
    logic [31:0] cur_l2_idx;
    logic [2:0]  cur_l2_slot;

    logic [511:0] fetched_cb_data;
    logic [511:0] fetched_l1_data;
    logic [511:0] fetched_l2_data;

    logic [63:0]  calc_cb_hash;
    logic [63:0]  calc_l1_hash;
    logic [63:0]  calc_l2_hash;

    logic [63:0]  ev_target_addr;
    logic [511:0] ev_target_data;
    logic [3:0]   ev_level;
    logic [31:0]  ev_idx;
    logic [63:0]  ev_hash;
    logic [31:0]  flush_evict_count;

    logic [63:0]  p_addr;
    logic [2:0]   p_slot;
    logic [511:0] parent_data;

    logic         normal_evict_pending;
    logic         pending_ev_data_cap;
    logic         lk_data_ready;
    logic [63:0]  pending_ev_addr;
    logic [511:0] pending_ev_data;

    // Gán đầu ra
    assign o_tree_root       = reg_tree_root;
    assign o_tree_root_slots = reg_tree_root_slots;
    assign o_tree_fail_cnt   = reg_tree_fail_cnt;
    assign o_verify_cnt      = reg_verify_cnt;
    assign o_update_cnt      = reg_update_cnt;
    assign o_init_cycles     = reg_init_cycles;
    assign o_integrity_alert = reg_integrity_alert;

    assign o_verify_ready = (state == ST_IDLE) && !normal_evict_pending;
    assign o_update_ready = (state == ST_IDLE) && !normal_evict_pending;

    // -------------------------------------------------------------------------
    // Tiến trình điều khiển FSM chính
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                <= ST_IDLE;
            reg_tree_root        <= 64'd0;
            reg_tree_root_slots  <= '0;
            reg_tree_fail_cnt    <= 32'd0;
            reg_verify_cnt       <= 32'd0;
            reg_update_cnt       <= 32'd0;
            reg_init_cycles      <= 32'd0;
            reg_integrity_alert  <= 1'b0;

            o_init_busy          <= 1'b0;
            o_init_done          <= 1'b0;
            o_flush_busy         <= 1'b0;
            o_flush_done         <= 1'b0;

            o_verify_done        <= 1'b0;
            o_verify_pass        <= 1'b0;
            o_verify_fail        <= 1'b0;
            o_cb_data            <= '0;
            o_cb_slot            <= '0;

            o_update_done        <= 1'b0;

            o_dram_rd_valid      <= 1'b0;
            o_dram_rd_addr       <= '0;
            o_dram_wr_valid      <= 1'b0;
            o_dram_wr_addr       <= '0;
            o_dram_wr_data       <= '0;

            mc_lk_valid          <= 1'b0;
            mc_lk_addr           <= '0;
            mc_lk_pin            <= 1'b0;
            mc_fl_valid          <= 1'b0;
            mc_fl_addr           <= '0;
            mc_fl_data           <= '0;
            mc_fl_verified       <= 1'b0;
            mc_fl_pin            <= 1'b0;
            mc_up_valid          <= 1'b0;
            mc_up_addr           <= '0;
            mc_up_data           <= '0;
            mc_up_dirty          <= 1'b0;
            mc_up_data_en        <= 1'b0;
            mc_un_valid          <= 1'b0;
            mc_un_addr           <= '0;
            mc_flush_start       <= 1'b0;
            mc_flush_ready       <= 1'b0;

            mac_valid            <= 1'b0;
            mac_data             <= '0;
            mac_mask             <= '0;
            mac_level            <= '0;
            mac_node_idx         <= '0;
            mac_expected_tag     <= '0;

            aes_in_valid         <= 1'b0;
            aes_in_pt            <= '0;

            loop_idx             <= 32'd0;
            cur_req_addr         <= '0;
            cur_req_data         <= '0;
            flush_evict_count    <= 32'd0;
            normal_evict_pending <= 1'b0;
            pending_ev_data_cap  <= 1'b0;
            lk_data_ready        <= 1'b0;
            pending_ev_addr      <= '0;
            pending_ev_data      <= '0;

            l1_init_buf[0] <= '0; l1_init_buf[1] <= '0; l1_init_buf[2] <= '0; l1_init_buf[3] <= '0;
            l1_init_buf[4] <= '0; l1_init_buf[5] <= '0; l1_init_buf[6] <= '0; l1_init_buf[7] <= '0;
            l2_init_buf[0] <= '0;
        end else begin
            o_init_done     <= 1'b0;
            o_flush_done    <= 1'b0;
            o_verify_done   <= 1'b0;
            o_verify_pass   <= 1'b0;
            o_verify_fail   <= 1'b0;
            o_update_done   <= 1'b0;
            o_dram_rd_valid <= 1'b0;
            o_dram_wr_valid <= 1'b0;
            mc_lk_valid     <= 1'b0;
            mc_fl_valid     <= 1'b0;
            mc_up_valid     <= 1'b0;
            mc_un_valid     <= 1'b0;
            mc_flush_start  <= 1'b0;
            mc_flush_ready  <= 1'b0;
            mac_valid       <= 1'b0;
            aes_in_valid    <= 1'b0;

            if (o_init_busy) reg_init_cycles <= reg_init_cycles + 1'b1;

            // Bắt sự kiện evict dòng dirty trong lúc fill
            if (pending_ev_data_cap) begin
                pending_ev_data     <= mc_ev_data;
                pending_ev_data_cap <= 1'b0;
            end
            if (mc_fl_valid && mc_ev_valid && mc_ev_dirty) begin
                normal_evict_pending <= 1'b1;
                pending_ev_data_cap  <= 1'b1;
                pending_ev_addr      <= mc_ev_addr;
            end

            case (state)
                ST_IDLE: begin
                    lk_data_ready <= 1'b0;
                    if (normal_evict_pending) begin
                        if (!pending_ev_data_cap) begin
                            state <= ST_EVICT_HASH;
                        end
                    end else if (i_init_start) begin
                        o_init_busy     <= 1'b1;
                        reg_init_cycles <= 32'd0;
                        loop_idx        <= 32'd0;
                        state           <= ST_INIT_CB_WR;
                    end else if (i_flush_start) begin
                        o_flush_busy      <= 1'b1;
                        flush_evict_count <= 32'd0;
                        mc_flush_start    <= 1'b1;
                        state             <= ST_EVICT_HASH;
                    end else if (i_verify_valid) begin
                        cur_req_addr   <= i_verify_addr;
                        reg_verify_cnt <= reg_verify_cnt + 1'b1;
                        ml_addr        <= i_verify_addr;
                        cur_cb_addr    <= CB_BASE + ((((i_verify_addr - PROT_BASE) >> 6) >> 6) << 6);
                        cur_cb_slot    <= ((i_verify_addr - PROT_BASE) >> 6) & 6'h3F;
                        cur_cb_idx     <= ((i_verify_addr - PROT_BASE) >> 6) >> 6;
                        mc_lk_valid    <= 1'b1;
                        mc_lk_addr     <= CB_BASE + ((((i_verify_addr - PROT_BASE) >> 6) >> 6) << 6);
                        state          <= ST_VERIFY_LK_CB;
                    end else if (i_update_valid) begin
                        cur_req_addr   <= i_update_addr;
                        cur_req_data   <= i_update_cb_data;
                        reg_update_cnt <= reg_update_cnt + 1'b1;
                        cur_cb_addr    <= CB_BASE + ((((i_update_addr - PROT_BASE) >> 6) >> 6) << 6);
                        cur_cb_slot    <= ((i_update_addr - PROT_BASE) >> 6) & 6'h3F;
                        cur_cb_idx     <= ((i_update_addr - PROT_BASE) >> 6) >> 6;
                        mc_up_valid    <= 1'b1;
                        mc_up_addr     <= CB_BASE + ((((i_update_addr - PROT_BASE) >> 6) >> 6) << 6);
                        mc_up_data     <= i_update_cb_data;
                        mc_up_dirty    <= 1'b1;
                        mc_up_data_en  <= 1'b1;
                        state          <= ST_UPDATE_EXEC;
                    end
                end

                // -------------------------------------------------------------
                // Flow meta_init: Khởi tạo toàn bộ CB, L1, L2 và root
                // -------------------------------------------------------------
                ST_INIT_CB_WR: begin
                    o_dram_wr_valid <= 1'b1;
                    o_dram_wr_addr  <= CB_BASE + loop_idx * 64;
                    o_dram_wr_data  <= '0;
                    aes_in_valid    <= 1'b1;
                    aes_in_pt       <= {8'h02, 4'd0, 60'(loop_idx), 56'd0};
                    state           <= ST_INIT_CB_HASH;
                end

                ST_INIT_CB_HASH: begin
                    if (aes_out_valid) begin
                        mac_valid        <= 1'b1;
                        mac_data         <= '0;
                        mac_mask         <= aes_out_ct;
                        mac_level        <= 4'd0;
                        mac_node_idx     <= 60'(loop_idx);
                        mac_expected_tag <= '0;
                        state            <= ST_INIT_CB_WAIT;
                    end
                end

                ST_INIT_CB_WAIT: begin
                    if (mac_out_valid) begin
                        l1_init_buf[loop_idx / 8][(loop_idx % 8)*64 +: 64] <= mac_tag;
                        if (loop_idx == NUM_CB - 1) begin
                            loop_idx <= 32'd0;
                            state    <= ST_INIT_L1_WR;
                        end else begin
                            loop_idx <= loop_idx + 1'b1;
                            state    <= ST_INIT_CB_WR;
                        end
                    end
                end

                ST_INIT_L1_WR: begin
                    o_dram_wr_valid <= 1'b1;
                    o_dram_wr_addr  <= TN_L1_BASE + loop_idx * 64;
                    o_dram_wr_data  <= l1_init_buf[loop_idx];
                    aes_in_valid    <= 1'b1;
                    aes_in_pt       <= {8'h02, 4'd1, 60'(loop_idx), 56'd0};
                    state           <= ST_INIT_L1_HASH;
                end

                ST_INIT_L1_HASH: begin
                    if (aes_out_valid) begin
                        mac_valid        <= 1'b1;
                        mac_data         <= l1_init_buf[loop_idx];
                        mac_mask         <= aes_out_ct;
                        mac_level        <= 4'd1;
                        mac_node_idx     <= 60'(loop_idx);
                        mac_expected_tag <= '0;
                        state            <= ST_INIT_L1_WAIT;
                    end
                end

                ST_INIT_L1_WAIT: begin
                    if (mac_out_valid) begin
                        l2_init_buf[loop_idx / 8][(loop_idx % 8)*64 +: 64] <= mac_tag;
                        if (loop_idx == TN_L1_COUNT - 1) begin
                            loop_idx <= 32'd0;
                            state    <= ST_INIT_L2_WR;
                        end else begin
                            loop_idx <= loop_idx + 1'b1;
                            state    <= ST_INIT_L1_WR;
                        end
                    end
                end

                ST_INIT_L2_WR: begin
                    o_dram_wr_valid <= 1'b1;
                    o_dram_wr_addr  <= TN_L2_BASE + loop_idx * 64;
                    o_dram_wr_data  <= l2_init_buf[loop_idx];
                    aes_in_valid    <= 1'b1;
                    aes_in_pt       <= {8'h02, 4'd2, 60'(loop_idx), 56'd0};
                    state           <= ST_INIT_L2_HASH;
                end

                ST_INIT_L2_HASH: begin
                    if (aes_out_valid) begin
                        mac_valid        <= 1'b1;
                        mac_data         <= l2_init_buf[loop_idx];
                        mac_mask         <= aes_out_ct;
                        mac_level        <= 4'd2;
                        mac_node_idx     <= 60'(loop_idx);
                        mac_expected_tag <= '0;
                        state            <= ST_INIT_L2_WAIT;
                    end
                end

                ST_INIT_L2_WAIT: begin
                    if (mac_out_valid) begin
                        reg_tree_root                <= mac_tag;
                        reg_tree_root_slots[0 +: 64] <= mac_tag;
                        state                        <= ST_INIT_DONE;
                    end
                end

                ST_INIT_DONE: begin
                    o_init_busy <= 1'b0;
                    o_init_done <= 1'b1;
                    state       <= ST_IDLE;
                end

                // -------------------------------------------------------------
                // Flow Verify: Tra cứu MC -> trượt thì đọc DRAM và xác minh lên gốc
                // -------------------------------------------------------------
                ST_VERIFY_LK_CB: begin
                    if (lk_data_ready) begin
                        lk_data_ready <= 1'b0;
                        o_cb_data     <= mc_lk_data;
                        o_cb_slot     <= cur_cb_slot;
                        o_verify_pass <= 1'b1;
                        o_verify_done <= 1'b1;
                        state         <= ST_IDLE;
                    end else if (mc_lk_hit && mc_lk_verified) begin
                        // Wait 1 cycle for synchronous cache BRAM read
                        lk_data_ready <= 1'b1;
                    end else begin
                        o_dram_rd_valid <= 1'b1;
                        o_dram_rd_addr  <= cur_cb_addr;
                        state           <= ST_VERIFY_RD_CB;
                    end
                end

                ST_VERIFY_RD_CB: begin
                    if (i_dram_rd_valid) begin
                        fetched_cb_data <= i_dram_rd_data;
                        aes_in_valid    <= 1'b1;
                        aes_in_pt       <= {8'h02, 4'd0, 60'(cur_cb_idx), 56'd0};
                        state           <= ST_VERIFY_CB_HASH;
                    end
                end

                ST_VERIFY_CB_HASH: begin
                    if (aes_out_valid) begin
                        mac_valid    <= 1'b1;
                        mac_data     <= fetched_cb_data;
                        mac_mask     <= aes_out_ct;
                        mac_level    <= 4'd0;
                        mac_node_idx <= 60'(cur_cb_idx);
                        state        <= ST_VERIFY_CB_HWAIT;
                    end
                end

                ST_VERIFY_CB_HWAIT: begin
                    if (mac_out_valid) begin
                        calc_cb_hash <= mac_tag;
                        cur_l1_idx   <= cur_cb_idx / 8;
                        cur_l1_slot  <= cur_cb_idx % 8;
                        cur_l1_addr  <= TN_L1_BASE + (cur_cb_idx / 8) * 64;
                        mc_lk_valid  <= 1'b1;
                        mc_lk_addr   <= TN_L1_BASE + (cur_cb_idx / 8) * 64;
                        state        <= ST_VERIFY_LK_L1;
                    end
                end

                ST_VERIFY_LK_L1: begin
                    if (lk_data_ready) begin
                        lk_data_ready <= 1'b0;
                        if (calc_cb_hash == mc_lk_data[cur_l1_slot*64 +: 64]) begin
                            mc_fl_valid     <= 1'b1;
                            mc_fl_addr      <= cur_cb_addr;
                            mc_fl_data      <= fetched_cb_data;
                            mc_fl_verified  <= 1'b1;
                            mc_fl_pin       <= 1'b0;
                            o_cb_data       <= fetched_cb_data;
                            o_cb_slot       <= cur_cb_slot;
                            o_verify_pass   <= 1'b1;
                            o_verify_done   <= 1'b1;
                            state           <= ST_IDLE;
                        end else begin
                            reg_tree_fail_cnt   <= reg_tree_fail_cnt + 1'b1;
                            reg_integrity_alert <= 1'b1;
                            o_verify_fail       <= 1'b1;
                            o_verify_done       <= 1'b1;
                            state               <= ST_IDLE;
                        end
                    end else if (mc_lk_hit && mc_lk_verified) begin
                        lk_data_ready <= 1'b1;
                    end else begin
                        o_dram_rd_valid <= 1'b1;
                        o_dram_rd_addr  <= cur_l1_addr;
                        state           <= ST_VERIFY_RD_L1;
                    end
                end

                ST_VERIFY_RD_L1: begin
                    if (i_dram_rd_valid) begin
                        fetched_l1_data <= i_dram_rd_data;
                        aes_in_valid    <= 1'b1;
                        aes_in_pt       <= {8'h02, 4'd1, 60'(cur_l1_idx), 56'd0};
                        state           <= ST_VERIFY_L1_HASH;
                    end
                end

                ST_VERIFY_L1_HASH: begin
                    if (aes_out_valid) begin
                        mac_valid    <= 1'b1;
                        mac_data     <= fetched_l1_data;
                        mac_mask     <= aes_out_ct;
                        mac_level    <= 4'd1;
                        mac_node_idx <= 60'(cur_l1_idx);
                        state        <= ST_VERIFY_L1_HWAIT;
                    end
                end

                ST_VERIFY_L1_HWAIT: begin
                    if (mac_out_valid) begin
                        calc_l1_hash <= mac_tag;
                        cur_l2_idx   <= cur_l1_idx / 8;
                        cur_l2_slot  <= cur_l1_idx % 8;
                        cur_l2_addr  <= TN_L2_BASE + (cur_l1_idx / 8) * 64;
                        mc_lk_valid  <= 1'b1;
                        mc_lk_addr   <= TN_L2_BASE + (cur_l1_idx / 8) * 64;
                        state        <= ST_VERIFY_LK_L2;
                    end
                end

                ST_VERIFY_LK_L2: begin
                    if (lk_data_ready) begin
                        lk_data_ready <= 1'b0;
                        if (calc_l1_hash == mc_lk_data[cur_l2_slot*64 +: 64]) begin
                            if (calc_cb_hash == fetched_l1_data[cur_l1_slot*64 +: 64]) begin
                                mc_fl_valid     <= 1'b1;
                                mc_fl_addr      <= cur_l1_addr;
                                mc_fl_data      <= fetched_l1_data;
                                mc_fl_verified  <= 1'b1;
                                mc_fl_pin       <= 1'b0;
                                state           <= ST_VERIFY_FINISH;
                            end else begin
                                reg_tree_fail_cnt   <= reg_tree_fail_cnt + 1'b1;
                                reg_integrity_alert <= 1'b1;
                                o_verify_fail       <= 1'b1;
                                o_verify_done       <= 1'b1;
                                state               <= ST_IDLE;
                            end
                        end else begin
                            reg_tree_fail_cnt   <= reg_tree_fail_cnt + 1'b1;
                            reg_integrity_alert <= 1'b1;
                            o_verify_fail       <= 1'b1;
                            o_verify_done       <= 1'b1;
                            state               <= ST_IDLE;
                        end
                    end else if (mc_lk_hit && mc_lk_verified) begin
                        lk_data_ready <= 1'b1;
                    end else begin
                        o_dram_rd_valid <= 1'b1;
                        o_dram_rd_addr  <= cur_l2_addr;
                        state           <= ST_VERIFY_RD_L2;
                    end
                end

                ST_VERIFY_RD_L2: begin
                    if (i_dram_rd_valid) begin
                        fetched_l2_data <= i_dram_rd_data;
                        aes_in_valid    <= 1'b1;
                        aes_in_pt       <= {8'h02, 4'd2, 60'(cur_l2_idx), 56'd0};
                        state           <= ST_VERIFY_L2_HASH;
                    end
                end

                ST_VERIFY_L2_HASH: begin
                    if (aes_out_valid) begin
                        mac_valid    <= 1'b1;
                        mac_data     <= fetched_l2_data;
                        mac_mask     <= aes_out_ct;
                        mac_level    <= 4'd2;
                        mac_node_idx <= 60'(cur_l2_idx);
                        state        <= ST_VERIFY_L2_HWAIT;
                    end
                end

                ST_VERIFY_L2_HWAIT: begin
                    if (mac_out_valid) begin
                        calc_l2_hash <= mac_tag;
                        if (mac_tag == reg_tree_root) begin
                            if (calc_l1_hash == fetched_l2_data[cur_l2_slot*64 +: 64]) begin
                                if (calc_cb_hash == fetched_l1_data[cur_l1_slot*64 +: 64]) begin
                                    mc_fl_valid     <= 1'b1;
                                    mc_fl_addr      <= cur_l2_addr;
                                    mc_fl_data      <= fetched_l2_data;
                                    mc_fl_verified  <= 1'b1;
                                    mc_fl_pin       <= 1'b0;
                                    state           <= ST_VERIFY_FILL_L1;
                                end else begin
                                    reg_tree_fail_cnt   <= reg_tree_fail_cnt + 1'b1;
                                    reg_integrity_alert <= 1'b1;
                                    o_verify_fail       <= 1'b1;
                                    o_verify_done       <= 1'b1;
                                    state               <= ST_IDLE;
                                end
                            end else begin
                                reg_tree_fail_cnt   <= reg_tree_fail_cnt + 1'b1;
                                reg_integrity_alert <= 1'b1;
                                o_verify_fail       <= 1'b1;
                                o_verify_done       <= 1'b1;
                                state               <= ST_IDLE;
                            end
                        end else begin
                            reg_tree_fail_cnt   <= reg_tree_fail_cnt + 1'b1;
                            reg_integrity_alert <= 1'b1;
                            o_verify_fail       <= 1'b1;
                            o_verify_done       <= 1'b1;
                            state               <= ST_IDLE;
                        end
                    end
                end

                ST_VERIFY_FILL_L1: begin
                    mc_fl_valid    <= 1'b1;
                    mc_fl_addr     <= cur_l1_addr;
                    mc_fl_data     <= fetched_l1_data;
                    mc_fl_verified <= 1'b1;
                    mc_fl_pin      <= 1'b0;
                    state          <= ST_VERIFY_FINISH;
                end

                ST_VERIFY_FINISH: begin
                    mc_fl_valid    <= 1'b1;
                    mc_fl_addr     <= cur_cb_addr;
                    mc_fl_data     <= fetched_cb_data;
                    mc_fl_verified <= 1'b1;
                    mc_fl_pin      <= 1'b0;
                    o_cb_data      <= fetched_cb_data;
                    o_cb_slot      <= cur_cb_slot;
                    o_verify_pass  <= 1'b1;
                    o_verify_done  <= 1'b1;
                    state          <= ST_IDLE;
                end

                // -------------------------------------------------------------
                // Flow Update: Cập nhật CB vào MC (dirty=1)
                // -------------------------------------------------------------
                ST_UPDATE_EXEC: begin
                    if (mc_up_hit) begin
                        o_update_done <= 1'b1;
                        state         <= ST_IDLE;
                    end else begin
                        mc_fl_valid    <= 1'b1;
                        mc_fl_addr     <= cur_cb_addr;
                        mc_fl_data     <= cur_req_data;
                        mc_fl_verified <= 1'b1;
                        mc_fl_pin      <= 1'b0;
                        state          <= ST_UPDATE_SET_DIRTY;
                    end
                end

                ST_UPDATE_SET_DIRTY: begin
                    mc_up_valid   <= 1'b1;
                    mc_up_addr    <= cur_cb_addr;
                    mc_up_data    <= cur_req_data;
                    mc_up_dirty   <= 1'b1;
                    mc_up_data_en <= 1'b1;
                    o_update_done <= 1'b1;
                    state         <= ST_IDLE;
                end

                // -------------------------------------------------------------
                // Flow Evict / Flush: Lan truyền lười khi đẩy dòng dirty khỏi MC
                // -------------------------------------------------------------
                ST_EVICT_HASH: begin
                    if (o_flush_busy) begin
                        if (mc_flush_done) begin
                            if (flush_evict_count == 32'd0) begin
                                o_flush_busy <= 1'b0;
                                o_flush_done <= 1'b1;
                                state        <= ST_IDLE;
                            end else begin
                                // Vòng quét tiếp theo cho các node cha vừa nhận dirty
                                flush_evict_count <= 32'd0;
                                mc_flush_start    <= 1'b1;
                                state             <= ST_EVICT_HASH;
                            end
                        end else if (mc_flush_ev_valid) begin
                            ev_target_addr    <= mc_flush_ev_addr;
                            ev_target_data    <= mc_flush_ev_data;
                            flush_evict_count <= flush_evict_count + 1'b1;

                            if (mc_flush_ev_addr < ML_BASE) begin
                                ev_level <= 4'd0;
                                ev_idx   <= 32'((mc_flush_ev_addr - CB_BASE) >> 6);
                            end else if (mc_flush_ev_addr < TN_L2_BASE) begin
                                ev_level <= 4'd1;
                                ev_idx   <= 32'((mc_flush_ev_addr - TN_L1_BASE) >> 6);
                            end else begin
                                ev_level <= 4'd2;
                                ev_idx   <= 32'((mc_flush_ev_addr - TN_L2_BASE) >> 6);
                            end

                            aes_in_valid <= 1'b1;
                            aes_in_pt    <= (mc_flush_ev_addr < ML_BASE) ?
                                            {8'h02, 4'd0, 60'((mc_flush_ev_addr - CB_BASE) >> 6), 56'd0} :
                                            ((mc_flush_ev_addr < TN_L2_BASE) ?
                                             {8'h02, 4'd1, 60'((mc_flush_ev_addr - TN_L1_BASE) >> 6), 56'd0} :
                                             {8'h02, 4'd2, 60'((mc_flush_ev_addr - TN_L2_BASE) >> 6), 56'd0});
                            state        <= ST_EVICT_HWAIT;
                        end
                    end else if (normal_evict_pending) begin
                        ev_target_addr       <= pending_ev_addr;
                        ev_target_data       <= pending_ev_data;
                        normal_evict_pending <= 1'b0;

                        if (pending_ev_addr < ML_BASE) begin
                            ev_level <= 4'd0;
                            ev_idx   <= 32'((pending_ev_addr - CB_BASE) >> 6);
                        end else if (pending_ev_addr < TN_L2_BASE) begin
                            ev_level <= 4'd1;
                            ev_idx   <= 32'((pending_ev_addr - TN_L1_BASE) >> 6);
                        end else begin
                            ev_level <= 4'd2;
                            ev_idx   <= 32'((pending_ev_addr - TN_L2_BASE) >> 6);
                        end

                        aes_in_valid <= 1'b1;
                        aes_in_pt    <= (pending_ev_addr < ML_BASE) ?
                                        {8'h02, 4'd0, 60'((pending_ev_addr - CB_BASE) >> 6), 56'd0} :
                                        ((pending_ev_addr < TN_L2_BASE) ?
                                         {8'h02, 4'd1, 60'((pending_ev_addr - TN_L1_BASE) >> 6), 56'd0} :
                                         {8'h02, 4'd2, 60'((pending_ev_addr - TN_L2_BASE) >> 6), 56'd0});
                        state        <= ST_EVICT_HWAIT;
                    end else begin
                        state <= ST_IDLE;
                    end
                end

                ST_EVICT_HWAIT: begin
                    if (aes_out_valid) begin
                        mac_valid       <= 1'b1;
                        mac_data        <= ev_target_data;
                        mac_mask        <= aes_out_ct;
                        mac_level       <= ev_level;
                        mac_node_idx    <= 60'(ev_idx);
                        o_dram_wr_valid <= 1'b1;
                        o_dram_wr_addr  <= ev_target_addr;
                        o_dram_wr_data  <= ev_target_data;
                        state           <= ST_EVICT_DRAM_WR;
                    end
                end

                ST_EVICT_DRAM_WR: begin
                    if (mac_out_valid) begin
                        ev_hash <= mac_tag;
                        state   <= ST_EVICT_UP_PARENT;
                    end
                end

                ST_EVICT_UP_PARENT: begin
                    if (ev_level == 4'd2) begin
                        reg_tree_root                <= ev_hash;
                        reg_tree_root_slots[0 +: 64] <= ev_hash;
                        state                        <= ST_EVICT_ACK;
                    end else begin
                        if (ev_level == 4'd0) begin
                            p_addr <= TN_L1_BASE + (ev_idx / 8) * 64;
                            p_slot <= ev_idx % 8;
                            mc_lk_valid <= 1'b1;
                            mc_lk_addr  <= TN_L1_BASE + (ev_idx / 8) * 64;
                        end else begin
                            p_addr <= TN_L2_BASE;
                            p_slot <= ev_idx % 8;
                            mc_lk_valid <= 1'b1;
                            mc_lk_addr  <= TN_L2_BASE;
                        end
                        state <= ST_EVICT_LK_PARENT;
                    end
                end

                ST_EVICT_LK_PARENT: begin
                    if (lk_data_ready) begin
                        lk_data_ready <= 1'b0;
                        parent_data = mc_lk_data;
                        parent_data[p_slot*64 +: 64] = ev_hash;
                        mc_up_valid   <= 1'b1;
                        mc_up_addr    <= p_addr;
                        mc_up_data    <= parent_data;
                        mc_up_dirty   <= 1'b1;
                        mc_up_data_en <= 1'b1;
                        state         <= ST_EVICT_ACK;
                    end else if (mc_lk_hit) begin
                        lk_data_ready <= 1'b1;
                    end else begin
                        o_dram_rd_valid <= 1'b1;
                        o_dram_rd_addr  <= p_addr;
                        state           <= ST_EVICT_RD_PARENT;
                    end
                end

                ST_EVICT_RD_PARENT: begin
                    if (i_dram_rd_valid) begin
                        parent_data = i_dram_rd_data;
                        parent_data[p_slot*64 +: 64] = ev_hash;
                        mc_fl_valid    <= 1'b1;
                        mc_fl_addr     <= p_addr;
                        mc_fl_data     <= parent_data;
                        mc_fl_verified <= 1'b1;
                        mc_fl_pin      <= 1'b0;
                        state          <= ST_EVICT_DIRTY_PARENT;
                    end
                end

                ST_EVICT_DIRTY_PARENT: begin
                    mc_up_valid   <= 1'b1;
                    mc_up_addr    <= p_addr;
                    mc_up_data    <= parent_data;
                    mc_up_dirty   <= 1'b1;
                    mc_up_data_en <= 1'b1;
                    state         <= ST_EVICT_ACK;
                end

                ST_EVICT_ACK: begin
                    if (o_flush_busy) begin
                        mc_flush_ready <= 1'b1;
                        state          <= ST_EVICT_HASH;
                    end else begin
                        state <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
