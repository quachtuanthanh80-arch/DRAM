// File: qshield_mac_unit.sv
// Chức năng: Đơn vị tính và kiểm tra MAC Carter-Wegman trên GF(2^128) cho dòng dữ liệu và node cây.

`timescale 1ns / 1ps

module qshield_mac_unit #(
    parameter int GF_STAGES = 4 // Số tầng pipeline của bộ nhân GF(2^128)
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // Giao diện cấu hình khóa
    input  logic [127:0]           i_h,               // Khóa con GHASH H = AES256_K3(0^128)

    // Giao diện yêu cầu tính MAC / Hash
    input  logic                   i_valid,
    output logic                   o_ready,
    input  logic                   i_mode,            // 0: Dòng dữ liệu (0x01), 1: Node cây / CB (0x02)
    input  logic [511:0]           i_data,            // 4 khối 128-bit: {C0, C1, C2, C3} hoặc {B0, B1, B2, B3}
    input  logic [127:0]           i_mask,            // Vector mask = AES256_K3(...)

    // Đầu vào hỗ trợ sinh bản rõ mask cho AES256
    input  logic [63:0]            i_major,
    input  logic [6:0]             i_minor,
    input  logic [48:0]            i_line_idx,
    input  logic [3:0]             i_level,
    input  logic [59:0]            i_node_idx,
    output logic [127:0]           o_mask_plaintext,  // Bản rõ đầu vào AES-256 để sinh mask

    // Tag kỳ vọng phục vụ kiểm tra (chiều đọc)
    input  logic [63:0]            i_expected_tag,

    // Giao diện kết quả
    output logic                   o_valid,
    input  logic                   i_ready,
    output logic [63:0]            o_tag,             // Tag MAC 64-bit (cắt 64 bit cao từ tag 128-bit)
    output logic [127:0]           o_tag128,          // Tag đầy đủ 128-bit
    output logic [127:0]           o_ghash,           // Giá trị GHASH_H(data, LEN)
    output logic                   o_tag_match,       // So sánh song song trong 1 chu kỳ: o_tag == i_expected_tag
    output logic                   o_tag_mismatch     // Phát hiện vi phạm toàn vẹn: o_tag != i_expected_tag
);
    // Khối độ dài GHASH chuẩn: len(AAD)=0, len(C)=512 bit
    localparam logic [127:0] GHASH_LEN_BLOCK = 128'h0000_0000_0000_0000_0000_0000_0000_0200;

    // Sinh bản rõ mask theo spec mục 4:
    // Dòng dữ liệu: 0x01 || major[63:0] || minor[6:0] || line_idx[48:0] (128 bit)
    // Node cây:     0x02 || level[3:0] || node_idx[59:0] || pad[56:0]  (128 bit)
    assign o_mask_plaintext = (i_mode == 1'b0) ?
        {8'h01, i_major[63:0], i_minor[6:0], i_line_idx[48:0]} :
        {8'h02, i_level[3:0], i_node_idx[59:0], 56'd0};

    // Định nghĩa các trạng thái FSM điều khiển luồng tính GHASH
    typedef enum logic [1:0] {
        S_IDLE = 2'd0,
        S_FEED = 2'd1,
        S_WAIT = 2'd2,
        S_OUT  = 2'd3
    } state_t;

    state_t state_q;

    // Các thanh ghi lưu trữ ngữ cảnh tính toán
    logic [127:0] reg_c [0:3];
    logic [127:0] reg_h;
    logic [127:0] reg_mask;
    logic [63:0]  reg_expected_tag;
    logic [127:0] accum_y;
    logic [2:0]   blk_idx;

    // Thanh ghi kết quả đầu ra
    logic [127:0] res_ghash;
    logic [127:0] res_tag128;
    logic [63:0]  res_tag;
    logic         res_match;
    logic         res_mismatch;
    logic         out_valid_q;

    // Kết nối bộ nhân GF(2^128) pipeline
    logic         mul_i_valid;
    wire          mul_o_ready;
    logic [127:0] mul_i_x;
    logic [127:0] mul_i_y;
    wire          mul_o_valid;
    wire  [127:0] mul_o_z;

    gf128_mul_pipe #(
        .GF_STAGES(GF_STAGES)
    ) u_gf128_mul (
        .clk    (clk),
        .rst_n  (rst_n),
        .i_valid(mul_i_valid),
        .o_ready(mul_o_ready),
        .i_x    (mul_i_x),
        .i_y    (mul_i_y),
        .o_valid(mul_o_valid),
        .i_ready(1'b1),
        .o_z    (mul_o_z)
    );

    // Lựa chọn khối đưa vào bộ nhân: 4 khối dữ liệu hoặc khối độ dài LEN
    logic [127:0] cur_block;
    always_comb begin
        case (blk_idx)
            3'd0: cur_block = reg_c[0];
            3'd1: cur_block = reg_c[1];
            3'd2: cur_block = reg_c[2];
            3'd3: cur_block = reg_c[3];
            3'd4: cur_block = GHASH_LEN_BLOCK;
            default: cur_block = 128'd0;
        endcase
    end

    // FSM tuần tự hóa 5 khối dữ liệu qua bộ nhân GF(2^128) chia sẻ tài nguyên
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q          <= S_IDLE;
            mul_i_valid      <= 1'b0;
            mul_i_x          <= 128'd0;
            mul_i_y          <= 128'd0;
            accum_y          <= 128'd0;
            blk_idx          <= 3'd0;
            reg_h            <= 128'd0;
            reg_mask         <= 128'd0;
            reg_expected_tag <= 64'd0;
            res_ghash        <= 128'd0;
            res_tag128       <= 128'd0;
            res_tag          <= 64'd0;
            res_match        <= 1'b0;
            res_mismatch     <= 1'b0;
            out_valid_q      <= 1'b0;
            for (int i = 0; i < 4; i++) reg_c[i] <= 128'd0;
        end else begin
            case (state_q)
                S_IDLE: begin
                    mul_i_valid <= 1'b0;
                    if (i_valid && o_ready) begin
                        reg_c[0]         <= i_data[511:384];
                        reg_c[1]         <= i_data[383:256];
                        reg_c[2]         <= i_data[255:128];
                        reg_c[3]         <= i_data[127:0];
                        reg_h            <= i_h;
                        reg_mask         <= i_mask;
                        reg_expected_tag <= i_expected_tag;
                        accum_y          <= 128'd0;
                        blk_idx          <= 3'd0;
                        state_q          <= S_FEED;
                    end
                end

                S_FEED: begin
                    if (mul_o_ready) begin
                        mul_i_valid <= 1'b1;
                        mul_i_x     <= accum_y ^ cur_block;
                        mul_i_y     <= reg_h;
                        state_q     <= S_WAIT;
                    end
                end

                S_WAIT: begin
                    mul_i_valid <= 1'b0;
                    if (mul_o_valid) begin
                        accum_y <= mul_o_z;
                        if (blk_idx == 3'd4) begin
                            // Đã xử lý xong 4 khối dữ liệu + 1 khối LEN
                            logic [127:0] final_tag128;
                            logic [63:0]  final_tag64;

                            final_tag128 = mul_o_z ^ reg_mask;
                            final_tag64  = final_tag128[127:64];

                            res_ghash    <= mul_o_z;
                            res_tag128   <= final_tag128;
                            res_tag      <= final_tag64;
                            // So sánh tag 64-bit song song trong 1 chu kỳ
                            res_match    <= (final_tag64 == reg_expected_tag);
                            res_mismatch <= (final_tag64 != reg_expected_tag);
                            out_valid_q  <= 1'b1;
                            state_q      <= S_OUT;
                        end else begin
                            blk_idx <= blk_idx + 1'b1;
                            state_q <= S_FEED;
                        end
                    end
                end

                S_OUT: begin
                    if (i_ready) begin
                        out_valid_q <= 1'b0;
                        state_q     <= S_IDLE;
                    end
                end

                default: state_q <= S_IDLE;
            endcase
        end
    end

    // Gán tín hiệu giao tiếp đầu ra
    assign o_ready        = (state_q == S_IDLE);
    assign o_valid        = out_valid_q;
    assign o_tag          = res_tag;
    assign o_tag128       = res_tag128;
    assign o_ghash        = res_ghash;
    assign o_tag_match    = res_match;
    assign o_tag_mismatch = res_mismatch;

endmodule
