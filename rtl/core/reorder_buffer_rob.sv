//=============================================================================
// File:        reorder_buffer_rob.sv
// Chức năng:   ROB theo dõi giao dịch đọc phi tuần tự, khóa nguy cơ RAW và hoàn tất in-order theo từng AXI ID.
//=============================================================================
`timescale 1ns / 1ps

module reorder_buffer_rob #(
    parameter int AXI_ID_WIDTH    = 4,
    parameter int AXI_DATA_WIDTH  = 64,
    parameter int AXI_ADDR_WIDTH  = 32,
    parameter int AXI_LEN_WIDTH   = 8,
    parameter int ROB_DEPTH       = 32,
    parameter int ROB_PTR_WIDTH   = $clog2(ROB_DEPTH),
    parameter int MAX_BURST_BEATS = 8,
    parameter int BURST_IDX_WIDTH = $clog2(MAX_BURST_BEATS),
    parameter int MAX_WR_TRACK    = 8
)(
    input  logic                                  clk,
    input  logic                                  rst_n,

    //-------------------------------------------------------------------------
    // Allocation Interface (from Dispatch / Frontend)
    //-------------------------------------------------------------------------
    input  logic                                  i_alloc_valid,
    input  logic [AXI_ID_WIDTH-1:0]               i_alloc_id,
    input  logic [AXI_ADDR_WIDTH-1:0]             i_alloc_addr,
    input  logic [AXI_LEN_WIDTH-1:0]              i_alloc_len,
    // Đoạn cuối của burst AXI (bộ tách burst chia burst dài thành nhiều entry): chỉ đoạn cuối mang RLAST
    input  logic                                  i_alloc_last = 1'b1,
    output logic                                  o_alloc_ready,
    output logic [ROB_PTR_WIDTH-1:0]              o_alloc_tag,

    //-------------------------------------------------------------------------
    // RAW Hazard Detection Interface
    //-------------------------------------------------------------------------
    input  logic [MAX_WR_TRACK-1:0]               i_wr_active_valid,
    input  logic [MAX_WR_TRACK*AXI_ADDR_WIDTH-1:0]i_wr_active_addr,
    output logic                                  o_raw_hazard,
    output logic [MAX_WR_TRACK-1:0]               o_raw_match_mask,

    //-------------------------------------------------------------------------
    // DRAM Read Data Writeback Interface (from DDR5 Data Return Engine)
    //-------------------------------------------------------------------------
    input  logic                                  i_wb_valid,
    input  logic [ROB_PTR_WIDTH-1:0]              i_wb_tag,
    input  logic [AXI_DATA_WIDTH-1:0]             i_wb_data,
    input  logic [1:0]                            i_wb_resp,
    input  logic                                  i_wb_last,

    //-------------------------------------------------------------------------
    // AXI4 R-Channel Interface (Out to AXI Master)
    //-------------------------------------------------------------------------
    output logic                                  o_rvalid,
    output logic [AXI_ID_WIDTH-1:0]               o_rid,
    output logic [AXI_DATA_WIDTH-1:0]             o_rdata,
    output logic [1:0]                            o_rresp,
    output logic                                  o_rlast,
    input  logic                                  i_rready,

    //-------------------------------------------------------------------------
    // Buffer Status Telemetry
    //-------------------------------------------------------------------------
    output logic                                  o_rob_empty,
    output logic                                  o_rob_full,
    output logic [ROB_PTR_WIDTH:0]                o_rob_count
);

    //=========================================================================
    // Internal Data Structures
    //=========================================================================
    // Metadata per entry
    logic [ROB_DEPTH-1:0]                      entry_valid;
    logic [ROB_DEPTH-1:0]                      entry_final;
    logic [ROB_DEPTH-1:0][AXI_ID_WIDTH-1:0]    entry_id;
    logic [ROB_DEPTH-1:0][BURST_IDX_WIDTH:0]   entry_len;      // truncated to max burst beats
    logic [ROB_DEPTH-1:0][BURST_IDX_WIDTH:0]   entry_wb_count; // counts received beats (0..MAX_BURST_BEATS)
    logic [ROB_DEPTH-1:0]                      entry_wb_done;

    // Payload storage (ROB_DEPTH entries x MAX_BURST_BEATS data words)
    logic [AXI_DATA_WIDTH-1:0] payload_data [ROB_DEPTH][MAX_BURST_BEATS];
    logic [1:0]                payload_resp [ROB_DEPTH][MAX_BURST_BEATS];

    // Ma trận tuổi phẳng: older[j*ROB_DEPTH+e] = 1 khi entry j được cấp trước entry e (chỉ có nghĩa khi cả hai còn valid).
    // AXI4 chỉ buộc thứ tự trong cùng ID; một con trỏ retire toàn cục bắt mọi ID chờ entry cũ nhất (chặn đầu hàng R18).
    logic [ROB_DEPTH*ROB_DEPTH-1:0] older;
    // id_blk[e*ROB_DEPTH+j] = 1: entry e chờ entry j cùng AXI ID cũ hơn. Tính lúc cấp phát (16 phép so sánh ID)
    // thay vì so sánh 16x16 cặp ID mỗi chu kỳ trên đường chọn entry (không đạt 400 MHz).
    logic [ROB_DEPTH*ROB_DEPTH-1:0] id_blk;

    logic [ROB_PTR_WIDTH-1:0]  alloc_ptr;
    logic [ROB_PTR_WIDTH-1:0]  retire_ptr;
    logic                      sel_valid;
    // Độ dài và số beat đã về của entry được chọn, chốt lúc chọn: bỏ mux ROB_DEPTH:1 khỏi chuỗi điều khiển retire
    logic [BURST_IDX_WIDTH:0]  sel_len;
    logic [BURST_IDX_WIDTH:0]  sel_wbcnt;
    logic [BURST_IDX_WIDTH:0]  retire_beat;
    logic [ROB_PTR_WIDTH:0]    occupancy_count;

    assign o_rob_empty   = (occupancy_count == '0);
    assign o_rob_full    = (occupancy_count >= ROB_DEPTH[ROB_PTR_WIDTH:0]);
    assign o_rob_count   = occupancy_count;
    assign o_alloc_ready = !o_rob_full && !o_raw_hazard;
    assign o_alloc_tag   = alloc_ptr;

    // Retire không theo vòng nên slot trống nằm rải rác: cấp slot trống có chỉ số thấp nhất.
    always_comb begin
        alloc_ptr = '0;
        for (int i = ROB_DEPTH - 1; i >= 0; i--)
            if (!entry_valid[i]) alloc_ptr = ROB_PTR_WIDTH'(i);
    end

    //=========================================================================
    // RAW Hazard Detection Logic (Combinational)
    // Checks incoming Read address against all active in-flight writes
    // (64-byte Cacheline granularity: addr[AXI_ADDR_WIDTH-1:6])
    //=========================================================================
    logic [MAX_WR_TRACK-1:0] raw_match_comb;
    always_comb begin
        raw_match_comb = '0;
        for (int k = 0; k < MAX_WR_TRACK; k++) begin
            if (i_wr_active_valid[k]) begin
                // Compare cacheline tag (bits [AXI_ADDR_WIDTH-1 : 6])
                if (i_wr_active_addr[k*AXI_ADDR_WIDTH + 6 +: (AXI_ADDR_WIDTH-6)] == i_alloc_addr[AXI_ADDR_WIDTH-1:6]) begin
                    raw_match_comb[k] = 1'b1;
                end
            end
        end
    end

    assign o_raw_match_mask = raw_match_comb;
    assign o_raw_hazard     = |raw_match_comb;

    //=========================================================================
    // Slot Allocation Process
    //=========================================================================
    wire alloc_fire = i_alloc_valid && o_alloc_ready && !o_raw_hazard;

    // Truncate i_alloc_len safely to maximum supported burst beats
    wire [BURST_IDX_WIDTH:0] clamped_alloc_len =
        (i_alloc_len >= AXI_LEN_WIDTH'(MAX_BURST_BEATS)) ?
        (BURST_IDX_WIDTH + 1)'(MAX_BURST_BEATS - 1) :
        i_alloc_len[BURST_IDX_WIDTH:0];

    //=========================================================================
    // Internal Read Retirement Signals (Pre-Skid Buffer)
    //=========================================================================
    logic                      core_rvalid;
    logic [AXI_ID_WIDTH-1:0]   core_rid;
    logic [AXI_DATA_WIDTH-1:0] core_rdata;
    logic [1:0]                core_rresp;
    logic                      core_rlast;
    logic                      core_rready;

    // retire_ptr là thanh ghi: mux payload không nằm sau logic chọn entry. Beat chỉ phát khi DRAM đã trả về nó.
    wire retire_entry_has_beat = sel_valid && (retire_beat < sel_wbcnt);

    wire [BURST_IDX_WIDTH-1:0] retire_beat_idx = retire_beat[BURST_IDX_WIDTH-1:0];

    assign core_rvalid = retire_entry_has_beat;
    assign core_rid    = entry_id[retire_ptr];
    assign core_rdata  = payload_data[retire_ptr][retire_beat_idx];
    assign core_rresp  = payload_resp[retire_ptr][retire_beat_idx];
    assign core_rlast  = (retire_beat == sel_len);

    wire retire_beat_fire  = core_rvalid && core_rready;
    wire retire_entry_done = retire_beat_fire && core_rlast;
    wire [BURST_IDX_WIDTH:0] tag_wb_cnt = entry_wb_count[i_wb_tag];
    wire [BURST_IDX_WIDTH-1:0] wb_beat_idx = tag_wb_cnt[BURST_IDX_WIDTH-1:0];

    //=========================================================================
    // Chọn entry cho chu kỳ kế tiếp từ trạng thái KẾ TIẾP (sau retire/writeback của chu kỳ này), rồi thanh ghi hóa.
    // Kết quả trùng khớp chu kỳ với việc chọn tổ hợp trên trạng thái hiện tại, nhưng cắt đường dài khỏi kênh R.
    // Entry đủ điều kiện: còn valid, đã có beat đầu, không còn entry cùng ID cũ hơn; chọn entry cũ nhất (không starvation).
    //=========================================================================
    // Hai phương án tính song song: k=0 entry đang chọn không retire, k=1 nó retire chu kỳ này. Mặt nạ k=1 chỉ phụ thuộc
    // retire_ptr đã đăng ký, nên retire_entry_done (sau so sánh beat/handshake) chỉ còn chọn kết quả ở mux 2:1 cuối.
    logic [ROB_DEPTH-1:0]     retiring;
    logic [ROB_DEPTH-1:0]     sel_onehot;
    logic [ROB_DEPTH-1:0]     wb_nz_n;
    logic [ROB_DEPTH-1:0]     elig_n   [2];
    logic [ROB_DEPTH-1:0]     pick_k   [2];
    logic [ROB_PTR_WIDTH-1:0] idx_k    [2];
    logic [BURST_IDX_WIDTH:0] len_k    [2];
    logic [BURST_IDX_WIDTH:0] wbcnt_k  [2];
    logic [ROB_DEPTH-1:0]     pick_n;
    logic [ROB_PTR_WIDTH-1:0] pick_idx_n;
    logic [BURST_IDX_WIDTH:0] pick_len_n;
    logic [BURST_IDX_WIDTH:0] pick_wbcnt_n;
    always_comb begin
        sel_onehot = '0;
        if (sel_valid) sel_onehot[retire_ptr] = 1'b1;
        retiring = retire_entry_done ? sel_onehot : '0;
        for (int e = 0; e < ROB_DEPTH; e++)
            wb_nz_n[e] = (entry_wb_count[e] != '0) || (i_wb_valid && i_wb_tag == ROB_PTR_WIDTH'(e));
        for (int k = 0; k < 2; k++) begin
            logic [ROB_DEPTH-1:0] gone;
            gone = (k == 1) ? sel_onehot : '0;
            for (int e = 0; e < ROB_DEPTH; e++)
                elig_n[k][e] = entry_valid[e] && !gone[e] && wb_nz_n[e] &&
                               ((id_blk[e*ROB_DEPTH +: ROB_DEPTH] & ~gone) == '0);
            for (int e = 0; e < ROB_DEPTH; e++) begin
                pick_k[k][e] = elig_n[k][e];
                for (int j = 0; j < ROB_DEPTH; j++)
                    if (j != e && elig_n[k][j] && older[j*ROB_DEPTH+e]) pick_k[k][e] = 1'b0;
            end
            idx_k[k]   = '0;
            len_k[k]   = '0;
            wbcnt_k[k] = '0;
            for (int e = 0; e < ROB_DEPTH; e++)
                if (pick_k[k][e]) begin
                    idx_k[k]   = idx_k[k] | ROB_PTR_WIDTH'(e);
                    len_k[k]   = len_k[k] | entry_len[e];
                    wbcnt_k[k] = wbcnt_k[k] | (entry_wb_count[e] +
                                 ((i_wb_valid && i_wb_tag == ROB_PTR_WIDTH'(e)) ? 1'b1 : 1'b0));
                end
        end
        pick_n       = retire_entry_done ? pick_k[1]  : pick_k[0];
        pick_idx_n   = retire_entry_done ? idx_k[1]   : idx_k[0];
        pick_len_n   = retire_entry_done ? len_k[1]   : len_k[0];
        pick_wbcnt_n = retire_entry_done ? wbcnt_k[1] : wbcnt_k[0];
    end

    // Không xen kẽ beat giữa các burst: giữ entry đang phát cho tới RLAST.
    wire mid_burst_n = retire_beat_fire ? !core_rlast : (retire_beat != '0);

    //=========================================================================
    // Sequential State Update
    //=========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            retire_ptr       <= '0;
            sel_valid        <= 1'b0;
            sel_len          <= '0;
            sel_wbcnt        <= '0;
            retire_beat      <= '0;
            older            <= '0;
            id_blk           <= '0;
            occupancy_count  <= '0;
            entry_valid      <= '0;
            entry_wb_done    <= '0;
            entry_final      <= '0;
            for (int i = 0; i < ROB_DEPTH; i++) begin
                entry_id[i]       <= '0;
                entry_len[i]      <= '0;
                entry_wb_count[i] <= '0;
            end
        end else begin
            // 1. Allocation
            if (alloc_fire) begin
                entry_valid[alloc_ptr]      <= 1'b1;
                entry_final[alloc_ptr]      <= i_alloc_last;
                entry_id[alloc_ptr]         <= i_alloc_id;
                entry_len[alloc_ptr]        <= clamped_alloc_len;
                entry_wb_count[alloc_ptr]   <= '0;
                entry_wb_done[alloc_ptr]    <= 1'b0;
                // Cột alloc_ptr: mọi entry đang valid đều cũ hơn entry mới; hàng alloc_ptr xóa về 0.
                for (int j = 0; j < ROB_DEPTH; j++) begin
                    older[j*ROB_DEPTH + alloc_ptr] <= entry_valid[j];
                    older[alloc_ptr*ROB_DEPTH + j] <= 1'b0;
                end
            end

            // Entry vừa retire không còn chặn ai; xóa trước để slot của nó tái sử dụng an toàn.
            for (int e = 0; e < ROB_DEPTH; e++)
                for (int j = 0; j < ROB_DEPTH; j++)
                    if (retiring[j]) id_blk[e*ROB_DEPTH + j] <= 1'b0;
            if (alloc_fire) begin
                for (int j = 0; j < ROB_DEPTH; j++)
                    id_blk[alloc_ptr*ROB_DEPTH + j] <= entry_valid[j] && !retiring[j] && (entry_id[j] == i_alloc_id);
            end

            // 2. Writeback Reception from DRAM
            if (i_wb_valid && entry_valid[i_wb_tag]) begin
                entry_wb_count[i_wb_tag] <= entry_wb_count[i_wb_tag] + 1'b1;
                if (i_wb_last || (entry_wb_count[i_wb_tag] >= entry_len[i_wb_tag])) begin
                    entry_wb_done[i_wb_tag] <= 1'b1;
                end
            end

            // 3. Retirement from Head
            if (retire_beat_fire) begin
                if (core_rlast) begin
                    entry_valid[retire_ptr]   <= 1'b0;
                    entry_wb_done[retire_ptr] <= 1'b0;
                    retire_beat               <= '0;
                end else begin
                    retire_beat               <= retire_beat + 1'b1;
                end
            end
            if (!mid_burst_n) begin
                retire_ptr <= pick_idx_n;
                sel_valid  <= |pick_n;
                sel_len    <= pick_len_n;
                sel_wbcnt  <= pick_wbcnt_n;
            end else if (i_wb_valid && i_wb_tag == retire_ptr) begin
                sel_wbcnt  <= sel_wbcnt + 1'b1;
            end

            // 4. Track Occupancy
            case ({alloc_fire, retire_entry_done})
                2'b10: occupancy_count <= occupancy_count + 1'b1;
                2'b01: occupancy_count <= occupancy_count - 1'b1;
                default: occupancy_count <= occupancy_count;
            endcase
        end
    end

    // Tách mảng dữ liệu ROB sang khối tuần tự thuần đồng bộ để hỗ trợ suy luận LUTRAM và tránh xung đột Set/Reset
    always_ff @(posedge clk) begin
        if (i_wb_valid && entry_valid[i_wb_tag]) begin
            payload_data[i_wb_tag][wb_beat_idx] <= i_wb_data;
            payload_resp[i_wb_tag][wb_beat_idx] <= i_wb_resp;
        end
    end

    //=========================================================================
    // Zero-Bubble Forward-Registered Skid Buffer on AXI R-Channel
    // Canonical 2-register slice decoupling upstream and downstream handshakes.
    //=========================================================================
    localparam int R_PAYLOAD_W = AXI_ID_WIDTH + AXI_DATA_WIDTH + 2 + 1;

    wire [R_PAYLOAD_W-1:0] core_payload = {core_rid, core_rdata, core_rresp, core_rlast && entry_final[retire_ptr]};
    logic [R_PAYLOAD_W-1:0] out_payload;

    logic                   skid_valid;
    logic [R_PAYLOAD_W-1:0] skid_payload;
    logic                   reg_rvalid;

    assign core_rready = !skid_valid;
    assign o_rvalid    = reg_rvalid;
    assign {o_rid, o_rdata, o_rresp, o_rlast} = out_payload;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_rvalid   <= 1'b0;
            out_payload  <= '0;
            skid_valid   <= 1'b0;
            skid_payload <= '0;
        end else begin
            if (i_rready || !reg_rvalid) begin
                if (skid_valid) begin
                    reg_rvalid   <= 1'b1;
                    out_payload  <= skid_payload;
                    skid_valid   <= 1'b0;
                end else begin
                    reg_rvalid   <= core_rvalid;
                    out_payload  <= core_payload;
                end
            end else if (core_rvalid && core_rready) begin
                skid_valid   <= 1'b1;
                skid_payload <= core_payload;
            end
        end
    end

    // Unused bits sink for clean lint
    logic _unused_sink;
    assign _unused_sink = &{1'b0, i_alloc_addr[5:0], entry_wb_done, 1'b0};

    //=========================================================================
    // Formal & Assertions
    //=========================================================================
`ifdef SYSTEMVERILOG_ASSERTIONS
    // Check no allocation when full
    assert property (@(posedge clk) disable iff (!rst_n)
        (i_alloc_valid && o_rob_full) |-> !alloc_fire
    ) else $error("ROB: Allocation occurred while buffer was FULL!");

    // Check writeback tag validity
    assert property (@(posedge clk) disable iff (!rst_n)
        i_wb_valid |-> entry_valid[i_wb_tag]
    ) else $error("ROB: Received DRAM writeback for an invalid/unallocated tag!");
