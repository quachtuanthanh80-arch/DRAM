// File: check_t10_main_hierarchy.sv
// Chức năng: Kiểm chứng đường chính (axi_ddr5_mc_top và toàn bộ cây instance) không phụ thuộc hay instantiate sec_ddr5_controller_top.

`timescale 1ns / 1ps

module check_t10_main_hierarchy;
    `include "tb_check.svh"

    logic clk_axi = 1'b0;
    always #2.0 clk_axi = ~clk_axi;

    logic clk_ddr = 1'b0;
    always #1.25 clk_ddr = ~clk_ddr;

    logic aresetn_axi = 1'b0;
    logic aresetn_ddr = 1'b0;

    wire s_axi_awready;
    wire s_axi_wready;
    wire [3:0] s_axi_bid;
    wire [1:0] s_axi_bresp;
    wire s_axi_bvalid;
    wire s_axi_arready;
    wire [3:0] s_axi_rid;
    wire [63:0] s_axi_rdata;
    wire [1:0] s_axi_rresp;
    wire s_axi_rlast;
    wire s_axi_rvalid;

    // Instantiate canonical production top axi_ddr5_mc_top without compiling sec_ddr5_controller_top.sv
    axi_ddr5_mc_top #(
        .TCK_PS(4000),
        .DFI_RDLAT(8)
    ) dut (
        .clk_axi                        (clk_axi),
        .aresetn_axi                    (aresetn_axi),
        .clk_ddr                        (clk_ddr),
        .aresetn_ddr                    (aresetn_ddr),
        .s_axi_awid                     (4'd0),
        .s_axi_awaddr                   (32'd0),
        .s_axi_awlen                    (8'd0),
        .s_axi_awsize                   (3'b011),
        .s_axi_awburst                  (2'b01),
        .s_axi_awqos                    (4'd0),
        .s_axi_awvalid                  (1'b0),
        .s_axi_awready                  (s_axi_awready),
        .s_axi_wdata                    (64'd0),
        .s_axi_wstrb                    (8'd0),
        .s_axi_wlast                    (1'b0),
        .s_axi_wvalid                   (1'b0),
        .s_axi_wready                   (s_axi_wready),
        .s_axi_bid                      (s_axi_bid),
        .s_axi_bresp                    (s_axi_bresp),
        .s_axi_bvalid                   (s_axi_bvalid),
        .s_axi_bready                   (1'b1),
        .s_axi_arid                     (4'd0),
        .s_axi_araddr                   (32'd0),
        .s_axi_arlen                    (8'd0),
        .s_axi_arsize                   (3'b011),
        .s_axi_arburst                  (2'b01),
        .s_axi_arqos                    (4'd0),
        .s_axi_arvalid                  (1'b0),
        .s_axi_arready                  (s_axi_arready),
        .s_axi_rid                      (s_axi_rid),
        .s_axi_rdata                    (s_axi_rdata),
        .s_axi_rresp                    (s_axi_rresp),
        .s_axi_rlast                    (s_axi_rlast),
        .s_axi_rvalid                   (s_axi_rvalid),
        .s_axi_rready                   (1'b1),
        .s_axi_rpoison                  (),
        .s_axi_rchk                     (),
        .o_parity_err                   (),
        .dfi_cmd                        (),
        .dfi_bg                         (),
        .dfi_bank                       (),
        .dfi_row                        (),
        .dfi_col                        (),
        .dfi_len                        (),
        .dfi_wrdata_en                  (),
        .dfi_wrdata                     (),
        .dfi_wrdata_mask                (),
        .dfi_wrdata_ecc                 (),
        .dfi_rddata_valid               (1'b0),
        .dfi_rddata                     (64'd0),
        .dfi_rddata_ecc                 (8'd0),
        .cfg_is_ddr5                    (1'b1),
        .cfg_dual_hash_en               (1'b1),
        .cfg_rh_threshold               (16'd64),
        .cfg_window_size                (16'd1024),
        .o_throttled_events             (),
        .o_ecc_single_err_cnt           (),
        .o_ecc_double_err_cnt           (),
        .cfg_bank_coloring_en           (1'b0),
        .cfg_mapping_mode               (2'b00),
        .cfg_scramble_en                (1'b0),
        .cfg_scramble_reseed            (1'b0),
        .cfg_scramble_seed              (64'hA5A5_5A5A_0123_4567),
        .cfg_pmu_en                     (1'b1),
        .cfg_pmu_reset                  (1'b0),
        .o_pmu_counters                 (),
        .cfg_rowpress_curve             (2'b00),
        .cfg_victim3_en                 (1'b0),
        .i_dram_abo_alert               (1'b0),
        .o_abo_alert_cnt                (),
        .o_ecc_miscorrect_cnt           (),
        .o_coordinated_throttle_active  (),
        .o_rfm_auto_cnt                 (),
        .o_tras_clamped_alert           (),
        .cfg_scramble_mode              (2'b10),
        .cfg_decoy_en                   (1'b0),
        .cfg_fault_clr                  (1'b0),
        .o_decoy_active                 (),
        .o_decoy_cnt                    (),
        .o_fault_cause                  (),
        .o_glitch_alert                 (),
        .o_security_locked              ()
    );

    // Quét luồng byte của file nguồn đường chính để chắc chắn không chứa tham chiếu tới sec_ddr5_controller_top
    task automatic check_file_no_demo_ref(input string path, input string label);
        int fd;
        int ch;
        bit found_sec_top;
        bit found_demo_sub;
        logic [23*8-1:0] win23;
        logic [25*8-1:0] win25;
        logic [18*8-1:0] win18;
        logic [15*8-1:0] win15;
        begin
            fd = $fopen(path, "r");
            tb_check(fd != 0, {label, ": canonical RTL source file must exist"});
            if (fd != 0) begin
                found_sec_top  = 1'b0;
                found_demo_sub = 1'b0;
                win23 = '0;
                win25 = '0;
                win18 = '0;
                win15 = '0;
                ch = $fgetc(fd);
                while (ch != -1) begin
                    win23 = {win23[22*8-1:0], ch[7:0]};
                    win25 = {win25[24*8-1:0], ch[7:0]};
                    win18 = {win18[17*8-1:0], ch[7:0]};
                    win15 = {win15[14*8-1:0], ch[7:0]};
                    if (win23 == "sec_ddr5_controller_top") begin
                        found_sec_top = 1'b1;
                    end
                    if (win25 == "ddr5_subchannel_scheduler" ||
                        win18 == "axi4_slave_adapter" ||
                        win15 == "dfi_phy_adapter") begin
                        found_demo_sub = 1'b1;
                    end
                    ch = $fgetc(fd);
                end
                $fclose(fd);
                tb_check(!found_sec_top,  {label, ": must not reference or instantiate sec_ddr5_controller_top"});
                tb_check(!found_demo_sub, {label, ": must not instantiate demo-only submodules (C-3/C-4/H-2)"});
            end
        end
    endtask

    initial begin
        // 1. Kiểm tra tĩnh toàn bộ 28 file RTL thuộc cây instance của axi_ddr5_mc_top
        check_file_no_demo_ref("rtl/top/axi_ddr5_mc_top.sv",                 "axi_ddr5_mc_top");
        check_file_no_demo_ref("rtl/top/bank_credit_ctrl.sv",                "bank_credit_ctrl");
        check_file_no_demo_ref("rtl/cdc/rst_sync.sv",                        "rst_sync");
        check_file_no_demo_ref("rtl/cdc/async_fifo_cdc.sv",                  "async_fifo_cdc");
        check_file_no_demo_ref("rtl/bus/axi4_skid_buffer.sv",                "axi4_skid_buffer");
        check_file_no_demo_ref("rtl/bus/perf_monitor_unit.sv",               "perf_monitor_unit");
        check_file_no_demo_ref("rtl/frontend/axi_slave_frontend.sv",         "axi_slave_frontend");
        check_file_no_demo_ref("rtl/frontend/wdata_buffer.sv",               "wdata_buffer");
        check_file_no_demo_ref("rtl/frontend/wr_data_store.sv",              "wr_data_store");
        check_file_no_demo_ref("rtl/frontend/axi_burst_splitter.sv",         "axi_burst_splitter");
        check_file_no_demo_ref("rtl/frontend/rd_issue_queue.sv",             "rd_issue_queue");
        check_file_no_demo_ref("rtl/frontend/domain_bank_coloring.sv",       "domain_bank_coloring");
        check_file_no_demo_ref("rtl/frontend/addr_mapper_ddr5.sv",           "addr_mapper_ddr5");
        check_file_no_demo_ref("rtl/core/scarf_dram_randomizer.sv",          "scarf_dram_randomizer");
        check_file_no_demo_ref("rtl/core/reorder_buffer_rob.sv",             "reorder_buffer_rob");
        check_file_no_demo_ref("rtl/core/fault_hardened_csr.sv",             "fault_hardened_csr");
        check_file_no_demo_ref("rtl/core/pxor_hash_engine.sv",               "pxor_hash_engine");
        check_file_no_demo_ref("rtl/core/sdc_resilient_filter.sv",           "sdc_resilient_filter");
        check_file_no_demo_ref("rtl/core/adaptive_threshold_engine.sv",      "adaptive_threshold_engine");
        check_file_no_demo_ref("rtl/core/qos_scheduler_queue.sv",            "qos_scheduler_queue");
        check_file_no_demo_ref("rtl/crypto/multi_vm_key_table.sv",           "multi_vm_key_table");
        check_file_no_demo_ref("rtl/backend/directed_refresh_manager.sv",    "directed_refresh_manager");
        check_file_no_demo_ref("rtl/backend/slack_aware_arbiter.sv",         "slack_aware_arbiter");
        check_file_no_demo_ref("rtl/backend/ddr5_cmd_engine.sv",             "ddr5_cmd_engine");
        check_file_no_demo_ref("rtl/backend/ecc_scrubber.sv",                "ecc_scrubber");
        check_file_no_demo_ref("rtl/backend/secded_72_64_pkg.sv",            "secded_72_64_pkg");
        check_file_no_demo_ref("rtl/memory/bus_scrambler.sv",                "bus_scrambler");
        check_file_no_demo_ref("rtl/memory/scrambler_ks_pipe.sv",            "scrambler_ks_pipe");

        // 2. Kiểm tra động: axi_ddr5_mc_top elaborate và thoát reset độc lập (không có sec_ddr5_controller_top)
        aresetn_axi = 1'b0;
        aresetn_ddr = 1'b0;
        repeat (8) @(posedge clk_axi);
        aresetn_axi = 1'b1;
        aresetn_ddr = 1'b1;
        repeat (16) @(posedge clk_axi);

        tb_check(s_axi_awready === 1'b1, "axi_ddr5_mc_top AWREADY asserted after reset without sec_ddr5_controller_top");
        tb_check(s_axi_arready === 1'b1, "axi_ddr5_mc_top ARREADY asserted after reset without sec_ddr5_controller_top");

        tb_report();
        $finish;
    end

endmodule
