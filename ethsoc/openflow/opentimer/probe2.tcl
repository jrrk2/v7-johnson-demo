open_checkpoint vc707_ethloop.dcp
puts "=== input-pin CAPACITANCE (the load a driver must charge) ==="
foreach p {LUT6/I0 LUT6/O FDRE/D FDRE/C FDRE/Q CARRY4/S0 RAMB36E1/ADDRARDADDR0} {
  set lp [get_lib_pins -quiet */$p]
  if {$lp ne ""} { puts "  $p  CAP=[get_property -quiet CAPACITANCE $lp] DIR=[get_property -quiet DIRECTION $lp]" }
}
puts "=== properties of a placed LUT6 output timing arc ==="
set cell [lindex [get_cells -quiet -hier -filter {REF_NAME==LUT6}] 0]
set arc [lindex [get_timing_arcs -quiet -to [get_pins -quiet $cell/O]] 0]
report_property -all $arc
puts "=== does report_timing -input_pins show slew? (grep the rpt) ==="
report_timing -max_paths 1 -input_pins -nets -file openflow/opentimer/rt_ip.rpt
puts "PROBE2_DONE"
