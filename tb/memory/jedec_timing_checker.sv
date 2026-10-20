// File: jedec_timing_checker.sv
// Chức năng: Giám sát và phát hiện vi phạm định thời chuẩn JEDEC DDR5/DDR4 (tRCD, tRP, tRAS, tCCD, tRRD, tRFC).
`timescale 1ns / 1ps

module jedec_timing_checker #(
    parameter int BG_COUNT    = 8,
    parameter int BANK_COUNT  = 4,
    parameter int ROW_WIDTH   = 17,
    parameter int COL_WIDTH   = 10,

    // JEDEC Timing Parameters (tính bằng chu kỳ xung nhịp DRAM 16-bit)
    parameter logic [15:0] T_RCD   = 16'd6,   // ACT -> RD/WR trên cùng một Bank
    parameter logic [15:0] T_RP    = 16'd6,   // PRE -> ACT trên cùng một Bank
    parameter logic [15:0] T_RAS   = 16'd14,  // ACT -> PRE trên cùng một Bank (thời gian mở hàng tối thiểu)
    parameter logic [15:0] T_CCD_L = 16'd4,   // RD/WR -> RD/WR trong cùng một Bank Group
    parameter logic [15:0] T_CCD_S = 16'd2,   // RD/WR -> RD/WR giữa các Bank Group khác nhau
    parameter logic [15:0] T_RRD_L = 16'd4,   // ACT -> ACT trong cùng một Bank Group
    parameter logic [15:0] T_RRD_S = 16'd2,   // ACT -> ACT giữa các Bank Group khác nhau
    parameter logic [15:0] T_RFC   = 16'd32   // REF -> ACT (chu kỳ hoàn tất lệnh Refresh)
) (
    input  logic                          clk,
    input  logic                          rst_n,

    // Giao diện lệnh DFI từ bộ điều khiển
    input  logic [2:0]                    i_dfi_cmd,  // 0:NOP, 1:ACT, 2:PRE, 3:RD, 4:WR, 5:REF
    input  logic [$clog2(BG_COUNT)-1:0]   i_dfi_bg,
    input  logic [$clog2(BANK_COUNT)-1:0] i_dfi_bank,
    input  logic [ROW_WIDTH-1:0]          i_dfi_row,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [COL_WIDTH-1:0]          i_dfi_col,
    /* verilator lint_on UNUSEDSIGNAL */

    // Tín hiệu cảnh báo vi phạm
    output logic                          o_timing_violation,
    output logic [31:0]                   o_violation_count,
    output logic [3:0]                    o_last_violation_type
);

    localparam logic [2:0] CMD_ACT = 3'b001;
    localparam logic [2:0] CMD_PRE = 3'b010;
    localparam logic [2:0] CMD_RD  = 3'b011;
    localparam logic [2:0] CMD_WR  = 3'b100;
    localparam logic [2:0] CMD_REF = 3'b101;

    // Mã định danh vi phạm
    localparam logic [3:0] ERR_NONE  = 4'h0;
    localparam logic [3:0] ERR_TRCD  = 4'h1;
    localparam logic [3:0] ERR_TRP   = 4'h2;
    localparam logic [3:0] ERR_TRAS  = 4'h3;
    localparam logic [3:0] ERR_TCCDL = 4'h4;
    localparam logic [3:0] ERR_TCCDS = 4'h5;
    localparam logic [3:0] ERR_TRRDL = 4'h6;
    localparam logic [3:0] ERR_TRRDS = 4'h7;
    localparam logic [3:0] ERR_TRFC  = 4'h8;

    // Bộ đếm thời gian trôi qua từ các mốc lệnh
    logic [15:0] cycles_since_act [BG_COUNT-1:0][BANK_COUNT-1:0];
    logic [15:0] cycles_since_pre [BG_COUNT-1:0][BANK_COUNT-1:0];
    logic        bank_active      [BG_COUNT-1:0][BANK_COUNT-1:0];
    /* verilator lint_off UNUSEDSIGNAL */
    logic [ROW_WIDTH-1:0] active_row [BG_COUNT-1:0][BANK_COUNT-1:0];
    /* verilator lint_on UNUSEDSIGNAL */

    logic [15:0] cycles_since_col_cmd [BG_COUNT-1:0];
    logic [15:0] cycles_since_last_col_any_bg;

    logic [15:0] cycles_since_act_bg  [BG_COUNT-1:0];
    logic [15:0] cycles_since_last_act_any_bg;

    logic [15:0] cycles_since_ref;
    logic        ref_in_progress;

    // Cơ chế đo lường & phát hiện vi phạm định thời trong chu kỳ hiện tại
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_timing_violation           <= 1'b0;
            o_violation_count             <= '0;
            o_last_violation_type        <= ERR_NONE;
            ref_in_progress              <= 1'b0;
            cycles_since_ref             <= 16'hFFFF;
            cycles_since_last_col_any_bg <= 16'hFFFF;
            cycles_since_last_act_any_bg <= 16'hFFFF;

            for (int bg = 0; bg < BG_COUNT; bg++) begin
                cycles_since_col_cmd[bg] <= 16'hFFFF;
                cycles_since_act_bg[bg]  <= 16'hFFFF;
                for (int bk = 0; bk < BANK_COUNT; bk++) begin
                    cycles_since_act[bg][bk] <= 16'hFFFF;
                    cycles_since_pre[bg][bk] <= 16'hFFFF;
                    bank_active[bg][bk]      <= 1'b0;
                    active_row[bg][bk]       <= '0;
                end
            end
        end else begin
            o_timing_violation <= 1'b0;

            // Tăng biến đếm thời gian
            if (cycles_since_ref < 16'hFFFE)
                cycles_since_ref <= cycles_since_ref + 16'd1;
            if (cycles_since_last_col_any_bg < 16'hFFFE)
                cycles_since_last_col_any_bg <= cycles_since_last_col_any_bg + 16'd1;
            if (cycles_since_last_act_any_bg < 16'hFFFE)
                cycles_since_last_act_any_bg <= cycles_since_last_act_any_bg + 16'd1;

            for (int bg = 0; bg < BG_COUNT; bg++) begin
                if (cycles_since_col_cmd[bg] < 16'hFFFE)
                    cycles_since_col_cmd[bg] <= cycles_since_col_cmd[bg] + 16'd1;
                if (cycles_since_act_bg[bg] < 16'hFFFE)
                    cycles_since_act_bg[bg] <= cycles_since_act_bg[bg] + 16'd1;

                for (int bk = 0; bk < BANK_COUNT; bk++) begin
                    if (cycles_since_act[bg][bk] < 16'hFFFE)
                        cycles_since_act[bg][bk] <= cycles_since_act[bg][bk] + 16'd1;
                    if (cycles_since_pre[bg][bk] < 16'hFFFE)
                        cycles_since_pre[bg][bk] <= cycles_since_pre[bg][bk] + 16'd1;
                end
            end

            // Kiểm tra lệnh DFI hợp lệ
            case (i_dfi_cmd)
                CMD_ACT: begin
                    // 1. Kiểm tra t_RP: Thời gian chờ từ PRE đến ACT trên cùng Bank
                    if (cycles_since_pre[i_dfi_bg][i_dfi_bank] < T_RP) begin
                        o_timing_violation    <= 1'b1;
                        o_violation_count     <= o_violation_count + 32'd1;
                        o_last_violation_type <= ERR_TRP;
                    end

                    // 2. Kiểm tra t_RRD_L & t_RRD_S: Khoảng cách giữa 2 lệnh ACT
                    if (cycles_since_act_bg[i_dfi_bg] < T_RRD_L) begin
                        o_timing_violation    <= 1'b1;
                        o_violation_count     <= o_violation_count + 32'd1;
                        o_last_violation_type <= ERR_TRRDL;
                    end else if (cycles_since_last_act_any_bg < T_RRD_S) begin
                        o_timing_violation    <= 1'b1;
                        o_violation_count     <= o_violation_count + 32'd1;
                        o_last_violation_type <= ERR_TRRDS;
                    end

                    // 3. Kiểm tra t_RFC: Không được ACT khi DRAM chưa hoàn tất chu kỳ Refresh
                    if (ref_in_progress && (cycles_since_ref < T_RFC)) begin
                        o_timing_violation    <= 1'b1;
                        o_violation_count     <= o_violation_count + 32'd1;
                        o_last_violation_type <= ERR_TRFC;
                    end else begin
                        ref_in_progress <= 1'b0;
                    end

                    // Cập nhật trạng thái Bank
                    bank_active[i_dfi_bg][i_dfi_bank]      <= 1'b1;
                    active_row[i_dfi_bg][i_dfi_bank]       <= i_dfi_row;
                    cycles_since_act[i_dfi_bg][i_dfi_bank] <= 16'd0;
                    cycles_since_act_bg[i_dfi_bg]          <= 16'd0;
                    cycles_since_last_act_any_bg           <= 16'd0;
                end

                CMD_PRE: begin
                    // 4. Kiểm tra t_RAS: Thời gian tối thiểu hàng phải mở trước khi PRE
                    if (bank_active[i_dfi_bg][i_dfi_bank] && (cycles_since_act[i_dfi_bg][i_dfi_bank] < T_RAS)) begin
                        o_timing_violation    <= 1'b1;
                        o_violation_count     <= o_violation_count + 32'd1;
                        o_last_violation_type <= ERR_TRAS;
                    end

                    bank_active[i_dfi_bg][i_dfi_bank]      <= 1'b0;
                    cycles_since_pre[i_dfi_bg][i_dfi_bank] <= 16'd0;
                end

                CMD_RD, CMD_WR: begin
                    // 5. Kiểm tra t_RCD: Thời gian từ ACT đến lệnh đọc/ghi trên cùng Bank
                    if (cycles_since_act[i_dfi_bg][i_dfi_bank] < T_RCD) begin
                        o_timing_violation    <= 1'b1;
                        o_violation_count     <= o_violation_count + 32'd1;
                        o_last_violation_type <= ERR_TRCD;
                    end

                    // 6. Kiểm tra t_CCD_L & t_CCD_S: Giãn cách truy xuất cột cùng/khác Bank Group
                    if (cycles_since_col_cmd[i_dfi_bg] < T_CCD_L) begin
                        o_timing_violation    <= 1'b1;
                        o_violation_count     <= o_violation_count + 32'd1;
                        o_last_violation_type <= ERR_TCCDL;
                    end else if (cycles_since_last_col_any_bg < T_CCD_S) begin
                        o_timing_violation    <= 1'b1;
                        o_violation_count     <= o_violation_count + 32'd1;
                        o_last_violation_type <= ERR_TCCDS;
                    end

                    cycles_since_col_cmd[i_dfi_bg] <= 16'd0;
                    cycles_since_last_col_any_bg   <= 16'd0;
                end

                CMD_REF: begin
                    ref_in_progress  <= 1'b1;
                    cycles_since_ref <= 16'd0;
                end

                default: begin
                    // NOP
                end
            endcase
        end
    end

endmodule
