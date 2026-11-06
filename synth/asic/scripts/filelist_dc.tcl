#=============================================================================
# Project:     Q-Shield Secure & Resilient DDR5/DDR4 Memory Controller
# File:        filelist_dc.tcl
# Description: Synopsys Design Compiler SystemVerilog RTL Filelist
#              Organized hierarchically to guarantee clean elaboration.
#=============================================================================

# Base directory for RTL (relative to synth/asic/scripts or absolute)
set RTL_ROOT "../../rtl"

#-----------------------------------------------------------------------------
# 1. Common CDC, Infrastructure & Skid Buffers
#-----------------------------------------------------------------------------
set CDC_FILES [list \
    "$RTL_ROOT/cdc/rst_sync.sv" \
    "$RTL_ROOT/cdc/async_fifo_cdc.sv" \
]

set BUS_FILES [list \
    "$RTL_ROOT/bus/axi4_skid_buffer.sv" \
    "$RTL_ROOT/bus/axi4_slave_adapter.sv" \
    "$RTL_ROOT/core/fault_hardened_csr.sv" \
    "$RTL_ROOT/bus/apb_csr_regs.sv" \
]

#-----------------------------------------------------------------------------
# 2. Q-Shield Primary Architecture Modules (axi_ddr5_mc_top target)
#-----------------------------------------------------------------------------
# Danh sách khớp đúng cây module của axi_ddr5_mc_top (cùng tập file mà regression Icarus biên dịch);
# bản trước trỏ tới 4 file không tồn tại (timing_parameter_checker, bank_state_machine, request_queue, fr_fcfs_scheduler).
set FRONTEND_FILES [list \
    "$RTL_ROOT/frontend/axi_slave_frontend.sv" \
    "$RTL_ROOT/frontend/wdata_buffer.sv" \
    "$RTL_ROOT/frontend/wr_data_store.sv" \
    "$RTL_ROOT/frontend/axi_burst_splitter.sv" \
    "$RTL_ROOT/frontend/rd_issue_queue.sv" \
    "$RTL_ROOT/frontend/domain_bank_coloring.sv" \
    "$RTL_ROOT/frontend/addr_mapper_ddr5.sv" \
]

set CORE_FILES [list \
    "$RTL_ROOT/core/scarf_dram_randomizer.sv" \
    "$RTL_ROOT/core/reorder_buffer_rob.sv" \
    "$RTL_ROOT/core/fault_hardened_csr.sv" \
    "$RTL_ROOT/core/pxor_hash_engine.sv" \
    "$RTL_ROOT/core/sdc_resilient_filter.sv" \
    "$RTL_ROOT/core/adaptive_threshold_engine.sv" \
    "$RTL_ROOT/core/qos_scheduler_queue.sv" \
    "$RTL_ROOT/crypto/multi_vm_key_table.sv" \
]

set BACKEND_FILES [list \
    "$RTL_ROOT/backend/secded_72_64_pkg.sv" \
    "$RTL_ROOT/backend/directed_refresh_manager.sv" \
    "$RTL_ROOT/backend/slack_aware_arbiter.sv" \
    "$RTL_ROOT/backend/ddr5_cmd_engine.sv" \
    "$RTL_ROOT/backend/ecc_scrubber.sv" \
]

set MEMORY_FILES [list \
    "$RTL_ROOT/memory/bus_scrambler.sv" \
    "$RTL_ROOT/memory/scrambler_ks_pipe.sv" \
    "$RTL_ROOT/bus/perf_monitor_unit.sv" \
]

# Primary Top Module: Resilient & QoS DDR5 Controller Core
set QSHIELD_MC_FILES [concat \
    [list "$RTL_ROOT/cdc/rst_sync.sv" "$RTL_ROOT/bus/axi4_skid_buffer.sv"] \
    $FRONTEND_FILES \
    $CORE_FILES \
    $BACKEND_FILES \
    $MEMORY_FILES \
    [list "$RTL_ROOT/top/bank_credit_ctrl.sv" "$RTL_ROOT/top/axi_ddr5_mc_top.sv"] \
]

#-----------------------------------------------------------------------------
# 3. Cryptographic Subsystem (for sec_ddr5_controller_top target)
#-----------------------------------------------------------------------------
set CRYPTO_FILES [list \
    "$RTL_ROOT/crypto/aes_pkg.sv" \
    "$RTL_ROOT/crypto/aes_sbox.sv" \
    "$RTL_ROOT/crypto/aes_sbox_composite.sv" \
    "$RTL_ROOT/crypto/aes_tweak_gen.sv" \
    "$RTL_ROOT/crypto/aes_round_pipe.sv" \
    "$RTL_ROOT/crypto/subchannel_aes_xts_pipe.sv" \
    "$RTL_ROOT/crypto/split_counter_table.sv" \
    "$RTL_ROOT/crypto/aes_ctr_keystream.sv" \
    "$RTL_ROOT/crypto/aes128_enc_iter.sv" \
    "$RTL_ROOT/crypto/integrity_mac_gen.sv" \
    "$RTL_ROOT/crypto/qshield_crypto_top.sv" \
]

# Full Secure Top Module: Inline AES-256-XTS + Dual Subchannel Controller
set QSHIELD_SEC_FILES [concat \
    $CDC_FILES \
    $BUS_FILES \
    $CRYPTO_FILES \
    [list "$RTL_ROOT/memory/dfi_phy_adapter.sv" "$RTL_ROOT/memory/ddr5_subchannel_scheduler.sv"] \
    [list "$RTL_ROOT/top/sec_ddr5_controller_top.sv"] \
]

#-----------------------------------------------------------------------------
# 4. Form Factor Interconnect Shims (CXL 3.0 & UCIe 1.1)
#-----------------------------------------------------------------------------
set INTERFACE_FILES [list \
    "$RTL_ROOT/interfaces/pcie_cxl_io_apb_shim.sv" \
    "$RTL_ROOT/interfaces/cxl_mem_axi_shim.sv" \
    "$RTL_ROOT/interfaces/ucie_fdi_axi_shim.sv" \
]

puts "\[INFO\] Q-Shield Filelist loaded successfully."
puts "       - Target 1 (axi_ddr5_mc_top): [llength $QSHIELD_MC_FILES] RTL files"
puts "       - Target 2 (sec_ddr5_controller_top): [llength $QSHIELD_SEC_FILES] RTL files"
puts "       - Interconnect Shims (CXL/UCIe): [llength $INTERFACE_FILES] RTL files"
