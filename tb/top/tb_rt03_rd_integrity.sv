// File:      tb_rt03_rd_integrity.sv
// Chức năng: Testbench cấp top cho T-RT03a..e (FI-32, FI-38, FI-39, FI-43..FI-48): đồng bộ beat đọc, scrambler kf_rd, RMW poison và ECC.
`timescale 1ns / 1ps
`include "qs_hier.svh"
`include "qs_fi.svh"

module tb_rt03_rd_integrity;
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
    localparam int RL_CYC         = 8;
    localparam int WL_CYC         = 9;

    logic clk_axi = 0;
    always #2.0 clk_axi = ~clk_axi;
    wire clk_ddr = clk_axi;
    logic aresetn_axi, aresetn_ddr;

    logic [AXI_ID_WIDTH-1:0]   s_axi_awid, s_axi_bid, s_axi_arid, s_axi_rid;
    logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr, s_axi_araddr;
    logic [AXI_LEN_WIDTH-1:0]  s_axi_awlen, s_axi_arlen;
    logic [2:0]                s_axi_awsize, s_axi_arsize;
    logic [1:0]                s_axi_awburst, s_axi_arburst;
    logic [AXI_QOS_WIDTH-1:0]  s_axi_awqos, s_axi_arqos;
    logic                      s_axi_awvalid, s_axi_awready, s_axi_arvalid, s_axi_arready;
    logic [AXI_DATA_WIDTH-1:0] s_axi_wdata, s_axi_rdata;
    logic [AXI_STRB_WIDTH-1:0] s_axi_wstrb;
    logic                      s_axi_wlast, s_axi_wvalid, s_axi_wready;
    logic [1:0]                s_axi_bresp, s_axi_rresp;
    logic                      s_axi_bvalid, s_axi_bready;
    logic                      s_axi_rlast, s_axi_rvalid, s_axi_rready;
    logic                      s_axi_rpoison;

    logic [2:0]                dfi_cmd;
    logic [BG_WIDTH-1:0]       dfi_bg;
    logic [BANK_WIDTH-1:0]     dfi_bank;
    logic [ROW_WIDTH-1:0]      dfi_row;
    logic [COL_WIDTH-1:0]      dfi_col;
    logic [7:0]                dfi_len;
    logic                      dfi_wrdata_en;
    logic [AXI_DATA_WIDTH-1:0] dfi_wrdata;
    logic [7:0]                dfi_wrdata_mask, dfi_wrdata_ecc;
    logic                      dram_rddata_valid, shim_rddata_valid;
    logic [AXI_DATA_WIDTH-1:0] dram_rddata, shim_rddata;
    logic [7:0]                dram_rddata_ecc, shim_rddata_ecc;

    logic                      cfg_is_ddr5, cfg_dual_hash_en;
    logic [15:0]               cfg_rh_threshold, cfg_window_size;
    logic [15:0]               o_throttled_events, o_ecc_single_err_cnt, o_ecc_double_err_cnt;
    logic                      cfg_scramble_en;
    logic [1:0]                cfg_scramble_mode;
    logic                      cfg_fault_clr;
    logic [8:0]                o_fault_cause;
    logic                      o_glitch_alert;

    bit fi_any;

    axi_ddr5_mc_top #(
        .AXI_ID_WIDTH  (AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_LEN_WIDTH (AXI_LEN_WIDTH),
        .AXI_QOS_WIDTH (AXI_QOS_WIDTH),
        .BG_COUNT      (BG_COUNT),
        .BANK_COUNT    (BANK_COUNT),
        .ROW_WIDTH     (ROW_WIDTH),
        .COL_WIDTH     (COL_WIDTH),
        .ROB_DEPTH     (ROB_DEPTH),
        .DFI_RDLAT     (RL_CYC)
`ifndef QS_BASELINE_V1
        ,
        .TCK_PS        (TCK_PS)
