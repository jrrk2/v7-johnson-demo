open_checkpoint ethsoc/vc707_ethloop.dcp
set fp [open ethsoc/openflow/opentimer/golden_netgeom.tsv w]
puts $fp "net\tpips\tfanout"
foreach n [get_nets -hier -filter {ROUTE_STATUS==ROUTED}] {
  set np [llength [get_pips -quiet -of_objects $n]]
  set fo [llength [get_pins -quiet -leaf -of_objects $n -filter {DIRECTION==IN}]]
  puts $fp "$n\t$np\t$fo"
}
close $fp
puts "NETGEOM_DONE"