`endif


    //=========================================================================
    // Hardware Formal Verification (SymbiYosys / SVA)
    //=========================================================================
`ifdef FORMAL
    initial begin
        assume (!rst_n);
    end

    always_ff @(posedge clk) begin
        if ($past(!rst_n))
            assume (rst_n);
    end

    // Property 1: Reset state
    always_comb begin
        if (!rst_n) begin
            assert (alloc_ptr == '0);
            assert (retire_ptr == '0);
            assert (o_rob_count == '0);
            assert (o_rob_empty);
            assert (!o_rob_full);
            assert (!o_rvalid);
        end
    end

    // Property 2: Capacity Invariant
    always_comb begin
        if (rst_n) begin
            assert (o_rob_count <= ROB_DEPTH);
            assert (o_rob_full == (o_rob_count == ROB_DEPTH));
            assert (o_rob_empty == (o_rob_count == '0));
            assert (o_alloc_ready == !o_rob_full);
        end
    end

    // Property 3: In-Order Retirement Guard
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if (retire_entry_done) begin
                assert (entry_valid[retire_ptr]);
                assert (entry_wb_done[retire_ptr]);
            end
        end
    end

    // Property 3b: Beat đầu của một entry chỉ rời ROB khi không còn entry cùng AXI ID nào cũ hơn (thứ tự AXI4 theo ID)
    always_comb begin
        if (rst_n && retire_beat_fire && retire_beat == '0)
            assert (id_blk[retire_ptr*ROB_DEPTH +: ROB_DEPTH] == '0);
    end

    // Property 4: RAW Hazard Soundness
    always_comb begin
        if (rst_n) begin
            for (int k = 0; k < MAX_WR_TRACK; k++) begin
                if (i_wr_active_valid[k] &&
                    (i_wr_active_addr[k*AXI_ADDR_WIDTH + 6 +: (AXI_ADDR_WIDTH-6)] == i_alloc_addr[AXI_ADDR_WIDTH-1:6])) begin
                    assert (o_raw_hazard);
                end
            end
        end
    end
`endif

endmodule
