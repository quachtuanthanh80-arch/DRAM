// File: scheduler_sva.sv
// Chức năng: Tập thuộc tính SVA cho bộ lập lịch DDR5: open_row[bg,ba] đã ACT trước RD/WR.

`timescale 1ns / 1ps

`ifndef __ICARUS__

interface scheduler_sva #(
    parameter int TotalBanks = 32,
    parameter int RowWidth   = 16
)(
    input logic clk,
    input logic rst_n,

    // Giao diện lệnh DDR5 phát ra PHY
    input logic                cmd_valid,
    input logic [2:0]          cmd_type,
    input logic [2:0]          cmd_bg,
    input logic [1:0]          cmd_ba,
    input logic [RowWidth-1:0] cmd_row,

    // Trạng thái nội bộ của các bank
    input logic [1:0]          bank_state [TotalBanks],
    input logic [RowWidth-1:0] open_row   [TotalBanks]
);

    localparam logic [2:0] CmdRd  = 3'd1;
    localparam logic [2:0] CmdWr  = 3'd2;
    localparam logic [1:0] BANK_ACTIVE = 2'b10;

    wire [4:0] bank_idx = {cmd_bg, cmd_ba};

    // -------------------------------------------------------------------------
    // SVA 5: RD/WR chỉ được phát khi open_row[{bg, ba}] đã hoàn tất ACT
    // (bank_state == BANK_ACTIVE và open_row trùng khớp cmd_row)
    // -------------------------------------------------------------------------
    property p_bank_active_before_cas;
        @(posedge clk) disable iff (!rst_n)
        (cmd_valid && (cmd_type == CmdRd || cmd_type == CmdWr)) |-> (bank_state[bank_idx] == BANK_ACTIVE);
    endproperty

    property p_open_row_match_cas;
        @(posedge clk) disable iff (!rst_n)
        (cmd_valid && (cmd_type == CmdRd || cmd_type == CmdWr)) |-> (open_row[bank_idx] == cmd_row);
    endproperty

    assert property (p_bank_active_before_cas)
        else $error("[SVA_ERR] RD/WR command issued to inactive DDR5 bank");

    assert property (p_open_row_match_cas)
        else $error("[SVA_ERR] RD/WR command row does not match currently active open row");

endinterface

`endif
