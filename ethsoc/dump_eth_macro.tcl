# Dump the eth_macro implementation artifacts from the harness DCP for the
# macro-merge open flow:
#   eth_macro_impl_raw.v  — structural netlist of the u_macro cell (module
#                           eth_macro; run patch_netlist.py before yosys)
#   placement_macro.txt   — name<TAB>site<TAB>BEL<TAB>REF_NAME for every
#                           placed primitive under u_macro/ (names keep the
#                           u_macro/ prefix: the merge design instantiates
#                           the macro as u_macro so yosys-flattened names
#                           match after '/'->'.' normalisation)
#   vivado -mode batch -source dump_eth_macro.tcl
open_checkpoint eth_macro_harness.dcp

write_verilog -force -mode design -cell [get_cells u_macro] eth_macro_impl_raw.v

set fp [open placement_macro.txt w]
set n 0
foreach c [get_cells -hierarchical -filter {IS_PRIMITIVE && PRIMITIVE_LEVEL != "MACRO" && NAME =~ u_macro/*}] {
    set site [get_property LOC $c]
    set bel  [get_property BEL $c]
    if {$site ne "" && $bel ne ""} {
        puts $fp "$c\t$site\t$bel\t[get_property REF_NAME $c]"
        incr n
    }
}
close $fp
puts "DUMP_ETH_MACRO_DONE: $n placements"
