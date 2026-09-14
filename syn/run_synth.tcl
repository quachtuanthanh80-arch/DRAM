# ==============================================================================
# SECURE DDR5 MEMORY CONTROLLER - SYNTHESIS & TIMING CLOSURE SCRIPT
# ==============================================================================
set TARGET_PART "xczu7ev-ffvc1156-2-e"
set TOP_MODULE  "sec_ddr5_controller_top"

puts "=========================================================="
puts "Starting Out-Of-Context Synthesis for $TOP_MODULE on $TARGET_PART"
puts "=========================================================="

# 1. Read SystemVerilog RTL files in dependency order
read_verilog -sv "D:/RAM/rtl/crypto/aes_pkg.sv"
read_verilog -sv "D:/RAM/rtl/crypto/aes_sbox.sv"
read_verilog -sv "D:/RAM/rtl/crypto/aes_round_pipe.sv"
read_verilog -sv "D:/RAM/rtl/crypto/subchannel_aes_xts_pipe.sv"
read_verilog -sv "D:/RAM/rtl/bus/axi4_skid_buffer.sv"
read_verilog -sv "D:/RAM/rtl/bus/apb_csr_regs.sv"
read_verilog -sv "D:/RAM/rtl/bus/axi4_slave_adapter.sv"
read_verilog -sv "D:/RAM/rtl/memory/async_fifo_cdc.sv"
read_verilog -sv "D:/RAM/rtl/memory/ddr5_subchannel_scheduler.sv"
read_verilog -sv "D:/RAM/rtl/memory/dfi_phy_adapter.sv"
read_verilog -sv "D:/RAM/rtl/top/sec_ddr5_controller_top.sv"

# 2. Read Timing Constraints
read_xdc "D:/RAM/syn/constraints.xdc"

# 3. Run Synthesis
synth_design -top $TOP_MODULE -part $TARGET_PART -mode out_of_context -flatten_hierarchy rebuilt

# 4. Generate Reports
file mkdir "D:/RAM/syn/reports"
report_utilization -file "D:/RAM/syn/reports/utilization.rpt" -pb "D:/RAM/syn/reports/utilization.pb"
report_timing_summary -file "D:/RAM/syn/reports/timing_summary.rpt" -max_paths 10
report_clock_networks -file "D:/RAM/syn/reports/clock_networks.rpt"
report_design_analysis -file "D:/RAM/syn/reports/design_analysis.rpt"

puts "=========================================================="
puts "Synthesis and Timing Analysis Completed Successfully!"
puts "Reports generated in D:/RAM/syn/reports/"
puts "=========================================================="
exit
