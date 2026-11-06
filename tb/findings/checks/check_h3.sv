// File: check_h3.sv
// Chức năng: Kiểm tra tái hiện finding H-3 (RREADY=0 làm lặp beat đọc do i_rready ROB nối pad và bỏ hở o_rdata_ready).

`timescale 1ns / 1ps

module check_h3;
    `include "tb_check.svh"

    localparam int AXI_ID_WIDTH   = 8;
    localparam int AXI_DATA_WIDTH = 128;
    localparam int ROB_DEPTH      = 16;
    localparam int R_PAYLOAD_W    = AXI_ID_WIDTH + AXI_DATA_WIDTH + 2 + 1;

    logic clk = 0;
    logic rst_n;
    always #2.5 clk = ~clk;

    // ROB Signals
    logic                      i_alloc_valid;
    wire                       o_alloc_ready;
    logic [AXI_ID_WIDTH-1:0]   i_alloc_id;
    logic [33:0]               i_alloc_addr;
    logic [7:0]                i_alloc_len;
    logic                      i_alloc_last;
    wire  [3:0]                o_alloc_tag;

    logic                      i_wb_valid;
    logic [3:0]                i_wb_tag;
    logic [AXI_DATA_WIDTH-1:0] i_wb_data;
    logic [1:0]                i_wb_resp;
    logic                      i_wb_last;

    wire                       rob_rvalid;
    wire  [AXI_ID_WIDTH-1:0]   rob_rid;
    wire  [AXI_DATA_WIDTH-1:0] rob_rdata;
    wire  [1:0]                rob_rresp;
    wire                       rob_rlast;

    // AXI Bus Signals
    logic                      s_axi_rready;
    wire                       s_axi_rvalid;
    wire  [AXI_ID_WIDTH-1:0]   s_axi_rid;
    wire  [AXI_DATA_WIDTH-1:0] s_axi_rdata;
    wire  [1:0]                s_axi_rresp;
    wire                       s_axi_rlast;

    wire  [R_PAYLOAD_W-1:0] r_payload_in  = {rob_rid, rob_rdata, rob_rresp, rob_rlast};
    wire  [R_PAYLOAD_W-1:0] r_payload_out;
    wire  o_rdata_ready;

    // Instantiate ROB exactly as in axi_ddr5_mc_top.sv:1078 (i_rready connected to s_axi_rready)
    reorder_buffer_rob #(
        .ROB_DEPTH     (ROB_DEPTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(34)
    ) u_rob (
        .clk                (clk),
        .rst_n              (rst_n),
        .i_alloc_valid      (i_alloc_valid),
        .o_alloc_ready      (o_alloc_ready),
        .i_alloc_id         (i_alloc_id),
        .i_alloc_addr       (i_alloc_addr),
        .i_alloc_len        (i_alloc_len),
        .i_alloc_last       (i_alloc_last),
        .o_alloc_tag        (o_alloc_tag),
        .i_wr_active_valid  (8'b0),
        .i_wr_active_addr   (272'b0),
        .o_raw_hazard       (),
        .o_raw_match_mask   (),
        .i_wb_valid         (i_wb_valid),
        .i_wb_tag           (i_wb_tag),
        .i_wb_data          (i_wb_data),
        .i_wb_resp          (i_wb_resp),
        .i_wb_last          (i_wb_last),
        .o_rvalid           (rob_rvalid),
        .o_rid              (rob_rid),
        .o_rdata            (rob_rdata),
        .o_rresp            (rob_rresp),
        .o_rlast            (rob_rlast),
        // Lỗi H-3: i_rready nối thẳng s_axi_rready ngoài pad thay vì nối o_rdata_ready của frontend skid buffer
        .i_rready           (s_axi_rready),
        .o_rob_empty        (),
        .o_rob_full         (),
        .o_rob_count        ()
    );

    // Instantiate Frontend Skid Buffer as in axi_slave_frontend.sv:258 / axi_ddr5_mc_top.sv:381
    // (o_rdata_ready is left unconnected!)
    axi4_skid_buffer #(
        .DATA_WIDTH(R_PAYLOAD_W)
    ) u_r_skid (
        .clk     (clk),
        .rst_n   (rst_n),
        .s_valid (rob_rvalid),
        .s_ready (o_rdata_ready), // axi_ddr5_mc_top.sv:381 bỏ hở (.o_rdata_ready ())
        .s_data  (r_payload_in),
        .m_valid (s_axi_rvalid),
        .m_ready (s_axi_rready),
        .m_data  (r_payload_out)
    );

    assign {s_axi_rid, s_axi_rdata, s_axi_rresp, s_axi_rlast} = r_payload_out;

    int total_beats_received = 0;
    int alloc_tag;

    initial begin
        rst_n            = 0;
        i_alloc_valid    = 0;
        i_alloc_id       = 8'h01;
        i_alloc_addr     = 34'h1000;
        i_alloc_len      = 8'd0; // 1 beat
        i_alloc_last     = 1'b1;
        i_wb_valid       = 0;
        i_wb_tag         = 0;
        i_wb_data        = 128'hCAFE_BABE_1122_3344_5566_7788_99AA_BBCC;
        i_wb_resp        = 2'b00;
        i_wb_last        = 1;
        s_axi_rready     = 0;

        #20;
        rst_n = 1;
        #10;

        // Cấp phát 1 lệnh đọc trong ROB (1 beat, len = 0)
        @(posedge clk);
        i_alloc_valid <= 1'b1;
        @(posedge clk);
        alloc_tag     = o_alloc_tag;
        i_alloc_valid <= 1'b0;

        // Ghi trả dữ liệu từ memory về ROB cho lệnh đọc này
        @(posedge clk);
        i_wb_valid <= 1'b1;
        i_wb_tag   <= alloc_tag;
        @(posedge clk);
        i_wb_valid <= 1'b0;

        // Chờ s_axi_rvalid lên
        while (!s_axi_rvalid) @(posedge clk);

        // Master giữ RREADY = 0 trong 2 chu kỳ khi RVALID đang lên
        s_axi_rready <= 1'b0;
        @(posedge clk);
        @(posedge clk);

        // Master bật RREADY = 1 để nhận dữ liệu qua nhiều chu kỳ
        repeat (6) begin
            @(posedge clk);
            s_axi_rready <= 1'b1;
            #1;
            if (s_axi_rvalid && s_axi_rready) begin
                total_beats_received++;
            end
        end
        s_axi_rready <= 1'b0;

        // Check H-3: Lệnh đọc 1 beat (len=0) chỉ được phép trả về đúng 1 beat.
        // Do lỗi nối dây ROB i_rready với pad, beat đọc bị phát lặp lại 2 lần!
        tb_check(total_beats_received == 1, "H-3: Single-beat read must return exactly 1 beat when RREADY is delayed");

        tb_report();
        $finish;
    end

endmodule
