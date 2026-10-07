#=============================================================================
# Project:     Q-Shield Secure & Resilient DDR5/DDR4 Memory Controller
# File:        run_innovus_pnr.tcl
# Description: Production Cadence Innovus Place & Route (P&R) Flow Script
#              Floorplan -> Power Grid -> Placement -> CTS -> Routing -> Signoff
# Target Node: Nangate 45nm / TSMC 28nm / GF 22FDX
# Usage:       innovus -files run_innovus_pnr.tcl -log innovus.log
#=============================================================================

#-----------------------------------------------------------------------------
# 1. Environment & Design Initialization
#-----------------------------------------------------------------------------
set DESIGN_NAME "axi_ddr5_mc_top"
set NETLIST_DIR "../netlist"
set OUTPUT_DIR  "../outputs"
set REPORT_DIR  "../reports"

file mkdir $OUTPUT_DIR
file mkdir $REPORT_DIR

setMultiCpuUsage -localCpu 8 -keepLicense true

# Set MMMC view and load design files
set init_verilog         "$NETLIST_DIR/${DESIGN_NAME}_syn.v"
set init_top_cell        "$DESIGN_NAME"
set init_pwr_net         "VDD"
set init_gnd_net         "VSS"

# Default PDK LEF files (update paths for specific foundry target)
set PDK_DIR "/opt/pdk/nangate45"
set init_lef_file [list \
    "$PDK_DIR/lef/nangate45_tech.lef" \
    "$PDK_DIR/lef/NangateOpenCellLibrary.macro.lef" \
]

puts "\[INFO\] Initializing Innovus design..."
init_design

#-----------------------------------------------------------------------------
# 2. Floorplanning & I/O Pin Placement
#-----------------------------------------------------------------------------
puts "\[INFO\] Creating Floorplan..."
# Aspect Ratio: 1.0 (Square), Core Utilization: 58%, Core-to-Die Margins: 20 um
floorPlan -site FreePDK45_38x28_10Site_rectilinear \
          -r 1.0 0.58 20.0 20.0 20.0 20.0

# Pin placement: AXI on West, DFI on East, Clocks/Resets on North/South
editPin -pin {clk_axi aresetn_axi clk_ddr aresetn_ddr} -edge 0 -layer 3 -spreadType SIDE
editPin -pin {s_axi_*} -edge 3 -layer 4 -spreadType SIDE
editPin -pin {dfi_*}   -edge 1 -layer 4 -spreadType SIDE
editPin -pin {cfg_* o_*} -edge 2 -layer 3 -spreadType SIDE

#-----------------------------------------------------------------------------
# 3. Power Distribution Network (PDN) & Special Route
#-----------------------------------------------------------------------------
puts "\[INFO\] Synthesizing Power Grid (VDD/VSS Rings & Stripes)..."

globalNetConnect VDD -type pgpin -pin VDD -inst * -module {}
globalNetConnect VSS -type pgpin -pin VSS -inst * -module {}
globalNetConnect VDD -type tiehi -inst * -module {}
globalNetConnect VSS -type tielo -inst * -module {}

# Core Power Rings (Metal 6 Vertical, Metal 7 Horizontal)
addRing -nets {VDD VSS} -type core_rings -follow core \
        -layer {top metal7 bottom metal7 left metal6 right metal6} \
        -width 3.0 -spacing 1.5 -offset 2.0

# Power Stripes across the core
addStripe -nets {VDD VSS} -layer metal6 -direction vertical \
          -width 2.0 -spacing 1.5 -set_to_set_distance 40.0 -start_offset 10.0

# Connect standard cell power rails to rings and stripes
sroute -connect {blockPin padPin padRing corePin floatingStripe} \
       -nets {VDD VSS} \
       -allowJogging 1

#-----------------------------------------------------------------------------
# 4. Standard Cell Placement & Pre-CTS Optimization
#-----------------------------------------------------------------------------
puts "\[INFO\] Running Standard Cell Placement & Timing Driven Optimization..."

