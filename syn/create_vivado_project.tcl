# File: create_vivado_project.tcl
# Chức năng: Khởi tạo dự án Vivado 2026.1 (.xpr) tích hợp toàn bộ 43 mô-đun RTL và 7 bộ testbench chuẩn quốc tế

set PROJ_NAME   "qshield_ddr5_synth"
set PROJ_DIR    "D:/RAM/syn/vivado_project"
set TARGET_PART "xczu7ev-ffvc1156-2-e"
set TOP_MODULE  "axi_ddr5_mc_top"

create_project -force $PROJ_NAME $PROJ_DIR -part $TARGET_PART
set_property target_language Verilog [current_project]
set_property default_lib xil_defaultlib [current_project]

add_files -fileset sources_1 -norecurse {
    D:/RAM/rtl/backend/gf256_arith_pkg.sv
    D:/RAM/rtl/backend/secded_72_64_pkg.sv
    D:/RAM/rtl/backend/ddr5_cmd_engine.sv
    D:/RAM/rtl/backend/directed_refresh_manager.sv
    D:/RAM/rtl/backend/ecc_scrubber.sv
    D:/RAM/rtl/crypto/aes128_enc_iter.sv
    D:/RAM/rtl/frontend/wr_data_store.sv
    D:/RAM/rtl/frontend/axi_burst_splitter.sv
    D:/RAM/rtl/frontend/rd_issue_queue.sv
    D:/RAM/rtl/backend/rs_chipkill_decoder.sv
    D:/RAM/rtl/backend/rs_chipkill_encoder.sv
    D:/RAM/rtl/backend/slack_aware_arbiter.sv
    D:/RAM/rtl/bus/apb_csr_regs.sv
    D:/RAM/rtl/bus/axi4_skid_buffer.sv
    D:/RAM/rtl/bus/axi4_slave_adapter.sv
    D:/RAM/rtl/bus/perf_monitor_unit.sv
    D:/RAM/rtl/cdc/async_fifo_cdc.sv
    D:/RAM/rtl/cdc/rst_sync.sv
    D:/RAM/rtl/core/adaptive_threshold_engine.sv
    D:/RAM/rtl/core/fault_hardened_csr.sv
    D:/RAM/rtl/core/pxor_hash_engine.sv
    D:/RAM/rtl/core/qos_scheduler_queue.sv
    D:/RAM/rtl/core/reorder_buffer_rob.sv
    D:/RAM/rtl/core/scarf_dram_randomizer.sv
    D:/RAM/rtl/core/sdc_resilient_filter.sv
    D:/RAM/rtl/crypto/aes_pkg.sv
    D:/RAM/rtl/crypto/aes_ctr_keystream.sv
    D:/RAM/rtl/crypto/aes_round_pipe.sv
    D:/RAM/rtl/crypto/aes_sbox.sv
    D:/RAM/rtl/crypto/aes_sbox_composite.sv
    D:/RAM/rtl/crypto/aes_tweak_gen.sv
    D:/RAM/rtl/crypto/integrity_mac_gen.sv
    D:/RAM/rtl/crypto/multi_vm_key_table.sv
    D:/RAM/rtl/crypto/qshield_crypto_top.sv
    D:/RAM/rtl/crypto/split_counter_table.sv
    D:/RAM/rtl/crypto/subchannel_aes_xts_pipe.sv
    D:/RAM/rtl/frontend/addr_mapper_ddr5.sv
    D:/RAM/rtl/frontend/axi_slave_frontend.sv
    D:/RAM/rtl/frontend/domain_bank_coloring.sv
    D:/RAM/rtl/frontend/wdata_buffer.sv
    D:/RAM/rtl/interfaces/cxl_mem_axi_shim.sv
    D:/RAM/rtl/interfaces/pcie_cxl_io_apb_shim.sv
    D:/RAM/rtl/interfaces/ucie_fdi_axi_shim.sv
    D:/RAM/rtl/memory/bus_scrambler.sv
    D:/RAM/rtl/memory/scrambler_ks_pipe.sv
    D:/RAM/rtl/memory/ddr5_subchannel_scheduler.sv
    D:/RAM/rtl/memory/dfi_phy_adapter.sv
    D:/RAM/rtl/top/bank_credit_ctrl.sv
    D:/RAM/rtl/top/axi_ddr5_mc_top.sv
    D:/RAM/rtl/top/sec_ddr5_controller_top.sv
}

add_files -fileset sim_1 -norecurse {
    D:/RAM/tb/common/ddr5_jedec_bin_pkg.sv
    D:/RAM/tb/common/dfi_jedec_checker.sv
    D:/RAM/tb/common/dram_model.sv
    D:/RAM/tb/common/dfi_rd_fault_shim.sv
    D:/RAM/tb/common/qs_rd_beat_model.sv
    D:/RAM/tb/common/qs_engine_port_chk.sv
    D:/RAM/tb/common/qs_axi_txn_chk.sv
    D:/RAM/tb/common/qs_top_probe_chk.sv
    D:/RAM/tb/top/tb_standard_benchmarks.sv
    D:/RAM/tb/top/tb_security_attacks_vcd.sv
    D:/RAM/tb/top/tb_axi_ddr5_mc_top.sv
    D:/RAM/tb/top/tb_axi_ddr5_mc_top_400.sv
    D:/RAM/tb/top/tb_e2e_scoreboard.sv
    D:/RAM/tb/top/tb_e2e_scoreboard_400.sv
    D:/RAM/tb/top/tb_rt01_ref_starvation.sv
    D:/RAM/tb/top/tb_rt02_credit_race.sv
    D:/RAM/tb/top/tb_rt03_rd_integrity.sv
    D:/RAM/tb/top/tb_rt04_jedec_400mhz.sv
    D:/RAM/tb/top/tb_rt05_fault_agg.sv
    D:/RAM/tb/top/tb_rt06_xbg_channel.sv
    D:/RAM/tb/top/tb_rt07_phys_bank_credit.sv
    D:/RAM/tb/top/tb_rt08_cfg_change.sv
    D:/RAM/tb/top/tb_rt09_decoy_prf.sv
    D:/RAM/tb/top/tb_rt12_param_corners.sv
    D:/RAM/tb/top/tb_sec_ddr5_controller_top.sv
    D:/RAM/tb/backend/tb_prac_abo_phoenix.sv
    D:/RAM/tb/backend/tb_eccfail_zem_scrubber.sv
    D:/RAM/tb/backend/tb_rs_chipkill_selfcheck.sv
    D:/RAM/tb/backend/tb_eng_ref_starve.sv
    D:/RAM/tb/backend/tb_eng_rd_sync.sv
    D:/RAM/tb/backend/tb_eng_fault_inject.sv
    D:/RAM/tb/backend/tb_drm_fault_inject.sv
    D:/RAM/tb/backend/tb_eng_v2_random.sv
    D:/RAM/tb/backend/tb_eng_edge_cases.sv
}

set_property include_dirs {D:/RAM/tb/common} [get_filesets sim_1]
set_property file_type SystemVerilog [get_files *.sv]
add_files -fileset constrs_1 -norecurse D:/RAM/syn/constraints.xdc
set_property top $TOP_MODULE [get_filesets sources_1]
set_property top tb_axi_ddr5_mc_top [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value {-mode out_of_context} -objects [get_runs synth_1]
