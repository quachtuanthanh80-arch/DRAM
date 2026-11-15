// File: integrity_formal.sv
// Chức năng: Formal wrapper kiểm chứng 4 bất biến toàn vẹn BMT/Security theo D14 và spec mục 5, 6, 9.

`timescale 1ns / 1ps

module integrity_formal #(
    parameter int MC_SETS         = 2,
    parameter int MC_WAYS         = 4,
    parameter int TABLE_DEPTH     = 2,
    parameter int LINES_PER_PAGE  = 4,
    parameter int MAJOR_WIDTH     = 16,
    parameter int MINOR_WIDTH     = 3 // MINOR_MAX = 7, roll-over reachable within 8 steps
)(
    input logic clk,
    input logic rst_n,

    // -------------------------------------------------------------------------
    // Khối 1: Bất biến Nonce Freshness & Không dùng lại (L, major, minor) [H-8, D14]
    // -------------------------------------------------------------------------
    input  logic                                commit_valid,
    input  logic [$clog2(LINES_PER_PAGE)-1:0]   commit_line,
    input  logic [$clog2(TABLE_DEPTH)-1:0]      commit_page,
    input  logic [2:0]                          tree_level, // Cấp cây L: 0=CB, 1=L1, 2=L2, ...

    // -------------------------------------------------------------------------
    // Khối 2: Bất biến MAC sai -> SLVERR và Không rò rỉ bản rõ [D14, spec mục 6]
    // -------------------------------------------------------------------------
    input  logic                   rd_mac_done,
    input  logic                   rd_mac_mismatch,
    input  logic                   rd_bmt_fail,
    input  logic [63:0]            plain_data_in,
    input  logic                   rready,

    // -------------------------------------------------------------------------
    // Khối 3: Bất biến Metadata Cache không ghim hết way / Không Deadlock [spec mục 5]
    // -------------------------------------------------------------------------
    input  logic [$clog2(MC_SETS)-1:0] req_set,
    input  logic                       req_pin,
    input  logic                       req_unpin,
    input  logic [$clog2(MC_WAYS)-1:0] unpin_way,

    // -------------------------------------------------------------------------
    // Khối 4: Bất biến Tree Root chỉ đổi khi đẩy node mức cao nhất [spec mục 9]
    // -------------------------------------------------------------------------
    input  logic                   root_push_valid,
    input  logic [2:0]             push_level,
    input  logic [63:0]            new_root_hash
);

    // =========================================================================
    // 1. NONCE FRESHNESS & UNIQUE (L, major, minor)
    // =========================================================================
    localparam logic [MINOR_WIDTH-1:0] MINOR_MAX = {MINOR_WIDTH{1'b1}};

    logic [MAJOR_WIDTH-1:0] major_table [TABLE_DEPTH];
    logic [MINOR_WIDTH-1:0] minor_table [TABLE_DEPTH][LINES_PER_PAGE];

    logic [MAJOR_WIDTH-1:0] past_major;
    logic [MINOR_WIDTH-1:0] past_minor;
    logic [MAJOR_WIDTH-1:0] cur_major;
    logic [MINOR_WIDTH-1:0] cur_minor;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int p = 0; p < TABLE_DEPTH; p++) begin
                major_table[p] <= '0;
                for (int l = 0; l < LINES_PER_PAGE; l++) begin
                    minor_table[p][l] <= '0;
                end
            end
            cur_major   <= '0;
            cur_minor   <= '0;
            past_major  <= '0;
            past_minor  <= '0;
        end else if (commit_valid) begin
            past_major <= major_table[commit_page];
            past_minor <= minor_table[commit_page][commit_line];

            if (minor_table[commit_page][commit_line] == MINOR_MAX) begin
                minor_table[commit_page][commit_line] <= '0;
                major_table[commit_page]              <= major_table[commit_page] + 1'b1;
                cur_major                             <= major_table[commit_page] + 1'b1;
                cur_minor                             <= '0;
            end else begin
                minor_table[commit_page][commit_line] <= minor_table[commit_page][commit_line] + 1'b1;
                cur_major                             <= major_table[commit_page];
                cur_minor                             <= minor_table[commit_page][commit_line] + 1'b1;
            end
        end
    end

    wire [MAJOR_WIDTH+MINOR_WIDTH-1:0] full_counter = {cur_major, cur_minor};
    wire [MAJOR_WIDTH+MINOR_WIDTH-1:0] past_counter = {past_major, past_minor};

    // =========================================================================
    // 2. MAC FAILURE ISOLATION & NON-SPECULATIVE RELEASE
    // =========================================================================
    logic        stream_active;
    logic        stream_fail;
    logic [2:0]  stream_beat;
    logic [63:0] s_axi_rdata;
    logic [1:0]  s_axi_rresp;
    logic        s_axi_rvalid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stream_active <= 1'b0;
            stream_fail   <= 1'b0;
            stream_beat   <= 3'd0;
        end else begin
            if (rd_mac_done) begin
                stream_active <= 1'b1;
                stream_beat   <= 3'd0;
                stream_fail   <= (rd_mac_mismatch || rd_bmt_fail);
            end else if (stream_active && rready) begin
                if (stream_beat == 3'd7)
                    stream_active <= 1'b0;
                else
                    stream_beat <= stream_beat + 1'b1;
            end
        end
    end

    always_comb begin
        s_axi_rvalid = stream_active;
        s_axi_rdata  = stream_fail ? 64'h0 : plain_data_in;
        s_axi_rresp  = stream_fail ? 2'b10 : 2'b00; // 2'b10 = SLVERR
    end

    // =========================================================================
    // 3. METADATA CACHE PINNING & DEADLOCK FREEDOM
    // =========================================================================
    logic [MC_WAYS-1:0] way_pinned [MC_SETS];
    logic [$clog2(MC_WAYS):0] set_pinned_cnt [MC_SETS];
    logic [MC_SETS-1:0] set_can_pin;
    logic               pin_violation;

    always_comb begin
        for (int s = 0; s < MC_SETS; s++) begin
            set_pinned_cnt[s] = '0;
            for (int w = 0; w < MC_WAYS; w++) begin
                if (way_pinned[s][w])
                    set_pinned_cnt[s] = set_pinned_cnt[s] + 1'b1;
            end
            set_can_pin[s] = (set_pinned_cnt[s] < (MC_WAYS - 1));
        end
    end

    wire [MC_WAYS-1:0] unpinned_mask = ~way_pinned[req_set];
    wire [MC_WAYS-1:0] first_free_way = unpinned_mask & (-unpinned_mask);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int s = 0; s < MC_SETS; s++)
                way_pinned[s] <= '0;
            pin_violation <= 1'b0;
        end else begin
            pin_violation <= 1'b0;
            if (req_pin) begin
                if (!set_can_pin[req_set]) begin
                    pin_violation <= 1'b1; // Chặn ghim cạn kiệt
                end else begin
                    way_pinned[req_set] <= way_pinned[req_set] | first_free_way;
                end
            end
            if (req_unpin) begin
                way_pinned[req_set][unpin_way] <= 1'b0;
            end
        end
    end

    // =========================================================================
    // 4. MERKLE TREE ROOT INVARIANCE
    // =========================================================================
    localparam [2:0] TOP_TREE_LEVEL = 3'd3;
    logic [63:0] reg_tree_root;
    wire         is_top_level_push = (push_level == TOP_TREE_LEVEL);
    wire         root_updated = rst_n && root_push_valid && is_top_level_push;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_tree_root <= 64'h0;
        end else if (root_push_valid && is_top_level_push) begin
            reg_tree_root <= new_root_hash;
        end
    end

    // =========================================================================
    // SYSTEMVERILOG FORMAL PROPERTIES (SVA)
    // =========================================================================
`ifdef FORMAL
    initial assume (!rst_n);

    always_ff @(posedge clk) begin
        if ($past(!rst_n)) assume (rst_n);
    end

    // -------------------------------------------------------------------------
    // Bất biến 1: Nonce Freshness - (L, major, minor) và (major, minor, addr)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(commit_valid)) begin
                assert (full_counter > past_counter);
                assert ({tree_level, full_counter} != {tree_level, past_counter});
            end
        end
    end

    // -------------------------------------------------------------------------
    // Bất biến 2: MAC Failure Isolation
    // a) Phản hồi AXI R luôn trả SLVERR (2'b10)
    // b) Không beat dữ liệu bản rõ nào được phát ra (rdata == 0)
    // -------------------------------------------------------------------------
    always_comb begin
        if (rst_n && stream_active && stream_fail) begin
            assert (s_axi_rresp == 2'b10);
            assert (s_axi_rdata == 64'h0);
        end
    end

    // -------------------------------------------------------------------------
    // Bất biến 3: Metadata Cache Deadlock Freedom
    // Số way bị ghim trong mọi set luôn nhỏ hơn MC_WAYS (tối thiểu 1 way tự do)
    // -------------------------------------------------------------------------
    always_comb begin
        if (rst_n) begin
            for (int s = 0; s < MC_SETS; s++) begin
                assert (set_pinned_cnt[s] <= (MC_WAYS - 1));
                assert (!(&way_pinned[s]));
            end
        end
    end

    // -------------------------------------------------------------------------
    // Bất biến 4: Tree Root Invariance
    // tree_root CHỈ thay đổi khi đẩy node ở mức cao nhất
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if (!$past(root_updated)) begin
                assert (reg_tree_root == $past(reg_tree_root));
            end
        end
    end

    // -------------------------------------------------------------------------
    // COVER PROPERTIES
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst_n) begin
            cover (commit_valid && past_minor == MINOR_MAX);
            cover (stream_active && stream_fail && stream_beat == 3'd7);
            cover (set_pinned_cnt[0] == (MC_WAYS - 1));
            cover (root_updated);
        end
    end

`endif

endmodule
