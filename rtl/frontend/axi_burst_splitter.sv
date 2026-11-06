// File:      axi_burst_splitter.sv
// Chức năng: Tách một burst AXI4 (INCR/WRAP/FIXED, mọi AxSIZE, tới 256 beat) thành các đoạn nằm gọn trong một dòng 64B, mỗi đoạn tối đa 8 beat.
`timescale 1ns / 1ps

module axi_burst_splitter #(
    parameter int AXI_ID_WIDTH   = 4,
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_QOS_WIDTH  = 4,
    parameter int DATA_BYTES     = 8,
    parameter int LINE_BYTES     = 64
) (
    input  logic                       clk,
    input  logic                       rst_n,

    input  logic                       i_valid,
    output logic                       o_ready,
    input  logic [AXI_ID_WIDTH-1:0]    i_id,
    input  logic [AXI_ADDR_WIDTH-1:0]  i_addr,
    input  logic [7:0]                 i_len,
    input  logic [2:0]                 i_size,
    input  logic [1:0]                 i_burst,
    input  logic [AXI_QOS_WIDTH-1:0]   i_qos,

    // Một đoạn: o_len = số beat - 1 (<= LINE_BYTES/DATA_BYTES - 1); o_last = đoạn cuối của burst AXI
    output logic                       o_valid,
    input  logic                       i_ready,
    output logic [AXI_ID_WIDTH-1:0]    o_id,
    output logic [AXI_ADDR_WIDTH-1:0]  o_addr,
    output logic [7:0]                 o_len,
    output logic [AXI_QOS_WIDTH-1:0]   o_qos,
    output logic                       o_last,
    // Đang còn burst chưa phát hết đoạn: bộ ghép đọc/ghi coi như còn lệnh ghi tồn đọng (RAW)
    output logic                       o_busy
);

    localparam int WB  = $clog2(DATA_BYTES);              // bit địa chỉ byte trong word
    localparam int LW  = LINE_BYTES / DATA_BYTES;         // word mỗi dòng
    localparam int LWB = $clog2(LW);
    localparam logic [1:0] B_FIXED = 2'b00, B_INCR = 2'b01, B_WRAP = 2'b10;

    logic                      busy;
    logic [AXI_ADDR_WIDTH-1:0] addr;
    logic [8:0]                rem;      // số beat còn lại (1..256)
    logic [7:0]                len;      // AxLEN gốc: biên WRAP = (len+1) << size
    logic [2:0]                size;
    logic [1:0]                burst;
    logic [AXI_ID_WIDTH-1:0]   id;
    logic [AXI_QOS_WIDTH-1:0]  qos;

    // Cơ chế: beat rộng đủ bus (AxSIZE = log2 DATA_BYTES) đi theo word liên tiếp, gộp được tới hết dòng
    // (hoặc tới biên WRAP). Beat hẹp hay FIXED có thể lặp lại cùng word nên mỗi beat là một đoạn 1 beat:
    // chậm hơn nhưng đúng làn byte (đọc trả cả word, ghi dùng WSTRB và RMW).
    wire                 full      = (size == 3'(WB)) && (burst != B_FIXED);
    wire [LWB:0]         to_line   = (LWB+1)'(LW) - (LWB+1)'(addr[WB +: LWB]);
    wire [4:0]           wrap_w    = 5'(len) + 5'd1;                      // số word trong vùng WRAP (2/4/8/16)
    wire [4:0]           wrap_off  = 5'(addr[WB +: 4]) & (wrap_w - 5'd1);
    wire [4:0]           to_wrap   = wrap_w - wrap_off;
    logic [LWB:0]        clen;
    always_comb begin
        if (!full)
            clen = (LWB+1)'(1);
        else begin
            clen = to_line;
            if (burst == B_WRAP && 5'(to_wrap) < 5'(clen)) clen = (LWB+1)'(to_wrap);
            if (9'(clen) > rem) clen = (LWB+1)'(rem);
        end
    end

    // Địa chỉ beat kế tiếp sau đoạn hiện tại (từ độ dài đoạn đã chốt ở pha 0)
    logic [LWB:0] clen_q;
    wire [AXI_ADDR_WIDTH-1:0] bytes_sz  = AXI_ADDR_WIDTH'(1) << size;
    wire [AXI_ADDR_WIDTH-1:0] aligned   = addr & ~(bytes_sz - 1'b1);
    wire [AXI_ADDR_WIDTH-1:0] wrap_byt  = AXI_ADDR_WIDTH'(9'(len) + 9'd1) << size;
    wire [AXI_ADDR_WIDTH-1:0] incr_next = aligned + (AXI_ADDR_WIDTH'(clen_q) << size);
    logic [AXI_ADDR_WIDTH-1:0] next_addr;
    always_comb begin
        next_addr = incr_next;
        if (burst == B_FIXED)
            next_addr = addr;
        else if (burst == B_WRAP && (incr_next & (wrap_byt - 1'b1)) == '0)
            next_addr = incr_next - wrap_byt;
    end

    // Hai pha mỗi đoạn: pha 0 chốt độ dài đoạn (so biên dòng/biên WRAP/số beat còn lại), pha 1 tính địa chỉ kế tiếp
    // từ độ dài đã chốt và phát đoạn. Tách để mỗi pha chỉ còn một nửa chuỗi logic (Fmax); một đoạn tối đa 8 beat
    // chiếm bus DRAM >= 8 chu kỳ nên 2 chu kỳ/đoạn không làm giảm băng thông.
    logic        phase;
    wire gen = busy && phase && (!o_valid || i_ready);
    assign o_ready = !busy;
    assign o_busy  = busy || o_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy    <= 1'b0;
            phase   <= 1'b0;
            o_valid <= 1'b0;
            rem     <= '0;
        end else begin
            if (i_valid && o_ready) begin
                busy  <= 1'b1;
                phase <= 1'b0;
                rem   <= 9'(i_len) + 9'd1;
            end else if (busy && !phase) begin
                phase <= 1'b1;
            end else if (gen) begin
                rem   <= rem - 9'(clen_q);
                busy  <= (rem != 9'(clen_q));
                phase <= 1'b0;
            end
            if (gen)          o_valid <= 1'b1;
            else if (i_ready) o_valid <= 1'b0;
        end
    end

    always_ff @(posedge clk) begin
        if (i_valid && o_ready) begin
            addr  <= i_addr;
            len   <= i_len;
            size  <= i_size;
            burst <= i_burst;
            id    <= i_id;
            qos   <= i_qos;
        end else if (gen) begin
            addr  <= next_addr;
        end
        if (busy && !phase) clen_q <= clen;
        if (gen) begin
            o_id   <= id;
            o_addr <= addr;
            o_len  <= 8'(clen_q) - 8'd1;
            o_qos  <= qos;
            o_last <= (rem == 9'(clen_q));
        end
    end

endmodule