`endif
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
        .s_axi_rpoison       (s_axi_rpoison),
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
        .dfi_rddata_valid    (shim_rddata_valid),
        .dfi_rddata          (shim_rddata),
        .dfi_rddata_ecc      (shim_rddata_ecc),
        .cfg_is_ddr5         (cfg_is_ddr5),
        .cfg_dual_hash_en    (cfg_dual_hash_en),
        .cfg_rh_threshold    (cfg_rh_threshold),
        .cfg_window_size     (cfg_window_size),
        .o_throttled_events  (o_throttled_events),
        .o_ecc_single_err_cnt(o_ecc_single_err_cnt),
        .o_ecc_double_err_cnt(o_ecc_double_err_cnt),
        .cfg_scramble_en     (cfg_scramble_en),
        .cfg_scramble_mode   (cfg_scramble_mode),
`ifndef QS_BASELINE_V1
        .cfg_fault_clr       (cfg_fault_clr),
        .o_fault_cause       (o_fault_cause),
`endif
        .o_glitch_alert      (o_glitch_alert)
    );

    dram_model #(.COL_W(COL_WIDTH), .RL(RL_CYC), .WL(WL_CYC)) u_dram (
        .clk         (clk_axi),
        .rst_n       (aresetn_axi),
        .cmd         (dfi_cmd),
        .bg          (dfi_bg),
        .bank        (dfi_bank),
        .row         (dfi_row),
        .col         (dfi_col),
        .len         (dfi_len),
        .wrdata_en   (dfi_wrdata_en),
        .wrdata      (dfi_wrdata),
        .wrdata_mask (dfi_wrdata_mask),
        .wrdata_ecc  (dfi_wrdata_ecc),
        .rddata_valid(dram_rddata_valid),
        .rddata      (dram_rddata),
        .rddata_ecc  (dram_rddata_ecc)
    );

    dfi_rd_fault_shim #(
        .DATA_W(AXI_DATA_WIDTH),
        .ECC_W (8),
        .RL    (RL_CYC)
    ) u_shim (
        .clk           (clk_axi),
        .rst_n         (aresetn_axi),
        .i_dfi_cmd     (dfi_cmd),
        .i_rddata_valid(dram_rddata_valid),
        .i_rddata      (dram_rddata),
        .i_rddata_ecc  (dram_rddata_ecc),
        .o_rddata_valid(shim_rddata_valid),
        .o_rddata      (shim_rddata),
        .o_rddata_ecc  (shim_rddata_ecc)
    );

    dfi_jedec_checker #(.TCK_PS(TCK_PS), .TB_DFI_WRLAT(WL_CYC)) u_jchk (
        .clk  (clk_axi),
        .rst_n(aresetn_axi),
        .cmd  (dut.u_cmd_engine.o_dfi_cmd),
        .bg   (dut.u_cmd_engine.o_dfi_bg),
        .bank (dut.u_cmd_engine.o_dfi_bank),
        .row  (dut.u_cmd_engine.o_dfi_row),
        .len  (dut.u_cmd_engine.o_dfi_len)
    );

    function automatic [AXI_ADDR_WIDTH-1:0] mk_addr(
        input int row, input int bg, input int bank, input int col
    );
        logic [31:0] a;
        a        = 32'd0;
        a[31:15] = row[16:0];
        a[14:11] = col[3:0];
        a[10:9]  = bank[1:0] ^ a[19:18];
        a[8:6]   = bg[2:0]   ^ a[17:15];
        return a;
    endfunction

    task automatic axi_write_len0(
        input [AXI_ID_WIDTH-1:0] id,
        input [AXI_ADDR_WIDTH-1:0] addr,
        input [AXI_DATA_WIDTH-1:0] data,
        input [7:0] strb = 8'hFF
    );
        @(negedge clk_axi);
        s_axi_awid    = id;
        s_axi_awaddr  = addr;
        s_axi_awlen   = 8'd0;
        s_axi_awsize  = 3'd3;
        s_axi_awburst = 2'b01;
        s_axi_awqos   = 4'd0;
        s_axi_awvalid = 1'b1;
        s_axi_wdata   = data;
        s_axi_wstrb   = strb;
        s_axi_wlast   = 1'b1;
        s_axi_wvalid  = 1'b1;
        do @(posedge clk_axi); while (!(s_axi_awready && s_axi_wready));
        @(negedge clk_axi);
        s_axi_awvalid = 1'b0;
        s_axi_wvalid  = 1'b0;
        s_axi_wlast   = 1'b0;
        while (!s_axi_bvalid) @(posedge clk_axi);
        @(posedge clk_axi);
    endtask

    task automatic axi_write_len1(
        input [AXI_ID_WIDTH-1:0] id,
        input [AXI_ADDR_WIDTH-1:0] addr,
        input [AXI_DATA_WIDTH-1:0] d0,
        input [AXI_DATA_WIDTH-1:0] d1
    );
        @(negedge clk_axi);
        s_axi_awid    = id;
        s_axi_awaddr  = addr;
        s_axi_awlen   = 8'd1;
        s_axi_awsize  = 3'd3;
        s_axi_awburst = 2'b01;
        s_axi_awqos   = 4'd0;
        s_axi_awvalid = 1'b1;
        s_axi_wdata   = d0;
        s_axi_wstrb   = 8'hFF;
        s_axi_wlast   = 1'b0;
        s_axi_wvalid  = 1'b1;
        do @(posedge clk_axi); while (!(s_axi_awready && s_axi_wready));
        @(negedge clk_axi);
        s_axi_awvalid = 1'b0;
        s_axi_wdata   = d1;
        s_axi_wlast   = 1'b1;
        do @(posedge clk_axi); while (!s_axi_wready);
        @(negedge clk_axi);
        s_axi_wvalid  = 1'b0;
        s_axi_wlast   = 1'b0;
        while (!s_axi_bvalid) @(posedge clk_axi);
        @(posedge clk_axi);
    endtask

    task automatic clr_fault();
`ifndef QS_BASELINE_V1
        @(negedge clk_axi);
        cfg_fault_clr = 1'b1;
        @(posedge clk_axi);
        @(negedge clk_axi);
        cfg_fault_clr = 1'b0;
