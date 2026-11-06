// File:      tb_reorder_buffer_rob.sv
// Chức năng: Kiểm tra ROB: thứ tự AXI theo từng ID, ID khác nhau không chặn nhau, toàn vẹn dữ liệu dưới writeback ngẫu nhiên và backpressure R.
`timescale 1ns / 1ps

module tb_reorder_buffer_rob;
    `include "tb_check.svh"

    localparam int IDW    = 4;
    localparam int DW     = 64;
    localparam int DEPTH  = 16;
    localparam int PTRW   = $clog2(DEPTH);
    localparam int BEATS  = 8;
    localparam int MAXREQ = 512;

    logic            clk = 0, rst_n = 0;
    logic            i_alloc_valid = 0;
    logic [IDW-1:0]  i_alloc_id = 0;
    logic [31:0]     i_alloc_addr = 0;
    logic [7:0]      i_alloc_len = 0;
    logic            o_alloc_ready;
    logic [PTRW-1:0] o_alloc_tag;
    logic            i_wb_valid = 0;
    logic [PTRW-1:0] i_wb_tag = 0;
    logic [DW-1:0]   i_wb_data = 0;
    logic            i_wb_last = 0;
    logic            o_rvalid, o_rlast;
    logic [IDW-1:0]  o_rid;
    logic [DW-1:0]   o_rdata;
    logic [1:0]      o_rresp;
    logic            i_rready = 1;
    logic            o_rob_empty;

    reorder_buffer_rob #(
        .AXI_ID_WIDTH(IDW), .AXI_DATA_WIDTH(DW), .ROB_DEPTH(DEPTH), .MAX_BURST_BEATS(BEATS), .MAX_WR_TRACK(8)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .i_alloc_valid(i_alloc_valid), .i_alloc_id(i_alloc_id), .i_alloc_addr(i_alloc_addr), .i_alloc_len(i_alloc_len),
        .o_alloc_ready(o_alloc_ready), .o_alloc_tag(o_alloc_tag),
        .i_wr_active_valid(8'd0), .i_wr_active_addr(256'd0), .o_raw_hazard(), .o_raw_match_mask(),
        .i_wb_valid(i_wb_valid), .i_wb_tag(i_wb_tag), .i_wb_data(i_wb_data), .i_wb_resp(2'b00), .i_wb_last(i_wb_last),
        .o_rvalid(o_rvalid), .o_rid(o_rid), .o_rdata(o_rdata), .o_rresp(o_rresp), .o_rlast(o_rlast), .i_rready(i_rready),
        .o_rob_empty(o_rob_empty), .o_rob_full(), .o_rob_count()
    );

    always #1.25 clk = ~clk;

    // Mô hình tham chiếu: mỗi request mang số thứ tự toàn cục; dữ liệu beat = {A5, seq, beat, id} để phát hiện lẫn/đảo.
    int req_id  [MAXREQ];
    int req_len [MAXREQ];
    int seq_tag [MAXREQ];
    int tag_seq [DEPTH];
    int exp_q   [16][MAXREQ];   // hàng đợi seq dự kiến theo từng ID (con trỏ đầu/cuối riêng)
    int exp_h   [16];
    int exp_t   [16];
    int next_seq;
    int pend [DEPTH];
    int npend;
    int retired, order_err, data_err, interleave_err, tag_err;
    int cur_beat, cur_seq, first_done_seq;

    function automatic logic [DW-1:0] beat_data(int seq, int beat, int id);
        return {8'hA5, 24'(seq), 16'(beat), 16'(id)};
    endfunction

    // Bộ giám sát kênh R: kiểm tra thứ tự trong cùng ID, dữ liệu từng beat và không xen kẽ beat giữa các burst.
    always @(posedge clk) begin
        if (rst_n && o_rvalid && i_rready) begin
            int id;
            id = o_rid;
            if (cur_beat == 0) begin
                if (exp_h[id] == exp_t[id]) begin
                    order_err++;
                    cur_seq = -1;
                    $display("  [DIAG] unexpected R beat for ID %0d", id);
                end else begin
                    cur_seq = exp_q[id][exp_h[id]];
                    exp_h[id]++;
                end
            end
            if (cur_seq >= 0) begin
                if (o_rdata !== beat_data(cur_seq, cur_beat, id)) begin
                    if (o_rdata[55:32] != 24'(cur_seq)) interleave_err++;
                    data_err++;
                    $display("  [DIAG] R data mismatch ID %0d seq %0d beat %0d: got %h", id, cur_seq, cur_beat, o_rdata);
                end
                if (o_rlast !== (cur_beat == req_len[cur_seq])) begin
                    data_err++;
                    $display("  [DIAG] RLAST wrong ID %0d seq %0d beat %0d", id, cur_seq, cur_beat);
                end
            end
            if (o_rlast) begin
                if (first_done_seq < 0) first_done_seq = cur_seq;
                retired++;
                cur_beat = 0;
            end else begin
                cur_beat++;
            end
        end
    end

    // Giữ valid tới khi ROB thật sự nhận (ready lấy mẫu sau khi NBA của cạnh trước đã cập nhật).
    task automatic alloc(input int id, input int len, output int tag);
        bit acc;
        i_alloc_valid <= 1;
        i_alloc_id    <= id;
        i_alloc_len   <= len;
        i_alloc_addr  <= 32'h1000 * next_seq;
        do begin
            #0.1;
            acc = o_alloc_ready;
            tag = o_alloc_tag;
            @(posedge clk);
        end while (!acc);
        // Slot được cấp không được trùng một request còn chờ writeback.
        for (int i = 0; i < npend; i++)
            if (pend[i] == tag) begin
                tag_err++;
                $display("  [DIAG] ROB reissued tag %0d still awaiting writeback", tag);
            end
        tag_seq[tag]      = next_seq;
        seq_tag[next_seq] = tag;
        req_id[next_seq]  = id;
        req_len[next_seq] = len;
        exp_q[id][exp_t[id]] = next_seq;
        exp_t[id]++;
        next_seq++;
        i_alloc_valid <= 0;
    endtask

    task automatic writeback(input int tag);
        int seq;
        seq = tag_seq[tag];
        for (int b = 0; b <= req_len[seq]; b++) begin
            i_wb_valid <= 1;
            i_wb_tag   <= tag;
            i_wb_data  <= beat_data(seq, b, req_id[seq]);
            i_wb_last  <= (b == req_len[seq]);
            @(posedge clk);
        end
        i_wb_valid <= 0;
        i_wb_last  <= 0;
    endtask

    task automatic reset_dut();
        rst_n = 0;
        i_alloc_valid = 0;
        i_wb_valid = 0;
        i_rready = 1;
        for (int i = 0; i < 16; i++) begin
            exp_h[i] = 0;
            exp_t[i] = 0;
        end
        npend = 0;
        next_seq = 0;
        cur_beat = 0; cur_seq = -1; first_done_seq = -1;
        retired = 0; order_err = 0; data_err = 0; interleave_err = 0; tag_err = 0;
        repeat (3) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);
    endtask

    task automatic wait_retired(input int n, input int max_cycles);
        int c;
        c = 0;
        while (retired < n && c < max_cycles) begin
            @(posedge clk);
            c++;
        end
    endtask

    task automatic writeback_random_pending();
        int k;
        k = $urandom_range(0, npend - 1);
        writeback(pend[k]);
        pend[k] = pend[npend - 1];
        npend--;
    endtask

    initial begin
        int t0, t1, t2, cyc;

        // T1 (R18): ID khác nhau phải vượt được entry cũ hơn đang chờ DRAM.
        reset_dut();
        $display("[TEST 1] Different IDs are not blocked by an older pending read");
        alloc(1, 3, t0);
        alloc(2, 0, t1);
        writeback(t1);
        cyc = 0;
        while (retired == 0 && cyc < 20) begin @(posedge clk); cyc++; end
        tb_check(retired == 1 && first_done_seq == 1,
                 $sformatf("T1 younger ID 2 retired while older ID 1 waits for DRAM (%0d cycles)", cyc));
        writeback(t0);
        wait_retired(2, 50);
        tb_check(retired == 2 && order_err == 0 && data_err == 0, "T1 older ID 1 retired afterwards with correct data");

        // T2: cùng ID phải giữ thứ tự AXI dù DRAM trả về đảo ngược.
        reset_dut();
        $display("[TEST 2] Same ID keeps AXI order under reversed DRAM return");
        alloc(3, 1, t0);
        alloc(3, 2, t1);
        alloc(3, 0, t2);
        writeback(t2);
        writeback(t1);
        repeat (10) @(posedge clk);
        tb_check(retired == 0, $sformatf("T2 no same-ID read overtakes the oldest one (%0d retired early)", retired));
        writeback(t0);
        wait_retired(3, 60);
        tb_check(retired == 3 && order_err == 0 && data_err == 0, "T2 three same-ID reads retired in issue order");

        // T3: ngẫu nhiên có ràng buộc: 400 request, 4 ID, độ dài 1..4 beat, writeback đảo thứ tự, RREADY ngẫu nhiên.
        reset_dut();
        $display("[TEST 3] Constrained-random OoO writeback with R backpressure");
        npend = 0;
        fork
            begin
                bit alloc_done;
                alloc_done = 0;
                // DRAM trả dữ liệu độc lập với cấp phát: hai luồng chạy song song như phần cứng thật.
                fork
                    begin
                        for (int n = 0; n < 400; n++) begin
                            int tg;
                            alloc($urandom_range(0, 3) * 4 + 1, $urandom_range(0, 3), tg);
                            pend[npend] = tg;
                            npend++;
                            repeat ($urandom_range(0, 2)) @(posedge clk);
                        end
                        alloc_done = 1;
                    end
                    begin
                        while (!alloc_done || npend > 0) begin
                            if (npend > 0 && $urandom_range(0, 2) == 0) writeback_random_pending();
                            else @(posedge clk);
                        end
                    end
                join
            end
            begin
                forever begin
                    @(posedge clk);
                    i_rready <= ($urandom_range(0, 3) != 0);
                end
            end
        join_any
        disable fork;
        i_rready <= 1;
        wait_retired(400, 2000);
        tb_check(retired == 400, $sformatf("T3 all 400 random reads retired (%0d)", retired));
        tb_check(order_err == 0, $sformatf("T3 per-ID AXI ordering preserved (%0d violations)", order_err));
        tb_check(data_err == 0 && interleave_err == 0,
                 $sformatf("T3 every beat carries its own data, no burst interleaving (%0d data, %0d interleave errors)", data_err, interleave_err));
        tb_check(tag_err == 0, $sformatf("T3 no tag reissued while awaiting writeback (%0d)", tag_err));
        tb_check(o_rob_empty, "T3 ROB drains to empty");

        tb_report();
        $finish;
    end

    initial begin
        #2_000_000;
        $display("[FAIL] watchdog timeout");
        tb_report();
        $finish;
    end
endmodule
