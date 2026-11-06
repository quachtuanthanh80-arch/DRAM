// File:      tb_qos_scheduler_queue.sv
// Chức năng: Kiểm tra hàng đợi QoS: lệnh xung đột cùng địa chỉ (RAW/WAR/WAW) không bị đảo thứ tự, lệnh độc lập vẫn ưu tiên theo QoS.
`timescale 1ns / 1ps

module tb_qos_scheduler_queue;
    `include "tb_check.svh"

    localparam int NBG   = 8;
    localparam int DEPTH = 8;
    localparam int IDXW  = $clog2(DEPTH);
    localparam int ROWW  = 17;
    localparam int COLW  = 10;
    localparam int MAXN  = 1024;

    logic             clk = 0, rst_n = 0;
    logic             i_cmd_valid = 0;
    logic [3:0]       i_cmd_id = 0;
    logic             i_cmd_is_write = 0;
    logic [2:0]       i_cmd_bg = 0;
    logic [1:0]       i_cmd_bank = 0;
    logic [ROWW-1:0]  i_cmd_row = 0;
    logic [COLW-1:0]  i_cmd_col = 0;
    logic [3:0]       i_cmd_qos = 0;
    logic             o_cmd_ready;
    logic [NBG-1:0]   o_cand_valid, o_cand_is_write;
    logic [NBG*4-1:0] o_cand_id;
    logic [NBG*IDXW-1:0] o_cand_entry_idx;
    logic             gnt_valid = 0;
    logic [2:0]       gnt_bg = 0;
    logic [IDXW-1:0]  gnt_idx = 0;

    qos_scheduler_queue #(
        .AXI_ID_WIDTH(4), .AXI_QOS_WIDTH(4), .NUM_BG(NBG), .BG_WIDTH(3), .QUEUE_DEPTH(DEPTH),
        .BANK_WIDTH(2), .ROW_WIDTH(ROWW), .COL_WIDTH(COLW), .STARVATION_LIMIT(64)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .i_cmd_valid(i_cmd_valid), .i_cmd_id(i_cmd_id), .i_cmd_is_write(i_cmd_is_write), .i_cmd_bg(i_cmd_bg),
        .i_cmd_bank(i_cmd_bank), .i_cmd_row(i_cmd_row), .i_cmd_col(i_cmd_col), .i_cmd_len(8'd0), .i_cmd_qos(i_cmd_qos),
        .i_cmd_throttled(1'b0), .o_cmd_ready(o_cmd_ready),
        .o_cand_valid(o_cand_valid), .o_cand_id(o_cand_id), .o_cand_is_write(o_cand_is_write), .o_cand_bank(),
        .o_cand_row(), .o_cand_col(), .o_cand_len(), .o_cand_qos(), .o_cand_throttled(), .o_cand_starved(),
        .o_cand_entry_idx(o_cand_entry_idx),
        .i_issue_grant_valid(gnt_valid), .i_issue_grant_bg(gnt_bg), .i_issue_grant_idx(gnt_idx),
        .i_bank_free({(NBG*4){1'b1}})
    );

    always #1.25 clk = ~clk;

    // Mô hình tham chiếu: mỗi lệnh có số thứ tự; ID = seq mod 16 chỉ dùng để nhận diện lệnh khi được cấp.
    int  m_bg [MAXN], m_addr [MAXN];
    bit  m_wr [MAXN], m_pending [MAXN];
    int  slot_seq [NBG][DEPTH];
    int  n_enq, hazard_err;
    int  issue_log [$];

    task automatic reset_dut();
        rst_n = 0;
        i_cmd_valid = 0;
        gnt_valid = 0;
        n_enq = 0;
        hazard_err = 0;
        issue_log.delete();
        for (int i = 0; i < MAXN; i++) m_pending[i] = 0;
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
    endtask

    // addr mã hóa {bank, row, col}; nạp đến khi hàng đợi BG nhận.
    task automatic enq(input int bg, input int addr, input bit wr, input int qos);
        int slot;
        i_cmd_valid    <= 1;
        i_cmd_bg       <= bg;
        i_cmd_bank     <= addr[29:28];
        i_cmd_row      <= addr[27:10];
        i_cmd_col      <= addr[9:0];
        i_cmd_is_write <= wr;
        i_cmd_qos      <= qos;
        i_cmd_id       <= n_enq % 16;
        do begin
            #0.1;
            slot = -1;
            for (int e = 0; e < DEPTH; e++)
                if (slot < 0 && !dut.q_valid[bg * DEPTH + e]) slot = e;
            @(posedge clk);
        end while (!o_cmd_ready);
        slot_seq[bg][slot] = n_enq;
        m_bg[n_enq] = bg;
        m_addr[n_enq] = addr;
        m_wr[n_enq] = wr;
        m_pending[n_enq] = 1;
        n_enq++;
        i_cmd_valid <= 0;
    endtask

    // Cấp đúng ứng viên hàng đợi đưa ra cho BG; kiểm tra không còn lệnh cũ hơn xung đột cùng địa chỉ đang chờ.
    task automatic grant(input int bg);
        int idx, seq;
        #0.1;
        // Ứng viên được đăng ký và bị che một chu kỳ sau mỗi grant cùng BG: chờ tối đa vài chu kỳ
        for (int w = 0; w < 3 && !o_cand_valid[bg]; w++) begin
            @(posedge clk);
            #0.1;
        end
        if (!o_cand_valid[bg]) begin
            @(posedge clk);
        end else begin
            idx = o_cand_entry_idx[bg*IDXW +: IDXW];
            seq = slot_seq[bg][idx];
            for (int o = 0; o < seq; o++) begin
                if (m_pending[o] && m_bg[o] == bg && m_addr[o] == m_addr[seq] && (m_wr[o] || m_wr[seq])) begin
                    hazard_err++;
                    if (hazard_err <= 5)
                        $display("  [DIAG] seq %0d (%s) issued before older conflicting seq %0d (%s) addr 0x%0h",
                                 seq, m_wr[seq] ? "WR" : "RD", o, m_wr[o] ? "WR" : "RD", m_addr[seq]);
                end
            end
            m_pending[seq] = 0;
            issue_log.push_back(seq);
            gnt_valid <= 1;
            gnt_bg    <= bg;
            gnt_idx   <= idx;
            @(posedge clk);
            gnt_valid <= 0;
        end
    endtask

    task automatic pair_test(input string name, input bit wr0, input int q0, input bit wr1, input int q1,
                             input int addr1, input bit expect_in_order);
        reset_dut();
        enq(2, 32'h0012_3456, wr0, q0);
        enq(2, addr1,         wr1, q1);
        @(posedge clk);
        grant(2);
        grant(2);
        if (expect_in_order)
            tb_check(issue_log.size() == 2 && issue_log[0] == 0 && hazard_err == 0,
                     $sformatf("%s: older conflicting command issued first (order %0d,%0d)", name, issue_log[0], issue_log[1]));
        else
            tb_check(issue_log.size() == 2 && issue_log[0] == 1,
                     $sformatf("%s: independent high-QoS command still bypasses (order %0d,%0d)", name, issue_log[0], issue_log[1]));
    endtask

    initial begin
        $display("[TEST 1] Directed same-address hazards and QoS controls");
        pair_test("RAW write(QoS0)->read(QoS15) same addr", 1, 0, 0, 15, 32'h0012_3456, 1);
        pair_test("WAR read(QoS0)->write(QoS15) same addr", 0, 0, 1, 15, 32'h0012_3456, 1);
        pair_test("WAW write(QoS0)->write(QoS15) same addr", 1, 0, 1, 15, 32'h0012_3456, 1);
        pair_test("Control: write(QoS0)->read(QoS15) different col", 1, 0, 0, 15, 32'h0012_3457, 0);
        pair_test("Control: read(QoS0)->read(QoS15) same addr (RAR may reorder)", 0, 0, 0, 15, 32'h0012_3456, 0);

        // T2: ngẫu nhiên: 600 lệnh, 4 địa chỉ/BG trên 3 BG, QoS ngẫu nhiên, cấp ngẫu nhiên theo BG.
        reset_dut();
        $display("[TEST 2] Constrained-random mixed read/write stream, 4 hot addresses per BG");
        fork
            begin
                for (int n = 0; n < 600; n++)
                    enq($urandom_range(0, 2), 32'h0040_0000 + $urandom_range(0, 3), $urandom_range(0, 1), $urandom_range(0, 15));
            end
            begin
                repeat (6000) begin
                    if ($urandom_range(0, 2) == 0) grant($urandom_range(0, 2));
                    else @(posedge clk);
                end
            end
        join
        while (|o_cand_valid[2:0]) begin
            for (int b = 0; b < 3; b++) grant(b);
        end
        tb_check(issue_log.size() == 600, $sformatf("T2 all 600 commands issued (%0d)", issue_log.size()));
        tb_check(hazard_err == 0, $sformatf("T2 no same-address RAW/WAR/WAW reordering (%0d violations)", hazard_err));

        tb_report();
        $finish;
    end

    initial begin
        #5_000_000;
        $display("[FAIL] watchdog timeout");
        tb_report();
        $finish;
    end
endmodule
