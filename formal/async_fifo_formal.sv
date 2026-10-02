//=============================================================================
// File:        async_fifo_formal.sv
// Chức năng:   Formal verification wrapper chứng minh an toàn toán học cho FIFO bất đồng bộ async_fifo_cdc.
//=============================================================================
`timescale 1ns / 1ps

module async_fifo_formal #(
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = 3,   // Depth = 8 để tối ưu thời gian solver chứng minh
    parameter int Depth      = 1 << ADDR_WIDTH
) (
    input  logic                  wclk,
    input  logic                  wrst_n,
    input  logic                  winc,
    input  logic [DATA_WIDTH-1:0] wdata,
    output logic                  wfull,
    output logic                  walmost_full,

    input  logic                  rclk,
    input  logic                  rrst_n,
    input  logic                  rinc,
    output logic [DATA_WIDTH-1:0] rdata,
    output logic                  rempty,
    output logic                  ralmost_empty
);

    // Instantiate async FIFO DUT
    async_fifo_cdc #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DataWidth (DATA_WIDTH),
        .Depth     (Depth)
    ) dut (
        .wclk         (wclk),
        .wrst_n       (wrst_n),
        .winc         (winc),
        .wdata        (wdata),
        .wfull        (wfull),
        .walmost_full (walmost_full),

        .rclk         (rclk),
        .rrst_n       (rrst_n),
        .rinc         (rinc),
        .rdata        (rdata),
        .rempty       (rempty),
        .ralmost_empty(ralmost_empty)
    );

`ifdef FORMAL
    // Khởi tạo reset cho cả 2 miền xung nhịp
    initial begin
        assume (!wrst_n);
        assume (!rrst_n);
    end

    // Giữ reset tối thiểu 1 chu kỳ rồi nhả
    always_ff @(posedge wclk) begin
        if ($past(!wrst_n)) assume (wrst_n);
    end

    always_ff @(posedge rclk) begin
        if ($past(!rrst_n)) assume (rrst_n);
    end

    // Thuộc tính 1: Trạng thái Reset hợp lệ
    always_comb begin
        if (!wrst_n) begin
            assert (!wfull);
            assert (dut.wbin == '0);
            assert (dut.wgray == '0);
        end
        if (!rrst_n) begin
            assert (rempty);
            assert (dut.rbin == '0);
            assert (dut.rgray == '0);
        end
    end

    // Thuộc tính 2: Đơn điệu mã Gray (1-bit Hamming distance mỗi bước tăng con trỏ)
    always_ff @(posedge wclk) begin
        if (wrst_n && $past(wrst_n)) begin
            assert ($countones(dut.wgray ^ $past(dut.wgray)) <= 1);
        end
    end

    always_ff @(posedge rclk) begin
        if (rrst_n && $past(rrst_n)) begin
            assert ($countones(dut.rgray ^ $past(dut.rgray)) <= 1);
        end
    end

    // Thuộc tính 3: Chống tràn (No Overflow khi wfull = 1)
    always_ff @(posedge wclk) begin
        if (wrst_n && $past(wrst_n)) begin
            if ($past(wfull) && $past(winc)) begin
                assert (dut.wbin == $past(dut.wbin));
            end
        end
    end

    // Thuộc tính 4: Chống cạn (No Underflow khi rempty = 1)
    always_ff @(posedge rclk) begin
        if (rrst_n && $past(rrst_n)) begin
            if ($past(rempty) && $past(rinc)) begin
                assert (dut.rbin == $past(dut.rbin));
            end
        end
    end

    // Thuộc tính 5: Không thể vừa empty vừa full cùng lúc nếu reset đã nhả
    always_comb begin
        if (wrst_n && rrst_n) begin
            // Nếu con trỏ nhị phân ghi và đọc đồng bộ trùng nhau thì không thể full
            if (dut.wbin == dut.rbin_synced_in_wclk) begin
                assert (!wfull);
            end
        end
    end

    // Cover properties đo lường khả năng vươn tới trạng thái giới hạn
    always_ff @(posedge wclk) begin
        cover (wfull);
        cover (walmost_full);
    end

    always_ff @(posedge rclk) begin
        cover (rempty);
        cover (ralmost_empty);
    end
`endif

endmodule
