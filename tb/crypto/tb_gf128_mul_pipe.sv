// File: tb_gf128_mul_pipe.sv
// Chức năng: Kiểm thử đơn vị nhân GF(2^128) pipeline với phần tử đơn vị, vector không, và kiểm tra dừng pipeline.

`timescale 1ns / 1ps
`include "tb_check.svh"

module tb_gf128_mul_pipe;
    logic         clk;
    logic         rst_n;
    logic         i_valid;
    logic         o_ready;
    logic [127:0] i_x;
    logic [127:0] i_y;
    logic         o_valid;
    logic         i_ready;
    logic [127:0] o_z;

    gf128_mul_pipe #(
        .GF_STAGES(4)
    ) dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .i_valid(i_valid),
        .o_ready(o_ready),
        .i_x    (i_x),
        .i_y    (i_y),
        .o_valid(o_valid),
        .i_ready(i_ready),
        .o_z    (o_z)
    );

    always #1.25 clk = ~clk; // 400 MHz chu kỳ 2.5 ns

    task automatic send_op(input [127:0] x, input [127:0] y);
        begin
            @(posedge clk);
            while (!o_ready) @(posedge clk);
            i_valid <= 1'b1;
            i_x     <= x;
            i_y     <= y;
            @(posedge clk);
            i_valid <= 1'b0;
        end
    endtask

    task automatic wait_result(output [127:0] z);
        begin
            @(posedge clk);
            while (!o_valid) @(posedge clk);
            z = o_z;
        end
    endtask

    logic [127:0] res;

    initial begin
        clk     = 0;
        rst_n   = 0;
        i_valid = 0;
        i_ready = 1;
        i_x     = 0;
        i_y     = 0;

        #10;
        rst_n = 1;
        #10;

        // 1. Kiểm tra nhân với 0: 0 * Y = 0
        send_op(128'd0, 128'h123456789ABCDEF0123456789ABCDEF0);
        wait_result(res);
        tb_check(res == 128'd0, "0 * Y == 0");

        // 2. Kiểm tra nhân với phần tử đơn vị e = 0x8000_0000...00
        send_op(128'h8000_0000_0000_0000_0000_0000_0000_0000, 128'h1234_5678_9ABC_DEF0_1234_5678_9ABC_DEF0);
        wait_result(res);
        tb_check(res == 128'h1234_5678_9ABC_DEF0_1234_5678_9ABC_DEF0, "e * Y == Y");

        send_op(128'h1234_5678_9ABC_DEF0_1234_5678_9ABC_DEF0, 128'h8000_0000_0000_0000_0000_0000_0000_0000);
        wait_result(res);
        tb_check(res == 128'h1234_5678_9ABC_DEF0_1234_5678_9ABC_DEF0, "X * e == X");

        // 3. Kiểm tra các vector ngẫu nhiên mẫu từ mô hình Python
        // Vec 1
        send_op(128'hbdd640fb06671ad11c80317fa3b1799d, 128'hbc8960a923b8c1e9392456de3eb13b90);
        wait_result(res);
        tb_check(res == 128'h915ca40cc7dc1e4ff2a01a5551b6b15a, "GF128 random vector 1");

        // Vec 2
        send_op(128'h8b9d2434e465e150bd9c66b3ad3c2d6d, 128'h07a0ca6e0822e8f36c031199972a8469);
        wait_result(res);
        tb_check(res == 128'h3b359b858ac53be823ade6b8a5a20405, "GF128 random vector 2");

        // Vec 3
        send_op(128'h9a1de644815ef6d13b8faa1837f8a88b, 128'h6c307511b2b9437a28df6ec4ce4a2bbd);
        wait_result(res);
        tb_check(res == 128'h33e18e5f243236a9cf454b7ed75fadd6, "GF128 random vector 3");

        // Vec 4
        send_op(128'h6142ea7d17be31111a2a73ed562b0f79, 128'h9a8dca03580d7b71d8f564135be6128e);
        wait_result(res);
        tb_check(res == 128'h26d9adc121628201f4370f1007047e96, "GF128 random vector 4");

        // Vec 5
        send_op(128'h60e7a113ec1b8ca1f91e1d4c1ff49b78, 128'h93cd59bf5c941cf0dc98d2c1e2acf72f);
        wait_result(res);
        tb_check(res == 128'h427b3caba2c9376579f7a49cc9fb5a1c, "GF128 random vector 5");

        // 4. Kiểm tra cơ chế dừng (pipe stall): khi i_ready = 0 thì đầu ra không bị mất giá trị
        send_op(128'h8b9d2434e465e150bd9c66b3ad3c2d6d, 128'h07a0ca6e0822e8f36c031199972a8469);
        i_ready <= 1'b0;
        repeat(6) @(posedge clk);
        tb_check(o_valid == 1'b1, "Pipeline holds o_valid when i_ready=0");
        tb_check(o_z == 128'h3b359b858ac53be823ade6b8a5a20405, "Pipeline preserves o_z during stall");
        @(posedge clk);
        i_ready <= 1'b1;
        @(posedge clk);

        tb_report();
        $finish;
    end
endmodule
