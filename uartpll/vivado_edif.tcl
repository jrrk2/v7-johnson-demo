set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog -sv [glob uart_src/*.sv]
read_verilog -sv top.sv
set defs ""
if {[info exists ::env(PLLDEF)] && $::env(PLLDEF) ne ""} {
    set defs "-verilog_define $::env(PLLDEF)"
}
# For the SGMII build, read the XDC at synth so Vivado knows AH8/AH7 are
# MGTREFCLK pins and connects IBUFDS_GTE2 straight to the IPAD (no bogus IBUF).
if {[info exists ::env(PLLDEF)] && $::env(PLLDEF) eq "USE_SGMII"} {
    read_xdc top.xdc
}
synth_design -top top -part $part -flatten_hierarchy full {*}$defs
# Belt-and-braces: if synth still inserted IBUFs in front of IBUFDS_GTE2 (Vivado
# auto-IO-buffer insertion on the GT refclk port), splice them out so the IPAD
# drives IBUFDS_GTE2.I/.IB directly, as the silicon requires.
foreach g [get_cells -hier -filter {REF_NAME =~ IBUFDS_GTE2*}] {
    foreach p {I IB} {
        set ipin [get_pins $g/$p]
        set inet [get_nets -of $ipin]
        set drv  [get_cells -of [get_pins -of $inet -filter {DIRECTION == OUT}]]
        if {$drv ne "" && [get_property REF_NAME $drv] eq "IBUF"} {
            set src [get_nets -of [get_pins $drv/I]]
            disconnect_net -net $inet -objects $ipin
            connect_net   -net $src  -objects $ipin
            remove_cell $drv
            puts "spliced out IBUF $drv feeding $g/$p"
        }
    }
}
puts "PLLE2: [llength [get_cells -hier -filter {REF_NAME =~ PLLE2*}]]  BUFG: [llength [get_cells -hier -filter {REF_NAME =~ BUFG*}]]"
write_edif -force /tmp/uartpll_synth.edif
puts "uartpll_EDIF_DONE"
