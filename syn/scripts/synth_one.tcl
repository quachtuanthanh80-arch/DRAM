# Usage: vivado -mode batch -source synth_one.tcl -tclargs <tag> <top> <file1> [file2 ...]
# OOC synthesis at 400 MHz on xczu7ev; writes <tag>_util.rpt, <tag>_timing.rpt and appends a line to batch_summary.txt.
set WD   [file normalize [file join [file dirname [info script]] .. reports build]]
file mkdir $WD
set PART "xczu7ev-ffvc1156-2-e"
set tag  [lindex $argv 0]
set top  [lindex $argv 1]
create_project -in_memory -part $PART
foreach f [lrange $argv 2 end] { read_verilog -sv $f }
synth_design -top $top -part $PART -mode out_of_context -flatten_hierarchy rebuilt
create_clock -period 2.500 -name clk [get_ports clk]
report_utilization    -file "$WD/${tag}_util.rpt"
report_timing -max_paths 40 -nworst 1 -unique_pins -file "$WD/${tag}_paths.rpt"
report_timing_summary -file "$WD/${tag}_timing.rpt" -max_paths 3
set wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
set fh [open "$WD/batch_summary.txt" a]; puts $fh "[clock format [clock seconds] -format %H:%M] $tag WNS=$wns"; close $fh
puts "RESULT $tag WNS=$wns"
