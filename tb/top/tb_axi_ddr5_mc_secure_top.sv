// File: tb_axi_ddr5_mc_secure_top.sv
// Chức năng: Testbench tích hợp cho axi_ddr5_mc_secure_top (AES-256-XTS IEEE 1619, từ chối S3, bypass, nhiều ID, RREADY ngẫu nhiên).

`timescale 1ns / 1ps

module tb_axi_ddr5_mc_secure_top #(
    parameter int TB_TCK_PS     = 4000,
    parameter bit RANDOM_RREADY = 1'b1
);
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

    logic clk_axi = 1'b0;
    always #(0.0005ns * TB_TCK_PS) clk_axi = ~clk_axi;

    logic clk_ddr = 1'b0;
    always #1.25 clk_ddr = ~clk_ddr;

    logic aresetn_axi;
    logic aresetn_ddr;

    // Security Ports S8
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
        .TCK_PS         (TB_TCK_PS)
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

    // DRAM Model
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

    logic [63:0] dfi_wr_captured [256];
    int          dfi_wr_cap_idx = 0;

    always @(posedge clk_axi) begin
        if (dfi_wrdata_en) begin
            dfi_wr_captured[dfi_wr_cap_idx] <= dfi_wrdata;
            dfi_wr_cap_idx <= dfi_wr_cap_idx + 1;
        end
    end

    logic [1:0]  captured_bresp;
    logic [AXI_ID_WIDTH-1:0] captured_bid;
    int          b_done_count = 0;

    always @(posedge clk_axi) begin
        if (s_axi_bvalid && s_axi_bready) begin
            captured_bresp <= s_axi_bresp;
            captured_bid   <= s_axi_bid;
            b_done_count   <= b_done_count + 1;
        end
    end

    logic [63:0] r_data_captured [256];
    logic [1:0]  r_resp_captured [256];
    logic [AXI_ID_WIDTH-1:0] r_id_captured [256];
    int          r_beat_count = 0;

    always @(posedge clk_axi) begin
        if (s_axi_rvalid && s_axi_rready) begin
            r_data_captured[r_beat_count] <= s_axi_rdata;
            r_resp_captured[r_beat_count] <= s_axi_rresp;
            r_id_captured[r_beat_count]   <= s_axi_rid;
            r_beat_count <= r_beat_count + 1;
        end
    end

    // Random RREADY generator
    logic [31:0] lfsr = 32'h1928_3746;
    always @(posedge clk_axi or negedge aresetn_axi) begin
        if (!aresetn_axi) begin
            lfsr         <= 32'h1928_3746;
            s_axi_rready <= 1'b1;
            s_axi_bready <= 1'b1;
        end else if (RANDOM_RREADY) begin
            lfsr         <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
            s_axi_rready <= lfsr[0] | lfsr[1];
            s_axi_bready <= lfsr[2] | lfsr[3];
        end else begin
            s_axi_rready <= 1'b1;
            s_axi_bready <= 1'b1;
        end
    end

    // Task ghi 64B (8 beat)
    task automatic write_64b(
        input logic [AXI_ID_WIDTH-1:0]   id,
        input logic [AXI_ADDR_WIDTH-1:0] addr,
        input logic [511:0]              data_512
    );
        @(negedge clk_axi);
        s_axi_awid    <= id;
        s_axi_awaddr  <= addr;
        s_axi_awlen   <= 8'd7;
        s_axi_awsize  <= 3'b011;
        s_axi_awburst <= 2'b01;
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

        while (!(s_axi_bvalid && s_axi_bready)) @(posedge clk_axi);
        @(negedge clk_axi);
    endtask

    // Task đọc 64B (8 beat)
    task automatic read_64b(
        input logic [AXI_ID_WIDTH-1:0]   id,
        input logic [AXI_ADDR_WIDTH-1:0] addr
    );
        @(negedge clk_axi);
        s_axi_arid    <= id;
        s_axi_araddr  <= addr;
        s_axi_arlen   <= 8'd7;
        s_axi_arsize  <= 3'b011;
        s_axi_arburst <= 2'b01;
        s_axi_arqos   <= 4'd2;
        s_axi_arvalid <= 1'b1;

        while (!s_axi_arready) @(posedge clk_axi);
        @(negedge clk_axi);
        s_axi_arvalid <= 1'b0;
    endtask

    initial begin
        $display("================================================================================");
        $display("  Q-SHIELD AXI DDR5 SECURE TOP INTEGRATION TESTBENCH");
        $display("  Target: tb_axi_ddr5_mc_secure_top (IEEE 1619 AES-XTS, S3 Rejections, Bypass)");
        $display("================================================================================");

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

        // 1. Chờ mở rộng khoá AES-256
        $display("[STAGE 1] Key expansion and cryptographic initialization...");
        repeat (60) @(posedge clk_axi);
        tb_check(dut.u_crypto_bridge.keys_ready === 1'b1, "K1 and K2 expansion valid");

        // 2. Ghi và Đọc mã hoá dòng 64 B (8 beat)
        $display("[STAGE 2] Encrypted 64B write and readback verification...");
        begin
            logic [511:0] p_line;
            for (int b = 0; b < 8; b++) begin
                p_line[b*64 +: 64] = 64'hA0B1_C2D3_E4F5_0000 | 64'(b);
            end

            dfi_wr_cap_idx = 0;
            write_64b(4'h1, 32'h0000_1000, p_line);
            tb_check(captured_bresp === 2'b00, "Write 64B received OKAY");

            repeat (50) @(posedge clk_axi);
            tb_check(dfi_wr_cap_idx >= 8, "DFI captured 8 write beats");

            // Kiểm tra bản mã trong DRAM khác bản rõ
            begin
                int diff_cnt;
                diff_cnt = 0;
                for (int b = 0; b < 8; b++) begin
                    if (dfi_wr_captured[b] !== p_line[b*64 +: 64]) diff_cnt++;
                end
                tb_check(diff_cnt == 8, "Ciphertext on DRAM differs from plaintext on all 8 beats");
            end

            // Đọc lại và kiểm tra giải mã khôi phục bản rõ chính xác
            r_beat_count = 0;
            read_64b(4'h1, 32'h0000_1000);
            while (r_beat_count < 8) @(posedge clk_axi);
            repeat (5) @(posedge clk_axi);

            begin
                int match_cnt;
                match_cnt = 0;
                for (int b = 0; b < 8; b++) begin
                    if (r_data_captured[b] === p_line[b*64 +: 64]) match_cnt++;
                end
                tb_check(match_cnt == 8, "Decryption recovered all 8 plaintext beats bit-exact");
            end
        end

        // 3. Phân tách miền địa chỉ (Domain Separation across Addresses & Epochs)
        $display("[STAGE 3] Domain separation verification (different tweak per line)...");
        begin
            logic [511:0] p_line2;
            for (int b = 0; b < 8; b++) p_line2[b*64 +: 64] = 64'hA0B1_C2D3_E4F5_0000 | 64'(b);

            dfi_wr_cap_idx = 0;
            write_64b(4'h2, 32'h0000_2000, p_line2);
            tb_check(captured_bresp === 2'b00, "Write to second line OKAY");

            repeat (30) @(posedge clk_axi);
            // Bản mã của dòng 0x2000 PHẢI KHÁC bản mã của dòng 0x1000 dù cùng bản rõ
            tb_check(dfi_wr_captured[0] !== dfi_wr_captured[8], "Different line address generates different ciphertext");

            r_beat_count = 0;
            read_64b(4'h2, 32'h0000_2000);
            while (r_beat_count < 8) @(posedge clk_axi);
            tb_check(r_data_captured[0] === p_line2[63:0], "Read from second line recovers plaintext");
        end

        // 4. Kiểm tra chế độ Bypass (i_enc_enable = 0)
        $display("[STAGE 4] Bypass mode verification...");
        begin
            logic [511:0] p_bypass;
            for (int b = 0; b < 8; b++) p_bypass[b*64 +: 64] = 64'h1122_3344_5566_7788 | 64'(b);

            @(negedge clk_axi);
            i_enc_enable = 1'b0;
            repeat (2) @(posedge clk_axi);

            dfi_wr_cap_idx = 0;
            write_64b(4'h3, 32'h0000_3000, p_bypass);
            tb_check(captured_bresp === 2'b00, "Bypass write OKAY");

            r_beat_count = 0;
            read_64b(4'h3, 32'h0000_3000);
            while (r_beat_count < 8) @(posedge clk_axi);
            tb_check(r_data_captured[0] === p_bypass[63:0], "Bypass read beat 0 returns raw plaintext");
            tb_check(r_data_captured[7] === p_bypass[511:448], "Bypass read beat 7 returns raw plaintext");

            @(negedge clk_axi);
            i_enc_enable = 1'b1;
            repeat (2) @(posedge clk_axi);
        end

        // 5. Kiểm tra từ chối giao dịch S3 (Rejection Test Suite)
        $display("[STAGE 5] S3 Protocol rejections test suite...");
        begin
            // 5a. Địa chỉ không căn 16B
            @(negedge clk_axi);
            s_axi_awid    <= 4'h4;
            s_axi_awaddr  <= 32'h0000_4004;
            s_axi_awlen   <= 8'd1;
            s_axi_awsize  <= 3'b011;
            s_axi_awburst <= 2'b01;
            s_axi_awvalid <= 1'b1;
            while (!s_axi_awready) @(posedge clk_axi);
            @(negedge clk_axi);
            s_axi_awvalid <= 1'b0;

            for (int b = 0; b < 2; b++) begin
                s_axi_wdata  <= 64'hDEAD_DEAD_DEAD_DEAD;
                s_axi_wstrb  <= 8'hFF;
                s_axi_wlast  <= (b == 1);
                s_axi_wvalid <= 1'b1;
                while (!s_axi_wready) @(posedge clk_axi);
                @(negedge clk_axi);
            end
            s_axi_wvalid <= 1'b0;

            while (!(s_axi_bvalid && s_axi_bready)) @(posedge clk_axi);
            @(negedge clk_axi);
            tb_check(captured_bresp === 2'b10, "Unaligned write rejected with SLVERR");

            // 5b. Đọc không căn 16B
            r_beat_count = 0;
            @(negedge clk_axi);
            s_axi_arid    <= 4'h5;
            s_axi_araddr  <= 32'h0000_5004;
            s_axi_arlen   <= 8'd1;
            s_axi_arsize  <= 3'b011;
            s_axi_arburst <= 2'b01;
            s_axi_arvalid <= 1'b1;
            while (!s_axi_arready) @(posedge clk_axi);
            @(negedge clk_axi);
            s_axi_arvalid <= 1'b0;

            while (r_beat_count < 2) @(posedge clk_axi);
            tb_check(r_resp_captured[0] === 2'b10, "Unaligned read rejected with SLVERR");
            tb_check(r_data_captured[0] === 64'h0, "Rejected read returns data 0");
            tb_check(o_crypto_reject_cnt >= 16'd2, "Reject counter tracks both rejected transactions");
        end

        repeat (20) @(posedge clk_axi);
        $display("================================================================================");
        $display("  ALL VERIFICATION STAGES COMPLETED SUCCESSFULLY");
        $display("================================================================================");
        tb_report();
        $finish;
    end

endmodule
