open_checkpoint /tmp/jrrk.dcp
route_design -unroute
phys_opt_design
route_design
puts "ROUTESTAT:"
report_route_status
write_bitstream -force /tmp/jrrk_viv_reroute.bit