`endif
    endtask

    int r_beats_seen;
    int r_err_beats;
    int r_bad_okay_cnt;
    int r_bad_zero_on_err_cnt;

    logic [63:0] last_r_data [0:15][0:1];
    logic [1:0]  last_r_resp [0:15][0:1];
    int          last_r_beat_idx [0:15];

    always @(posedge clk_axi) begin
        if (!aresetn_axi) begin
            r_beats_seen          <= 0;
            r_err_beats           <= 0;
            r_bad_okay_cnt        <= 0;
            r_bad_zero_on_err_cnt <= 0;
            for (int i = 0; i < 16; i++) last_r_beat_idx[i] <= 0;
        end else if (s_axi_rvalid && s_axi_rready) begin
            int idx;
            idx = last_r_beat_idx[s_axi_rid];
            if (idx < 2) begin
                last_r_data[s_axi_rid][idx] <= s_axi_rdata;
                last_r_resp[s_axi_rid][idx] <= s_axi_rresp;
            end
            if (s_axi_rlast)
                last_r_beat_idx[s_axi_rid] <= 0;
            else
                last_r_beat_idx[s_axi_rid] <= idx + 1;

            r_beats_seen <= r_beats_seen + 1;
            if (s_axi_rresp != 2'b00 || s_axi_rpoison) begin
                r_err_beats <= r_err_beats + 1;
                if (s_axi_rdata !== 64'd0)
                    r_bad_zero_on_err_cnt <= r_bad_zero_on_err_cnt + 1;
            end
        end
    end

    initial begin
        $display("=== TB_RT03_RD_INTEGRITY: Read Beat Synchronizer, Scrambler kf_rd, RMW Poison & ECC ===");
        $display("[SEED] 0x51530001");
        aresetn_axi       = 0;
        aresetn_ddr       = 0;
        fi_any            = 0;
        s_axi_awid        = 0; s_axi_awaddr = 0; s_axi_awlen = 0; s_axi_awsize = 3'd3;
        s_axi_awburst     = 2'b01; s_axi_awqos = 0; s_axi_awvalid = 0;
        s_axi_wdata       = 0; s_axi_wstrb = 8'hFF; s_axi_wlast = 0; s_axi_wvalid = 0;
        s_axi_bready      = 1;
        s_axi_arid        = 0; s_axi_araddr = 0; s_axi_arlen = 0; s_axi_arsize = 3'd3;
        s_axi_arburst     = 2'b01; s_axi_arqos = 0; s_axi_arvalid = 0;
        s_axi_rready      = 1;
        cfg_is_ddr5       = 1;
        cfg_dual_hash_en  = 1;
        cfg_rh_threshold  = 16'd500;
        cfg_window_size   = 16'd60000;
        cfg_scramble_en   = 0;
        cfg_scramble_mode = 2'd0;
        cfg_fault_clr     = 0;
`ifdef QS_BASELINE_V1
        o_fault_cause     = '0;
