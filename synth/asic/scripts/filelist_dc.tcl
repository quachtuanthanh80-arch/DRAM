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
    "$RTL_ROOT/bus/apb_csr_regs.sv" \
]

#-----------------------------------------------------------------------------
# 2. Q-Shield Primary Architecture Modules (axi_ddr5_mc_top target)
#-----------------------------------------------------------------------------
set FRONTEND_FILES [list \
    "$RTL_ROOT/frontend/axi4_skid_buffer.sv" \
    "$RTL_ROOT/frontend/axi_address_decoder.sv" \
    "$RTL_ROOT/frontend/wdata_buffer.sv" \
    "$RTL_ROOT/frontend/addr_mapper_ddr5.sv" \
    "$RTL_ROOT/frontend/axi_slave_frontend.sv" \
]

set CORE_FILES [list \
    "$RTL_ROOT/core/timing_parameter_checker.sv" \
    "$RTL_ROOT/core/bank_state_machine.sv" \
    "$RTL_ROOT/core/sdc_resilient_filter.sv" \
    "$RTL_ROOT/core/request_queue.sv" \
    "$RTL_ROOT/core/reorder_buffer_rob.sv" \
    "$RTL_ROOT/core/qos_scheduler_queue.sv" \
    "$RTL_ROOT/core/fr_fcfs_scheduler.sv" \
]

set BACKEND_FILES [list \
    "$RTL_ROOT/backend/slack_aware_arbiter.sv" \
    "$RTL_ROOT/backend/ecc_scrubber.sv" \
    "$RTL_ROOT/backend/ddr5_cmd_engine.sv" \
]

set MEMORY_FILES [list \
    "$RTL_ROOT/memory/dfi_phy_adapter.sv" \
    "$RTL_ROOT/memory/ddr5_subchannel_scheduler.sv" \
]

# Primary Top Module: Resilient & QoS DDR5 Controller Core
set QSHIELD_MC_FILES [concat \
    $CDC_FILES \
    $FRONTEND_FILES \
    $CORE_FILES \
    $BACKEND_FILES \
    $MEMORY_FILES \
    [list "$RTL_ROOT/top/axi_ddr5_mc_top.sv"] \
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
]

# Full Secure Top Module: Inline AES-256-XTS + Dual Subchannel Controller
set QSHIELD_SEC_FILES [concat \
    $CDC_FILES \
    $BUS_FILES \
    $CRYPTO_FILES \
    $MEMORY_FILES \
    [list "$RTL_ROOT/top/sec_ddr5_controller_top.sv"] \
]

puts "\[INFO\] Q-Shield Filelist loaded successfully."
puts "       - Target 1 (axi_ddr5_mc_top): [llength $QSHIELD_MC_FILES] RTL files"
puts "       - Target 2 (sec_ddr5_controller_top): [llength $QSHIELD_SEC_FILES] RTL files"
