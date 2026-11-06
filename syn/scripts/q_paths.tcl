open_checkpoint top2_synth.dcp
create_clock -period 2.500 -name clk_axi [get_ports clk_axi]
create_clock -period 2.500 -name clk_ddr [get_ports clk_ddr]
set_clock_groups -asynchronous -group clk_axi -group clk_ddr
foreach blk {u_sdc_filter u_qos_queue u_ate u_ecc_scrubber u_rob u_ar_split u_pmu u_cmd_engine u_drm u_addr_mapper u_arbiter u_wds} {
  set p [get_timing_paths -quiet -max_paths 1 -to [get_cells -quiet -hier -filter "NAME =~ $blk/* && IS_SEQUENTIAL"]]
  puts "=== $blk slack [get_property SLACK $p] levels [get_property LOGIC_LEVELS $p]"
  puts "  start [get_property STARTPOINT_PIN $p]"
  puts "  end   [get_property ENDPOINT_PIN $p]"
  set prev ""
  foreach c [get_cells -quiet -of_objects $p] { set h [join [lrange [split $c /] 0 end-1] /]; if {$h ne $prev} { puts "    via $h"; set prev $h } }
}