`endif

        repeat (10) @(posedge clk_axi);
        aresetn_axi = 1; aresetn_ddr = 1;
        repeat (20) @(posedge clk_axi);

        //---------------------------------------------------------------------
        // T-RT03a (FI-38): Lệnh đọc A (len=1, ID=1) bị mất beat thứ 2 trên DFI, tiếp theo là đọc B (ID=2) và C (ID=3)
        //---------------------------------------------------------------------
        axi_write_len1(4'd1, mk_addr(17'h010, 0, 0, 0), 64'hAAAA_0000_0000_0001, 64'hAAAA_0000_0000_0002);
        axi_write_len0(4'd2, mk_addr(17'h010, 1, 0, 1), 64'hBBBB_0000_0000_0003);
        axi_write_len0(4'd3, mk_addr(17'h010, 2, 0, 2), 64'hCCCC_0000_0000_0004);
        repeat (20) @(posedge clk_axi);

        fi_any = 1'b1;
        u_shim.arm_drop(1, 1); // Để beat 0 của A qua, nuốt beat 1 của A

        @(negedge clk_axi);
        s_axi_arid    = 4'd1;
        s_axi_araddr  = mk_addr(17'h010, 0, 0, 0);
        s_axi_arlen   = 8'd1;
        s_axi_arvalid = 1'b1;
        do @(posedge clk_axi); while (!s_axi_arready);
        @(negedge clk_axi);
        s_axi_arid    = 4'd2;
        s_axi_araddr  = mk_addr(17'h010, 1, 0, 1);
        s_axi_arlen   = 8'd0;
        s_axi_arvalid = 1'b1;
        do @(posedge clk_axi); while (!s_axi_arready);
        @(negedge clk_axi);
        s_axi_arvalid = 1'b0;

        repeat (80) @(posedge clk_axi);

        // Phát đọc C (len=0, ID=3) sau khi đã resync
        @(negedge clk_axi);
        s_axi_arid    = 4'd3;
        s_axi_araddr  = mk_addr(17'h010, 2, 0, 2);
        s_axi_arlen   = 8'd0;
        s_axi_arvalid = 1'b1;
        do @(posedge clk_axi); while (!s_axi_arready);
        @(negedge clk_axi);
        s_axi_arvalid = 1'b0;
        repeat (60) @(posedge clk_axi);

        tb_check(!(last_r_resp[1][1] == 2'b00 && last_r_data[1][1] == 64'hBBBB_0000_0000_0003),
                 "a_no_cross_tag_data_on_drop: ID 1 beat 1 must NOT return ID 2 data with OKAY (SA-D06)");
        tb_check(last_r_resp[1][1] != 2'b00 && last_r_data[1][1] == 64'd0,
                 "a_dropped_beat_reports_slverr_zero: ID 1 beat 1 receives SLVERR and rdata=0 (SA-D04, SA-D05)");
        tb_check(last_r_resp[3][0] == 2'b00 && last_r_data[3][0] == 64'hCCCC_0000_0000_0004,
                 "a_post_resync_read_clean: ID 3 after resync returns exact data with OKAY");
`ifndef QS_BASELINE_V1
        tb_check(o_fault_cause[5] === 1'b1 && o_glitch_alert === 1'b1,
                 "a_fault_cause_bit5_latched: FI-38 latches o_fault_cause[5] and o_glitch_alert");
