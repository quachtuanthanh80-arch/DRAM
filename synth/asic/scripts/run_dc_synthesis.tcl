#=============================================================================
# Project:     Q-Shield Secure & Resilient DDR5/DDR4 Memory Controller
# File:        run_dc_synthesis.tcl
# Description: Production Synopsys Design Compiler (DC) ASIC Synthesis Script
# Target Node: Nangate 45nm Open Cell Library (Default) / TSMC 28nm / ASAP7
# Author:      Q-Shield Research & Architecture Team
# Usage:       dc_shell -f run_dc_synthesis.tcl | tee dc_synth.log
#=============================================================================

#-----------------------------------------------------------------------------
# 1. User & Architecture Configuration
#-----------------------------------------------------------------------------
# Target Top Module: "axi_ddr5_mc_top" (Resilient Core) or "sec_ddr5_controller_top" (Crypto Core)
if {![info exists TOP_MODULE]} {
    set TOP_MODULE "axi_ddr5_mc_top"
}

# Number of parallel compilation threads
set_host_options -max_cores 8

# Output Directories
set SCRIPT_DIR    [file dirname [info script]]
set NETLIST_DIR   "$SCRIPT_DIR/../netlist"
set OUTPUT_DIR    "$SCRIPT_DIR/../outputs"
set REPORT_DIR    "$SCRIPT_DIR/../reports"
set CONST_DIR     "$SCRIPT_DIR/../constraints"

file mkdir $NETLIST_DIR
file mkdir $OUTPUT_DIR
file mkdir $REPORT_DIR

#-----------------------------------------------------------------------------
# 2. Technology Library Setup
#-----------------------------------------------------------------------------
# DEFAULT: Nangate 45nm Open Cell Library (Freely available for academic research)
# Note: For commercial TSMC 28nm or GF 22FDX, update the paths below accordingly.
set PDK_PATH           "/opt/pdk/nangate45"
set TARGET_DB          "NangateOpenCellLibrary_typical.db"
set SYMBOL_LIB         "NangateOpenCellLibrary.sdb"
set DW_FOUNDATION_LIB  "dw_foundation.sldb"

set search_path [list \
    "." \
    "$PDK_PATH/lib" \
    "$PDK_PATH/db" \
    "$SCRIPT_DIR" \
    "$SCRIPT_DIR/../../rtl" \
]

# Set Target and Link Libraries
set target_library [list $TARGET_DB]
set link_library   [list * $TARGET_DB $DW_FOUNDATION_LIB]
set symbol_library [list $SYMBOL_LIB]

#-----------------------------------------------------------------------------
# 3. Read & Analyze RTL Design
#-----------------------------------------------------------------------------
puts "\n=================================================================="
puts "  [STEP 1] READING & ANALYZING SYSTEMVERILOG RTL"
puts "  Top-Level Module: $TOP_MODULE"
puts "=================================================================="

# Source the hierarchical filelist
source "$SCRIPT_DIR/filelist_dc.tcl"

# Select filelist based on target module
if {$TOP_MODULE eq "sec_ddr5_controller_top"} {
    set RTL_FILES $QSHIELD_SEC_FILES
} else {
    set RTL_FILES $QSHIELD_MC_FILES
}

# Set SystemVerilog 2017 dialect and analyze
set_svf "$OUTPUT_DIR/${TOP_MODULE}.svf"
define_design_lib WORK -path ./WORK

# Analyze each RTL file
foreach f $RTL_FILES {
    puts "Analyzing: $f"
    analyze -format sverilog -work WORK $f
}

# Elaborate top-level module
elaborate $TOP_MODULE -work WORK
current_design $TOP_MODULE

# Verify design links without unresolved references
link
if {[link] == 0} {
    puts "\[ERROR\] Design link failed! Check missing modules or unresolved cells."
    exit 1
}

# Uniquify instances
uniquify

# Initial Lint / Check Design
check_design > "$REPORT_DIR/${TOP_MODULE}_check_design.rpt"

#-----------------------------------------------------------------------------
# 4. Apply Timing & Environmental Constraints (SDC)
#-----------------------------------------------------------------------------
puts "\n=================================================================="
puts "  [STEP 2] APPLYING DUAL-CLOCK SDC CONSTRAINTS"
puts "=================================================================="

set SDC_FILE "$CONST_DIR/qshield_dual_clk.sdc"
if {[file exists $SDC_FILE]} {
    puts "Sourcing SDC: $SDC_FILE"
    source $SDC_FILE
} else {
    puts "\[WARNING\] SDC file not found at $SDC_FILE. Applying default clock constraints."
    create_clock -name clk_axi -period 4.00 [get_ports clk_axi]
    create_clock -name clk_ddr -period 2.50 [get_ports clk_ddr]
    set_clock_groups -asynchronous -group {clk_axi} -group {clk_ddr}
}

