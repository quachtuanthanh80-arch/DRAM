// File: check_h2.sv
// Chức năng: Kiểm tra tái hiện finding H-2 (Scheduler bỏ qua Bank Group trong chỉ mục bank_state).

`timescale 1ns / 1ps

module check_h2;
    `include "tb_check.svh"

    logic clk = 0;
    logic rst_n;
    always #2.5 clk = ~clk;

    logic        req_valid;
    wire         req_ready;
    logic        req_is_write;
    logic [2:0]  req_bank;
    logic [1:0]  req_bank_grp;
    logic [15:0] req_row;
    logic [9:0]  req_col;
    logic [127:0] req_wdata;
    logic [15:0] req_tag;

    wire         cmd_valid;
    logic        cmd_ready;
    wire  [2:0]  cmd_type;
    wire  [1:0]  cmd_bg;
    wire  [2:0]  cmd_ba;
    wire  [15:0] cmd_addr;
    wire  [127:0] cmd_wdata;
    wire  [15:0] cmd_tag;

    localparam logic [2:0] CmdAct = 3'b001;
    localparam logic [2:0] CmdWr  = 3'b100;

    ddr5_subchannel_scheduler #(
        .NumBanks   (8),
        .NumBankGrps(4),
        .RowWidth   (16),
        .ColWidth   (10),
        .TRCD_CYC   (6)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .req_valid    (req_valid),
        .req_ready    (req_ready),
        .req_is_write (req_is_write),
        .req_bank     (req_bank),
        .req_bank_grp (req_bank_grp),
        .req_row      (req_row),
        .req_col      (req_col),
        .req_wdata    (req_wdata),
        .req_tag      (req_tag),
        .cmd_valid    (cmd_valid),
        .cmd_ready    (cmd_ready),
        .cmd_type     (cmd_type),
        .cmd_bg       (cmd_bg),
        .cmd_ba       (cmd_ba),
        .cmd_addr     (cmd_addr),
        .cmd_wdata    (cmd_wdata),
        .cmd_tag      (cmd_tag),
        .page_hits    (),
        .page_misses  (),
        .total_cmds   ()
    );

    logic [2:0] first_cmd_bg1 = 3'b000;
    logic       seen_bg1_cmd  = 1'b0;

    initial begin
        rst_n        = 0;
        req_valid    = 0;
        req_is_write = 1;
        req_bank     = 3'd0;
        req_bank_grp = 2'd0;
        req_row      = 16'h1234;
        req_col      = 10'd0;
        req_wdata    = 128'h0;
        req_tag      = 16'd1;
        cmd_ready    = 1;

        #20;
        rst_n = 1;
        #10;

        // Yêu cầu 1: Ghi vào BG0 / Bank0, Row 0x1234
        @(posedge clk);
        req_valid    <= 1'b1;
        req_bank_grp <= 2'd0;
        req_bank     <= 3'd0;
        req_row      <= 16'h1234;

        // Chờ nhận lệnh ACT cho BG0
        wait (cmd_valid && cmd_type == CmdAct && cmd_bg == 2'd0);
        @(posedge clk);

        // Chờ nhận lệnh WR cho BG0
        wait (cmd_valid && cmd_type == CmdWr && cmd_bg == 2'd0);
        @(posedge clk);
        req_valid <= 1'b0;
        #20;

        // Yêu cầu 2: Ghi vào BG1 / Bank0, Row 0x1234 (Cùng bank 0 nhưng KHÁC Bank Group BG1)
        // Bank 0 của BG1 hoàn toàn chưa được mở; chuẩn JEDEC DDR5 bắt buộc phải phát CmdAct trước!
        @(posedge clk);
        req_valid    <= 1'b1;
        req_bank_grp <= 2'd1;
        req_bank     <= 3'd0;
        req_row      <= 16'h1234;

        // Bắt lệnh đầu tiên scheduler phát cho BG1
        while (!seen_bg1_cmd) begin
            @(posedge clk);
            if (cmd_valid && cmd_bg == 2'd1) begin
                first_cmd_bg1 = cmd_type;
                seen_bg1_cmd  = 1'b1;
            end
        end

        // Check H-2: Lệnh đầu tiên phát cho BG1/BA0 phải là ACT (3'b001); không được phát thẳng WR (3'b100)
        tb_check(first_cmd_bg1 == CmdAct, "H-2: Scheduler must issue ACT to BG1 before issuing WR");

        tb_report();
        $finish;
    end

endmodule
