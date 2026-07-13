set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog vc707_wireloop.v
read_xdc wireloop_pins.xdc
synth_design -top wireloop -part $part
opt_design
place_design
route_design
write_bitstream -force vc707_wireloop.bit
write_verilog -force -mode design vc707_wireloop_netlist.v
set fp [open placement_wireloop.txt w]
foreach c [get_cells -hierarchical -filter {IS_PRIMITIVE && PRIMITIVE_LEVEL != "MACRO"}] {
    set site [get_property LOC $c]; set bel [get_property BEL $c]
    if {$site ne "" && $bel ne ""} { puts $fp "$c\t$site\t$bel\t[get_property REF_NAME $c]" }
}
close $fp
puts "WIRELOOP_BUILD_DONE"
