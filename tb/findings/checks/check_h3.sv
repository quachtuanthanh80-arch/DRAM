// File: check_h3.sv
// Chức năng: Tái hiện Finding H-3 trên đường chính axi_ddr5_mc_top với RREADY ngẫu nhiên có seed.
`timescale 1ns / 1ps

module check_h3;
    `include "tb_check.svh"

    localparam int AXI_ID_WIDTH   = 4;
    localparam int AXI_ADDR_WIDTH = 32;
    localparam int AXI_DATA_WIDTH = 64;
    localparam int AXI_STRB_WIDTH = 8;
    localparam int AXI_LEN_WIDTH  = 8;
    localparam int AXI_QOS_WIDTH  = 4;
    localparam int BG_COUNT       = 8;
    localparam int BG_WIDTH       = 3;
    localparam int BANK_COUNT     = 4;
    localparam int BANK_WIDTH     = 2;
    localparam int ROW_WIDTH      = 17;
    localparam int COL_WIDTH      = 10;
    localparam int ROB_DEPTH      = 16;

    logic clk_axi = 1'b0;
    always #2.0 clk_axi = ~clk_axi;

    logic clk_ddr = 1'b0;
    always #1.25 clk_ddr = ~clk_ddr;

    logic aresetn_axi;
    logic aresetn_ddr;

    logic [AXI_ID_WIDTH-1:0]   s_axi_awid;
    logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr;
    logic [AXI_LEN_WIDTH-1:0]  s_axi_awlen;
    logic [2:0]                s_axi_awsize;
    logic [1:0]                s_axi_awburst;
    logic [AXI_QOS_WIDTH-1:0]  s_axi_awqos;
    logic                      s_axi_awvalid;
    logic                      s_axi_awready;

    logic [AXI_DATA_WIDTH-1:0] s_axi_wdata;
    logic [AXI_STRB_WIDTH-1:0] s_axi_wstrb;
    logic                      s_axi_wlast;
    logic                      s_axi_wvalid;
    logic                      s_axi_wready;

    logic [AXI_ID_WIDTH-1:0]   s_axi_bid;
    logic [1:0]                s_axi_bresp;
    logic                      s_axi_bvalid;
    logic                      s_axi_bready;

    logic [AXI_ID_WIDTH-1:0]   s_axi_arid;
    logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr;
    logic [AXI_LEN_WIDTH-1:0]  s_axi_arlen;
    logic [2:0]                s_axi_arsize;
    logic [1:0]                s_axi_arburst;
    logic [AXI_QOS_WIDTH-1:0]  s_axi_arqos;
    logic                      s_axi_arvalid;
    logic                      s_axi_arready;

    logic [AXI_ID_WIDTH-1:0]   s_axi_rid;
    logic [AXI_DATA_WIDTH-1:0] s_axi_rdata;
    logic [1:0]                s_axi_rresp;
    logic                      s_axi_rlast;
    logic                      s_axi_rvalid;
    logic                      s_axi_rready;

    logic [2:0]                dfi_cmd;
    logic [BG_WIDTH-1:0]       dfi_bg;
    logic [BANK_WIDTH-1:0]     dfi_bank;
    logic [ROW_WIDTH-1:0]      dfi_row;
    logic [COL_WIDTH-1:0]      dfi_col;
    logic [7:0]                dfi_len;
    logic                      dfi_wrdata_en;
    logic [63:0]               dfi_wrdata;
    logic [7:0]                dfi_wrdata_mask;
    logic [7:0]                dfi_wrdata_ecc;
    logic                      dfi_rddata_valid;
    logic [63:0]               dfi_rddata;
    logic [7:0]                dfi_rddata_ecc;

    axi_ddr5_mc_top #(
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_LEN_WIDTH  (AXI_LEN_WIDTH),
        .AXI_QOS_WIDTH  (AXI_QOS_WIDTH),
        .BG_COUNT       (BG_COUNT),
        .BANK_COUNT     (BANK_COUNT),
        .ROW_WIDTH      (ROW_WIDTH),
        .COL_WIDTH      (COL_WIDTH),
        .ROB_DEPTH      (ROB_DEPTH),
        .DFI_RDLAT      (8),
        .TCK_PS         (4000)
    ) dut (
        .clk_axi             (clk_axi),
        .aresetn_axi         (aresetn_axi),
        .clk_ddr             (clk_ddr),
        .aresetn_ddr         (aresetn_ddr),
        .s_axi_awid          (s_axi_awid),
        .s_axi_awaddr        (s_axi_awaddr),
        .s_axi_awlen         (s_axi_awlen),
        .s_axi_awsize        (s_axi_awsize),
        .s_axi_awburst       (s_axi_awburst),
        .s_axi_awqos         (s_axi_awqos),
        .s_axi_awvalid       (s_axi_awvalid),
        .s_axi_awready       (s_axi_awready),
        .s_axi_wdata         (s_axi_wdata),
        .s_axi_wstrb         (s_axi_wstrb),
        .s_axi_wlast         (s_axi_wlast),
        .s_axi_wvalid        (s_axi_wvalid),
        .s_axi_wready        (s_axi_wready),
        .s_axi_bid           (s_axi_bid),
        .s_axi_bresp         (s_axi_bresp),
        .s_axi_bvalid        (s_axi_bvalid),
        .s_axi_bready        (s_axi_bready),
        .s_axi_arid          (s_axi_arid),
        .s_axi_araddr        (s_axi_araddr),
        .s_axi_arlen         (s_axi_arlen),
        .s_axi_arsize        (s_axi_arsize),
        .s_axi_arburst       (s_axi_arburst),
        .s_axi_arqos         (s_axi_arqos),
        .s_axi_arvalid       (s_axi_arvalid),
        .s_axi_arready       (s_axi_arready),
        .s_axi_rid           (s_axi_rid),
        .s_axi_rdata         (s_axi_rdata),
        .s_axi_rresp         (s_axi_rresp),
        .s_axi_rlast         (s_axi_rlast),
        .s_axi_rvalid        (s_axi_rvalid),
        .s_axi_rready        (s_axi_rready),
        .dfi_cmd             (dfi_cmd),
        .dfi_bg              (dfi_bg),
        .dfi_bank            (dfi_bank),
        .dfi_row             (dfi_row),
        .dfi_col             (dfi_col),
        .dfi_len             (dfi_len),
        .dfi_wrdata_en       (dfi_wrdata_en),
        .dfi_wrdata          (dfi_wrdata),
        .dfi_wrdata_mask     (dfi_wrdata_mask),
        .dfi_wrdata_ecc      (dfi_wrdata_ecc),
        .dfi_rddata_valid    (dfi_rddata_valid),
        .dfi_rddata          (dfi_rddata),
        .dfi_rddata_ecc      (dfi_rddata_ecc),
        .cfg_is_ddr5         (1'b1),
        .cfg_dual_hash_en    (1'b1),
        .cfg_rh_threshold    (16'd500),
        .cfg_window_size     (16'd1000),
        .o_throttled_events  (),
        .o_ecc_single_err_cnt(),
        .o_ecc_double_err_cnt()
    );

    dram_model #(.COL_W(COL_WIDTH), .RL(8), .WL(9)) u_dram (
        .clk          (clk_axi),
        .rst_n        (aresetn_axi),
        .cmd          (dfi_cmd),
        .bg           (dfi_bg),
        .bank         (dfi_bank),
        .row          (dfi_row),
        .col          (dfi_col),
        .len          (dfi_len),
        .wrdata_en    (dfi_wrdata_en),
        .wrdata       (dfi_wrdata),
        .wrdata_mask  (dfi_wrdata_mask),
        .wrdata_ecc   (dfi_wrdata_ecc),
        .rddata_valid (dfi_rddata_valid),
        .rddata       (dfi_rddata),
        .rddata_ecc   (dfi_rddata_ecc)
    );

    // Bộ tạo RREADY ngẫu nhiên có seed (LFSR 32-bit)
    logic        rand_rready_en;
    logic [31:0] rready_lfsr;
    always_ff @(posedge clk_axi or negedge aresetn_axi) begin
        if (!aresetn_axi) begin
            rready_lfsr  <= 32'hA5A5_1357;
            s_axi_rready <= 1'b1;
        end else if (rand_rready_en) begin
            rready_lfsr  <= {rready_lfsr[30:0], rready_lfsr[31] ^ rready_lfsr[21] ^ rready_lfsr[1] ^ rready_lfsr[0]};
            s_axi_rready <= rready_lfsr[0];
        end else begin
            s_axi_rready <= 1'b1;
        end
    end

    // Đếm beat R thu được ở cổng AXI và beat ROB thật sự retire
    int r_beats_received;
    int rob_beats_retired;
    int r_rlast_cnt;
    int r_data_mismatch;
    int cur_burst_idx;
    int cur_beat_in_burst;

    function automatic logic [63:0] exp_beat_data(input int burst_i, input int beat_i);
        return 64'hC300_0000_0000_0000 | (64'(burst_i) << 16) | 64'(beat_i);
    endfunction

    always_ff @(posedge clk_axi or negedge aresetn_axi) begin
        if (!aresetn_axi) begin
            r_beats_received  <= 0;
            rob_beats_retired <= 0;
            r_rlast_cnt       <= 0;
            r_data_mismatch   <= 0;
            cur_burst_idx     <= 0;
            cur_beat_in_burst <= 0;
        end else begin
            if (dut.u_rob.o_rvalid && dut.u_rob.i_rready)
                rob_beats_retired <= rob_beats_retired + 1;

            if (s_axi_rvalid && s_axi_rready) begin
                r_beats_received <= r_beats_received + 1;
                if (s_axi_rdata !== exp_beat_data(cur_burst_idx, cur_beat_in_burst) ||
                    s_axi_rid   !== AXI_ID_WIDTH'(cur_burst_idx + 1)) begin
                    r_data_mismatch <= r_data_mismatch + 1;
                end
                if (s_axi_rlast) begin
                    r_rlast_cnt       <= r_rlast_cnt + 1;
                    cur_burst_idx     <= cur_burst_idx + 1;
                    cur_beat_in_burst <= 0;
                end else begin
                    cur_beat_in_burst <= cur_beat_in_burst + 1;
                end
            end
        end
    end

    task automatic write_burst4(
        input logic [AXI_ID_WIDTH-1:0]   id,
        input logic [AXI_ADDR_WIDTH-1:0] addr,
        input int                        burst_i
    );
        @(negedge clk_axi);
        s_axi_awid    <= id;
        s_axi_awaddr  <= addr;
        s_axi_awlen   <= 8'd3; // 4 beats
        s_axi_awsize  <= 3'b011;
        s_axi_awburst <= 2'b01;
        s_axi_awqos   <= 4'd2;
        s_axi_awvalid <= 1'b1;
        while (!s_axi_awready) @(posedge clk_axi);
        @(negedge clk_axi);
        s_axi_awvalid <= 1'b0;

        for (int b = 0; b < 4; b++) begin
            s_axi_wdata  <= exp_beat_data(burst_i, b);
            s_axi_wstrb  <= 8'hFF;
            s_axi_wlast  <= (b == 3);
            s_axi_wvalid <= 1'b1;
            while (!s_axi_wready) @(posedge clk_axi);
            @(negedge clk_axi);
        end
        s_axi_wvalid <= 1'b0;
        s_axi_wlast  <= 1'b0;

        while (!s_axi_bvalid) @(posedge clk_axi);
        @(posedge clk_axi);
    endtask

    task automatic read_burst4(
        input logic [AXI_ID_WIDTH-1:0]   id,
        input logic [AXI_ADDR_WIDTH-1:0] addr
    );
        @(negedge clk_axi);
        s_axi_arid    <= id;
        s_axi_araddr  <= addr;
        s_axi_arlen   <= 8'd3; // 4 beats
        s_axi_arsize  <= 3'b011;
        s_axi_arburst <= 2'b01;
        s_axi_arqos   <= 4'd2;
        s_axi_arvalid <= 1'b1;
        while (!s_axi_arready) @(posedge clk_axi);
        @(negedge clk_axi);
        s_axi_arvalid <= 1'b0;
    endtask

    initial begin
        aresetn_axi    = 1'b0;
        aresetn_ddr    = 1'b0;
        rand_rready_en = 1'b0;
        s_axi_awid     = '0;
        s_axi_awaddr   = '0;
        s_axi_awlen    = '0;
        s_axi_awsize   = 3'b011;
        s_axi_awburst  = 2'b01;
        s_axi_awqos    = '0;
        s_axi_awvalid  = 1'b0;
        s_axi_wdata    = '0;
        s_axi_wstrb    = '0;
        s_axi_wlast    = 1'b0;
        s_axi_wvalid   = 1'b0;
        s_axi_bready   = 1'b1;
        s_axi_arid     = '0;
        s_axi_araddr   = '0;
        s_axi_arlen    = '0;
        s_axi_arsize   = 3'b011;
        s_axi_arburst  = 2'b01;
        s_axi_arqos    = '0;
        s_axi_arvalid  = 1'b0;

        repeat (10) @(posedge clk_axi);
        @(negedge clk_axi);
        aresetn_axi = 1'b1;
        aresetn_ddr = 1'b1;
        repeat (10) @(posedge clk_axi);

        // Ghi trước 4 burst 4-beat vào 4 BG khác nhau
        for (int i = 0; i < 4; i++) begin
            write_burst4(AXI_ID_WIDTH'(i + 1), 32'h0001_0000 + (i << 6), i);
        end
        repeat (80) @(posedge clk_axi);

        // Bật RREADY ngẫu nhiên có seed rồi phát 4 lệnh đọc 4-beat (tổng 16 beat)
        rand_rready_en = 1'b1;
        for (int i = 0; i < 4; i++) begin
            read_burst4(AXI_ID_WIDTH'(i + 1), 32'h0001_0000 + (i << 6));
        end

        repeat (300) @(posedge clk_axi);
        rand_rready_en = 1'b0;
        repeat (20) @(posedge clk_axi);

        // Kiểm tra H-3: số beat R nhận ở AXI phải bằng đúng số beat ROB retire (16 beat),
        // đủ 4 RLAST, và không có beat nào bị nhân đôi/lệch dữ liệu khi RREADY ngẫu nhiên.
        tb_check(rob_beats_retired == 16,
                 $sformatf("[H-3] ROB retired all 16 beats (got %0d)", rob_beats_retired));
        tb_check(r_beats_received == rob_beats_retired,
                 $sformatf("[H-3] AXI R beats received (%0d) must equal ROB beats retired (%0d) under random RREADY",
                           r_beats_received, rob_beats_retired));
        tb_check(r_rlast_cnt == 4 && r_beats_received == 16,
                 $sformatf("[H-3] Expected 4 RLAST bursts and 16 R beats, got RLAST=%0d beats=%0d",
                           r_rlast_cnt, r_beats_received));
        tb_check(r_data_mismatch == 0,
                 $sformatf("[H-3] Expected 0 RDATA/RID mismatches under random RREADY, got %0d",
                           r_data_mismatch));

        tb_report();
        $finish;
    end
endmodule
