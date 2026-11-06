// File:      rd_issue_queue.sv
// Chức năng: Hàng đợi phát lệnh đọc trước bộ ánh xạ: chọn lệnh theo QoS/tuổi trong số lệnh có tín dụng bank group, giữ thứ tự cùng ID và chặn RAW theo từng mục.
`timescale 1ns / 1ps

module rd_issue_queue #(
    parameter int AXI_ID_WIDTH   = 4,
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_QOS_WIDTH  = 4,
    parameter int BG_WIDTH       = 3,
    parameter int BANK_WIDTH     = 2,
    parameter int DEPTH          = 8,
    parameter int WR_TRACK       = 8,
    // Lệnh có QoS >= QOS_RSV được dùng các entry ROB dự trữ
    parameter int QOS_RSV        = 4,
    // Số mục chỉ dành cho lệnh QoS >= QOS_RSV: lệnh QoS cao luôn vào được hàng đợi để vượt lệnh QoS thấp đang chờ
    parameter int IQ_RSV         = 2
) (
    input  logic                              clk,
    input  logic                              rst_n,

    input  logic                              cfg_bank_coloring_en,
    input  logic [1:0]                        cfg_mapping_mode,
    input  logic                              cfg_is_ddr5,

    // Đoạn lệnh đọc từ bộ tách burst (thứ tự AR)
    input  logic                              i_valid,
    output logic                              o_ready,
    input  logic [AXI_ID_WIDTH-1:0]           i_id,
    input  logic [AXI_ADDR_WIDTH-1:0]         i_addr,
    input  logic [7:0]                        i_len,
    input  logic [AXI_QOS_WIDTH-1:0]          i_qos,
    input  logic                              i_last,

    // Lệnh được chọn (o_valid chỉ phụ thuộc thanh ghi và các cờ chặn; i_ready = mapper nhận + ROB còn slot)
    output logic                              o_valid,
    input  logic                              i_ready,
    output logic [AXI_ID_WIDTH-1:0]           o_id,
    output logic [AXI_ADDR_WIDTH-1:0]         o_addr,
    output logic [7:0]                        o_len,
    output logic [AXI_QOS_WIDTH-1:0]          o_qos,
    output logic                              o_last,
    output logic [BG_WIDTH-1:0]               o_bg,
    output logic [BANK_WIDTH-1:0]             o_bank,
    // Một mục vừa được chọn vào thanh ghi đầu ra: tín dụng bank được trừ ngay lúc này
    output logic                              o_sel_fire,
    output logic [BG_WIDTH-1:0]               o_sel_bg,
    output logic [BANK_WIDTH-1:0]             o_sel_bank,
    output logic [(1<<BG_WIDTH)-1:0]          o_bg_pend,
    output logic                              o_empty,

    // Tín dụng theo bank ({bg, bank}): 1 = hàng đợi QoS của BG còn chỗ cho thêm một lệnh tới bank này
    input  logic [(1<<(BG_WIDTH+BANK_WIDTH))-1:0] i_bank_credit,
    // BG vừa nhận một lệnh đọc ở chu kỳ trước (tín dụng của nó chưa phản ánh lệnh đó): không chọn thêm vào BG này
    input  logic                              i_bg_hold_valid = 1'b0,
    input  logic [BG_WIDTH-1:0]               i_bg_hold = '0,
    // ROB còn entry cho lệnh QoS thấp (ngoài phần dự trữ) / cho lệnh QoS cao
    input  logic                              i_rob_lo_ok = 1'b1,
    input  logic                              i_rob_hi_ok = 1'b1,

    // Chặn RAW: lệnh ghi đang gom (stage), AW ở đầu frontend, AW trong FIFO wdata_buffer, AW còn tồn đọng
    input  logic                              i_wstage_busy,
    input  logic [AXI_ADDR_WIDTH-1:0]         i_wstage_addr,
    input  logic                              i_fe_aw_valid,
    input  logic [AXI_ADDR_WIDTH-1:0]         i_fe_aw_addr,
    input  logic [WR_TRACK-1:0]               i_wr_active_valid,
    input  logic [WR_TRACK*AXI_ADDR_WIDTH-1:0] i_wr_active_addr,
    input  logic                              i_aw_backlog
);

    // Cơ chế: frontend nhận AR theo thứ tự nhưng các lệnh khác ID không có ràng buộc thứ tự (AXI4). Trước đây
    // lệnh đầu hàng tới một BG đang đầy làm nghẽn cả pipeline ánh xạ -> SDC -> hàng đợi, nên lệnh QoS cao tới BG
    // rảnh phải chờ (R20). Ở đây lệnh chỉ được phát khi BG đích còn tín dụng (pipeline phía sau không bao giờ
    // dừng vì hàng đợi đầy), và lệnh khác ID được vượt lệnh đang chờ tín dụng.
    localparam int LW  = AXI_ADDR_WIDTH - 6;           // địa chỉ dòng 64B
    localparam int IW  = $clog2(DEPTH);

    logic [DEPTH-1:0]          v;
    logic [AXI_ID_WIDTH-1:0]   e_id   [DEPTH];
    logic [AXI_ADDR_WIDTH-1:0] e_addr [DEPTH];
    logic [7:0]                e_len  [DEPTH];
    logic [AXI_QOS_WIDTH-1:0]  e_qos  [DEPTH];
    logic                      e_last [DEPTH];
    logic [BG_WIDTH-1:0]       e_bg   [DEPTH];
    logic [BANK_WIDTH-1:0]     e_bank [DEPTH];
    // older[i][j] = 1: mục j vào trước mục i và còn hợp lệ (ma trận tuổi, cập nhật lúc nạp)
    logic [DEPTH-1:0]          older  [DEPTH];

    wire [BG_WIDTH-1:0]   in_bg;
    wire [BANK_WIDTH-1:0] in_bank;
    domain_bank_coloring #(
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .BG_WIDTH       (BG_WIDTH),
        .BANK_WIDTH     (BANK_WIDTH)
    ) u_bg (
        .cfg_bank_coloring_en (cfg_bank_coloring_en),
        .cfg_mapping_mode     (cfg_mapping_mode),
        .cfg_is_ddr5          (cfg_is_ddr5),
        .i_req_id             (i_id),
        .i_req_addr           (i_addr),
        .o_bg                 (in_bg),
        .o_bank               (in_bank)
    );

    wire push;
    // Mục trống chỉ số thấp nhất
    logic [IW-1:0] free_idx;
    always_comb begin
        free_idx = '0;
        for (int i = DEPTH - 1; i >= 0; i--) if (!v[i]) free_idx = IW'(i);
    end
    // Mục đang giữ lệnh QoS thấp
    logic [IW:0] lo_cnt;
    always_comb begin
        lo_cnt = '0;
        for (int i = 0; i < DEPTH; i++)
            if (v[i] && e_qos[i] < AXI_QOS_WIDTH'(QOS_RSV)) lo_cnt = lo_cnt + 1'b1;
    end
    // READY phụ thuộc QoS của đoạn đang được đưa vào (AXI cho phép READY phụ thuộc VALID/payload)
    assign o_ready = !(&v) && ((i_qos >= AXI_QOS_WIDTH'(QOS_RSV)) || (lo_cnt < (IW+1)'(DEPTH - IQ_RSV)));
    assign push    = i_valid && o_ready;

    // Cờ RAW của từng mục được tính lại mỗi chu kỳ vào thanh ghi (tách CAM 10 địa chỉ ghi khỏi bộ chọn). Một lệnh ghi
    // chỉ cần chặn đọc khi AW của nó tới trước AR của lệnh đọc; khi đó nó đã nằm trong frontend/bộ tách/wdata_buffer
    // từ trước khi lệnh đọc vào hàng đợi này (AR qua skid + bộ tách >= 2 chu kỳ), nên bản trễ một chu kỳ luôn thấy nó.
    // Mục vừa nạp chưa có cờ RAW hợp lệ nên chưa được chọn ở chu kỳ đầu.
    logic [DEPTH-1:0] raw_q, fresh_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            raw_q   <= '0;
            fresh_q <= '0;
        end else begin
            for (int i = 0; i < DEPTH; i++) begin
                logic raw;
                raw = (i_wstage_busy && e_addr[i][AXI_ADDR_WIDTH-1:6] == i_wstage_addr[AXI_ADDR_WIDTH-1:6]) ||
                      (i_fe_aw_valid && e_addr[i][AXI_ADDR_WIDTH-1:6] == i_fe_aw_addr[AXI_ADDR_WIDTH-1:6]) || i_aw_backlog;
                for (int k = 0; k < WR_TRACK; k++)
                    if (i_wr_active_valid[k] && i_wr_active_addr[k*AXI_ADDR_WIDTH + 6 +: LW] == e_addr[i][AXI_ADDR_WIDTH-1:6])
                        raw = 1'b1;
                raw_q[i]   <= raw;
                fresh_q[i] <= v[i] && !(push && free_idx == IW'(i));
            end
        end
    end

    // Điều kiện phát của từng mục
    logic [DEPTH-1:0] elig, pick;
    always_comb begin
        for (int i = 0; i < DEPTH; i++) begin
            logic raw, same_id_older;
            raw = raw_q[i] || !fresh_q[i];
            same_id_older = 1'b0;
            for (int j = 0; j < DEPTH; j++)
                if (older[i][j] && e_id[j] == e_id[i]) same_id_older = 1'b1;
            elig[i] = v[i] && i_bank_credit[{e_bg[i], e_bank[i]}] && !(i_bg_hold_valid && e_bg[i] == i_bg_hold) && !raw && !same_id_older &&
                      ((e_qos[i] >= AXI_QOS_WIDTH'(QOS_RSV)) ? i_rob_hi_ok : i_rob_lo_ok);
        end
        // QoS cao thắng; cùng QoS thì mục cũ hơn thắng
        for (int i = 0; i < DEPTH; i++) begin
            pick[i] = elig[i];
            for (int j = 0; j < DEPTH; j++)
                if (j != i && elig[j] && (e_qos[j] > e_qos[i] || (e_qos[j] == e_qos[i] && older[i][j])))
                    pick[i] = 1'b0;
        end
    end

    logic [AXI_ID_WIDTH-1:0]   s_id;
    logic [AXI_ADDR_WIDTH-1:0] s_addr;
    logic [7:0]                s_len;
    logic [AXI_QOS_WIDTH-1:0]  s_qos;
    logic                      s_last;
    logic [BG_WIDTH-1:0]       s_bg;
    logic [BANK_WIDTH-1:0]     s_bank;
    always_comb begin
        s_id = '0; s_addr = '0; s_len = '0; s_qos = '0; s_last = 1'b0; s_bg = '0; s_bank = '0;
        for (int i = 0; i < DEPTH; i++)
            if (pick[i]) begin
                s_id   = s_id   | e_id[i];
                s_addr = s_addr | e_addr[i];
                s_len  = s_len  | e_len[i];
                s_qos  = s_qos  | e_qos[i];
                s_last = s_last | e_last[i];
                s_bg   = s_bg   | e_bg[i];
                s_bank = s_bank | e_bank[i];
            end
    end

    // Thanh ghi đầu ra: tách bộ chọn (RAW/tín dụng/QoS) khỏi đường cấp phát ROB -> bộ ánh xạ. Mục được chọn rời
    // hàng đợi ngay khi vào thanh ghi; lệnh ghi đến sau thời điểm chọn trẻ hơn lệnh đọc nên không cần chặn RAW lại.
    wire pop  = (|pick) && (!o_valid || i_ready);
    assign o_sel_fire = pop;
    assign o_sel_bg   = s_bg;
    assign o_sel_bank = s_bank;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)              o_valid <= 1'b0;
        else if (pop)            o_valid <= 1'b1;
        else if (i_ready)        o_valid <= 1'b0;
    end
    always_ff @(posedge clk)
        if (pop) begin
            o_id   <= s_id;
            o_addr <= s_addr;
            o_len  <= s_len;
            o_qos  <= s_qos;
            o_last <= s_last;
            o_bg   <= s_bg;
            o_bank <= s_bank;
        end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v <= '0;
            for (int i = 0; i < DEPTH; i++) older[i] <= '0;
        end else begin
            for (int i = 0; i < DEPTH; i++)
                if (pop && pick[i]) v[i] <= 1'b0;
            // Mục rời hàng không còn là "cũ hơn" của ai
            for (int i = 0; i < DEPTH; i++)
                for (int j = 0; j < DEPTH; j++)
                    if (pop && pick[j]) older[i][j] <= 1'b0;
            if (push) begin
                v[free_idx]     <= 1'b1;
                older[free_idx] <= v & ~((pop) ? pick : '0);
            end
        end
    end
    always_ff @(posedge clk)
        if (push) begin
            e_id[free_idx]   <= i_id;
            e_addr[free_idx] <= i_addr;
            e_len[free_idx]  <= i_len;
            e_qos[free_idx]  <= i_qos;
            e_last[free_idx] <= i_last;
            e_bg[free_idx]   <= in_bg;
            e_bank[free_idx] <= in_bank;
        end

    // o_bg_pend: BG có mục đọc trong hàng đợi ở chu kỳ trước (mục chỉ được chọn từ chu kỳ thứ hai sau khi nạp nên
    // cờ đăng ký luôn phủ mục được chọn); khối đỉnh dùng để chọn tín dụng ghi có chừa chỗ cho đọc đồng thời
    assign o_empty = (v == '0);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_bg_pend <= '0;
        end else begin
            for (int g = 0; g < (1<<BG_WIDTH); g++) begin
                logic pend_g;
                pend_g = 1'b0;
                for (int i = 0; i < DEPTH; i++)
                    if (v[i] && (e_bg[i] == BG_WIDTH'(g))) pend_g = 1'b1;
                o_bg_pend[g] <= pend_g;
            end
        end
    end

`ifdef FORMAL
    // Lệnh cùng ID ra theo đúng thứ tự vào; mỗi chu kỳ chọn tối đa một mục
    always_comb begin
        if (rst_n) begin
            assert ($onehot0(pick));
            for (int i = 0; i < DEPTH; i++)
                for (int j = 0; j < DEPTH; j++)
                    if (pick[i] && v[j] && older[i][j]) assert (e_id[j] != e_id[i]);
        end
    end
`endif

endmodule
