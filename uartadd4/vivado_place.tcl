# Vivado synth + place, dump placed EDIF + placement map (cell -> SITE/BEL),
# then golden bit.  nextpnr will lock this placement and route only.
set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog -sv [glob uart_src/*.sv]
read_verilog -sv uart_rx_lfsr.sv top.sv
read_xdc top.xdc
synth_design -top top -part $part -flatten_hierarchy full
opt_design
place_design
write_edif -force /tmp/ua4_placed.edif
set fh [open /tmp/ua4_place.map w]
foreach c [get_cells -hier -filter {IS_PRIMITIVE==1}] {
    set loc [get_property LOC $c]; set bel [get_property BEL $c]
    if {$loc eq "" || $bel eq ""} continue
    # lock SLICE logic and the BUFG (clock source); IOBs are placed by the XDC.
    if {![string match "SLICE_*" $loc] && ![string match "BUFGCTRL_*" $loc]} continue
    puts $fh "$c\t[get_property REF_NAME $c]\t$loc/[lindex [split $bel .] 1]"
}
close $fh
route_design
write_bitstream -force /tmp/ua4_golden.bit
puts "UA4_PLACE_DONE [llength [get_cells -hier -filter {IS_PRIMITIVE==1}]] prims, [exec wc -l < /tmp/ua4_place.map] locs"
