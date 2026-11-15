// File: axi_protocol_sva.sv
// Chức năng: Bộ thuộc tính SVA kiểm chứng tuân thủ giao thức AMBA AXI4 (tính ổn định VALID và hoàn tất giao dịch).

`timescale 1ns / 1ps

module axi_protocol_sva #(
    parameter int AXI_ID_WIDTH   = 4,
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 64,
    parameter int MAX_LATENCY    = 16
)(
    input logic                        clk,
    input logic                        rst_n,

    // AW Channel
    input logic [AXI_ID_WIDTH-1:0]     awid,
    input logic [AXI_ADDR_WIDTH-1:0]   awaddr,
    input logic [7:0]                  awlen,
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

`ifndef SYNTHESIS
    // -------------------------------------------------------------------------
    // Cơ chế ổn định Handshake AXI4: VALID giữ nguyên mức cao và Payload không đổi
    // cho đến khi chu kỳ Handshake hoàn tất (VALID && READY)
    // -------------------------------------------------------------------------

    // 1. Kênh ghi địa chỉ (AW)
    property p_aw_stability;
        @(posedge clk) disable iff (!rst_n)
        (awvalid && !awready) |=> (awvalid && $stable(awid) && $stable(awaddr) && $stable(awlen));
    endproperty
    assert property (p_aw_stability) else $error("[SVA_AXI] AWVALID/Payload thay doi truoc handshake!");

    // 2. Kênh dữ liệu ghi (W)
    property p_w_stability;
        @(posedge clk) disable iff (!rst_n)
        (wvalid && !wready) |=> (wvalid && $stable(wdata) && $stable(wstrb) && $stable(wlast));
    endproperty
    assert property (p_w_stability) else $error("[SVA_AXI] WVALID/Payload thay doi truoc handshake!");

    // 3. Kênh đọc địa chỉ (AR)
    property p_ar_stability;
        @(posedge clk) disable iff (!rst_n)
        (arvalid && !arready) |=> (arvalid && $stable(arid) && $stable(araddr) && $stable(arlen));
    endproperty
    assert property (p_ar_stability) else $error("[SVA_AXI] ARVALID/Payload thay doi truoc handshake!");

    // 4. Kênh phản hồi ghi (B)
    property p_b_stability;
        @(posedge clk) disable iff (!rst_n)
        (bvalid && !bready) |=> (bvalid && $stable(bid) && $stable(bresp));
    endproperty
    assert property (p_b_stability) else $error("[SVA_AXI] BVALID/Payload thay doi truoc handshake!");

    // 5. Kênh dữ liệu đọc (R)
    property p_r_stability;
        @(posedge clk) disable iff (!rst_n)
        (rvalid && !rready) |=> (rvalid && $stable(rid) && $stable(rdata) && $stable(rresp) && $stable(rlast));
    endproperty
    assert property (p_r_stability) else $error("[SVA_AXI] RVALID/Payload thay doi truoc handshake!");

    // 6. Reset an toàn: Sau reset, VALID của các kênh phản hồi từ Slave phải ở mức 0
    property p_reset_val_low;
        @(posedge clk)
        !rst_n |-> (!bvalid && !rvalid);
    endproperty
    assert property (p_reset_val_low) else $error("[SVA_AXI] Valid active khi dang reset!");

    // 7. Hoàn tất phản hồi đọc trong khoảng thời gian hữu hạn N chu kỳ
    property p_ar_to_r_completion;
        @(posedge clk) disable iff (!rst_n)
        (arvalid && arready) |-> ##[1:MAX_LATENCY] (rvalid && rlast);
    endproperty
    // Bounded liveness assertion
    assert property (p_ar_to_r_completion) else $error("[SVA_AXI] Yeu cau AR khong nhan duoc RLAST trong thoi gian quy dinh!");

`endif

endmodule