setPlaceMode -prerouteAddSlackThreshold 0.1 \
             -place_global_cong_effort high \
             -timingEffort high

place_opt_design -outDir "$REPORT_DIR/place_opt"

# Check placement density and congestion
checkPlace "$REPORT_DIR/${DESIGN_NAME}_place.rpt"

#-----------------------------------------------------------------------------
# 5. Clock Tree Synthesis (CTS - CCOpt)
#-----------------------------------------------------------------------------
puts "\[INFO\] Running Concurrent Clock and Data Optimization (CCOpt CTS)..."

# Generate clock tree specifications for clk_axi (250 MHz) and clk_ddr (400 MHz)
create_ccopt_clock_tree_spec
set_ccopt_property target_skew 0.050 ;# 50 ps skew target
set_ccopt_property target_max_trans 0.150 ;# 150 ps transition target

# Run CTS
ccopt_design -cts

# Post-CTS timing optimization (fixing Hold & Setup)
optDesign -postCTS -hold -outDir "$REPORT_DIR/post_cts"

#-----------------------------------------------------------------------------
# 6. Global & Detailed Nanoroute
#-----------------------------------------------------------------------------
puts "\[INFO\] Running NanoRoute (Signal Routing & Antenna Repair)..."

setNanoRouteMode -quiet -routeWithTimingDriven true \
                 -routeWithSiDriven true \
                 -routeAntennaRepair true \
                 -drouteFixAntenna true \
                 -routeInsertAntennaDiode true \
                 -routeAntennaCellName "ANTENNA_X1"

routeDesign

# Post-Route Timing & Crosstalk Optimization
optDesign -postRoute -setup -hold -outDir "$REPORT_DIR/post_route"

#-----------------------------------------------------------------------------
# 7. Signoff Physical & Electrical Verification
#-----------------------------------------------------------------------------
puts "\[INFO\] Running Signoff Verification (STA, DRC, LVS, Connectivity, Antenna)..."

# Tempus Static Timing Analysis Signoff
timeDesign -postRoute -signoff -outDir "$REPORT_DIR/signoff_sta"

# Design Rule Check (DRC)
verify_drc -report "$REPORT_DIR/${DESIGN_NAME}_drc.rpt"

# Layout Versus Schematic (LVS / Connectivity)
verify_connectivity -type all -report "$REPORT_DIR/${DESIGN_NAME}_lvs.rpt"

# Antenna Check
verify_process_antenna -report "$REPORT_DIR/${DESIGN_NAME}_antenna.rpt"

# Metal Density Check
verify_metal_density -report "$REPORT_DIR/${DESIGN_NAME}_density.rpt"

#-----------------------------------------------------------------------------
# 8. Final Layout Export (GDSII, DEF, SPEF, Verilog)
#-----------------------------------------------------------------------------
puts "\[INFO\] Streaming Out Final GDSII Layout & Physical Hand-off Files..."

# Parasitic RC Extraction (SPEF)
rcOut -spef "$OUTPUT_DIR/${DESIGN_NAME}.spef"

# Design Exchange Format (DEF)
defOut -floorplan -netlist -routing "$OUTPUT_DIR/${DESIGN_NAME}.def"

# Post-Route Verilog Netlist
saveNetlist "$OUTPUT_DIR/${DESIGN_NAME}_pr.v"

# Stream-out GDSII for tapeout
streamOut "$OUTPUT_DIR/${DESIGN_NAME}.gds" \
          -mapFile "$PDK_DIR/gds/gds.map" \
          -stripes 1 \
          -units 1000

puts "\n=================================================================="
puts "  CADENCE INNOVUS PHYSICAL DESIGN FLOW FINISHED SUCCESSFULLY!"
puts "  GDSII Layout: $OUTPUT_DIR/${DESIGN_NAME}.gds"
puts "  SPEF Delay:   $OUTPUT_DIR/${DESIGN_NAME}.spef"
puts "  Reports:      $REPORT_DIR/"
puts "==================================================================\n"

exit
