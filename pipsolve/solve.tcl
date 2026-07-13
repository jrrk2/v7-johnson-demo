# Route the MMCM->BUFG net through one target HCLK_CMT_L pip, bitstream it.
# env: CKIN (e.g. 1), MUXCLK (e.g. 8), OUT (bitfile)
set ckin  $::env(CKIN)
set muxclk $::env(MUXCLK)
set tile "HCLK_CMT_L_X305Y26"

create_project -force -in_memory -part xc7vx485tffg1761-2
read_verilog top.v
read_xdc top.xdc
synth_design -top top
# Pin the MMCM into the CMT region served by $tile
set cmt_tile [get_tiles CMT_TOP_L_LOWER_B_X305Y9]
set mmcm_site [get_sites -of_objects $cmt_tile -filter {SITE_TYPE == MMCME2_ADV}]
puts "MMCM site: $mmcm_site"
set_property LOC $mmcm_site [get_cells mmcm]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets clkin]
place_design
route_design

set net [get_nets -of_objects [get_pins bg/I]]
puts "target net: $net"
route_design -unroute -nets $net

set mux_node  [get_nodes -of_objects [get_wires "$tile/HCLK_CMT_MUX_CLK_$muxclk"]]
set ckin_node [get_nodes -of_objects [get_wires "$tile/HCLK_CMT_CK_IN$ckin"]]
set src_node  [get_nodes -of_objects [get_site_pins -filter {DIRECTION == OUT} -of_objects $net]]
set dst_node  [get_nodes -of_objects [get_site_pins -filter {DIRECTION == IN} -of_objects $net]]
puts "src=$src_node mux=$mux_node ckin=$ckin_node dst=$dst_node"

set pathA [find_routing_path -from $src_node -to $mux_node]
set pathB [find_routing_path -from $ckin_node -to $dst_node]
puts "pathA: [llength $pathA] nodes; pathB: [llength $pathB] nodes"
set full [concat $pathA $pathB]
set_property FIXED_ROUTE $full $net
route_design -nets $net
report_route_status -of_objects $net

write_bitstream -force $::env(OUT)
puts "PIPSOLVE_DONE"
