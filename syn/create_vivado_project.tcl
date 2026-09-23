# ==============================================================================
# SCRIPT: create_vivado_project.tcl
# DESCRIPTION: Creates a full Vivado GUI Project (.xpr) for Q-Shield Controller
# USAGE in Vivado Tcl Console:
#   cd D:/RAM/syn
#   source create_vivado_project.tcl
# ==============================================================================

set PROJ_NAME   "qshield_ddr5_synth"
set PROJ_DIR    "D:/RAM/syn/vivado_project"
set TARGET_PART "xczu7ev-ffvc1156-2-e"
set TOP_MODULE  "sec_ddr5_controller_top"

puts "=========================================================="
puts "Creating Vivado Project: $PROJ_NAME in $PROJ_DIR"
puts "Target Part: $TARGET_PART"
puts "Top Module:  $TOP_MODULE"
puts "=========================================================="

# 1. Create Project
create_project -force $PROJ_NAME $PROJ_DIR -part $TARGET_PART

# 2. Set Project Properties (SystemVerilog 2017)
set_property target_language Verilog [current_project]
set_property default_lib xil_defaultlib [current_project]

# 3. Add SystemVerilog RTL Sources
add_files -norecurse {
    D:/RAM/rtl/crypto/aes_pkg.sv
    D:/RAM/rtl/crypto/aes_sbox.sv
    D:/RAM/rtl/crypto/aes_sbox_composite.sv
    D:/RAM/rtl/crypto/aes_tweak_gen.sv
    D:/RAM/rtl/crypto/aes_round_pipe.sv
    D:/RAM/rtl/crypto/subchannel_aes_xts_pipe.sv
    D:/RAM/rtl/bus/axi4_skid_buffer.sv
    D:/RAM/rtl/bus/apb_csr_regs.sv
    D:/RAM/rtl/bus/axi4_slave_adapter.sv
    D:/RAM/rtl/memory/async_fifo_cdc.sv
    D:/RAM/rtl/memory/ddr5_subchannel_scheduler.sv
    D:/RAM/rtl/memory/dfi_phy_adapter.sv
    D:/RAM/rtl/top/sec_ddr5_controller_top.sv
}

# 4. Set File Types to SystemVerilog
set_property file_type SystemVerilog [get_files *.sv]

# 5. Add XDC Constraints
add_files -fileset constrs_1 -norecurse D:/RAM/syn/constraints.xdc

# 6. Set Top Module
set_property top $TOP_MODULE [current_fileset]
update_compile_order -fileset sources_1

# 7. Configure Out-Of-Context Mode for IP / Subsystem Synthesis
# Prevents I/O buffer insertion so Implementation places and routes internal logic
# without exceeding physical chip package pin capacity (767 ports vs 719 package pins).
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value {-mode out_of_context} -objects [get_runs synth_1]

puts "=========================================================="
puts "Project created successfully with Out-Of-Context mode enabled!"
puts "Project file: $PROJ_DIR/$PROJ_NAME.xpr"
puts "You can now click 'Run Synthesis' or 'Run Implementation' cleanly."
puts "=========================================================="
