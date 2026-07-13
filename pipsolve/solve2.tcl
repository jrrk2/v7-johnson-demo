# Force the IBUFDS_GTE2->BUFG net through CK_IN$::env(CKIN) <- MUX_CLK_$::env(MUXCLK)
set ckin   $::env(CKIN)
set muxclk $::env(MUXCLK)
set tile "HCLK_CMT_L_X305Y26"

create_project -force -in_memory -part xc7vx485tffg1761-2
read_verilog top2.v
read_xdc top2.xdc
synth_design -top top
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets refclk]
place_design
route_design

set net [get_nets refclk]
puts "target net: $net  status:"
report_route_status -of_objects $net

route_design -unroute -nets $net
set mux_node  [get_nodes -of_objects [get_wires "$tile/HCLK_CMT_MUX_CLK_$muxclk"]]
set ckin_node [get_nodes -of_objects [get_wires "$tile/HCLK_CMT_CK_IN$ckin"]]
set src_node  [get_nodes -of_objects [get_site_pins -filter {DIRECTION == OUT} -of_objects $net]]
set dst_node  [get_nodes -of_objects [get_site_pins -filter {DIRECTION == IN} -of_objects $net]]
puts "src=$src_node"
puts "mux=$mux_node"
puts "ckin=$ckin_node"
puts "dst=$dst_node"

set pathA [find_routing_path -from $src_node -to $mux_node]
if {[llength $pathA] == 0} { error "no path src->mux" }
set pathB [find_routing_path -from $ckin_node -to $dst_node]
if {[llength $pathB] == 0} { error "no path ckin->dst" }
puts "pathA [llength $pathA] nodes, pathB [llength $pathB] nodes"
set full [concat $pathA $pathB]
set_property FIXED_ROUTE $full $net
route_design -nets $net
report_route_status -of_objects $net
write_bitstream -force $::env(OUT)
puts "PIPSOLVE_DONE"
