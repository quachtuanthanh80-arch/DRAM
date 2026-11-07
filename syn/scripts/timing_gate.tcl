# File: timing_gate.tcl
# Chức năng: Script Vivado tổng hợp OOC và kiểm tra timing 400 MHz (2.5 ns) cho axi_ddr5_mc_top (Q-Shield).
# Usage: vivado -mode batch -source syn/scripts/timing_gate.tcl -tclargs <tag> [impl]

set PART "xczu7ev-ffvc1156-2-e"
set tag  [lindex $argv 0]
if {$tag eq ""} {
    set tag "timing_run"
}
set impl [expr {[llength $argv] > 1 && [lindex $argv 1] eq "impl"}]

set SCRIPT_DIR [file normalize [file dirname [info script]]]
set WD [file normalize [file join $SCRIPT_DIR .. reports build $tag]]
file mkdir $WD

set R [file normalize [file join $SCRIPT_DIR ../../rtl]]

create_project -in_memory -part $PART

# Nạp toàn bộ mã nguồn RTL của top chuẩn axi_ddr5_mc_top
foreach f {
  backend/secded_72_64_pkg.sv
  crypto/aes_pkg.sv
  cdc/rst_sync.sv
  frontend/axi_slave_frontend.sv
  bus/axi4_skid_buffer.sv
  frontend/wdata_buffer.sv
  frontend/wr_data_store.sv
  frontend/axi_burst_splitter.sv
  frontend/rd_issue_queue.sv
  core/fault_hardened_csr.sv
  crypto/multi_vm_key_table.sv
  frontend/addr_mapper_ddr5.sv
  frontend/domain_bank_coloring.sv
  core/scarf_dram_randomizer.sv
  core/reorder_buffer_rob.sv
  core/sdc_resilient_filter.sv
  core/pxor_hash_engine.sv
  core/adaptive_threshold_engine.sv
  backend/directed_refresh_manager.sv
  core/qos_scheduler_queue.sv
  backend/slack_aware_arbiter.sv
  backend/ddr5_cmd_engine.sv
  backend/ecc_scrubber.sv
  memory/bus_scrambler.sv
  memory/scrambler_ks_pipe.sv
  bus/perf_monitor_unit.sv
  cdc/async_fifo_cdc.sv
  top/bank_credit_ctrl.sv
  top/axi_ddr5_mc_top.sv
} {
  read_verilog -sv "$R/$f"
}

# Tổng hợp OOC (Out-of-Context) cho axi_ddr5_mc_top
synth_design -top axi_ddr5_mc_top -part $PART -mode out_of_context -flatten_hierarchy rebuilt

# Ràng buộc clock 400 MHz (2.5 ns) theo quyết định D3
create_clock -period 2.500 -name clk_axi [get_ports clk_axi]
create_clock -period 2.500 -name clk_ddr [get_ports clk_ddr]
set_clock_groups -asynchronous -group clk_axi -group clk_ddr

# Xuất báo cáo sau tổng hợp
write_checkpoint -force "$WD/${tag}_synth.dcp"
report_utilization -file "$WD/${tag}_util.rpt"
report_timing -max_paths 40 -nworst 1 -unique_pins -file "$WD/${tag}_paths.rpt"
report_timing_summary -file "$WD/${tag}_timing.rpt" -max_paths 10

set wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -hold]]
puts "TIMING_GATE_RESULT stage=synth tag=$tag WNS=$wns WHS=$whs"

if {$impl} {
  opt_design
  place_design
  phys_opt_design
  route_design
  report_timing_summary -file "$WD/${tag}_impl_timing.rpt" -max_paths 10
  report_utilization -file "$WD/${tag}_impl_util.rpt"
  set impl_wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
  set impl_whs [get_property SLACK [get_timing_paths -max_paths 1 -hold]]
  puts "TIMING_GATE_RESULT stage=impl tag=$tag WNS=$impl_wns WHS=$impl_whs"
}
