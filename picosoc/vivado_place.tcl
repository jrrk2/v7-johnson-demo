# Vivado synth + place (NO route) for PicoSoC; export the placed netlist (EDIF)
# and a placement map (cell -> SITE/BEL) so nextpnr can route-only with Vivado's
# placement locked.  This isolates nextpnr's ROUTER + FASM emitter from its
# placer, so the resulting FASM can be compared apples-to-apples against the
# Vivado golden bitstream (same synth, same placement).
set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog -sv vc707_picosoc.v picosoc_noflash.v picorv32.v simpleuart.v spimemio.v progmem.v
read_xdc vc707_picosoc.xdc
synth_design -top top -part $part
opt_design
place_design
write_edif -force /tmp/picosoc_placed.edif
# placement map: every placed primitive with a concrete SITE/BEL.  Lock all of
# them (SLICE/IOB/BRAM/BUFG/...) to reproduce Vivado's placement exactly.
set fh [open /tmp/picosoc_place.map w]
set n 0
foreach c [get_cells -hier -filter {IS_PRIMITIVE==1}] {
    set loc [get_property LOC $c]
    set bel [get_property BEL $c]
    if {$loc eq "" || $bel eq ""} continue
    set belleaf [lindex [split $bel .] 1]
    puts $fh "$c\t[get_property REF_NAME $c]\t$loc/$belleaf"
    incr n
}
close $fh
puts "PLACEMAP_DONE $n placed cells"
