// File: scheduler_bank_formal.sv
// Chức năng: Formal wrapper kiểm chứng thuộc tính SVA 5 JEDEC: open_row[bg,ba] đã ACT trước RD/WR.

`timescale 1ns / 1ps

module scheduler_bank_formal #(
    parameter int TotalBanks     = 8, // Tối ưu kích thước formal (2 BG x 4 BA)
    parameter int NumBankGroups  = 2,
    parameter int BanksPerGroup  = 4,
    parameter int RowWidth       = 16,
    parameter int ColWidth       = 10
)(
    input logic clk,
    input logic rst_n,

    // Giao diện hàng đợi yêu cầu đầu vào
    input logic [7:0]                   i_queue_valid,
    input logic [7:0][RowWidth-1:0]     i_queue_row,
    input logic [7:0][ColWidth-1:0]     i_queue_col,
    input logic [7:0]                   i_queue_is_wr,
    input logic [7:0][2:0]              i_queue_bg,
    input logic [7:0][1:0]              i_queue_ba,

    // Trạng thái PHY / DFI Ready
    input logic                         i_dfi_ready
);

    logic [2:0]          cmd_type;
    logic                cmd_valid;
    logic [2:0]          cmd_bg;
    logic [1:0]          cmd_ba;
    logic [RowWidth-1:0] cmd_row;
    logic [ColWidth-1:0] cmd_col;
    logic [7:0]          queue_pop;

    localparam logic [2:0] CmdRd  = 3'd1;
    localparam logic [2:0] CmdWr  = 3'd2;
    localparam logic [2:0] CmdAct = 3'd3;
    localparam logic [2:0] CmdPre = 3'd4;

    ddr5_subchannel_scheduler #(
        .TotalBanks     (TotalBanks),
        .NumBankGroups  (NumBankGroups),
        .BanksPerGroup  (BanksPerGroup),
        .RowWidth       (RowWidth),
        .ColWidth       (ColWidth)
    ) u_sched (
        .clk            (clk),
        .rst_n          (rst_n),
        .queue_valid    (i_queue_valid),
        .queue_row      (i_queue_row),
        .queue_col      (i_queue_col),
        .queue_is_wr    (i_queue_is_wr),
        .queue_bg       (i_queue_bg),
        .queue_ba       (i_queue_ba),
        .dfi_ready      (i_dfi_ready),
        .cmd_type       (cmd_type),
        .cmd_valid      (cmd_valid),
        .cmd_bg         (cmd_bg),
        .cmd_ba         (cmd_ba),
        .cmd_row        (cmd_row),
        .cmd_col        (cmd_col),
        .queue_pop      (queue_pop)
    );

    wire [2:0] cmd_bank_idx = {cmd_bg[0], cmd_ba[1:0]};

`ifdef FORMAL
    initial assume (!rst_n);

    always_ff @(posedge clk) begin
        if ($past(!rst_n)) assume (rst_n);
    end

    // Ràng buộc đầu vào: DFI ready luôn sẵn sàng hoặc toggle hợp lệ
    always_ff @(posedge clk) begin
        assume (i_dfi_ready);
    end

    // -------------------------------------------------------------------------
    // SVA 5: RD/WR chỉ được phát khi open_row[{bg, ba}] đã hoàn tất ACT
    // (nghĩa là bank_state == BANK_ACTIVE và open_row trùng khớp cmd_row)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst_n && cmd_valid) begin
            if (cmd_type == CmdRd || cmd_type == CmdWr) begin
                // Bank phải ở trạng thái BANK_ACTIVE (2'b10)
                assert (u_sched.bank_state[cmd_bank_idx] == 2'b10);
                // Row đang mở phải trùng khớp chính xác với cmd_row
                assert (u_sched.open_row[cmd_bank_idx] == cmd_row);
            end
        end
    end

    // -------------------------------------------------------------------------
    // COVER PROPERTIES
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst_n) begin
            // C1: Phát lệnh ACTIVATE
            cover (cmd_valid && (cmd_type == CmdAct));
            // C2: Phát lệnh READ sau khi đã ACTIVATE
            cover (cmd_valid && (cmd_type == CmdRd));
            // C3: Phát lệnh WRITE sau khi đã ACTIVATE
            cover (cmd_valid && (cmd_type == CmdWr));
            // C4: Phát lệnh PRECHARGE đóng bank
            cover (cmd_valid && (cmd_type == CmdPre));
        end
    end

`endif

endmodule
