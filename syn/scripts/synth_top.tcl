# Usage: vivado -mode batch -source synth_top.tcl -tclargs <tag> [impl]
# Full axi_ddr5_mc_top OOC synthesis (and optional place+route) at 400 MHz on xczu7ev, both clocks 2.5 ns, async to each other.
set WD   [file normalize [file join [file dirname [info script]] .. reports build]]
file mkdir $WD
set PART "xczu7ev-ffvc1156-2-e"
set tag  [lindex $argv 0]
set impl [expr {[llength $argv] > 1 && [lindex $argv 1] eq "impl"}]
set R D:/RAM/rtl
create_project -in_memory -part $PART
foreach f {
  backend/secded_72_64_pkg.sv crypto/aes_pkg.sv
  cdc/rst_sync.sv frontend/axi_slave_frontend.sv bus/axi4_skid_buffer.sv frontend/wdata_buffer.sv frontend/wr_data_store.sv frontend/axi_burst_splitter.sv frontend/rd_issue_queue.sv
  core/fault_hardened_csr.sv crypto/multi_vm_key_table.sv frontend/addr_mapper_ddr5.sv frontend/domain_bank_coloring.sv
  core/scarf_dram_randomizer.sv core/reorder_buffer_rob.sv core/sdc_resilient_filter.sv core/pxor_hash_engine.sv
  core/adaptive_threshold_engine.sv backend/directed_refresh_manager.sv core/qos_scheduler_queue.sv
  backend/slack_aware_arbiter.sv backend/ddr5_cmd_engine.sv backend/ecc_scrubber.sv memory/bus_scrambler.sv memory/scrambler_ks_pipe.sv
  bus/perf_monitor_unit.sv cdc/async_fifo_cdc.sv top/bank_credit_ctrl.sv top/axi_ddr5_mc_top.sv
} { read_verilog -sv $R/$f }
synth_design -top axi_ddr5_mc_top -part $PART -mode out_of_context -flatten_hierarchy rebuilt
create_clock -period 2.500 -name clk_axi [get_ports clk_axi]
create_clock -period 2.500 -name clk_ddr [get_ports clk_ddr]
set_clock_groups -asynchronous -group clk_axi -group clk_ddr
write_checkpoint -force "$WD/${tag}_synth.dcp"
report_utilization    -file "$WD/${tag}_util.rpt"
report_timing -max_paths 40 -nworst 1 -unique_pins -file "$WD/${tag}_paths.rpt"
set fh [open "$WD/${tag}_byblock.txt" w]
foreach c [lsort [get_cells -quiet u_*]] {
  set p [get_timing_paths -quiet -max_paths 1 -to [get_cells -quiet -hier -filter "NAME =~ $c/* && IS_SEQUENTIAL"]]
  if {[llength $p]} { puts $fh [format "%8.3f  %-24s  from %s" [get_property SLACK $p] $c [get_property STARTPOINT_PIN $p]] }
}
set p [get_timing_paths -quiet -max_paths 1 -to [get_cells -quiet -filter {IS_SEQUENTIAL}]]
if {[llength $p]} { puts $fh [format "%8.3f  %-24s  from %s" [get_property SLACK $p] "(top regs)" [get_property STARTPOINT_PIN $p]] }
close $fh
report_timing_summary -file "$WD/${tag}_timing.rpt" -max_paths 10
set wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -hold]]
set fh [open "$WD/batch_summary.txt" a]; puts $fh "[clock format [clock seconds] -format %H:%M] $tag synth WNS=$wns WHS=$whs"; close $fh
puts "RESULT $tag synth WNS=$wns"
if {$impl} {
  opt_design; place_design; phys_opt_design; route_design
  report_timing_summary -file "$WD/${tag}_impl_timing.rpt" -max_paths 10
  report_utilization    -file "$WD/${tag}_impl_util.rpt"
  set wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
  set whs [get_property SLACK [get_timing_paths -max_paths 1 -hold]]
  set fh [open "$WD/batch_summary.txt" a]; puts $fh "[clock format [clock seconds] -format %H:%M] $tag impl WNS=$wns WHS=$whs"; close $fh
  puts "RESULT $tag impl WNS=$wns WHS=$whs"
}
