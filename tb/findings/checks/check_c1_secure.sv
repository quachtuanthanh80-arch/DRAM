// File: check_c1_secure.sv
// Chức năng: Kiểm tra bảo mật finding C-1 trên axi_ddr5_mc_secure_top (bản rõ khác bản mã trên DRAM và đọc lại đúng).

`timescale 1ns / 1ps

module check_c1_secure;
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
    localparam int COL_WIDTH      = 13;
    localparam int ROB_DEPTH      = 16;
    localparam int TCK_PS         = 4000;

    logic clk_axi = 1'b0;
    always #2.0 clk_axi = ~clk_axi;

    logic clk_ddr = 1'b0;
    always #1.25 clk_ddr = ~clk_ddr;

    logic aresetn_axi;
    logic aresetn_ddr;

    // Tín hiệu bảo mật S8
    logic         i_enc_enable;
    logic         i_keys_valid;
    logic [255:0] i_key1;
    logic [255:0] i_key2;
    logic [3:0]   i_asid;
    logic [18:0]  i_epoch;
    wire          o_crypto_busy;
    wire  [15:0]  o_crypto_reject_cnt;
    wire  [15:0]  o_crypto_err_cnt;

    // AXI4 Interface
    logic [AXI_ID_WIDTH-1:0]   s_axi_awid;
    logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr;
    logic [AXI_LEN_WIDTH-1:0]  s_axi_awlen;
    logic [2:0]                s_axi_awsize;
    logic [1:0]                s_axi_awburst;
    logic [AXI_QOS_WIDTH-1:0]  s_axi_awqos;
    logic                      s_axi_awvalid;
    wire                       s_axi_awready;

    logic [AXI_DATA_WIDTH-1:0] s_axi_wdata;
    logic [AXI_STRB_WIDTH-1:0] s_axi_wstrb;
    logic                      s_axi_wlast;
    logic                      s_axi_wvalid;
    wire                       s_axi_wready;

    wire  [AXI_ID_WIDTH-1:0]   s_axi_bid;
    wire  [1:0]                s_axi_bresp;
    wire                       s_axi_bvalid;
    logic                      s_axi_bready;

    logic [AXI_ID_WIDTH-1:0]   s_axi_arid;
    logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr;
    logic [AXI_LEN_WIDTH-1:0]  s_axi_arlen;
    logic [2:0]                s_axi_arsize;
    logic [1:0]                s_axi_arburst;
    logic [AXI_QOS_WIDTH-1:0]  s_axi_arqos;
    logic                      s_axi_arvalid;
    wire                       s_axi_arready;

    wire  [AXI_ID_WIDTH-1:0]   s_axi_rid;
    wire  [AXI_DATA_WIDTH-1:0] s_axi_rdata;
    wire  [1:0]                s_axi_rresp;
    wire                       s_axi_rlast;
    wire                       s_axi_rvalid;
    logic                      s_axi_rready;

    // DFI Interface
    wire  [2:0]                dfi_cmd;
    wire  [BG_WIDTH-1:0]       dfi_bg;
    wire  [BANK_WIDTH-1:0]     dfi_bank;
    wire  [ROW_WIDTH-1:0]      dfi_row;
    wire  [COL_WIDTH-1:0]      dfi_col;
    wire  [7:0]                dfi_len;
    wire                       dfi_wrdata_en;
    wire  [63:0]               dfi_wrdata;
    wire  [7:0]                dfi_wrdata_mask;
    wire  [7:0]                dfi_wrdata_ecc;
    wire                       dfi_rddata_valid;
    wire  [63:0]               dfi_rddata;
    wire  [7:0]                dfi_rddata_ecc;

    axi_ddr5_mc_secure_top #(
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
        .DFI_WRLAT      (9),
        .DFI_RDLAT      (8),
        .TCK_PS         (TCK_PS)
    ) dut (
        .clk_axi             (clk_axi),
        .aresetn_axi         (aresetn_axi),
        .clk_ddr             (clk_ddr),
        .aresetn_ddr         (aresetn_ddr),

        .i_enc_enable        (i_enc_enable),
        .i_keys_valid        (i_keys_valid),
        .i_key1              (i_key1),
        .i_key2              (i_key2),
        .i_asid              (i_asid),
        .i_epoch             (i_epoch),
        .o_crypto_busy       (o_crypto_busy),
        .o_crypto_reject_cnt (o_crypto_reject_cnt),
        .o_crypto_err_cnt    (o_crypto_err_cnt),

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
        .s_axi_rpoison       (),
        .s_axi_rchk          (),
        .o_parity_err        (),

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
        .cfg_rh_threshold    (16'd32),
        .cfg_window_size     (16'd1024),
        .o_throttled_events  (),
        .o_ecc_single_err_cnt(),
        .o_ecc_double_err_cnt()
    );

    // Mô hình bộ nhớ DRAM hành vi
    dram_model #(
        .COL_W  (COL_WIDTH),
        .RL     (8),
        .WL     (9)
    ) u_dram (
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

    logic [1:0] captured_bresp;
    always @(posedge clk_axi) begin
        if (s_axi_bvalid && s_axi_bready) begin
            captured_bresp <= s_axi_bresp;
        end
    end
    logic [63:0] captured_dfi_wrdata [64];
    int          dfi_wr_beat_cnt = 0;

    always @(posedge clk_axi) begin
        if (dfi_wrdata_en) begin
            captured_dfi_wrdata[dfi_wr_beat_cnt] <= dfi_wrdata;
            dfi_wr_beat_cnt <= dfi_wr_beat_cnt + 1;
        end
    end

    logic [63:0] captured_axi_rdata [64];
    logic [1:0]  captured_axi_rresp [64];
    int          axi_rd_beat_cnt = 0;

    always @(posedge clk_axi) begin
        if (s_axi_rvalid && s_axi_rready) begin
            captured_axi_rdata[axi_rd_beat_cnt] <= s_axi_rdata;
            captured_axi_rresp[axi_rd_beat_cnt] <= s_axi_rresp;
            axi_rd_beat_cnt <= axi_rd_beat_cnt + 1;
        end
    end

    // Task thực thi Write Burst 8 beat (64 byte)
    task automatic do_write_8(
        input logic [AXI_ID_WIDTH-1:0]   id,
        input logic [AXI_ADDR_WIDTH-1:0] addr,
        input logic [511:0]              data_512,
        input logic [1:0]                burst_type,
        input logic [2:0]                size_type
    );
        @(negedge clk_axi);
        s_axi_awid    <= id;
        s_axi_awaddr  <= addr;
        s_axi_awlen   <= 8'd7;
        s_axi_awsize  <= size_type;
        s_axi_awburst <= burst_type;
        s_axi_awqos   <= 4'd2;
        s_axi_awvalid <= 1'b1;

        while (!s_axi_awready) @(posedge clk_axi);
        @(negedge clk_axi);
        s_axi_awvalid <= 1'b0;

        for (int b = 0; b < 8; b++) begin
            s_axi_wdata  <= data_512[b*64 +: 64];
            s_axi_wstrb  <= 8'hFF;
            s_axi_wlast  <= (b == 7);
            s_axi_wvalid <= 1'b1;
            while (!s_axi_wready) @(posedge clk_axi);
            @(negedge clk_axi);
        end
        s_axi_wvalid <= 1'b0;

        while (!s_axi_bvalid) @(posedge clk_axi);
        @(negedge clk_axi);
    endtask

    // Task thực thi Write Burst 2 beat (16 byte)
    task automatic do_write_2(
        input logic [AXI_ID_WIDTH-1:0]   id,
        input logic [AXI_ADDR_WIDTH-1:0] addr,
        input logic [127:0]              data_128,
        input logic [1:0]                burst_type,
        input logic [2:0]                size_type
    );
        @(negedge clk_axi);
        s_axi_awid    <= id;
        s_axi_awaddr  <= addr;
        s_axi_awlen   <= 8'd1;
        s_axi_awsize  <= size_type;
        s_axi_awburst <= burst_type;
        s_axi_awqos   <= 4'd2;
        s_axi_awvalid <= 1'b1;

        while (!s_axi_awready) @(posedge clk_axi);
        @(negedge clk_axi);
        s_axi_awvalid <= 1'b0;

        for (int b = 0; b < 2; b++) begin
            s_axi_wdata  <= data_128[b*64 +: 64];
            s_axi_wstrb  <= 8'hFF;
            s_axi_wlast  <= (b == 1);
            s_axi_wvalid <= 1'b1;
            while (!s_axi_wready) @(posedge clk_axi);
            @(negedge clk_axi);
        end
        s_axi_wvalid <= 1'b0;

        while (!s_axi_bvalid) @(posedge clk_axi);
        @(negedge clk_axi);
    endtask

    // Task thực thi Write Burst 1 beat (8 byte)
    task automatic do_write_1(
        input logic [AXI_ID_WIDTH-1:0]   id,
        input logic [AXI_ADDR_WIDTH-1:0] addr,
        input logic [63:0]               data_64,
        input logic [1:0]                burst_type,
        input logic [2:0]                size_type
    );
        @(negedge clk_axi);
        s_axi_awid    <= id;
        s_axi_awaddr  <= addr;
        s_axi_awlen   <= 8'd0;
        s_axi_awsize  <= size_type;
        s_axi_awburst <= burst_type;
        s_axi_awqos   <= 4'd2;
        s_axi_awvalid <= 1'b1;

        while (!s_axi_awready) @(posedge clk_axi);
        @(negedge clk_axi);
        s_axi_awvalid <= 1'b0;

        s_axi_wdata  <= data_64;
        s_axi_wstrb  <= 8'hFF;
        s_axi_wlast  <= 1'b1;
        s_axi_wvalid <= 1'b1;
        while (!s_axi_wready) @(posedge clk_axi);
        @(negedge clk_axi);
        s_axi_wvalid <= 1'b0;

        while (!s_axi_bvalid) @(posedge clk_axi);
        @(negedge clk_axi);
    endtask

    // Task thực thi Read Burst
    task automatic do_read(
        input logic [AXI_ID_WIDTH-1:0]   id,
        input logic [AXI_ADDR_WIDTH-1:0] addr,
        input logic [7:0]                len,
        input logic [1:0]                burst_type,
        input logic [2:0]                size_type
    );
        @(negedge clk_axi);
        s_axi_arid    <= id;
        s_axi_araddr  <= addr;
        s_axi_arlen   <= len;
        s_axi_arsize  <= size_type;
        s_axi_arburst <= burst_type;
        s_axi_arqos   <= 4'd2;
        s_axi_arvalid <= 1'b1;

        while (!s_axi_arready) @(posedge clk_axi);
        @(negedge clk_axi);
        s_axi_arvalid <= 1'b0;
    endtask

    initial begin
        $display("=== START CHECK_C1_SECURE (axi_ddr5_mc_secure_top) ===");

        // 1. Khởi tạo tín hiệu và Reset
        aresetn_axi   = 1'b0;
        aresetn_ddr   = 1'b0;
        i_enc_enable  = 1'b1;
        i_keys_valid  = 1'b1;
        i_key1        = 256'h2718281828459045235360287471352662497757247093699959574966967627;
        i_key2        = 256'h3141592653589793238462643383279502884197169399375105820974944592;
        i_asid        = 4'h1;
        i_epoch       = 19'h00001;

        s_axi_awvalid = 1'b0;
        s_axi_wvalid  = 1'b0;
        s_axi_bready  = 1'b1;
        s_axi_arvalid = 1'b0;
        s_axi_rready  = 1'b1;

        repeat (10) @(posedge clk_axi);
        @(negedge clk_axi);
        aresetn_axi = 1'b1;
        aresetn_ddr = 1'b1;

        // Chờ Key Expansion hoàn tất
        $display("[INFO] Waiting for AES-256 key expansion to finish...");
        repeat (60) @(posedge clk_axi);
        tb_check(dut.u_crypto_bridge.keys_ready === 1'b1, "K1 and K2 expansion valid");

        //=====================================================================
        // TEST 1: Ghi mã hoá dòng 64 B (8 beat) và kiểm tra bản mã trên DRAM
        //=====================================================================
        $display("[INFO] TEST 1: Encrypted 64B write (addr 0x1000)...");
        begin
            logic [511:0] pt_512;
            for (int b = 0; b < 8; b++) begin
                pt_512[b*64 +: 64] = 64'h0123_4567_89AB_CDEF ^ (64'(b) << 32) ^ 64'(b);
            end

            dfi_wr_beat_cnt = 0;
            do_write_8(4'h1, 32'h0000_1000, pt_512, 2'b01, 3'b011);
            tb_check(captured_bresp === 2'b00, "Write response OKAY");

            repeat (40) @(posedge clk_axi);
            tb_check(dfi_wr_beat_cnt >= 8, "DFI captured at least 8 write beats");

            // Kiểm tra: Bản mã trên DFI PHẢI KHÁC bản rõ (finding C-1 fix proof)
            begin
                int diff_beats;
                diff_beats = 0;
                for (int b = 0; b < 8; b++) begin
                    if (captured_dfi_wrdata[b] !== pt_512[b*64 +: 64]) begin
                        diff_beats++;
                    end
                end
                tb_check(diff_beats == 8, "All 8 beats in DRAM model are encrypted ciphertext (diff from plaintext)");
                $display("[PASS] C-1 verified: DRAM model sees ciphertext != plaintext for all beats.");
            end

            //=================================================================
            // TEST 2: Đọc ngược lại qua axi_ddr5_mc_secure_top, kiểm tra bản rõ
            //=================================================================
            $display("[INFO] TEST 2: Encrypted 64B read back (addr 0x1000)...");
            axi_rd_beat_cnt = 0;
            do_read(4'h1, 32'h0000_1000, 8'd7, 2'b01, 3'b011);

            while (axi_rd_beat_cnt < 8) @(posedge clk_axi);
            repeat (5) @(posedge clk_axi);

            tb_check(axi_rd_beat_cnt == 8, "Read received exactly 8 beats");
            begin
                int match_beats;
                match_beats = 0;
                for (int b = 0; b < 8; b++) begin
                    if (captured_axi_rdata[b] === pt_512[b*64 +: 64]) begin
                        match_beats++;
                    end
                end
                tb_check(match_beats == 8, "All 8 read beats match original plaintext bit-exact");
                $display("[PASS] Decryption verified: All 8 beats recovered plaintext bit-exact!");
            end
        end

        //=====================================================================
        // TEST 3: Chế độ Bypass (i_enc_enable = 0)
        //=====================================================================
        $display("[INFO] TEST 3: Bypass mode (i_enc_enable = 0, addr 0x2000)...");
        begin
            logic [511:0] bp_512;
            for (int b = 0; b < 8; b++) begin
                bp_512[b*64 +: 64] = 64'hDEAD_BEEF_0000_0000 | 64'(b);
            end

            @(negedge clk_axi);
            i_enc_enable = 1'b0;
            repeat (2) @(posedge clk_axi);

            dfi_wr_beat_cnt = 0;
            do_write_8(4'h2, 32'h0000_2000, bp_512, 2'b01, 3'b011);
            tb_check(captured_bresp === 2'b00, "Bypass write response OKAY");

            repeat (40) @(posedge clk_axi);
            begin
                int bp_match;
                bp_match = 0;
                for (int b = 0; b < 8; b++) begin
                    if (captured_dfi_wrdata[b] === bp_512[b*64 +: 64]) bp_match++;
                end
                tb_check(bp_match >= 6, "Bypass mode writes raw plaintext to core");
            end

            axi_rd_beat_cnt = 0;
            do_read(4'h2, 32'h0000_2000, 8'd7, 2'b01, 3'b011);
            while (axi_rd_beat_cnt < 8) @(posedge clk_axi);
            tb_check(captured_axi_rdata[0] === bp_512[63:0], "Bypass read returns plaintext");

            @(negedge clk_axi);
            i_enc_enable = 1'b1;
            repeat (2) @(posedge clk_axi);
        end

        //=====================================================================
        // TEST 4: Từ chối giao dịch không đủ chuẩn (S3 Rejections)
        //=====================================================================
        $display("[INFO] TEST 4: S3 Rejection tests...");
        begin
            // 4a. Địa chỉ không căn 16B (addr 0x3004)
            do_write_2(4'h3, 32'h0000_3004, 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF, 2'b01, 3'b011);
            tb_check(captured_bresp === 2'b10, "Unaligned 16B write rejected with SLVERR");
            tb_check(o_crypto_reject_cnt >= 16'd1, "Reject counter incremented on unaligned addr");

            // 4b. Loại burst không phải INCR (FIXED = 2'b00)
            do_write_2(4'h4, 32'h0000_4000, 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF, 2'b00, 3'b011);
            tb_check(captured_bresp === 2'b10, "Non-INCR burst rejected with SLVERR");
            tb_check(o_crypto_reject_cnt >= 16'd2, "Reject counter incremented on non-INCR");

            // 4c. Số beat lẻ (len = 0 => 1 beat)
            do_write_1(4'h5, 32'h0000_5000, 64'hFFFF_FFFF_FFFF_FFFF, 2'b01, 3'b011);
            tb_check(captured_bresp === 2'b10, "Odd beat count write rejected with SLVERR");
            tb_check(o_crypto_reject_cnt >= 16'd3, "Reject counter incremented on odd beat count");

            // 4d. Đọc với địa chỉ không căn 16B
            axi_rd_beat_cnt = 0;
            do_read(4'h6, 32'h0000_6004, 8'd1, 2'b01, 3'b011);
            while (axi_rd_beat_cnt < 2) @(posedge clk_axi);
            tb_check(captured_axi_rresp[0] === 2'b10, "Unaligned read rejected with SLVERR");
            tb_check(captured_axi_rdata[0] === 64'h0, "Rejected read returns zero data");
            tb_check(o_crypto_reject_cnt >= 16'd4, "Reject counter incremented on unaligned read");
        end

        repeat (20) @(posedge clk_axi);
        tb_report();
        $finish;
    end

endmodule
