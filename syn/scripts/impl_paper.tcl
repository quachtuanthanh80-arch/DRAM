# syn/scripts/impl_paper.tcl
# Chức năng: Place and Route (P&R) trên xczu7ev cho paper, trích xuất PPA (timing, util, util_hier, power).

set PART       "xczu7ev-ffvc1156-2-e"
set SCRIPT_DIR [file normalize [file dirname [info script]]]
set ROOT_DIR   [file normalize [file join $SCRIPT_DIR .. ..]]
set OUT_DIR    [file normalize [file join $ROOT_DIR reports paper fpga]]

if {[llength $argv] < 3} {
  puts "ERROR: Thieu tham so. Dung: vivado -mode batch -source syn/scripts/impl_paper.tcl -tclargs <top> <tag> <period> \[presynth_dcp\] \[out_dir\] \[max_threads\]"
  exit 1
}

set top_module   [lindex $argv 0]
set tag          [lindex $argv 1]
set period       [lindex $argv 2]
set presynth_dcp ""
if {[llength $argv] > 3 && [lindex $argv 3] ne ""} {
  set presynth_dcp [file normalize [lindex $argv 3]]
}
if {[llength $argv] > 4 && [lindex $argv 4] ne ""} {
  set OUT_DIR [file normalize [lindex $argv 4]]
}
set max_threads ""
if {[llength $argv] > 5 && [lindex $argv 5] ne ""} {
  set max_threads [lindex $argv 5]
  # Cố định số luồng khi tái lập để giảm dao động placement/routing giữa các máy
  set_param general.maxThreads $max_threads
}
file mkdir $OUT_DIR
# Giữ các tệp phụ phát sinh trong P&R nằm gọn trong OUT_DIR thay vì thư mục gốc
cd $OUT_DIR

puts "================================================================================"
puts "  Q-SHIELD FPGA IMPLEMENTATION FOR PAPER (T83)"
puts "  Vivado       : [version -short]"
puts "  Root Dir     : $ROOT_DIR"
puts "  Top Module   : $top_module"
puts "  Tag          : $tag"
puts "  Period       : $period ns ([expr {1000.0 / $period}] MHz)"
puts "  Part         : $PART"
puts "  Output Dir   : $OUT_DIR"
puts "  Presynth DCP : $presynth_dcp"
puts "  Max Threads  : [get_param general.maxThreads]"
puts "================================================================================"

if {$presynth_dcp ne "" && [file exists $presynth_dcp]} {
  puts "=== OPENING PRE-SYNTHESIS CHECKPOINT: $presynth_dcp ==="
  open_checkpoint $presynth_dcp
} else {
  set R [file join $ROOT_DIR rtl]
  create_project -in_memory -part $PART

  # 1. Core RTL files
  foreach f {
    backend/secded_72_64_pkg.sv crypto/aes_pkg.sv
    cdc/rst_sync.sv frontend/axi_slave_frontend.sv bus/axi4_skid_buffer.sv frontend/wdata_buffer.sv frontend/wr_data_store.sv frontend/axi_burst_splitter.sv frontend/rd_issue_queue.sv
    core/fault_hardened_csr.sv crypto/multi_vm_key_table.sv frontend/addr_mapper_ddr5.sv frontend/domain_bank_coloring.sv
    core/scarf_dram_randomizer.sv core/reorder_buffer_rob.sv core/sdc_resilient_filter.sv core/pxor_hash_engine.sv
    core/adaptive_threshold_engine.sv backend/directed_refresh_manager.sv core/qos_scheduler_queue.sv
    backend/slack_aware_arbiter.sv backend/ddr5_cmd_engine.sv backend/ecc_scrubber.sv memory/bus_scrambler.sv memory/scrambler_ks_pipe.sv
    bus/perf_monitor_unit.sv cdc/async_fifo_cdc.sv top/bank_credit_ctrl.sv top/axi_ddr5_mc_top.sv
  } { read_verilog -sv [file join $R $f] }

  # 2. Secure Top RTL files (Crypto, BMT, Meta Cache, Bridge)
  if {$top_module eq "axi_ddr5_mc_secure_top"} {
    foreach f {
      crypto/aes_sbox.sv crypto/aes_sbox_composite.sv crypto/aes_round_pipe.sv crypto/aes256_key_expand.sv
      crypto/qshield_xts_tweak_unit.sv crypto/subchannel_aes_xts_pipe.sv crypto/aes_inv_cipher_pipe.sv
      crypto/gf128_mul_pipe.sv crypto/qshield_mac_unit.sv crypto/qshield_meta_layout.sv crypto/qshield_meta_cache.sv
      crypto/qshield_counter_unit.sv crypto/qshield_bmt_engine.sv crypto/qshield_integrity_csr.sv crypto/qshield_axi_crypto_bridge.sv
      top/axi_ddr5_mc_secure_top.sv
    } { read_verilog -sv [file join $R $f] }
  }

  puts "=== STARTING SYNTHESIS (mode: out_of_context, rebuilt) ==="
  synth_design -top $top_module -part $PART -mode out_of_context -flatten_hierarchy rebuilt
  write_checkpoint -force [file join $OUT_DIR "${tag}_presynth.dcp"]
}

create_clock -period $period -name clk_axi [get_ports clk_axi]
create_clock -period $period -name clk_ddr [get_ports clk_ddr]
set_clock_groups -asynchronous -group clk_axi -group clk_ddr

# Save synth checkpoint and fast checks
write_checkpoint -force "$OUT_DIR/${tag}_synth.dcp"
report_timing_summary -file "$OUT_DIR/${tag}_synth_timing.rpt" -max_paths 10
report_utilization    -file "$OUT_DIR/${tag}_synth_util.rpt"

set synth_wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
puts "SYNTH_DONE: tag=$tag WNS=$synth_wns"

puts "=== STARTING IMPLEMENTATION (opt, place, phys_opt, route) ==="
opt_design
place_design
phys_opt_design
route_design

write_checkpoint -force "$OUT_DIR/${tag}_route.dcp"

puts "=== GENERATING POST-ROUTE REPORTS ==="
report_timing_summary -file "$OUT_DIR/${tag}_route_timing.rpt" -max_paths 20
report_utilization    -file "$OUT_DIR/${tag}_route_util.rpt"
report_utilization    -hierarchical -file "$OUT_DIR/${tag}_route_util_hier.rpt"
report_power          -file "$OUT_DIR/${tag}_route_power.rpt"

set route_wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
set route_whs [get_property SLACK [get_timing_paths -max_paths 1 -hold]]

puts "================================================================================"
puts "RESULT_PPA: tag=$tag top=$top_module period=$period route_WNS=$route_wns route_WHS=$route_whs"
puts "================================================================================"
