// File: check_t11_main_path.sv
// Chức năng: Rà soát đường chính axi_ddr5_mc_top theo ba lớp lỗi C-3 (1000 giao dịch DFI scoreboard), C-4 (đường đọc sống) và H-1/L-2 (reset).
`timescale 1ns / 1ps

module check_t11_main_path;
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
        .TCK_PS         (TCK_PS)
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
        .cfg_rh_threshold    (16'd2000),
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

    //=========================================================================
    // Scoreboard tham chiếu độc lập qua hai bộ addr_mapper_ddr5 (cho AW và AR)
    //=========================================================================
    logic                 ref_wr_valid;
    logic [BG_WIDTH-1:0]  ref_wr_bg;
    logic [BANK_WIDTH-1:0]ref_wr_bank;
    logic [ROW_WIDTH-1:0] ref_wr_row;
    logic [COL_WIDTH-1:0] ref_wr_col;

    addr_mapper_ddr5 #(
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_QOS_WIDTH  (AXI_QOS_WIDTH),
        .ROW_WIDTH      (ROW_WIDTH),
        .COL_WIDTH      (COL_WIDTH),
        .BG_WIDTH       (BG_WIDTH),
        .BANK_WIDTH     (BANK_WIDTH)
    ) u_ref_mapper_wr (
        .clk                  (clk_axi),
        .rst_n                (aresetn_axi),
        .cfg_is_ddr5          (1'b1),
        .cfg_bank_coloring_en (1'b0),
        .cfg_mapping_mode     (2'b00),
        .cfg_scramble_en      (1'b1),
        .cfg_scramble_mode    (2'b10),
        .cfg_scramble_seed    (64'hA5A5_5A5A_0123_4567),
        .i_req_valid          (s_axi_awvalid && s_axi_awready),
        .o_req_ready          (),
        .i_req_id             (s_axi_awid),
        .i_req_tenant         (s_axi_awid),
        .i_req_is_write       (1'b1),
        .i_req_addr           (s_axi_awaddr),
        .i_req_len            (s_axi_awlen),
        .i_req_qos            (s_axi_awqos),
        .o_cmd_valid          (ref_wr_valid),
        .i_cmd_ready          (1'b1),
        .o_cmd_id             (),
        .o_cmd_is_write       (),
        .o_cmd_bg             (ref_wr_bg),
        .o_cmd_bank           (ref_wr_bank),
        .o_cmd_row            (ref_wr_row),
        .o_cmd_col            (ref_wr_col),
        .o_cmd_len            (),
        .o_cmd_qos            (),
        .o_busy               ()
    );

    logic                 ref_rd_valid;
    logic [BG_WIDTH-1:0]  ref_rd_bg;
    logic [BANK_WIDTH-1:0]ref_rd_bank;
    logic [ROW_WIDTH-1:0] ref_rd_row;
    logic [COL_WIDTH-1:0] ref_rd_col;

    addr_mapper_ddr5 #(
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_QOS_WIDTH  (AXI_QOS_WIDTH),
        .ROW_WIDTH      (ROW_WIDTH),
        .COL_WIDTH      (COL_WIDTH),
        .BG_WIDTH       (BG_WIDTH),
        .BANK_WIDTH     (BANK_WIDTH)
    ) u_ref_mapper_rd (
        .clk                  (clk_axi),
        .rst_n                (aresetn_axi),
        .cfg_is_ddr5          (1'b1),
        .cfg_bank_coloring_en (1'b0),
        .cfg_mapping_mode     (2'b00),
        .cfg_scramble_en      (1'b1),
        .cfg_scramble_mode    (2'b10),
        .cfg_scramble_seed    (64'hA5A5_5A5A_0123_4567),
        .i_req_valid          (s_axi_arvalid && s_axi_arready),
        .o_req_ready          (),
        .i_req_id             (s_axi_arid),
        .i_req_tenant         (s_axi_arid),
        .i_req_is_write       (1'b0),
        .i_req_addr           (s_axi_araddr),
        .i_req_len            (s_axi_arlen),
        .i_req_qos            (s_axi_arqos),
        .o_cmd_valid          (ref_rd_valid),
        .i_cmd_ready          (1'b1),
        .o_cmd_id             (),
        .o_cmd_is_write       (),
        .o_cmd_bg             (ref_rd_bg),
        .o_cmd_bank           (ref_rd_bank),
        .o_cmd_row            (ref_rd_row),
        .o_cmd_col            (ref_rd_col),
        .o_cmd_len            (),
        .o_cmd_qos            (),
        .o_busy               ()
    );

    localparam int TUPLE_W = BG_WIDTH + BANK_WIDTH + ROW_WIDTH + COL_WIDTH;
    localparam int MAX_PEND = 128;

    logic [TUPLE_W-1:0] exp_wr_pool [MAX_PEND];
    bit                 exp_wr_vld  [MAX_PEND];
    logic [TUPLE_W-1:0] exp_rd_pool [MAX_PEND];
    bit                 exp_rd_vld  [MAX_PEND];

    logic [ROW_WIDTH-1:0] dfi_open_row [BG_COUNT][BANK_COUNT];
    bit                   dfi_row_open [BG_COUNT][BANK_COUNT];

    int sb_wr_matched, sb_wr_mismatch, sb_wr_pend_cnt;
    int sb_rd_matched, sb_rd_mismatch, sb_rd_pend_cnt;
    int ar_issued_cnt, r_bursts_done, r_beats_expected, r_beats_got, r_resp_err;
    int b_done_cnt;
    bit sb_enable;

    always @(posedge clk_axi or negedge aresetn_axi) begin
        if (!aresetn_axi) begin
            for (int i = 0; i < MAX_PEND; i++) begin
                exp_wr_vld[i] = 1'b0;
                exp_rd_vld[i] = 1'b0;
            end
            for (int g = 0; g < BG_COUNT; g++) begin
                for (int b = 0; b < BANK_COUNT; b++) begin
                    dfi_row_open[g][b] = 1'b0;
                    dfi_open_row[g][b] = '0;
                end
            end
            sb_wr_pend_cnt = 0;
            sb_rd_pend_cnt = 0;
        end else if (sb_enable) begin
            // 1. Nạp địa chỉ kỳ vọng từ u_ref_mapper_wr / u_ref_mapper_rd
            if (ref_wr_valid) begin
                bit placed;
                placed = 1'b0;
                for (int i = 0; i < MAX_PEND; i++) begin
                    if (!placed && !exp_wr_vld[i]) begin
                        exp_wr_vld[i]  = 1'b1;
                        exp_wr_pool[i] = {ref_wr_bg, ref_wr_bank, ref_wr_row, ref_wr_col};
                        sb_wr_pend_cnt++;
                        placed = 1'b1;
                    end
                end
            end
            if (ref_rd_valid) begin
                bit placed;
                placed = 1'b0;
                for (int i = 0; i < MAX_PEND; i++) begin
                    if (!placed && !exp_rd_vld[i]) begin
                        exp_rd_vld[i]  = 1'b1;
                        exp_rd_pool[i] = {ref_rd_bg, ref_rd_bank, ref_rd_row, ref_rd_col};
                        sb_rd_pend_cnt++;
                        placed = 1'b1;
                    end
                end
            end

            // 2. Theo dõi hàng đang mở trên DFI
            if (dfi_cmd == 3'b001) begin // ACT
                dfi_row_open[dfi_bg][dfi_bank] = 1'b1;
                dfi_open_row[dfi_bg][dfi_bank] = dfi_row;
            end else if (dfi_cmd == 3'b010) begin // PRE
                dfi_row_open[dfi_bg][dfi_bank] = 1'b0;
            end else if (dfi_cmd == 3'b101 || dfi_cmd == 3'b110) begin // REF / RFM
                for (int g = 0; g < BG_COUNT; g++)
                    for (int b = 0; b < BANK_COUNT; b++)
                        dfi_row_open[g][b] = 1'b0;
            end

            // 3. Đối chiếu lệnh WR trên DFI với tập kỳ vọng từ addr_mapper_ddr5
            if (dfi_cmd == 3'b100) begin
                logic [TUPLE_W-1:0] actual_tuple;
                bit matched;
                actual_tuple = {dfi_bg, dfi_bank, dfi_open_row[dfi_bg][dfi_bank], dfi_col};
                matched = 1'b0;
                if (dfi_row_open[dfi_bg][dfi_bank] && (dfi_open_row[dfi_bg][dfi_bank] === dfi_row)) begin
                    for (int i = 0; i < MAX_PEND; i++) begin
                        if (!matched && exp_wr_vld[i] && (exp_wr_pool[i] === actual_tuple)) begin
                            exp_wr_vld[i] = 1'b0;
                            sb_wr_pend_cnt--;
                            sb_wr_matched++;
                            matched = 1'b1;
                        end
                    end
                end
                if (!matched) sb_wr_mismatch++;
            end

            // 4. Đối chiếu lệnh RD trên DFI với tập kỳ vọng từ addr_mapper_ddr5
            if (dfi_cmd == 3'b011) begin
                logic [TUPLE_W-1:0] actual_tuple;
                bit matched;
                actual_tuple = {dfi_bg, dfi_bank, dfi_open_row[dfi_bg][dfi_bank], dfi_col};
                matched = 1'b0;
                if (dfi_row_open[dfi_bg][dfi_bank] && (dfi_open_row[dfi_bg][dfi_bank] === dfi_row)) begin
                    for (int i = 0; i < MAX_PEND; i++) begin
                        if (!matched && exp_rd_vld[i] && (exp_rd_pool[i] === actual_tuple)) begin
                            exp_rd_vld[i] = 1'b0;
                            sb_rd_pend_cnt--;
                            sb_rd_matched++;
                            matched = 1'b1;
                        end
                    end
                end
                if (!matched) sb_rd_mismatch++;
            end

            // 5. Theo dõi phản hồi B và R trên AXI
            if (s_axi_arvalid && s_axi_arready) begin
                ar_issued_cnt++;
                r_beats_expected += int'(s_axi_arlen) + 1;
            end
            if (s_axi_bvalid && s_axi_bready) begin
                b_done_cnt++;
            end
            if (s_axi_rvalid && s_axi_rready) begin
                r_beats_got++;
                if (s_axi_rresp != 2'b00) r_resp_err++;
                if (s_axi_rlast) r_bursts_done++;
            end
        end
    end

    // Hàm đọc file kiểm tra tĩnh L-2 và H-1
    function automatic bit file_contains_stages_fatal(input string path);
        int fd;
        int ch;
        bit has_stages;
        bit has_fatal;
        logic [10*8-1:0] win10;
        logic [6*8-1:0]  win6;
        fd = $fopen(path, "r");
        if (fd == 0) return 1'b0;
        has_stages = 1'b0;
        has_fatal  = 1'b0;
        win10 = '0;
        win6  = '0;
        ch = $fgetc(fd);
        while (ch != -1) begin
            win10 = {win10[9*8-1:0], ch[7:0]};
            win6  = {win6[5*8-1:0], ch[7:0]};
            if (win10 == "STAGES < 2") has_stages = 1'b1;
            if (win6 == "$fatal")      has_fatal  = 1'b1;
            ch = $fgetc(fd);
        end
        $fclose(fd);
        return has_stages && has_fatal;
    endfunction

    function automatic bit file_contains_soft_reset(input string path);
        int fd;
        int ch;
        bit found;
        logic [10*8-1:0] win10;
        fd = $fopen(path, "r");
        if (fd == 0) return 1'b0;
        found = 1'b0;
        win10 = '0;
        ch = $fgetc(fd);
        while (ch != -1) begin
            win10 = {win10[9*8-1:0], ch[7:0]};
            if (win10 == "soft_reset") found = 1'b1;
            ch = $fgetc(fd);
        end
        $fclose(fd);
        return found;
    endfunction

    // Hàm tạo địa chỉ ngẫu nhiên có seed: trải đều 8 BG x 4 Bank, hàng thay đổi theo epoch để vừa có row-hit vừa có row-conflict
    function automatic logic [31:0] make_rand_addr(input logic [31:0] rng, input int txn_idx);
        logic [2:0]  target_bg;
        logic [1:0]  target_bank;
        logic [13:0] target_row;
        logic [6:0]  target_col_hi;
        logic [2:0]  addr_8_6;
        int          epoch;
        logic [31:0] row_calc;
        epoch         = txn_idx >> 7; // 8 epochs x 8 BGs (mỗi epoch mở 1 hàng/BG, xoay vòng đủ 4 bank và nhiều hàng)
        target_bg     = rng[2:0];
        target_bank   = epoch[1:0] ^ target_bg[1:0];
        row_calc      = (epoch * 17) + 1;
        target_row    = row_calc[13:0];
        target_col_hi = rng[11:5];
        // bg_standard = addr[8:6] ^ addr[20:18] => addr[8:6] = target_bg ^ target_row[2:0]
        addr_8_6      = target_bg ^ target_row[2:0];
        return {target_row, target_bank, target_col_hi, addr_8_6, 6'b000000};
    endfunction

    initial begin
        logic [31:0] prng;
        int          wr_issued, rd_issued;

        aresetn_axi      = 1'b0;
        aresetn_ddr      = 1'b0;
        sb_enable        = 1'b1;
        sb_wr_matched    = 0;
        sb_wr_mismatch   = 0;
        sb_rd_matched    = 0;
        sb_rd_mismatch   = 0;
        ar_issued_cnt    = 0;
        r_bursts_done    = 0;
        r_beats_expected = 0;
        r_beats_got      = 0;
        r_resp_err       = 0;
        b_done_cnt       = 0;

        s_axi_awid       = '0;
        s_axi_awaddr     = '0;
        s_axi_awlen      = '0;
        s_axi_awsize     = 3'b011;
        s_axi_awburst    = 2'b01;
        s_axi_awqos      = 4'd2;
        s_axi_awvalid    = 1'b0;
        s_axi_wdata      = '0;
        s_axi_wstrb      = 8'hFF;
        s_axi_wlast      = 1'b0;
        s_axi_wvalid     = 1'b0;
        s_axi_bready     = 1'b1;
        s_axi_arid       = '0;
        s_axi_araddr     = '0;
        s_axi_arlen      = '0;
        s_axi_arsize     = 3'b011;
        s_axi_arburst    = 2'b01;
        s_axi_arqos      = 4'd2;
        s_axi_arvalid    = 1'b0;
        s_axi_rready     = 1'b1;

        repeat (10) @(posedge clk_axi);
        @(negedge clk_axi);
        aresetn_axi = 1'b1;
        aresetn_ddr = 1'b1;
        repeat (10) @(posedge clk_axi);

        //=====================================================================
        // NHÓM 1 & 2: 1000 giao dịch ngẫu nhiên có seed (500 WR + 500 RD)
        // Kiểm tra địa chỉ DFI (bg, bank, row, col) khớp addr_mapper_ddr5 (C-3)
        // và đường đọc sống: mọi AR nhận đủ RVALID/RLAST đúng số beat (C-4)
        //=====================================================================
        prng      = 32'h2026_1107;
        wr_issued = 0;
        rd_issued = 0;

        for (int t = 0; t < 1000; t++) begin
            logic [31:0] tx_addr;
            logic [3:0]  tx_id;
            logic [7:0]  tx_len;
            bit          do_wr;

            prng    = {prng[30:0], prng[31] ^ prng[21] ^ prng[1] ^ prng[0]};
            tx_addr = make_rand_addr(prng, t);
            tx_id   = prng[15:12];
            // Đa dạng độ dài burst (1, 2, 4 beat) cho cả đọc và ghi
            case (prng[17:16])
                2'b00:   tx_len = 8'd0;
                2'b01:   tx_len = 8'd1;
                2'b10:   tx_len = 8'd3;
                default: tx_len = 8'd0;
            endcase

            if (wr_issued == 500)
                do_wr = 1'b0;
            else if (rd_issued == 500)
                do_wr = 1'b1;
            else
                do_wr = ~t[0];

            // Giữ số giao dịch đang bay vừa phải để không nghẽn giả tạo
            while ((wr_issued - b_done_cnt) >= 8 || (rd_issued - r_bursts_done) >= 8)
                @(posedge clk_axi);

            if (do_wr) begin
                @(negedge clk_axi);
                s_axi_awid    <= tx_id;
                s_axi_awaddr  <= tx_addr;
                s_axi_awlen   <= tx_len;
                s_axi_awvalid <= 1'b1;
                while (!s_axi_awready) @(posedge clk_axi);
                @(negedge clk_axi);
                s_axi_awvalid <= 1'b0;

                for (int b = 0; b <= int'(tx_len); b++) begin
                    s_axi_wdata  <= {prng, 16'(t), 16'(b)};
                    s_axi_wstrb  <= 8'hFF;
                    s_axi_wlast  <= (b == int'(tx_len));
                    s_axi_wvalid <= 1'b1;
                    while (!s_axi_wready) @(posedge clk_axi);
                    @(negedge clk_axi);
                end
                s_axi_wvalid <= 1'b0;
                s_axi_wlast  <= 1'b0;
                wr_issued++;
            end else begin
                @(negedge clk_axi);
                s_axi_arid    <= tx_id;
                s_axi_araddr  <= tx_addr;
                s_axi_arlen   <= tx_len;
                s_axi_arvalid <= 1'b1;
                while (!s_axi_arready) @(posedge clk_axi);
                @(negedge clk_axi);
                s_axi_arvalid <= 1'b0;
                rd_issued++;
            end
        end

        // Chờ toàn bộ 1000 giao dịch hoàn tất trên cả DFI và AXI
        for (int wait_c = 0; wait_c < 4000; wait_c++) begin
            if (b_done_cnt == 500 && r_bursts_done == 500 && sb_wr_matched == 500 && sb_rd_matched == 500)
                wait_c = 4000;
            else
                @(posedge clk_axi);
        end
        repeat (20) @(posedge clk_axi);

        tb_check(wr_issued == 500 && rd_issued == 500,
                 $sformatf("[C-3/C-4] Dispatched 500 writes (%0d) and 500 reads (%0d)", wr_issued, rd_issued));
        tb_check(sb_wr_matched == 500 && sb_wr_mismatch == 0 && sb_wr_pend_cnt == 0,
                 $sformatf("[C-3 WR] DFI (bg,bank,row,col) matched addr_mapper_ddr5 for 500/500 writes (matched=%0d mismatch=%0d pend=%0d)",
                           sb_wr_matched, sb_wr_mismatch, sb_wr_pend_cnt));
        tb_check(sb_rd_matched == 500 && sb_rd_mismatch == 0 && sb_rd_pend_cnt == 0,
                 $sformatf("[C-3 RD] DFI (bg,bank,row,col) matched addr_mapper_ddr5 for 500/500 reads (matched=%0d mismatch=%0d pend=%0d)",
                           sb_rd_matched, sb_rd_mismatch, sb_rd_pend_cnt));
        tb_check((sb_wr_matched + sb_rd_matched) == 1000,
                 $sformatf("[C-3 TOTAL] 1000/1000 seeded random transactions verified at DFI (total=%0d)",
                           sb_wr_matched + sb_rd_matched));

        tb_check(b_done_cnt == 500,
                 $sformatf("[C-4 WR] All 500 write BVALID responses completed without hang (%0d/500)", b_done_cnt));
        tb_check(ar_issued_cnt == 500 && r_bursts_done == 500,
                 $sformatf("[C-4 RD] All 500 AR bursts completed with RLAST without hang (AR=%0d RLAST=%0d)",
                           ar_issued_cnt, r_bursts_done));
        tb_check(r_beats_got == r_beats_expected && r_beats_got > 500 && r_resp_err == 0,
                 $sformatf("[C-4 BEATS] Exact R beat count received (%0d/%0d, err=%0d)",
                           r_beats_got, r_beats_expected, r_resp_err));

        //=====================================================================
        // NHÓM 3: Kiểm tra Reset giữa burst (H-1) và rst_sync STAGES >= 2 (L-2)
        //=====================================================================
        tb_check(file_contains_stages_fatal("rtl/cdc/rst_sync.sv"),
                 "[L-2] rtl/cdc/rst_sync.sv contains elaboration assert for STAGES >= 2");
        tb_check(!file_contains_soft_reset("rtl/top/axi_ddr5_mc_top.sv"),
                 "[H-1] rtl/top/axi_ddr5_mc_top.sv has no combinational soft_reset gating on main path");

        // Bơm một burst ghi 8-beat dở dang (chỉ gửi 3/8 beat W, chưa có WLAST) và 2 lệnh AR vào hàng đợi
        sb_enable = 1'b0;
        @(negedge clk_axi);
        s_axi_awid    <= 4'hA;
        s_axi_awaddr  <= 32'h0008_1000;
        s_axi_awlen   <= 8'd7; // 8 beats
        s_axi_awvalid <= 1'b1;
        while (!s_axi_awready) @(posedge clk_axi);
        @(negedge clk_axi);
        s_axi_awvalid <= 1'b0;

        for (int b = 0; b < 3; b++) begin
            s_axi_wdata  <= 64'hBAD0_0000_0000_0000 | 64'(b);
            s_axi_wstrb  <= 8'hFF;
            s_axi_wlast  <= 1'b0;
            s_axi_wvalid <= 1'b1;
            while (!s_axi_wready) @(posedge clk_axi);
            @(negedge clk_axi);
        end
        s_axi_wvalid <= 1'b0;

        // Phát thêm 2 lệnh đọc vào pipeline trước khi xung reset giữa burst
        for (int r = 0; r < 2; r++) begin
            @(negedge clk_axi);
            s_axi_arid    <= 4'hB + r[3:0];
            s_axi_araddr  <= 32'h0009_0000 + (r << 6);
            s_axi_arlen   <= 8'd3;
            s_axi_arvalid <= 1'b1;
            while (!s_axi_arready) @(posedge clk_axi);
            @(negedge clk_axi);
            s_axi_arvalid <= 1'b0;
        end

        // Kéo reset giữa burst đang dở dang
        @(negedge clk_axi);
        aresetn_axi = 1'b0;
        aresetn_ddr = 1'b0;
        #1;
        tb_check(dut.rst_n_axi === 1'b0 && dut.rst_n_ddr === 1'b0,
                 "[H-1/L-2] rst_sync asserts internal reset asynchronously upon mid-burst reset");

        repeat (4) @(posedge clk_axi);
        @(negedge clk_axi);
        aresetn_axi = 1'b1;
        aresetn_ddr = 1'b1;

        // Sau 1 cạnh lên clk_axi: STAGES=2 chưa nhả reset; sau 2 cạnh lên: nhả đồng bộ
        @(posedge clk_axi);
        #1;
        tb_check(dut.rst_n_axi === 1'b0,
                 "[L-2] rst_sync (STAGES=2) holds sync_rst_n=0 on 1st clock edge after release");
        @(posedge clk_axi);
        #1;
        tb_check(dut.rst_n_axi === 1'b1,
                 "[L-2] rst_sync (STAGES=2) deasserts sync_rst_n=1 on 2nd clock edge after release");

        repeat (10) @(posedge clk_axi);

        // Xác nhận không còn entry ma ở bất kỳ FIFO/ROB/WDS/IQ/QoS queue nào sau reset giữa burst
        tb_check(dut.u_rob.o_rob_empty === 1'b1 && dut.u_rob.o_rob_count === '0,
                 $sformatf("[H-1] ROB has 0 phantom entries after mid-burst reset (empty=%b count=%0d)",
                           dut.u_rob.o_rob_empty, dut.u_rob.o_rob_count));
        tb_check(dut.u_wdata_buffer.o_cmd_valid === 1'b0 && dut.u_wdata_buffer.o_data_valid === 1'b0,
                 "[H-1] wdata_buffer has 0 phantom entries after mid-burst reset");
        tb_check(dut.u_wds.slot_busy === '0 && dut.u_wds.beats_avail === '0,
                 $sformatf("[H-1] wr_data_store has 0 phantom slots/beats after mid-burst reset (busy=%h beats=%0d)",
                           dut.u_wds.slot_busy, dut.u_wds.beats_avail));
        tb_check(dut.u_rd_iq.o_empty === 1'b1 && dut.u_rd_iq.v === '0,
                 "[H-1] rd_issue_queue has 0 phantom entries after mid-burst reset");
        tb_check(dut.u_qos_queue.o_cand_valid === '0 && dut.credit_cnt_err === 1'b0,
                 "[H-1] qos_scheduler_queue and bank_credit_ctrl clean after mid-burst reset");
        tb_check(s_axi_bvalid === 1'b0 && s_axi_rvalid === 1'b0,
                 "[H-1] No spurious BVALID or RVALID emitted after mid-burst reset");

        // Chạy giao dịch ghi + đọc 4-beat sau reset để chứng minh đường dữ liệu phục hồi hoàn toàn
        sb_enable        = 1'b1;
        sb_wr_matched    = 0;
        sb_wr_mismatch   = 0;
        sb_rd_matched    = 0;
        sb_rd_mismatch   = 0;
        ar_issued_cnt    = 0;
        r_bursts_done    = 0;
        r_beats_expected = 0;
        r_beats_got      = 0;
        r_resp_err       = 0;
        b_done_cnt       = 0;

        @(negedge clk_axi);
        s_axi_awid    <= 4'h5;
        s_axi_awaddr  <= 32'h0010_4000;
        s_axi_awlen   <= 8'd3;
        s_axi_awvalid <= 1'b1;
        while (!s_axi_awready) @(posedge clk_axi);
        @(negedge clk_axi);
        s_axi_awvalid <= 1'b0;
        for (int b = 0; b < 4; b++) begin
            s_axi_wdata  <= 64'h55AA_0000_0000_1000 + 64'(b);
            s_axi_wstrb  <= 8'hFF;
            s_axi_wlast  <= (b == 3);
            s_axi_wvalid <= 1'b1;
            while (!s_axi_wready) @(posedge clk_axi);
            @(negedge clk_axi);
        end
        s_axi_wvalid <= 1'b0;
        s_axi_wlast  <= 1'b0;

        while (b_done_cnt < 1) @(posedge clk_axi);
        repeat (30) @(posedge clk_axi);

        @(negedge clk_axi);
        s_axi_arid    <= 4'h5;
        s_axi_araddr  <= 32'h0010_4000;
        s_axi_arlen   <= 8'd3;
        s_axi_arvalid <= 1'b1;
        while (!s_axi_arready) @(posedge clk_axi);
        @(negedge clk_axi);
        s_axi_arvalid <= 1'b0;

        for (int c = 0; c < 200; c++) begin
            if (r_bursts_done == 1) c = 200;
            else @(posedge clk_axi);
        end
        repeat (10) @(posedge clk_axi);

        tb_check(b_done_cnt == 1 && r_bursts_done == 1 && r_beats_got == 4 &&
                 sb_wr_matched == 1 && sb_rd_matched == 1,
                 $sformatf("[H-1 RECOVERY] Post-reset 4-beat write+read succeeded cleanly (WR=%0d RD=%0d beats=%0d)",
                           sb_wr_matched, sb_rd_matched, r_beats_got));

        tb_report();
        $finish;
    end

    initial begin
        #400_000;
        $fatal(1, "[WATCHDOG] check_t11_main_path timed out");
    end
endmodule
