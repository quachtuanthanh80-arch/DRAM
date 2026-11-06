//=============================================================================
// File:        adaptive_threshold_engine.sv
// Chức năng:   Động cơ lọc số EWMA tự thích ứng điều chỉnh ngưỡng kích hoạt động ATE theo tải thực tế.
//=============================================================================
`timescale 1ns / 1ps

module adaptive_threshold_engine #(
    parameter int COUNT_WIDTH    = 16,
    parameter int ALPHA_SHIFT_DEF = 4,   // EWMA factor alpha = 1 / 16
    parameter int WINDOW_CYCLES  = 1024 // Periodic sampling window
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // Configuration
    input  logic                   cfg_ate_en,
    input  logic [3:0]             cfg_alpha_shift,
    input  logic [COUNT_WIDTH-1:0] cfg_base_thresh,
    input  logic [COUNT_WIDTH-1:0] cfg_max_thresh,

    // Real-Time Telemetry from SDC Filter
    input  logic [31:0]            i_telemetry_accesses,
    input  logic [31:0]            i_telemetry_throttles,
    input  logic                   i_rowpress_clamp_alert = 1'b0,

    // Dynamic Threshold Output to SDC Filter
    output logic [COUNT_WIDTH-1:0] o_dynamic_thresh,
    output logic [15:0]            o_sample_epochs
);

    // Internal Registers
    logic [COUNT_WIDTH-1:0] dynamic_thresh_reg;
    logic [15:0]            epoch_counter;
    logic [15:0]            window_timer;

    // Previous telemetry snapshot for delta calculation
    logic [31:0] prev_accesses;
    logic [31:0] prev_throttles;

    // Cấu hình CSR gần như tĩnh: đăng ký một lần (giá trị mặc định khi trường bằng 0) để tách khỏi phép tính ngưỡng
    logic [3:0]             alpha_shift;
    logic [COUNT_WIDTH-1:0] base_thresh, max_thresh;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alpha_shift <= 4'(ALPHA_SHIFT_DEF);
            base_thresh <= 16'd2048;
            max_thresh  <= 16'd8192;
        end else begin
            alpha_shift <= (cfg_alpha_shift != 4'd0) ? cfg_alpha_shift : 4'(ALPHA_SHIFT_DEF);
            base_thresh <= (cfg_base_thresh != '0) ? cfg_base_thresh : 16'd2048;
            max_thresh  <= (cfg_max_thresh != '0)  ? cfg_max_thresh  : 16'd8192;
        end
    end

    assign o_dynamic_thresh = (cfg_ate_en && (epoch_counter != 16'd0)) ? dynamic_thresh_reg : base_thresh;
    assign o_sample_epochs  = epoch_counter;

    localparam int WINDOW_LIMIT = WINDOW_CYCLES - 1;

    // Cập nhật mỗi cửa sổ chia 3 pha thanh ghi (lấy mẫu delta -> tính bước EWMA -> cập nhật ngưỡng): cả chuỗi
    // trừ 32 bit, dịch biến, cộng và so sánh trước đây nằm trong một chu kỳ. Cửa sổ dài WINDOW_CYCLES nên trễ
    // thêm 2 chu kỳ không ảnh hưởng thuật toán.
    logic                   ph2, ph3;
    logic [31:0]            d_acc, d_thr;
    logic [COUNT_WIDTH-1:0] cur_q, st_up_q, st_dn_q;
    logic                   relax_q, tight_q;
    // Bước phạt RowPress tính sẵn từ ngưỡng hiện tại (đăng ký): cảnh báo chỉ còn một phép trừ và so sánh
    logic [COUNT_WIDTH-1:0] pen_step_q;
    logic                   pen_floor_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dynamic_thresh_reg <= 16'd2048;
            epoch_counter      <= 16'd0;
            window_timer       <= 16'd0;
            prev_accesses      <= 32'd0;
            prev_throttles     <= 32'd0;
            ph2                <= 1'b0;
            ph3                <= 1'b0;
            d_acc              <= '0;
            d_thr              <= '0;
            cur_q              <= '0;
            st_up_q            <= '0;
            st_dn_q            <= '0;
            relax_q            <= 1'b0;
            tight_q            <= 1'b0;
            pen_step_q         <= 16'd1;
            pen_floor_q        <= 1'b1;
        end else begin
            begin
                logic [COUNT_WIDTH-1:0] st;
                st = (dynamic_thresh_reg - base_thresh) >> alpha_shift;
                if (st == '0) st = 16'd1;
                pen_step_q  <= st;
                pen_floor_q <= !(dynamic_thresh_reg > (base_thresh + st));
            end
            ph2 <= 1'b0;
            ph3 <= ph2;
            if (!cfg_ate_en) begin
                dynamic_thresh_reg <= base_thresh;
                epoch_counter      <= 16'd0;
                window_timer       <= 16'd0;
                prev_accesses      <= i_telemetry_accesses;
                prev_throttles     <= i_telemetry_throttles;
                ph3                <= 1'b0;
            end else if (int'(window_timer) >= WINDOW_LIMIT) begin
                // Pha 1: lấy mẫu số truy cập / số throttle của cửa sổ và ngưỡng tham chiếu
                d_acc          <= i_telemetry_accesses - prev_accesses;
                d_thr          <= i_telemetry_throttles - prev_throttles;
                prev_accesses  <= i_telemetry_accesses;
                prev_throttles <= i_telemetry_throttles;
                cur_q          <= (epoch_counter == 16'd0) ? base_thresh : dynamic_thresh_reg;
                window_timer   <= 16'd0;
                epoch_counter  <= epoch_counter + 1'b1;
                ph2            <= 1'b1;
            end else begin
                window_timer <= window_timer + 1'b1;
                if (ph2) begin
                    // Pha 2: bước EWMA alpha = 2^-shift về phía max (nới) hoặc về base (siết)
                    logic [COUNT_WIDTH-1:0] su, sd;
                    su = (max_thresh - cur_q) >> alpha_shift;
                    sd = (cur_q - base_thresh) >> alpha_shift;
                    st_up_q <= (su == '0) ? 16'd1 : su;
                    st_dn_q <= (sd == '0) ? 16'd1 : sd;
                    // Tỉ lệ throttle > 3,125 % (và >= 4 lần): nới ngưỡng; gần như không throttle: siết về base
                    relax_q <= (d_thr > (d_acc >> 5)) && (d_thr >= 32'd4);
                    tight_q <= (d_thr <= 32'd2);
                end else if (ph3) begin
                    // Pha 3: cập nhật ngưỡng
                    if (relax_q)
                        dynamic_thresh_reg <= ((cur_q + st_up_q) <= max_thresh) ? cur_q + st_up_q : max_thresh;
                    else if (tight_q)
                        dynamic_thresh_reg <= (cur_q > (base_thresh + st_dn_q)) ? cur_q - st_dn_q : base_thresh;
                    else
                        dynamic_thresh_reg <= cur_q;
                end else if (epoch_counter == 16'd0) begin
                    dynamic_thresh_reg <= base_thresh;
                end else if (i_rowpress_clamp_alert) begin
                    // Phạt tức thời: Hạ ngưỡng an toàn khi phát hiện tấn công mở hàng kéo dài RowPress
                    dynamic_thresh_reg <= pen_floor_q ? base_thresh : dynamic_thresh_reg - pen_step_q;
                end
            end
        end
    end

`ifdef FORMAL
    initial assume (!rst_n);
    always_ff @(posedge clk) begin
        if ($past(!rst_n))
            assume (rst_n);
        if (rst_n && $past(rst_n)) begin
            assume ($stable(cfg_base_thresh));
            assume ($stable(cfg_max_thresh));
            assume ($stable(cfg_alpha_shift));
        end
    end

    // Configuration assumptions
    always_comb begin
        assume (base_thresh <= max_thresh);
    end

    // Property 1: Threshold Safety Bounds Invariant (Evasion Robustness)
    // Guarantees that adaptive threshold is strictly clamped between base and max thresholds.
    always_comb begin
        if (rst_n) begin
            assert (o_dynamic_thresh >= base_thresh);
            assert (o_dynamic_thresh <= max_thresh);
        end
    end

    // Property 2: Non-Adaptive Bypass Mode
    always_comb begin
        if (rst_n && !cfg_ate_en) begin
            assert (o_dynamic_thresh == base_thresh);
        end
    end
`endif

endmodule: adaptive_threshold_engine
