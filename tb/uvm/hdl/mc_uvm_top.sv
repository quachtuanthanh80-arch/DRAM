// File: mc_uvm_top.sv
// Chức năng: Khối bọc HDL cho môi trường pyuvm kết nối axi_ddr5_mc_top với dram_model, checker JEDEC và bộ bơm lỗi $deposit.
`timescale 1ns / 1ps

module mc_uvm_top #(
    parameter int TB_TCK_PS = 4000
);
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

    // Clock & Reset driven from pyuvm/cocotb
    logic clk_axi = 1'b0;
    logic aresetn_axi = 1'b0;
    wire  clk_ddr = clk_axi;
    wire  aresetn_ddr = aresetn_axi;

    // AXI4 Slave Ports
    logic [AXI_ID_WIDTH-1:0]   s_axi_awid = '0;
    logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr = '0;
    logic [AXI_LEN_WIDTH-1:0]  s_axi_awlen = '0;
    logic [2:0]                s_axi_awsize = 3'd3;
    logic [1:0]                s_axi_awburst = 2'b01;
    logic [AXI_QOS_WIDTH-1:0]  s_axi_awqos = '0;
    logic                      s_axi_awvalid = 1'b0;
    logic                      s_axi_awready;

    logic [AXI_DATA_WIDTH-1:0] s_axi_wdata = '0;
    logic [AXI_STRB_WIDTH-1:0] s_axi_wstrb = 8'hFF;
    logic                      s_axi_wlast = 1'b0;
    logic                      s_axi_wvalid = 1'b0;
    logic                      s_axi_wready;

    logic [AXI_ID_WIDTH-1:0]   s_axi_bid;
    logic [1:0]                s_axi_bresp;
    logic                      s_axi_bvalid;
    logic                      s_axi_bready = 1'b1;

    logic [AXI_ID_WIDTH-1:0]   s_axi_arid = '0;
    logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr = '0;
    logic [AXI_LEN_WIDTH-1:0]  s_axi_arlen = '0;
    logic [2:0]                s_axi_arsize = 3'd3;
    logic [1:0]                s_axi_arburst = 2'b01;
    logic [AXI_QOS_WIDTH-1:0]  s_axi_arqos = '0;
    logic                      s_axi_arvalid = 1'b0;
    logic                      s_axi_arready;

    logic [AXI_ID_WIDTH-1:0]   s_axi_rid;
    logic [AXI_DATA_WIDTH-1:0] s_axi_rdata;
    logic [1:0]                s_axi_rresp;
    logic                      s_axi_rlast;
    logic                      s_axi_rvalid;
    logic                      s_axi_rready = 1'b1;
    logic [0:0]                s_axi_rpoison;
    logic [AXI_STRB_WIDTH-1:0] s_axi_rchk;
    logic                      o_parity_err;

    // DFI Interface wires (observable by DfiDramAgent)
    logic [2:0]                dfi_cmd;
    logic [BG_WIDTH-1:0]       dfi_bg;
    logic [BANK_WIDTH-1:0]     dfi_bank;
    logic [ROW_WIDTH-1:0]      dfi_row;
    logic [COL_WIDTH-1:0]      dfi_col;
    logic [7:0]                dfi_len;
    logic                      dfi_wrdata_en;
    logic [AXI_DATA_WIDTH-1:0] dfi_wrdata;
    logic [AXI_STRB_WIDTH-1:0] dfi_wrdata_mask;
    logic [AXI_STRB_WIDTH-1:0] dfi_wrdata_ecc;
    logic                      dfi_rddata_valid;
    logic [AXI_DATA_WIDTH-1:0] dfi_rddata;
    logic [AXI_STRB_WIDTH-1:0] dfi_rddata_ecc;

    // Runtime configuration ports
    logic                      cfg_is_ddr5 = 1'b1;
    logic                      cfg_dual_hash_en = 1'b1;
    logic [15:0]               cfg_rh_threshold = 16'd500;
    logic [15:0]               cfg_window_size = 16'd60000;
    logic                      cfg_bank_coloring_en = 1'b0;
    logic [1:0]                cfg_mapping_mode = 2'b00;
    logic                      cfg_scramble_en = 1'b0;
    logic                      cfg_scramble_reseed = 1'b0;
    logic [63:0]               cfg_scramble_seed = 64'hA5A5_5A5A_0123_4567;
    logic [1:0]                cfg_scramble_mode = 2'b00;
    logic                      cfg_decoy_en = 1'b0;
    logic                      cfg_fault_clr = 1'b0;
    logic                      cfg_parity_check_en = 1'b0;

    // Telemetry outputs
    logic [15:0]               o_throttled_events;
    logic [15:0]               o_ecc_single_err_cnt;
    logic [15:0]               o_ecc_double_err_cnt;
    logic [8:0]                o_fault_cause;
    logic                      o_glitch_alert;
    logic                      o_rob_raw_hazard;
    logic [31:0]               dram_err_total;
    logic [31:0]               jedec_viol_cnt;

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
        .TCK_PS         (TB_TCK_PS)
    ) dut (
        .clk_axi              (clk_axi),
        .aresetn_axi          (aresetn_axi),
        .clk_ddr              (clk_ddr),
        .aresetn_ddr          (aresetn_ddr),
        .s_axi_awid           (s_axi_awid),
        .s_axi_awaddr         (s_axi_awaddr),
        .s_axi_awlen          (s_axi_awlen),
        .s_axi_awsize         (s_axi_awsize),
        .s_axi_awburst        (s_axi_awburst),
        .s_axi_awqos          (s_axi_awqos),
        .s_axi_awvalid        (s_axi_awvalid),
        .s_axi_awready        (s_axi_awready),
        .s_axi_wdata          (s_axi_wdata),
        .s_axi_wstrb          (s_axi_wstrb),
        .s_axi_wlast          (s_axi_wlast),
        .s_axi_wvalid         (s_axi_wvalid),
        .s_axi_wready         (s_axi_wready),
        .s_axi_bid            (s_axi_bid),
        .s_axi_bresp          (s_axi_bresp),
        .s_axi_bvalid         (s_axi_bvalid),
        .s_axi_bready         (s_axi_bready),
        .s_axi_arid           (s_axi_arid),
        .s_axi_araddr         (s_axi_araddr),
        .s_axi_arlen          (s_axi_arlen),
        .s_axi_arsize         (s_axi_arsize),
        .s_axi_arburst        (s_axi_arburst),
        .s_axi_arqos          (s_axi_arqos),
        .s_axi_arvalid        (s_axi_arvalid),
        .s_axi_arready        (s_axi_arready),
        .s_axi_rid            (s_axi_rid),
        .s_axi_rdata          (s_axi_rdata),
        .s_axi_rresp          (s_axi_rresp),
        .s_axi_rlast          (s_axi_rlast),
        .s_axi_rvalid         (s_axi_rvalid),
        .s_axi_rready         (s_axi_rready),
        .s_axi_rpoison        (s_axi_rpoison),
        .s_axi_rchk           (s_axi_rchk),
        .o_parity_err         (o_parity_err),
        .dfi_cmd              (dfi_cmd),
        .dfi_bg               (dfi_bg),
        .dfi_bank             (dfi_bank),
        .dfi_row              (dfi_row),
        .dfi_col              (dfi_col),
        .dfi_len              (dfi_len),
        .dfi_wrdata_en        (dfi_wrdata_en),
        .dfi_wrdata           (dfi_wrdata),
        .dfi_wrdata_mask      (dfi_wrdata_mask),
        .dfi_wrdata_ecc       (dfi_wrdata_ecc),
        .dfi_rddata_valid     (dfi_rddata_valid),
        .dfi_rddata           (dfi_rddata),
        .dfi_rddata_ecc       (dfi_rddata_ecc),
        .cfg_is_ddr5          (cfg_is_ddr5),
        .cfg_dual_hash_en     (cfg_dual_hash_en),
        .cfg_rh_threshold     (cfg_rh_threshold),
        .cfg_window_size      (cfg_window_size),
        .o_throttled_events   (o_throttled_events),
        .o_ecc_single_err_cnt (o_ecc_single_err_cnt),
        .o_ecc_double_err_cnt (o_ecc_double_err_cnt),
        .cfg_bank_coloring_en (cfg_bank_coloring_en),
        .cfg_mapping_mode     (cfg_mapping_mode),
        .cfg_scramble_en      (cfg_scramble_en),
        .cfg_scramble_reseed  (cfg_scramble_reseed),
        .cfg_scramble_seed    (cfg_scramble_seed),
        .cfg_scramble_mode    (cfg_scramble_mode),
        .cfg_decoy_en         (cfg_decoy_en),
        .cfg_fault_clr        (cfg_fault_clr),
        .o_fault_cause        (o_fault_cause),
        .o_glitch_alert       (o_glitch_alert),
        .cfg_parity_check_en  (cfg_parity_check_en),
        .o_rob_raw_hazard     (o_rob_raw_hazard)
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

    dfi_jedec_checker #(.TCK_PS(TB_TCK_PS), .TB_DFI_WRLAT(9)) u_jchk (
        .clk   (clk_axi),
        .rst_n (aresetn_axi),
        .cmd   (dut.u_cmd_engine.o_dfi_cmd),
        .bg    (dut.u_cmd_engine.o_dfi_bg),
        .bank  (dut.u_cmd_engine.o_dfi_bank),
        .row   (dut.u_cmd_engine.o_dfi_row),
        .len   (dut.u_cmd_engine.o_dfi_len)
    );

    assign dram_err_total = u_dram.err_dq_conflict + u_dram.err_wr_beats +
                            u_dram.err_wr_orphan + u_dram.err_mem_full;
    assign jedec_viol_cnt = u_jchk.viol_trcd + u_jchk.viol_trp + u_jchk.viol_tras + u_jchk.viol_trasmax +
                            u_jchk.viol_trc + u_jchk.viol_trfc + u_jchk.viol_trfm + u_jchk.viol_cas_closed +
                            u_jchk.viol_act_open + u_jchk.viol_trrd + u_jchk.viol_tfaw + u_jchk.viol_tccd +
                            u_jchk.viol_tccd_wr + u_jchk.viol_twr + u_jchk.viol_twtr +
                            u_jchk.viol_ref_open + u_jchk.viol_refgap;

    // Bộ bơm lỗi điều khiển từ FaultDriver (pyuvm): SEU ($deposit), stuck (force/release), glitch
    // fi_mode: 0=idle, 1=SEU ($deposit), 2=STUCK (force N cycles), 3=GLITCH (1-cyc flip/pulse)
    // fi_target: 0=RAA rolling_act_cnt[0], 1=DRM blkp_a[0], 2=DRM inj_oh[2], 3=engine rcd_z[0]
    logic       fi_trig = 1'b0;
    logic [1:0] fi_mode = 2'd0;
    logic [2:0] fi_target = 3'd0;
    logic [7:0] fi_val = 8'd0;
    logic [7:0] fi_dur = 8'd1;
    logic       fi_busy = 1'b0;
    logic       fi_done = 1'b0;
    logic [7:0] fi_hold_val = 8'd0;

    always @(negedge clk_axi) begin
        fi_done <= 1'b0;
        if (fi_trig && !fi_busy) begin
            fi_busy <= 1'b1;
            if (fi_mode == 2'd1) begin
                // SEU 1 chu ky: $deposit cho vector packed (blkp_a, inj_oh, rcd_z), gan thu tuc cho mang unpacked (rolling_act_cnt[0])
                case (fi_target)
                    3'd0: dut.u_cmd_engine.rolling_act_cnt[0] = dut.u_cmd_engine.rolling_act_cnt[0] ^ fi_val;
                    3'd1: $deposit(dut.u_drm.blkp_a, dut.u_drm.blkp_a ^ fi_val);
                    3'd2: $deposit(dut.u_drm.inj_oh, dut.u_drm.inj_oh ^ fi_val[6:0]);
                    default: $deposit(dut.u_cmd_engine.rcd_z, dut.u_cmd_engine.rcd_z ^ fi_val);
                endcase
                repeat (3) @(negedge clk_axi);
                fi_busy <= 1'b0;
                fi_done <= 1'b1;
            end else if (fi_mode == 2'd2) begin
                // Stuck-at N chu ky bang force/release voi gia tri tinh san (tranh warning Icarus)
                case (fi_target)
                    3'd1: begin
                        fi_hold_val = dut.u_drm.blkp_a ^ fi_val;
                        force dut.u_drm.blkp_a = fi_hold_val;
                    end
                    3'd2: begin
                        fi_hold_val = {1'b0, (dut.u_drm.inj_oh ^ fi_val[6:0])};
                        force dut.u_drm.inj_oh = fi_hold_val[6:0];
                    end
                    default: begin
                        fi_hold_val = dut.u_cmd_engine.rcd_z & ~fi_val;
                        force dut.u_cmd_engine.rcd_z = fi_hold_val;
                    end
                endcase
                repeat (fi_dur) @(negedge clk_axi);
                case (fi_target)
                    3'd1: release dut.u_drm.blkp_a;
                    3'd2: release dut.u_drm.inj_oh;
                    default: release dut.u_cmd_engine.rcd_z;
                endcase
                fi_busy <= 1'b0;
                fi_done <= 1'b1;
            end else begin
                // Glitch 1 chu ky qua $deposit roi dao lai
                $deposit(dut.u_drm.blkp_b, dut.u_drm.blkp_b ^ fi_val);
                @(negedge clk_axi);
                $deposit(dut.u_drm.blkp_b, dut.u_drm.blkp_b ^ fi_val);
                fi_busy <= 1'b0;
                fi_done <= 1'b1;
            end
        end
    end
endmodule
