// File: qshield_meta_cache.sv
// Chức năng: Bộ nhớ đệm metadata tin cậy trên chip (SRAM 64 dòng) sử dụng Pseudo-LRU, write-back và ghim dòng an toàn.

`timescale 1ns / 1ps

module qshield_meta_cache #(
    parameter int MC_SETS    = 16, // Số set (16 sets -> 4 bit chỉ mục)
    parameter int MC_WAYS    = 4,  // Số way mỗi set (4 ways -> 2 bit)
    parameter int ADDR_WIDTH = 64, // Độ rộng địa chỉ DRAM (64-bit)
    parameter int DATA_WIDTH = 512 // 64 bytes dữ liệu một dòng metadata
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // Giao diện tra cứu (Lookup)
    input  logic                   i_lookup_valid,
    input  logic [ADDR_WIDTH-1:0]  i_lookup_addr,
    input  logic                   i_lookup_pin,
    output logic                   o_lookup_hit,
    output logic [1:0]             o_lookup_way,
    output logic [DATA_WIDTH-1:0]  o_lookup_data,
    output logic                   o_lookup_dirty,
    output logic                   o_lookup_verified,
    output logic                   o_lookup_pinned,

    // Giao diện nạp dòng (Fill)
    input  logic                   i_fill_valid,
    input  logic [ADDR_WIDTH-1:0]  i_fill_addr,
    input  logic [DATA_WIDTH-1:0]  i_fill_data,
    input  logic                   i_fill_verified,
    input  logic                   i_fill_pin,
    output logic [1:0]             o_fill_way,
    output logic                   o_evict_valid,
    output logic                   o_evict_dirty,
    output logic [ADDR_WIDTH-1:0]  o_evict_addr,
    output logic [DATA_WIDTH-1:0]  o_evict_data,

    // Giao diện cập nhật (Update dữ liệu / cờ dirty)
    input  logic                   i_update_valid,
    input  logic [ADDR_WIDTH-1:0]  i_update_addr,
    input  logic [DATA_WIDTH-1:0]  i_update_data,
    input  logic                   i_update_dirty,
    input  logic                   i_update_data_en,
    output logic                   o_update_hit,
    output logic [1:0]             o_update_way,

    // Giao diện bỏ ghim (Unpin)
    input  logic                   i_unpin_valid,
    input  logic [ADDR_WIDTH-1:0]  i_unpin_addr,
    output logic                   o_unpin_hit,
    output logic [1:0]             o_unpin_way,

    // Giao diện Flush tuần tự
    input  logic                   i_flush_start,
    input  logic                   i_flush_ready,
    output logic                   o_flush_busy,
    output logic                   o_flush_done,
    output logic                   o_flush_evict_valid,
    output logic [ADDR_WIDTH-1:0]  o_flush_evict_addr,
    output logic [DATA_WIDTH-1:0]  o_flush_evict_data,

    // Bộ đếm sự kiện CSR (32-bit)
    output logic [31:0]            o_hit_cnt,
    output logic [31:0]            o_miss_cnt,
    output logic [31:0]            o_evict_cnt,
    output logic [31:0]            o_wb_cnt,

    // Kiểm tra an toàn chống ghim cạn kiệt
    output logic [MC_SETS-1:0]     o_set_can_pin,
    output logic                   o_pin_violation
);
    localparam int SET_BITS   = $clog2(MC_SETS); // 4
    localparam int WAY_BITS   = $clog2(MC_WAYS); // 2
    localparam int NUM_LINES  = MC_SETS * MC_WAYS; // 64
    localparam int TAG_WIDTH  = ADDR_WIDTH - 6 - SET_BITS; // 54 bit cho ADDR=64

    // Hàm bóc tách set index và tag từ địa chỉ
    function automatic logic [SET_BITS-1:0] get_set(input logic [ADDR_WIDTH-1:0] a);
        return a[6 +: SET_BITS];
    endfunction

    function automatic logic [TAG_WIDTH-1:0] get_tag(input logic [ADDR_WIDTH-1:0] a);
        return a[6 + SET_BITS +: TAG_WIDTH];
    endfunction

    // Hàm cập nhật Tree-PLRU 3-bit khi truy cập way w
    function automatic logic [2:0] next_plru(input logic [2:0] cur, input logic [1:0] w);
        logic b0, b1, b2;
        b0 = cur[2];
        b1 = cur[1];
        b2 = cur[0];
        case (w)
            2'd0: begin b0 = 1'b1; b1 = 1'b1; end
            2'd1: begin b0 = 1'b1; b1 = 1'b0; end
            2'd2: begin b0 = 1'b0; b2 = 1'b1; end
            2'd3: begin b0 = 1'b0; b2 = 1'b0; end
        endcase
        return {b0, b1, b2};
    endfunction

    // Mảng lưu trữ trạng thái và dữ liệu của 64 dòng cache
    logic                  line_valid    [0:NUM_LINES-1];
    logic                  line_dirty    [0:NUM_LINES-1];
    logic                  line_verified [0:NUM_LINES-1];
    logic                  line_pinned   [0:NUM_LINES-1];
    logic [TAG_WIDTH-1:0]  line_tag      [0:NUM_LINES-1];
    // 64x512b synchronous BRAM (no reset on data array to enable SDP Block RAM inference)
    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] line_data [0:NUM_LINES-1];
    logic [DATA_WIDTH-1:0] ram_rd_data;
    logic                  rd_bypass_valid_q;
    logic [DATA_WIDTH-1:0] rd_bypass_data_q;
    wire  [DATA_WIDTH-1:0] rd_data_mux = rd_bypass_valid_q ? rd_bypass_data_q : ram_rd_data;

    // Trạng thái Pseudo-LRU 3-bit cho mỗi set
    logic [2:0]            set_plru      [0:MC_SETS-1];

    // Các bộ đếm CSR
    logic [31:0] reg_hit_cnt;
    logic [31:0] reg_miss_cnt;
    logic [31:0] reg_evict_cnt;
    logic [31:0] reg_wb_cnt;
    logic        reg_pin_violation;

    // FSM cho quá trình Flush
    typedef enum logic [1:0] {
        FLUSH_IDLE = 2'd0,
        FLUSH_SCAN = 2'd1,
        FLUSH_WAIT = 2'd2,
        FLUSH_DONE = 2'd3
    } flush_state_t;

    flush_state_t flush_st;
    logic [5:0]   flush_idx;
    logic         flush_rd_wait;

    // -------------------------------------------------------------------------
    // Logic tổ hợp tính toán số lượng pinned mỗi set
    // -------------------------------------------------------------------------
    logic [2:0] set_pinned_cnt [0:MC_SETS-1];
    generate
        for (genvar s = 0; s < MC_SETS; s++) begin : gen_pin_cnt
            assign set_pinned_cnt[s] = line_pinned[{s[3:0], 2'd0}] +
                                       line_pinned[{s[3:0], 2'd1}] +
                                       line_pinned[{s[3:0], 2'd2}] +
                                       line_pinned[{s[3:0], 2'd3}];
            // Invariant: Luôn chừa ít nhất một way có thể đẩy (ghim tối đa MC_WAYS - 1 = 3 way)
            assign o_set_can_pin[s]  = (set_pinned_cnt[s] < (MC_WAYS - 1));
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Logic Lookup tổ hợp: so sánh tag theo từng set trước rồi mux 1-bit hit (tránh mux 54-bit 16:1 trước CARRY8)
    // -------------------------------------------------------------------------
    logic [SET_BITS-1:0]  lk_set;
    logic [TAG_WIDTH-1:0] lk_tag;
    assign lk_set = i_lookup_addr[6 +: SET_BITS];
    assign lk_tag = i_lookup_addr[6 + SET_BITS +: TAG_WIDTH];

    (* keep = "true" *) logic [MC_WAYS-1:0] lk_match [0:MC_SETS-1];
    always_comb begin
        for (int s = 0; s < MC_SETS; s++) begin
            for (int w = 0; w < MC_WAYS; w++) begin
                lk_match[s][w] = line_valid[s*MC_WAYS + w] && (line_tag[s*MC_WAYS + w] == lk_tag);
            end
        end
    end

    wire lk_hit_0 = lk_match[lk_set][0];
    wire lk_hit_1 = lk_match[lk_set][1];
    wire lk_hit_2 = lk_match[lk_set][2];
    wire lk_hit_3 = lk_match[lk_set][3];

    assign o_lookup_hit = lk_hit_0 | lk_hit_1 | lk_hit_2 | lk_hit_3;
    assign o_lookup_way = {!lk_hit_0 && !lk_hit_1 && (lk_hit_2 || lk_hit_3),
                           !lk_hit_0 && (lk_hit_1 || (!lk_hit_2 && lk_hit_3))};

    wire [5:0] lk_entry = {lk_set, o_lookup_way};
    assign o_lookup_data     = rd_data_mux;
    assign o_lookup_dirty    = line_dirty[lk_entry];
    assign o_lookup_verified = line_verified[lk_entry];
    assign o_lookup_pinned   = line_pinned[lk_entry];

    // -------------------------------------------------------------------------
    // Logic Fill & Victim Selection tổ hợp
    // -------------------------------------------------------------------------
    logic [SET_BITS-1:0]  fl_set;
    logic [TAG_WIDTH-1:0] fl_tag;
    assign fl_set = i_fill_addr[6 +: SET_BITS];
    assign fl_tag = i_fill_addr[6 + SET_BITS +: TAG_WIDTH];

    wire fl_val_0 = line_valid[{fl_set, 2'd0}];
    wire fl_val_1 = line_valid[{fl_set, 2'd1}];
    wire fl_val_2 = line_valid[{fl_set, 2'd2}];
    wire fl_val_3 = line_valid[{fl_set, 2'd3}];

    wire fl_pin_0 = line_pinned[{fl_set, 2'd0}];
    wire fl_pin_1 = line_pinned[{fl_set, 2'd1}];
    wire fl_pin_2 = line_pinned[{fl_set, 2'd2}];
    wire fl_pin_3 = line_pinned[{fl_set, 2'd3}];

    wire [2:0] fl_cur_plru = set_plru[fl_set];
    wire fl_b0 = fl_cur_plru[2];
    wire fl_b1 = fl_cur_plru[1];
    wire fl_b2 = fl_cur_plru[0];
    wire [1:0] fl_plru_cand = fl_b0 ? (fl_b2 ? 2'd3 : 2'd2) : (fl_b1 ? 2'd1 : 2'd0);
    wire fl_cand_pinned = (fl_plru_cand == 2'd0) ? fl_pin_0 :
                         ((fl_plru_cand == 2'd1) ? fl_pin_1 :
                         ((fl_plru_cand == 2'd2) ? fl_pin_2 : fl_pin_3));

    wire [1:0] fl_first_unpinned = !fl_pin_0 ? 2'd0 : (!fl_pin_1 ? 2'd1 : (!fl_pin_2 ? 2'd2 : 2'd3));

    assign o_fill_way = (!fl_val_0 && !fl_pin_0) ? 2'd0 :
                       ((!fl_val_1 && !fl_pin_1) ? 2'd1 :
                       ((!fl_val_2 && !fl_pin_2) ? 2'd2 :
                       ((!fl_val_3 && !fl_pin_3) ? 2'd3 :
                       (!fl_cand_pinned ? fl_plru_cand : fl_first_unpinned))));

    wire [5:0] fl_victim_entry = {fl_set, o_fill_way};
    assign o_evict_valid = i_fill_valid && line_valid[fl_victim_entry];
    assign o_evict_dirty = line_dirty[fl_victim_entry];
    assign o_evict_addr  = {line_tag[fl_victim_entry], fl_set, 6'd0};
    assign o_evict_data  = rd_data_mux;

    // -------------------------------------------------------------------------
    // Logic Update tổ hợp: so sánh tag theo từng set trước khi mux hit
    // -------------------------------------------------------------------------
    logic [SET_BITS-1:0]  up_set;
    logic [TAG_WIDTH-1:0] up_tag;
    assign up_set = i_update_addr[6 +: SET_BITS];
    assign up_tag = i_update_addr[6 + SET_BITS +: TAG_WIDTH];

    (* keep = "true" *) logic [MC_WAYS-1:0] up_match [0:MC_SETS-1];
    always_comb begin
        for (int s = 0; s < MC_SETS; s++) begin
            for (int w = 0; w < MC_WAYS; w++) begin
                up_match[s][w] = line_valid[s*MC_WAYS + w] && (line_tag[s*MC_WAYS + w] == up_tag);
            end
        end
    end

    wire up_hit_0 = up_match[up_set][0];
    wire up_hit_1 = up_match[up_set][1];
    wire up_hit_2 = up_match[up_set][2];
    wire up_hit_3 = up_match[up_set][3];

    assign o_update_hit = up_hit_0 | up_hit_1 | up_hit_2 | up_hit_3;
    assign o_update_way = {!up_hit_0 && !up_hit_1 && (up_hit_2 || up_hit_3),
                           !up_hit_0 && (up_hit_1 || (!up_hit_2 && up_hit_3))};
    wire [5:0] up_entry = {up_set, o_update_way};

    // -------------------------------------------------------------------------
    // Logic Unpin tổ hợp
    // -------------------------------------------------------------------------
    logic [SET_BITS-1:0]  un_set;
    logic [TAG_WIDTH-1:0] un_tag;
    assign un_set = i_unpin_addr[6 +: SET_BITS];
    assign un_tag = i_unpin_addr[6 + SET_BITS +: TAG_WIDTH];

    wire un_hit_0 = line_valid[{un_set, 2'd0}] && (line_tag[{un_set, 2'd0}] == un_tag);
    wire un_hit_1 = line_valid[{un_set, 2'd1}] && (line_tag[{un_set, 2'd1}] == un_tag);
    wire un_hit_2 = line_valid[{un_set, 2'd2}] && (line_tag[{un_set, 2'd2}] == un_tag);
    wire un_hit_3 = line_valid[{un_set, 2'd3}] && (line_tag[{un_set, 2'd3}] == un_tag);

    assign o_unpin_hit = un_hit_0 | un_hit_1 | un_hit_2 | un_hit_3;
    assign o_unpin_way = un_hit_0 ? 2'd0 : (un_hit_1 ? 2'd1 : (un_hit_2 ? 2'd2 : 2'd3));
    wire [5:0] un_entry = {un_set, o_unpin_way};

    // -------------------------------------------------------------------------
    // Cập nhật trạng thái tuần tự (Sequential Update)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_hit_cnt           <= 32'd0;
            reg_miss_cnt          <= 32'd0;
            reg_evict_cnt         <= 32'd0;
            reg_wb_cnt            <= 32'd0;
            reg_pin_violation     <= 1'b0;
            flush_st              <= FLUSH_IDLE;
            flush_idx             <= 6'd0;
            flush_rd_wait         <= 1'b0;
            o_flush_busy          <= 1'b0;
            o_flush_done          <= 1'b0;
            o_flush_evict_valid   <= 1'b0;
            o_flush_evict_addr    <= '0;
            o_flush_evict_data    <= '0;

            for (int i = 0; i < NUM_LINES; i++) begin
                line_valid[i]    <= 1'b0;
                line_dirty[i]    <= 1'b0;
                line_verified[i] <= 1'b0;
                line_pinned[i]   <= 1'b0;
                line_tag[i]      <= '0;
            end
            for (int s = 0; s < MC_SETS; s++) begin
                set_plru[s] <= 3'd0;
            end
        end else begin
            o_flush_done        <= 1'b0;
            o_flush_evict_valid <= 1'b0;
            reg_pin_violation   <= 1'b0;

            // 1. Thực thi Flush nếu kích hoạt
            case (flush_st)
                FLUSH_IDLE: begin
                    flush_rd_wait <= 1'b0;
                    if (i_flush_start) begin
                        o_flush_busy <= 1'b1;
                        flush_idx    <= 6'd0;
                        flush_st     <= FLUSH_SCAN;
                    end
                end

                FLUSH_SCAN: begin
                    if (line_valid[flush_idx] && line_dirty[flush_idx]) begin
                        // 1-cycle synchronous BRAM read before issuing flush eviction payload
                        if (!flush_rd_wait) begin
                            flush_rd_wait <= 1'b1;
                        end else begin
                            flush_rd_wait       <= 1'b0;
                            o_flush_evict_valid <= 1'b1;
                            o_flush_evict_addr  <= {line_tag[flush_idx], flush_idx[5:2], 6'd0};
                            o_flush_evict_data  <= rd_data_mux;
                            flush_st            <= FLUSH_WAIT;
                        end
                    end else begin
                        flush_rd_wait <= 1'b0;
                        if (flush_idx == 6'd63) begin
                            flush_st <= FLUSH_DONE;
                        end else begin
                            flush_idx <= flush_idx + 1'b1;
                        end
                    end
                end

                FLUSH_WAIT: begin
                    if (i_flush_ready) begin
                        line_dirty[flush_idx] <= 1'b0;
                        reg_wb_cnt            <= reg_wb_cnt + 1'b1;
                        if (flush_idx == 6'd63) begin
                            flush_st <= FLUSH_DONE;
                        end else begin
                            flush_idx <= flush_idx + 1'b1;
                            flush_st  <= FLUSH_SCAN;
                        end
                    end
                end

                FLUSH_DONE: begin
                    o_flush_busy <= 1'b0;
                    o_flush_done <= 1'b1;
                    flush_st     <= FLUSH_IDLE;
                end
                default: flush_st <= FLUSH_IDLE;
            endcase

            // 2. Tra cứu (Lookup)
            if (i_lookup_valid) begin
                if (o_lookup_hit) begin
                    reg_hit_cnt         <= reg_hit_cnt + 1'b1;
                    set_plru[lk_set]    <= next_plru(set_plru[lk_set], o_lookup_way);
                    if (i_lookup_pin) begin
                        if (o_set_can_pin[lk_set]) begin
                            line_pinned[lk_entry] <= 1'b1;
                        end else begin
                            reg_pin_violation <= 1'b1;
                        end
                    end
                end else begin
                    reg_miss_cnt <= reg_miss_cnt + 1'b1;
                end
            end

            // 3. Nạp dòng (Fill)
            if (i_fill_valid) begin
                if (line_valid[fl_victim_entry]) begin
                    reg_evict_cnt <= reg_evict_cnt + 1'b1;
                    if (line_dirty[fl_victim_entry]) begin
                        reg_wb_cnt <= reg_wb_cnt + 1'b1;
                    end
                end

                line_valid[fl_victim_entry]    <= 1'b1;
                line_dirty[fl_victim_entry]    <= 1'b0;
                line_verified[fl_victim_entry] <= i_fill_verified;
                line_tag[fl_victim_entry]      <= fl_tag;
                set_plru[fl_set]               <= next_plru(set_plru[fl_set], o_fill_way);

                if (i_fill_pin) begin
                    if (o_set_can_pin[fl_set]) begin
                        line_pinned[fl_victim_entry] <= 1'b1;
                    end else begin
                        line_pinned[fl_victim_entry] <= 1'b0;
                        reg_pin_violation            <= 1'b1;
                    end
                end else begin
                    line_pinned[fl_victim_entry] <= 1'b0;
                end
            end

            // 4. Cập nhật (Update)
            if (i_update_valid && o_update_hit) begin
                line_dirty[up_entry] <= i_update_dirty;
                set_plru[up_set] <= next_plru(set_plru[up_set], o_update_way);
            end

            // 5. Bỏ ghim (Unpin)
            if (i_unpin_valid && o_unpin_hit) begin
                line_pinned[un_entry] <= 1'b0;
            end
        end
    end

    // Registered 1-cycle write buffer + forward bypass breaks tag_compare->RAMB36E2/WEBWE path
    wire                  data_wr_en   = i_fill_valid || (i_update_valid && o_update_hit && i_update_data_en);
    wire [5:0]            data_wr_addr = i_fill_valid ? fl_victim_entry : up_entry;
    wire [DATA_WIDTH-1:0] data_wr_data = i_fill_valid ? i_fill_data     : i_update_data;
    wire [5:0]            data_rd_addr = (flush_st == FLUSH_SCAN) ? flush_idx :
                                         (i_fill_valid ? fl_victim_entry : lk_entry);

    logic                  bram_wr_en_q;
    logic [5:0]            bram_wr_addr_q;
    logic [DATA_WIDTH-1:0] bram_wr_data_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bram_wr_en_q      <= 1'b0;
            bram_wr_addr_q    <= 6'd0;
            rd_bypass_valid_q <= 1'b0;
        end else begin
            bram_wr_en_q      <= data_wr_en;
            bram_wr_addr_q    <= data_wr_addr;
            rd_bypass_valid_q <= bram_wr_en_q && (data_rd_addr == bram_wr_addr_q);
        end
    end

    // Unconditional payload registers qualified by bram_wr_en_q / rd_bypass_valid_q eliminate 512-bit CE fanout and Synth 8-7137
    always_ff @(posedge clk) begin
        bram_wr_data_q   <= data_wr_data;
        rd_bypass_data_q <= bram_wr_data_q;
        if (bram_wr_en_q) begin
            line_data[bram_wr_addr_q] <= bram_wr_data_q;
        end
        ram_rd_data <= line_data[data_rd_addr];
    end

    // Gán đầu ra bộ đếm CSR
    assign o_hit_cnt        = reg_hit_cnt;
    assign o_miss_cnt       = reg_miss_cnt;
    assign o_evict_cnt      = reg_evict_cnt;
    assign o_wb_cnt         = reg_wb_cnt;
    assign o_pin_violation  = reg_pin_violation;

`ifdef FORMAL
    // Bất biến phần cứng: không bao giờ ghim hết tất cả way trong một set
    always_comb begin
        for (int s = 0; s < MC_SETS; s++) begin
            assert (set_pinned_cnt[s] < MC_WAYS);
        end
    end
`endif

endmodule
