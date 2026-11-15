// File: rob_retire_formal.sv
// Chức năng: Formal wrapper kiểm chứng bảo toàn beat đọc ROB và loại trừ lặp beat R khi RREADY=0 (Finding H-3).

`timescale 1ns / 1ps

module rob_retire_formal #(
    parameter int AXI_ID_WIDTH   = 4,
    parameter int AXI_DATA_WIDTH = 64
)(
    input  logic                      clk,
    input  logic                      rst_n,

    // Giao diện nội bộ ROB hoàn tất
    input  logic                      core_rvalid,
    input  logic [AXI_ID_WIDTH-1:0]   core_rid,
    input  logic [AXI_DATA_WIDTH-1:0] core_rdata,
    input  logic [1:0]                core_rresp,
    input  logic                      core_rlast,
    output logic                      core_rready,

    // Giao diện AXI Bus R-Channel
    output logic                      o_rvalid,
    output logic [AXI_ID_WIDTH-1:0]   o_rid,
    output logic [AXI_DATA_WIDTH-1:0] o_rdata,
    output logic [1:0]                o_rresp,
    output logic                      o_rlast,
    input  logic                      i_rready
);

    // Kích thước Payload
    localparam int R_PAYLOAD_W = AXI_ID_WIDTH + AXI_DATA_WIDTH + 2 + 1;

    wire [R_PAYLOAD_W-1:0] core_payload = {core_rid, core_rdata, core_rresp, core_rlast};
    logic [R_PAYLOAD_W-1:0] out_payload;

    logic                   skid_valid;
    logic [R_PAYLOAD_W-1:0] skid_payload;
    logic                   reg_rvalid;

    // Cơ chế Zero-Bubble Skid Buffer chuẩn trong reorder_buffer_rob.sv (H-3 fix)
    assign core_rready = !skid_valid;
    assign o_rvalid    = reg_rvalid;
    assign {o_rid, o_rdata, o_rresp, o_rlast} = out_payload;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_rvalid   <= 1'b0;
            out_payload  <= '0;
            skid_valid   <= 1'b0;
            skid_payload <= '0;
        end else begin
            if (i_rready || !reg_rvalid) begin
                if (skid_valid) begin
                    reg_rvalid   <= 1'b1;
                    out_payload  <= skid_payload;
                    skid_valid   <= 1'b0;
                end else begin
                    reg_rvalid   <= core_rvalid;
                    out_payload  <= core_payload;
                end
            end else if (core_rvalid && core_rready) begin
                skid_valid   <= 1'b1;
                skid_payload <= core_payload;
            end
        end
    end

    // Theo dõi số lượng beat retire và số lượng beat AXI hoàn tất
    logic [7:0] total_retire_beats;
    logic [7:0] total_axi_beats;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            total_retire_beats <= '0;
            total_axi_beats    <= '0;
        end else begin
            if (core_rvalid && core_rready)
                total_retire_beats <= total_retire_beats + 8'd1;
            if (o_rvalid && i_rready)
                total_axi_beats    <= total_axi_beats + 8'd1;
        end
    end

`ifdef FORMAL
    initial assume (!rst_n);

    always_ff @(posedge clk) begin
        if ($past(!rst_n)) assume (rst_n);
    end

    // -------------------------------------------------------------------------
    // BẤT BIẾN FORMAL
    // -------------------------------------------------------------------------

    // Bất biến 1 (Finding H-3): Khi AXI phát RVALID và RREADY=0, dữ liệu không bị thay đổi hoặc lặp
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(o_rvalid) && !$past(i_rready)) begin
                assert (o_rvalid);
                assert (o_rid   == $past(o_rid));
                assert (o_rdata == $past(o_rdata));
                assert (o_rresp == $past(o_rresp));
                assert (o_rlast == $past(o_rlast));
            end
        end
    end

    // Bất biến 2: Bảo toàn số beat (số beat R == số beat ROB retire)
    always_ff @(posedge clk) begin
        if (rst_n) begin
            assert (total_retire_beats == (total_axi_beats + (reg_rvalid ? 8'd1 : 8'd0) + (skid_valid ? 8'd1 : 8'd0)));
        end
    end

    // Bất biến 3: Reset an toàn (không có dữ liệu hợp lệ trong reset)
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            assert (!o_rvalid);
            assert (!skid_valid);
            assert (core_rready);
        end
    end

    // -------------------------------------------------------------------------
    // COVER TRACES
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst_n) begin
            // C1: Beat hoàn tất bình thường (o_rvalid && i_rready)
            cover (o_rvalid && i_rready);
            // C2: Backpressure xảy ra (o_rvalid && !i_rready)
            cover (o_rvalid && !i_rready);
            // C3: Skid buffer được lấp đầy (skid_valid == 1)
            cover (skid_valid);
            // C4: Thoát backpressure và xả skid buffer (skid_valid chuyển từ 1 về 0)
            cover ($past(skid_valid) && !skid_valid && i_rready);
        end
    end

`endif

endmodule
