// File:      wr_data_store.sv
// Chức năng: Gom từng đoạn burst ghi (nằm trong một dòng 64B) vào một slot có tag, phát B sau đoạn cuối và cấp dữ liệu cho DFI khi lệnh WR được phát.
`timescale 1ns / 1ps

module wr_data_store #(
    parameter int AXI_ID_WIDTH   = 4,
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 64,
    parameter int AXI_QOS_WIDTH  = 4,
    parameter int SLOTS          = 16,
    parameter int MAX_BEATS      = 8,
    parameter int TAG_W          = $clog2(SLOTS),
    parameter int BEAT_W         = $clog2(MAX_BEATS)
) (
    input  logic                          clk,
    input  logic                          rst_n,

    // Đoạn lệnh ghi từ wdata_buffer (thứ tự AW, đã qua axi_burst_splitter): i_cmd_len <= MAX_BEATS-1,
    // i_cmd_last = đoạn cuối của burst AXI (chỉ đoạn này sinh phản hồi B)
    input  logic                          i_cmd_valid,
    output logic                          o_cmd_ready,
    input  logic [AXI_ID_WIDTH-1:0]       i_cmd_id,
    input  logic [AXI_ADDR_WIDTH-1:0]     i_cmd_addr,
    input  logic [7:0]                    i_cmd_len,
    input  logic [AXI_QOS_WIDTH-1:0]      i_cmd_qos,
    input  logic                          i_cmd_last = 1'b1,

    // Beat ghi từ wdata_buffer (thứ tự W, AXI4 không xen kẽ nên trùng thứ tự AW)
    input  logic                          i_data_valid,
    output logic                          o_data_ready,
    input  logic [AXI_DATA_WIDTH-1:0]     i_data,
    input  logic [AXI_DATA_WIDTH/8-1:0]   i_strb,
    input  logic                          i_last,
    // Một beat W vừa vào wdata_buffer
    input  logic                          i_wbeat_accepted,

    // Lệnh ghi đã có đủ dữ liệu, mang tag slot, sang bộ ghép đọc/ghi
    output logic                          o_wcmd_valid,
    input  logic                          i_wcmd_ready,
    output logic [AXI_ID_WIDTH-1:0]       o_wcmd_id,
    output logic [TAG_W-1:0]              o_wcmd_tag,
    output logic [AXI_ADDR_WIDTH-1:0]     o_wcmd_addr,
    output logic [7:0]                    o_wcmd_len,
    output logic [AXI_QOS_WIDTH-1:0]      o_wcmd_qos,

    // Phản hồi B: chỉ sau khi beat cuối đã được lưu (AXI4: BVALID sau handshake WLAST)
    output logic                          o_bresp_valid,
    input  logic                          i_bresp_ready,
    output logic [AXI_ID_WIDTH-1:0]       o_bresp_id,

    // Lệnh ghi còn ở trạng thái gom/chờ: bộ ghép phải chặn lệnh đọc trùng dòng 64B (RAW)
    output logic                          o_stage_busy,
    output logic [AXI_ADDR_WIDTH-1:0]     o_stage_addr,

    // Cổng đọc cho DFI: lệnh WR mang tag; slot được giải phóng sau beat cuối
    input  logic [TAG_W-1:0]              i_rd_tag,
    input  logic [BEAT_W-1:0]             i_rd_beat,
    output logic [AXI_DATA_WIDTH-1:0]     o_rd_data,
    output logic [AXI_DATA_WIDTH/8-1:0]   o_rd_strb,
    output logic                          o_rd_poison,
    input  logic                          i_free_valid,
    input  logic [TAG_W-1:0]              i_free_tag,

    // Slot có beat ghi thiếu byte: với ECC, lệnh ghi này phải đi qua RMW ở engine
    output logic [SLOTS-1:0]              o_partial,
    // Trộn dữ liệu cũ (đã sửa ECC, đã giải xáo trộn) vào các byte master không ghi; sau đó beat đủ byte.
    // i_mrg_poison: dữ liệu cũ hỏng không sửa được, beat phải được ghi lại kèm ECC hỏng để lỗi không bị "tẩy".
    input  logic                          i_mrg_valid,
    input  logic [TAG_W-1:0]              i_mrg_tag,
    input  logic [BEAT_W-1:0]             i_mrg_beat,
    input  logic [AXI_DATA_WIDTH-1:0]     i_mrg_data,
    input  logic                          i_mrg_poison
);

    logic [AXI_DATA_WIDTH-1:0]   mem_data [SLOTS][MAX_BEATS];
    logic [AXI_DATA_WIDTH/8-1:0] mem_strb [SLOTS][MAX_BEATS];
    logic                        mem_psn  [SLOTS][MAX_BEATS];
    logic [SLOTS-1:0]            slot_busy;
    logic [SLOTS-1:0]            slot_partial;

    assign o_partial = slot_partial;

    // Số beat W đã nằm trong wdata_buffer mà chưa được gom: một đoạn chỉ bắt đầu khi đủ beat của nó, nên việc gom
    // không bao giờ phải chờ kênh W. Đếm theo beat (không theo WLAST) để burst dài hơn bộ đệm W vẫn chảy qua được.
    logic [8:0] beats_avail;

    // Slot trống chỉ số thấp nhất
    logic [TAG_W-1:0] free_tag;
    logic             any_free;
    always_comb begin
        free_tag = '0;
        any_free = 1'b0;
        for (int i = SLOTS - 1; i >= 0; i--)
            if (!slot_busy[i]) begin
                free_tag = TAG_W'(i);
                any_free = 1'b1;
            end
    end

    typedef enum logic [1:0] {S_IDLE, S_FILL, S_READY} state_t;
    state_t                    state;
    logic [TAG_W-1:0]          cur_tag;
    logic [BEAT_W:0]           cur_beat;
    logic [AXI_ID_WIDTH-1:0]   cur_id;
    logic [AXI_ADDR_WIDTH-1:0] cur_addr;
    logic [7:0]                cur_len;
    logic [AXI_QOS_WIDTH-1:0]  cur_qos;
    logic                      cur_last;

    wire start  = (state == S_IDLE) && i_cmd_valid && (beats_avail > 9'(i_cmd_len)) && any_free && !o_bresp_valid;
    wire beat_in = (state == S_FILL) && i_data_valid;

    assign o_cmd_ready  = start;
    assign o_data_ready = (state == S_FILL);

    assign o_wcmd_valid = (state == S_READY);
    assign o_wcmd_id    = cur_id;
    assign o_wcmd_tag   = cur_tag;
    assign o_wcmd_addr  = cur_addr;
    assign o_wcmd_len   = cur_len;
    assign o_wcmd_qos   = cur_qos;

    assign o_stage_busy = (state != S_IDLE);
    assign o_stage_addr = cur_addr;

    assign o_rd_data = mem_data[i_rd_tag][i_rd_beat];
    assign o_rd_strb   = mem_strb[i_rd_tag][i_rd_beat];
    assign o_rd_poison = mem_psn[i_rd_tag][i_rd_beat];

    logic [AXI_DATA_WIDTH-1:0] mrg_byte_mask;
    always_comb
        for (int by = 0; by < AXI_DATA_WIDTH / 8; by++)
            mrg_byte_mask[by*8 +: 8] = {8{mem_strb[i_mrg_tag][i_mrg_beat][by]}};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            slot_busy     <= '0;
            slot_partial  <= '0;
            beats_avail   <= '0;
            cur_last      <= 1'b0;
            cur_tag       <= '0;
            cur_beat      <= '0;
            cur_id        <= '0;
            cur_addr      <= '0;
            cur_len       <= '0;
            cur_qos       <= '0;
            o_bresp_valid <= 1'b0;
            o_bresp_id    <= '0;
        end else begin
            beats_avail <= beats_avail + (i_wbeat_accepted ? 9'd1 : 9'd0) - (beat_in ? 9'd1 : 9'd0);
            if (o_bresp_valid && i_bresp_ready) o_bresp_valid <= 1'b0;
            if (i_free_valid) slot_busy[i_free_tag] <= 1'b0;

            case (state)
                S_IDLE: if (start) begin
                    state              <= S_FILL;
                    cur_tag            <= free_tag;
                    cur_beat           <= '0;
                    cur_id             <= i_cmd_id;
                    cur_addr           <= i_cmd_addr;
                    cur_len            <= i_cmd_len;
                    cur_qos            <= i_cmd_qos;
                    cur_last           <= i_cmd_last;
                    slot_busy[free_tag]    <= 1'b1;
                    slot_partial[free_tag] <= 1'b0;
                end
                S_FILL: if (beat_in) begin
                    cur_beat <= cur_beat + 1'b1;
                    if (i_strb != '1) slot_partial[cur_tag] <= 1'b1;
                    if (cur_beat == (BEAT_W+1)'(cur_len)) begin
                        state <= S_READY;
                        // AXI4: một phản hồi B cho cả burst, sau beat WLAST (beat cuối của đoạn cuối)
                        if (cur_last) begin
                            o_bresp_valid <= 1'b1;
                            o_bresp_id    <= cur_id;
                        end
                    end
                end
                S_READY: if (i_wcmd_ready) state <= S_IDLE;
                default: state <= S_IDLE;
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (beat_in) begin
            mem_data[cur_tag][cur_beat[BEAT_W-1:0]] <= i_data;
            mem_strb[cur_tag][cur_beat[BEAT_W-1:0]] <= i_strb;
            mem_psn [cur_tag][cur_beat[BEAT_W-1:0]] <= 1'b0;
        end
        // Slot trộn đã rời giai đoạn gom (đã phát lệnh) nên không bao giờ trùng slot đang gom
        if (i_mrg_valid) begin
            mem_data[i_mrg_tag][i_mrg_beat] <= (mem_data[i_mrg_tag][i_mrg_beat] & mrg_byte_mask) |
                                               (i_mrg_data & ~mrg_byte_mask);
            mem_strb[i_mrg_tag][i_mrg_beat] <= '1;
            mem_psn [i_mrg_tag][i_mrg_beat] <= i_mrg_poison;
        end
    end

`ifndef SYNTHESIS
    // WLAST phải trùng beat cuối của đoạn cuối: lệch nghĩa là master vi phạm AWLEN (AXI4 A3.4.1)
    always_ff @(posedge clk)
        if (rst_n && beat_in && (i_last != (cur_last && cur_beat == (BEAT_W+1)'(cur_len))))
            $error("wr_data_store: WLAST mismatch with AWLEN (tag %0d beat %0d)", cur_tag, cur_beat);
`endif

endmodule
