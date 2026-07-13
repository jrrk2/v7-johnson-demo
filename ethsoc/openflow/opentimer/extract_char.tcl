open_checkpoint vc707_ethloop.dcp
set fp [open openflow/opentimer/arcs.tsv w]
puts $fp "libcell\ttype\tslowmax\tfastmin\tfanout"
# bulk: iterate cell types, get arcs, bulk-read delay props + output-net fanout
foreach ct {LUT1 LUT2 LUT3 LUT4 LUT5 LUT6 FDRE FDSE FDPE FDCE CARRY4 MUXF7 MUXF8 \
            RAMB36E1 SRL16E SRLC32E RAMD64E RAMD32 RAMS32 BUFG} {
  set cells [get_cells -quiet -hier -filter "REF_NAME==$ct"]
  if {$cells eq ""} continue
  set arcs [get_timing_arcs -quiet -of $cells]
  if {$arcs eq ""} continue
  set smx [get_property -quiet DELAY_SLOW_MAX_RISE $arcs]
  set fmn [get_property -quiet DELAY_FAST_MIN_RISE $arcs]
  set typ [get_property -quiet TYPE $arcs]
  set tp  [get_property -quiet TO_PIN $arcs]
  set i 0
  foreach a $arcs {
    set fo 0
    set net [get_nets -quiet -of [lindex $tp $i]]
    if {$net ne ""} { set fo [get_property -quiet FLAT_PIN_COUNT $net] }
    puts $fp "$ct\t[lindex $typ $i]\t[lindex $smx $i]\t[lindex $fmn $i]\t$fo"
    incr i
  }
  puts "  $ct: [llength $arcs] arcs"
}
close $fp
puts "EXTRACT_DONE"
