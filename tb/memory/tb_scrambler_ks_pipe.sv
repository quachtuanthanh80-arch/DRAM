// File:      tb_scrambler_ks_pipe.sv
// Chức năng: Kiểm tra scrambler_ks_pipe cho keystream bit-exact với bus_scrambler (tổ hợp) sau đúng 6 chu kỳ, kèm sideband.
`timescale 1ns / 1ps

module tb_scrambler_ks_pipe;
    `include "tb_check.svh"

    logic        clk = 0, rst_n = 0;
    logic [63:0] seed = 64'h1357_9BDF_2468_ACE0;
    logic        i_valid = 0;
    logic [63:0] i_key = 0;
    logic [15:0] i_side = 0;
    logic        o_valid;
    logic [63:0] o_ks;
    logic [15:0] o_side;
    logic [63:0] ref_ks;

    always #2 clk = ~clk;

    scrambler_ks_pipe #(.SIDE_W(16)) dut (.clk(clk), .rst_n(rst_n), .cfg_seed(seed), .i_valid(i_valid), .i_key(i_key),
                                          .i_side(i_side), .o_valid(o_valid), .o_ks(o_ks), .o_side(o_side));
    // Tham chiếu: bus_scrambler với dữ liệu 0 cho ra đúng mặt nạ keystream
    logic [63:0] ref_key;
    bus_scrambler #(.DATA_WIDTH(64)) u_ref (.cfg_scramble_en(1'b1), .cfg_seed(seed), .i_key(ref_key), .i_data(64'd0), .o_data(ref_ks));

    logic [63:0] key_q [$];
    logic [15:0] side_q [$];
    int n_ok = 0, n_bad = 0, n_out = 0;

    always @(posedge clk) begin
        if (rst_n && o_valid) begin
            logic [63:0] k, got;
            logic [15:0] sd, gs;
            got = o_ks;
            gs  = o_side;
            k  = key_q.pop_front();
            sd = side_q.pop_front();
            ref_key = k;
            #0.1;
            n_out++;
            if (got === ref_ks && gs === sd) n_ok++;
            else begin
                n_bad++;
                if (n_bad <= 4) $display("  [DIAG] key %h: pipe %h ref %h side %h/%h", k, got, ref_ks, gs, sd);
            end
        end
    end

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;
        for (int i = 0; i < 2000; i++) begin
            @(negedge clk);
            // Seed là cấu hình tĩnh: chỉ đổi khi pipeline rỗng (không phát key trong 20 chu kỳ quanh lúc đổi)
            i_valid = ($urandom_range(0, 3) != 0) && !(i >= 990 && i < 1010);
            i_key   = {$urandom, $urandom};
            i_side  = 16'(i);
            if (i == 1000) seed = 64'hDEAD_BEEF_0BAD_F00D;
            if (i_valid) begin key_q.push_back(i_key); side_q.push_back(i_side); end
        end
        @(negedge clk);
        i_valid = 0;
        repeat (10) @(posedge clk);
        tb_check(n_bad == 0 && n_ok > 1000, $sformatf("Pipelined keystream bit-exact with bus_scrambler (%0d OK, %0d bad)", n_ok, n_bad));
        tb_check(key_q.size() == 0, $sformatf("Every key produced exactly one keystream after 6 cycles (%0d left)", key_q.size()));
        tb_report();
        $finish;
    end
endmodule
