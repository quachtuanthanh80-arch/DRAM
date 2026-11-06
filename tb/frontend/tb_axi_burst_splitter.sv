// File:      tb_axi_burst_splitter.sv
// Chức năng: Kiểm tra axi_burst_splitter với mô hình địa chỉ beat AXI4 (A3.4.1) trên burst ngẫu nhiên INCR/WRAP/FIXED mọi AxSIZE.
`timescale 1ns / 1ps

module tb_axi_burst_splitter;
    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    logic        i_valid, o_ready, o_valid, i_ready, o_last, o_busy;
    logic [3:0]  i_id, o_id, i_qos, o_qos;
    logic [31:0] i_addr, o_addr;
    logic [7:0]  i_len, o_len;
    logic [2:0]  i_size;
    logic [1:0]  i_burst;

    axi_burst_splitter dut (.*);

    int checks = 0, fails = 0;
    `define CHK(c, m) begin checks++; if (!(c)) begin fails++; if (fails < 20) $display("[FAIL] %s", m); end end

    // Địa chỉ beat theo đặc tả AXI4 A3.4.1
    function automatic logic [31:0] beat_addr(input logic [31:0] start, input int sz, input int ln, input int bt, input int n);
        longint nb, al, wb, a;
        nb = 1 << sz;
        if (bt == 0) return start;
        if (n == 0) return start;
        al = (start / nb) * nb;
        a  = al + n * nb;
        if (bt == 2) begin
            wb = (start / (nb * (ln + 1))) * (nb * (ln + 1));
            if (a >= wb + nb * (ln + 1)) a = a - nb * (ln + 1);
        end
        return a[31:0];
    endfunction

    initial begin
        int bursts, chunks;
        bit done;
        bursts = 0; chunks = 0;
        i_valid = 0; i_ready = 1;
        repeat (3) @(posedge clk);
        rst_n = 1;
        for (int t = 0; t < 3000; t++) begin
            int sz, ln, bt, beat;
            logic [31:0] st;
            bt = $urandom_range(0, 2);
            sz = ($urandom_range(0, 3) == 0) ? $urandom_range(0, 2) : 3;
            if (bt == 2) ln = (1 << $urandom_range(1, 4)) - 1;
            else         ln = ($urandom_range(0, 3) == 0) ? $urandom_range(0, 255) : $urandom_range(0, 20);
            st = $urandom & 32'h00FF_FFFF;
            if (bt == 2) st = st & ~((32'd1 << sz) - 1);          // WRAP: địa chỉ đầu phải căn theo AxSIZE
            @(negedge clk);
            i_valid = 1; i_addr = st; i_len = ln; i_size = sz; i_burst = bt; i_id = t[3:0]; i_qos = t[7:4];
            do @(posedge clk); while (!o_ready);
            @(negedge clk);
            i_valid = 0;
            beat = 0;
            bursts++;
            done = 0;
            while (!done) begin
                // Đặt i_ready ở cạnh xuống; o_* chỉ đổi ở cạnh lên nên giá trị lúc này là giá trị được chuyển ở cạnh lên kế tiếp
                @(negedge clk);
                i_ready = ($urandom_range(0, 3) != 0);
                if (o_valid && i_ready) begin
                    chunks++;
                    `CHK(o_id == t[3:0] && o_qos == t[7:4], "id/qos")
                    `CHK(o_len <= 7, $sformatf("chunk len %0d > 7", o_len))
                    `CHK((o_addr >> 6) == (((o_addr >> 3) + o_len) >> 3), $sformatf("chunk crosses line addr=%h len=%0d", o_addr, o_len))
                    for (int k = 0; k <= o_len; k++) begin
                        logic [31:0] ref_a;
                        ref_a = beat_addr(st, sz, ln, bt, beat + k);
                        if (sz == 3 && bt != 0)
                            `CHK(((o_addr >> 3) + k) == (ref_a >> 3), $sformatf("t=%0d beat %0d word %h != %h", t, beat + k, (o_addr >> 3) + k, ref_a >> 3))
                        else
                            `CHK(o_len == 0 && o_addr == ref_a, $sformatf("t=%0d narrow/fixed beat %0d addr %h != %h", t, beat + k, o_addr, ref_a))
                    end
                    beat += o_len + 1;
                    `CHK(o_last == (beat == ln + 1), $sformatf("t=%0d last flag at beat %0d of %0d", t, beat, ln + 1))
                    `CHK(o_last || beat <= ln, "overrun")
                    done = o_last || beat > ln;
                end
            end
            @(negedge clk);
            i_ready = 1;
        end
        $display("[TB_SPLITTER] %0d bursts, %0d chunks", bursts, chunks);
        $display("[TB_RESULT] checks=%0d fails=%0d xfails=0", checks, fails);
        if (fails) $fatal(1, "[TESTBENCH COMPLETED WITH FAILURES]");
        $finish;
    end
endmodule
