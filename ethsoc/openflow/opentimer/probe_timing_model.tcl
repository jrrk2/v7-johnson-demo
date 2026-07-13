open_checkpoint vc707_ethloop.dcp
puts "=== lib cells for LUT6/FDRE ==="
foreach lc {LUT6 FDRE CARRY4 RAMB36E1} {
  set c [get_lib_cells -quiet */$lc]
  puts "libcell $lc -> $c"
}
puts "=== lib pin CAPACITANCE (driver load) ==="
foreach lp [get_lib_pins -quiet */LUT6/I0 */LUT6/O */FDRE/D */FDRE/C */FDRE/Q] {
  puts "  $lp  cap=[get_property -quiet CAPACITANCE $lp]  dir=[get_property -quiet DIRECTION $lp]"
}
puts "=== all properties of a LUT6/O lib pin (look for drive/model) ==="
report_property -all [lindex [get_lib_pins -quiet */LUT6/O] 0]
puts "=== timing arcs of a placed LUT6 (delay model) ==="
set cell [lindex [get_cells -quiet -hier -filter {REF_NAME==LUT6}] 0]
puts "cell: $cell"
foreach arc [get_timing_arcs -quiet -to [get_pins -quiet $cell/O]] {
  puts "  arc $arc"
  report_property -quiet -all $arc
}
puts "=== report_timing -input_pins showing SLEW columns ==="
report_timing -max_paths 1 -input_pins -nets -slack_lesser_than 100 -file openflow/opentimer/rt_inputpins.rpt
puts "PROBE_DONE"
