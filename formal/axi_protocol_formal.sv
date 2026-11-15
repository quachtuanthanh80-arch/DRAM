// File: axi_protocol_formal.sv
// Chức năng: Formal wrapper kiểm chứng các bất biến bắt tay AXI4 và phản hồi đọc hữu hạn (bounded latency).

`timescale 1ns / 1ps

module axi_protocol_formal #(
    parameter int AXI_ID_WIDTH   = 4,
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 64,
    parameter int MAX_LATENCY    = 8
)(
    input logic                        clk,
    input logic                        rst_n,

    // Giao diện AXI Slave
    input logic [AXI_ID_WIDTH-1:0]     s_axi_awid,
    input logic [AXI_ADDR_WIDTH-1:0]   s_axi_awaddr,
    input logic [7:0]                  s_axi_awlen,
    input logic [2:0]                  s_axi_awsize,
    input logic [1:0]                  s_axi_awburst,
    input logic                        s_axi_awvalid,
    output logic                       s_axi_awready,

    input logic [AXI_DATA_WIDTH-1:0]   s_axi_wdata,
    input logic [AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
    input logic                        s_axi_wlast,
    input logic                        s_axi_wvalid,
    output logic                       s_axi_wready,

    output logic [AXI_ID_WIDTH-1:0]    s_axi_bid,
    output logic [1:0]                 s_axi_bresp,
    output logic                       s_axi_bvalid,
    input logic                        s_axi_bready,

    input logic [AXI_ID_WIDTH-1:0]     s_axi_arid,
    input logic [AXI_ADDR_WIDTH-1:0]   s_axi_araddr,
    input logic [7:0]                  s_axi_arlen,
    input logic [2:0]                  s_axi_arsize,
    input logic [1:0]                  s_axi_arburst,
    input logic                        s_axi_arvalid,
    output logic                       s_axi_arready,

    output logic [AXI_ID_WIDTH-1:0]    s_axi_rid,
    output logic [AXI_DATA_WIDTH-1:0]  s_axi_rdata,
    output logic [1:0]                 s_axi_rresp,
    output logic                       s_axi_rlast,
    output logic                       s_axi_rvalid,
    input logic                        s_axi_rready
);

    // Mô hình kênh con Skid Buffer đơn giản chuẩn AXI cho phản hồi đọc (R Channel)
    // Tách biệt bắt tay giữa Core xử lý nội bộ và AXI Bus Master
    logic [AXI_ID_WIDTH-1:0]   core_rid;
    logic [AXI_DATA_WIDTH-1:0] core_rdata;
    logic [1:0]                core_rresp;
    logic                      core_rlast;
    logic                      core_rvalid;
    wire                       core_rready;

    // Bộ đếm theo dõi yêu cầu đọc đang xử lý (In-flight read request tracker)
    logic [3:0] in_flight_reads;
    logic [3:0] latency_counter;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_flight_reads <= '0;
            latency_counter <= '0;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                in_flight_reads <= in_flight_reads + 1'b1;
                latency_counter <= '0;
            end else if (in_flight_reads > 0) begin
                latency_counter <= latency_counter + 1'b1;
                if (s_axi_rvalid && s_axi_rready && s_axi_rlast) begin
                    in_flight_reads <= in_flight_reads - 1'b1;
                end
            end
        end
    end

    // Giả lập sinh phản hồi từ bộ nhớ trong khoảng 1..MAX_LATENCY chu kỳ
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            core_rvalid <= 1'b0;
            core_rid    <= '0;
            core_rdata  <= '0;
            core_rresp  <= 2'b00; // OKAY
            core_rlast  <= 1'b0;
        end else begin
            if (core_rvalid && core_rready) begin
                core_rvalid <= 1'b0;
                core_rlast  <= 1'b0;
            end else if (!core_rvalid && (in_flight_reads > 0) && (latency_counter >= 4'd2)) begin
                core_rvalid <= 1'b1;
                core_rid    <= s_axi_arid;
                core_rdata  <= 64'hA5A5_5A5A_DEAD_BEEF;
                core_rresp  <= 2'b00;
                core_rlast  <= 1'b1;
            end
        end
    end

    // Skid Buffer bảo đảm: Không có bubble, và giữ VALID ổn định khi s_axi_rready = 0
    logic [AXI_ID_WIDTH+AXI_DATA_WIDTH+2+1-1:0] reg_data, skid_data;
    logic reg_valid, skid_valid;

    assign core_rready  = !skid_valid;
    assign s_axi_rvalid = reg_valid;
    assign {s_axi_rid, s_axi_rdata, s_axi_rresp, s_axi_rlast} = reg_data;

    wire [AXI_ID_WIDTH+AXI_DATA_WIDTH+2+1-1:0] core_payload = {core_rid, core_rdata, core_rresp, core_rlast};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_valid  <= 1'b0;
            skid_valid <= 1'b0;
            reg_data   <= '0;
            skid_data  <= '0;
        end else begin
            if (s_axi_rready || !reg_valid) begin
                if (skid_valid) begin
                    reg_valid  <= 1'b1;
                    reg_data   <= skid_data;
                    skid_valid <= 1'b0;
                end else begin
                    reg_valid  <= core_rvalid;
                    reg_data   <= core_payload;
                end
            end else if (core_rvalid && core_rready) begin
                skid_valid <= 1'b1;
                skid_data  <= core_payload;
            end
        end
    end

    // Slave AW, W, B stubs với bắt tay tuân thủ
    assign s_axi_awready = 1'b1;
    assign s_axi_wready  = 1'b1;
    assign s_axi_arready = (in_flight_reads == 0); // Cho phép nhận 1 request tại một thời điểm
    assign s_axi_bid     = s_axi_awid;
    assign s_axi_bresp   = 2'b00;
    assign s_axi_bvalid  = 1'b0;

`ifdef FORMAL
    initial assume (!rst_n);

    always_ff @(posedge clk) begin
        if ($past(!rst_n)) assume (rst_n);
    end

    // Ràng buộc Master: VALID một khi lên phải giữ nguyên payload tới handshake
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(s_axi_arvalid) && !$past(s_axi_arready)) begin
                assume (s_axi_arvalid);
                assume (s_axi_arid   == $past(s_axi_arid));
                assume (s_axi_araddr == $past(s_axi_araddr));
                assume (s_axi_arlen  == $past(s_axi_arlen));
            end
            if ($past(s_axi_awvalid) && !$past(s_axi_awready)) begin
                assume (s_axi_awvalid);
                assume (s_axi_awid   == $past(s_axi_awid));
                assume (s_axi_awaddr == $past(s_axi_awaddr));
                assume (s_axi_awlen  == $past(s_axi_awlen));
            end
            if ($past(s_axi_wvalid) && !$past(s_axi_wready)) begin
                assume (s_axi_wvalid);
                assume (s_axi_wdata  == $past(s_axi_wdata));
                assume (s_axi_wlast  == $past(s_axi_wlast));
            end
        end
    end

    // -------------------------------------------------------------------------
    // BẤT BIẾN GIAO THỨC AXI4 (PROVED / ASSERTED)
    // -------------------------------------------------------------------------

    // 1. Phản hồi Slave RVALID một khi lên mức 1 phải giữ nguyên dữ liệu khi rready == 0
    always_ff @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(s_axi_rvalid) && !$past(s_axi_rready)) begin
                assert (s_axi_rvalid);
                assert (s_axi_rid   == $past(s_axi_rid));
                assert (s_axi_rdata == $past(s_axi_rdata));
                assert (s_axi_rresp == $past(s_axi_rresp));
                assert (s_axi_rlast == $past(s_axi_rlast));
            end
        end
    end

    // 2. Không phát valid khi đang reset
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            assert (!s_axi_rvalid);
        end
    end

    // 3. Hoàn tất phản hồi đọc: Yêu cầu AR sau khi được chấp nhận (handshake)
    // Memory Controller phải phát RVALID trong khoảng thời gian hữu hạn
    always_ff @(posedge clk) begin
        if (rst_n) begin
            if (in_flight_reads > 0 && !s_axi_rvalid && !reg_valid && !skid_valid) begin
                assert (latency_counter <= 4'd4);
            end
        end
    end

    // -------------------------------------------------------------------------
    // COVER TRACES
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst_n) begin
            // C1: Handshake đọc hoàn tất (arvalid && arready)
            cover (s_axi_arvalid && s_axi_arready);
            // C2: Phản hồi đọc hoàn tất tới Master (rvalid && rready && rlast)
            cover (s_axi_rvalid && s_axi_rready && s_axi_rlast);
            // C3: Phản hồi bị backpressure (rvalid && !rready)
            cover (s_axi_rvalid && !s_axi_rready);
        end
    end

`endif

endmodule
