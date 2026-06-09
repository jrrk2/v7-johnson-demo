# Vivado does synth + place (NO route); export the placed netlist (EDIF) and a
# placement map (cell -> SITE/BEL) so nextpnr can route-only with every slice
# cell locked.  Isolates nextpnr's ROUTER from its placer.
set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog top.v telegraph_core.v
read_xdc top.xdc
synth_design -top top -part $part
opt_design
place_design
# netlist (names match get_cells after place, no phys_opt)
write_edif -force /tmp/tg_placed.edif
# placement map: only the slice logic we care about; IO/clock left to nextpnr
set fh [open /tmp/tg_place.map w]
foreach c [get_cells -hier -filter {IS_PRIMITIVE==1}] {
    set ref [get_property REF_NAME $c]
    set loc [get_property LOC $c]
    set bel [get_property BEL $c]
    if {$loc eq "" || $bel eq ""} continue
    # only SLICE-resident cells
    if {![string match "SLICE_*" $loc]} continue
    set belleaf [lindex [split $bel .] 1]
    puts $fh "$c\t$ref\t$loc/$belleaf"
}
close $fh
puts "PLACEMAP_DONE [llength [get_cells -hier -filter {IS_PRIMITIVE==1}]] cells"