# Propagate clocks & check timing setup
check_timing > "$REPORT_DIR/${TOP_MODULE}_check_timing.rpt"

#-----------------------------------------------------------------------------
# 5. Low-Power Clock Gating & Architectural Directives
#-----------------------------------------------------------------------------
puts "\n=================================================================="
puts "  [STEP 3] ENABLING POWER-AWARE CLOCK GATING"
puts "=================================================================="

# Enable Integrated Clock Gating (ICG) insertion
set_clock_gating_style -positive_edge_logic {integrated} \
                       -control_point before \
                       -minimum_bitwidth 4 \
                       -max_fanout 64

# Retiming & registers preservation on critical CDC boundaries
set_dont_retime [get_cells -hierarchical *cdc*] true

#-----------------------------------------------------------------------------
# 6. Ultra High-Performance Optimization (Compile)
#-----------------------------------------------------------------------------
puts "\n=================================================================="
puts "  [STEP 4] RUNNING COMPILE ULTRA OPTIMIZATION"
puts "=================================================================="

# Compile with gate-level clock gating and area-timing tradeoff
compile_ultra -gate_clock -no_autoungroup -timing_high_effort_script

# Incremental boundary optimization for timing closure
compile_ultra -incremental -timing_high_effort_script

#-----------------------------------------------------------------------------
# 7. Generate Comprehensive PPA Reports
#-----------------------------------------------------------------------------
puts "\n=================================================================="
puts "  [STEP 5] EXPORTING ASIC REPORTS (AREA, TIMING, POWER, QOR)"
puts "=================================================================="

# Timing Reports (Setup & Hold)
report_timing -delay_type max -max_paths 20 -significant_digits 3 \
    > "$REPORT_DIR/${TOP_MODULE}_timing_setup.rpt"

report_timing -delay_type min -max_paths 20 -significant_digits 3 \
    > "$REPORT_DIR/${TOP_MODULE}_timing_hold.rpt"

# Hierarchical Area Report (Cell area in um^2)
report_area -hierarchy -designware \
    > "$REPORT_DIR/${TOP_MODULE}_area_hierarchy.rpt"

# Hierarchical Power Report (Dynamic, Leakage, Internal)
report_power -hierarchy -analysis_effort medium \
    > "$REPORT_DIR/${TOP_MODULE}_power_hierarchy.rpt"

# Quality of Results (QoR) Summary
report_qor \
    > "$REPORT_DIR/${TOP_MODULE}_qor.rpt"

# Reference Cell Distribution (AND, OR, MUX, DFF, ICG counts)
report_reference -hierarchy \
    > "$REPORT_DIR/${TOP_MODULE}_cell_distribution.rpt"

# Clock Gating Insertion Report
report_clock_gating -gating_elements \
    > "$REPORT_DIR/${TOP_MODULE}_clock_gating.rpt"

# Constraint Violations
report_constraint -all_violators \
    > "$REPORT_DIR/${TOP_MODULE}_violators.rpt"

#-----------------------------------------------------------------------------
# 8. Export Post-Synthesis Netlist, SDC, SDF & DDC
#-----------------------------------------------------------------------------
puts "\n=================================================================="
puts "  [STEP 6] WRITING GATE-LEVEL NETLIST & PHYSICAL HANDOFF ARTIFACTS"
puts "=================================================================="

# Gate-level structural Verilog netlist for Physical Design (P&R)
write -format verilog -hierarchy \
      -output "$NETLIST_DIR/${TOP_MODULE}_syn.v"

# Post-synthesis actual SDC for Place & Route
write_sdc -nosplit "$OUTPUT_DIR/${TOP_MODULE}_syn.sdc"

# Standard Delay Format (SDF) for gate-level back-annotated timing simulation
write_sdf "$OUTPUT_DIR/${TOP_MODULE}_syn.sdf"

# Synopsys Design Database (DDC)
write -format ddc -hierarchy \
      -output "$OUTPUT_DIR/${TOP_MODULE}_syn.ddc"

# Close SVF record
set_svf -off

puts "\n=================================================================="
puts "  Q-SHIELD SYNTHESIS COMPLETE!"
puts "  Netlist: $NETLIST_DIR/${TOP_MODULE}_syn.v"
puts "  Reports: $REPORT_DIR/"
puts "==================================================================\n"

exit 0
