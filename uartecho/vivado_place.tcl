# Vivado synth+place (dump placement map + placed EDIF), then route+golden bit.
# Lets nextpnr route-only the SAME placement so the open-flow frames can be
# diffed against Vivado's golden apples-to-apples (no hardware needed).
set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog -sv uart_src/uart_baudgen.sv uart_src/uart_receiver.sv uart_src/uart_transmitter.sv uart_src/slib_clock_div.sv uart_src/slib_counter.sv uart_src/slib_edge_detect.sv uart_src/slib_input_filter.sv uart_src/slib_input_sync.sv uart_src/slib_mv_filter.sv
read_verilog -sv top.sv uart_echo.sv
read_xdc top.xdc
synth_design -top top -part $part -flatten_hierarchy full
opt_design
place_design
write_edif -force /tmp/ue_placed.edif
set fh [open /tmp/ue_place.map w]
foreach c [get_cells -hier -filter {IS_PRIMITIVE==1}] {
    set loc [get_property LOC $c]; set bel [get_property BEL $c]
    if {$loc eq "" || $bel eq ""} continue
    if {![string match "SLICE_*" $loc]} continue
    puts $fh "$c\t[get_property REF_NAME $c]\t$loc/[lindex [split $bel .] 1]"
}
close $fh
route_design
write_bitstream -force /tmp/ue_golden.bit
puts "UE_PLACE_DONE [llength [get_cells -hier -filter {IS_PRIMITIVE==1}]] prims"
