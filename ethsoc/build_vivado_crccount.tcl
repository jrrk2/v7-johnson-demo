# Golden Vivado build of the minimal SGMII RX-front-end CRC counter
# (vc707_crccount.v): PCS/PMA -> axis_gmii_rx (CRC32) -> valid-frame counter ->
# LEDs.  No MAC, no packet buffer, no UART/CPU.  Produces the vendored artifacts
# for the R0 open flow: structural netlist + placement dump + golden bit.
set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog -sv [list axis_gmii_rx.sv rgmii_lfsr.sv]
read_verilog pcs_pma_flat.v
read_verilog vc707_crccount.v
read_xdc vc707_ethsoc.xdc
read_xdc vc707_ethsoc_clocks.xdc
synth_design -top top -part $part -flatten_hierarchy rebuilt -verilog_define VC707
opt_design
place_design
route_design
write_checkpoint -force vc707_crccount.dcp
write_bitstream -force vc707_crccount.bit
write_verilog -force -mode design vc707_crccount_netlist.v
set fp [open placement_crccount.txt w]
foreach c [get_cells -hierarchical -filter {IS_PRIMITIVE && PRIMITIVE_LEVEL != "MACRO"}] {
    set site [get_property LOC $c]
    set bel  [get_property BEL $c]
    if {$site ne "" && $bel ne ""} {
        puts $fp "$c\t$site\t$bel\t[get_property REF_NAME $c]"
    }
}
close $fp
report_utilization -file util_crccount.rpt
report_timing_summary -file timing_crccount.rpt -max_paths 3
puts "CRCCOUNT_BUILD_DONE"
