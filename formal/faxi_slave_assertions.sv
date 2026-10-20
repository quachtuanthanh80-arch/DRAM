// File: faxi_slave_assertions.sv
// Chức năng: Bộ thuộc tính kiểm chứng hình thức SVA cho giao diện AXI4 Slave (dựa trên ZipCPU wb2axip).
`timescale 1ns / 1ps

module faxi_slave_assertions #(
    parameter int AXI_ID_WIDTH   = 4,
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 64,
    parameter int AXI_QOS_WIDTH  = 4
) (
    input logic                        clk,
    input logic                        rst_n,

    // AW Channel
    input logic [AXI_ID_WIDTH-1:0]     awid,
    input logic [AXI_ADDR_WIDTH-1:0]   awaddr,
    input logic [7:0]                  awlen,
    input logic [2:0]                  awsize,
    input logic [1:0]                  awburst,
    input logic [AXI_QOS_WIDTH-1:0]    awqos,
    input logic                        awvalid,
    input logic                        awready,

    // W Channel
    input logic [AXI_DATA_WIDTH-1:0]   wdata,
    input logic [AXI_DATA_WIDTH/8-1:0] wstrb,
    input logic                        wlast,
    input logic                        wvalid,
    input logic                        wready,

    // B Channel
    input logic [AXI_ID_WIDTH-1:0]     bid,
    input logic [1:0]                  bresp,
    input logic                        bvalid,
    input logic                        bready,

    // AR Channel
    input logic [AXI_ID_WIDTH-1:0]     arid,
    input logic [AXI_ADDR_WIDTH-1:0]   araddr,
    input logic [7:0]                  arlen,
    input logic [2:0]                  arsize,
    input logic [1:0]                  arburst,
    input logic [AXI_QOS_WIDTH-1:0]    arqos,
    input logic                        arvalid,
    input logic                        arready,

    // R Channel
    input logic [AXI_ID_WIDTH-1:0]     rid,
    input logic [AXI_DATA_WIDTH-1:0]   rdata,
    input logic [1:0]                  rresp,
    input logic                        rlast,
    input logic                        rvalid,
    input logic                        rready
);

`ifdef FORMAL
    // Ràng buộc chu kỳ reset ban đầu
    initial assume (!rst_n);

    always_ff @(posedge clk) begin
        if ($past(!rst_n))
            assume (rst_n);
    end

    // Cơ chế bắt tay AXI4: Tín hiệu VALID một khi đã lên mức cao phải giữ nguyên
    // toàn bộ payload (địa chỉ, len, id) cho đến khi READY được đáp ứng để tránh mất mát giao dịch.
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            // Kênh ghi địa chỉ (AW)
            if ($past(awvalid) && !$past(awready)) begin
                assume (awvalid);
                assume (awid    == $past(awid));
                assume (awaddr  == $past(awaddr));
                assume (awlen   == $past(awlen));
                assume (awsize  == $past(awsize));
                assume (awburst == $past(awburst));
                assume (awqos   == $past(awqos));
            end

            // Kênh đọc địa chỉ (AR)
            if ($past(arvalid) && !$past(arready)) begin
                assume (arvalid);
                assume (arid    == $past(arid));
                assume (araddr  == $past(araddr));
                assume (arlen   == $past(arlen));
                assume (arsize  == $past(arsize));
                assume (arburst == $past(arburst));
                assume (arqos   == $past(arqos));
            end

            // Kênh dữ liệu ghi (W)
            if ($past(wvalid) && !$past(wready)) begin
                assume (wvalid);
                assume (wdata == $past(wdata));
                assume (wstrb == $past(wstrb));
                assume (wlast == $past(wlast));
            end
        end
    end

    // Ràng buộc phần cứng: Kích thước burst không được vượt quá độ rộng bus vật lý
    always_comb begin
        if (rst_n && awvalid)
            assume (awsize <= 3'($clog2(AXI_DATA_WIDTH / 8)));
        if (rst_n && arvalid)
            assume (arsize <= 3'($clog2(AXI_DATA_WIDTH / 8)));
    end

    // Ràng buộc AMBA AXI4: Giao dịch burst không được vượt qua biên 4KB để đảm bảo
    // ánh xạ MMU trang nhớ và không nhảy sai vùng nhớ DRAM.
    always_comb begin
        if (rst_n && awvalid) begin
            assume ((13'd4096 - {1'b0, awaddr[11:0]}) >= (({5'b0, awlen} + 13'd1) << awsize));
        end
        if (rst_n && arvalid) begin
            assume ((13'd4096 - {1'b0, araddr[11:0]}) >= (({5'b0, arlen} + 13'd1) << arsize));
        end
    end

    // Kiểm chứng phản hồi Slave (B & R Channel Invariance):
    // Phản hồi từ Memory Controller một khi phát ra phải ổn định cho đến khi Master nhận.
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(bvalid) && !$past(bready)) begin
                assert (bvalid);
                assert (bid   == $past(bid));
                assert (bresp == $past(bresp));
            end

            if ($past(rvalid) && !$past(rready)) begin
                assert (rvalid);
                assert (rid   == $past(rid));
                assert (rdata == $past(rdata));
                assert (rresp == $past(rresp));
                assert (rlast == $past(rlast));
            end
        end
    end

    // Trạng thái reset an toàn: Không được phát valid khi reset đang hạ
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            assert (!bvalid);
            assert (!rvalid);
        end
    end

`endif

endmodule