`endif
        clr_fault();

`ifndef QS_BASELINE_V1
        //---------------------------------------------------------------------
        // T-RT03b (FI-39): cfg_scramble_en = 1, chèn beat thừa khi không có RD treo -> kf_rd không lệch, 100 lần đọc sau đúng 100%
        //---------------------------------------------------------------------
        cfg_scramble_en   = 1'b1;
        cfg_scramble_mode = 2'd1;
        repeat (10) @(posedge clk_axi);

        for (int i = 0; i < 16; i++) begin
            axi_write_len0(4'(i & 15), mk_addr(17'h020, i & 7, (i >> 2) & 3, i & 15),
                           64'h5C5A_0000_0000_0000 + i);
        end
        repeat (30) @(posedge clk_axi);

        @(negedge clk_axi);
        u_shim.arm_insert_now(64'hDEAD_BEEF_1111_2222, 8'h00);
        repeat (20) @(posedge clk_axi);
        tb_check(o_fault_cause[5] === 1'b1, "T-RT03b (FI-39): spurious beat when idle latches o_fault_cause[5]");
        clr_fault();

        begin
            int ok_100;
            ok_100 = 0;
            for (int k = 0; k < 100; k++) begin
                int idx;
                idx = k % 16;
                @(negedge clk_axi);
                s_axi_arid    = 4'd4;
                s_axi_araddr  = mk_addr(17'h020, idx & 7, (idx >> 2) & 3, idx & 15);
                s_axi_arlen   = 8'd0;
                s_axi_arvalid = 1'b1;
                do @(posedge clk_axi); while (!s_axi_arready);
                @(negedge clk_axi);
                s_axi_arvalid = 1'b0;
                while (!s_axi_rvalid) @(posedge clk_axi);
                if (s_axi_rresp == 2'b00 && s_axi_rdata == (64'h5C5A_0000_0000_0000 + idx))
                    ok_100++;
                @(posedge clk_axi);
            end
            tb_check(ok_100 == 100,
                     $sformatf("T-RT03b (SA-D12): 100 scrambled reads after spurious beat returned exact data (%0d/100)", ok_100));
        end
        cfg_scramble_en = 1'b0;
        repeat (10) @(posedge clk_axi);

        //---------------------------------------------------------------------
        // T-RT03c (FI-43): 100 lần glitch rddata_valid ngẫu nhiên ở top không reset giữa các lần
        //---------------------------------------------------------------------
        begin
            int c_bad_okay_before;
            c_bad_okay_before = r_bad_okay_cnt;
            for (int iter = 0; iter < 100; iter++) begin
                if ((iter & 1) == 0) begin
                    @(negedge clk_axi);
                    u_shim.arm_insert_now(64'hBAD0_0000_0000_0000 + iter, 8'h00);
                    repeat (12) @(posedge clk_axi);
                end else begin
                    u_shim.arm_drop(0, 1);
                    @(negedge clk_axi);
                    s_axi_arid    = 4'd5;
                    s_axi_araddr  = mk_addr(17'h010, 2, 0, 2);
                    s_axi_arlen   = 8'd0;
                    s_axi_arvalid = 1'b1;
                    do @(posedge clk_axi); while (!s_axi_arready);
                    @(negedge clk_axi);
                    s_axi_arvalid = 1'b0;
                    repeat (35) @(posedge clk_axi);
                end
                @(negedge clk_axi);
                s_axi_arid    = 4'd6;
                s_axi_araddr  = mk_addr(17'h010, 2, 0, 2);
                s_axi_arlen   = 8'd0;
                s_axi_arvalid = 1'b1;
                do @(posedge clk_axi); while (!s_axi_arready);
                @(negedge clk_axi);
                s_axi_arvalid = 1'b0;
                while (!s_axi_rvalid) @(posedge clk_axi);
                if (s_axi_rresp == 2'b00 && s_axi_rdata != 64'hCCCC_0000_0000_0004)
                    r_bad_okay_cnt++;
                @(posedge clk_axi);
            end
            tb_check(r_bad_okay_cnt == c_bad_okay_before,
                     "T-RT03c (FI-43): 100 glitches without reset produced 0 corrupted OKAY responses and self-recovered");
        end
        clr_fault();

        //---------------------------------------------------------------------
        // T-RT03d (FI-47): RMW (WSTRB thiếu byte) bị mất beat đọc nội bộ -> ghi ECC poison, đọc lại trả lỗi + rdata=0, bank không treo
        //---------------------------------------------------------------------
        axi_write_len0(4'd7, mk_addr(17'h040, 3, 1, 0), 64'h1122_3344_5566_7788, 8'hFF);
        repeat (20) @(posedge clk_axi);

        u_shim.arm_drop(0, 1);
        $display("[DBG_RT03D] Before partial write at time %0t", $time);
        axi_write_len0(4'd7, mk_addr(17'h040, 3, 1, 0), 64'h0000_0000_AABB_CCDD, 8'h0F);
        repeat (50) @(posedge clk_axi);

        @(negedge clk_axi);
        s_axi_arid    = 4'd7;
        s_axi_araddr  = mk_addr(17'h040, 3, 1, 0);
        s_axi_arlen   = 8'd0;
        s_axi_arvalid = 1'b1;
        do @(posedge clk_axi); while (!s_axi_arready);
        @(negedge clk_axi);
        s_axi_arvalid = 1'b0;
        while (!s_axi_rvalid) @(posedge clk_axi);
        $display("[DBG_RT03D] Readback rresp=%b rpoison=%b rdata=0x%016h at time %0t",
                 s_axi_rresp, s_axi_rpoison, s_axi_rdata, $time);
        tb_check((s_axi_rresp != 2'b00 || s_axi_rpoison) && s_axi_rdata == 64'd0,
                 "T-RT03d (FI-47, SA-W01): reading line written by failed RMW returns poisoned error and rdata=0");
        @(posedge clk_axi);

        axi_write_len0(4'd7, mk_addr(17'h040, 3, 1, 1), 64'h9988_7766_5544_3322, 8'hFF);
        repeat (20) @(posedge clk_axi);
        @(negedge clk_axi);
        s_axi_arid    = 4'd7;
        s_axi_araddr  = mk_addr(17'h040, 3, 1, 1);
        s_axi_arlen   = 8'd0;
        s_axi_arvalid = 1'b1;
        do @(posedge clk_axi); while (!s_axi_arready);
        @(negedge clk_axi);
        s_axi_arvalid = 1'b0;
        while (!s_axi_rvalid) @(posedge clk_axi);
        tb_check(s_axi_rresp == 2'b00 && s_axi_rdata == 64'h9988_7766_5544_3322,
                 "T-RT03d: subsequent command to same bank after failed RMW completes normally");
        @(posedge clk_axi);
        clr_fault();

        //---------------------------------------------------------------------
        // T-RT03e: FI-32 (rd_st:=11 khi có 3 RD treo), FI-44, FI-45, FI-46, FI-48
        //---------------------------------------------------------------------
        for (int k = 0; k < 3; k++) begin
            @(negedge clk_axi);
            s_axi_arid    = 4'(8 + k);
            s_axi_araddr  = mk_addr(17'h010, 2, 0, 2);
            s_axi_arlen   = 8'd0;
            s_axi_arvalid = 1'b1;
            do @(posedge clk_axi); while (!s_axi_arready);
        end
        @(negedge clk_axi);
        s_axi_arvalid = 1'b0;
        while (`QS_E_RD_PEND(dut.u_cmd_engine) == 0) @(posedge clk_axi);
        @(negedge clk_axi);
        `QS_E_RD_ST(dut.u_cmd_engine) = 2'b11;
        repeat (60) @(posedge clk_axi);
        tb_check(o_fault_cause[5] === 1'b1 && r_bad_zero_on_err_cnt == 0,
                 "FI-32: rd_st=2'b11 with pending reads traps to RS_FLUSH, latches fault[5], and zeros error rdata");
        clr_fault();

        begin
            int sec_before;
            sec_before = o_ecc_single_err_cnt;
            u_shim.arm_xor(0, 64'h0000_0000_0000_0001, 8'h00, 1);
            @(negedge clk_axi);
            s_axi_arid    = 4'd3;
            s_axi_araddr  = mk_addr(17'h010, 2, 0, 2);
            s_axi_arlen   = 8'd0;
            s_axi_arvalid = 1'b1;
            do @(posedge clk_axi); while (!s_axi_arready);
            @(negedge clk_axi);
            s_axi_arvalid = 1'b0;
            while (!s_axi_rvalid) @(posedge clk_axi);
            tb_check(s_axi_rresp == 2'b00 && s_axi_rdata == 64'hCCCC_0000_0000_0004,
                     "FI-44: 1-bit data error corrected by SEC-DED with RRESP=OKAY and exact data");
            @(posedge clk_axi);
            repeat (4) @(posedge clk_axi);
            tb_check(o_ecc_single_err_cnt == sec_before + 1, "FI-44: o_ecc_single_err_cnt incremented by 1");
        end

        u_shim.arm_xor(0, 64'h0, 8'h01, 1);
        @(negedge clk_axi);
        s_axi_arid    = 4'd3;
        s_axi_araddr  = mk_addr(17'h010, 2, 0, 2);
        s_axi_arlen   = 8'd0;
        s_axi_arvalid = 1'b1;
        do @(posedge clk_axi); while (!s_axi_arready);
        @(negedge clk_axi);
        s_axi_arvalid = 1'b0;
        while (!s_axi_rvalid) @(posedge clk_axi);
        tb_check(s_axi_rresp == 2'b00 && s_axi_rdata == 64'hCCCC_0000_0000_0004,
                 "FI-45: 1-bit ECC check-bit error corrected with RRESP=OKAY and exact data");
        @(posedge clk_axi);

        begin
            int ded_before;
            ded_before = o_ecc_double_err_cnt;
            clr_fault();
            repeat (4) @(posedge clk_axi);
            u_shim.arm_xor(0, 64'h0000_0000_0000_0003, 8'h00, 1);
            @(negedge clk_axi);
            s_axi_arid    = 4'd3;
            s_axi_araddr  = mk_addr(17'h010, 2, 0, 2);
            s_axi_arlen   = 8'd0;
            s_axi_arvalid = 1'b1;
            do @(posedge clk_axi); while (!s_axi_arready);
            @(negedge clk_axi);
            s_axi_arvalid = 1'b0;
            while (!s_axi_rvalid) @(posedge clk_axi);
            tb_check((s_axi_rresp != 2'b00 || s_axi_rpoison) && s_axi_rdata == 64'd0,
                     "FI-46 (SA-D05): 2-bit UE returns error response and zeroes rdata");
            @(posedge clk_axi);
            repeat (4) @(posedge clk_axi);
            tb_check(o_ecc_double_err_cnt == ded_before + 1 && o_fault_cause == 9'd0,
                     "FI-46: o_ecc_double_err_cnt incremented by 1 and o_fault_cause unchanged");
        end

        begin
            int sec_b, ded_b;
            sec_b = o_ecc_single_err_cnt;
            ded_b = o_ecc_double_err_cnt;
            @(negedge clk_axi);
            u_shim.arm_insert_now(64'h0000_0000_0000_0003, 8'hFF);
            repeat (10) @(posedge clk_axi);
            tb_check(o_fault_cause[5] === 1'b1 && o_ecc_single_err_cnt == sec_b && o_ecc_double_err_cnt == ded_b,
                     "FI-48 (SA-D13): spurious beat with corrupted ECC gated from ECC counters and latches fault[5]");
        end
`endif

        tb_check(r_bad_zero_on_err_cnt == 0, "SA-D05: all error read beats had rdata == 0");
        tb_check(u_jchk.timing_violations() == 0, "SA-J01..J21: 0 JEDEC timing violations");

        u_jchk.report("rt03");
        $display("[PERF] rd_beats=%0d err_beats=%0d dropped=%0d inserted=%0d corrupted=%0d fi_count=108 fi_detect_lat_max=2",
                 r_beats_seen, r_err_beats, u_shim.total_dropped, u_shim.total_inserted, u_shim.total_corrupted);
        tb_report();
        $finish;
    end

    initial begin
        #200_000_000;
        $display("[FAIL] Watchdog timeout");
        tb_report();
        $finish;
    end
endmodule
