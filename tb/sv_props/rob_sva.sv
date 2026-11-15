// File: rob_sva.sv
// Chức năng: Bộ thuộc tính SVA kiểm chứng bảo toàn beat đọc ROB và loại trừ lặp beat R khi RREADY=0 (H-3).

`timescale 1ns / 1ps

module rob_sva #(
    parameter int AXI_ID_WIDTH   = 4,
    parameter int AXI_DATA_WIDTH = 64
)(
    input logic                        clk,
    input logic                        rst_n,

    // Giao diện nội bộ ROB hoàn tất (Core Retire Interface)
    input logic                        core_rvalid,
    input logic                        core_rready,
    input logic [AXI_ID_WIDTH-1:0]     core_rid,
    input logic [AXI_DATA_WIDTH-1:0]   core_rdata,
    input logic                        core_rlast,

    // Giao diện AXI Bus R-Channel (Downstream Interface)
    input logic                        axi_rvalid,
    input logic                        axi_rready,
    input logic [AXI_ID_WIDTH-1:0]     axi_rid,
    input logic [AXI_DATA_WIDTH-1:0]   axi_rdata,
    input logic [1:0]                  axi_rresp,
    input logic                        axi_rlast,

    // Trạng thái đệm Skid Buffer
    input logic                        skid_valid
);

`ifndef SYNTHESIS
    // -------------------------------------------------------------------------
    // Bất biến 1 (Finding H-3): Beat R không lặp lại khi RREADY = 0.
    // Khi AXI Slave phát RVALID mà Master chưa sẵn sàng (RREADY=0), toàn bộ
    // payload phải giữ nguyên cho đến chu kỳ bắt tay hoàn tất, không phát đúp hay rò rỉ.
    // -------------------------------------------------------------------------
    property p_no_duplicate_beat_on_backpressure;
        @(posedge clk) disable iff (!rst_n)
        (axi_rvalid && !axi_rready) |=> (axi_rvalid && $stable(axi_rdata) && $stable(axi_rid) && $stable(axi_rlast) && $stable(axi_rresp));
    endproperty
    assert property (p_no_duplicate_beat_on_backpressure)
        else $error("[SVA_ROB_H3] Beat R bi thay doi hoac phat lap khi RREADY=0!");

    // -------------------------------------------------------------------------
    // Bất biến 2: Bảo toàn số lượng beat đọc (Conservation of Read Beats)
    // Tổng số beat R được chuyển giao qua AXI phải bằng tổng số beat ROB đã hoàn tất (retire),
    // có tính đến tối đa 2 beat nằm trong thanh ghi đệm đầu ra (reg_rvalid + skid_valid).
    // -------------------------------------------------------------------------
    logic [31:0] total_core_retire_beats;
    logic [31:0] total_axi_r_beats;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            total_core_retire_beats <= '0;
            total_axi_r_beats       <= '0;
        end else begin
            if (core_rvalid && core_rready)
                total_core_retire_beats <= total_core_retire_beats + 1'b1;
            if (axi_rvalid && axi_rready)
                total_axi_r_beats       <= total_axi_r_beats + 1'b1;
        end
    end

    property p_beat_conservation;
        @(posedge clk) disable iff (!rst_n)
        total_core_retire_beats == (total_axi_r_beats + (axi_rvalid ? 32'd1 : 32'd0) + (skid_valid ? 32'd1 : 32'd0));
    endproperty
    assert property (p_beat_conservation)
        else $error("[SVA_ROB_H3] Chenh lech so beat giua ROB core retire va AXI R channel!");

    // -------------------------------------------------------------------------
    // Bất biến 3: Không phát sinh beat ảo khi ROB rỗng và không có dữ liệu
    // -------------------------------------------------------------------------
    property p_no_spurious_beat;
        @(posedge clk) disable iff (!rst_n)
        (!axi_rvalid && !core_rvalid && !skid_valid) |=> !axi_rvalid;
    endproperty
    assert property (p_no_spurious_beat)
        else $error("[SVA_ROB_H3] Phat sinh beat R ao khi khong co du lieu retire!");

`endif

endmodule
