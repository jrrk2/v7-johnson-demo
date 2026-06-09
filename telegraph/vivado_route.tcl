# Full Vivado build of the CURRENT netlist, re-dumping the placement map so we
# can confirm it matches the placement locked into nextpnr (place_design is
# deterministic).  Same placement + Vivado routing -> bitstream, for an
# apples-to-apples FASM diff against the nextpnr-routed bitstream.
set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog top.v telegraph_core.v
read_xdc top.xdc
synth_design -top top -part $part
opt_design
place_design
set fh [open /tmp/tg_place2.map w]
foreach c [get_cells -hier -filter {IS_PRIMITIVE==1}] {
    set loc [get_property LOC $c]
    set bel [get_property BEL $c]
    if {$loc eq "" || $bel eq ""} continue
    if {![string match "SLICE_*" $loc]} continue
    puts $fh "$c\t[get_property REF_NAME $c]\t$loc/[lindex [split $bel .] 1]"
}
close $fh
route_design
write_bitstream -force /tmp/tg_viv_same.bit
puts "VIV_ROUTE_DONE"
